const std = @import("std");

const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const atlas_page_mod = @import("../render/format/atlas/page.zig");
const bezier = @import("../math/bezier.zig");
const config_mod = @import("config.zig");
const curve_tex = @import("../render/format/curve_texture.zig");
const text_hint = @import("../render/format/text_hint.zig");
const tt_exec = @import("../font/tt_exec.zig");
const tt_outline = @import("../font/tt_outline.zig");
const tt_points = @import("../font/tt_points.zig");
const tt_vm = @import("../font/tt_vm.zig");
const vec = @import("../math/vec.zig");

const Allocator = std.mem.Allocator;
const AtlasPage = atlas_page_mod.AtlasPage;
const CurveSegment = bezier.CurveSegment;
const BBox = bezier.BBox;
const FaceConfig = config_mod.FaceConfig;
const GlyphInfo = atlas_curve_mod.CurveAtlas.GlyphInfo;
const Program = tt_vm.Program;
const QuadBezier = tt_points.QuadBezier;
const Vec2 = vec.Vec2;

pub const HintPpem = struct {
    x_26_6: u32,
    y_26_6: u32,

    pub fn uniform(ppem_26_6: u32) HintPpem {
        return .{ .x_26_6 = ppem_26_6, .y_26_6 = ppem_26_6 };
    }
};

pub const BaseGlyph = struct {
    info: GlyphInfo,
    page: *const AtlasPage,
};

pub const GlyphHintOptions = struct {
    base: ?BaseGlyph = null,
};

pub const GlyphHint = struct {
    allocator: Allocator,
    glyph_id: u16,
    advance: Vec2,
    bbox: BBox,
    curves: []CurveSegment,
    prepared_curves: []CurveSegment,
    curve_bboxes: []BBox,
    curve_deltas_f16: []u16,
    band_reuse: ?text_hint.BandReuseProof = null,

    pub fn deinit(self: *GlyphHint) void {
        self.allocator.free(self.curves);
        self.allocator.free(self.prepared_curves);
        self.allocator.free(self.curve_bboxes);
        self.allocator.free(self.curve_deltas_f16);
        self.* = undefined;
    }

    pub fn curveDeltaBytes(self: *const GlyphHint) usize {
        return self.curve_deltas_f16.len * @sizeOf(u16);
    }

    pub fn curveDeltaUpload(self: *const GlyphHint) text_hint.UploadOp {
        return .{ .curve_deltas = .{ .byte_len = self.curveDeltaBytes() } };
    }

    pub fn bandsReusable(self: *const GlyphHint) ?bool {
        return if (self.band_reuse) |proof| proof.reusable() else null;
    }
};

pub const HintMachine = struct {
    allocator: Allocator,
    program: *const Program,
    size: tt_vm.SizeState,
    stack: []i32,
    storage: []i32,
    storage_snapshot: []i32,
    function_entries: []tt_exec.Function,
    functions: tt_exec.FunctionDefs,
    twilight_points: []tt_exec.Point,
    glyph_points: []tt_exec.Point,
    zones: tt_exec.PointZones,
    snapshot: tt_vm.ControlProgramSnapshot,

    pub fn init(allocator: Allocator, face: *const FaceConfig, ppem: HintPpem) !HintMachine {
        const program = if (face.tt_program) |*program| program else return error.NoTrueTypeProgram;
        return initForProgram(allocator, program, ppem);
    }

    pub fn initForProgram(allocator: Allocator, program: *const Program, ppem: HintPpem) !HintMachine {
        var machine = try allocateMachine(allocator, program, ppem);
        errdefer machine.deinit();
        try machine.runSetupPrograms();
        return machine;
    }

    pub fn deinit(self: *HintMachine) void {
        self.allocator.free(self.stack);
        self.allocator.free(self.storage);
        self.allocator.free(self.storage_snapshot);
        self.allocator.free(self.function_entries);
        self.allocator.free(self.twilight_points);
        self.allocator.free(self.glyph_points);
        self.size.deinit();
        self.* = undefined;
    }

    pub fn hintGlyph(self: *HintMachine, allocator: Allocator, glyph_id: u16, options: GlyphHintOptions) !GlyphHint {
        var topology = try self.program.loadGlyphTopology(allocator, glyph_id);
        defer topology.deinit();
        return switch (topology) {
            .empty => self.hintEmptyGlyph(allocator, glyph_id),
            .simple => |*simple| self.hintSimpleGlyph(allocator, glyph_id, simple, options),
            .compound => error.UnsupportedCompoundHinting,
        };
    }

    fn runSetupPrograms(self: *HintMachine) !void {
        var context = self.makeContext();
        context.setFunctions(&self.functions);
        context.setZones(&self.zones);
        try self.program.runFontProgram(&context);

        context.reset();
        context.resetGraphics();
        context.setEnvironment(self.size.environment());
        context.setFunctions(&self.functions);
        context.setZones(&self.zones);
        try self.program.runControlProgram(&context);
        self.snapshot = try self.size.captureControlProgramSnapshot(&context, self.storage_snapshot);
    }

    fn makeContext(self: *HintMachine) tt_exec.Context {
        return self.size.executionContext(.{
            .stack = self.stack,
            .storage = self.storage,
        }, .x, .{});
    }

    fn hintEmptyGlyph(self: *HintMachine, allocator: Allocator, glyph_id: u16) !GlyphHint {
        return .{
            .allocator = allocator,
            .glyph_id = glyph_id,
            .advance = try self.emptyAdvance(glyph_id),
            .bbox = emptyBBox(),
            .curves = &.{},
            .prepared_curves = &.{},
            .curve_bboxes = &.{},
            .curve_deltas_f16 = &.{},
        };
    }

    fn hintSimpleGlyph(
        self: *HintMachine,
        allocator: Allocator,
        glyph_id: u16,
        simple: *const tt_outline.SimpleGlyph,
        options: GlyphHintOptions,
    ) !GlyphHint {
        var context = self.makeContext();
        try self.snapshot.restore(&context);
        context.setFunctions(&self.functions);
        context.setZones(&self.zones);

        const hinted = try self.size.executeSimpleGlyph(
            &context,
            &self.zones,
            self.glyph_points,
            simple,
            try self.program.glyphPhantomMetrics(glyph_id),
        );
        return self.makeGlyphHint(allocator, glyph_id, hinted, options);
    }

    fn makeGlyphHint(
        self: *const HintMachine,
        allocator: Allocator,
        glyph_id: u16,
        hinted: tt_vm.HintedSimpleGlyph,
        options: GlyphHintOptions,
    ) !GlyphHint {
        const curves = try hintedCurves(allocator, hinted, self.ppemScaleX(), self.ppemScaleY());
        errdefer allocator.free(curves);
        const prepared = try curve_tex.prepareGlyphCurvesForDirectEncoding(allocator, curves, .zero);
        errdefer allocator.free(prepared);
        const curve_bboxes = try collectCurveBboxes(allocator, prepared);
        errdefer allocator.free(curve_bboxes);
        const deltas = try maybeEncodeDeltas(allocator, options.base, prepared);
        errdefer allocator.free(deltas);

        return .{
            .allocator = allocator,
            .glyph_id = glyph_id,
            .advance = .{ .x = self.toEmX(hinted.advance_x_26_6), .y = 0 },
            .bbox = bboxForCurves(curve_bboxes),
            .curves = curves,
            .prepared_curves = prepared,
            .curve_bboxes = curve_bboxes,
            .curve_deltas_f16 = deltas,
            .band_reuse = proveBandReuse(options.base, curve_bboxes),
        };
    }

    fn emptyAdvance(self: *const HintMachine, glyph_id: u16) !Vec2 {
        const phantoms = try self.program.glyphPhantomMetrics(glyph_id);
        const left = @as(i32, phantoms.x_min) - @as(i32, phantoms.left_side_bearing);
        const right = left + @as(i32, phantoms.advance_width);
        const env = self.size.environment();
        return .{ .x = self.toEmX(env.scaleFUnitsX(right) - env.scaleFUnitsX(left)), .y = 0 };
    }

    fn ppemScaleX(self: *const HintMachine) f32 {
        return 1.0 / @as(f32, @floatFromInt(self.size.request.ppem_x_26_6));
    }

    fn ppemScaleY(self: *const HintMachine) f32 {
        return 1.0 / @as(f32, @floatFromInt(self.size.request.ppem_y_26_6));
    }

    fn toEmX(self: *const HintMachine, value_26_6: i32) f32 {
        return @as(f32, @floatFromInt(value_26_6)) * self.ppemScaleX();
    }
};

fn allocateMachine(allocator: Allocator, program: *const Program, ppem: HintPpem) !HintMachine {
    const sizes = program.executionBufferSizes();
    var size = try program.sizeState(allocator, .{
        .ppem_x_26_6 = ppem.x_26_6,
        .ppem_y_26_6 = ppem.y_26_6,
    });
    errdefer size.deinit();

    const stack = try allocator.alloc(i32, sizes.stack);
    errdefer allocator.free(stack);
    const storage = try allocator.alloc(i32, @max(sizes.storage, 1));
    errdefer allocator.free(storage);
    @memset(storage, 0);
    const storage_snapshot = try allocator.alloc(i32, storage.len);
    errdefer allocator.free(storage_snapshot);
    const function_entries = try allocator.alloc(tt_exec.Function, @max(sizes.functions, 1));
    errdefer allocator.free(function_entries);
    const twilight_points = try allocator.alloc(tt_exec.Point, @max(sizes.twilight_points, 1));
    errdefer allocator.free(twilight_points);
    const glyph_points = try allocator.alloc(tt_exec.Point, @max(sizes.glyph_points, 1));
    errdefer allocator.free(glyph_points);

    return .{
        .allocator = allocator,
        .program = program,
        .size = size,
        .stack = stack,
        .storage = storage,
        .storage_snapshot = storage_snapshot,
        .function_entries = function_entries,
        .functions = .{ .entries = function_entries },
        .twilight_points = twilight_points,
        .glyph_points = glyph_points,
        .zones = .{
            .twilight = tt_exec.PointZone.initTwilight(twilight_points),
            .glyph = .{ .points = glyph_points[0..0] },
        },
        .snapshot = .{ .graphics = .{}, .storage = storage_snapshot },
    };
}

fn hintedCurves(allocator: Allocator, hinted: tt_vm.HintedSimpleGlyph, scale_x: f32, scale_y: f32) ![]CurveSegment {
    const quads = try hinted.curvesXY(allocator, scale_x, scale_y);
    defer if (quads.len > 0) allocator.free(quads);
    return quadCurvesToSegments(allocator, quads);
}

fn quadCurvesToSegments(allocator: Allocator, quads: []const QuadBezier) ![]CurveSegment {
    const curves = try allocator.alloc(CurveSegment, quads.len);
    errdefer allocator.free(curves);
    for (quads, curves) |quad, *out| out.* = CurveSegment.fromQuad(quad);
    return curves;
}

fn collectCurveBboxes(allocator: Allocator, curves: []const CurveSegment) ![]BBox {
    const bboxes = try allocator.alloc(BBox, curves.len);
    errdefer allocator.free(bboxes);
    for (curves, bboxes) |curve, *bbox| bbox.* = curve.boundingBox();
    return bboxes;
}

fn maybeEncodeDeltas(allocator: Allocator, base: ?BaseGlyph, hinted: []const CurveSegment) ![]u16 {
    const base_glyph = base orelse return &.{};
    if (base_glyph.info.curve_count != hinted.len) return error.CurveTopologyChanged;
    const encoded = try allocator.alloc(u16, hinted.len * 8);
    errdefer allocator.free(encoded);

    for (hinted, 0..) |hinted_curve, i| {
        const base_curve = decodeBaseCurve(base_glyph, i) orelse return error.InvalidBaseCurve;
        if (base_curve.kind != hinted_curve.kind) return error.CurveTopologyChanged;
        encodeCurveDelta(encoded[i * 8 ..][0..8], base_curve, hinted_curve);
    }
    return encoded;
}

fn decodeBaseCurve(base: BaseGlyph, index: usize) ?CurveSegment {
    const texel = base.info.base_curve_texel + @as(u32, @intCast(index)) * curve_tex.SEGMENT_TEXELS;
    return curve_tex.decodeSegmentAt(base.page.curve_data, texel);
}

fn encodeCurveDelta(out: []u16, base: CurveSegment, hinted: CurveSegment) void {
    encodePointDelta(out[0..][0..2], base.p0, hinted.p0);
    encodePointDelta(out[2..][0..2], base.p1, hinted.p1);
    encodePointDelta(out[4..][0..2], base.p2, hinted.p2);
    encodePointDelta(out[6..][0..2], base.p3, hinted.p3);
}

fn encodePointDelta(out: []u16, base: Vec2, hinted: Vec2) void {
    out[0] = curve_tex.f32ToF16(hinted.x - base.x);
    out[1] = curve_tex.f32ToF16(hinted.y - base.y);
}

fn proveBandReuse(base: ?BaseGlyph, curve_bboxes: []const BBox) ?text_hint.BandReuseProof {
    const base_glyph = base orelse return null;
    return text_hint.proveBandReuse(.{
        .band_data = base_glyph.page.band_data,
        .band_width = base_glyph.page.band_width,
        .band_entry = base_glyph.info.band_entry,
        .base_curve_texel = base_glyph.info.base_curve_texel,
        .hinted_curve_bboxes = curve_bboxes,
    });
}

fn bboxForCurves(bboxes: []const BBox) BBox {
    if (bboxes.len == 0) return emptyBBox();
    var bbox = bboxes[0];
    for (bboxes[1..]) |next| bbox = bbox.merge(next);
    return bbox;
}

fn emptyBBox() BBox {
    return .{ .min = Vec2.zero, .max = Vec2.zero };
}

test "hint machine emits simple glyph curves and band proof" {
    const assets = @import("assets");
    const atlas_mod = @import("atlas.zig");

    var atlas = try atlas_mod.TextAtlas.init(std.testing.allocator, &.{
        .{ .data = assets.noto_sans_regular },
    });
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, "A")) |next| {
        atlas.deinit();
        atlas = next;
    }

    const face = &atlas.config.faces[0];
    const glyph_id = (try atlas.glyphIndex(0, 'A')).?;
    const info = atlas.face_glyphs[0].getGlyph(glyph_id).?;
    var machine = try HintMachine.init(std.testing.allocator, face, HintPpem.uniform(12 * 64));
    defer machine.deinit();

    var hint = try machine.hintGlyph(std.testing.allocator, glyph_id, .{
        .base = .{ .info = info, .page = atlas.pages[info.page_index] },
    });
    defer hint.deinit();

    try std.testing.expect(hint.advance.x > 0);
    try std.testing.expectEqual(@as(usize, info.curve_count), hint.prepared_curves.len);
    try std.testing.expectEqual(@as(usize, info.curve_count) * 8, hint.curve_deltas_f16.len);
    try std.testing.expect(hint.band_reuse != null);
}

test "hint machine handles empty glyph advances" {
    const assets = @import("assets");
    const atlas_mod = @import("atlas.zig");

    var atlas = try atlas_mod.TextAtlas.init(std.testing.allocator, &.{
        .{ .data = assets.noto_sans_regular },
    });
    defer atlas.deinit();

    const face = &atlas.config.faces[0];
    const glyph_id = (try atlas.glyphIndex(0, ' ')).?;
    var machine = try HintMachine.init(std.testing.allocator, face, HintPpem.uniform(12 * 64));
    defer machine.deinit();

    var hint = try machine.hintGlyph(std.testing.allocator, glyph_id, .{});
    defer hint.deinit();

    try std.testing.expectEqual(@as(usize, 0), hint.curves.len);
    try std.testing.expect(hint.advance.x > 0);
}

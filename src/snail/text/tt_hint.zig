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

pub const GlyphHint = struct {
    allocator: Allocator,
    glyph_id: u16,
    advance: Vec2,
    bbox: BBox,
    curves: []CurveSegment,
    prepared_curves: []CurveSegment,
    curve_bboxes: []BBox,

    pub fn deinit(self: *GlyphHint) void {
        self.allocator.free(self.curves);
        self.allocator.free(self.prepared_curves);
        self.allocator.free(self.curve_bboxes);
        self.* = undefined;
    }
};

pub const GlyphHintPatch = struct {
    allocator: Allocator,
    record: text_hint.GlyphRecord,
    curve_deltas_f16: []u16,
    band_reuse: text_hint.BandReuseProof,

    pub fn deinit(self: *GlyphHintPatch) void {
        self.allocator.free(self.curve_deltas_f16);
        self.* = undefined;
    }

    pub fn curveDeltaBytes(self: *const GlyphHintPatch) usize {
        return self.curve_deltas_f16.len * @sizeOf(u16);
    }

    pub fn curveDeltaUpload(self: *const GlyphHintPatch) text_hint.UploadOp {
        return .{ .curve_deltas = .{ .byte_len = self.curveDeltaBytes() } };
    }

    pub fn bandsReusable(self: *const GlyphHintPatch) bool {
        return self.band_reuse.reusable();
    }
};

pub const ExecutedGlyph = union(enum) {
    empty: Vec2,
    simple: tt_vm.HintedSimpleGlyph,
};

const CompoundBuildError = error{
    BufferTooSmall,
    InvalidFont,
    MissingRequiredTable,
    OutOfMemory,
    UnexpectedEof,
};

pub const GlyphTopologyCache = struct {
    allocator: Allocator,
    program: *const Program,
    map: std.AutoHashMap(u16, tt_vm.GlyphTopology),

    pub fn init(allocator: Allocator, face: *const FaceConfig) !GlyphTopologyCache {
        const program = if (face.tt_program) |*program| program else return error.NoTrueTypeProgram;
        return initForProgram(allocator, program);
    }

    pub fn initForProgram(allocator: Allocator, program: *const Program) GlyphTopologyCache {
        return .{
            .allocator = allocator,
            .program = program,
            .map = std.AutoHashMap(u16, tt_vm.GlyphTopology).init(allocator),
        };
    }

    pub fn deinit(self: *GlyphTopologyCache) void {
        var values = self.map.valueIterator();
        while (values.next()) |topology| topology.deinit();
        self.map.deinit();
        self.* = undefined;
    }

    pub fn preload(self: *GlyphTopologyCache, glyph_ids: []const u16) !void {
        for (glyph_ids) |glyph_id| _ = try self.get(glyph_id);
    }

    pub fn get(self: *GlyphTopologyCache, glyph_id: u16) !*tt_vm.GlyphTopology {
        const gop = try self.map.getOrPut(glyph_id);
        if (!gop.found_existing) {
            gop.value_ptr.* = try self.program.loadGlyphTopology(self.allocator, glyph_id);
        }
        return gop.value_ptr;
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
    function_lookup: []?[]const u8,
    functions: tt_exec.FunctionDefs,
    twilight_points: []tt_exec.Point,
    glyph_points: []tt_exec.Point,
    compound_contours: []tt_outline.ContourRange,
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
        self.allocator.free(self.function_lookup);
        self.allocator.free(self.twilight_points);
        self.allocator.free(self.glyph_points);
        self.allocator.free(self.compound_contours);
        self.size.deinit();
        self.* = undefined;
    }

    pub fn hintGlyph(self: *HintMachine, allocator: Allocator, glyph_id: u16) !GlyphHint {
        var topology = try self.program.loadGlyphTopology(allocator, glyph_id);
        defer topology.deinit();
        const executed = try self.executeTopology(glyph_id, &topology, null);
        return self.buildGlyphHint(allocator, glyph_id, executed);
    }

    pub fn hintCachedGlyph(
        self: *HintMachine,
        allocator: Allocator,
        cache: *GlyphTopologyCache,
        glyph_id: u16,
    ) !GlyphHint {
        const executed = try self.executeCachedGlyph(cache, glyph_id);
        return self.buildGlyphHint(allocator, glyph_id, executed);
    }

    /// Executes the glyph program using caller-owned face-invariant topology.
    /// The returned simple glyph view is invalidated by the next glyph execution.
    pub fn executeCachedGlyph(
        self: *HintMachine,
        cache: *GlyphTopologyCache,
        glyph_id: u16,
    ) !ExecutedGlyph {
        return self.executeTopology(glyph_id, try cache.get(glyph_id), cache);
    }

    pub fn buildGlyphHint(
        self: *const HintMachine,
        allocator: Allocator,
        glyph_id: u16,
        executed: ExecutedGlyph,
    ) !GlyphHint {
        return switch (executed) {
            .empty => |advance| emptyGlyphHint(allocator, glyph_id, advance),
            .simple => |hinted| self.makeGlyphHint(allocator, glyph_id, hinted),
        };
    }

    pub fn gridFits(self: *const HintMachine) bool {
        return self.size.grid_fit;
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

    fn executeTopology(
        self: *HintMachine,
        glyph_id: u16,
        topology: *tt_vm.GlyphTopology,
        cache: ?*GlyphTopologyCache,
    ) !ExecutedGlyph {
        return switch (topology.*) {
            .empty => .{ .empty = try self.emptyAdvance(glyph_id) },
            .simple => |*simple| .{ .simple = try self.executeSimpleGlyph(glyph_id, simple) },
            .compound => |*compound| .{ .simple = try self.executeCompoundGlyph(glyph_id, compound, cache) },
        };
    }

    fn executeSimpleGlyph(
        self: *HintMachine,
        glyph_id: u16,
        simple: *const tt_outline.SimpleGlyph,
    ) !tt_vm.HintedSimpleGlyph {
        var context = self.makeContext();
        try self.snapshot.restore(&context);
        context.setFunctions(&self.functions);
        context.setZones(&self.zones);

        return self.size.executeSimpleGlyph(
            &context,
            &self.zones,
            self.glyph_points,
            simple,
            try self.program.glyphPhantomMetrics(glyph_id),
        );
    }

    fn executeCompoundGlyph(
        self: *HintMachine,
        glyph_id: u16,
        compound: *const tt_outline.CompoundGlyph,
        cache: ?*GlyphTopologyCache,
    ) !tt_vm.HintedSimpleGlyph {
        var builder = CompoundGlyphBuilder.init(
            self.size.environment(),
            self.glyph_points,
            self.compound_contours,
        );
        try self.appendCompoundGlyph(&builder, compound, .{}, .zero, cache);
        const metrics_id = compoundMetricsGlyphId(glyph_id, compound);
        const phantom_start = try builder.appendPhantoms(try self.program.glyphPhantomMetrics(metrics_id));

        var context = self.makeContext();
        try self.snapshot.restore(&context);
        context.setFunctions(&self.functions);
        context.setZones(&self.zones);
        return self.size.executeGlyphZone(
            &context,
            &self.zones,
            builder.zone(),
            phantom_start,
            compound.instructions,
        );
    }

    fn appendCompoundGlyph(
        self: *HintMachine,
        builder: *CompoundGlyphBuilder,
        compound: *const tt_outline.CompoundGlyph,
        transform: tt_outline.ComponentTransform,
        offset: Vec2,
        cache: ?*GlyphTopologyCache,
    ) CompoundBuildError!void {
        for (compound.components) |component| {
            try self.appendCompoundComponent(builder, component, transform, offset, cache);
        }
    }

    fn appendCompoundComponent(
        self: *HintMachine,
        builder: *CompoundGlyphBuilder,
        component: tt_outline.CompoundComponent,
        parent_transform: tt_outline.ComponentTransform,
        parent_offset: Vec2,
        cache: ?*GlyphTopologyCache,
    ) CompoundBuildError!void {
        const point_start = builder.point_count;
        const transform = parent_transform.concat(component.transform);
        const offset = componentOffset(parent_transform, parent_offset, component);
        try self.appendComponentTopology(builder, component.glyph_id, transform, offset, cache);
        if (component.args_are_xy) {
            if (component.roundXYToGrid()) builder.roundOffset(point_start, parent_transform.apply(componentRawOffset(component)));
            return;
        }
        try builder.alignComponentPoints(try componentPointArg(component.arg1), try componentPointArg(component.arg2), point_start);
    }

    fn appendComponentTopology(
        self: *HintMachine,
        builder: *CompoundGlyphBuilder,
        glyph_id: u16,
        transform: tt_outline.ComponentTransform,
        offset: Vec2,
        cache: ?*GlyphTopologyCache,
    ) CompoundBuildError!void {
        var owned: ?tt_vm.GlyphTopology = null;
        defer if (owned) |*topology| topology.deinit();

        const topology = if (cache) |topology_cache|
            try topology_cache.get(glyph_id)
        else blk: {
            owned = try self.program.loadGlyphTopology(self.allocator, glyph_id);
            break :blk &owned.?;
        };

        return switch (topology.*) {
            .empty => {},
            .simple => |*simple| builder.appendSimple(simple, transform, offset),
            .compound => |*compound| self.appendCompoundGlyph(builder, compound, transform, offset, cache),
        };
    }

    fn emptyGlyphHint(allocator: Allocator, glyph_id: u16, advance: Vec2) GlyphHint {
        return .{
            .allocator = allocator,
            .glyph_id = glyph_id,
            .advance = advance,
            .bbox = emptyBBox(),
            .curves = &.{},
            .prepared_curves = &.{},
            .curve_bboxes = &.{},
        };
    }

    fn makeGlyphHint(
        self: *const HintMachine,
        allocator: Allocator,
        glyph_id: u16,
        hinted: tt_vm.HintedSimpleGlyph,
    ) !GlyphHint {
        const curves = try hintedCurves(allocator, hinted, self.ppemScaleX(), self.ppemScaleY());
        errdefer allocator.free(curves);
        const prepared = try curve_tex.prepareGlyphCurvesForDirectEncoding(allocator, curves, .zero);
        errdefer allocator.free(prepared);
        const curve_bboxes = try collectCurveBboxes(allocator, prepared);
        errdefer allocator.free(curve_bboxes);

        return .{
            .allocator = allocator,
            .glyph_id = glyph_id,
            .advance = .{ .x = self.toEmX(hinted.advance_x_26_6), .y = 0 },
            .bbox = bboxForCurves(curve_bboxes),
            .curves = curves,
            .prepared_curves = prepared,
            .curve_bboxes = curve_bboxes,
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
    const function_lookup = try allocator.alloc(?[]const u8, functionLookupCapacity(sizes.functions));
    errdefer allocator.free(function_lookup);
    @memset(function_lookup, null);
    const twilight_points = try allocator.alloc(tt_exec.Point, @max(sizes.twilight_points, 1));
    errdefer allocator.free(twilight_points);
    const glyph_points = try allocator.alloc(tt_exec.Point, @max(sizes.glyph_points, 1));
    errdefer allocator.free(glyph_points);
    const compound_contours = try allocator.alloc(tt_outline.ContourRange, compoundContourCapacity(program));
    errdefer allocator.free(compound_contours);

    return .{
        .allocator = allocator,
        .program = program,
        .size = size,
        .stack = stack,
        .storage = storage,
        .storage_snapshot = storage_snapshot,
        .function_entries = function_entries,
        .function_lookup = function_lookup,
        .functions = .{ .entries = function_entries, .lookup = function_lookup },
        .twilight_points = twilight_points,
        .glyph_points = glyph_points,
        .compound_contours = compound_contours,
        .zones = .{
            .twilight = tt_exec.PointZone.initTwilight(twilight_points),
            .glyph = .{ .points = glyph_points[0..0] },
        },
        .snapshot = .{ .graphics = .{}, .storage = storage_snapshot },
    };
}

const CompoundGlyphBuilder = struct {
    environment: tt_exec.Environment,
    points: []tt_exec.Point,
    contours: []tt_outline.ContourRange,
    point_count: usize = 0,
    contour_count: usize = 0,

    fn init(
        environment: tt_exec.Environment,
        points: []tt_exec.Point,
        contours: []tt_outline.ContourRange,
    ) CompoundGlyphBuilder {
        return .{
            .environment = environment,
            .points = points,
            .contours = contours,
        };
    }

    fn appendSimple(
        self: *CompoundGlyphBuilder,
        simple: *const tt_outline.SimpleGlyph,
        transform: tt_outline.ComponentTransform,
        offset: Vec2,
    ) !void {
        const point_base = self.point_count;
        try self.appendContours(simple.contours, point_base);
        for (simple.points) |source| try self.appendPoint(source, transform, offset);
    }

    fn appendPhantoms(self: *CompoundGlyphBuilder, metrics: tt_points.PhantomMetrics) !usize {
        if (self.point_count + tt_points.phantom_count > self.points.len) return error.BufferTooSmall;
        const phantom_start = self.point_count;
        const left = @as(i32, metrics.x_min) - @as(i32, metrics.left_side_bearing);
        const right = left + @as(i32, metrics.advance_width);
        const top = @as(i32, metrics.y_max) + metrics.top_side_bearing;
        const bottom = top - metrics.advance_height;
        self.writePhantom(0, self.environment.scaleFUnitsX(left), 0);
        self.writePhantom(1, self.environment.scaleFUnitsX(right), 0);
        self.writePhantom(2, 0, self.environment.scaleFUnitsY(top));
        self.writePhantom(3, 0, self.environment.scaleFUnitsY(bottom));
        self.point_count += tt_points.phantom_count;
        return phantom_start;
    }

    fn zone(self: *const CompoundGlyphBuilder) tt_exec.PointZone {
        return .{
            .points = self.points[0..self.point_count],
            .contours = self.contours[0..self.contour_count],
        };
    }

    fn alignComponentPoints(
        self: *CompoundGlyphBuilder,
        parent_point: usize,
        component_point: usize,
        component_start: usize,
    ) !void {
        if (parent_point >= component_start) return error.InvalidFont;
        if (component_point < component_start or component_point >= self.point_count) return error.InvalidFont;
        const dx = subWrap(self.points[parent_point].x, self.points[component_point].x);
        const dy = subWrap(self.points[parent_point].y, self.points[component_point].y);
        self.shiftRange(component_start, self.point_count, dx, dy);
    }

    fn roundOffset(self: *CompoundGlyphBuilder, point_start: usize, offset: Vec2) void {
        const dx = round26Dot6(self.scaleX(offset.x)) - self.scaleX(offset.x);
        const dy = round26Dot6(self.scaleY(offset.y)) - self.scaleY(offset.y);
        self.shiftRange(point_start, self.point_count, dx, dy);
    }

    fn appendContours(self: *CompoundGlyphBuilder, contours: []const tt_outline.ContourRange, point_base: usize) !void {
        if (self.contour_count + contours.len > self.contours.len) return error.BufferTooSmall;
        const base: u32 = @intCast(point_base);
        for (contours) |contour| {
            self.contours[self.contour_count] = .{
                .start = base + contour.start,
                .end = base + contour.end,
            };
            self.contour_count += 1;
        }
    }

    fn appendPoint(
        self: *CompoundGlyphBuilder,
        source: tt_outline.Point,
        transform: tt_outline.ComponentTransform,
        offset: Vec2,
    ) !void {
        if (self.point_count >= self.points.len) return error.BufferTooSmall;
        const raw = transform.apply(.{
            .x = @floatFromInt(source.x),
            .y = @floatFromInt(source.y),
        });
        self.points[self.point_count] = self.makePoint(Vec2.add(raw, offset), source.on_curve);
        self.point_count += 1;
    }

    fn makePoint(self: *const CompoundGlyphBuilder, raw: Vec2, on_curve: bool) tt_exec.Point {
        const x = self.scaleX(raw.x);
        const y = self.scaleY(raw.y);
        return .{
            .x = x,
            .y = y,
            .ox = x,
            .oy = y,
            .on_curve = on_curve,
        };
    }

    fn writePhantom(self: *CompoundGlyphBuilder, index: usize, x: i32, y: i32) void {
        const point_index = self.point_count + index;
        self.points[point_index] = .{
            .x = x,
            .y = y,
            .ox = x,
            .oy = y,
            .on_curve = true,
        };
    }

    fn shiftRange(self: *CompoundGlyphBuilder, start: usize, end: usize, dx: i32, dy: i32) void {
        for (self.points[start..end]) |*p| {
            p.x = addWrap(p.x, dx);
            p.y = addWrap(p.y, dy);
            p.ox = addWrap(p.ox, dx);
            p.oy = addWrap(p.oy, dy);
        }
    }

    fn scaleX(self: *const CompoundGlyphBuilder, value: f32) i32 {
        return scaleFUnitFloat(value, self.environment.ppem_x_26_6, self.environment.units_per_em);
    }

    fn scaleY(self: *const CompoundGlyphBuilder, value: f32) i32 {
        return scaleFUnitFloat(value, self.environment.ppem_y_26_6, self.environment.units_per_em);
    }
};

fn componentOffset(
    parent_transform: tt_outline.ComponentTransform,
    parent_offset: Vec2,
    component: tt_outline.CompoundComponent,
) Vec2 {
    if (!component.args_are_xy) return parent_offset;
    return Vec2.add(parent_offset, parent_transform.apply(componentRawOffset(component)));
}

fn componentRawOffset(component: tt_outline.CompoundComponent) Vec2 {
    return .{
        .x = @floatFromInt(component.arg1),
        .y = @floatFromInt(component.arg2),
    };
}

fn componentPointArg(value: i16) !usize {
    if (value < 0) return error.InvalidFont;
    return @intCast(value);
}

fn compoundMetricsGlyphId(glyph_id: u16, compound: *const tt_outline.CompoundGlyph) u16 {
    for (compound.components) |component| {
        if (component.useMyMetrics()) return component.glyph_id;
    }
    return glyph_id;
}

fn compoundContourCapacity(program: *const Program) usize {
    return @max(
        @as(usize, program.maxp.max_composite_contours),
        @as(usize, program.maxp.max_contours),
        1,
    );
}

fn functionLookupCapacity(function_count: usize) usize {
    return @max(function_count, 256);
}

fn scaleFUnitFloat(value: f32, ppem_26_6: u32, units_per_em: u16) i32 {
    if (units_per_em == 0) return 0;
    const scaled = @as(f64, @floatCast(value)) *
        @as(f64, @floatFromInt(ppem_26_6)) /
        @as(f64, @floatFromInt(units_per_em));
    return @intFromFloat(@round(scaled));
}

fn round26Dot6(value: i32) i32 {
    if (value >= 0) return @intCast(@divTrunc(@as(i64, value) + 32, 64) * 64);
    return @intCast(-@divTrunc(@as(i64, -value) + 32, 64) * 64);
}

fn addWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) + @as(i64, rhs));
}

fn subWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) - @as(i64, rhs));
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

pub fn patchGlyphHint(allocator: Allocator, base: BaseGlyph, hint: *const GlyphHint) !GlyphHintPatch {
    const deltas = try encodeDeltas(allocator, base, hint.prepared_curves);
    errdefer allocator.free(deltas);
    return .{
        .allocator = allocator,
        .record = .{
            .base_curve_texel = base.info.base_curve_texel,
            .curve_count = base.info.curve_count,
            .band_entry = base.info.band_entry,
            .bbox = hint.bbox,
        },
        .curve_deltas_f16 = deltas,
        .band_reuse = proveBandReuse(base, hint.curve_bboxes),
    };
}

fn encodeDeltas(allocator: Allocator, base: BaseGlyph, hinted: []const CurveSegment) ![]u16 {
    if (base.info.curve_count != hinted.len) return error.CurveTopologyChanged;
    const encoded = try allocator.alloc(u16, hinted.len * 8);
    errdefer allocator.free(encoded);

    for (hinted, 0..) |hinted_curve, i| {
        const base_curve = decodeBaseCurve(base, i) orelse return error.InvalidBaseCurve;
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

fn proveBandReuse(base: BaseGlyph, curve_bboxes: []const BBox) text_hint.BandReuseProof {
    return text_hint.proveBandReuse(.{
        .band_data = base.page.band_data,
        .band_width = base.page.band_width,
        .band_entry = base.info.band_entry,
        .base_curve_texel = base.info.base_curve_texel,
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

    var hint = try machine.hintGlyph(std.testing.allocator, glyph_id);
    defer hint.deinit();
    var patch = try patchGlyphHint(std.testing.allocator, .{
        .info = info,
        .page = atlas.pages[info.page_index],
    }, &hint);
    defer patch.deinit();

    try std.testing.expect(hint.advance.x > 0);
    try std.testing.expectEqual(@as(usize, info.curve_count), hint.prepared_curves.len);
    try std.testing.expectEqual(@as(usize, info.curve_count) * 8, patch.curve_deltas_f16.len);
    try std.testing.expectEqual(info.base_curve_texel, patch.record.base_curve_texel);
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

    var hint = try machine.hintGlyph(std.testing.allocator, glyph_id);
    defer hint.deinit();

    try std.testing.expectEqual(@as(usize, 0), hint.curves.len);
    try std.testing.expect(hint.advance.x > 0);
}

test "hint machine flattens compound glyphs" {
    const assets = @import("assets");
    const font_mod = @import("../font/ttf.zig");
    const allocator = std.testing.allocator;
    const samples = [_]u32{ 0x00C0, 0x00C1, 0x00C5, 0x00E9, 0x00F1, 0x00FC };

    const program = try Program.init(assets.noto_sans_regular);
    const font = try font_mod.Font.init(assets.noto_sans_regular);
    var machine = try HintMachine.initForProgram(allocator, &program, HintPpem.uniform(12 * 64));
    defer machine.deinit();

    for (samples) |codepoint| {
        const glyph_id = try font.glyphIndex(codepoint);
        if (glyph_id == 0) continue;

        var topology = try program.loadGlyphTopology(allocator, glyph_id);
        defer topology.deinit();
        switch (topology) {
            .compound => {},
            else => continue,
        }

        var hint = try machine.hintGlyph(allocator, glyph_id);
        defer hint.deinit();
        try std.testing.expect(hint.advance.x > 0);
        try std.testing.expect(hint.curves.len > 0);
        return;
    }

    return error.SkipZigTest;
}

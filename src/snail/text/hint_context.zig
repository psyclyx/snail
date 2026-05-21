const std = @import("std");

const atlas_mod = @import("atlas.zig");
const bezier = @import("../math/bezier.zig");
const config_mod = @import("config.zig");
const range_mod = @import("../range.zig");
const shape_mod = @import("shape.zig");
const text_hint = @import("../render/format/text_hint.zig");
const tt_hint = @import("tt_hint.zig");
const types_mod = @import("types.zig");
const vec = @import("../math/vec.zig");

const Allocator = std.mem.Allocator;
const BBox = bezier.BBox;
const FaceIndex = config_mod.FaceIndex;
const Range = range_mod.Range;
const ShapedText = types_mod.ShapedText;
const TextAtlas = atlas_mod.TextAtlas;
const Vec2 = vec.Vec2;
const shapedPenAt = shape_mod.shapedPenAt;

pub const HintGlyphKey = struct {
    face_index: FaceIndex,
    ppem_x_26_6: u32,
    ppem_y_26_6: u32,
    glyph_id: u16,

    const Context = struct {
        pub fn hash(_: Context, key: HintGlyphKey) u64 {
            var h = hashField(0xcbf29ce484222325, key.face_index);
            h = hashField(h, key.ppem_x_26_6);
            h = hashField(h, key.ppem_y_26_6);
            h = hashField(h, key.glyph_id);
            return h;
        }

        pub fn eql(_: Context, a: HintGlyphKey, b: HintGlyphKey) bool {
            return a.face_index == b.face_index and
                a.ppem_x_26_6 == b.ppem_x_26_6 and
                a.ppem_y_26_6 == b.ppem_y_26_6 and
                a.glyph_id == b.glyph_id;
        }
    };
};

const SizeKey = struct {
    face_index: FaceIndex,
    ppem_x_26_6: u32,
    ppem_y_26_6: u32,

    fn fromGlyphKey(key: HintGlyphKey) SizeKey {
        return .{
            .face_index = key.face_index,
            .ppem_x_26_6 = key.ppem_x_26_6,
            .ppem_y_26_6 = key.ppem_y_26_6,
        };
    }

    const Context = struct {
        pub fn hash(_: Context, key: SizeKey) u64 {
            var h = hashField(0xcbf29ce484222325, key.face_index);
            h = hashField(h, key.ppem_x_26_6);
            h = hashField(h, key.ppem_y_26_6);
            return h;
        }

        pub fn eql(_: Context, a: SizeKey, b: SizeKey) bool {
            return a.face_index == b.face_index and
                a.ppem_x_26_6 == b.ppem_x_26_6 and
                a.ppem_y_26_6 == b.ppem_y_26_6;
        }
    };
};

const FaceIndexContext = struct {
    pub fn hash(_: FaceIndexContext, face_index: FaceIndex) u64 {
        return hashField(0xcbf29ce484222325, face_index);
    }

    pub fn eql(_: FaceIndexContext, a: FaceIndex, b: FaceIndex) bool {
        return a == b;
    }
};

pub const HintRejectReason = enum {
    invalid_face,
    no_true_type_program,
    synthetic_embolden,
    color_glyph,
    grid_fit_disabled,
    missing_base_glyph,
    topology_changed,
    bands_not_reusable,
    empty_hinted_outline,
};

pub const HintReject = struct {
    key: HintGlyphKey,
    reason: HintRejectReason,
};

pub const HintedGlyphAttachment = struct {
    record: text_hint.GlyphRecord,
    curve_deltas_f16: []u16,
};

pub const HintedGlyphValue = struct {
    key: HintGlyphKey,
    advance: Vec2,
    bbox: BBox,
    attachment: ?HintedGlyphAttachment = null,

    pub fn deinit(self: *HintedGlyphValue, allocator: Allocator) void {
        if (self.attachment) |attachment| allocator.free(attachment.curve_deltas_f16);
        self.* = undefined;
    }

    pub fn renderable(self: *const HintedGlyphValue) bool {
        return self.attachment != null;
    }
};

pub const HintGlyphStatus = union(enum) {
    ready: *const HintedGlyphValue,
    missing,
    unsupported: HintRejectReason,
};

pub const PreparedHintGlyph = struct {
    face_index: FaceIndex,
    glyph_id: u16,
    placement_delta: Vec2,
    hint: *const HintedGlyphValue,
};

pub const PreparedHintRunStats = struct {
    glyph_count: usize = 0,
    advance: Vec2 = .zero,
};

pub const PreparedHintRun = struct {
    allocator: Allocator,
    atlas: *const TextAtlas,
    atlas_identity: u64,
    glyphs: []PreparedHintGlyph,
    stats: PreparedHintRunStats,

    pub fn validateAtlas(self: *const PreparedHintRun, atlas: *const TextAtlas) !void {
        if (self.atlas != atlas) return error.WrongTextAtlasSnapshot;
        if (atlas.snapshotIdentity() != self.atlas_identity) return error.WrongTextAtlasSnapshot;
    }

    pub fn deinit(self: *PreparedHintRun) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub const PreparedBestEffortHintGlyph = struct {
    face_index: FaceIndex,
    glyph_id: u16,
    placement_delta: Vec2,
    advance: Vec2,
    source: union(enum) {
        hint: *const HintedGlyphValue,
        fallback,
    },
};

pub const PreparedBestEffortHintRunStats = struct {
    glyph_count: usize = 0,
    hinted_count: usize = 0,
    fallback_count: usize = 0,
    advance: Vec2 = .zero,
};

pub const PreparedBestEffortHintRun = struct {
    allocator: Allocator,
    atlas: *const TextAtlas,
    atlas_identity: u64,
    glyphs: []PreparedBestEffortHintGlyph,
    stats: PreparedBestEffortHintRunStats,

    pub fn validateAtlas(self: *const PreparedBestEffortHintRun, atlas: *const TextAtlas) !void {
        if (self.atlas != atlas) return error.WrongTextAtlasSnapshot;
        if (atlas.snapshotIdentity() != self.atlas_identity) return error.WrongTextAtlasSnapshot;
    }

    pub fn deinit(self: *PreparedBestEffortHintRun) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub const PrepareRunOptions = struct {
    shaped: *const ShapedText,
    glyphs: Range = .{},
    ppem: tt_hint.HintPpem,
};

const FaceProgramState = struct {
    cache: tt_hint.GlyphTopologyCache,

    fn init(allocator: Allocator, face: anytype) !FaceProgramState {
        return .{ .cache = try tt_hint.GlyphTopologyCache.init(allocator, face) };
    }

    fn deinit(self: *FaceProgramState) void {
        self.cache.deinit();
        self.* = undefined;
    }
};

const SizeHintState = struct {
    machine: tt_hint.HintMachine,

    fn init(allocator: Allocator, face: anytype, ppem: tt_hint.HintPpem) !SizeHintState {
        return .{ .machine = try tt_hint.HintMachine.init(allocator, face, ppem) };
    }

    fn deinit(self: *SizeHintState) void {
        self.machine.deinit();
        self.* = undefined;
    }
};

const GlyphEntry = union(enum) {
    ready: *HintedGlyphValue,
    unsupported: HintRejectReason,
};

const FaceProgramMap = std.HashMap(FaceIndex, FaceProgramState, FaceIndexContext, 80);
const SizeStateMap = std.HashMap(SizeKey, SizeHintState, SizeKey.Context, 80);
const GlyphMap = std.HashMap(HintGlyphKey, GlyphEntry, HintGlyphKey.Context, 80);

pub const TrueTypeHintContext = struct {
    allocator: Allocator,
    atlas: *const TextAtlas,
    atlas_identity: u64,
    face_programs: FaceProgramMap,
    size_states: SizeStateMap,
    glyphs: GlyphMap,

    pub fn init(allocator: Allocator, atlas: *const TextAtlas) TrueTypeHintContext {
        return .{
            .allocator = allocator,
            .atlas = atlas,
            .atlas_identity = atlas.snapshotIdentity(),
            .face_programs = FaceProgramMap.init(allocator),
            .size_states = SizeStateMap.init(allocator),
            .glyphs = GlyphMap.init(allocator),
        };
    }

    pub fn deinit(self: *TrueTypeHintContext) void {
        self.clear();
        self.face_programs.deinit();
        self.size_states.deinit();
        self.glyphs.deinit();
        self.* = undefined;
    }

    pub fn resetForAtlas(self: *TrueTypeHintContext, atlas: *const TextAtlas) void {
        self.clear();
        self.atlas = atlas;
        self.atlas_identity = atlas.snapshotIdentity();
    }

    pub fn validateAtlas(self: *const TrueTypeHintContext) !void {
        if (self.atlas.snapshotIdentity() != self.atlas_identity) return error.WrongTextAtlasSnapshot;
    }

    pub fn prepareSize(self: *TrueTypeHintContext, face_index: FaceIndex, ppem: tt_hint.HintPpem) !void {
        try self.validateAtlas();
        const key = HintGlyphKey{
            .face_index = face_index,
            .ppem_x_26_6 = ppem.x_26_6,
            .ppem_y_26_6 = ppem.y_26_6,
            .glyph_id = 0,
        };
        _ = try self.sizeStateFor(SizeKey.fromGlyphKey(key));
    }

    pub fn queryGlyph(self: *const TrueTypeHintContext, key: HintGlyphKey) HintGlyphStatus {
        const entry = self.glyphs.get(key) orelse return .missing;
        return switch (entry) {
            .ready => |value| .{ .ready = value },
            .unsupported => |reason| .{ .unsupported = reason },
        };
    }

    pub fn computeGlyph(self: *TrueTypeHintContext, key: HintGlyphKey) !HintGlyphStatus {
        try self.validateAtlas();
        switch (self.queryGlyph(key)) {
            .missing => {},
            else => |status| return status,
        }
        return self.computeMissingGlyph(key);
    }

    pub fn prepareRun(
        self: *TrueTypeHintContext,
        allocator: Allocator,
        options: PrepareRunOptions,
    ) !PreparedHintRun {
        try self.validateAtlas();
        if (options.shaped.config != self.atlas.config) return error.WrongTextAtlasSnapshot;

        const range = options.glyphs.resolve(options.shaped.glyphs.len);
        const out_glyphs = try allocator.alloc(PreparedHintGlyph, range.end - range.start);
        errdefer allocator.free(out_glyphs);

        var nominal_pen = shapedPenAt(options.shaped, range.start);
        var hinted_pen = Vec2.zero;
        for (out_glyphs, options.shaped.glyphs[range.start..range.end]) |*out, glyph| {
            const hint = try self.prepareShapedGlyph(glyph, options.ppem);
            out.* = .{
                .face_index = glyph.face_index,
                .glyph_id = glyph.glyph_id,
                .placement_delta = .{
                    .x = glyph.x_offset - nominal_pen.x,
                    .y = glyph.y_offset - nominal_pen.y,
                },
                .hint = hint,
            };
            nominal_pen = Vec2.add(nominal_pen, .{ .x = glyph.x_advance, .y = glyph.y_advance });
            hinted_pen = Vec2.add(hinted_pen, hint.advance);
        }

        return .{
            .allocator = allocator,
            .atlas = self.atlas,
            .atlas_identity = self.atlas_identity,
            .glyphs = out_glyphs,
            .stats = .{ .glyph_count = out_glyphs.len, .advance = hinted_pen },
        };
    }

    pub fn prepareBestEffortRun(
        self: *TrueTypeHintContext,
        allocator: Allocator,
        options: PrepareRunOptions,
    ) !PreparedBestEffortHintRun {
        try self.validateAtlas();
        if (options.shaped.config != self.atlas.config) return error.WrongTextAtlasSnapshot;

        const range = options.glyphs.resolve(options.shaped.glyphs.len);
        const out_glyphs = try allocator.alloc(PreparedBestEffortHintGlyph, range.end - range.start);
        errdefer allocator.free(out_glyphs);

        var stats = PreparedBestEffortHintRunStats{ .glyph_count = out_glyphs.len };
        var nominal_pen = shapedPenAt(options.shaped, range.start);
        for (out_glyphs, options.shaped.glyphs[range.start..range.end]) |*out, glyph| {
            const placement_delta = Vec2{
                .x = glyph.x_offset - nominal_pen.x,
                .y = glyph.y_offset - nominal_pen.y,
            };
            const status = try self.computeGlyph(keyForGlyph(glyph, options.ppem));
            switch (status) {
                .ready => |hint| {
                    out.* = .{
                        .face_index = glyph.face_index,
                        .glyph_id = glyph.glyph_id,
                        .placement_delta = placement_delta,
                        .advance = hint.advance,
                        .source = .{ .hint = hint },
                    };
                    if (hint.renderable()) stats.hinted_count += 1;
                },
                .missing, .unsupported => {
                    out.* = .{
                        .face_index = glyph.face_index,
                        .glyph_id = glyph.glyph_id,
                        .placement_delta = placement_delta,
                        .advance = .{ .x = glyph.x_advance, .y = glyph.y_advance },
                        .source = .fallback,
                    };
                    stats.fallback_count += 1;
                },
            }
            nominal_pen = Vec2.add(nominal_pen, .{ .x = glyph.x_advance, .y = glyph.y_advance });
            stats.advance = Vec2.add(stats.advance, out.advance);
        }

        return .{
            .allocator = allocator,
            .atlas = self.atlas,
            .atlas_identity = self.atlas_identity,
            .glyphs = out_glyphs,
            .stats = stats,
        };
    }

    fn clear(self: *TrueTypeHintContext) void {
        var glyph_values = self.glyphs.valueIterator();
        while (glyph_values.next()) |entry| {
            switch (entry.*) {
                .ready => |value| {
                    value.deinit(self.allocator);
                    self.allocator.destroy(value);
                },
                .unsupported => {},
            }
        }
        self.glyphs.clearRetainingCapacity();

        var size_values = self.size_states.valueIterator();
        while (size_values.next()) |state| state.deinit();
        self.size_states.clearRetainingCapacity();

        var face_values = self.face_programs.valueIterator();
        while (face_values.next()) |state| state.deinit();
        self.face_programs.clearRetainingCapacity();
    }

    fn computeMissingGlyph(self: *TrueTypeHintContext, key: HintGlyphKey) !HintGlyphStatus {
        const face_index = self.atlas.checkedFaceIndex(key.face_index) catch {
            return self.putUnsupported(key, .invalid_face);
        };
        const face = &self.atlas.config.faces[face_index];
        if (face.synthetic.embolden != 0) return self.putUnsupported(key, .synthetic_embolden);

        const face_view = self.atlas.faceView(face_index, .{});
        if (glyphHasColorLayers(&face_view, key.glyph_id)) return self.putUnsupported(key, .color_glyph);

        var face_state = self.faceStateFor(face_index) catch |err| switch (err) {
            error.NoTrueTypeProgram => return self.putUnsupported(key, .no_true_type_program),
            else => return err,
        };
        var size_state = self.sizeStateFor(SizeKey.fromGlyphKey(key)) catch |err| switch (err) {
            error.NoTrueTypeProgram => return self.putUnsupported(key, .no_true_type_program),
            else => return err,
        };
        if (!size_state.machine.gridFits()) return self.putUnsupported(key, .grid_fit_disabled);

        var hint = try size_state.machine.hintCachedGlyph(self.allocator, &face_state.cache, key.glyph_id);

        if (hint.curves.len == 0) {
            const can_skip = glyphCanSkipEmptyHint(&face_view, key.glyph_id);
            defer hint.deinit();
            if (!can_skip) return self.putUnsupported(key, .empty_hinted_outline);
            return self.putReadyValue(.{
                .key = key,
                .advance = hint.advance,
                .bbox = hint.bbox,
                .attachment = null,
            });
        }

        const base_info = face_view.getGlyph(key.glyph_id);
        const info = base_info orelse {
            hint.deinit();
            return self.putUnsupported(key, .missing_base_glyph);
        };
        var patch = tt_hint.patchGlyphHint(self.allocator, .{
            .info = info,
            .page = self.atlas.pages[info.page_index],
        }, &hint) catch |err| switch (err) {
            error.CurveTopologyChanged, error.InvalidBaseCurve => {
                hint.deinit();
                return self.putUnsupported(key, .topology_changed);
            },
            else => {
                hint.deinit();
                return err;
            },
        };
        return self.putReadyValue(takeHintedGlyphValue(key, &hint, &patch));
    }

    fn prepareShapedGlyph(
        self: *TrueTypeHintContext,
        glyph: ShapedText.Glyph,
        ppem: tt_hint.HintPpem,
    ) !*const HintedGlyphValue {
        const status = try self.computeGlyph(keyForGlyph(glyph, ppem));
        return switch (status) {
            .ready => |value| value,
            .missing, .unsupported => error.HintUnavailable,
        };
    }

    fn faceStateFor(self: *TrueTypeHintContext, face_index: FaceIndex) !*FaceProgramState {
        if (self.face_programs.getPtr(face_index)) |state| return state;
        const face = &self.atlas.config.faces[face_index];
        var state = try FaceProgramState.init(self.allocator, face);
        errdefer state.deinit();
        try self.face_programs.put(face_index, state);
        return self.face_programs.getPtr(face_index).?;
    }

    fn sizeStateFor(self: *TrueTypeHintContext, key: SizeKey) !*SizeHintState {
        if (self.size_states.getPtr(key)) |state| return state;
        const face = &self.atlas.config.faces[key.face_index];
        var state = try SizeHintState.init(self.allocator, face, .{
            .x_26_6 = key.ppem_x_26_6,
            .y_26_6 = key.ppem_y_26_6,
        });
        errdefer state.deinit();
        try self.size_states.put(key, state);
        return self.size_states.getPtr(key).?;
    }

    fn putReadyValue(self: *TrueTypeHintContext, value: HintedGlyphValue) !HintGlyphStatus {
        const node = try self.allocator.create(HintedGlyphValue);
        errdefer self.allocator.destroy(node);
        node.* = value;
        errdefer node.deinit(self.allocator);

        try self.glyphs.put(value.key, .{ .ready = node });
        return .{ .ready = node };
    }

    fn putUnsupported(self: *TrueTypeHintContext, key: HintGlyphKey, reason: HintRejectReason) !HintGlyphStatus {
        try self.glyphs.put(key, .{ .unsupported = reason });
        return .{ .unsupported = reason };
    }
};

pub fn keyForGlyph(glyph: ShapedText.Glyph, ppem: tt_hint.HintPpem) HintGlyphKey {
    return .{
        .face_index = glyph.face_index,
        .ppem_x_26_6 = ppem.x_26_6,
        .ppem_y_26_6 = ppem.y_26_6,
        .glyph_id = glyph.glyph_id,
    };
}

fn takeHintedGlyphValue(
    key: HintGlyphKey,
    hint: *tt_hint.GlyphHint,
    patch: *tt_hint.GlyphHintPatch,
) HintedGlyphValue {
    const deltas = patch.curve_deltas_f16;
    patch.curve_deltas_f16 = &.{};
    defer patch.deinit();
    defer hint.deinit();

    return .{
        .key = key,
        .advance = hint.advance,
        .bbox = hint.bbox,
        .attachment = .{
            .record = patch.record,
            .curve_deltas_f16 = deltas,
        },
    };
}

fn glyphCanSkipEmptyHint(face_view: anytype, glyph_id: u16) bool {
    if (glyph_id == 0) return true;
    if (glyphHasColorLayers(face_view, glyph_id)) return false;
    return face_view.getGlyph(glyph_id) == null;
}

fn glyphHasColorLayers(face_view: anytype, glyph_id: u16) bool {
    if (face_view.getColrBase(glyph_id) != null) return true;
    var layers = face_view.colrLayers(glyph_id);
    return layers.count() != 0;
}

fn hashField(seed: u64, value: anytype) u64 {
    var h = seed ^ @as(u64, @intCast(value));
    h *%= 0x100000001b3;
    h ^= h >> 32;
    return h;
}

test "hint context prepares runs and caches repeated glyphs" {
    const assets = @import("assets");
    const testing = std.testing;
    const samples = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    var atlas = try TextAtlas.init(testing.allocator, &.{.{ .data = assets.noto_sans_regular }});
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, samples)) |next| {
        atlas.deinit();
        atlas = next;
    }

    var context = TrueTypeHintContext.init(testing.allocator, &atlas);
    defer context.deinit();

    for (samples) |sample| {
        var text = [_]u8{ sample, sample, sample, sample };
        var shaped = try atlas.shapeText(testing.allocator, .{}, &text);
        defer shaped.deinit();
        if (shaped.glyphs.len != text.len) continue;

        var first_run = context.prepareRun(testing.allocator, .{
            .shaped = &shaped,
            .ppem = tt_hint.HintPpem.uniform(12 * 64),
        }) catch |err| switch (err) {
            error.HintUnavailable => continue,
            else => return err,
        };
        defer first_run.deinit();
        try testing.expectEqual(@as(usize, 4), first_run.glyphs.len);
        try testing.expect(first_run.stats.advance.x > 0);

        const cached = first_run.glyphs[0].hint;
        for (first_run.glyphs) |glyph| try testing.expect(glyph.hint == cached);

        var second_run = try context.prepareRun(testing.allocator, .{
            .shaped = &shaped,
            .ppem = tt_hint.HintPpem.uniform(12 * 64),
        });
        defer second_run.deinit();
        try testing.expect(second_run.glyphs[0].hint == cached);
        return;
    }

    return error.SkipZigTest;
}

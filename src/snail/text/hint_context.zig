const std = @import("std");

const atlas_mod = @import("atlas.zig");
const bezier = @import("../math/bezier.zig");
const config_mod = @import("config.zig");
const range_mod = @import("../range.zig");
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
    missing_base_glyph,
    unsupported_compound,
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

pub const RunGlyphKey = struct {
    shaped_index: usize,
    key: HintGlyphKey,
};

pub const HintRunKeys = struct {
    allocator: Allocator,
    glyphs: []RunGlyphKey,
    unique: []HintGlyphKey,

    pub fn deinit(self: *HintRunKeys) void {
        self.allocator.free(self.glyphs);
        self.allocator.free(self.unique);
        self.* = undefined;
    }
};

pub const HintRunAvailability = struct {
    allocator: Allocator,
    glyphs: []?*const HintedGlyphValue,
    missing_keys: []HintGlyphKey,
    unsupported: []HintReject,

    pub fn deinit(self: *HintRunAvailability) void {
        self.allocator.free(self.glyphs);
        self.allocator.free(self.missing_keys);
        self.allocator.free(self.unsupported);
        self.* = undefined;
    }

    pub fn ready(self: *const HintRunAvailability) bool {
        return self.missing_keys.len == 0 and self.unsupported.len == 0;
    }
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
const KeySet = std.HashMap(HintGlyphKey, void, HintGlyphKey.Context, 80);

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

    pub fn queryRun(
        self: *const TrueTypeHintContext,
        allocator: Allocator,
        keys: *const HintRunKeys,
    ) !HintRunAvailability {
        try self.validateAtlas();

        const glyphs = try allocator.alloc(?*const HintedGlyphValue, keys.glyphs.len);
        errdefer allocator.free(glyphs);
        @memset(glyphs, null);

        var missing = std.ArrayListUnmanaged(HintGlyphKey).empty;
        errdefer missing.deinit(allocator);
        var unsupported = std.ArrayListUnmanaged(HintReject).empty;
        errdefer unsupported.deinit(allocator);

        for (keys.unique) |key| {
            switch (self.queryGlyph(key)) {
                .ready => {},
                .missing => try missing.append(allocator, key),
                .unsupported => |reason| try unsupported.append(allocator, .{ .key = key, .reason = reason }),
            }
        }

        for (keys.glyphs, glyphs) |run_key, *out| {
            out.* = switch (self.queryGlyph(run_key.key)) {
                .ready => |value| value,
                else => null,
            };
        }

        return .{
            .allocator = allocator,
            .glyphs = glyphs,
            .missing_keys = try missing.toOwnedSlice(allocator),
            .unsupported = try unsupported.toOwnedSlice(allocator),
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

        const base_info = face_view.getGlyph(key.glyph_id);
        const base = if (base_info) |info|
            tt_hint.BaseGlyph{ .info = info, .page = self.atlas.pages[info.page_index] }
        else
            null;

        var hint = size_state.machine.hintCachedGlyph(self.allocator, &face_state.cache, key.glyph_id, .{ .base = base }) catch |err| switch (err) {
            error.UnsupportedCompoundHinting => return self.putUnsupported(key, .unsupported_compound),
            error.CurveTopologyChanged, error.InvalidBaseCurve => return self.putUnsupported(key, .topology_changed),
            else => return err,
        };

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

        const info = base_info orelse {
            hint.deinit();
            return self.putUnsupported(key, .missing_base_glyph);
        };
        if (hint.bandsReusable() != true) {
            hint.deinit();
            return self.putUnsupported(key, .bands_not_reusable);
        }

        return self.putReadyValue(takeHintedGlyphValue(key, info, &hint));
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

pub fn gatherRunKeys(
    allocator: Allocator,
    shaped: *const ShapedText,
    glyphs: Range,
    ppem: tt_hint.HintPpem,
) !HintRunKeys {
    const range = glyphs.resolve(shaped.glyphs.len);
    var run_keys = std.ArrayListUnmanaged(RunGlyphKey).empty;
    errdefer run_keys.deinit(allocator);
    try run_keys.ensureTotalCapacity(allocator, range.end - range.start);

    var unique = std.ArrayListUnmanaged(HintGlyphKey).empty;
    errdefer unique.deinit(allocator);

    var seen = KeySet.init(allocator);
    defer seen.deinit();

    for (shaped.glyphs[range.start..range.end], range.start..) |glyph, shaped_index| {
        const key = keyForGlyph(glyph, ppem);
        try run_keys.append(allocator, .{ .shaped_index = shaped_index, .key = key });
        const gop = try seen.getOrPut(key);
        if (!gop.found_existing) try unique.append(allocator, key);
    }

    return .{
        .allocator = allocator,
        .glyphs = try run_keys.toOwnedSlice(allocator),
        .unique = try unique.toOwnedSlice(allocator),
    };
}

fn takeHintedGlyphValue(
    key: HintGlyphKey,
    base_info: @import("../render/format/atlas/curve.zig").CurveAtlas.GlyphInfo,
    hint: *tt_hint.GlyphHint,
) HintedGlyphValue {
    const deltas = hint.curve_deltas_f16;
    hint.curve_deltas_f16 = &.{};
    defer hint.deinit();

    return .{
        .key = key,
        .advance = hint.advance,
        .bbox = hint.bbox,
        .attachment = .{
            .record = .{
                .base_curve_texel = base_info.base_curve_texel,
                .curve_count = base_info.curve_count,
                .band_entry = base_info.band_entry,
                .bbox = hint.bbox,
            },
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

test "hint context caches repeated glyphs by face size and glyph id" {
    const assets = @import("assets");
    const testing = std.testing;

    var atlas = try TextAtlas.init(testing.allocator, &.{.{ .data = assets.noto_sans_regular }});
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, "A")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var context = TrueTypeHintContext.init(testing.allocator, &atlas);
    defer context.deinit();

    var shaped = try atlas.shapeText(testing.allocator, .{}, "AAAA");
    defer shaped.deinit();

    var keys = try gatherRunKeys(testing.allocator, &shaped, .{}, tt_hint.HintPpem.uniform(12 * 64));
    defer keys.deinit();
    try testing.expectEqual(@as(usize, 4), keys.glyphs.len);
    try testing.expectEqual(@as(usize, 1), keys.unique.len);

    var missing = try context.queryRun(testing.allocator, &keys);
    defer missing.deinit();
    try testing.expectEqual(@as(usize, 1), missing.missing_keys.len);
    try testing.expectEqual(@as(usize, 0), missing.unsupported.len);

    const first_status = try context.computeGlyph(keys.unique[0]);
    const second_status = try context.computeGlyph(keys.unique[0]);
    switch (first_status) {
        .ready => |first| {
            const second = switch (second_status) {
                .ready => |value| value,
                else => return error.TestExpectedEqual,
            };
            try testing.expect(first == second);

            var ready = try context.queryRun(testing.allocator, &keys);
            defer ready.deinit();
            try testing.expect(ready.ready());
            for (ready.glyphs) |value| try testing.expect(value.? == first);
        },
        .unsupported => |reason| {
            try testing.expectEqual(reason, switch (second_status) {
                .unsupported => |second_reason| second_reason,
                else => return error.TestExpectedEqual,
            });

            var rejected = try context.queryRun(testing.allocator, &keys);
            defer rejected.deinit();
            try testing.expectEqual(@as(usize, 1), rejected.unsupported.len);
            try testing.expectEqual(reason, rejected.unsupported[0].reason);
        },
        .missing => return error.TestExpectedEqual,
    }
}

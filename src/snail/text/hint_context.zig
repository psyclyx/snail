const std = @import("std");

const atlas_mod = @import("atlas.zig");
const bezier = @import("../math/bezier.zig");
const config_mod = @import("config.zig");
const text_hint = @import("../render/format/text_hint.zig");
const tt_hint = @import("tt_hint.zig");
const types_mod = @import("types.zig");
const vec = @import("../math/vec.zig");

const Allocator = std.mem.Allocator;
const BBox = bezier.BBox;
const FaceIndex = config_mod.FaceIndex;
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
    grid_fit_disabled,
    missing_base_glyph,
    topology_changed,
    bands_not_reusable,
    empty_hinted_outline,
    exec_failed,
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

/// A prepared run of hinted glyphs. Always whole-run (covers every glyph of
/// the source `ShapedText`). Each glyph carries either a hint pointer or a
/// fallback marker; callers wanting strict all-or-nothing semantics check
/// `stats.fallback_count == 0` before consuming the run.
pub const PreparedHintRun = struct {
    allocator: Allocator,
    atlas: *const TextAtlas,
    atlas_identity: u64,
    glyphs: []Glyph,
    stats: Stats,

    pub const Glyph = struct {
        face_index: FaceIndex,
        glyph_id: u16,
        placement_delta: Vec2,
        advance: Vec2,
        source: union(enum) {
            hint: *const HintedGlyphValue,
            fallback,
        },
    };

    pub const Stats = struct {
        glyph_count: usize = 0,
        hinted_count: usize = 0,
        fallback_count: usize = 0,
        advance: Vec2 = .zero,
    };

    pub fn validateAtlas(self: *const PreparedHintRun, atlas: *const TextAtlas) !void {
        if (self.atlas != atlas) return error.WrongTextAtlasSnapshot;
        if (atlas.snapshotIdentity() != self.atlas_identity) return error.WrongTextAtlasSnapshot;
    }

    pub fn deinit(self: *PreparedHintRun) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub const PrepareRunOptions = struct {
    shaped: *const ShapedText,
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

    fn init(
        allocator: Allocator,
        face: anytype,
        ppem: tt_hint.HintPpem,
        options: tt_hint.HintOptions,
    ) !SizeHintState {
        return .{ .machine = try tt_hint.HintMachine.initWithOptions(allocator, face, ppem, options) };
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

pub const TrueTypeHintContextOptions = struct {
    /// See `tt_vm.SizeRequest.cvt_headroom`. A small non-zero value (e.g.
    /// 32) tolerates fonts that write past their declared CVT length —
    /// common in the wild, accepted by FreeType/Skia/CoreText — at the
    /// cost of a few hundred extra bytes per cached size.
    cvt_headroom: u32 = 0,

    fn toHintOptions(self: TrueTypeHintContextOptions) tt_hint.HintOptions {
        return .{ .cvt_headroom = self.cvt_headroom };
    }
};

pub const TrueTypeHintContext = struct {
    allocator: Allocator,
    atlas: *const TextAtlas,
    atlas_identity: u64,
    options: TrueTypeHintContextOptions,
    face_programs: FaceProgramMap,
    size_states: SizeStateMap,
    glyphs: GlyphMap,

    pub fn init(allocator: Allocator, atlas: *const TextAtlas) TrueTypeHintContext {
        return initWithOptions(allocator, atlas, .{});
    }

    pub fn initWithOptions(
        allocator: Allocator,
        atlas: *const TextAtlas,
        options: TrueTypeHintContextOptions,
    ) TrueTypeHintContext {
        return .{
            .allocator = allocator,
            .atlas = atlas,
            .atlas_identity = atlas.snapshotIdentity(),
            .options = options,
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

    /// Rebind to a new atlas snapshot. If the new snapshot extends the
    /// current one (`canRebindFrom`), the cached hint values, face
    /// programs, and size states are preserved — caches survive atlas
    /// growth. Otherwise the cache is cleared. Eliminates the rehint
    /// storm on `ensureText`-style snapshot extensions.
    pub fn rebindAtlas(self: *TrueTypeHintContext, atlas: *const TextAtlas) void {
        if (!atlas.canRebindFrom(self.atlas)) self.clear();
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

    /// Prepare hinted glyphs for the entire `options.shaped`. Per-glyph,
    /// either a hint pointer or a `.fallback` marker is recorded. Strict
    /// callers check `result.stats.fallback_count == 0` after this call.
    pub fn prepareRun(
        self: *TrueTypeHintContext,
        allocator: Allocator,
        options: PrepareRunOptions,
    ) !PreparedHintRun {
        try self.validateAtlas();
        if (options.shaped.config != self.atlas.config) return error.WrongTextAtlasSnapshot;

        const out_glyphs = try allocator.alloc(PreparedHintRun.Glyph, options.shaped.glyphs.len);
        errdefer allocator.free(out_glyphs);

        var stats = PreparedHintRun.Stats{ .glyph_count = out_glyphs.len };
        var nominal_pen = Vec2.zero;
        for (out_glyphs, options.shaped.glyphs) |*out, glyph| {
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
                    // Metric-only auto-hint: every fallback glyph gets its
                    // advance snapped to whole pixels at the hint context's
                    // PPEM. Unhinted curve geometry still renders via the
                    // `.fallback` path downstream, but integer-pixel advances
                    // stop adjacent glyphs from sub-pixel shimmering and let
                    // columns of text line up cleanly. The one opt-out:
                    // `grid_fit_disabled` is the font author's explicit
                    // "do not grid-fit at this PPEM" instruction — honour
                    // that by passing the original advance through.
                    const honor_no_snap = switch (status) {
                        .unsupported => |reason| reason == .grid_fit_disabled,
                        else => false,
                    };
                    const advance: Vec2 = if (honor_no_snap)
                        .{ .x = glyph.x_advance, .y = glyph.y_advance }
                    else
                        snapEmAdvanceToPixels(
                            .{ .x = glyph.x_advance, .y = glyph.y_advance },
                            options.ppem,
                        );
                    out.* = .{
                        .face_index = glyph.face_index,
                        .glyph_id = glyph.glyph_id,
                        .placement_delta = placement_delta,
                        .advance = advance,
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
        // Synthetic emboldening (faux-bold) is applied as a second translated
        // copy of the rendered glyph at draw time (see `batch.zig`). The hint
        // VM runs on the un-emboldened outline; both copies share the same
        // hinted geometry. Stems end up `embolden` pixels wider than the hint
        // program anticipated, but every stem stays grid-aligned — strictly
        // better than rejecting and rendering both copies unhinted.

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

        var hint = size_state.machine.hintCachedGlyph(self.allocator, &face_state.cache, key.glyph_id) catch |err| {
            if (isExecFailure(err)) return self.putUnsupported(key, .exec_failed);
            return err;
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
        }, self.options.toHintOptions());
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

/// Round each axis of an em-unit advance to the nearest whole pixel at the
/// given PPEM. Used by the metric-only auto-hint path: even when we can't
/// run a hint program, integer-pixel advances keep adjacent glyphs from
/// shimmering on horizontal scrolls and let columns of text line up cleanly.
fn snapEmAdvanceToPixels(em_advance: Vec2, ppem: tt_hint.HintPpem) Vec2 {
    const ppem_x = @as(f32, @floatFromInt(ppem.x_26_6)) / 64.0;
    const ppem_y = @as(f32, @floatFromInt(ppem.y_26_6)) / 64.0;
    return .{
        .x = if (ppem_x > 0) @round(em_advance.x * ppem_x) / ppem_x else em_advance.x,
        .y = if (ppem_y > 0) @round(em_advance.y * ppem_y) / ppem_y else em_advance.y,
    };
}

fn isExecFailure(err: anyerror) bool {
    return switch (err) {
        error.BufferTooSmall,
        error.UnexpectedEof,
        error.StackUnderflow,
        error.StackOverflow,
        error.InvalidOpcode,
        error.InvalidStorageIndex,
        error.InvalidCvtIndex,
        error.InvalidPoint,
        error.InvalidZone,
        error.InvalidJump,
        error.MissingZones,
        error.UnsupportedVector,
        error.MissingFunctions,
        error.TooManyFunctions,
        error.UnknownFunction,
        error.CallDepthExceeded,
        error.InvalidFunctionDefinition,
        error.ExecutionLimitExceeded,
        error.DivisionByZero,
        => true,
        else => false,
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

        var first_run = try context.prepareRun(testing.allocator, .{
            .shaped = &shaped,
            .ppem = tt_hint.HintPpem.uniform(12 * 64),
        });
        defer first_run.deinit();
        if (first_run.stats.fallback_count != 0) continue;
        try testing.expectEqual(@as(usize, 4), first_run.glyphs.len);
        try testing.expect(first_run.stats.advance.x > 0);

        const cached = first_run.glyphs[0].source.hint;
        for (first_run.glyphs) |glyph| try testing.expect(glyph.source.hint == cached);

        var second_run = try context.prepareRun(testing.allocator, .{
            .shaped = &shaped,
            .ppem = tt_hint.HintPpem.uniform(12 * 64),
        });
        defer second_run.deinit();
        try testing.expect(second_run.glyphs[0].source.hint == cached);
        return;
    }

    return error.SkipZigTest;
}

test "snapEmAdvanceToPixels rounds each axis to the nearest pixel" {
    const ppem = tt_hint.HintPpem.uniform(16 * 64); // 16 px/em
    // 0.4 em * 16 = 6.4 px → 6 px → 0.375 em
    // 0.6 em * 16 = 9.6 px → 10 px → 0.625 em
    const snapped = snapEmAdvanceToPixels(.{ .x = 0.4, .y = 0.6 }, ppem);
    try std.testing.expectApproxEqAbs(@as(f32, 0.375), snapped.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.625), snapped.y, 1e-6);
}

test "snapEmAdvanceToPixels handles zero ppem as identity" {
    const ppem = tt_hint.HintPpem{ .x_26_6 = 0, .y_26_6 = 0 };
    const snapped = snapEmAdvanceToPixels(.{ .x = 0.42, .y = 0.13 }, ppem);
    try std.testing.expectEqual(@as(f32, 0.42), snapped.x);
    try std.testing.expectEqual(@as(f32, 0.13), snapped.y);
}

test "snapEmAdvanceToPixels keeps integer pixel advances unchanged" {
    const ppem = tt_hint.HintPpem.uniform(20 * 64); // 20 px/em
    // 0.5 em * 20 = 10 px (already integer) → stays 0.5 em
    const snapped = snapEmAdvanceToPixels(.{ .x = 0.5, .y = 1.0 }, ppem);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), snapped.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), snapped.y, 1e-6);
}

test "hint context hints emboldened faces (faux-bold)" {
    const assets = @import("assets");
    const testing = std.testing;

    // Build the same font twice: once plain, once with synthetic embolden.
    // Both should hint successfully and produce identical hint geometry —
    // the embolden offset is applied as a second draw at render time, not
    // baked into the hinted curves.
    var plain = try TextAtlas.init(testing.allocator, &.{.{ .data = assets.noto_sans_regular }});
    defer plain.deinit();
    if (try plain.ensureText(.{}, "H")) |next| {
        plain.deinit();
        plain = next;
    }

    var bold = try TextAtlas.init(testing.allocator, &.{.{
        .data = assets.noto_sans_regular,
        .synthetic = .{ .embolden = 0.5 },
    }});
    defer bold.deinit();
    if (try bold.ensureText(.{}, "H")) |next| {
        bold.deinit();
        bold = next;
    }

    var shaped_plain = try plain.shapeText(testing.allocator, .{}, "H");
    defer shaped_plain.deinit();
    var shaped_bold = try bold.shapeText(testing.allocator, .{}, "H");
    defer shaped_bold.deinit();

    var ctx_plain = TrueTypeHintContext.init(testing.allocator, &plain);
    defer ctx_plain.deinit();
    var ctx_bold = TrueTypeHintContext.init(testing.allocator, &bold);
    defer ctx_bold.deinit();

    const ppem = tt_hint.HintPpem.uniform(12 * 64);

    var run_plain = try ctx_plain.prepareRun(testing.allocator, .{ .shaped = &shaped_plain, .ppem = ppem });
    defer run_plain.deinit();
    var run_bold = try ctx_bold.prepareRun(testing.allocator, .{ .shaped = &shaped_bold, .ppem = ppem });
    defer run_bold.deinit();

    // Both runs hint successfully — the emboldened face is no longer rejected.
    try testing.expectEqual(@as(usize, 0), run_plain.stats.fallback_count);
    try testing.expectEqual(@as(usize, 0), run_bold.stats.fallback_count);

    // And both produce identical hinted advances (the embolden offset is a
    // render-time concern, not a hint-time one).
    try testing.expectApproxEqAbs(run_plain.stats.advance.x, run_bold.stats.advance.x, 1e-6);
}

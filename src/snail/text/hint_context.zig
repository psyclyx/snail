const std = @import("std");

const atlas_mod = @import("atlas.zig");
const bezier = @import("../math/bezier.zig");
const config_mod = @import("config.zig");
const hint_snapshot_mod = @import("hint_snapshot.zig");
const text_hint = @import("../render/format/text_hint.zig");
const tt_hint = @import("tt_hint.zig");
const tt_vm = @import("../font/tt_vm.zig");
const types_mod = @import("types.zig");
const vec = @import("../math/vec.zig");

const Allocator = std.mem.Allocator;
const BBox = bezier.BBox;
const FaceIndex = config_mod.FaceIndex;
const GlyphHintSnapshot = hint_snapshot_mod.GlyphHintSnapshot;
const ShapedText = types_mod.ShapedText;
const TextAtlas = atlas_mod.TextAtlas;
const Vec2 = vec.Vec2;

pub const HintGlyphKey = struct {
    face_index: FaceIndex,
    ppem_x_26_6: u32,
    ppem_y_26_6: u32,
    glyph_id: u16,

    pub const Context = struct {
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
    /// Absolute hinted control points (f16 pairs, 8 per quadratic).
    /// Consumers do not need the unhinted base outline to interpret these.
    curve_points_f16: []u16,
};

pub const HintedGlyphValue = struct {
    key: HintGlyphKey,
    advance: Vec2,
    bbox: BBox,
    attachment: ?HintedGlyphAttachment = null,

    pub fn deinit(self: *HintedGlyphValue, allocator: Allocator) void {
        if (self.attachment) |attachment| allocator.free(attachment.curve_points_f16);
        self.* = undefined;
    }

    pub fn renderable(self: *const HintedGlyphValue) bool {
        return self.attachment != null;
    }

    /// Approximate heap footprint of this glyph entry's allocations.
    /// The `HintedGlyphValue` struct itself is excluded (one per map
    /// slot; that overhead is counted at the map level).
    pub fn byteSize(self: *const HintedGlyphValue) usize {
        if (self.attachment) |attachment| return attachment.curve_points_f16.len * @sizeOf(u16);
        return 0;
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

    fn byteSize(self: *const FaceProgramState) usize {
        // Topology cache holds per-glyph parsed bytecode tables;
        // the map and its values together approximate the working set.
        return self.cache.map.count() * (@sizeOf(u16) + @sizeOf(tt_vm.GlyphTopology));
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

    fn byteSize(self: *const SizeHintState) usize {
        return self.machine.byteSize();
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
        self.clearInternal();
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

    fn clearInternal(self: *TrueTypeHintContext) void {
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

        // `getGlyph` reflects what the *current atlas snapshot* has loaded,
        // not what the font contains. A later `ensureText` may add this gid,
        // and `rebindAtlas` preserves caches across snapshot extensions —
        // so this rejection is the one reason that must not be cached, lest
        // we strand the glyph on the unhinted path after atlas growth.
        const base_info = face_view.getGlyph(key.glyph_id) orelse
            return .{ .unsupported = .missing_base_glyph };

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

        var patch = tt_hint.patchGlyphHint(self.allocator, .{
            .info = base_info,
            .page = self.atlas.pages[base_info.page_index],
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

    /// Freeze the current cache into an immutable `GlyphHintSnapshot`. The
    /// snapshot owns its own storage and slab; the context's cache is
    /// untouched and can continue to grow. Multiple snapshots taken from
    /// the same context are independent values and may be bound to
    /// different bundles.
    pub fn snapshot(
        self: *TrueTypeHintContext,
        allocator: Allocator,
        options: hint_snapshot_mod.BuilderOptions,
    ) !GlyphHintSnapshot {
        try self.validateAtlas();
        var builder = try hint_snapshot_mod.Builder.init(allocator, self.atlas, options);
        errdefer builder.deinit();
        var it = self.glyphs.valueIterator();
        while (it.next()) |entry| switch (entry.*) {
            .ready => |value| if (value.renderable())
                try builder.addRenderable(value)
            else
                try builder.addEmpty(value),
            .unsupported => {},
        };
        return builder.finish();
    }

    // ── Cache inspection and eviction ──
    //
    // The context's internal cache grows monotonically as new glyphs and
    // PPEMs are queried. Snail ships mechanism, not policy: these verbs
    // let any caller implement LRU, capacity-bound, manual, or
    // workload-scoped eviction in user code without snail second-guessing
    // them. See README §Hint Cache Lifecycle for consumer recipes.
    //
    // Invariant: cache entries are eligible for eviction at any point
    // between `prepareRun`/`computeGlyph` calls. Bundles built via
    // `bindHintContext` copy their pending points into bundle-owned
    // storage at append time, so eviction never produces dangling
    // references.

    /// Heap footprint breakdown of the context's caches.
    pub const Footprint = struct {
        face_program_count: usize = 0,
        face_program_bytes: usize = 0,
        size_state_count: usize = 0,
        size_state_bytes: usize = 0,
        glyph_value_count: usize = 0,
        glyph_value_bytes: usize = 0,

        pub fn totalBytes(self: Footprint) usize {
            return self.face_program_bytes + self.size_state_bytes + self.glyph_value_bytes;
        }
    };

    pub fn byteFootprint(self: *const TrueTypeHintContext) Footprint {
        var out: Footprint = .{};
        var face_it = self.face_programs.iterator();
        while (face_it.next()) |entry| {
            out.face_program_count += 1;
            out.face_program_bytes += entry.value_ptr.byteSize();
        }
        var size_it = self.size_states.iterator();
        while (size_it.next()) |entry| {
            out.size_state_count += 1;
            out.size_state_bytes += entry.value_ptr.byteSize();
        }
        var glyph_it = self.glyphs.valueIterator();
        while (glyph_it.next()) |entry| {
            out.glyph_value_count += 1;
            switch (entry.*) {
                .ready => |value| out.glyph_value_bytes += value.byteSize(),
                .unsupported => {},
            }
        }
        return out;
    }

    pub const SizeKeyEntry = struct {
        face_index: FaceIndex,
        ppem: tt_hint.HintPpem,
        byte_size: usize,
    };

    pub const SizeKeyIterator = struct {
        inner: SizeStateMap.Iterator,

        pub fn next(self: *SizeKeyIterator) ?SizeKeyEntry {
            const entry = self.inner.next() orelse return null;
            return .{
                .face_index = entry.key_ptr.face_index,
                .ppem = .{ .x_26_6 = entry.key_ptr.ppem_x_26_6, .y_26_6 = entry.key_ptr.ppem_y_26_6 },
                .byte_size = entry.value_ptr.byteSize(),
            };
        }
    };

    /// Iterate every cached size state. Safe to inspect during iteration;
    /// callers that want to evict during the walk should collect victim
    /// keys first and pass them to `evictSize` after.
    pub fn sizeKeyIterator(self: *const TrueTypeHintContext) SizeKeyIterator {
        return .{ .inner = self.size_states.iterator() };
    }

    pub const GlyphKeyEntry = struct {
        key: HintGlyphKey,
        byte_size: usize,
        renderable: bool,
    };

    pub const GlyphKeyIterator = struct {
        inner: GlyphMap.Iterator,

        pub fn next(self: *GlyphKeyIterator) ?GlyphKeyEntry {
            const entry = self.inner.next() orelse return null;
            const renderable = switch (entry.value_ptr.*) {
                .ready => |v| v.renderable(),
                .unsupported => false,
            };
            const bytes = switch (entry.value_ptr.*) {
                .ready => |v| v.byteSize(),
                .unsupported => 0,
            };
            return .{
                .key = entry.key_ptr.*,
                .byte_size = bytes,
                .renderable = renderable,
            };
        }
    };

    pub fn glyphKeyIterator(self: *const TrueTypeHintContext) GlyphKeyIterator {
        return .{ .inner = self.glyphs.iterator() };
    }

    /// Evict the size state for `(face_index, ppem)` and every cached
    /// glyph value at that PPEM/face. No-op if the size state is absent.
    /// Subsequent queries at this PPEM rebuild the VM on demand (the
    /// expensive setup runs again).
    pub fn evictSize(
        self: *TrueTypeHintContext,
        face_index: FaceIndex,
        ppem: tt_hint.HintPpem,
    ) void {
        const size_key = SizeKey{
            .face_index = face_index,
            .ppem_x_26_6 = ppem.x_26_6,
            .ppem_y_26_6 = ppem.y_26_6,
        };
        evictGlyphsMatching(self, .{ .face_index = face_index, .ppem = ppem });
        if (self.size_states.fetchRemove(size_key)) |kv| {
            var state = kv.value;
            state.deinit();
        }
    }

    /// Evict every cached size state and glyph value at this PPEM across
    /// all faces. Useful for "drop everything for the zoom level I just
    /// left" policies.
    pub fn evictPpem(self: *TrueTypeHintContext, ppem: tt_hint.HintPpem) void {
        var face_it = self.face_programs.keyIterator();
        var face_buf: [16]FaceIndex = undefined;
        var face_count: usize = 0;
        while (face_it.next()) |key_ptr| : (face_count += 1) {
            if (face_count >= face_buf.len) break;
            face_buf[face_count] = key_ptr.*;
        }
        for (face_buf[0..face_count]) |face| self.evictSize(face, ppem);
    }

    /// Drop every cached glyph value but keep size states (and therefore
    /// the warm TT VMs) intact. Optimised for the "zoom-scrubbing"
    /// pattern where outline values churn but the VMs are reused
    /// frame-to-frame.
    pub fn clearGlyphs(self: *TrueTypeHintContext) void {
        var values = self.glyphs.valueIterator();
        while (values.next()) |entry| {
            switch (entry.*) {
                .ready => |value| {
                    value.deinit(self.allocator);
                    self.allocator.destroy(value);
                },
                .unsupported => {},
            }
        }
        self.glyphs.clearRetainingCapacity();
    }

    /// Drop every cached glyph value, size state, and face program.
    /// Equivalent to a fresh `init` on the same allocator/atlas; any
    /// subsequent query rebuilds from scratch.
    pub fn clear(self: *TrueTypeHintContext) void {
        self.clearInternal();
    }
};

const EvictMatch = struct {
    face_index: config_mod.FaceIndex,
    ppem: tt_hint.HintPpem,
};

fn evictGlyphsMatching(self: *TrueTypeHintContext, match: EvictMatch) void {
    // Collect victim keys first; mutating the map while iterating is
    // not safe in Zig's std HashMap.
    var victims = std.ArrayListUnmanaged(HintGlyphKey).empty;
    defer victims.deinit(self.allocator);
    var it = self.glyphs.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (key.face_index != match.face_index) continue;
        if (key.ppem_x_26_6 != match.ppem.x_26_6 or key.ppem_y_26_6 != match.ppem.y_26_6) continue;
        victims.append(self.allocator, key) catch return;
    }
    for (victims.items) |key| {
        if (self.glyphs.fetchRemove(key)) |kv| {
            switch (kv.value) {
                .ready => |value| {
                    value.deinit(self.allocator);
                    self.allocator.destroy(value);
                },
                .unsupported => {},
            }
        }
    }
}

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
    const points = patch.curve_points_f16;
    patch.curve_points_f16 = &.{};
    defer patch.deinit();
    defer hint.deinit();

    return .{
        .key = key,
        .advance = hint.advance,
        .bbox = hint.bbox,
        .attachment = .{
            .record = patch.record,
            .curve_points_f16 = points,
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

test "hint cache eviction verbs preserve invariants" {
    const assets = @import("assets");
    const testing = std.testing;

    var atlas = try TextAtlas.init(testing.allocator, &.{.{ .data = assets.noto_sans_regular }});
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, "AB")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var ctx = TrueTypeHintContext.init(testing.allocator, &atlas);
    defer ctx.deinit();

    var shaped = try atlas.shapeText(testing.allocator, .{}, "AB");
    defer shaped.deinit();

    const ppem_a = tt_hint.HintPpem.uniform(12 * 64);
    const ppem_b = tt_hint.HintPpem.uniform(16 * 64);

    var run_a = try ctx.prepareRun(testing.allocator, .{ .shaped = &shaped, .ppem = ppem_a });
    defer run_a.deinit();
    var run_b = try ctx.prepareRun(testing.allocator, .{ .shaped = &shaped, .ppem = ppem_b });
    defer run_b.deinit();
    if (run_a.stats.hinted_count == 0 or run_b.stats.hinted_count == 0) return error.SkipZigTest;

    const footprint_full = ctx.byteFootprint();
    try testing.expect(footprint_full.size_state_count >= 2);
    try testing.expect(footprint_full.glyph_value_count >= 2);
    try testing.expect(footprint_full.totalBytes() > 0);

    // clearGlyphs drops outlines but keeps VM state warm.
    ctx.clearGlyphs();
    const footprint_after_glyphs = ctx.byteFootprint();
    try testing.expectEqual(@as(usize, 0), footprint_after_glyphs.glyph_value_count);
    try testing.expect(footprint_after_glyphs.size_state_count >= 2);

    // Re-prepare to repopulate glyphs; size state is reused.
    var run_a2 = try ctx.prepareRun(testing.allocator, .{ .shaped = &shaped, .ppem = ppem_a });
    defer run_a2.deinit();
    try testing.expect(ctx.byteFootprint().glyph_value_count >= 2);

    // evictSize(ppem_a) drops the ppem_a VM and any glyphs at that PPEM.
    ctx.evictSize(0, ppem_a);
    var glyph_it = ctx.glyphKeyIterator();
    while (glyph_it.next()) |entry| {
        try testing.expect(entry.key.ppem_x_26_6 != ppem_a.x_26_6 or entry.key.face_index != 0);
    }
    var size_it = ctx.sizeKeyIterator();
    while (size_it.next()) |entry| {
        try testing.expect(entry.ppem.x_26_6 != ppem_a.x_26_6 or entry.face_index != 0);
    }

    // clear() empties everything.
    ctx.clear();
    const empty = ctx.byteFootprint();
    try testing.expectEqual(@as(usize, 0), empty.totalBytes());
}

test "default snapshot key is stable across rebuilds for same atlas" {
    // Regression: each `bindHintContext` rebuild used to mint a unique
    // resource key (snapshot identity was folded in), so the upload
    // pipeline accumulated GPU buffers per zoom level until VRAM was
    // exhausted. Default key must depend only on the atlas's snapshot
    // identity so repeated rebuilds replace rather than accumulate.
    const assets = @import("assets");
    const testing = std.testing;

    var atlas = try TextAtlas.init(testing.allocator, &.{.{ .data = assets.noto_sans_regular }});
    defer atlas.deinit();

    var ctx = TrueTypeHintContext.init(testing.allocator, &atlas);
    defer ctx.deinit();

    var snap_a = try ctx.snapshot(testing.allocator, .{});
    defer snap_a.deinit();
    var snap_b = try ctx.snapshot(testing.allocator, .{});
    defer snap_b.deinit();

    try testing.expect(snap_a.key.eql(snap_b.key));
    // Identities still differ — that's what enables idempotent
    // `bindHintSnapshot` to detect a genuinely different snapshot.
    try testing.expect(snap_a.snapshot_identity != snap_b.snapshot_identity);
}

test "bundle copies hint points so eviction does not dangle" {
    const assets = @import("assets");
    const testing = std.testing;
    const blob_mod = @import("blob.zig");

    var atlas = try TextAtlas.init(testing.allocator, &.{.{ .data = assets.noto_sans_regular }});
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, "AB")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var ctx = TrueTypeHintContext.init(testing.allocator, &atlas);
    defer ctx.deinit();

    var shaped = try atlas.shapeText(testing.allocator, .{}, "AB");
    defer shaped.deinit();
    var run = try ctx.prepareRun(testing.allocator, .{
        .shaped = &shaped,
        .ppem = tt_hint.HintPpem.uniform(12 * 64),
    });
    defer run.deinit();
    if (run.stats.hinted_count == 0) return error.SkipZigTest;

    var bundle = blob_mod.TextBlobBundle.init(testing.allocator, &atlas);
    defer bundle.deinit();
    try bundle.bindHintContext(&ctx);

    var bip = try bundle.startBlob();
    errdefer bip.abort();
    _ = try bip.append(.{
        .source = .{ .hinted = run.glyphs },
        .placement = .{ .baseline = .{ .x = 0, .y = 12 }, .em = 12 },
        .fill = .{ .solid = .{ 1, 1, 1, 1 } },
    });
    _ = try bip.finish(@import("../resource_key.zig").ResourceKey.named("dangling_test"));
    try bundle.materialiseHintSnapshot();

    // Evict from the hint context. If the bundle had borrowed slices,
    // this would dangle. With the copy-on-append fix, the bundle's
    // owned snapshot is still valid.
    ctx.clearGlyphs();
    const snap = bundle.hintSnapshotResolved().?;
    try testing.expect(snap.hasRenderable());
    try testing.expect(snap.layer_info_data != null);
}

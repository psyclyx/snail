const std = @import("std");

const atlas_mod = @import("atlas.zig");
const bezier = @import("../math/bezier.zig");
const hint_context_mod = @import("hint_context.zig");
const resource_key_mod = @import("../resource_key.zig");
const text_hint = @import("../render/format/text_hint.zig");
const vec = @import("../math/vec.zig");

const Allocator = std.mem.Allocator;
const BBox = bezier.BBox;
const HintGlyphKey = hint_context_mod.HintGlyphKey;
const HintedGlyphValue = hint_context_mod.HintedGlyphValue;
const ResourceKey = resource_key_mod.ResourceKey;
const TextAtlas = atlas_mod.TextAtlas;
const Vec2 = vec.Vec2;

/// Per-(atlas, hint-context, PPEM) immutable snapshot of hinted glyph
/// outlines. Holds absolute control points pre-packed for GPU upload, plus
/// the lookup table the renderer needs to resolve a hinted glyph reference
/// to its position in the slab.
///
/// Snapshots are the value-typed counterpart to `TextAtlas`: the atlas is
/// the PPEM-independent geometry; the snapshot is the PPEM-specific
/// hinted geometry. A bundle binds one snapshot via `bindHintSnapshot`;
/// many bundles can share the same snapshot.
pub const GlyphHintSnapshot = struct {
    allocator: Allocator,

    /// Atlas the snapshot was built against. Validated on bind so the
    /// renderer cannot pair a snapshot with a different atlas snapshot.
    atlas: *const TextAtlas,
    atlas_identity: u64,
    /// Unique per snapshot instance — drives manifest dedup and the
    /// hint resource key.
    snapshot_identity: u64,
    /// Resource key the manifest entry uses. Defaults to
    /// `derived(atlas_key, "glyph_hint_snapshot")` mixed with the snapshot
    /// identity; callers can override at construction time.
    key: ResourceKey,

    entries: EntryMap,
    /// Packed layer-info slab the renderer uploads. Each entry's
    /// `record_texel_offset` indexes into this buffer in texel units.
    layer_info_data: ?[]f32 = null,
    layer_info_width: u32 = 0,
    layer_info_height: u32 = 0,

    pub const Entry = struct {
        advance: Vec2,
        bbox: BBox,
        /// First texel of this entry's record within `layer_info_data`.
        /// `null` for empty hints (skip-target glyphs that hint to an
        /// empty outline — recorded so callers can distinguish "absent"
        /// from "present but renders nothing").
        record_texel_offset: ?u32,
    };

    pub const EntryMap = std.HashMap(HintGlyphKey, Entry, HintGlyphKey.Context, 80);

    pub fn deinit(self: *GlyphHintSnapshot) void {
        if (self.layer_info_data) |data| self.allocator.free(data);
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn identity(self: *const GlyphHintSnapshot) u64 {
        return self.snapshot_identity;
    }

    pub fn atlasIdentity(self: *const GlyphHintSnapshot) u64 {
        return self.atlas_identity;
    }

    pub fn validateAtlas(self: *const GlyphHintSnapshot, atlas: *const TextAtlas) !void {
        if (self.atlas != atlas) return error.WrongTextAtlasSnapshot;
        if (atlas.snapshotIdentity() != self.atlas_identity) return error.WrongTextAtlasSnapshot;
    }

    /// Resolve a glyph reference to its texel offset within the
    /// pre-packed slab. Returns `null` for entries the snapshot was built
    /// without (caller is expected to fall back).
    pub fn lookup(self: *const GlyphHintSnapshot, key: HintGlyphKey) ?*const Entry {
        return self.entries.getPtr(key);
    }

    /// True if any entry contributes renderable geometry. Empty snapshots
    /// produce no upload and don't need a manifest binding.
    pub fn hasRenderable(self: *const GlyphHintSnapshot) bool {
        return self.layer_info_data != null;
    }

    pub fn layerInfoUpload(self: *const GlyphHintSnapshot) view_mod.PreparedHintLayerInfoUpload {
        return .{
            .data = self.layer_info_data,
            .width = self.layer_info_width,
            .height = self.layer_info_height,
        };
    }
};

const view_mod = @import("../resources/view.zig");

// Snapshot-building helpers used by `TrueTypeHintContext.snapshot`. The
// builder is split out from the type itself so the type stays a pure
// value with no construction policy embedded.

pub const BuilderOptions = struct {
    /// Optional resource key for the manifest entry. If `null`, a key
    /// is derived from the atlas key and the snapshot identity.
    key: ?ResourceKey = null,
};

pub const Builder = struct {
    allocator: Allocator,
    atlas: *const TextAtlas,
    atlas_identity: u64,
    snapshot_identity: u64,
    key: ResourceKey,
    entries: GlyphHintSnapshot.EntryMap,
    layer_info_texels: u32 = 0,
    pending: std.ArrayListUnmanaged(Pending) = .empty,

    const Pending = struct {
        key: HintGlyphKey,
        record: text_hint.GlyphRecord,
        points_f16: []const u16,
        texel_offset: u32,
        advance: Vec2,
        bbox: BBox,
    };

    pub fn init(allocator: Allocator, atlas: *const TextAtlas, options: BuilderOptions) !Builder {
        return initWithCursor(allocator, atlas, options, 0);
    }

    /// Same as `init`, but the slab cursor starts at `initial_texel_cursor`
    /// rather than zero. Used by `TextBlobBundle`'s auto mode to repack an
    /// owned snapshot whose pending entries were assigned texel offsets at
    /// append time — the repacked slab must allocate at least as many
    /// texels as the cursor records to keep those offsets valid.
    pub fn initWithCursor(
        allocator: Allocator,
        atlas: *const TextAtlas,
        options: BuilderOptions,
        initial_texel_cursor: u32,
    ) !Builder {
        const identity = nextSnapshotIdentity();
        const key = options.key orelse defaultKey(atlas);
        return .{
            .allocator = allocator,
            .atlas = atlas,
            .atlas_identity = atlas.snapshotIdentity(),
            .snapshot_identity = identity,
            .key = key,
            .entries = GlyphHintSnapshot.EntryMap.init(allocator),
            .layer_info_texels = initial_texel_cursor,
        };
    }

    pub fn deinit(self: *Builder) void {
        self.pending.deinit(self.allocator);
        self.entries.deinit();
        self.* = undefined;
    }

    /// Reserve a slot for an empty hint (no renderable curves).
    pub fn addEmpty(self: *Builder, value: *const HintedGlyphValue) !void {
        try self.entries.put(value.key, .{
            .advance = value.advance,
            .bbox = value.bbox,
            .record_texel_offset = null,
        });
    }

    /// Reserve and bookkeep a slot for a renderable hint. The record's
    /// texel layout is computed eagerly; the data is written into the
    /// slab during `finish()`.
    pub fn addRenderable(self: *Builder, value: *const HintedGlyphValue) !void {
        const attachment = value.attachment orelse return self.addEmpty(value);
        const texel_offset = self.layer_info_texels;
        const texel_count = text_hint.recordTexelCount(attachment.record.curve_count);
        try self.pending.append(self.allocator, .{
            .key = value.key,
            .record = attachment.record,
            .points_f16 = attachment.curve_points_f16,
            .texel_offset = texel_offset,
            .advance = value.advance,
            .bbox = value.bbox,
        });
        self.layer_info_texels += texel_count;
        try self.entries.put(value.key, .{
            .advance = value.advance,
            .bbox = value.bbox,
            .record_texel_offset = texel_offset,
        });
    }

    /// Insert a pre-positioned entry. Used by the bundle's auto mode
    /// to repack a snapshot from a pending list where texel offsets
    /// were assigned at append time and must remain stable across
    /// repacks. The slab must already be sized via `initWithCursor` to
    /// cover all offsets the caller intends to insert.
    pub fn addAtOffset(
        self: *Builder,
        key: HintGlyphKey,
        advance: Vec2,
        bbox: bezier.BBox,
        record: text_hint.GlyphRecord,
        points_f16: []const u16,
        texel_offset: u32,
    ) !void {
        try self.pending.append(self.allocator, .{
            .key = key,
            .record = record,
            .points_f16 = points_f16,
            .texel_offset = texel_offset,
            .advance = advance,
            .bbox = bbox,
        });
        try self.entries.put(key, .{
            .advance = advance,
            .bbox = bbox,
            .record_texel_offset = texel_offset,
        });
    }

    /// Pack the queued entries into the snapshot's layer-info slab and
    /// return the immutable snapshot. The builder is consumed.
    pub fn finish(self: *Builder) !GlyphHintSnapshot {
        defer self.pending.deinit(self.allocator);

        var snapshot = GlyphHintSnapshot{
            .allocator = self.allocator,
            .atlas = self.atlas,
            .atlas_identity = self.atlas_identity,
            .snapshot_identity = self.snapshot_identity,
            .key = self.key,
            .entries = self.entries,
            .layer_info_data = null,
            .layer_info_width = 0,
            .layer_info_height = 0,
        };
        // The entry map moves into the snapshot; clear the builder slot so
        // its deinit doesn't free it twice.
        self.entries = GlyphHintSnapshot.EntryMap.init(self.allocator);
        errdefer snapshot.deinit();

        if (self.layer_info_texels == 0) return snapshot;

        const width = text_hint.infoWidth(self.layer_info_texels);
        const height = @max(@as(u32, 1), (self.layer_info_texels + width - 1) / width);
        const data = try self.allocator.alloc(f32, @as(usize, width) * @as(usize, height) * 4);
        errdefer self.allocator.free(data);
        @memset(data, 0);

        for (self.pending.items) |entry| {
            try text_hint.writeGlyphRecord(data, width, entry.texel_offset, entry.record, entry.points_f16);
        }

        snapshot.layer_info_data = data;
        snapshot.layer_info_width = width;
        snapshot.layer_info_height = height;
        return snapshot;
    }
};

var snapshot_serial: std.atomic.Value(u64) = .init(1);

fn nextSnapshotIdentity() u64 {
    return snapshot_serial.fetchAdd(1, .monotonic);
}

/// Default manifest key for a snapshot built without an explicit
/// `BuilderOptions.key`. Stable per-atlas (the snapshot's own identity
/// is deliberately NOT folded in): rebuilding a snapshot for the same
/// atlas — e.g. after `bundle.reset()` and a fresh `bindHintContext`
/// across a zoom level — produces the same key so the upload pipeline
/// replaces the previous payload instead of accumulating GPU buffers.
/// Callers that need to hold multiple distinct snapshots for the same
/// atlas concurrently (e.g. different `cvt_headroom` or different hint
/// contexts) must supply explicit keys via `BuilderOptions.key`.
fn defaultKey(atlas: *const TextAtlas) ResourceKey {
    return resource_key_mod.derived(ResourceKey.fromOpaque(atlas.snapshotIdentity()), "glyph_hint_snapshot");
}

const std = @import("std");

const atlas_curve_mod = @import("render/format/atlas/curve.zig");
const footprint_types = @import("resources/footprint_types.zig");
const image_mod = @import("image.zig");
const prepared_mod = @import("resources/prepared.zig");
const render_mod = @import("render.zig");
const resource_key_mod = @import("resource_key.zig");
const manifest_mod = @import("resources/manifest.zig");
const stamp_mod = @import("resources/stamp.zig");
const text_mod = @import("text.zig");
const upload_common = @import("render/format/upload_common.zig");
const view_mod = @import("resources/view.zig");

const Atlas = atlas_curve_mod.Atlas;
const Image = image_mod.Image;
const PreparedAtlasView = view_mod.PreparedAtlasView;
const PreparedImageView = view_mod.PreparedImageView;
const PreparedLayerInfoUpload = view_mod.PreparedLayerInfoUpload;
const PreparedLayerInfoView = view_mod.PreparedLayerInfoView;
const PreparedResources = prepared_mod.PreparedResources;
const Renderer = render_mod.Renderer;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceManifest = manifest_mod.ResourceManifest;
const ResourceStamp = resource_key_mod.ResourceStamp;
const TextAtlas = text_mod.TextAtlas;

pub const ResourceFootprint = footprint_types.ResourceFootprint;

pub const ResourceCacheStats = struct {
    generation: u64 = 0,
    active_atlas_pages_resident: u32 = 0,
    active_atlas_layers_allocated: u32 = 0,
    atlas_pages_resident: u32 = 0,
    atlas_layers_allocated: u32 = 0,
    active_image_layers_resident: u32 = 0,
    active_image_layers_allocated: u32 = 0,
    image_layers_resident: u32 = 0,
    image_layers_allocated: u32 = 0,
};

pub const UploadAllocators = struct {
    persistent: std.mem.Allocator,
    scratch: std.mem.Allocator,
};

pub const ResourceUploadBatch = struct {
    atlases: []const *const Atlas,
    atlas_capacity_modes: []const upload_common.AtlasCapacityMode,
    atlas_views: []PreparedAtlasView,
    layer_infos: []const PreparedLayerInfoUpload,
    layer_info_views: []PreparedLayerInfoView,
    images: []const *const Image,
    image_views: []PreparedImageView,
};

pub const ResourceManifestSnapshot = struct {
    allocator: std.mem.Allocator,
    entries: []ResourceManifest.Entry,

    pub fn init(allocator: std.mem.Allocator, manifest: *const ResourceManifest) !ResourceManifestSnapshot {
        return initEntries(allocator, manifest.slice());
    }

    pub fn initEntries(allocator: std.mem.Allocator, entries: []const ResourceManifest.Entry) !ResourceManifestSnapshot {
        return .{
            .allocator = allocator,
            .entries = try allocator.dupe(ResourceManifest.Entry, entries),
        };
    }

    pub fn clone(self: *const ResourceManifestSnapshot, allocator: std.mem.Allocator) !ResourceManifestSnapshot {
        return initEntries(allocator, self.entries);
    }

    pub fn deinit(self: *ResourceManifestSnapshot) void {
        self.allocator.free(self.entries);
        self.* = undefined;
    }
};

pub const ResourceManifestDiff = struct {
    allocator: std.mem.Allocator,
    changed_keys: []ResourceKey,
    changed_len: usize = 0,
    changed_bytes: usize = 0,

    pub fn initCapacity(allocator: std.mem.Allocator, capacity: usize) !ResourceManifestDiff {
        return .{
            .allocator = allocator,
            .changed_keys = try allocator.alloc(ResourceKey, capacity),
        };
    }

    pub fn clone(self: *const ResourceManifestDiff, allocator: std.mem.Allocator) !ResourceManifestDiff {
        var out = try initCapacity(allocator, self.changed_keys.len);
        errdefer out.deinit();
        @memcpy(out.changed_keys[0..self.changed_len], self.keys());
        out.changed_len = self.changed_len;
        out.changed_bytes = self.changed_bytes;
        return out;
    }

    pub fn deinit(self: *ResourceManifestDiff) void {
        self.allocator.free(self.changed_keys);
        self.* = undefined;
    }

    pub fn keys(self: *const ResourceManifestDiff) []const ResourceKey {
        return self.changed_keys[0..self.changed_len];
    }

    pub fn add(self: *ResourceManifestDiff, key: ResourceKey, bytes: usize) !void {
        if (self.changed_len >= self.changed_keys.len) return error.ResourceUploadPlanFull;
        self.changed_keys[self.changed_len] = key;
        self.changed_len += 1;
        self.changed_bytes += bytes;
    }
};

pub const ResourceCachePlan = struct {
    reused_atlas_pages: u32 = 0,
    missing_atlas_pages: u32 = 0,
    new_atlas_banks: u32 = 0,
    reused_images: u32 = 0,
    missing_images: u32 = 0,
    new_image_banks: u32 = 0,
    atlas_rebuilds: u32 = 0,
    image_rebuilds: u32 = 0,

    pub fn rebuilds(self: ResourceCachePlan) u32 {
        return self.atlas_rebuilds + self.image_rebuilds;
    }

    pub fn requiresRebuild(self: ResourceCachePlan) bool {
        return self.rebuilds() != 0;
    }
};

pub const ResourceUploadEstimate = struct {
    /// Bytes this backend path will upload or construct for the next prepared
    /// resource manifest. Backend packing may make this larger than the diff.
    bytes: usize = 0,
    curve_bytes: usize = 0,
    band_bytes: usize = 0,
    layer_info_bytes: usize = 0,
    image_bytes: usize = 0,
};

pub const ResourceUploadPlan = struct {
    manifest: ResourceManifestSnapshot,
    /// Backend allocation footprint for the next prepared resource manifest.
    footprint: ResourceFootprint = .{},
    /// Logical differences between the current prepared resources and manifest.
    diff: ResourceManifestDiff,
    /// Backend cache admission and rebuild requirements.
    cache: ResourceCachePlan = .{},
    /// Executable upload/construct byte counts for this backend path.
    upload: ResourceUploadEstimate = .{},

    pub fn init(allocator: std.mem.Allocator, set: *const ResourceManifest) !ResourceUploadPlan {
        var snapshot = try ResourceManifestSnapshot.init(allocator, set);
        errdefer snapshot.deinit();
        const diff = try ResourceManifestDiff.initCapacity(allocator, snapshot.entries.len);
        return .{
            .manifest = snapshot,
            .diff = diff,
        };
    }

    pub fn clone(self: *const ResourceUploadPlan, allocator: std.mem.Allocator) !ResourceUploadPlan {
        var snapshot = try self.manifest.clone(allocator);
        errdefer snapshot.deinit();
        var diff = try self.diff.clone(allocator);
        errdefer diff.deinit();
        return .{
            .manifest = snapshot,
            .footprint = self.footprint,
            .diff = diff,
            .cache = self.cache,
            .upload = self.upload,
        };
    }

    pub fn deinit(self: *ResourceUploadPlan) void {
        self.manifest.deinit();
        self.diff.deinit();
        self.* = undefined;
    }
};

const UploadEntryCounts = struct {
    atlases: usize = 0,
    layer_infos: usize = 0,
    images: usize = 0,
};

const ResourceUploadScratch = struct {
    upload_atlases: []*const Atlas,
    atlas_capacity_modes: []upload_common.AtlasCapacityMode,
    atlas_views: []PreparedAtlasView,
    text_wrappers: []Atlas,
    text_wrapper_sources: []?*const TextAtlas,
    upload_layer_infos: []PreparedLayerInfoUpload,
    layer_info_views: []PreparedLayerInfoView,
    upload_images: []*const Image,
    image_views: []PreparedImageView,

    fn init(allocator: std.mem.Allocator, counts: UploadEntryCounts) !ResourceUploadScratch {
        const upload_atlases = try allocator.alloc(*const Atlas, counts.atlases);
        errdefer allocator.free(upload_atlases);
        const atlas_capacity_modes = try allocator.alloc(upload_common.AtlasCapacityMode, counts.atlases);
        errdefer allocator.free(atlas_capacity_modes);
        const atlas_views = try allocator.alloc(PreparedAtlasView, counts.atlases);
        errdefer allocator.free(atlas_views);
        const text_wrappers = try allocator.alloc(Atlas, counts.atlases);
        errdefer allocator.free(text_wrappers);
        const text_wrapper_sources = try allocator.alloc(?*const TextAtlas, counts.atlases);
        errdefer allocator.free(text_wrapper_sources);
        @memset(text_wrapper_sources, null);

        const upload_layer_infos = try allocator.alloc(PreparedLayerInfoUpload, counts.layer_infos);
        errdefer allocator.free(upload_layer_infos);
        const layer_info_views = try allocator.alloc(PreparedLayerInfoView, counts.layer_infos);
        errdefer allocator.free(layer_info_views);

        const upload_images = try allocator.alloc(*const Image, counts.images);
        errdefer allocator.free(upload_images);
        const image_views = try allocator.alloc(PreparedImageView, counts.images);

        return .{
            .upload_atlases = upload_atlases,
            .atlas_capacity_modes = atlas_capacity_modes,
            .atlas_views = atlas_views,
            .text_wrappers = text_wrappers,
            .text_wrapper_sources = text_wrapper_sources,
            .upload_layer_infos = upload_layer_infos,
            .layer_info_views = layer_info_views,
            .upload_images = upload_images,
            .image_views = image_views,
        };
    }

    fn deinit(self: *ResourceUploadScratch, allocator: std.mem.Allocator) void {
        for (self.text_wrapper_sources, 0..) |source, i| {
            if (source) |text_atlas| text_atlas.deinitUploadAtlas(&self.text_wrappers[i]);
        }
        allocator.free(self.upload_atlases);
        allocator.free(self.atlas_capacity_modes);
        allocator.free(self.atlas_views);
        allocator.free(self.text_wrappers);
        allocator.free(self.text_wrapper_sources);
        allocator.free(self.upload_layer_infos);
        allocator.free(self.layer_info_views);
        allocator.free(self.upload_images);
        allocator.free(self.image_views);
    }

    fn batch(self: *ResourceUploadScratch) ResourceUploadBatch {
        return .{
            .atlases = self.upload_atlases,
            .atlas_capacity_modes = self.atlas_capacity_modes,
            .atlas_views = self.atlas_views,
            .layer_infos = self.upload_layer_infos,
            .layer_info_views = self.layer_info_views,
            .images = self.upload_images,
            .image_views = self.image_views,
        };
    }
};

fn countUploadEntries(entries: []const ResourceManifest.Entry) UploadEntryCounts {
    var counts: UploadEntryCounts = .{};
    for (entries) |entry| switch (entry) {
        .text_atlas, .path_picture => counts.atlases += 1,
        .text_paint => counts.layer_infos += 1,
        .image => counts.images += 1,
    };
    return counts;
}

fn initPreparedResourceSlots(allocator: std.mem.Allocator, counts: UploadEntryCounts) !PreparedResources {
    const atlases = try allocator.alloc(PreparedResources.PreparedAtlasResource, counts.atlases);
    errdefer allocator.free(atlases);
    const layer_infos = try allocator.alloc(PreparedResources.PreparedLayerInfoResource, counts.layer_infos);
    errdefer allocator.free(layer_infos);
    const images = try allocator.alloc(PreparedResources.PreparedImageResource, counts.images);
    @memset(atlases, .{});
    @memset(layer_infos, .{});
    @memset(images, .{});

    return .{
        .allocator = allocator,
        .atlases = atlases,
        .layer_infos = layer_infos,
        .images = images,
    };
}

fn atlasPageFingerprints(allocator: std.mem.Allocator, atlas: *const Atlas) ![]upload_common.PageFingerprint {
    const fingerprints = try allocator.alloc(upload_common.PageFingerprint, atlas.pageCount());
    errdefer allocator.free(fingerprints);
    for (fingerprints, 0..) |*fingerprint, i| {
        fingerprint.* = upload_common.atlasPageFingerprint(atlas, i);
    }
    return fingerprints;
}

fn uploadTextAtlas(scratch: *ResourceUploadScratch, index: usize, text_atlas: *const TextAtlas) *const Atlas {
    scratch.text_wrappers[index] = text_atlas.uploadAtlas();
    scratch.text_wrapper_sources[index] = text_atlas;
    return &scratch.text_wrappers[index];
}

fn prepareTextAtlasEntry(
    allocator: std.mem.Allocator,
    prepared: *PreparedResources,
    scratch: *ResourceUploadScratch,
    index: usize,
    text: ResourceManifest.TextAtlasEntry,
    stamp: ResourceStamp,
) !void {
    const atlas = uploadTextAtlas(scratch, index, text.atlas);
    prepared.atlases[index] = .{
        .key = text.key,
        .kind = .text,
        .page_fingerprints = try atlasPageFingerprints(allocator, atlas),
        .stamp = stamp,
    };
    scratch.upload_atlases[index] = atlas;
    scratch.atlas_capacity_modes[index] = text.atlas_capacity;
}

fn prepareTextPaintEntry(
    prepared: *PreparedResources,
    scratch: *ResourceUploadScratch,
    index: usize,
    text: ResourceManifest.TextPaintEntry,
    stamp: ResourceStamp,
) void {
    prepared.layer_infos[index] = .{
        .key = text.key,
        .stamp = stamp,
    };
    scratch.upload_layer_infos[index] = stamp_mod.textPaintLayerInfoUpload(text.blob);
}

fn preparePathPictureEntry(
    allocator: std.mem.Allocator,
    prepared: *PreparedResources,
    scratch: *ResourceUploadScratch,
    index: usize,
    path: ResourceManifest.PathPictureEntry,
    stamp: ResourceStamp,
) !void {
    prepared.atlases[index] = .{
        .key = path.key,
        .kind = .path,
        .page_fingerprints = try atlasPageFingerprints(allocator, &path.picture.atlas),
        .stamp = stamp,
    };
    scratch.upload_atlases[index] = &path.picture.atlas;
    scratch.atlas_capacity_modes[index] = path.atlas_capacity;
}

fn prepareImageEntry(
    prepared: *PreparedResources,
    scratch: *ResourceUploadScratch,
    index: usize,
    image: ResourceManifest.ImageEntry,
    stamp: ResourceStamp,
) void {
    prepared.images[index] = .{
        .key = image.key,
        .stamp = stamp,
    };
    scratch.upload_images[index] = image.image;
}

fn populatePreparedResourceBatch(
    allocator: std.mem.Allocator,
    prepared: *PreparedResources,
    scratch: *ResourceUploadScratch,
    entries: []const ResourceManifest.Entry,
) !void {
    var atlas_i: usize = 0;
    var layer_info_i: usize = 0;
    var image_i: usize = 0;
    for (entries) |entry| {
        const stamp = stamp_mod.resourceEntryStamp(entry);
        switch (entry) {
            .text_atlas => |text| {
                try prepareTextAtlasEntry(allocator, prepared, scratch, atlas_i, text, stamp);
                atlas_i += 1;
            },
            .text_paint => |text| {
                prepareTextPaintEntry(prepared, scratch, layer_info_i, text, stamp);
                layer_info_i += 1;
            },
            .path_picture => |path| {
                try preparePathPictureEntry(allocator, prepared, scratch, atlas_i, path, stamp);
                atlas_i += 1;
            },
            .image => |image| {
                prepareImageEntry(prepared, scratch, image_i, image, stamp);
                image_i += 1;
            },
        }
    }
}

fn attachUploadedViews(allocator: std.mem.Allocator, prepared: *PreparedResources, scratch: *ResourceUploadScratch) !void {
    for (prepared.atlases, 0..) |*entry, i| {
        entry.view = scratch.atlas_views[i];
        if (scratch.atlas_views[i].page_layers.len > 0) {
            const page_layers = try allocator.dupe(u32, scratch.atlas_views[i].page_layers);
            entry.view.page_layers = page_layers;
            entry.owns_page_layers = true;
        }
    }
    for (prepared.layer_infos, 0..) |*entry, i| entry.view = scratch.layer_info_views[i];
}

pub fn uploadPreparedResources(renderer: anytype, set: *const ResourceManifest, allocators: UploadAllocators) !PreparedResources {
    return uploadPreparedResourceEntries(renderer, set.slice(), allocators);
}

pub fn uploadPreparedResourceEntries(renderer: anytype, entries: []const ResourceManifest.Entry, allocators: UploadAllocators) !PreparedResources {
    const persistent = allocators.persistent;
    const scratch = allocators.scratch;

    const counts = countUploadEntries(entries);
    var prepared = try initPreparedResourceSlots(persistent, counts);
    errdefer prepared.deinit();

    var scratch_upload = try ResourceUploadScratch.init(scratch, counts);
    defer scratch_upload.deinit(scratch);

    try populatePreparedResourceBatch(persistent, &prepared, &scratch_upload, entries);
    try renderer.uploadResourceBatch(allocators, &prepared, scratch_upload.batch());
    try attachUploadedViews(persistent, &prepared, &scratch_upload);
    return prepared;
}

/// In-flight scheduled upload returned by `Renderer.beginResourceUpload` and
/// the typed GL/Vulkan wrappers.
///
/// Callers should construct this through `beginResourceUpload`, then call
/// `record`, `ready`, `publish`, and `deinit` as needed.
/// The erased renderer handle is copied; the underlying backend state still
/// must outlive the pending upload.
pub const PendingResourceUpload = struct {
    renderer: Renderer,
    allocators: UploadAllocators,
    plan: ResourceUploadPlan,
    prepared: ?PreparedResources = null,
    external_completion_required: bool = false,
    ready_to_publish: bool = false,

    pub const RecordOptions = struct {
        budget_bytes: usize = std.math.maxInt(usize),
        allow_cache_rebuilds: bool = true,
    };

    /// Record upload work for this plan using backend-owned synchronization.
    /// CPU and GL complete during this call. Vulkan uses the renderer's
    /// internal transfer path and waits before returning.
    pub fn record(self: *PendingResourceUpload, options: RecordOptions) !void {
        try self.recordPrepared(options, false);
    }

    /// Record upload work while a backend-specific caller-synchronized upload
    /// scope is already active. Backend adapters use this after binding the
    /// caller's command buffer or equivalent external completion mechanism.
    pub fn recordExternal(self: *PendingResourceUpload, options: RecordOptions) !void {
        try self.recordPrepared(options, true);
    }

    fn recordPrepared(self: *PendingResourceUpload, options: RecordOptions, external_completion_required: bool) !void {
        if (self.prepared != null) return;
        if (!options.allow_cache_rebuilds and self.plan.cache.requiresRebuild()) return error.ResourceCacheRebuildRequired;
        if (self.plan.upload.bytes > options.budget_bytes) return error.ResourceUploadBudgetExceeded;

        self.prepared = try uploadPreparedResourceEntries(&self.renderer, self.plan.manifest.entries, self.allocators);
        self.external_completion_required = external_completion_required;
        self.ready_to_publish = !external_completion_required;
    }

    pub fn ready(self: *PendingResourceUpload, is_ready: bool) bool {
        if (self.prepared == null) return false;
        if (!self.external_completion_required) {
            self.ready_to_publish = true;
            return true;
        }
        if (is_ready) {
            self.ready_to_publish = true;
            return true;
        }
        return false;
    }

    pub fn readyNow(self: *PendingResourceUpload) bool {
        return self.ready(true);
    }

    pub fn publish(self: *PendingResourceUpload) !PreparedResources {
        if (self.external_completion_required and !self.ready_to_publish) return error.ResourceUploadNotReady;
        if (self.prepared) |prepared| {
            self.prepared = null;
            self.external_completion_required = false;
            self.ready_to_publish = false;
            return prepared;
        }
        return error.ResourceUploadNotReady;
    }

    pub fn deinit(self: *PendingResourceUpload) void {
        if (self.prepared) |*prepared| prepared.deinit();
        self.plan.deinit();
        self.prepared = null;
        self.external_completion_required = false;
        self.ready_to_publish = false;
    }
};

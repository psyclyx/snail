const std = @import("std");

const backend_kind_mod = @import("../backend_kind.zig");
const coverage_mod = @import("../coverage.zig");
const draw_mod = @import("../draw.zig");
const prepared_mod = @import("../resources/prepared.zig");
const set_mod = @import("../resources/manifest.zig");
const upload_mod = @import("../upload.zig");
const upload_plan = @import("upload_plan.zig");

pub const BackendKind = backend_kind_mod.BackendKind;

const CoverageBackend = coverage_mod.Backend;
const DrawPass = draw_mod.DrawPass;
const DrawState = draw_mod.DrawState;
const DrawRecords = draw_mod.DrawRecords;
const PendingResourceUpload = upload_mod.PendingResourceUpload;
const PreparedResources = prepared_mod.PreparedResources;
const PreparedScene = draw_mod.PreparedScene;
const ResourceCacheStats = upload_mod.ResourceCacheStats;
const ResourceUploadBatch = upload_mod.ResourceUploadBatch;
const ResourceManifest = set_mod.ResourceManifest;
const ResourceUploadPlan = upload_mod.ResourceUploadPlan;
const UploadAllocators = upload_mod.UploadAllocators;
const uploadPreparedResources = upload_mod.uploadPreparedResources;

/// Renderer execution machinery. GPU resource residency lives in renderer-owned
/// caches; PreparedResources records validated bindings into those caches.
pub const Renderer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const ResourceCacheVTable = struct {
        uses_resource_cache: bool,
        stats: *const fn (*const anyopaque) ResourceCacheStats,
        reset: *const fn (*anyopaque) void,
        validateBackendGeneration: *const fn (*const PreparedResources) anyerror!void,
        atlasCacheStatus: *const fn (*const PreparedResources, usize, upload_plan.PagedAtlasSource) upload_plan.AtlasCacheStatus,
        canUseAtlasOverflowBanks: *const fn (*const PreparedResources, usize) bool,
        imageArrayWouldRebuild: *const fn (*const PreparedResources, u32, u32, u32) bool,
    };

    pub const UploadVTable = struct {
        uploadResources: *const fn (*anyopaque, UploadAllocators, *PreparedResources, ResourceUploadBatch) anyerror!void,
    };

    pub const CoverageVTable = struct {
        coverageBackend: *const fn (*anyopaque, *const PreparedResources) ?CoverageBackend,
    };

    pub const DrawVTable = struct {
        draw: *const fn (*Renderer, *const PreparedResources, DrawRecords, DrawState) anyerror!void,
        drawPass: *const fn (*Renderer, *const PreparedResources, DrawRecords, DrawPass) anyerror!void,
        drawText: *const fn (*anyopaque, ?*const anyopaque, []const u32, DrawState, u32) anyerror!void,
        drawPaths: *const fn (*anyopaque, ?*const anyopaque, []const u32, DrawState, u32) anyerror!void,
        beginDraw: *const fn (*anyopaque) void,
    };

    pub const VTable = struct {
        backend: BackendKind,
        deinit: *const fn (*anyopaque) void,
        upload: UploadVTable,
        coverage: CoverageVTable,
        draw: DrawVTable,
        resource_cache: ResourceCacheVTable,
        backendName: *const fn (*anyopaque) [:0]const u8,
    };

    /// Blocking upload for simple programs. GL requires the target context to
    /// be current. CPU upload builds cheap views. Vulkan does not perform an
    /// implicit device/queue idle here.
    pub fn uploadResourcesBlocking(self: *Renderer, allocators: UploadAllocators, set: *const ResourceManifest) !PreparedResources {
        var uploader = self.resourceUploader();
        return uploader.uploadResourcesBlocking(allocators, set);
    }

    pub fn uploadResourceBatch(self: *Renderer, allocators: UploadAllocators, prepared: *PreparedResources, batch: ResourceUploadBatch) !void {
        var uploader = self.resourceUploader();
        try uploader.uploadResourceBatch(allocators, prepared, batch);
    }

    pub fn coverageBackend(self: *Renderer, prepared: *const PreparedResources) ?CoverageBackend {
        return self.vtable.coverage.coverageBackend(self.ptr, prepared);
    }

    pub fn planResourceUpload(self: *Renderer, allocator: std.mem.Allocator, current: ?*const PreparedResources, next_set: *const ResourceManifest) !ResourceUploadPlan {
        var uploader = self.resourceUploader();
        return uploader.planResourceUpload(allocator, current, next_set);
    }

    pub fn beginResourceUpload(self: *Renderer, allocators: UploadAllocators, plan: *const ResourceUploadPlan) !PendingResourceUpload {
        var uploader = self.resourceUploader();
        return uploader.beginResourceUpload(allocators, plan);
    }

    pub fn resourceCacheStats(self: *const Renderer) ResourceCacheStats {
        return self.vtable.resource_cache.stats(self.ptr);
    }

    pub fn resetResourceCache(self: *Renderer) void {
        self.vtable.resource_cache.reset(self.ptr);
    }

    pub fn backend(self: *const Renderer) BackendKind {
        return self.vtable.backend;
    }

    pub fn resourceUploader(self: *Renderer) ResourceUploader {
        return .{
            .ptr = self.ptr,
            .backend_kind = self.vtable.backend,
            .upload = &self.vtable.upload,
            .resource_cache = &self.vtable.resource_cache,
            .backendNameFn = self.vtable.backendName,
        };
    }

    pub fn usesResourceCache(self: *const Renderer) bool {
        return self.vtable.resource_cache.uses_resource_cache;
    }

    pub fn atlasCacheStatus(self: *const Renderer, prepared: *const PreparedResources, atlas_index: usize, atlas: upload_plan.PagedAtlasSource) upload_plan.AtlasCacheStatus {
        return self.vtable.resource_cache.atlasCacheStatus(prepared, atlas_index, atlas);
    }

    pub fn canUseAtlasOverflowBanks(self: *const Renderer, prepared: *const PreparedResources, atlas_count: usize) bool {
        return self.vtable.resource_cache.canUseAtlasOverflowBanks(prepared, atlas_count);
    }

    pub fn imageArrayWouldRebuild(self: *const Renderer, prepared: *const PreparedResources, capacity_count: u32, capacity_width: u32, capacity_height: u32) bool {
        return self.vtable.resource_cache.imageArrayWouldRebuild(prepared, capacity_count, capacity_width, capacity_height);
    }

    /// Execute prebuilt draw records. This never discovers, uploads, allocates,
    /// or invalidates resources. The backend's vtable entry decides whether
    /// to walk records serially or fan them out across worker threads.
    pub fn draw(self: *Renderer, prepared: *const PreparedResources, records: DrawRecords, state: DrawState) !void {
        return self.vtable.draw.draw(self, prepared, records, state);
    }

    pub fn drawPrepared(self: *Renderer, prepared: *const PreparedResources, scene: *const PreparedScene, state: DrawState) !void {
        return self.draw(prepared, scene.slice(), state);
    }

    pub fn drawPass(self: *Renderer, prepared: *const PreparedResources, records: DrawRecords, pass: DrawPass) !void {
        return self.vtable.draw.drawPass(self, prepared, records, pass);
    }

    pub fn drawPreparedPass(self: *Renderer, prepared: *const PreparedResources, scene: *const PreparedScene, pass: DrawPass) !void {
        return self.drawPass(prepared, scene.slice(), pass);
    }

    /// Verify every segment's stamps still match the live prepared resources.
    /// Returns `error.StaleDrawRecords` if a resource has been re-uploaded;
    /// `error.MissingPreparedResource` if a key is gone.
    /// Vtables call this once per frame before fan-out so per-tile workers
    /// don't have to re-validate (and don't need an error path).
    fn validateBackendGeneration(self: *Renderer, prepared: *const PreparedResources) !void {
        try self.vtable.resource_cache.validateBackendGeneration(prepared);
    }

    pub fn validateRecords(self: *Renderer, prepared: *const PreparedResources, records: DrawRecords) !void {
        try self.validateBackendGeneration(prepared);
        for (records.segments) |segment| {
            const actual_stamp = prepared.stampForKey(segment.key) orelse return error.MissingPreparedResource;
            if (!actual_stamp.eql(segment.resource_stamp)) return error.StaleDrawRecords;
        }
    }

    /// Draw-level execution: set state, walk records serially dispatching each
    /// segment to the backend's `drawText` / `drawPaths`. Used by GPU adapters
    /// directly, and by the CPU adapter's serial fallback / tile workers.
    /// Caller has already invoked `validateRecords`.
    pub fn iterateRecords(self: *Renderer, records: DrawRecords, state: DrawState, backend_prepared: ?*const anyopaque) !void {
        self.beginBackendDraw();
        for (records.segments) |segment| {
            const vertices = records.words[segment.offset..][0..segment.len];
            switch (segment.kind) {
                .text => if (vertices.len > 0) try self.drawText(backend_prepared, vertices, state, segment.texture_layer_base),
                .path => if (vertices.len > 0) try self.drawPaths(backend_prepared, vertices, state, segment.texture_layer_base),
            }
        }
    }

    pub fn deinit(self: *Renderer) void {
        self.vtable.deinit(self.ptr);
    }

    fn beginBackendDraw(self: *Renderer) void {
        self.vtable.draw.beginDraw(self.ptr);
    }

    fn drawText(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, state: DrawState, texture_layer_base: u32) !void {
        try self.vtable.draw.drawText(self.ptr, backend_prepared, vertices, state, texture_layer_base);
    }

    fn drawPaths(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, state: DrawState, texture_layer_base: u32) !void {
        try self.vtable.draw.drawPaths(self.ptr, backend_prepared, vertices, state, texture_layer_base);
    }

    pub fn backendName(self: *const Renderer) [:0]const u8 {
        return self.vtable.backendName(@constCast(self.ptr));
    }
};

pub const ResourceUploader = struct {
    ptr: *anyopaque,
    backend_kind: BackendKind,
    upload: *const Renderer.UploadVTable,
    resource_cache: *const Renderer.ResourceCacheVTable,
    backendNameFn: *const fn (*anyopaque) [:0]const u8,

    pub fn uploadResourcesBlocking(self: *ResourceUploader, allocators: UploadAllocators, set: *const ResourceManifest) !PreparedResources {
        return uploadPreparedResources(self, set, allocators);
    }

    pub fn uploadResourceBatch(self: *ResourceUploader, allocators: UploadAllocators, prepared: *PreparedResources, batch: ResourceUploadBatch) !void {
        try self.upload.uploadResources(self.ptr, allocators, prepared, batch);
    }

    pub fn planResourceUpload(self: *ResourceUploader, allocator: std.mem.Allocator, current: ?*const PreparedResources, next_set: *const ResourceManifest) !ResourceUploadPlan {
        return upload_plan.planResourceUpload(self, allocator, current, next_set);
    }

    pub fn beginResourceUpload(self: *ResourceUploader, allocators: UploadAllocators, plan: *const ResourceUploadPlan) !PendingResourceUpload {
        return .{
            .uploader = self.*,
            .allocators = allocators,
            .plan = try plan.clone(allocators.persistent),
        };
    }

    pub fn resourceCacheStats(self: *const ResourceUploader) ResourceCacheStats {
        return self.resource_cache.stats(self.ptr);
    }

    pub fn resetResourceCache(self: *ResourceUploader) void {
        self.resource_cache.reset(self.ptr);
    }

    pub fn backend(self: *const ResourceUploader) BackendKind {
        return self.backend_kind;
    }

    pub fn usesResourceCache(self: *const ResourceUploader) bool {
        return self.resource_cache.uses_resource_cache;
    }

    pub fn atlasCacheStatus(self: *const ResourceUploader, prepared: *const PreparedResources, atlas_index: usize, atlas: upload_plan.PagedAtlasSource) upload_plan.AtlasCacheStatus {
        return self.resource_cache.atlasCacheStatus(prepared, atlas_index, atlas);
    }

    pub fn canUseAtlasOverflowBanks(self: *const ResourceUploader, prepared: *const PreparedResources, atlas_count: usize) bool {
        return self.resource_cache.canUseAtlasOverflowBanks(prepared, atlas_count);
    }

    pub fn imageArrayWouldRebuild(self: *const ResourceUploader, prepared: *const PreparedResources, capacity_count: u32, capacity_width: u32, capacity_height: u32) bool {
        return self.resource_cache.imageArrayWouldRebuild(prepared, capacity_count, capacity_width, capacity_height);
    }

    pub fn backendName(self: *const ResourceUploader) [:0]const u8 {
        return self.backendNameFn(@constCast(self.ptr));
    }
};

fn disabledDeinit(_: *anyopaque) void {}

fn disabledUploadResources(_: *anyopaque, _: UploadAllocators, _: *PreparedResources, _: ResourceUploadBatch) anyerror!void {
    return error.UnsupportedRenderer;
}

fn disabledCoverageBackend(_: *anyopaque, _: *const PreparedResources) ?CoverageBackend {
    return null;
}

fn disabledDraw(_: *Renderer, _: *const PreparedResources, _: DrawRecords, _: DrawState) anyerror!void {
    return error.UnsupportedRenderer;
}

fn disabledDrawPass(_: *Renderer, _: *const PreparedResources, _: DrawRecords, _: DrawPass) anyerror!void {
    return error.UnsupportedRenderer;
}

fn disabledDrawText(_: *anyopaque, _: ?*const anyopaque, _: []const u32, _: DrawState, _: u32) anyerror!void {
    return error.UnsupportedRenderer;
}

fn disabledDrawPaths(_: *anyopaque, _: ?*const anyopaque, _: []const u32, _: DrawState, _: u32) anyerror!void {
    return error.UnsupportedRenderer;
}

fn disabledBeginDraw(_: *anyopaque) void {}

fn disabledResourceCacheStats(_: *const anyopaque) ResourceCacheStats {
    return .{};
}

fn disabledResetResourceCache(_: *anyopaque) void {}

fn disabledValidateBackendGeneration(_: *const PreparedResources) anyerror!void {
    return error.UnsupportedRenderer;
}

fn disabledAtlasCacheStatus(_: *const PreparedResources, _: usize, _: upload_plan.PagedAtlasSource) upload_plan.AtlasCacheStatus {
    return .{};
}

fn disabledCanUseAtlasOverflowBanks(_: *const PreparedResources, _: usize) bool {
    return false;
}

fn disabledImageArrayWouldRebuild(_: *const PreparedResources, _: u32, _: u32, _: u32) bool {
    return false;
}

fn disabledGlBackendName(_: *anyopaque) [:0]const u8 {
    return "OpenGL (disabled)";
}

fn disabledVulkanBackendName(_: *anyopaque) [:0]const u8 {
    return "Vulkan (disabled)";
}

fn disabledCpuBackendName(_: *anyopaque) [:0]const u8 {
    return "CPU (disabled)";
}

fn disabledBackendName(comptime backend_kind: BackendKind) *const fn (*anyopaque) [:0]const u8 {
    return switch (backend_kind) {
        .gl => &disabledGlBackendName,
        .vulkan => &disabledVulkanBackendName,
        .cpu => &disabledCpuBackendName,
    };
}

pub fn disabledVTable(comptime backend_kind: BackendKind) Renderer.VTable {
    return .{
        .backend = backend_kind,
        .deinit = &disabledDeinit,
        .upload = .{
            .uploadResources = &disabledUploadResources,
        },
        .coverage = .{
            .coverageBackend = &disabledCoverageBackend,
        },
        .draw = .{
            .draw = &disabledDraw,
            .drawPass = &disabledDrawPass,
            .drawText = &disabledDrawText,
            .drawPaths = &disabledDrawPaths,
            .beginDraw = &disabledBeginDraw,
        },
        .resource_cache = .{
            .uses_resource_cache = false,
            .stats = &disabledResourceCacheStats,
            .reset = &disabledResetResourceCache,
            .validateBackendGeneration = &disabledValidateBackendGeneration,
            .atlasCacheStatus = &disabledAtlasCacheStatus,
            .canUseAtlasOverflowBanks = &disabledCanUseAtlasOverflowBanks,
            .imageArrayWouldRebuild = &disabledImageArrayWouldRebuild,
        },
        .backendName = disabledBackendName(backend_kind),
    };
}

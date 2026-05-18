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
        atlasSlotCanOverflowIntoBank: *const fn (*const PreparedResources, usize, upload_plan.AtlasRef) bool,
        atlasNeedsOverflowBank: *const fn (*const PreparedResources, usize, upload_plan.AtlasRef) bool,
        atlasWouldRebuild: *const fn (*const PreparedResources, usize, upload_plan.AtlasRef) bool,
        canUseAtlasOverflowBanks: *const fn (*const PreparedResources, usize) bool,
        imageArrayWouldRebuild: *const fn (*const PreparedResources, u32, u32, u32) bool,
    };

    pub const VTable = struct {
        backend: BackendKind,
        deinit: *const fn (*anyopaque) void,
        uploadResources: *const fn (*anyopaque, UploadAllocators, *PreparedResources, ResourceUploadBatch) anyerror!void,
        coverageBackend: *const fn (*anyopaque, *const PreparedResources) ?CoverageBackend,
        // Draw-level execution: validate, set state, walk records. Each backend
        // owns this so it can decide how to schedule the work.
        draw: *const fn (*Renderer, *const PreparedResources, DrawRecords, DrawState) anyerror!void,
        drawPass: *const fn (*Renderer, *const PreparedResources, DrawRecords, DrawPass) anyerror!void,
        // Segment-level dispatch, called from `iterateRecords`.
        drawText: *const fn (*anyopaque, ?*const anyopaque, []const u32, DrawState, u32) anyerror!void,
        drawPaths: *const fn (*anyopaque, ?*const anyopaque, []const u32, DrawState, u32) anyerror!void,
        beginDraw: *const fn (*anyopaque) void,
        resource_cache: ResourceCacheVTable,
        backendName: *const fn (*anyopaque) []const u8,
    };

    /// Blocking upload for simple programs. GL requires the target context to
    /// be current. CPU upload builds cheap views. Vulkan does not perform an
    /// implicit device/queue idle here.
    pub fn uploadResourcesBlocking(self: *Renderer, allocators: UploadAllocators, set: *const ResourceManifest) !PreparedResources {
        return uploadPreparedResources(self, set, allocators);
    }

    pub fn uploadResourceBatch(self: *Renderer, allocators: UploadAllocators, prepared: *PreparedResources, batch: ResourceUploadBatch) !void {
        try self.vtable.uploadResources(self.ptr, allocators, prepared, batch);
    }

    pub fn coverageBackend(self: *Renderer, prepared: *const PreparedResources) ?CoverageBackend {
        return self.vtable.coverageBackend(self.ptr, prepared);
    }

    pub fn planResourceUpload(self: *Renderer, allocator: std.mem.Allocator, current: ?*const PreparedResources, next_set: *const ResourceManifest) !ResourceUploadPlan {
        return upload_plan.planResourceUpload(self, allocator, current, next_set);
    }

    pub fn beginResourceUpload(self: *Renderer, allocators: UploadAllocators, plan: *const ResourceUploadPlan) !PendingResourceUpload {
        return .{
            .renderer = self.*,
            .allocators = allocators,
            .plan = try plan.clone(allocators.persistent),
        };
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

    pub fn usesResourceCache(self: *const Renderer) bool {
        return self.vtable.resource_cache.uses_resource_cache;
    }

    pub fn atlasSlotCanOverflowIntoBank(self: *const Renderer, prepared: *const PreparedResources, atlas_index: usize, atlas: upload_plan.AtlasRef) bool {
        return self.vtable.resource_cache.atlasSlotCanOverflowIntoBank(prepared, atlas_index, atlas);
    }

    pub fn atlasNeedsOverflowBank(self: *const Renderer, prepared: *const PreparedResources, atlas_index: usize, atlas: upload_plan.AtlasRef) bool {
        return self.vtable.resource_cache.atlasNeedsOverflowBank(prepared, atlas_index, atlas);
    }

    pub fn atlasWouldRebuild(self: *const Renderer, prepared: *const PreparedResources, atlas_index: usize, atlas: upload_plan.AtlasRef) bool {
        return self.vtable.resource_cache.atlasWouldRebuild(prepared, atlas_index, atlas);
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
        return self.vtable.draw(self, prepared, records, state);
    }

    pub fn drawPrepared(self: *Renderer, prepared: *const PreparedResources, scene: *const PreparedScene, state: DrawState) !void {
        return self.draw(prepared, scene.slice(), state);
    }

    pub fn drawPass(self: *Renderer, prepared: *const PreparedResources, records: DrawRecords, pass: DrawPass) !void {
        return self.vtable.drawPass(self, prepared, records, pass);
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
        self.vtable.beginDraw(self.ptr);
    }

    fn drawText(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, state: DrawState, texture_layer_base: u32) !void {
        try self.vtable.drawText(self.ptr, backend_prepared, vertices, state, texture_layer_base);
    }

    fn drawPaths(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, state: DrawState, texture_layer_base: u32) !void {
        try self.vtable.drawPaths(self.ptr, backend_prepared, vertices, state, texture_layer_base);
    }

    pub fn backendName(self: *const Renderer) []const u8 {
        return self.vtable.backendName(@constCast(self.ptr));
    }
};

pub fn disabledVTable(comptime backend_kind: BackendKind) Renderer.VTable {
    const S = struct {
        fn deinitFn(_: *anyopaque) void {}
        fn uploadResourcesFn(_: *anyopaque, _: UploadAllocators, _: *PreparedResources, _: ResourceUploadBatch) anyerror!void {
            return error.UnsupportedRenderer;
        }
        fn coverageBackendFn(_: *anyopaque, _: *const PreparedResources) ?CoverageBackend {
            return null;
        }
        fn drawFn(_: *Renderer, _: *const PreparedResources, _: DrawRecords, _: DrawState) anyerror!void {
            return error.UnsupportedRenderer;
        }
        fn drawPassFn(_: *Renderer, _: *const PreparedResources, _: DrawRecords, _: DrawPass) anyerror!void {
            return error.UnsupportedRenderer;
        }
        fn drawTextFn(_: *anyopaque, _: ?*const anyopaque, _: []const u32, _: DrawState, _: u32) anyerror!void {
            return error.UnsupportedRenderer;
        }
        fn drawPathsFn(_: *anyopaque, _: ?*const anyopaque, _: []const u32, _: DrawState, _: u32) anyerror!void {
            return error.UnsupportedRenderer;
        }
        fn beginDrawFn(_: *anyopaque) void {}
        fn resourceCacheStatsFn(_: *const anyopaque) ResourceCacheStats {
            return .{};
        }
        fn resetResourceCacheFn(_: *anyopaque) void {}
        fn validateBackendGenerationFn(_: *const PreparedResources) anyerror!void {
            return error.UnsupportedRenderer;
        }
        fn atlasSlotCanOverflowIntoBankFn(_: *const PreparedResources, _: usize, _: upload_plan.AtlasRef) bool {
            return false;
        }
        fn atlasNeedsOverflowBankFn(_: *const PreparedResources, _: usize, _: upload_plan.AtlasRef) bool {
            return false;
        }
        fn atlasWouldRebuildFn(_: *const PreparedResources, _: usize, _: upload_plan.AtlasRef) bool {
            return false;
        }
        fn canUseAtlasOverflowBanksFn(_: *const PreparedResources, _: usize) bool {
            return false;
        }
        fn imageArrayWouldRebuildFn(_: *const PreparedResources, _: u32, _: u32, _: u32) bool {
            return false;
        }
        fn backendNameFn(_: *anyopaque) []const u8 {
            return switch (backend_kind) {
                .gl => "OpenGL (disabled)",
                .vulkan => "Vulkan (disabled)",
                .cpu => "CPU (disabled)",
            };
        }
    };
    return .{
        .backend = backend_kind,
        .deinit = &S.deinitFn,
        .uploadResources = &S.uploadResourcesFn,
        .coverageBackend = &S.coverageBackendFn,
        .draw = &S.drawFn,
        .drawPass = &S.drawPassFn,
        .drawText = &S.drawTextFn,
        .drawPaths = &S.drawPathsFn,
        .beginDraw = &S.beginDrawFn,
        .resource_cache = .{
            .uses_resource_cache = false,
            .stats = &S.resourceCacheStatsFn,
            .reset = &S.resetResourceCacheFn,
            .validateBackendGeneration = &S.validateBackendGenerationFn,
            .atlasSlotCanOverflowIntoBank = &S.atlasSlotCanOverflowIntoBankFn,
            .atlasNeedsOverflowBank = &S.atlasNeedsOverflowBankFn,
            .atlasWouldRebuild = &S.atlasWouldRebuildFn,
            .canUseAtlasOverflowBanks = &S.canUseAtlasOverflowBanksFn,
            .imageArrayWouldRebuild = &S.imageArrayWouldRebuildFn,
        },
        .backendName = &S.backendNameFn,
    };
}

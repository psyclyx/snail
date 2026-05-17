const std = @import("std");

const backend_kind_mod = @import("../backend_kind.zig");
const coverage_mod = @import("../coverage.zig");
const draw_mod = @import("../draw.zig");
const prepared_mod = @import("../resources/prepared.zig");
const resource_key_mod = @import("../resource_key.zig");
const set_mod = @import("../resources/set.zig");
const target_mod = @import("../target.zig");
const upload_mod = @import("../upload.zig");
const upload_plan = @import("upload_plan.zig");
const vec = @import("../math/vec.zig");

pub const BackendKind = backend_kind_mod.BackendKind;

const CoverageBackend = coverage_mod.Backend;
const CoverageTransfer = target_mod.CoverageTransfer;
const DrawOptions = draw_mod.DrawOptions;
const DrawRecords = draw_mod.DrawRecords;
const FillRule = target_mod.FillRule;
const Mat4 = vec.Mat4;
const PendingResourceUpload = upload_mod.PendingResourceUpload;
const PreparedResources = prepared_mod.PreparedResources;
const PreparedScene = draw_mod.PreparedScene;
const Resolve = target_mod.Resolve;
const ResourceCacheStats = upload_mod.ResourceCacheStats;
const ResourceUploadBatch = upload_mod.ResourceUploadBatch;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceSet = set_mod.ResourceSet;
const ResourceUploadPlan = upload_mod.ResourceUploadPlan;
const SubpixelOrder = target_mod.SubpixelOrder;
const TargetEncoding = target_mod.TargetEncoding;
const TargetStamp = target_mod.TargetStamp;
const UploadAllocators = upload_mod.UploadAllocators;
const effectiveSubpixelOrderRef = target_mod.effectiveSubpixelOrderRef;
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
    };

    pub const VTable = struct {
        backend: BackendKind,
        deinit: *const fn (*anyopaque) void,
        uploadResources: *const fn (*anyopaque, UploadAllocators, *PreparedResources, ResourceUploadBatch) anyerror!void,
        coverageBackend: *const fn (*anyopaque, *const PreparedResources) ?CoverageBackend,
        // Frame-level draw: validate, set state, walk records. Each backend
        // owns this so it can decide how to schedule the work.
        draw: *const fn (*Renderer, *const PreparedResources, DrawRecords, DrawOptions) anyerror!void,
        // Segment-level dispatch, called from `iterateRecords`.
        drawText: *const fn (*anyopaque, ?*const anyopaque, []const u32, Mat4, f32, f32, u32) void,
        drawPaths: *const fn (*anyopaque, ?*const anyopaque, []const u32, Mat4, f32, f32, u32) void,
        beginFrame: *const fn (*anyopaque) void,
        setSubpixelOrder: *const fn (*anyopaque, SubpixelOrder) void,
        getSubpixelOrder: *const fn (*anyopaque) SubpixelOrder,
        setFillRule: *const fn (*anyopaque, FillRule) void,
        getFillRule: *const fn (*anyopaque) FillRule,
        setTargetEncoding: *const fn (*anyopaque, TargetEncoding) void,
        getTargetEncoding: *const fn (*anyopaque) TargetEncoding,
        setResolve: *const fn (*anyopaque, Resolve) void,
        getResolve: *const fn (*anyopaque) Resolve,
        setCoverageTransfer: *const fn (*anyopaque, CoverageTransfer) void,
        getCoverageTransfer: *const fn (*anyopaque) CoverageTransfer,
        resource_cache: ResourceCacheVTable,
        backendName: *const fn (*anyopaque) []const u8,
    };

    /// Blocking upload for simple programs. GL requires the target context to
    /// be current. CPU upload builds cheap views. Vulkan does not perform an
    /// implicit device/queue idle here.
    pub fn uploadResourcesBlocking(self: *Renderer, allocators: UploadAllocators, set: *const ResourceSet) !PreparedResources {
        return uploadPreparedResources(self, set, allocators);
    }

    pub fn uploadResourceBatch(self: *Renderer, allocators: UploadAllocators, prepared: *PreparedResources, batch: ResourceUploadBatch) !void {
        try self.vtable.uploadResources(self.ptr, allocators, prepared, batch);
    }

    pub fn coverageBackend(self: *Renderer, prepared: *const PreparedResources) ?CoverageBackend {
        return self.vtable.coverageBackend(self.ptr, prepared);
    }

    pub fn planResourceUpload(self: *Renderer, current: ?*const PreparedResources, next_set: *const ResourceSet, changed_keys: []ResourceKey) !ResourceUploadPlan {
        return upload_plan.planResourceUpload(self, current, next_set, changed_keys);
    }

    pub fn beginResourceUpload(self: *Renderer, allocators: UploadAllocators, plan: ResourceUploadPlan) !PendingResourceUpload {
        return .{ .renderer = self.*, .allocators = allocators, .plan = plan };
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

    /// Execute prebuilt draw records. This never discovers, uploads, allocates,
    /// or invalidates resources. The backend's vtable entry decides whether
    /// to walk records serially or fan them out across worker threads.
    pub fn draw(self: *Renderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        return self.vtable.draw(self, prepared, records, options);
    }

    pub fn drawPrepared(self: *Renderer, prepared: *const PreparedResources, scene: *const PreparedScene, options: DrawOptions) !void {
        return self.draw(prepared, scene.slice(), options);
    }

    /// Verify every segment's stamps still match the live prepared resources
    /// and the requested draw target. Returns `error.StaleDrawRecords` if a
    /// resource has been re-uploaded or the target/MVP has changed since the
    /// records were built; `error.MissingPreparedResource` if a key is gone.
    /// Vtables call this once per frame before fan-out so per-tile workers
    /// don't have to re-validate (and don't need an error path).
    fn validateBackendGeneration(self: *Renderer, prepared: *const PreparedResources) !void {
        try self.vtable.resource_cache.validateBackendGeneration(prepared);
    }

    pub fn validateRecords(self: *Renderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        try self.validateBackendGeneration(prepared);
        const expected_target_stamp = TargetStamp.fromRef(&options.mvp, &options.target);
        for (records.segments) |segment| {
            const actual_stamp = prepared.stampForKey(segment.key) orelse return error.MissingPreparedResource;
            if (!actual_stamp.eql(segment.resource_stamp)) return error.StaleDrawRecords;
            if (!std.meta.eql(expected_target_stamp, segment.target_stamp)) return error.StaleDrawRecords;
        }
    }

    /// Frame-level draw: set state, walk records serially dispatching each
    /// segment to the backend's `drawText` / `drawPaths`. Used by GPU adapters
    /// directly, and by the CPU adapter's serial fallback / tile workers.
    /// Caller has already invoked `validateRecords`.
    pub fn iterateRecords(self: *Renderer, records: DrawRecords, options: DrawOptions, backend_prepared: ?*const anyopaque) void {
        self.applySubpixelOrder(effectiveSubpixelOrderRef(&options.target));
        self.applyFillRule(options.target.fill_rule);
        self.applyTargetEncoding(options.target.encoding);
        self.applyResolve(options.target.resolve);
        self.applyCoverageTransfer(options.target.coverage_transfer);
        self.beginBackendFrame();
        for (records.segments) |segment| {
            const vertices = records.words[segment.offset..][0..segment.len];
            switch (segment.kind) {
                .text => if (vertices.len > 0) self.drawText(backend_prepared, vertices, options.mvp, options.target.pixel_width, options.target.pixel_height, segment.texture_layer_base),
                .path => if (vertices.len > 0) self.drawPaths(backend_prepared, vertices, options.mvp, options.target.pixel_width, options.target.pixel_height, segment.texture_layer_base),
            }
        }
    }

    pub fn deinit(self: *Renderer) void {
        self.vtable.deinit(self.ptr);
    }

    fn beginBackendFrame(self: *Renderer) void {
        self.vtable.beginFrame(self.ptr);
    }

    fn drawText(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        self.vtable.drawText(self.ptr, backend_prepared, vertices, mvp, viewport_w, viewport_h, texture_layer_base);
    }

    fn drawPaths(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        self.vtable.drawPaths(self.ptr, backend_prepared, vertices, mvp, viewport_w, viewport_h, texture_layer_base);
    }

    fn applySubpixelOrder(self: *Renderer, order: SubpixelOrder) void {
        self.vtable.setSubpixelOrder(self.ptr, order);
    }

    fn applyFillRule(self: *Renderer, rule: FillRule) void {
        self.vtable.setFillRule(self.ptr, rule);
    }

    fn applyTargetEncoding(self: *Renderer, encoding: TargetEncoding) void {
        self.vtable.setTargetEncoding(self.ptr, encoding);
    }

    fn applyResolve(self: *Renderer, next_resolve: Resolve) void {
        self.vtable.setResolve(self.ptr, next_resolve);
    }

    fn applyCoverageTransfer(self: *Renderer, transfer: CoverageTransfer) void {
        self.vtable.setCoverageTransfer(self.ptr, transfer);
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
        fn drawFn(_: *Renderer, _: *const PreparedResources, _: DrawRecords, _: DrawOptions) anyerror!void {
            return error.UnsupportedRenderer;
        }
        fn drawTextFn(_: *anyopaque, _: ?*const anyopaque, _: []const u32, _: Mat4, _: f32, _: f32, _: u32) void {}
        fn drawPathsFn(_: *anyopaque, _: ?*const anyopaque, _: []const u32, _: Mat4, _: f32, _: f32, _: u32) void {}
        fn beginFrameFn(_: *anyopaque) void {}
        fn setSubpixelOrderFn(_: *anyopaque, _: SubpixelOrder) void {}
        fn getSubpixelOrderFn(_: *anyopaque) SubpixelOrder {
            return .none;
        }
        fn setFillRuleFn(_: *anyopaque, _: FillRule) void {}
        fn getFillRuleFn(_: *anyopaque) FillRule {
            return .non_zero;
        }
        fn setTargetEncodingFn(_: *anyopaque, _: TargetEncoding) void {}
        fn getTargetEncodingFn(_: *anyopaque) TargetEncoding {
            return .srgb;
        }
        fn setResolveFn(_: *anyopaque, _: Resolve) void {}
        fn getResolveFn(_: *anyopaque) Resolve {
            return .{ .direct = .{} };
        }
        fn setCoverageTransferFn(_: *anyopaque, _: CoverageTransfer) void {}
        fn getCoverageTransferFn(_: *anyopaque) CoverageTransfer {
            return .identity;
        }
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
        .drawText = &S.drawTextFn,
        .drawPaths = &S.drawPathsFn,
        .beginFrame = &S.beginFrameFn,
        .setSubpixelOrder = &S.setSubpixelOrderFn,
        .getSubpixelOrder = &S.getSubpixelOrderFn,
        .setFillRule = &S.setFillRuleFn,
        .getFillRule = &S.getFillRuleFn,
        .setTargetEncoding = &S.setTargetEncodingFn,
        .getTargetEncoding = &S.getTargetEncodingFn,
        .setResolve = &S.setResolveFn,
        .getResolve = &S.getResolveFn,
        .setCoverageTransfer = &S.setCoverageTransferFn,
        .getCoverageTransfer = &S.getCoverageTransferFn,
        .resource_cache = .{
            .uses_resource_cache = false,
            .stats = &S.resourceCacheStatsFn,
            .reset = &S.resetResourceCacheFn,
            .validateBackendGeneration = &S.validateBackendGenerationFn,
            .atlasSlotCanOverflowIntoBank = &S.atlasSlotCanOverflowIntoBankFn,
            .atlasNeedsOverflowBank = &S.atlasNeedsOverflowBankFn,
            .atlasWouldRebuild = &S.atlasWouldRebuildFn,
            .canUseAtlasOverflowBanks = &S.canUseAtlasOverflowBanksFn,
        },
        .backendName = &S.backendNameFn,
    };
}

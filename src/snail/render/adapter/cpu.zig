const build_options = @import("build_options");

const common = @import("common.zig");
const coverage_mod = @import("../../coverage.zig");
const draw_mod = @import("../../draw.zig");
const interface = @import("../interface.zig");
const prepared_mod = @import("../../resources/prepared.zig");
const upload_mod = @import("../../upload.zig");

const pipeline = if (build_options.enable_cpu) @import("../backend/cpu/renderer.zig") else struct {
    pub const CpuRenderer = void;
    pub const PreparedResources = void;
};

pub const CpuRenderer = pipeline.CpuRenderer;

const CoverageBackend = coverage_mod.Backend;
const DrawOptions = draw_mod.DrawOptions;
const DrawRecords = draw_mod.DrawRecords;
const ErasedRenderer = interface.Renderer;
const ResourceUploadBatch = upload_mod.ResourceUploadBatch;
const UploadAllocators = upload_mod.UploadAllocators;
const UnifiedPreparedResources = prepared_mod.PreparedResources;

const Config = if (build_options.enable_cpu) struct {
    pub const Backend = pipeline.CpuRenderer;
    pub const Prepared = pipeline.PreparedResources;
    pub const backend_kind = interface.BackendKind.cpu;
    pub const uses_resource_cache = false;

    pub fn prepared(prepared_resources: *const UnifiedPreparedResources) ?*const Prepared {
        if (prepared_resources.backend.cpu) |*cpu_prepared| return cpu_prepared;
        return null;
    }

    pub fn uploadResources(_: *Backend, allocators: UploadAllocators, prepared_resources: *UnifiedPreparedResources, batch: ResourceUploadBatch) !void {
        var cpu_prepared = try Prepared.init(allocators.persistent, batch.atlases, batch.layer_infos);
        errdefer cpu_prepared.deinit();
        if (batch.atlases.len > 0) try cpu_prepared.uploadAtlases(batch.atlases, batch.atlas_views);
        if (batch.layer_infos.len > 0) try cpu_prepared.uploadLayerInfoBlocks(batch.layer_infos, batch.layer_info_views);
        if (batch.images.len > 0) cpu_prepared.uploadImages(batch.images, batch.image_views);
        prepared_resources.backend.cpu = cpu_prepared;
    }

    pub fn coverageBackend(_: *Backend, _: *const UnifiedPreparedResources) ?CoverageBackend {
        return null;
    }

    pub fn draw(renderer: *ErasedRenderer, prepared_resources: *const UnifiedPreparedResources, records: DrawRecords, options: DrawOptions) anyerror!void {
        const backend_prepared = prepared(prepared_resources) orelse return error.MissingPreparedResource;
        try renderer.validateRecords(prepared_resources, records, options);
        switch (options.target.resolve) {
            .direct => {},
            .linear => |linear| {
                if (!options.target.supportsLinearResolve()) return error.InvalidResolve;
                const cpu_self: *Backend = @ptrCast(@alignCast(renderer.ptr));
                const restore = cpu_self.beginLinearResolve(options.target, linear);
                defer cpu_self.endLinearResolve(restore);
                if (dispatchThreaded(cpu_self, backend_prepared, records, options)) return;
                renderer.iterateRecords(records, options, @ptrCast(backend_prepared));
                return;
            },
        }
        const cpu_self: *Backend = @ptrCast(@alignCast(renderer.ptr));
        if (dispatchThreaded(cpu_self, backend_prepared, records, options)) return;
        renderer.iterateRecords(records, options, @ptrCast(backend_prepared));
    }

    fn dispatchThreaded(cpu_self: *Backend, backend_prepared: *const Prepared, records: DrawRecords, options: DrawOptions) bool {
        if (cpu_self.thread_pool) |pool| {
            const span = cpu_self.row_clip_max - cpu_self.row_clip_min;
            if (span >= 2 * Backend.TILE_ROWS) {
                cpu_self.dispatchTiledDraw(pool, @ptrCast(backend_prepared), records, options);
                return true;
            }
        }
        return false;
    }
} else struct {};

pub const vtable = if (build_options.enable_cpu) common.vtable(Config) else interface.disabledVTable(.cpu);

pub fn borrow(cpu: *CpuRenderer) ErasedRenderer {
    return .{ .ptr = @ptrCast(cpu), .vtable = &vtable };
}

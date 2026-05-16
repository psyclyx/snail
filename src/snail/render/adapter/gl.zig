const std = @import("std");

const build_options = @import("build_options");
const common = @import("common.zig");
const coverage_mod = @import("../../coverage.zig");
const draw_mod = @import("../../draw.zig");
const interface = @import("../interface.zig");
const prepared_mod = @import("../../resources/prepared.zig");
const resource_key_mod = @import("../../resource_key.zig");
const resource_upload_mod = @import("../../resources/upload.zig");
const set_mod = @import("../../resources/set.zig");
const upload_mod = @import("../../upload.zig");

const pipeline = if (build_options.enable_opengl) @import("../../render/backend/gl.zig") else struct {
    pub const GlTextState = void;
    pub const PreparedResources = void;
};

const CoverageBackend = coverage_mod.Backend;
const DrawOptions = draw_mod.DrawOptions;
const DrawRecords = draw_mod.DrawRecords;
const ErasedRenderer = interface.Renderer;
const PendingResourceUpload = upload_mod.PendingResourceUpload;
const PreparedResources = prepared_mod.PreparedResources;
const PreparedScene = draw_mod.PreparedScene;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceCacheStats = upload_mod.ResourceCacheStats;
const ResourceSet = set_mod.ResourceSet;
const ResourceUploadPlan = upload_mod.ResourceUploadPlan;
const ResourceUploadBatch = resource_upload_mod.ResourceUploadBatch;
const UploadAllocators = upload_mod.UploadAllocators;

const Config = if (build_options.enable_opengl) struct {
    pub const Backend = pipeline.GlTextState;
    pub const Prepared = pipeline.PreparedResources;
    pub const backend_kind = interface.BackendKind.gl;
    pub const uses_resource_cache = true;

    pub fn prepared(prepared_resources: *const PreparedResources) ?*const Prepared {
        return prepared_resources.gl orelse null;
    }

    pub fn uploadResources(self: *Backend, allocators: UploadAllocators, prepared_resources: *PreparedResources, batch: ResourceUploadBatch) !void {
        const gl_prepared = self.resourceCache(allocators.persistent);
        if (batch.atlases.len > 0 or batch.layer_infos.len > 0) try gl_prepared.uploadAtlasesAndLayerInfoWithCapacityModes(
            allocators.scratch,
            batch.atlases,
            batch.atlas_capacity_modes,
            batch.atlas_views,
            batch.layer_infos,
            batch.layer_info_views,
        );
        if (batch.images.len > 0) try gl_prepared.uploadImages(allocators.scratch, batch.images, batch.image_views);
        prepared_resources.gl = gl_prepared;
        prepared_resources.backend_generation = gl_prepared.generation;
    }

    pub fn coverageBackend(self: *Backend, prepared_resources: *const PreparedResources) ?CoverageBackend {
        if (prepared_resources.gl) |gl_resources| {
            return .{ .gl = .{ .gl = self, .gl_resources = gl_resources, .prepared = prepared_resources } };
        }
        return null;
    }

    pub fn draw(renderer: *ErasedRenderer, prepared_resources: *const PreparedResources, records: DrawRecords, options: DrawOptions) anyerror!void {
        const backend_prepared = prepared(prepared_resources) orelse return error.MissingPreparedResource;
        try renderer.validateRecords(prepared_resources, records, options);
        switch (options.target.resolve) {
            .direct => {},
            .linear => |linear| {
                if (!options.target.supportsLinearResolve()) return error.InvalidResolve;
                const width: u32 = @intFromFloat(@max(options.target.pixel_width, 0.0));
                const height: u32 = @intFromFloat(@max(options.target.pixel_height, 0.0));
                const gl_self: *Backend = @ptrCast(@alignCast(renderer.ptr));
                const restore = try gl_self.beginLinearResolve(width, height, linear);
                var inner_options = options;
                inner_options.target.encoding = .linear;
                inner_options.target.resolve = .{ .direct = .{} };
                renderer.iterateRecords(records, inner_options, @ptrCast(backend_prepared));
                gl_self.endLinearResolve(restore);
                gl_self.setTargetEncoding(options.target.encoding);
                gl_self.setResolve(options.target.resolve);
                return;
            },
        }
        renderer.iterateRecords(records, options, @ptrCast(backend_prepared));
    }
} else struct {};

pub const vtable = if (build_options.enable_opengl) common.vtable(Config) else interface.disabledVTable(.gl);

/// Typed handle for the GL backend.
///
/// `Renderer` owns the GL state; the upload / draw methods are thin shims over
/// the erased renderer for callers that want to stay strongly typed.
pub const Renderer = if (build_options.enable_opengl) struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: *pipeline.GlTextState,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const text = try allocator.create(pipeline.GlTextState);
        text.* = .{};
        errdefer allocator.destroy(text);
        try text.init();
        return .{ .allocator = allocator, .state = text };
    }

    pub fn deinit(self: *Self) void {
        self.state.deinit();
        self.allocator.destroy(self.state);
        self.* = undefined;
    }

    pub fn asRenderer(self: *Self) ErasedRenderer {
        return .{ .ptr = @ptrCast(self.state), .vtable = &vtable };
    }

    pub fn uploadResourcesBlocking(self: *Self, allocators: UploadAllocators, set: *const ResourceSet) !PreparedResources {
        var renderer = self.asRenderer();
        return renderer.uploadResourcesBlocking(allocators, set);
    }

    pub fn planResourceUpload(self: *Self, current: ?*const PreparedResources, next_set: *const ResourceSet, changed_keys: []ResourceKey) !ResourceUploadPlan {
        var renderer = self.asRenderer();
        return renderer.planResourceUpload(current, next_set, changed_keys);
    }

    pub fn beginResourceUpload(self: *Self, allocators: UploadAllocators, plan: ResourceUploadPlan) !PendingResourceUpload {
        var renderer = self.asRenderer();
        return renderer.beginResourceUpload(allocators, plan);
    }

    pub fn draw(self: *Self, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.draw(prepared, records, options);
    }

    pub fn drawPrepared(self: *Self, prepared: *const PreparedResources, scene: *const PreparedScene, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.drawPrepared(prepared, scene, options);
    }

    pub fn coverageBackend(self: *Self, prepared_resources: *const PreparedResources) ?CoverageBackend {
        if (prepared_resources.gl) |gl_resources| {
            return .{ .gl = .{ .gl = self.state, .gl_resources = gl_resources, .prepared = prepared_resources } };
        }
        return null;
    }

    pub fn backendName(self: *const Self) []const u8 {
        return self.state.backendName();
    }

    pub fn resourceCacheStats(self: *const Self) ResourceCacheStats {
        return self.state.resourceCacheStats();
    }

    pub fn resetResourceCache(self: *Self) void {
        self.state.resetResourceCache();
    }
} else void;

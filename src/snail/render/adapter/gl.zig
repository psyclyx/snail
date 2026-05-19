const std = @import("std");

const build_options = @import("build_options");
const common = @import("common.zig");
const coverage_mod = @import("../../coverage.zig");
const draw_mod = @import("../../draw.zig");
const interface = @import("../interface.zig");
const prepared_mod = @import("../../resources/prepared.zig");
const set_mod = @import("../../resources/manifest.zig");
const upload_mod = @import("../../upload.zig");

const pipeline = if (build_options.enable_opengl) @import("../backend/gl/state.zig") else struct {
    pub const GlTextState = void;
    pub const PreparedResources = void;
};

const CoverageBackend = coverage_mod.Backend;
const DrawPass = draw_mod.DrawPass;
const DrawState = draw_mod.DrawState;
const DrawRecords = draw_mod.DrawRecords;
const ErasedRenderer = interface.Renderer;
const PendingResourceUpload = upload_mod.PendingResourceUpload;
const PreparedResources = prepared_mod.PreparedResources;
const PreparedScene = draw_mod.PreparedScene;
const ResourceCacheStats = upload_mod.ResourceCacheStats;
const ResourceManifest = set_mod.ResourceManifest;
const ResourceUploadPlan = upload_mod.ResourceUploadPlan;
const ResourceUploadBatch = upload_mod.ResourceUploadBatch;
const UploadAllocators = upload_mod.UploadAllocators;

const Config = if (build_options.enable_opengl) struct {
    pub const Backend = pipeline.GlTextState;
    pub const Prepared = pipeline.PreparedResources;
    pub const backend_kind = interface.BackendKind.gl;
    pub const uses_resource_cache = true;

    pub fn prepared(prepared_resources: *const PreparedResources) ?*const Prepared {
        return prepared_resources.resident.gl orelse null;
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
        prepared_resources.resident.gl = gl_prepared;
        prepared_resources.resident.generation = gl_prepared.generation;
    }

    pub fn coverageBackend(self: *Backend, prepared_resources: *const PreparedResources) ?CoverageBackend {
        if (prepared_resources.resident.gl) |gl_resources| {
            return .{ .gl = .{ .gl = self, .gl_resources = gl_resources, .prepared = prepared_resources } };
        }
        return null;
    }

    pub fn draw(renderer: *ErasedRenderer, prepared_resources: *const PreparedResources, records: DrawRecords, state: DrawState) anyerror!void {
        const backend_prepared = prepared(prepared_resources) orelse return error.MissingPreparedResource;
        try renderer.validateRecords(prepared_resources, records);
        try renderer.iterateRecords(records, state, @ptrCast(backend_prepared));
    }

    pub fn drawPass(renderer: *ErasedRenderer, prepared_resources: *const PreparedResources, records: DrawRecords, pass: DrawPass) anyerror!void {
        switch (pass.resolve) {
            .direct => try draw(renderer, prepared_resources, records, pass.state),
            .linear => |resolve| {
                const gl_state: *Backend = @ptrCast(@alignCast(renderer.ptr));
                const restore = try gl_state.beginLinearResolve(pass.state.surface, resolve);
                defer gl_state.endLinearResolve(restore);
                try draw(renderer, prepared_resources, records, pass.state);
            },
        }
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

    pub fn uploadResourcesBlocking(self: *Self, allocators: UploadAllocators, set: *const ResourceManifest) !PreparedResources {
        var renderer = self.asRenderer();
        return renderer.uploadResourcesBlocking(allocators, set);
    }

    pub fn planResourceUpload(self: *Self, allocator: std.mem.Allocator, current: ?*const PreparedResources, next_set: *const ResourceManifest) !ResourceUploadPlan {
        var renderer = self.asRenderer();
        return renderer.planResourceUpload(allocator, current, next_set);
    }

    pub fn beginResourceUpload(self: *Self, allocators: UploadAllocators, plan: *const ResourceUploadPlan) !PendingResourceUpload {
        var renderer = self.asRenderer();
        return renderer.beginResourceUpload(allocators, plan);
    }

    pub fn draw(self: *Self, prepared: *const PreparedResources, records: DrawRecords, state: DrawState) !void {
        var renderer = self.asRenderer();
        try renderer.draw(prepared, records, state);
    }

    pub fn drawPrepared(self: *Self, prepared: *const PreparedResources, scene: *const PreparedScene, state: DrawState) !void {
        var renderer = self.asRenderer();
        try renderer.drawPrepared(prepared, scene, state);
    }

    pub fn drawPass(self: *Self, prepared: *const PreparedResources, records: DrawRecords, pass: DrawPass) !void {
        var renderer = self.asRenderer();
        try renderer.drawPass(prepared, records, pass);
    }

    pub fn drawPreparedPass(self: *Self, prepared: *const PreparedResources, scene: *const PreparedScene, pass: DrawPass) !void {
        var renderer = self.asRenderer();
        try renderer.drawPreparedPass(prepared, scene, pass);
    }

    pub fn coverageBackend(self: *Self, prepared_resources: *const PreparedResources) ?CoverageBackend {
        if (prepared_resources.resident.gl) |gl_resources| {
            return .{ .gl = .{ .gl = self.state, .gl_resources = gl_resources, .prepared = prepared_resources } };
        }
        return null;
    }

    pub fn backendName(self: *const Self) [:0]const u8 {
        return self.state.backendName();
    }

    pub fn resourceCacheStats(self: *const Self) ResourceCacheStats {
        return self.state.resourceCacheStats();
    }

    pub fn resetResourceCache(self: *Self) void {
        self.state.resetResourceCache();
    }
} else void;

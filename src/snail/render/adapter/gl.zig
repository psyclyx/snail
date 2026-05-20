const std = @import("std");

const build_options = @import("build_options");
const common = @import("common.zig");
const coverage_mod = @import("../../coverage.zig");
const draw_mod = @import("../../draw.zig");
const interface = @import("../interface.zig");
const prepared_mod = @import("../../resources/prepared.zig");
const set_mod = @import("../../resources/manifest.zig");
const upload_mod = @import("../../upload.zig");

const pipeline = if ((build_options.enable_gl33 or build_options.enable_gl44)) @import("../backend/gl/state.zig") else struct {
    pub const Backend = enum { gl33, gl44 };
    pub const Gl33TextState = void;
    pub const Gl44TextState = void;
    pub const Gl33PreparedResources = void;
    pub const Gl44PreparedResources = void;
};

const CoverageBackend = coverage_mod.Backend;
const DrawPass = draw_mod.DrawPass;
const DrawState = draw_mod.DrawState;
const DrawList = draw_mod.DrawList;
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

fn isEnabled(comptime backend: pipeline.Backend) bool {
    return switch (backend) {
        .gl33 => build_options.enable_gl33,
        .gl44 => build_options.enable_gl44,
    };
}

fn backendForKind(comptime kind: interface.BackendKind) pipeline.Backend {
    return switch (kind) {
        .gl33 => .gl33,
        .gl44 => .gl44,
        else => unreachable,
    };
}

fn stateType(comptime backend: pipeline.Backend) type {
    return switch (backend) {
        .gl33 => pipeline.Gl33TextState,
        .gl44 => pipeline.Gl44TextState,
    };
}

fn preparedType(comptime backend: pipeline.Backend) type {
    return switch (backend) {
        .gl33 => pipeline.Gl33PreparedResources,
        .gl44 => pipeline.Gl44PreparedResources,
    };
}

fn Config(comptime kind: interface.BackendKind) type {
    const gl_backend = backendForKind(kind);
    return if (isEnabled(gl_backend)) struct {
        pub const Backend = stateType(gl_backend);
        pub const Prepared = preparedType(gl_backend);
        pub const backend_kind = kind;
        pub const uses_resource_cache = true;

        pub fn prepared(prepared_resources: *const PreparedResources) ?*const Prepared {
            if (comptime gl_backend == .gl33) return prepared_resources.resident.gl33 orelse null;
            return prepared_resources.resident.gl44 orelse null;
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
            if (comptime gl_backend == .gl33) {
                prepared_resources.resident.gl33 = gl_prepared;
            } else {
                prepared_resources.resident.gl44 = gl_prepared;
            }
            prepared_resources.resident.generation = gl_prepared.generation;
        }

        pub fn coverageBackend(self: *Backend, prepared_resources: *const PreparedResources) ?CoverageBackend {
            if (prepared(prepared_resources)) |gl_resources| {
                return switch (kind) {
                    .gl33 => .{ .gl33 = .{ .gl = self, .gl_resources = gl_resources, .prepared = prepared_resources } },
                    .gl44 => .{ .gl44 = .{ .gl = self, .gl_resources = gl_resources, .prepared = prepared_resources } },
                    else => unreachable,
                };
            }
            return null;
        }

        pub fn draw(renderer: *ErasedRenderer, prepared_resources: *const PreparedResources, records: DrawRecords, state: DrawState) anyerror!void {
            const backend_prepared = prepared(prepared_resources) orelse return error.MissingPreparedResource;
            try interface.validateRecords(renderer, prepared_resources, records);
            try interface.iterateRecords(renderer, records, state, @ptrCast(backend_prepared));
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
}

pub const vtable_gl33 = if (build_options.enable_gl33) common.vtable(Config(.gl33)) else interface.disabledVTable(.gl33);
pub const vtable_gl44 = if (build_options.enable_gl44) common.vtable(Config(.gl44)) else interface.disabledVTable(.gl44);

fn backendKind(comptime backend: pipeline.Backend) interface.BackendKind {
    return switch (backend) {
        .gl33 => .gl33,
        .gl44 => .gl44,
    };
}

fn vtableFor(comptime backend: pipeline.Backend) *const ErasedRenderer.VTable {
    return switch (backend) {
        .gl33 => &vtable_gl33,
        .gl44 => &vtable_gl44,
    };
}

fn RendererType(comptime gl_backend: pipeline.Backend) type {
    return if (isEnabled(gl_backend)) struct {
        const Self = @This();
        const kind = backendKind(gl_backend);
        const State = stateType(gl_backend);

        allocator: std.mem.Allocator,
        state: *State,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const text = try allocator.create(State);
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
            return .{ .ptr = @ptrCast(self.state), .vtable = vtableFor(gl_backend) };
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

        pub fn draw(self: *Self, prepared: *const PreparedResources, list: *const DrawList, state: DrawState) !void {
            var renderer = self.asRenderer();
            try renderer.draw(prepared, list, state);
        }

        pub fn drawPrepared(self: *Self, prepared: *const PreparedResources, scene: *const PreparedScene, state: DrawState) !void {
            var renderer = self.asRenderer();
            try renderer.drawPrepared(prepared, scene, state);
        }

        pub fn drawPass(self: *Self, prepared: *const PreparedResources, list: *const DrawList, pass: DrawPass) !void {
            var renderer = self.asRenderer();
            try renderer.drawPass(prepared, list, pass);
        }

        pub fn drawPreparedPass(self: *Self, prepared: *const PreparedResources, scene: *const PreparedScene, pass: DrawPass) !void {
            var renderer = self.asRenderer();
            try renderer.drawPreparedPass(prepared, scene, pass);
        }

        pub fn coverageBackend(self: *Self, prepared_resources: *const PreparedResources) ?CoverageBackend {
            const gl_resources = if (comptime gl_backend == .gl33)
                prepared_resources.resident.gl33 orelse return null
            else
                prepared_resources.resident.gl44 orelse return null;
            return switch (kind) {
                .gl33 => .{ .gl33 = .{ .gl = self.state, .gl_resources = gl_resources, .prepared = prepared_resources } },
                .gl44 => .{ .gl44 = .{ .gl = self.state, .gl_resources = gl_resources, .prepared = prepared_resources } },
                else => unreachable,
            };
        }

        pub fn backend(_: *const Self) interface.BackendKind {
            return kind;
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
}

/// Typed handle for the GL 3.3 backend.
///
/// The renderer owns the GL state; the upload / draw methods are thin shims over
/// the erased renderer for callers that want to stay strongly typed.
pub const Gl33Renderer = RendererType(.gl33);

/// Typed handle for the GL 4.4 backend.
pub const Gl44Renderer = RendererType(.gl44);

const std = @import("std");

const build_options = @import("build_options");
const common = @import("common.zig");
const coverage_mod = @import("../../coverage.zig");
const draw_mod = @import("../../draw.zig");
const interface = @import("../interface.zig");
const prepared_mod = @import("../../resources/prepared.zig");
const set_mod = @import("../../resources/manifest.zig");
const upload_mod = @import("../../upload.zig");

const pipeline = if (build_options.enable_vulkan) @import("../backend/vulkan/pipeline.zig") else struct {
    pub const PreparedResources = void;
    pub const VulkanContext = void;
    pub const VulkanPipeline = void;
};

pub const VulkanContext = pipeline.VulkanContext;

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

const Config = if (build_options.enable_vulkan) struct {
    pub const Backend = pipeline.VulkanPipeline;
    pub const Prepared = pipeline.PreparedResources;
    pub const backend_kind = interface.BackendKind.vulkan;
    pub const uses_resource_cache = true;

    pub fn prepared(prepared_resources: *const PreparedResources) ?*const Prepared {
        return prepared_resources.backend.vulkan orelse null;
    }

    pub fn uploadResources(self: *Backend, allocators: UploadAllocators, prepared_resources: *PreparedResources, batch: ResourceUploadBatch) !void {
        const vk_prepared = try self.resourceCache(allocators.persistent);
        if (batch.atlases.len > 0 or batch.layer_infos.len > 0) try self.uploadPreparedAtlasesAndLayerInfoWithCapacityModes(
            vk_prepared,
            allocators.scratch,
            batch.atlases,
            batch.atlas_capacity_modes,
            batch.atlas_views,
            batch.layer_infos,
            batch.layer_info_views,
        );
        if (batch.images.len > 0) try self.uploadPreparedImages(vk_prepared, allocators.scratch, batch.images, batch.image_views);
        prepared_resources.backend.vulkan = vk_prepared;
        prepared_resources.backend.generation = vk_prepared.generation;
    }

    pub fn coverageBackend(_: *Backend, _: *const PreparedResources) ?CoverageBackend {
        return null;
    }

    pub fn draw(renderer: *ErasedRenderer, prepared_resources: *const PreparedResources, records: DrawRecords, state: DrawState) anyerror!void {
        const backend_prepared = prepared(prepared_resources) orelse return error.MissingPreparedResource;
        try renderer.validateRecords(prepared_resources, records);
        try renderer.iterateRecords(records, state, @ptrCast(backend_prepared));
    }

    pub fn drawPass(renderer: *ErasedRenderer, prepared_resources: *const PreparedResources, records: DrawRecords, pass: DrawPass) anyerror!void {
        return switch (pass.resolve) {
            .direct => draw(renderer, prepared_resources, records, pass.state),
            .linear => error.UnsupportedResolve,
        };
    }
} else struct {};

pub const vtable = if (build_options.enable_vulkan) common.vtable(Config) else interface.disabledVTable(.vulkan);

/// Typed handle for the Vulkan backend.
///
/// The typed handle exists for Vulkan-specific command-buffer integration.
pub const Renderer = if (build_options.enable_vulkan) struct {
    const Self = @This();
    pub const Frame = struct {
        renderer: *Self,
        cmd: pipeline.vk.VkCommandBuffer,
        slot: u32,

        pub fn draw(self: Frame, prepared: *const PreparedResources, records: DrawRecords, state: DrawState) !void {
            self.renderer.state.setCommandBuffer(self.cmd);
            defer self.renderer.state.clearCommandBuffer();
            var renderer = self.renderer.asRenderer();
            try renderer.draw(prepared, records, state);
        }

        pub fn drawPrepared(self: Frame, prepared: *const PreparedResources, scene: *const PreparedScene, state: DrawState) !void {
            try self.draw(prepared, scene.slice(), state);
        }

        pub fn drawPass(self: Frame, prepared: *const PreparedResources, records: DrawRecords, pass: DrawPass) !void {
            self.renderer.state.setCommandBuffer(self.cmd);
            defer self.renderer.state.clearCommandBuffer();
            var renderer = self.renderer.asRenderer();
            try renderer.drawPass(prepared, records, pass);
        }

        pub fn drawPreparedPass(self: Frame, prepared: *const PreparedResources, scene: *const PreparedScene, pass: DrawPass) !void {
            try self.drawPass(prepared, scene.slice(), pass);
        }

        pub fn coverageBackend(self: Frame, prepared_resources: *const PreparedResources) ?CoverageBackend {
            if (prepared_resources.backend.vulkan) |vk_resources| {
                return .{ .vulkan = .{
                    .vk = self.renderer.state,
                    .vk_resources = vk_resources,
                    .prepared = prepared_resources,
                    .cmd = self.cmd,
                } };
            }
            return null;
        }
    };

    allocator: std.mem.Allocator,
    state: *pipeline.VulkanPipeline,

    pub fn init(allocator: std.mem.Allocator, vk_ctx: VulkanContext) !Self {
        const vkp = try allocator.create(pipeline.VulkanPipeline);
        vkp.* = .{};
        errdefer allocator.destroy(vkp);
        try vkp.init(vk_ctx);
        return .{ .allocator = allocator, .state = vkp };
    }

    pub fn deinit(self: *Self) void {
        self.state.deinit();
        self.allocator.destroy(self.state);
        self.* = undefined;
    }

    pub fn asRenderer(self: *Self) ErasedRenderer {
        return .{ .ptr = @ptrCast(self.state), .vtable = &vtable };
    }

    pub fn frame(self: *Self, context: anytype) Frame {
        self.state.setFrameSlot(context.slot);
        return .{
            .renderer = self,
            .cmd = @ptrCast(context.cmd),
            .slot = context.slot,
        };
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

    pub fn recordResourceUpload(self: *Self, pending: *PendingResourceUpload, cmd: pipeline.vk.VkCommandBuffer, options: PendingResourceUpload.RecordOptions) !void {
        if (!self.ownsPendingResourceUpload(pending)) return error.InvalidArgument;
        self.state.beginResourceUploadRecording(cmd);
        defer self.state.endResourceUploadRecording();
        try pending.recordExternal(options);
    }

    pub fn resourceUploadReadyFence(self: *Self, pending: *PendingResourceUpload, fence: pipeline.vk.VkFence) bool {
        if (!self.ownsPendingResourceUpload(pending)) return false;
        return pending.ready(pipeline.vk.vkGetFenceStatus(self.state.ctx.device, fence) == pipeline.vk.VK_SUCCESS);
    }

    fn ownsPendingResourceUpload(self: *const Self, pending: *const PendingResourceUpload) bool {
        return pending.renderer.ptr == @as(*anyopaque, @ptrCast(self.state)) and pending.renderer.backend() == .vulkan;
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

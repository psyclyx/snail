const std = @import("std");

const build_options = @import("build_options");
const render_mod = @import("render.zig");
const resource_key_mod = @import("resource_key.zig");
const resources_mod = @import("resources.zig");
const vulkan_pipeline = if (build_options.enable_vulkan) @import("renderer/vulkan.zig") else struct {
    pub const VkCommandBuffer = void;
    pub const VkFence = void;
    pub const VulkanPipeline = void;
};

const PreparedResources = resources_mod.PreparedResources;
const Renderer = render_mod.Renderer;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceSet = resources_mod.ResourceSet;
const uploadPreparedResources = resources_mod.uploadPreparedResources;

/// Allocation-free estimate of upload-source bytes and backend texture bytes.
/// `*_used` is the payload bytes in the source resource data; `*_allocated`
/// is the texture storage implied by Snail's packing policy, excluding driver
/// alignment and API object overhead.
pub const ResourceFootprint = struct {
    curve_bytes_used: usize = 0,
    curve_bytes_allocated: usize = 0,
    band_bytes_used: usize = 0,
    band_bytes_allocated: usize = 0,
    layer_info_bytes_used: usize = 0,
    layer_info_bytes_allocated: usize = 0,
    image_bytes_used: usize = 0,
    image_bytes_allocated: usize = 0,

    pub fn usedBytes(self: ResourceFootprint) usize {
        return self.curve_bytes_used +
            self.band_bytes_used +
            self.layer_info_bytes_used +
            self.image_bytes_used;
    }

    pub fn allocatedBytes(self: ResourceFootprint) usize {
        return self.curve_bytes_allocated +
            self.band_bytes_allocated +
            self.layer_info_bytes_allocated +
            self.image_bytes_allocated;
    }

    pub fn add(self: *ResourceFootprint, other: ResourceFootprint) void {
        self.curve_bytes_used += other.curve_bytes_used;
        self.curve_bytes_allocated += other.curve_bytes_allocated;
        self.band_bytes_used += other.band_bytes_used;
        self.band_bytes_allocated += other.band_bytes_allocated;
        self.layer_info_bytes_used += other.layer_info_bytes_used;
        self.layer_info_bytes_allocated += other.layer_info_bytes_allocated;
        self.image_bytes_used += other.image_bytes_used;
        self.image_bytes_allocated += other.image_bytes_allocated;
    }
};

pub const ResourceCacheStats = struct {
    generation: u64 = 0,
    atlas_pages_resident: u32 = 0,
    atlas_layers_allocated: u32 = 0,
    image_layers_resident: u32 = 0,
    image_layers_allocated: u32 = 0,
};

pub const UploadAllocators = struct {
    persistent: std.mem.Allocator,
    scratch: std.mem.Allocator,
};

pub const ResourceUploadPlan = struct {
    set: *const ResourceSet,
    /// Backend allocation footprint for the next prepared resource set.
    upload_footprint: ResourceFootprint = .{},
    /// Bytes this backend path will upload or construct for the next prepared
    /// resource set. Backend packing may make this larger than `changed_bytes`.
    upload_bytes: usize = 0,
    /// Bytes whose dependency stamp differs from `current`, keyed by stable
    /// ResourceSet keys. Exposed so callers can see intent-preserving changes.
    changed_bytes: usize = 0,
    changed_keys: []ResourceKey = &.{},
    changed_len: usize = 0,
    reused_atlas_pages: u32 = 0,
    missing_atlas_pages: u32 = 0,
    duplicated_atlas_pages: u32 = 0,
    new_atlas_banks: u32 = 0,
    reused_images: u32 = 0,
    missing_images: u32 = 0,
    new_image_banks: u32 = 0,
    curve_bytes_upload: usize = 0,
    band_bytes_upload: usize = 0,
    layer_info_bytes_upload: usize = 0,
    image_bytes_upload: usize = 0,
    gpu_bytes_allocated: usize = 0,

    pub fn changedKeys(self: *const ResourceUploadPlan) []const ResourceKey {
        return self.changed_keys[0..self.changed_len];
    }

    pub fn addChanged(self: *ResourceUploadPlan, key: ResourceKey, bytes: usize) !void {
        if (self.changed_len >= self.changed_keys.len) return error.ResourceUploadPlanFull;
        self.changed_keys[self.changed_len] = key;
        self.changed_len += 1;
        self.changed_bytes += bytes;
    }
};

pub const ResourceUploadCommand = union(enum) {
    none,
    vulkan: if (build_options.enable_vulkan) vulkan_pipeline.vk.VkCommandBuffer else void,

    pub const no_command = ResourceUploadCommand{ .none = {} };
};

pub const ResourceUploadCompletion = union(enum) {
    immediate,
    ready: bool,
    vulkan_fence: if (build_options.enable_vulkan) vulkan_pipeline.vk.VkFence else void,

    pub const complete = ResourceUploadCompletion{ .ready = true };
    pub const pending = ResourceUploadCompletion{ .ready = false };
};

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

    /// Record upload work for this plan. Vulkan records into a caller-owned
    /// command buffer; CPU and GL complete during this call.
    pub fn record(self: *PendingResourceUpload, command: ResourceUploadCommand, options: struct { budget_bytes: usize = std.math.maxInt(usize) }) !void {
        if (self.prepared != null) return;
        if (self.plan.upload_bytes > options.budget_bytes) return error.ResourceUploadBudgetExceeded;

        if (comptime build_options.enable_vulkan) {
            if (self.renderer.backend() == .vulkan) {
                const cmd = switch (command) {
                    .vulkan => |vk_cmd| vk_cmd,
                    else => return error.MissingUploadCommand,
                };
                const vk_state: *vulkan_pipeline.VulkanPipeline = @ptrCast(@alignCast(self.renderer.ptr));
                vk_state.beginResourceUploadRecording(cmd);
                defer vk_state.endResourceUploadRecording();
                self.prepared = try uploadPreparedResources(&self.renderer, self.plan.set, self.allocators);
                self.external_completion_required = true;
                self.ready_to_publish = false;
                return;
            }
        }

        self.prepared = try self.renderer.uploadResourcesBlocking(self.allocators, self.plan.set);
        self.external_completion_required = false;
        self.ready_to_publish = true;
    }

    pub fn ready(self: *PendingResourceUpload, completion: ResourceUploadCompletion) bool {
        if (self.prepared == null) return false;
        if (!self.external_completion_required) {
            self.ready_to_publish = true;
            return true;
        }
        if (self.externalCompletionReady(completion)) {
            self.ready_to_publish = true;
            return true;
        }
        return false;
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
        self.prepared = null;
        self.external_completion_required = false;
        self.ready_to_publish = false;
    }

    fn externalCompletionReady(self: *const PendingResourceUpload, completion: ResourceUploadCompletion) bool {
        return switch (completion) {
            .immediate => true,
            .ready => |is_ready| is_ready,
            .vulkan_fence => |fence| if (comptime build_options.enable_vulkan) self.vulkanFenceReady(fence) else false,
        };
    }

    fn vulkanFenceReady(self: *const PendingResourceUpload, fence: if (build_options.enable_vulkan) vulkan_pipeline.vk.VkFence else void) bool {
        if (comptime !build_options.enable_vulkan) return false;
        if (self.renderer.backend() != .vulkan) return false;
        const vk_state: *vulkan_pipeline.VulkanPipeline = @ptrCast(@alignCast(self.renderer.ptr));
        return vulkan_pipeline.vk.vkGetFenceStatus(vk_state.ctx.device, fence) == vulkan_pipeline.vk.VK_SUCCESS;
    }
};

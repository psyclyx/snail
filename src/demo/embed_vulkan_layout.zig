//! Standalone owner of the Vulkan sampler + descriptor-set-layout resources.
//!
//! These used to live inside the all-in-one `VulkanPipeline`. They are pulled
//! out here so both the all-in-one renderer and an embeddable caller consume
//! the *same* layout — and so the descriptor-set layout (a core piece of the
//! embeddable contract) outlives the all-in-one renderer's removal.
//!
//! The layout owns two immutable samplers (nearest for the curve/band/
//! layer-info textures, linear for the image array) baked into a 4-binding
//! combined-image-sampler descriptor-set layout (see `contract.zig` for the
//! binding order). A `VulkanBackendCache` is fed this layout's handles via
//! `PipelineShape` to allocate + write its descriptor set.

const std = @import("std");

const contract = @import("embed_vulkan_contract.zig");
const vulkan_types = @import("vulkan_types");
const vulkan_device = @import("embed_vulkan_device.zig");

pub const vk = vulkan_types.vk;
pub const VulkanContext = vulkan_types.VulkanContext;
const check = vulkan_device.check;

pub const VulkanResourceLayout = struct {
    ctx: VulkanContext = undefined,
    sampler_nearest: vk.VkSampler = null,
    sampler_linear: vk.VkSampler = null,
    desc_set_layout: vk.VkDescriptorSetLayout = null,

    pub fn init(self: *VulkanResourceLayout, ctx: VulkanContext) !void {
        self.* = .{ .ctx = ctx };
        errdefer self.deinit();
        try self.initSamplers();
        try self.initDescriptorSetLayout();
    }

    fn initSamplers(self: *VulkanResourceLayout) !void {
        const sampler_info = std.mem.zeroInit(vk.VkSamplerCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = vk.VK_FILTER_NEAREST,
            .minFilter = vk.VK_FILTER_NEAREST,
            .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        });
        try check(vk.vkCreateSampler(self.ctx.device, &sampler_info, null, &self.sampler_nearest));

        const linear_sampler_info = std.mem.zeroInit(vk.VkSamplerCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = vk.VK_FILTER_LINEAR,
            .minFilter = vk.VK_FILTER_LINEAR,
            .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        });
        try check(vk.vkCreateSampler(self.ctx.device, &linear_sampler_info, null, &self.sampler_linear));
    }

    fn initDescriptorSetLayout(self: *VulkanResourceLayout) !void {
        var bindings: [4]vk.VkDescriptorSetLayoutBinding = undefined;
        bindings[contract.CURVE_BINDING] = std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = contract.CURVE_BINDING,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        });
        bindings[contract.CURVE_BINDING].pImmutableSamplers = &self.sampler_nearest;
        bindings[contract.BAND_BINDING] = std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = contract.BAND_BINDING,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        });
        bindings[contract.BAND_BINDING].pImmutableSamplers = &self.sampler_nearest;
        bindings[contract.LAYER_INFO_BINDING] = std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = contract.LAYER_INFO_BINDING,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        });
        bindings[contract.LAYER_INFO_BINDING].pImmutableSamplers = &self.sampler_nearest;
        bindings[contract.IMAGE_BINDING] = std.mem.zeroInit(vk.VkDescriptorSetLayoutBinding, .{
            .binding = contract.IMAGE_BINDING,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        });
        bindings[contract.IMAGE_BINDING].pImmutableSamplers = &self.sampler_linear;

        const dsl_info = std.mem.zeroInit(vk.VkDescriptorSetLayoutCreateInfo, .{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = 4,
            .pBindings = &bindings,
        });
        try check(vk.vkCreateDescriptorSetLayout(self.ctx.device, &dsl_info, null, &self.desc_set_layout));
    }

    pub fn deinit(self: *VulkanResourceLayout) void {
        // Reads `ctx.device` only inside the non-null branches, so a
        // zero-value (never-init'd) layout deinits to a safe no-op.
        if (self.desc_set_layout != null) vk.vkDestroyDescriptorSetLayout(self.ctx.device, self.desc_set_layout, null);
        if (self.sampler_linear != null) vk.vkDestroySampler(self.ctx.device, self.sampler_linear, null);
        if (self.sampler_nearest != null) vk.vkDestroySampler(self.ctx.device, self.sampler_nearest, null);
        self.desc_set_layout = null;
        self.sampler_linear = null;
        self.sampler_nearest = null;
    }
};

const interface = @import("render/interface.zig");

pub const adapter = struct {
    pub const cpu = @import("render/adapter/cpu.zig");
    pub const gl = @import("render/adapter/gl.zig");
    pub const vulkan = @import("render/adapter/vulkan.zig");
};

pub const BackendKind = interface.BackendKind;
pub const Renderer = interface.Renderer;
pub const ResourceUploader = interface.ResourceUploader;

pub const CpuRenderer = adapter.cpu.CpuRenderer;
pub const GlRenderer = adapter.gl.Renderer;
pub const ThreadPool = @import("thread_pool.zig").ThreadPool;
pub const VulkanContext = adapter.vulkan.VulkanContext;
pub const VulkanRenderer = adapter.vulkan.Renderer;

const interface = @import("render/interface.zig");

pub const adapter = struct {
    pub const cpu = @import("render/adapter/cpu.zig");
    pub const gl = @import("render/adapter/gl.zig");
    pub const gles3 = @import("render/adapter/gles3.zig");
    pub const vulkan = @import("render/adapter/vulkan.zig");
};

pub const BackendKind = interface.BackendKind;
pub const Renderer = interface.Renderer;

pub const CpuRenderer = adapter.cpu.CpuRenderer;
pub const Gl33Renderer = adapter.gl.Gl33Renderer;
pub const Gl44Renderer = adapter.gl.Gl44Renderer;
pub const Gles3Renderer = adapter.gles3.Renderer;
pub const ThreadPool = @import("thread_pool.zig").ThreadPool;
pub const VulkanContext = adapter.vulkan.VulkanContext;
pub const VulkanRenderer = adapter.vulkan.Renderer;

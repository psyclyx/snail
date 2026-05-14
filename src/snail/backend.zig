const core = @import("core.zig");

pub const Kind = core.BackendKind;

pub const gl = struct {
    pub const Renderer = core.GlRenderer;
};

pub const vulkan = struct {
    pub const Renderer = core.VulkanRenderer;
    pub const Context = core.VulkanContext;
};

pub const cpu = struct {
    pub const Renderer = core.CpuRenderer;
};

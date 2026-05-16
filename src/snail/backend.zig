const render_mod = @import("render.zig");

pub const Kind = enum(c_int) {
    gl = 0,
    vulkan = 1,
    cpu = 2,
};

pub const gl = struct {
    pub const Renderer = render_mod.GlRenderer;
};

pub const vulkan = struct {
    pub const Renderer = render_mod.VulkanRenderer;
    pub const Context = render_mod.VulkanContext;
};

pub const cpu = struct {
    pub const Renderer = render_mod.CpuRenderer;
};

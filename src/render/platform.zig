const std = @import("std");
const build_options = @import("build_options");
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;

pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "");
    @cInclude("GLFW/glfw3.h");
});

pub const gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
});

var window: ?*c.GLFWwindow = null;
var monitor_changed: bool = false;

fn onWindowMoved(_: ?*c.GLFWwindow, _: c_int, _: c_int) callconv(.c) void {
    monitor_changed = true;
}

pub fn init(width: u32, height: u32, title: [*:0]const u8) !void {
    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;

    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    if (!build_options.force_gl33) {
        // Try GL 4.4 first
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 4);
        window = c.glfwCreateWindow(@intCast(width), @intCast(height), title, null, null);
    }

    if (window == null) {
        // Fall back to (or start at) GL 3.3
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
        window = c.glfwCreateWindow(@intCast(width), @intCast(height), title, null, null)
            orelse return error.WindowCreateFailed;
    }

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);
    _ = c.glfwSetWindowPosCallback(window, onWindowMoved);
}

/// Returns true once after the window has moved (which may indicate a monitor change).
pub fn consumeMonitorChanged() bool {
    const v = monitor_changed;
    monitor_changed = false;
    return v;
}

/// Detect the subpixel order for the monitor currently containing the window centre.
/// Applies a rotation correction if the monitor's physical and video orientations differ
/// (i.e. the display is rotated 90°/270°). Falls back to `base` when uncertain.
pub fn detectCurrentMonitorSubpixelOrder(base: SubpixelOrder) SubpixelOrder {
    const win = window orelse return base;
    var wx: c_int = 0;
    var wy: c_int = 0;
    c.glfwGetWindowPos(win, &wx, &wy);
    var ww: c_int = 0;
    var wh: c_int = 0;
    c.glfwGetWindowSize(win, &ww, &wh);
    const cx: c_int = wx + @divTrunc(ww, 2);
    const cy: c_int = wy + @divTrunc(wh, 2);

    var count: c_int = 0;
    const monitors = c.glfwGetMonitors(&count) orelse return base;
    for (0..@as(usize, @intCast(count))) |i| {
        const m = monitors[i];
        var mx: c_int = 0;
        var my: c_int = 0;
        c.glfwGetMonitorPos(m, &mx, &my);
        const mode = c.glfwGetVideoMode(m) orelse continue;
        if (cx >= mx and cx < mx + mode[0].width and
            cy >= my and cy < my + mode[0].height)
        {
            // If physical size orientation differs from video mode orientation the
            // monitor is rotated; flip between horizontal and vertical subpixel orders.
            var pw: c_int = 0;
            var ph: c_int = 0;
            c.glfwGetMonitorPhysicalSize(m, &pw, &ph);
            const vid_landscape = mode[0].width > mode[0].height;
            const phy_landscape = pw > ph;
            if (vid_landscape != phy_landscape) {
                return switch (base) {
                    .rgb  => .vrgb,
                    .bgr  => .vbgr,
                    .vrgb => .rgb,
                    .vbgr => .bgr,
                    .none => .none,
                };
            }
            return base;
        }
    }
    return base;
}

pub fn deinit() void {
    if (window) |w| c.glfwDestroyWindow(w);
    c.glfwTerminate();
}

pub fn shouldClose() bool {
    c.glfwPollEvents();
    return c.glfwWindowShouldClose(window) == c.GLFW_TRUE;
}

pub fn clear(r: f32, g: f32, b: f32, a: f32) void {
    gl.glClearColor(r, g, b, a);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
}

pub fn swapBuffers() void {
    if (window) |w| c.glfwSwapBuffers(w);
}

pub fn getWindowSize() [2]u32 {
    var w: c_int = 0;
    var h: c_int = 0;
    if (window) |win| c.glfwGetFramebufferSize(win, &w, &h);
    return .{ @intCast(w), @intCast(h) };
}

pub fn getTime() f64 {
    return c.glfwGetTime();
}

pub fn isKeyDown(key: c_int) bool {
    if (window) |w| return c.glfwGetKey(w, key) == c.GLFW_PRESS;
    return false;
}

pub fn getWindow() ?*c.GLFWwindow {
    return window;
}

var prev_keys: [512]bool = .{false} ** 512;

pub fn isKeyPressed(key: c_int) bool {
    const idx: usize = @intCast(@as(u32, @bitCast(key)));
    if (idx >= 512) return false;
    const down = isKeyDown(key);
    const was_down = prev_keys[idx];
    prev_keys[idx] = down;
    return down and !was_down;
}

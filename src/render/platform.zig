const std = @import("std");

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

pub fn init(width: u32, height: u32, title: [*:0]const u8) !void {
    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;

    // Try GL 4.4 first, fall back to 3.3
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 4);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    window = c.glfwCreateWindow(@intCast(width), @intCast(height), title, null, null);

    if (window == null) {
        // Retry with GL 3.3
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
        window = c.glfwCreateWindow(@intCast(width), @intCast(height), title, null, null)
            orelse return error.WindowCreateFailed;
    }

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);
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

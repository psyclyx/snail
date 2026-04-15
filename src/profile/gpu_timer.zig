const std = @import("std");
const build_options = @import("build_options");
const profiling_enabled = build_options.enable_profiling;
const gl = @import("../render/gl.zig").gl;
const timer = @import("timer.zig");

pub const GpuTimer = if (profiling_enabled) struct {
    queries: [2]gl.GLuint = .{ 0, 0 },
    current: u1 = 0,
    label: []const u8,
    initialized: bool = false,

    pub fn init(comptime label: []const u8) GpuTimer {
        var t = GpuTimer{ .label = label };
        gl.glGenQueries(2, &t.queries);
        return t;
    }

    pub fn deinit(self: *GpuTimer) void {
        if (self.queries[0] != 0) gl.glDeleteQueries(2, &self.queries);
    }

    pub fn beginQuery(self: *GpuTimer) void {
        // Read previous frame's result (double-buffered)
        if (self.initialized) {
            const prev = self.current ^ 1;
            var available: gl.GLint = 0;
            gl.glGetQueryObjectiv(self.queries[prev], gl.GL_QUERY_RESULT_AVAILABLE, &available);
            if (available != 0) {
                var elapsed_ns: gl.GLuint64 = 0;
                gl.glGetQueryObjectui64v(self.queries[prev], gl.GL_QUERY_RESULT, &elapsed_ns);
                const elapsed_us: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;
                timer.stats.record(self.label, elapsed_us);
            }
        }

        gl.glBeginQuery(gl.GL_TIME_ELAPSED, self.queries[self.current]);
    }

    pub fn endQuery(self: *GpuTimer) void {
        gl.glEndQuery(gl.GL_TIME_ELAPSED);
        self.current ^= 1;
        self.initialized = true;
    }
} else struct {
    pub fn init(comptime _: []const u8) GpuTimer {
        return .{};
    }
    pub fn deinit(_: *GpuTimer) void {}
    pub fn beginQuery(_: *GpuTimer) void {}
    pub fn endQuery(_: *GpuTimer) void {}
};

pub const ColorEncoding = enum {
    linear,
    srgb,
};

pub const Info = struct {
    logical_size: [2]u32 = .{ 0, 0 },
    framebuffer_size: [2]u32 = .{ 0, 0 },
    buffer_scale: u32 = 1,
    framebuffer_encoding: ColorEncoding = .srgb,
    will_resample: bool = false,

    pub fn scale(self: Info) [2]f32 {
        return .{
            axisScale(self.logical_size[0], self.framebuffer_size[0]),
            axisScale(self.logical_size[1], self.framebuffer_size[1]),
        };
    }

    fn axisScale(logical: u32, framebuffer: u32) f32 {
        if (logical == 0) return 1.0;
        return @as(f32, @floatFromInt(framebuffer)) / @as(f32, @floatFromInt(logical));
    }
};

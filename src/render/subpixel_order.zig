pub const SubpixelOrder = enum(i32) {
    none = 0,
    rgb = 1,
    bgr = 2,
    vrgb = 3,
    vbgr = 4,

    pub fn name(self: SubpixelOrder) []const u8 {
        return switch (self) {
            .none => "none",
            .rgb  => "RGB",
            .bgr  => "BGR",
            .vrgb => "VRGB",
            .vbgr => "VBGR",
        };
    }
};

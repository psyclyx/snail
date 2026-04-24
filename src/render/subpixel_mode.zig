pub const SubpixelMode = enum(i32) {
    safe = 0,
    legacy_unsafe = 1,

    pub fn name(self: SubpixelMode) []const u8 {
        return switch (self) {
            .safe => "safe",
            .legacy_unsafe => "legacy-unsafe",
        };
    }
};

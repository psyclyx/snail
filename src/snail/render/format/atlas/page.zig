const std = @import("std");

pub const AtlasPage = struct {
    allocator: std.mem.Allocator,
    ref_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    curve_data: []u16,
    curve_width: u32,
    curve_height: u32,
    band_data: []u16,
    band_width: u32,
    band_height: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        curve_data: []u16,
        curve_width: u32,
        curve_height: u32,
        band_data: []u16,
        band_width: u32,
        band_height: u32,
    ) !*AtlasPage {
        const page = try allocator.create(AtlasPage);
        page.* = .{
            .allocator = allocator,
            .curve_data = curve_data,
            .curve_width = curve_width,
            .curve_height = curve_height,
            .band_data = band_data,
            .band_width = band_width,
            .band_height = band_height,
        };
        return page;
    }

    pub fn retain(self: *AtlasPage) *AtlasPage {
        _ = self.ref_count.fetchAdd(1, .monotonic);
        return self;
    }

    pub fn release(self: *AtlasPage) void {
        if (self.ref_count.fetchSub(1, .acq_rel) == 1) {
            self.allocator.free(self.curve_data);
            self.allocator.free(self.band_data);
            self.allocator.destroy(self);
        }
    }

    pub fn textureBytes(self: *const AtlasPage) usize {
        return self.curve_data.len * @sizeOf(u16) + self.band_data.len * @sizeOf(u16);
    }

    pub fn curveTextureBytes(self: *const AtlasPage) usize {
        return self.curve_data.len * @sizeOf(u16);
    }

    pub fn bandTextureBytes(self: *const AtlasPage) usize {
        return self.band_data.len * @sizeOf(u16);
    }
};

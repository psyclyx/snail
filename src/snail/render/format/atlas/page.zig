const std = @import("std");

pub const PageFingerprint = struct {
    layout: u64 = 0,
    content: u64 = 0,

    pub fn eql(a: PageFingerprint, b: PageFingerprint) bool {
        return a.layout == b.layout and a.content == b.content;
    }
};

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

    pub fn fingerprint(self: *const AtlasPage) PageFingerprint {
        const layout = pageLayoutHash(self);
        var content = std.hash.Wyhash.hash(layout, std.mem.sliceAsBytes(self.curve_data));
        content = std.hash.Wyhash.hash(content, std.mem.sliceAsBytes(self.band_data));
        return .{ .layout = layout, .content = content };
    }
};

fn pageLayoutHash(page: *const AtlasPage) u64 {
    var hash = mix64(0x9f26_9d6e_2ec5_7f4d, page.curve_width);
    hash = mix64(hash, page.curve_height);
    hash = mix64(hash, page.band_width);
    hash = mix64(hash, page.band_height);
    hash = mix64(hash, page.curve_data.len);
    hash = mix64(hash, page.band_data.len);
    return hash;
}

fn mix64(seed: u64, value: anytype) u64 {
    var x = seed ^ @as(u64, @intCast(value));
    x +%= 0x9e37_79b9_7f4a_7c15;
    x = (x ^ (x >> 30)) *% 0xbf58_476d_1ce4_e5b9;
    x = (x ^ (x >> 27)) *% 0x94d0_49bb_1331_11eb;
    return x ^ (x >> 31);
}

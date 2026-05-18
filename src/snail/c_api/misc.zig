const common = @import("common.zig");
const std = common.std;
const resource_key = common.resource_key;
const SnailResourceKey = common.SnailResourceKey;
const SnailResourceFootprint = common.SnailResourceFootprint;

pub export fn snail_resource_footprint_used_bytes(footprint: SnailResourceFootprint) usize {
    return footprint.curve_bytes_used +
        footprint.band_bytes_used +
        footprint.layer_info_bytes_used +
        footprint.image_bytes_used;
}

pub export fn snail_resource_footprint_allocated_bytes(footprint: SnailResourceFootprint) usize {
    return footprint.curve_bytes_allocated +
        footprint.band_bytes_allocated +
        footprint.layer_info_bytes_allocated +
        footprint.image_bytes_allocated;
}

pub export fn snail_resource_key_from_bytes(data: [*]const u8, len: usize) SnailResourceKey {
    return resource_key.ResourceKey.fromName(data[0..len]).toOpaque();
}

pub export fn snail_resource_key_from_cstr(data: [*:0]const u8) SnailResourceKey {
    return resource_key.ResourceKey.fromName(std.mem.span(data)).toOpaque();
}

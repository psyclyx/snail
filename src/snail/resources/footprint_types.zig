/// Allocation-free estimate of upload-source bytes and backend texture bytes.
/// `*_used` is the payload bytes in the source resource data; `*_allocated`
/// is the texture storage implied by Snail's packing policy, excluding driver
/// alignment and API object overhead.
pub const ResourceFootprint = struct {
    curve_bytes_used: usize = 0,
    curve_bytes_allocated: usize = 0,
    band_bytes_used: usize = 0,
    band_bytes_allocated: usize = 0,
    layer_info_bytes_used: usize = 0,
    layer_info_bytes_allocated: usize = 0,
    image_bytes_used: usize = 0,
    image_bytes_allocated: usize = 0,

    pub fn usedBytes(self: ResourceFootprint) usize {
        return self.curve_bytes_used +
            self.band_bytes_used +
            self.layer_info_bytes_used +
            self.image_bytes_used;
    }

    pub fn allocatedBytes(self: ResourceFootprint) usize {
        return self.curve_bytes_allocated +
            self.band_bytes_allocated +
            self.layer_info_bytes_allocated +
            self.image_bytes_allocated;
    }

    pub fn add(self: *ResourceFootprint, other: ResourceFootprint) void {
        self.curve_bytes_used += other.curve_bytes_used;
        self.curve_bytes_allocated += other.curve_bytes_allocated;
        self.band_bytes_used += other.band_bytes_used;
        self.band_bytes_allocated += other.band_bytes_allocated;
        self.layer_info_bytes_used += other.layer_info_bytes_used;
        self.layer_info_bytes_allocated += other.layer_info_bytes_allocated;
        self.image_bytes_used += other.image_bytes_used;
        self.image_bytes_allocated += other.image_bytes_allocated;
    }
};

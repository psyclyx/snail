const common = @import("common.zig");
const std = common.std;
const snail = common.snail;
const createHandle = common.createHandle;
const allocatorForHandle = common.allocatorForHandle;
const mapError = common.mapError;
const SnailAllocator = common.SnailAllocator;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SNAIL_ERR_INVALID_ARGUMENT = common.SNAIL_ERR_INVALID_ARGUMENT;
const SnailResourceFootprint = common.SnailResourceFootprint;
const fromResourceFootprint = common.fromResourceFootprint;
const ImageImpl = common.ImageImpl;
const destroyHandle = common.destroyHandle;

// Image

pub export fn snail_image_init_srgba8(
    alloc_ptr: ?*const SnailAllocator,
    width: u32,
    height: u32,
    pixels: ?[*]const u8,
    pixel_len: usize,
    out: *?*ImageImpl,
) c_int {
    const px_count = std.math.mul(usize, width, height) catch return SNAIL_ERR_INVALID_ARGUMENT;
    const byte_count = std.math.mul(usize, px_count, 4) catch return SNAIL_ERR_INVALID_ARGUMENT;
    if (pixel_len != byte_count) return SNAIL_ERR_INVALID_ARGUMENT;
    const pixel_ptr = pixels orelse return SNAIL_ERR_INVALID_ARGUMENT;
    const impl = createHandle(ImageImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const img = snail.Image.initSrgba8(allocator, width, height, pixel_ptr[0..pixel_len]) catch |err| {
        destroyHandle(impl);
        return mapError(err);
    };
    impl.inner = img;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_image_deinit(image: ?*ImageImpl) void {
    if (image) |img| {
        img.inner.deinit();
        destroyHandle(img);
    }
}

pub export fn snail_image_width(image: *const ImageImpl) u32 {
    return image.inner.width;
}

pub export fn snail_image_height(image: *const ImageImpl) u32 {
    return image.inner.height;
}

pub export fn snail_image_upload_footprint(image: *const ImageImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(image.inner.uploadFootprint());
}

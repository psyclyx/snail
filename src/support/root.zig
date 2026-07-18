const std = @import("std");
const snail = @import("snail");

pub const screenshot = @import("screenshot.zig");
pub const gl = @import("gl.zig").gl;

pub const Picture = @import("picture.zig").Picture;
pub const ShapedRunCache = @import("shaped_run_cache.zig").ShapedRunCache;

const path_shape = @import("path_shape.zig");
pub const placeRect = path_shape.placeRect;
pub const placeRectUniform = path_shape.placeRectUniform;
pub const unitEllipsePath = path_shape.unitEllipsePath;
pub const unitRectPath = path_shape.unitRectPath;
pub const unitRoundedRectPath = path_shape.unitRoundedRectPath;
pub const unitRoundedRectPathFor = path_shape.unitRoundedRectPathFor;
pub const unitStrokeWidth = path_shape.unitStrokeWidth;

/// Demo adapter from the allocation-oriented `snail.placeRunAlloc` API to the
/// demo's owned shape-slice container.
pub fn placeRun(
    allocator: std.mem.Allocator,
    shaped: *const snail.ShapedText,
    faces: ?*const snail.Faces,
    placement: snail.RunPlacement,
) snail.PlaceRunAllocError!Picture {
    const shapes = try snail.placeRunAlloc(allocator, shaped, faces, placement);
    return Picture.fromOwnedSlice(allocator, shapes);
}

test {
    _ = @import("picture.zig");
    _ = @import("path_shape.zig");
    _ = @import("shaped_run_cache.zig");
}

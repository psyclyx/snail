const core = @import("path/core.zig");
const picture = @import("path/picture.zig");
const batch = @import("path/batch.zig");

pub const Path = core.Path;
pub const PathPicture = picture.PathPicture;
pub const PathPictureBuilder = picture.PathPictureBuilder;
pub const PathPictureDebugView = picture.PathPictureDebugView;
pub const PathPictureBoundsOverlayOptions = picture.PathPictureBoundsOverlayOptions;
pub const PathBatch = batch.PathBatch;

pub const PATH_PAINT_INFO_WIDTH: u32 = picture.PATH_PAINT_INFO_WIDTH;
pub const PATH_PAINT_TEXELS_PER_RECORD: u32 = picture.PATH_PAINT_TEXELS_PER_RECORD;
pub const PATH_PAINT_TAG_SOLID: f32 = picture.PATH_PAINT_TAG_SOLID;
pub const PATH_PAINT_TAG_LINEAR_GRADIENT: f32 = picture.PATH_PAINT_TAG_LINEAR_GRADIENT;
pub const PATH_PAINT_TAG_RADIAL_GRADIENT: f32 = picture.PATH_PAINT_TAG_RADIAL_GRADIENT;
pub const PATH_PAINT_TAG_IMAGE: f32 = picture.PATH_PAINT_TAG_IMAGE;
pub const PATH_PAINT_TAG_COMPOSITE_GROUP: f32 = picture.PATH_PAINT_TAG_COMPOSITE_GROUP;

pub const PATH_WORDS_PER_VERTEX = batch.PATH_WORDS_PER_VERTEX;
pub const PATH_VERTICES_PER_SHAPE = batch.PATH_VERTICES_PER_SHAPE;
pub const PATH_WORDS_PER_SHAPE = batch.PATH_WORDS_PER_SHAPE;

test {
    _ = @import("path/tests.zig");
}

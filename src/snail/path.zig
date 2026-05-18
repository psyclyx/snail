const core = @import("path/core.zig");
const picture = @import("path/picture.zig");
const batch = @import("path/batch.zig");

pub const Path = core.Path;
pub const PathPicture = picture.PathPicture;
pub const PathPictureBuilder = picture.PathPictureBuilder;
pub const PathPictureDebugView = picture.PathPictureDebugView;
pub const PathPictureBoundsOverlayOptions = picture.PathPictureBoundsOverlayOptions;
pub const PathBatch = batch.PathBatch;

pub const PATH_WORDS_PER_VERTEX = batch.PATH_WORDS_PER_VERTEX;
pub const PATH_VERTICES_PER_SHAPE = batch.PATH_VERTICES_PER_SHAPE;
pub const PATH_WORDS_PER_SHAPE = batch.PATH_WORDS_PER_SHAPE;

test {
    _ = @import("path/tests.zig");
}

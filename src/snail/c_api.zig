//! C API for snail's public Zig resource model.
//! All exported functions use opaque handles and explicit ownership.

pub const common = @import("c_api/common.zig");
pub const misc = @import("c_api/misc.zig");
pub const font = @import("c_api/font.zig");
pub const text = @import("c_api/text.zig");
pub const image = @import("c_api/image.zig");
pub const path = @import("c_api/path.zig");
pub const scene = @import("c_api/scene.zig");
pub const resources = @import("c_api/resources.zig");
pub const render_backends = @import("c_api/render_backends.zig");
pub const shaders = @import("c_api/shaders.zig");
pub const render = @import("c_api/render.zig");
pub const constants = @import("c_api/constants.zig");

comptime {
    _ = misc;
    _ = font;
    _ = text;
    _ = image;
    _ = path;
    _ = scene;
    _ = resources;
    _ = render_backends;
    _ = shaders;
    _ = render;
    _ = constants;
}

test {
    _ = @import("c_api/tests.zig");
}

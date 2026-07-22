//! Build-wired implementation support for `snail-raster`.
//!
//! This is deliberately not exported from the public `snail` module. The
//! software renderer needs the host implementation of the runtime autohint
//! warp, while ordinary consumers need only analyzer inputs, policy values,
//! packed records, and shader contracts.

pub const autohint = struct {
    pub const warp = @import("font/autohint/warp.zig");
};

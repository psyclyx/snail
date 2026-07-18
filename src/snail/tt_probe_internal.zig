//! Private compiler-module surface for the TrueType research probe.
//! Not imported by the public `snail` module.

pub const hint = @import("font/truetype/hint.zig");
pub const vm = @import("font/truetype/vm.zig");
pub const ttf = @import("font/ttf.zig");

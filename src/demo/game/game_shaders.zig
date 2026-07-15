//! SPIR-V for the game's custom Vulkan material shader, compiled at build time
//! from `glsl/game_material.{vert,frag}` (which #include snail's coverage +
//! records sources) and injected as anonymous imports by the build.

const raw_vert = @embedFile("game_material.vert.spv");
const raw_frag = @embedFile("game_material.frag.spv");

const aligned_vert: [raw_vert.len]u8 align(4) = raw_vert.*;
const aligned_frag: [raw_frag.len]u8 align(4) = raw_frag.*;

pub const vert_spv: []align(4) const u8 = &aligned_vert;
pub const frag_spv: []align(4) const u8 = &aligned_frag;

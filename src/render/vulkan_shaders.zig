//! SPIR-V shader bytecode for the Vulkan backend.
//! The .spv files are compiled from GLSL 450 sources at build time via glslc
//! and injected as anonymous imports by the build system.
//! Data is forced to 4-byte alignment as required by VkShaderModuleCreateInfo.pCode.

const raw_vert = @embedFile("snail.vert.spv");
const raw_frag = @embedFile("snail.frag.spv");
const raw_frag_text_sp = @embedFile("snail_text_subpixel.frag.spv");
const raw_frag_text_sp_dual = @embedFile("snail_text_subpixel_dual.frag.spv");
const raw_sprite_vert = @embedFile("sprite.vert.spv");
const raw_sprite_frag = @embedFile("sprite.frag.spv");

// Force 4-byte alignment for SPIR-V (Vulkan requires aligned pCode)
const aligned_vert: [raw_vert.len]u8 align(4) = raw_vert.*;
const aligned_frag: [raw_frag.len]u8 align(4) = raw_frag.*;
const aligned_frag_text_sp: [raw_frag_text_sp.len]u8 align(4) = raw_frag_text_sp.*;
const aligned_frag_text_sp_dual: [raw_frag_text_sp_dual.len]u8 align(4) = raw_frag_text_sp_dual.*;
const aligned_sprite_vert: [raw_sprite_vert.len]u8 align(4) = raw_sprite_vert.*;
const aligned_sprite_frag: [raw_sprite_frag.len]u8 align(4) = raw_sprite_frag.*;

pub const vert_spv: []align(4) const u8 = &aligned_vert;
pub const frag_spv: []align(4) const u8 = &aligned_frag;
pub const frag_text_subpixel_spv: []align(4) const u8 = &aligned_frag_text_sp;
pub const frag_text_subpixel_dual_spv: []align(4) const u8 = &aligned_frag_text_sp_dual;
pub const sprite_vert_spv: []align(4) const u8 = &aligned_sprite_vert;
pub const sprite_frag_spv: []align(4) const u8 = &aligned_sprite_frag;

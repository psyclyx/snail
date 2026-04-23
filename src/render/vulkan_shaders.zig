//! SPIR-V shader bytecode for the Vulkan backend.
//! The .spv files are compiled from GLSL 450 sources at build time via glslc
//! and injected as anonymous imports by the build system.
//! Data is forced to 4-byte alignment as required by VkShaderModuleCreateInfo.pCode.

const raw_vert = @embedFile("slug.vert.spv");
const raw_frag = @embedFile("slug.frag.spv");
const raw_frag_sp = @embedFile("slug_subpixel.frag.spv");
const raw_vector_vert = @embedFile("vector.vert.spv");
const raw_vector_frag = @embedFile("vector.frag.spv");
const raw_sprite_vert = @embedFile("sprite.vert.spv");
const raw_sprite_frag = @embedFile("sprite.frag.spv");

// Force 4-byte alignment for SPIR-V (Vulkan requires aligned pCode)
const aligned_vert: [raw_vert.len]u8 align(4) = raw_vert.*;
const aligned_frag: [raw_frag.len]u8 align(4) = raw_frag.*;
const aligned_frag_sp: [raw_frag_sp.len]u8 align(4) = raw_frag_sp.*;
const aligned_vector_vert: [raw_vector_vert.len]u8 align(4) = raw_vector_vert.*;
const aligned_vector_frag: [raw_vector_frag.len]u8 align(4) = raw_vector_frag.*;
const aligned_sprite_vert: [raw_sprite_vert.len]u8 align(4) = raw_sprite_vert.*;
const aligned_sprite_frag: [raw_sprite_frag.len]u8 align(4) = raw_sprite_frag.*;

pub const vert_spv: []align(4) const u8 = &aligned_vert;
pub const frag_spv: []align(4) const u8 = &aligned_frag;
pub const frag_subpixel_spv: []align(4) const u8 = &aligned_frag_sp;
pub const vector_vert_spv: []align(4) const u8 = &aligned_vector_vert;
pub const vector_frag_spv: []align(4) const u8 = &aligned_vector_frag;
pub const sprite_vert_spv: []align(4) const u8 = &aligned_sprite_vert;
pub const sprite_frag_spv: []align(4) const u8 = &aligned_sprite_frag;

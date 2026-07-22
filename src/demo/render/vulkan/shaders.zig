//! SPIR-V shader bytecode for the reference Vulkan renderer.
//! The .spv files are compiled from GLSL 450 sources at build time via slangc
//! and injected as anonymous imports by the build system.
//! Data is forced to 4-byte alignment as required by VkShaderModuleCreateInfo.pCode.

const raw_vert = @embedFile("snail.vert.spv");
const raw_vert_autohint = @embedFile("snail_autohint.vert.spv");
const raw_frag_text = @embedFile("snail_text.frag.spv");
const raw_frag_colr = @embedFile("snail_colr.frag.spv");
const raw_frag_path = @embedFile("snail_path.frag.spv");
const raw_frag_tt_hinted_text = @embedFile("snail_tt_hinted_text.frag.spv");
const raw_frag_autohint = @embedFile("snail_autohint.frag.spv");
const raw_frag_text_sp_dual = @embedFile("snail_text_subpixel_dual.frag.spv");
// Native-Slang families (Slang cutover): compiled from
// src/snail/shader/slang/families/*.slang. Fragment-only families pair
// with the native text vertex module.
const raw_vert_text_native = @embedFile("snail_text_native.vert.spv");
const raw_frag_text_native = @embedFile("snail_text_native.frag.spv");
const raw_frag_colr_native = @embedFile("snail_colr_native.frag.spv");
const raw_frag_path_native = @embedFile("snail_path_native.frag.spv");
const raw_frag_tt_hinted_native = @embedFile("snail_tt_hinted_native.frag.spv");
const raw_vert_autohint_native = @embedFile("snail_autohint_native.vert.spv");
const raw_frag_autohint_native = @embedFile("snail_autohint_native.frag.spv");
const raw_frag_subpixel_native = @embedFile("snail_subpixel_native.frag.spv");

// Force 4-byte alignment for SPIR-V (Vulkan requires aligned pCode)
const aligned_vert: [raw_vert.len]u8 align(4) = raw_vert.*;
const aligned_vert_autohint: [raw_vert_autohint.len]u8 align(4) = raw_vert_autohint.*;
const aligned_frag_text: [raw_frag_text.len]u8 align(4) = raw_frag_text.*;
const aligned_frag_colr: [raw_frag_colr.len]u8 align(4) = raw_frag_colr.*;
const aligned_frag_path: [raw_frag_path.len]u8 align(4) = raw_frag_path.*;
const aligned_frag_tt_hinted_text: [raw_frag_tt_hinted_text.len]u8 align(4) = raw_frag_tt_hinted_text.*;
const aligned_frag_autohint: [raw_frag_autohint.len]u8 align(4) = raw_frag_autohint.*;
const aligned_frag_text_sp_dual: [raw_frag_text_sp_dual.len]u8 align(4) = raw_frag_text_sp_dual.*;
const aligned_vert_text_native: [raw_vert_text_native.len]u8 align(4) = raw_vert_text_native.*;
const aligned_frag_text_native: [raw_frag_text_native.len]u8 align(4) = raw_frag_text_native.*;
const aligned_frag_colr_native: [raw_frag_colr_native.len]u8 align(4) = raw_frag_colr_native.*;
const aligned_frag_path_native: [raw_frag_path_native.len]u8 align(4) = raw_frag_path_native.*;
const aligned_frag_tt_hinted_native: [raw_frag_tt_hinted_native.len]u8 align(4) = raw_frag_tt_hinted_native.*;
const aligned_vert_autohint_native: [raw_vert_autohint_native.len]u8 align(4) = raw_vert_autohint_native.*;
const aligned_frag_autohint_native: [raw_frag_autohint_native.len]u8 align(4) = raw_frag_autohint_native.*;
const aligned_frag_subpixel_native: [raw_frag_subpixel_native.len]u8 align(4) = raw_frag_subpixel_native.*;

pub const vert_spv: []align(4) const u8 = &aligned_vert;
pub const vert_autohint_spv: []align(4) const u8 = &aligned_vert_autohint;
pub const frag_text_spv: []align(4) const u8 = &aligned_frag_text;
pub const frag_colr_spv: []align(4) const u8 = &aligned_frag_colr;
pub const frag_path_spv: []align(4) const u8 = &aligned_frag_path;
pub const frag_tt_hinted_text_spv: []align(4) const u8 = &aligned_frag_tt_hinted_text;
pub const frag_autohint_spv: []align(4) const u8 = &aligned_frag_autohint;
pub const frag_text_subpixel_dual_spv: []align(4) const u8 = &aligned_frag_text_sp_dual;
pub const vert_text_native_spv: []align(4) const u8 = &aligned_vert_text_native;
pub const frag_text_native_spv: []align(4) const u8 = &aligned_frag_text_native;
pub const frag_colr_native_spv: []align(4) const u8 = &aligned_frag_colr_native;
pub const frag_path_native_spv: []align(4) const u8 = &aligned_frag_path_native;
pub const frag_tt_hinted_native_spv: []align(4) const u8 = &aligned_frag_tt_hinted_native;
pub const vert_autohint_native_spv: []align(4) const u8 = &aligned_vert_autohint_native;
pub const frag_autohint_native_spv: []align(4) const u8 = &aligned_frag_autohint_native;
pub const frag_subpixel_native_spv: []align(4) const u8 = &aligned_frag_subpixel_native;

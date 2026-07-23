//! SPIR-V shader bytecode for the reference Vulkan renderer.
//! Compiled at build time by slangc from the native-Slang family sources
//! (src/snail/shader/slang/families/*.slang) and injected as anonymous
//! imports by the build system. Fragment-only families pair with the text
//! vertex module.
//! Data is forced to 4-byte alignment as required by VkShaderModuleCreateInfo.pCode.

const raw_vert_text_native = @embedFile("snail_text_native.vert.spv");
const raw_frag_text_native = @embedFile("snail_text_native.frag.spv");
const raw_frag_colr_native = @embedFile("snail_colr_native.frag.spv");
const raw_frag_path_native = @embedFile("snail_path_native.frag.spv");
const raw_frag_tt_hinted_native = @embedFile("snail_tt_hinted_native.frag.spv");
const raw_vert_autohint_native = @embedFile("snail_autohint_native.vert.spv");
const raw_frag_autohint_native = @embedFile("snail_autohint_native.frag.spv");
const raw_frag_subpixel_native = @embedFile("snail_subpixel_native.frag.spv");
const raw_frag_tt_hinted_subpixel_native = @embedFile("snail_tt_hinted_subpixel_native.frag.spv");
const raw_frag_autohint_subpixel_native = @embedFile("snail_autohint_subpixel_native.frag.spv");

// Force 4-byte alignment for SPIR-V (Vulkan requires aligned pCode)
const aligned_vert_text_native: [raw_vert_text_native.len]u8 align(4) = raw_vert_text_native.*;
const aligned_frag_text_native: [raw_frag_text_native.len]u8 align(4) = raw_frag_text_native.*;
const aligned_frag_colr_native: [raw_frag_colr_native.len]u8 align(4) = raw_frag_colr_native.*;
const aligned_frag_path_native: [raw_frag_path_native.len]u8 align(4) = raw_frag_path_native.*;
const aligned_frag_tt_hinted_native: [raw_frag_tt_hinted_native.len]u8 align(4) = raw_frag_tt_hinted_native.*;
const aligned_vert_autohint_native: [raw_vert_autohint_native.len]u8 align(4) = raw_vert_autohint_native.*;
const aligned_frag_autohint_native: [raw_frag_autohint_native.len]u8 align(4) = raw_frag_autohint_native.*;
const aligned_frag_subpixel_native: [raw_frag_subpixel_native.len]u8 align(4) = raw_frag_subpixel_native.*;
const aligned_frag_tt_hinted_subpixel_native: [raw_frag_tt_hinted_subpixel_native.len]u8 align(4) = raw_frag_tt_hinted_subpixel_native.*;
const aligned_frag_autohint_subpixel_native: [raw_frag_autohint_subpixel_native.len]u8 align(4) = raw_frag_autohint_subpixel_native.*;

pub const vert_text_native_spv: []align(4) const u8 = &aligned_vert_text_native;
pub const frag_text_native_spv: []align(4) const u8 = &aligned_frag_text_native;
pub const frag_colr_native_spv: []align(4) const u8 = &aligned_frag_colr_native;
pub const frag_path_native_spv: []align(4) const u8 = &aligned_frag_path_native;
pub const frag_tt_hinted_native_spv: []align(4) const u8 = &aligned_frag_tt_hinted_native;
pub const vert_autohint_native_spv: []align(4) const u8 = &aligned_vert_autohint_native;
pub const frag_autohint_native_spv: []align(4) const u8 = &aligned_frag_autohint_native;
pub const frag_subpixel_native_spv: []align(4) const u8 = &aligned_frag_subpixel_native;
pub const frag_tt_hinted_subpixel_native_spv: []align(4) const u8 = &aligned_frag_tt_hinted_subpixel_native;
pub const frag_autohint_subpixel_native_spv: []align(4) const u8 = &aligned_frag_autohint_subpixel_native;

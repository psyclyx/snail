//! SPIR-V shader bytecode for the Vulkan backend.
//! The .spv files are compiled from GLSL 450 sources at build time via glslc
//! and injected as anonymous imports by the build system.

pub const vert_spv = @embedFile("slug.vert.spv");
pub const frag_spv = @embedFile("slug.frag.spv");
pub const frag_subpixel_spv = @embedFile("slug_subpixel.frag.spv");

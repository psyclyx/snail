//! snail_vulkan module root — the Vulkan backend surface.
//!
//! Font-necessary only: snail provides the pipeline `contract` (push constants,
//! descriptor binding order, vertex input, per-family SPIR-V, blend, recipes,
//! glyph-run dispatch), the caller-facing `types`, and the compiled `shaders`.
//! The atlas texel data + upload plan are in `snail_core`
//! (`AtlasUploadPlanner`). GPU resource management — textures, samplers,
//! descriptor sets, uploads — is the caller's (every GPU app has it); see the
//! reference caller renderer + atlas cache under `src/demo/embed_vulkan*.zig`.

pub const types = @import("types.zig");
pub const contract = @import("contract.zig");
pub const embeddable = @import("embeddable.zig");

pub const VulkanContext = types.VulkanContext;

test {
    _ = types;
    _ = contract;
    _ = embeddable;
}

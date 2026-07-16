//! snail_vulkan module root — the Vulkan backend surface.
//!
//! Snail provides only the includable shader/resource `embeddable` contract.
//! The atlas texel data + upload plan are in `snail_core`
//! (`AtlasUploadPlanner`). GPU resource management — textures, samplers,
//! descriptor sets, uploads — is the caller's (every GPU app has it); see the
//! reference caller renderer + atlas cache under `src/demo/embed_vulkan*.zig`.

pub const embeddable = @import("embeddable.zig");

test {
    _ = embeddable;
}

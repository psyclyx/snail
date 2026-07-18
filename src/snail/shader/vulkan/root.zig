//! snail Vulkan shader contract root — the Vulkan backend surface.
//!
//! Snail provides only the includable shader/resource `embeddable` contract.
//! The atlas texel data + upload plan come from `snail.AtlasUploadPlanner`.
//! GPU resource management — textures, samplers,
//! descriptor sets, uploads — is the caller's (every GPU app has it); see the
//! reference caller renderer + atlas cache under `src/demo/render/vulkan/`.

pub const embeddable = @import("embeddable.zig");

test {
    _ = embeddable;
}

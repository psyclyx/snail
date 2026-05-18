const manifest = @import("resources/manifest.zig");
const view = @import("resources/view.zig");
const prepared = @import("resources/prepared.zig");
const stamp = @import("resources/stamp.zig");
const footprint = @import("resources/footprint.zig");
const footprint_types = @import("resources/footprint_types.zig");

pub const ResourceManifest = manifest.ResourceManifest;
pub const PreparedManifest = prepared.PreparedManifest;
pub const ResidentResources = prepared.ResidentResources;
pub const PreparedResources = prepared.PreparedResources;
pub const PreparedResourceRetirementQueue = prepared.PreparedResourceRetirementQueue;
pub const ResourceFootprint = footprint_types.ResourceFootprint;
pub const PreparedAtlasView = view.PreparedAtlasView;
pub const PreparedTextAtlasView = view.PreparedTextAtlasView;
pub const PreparedImageView = view.PreparedImageView;
pub const curveAtlasFootprint = footprint.curveAtlasFootprint;
pub const textAtlasUploadFootprint = footprint.textAtlasUploadFootprint;

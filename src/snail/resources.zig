pub const set = @import("resources/set.zig");
pub const view = @import("resources/view.zig");
pub const prepared = @import("resources/prepared.zig");
pub const stamp = @import("resources/stamp.zig");
pub const footprint = @import("resources/footprint.zig");
pub const footprint_types = @import("resources/footprint_types.zig");
pub const upload = @import("resources/upload.zig");

pub const ResourceSet = set.ResourceSet;
pub const PreparedResources = prepared.PreparedResources;
pub const PreparedResourceRetirementQueue = prepared.PreparedResourceRetirementQueue;
pub const ResourceFootprint = footprint_types.ResourceFootprint;
pub const PreparedAtlasView = view.PreparedAtlasView;
pub const PreparedTextAtlasView = view.PreparedTextAtlasView;
pub const PreparedImageView = view.PreparedImageView;
pub const PreparedLayerInfoUpload = view.PreparedLayerInfoUpload;
pub const PreparedLayerInfoView = view.PreparedLayerInfoView;
pub const coerceAtlasHandle = view.coerceAtlasHandle;

pub const ResourceUploadBatch = upload.ResourceUploadBatch;
pub const uploadPreparedResources = upload.uploadPreparedResources;

pub const resourceEntryKey = stamp.resourceEntryKey;
pub const resourceEntryStamp = stamp.resourceEntryStamp;
pub const resourceEntryUploadBytes = stamp.resourceEntryUploadBytes;

pub const curveAtlasFootprint = footprint.curveAtlasFootprint;
pub const textAtlasUploadFootprint = footprint.textAtlasUploadFootprint;

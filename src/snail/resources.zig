pub const set = @import("resources/set.zig");
pub const prepared = @import("resources/prepared.zig");
pub const stamp = @import("resources/stamp.zig");
pub const footprint = @import("resources/footprint.zig");
pub const upload = @import("resources/upload.zig");

pub const ResourceSet = set.ResourceSet;
pub const PreparedResources = prepared.PreparedResources;
pub const PreparedResourceRetirementQueue = prepared.PreparedResourceRetirementQueue;

pub const ResourceUploadBatch = upload.ResourceUploadBatch;
pub const uploadPreparedResources = upload.uploadPreparedResources;

pub const resourceEntryKey = stamp.resourceEntryKey;
pub const resourceEntryStamp = stamp.resourceEntryStamp;
pub const resourceEntryUploadBytes = stamp.resourceEntryUploadBytes;

pub const curveAtlasFootprint = footprint.curveAtlasFootprint;
pub const textAtlasUploadFootprint = footprint.textAtlasUploadFootprint;

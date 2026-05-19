pub const ErrorCode = struct {
    name: []const u8,
    c_name: []const u8,
    value: i32,
};

pub const Handle = struct {
    name: []const u8,
};

pub const errors = [_]ErrorCode{
    .{ .name = "ok", .c_name = "SNAIL_OK", .value = 0 },
    .{ .name = "invalid_font", .c_name = "SNAIL_ERR_INVALID_FONT", .value = -1 },
    .{ .name = "out_of_memory", .c_name = "SNAIL_ERR_OUT_OF_MEMORY", .value = -2 },
    .{ .name = "renderer_failed", .c_name = "SNAIL_ERR_RENDERER_FAILED", .value = -3 },
    .{ .name = "invalid_argument", .c_name = "SNAIL_ERR_INVALID_ARGUMENT", .value = -4 },
    .{ .name = "draw_failed", .c_name = "SNAIL_ERR_DRAW_FAILED", .value = -5 },
    .{ .name = "hint_unavailable", .c_name = "SNAIL_ERR_HINT_UNAVAILABLE", .value = -6 },
};

pub const handles = [_]Handle{
    .{ .name = "SnailFont" },
    .{ .name = "SnailTextAtlas" },
    .{ .name = "SnailShapedText" },
    .{ .name = "SnailTextBlob" },
    .{ .name = "SnailTextBlobBuilder" },
    .{ .name = "SnailTrueTypeHintContext" },
    .{ .name = "SnailTrueTypePreparedHintRun" },
    .{ .name = "SnailImage" },
    .{ .name = "SnailPath" },
    .{ .name = "SnailPathPictureBuilder" },
    .{ .name = "SnailPathPicture" },
    .{ .name = "SnailScene" },
    .{ .name = "SnailResourceManifest" },
    .{ .name = "SnailPreparedResources" },
    .{ .name = "SnailPreparedScene" },
    .{ .name = "SnailPreparedResourceRetirementQueue" },
    .{ .name = "SnailResourceUploadPlan" },
    .{ .name = "SnailPendingResourceUpload" },
    .{ .name = "SnailVulkanFrame" },
    .{ .name = "SnailDrawList" },
    .{ .name = "SnailTextCoverageRecords" },
    .{ .name = "SnailCoverageBackend" },
    .{ .name = "SnailRenderer" },
};

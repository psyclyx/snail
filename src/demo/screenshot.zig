const std = @import("std");
const snail = @import("snail");
const compact_scene = @import("screenshot_scene.zig");
const demo_banner = @import("banner.zig");
const demo_scene = @import("scene.zig");
const screenshot = @import("support").screenshot;
const egl_offscreen = @import("platform/offscreen_gl.zig");
const gl = @import("support").gl;

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

const SCREENSHOT_WIDTH: u32 = compact_scene.WIDTH;
const SCREENSHOT_HEIGHT: u32 = compact_scene.HEIGHT;
const SCREENSHOT_PATH = "zig-out/demo-screenshot.tga";
const REPRO_SCREENSHOT_PATH = "zig-out/repro-frame.tga";
const GL_RGBA8: gl.GLint = 0x8058;
const GL_SRGB8_ALPHA8: gl.GLint = 0x8C43;

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    if (std.c.getenv("SNAIL_REPRO") != null) {
        try renderRepro(allocator);
    } else {
        try renderCompactBanner(allocator);
    }
}

const OffscreenTarget = struct {
    fbo: gl.GLuint = 0,
    fbo_tex: gl.GLuint = 0,
    width: u32,
    height: u32,

    fn init(width: u32, height: u32, attachment_encoding: snail.ColorEncoding) !OffscreenTarget {
        var self = OffscreenTarget{ .width = width, .height = height };
        gl.glGenFramebuffers(1, &self.fbo);
        gl.glGenTextures(1, &self.fbo_tex);

        const internal_format = if (attachment_encoding == .srgb) GL_SRGB8_ALPHA8 else GL_RGBA8;
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.fbo_tex);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, internal_format, @intCast(width), @intCast(height), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.fbo);
        gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.fbo_tex, 0);
        if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
        gl.glViewport(0, 0, @intCast(width), @intCast(height));
        return self;
    }

    fn deinit(self: *OffscreenTarget) void {
        gl.glDeleteFramebuffers(1, &self.fbo);
        gl.glDeleteTextures(1, &self.fbo_tex);
    }
};

fn parseU32Auto(value: []const u8) !u32 {
    if (std.mem.startsWith(u8, value, "0x") or std.mem.startsWith(u8, value, "0X")) {
        return std.fmt.parseInt(u32, value[2..], 16);
    }
    return std.fmt.parseInt(u32, value, 10);
}

fn envU32(comptime name: [:0]const u8, default: u32) u32 {
    const ptr = std.c.getenv(name.ptr) orelse return default;
    return parseU32Auto(std.mem.span(ptr)) catch default;
}

fn envBool(comptime name: [:0]const u8, default: bool) bool {
    return envU32(name, @intFromBool(default)) != 0;
}

fn envMat4(comptime name: [:0]const u8, fallback: snail.Mat4) snail.Mat4 {
    const ptr = std.c.getenv(name.ptr) orelse return fallback;
    var it = std.mem.splitScalar(u8, std.mem.span(ptr), ',');
    var data: [16]f32 = undefined;
    for (&data) |*value| {
        const part = it.next() orelse return fallback;
        const bits = parseU32Auto(part) catch return fallback;
        value.* = @as(f32, @bitCast(bits));
    }
    if (it.next() != null) return fallback;
    return .{ .data = data };
}

fn envSubpixelOrder() snail.SubpixelOrder {
    return switch (envU32("SNAIL_REPRO_SUBPIXEL", 0)) {
        0 => .none,
        1 => .rgb,
        2 => .bgr,
        3 => .vrgb,
        4 => .vbgr,
        else => .none,
    };
}

fn colorEncodingFromEnv(comptime name: [:0]const u8, default: snail.ColorEncoding) snail.ColorEncoding {
    return switch (envU32(name, @intCast(@intFromEnum(default)))) {
        0 => .linear,
        1 => .srgb,
        else => default,
    };
}

fn outputPath(default: [*:0]const u8) [*:0]const u8 {
    return std.c.getenv("SNAIL_REPRO_OUTPUT") orelse default;
}

fn renderCompactBanner(allocator: std.mem.Allocator) !void {
    var gl_ctx = try egl_offscreen.Context.init(SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
    defer gl_ctx.deinit();

    var target = try OffscreenTarget.init(SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT, .srgb);
    defer target.deinit();

    var scene_assets = try compact_scene.Assets.init(allocator);
    defer scene_assets.deinit();

    var gl_renderer = try snail.GlRenderer.init(allocator);
    defer gl_renderer.deinit();
    var renderer = gl_renderer.asRenderer();

    const w: f32 = @floatFromInt(SCREENSHOT_WIDTH);
    const h: f32 = @floatFromInt(SCREENSHOT_HEIGHT);
    const projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);

    var builder = snail.TextBlobBuilder.init(allocator, &scene_assets.fonts);
    defer builder.deinit();
    try compact_scene.buildTextBlob(&builder);
    var text_blob = try builder.finish();
    defer text_blob.deinit();

    var path_picture = try compact_scene.buildPathPicture(allocator);
    defer path_picture.deinit();
    var scene = snail.Scene.init(allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &path_picture });
    try scene.addText(.{ .blob = &text_blob });

    var resource_entries: [8]snail.ResourceSet.Entry = undefined;
    var resources = snail.ResourceSet.init(&resource_entries);
    try resources.addScene(&scene);
    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &resources);
    defer prepared.deinit();

    const clear = compact_scene.clearColor();
    gl.glClearColor(srgbToLinear(clear[0]), srgbToLinear(clear[1]), srgbToLinear(clear[2]), clear[3]);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    const draw_state = snail.DrawState{
        .mvp = projection,
        .surface = .{
            .pixel_width = w,
            .pixel_height = h,
            .encoding = .srgb,
        },
    };
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, &scene);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, draw_state);

    if (screenshot.captureFramebuffer(allocator, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT) catch null) |px| {
        defer allocator.free(px);
        screenshot.writeTga(SCREENSHOT_PATH, px, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
        std.debug.print("wrote {s}\n", .{SCREENSHOT_PATH});
    } else {
        return error.ScreenshotCaptureFailed;
    }
}

fn renderRepro(allocator: std.mem.Allocator) !void {
    const logical_width = envU32("SNAIL_REPRO_LOGICAL_W", 1280);
    const logical_height = envU32("SNAIL_REPRO_LOGICAL_H", 720);
    const framebuffer_width = envU32("SNAIL_REPRO_FB_W", logical_width);
    const framebuffer_height = envU32("SNAIL_REPRO_FB_H", logical_height);
    const target_encoding = snail.TargetEncoding{
        .attachment = colorEncodingFromEnv("SNAIL_REPRO_ATTACHMENT", .srgb),
        .stored_pixels = colorEncodingFromEnv("SNAIL_REPRO_STORED", .srgb),
    };

    var gl_ctx = try egl_offscreen.Context.init(framebuffer_width, framebuffer_height);
    defer gl_ctx.deinit();

    var target = try OffscreenTarget.init(framebuffer_width, framebuffer_height, target_encoding.attachment);
    defer target.deinit();

    var scene_assets = try demo_scene.Assets.init(allocator);
    defer scene_assets.deinit();

    var gl_renderer = try snail.GlRenderer.init(allocator);
    defer gl_renderer.deinit();
    var renderer = gl_renderer.asRenderer();

    const w: f32 = @floatFromInt(logical_width);
    const h: f32 = @floatFromInt(logical_height);
    const viewport_w: f32 = @floatFromInt(framebuffer_width);
    const viewport_h: f32 = @floatFromInt(framebuffer_height);
    const layout = demo_banner.buildLayout(w, h);
    const snap_step = snail.pixelSteps(.{ w, h }, .{ framebuffer_width, framebuffer_height });

    var builder = snail.TextBlobBuilder.init(allocator, &scene_assets.fonts);
    defer builder.deinit();
    var dec_rects: [8]snail.Rect = undefined;
    const text_result = demo_scene.buildTextBlob(&builder, layout, snap_step, &scene_assets, &dec_rects);
    var text_blob = try builder.finish();
    defer text_blob.deinit();

    var path_picture = try demo_scene.buildPathPicture(allocator, layout, &scene_assets, dec_rects[0..text_result.decoration_count]);
    defer path_picture.deinit();
    var scene = snail.Scene.init(allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &path_picture });
    try scene.addText(.{ .blob = &text_blob });

    var resource_entries: [8]snail.ResourceSet.Entry = undefined;
    var resources = snail.ResourceSet.init(&resource_entries);
    try resources.addScene(&scene);
    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &resources);
    defer prepared.deinit();

    const clear = demo_banner.clearColor();
    gl.glClearColor(srgbToLinear(clear[0]), srgbToLinear(clear[1]), srgbToLinear(clear[2]), clear[3]);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    const fallback_mvp = snail.Mat4.ortho(0, w, h, 0, -1, 1);
    const draw_state = snail.DrawState{
        .mvp = envMat4("SNAIL_REPRO_MVP", fallback_mvp),
        .surface = .{
            .pixel_width = viewport_w,
            .pixel_height = viewport_h,
            .encoding = target_encoding,
        },
        .raster = .{ .subpixel_order = if (envBool("SNAIL_REPRO_WILL_RESAMPLE", false)) .none else envSubpixelOrder() },
    };

    const needed = snail.DrawList.estimate(&scene);
    const needed_segments = snail.DrawList.estimateSegments(&scene);
    const draw_buf = try allocator.alloc(u32, needed);
    defer allocator.free(draw_buf);
    const draw_segments_buf = try allocator.alloc(snail.DrawSegment, needed_segments);
    defer allocator.free(draw_segments_buf);
    var draw = snail.DrawList.init(draw_buf, draw_segments_buf);
    try draw.addScene(&prepared, &scene);
    try renderer.draw(&prepared, draw.slice(), draw_state);

    if (screenshot.captureFramebuffer(allocator, framebuffer_width, framebuffer_height) catch null) |px| {
        defer allocator.free(px);
        const path = outputPath(REPRO_SCREENSHOT_PATH);
        screenshot.writeTga(path, px, framebuffer_width, framebuffer_height);
        std.debug.print("wrote {s}\n", .{std.mem.span(path)});
    } else {
        return error.ScreenshotCaptureFailed;
    }
}

const std = @import("std");
const build_options = @import("build_options");
const assets = @import("assets");
const snail = @import("snail.zig");
const screenshot = @import("render/screenshot.zig");
const egl_offscreen = @import("render/egl_offscreen.zig");
const gl = @import("render/gl.zig").gl;
const vulkan_platform = if (build_options.enable_vulkan) @import("render/vulkan_platform.zig") else struct {};

const WIDTH: u32 = 220;
const HEIGHT: u32 = 112;
const GL_SRGB8_ALPHA8: gl.GLenum = 0x8C43;
const DUMP_DIR = "zig-out/backend-compare";
const DEVANAGARI_TEXT = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87";

const CompareCase = struct {
    name: []const u8,
    subpixel_order: snail.SubpixelOrder,
    requires_dual_source: bool = false,
};

const CompareStats = struct {
    pixel_count: usize,
    mismatched_pixels: usize = 0,
    max_channel_delta: u8 = 0,
    total_channel_delta: u64 = 0,
    worst_offset: usize = 0,

    fn averageChannelDelta(self: CompareStats) f64 {
        const channel_count = @as(f64, @floatFromInt(self.pixel_count * 4));
        return @as(f64, @floatFromInt(self.total_channel_delta)) / @max(channel_count, 1.0);
    }
};

const SceneBundle = struct {
    atlas: *snail.TextAtlas,
    latin_blob: *snail.TextBlob,
    devanagari_blob: *snail.TextBlob,
    picture: *snail.PathPicture,
    scene: snail.Scene,
    allocator: std.mem.Allocator,

    fn deinit(self: *SceneBundle) void {
        self.scene.deinit();
        self.picture.deinit();
        self.allocator.destroy(self.picture);
        self.devanagari_blob.deinit();
        self.allocator.destroy(self.devanagari_blob);
        self.latin_blob.deinit();
        self.allocator.destroy(self.latin_blob);
        self.atlas.deinit();
        self.allocator.destroy(self.atlas);
        self.* = undefined;
    }
};

fn drawOptions(subpixel_order: snail.SubpixelOrder) snail.DrawOptions {
    const wf: f32 = @floatFromInt(WIDTH);
    const hf: f32 = @floatFromInt(HEIGHT);
    return .{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .target = .{
            .pixel_width = wf,
            .pixel_height = hf,
            .subpixel_order = subpixel_order,
            .is_final_composite = true,
            .opaque_backdrop = true,
        },
    };
}

fn ensureText(atlas: *snail.TextAtlas, style: snail.FontStyle, text: []const u8) !void {
    if (try atlas.ensureText(style, text)) |next| {
        atlas.deinit();
        atlas.* = next;
    }
}

fn buildTextBlob(
    allocator: std.mem.Allocator,
    atlas: *const snail.TextAtlas,
    text: []const u8,
    x: f32,
    y: f32,
    size: f32,
    color: [4]f32,
) !snail.TextBlob {
    var builder = snail.TextBlobBuilder.init(allocator, atlas);
    defer builder.deinit();
    _ = try builder.addText(.{}, text, x, y, size, color);
    return builder.finish();
}

fn buildPathPicture(allocator: std.mem.Allocator) !snail.PathPicture {
    var builder = snail.PathPictureBuilder.init(allocator);
    defer builder.deinit();

    try builder.addRoundedRect(
        .{ .x = 8.5, .y = 8.5, .w = 203.0, .h = 94.0 },
        .{ .color = .{ 0.07, 0.09, 0.12, 1.0 } },
        .{
            .color = .{ 0.30, 0.38, 0.50, 1.0 },
            .width = 1.5,
            .join = .round,
            .placement = .inside,
        },
        8.0,
        .identity,
    );
    try builder.addEllipse(
        .{ .x = 146.25, .y = 23.75, .w = 48.5, .h = 35.5 },
        .{ .color = .{ 0.18, 0.50, 0.80, 0.72 } },
        .{
            .color = .{ 0.90, 0.94, 0.98, 0.82 },
            .width = 1.25,
            .join = .round,
            .placement = .inside,
        },
        .identity,
    );

    var path = snail.Path.init(allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 28.0, .y = 84.0 });
    try path.cubicTo(.{ .x = 47.0, .y = 56.0 }, .{ .x = 72.0, .y = 106.0 }, .{ .x = 94.0, .y = 74.0 });
    try path.quadTo(.{ .x = 66.0, .y = 92.0 }, .{ .x = 28.0, .y = 84.0 });
    try path.close();
    try builder.addPath(
        &path,
        .{ .color = .{ 0.78, 0.33, 0.22, 0.78 } },
        .{
            .color = .{ 0.96, 0.77, 0.42, 0.86 },
            .width = 1.25,
            .join = .round,
            .placement = .inside,
        },
        .identity,
    );

    return builder.freeze(allocator);
}

fn buildScene(allocator: std.mem.Allocator) !SceneBundle {
    const atlas = try allocator.create(snail.TextAtlas);
    errdefer allocator.destroy(atlas);
    atlas.* = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets.noto_sans_regular },
        .{ .data = assets.noto_sans_devanagari, .fallback = true },
    });
    errdefer atlas.deinit();

    try ensureText(atlas, .{}, "CH5+ Hello, world!");
    try ensureText(atlas, .{}, DEVANAGARI_TEXT);

    const latin_blob = try allocator.create(snail.TextBlob);
    errdefer allocator.destroy(latin_blob);
    latin_blob.* = try buildTextBlob(allocator, atlas, "CH5+ Hello, world!", 18.25, 40.5, 24.0, .{ 0.93, 0.95, 0.98, 1.0 });
    errdefer latin_blob.deinit();

    const devanagari_blob = try allocator.create(snail.TextBlob);
    errdefer allocator.destroy(devanagari_blob);
    devanagari_blob.* = try buildTextBlob(allocator, atlas, DEVANAGARI_TEXT, 18.25, 73.25, 22.0, .{ 0.72, 0.84, 1.0, 1.0 });
    errdefer devanagari_blob.deinit();

    const picture = try allocator.create(snail.PathPicture);
    errdefer allocator.destroy(picture);
    picture.* = try buildPathPicture(allocator);
    errdefer picture.deinit();

    var scene = snail.Scene.init(allocator);
    errdefer scene.deinit();
    try scene.addPathPicture(picture);
    try scene.addTextOptions(latin_blob, .{ .hinting = .metrics });
    try scene.addTextOptions(devanagari_blob, .{ .hinting = .metrics });

    return .{
        .atlas = atlas,
        .latin_blob = latin_blob,
        .devanagari_blob = devanagari_blob,
        .picture = picture,
        .scene = scene,
        .allocator = allocator,
    };
}

fn uploadSceneResources(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    scene: *const snail.Scene,
) !snail.PreparedResources {
    var entries: [8]snail.ResourceSet.Entry = undefined;
    var set = snail.ResourceSet.init(&entries);
    try set.addScene(scene);
    return renderer.uploadResourcesBlocking(allocator, &set);
}

fn clearPixels(pixels: []u8) void {
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        pixels[i + 0] = 0;
        pixels[i + 1] = 0;
        pixels[i + 2] = 0;
        pixels[i + 3] = 255;
    }
}

fn renderCpu(
    allocator: std.mem.Allocator,
    scene: *const snail.Scene,
    options: snail.DrawOptions,
) ![]u8 {
    const pixels = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    errdefer allocator.free(pixels);
    clearPixels(pixels);

    var cpu = snail.CpuRenderer.init(pixels.ptr, WIDTH, HEIGHT, WIDTH * 4);
    var renderer = snail.Renderer.initCpu(&cpu);
    var prepared = try uploadSceneResources(allocator, &renderer, scene);
    defer prepared.deinit();
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, scene, options);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, options);
    return pixels;
}

fn initFramebuffer() !struct { fbo: gl.GLuint, texture: gl.GLuint } {
    var fbo: gl.GLuint = 0;
    var tex: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, WIDTH, HEIGHT, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, tex, 0);
    if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
    gl.glViewport(0, 0, WIDTH, HEIGHT);
    gl.glDisable(gl.GL_DITHER);
    return .{ .fbo = fbo, .texture = tex };
}

fn flipRowsInPlace(pixels: []u8) void {
    var tmp: [WIDTH * 4]u8 = undefined;
    var y: usize = 0;
    while (y < HEIGHT / 2) : (y += 1) {
        const top = y * WIDTH * 4;
        const bottom = (@as(usize, HEIGHT) - 1 - y) * WIDTH * 4;
        @memcpy(&tmp, pixels[top..][0 .. WIDTH * 4]);
        @memcpy(pixels[top..][0 .. WIDTH * 4], pixels[bottom..][0 .. WIDTH * 4]);
        @memcpy(pixels[bottom..][0 .. WIDTH * 4], &tmp);
    }
}

fn renderGl(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    fbo: gl.GLuint,
    scene: *const snail.Scene,
    options: snail.DrawOptions,
) ![]u8 {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glViewport(0, 0, WIDTH, HEIGHT);
    gl.glClearColor(0.0, 0.0, 0.0, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    var prepared = try uploadSceneResources(allocator, renderer, scene);
    defer prepared.deinit();
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, scene, options);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, options);
    gl.glFinish();

    const pixels = try screenshot.captureFramebuffer(allocator, WIDTH, HEIGHT);
    flipRowsInPlace(pixels);
    return pixels;
}

fn renderVulkan(
    allocator: std.mem.Allocator,
    vk_renderer: *snail.VulkanRenderer,
    renderer: *snail.Renderer,
    scene: *const snail.Scene,
    options: snail.DrawOptions,
) ![]u8 {
    if (comptime !build_options.enable_vulkan) unreachable;

    var prepared = try uploadSceneResources(allocator, renderer, scene);
    defer prepared.deinit();
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, scene, options);
    defer prepared_scene.deinit();

    const cmd = vulkan_platform.beginFrameOffscreenWithClear(.{ 0.0, 0.0, 0.0, 1.0 });
    vk_renderer.beginFrame(.{ .cmd = cmd, .frame_index = vulkan_platform.currentOffscreenFrameIndex() });
    try renderer.drawPrepared(&prepared, &prepared_scene, options);
    vulkan_platform.endFrameOffscreen();
    vulkan_platform.queueWaitIdle();
    return vulkan_platform.captureOffscreenRgba8(allocator);
}

fn comparePixels(expected: []const u8, actual: []const u8, tolerance: u8) CompareStats {
    std.debug.assert(expected.len == actual.len);
    var stats = CompareStats{ .pixel_count = expected.len / 4 };
    var i: usize = 0;
    while (i < expected.len) : (i += 4) {
        var pixel_mismatch = false;
        for (0..4) |channel| {
            const offset = i + channel;
            const delta_i = @as(i16, expected[offset]) - @as(i16, actual[offset]);
            const delta: u8 = @intCast(if (delta_i < 0) -delta_i else delta_i);
            stats.total_channel_delta += delta;
            if (delta > stats.max_channel_delta) {
                stats.max_channel_delta = delta;
                stats.worst_offset = offset;
            }
            if (delta > tolerance) pixel_mismatch = true;
        }
        if (pixel_mismatch) stats.mismatched_pixels += 1;
    }
    return stats;
}

fn makeDiffImage(allocator: std.mem.Allocator, expected: []const u8, actual: []const u8) ![]u8 {
    const diff = try allocator.alloc(u8, expected.len);
    errdefer allocator.free(diff);
    var i: usize = 0;
    while (i < expected.len) : (i += 4) {
        for (0..3) |channel| {
            const delta_i = @as(i16, expected[i + channel]) - @as(i16, actual[i + channel]);
            const delta: u8 = @intCast(if (delta_i < 0) -delta_i else delta_i);
            diff[i + channel] = @min(@as(u16, delta) * 8, 255);
        }
        diff[i + 3] = 255;
    }
    return diff;
}

fn writeTgaAlloc(allocator: std.mem.Allocator, name: []const u8, pixels: []const u8) !void {
    _ = std.c.mkdir("zig-out", 0o755);
    _ = std.c.mkdir(DUMP_DIR, 0o755);
    const path = try std.fmt.allocPrintSentinel(allocator, "{s}/{s}.tga", .{ DUMP_DIR, name }, 0);
    defer allocator.free(path);
    screenshot.writeTga(path, pixels, WIDTH, HEIGHT);
}

fn dumpFailure(
    allocator: std.mem.Allocator,
    case_name: []const u8,
    backend_slug: []const u8,
    expected: []const u8,
    actual: []const u8,
) !void {
    const expected_name = try std.fmt.allocPrint(allocator, "{s}-cpu", .{case_name});
    defer allocator.free(expected_name);
    const actual_name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ case_name, backend_slug });
    defer allocator.free(actual_name);
    const diff_name = try std.fmt.allocPrint(allocator, "{s}-{s}-diff", .{ case_name, backend_slug });
    defer allocator.free(diff_name);

    try writeTgaAlloc(allocator, expected_name, expected);
    try writeTgaAlloc(allocator, actual_name, actual);
    const diff = try makeDiffImage(allocator, expected, actual);
    defer allocator.free(diff);
    try writeTgaAlloc(allocator, diff_name, diff);
}

fn checkBackend(
    allocator: std.mem.Allocator,
    case_name: []const u8,
    backend_name: []const u8,
    backend_slug: []const u8,
    expected: []const u8,
    actual: []const u8,
) !void {
    const tolerance: u8 = 4;
    const outlier_budget = @max(@as(usize, 16), expected.len / (4 * 500));
    const average_budget = 1.0;
    const stats = comparePixels(expected, actual, tolerance);
    if (stats.mismatched_pixels <= outlier_budget and stats.averageChannelDelta() <= average_budget) {
        std.debug.print(
            "{s}: {s} matches CPU ({d} outlier pixels, max delta {d}, avg channel delta {d:.3})\n",
            .{ case_name, backend_name, stats.mismatched_pixels, stats.max_channel_delta, stats.averageChannelDelta() },
        );
        return;
    }

    const pixel = stats.worst_offset / 4;
    const x = pixel % WIDTH;
    const y = pixel / WIDTH;
    std.debug.print(
        "{s}: {s} differs from CPU: {d}/{d} pixels over tolerance, max channel delta {d} at ({d}, {d}), avg channel delta {d:.3}\n",
        .{ case_name, backend_name, stats.mismatched_pixels, stats.pixel_count, stats.max_channel_delta, x, y, stats.averageChannelDelta() },
    );
    try dumpFailure(allocator, case_name, backend_slug, expected, actual);
    return error.BackendPixelMismatch;
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var scene_bundle = try buildScene(allocator);
    defer scene_bundle.deinit();

    var gl_ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT);
    defer gl_ctx.deinit();
    const framebuffer = try initFramebuffer();
    defer {
        var fbo = framebuffer.fbo;
        var texture = framebuffer.texture;
        gl.glDeleteFramebuffers(1, &fbo);
        gl.glDeleteTextures(1, &texture);
    }

    var gl_renderer_state = try snail.GlRenderer.init(allocator);
    defer gl_renderer_state.deinit();
    var gl_renderer = gl_renderer_state.asRenderer();
    const gl_supports_lcd = gl_renderer_state.state.supports_dual_source_blend;

    var vk_renderer_state: if (build_options.enable_vulkan) snail.VulkanRenderer else void = undefined;
    var vk_renderer: if (build_options.enable_vulkan) snail.Renderer else void = undefined;
    var vk_supports_lcd = false;
    if (comptime build_options.enable_vulkan) {
        const vk_ctx = try vulkan_platform.initOffscreen(WIDTH, HEIGHT);
        errdefer vulkan_platform.deinitOffscreen();
        vk_renderer_state = try snail.VulkanRenderer.init(vk_ctx);
        errdefer vk_renderer_state.deinit();
        vk_renderer = vk_renderer_state.asRenderer();
        vk_supports_lcd = vk_renderer_state.state.ctx.supports_dual_source_blend;
    }
    defer if (build_options.enable_vulkan) {
        vk_renderer_state.deinit();
        vulkan_platform.deinitOffscreen();
    };

    const cases = [_]CompareCase{
        .{ .name = "grayscale", .subpixel_order = .none },
        .{ .name = "subpixel-rgb", .subpixel_order = .rgb, .requires_dual_source = true },
    };

    for (cases) |case| {
        const options = drawOptions(case.subpixel_order);
        const cpu_pixels = try renderCpu(allocator, &scene_bundle.scene, options);
        defer allocator.free(cpu_pixels);

        if (!case.requires_dual_source or gl_supports_lcd) {
            const gl_pixels = try renderGl(allocator, &gl_renderer, framebuffer.fbo, &scene_bundle.scene, options);
            defer allocator.free(gl_pixels);
            try checkBackend(allocator, case.name, gl_renderer_state.backendName(), "gl", cpu_pixels, gl_pixels);
        } else {
            std.debug.print("{s}: skipping OpenGL LCD compare; dual-source blending unavailable\n", .{case.name});
        }

        if (comptime build_options.enable_vulkan) {
            if (!case.requires_dual_source or vk_supports_lcd) {
                const vk_pixels = try renderVulkan(allocator, &vk_renderer_state, &vk_renderer, &scene_bundle.scene, options);
                defer allocator.free(vk_pixels);
                try checkBackend(allocator, case.name, vk_renderer_state.backendName(), "vulkan", cpu_pixels, vk_pixels);
            } else {
                std.debug.print("{s}: skipping Vulkan LCD compare; dual-source blending unavailable\n", .{case.name});
            }
        } else if (!case.requires_dual_source) {
            std.debug.print("{s}: Vulkan not built (`zig build backend-compare -Dvulkan=true`)\n", .{case.name});
        }
    }
}

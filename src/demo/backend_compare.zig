const std = @import("std");
const build_options = @import("build_options");
const assets = @import("assets");
const snail = @import("snail");
const screenshot = @import("platform/screenshot.zig");
const egl_offscreen = @import("platform/offscreen_gl.zig");
const gl = snail.lowlevel.gl;
const vulkan_platform = if (build_options.enable_vulkan) @import("platform/vulkan.zig") else struct {};

const WIDTH: u32 = 220;
const HEIGHT: u32 = 112;
const GL_RGBA8: gl.GLenum = 0x8058;
const GL_SRGB8_ALPHA8: gl.GLenum = 0x8C43;
const DUMP_DIR = "zig-out/backend-compare";
const DEVANAGARI_TEXT = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87";
const LINEAR_RESOLVE_SEED = [4]u8{ 34, 45, 59, 255 };

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

const ComparePolicy = struct {
    tolerance: u8,
    max_channel_delta: u8,
    outlier_budget: usize,
    average_budget: f64,
};

// CPU and GPU paths intentionally use different arithmetic, so CPU-vs-backend
// comparison allows a tight budget of rare near-tangent conic outliers.
const cpu_backend_policy = ComparePolicy{
    .tolerance = 1,
    .max_channel_delta = 64,
    .outlier_budget = 32,
    .average_budget = 0.05,
};

// GL and Vulkan should be the same shader algorithm. Allow only 2-LSB store
// rounding drift, and no channel may exceed that.
const gpu_consistency_policy = ComparePolicy{
    .tolerance = 2,
    .max_channel_delta = 2,
    .outlier_budget = 0,
    .average_budget = 1.0,
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
            .encoding = .srgb,
        },
    };
}

fn linearResolveDrawOptions(subpixel_order: snail.SubpixelOrder) snail.DrawOptions {
    var options = drawOptions(subpixel_order);
    options.target.encoding = .srgb_pixels_on_linear_attachment;
    options.target.resolve = .{ .linear = .{} };
    return options;
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
    return buildPaintedTextBlob(allocator, atlas, text, x, y, size, .{ .solid = color });
}

fn buildPaintedTextBlob(
    allocator: std.mem.Allocator,
    atlas: *const snail.TextAtlas,
    text: []const u8,
    x: f32,
    y: f32,
    size: f32,
    paint: snail.Paint,
) !snail.TextBlob {
    var builder = snail.TextBlobBuilder.init(allocator, atlas);
    defer builder.deinit();
    var shaped = try atlas.shapeText(allocator, .{}, text);
    defer shaped.deinit();
    _ = try builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = x, .y = y }, .em = size },
        .fill = paint,
    });
    return builder.finish();
}

fn buildPathPicture(allocator: std.mem.Allocator) !snail.PathPicture {
    var builder = snail.PathPictureBuilder.init(allocator);
    defer builder.deinit();

    try builder.addRoundedRect(
        .{ .x = 8.5, .y = 8.5, .w = 203.0, .h = 94.0 },
        .{ .paint = .{ .solid = .{ 0.07, 0.09, 0.12, 1.0 } } },
        .{
            .paint = .{ .solid = .{ 0.30, 0.38, 0.50, 1.0 } },
            .width = 1.5,
            .join = .round,
            .placement = .inside,
        },
        8.0,
        .identity,
    );
    try builder.addEllipse(
        .{ .x = 146.25, .y = 23.75, .w = 48.5, .h = 35.5 },
        .{ .paint = .{ .solid = .{ 0.18, 0.50, 0.80, 0.72 } } },
        .{
            .paint = .{ .solid = .{ 0.90, 0.94, 0.98, 0.82 } },
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
        .{ .paint = .{ .solid = .{ 0.78, 0.33, 0.22, 0.78 } } },
        .{
            .paint = .{ .solid = .{ 0.96, 0.77, 0.42, 0.86 } },
            .width = 1.25,
            .join = .round,
            .placement = .inside,
        },
        .identity,
    );

    return builder.freeze(.{ .persistent_allocator = allocator, .scratch_allocator = allocator });
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
    // Baselines pinned to integer y. CPU and GL compute the same mathematical
    // sample point at every pixel, but via different float op orderings: CPU
    // applies inverseTransform directly, GL interpolates v_texcoord across the
    // dilated quad. When a baseline lands at a half-pixel y, the sample em
    // coord at the baseline pixel is mathematically zero — and CPU's
    // computation rounds to a tiny negative (~−7e-7) while GL's lands on a
    // tiny positive. calcRootCode's bit-level sign trick then disagrees about
    // whether contour curves at em y=0 cross the sample ray, producing a
    // ~0.5 coverage gap on the affected row. Pinning to integer y avoids
    // tripping this; see TODO comment in evalGlyphCoverageAxis.
    latin_blob.* = try buildPaintedTextBlob(allocator, atlas, "CH5+ Hello, world!", 18.25, 40.0, 24.0, .{ .linear_gradient = .{
        .start = .{ .x = 18.25, .y = 16.0 },
        .end = .{ .x = 205.0, .y = 48.0 },
        .start_color = .{ 0.36, 0.68, 1.0, 1.0 },
        .end_color = .{ 0.98, 0.99, 1.0, 1.0 },
    } });
    errdefer latin_blob.deinit();

    const devanagari_blob = try allocator.create(snail.TextBlob);
    errdefer allocator.destroy(devanagari_blob);
    devanagari_blob.* = try buildTextBlob(allocator, atlas, DEVANAGARI_TEXT, 18.25, 73.0, 22.0, .{ 0.72, 0.84, 1.0, 1.0 });
    errdefer devanagari_blob.deinit();

    const picture = try allocator.create(snail.PathPicture);
    errdefer allocator.destroy(picture);
    picture.* = try buildPathPicture(allocator);
    errdefer picture.deinit();

    var scene = snail.Scene.init(allocator);
    errdefer scene.deinit();
    try scene.addPath(.{ .picture = picture });
    try scene.addText(.{ .blob = latin_blob });
    try scene.addText(.{ .blob = devanagari_blob });

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
    return renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set);
}

fn clearPixelsTo(pixels: []u8, color: [4]u8) void {
    var i: usize = 0;
    while (i < pixels.len) : (i += 4) {
        pixels[i + 0] = color[0];
        pixels[i + 1] = color[1];
        pixels[i + 2] = color[2];
        pixels[i + 3] = color[3];
    }
}

fn renderCpu(
    allocator: std.mem.Allocator,
    scene: *const snail.Scene,
    options: snail.DrawOptions,
) ![]u8 {
    return renderCpuSeeded(allocator, scene, options, .{ 0, 0, 0, 255 });
}

fn renderCpuSeeded(
    allocator: std.mem.Allocator,
    scene: *const snail.Scene,
    options: snail.DrawOptions,
    seed: [4]u8,
) ![]u8 {
    const pixels = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    errdefer allocator.free(pixels);
    clearPixelsTo(pixels, seed);

    var cpu = snail.CpuRenderer.init(pixels.ptr, WIDTH, HEIGHT, WIDTH * 4);
    var renderer = cpu.asRenderer();
    var prepared = try uploadSceneResources(allocator, &renderer, scene);
    defer prepared.deinit();
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, scene, options);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, options);
    return pixels;
}

fn initFramebuffer(internal_format: gl.GLenum) !struct { fbo: gl.GLuint, texture: gl.GLuint } {
    var fbo: gl.GLuint = 0;
    var tex: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, @intCast(internal_format), WIDTH, HEIGHT, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, tex, 0);
    if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
    gl.glViewport(0, 0, WIDTH, HEIGHT);
    gl.glDisable(gl.GL_DITHER);
    return .{ .fbo = fbo, .texture = tex };
}

fn clearGlTo(color: [4]u8) void {
    gl.glClearColor(
        @as(f32, @floatFromInt(color[0])) / 255.0,
        @as(f32, @floatFromInt(color[1])) / 255.0,
        @as(f32, @floatFromInt(color[2])) / 255.0,
        @as(f32, @floatFromInt(color[3])) / 255.0,
    );
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
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
    return renderGlSeeded(allocator, renderer, fbo, scene, options, .{ 0, 0, 0, 255 });
}

fn renderGlSeeded(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    fbo: gl.GLuint,
    scene: *const snail.Scene,
    options: snail.DrawOptions,
    seed: [4]u8,
) ![]u8 {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glViewport(0, 0, WIDTH, HEIGHT);
    clearGlTo(seed);

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
    expected_slug: []const u8,
    actual_slug: []const u8,
    expected: []const u8,
    actual: []const u8,
) !void {
    const expected_name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ case_name, expected_slug });
    defer allocator.free(expected_name);
    const actual_name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ case_name, actual_slug });
    defer allocator.free(actual_name);
    const diff_name = try std.fmt.allocPrint(allocator, "{s}-{s}-vs-{s}-diff", .{ case_name, expected_slug, actual_slug });
    defer allocator.free(diff_name);

    try writeTgaAlloc(allocator, expected_name, expected);
    try writeTgaAlloc(allocator, actual_name, actual);
    const diff = try makeDiffImage(allocator, expected, actual);
    defer allocator.free(diff);
    try writeTgaAlloc(allocator, diff_name, diff);
}

fn checkPixelMatch(
    allocator: std.mem.Allocator,
    case_name: []const u8,
    expected_name: []const u8,
    expected_slug: []const u8,
    actual_name: []const u8,
    actual_slug: []const u8,
    expected: []const u8,
    actual: []const u8,
    policy: ComparePolicy,
) !void {
    const stats = comparePixels(expected, actual, policy.tolerance);
    const pass = stats.mismatched_pixels <= policy.outlier_budget and
        stats.averageChannelDelta() <= policy.average_budget and
        stats.max_channel_delta <= policy.max_channel_delta;
    if (pass) {
        std.debug.print(
            "{s}: {s} matches {s} ({d} pixels over {d} LSB, max delta {d}, avg channel delta {d:.3})\n",
            .{ case_name, actual_name, expected_name, stats.mismatched_pixels, policy.tolerance, stats.max_channel_delta, stats.averageChannelDelta() },
        );
        return;
    }

    const pixel = stats.worst_offset / 4;
    const x = pixel % WIDTH;
    const y = pixel / WIDTH;
    std.debug.print(
        "{s}: {s} differs from {s}: {d}/{d} pixels over {d} LSB, max channel delta {d} at ({d}, {d}), avg channel delta {d:.3}\n",
        .{ case_name, actual_name, expected_name, stats.mismatched_pixels, stats.pixel_count, policy.tolerance, stats.max_channel_delta, x, y, stats.averageChannelDelta() },
    );
    try dumpFailure(allocator, case_name, expected_slug, actual_slug, expected, actual);
    return error.BackendPixelMismatch;
}

fn checkBackendAgainstCpu(
    allocator: std.mem.Allocator,
    case_name: []const u8,
    backend_name: []const u8,
    backend_slug: []const u8,
    cpu_pixels: []const u8,
    backend_pixels: []const u8,
) !void {
    try checkPixelMatch(allocator, case_name, "CPU", "cpu", backend_name, backend_slug, cpu_pixels, backend_pixels, cpu_backend_policy);
}

fn checkGpuConsistency(
    allocator: std.mem.Allocator,
    case_name: []const u8,
    gl_name: []const u8,
    gl_pixels: []const u8,
    vk_name: []const u8,
    vk_pixels: []const u8,
) !void {
    try checkPixelMatch(allocator, case_name, gl_name, "gl", vk_name, "vulkan", gl_pixels, vk_pixels, gpu_consistency_policy);
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var scene_bundle = try buildScene(allocator);
    defer scene_bundle.deinit();

    var gl_ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT);
    defer gl_ctx.deinit();
    const framebuffer = try initFramebuffer(GL_SRGB8_ALPHA8);
    defer {
        var fbo = framebuffer.fbo;
        var texture = framebuffer.texture;
        gl.glDeleteFramebuffers(1, &fbo);
        gl.glDeleteTextures(1, &texture);
    }
    const linear_framebuffer = try initFramebuffer(GL_RGBA8);
    defer {
        var fbo = linear_framebuffer.fbo;
        var texture = linear_framebuffer.texture;
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

    var any_failure = false;
    for (cases) |case| {
        const options = drawOptions(case.subpixel_order);
        const cpu_pixels = try renderCpu(allocator, &scene_bundle.scene, options);
        defer allocator.free(cpu_pixels);

        var gl_pixels_opt: ?[]u8 = null;
        defer if (gl_pixels_opt) |p| allocator.free(p);
        if (!case.requires_dual_source or gl_supports_lcd) {
            gl_pixels_opt = try renderGl(allocator, &gl_renderer, framebuffer.fbo, &scene_bundle.scene, options);
            checkBackendAgainstCpu(allocator, case.name, gl_renderer_state.backendName(), "gl", cpu_pixels, gl_pixels_opt.?) catch {
                any_failure = true;
            };
        } else {
            std.debug.print("{s}: skipping OpenGL LCD compare; dual-source blending unavailable\n", .{case.name});
        }

        if (comptime build_options.enable_vulkan) {
            if (!case.requires_dual_source or vk_supports_lcd) {
                const vk_pixels = try renderVulkan(allocator, &vk_renderer_state, &vk_renderer, &scene_bundle.scene, options);
                defer allocator.free(vk_pixels);
                checkBackendAgainstCpu(allocator, case.name, vk_renderer_state.backendName(), "vulkan", cpu_pixels, vk_pixels) catch {
                    any_failure = true;
                };
                if (gl_pixels_opt) |gl_pixels| {
                    checkGpuConsistency(allocator, case.name, gl_renderer_state.backendName(), gl_pixels, vk_renderer_state.backendName(), vk_pixels) catch {
                        any_failure = true;
                    };
                }
            } else {
                std.debug.print("{s}: skipping Vulkan LCD compare; dual-source blending unavailable\n", .{case.name});
            }
        } else if (!case.requires_dual_source) {
            std.debug.print("{s}: Vulkan disabled (`zig build backend-compare -Dvulkan=false`)\n", .{case.name});
        }

        if (!case.requires_dual_source or gl_supports_lcd) {
            const linear_case_name = try std.fmt.allocPrint(allocator, "{s}-linear-resolve", .{case.name});
            defer allocator.free(linear_case_name);
            const linear_options = linearResolveDrawOptions(case.subpixel_order);
            const cpu_linear_pixels = try renderCpuSeeded(allocator, &scene_bundle.scene, linear_options, LINEAR_RESOLVE_SEED);
            defer allocator.free(cpu_linear_pixels);
            const gl_linear_pixels = try renderGlSeeded(allocator, &gl_renderer, linear_framebuffer.fbo, &scene_bundle.scene, linear_options, LINEAR_RESOLVE_SEED);
            defer allocator.free(gl_linear_pixels);
            checkBackendAgainstCpu(allocator, linear_case_name, gl_renderer_state.backendName(), "gl", cpu_linear_pixels, gl_linear_pixels) catch {
                any_failure = true;
            };
        }
    }
    if (any_failure) return error.BackendPixelMismatch;
}

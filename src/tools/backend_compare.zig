const std = @import("std");
const build_options = @import("build_options");
const assets = @import("assets");
const snail = @import("snail");
const screenshot = @import("support").screenshot;
const egl_offscreen = @import("demo_platform_offscreen_gl");
const gl = @import("support").gl;
const vulkan_platform = if (build_options.enable_vulkan) @import("demo_platform_vulkan") else struct {};

const WIDTH: u32 = 220;
const HEIGHT: u32 = 112;
const GL_RGBA8: gl.GLenum = 0x8058;
const GL_SRGB8_ALPHA8: gl.GLenum = 0x8C43;
const DUMP_DIR = "zig-out/backend-compare";
const DEVANAGARI_TEXT = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87";
const LINEAR_RESOLVE_SEED = [4]u8{ 34, 45, 59, 255 };
const LINEAR_RESOLVE = snail.LinearResolve{};
const APPEND_BASE_TEXT = "ABCDEFGHIJKLMNOPQRSTUVWXY";
const APPEND_DRAW_TEXT = "SNAP";
const APPEND_EXTRA_TEXT = "Z";
const SCENE_TEXT_ATLAS_KEY = snail.ResourceKey.named("backend-compare.scene-text-atlas");
const SCENE_LATIN_TEXT_KEY = snail.ResourceKey.named("backend-compare.scene-latin-text");
const SCENE_DEVANAGARI_TEXT_KEY = snail.ResourceKey.named("backend-compare.scene-devanagari-text");
const SCENE_PATH_KEY = snail.ResourceKey.named("backend-compare.scene-path");
const APPEND_RESOURCE_KEY = snail.ResourceKey.named("backend-compare.append-atlas");
const APPEND_TEXT_KEY = snail.ResourceKey.named("backend-compare.append-text");
const PATH_BAND_RESOURCE_KEY = snail.ResourceKey.named("backend-compare.path-band");
const BAND_STRESS_FILL = [4]f32{ 0.58, 0.68, 0.54, 1.0 };

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

const EdgePolicy = struct {
    edge_threshold: u8,
    edge_radius: u32,
};

const LowPassPolicy = struct {
    tolerance: u8,
    max_channel_delta: u8,
    average_budget: f64,
};

const CpuBackendPolicy = struct {
    raw: ComparePolicy,
    edge: EdgePolicy,
    low_pass: LowPassPolicy,
};

// CPU and GPU paths intentionally use different arithmetic. Keep raw drift
// bounded, require every raw outlier to be near a reference edge, and separately
// verify visual equivalence after a deterministic low-pass filter.
const cpu_backend_policy = CpuBackendPolicy{
    .raw = .{
        .tolerance = 1,
        .max_channel_delta = 64,
        .outlier_budget = 32,
        .average_budget = 0.05,
    },
    .edge = .{
        .edge_threshold = 8,
        .edge_radius = 2,
    },
    .low_pass = .{
        .tolerance = 1,
        .max_channel_delta = 12,
        .average_budget = 0.04,
    },
};

// GL and Vulkan should be the same shader algorithm. Allow only 2-LSB store
// rounding drift, and no channel may exceed that.
const gpu_consistency_policy = ComparePolicy{
    .tolerance = 2,
    .max_channel_delta = 2,
    .outlier_budget = 0,
    .average_budget = 1.0,
};

const exact_policy = ComparePolicy{
    .tolerance = 0,
    .max_channel_delta = 0,
    .outlier_budget = 0,
    .average_budget = 0.0,
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

fn drawState(subpixel_order: snail.SubpixelOrder) snail.DrawState {
    const wf: f32 = @floatFromInt(WIDTH);
    const hf: f32 = @floatFromInt(HEIGHT);
    return .{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .surface = .{
            .pixel_width = wf,
            .pixel_height = hf,
            .encoding = .srgb,
        },
        .raster = .{ .subpixel_order = subpixel_order },
    };
}

fn linearResolveDrawState(subpixel_order: snail.SubpixelOrder) snail.DrawState {
    var state = drawState(subpixel_order);
    state.surface.encoding = .srgb_pixels_on_linear_attachment;
    return state;
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
    // Keep baselines off exact half-pixel samples for the LCD compare; CPU and
    // GPU subpixel paths still have tiny interpolation-order differences there.
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
    try scene.addPath(.{ .picture = picture, .resource_key = SCENE_PATH_KEY });
    try scene.addText(.{
        .blob = latin_blob,
        .resources = latin_blob.resourceKeys(SCENE_TEXT_ATLAS_KEY, SCENE_LATIN_TEXT_KEY),
    });
    try scene.addText(.{
        .blob = devanagari_blob,
        .resources = devanagari_blob.resourceKeys(SCENE_TEXT_ATLAS_KEY, SCENE_DEVANAGARI_TEXT_KEY),
    });

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
    var entries: [8]snail.ResourceManifest.Entry = undefined;
    var set = snail.ResourceManifest.init(&entries);
    for (scene.commands.items) |command| switch (command) {
        .text => |text| try set.putTextBlob(text.resources, text.blob),
        .path => |path| try set.putPathPicture(path.resource_key, path.picture),
    };
    return renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set);
}

fn uploadTextBlobResourceWithCapacity(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    atlas_key: snail.ResourceKey,
    blob_key: snail.ResourceKey,
    blob: *const snail.TextBlob,
    capacity: snail.ResourceCapacityMode,
) !snail.PreparedResources {
    var entries: [2]snail.ResourceManifest.Entry = undefined;
    var set = snail.ResourceManifest.init(&entries);
    try set.putTextBlobOptions(blob.resourceKeys(atlas_key, blob_key), blob, .{ .atlas_capacity = capacity });
    return renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set);
}

const AppendPlanExpectation = struct {
    new_atlas_banks: u32 = 0,
    atlas_rebuilds: u32 = 0,
};

fn checkAppendPlanForTextBlob(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    current: *const snail.PreparedResources,
    atlas_key: snail.ResourceKey,
    blob_key: snail.ResourceKey,
    blob: *const snail.TextBlob,
    capacity: snail.ResourceCapacityMode,
    expected: AppendPlanExpectation,
) !void {
    var entries: [2]snail.ResourceManifest.Entry = undefined;
    var set = snail.ResourceManifest.init(&entries);
    try set.putTextBlobOptions(blob.resourceKeys(atlas_key, blob_key), blob, .{ .atlas_capacity = capacity });
    var plan = try renderer.planResourceUpload(allocator, current, &set);
    defer plan.deinit();
    try expectAppendPlan(&plan, current.manifest.atlases[0].page_fingerprints.len, blob.atlas.pageCount(), expected);
}

fn expectAppendPlan(plan: *const snail.ResourceUploadPlan, old_pages: usize, new_pages: usize, expected: AppendPlanExpectation) !void {
    if (plan.cache.reused_atlas_pages != old_pages) return error.AppendPlanDidNotReusePages;
    if (plan.cache.missing_atlas_pages != new_pages - old_pages) return error.AppendPlanMissingPageMismatch;
    if (plan.cache.new_atlas_banks != expected.new_atlas_banks) return error.AppendPlanBankMismatch;
    if (plan.cache.atlas_rebuilds != expected.atlas_rebuilds) return error.AppendPlanRebuildMismatch;
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
    options: snail.DrawState,
) ![]u8 {
    return renderCpuSeeded(allocator, scene, options, .{ 0, 0, 0, 255 });
}

fn renderCpuSeeded(
    allocator: std.mem.Allocator,
    scene: *const snail.Scene,
    options: snail.DrawState,
    seed: [4]u8,
) ![]u8 {
    const pixels = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    errdefer allocator.free(pixels);
    clearPixelsTo(pixels, seed);

    var cpu = snail.CpuRenderer.init(pixels.ptr, WIDTH, HEIGHT, WIDTH * 4);
    var renderer = cpu.asRenderer();
    var prepared = try uploadSceneResources(allocator, &renderer, scene);
    defer prepared.deinit();
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, scene);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, options);
    return pixels;
}

fn renderCpuLinearSeeded(
    allocator: std.mem.Allocator,
    scene: *const snail.Scene,
    state: snail.DrawState,
    seed: [4]u8,
    resolve: snail.LinearResolve,
) ![]u8 {
    const pixels = try allocator.alloc(u8, WIDTH * HEIGHT * 4);
    errdefer allocator.free(pixels);
    clearPixelsTo(pixels, seed);

    var cpu = snail.CpuRenderer.init(pixels.ptr, WIDTH, HEIGHT, WIDTH * 4);
    var renderer = cpu.asRenderer();
    var prepared = try uploadSceneResources(allocator, &renderer, scene);
    defer prepared.deinit();
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, scene);
    defer prepared_scene.deinit();
    try renderer.drawPreparedPass(&prepared, &prepared_scene, .{ .state = state, .resolve = .{ .linear = resolve } });
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
    options: snail.DrawState,
) ![]u8 {
    return renderGlSeeded(allocator, renderer, fbo, scene, options, .{ 0, 0, 0, 255 });
}

fn renderGlSeeded(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    fbo: gl.GLuint,
    scene: *const snail.Scene,
    options: snail.DrawState,
    seed: [4]u8,
) ![]u8 {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glViewport(0, 0, WIDTH, HEIGHT);
    clearGlTo(seed);

    var prepared = try uploadSceneResources(allocator, renderer, scene);
    defer prepared.deinit();
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, scene);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, options);
    gl.glFinish();

    const pixels = try screenshot.captureFramebuffer(allocator, WIDTH, HEIGHT);
    flipRowsInPlace(pixels);
    return pixels;
}

fn renderGlLinearSeeded(
    allocator: std.mem.Allocator,
    gl_renderer: *snail.GlRenderer,
    fbo: gl.GLuint,
    scene: *const snail.Scene,
    state: snail.DrawState,
    seed: [4]u8,
    resolve: snail.LinearResolve,
) ![]u8 {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glViewport(0, 0, WIDTH, HEIGHT);
    clearGlTo(seed);

    var renderer = gl_renderer.asRenderer();
    var prepared = try uploadSceneResources(allocator, &renderer, scene);
    defer prepared.deinit();
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, scene);
    defer prepared_scene.deinit();
    try renderer.drawPreparedPass(&prepared, &prepared_scene, .{ .state = state, .resolve = .{ .linear = resolve } });
    gl.glFinish();

    const pixels = try screenshot.captureFramebuffer(allocator, WIDTH, HEIGHT);
    flipRowsInPlace(pixels);
    return pixels;
}

fn drawPreparedGlToPixels(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    fbo: gl.GLuint,
    prepared: *const snail.PreparedResources,
    scene: *const snail.PreparedScene,
    options: snail.DrawState,
    seed: [4]u8,
) ![]u8 {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glViewport(0, 0, WIDTH, HEIGHT);
    clearGlTo(seed);
    try renderer.drawPrepared(prepared, scene, options);
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
    options: snail.DrawState,
) ![]u8 {
    if (comptime !build_options.enable_vulkan) unreachable;

    var prepared = try uploadSceneResources(allocator, renderer, scene);
    defer prepared.deinit();
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, scene);
    defer prepared_scene.deinit();

    const cmd = vulkan_platform.beginFrameOffscreenWithClear(.{ 0.0, 0.0, 0.0, 1.0 });
    const frame = vk_renderer.frame(.{ .cmd = cmd, .slot = vulkan_platform.currentOffscreenFrameIndex() });
    try frame.drawPrepared(&prepared, &prepared_scene, options);
    vulkan_platform.endFrameOffscreen();
    vulkan_platform.queueWaitIdle();
    return vulkan_platform.captureOffscreenRgba8(allocator);
}

fn drawPreparedVulkanToPixels(
    allocator: std.mem.Allocator,
    vk_renderer: *snail.VulkanRenderer,
    renderer: *snail.Renderer,
    prepared: *const snail.PreparedResources,
    scene: *const snail.PreparedScene,
    options: snail.DrawState,
) ![]u8 {
    if (comptime !build_options.enable_vulkan) unreachable;
    _ = renderer;

    const cmd = vulkan_platform.beginFrameOffscreenWithClear(.{ 0.0, 0.0, 0.0, 1.0 });
    const frame = vk_renderer.frame(.{ .cmd = cmd, .slot = vulkan_platform.currentOffscreenFrameIndex() });
    try frame.drawPrepared(prepared, scene, options);
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

fn channelDelta(lhs: u8, rhs: u8) u8 {
    return if (lhs > rhs) lhs - rhs else rhs - lhs;
}

fn pixelMaxDelta(expected: []const u8, actual: []const u8, pixel: usize) u8 {
    const base = pixel * 4;
    var max_delta: u8 = 0;
    for (0..4) |channel| {
        max_delta = @max(max_delta, channelDelta(expected[base + channel], actual[base + channel]));
    }
    return max_delta;
}

fn pixelEdgeMagnitude(pixels: []const u8, x: u32, y: u32) u8 {
    const center = (@as(usize, y) * WIDTH + @as(usize, x)) * 4;
    const offsets = [_]i32{ -1, 0, 1 };
    const width_i: i32 = @intCast(WIDTH);
    const height_i: i32 = @intCast(HEIGHT);
    const x_i: i32 = @intCast(x);
    const y_i: i32 = @intCast(y);
    var result: u8 = 0;

    for (offsets) |dy| {
        for (offsets) |dx| {
            if (dx == 0 and dy == 0) continue;
            const nx = x_i + dx;
            const ny = y_i + dy;
            if (nx < 0 or ny < 0 or nx >= width_i or ny >= height_i) continue;
            const neighbor = (@as(usize, @intCast(ny)) * WIDTH + @as(usize, @intCast(nx))) * 4;
            for (0..4) |channel| {
                result = @max(result, channelDelta(pixels[center + channel], pixels[neighbor + channel]));
            }
        }
    }
    return result;
}

fn isNearReferenceEdge(expected: []const u8, pixel: usize, policy: EdgePolicy) bool {
    const px: i32 = @intCast(pixel % WIDTH);
    const py: i32 = @intCast(pixel / WIDTH);
    const radius: i32 = @intCast(policy.edge_radius);
    const width_i: i32 = @intCast(WIDTH);
    const height_i: i32 = @intCast(HEIGHT);

    var y = py - radius;
    while (y <= py + radius) : (y += 1) {
        if (y < 0 or y >= height_i) continue;
        var x = px - radius;
        while (x <= px + radius) : (x += 1) {
            if (x < 0 or x >= width_i) continue;
            if (pixelEdgeMagnitude(expected, @intCast(x), @intCast(y)) >= policy.edge_threshold) return true;
        }
    }
    return false;
}

const EdgeOutlierStats = struct {
    outlier_pixels: usize = 0,
    non_edge_pixels: usize = 0,
    worst_offset: usize = 0,
    max_channel_delta: u8 = 0,
};

fn compareEdgeLocalizedOutliers(expected: []const u8, actual: []const u8, raw_tolerance: u8, policy: EdgePolicy) EdgeOutlierStats {
    std.debug.assert(expected.len == actual.len);
    var stats = EdgeOutlierStats{};
    const pixel_count = expected.len / 4;
    for (0..pixel_count) |pixel| {
        const delta = pixelMaxDelta(expected, actual, pixel);
        if (delta <= raw_tolerance) continue;
        stats.outlier_pixels += 1;
        if (delta > stats.max_channel_delta) {
            stats.max_channel_delta = delta;
            stats.worst_offset = pixel * 4;
        }
        if (!isNearReferenceEdge(expected, pixel, policy)) stats.non_edge_pixels += 1;
    }
    return stats;
}

// Separable binomial [1 4 6 4 1] / 16 low-pass. This smooths one-pixel
// coverage phase differences without pulling in a perceptual-image dependency.
const blur_weights = [_]u16{ 1, 4, 6, 4, 1 };

fn clampCoord(v: i32, max: u32) u32 {
    if (v <= 0) return 0;
    const max_i: i32 = @intCast(max - 1);
    if (v >= max_i) return @intCast(max_i);
    return @intCast(v);
}

fn lowPassChannel(pixels: []const u8, x: u32, y: u32, channel: usize) u8 {
    var sum: u32 = 0;
    const x_i: i32 = @intCast(x);
    const y_i: i32 = @intCast(y);
    for (blur_weights, 0..) |wy, ky| {
        const sy = clampCoord(y_i + @as(i32, @intCast(ky)) - 2, HEIGHT);
        for (blur_weights, 0..) |wx, kx| {
            const sx = clampCoord(x_i + @as(i32, @intCast(kx)) - 2, WIDTH);
            const weight = @as(u32, wy) * @as(u32, wx);
            const offset = (@as(usize, sy) * WIDTH + @as(usize, sx)) * 4 + channel;
            sum += weight * pixels[offset];
        }
    }
    return @intCast((sum + 128) / 256);
}

fn compareLowPassPixels(expected: []const u8, actual: []const u8, tolerance: u8) CompareStats {
    std.debug.assert(expected.len == actual.len);
    var stats = CompareStats{ .pixel_count = expected.len / 4 };
    for (0..HEIGHT) |y| {
        for (0..WIDTH) |x| {
            var pixel_mismatch = false;
            const pixel = y * WIDTH + x;
            for (0..4) |channel| {
                const expected_channel = lowPassChannel(expected, @intCast(x), @intCast(y), channel);
                const actual_channel = lowPassChannel(actual, @intCast(x), @intCast(y), channel);
                const delta = channelDelta(expected_channel, actual_channel);
                stats.total_channel_delta += delta;
                if (delta > stats.max_channel_delta) {
                    stats.max_channel_delta = delta;
                    stats.worst_offset = pixel * 4 + channel;
                }
                if (delta > tolerance) pixel_mismatch = true;
            }
            if (pixel_mismatch) stats.mismatched_pixels += 1;
        }
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
    const raw_stats = comparePixels(cpu_pixels, backend_pixels, cpu_backend_policy.raw.tolerance);
    const raw_pass = raw_stats.mismatched_pixels <= cpu_backend_policy.raw.outlier_budget and
        raw_stats.averageChannelDelta() <= cpu_backend_policy.raw.average_budget and
        raw_stats.max_channel_delta <= cpu_backend_policy.raw.max_channel_delta;
    if (!raw_pass) {
        const pixel = raw_stats.worst_offset / 4;
        const x = pixel % WIDTH;
        const y = pixel / WIDTH;
        std.debug.print(
            "{s}: {s} differs from CPU raw pixels: {d}/{d} pixels over {d} LSB, max channel delta {d} at ({d}, {d}), avg channel delta {d:.3}\n",
            .{ case_name, backend_name, raw_stats.mismatched_pixels, raw_stats.pixel_count, cpu_backend_policy.raw.tolerance, raw_stats.max_channel_delta, x, y, raw_stats.averageChannelDelta() },
        );
        try dumpFailure(allocator, case_name, "cpu", backend_slug, cpu_pixels, backend_pixels);
        return error.BackendPixelMismatch;
    }

    const edge_stats = compareEdgeLocalizedOutliers(cpu_pixels, backend_pixels, cpu_backend_policy.raw.tolerance, cpu_backend_policy.edge);
    if (edge_stats.non_edge_pixels != 0) {
        const pixel = edge_stats.worst_offset / 4;
        const x = pixel % WIDTH;
        const y = pixel / WIDTH;
        std.debug.print(
            "{s}: {s} has {d}/{d} raw outliers away from CPU reference edges (radius {d}, edge threshold {d}); max delta {d} at ({d}, {d})\n",
            .{ case_name, backend_name, edge_stats.non_edge_pixels, edge_stats.outlier_pixels, cpu_backend_policy.edge.edge_radius, cpu_backend_policy.edge.edge_threshold, edge_stats.max_channel_delta, x, y },
        );
        try dumpFailure(allocator, case_name, "cpu", backend_slug, cpu_pixels, backend_pixels);
        return error.BackendPixelMismatch;
    }

    const low_pass_stats = compareLowPassPixels(cpu_pixels, backend_pixels, cpu_backend_policy.low_pass.tolerance);
    const low_pass_pass = low_pass_stats.averageChannelDelta() <= cpu_backend_policy.low_pass.average_budget and
        low_pass_stats.max_channel_delta <= cpu_backend_policy.low_pass.max_channel_delta;
    if (!low_pass_pass) {
        const pixel = low_pass_stats.worst_offset / 4;
        const x = pixel % WIDTH;
        const y = pixel / WIDTH;
        std.debug.print(
            "{s}: {s} differs from CPU after low-pass compare: {d}/{d} pixels over {d} LSB, max channel delta {d} at ({d}, {d}), avg channel delta {d:.3}\n",
            .{ case_name, backend_name, low_pass_stats.mismatched_pixels, low_pass_stats.pixel_count, cpu_backend_policy.low_pass.tolerance, low_pass_stats.max_channel_delta, x, y, low_pass_stats.averageChannelDelta() },
        );
        try dumpFailure(allocator, case_name, "cpu", backend_slug, cpu_pixels, backend_pixels);
        return error.BackendPixelMismatch;
    }

    std.debug.print(
        "{s}: {s} matches CPU (raw {d} pixels over {d} LSB, max delta {d}, avg {d:.3}; edge-localized {d}/{d}; low-pass {d} pixels over {d} LSB, max delta {d}, avg {d:.3})\n",
        .{
            case_name,
            backend_name,
            raw_stats.mismatched_pixels,
            cpu_backend_policy.raw.tolerance,
            raw_stats.max_channel_delta,
            raw_stats.averageChannelDelta(),
            edge_stats.outlier_pixels - edge_stats.non_edge_pixels,
            edge_stats.outlier_pixels,
            low_pass_stats.mismatched_pixels,
            cpu_backend_policy.low_pass.tolerance,
            low_pass_stats.max_channel_delta,
            low_pass_stats.averageChannelDelta(),
        },
    );
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

const AppendSceneBundle = struct {
    atlas: *snail.TextAtlas,
    blob: *snail.TextBlob,
    scene: snail.Scene,
    allocator: std.mem.Allocator,

    fn deinit(self: *AppendSceneBundle) void {
        self.scene.deinit();
        self.blob.deinit();
        self.allocator.destroy(self.blob);
        self.atlas.deinit();
        self.allocator.destroy(self.atlas);
        self.* = undefined;
    }
};

const PathBandStressBundle = struct {
    picture: *snail.PathPicture,
    overrides: []snail.Override,
    scene: snail.Scene,
    allocator: std.mem.Allocator,

    fn deinit(self: *PathBandStressBundle) void {
        self.scene.deinit();
        self.allocator.free(self.overrides);
        self.picture.deinit();
        self.allocator.destroy(self.picture);
        self.* = undefined;
    }
};

fn buildPathBandStressPicture(allocator: std.mem.Allocator) !snail.PathPicture {
    var builder = snail.PathPictureBuilder.init(allocator);
    defer builder.deinit();

    var path = snail.Path.init(allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 18.0, .y = 82.0 });
    try path.cubicTo(.{ .x = 34.0, .y = 38.0 }, .{ .x = 72.0, .y = 22.0 }, .{ .x = 105.0, .y = 36.0 });
    try path.cubicTo(.{ .x = 134.0, .y = 48.0 }, .{ .x = 158.0, .y = 18.0 }, .{ .x = 194.0, .y = 35.0 });
    try path.cubicTo(.{ .x = 214.0, .y = 45.0 }, .{ .x = 208.0, .y = 83.0 }, .{ .x = 178.0, .y = 93.0 });
    try path.cubicTo(.{ .x = 136.0, .y = 108.0 }, .{ .x = 72.0, .y = 103.0 }, .{ .x = 18.0, .y = 82.0 });
    try path.close();

    try builder.addPath(&path, .{ .paint = .{ .solid = BAND_STRESS_FILL } }, null, .identity);
    return builder.freeze(.{ .persistent_allocator = allocator, .scratch_allocator = allocator });
}

fn buildPathBandStressScene(allocator: std.mem.Allocator) !PathBandStressBundle {
    const picture = try allocator.create(snail.PathPicture);
    errdefer allocator.destroy(picture);
    picture.* = try buildPathBandStressPicture(allocator);
    errdefer picture.deinit();

    const overrides = try allocator.alloc(snail.Override, 1);
    errdefer allocator.free(overrides);
    overrides[0] = .{};

    var scene = snail.Scene.init(allocator);
    errdefer scene.deinit();
    try scene.addPath(.{ .picture = picture, .resource_key = PATH_BAND_RESOURCE_KEY, .instances = overrides });

    return .{
        .picture = picture,
        .overrides = overrides,
        .scene = scene,
        .allocator = allocator,
    };
}

fn buildAppendScene(allocator: std.mem.Allocator) !AppendSceneBundle {
    const atlas = try allocator.create(snail.TextAtlas);
    errdefer allocator.destroy(atlas);
    atlas.* = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets.noto_sans_regular },
    });
    errdefer atlas.deinit();

    try ensureText(atlas, .{}, APPEND_BASE_TEXT);

    const blob = try allocator.create(snail.TextBlob);
    errdefer allocator.destroy(blob);
    blob.* = try buildTextBlob(allocator, atlas, APPEND_DRAW_TEXT, 18.0, 62.0, 32.0, .{ 0.9, 0.95, 1.0, 1.0 });
    errdefer blob.deinit();

    var scene = snail.Scene.init(allocator);
    errdefer scene.deinit();
    try scene.addText(.{
        .blob = blob,
        .resources = blob.resourceKeys(APPEND_RESOURCE_KEY, APPEND_TEXT_KEY),
    });

    return .{
        .atlas = atlas,
        .blob = blob,
        .scene = scene,
        .allocator = allocator,
    };
}

fn growAppendAtlas(base: *const snail.TextAtlas) !snail.TextAtlas {
    const grown = try base.ensureText(.{}, APPEND_EXTRA_TEXT) orelse return error.AppendAtlasDidNotGrow;
    if (grown.pageCount() <= base.pageCount()) {
        var mutable = grown;
        mutable.deinit();
        return error.AppendAtlasDidNotGrow;
    }
    return grown;
}

fn uploadAppendedAtlas(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    current: *const snail.PreparedResources,
    grown: *const snail.TextAtlas,
    capacity: snail.ResourceCapacityMode,
    expected: AppendPlanExpectation,
) !snail.PreparedResources {
    var resource_blob = try buildTextBlob(allocator, grown, APPEND_EXTRA_TEXT, 18.0, 62.0, 32.0, .{ 0.95, 0.7, 0.2, 1.0 });
    defer resource_blob.deinit();
    try checkAppendPlanForTextBlob(allocator, renderer, current, APPEND_RESOURCE_KEY, APPEND_TEXT_KEY, &resource_blob, capacity, expected);
    return uploadTextBlobResourceWithCapacity(allocator, renderer, APPEND_RESOURCE_KEY, APPEND_TEXT_KEY, &resource_blob, capacity);
}

fn buildAppendedPagePreparedScene(
    allocator: std.mem.Allocator,
    prepared: *const snail.PreparedResources,
    atlas: *const snail.TextAtlas,
) !struct { blob: *snail.TextBlob, scene: snail.Scene, prepared_scene: snail.PreparedScene } {
    const blob = try allocator.create(snail.TextBlob);
    errdefer allocator.destroy(blob);
    blob.* = try buildTextBlob(allocator, atlas, APPEND_EXTRA_TEXT, 18.0, 62.0, 32.0, .{ 0.95, 0.7, 0.2, 1.0 });
    errdefer blob.deinit();

    var scene = snail.Scene.init(allocator);
    errdefer scene.deinit();
    try scene.addText(.{
        .blob = blob,
        .resources = blob.resourceKeys(APPEND_RESOURCE_KEY, APPEND_TEXT_KEY),
    });

    const prepared_scene = try snail.PreparedScene.initOwned(allocator, prepared, &scene);
    return .{ .blob = blob, .scene = scene, .prepared_scene = prepared_scene };
}

fn runGlAppendSnapshotRegression(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    fbo: gl.GLuint,
    backend_name: []const u8,
) !void {
    renderer.resetResourceCache();
    defer renderer.resetResourceCache();

    var bundle = try buildAppendScene(allocator);
    defer bundle.deinit();

    var prepared = try uploadTextBlobResourceWithCapacity(allocator, renderer, APPEND_RESOURCE_KEY, APPEND_TEXT_KEY, bundle.blob, .exact);
    defer prepared.deinit();
    const options = drawState(.none);
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, &bundle.scene);
    defer prepared_scene.deinit();

    const before = try drawPreparedGlToPixels(allocator, renderer, fbo, &prepared, &prepared_scene, options, .{ 0, 0, 0, 255 });
    defer allocator.free(before);

    var grown = try growAppendAtlas(bundle.atlas);
    defer grown.deinit();
    var appended = try uploadAppendedAtlas(allocator, renderer, &prepared, &grown, .exact, .{ .new_atlas_banks = 1 });
    defer appended.deinit();

    const after = try drawPreparedGlToPixels(allocator, renderer, fbo, &prepared, &prepared_scene, options, .{ 0, 0, 0, 255 });
    defer allocator.free(after);

    try checkPixelMatch(allocator, "append-snapshot", backend_name, "gl-before", backend_name, "gl-after", before, after, exact_policy);

    var appended_draw = try buildAppendedPagePreparedScene(allocator, &appended, &grown);
    defer {
        appended_draw.blob.deinit();
        allocator.destroy(appended_draw.blob);
    }
    defer appended_draw.scene.deinit();
    defer appended_draw.prepared_scene.deinit();
    const bank_cpu = try renderCpu(allocator, &appended_draw.scene, options);
    defer allocator.free(bank_cpu);
    const bank_gl = try drawPreparedGlToPixels(allocator, renderer, fbo, &appended, &appended_draw.prepared_scene, options, .{ 0, 0, 0, 255 });
    defer allocator.free(bank_gl);
    try checkBackendAgainstCpu(allocator, "append-bank", backend_name, "gl", bank_cpu, bank_gl);
}

fn runVulkanAppendSnapshotRegression(
    allocator: std.mem.Allocator,
    vk_renderer: *snail.VulkanRenderer,
    renderer: *snail.Renderer,
    backend_name: []const u8,
) !void {
    if (comptime !build_options.enable_vulkan) unreachable;

    renderer.resetResourceCache();
    defer renderer.resetResourceCache();

    var bundle = try buildAppendScene(allocator);
    defer bundle.deinit();

    var prepared = try uploadTextBlobResourceWithCapacity(allocator, renderer, APPEND_RESOURCE_KEY, APPEND_TEXT_KEY, bundle.blob, .exact);
    defer prepared.deinit();
    const options = drawState(.none);
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, &bundle.scene);
    defer prepared_scene.deinit();

    const before = try drawPreparedVulkanToPixels(allocator, vk_renderer, renderer, &prepared, &prepared_scene, options);
    defer allocator.free(before);

    var grown = try growAppendAtlas(bundle.atlas);
    defer grown.deinit();
    var appended = try uploadAppendedAtlas(allocator, renderer, &prepared, &grown, .exact, .{ .new_atlas_banks = 1 });
    defer appended.deinit();

    const after = try drawPreparedVulkanToPixels(allocator, vk_renderer, renderer, &prepared, &prepared_scene, options);
    defer allocator.free(after);

    try checkPixelMatch(allocator, "append-snapshot", backend_name, "vulkan-before", backend_name, "vulkan-after", before, after, exact_policy);

    var appended_draw = try buildAppendedPagePreparedScene(allocator, &appended, &grown);
    defer {
        appended_draw.blob.deinit();
        allocator.destroy(appended_draw.blob);
    }
    defer appended_draw.scene.deinit();
    defer appended_draw.prepared_scene.deinit();
    const bank_cpu = try renderCpu(allocator, &appended_draw.scene, options);
    defer allocator.free(bank_cpu);
    const bank_vk = try drawPreparedVulkanToPixels(allocator, vk_renderer, renderer, &appended, &appended_draw.prepared_scene, options);
    defer allocator.free(bank_vk);
    try checkBackendAgainstCpu(allocator, "append-bank", backend_name, "vulkan", bank_cpu, bank_vk);
}

fn runPathBandSpanRegression(
    allocator: std.mem.Allocator,
    gl_renderer: *snail.Renderer,
    gl_fbo: gl.GLuint,
    gl_name: []const u8,
    vk_renderer_state: if (build_options.enable_vulkan) *snail.VulkanRenderer else void,
    vk_renderer: if (build_options.enable_vulkan) *snail.Renderer else void,
    vk_name: if (build_options.enable_vulkan) []const u8 else void,
) !void {
    var bundle = try buildPathBandStressScene(allocator);
    defer bundle.deinit();

    const options = drawState(.none);
    const shape_origin = bundle.picture.shapes[0].transform.applyPoint(.zero);
    const scales = [_]f32{ 0.62, 0.83, 1.07, 1.31 };
    const offsets = [_]f32{ -0.49, -0.17, 0.0, 0.17, 0.49 };

    var case_index: usize = 0;
    for (scales) |scale| {
        for (offsets) |offset| {
            const target_x = 106.5 + offset;
            const target_y = 58.5 - offset * 0.5;
            const tx = target_x - shape_origin.x * scale;
            const ty = target_y - shape_origin.y * scale;
            bundle.overrides[0].transform = snail.Transform2D.multiply(
                snail.Transform2D.translate(tx, ty),
                snail.Transform2D.scale(scale, scale),
            );

            const case_name = try std.fmt.allocPrint(allocator, "path-band-span-{d}", .{case_index});
            defer allocator.free(case_name);
            case_index += 1;

            const cpu_pixels = try renderCpu(allocator, &bundle.scene, options);
            defer allocator.free(cpu_pixels);

            const gl_pixels = try renderGl(allocator, gl_renderer, gl_fbo, &bundle.scene, options);
            defer allocator.free(gl_pixels);
            try checkBackendAgainstCpu(allocator, case_name, gl_name, "gl", cpu_pixels, gl_pixels);

            if (comptime build_options.enable_vulkan) {
                const vk_pixels = try renderVulkan(allocator, vk_renderer_state, vk_renderer, &bundle.scene, options);
                defer allocator.free(vk_pixels);
                try checkBackendAgainstCpu(allocator, case_name, vk_name, "vulkan", cpu_pixels, vk_pixels);
            }
        }
    }
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
        vk_renderer_state = try snail.VulkanRenderer.init(allocator, vk_ctx);
        errdefer vk_renderer_state.deinit();
        vk_renderer = vk_renderer_state.asRenderer();
        vk_supports_lcd = vk_renderer_state.state.ctx.supports_dual_source_blend;
    }
    defer if (build_options.enable_vulkan) {
        vk_renderer_state.deinit();
        vulkan_platform.deinitOffscreen();
    };

    try runGlAppendSnapshotRegression(allocator, &gl_renderer, framebuffer.fbo, gl_renderer_state.backendName());
    if (comptime build_options.enable_vulkan) {
        try runVulkanAppendSnapshotRegression(allocator, &vk_renderer_state, &vk_renderer, vk_renderer_state.backendName());
    }
    try runPathBandSpanRegression(
        allocator,
        &gl_renderer,
        framebuffer.fbo,
        gl_renderer_state.backendName(),
        if (build_options.enable_vulkan) &vk_renderer_state else {},
        if (build_options.enable_vulkan) &vk_renderer else {},
        if (build_options.enable_vulkan) vk_renderer_state.backendName() else {},
    );

    const cases = [_]CompareCase{
        .{ .name = "grayscale", .subpixel_order = .none },
        .{ .name = "subpixel-rgb", .subpixel_order = .rgb, .requires_dual_source = true },
    };

    var any_failure = false;
    for (cases) |case| {
        const options = drawState(case.subpixel_order);
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
            std.debug.print("{s}: Vulkan disabled (`zig build run-backend-compare -Dvulkan=false`)\n", .{case.name});
        }

        if (!case.requires_dual_source or gl_supports_lcd) {
            const linear_case_name = try std.fmt.allocPrint(allocator, "{s}-linear-resolve", .{case.name});
            defer allocator.free(linear_case_name);
            const linear_options = linearResolveDrawState(case.subpixel_order);
            const cpu_linear_pixels = try renderCpuLinearSeeded(allocator, &scene_bundle.scene, linear_options, LINEAR_RESOLVE_SEED, LINEAR_RESOLVE);
            defer allocator.free(cpu_linear_pixels);
            const gl_linear_pixels = try renderGlLinearSeeded(allocator, &gl_renderer_state, linear_framebuffer.fbo, &scene_bundle.scene, linear_options, LINEAR_RESOLVE_SEED, LINEAR_RESOLVE);
            defer allocator.free(gl_linear_pixels);
            checkBackendAgainstCpu(allocator, linear_case_name, gl_renderer_state.backendName(), "gl", cpu_linear_pixels, gl_linear_pixels) catch {
                any_failure = true;
            };
        }
    }
    if (any_failure) return error.BackendPixelMismatch;
}

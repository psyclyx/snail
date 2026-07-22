//! Minimal Snail + OpenGL example.
//!
//! This file intentionally imports none of the demo renderer, cache, scene,
//! platform, or support modules. It owns the EGL context, GL resources, shader
//! entry points, atlas upload loop, draw submission, and screenshot writer. Its
//! one frame covers unhinted, autohinted, TT-hinted, and COLR text plus
//! filled and stroked paths.

const std = @import("std");
const snail = @import("snail");
const assets = @import("assets");

const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("EGL/egl.h");
    @cInclude("EGL/eglext.h");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
    @cInclude("stdio.h");
    @cInclude("sys/stat.h");
});

const width = 960;
const height = 420;
const text = "Hello, world!";
const ppem: u32 = 34 * 64;

const glsl = snail.shader.glsl;
const vertex_source: [:0]const u8 =
    "#version 330 core\n" ++
    glsl.source(.vertex_interface) ++ "\n" ++
    glsl.source(.color_common) ++ "\n" ++
    glsl.source(.vertex_body) ++ "\n" ++
    "void main() { snailVertex(); }\n";
const autohint_vertex_source: [:0]const u8 =
    "#version 330 core\n" ++
    glsl.source(.autohint_vertex_interface) ++ "\n" ++
    glsl.source(.color_common) ++ "\n" ++
    glsl.source(.autohint_warp) ++ "\n" ++
    glsl.source(.vertex_body) ++ "\n" ++
    glsl.source(.autohint_vertex_body) ++ "\n" ++
    "void main() { snailAutohintVertex(); }\n";
const regular_fragment_source: [:0]const u8 =
    "#version 330 core\n" ++
    glsl.source(.render_fragment_interface) ++ "\n" ++
    glsl.source(.render_abi) ++ "\n" ++
    glsl.source(.coverage_common) ++ "\n" ++
    glsl.source(.color_common) ++ "\n" ++
    glsl.source(.text_coverage_body) ++ "\n" ++
    glsl.source(.regular_text_body) ++ "\n" ++
    "void main() { snailTextFragment(); }\n";
const autohint_fragment_source: [:0]const u8 =
    "#version 330 core\n" ++
    glsl.source(.autohint_fragment_interface) ++ "\n" ++
    glsl.source(.render_abi) ++ "\n" ++
    glsl.source(.coverage_common) ++ "\n" ++
    glsl.source(.color_common) ++ "\n" ++
    glsl.source(.text_coverage_body) ++ "\n" ++
    glsl.source(.autohint_warp) ++ "\n" ++
    glsl.source(.autohint_fast_body) ++ "\n" ++
    "void main() { snailAutohintFragment(); }\n";
const tt_hint_fragment_source: [:0]const u8 =
    "#version 330 core\n" ++
    glsl.source(.render_fragment_interface) ++ "\n" ++
    glsl.source(.render_abi) ++ "\n" ++
    glsl.source(.coverage_common) ++ "\n" ++
    glsl.source(.color_common) ++ "\n" ++
    glsl.source(.text_coverage_body) ++ "\n" ++
    glsl.source(.tt_hinted_text_body) ++ "\n" ++
    "void main() { snailTtHintedTextFragment(); }\n";
const path_fragment_source: [:0]const u8 =
    "#version 330 core\n" ++
    glsl.source(.render_fragment_interface) ++ "\n" ++
    glsl.source(.render_abi) ++ "\n" ++
    glsl.source(.coverage_common) ++ "\n" ++
    glsl.source(.color_common) ++ "\n" ++
    glsl.source(.path_body) ++ "\n" ++
    "void main() { snailPathFragment(); }\n";
const colr_fragment_source: [:0]const u8 =
    "#version 330 core\n" ++
    glsl.source(.render_fragment_interface) ++ "\n" ++
    glsl.source(.render_abi) ++ "\n" ++
    glsl.source(.coverage_common) ++ "\n" ++
    glsl.source(.color_common) ++ "\n" ++
    glsl.source(.path_body) ++ "\n" ++
    glsl.source(.colr_body) ++ "\n" ++
    "void main() { snailColrFragment(); }\n";

const Programs = struct {
    regular: c.GLuint,
    autohint: c.GLuint,
    tt_hint: c.GLuint,
    path: c.GLuint,
    colr: c.GLuint,

    fn init() !Programs {
        var self = Programs{ .regular = 0, .autohint = 0, .tt_hint = 0, .path = 0, .colr = 0 };
        errdefer self.deinit();
        self.regular = try linkProgram(vertex_source, regular_fragment_source);
        self.autohint = try linkProgram(autohint_vertex_source, autohint_fragment_source);
        self.tt_hint = try linkProgram(vertex_source, tt_hint_fragment_source);
        self.path = try linkProgram(vertex_source, path_fragment_source);
        self.colr = try linkProgram(vertex_source, colr_fragment_source);
        return self;
    }

    fn deinit(self: Programs) void {
        c.glDeleteProgram(self.regular);
        c.glDeleteProgram(self.autohint);
        c.glDeleteProgram(self.tt_hint);
        c.glDeleteProgram(self.path);
        c.glDeleteProgram(self.colr);
    }

    fn forKind(self: Programs, kind: snail.render.records.ShapeKind) c.GLuint {
        return switch (kind) {
            .regular => self.regular,
            .autohint => self.autohint,
            .tt_hinted_text => self.tt_hint,
            .path => self.path,
            .colr => self.colr,
        };
    }
};

/// The complete caller-owned GPU side of a Snail atlas. Snail's planner says
/// which bytes changed; this type decides what GL objects receive them.
const GpuAtlas = struct {
    pool: *snail.PagePool,
    curve_tex: c.GLuint = 0,
    band_tex: c.GLuint = 0,
    layer_tex: c.GLuint = 0,
    uploads: snail.OwnedAtlasUploadPlanner,
    binding: ?snail.render.records.Binding = null,

    const options = snail.atlas_upload.Options{
        .max_bindings = 1,
        .layer_info_height = 256,
        .max_images = 0,
        .max_image_width = 0,
        .max_image_height = 0,
    };

    fn init(allocator: std.mem.Allocator, pool: *snail.PagePool) !GpuAtlas {
        var self = GpuAtlas{
            .pool = pool,
            .uploads = try snail.OwnedAtlasUploadPlanner.init(allocator, pool, options),
        };
        errdefer self.uploads.deinit();
        self.createTextures();
        return self;
    }

    fn deinit(self: *GpuAtlas) void {
        c.glDeleteTextures(1, &self.curve_tex);
        c.glDeleteTextures(1, &self.band_tex);
        c.glDeleteTextures(1, &self.layer_tex);
        self.uploads.deinit();
        self.* = undefined;
    }

    fn createTextures(self: *GpuAtlas) void {
        const curve_height = self.pool.options.curve_words_per_page / (snail.atlas_upload.CURVE_TEX_WIDTH * 4);
        const band_height = self.pool.options.band_words_per_page / (snail.atlas_upload.BAND_TEX_WIDTH * 2);

        c.glGenTextures(1, &self.curve_tex);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, self.curve_tex);
        c.glTexImage3D(c.GL_TEXTURE_2D_ARRAY, 0, c.GL_RGBA16F, snail.atlas_upload.CURVE_TEX_WIDTH, @intCast(curve_height), @intCast(self.pool.options.max_layers), 0, c.GL_RGBA, c.GL_HALF_FLOAT, null);
        setNearest(c.GL_TEXTURE_2D_ARRAY);

        c.glGenTextures(1, &self.band_tex);
        c.glActiveTexture(c.GL_TEXTURE1);
        c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, self.band_tex);
        c.glTexImage3D(c.GL_TEXTURE_2D_ARRAY, 0, c.GL_RG16UI, snail.atlas_upload.BAND_TEX_WIDTH, @intCast(band_height), @intCast(self.pool.options.max_layers), 0, c.GL_RG_INTEGER, c.GL_UNSIGNED_SHORT, null);
        setNearest(c.GL_TEXTURE_2D_ARRAY);

        c.glGenTextures(1, &self.layer_tex);
        c.glActiveTexture(c.GL_TEXTURE2);
        c.glBindTexture(c.GL_TEXTURE_2D, self.layer_tex);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA32F, snail.atlas_upload.INFO_WIDTH, options.layer_info_height, 0, c.GL_RGBA, c.GL_FLOAT, null);
        setNearest(c.GL_TEXTURE_2D);
    }

    /// Upload after every `Atlas.extend`. A delta stays in the existing slot
    /// when its metadata reservation still fits. Adding autohint/TT/path
    /// records can grow layer-info, so the documented fallback releases the
    /// old slot and plans a larger one; already-resident curve pages remain
    /// tracked and are not redundantly prepared.
    fn upload(self: *GpuAtlas, atlas: *const snail.Atlas) !void {
        const planned = if (self.binding) |old|
            self.uploads.planDelta(old, atlas) catch |err| switch (err) {
                error.NoLayerInfoRoomToGrow, error.NoImageRoomToGrow => blk: {
                    std.debug.assert(self.uploads.release(old));
                    break :blk try self.uploads.plan(atlas);
                },
                else => return err,
            }
        else
            try self.uploads.plan(atlas);

        for (planned.regions) |region| self.apply(region);
        self.binding = planned.binding;
    }

    fn apply(self: *GpuAtlas, region: snail.atlas_upload.Region) void {
        switch (region.target) {
            .curve => {
                c.glActiveTexture(c.GL_TEXTURE0);
                c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, self.curve_tex);
                c.glTexSubImage3D(c.GL_TEXTURE_2D_ARRAY, 0, @intCast(region.col_base), @intCast(region.row_base), @intCast(region.layer), @intCast(region.width), @intCast(region.height), 1, c.GL_RGBA, c.GL_HALF_FLOAT, region.src.ptr);
            },
            .band => {
                c.glActiveTexture(c.GL_TEXTURE1);
                c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, self.band_tex);
                c.glTexSubImage3D(c.GL_TEXTURE_2D_ARRAY, 0, @intCast(region.col_base), @intCast(region.row_base), @intCast(region.layer), @intCast(region.width), @intCast(region.height), 1, c.GL_RG_INTEGER, c.GL_UNSIGNED_SHORT, region.src.ptr);
            },
            .layer_info => {
                c.glActiveTexture(c.GL_TEXTURE2);
                c.glBindTexture(c.GL_TEXTURE_2D, self.layer_tex);
                c.glTexSubImage2D(c.GL_TEXTURE_2D, 0, 0, @intCast(region.row_base), @intCast(region.width), @intCast(region.height), c.GL_RGBA, c.GL_FLOAT, region.src.ptr);
            },
            .image => unreachable,
        }
    }

    fn bind(self: *const GpuAtlas) void {
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, self.curve_tex);
        c.glActiveTexture(c.GL_TEXTURE1);
        c.glBindTexture(c.GL_TEXTURE_2D_ARRAY, self.band_tex);
        c.glActiveTexture(c.GL_TEXTURE2);
        c.glBindTexture(c.GL_TEXTURE_2D, self.layer_tex);
    }
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var egl = try initEgl();
    defer egl.deinit();

    var font = try snail.Font.init(assets.dejavu_sans_mono);
    var emoji_font = try snail.Font.init(assets.twemoji_mozilla);
    var faces = try snail.Faces.build(allocator, &.{
        .{ .font = &font },
        .{ .font = &emoji_font, .fallback = true },
    });
    defer faces.deinit();
    const font_id = faces.fontIdForFace(0).?;

    var seed = try snail.shape(allocator, &faces, "Hello, ", .{});
    defer seed.deinit();
    var shaped = try snail.shape(allocator, &faces, text, .{});
    defer shaped.deinit();
    var emoji = try snail.shape(allocator, &faces, "\xF0\x9F\x8C\x8D", .{});
    defer emoji.deinit();

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 17,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var gpu = try GpuAtlas.init(allocator, pool);
    defer gpu.deinit();

    // Round 1: seed a new atlas with the first part of the unhinted run.
    var atlas = try snail.Atlas.init(allocator, pool);
    defer atlas.deinit();
    try snail.recordUnhintedRun(&atlas, allocator, &faces, &seed, .{});
    try gpu.upload(&atlas);

    // Round 2: extend it with the remaining unhinted glyphs. This is the
    // ordinary hot path: `planDelta` keeps the binding and uploads new pages.
    try snail.recordUnhintedRun(&atlas, allocator, &faces, &shaped, .{});
    try gpu.upload(&atlas);

    // Round 3: extend the same atlas with immutable autohint analysis.
    var analyzer = try snail.autohint.AutohintAnalyzer.init(allocator, assets.dejavu_sans_mono);
    defer analyzer.deinit();
    try snail.recordAutohintRun(&atlas, allocator, &analyzer, font_id, &shaped);
    try gpu.upload(&atlas);

    // Round 4: record per-PPEM TT-hinted curves (advances come along for
    // free), filled and stroked paths, and one composite COLR glyph. The
    // core helpers own all temporary font-atlas packing; only path
    // construction remains local.
    var tt_hint_vm = try snail.TtHintVm.init(allocator, &font);
    defer tt_hint_vm.deinit();
    var prepared = try tt_hint_vm.prepare(snail.TtHintPpem.uniform(ppem));
    defer prepared.deinit();
    try snail.recordTtHintRun(&atlas, allocator, &tt_hint_vm, &prepared, font_id, &shaped);
    const path_shapes = try extendWithPaths(allocator, &atlas);
    try snail.recordUnhintedRun(&atlas, allocator, &faces, &emoji, .{
        .colr_foreground = snail.color.srgbToLinearColor(.{ 0.18, 0.35, 0.70, 1.0 }),
    });
    const colr = try snail.placeRunAlloc(allocator, &emoji, null, .{
        .baseline = .{ .x = 775, .y = 145 },
        .em = 92,
        .color = .{ 1, 1, 1, 1 },
    });
    defer allocator.free(colr);
    std.debug.assert(colr.len == 1);
    const extras = [3]snail.Shape{
        path_shapes[0],
        path_shapes[1],
        colr[0],
    };
    try gpu.upload(&atlas);

    const autohint_policy = snail.autohint.AutohintPolicy{
        .x = .{ .@"align" = .grid, .stem_width = .{ .full = .{ .std_snap_ratio = 0.10 } }, .positioning = .relative },
        .y = .{ .@"align" = .blue_zones, .stem_width = .{ .full = .{ .std_snap_ratio = 0.10 } } },
    };
    const world_to_pixel = snail.Transform2D.identity;
    const unhinted = try snail.placeRunAlloc(allocator, &shaped, null, .{
        .baseline = .{ .x = 48, .y = 92 },
        .em = 34,
        .color = snail.color.srgbToLinearColor(.{ 0.10, 0.22, 0.48, 1.0 }),
        .mode = .unhinted,
    });
    defer allocator.free(unhinted);
    const autohinted = try snail.placeRunAlloc(allocator, &shaped, null, .{
        .baseline = .{ .x = 48, .y = 202 },
        .em = 34,
        .color = snail.color.srgbToLinearColor(.{ 0.18, 0.48, 0.30, 1.0 }),
        .mode = .{ .autohint = autohint_policy },
        .snap = .origins,
        .world_to_pixel = world_to_pixel,
    });
    defer allocator.free(autohinted);
    const tt_hinted = try snail.placeRunAlloc(allocator, &shaped, null, .{
        .baseline = .{ .x = 48, .y = 312 },
        .em = 34,
        .color = snail.color.srgbToLinearColor(.{ 0.54, 0.20, 0.20, 1.0 }),
        .mode = .{ .tt_hint = .{ .ppem_26_6 = ppem } },
        .snap = .origins,
        .world_to_pixel = world_to_pixel,
    });
    defer allocator.free(tt_hinted);

    const total_shapes = extras.len + unhinted.len + autohinted.len + tt_hinted.len;
    const instances = try allocator.alloc(snail.render.records.Instance, total_shapes);
    defer allocator.free(instances);
    const batches = try allocator.alloc(snail.render.records.DrawBatch, total_shapes);
    defer allocator.free(batches);
    var instance_len: usize = 0;
    var batch_len: usize = 0;
    const binding = gpu.binding.?;
    _ = try snail.emit.emit(instances, batches, &instance_len, &batch_len, binding, &atlas, &extras, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(instances, batches, &instance_len, &batch_len, binding, &atlas, unhinted, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(instances, batches, &instance_len, &batch_len, binding, &atlas, autohinted, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(instances, batches, &instance_len, &batch_len, binding, &atlas, tt_hinted, .identity, .{ 1, 1, 1, 1 });

    var seen = struct {
        regular: bool = false,
        autohint: bool = false,
        tt_hinted_text: bool = false,
        colr: bool = false,
        path_shapes: u32 = 0,
    }{};
    for (batches[0..batch_len]) |batch| switch (batch.kind) {
        .regular => seen.regular = true,
        .autohint => seen.autohint = true,
        .tt_hinted_text => seen.tt_hinted_text = true,
        .colr => seen.colr = true,
        .path => seen.path_shapes += batch.instance_count,
    };
    std.debug.assert(seen.regular and seen.autohint and seen.tt_hinted_text and seen.colr and seen.path_shapes == 2);

    var target = try RenderTarget.init();
    defer target.deinit();
    const programs = try Programs.init();
    defer programs.deinit();
    var geometry = initGeometry(instance_len * snail.render.records.BYTES_PER_INSTANCE);
    defer geometry.deinit();

    target.bind();
    c.glViewport(0, 0, width, height);
    c.glEnable(c.GL_FRAMEBUFFER_SRGB);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);
    c.glClearColor(0.955, 0.965, 0.985, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    gpu.bind();

    const projection = snail.Mat4.ortho(0, width, height, 0, -1, 1);
    for (batches[0..batch_len]) |batch| {
        const run = instances[batch.first_instance..][0..batch.instance_count];
        const run_bytes = std.mem.sliceAsBytes(run);
        const program = programs.forKind(batch.kind);
        bindProgram(program, projection);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, geometry.vbo);
        c.glBufferSubData(c.GL_ARRAY_BUFFER, 0, @intCast(run_bytes.len), run_bytes.ptr);
        c.glDrawElementsInstanced(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null, @intCast(batch.instance_count));
    }
    c.glFinish();
    try writeTga(allocator, "zig-out/minimal-gl.tga");
    std.debug.print("wrote zig-out/minimal-gl.tga\n", .{});
}

fn extendWithPaths(allocator: std.mem.Allocator, atlas: *snail.Atlas) ![2]snail.Shape {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();

    // Filled path.
    var fill_path = snail.Path.init(allocator);
    defer fill_path.deinit();
    try fill_path.addRoundedRect(.{ .x = 530, .y = 205, .w = 145, .h = 105 }, 22);
    var prepared_fill = try fill_path.prepare(allocator);
    defer prepared_fill.deinit();
    var fill_curves = try prepared_fill.fillCurves(allocator, scratch.allocator());
    defer fill_curves.deinit();
    _ = scratch.reset(.retain_capacity);
    const fill_key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = 1 };

    // Stroked path. `strokeCurves` outlines the source-space stroke before
    // packing it, so the same path program consumes the resulting geometry.
    var stroke_path = snail.Path.init(allocator);
    defer stroke_path.deinit();
    try stroke_path.moveTo(.{ .x = 705, .y = 220 });
    try stroke_path.cubicTo(.{ .x = 760, .y = 330 }, .{ .x = 855, .y = 175 }, .{ .x = 920, .y = 295 });
    var prepared_stroke = try stroke_path.prepare(allocator);
    defer prepared_stroke.deinit();
    const stroke_style = snail.StrokeStyle{
        .paint = .{ .solid = snail.color.srgbToLinearColor(.{ 0.10, 0.48, 0.64, 1.0 }) },
        .width = 12,
        .cap = .round,
        .join = .round,
    };
    var stroke_curves = try prepared_stroke.strokeCurves(allocator, scratch.allocator(), stroke_style);
    defer stroke_curves.deinit();
    _ = scratch.reset(.retain_capacity);
    const stroke_key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_stroke, .a = 1 };

    try atlas.extendInPlace(allocator, &.{
        .{
            .key = fill_key,
            .curves = fill_curves,
            .paint = prepared_fill.paintForDesign(.{ .solid = snail.color.srgbToLinearColor(.{ 0.34, 0.25, 0.72, 0.92 }) }),
        },
        .{
            .key = stroke_key,
            .curves = stroke_curves,
            .paint = prepared_stroke.paintForDesign(stroke_style.paint),
        },
    });
    return .{
        .{ .key = fill_key, .local_transform = prepared_fill.placedBy(.identity) },
        .{ .key = stroke_key, .local_transform = prepared_stroke.placedBy(.identity) },
    };
}

const Egl = struct {
    display: c.EGLDisplay,
    surface: c.EGLSurface,
    context: c.EGLContext,

    fn deinit(self: *Egl) void {
        _ = c.eglMakeCurrent(self.display, c.EGL_NO_SURFACE, c.EGL_NO_SURFACE, c.EGL_NO_CONTEXT);
        _ = c.eglDestroyContext(self.display, self.context);
        _ = c.eglDestroySurface(self.display, self.surface);
        _ = c.eglTerminate(self.display);
    }
};

fn initEgl() !Egl {
    const GetPlatformDisplay = *const fn (c.EGLenum, ?*anyopaque, ?[*]const c.EGLint) callconv(.c) c.EGLDisplay;
    const get_platform_display: ?GetPlatformDisplay = @ptrCast(c.eglGetProcAddress("eglGetPlatformDisplayEXT"));
    var display = if (get_platform_display) |get|
        get(c.EGL_PLATFORM_SURFACELESS_MESA, c.EGL_DEFAULT_DISPLAY, null)
    else
        c.EGL_NO_DISPLAY;
    if (display == c.EGL_NO_DISPLAY) display = c.eglGetDisplay(c.EGL_DEFAULT_DISPLAY);
    if (display == c.EGL_NO_DISPLAY) return error.EglDisplayFailed;
    errdefer _ = c.eglTerminate(display);

    var major: c.EGLint = 0;
    var minor: c.EGLint = 0;
    if (c.eglInitialize(display, &major, &minor) == c.EGL_FALSE) return error.EglInitializeFailed;
    if (c.eglBindAPI(c.EGL_OPENGL_API) == c.EGL_FALSE) return error.EglBindFailed;

    const config_attrs = [_]c.EGLint{
        c.EGL_SURFACE_TYPE,    c.EGL_PBUFFER_BIT,
        c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_BIT,
        c.EGL_RED_SIZE,        8,
        c.EGL_GREEN_SIZE,      8,
        c.EGL_BLUE_SIZE,       8,
        c.EGL_ALPHA_SIZE,      8,
        c.EGL_NONE,
    };
    var config: c.EGLConfig = null;
    var config_count: c.EGLint = 0;
    if (c.eglChooseConfig(display, &config_attrs, &config, 1, &config_count) == c.EGL_FALSE or config_count == 0) return error.EglConfigFailed;
    const surface_attrs = [_]c.EGLint{ c.EGL_WIDTH, width, c.EGL_HEIGHT, height, c.EGL_NONE };
    const surface = c.eglCreatePbufferSurface(display, config, &surface_attrs);
    if (surface == c.EGL_NO_SURFACE) return error.EglSurfaceFailed;
    errdefer _ = c.eglDestroySurface(display, surface);

    const context_attrs = [_]c.EGLint{
        c.EGL_CONTEXT_MAJOR_VERSION_KHR,       3,
        c.EGL_CONTEXT_MINOR_VERSION_KHR,       3,
        c.EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, c.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR,
        c.EGL_NONE,
    };
    const context = c.eglCreateContext(display, config, c.EGL_NO_CONTEXT, &context_attrs);
    if (context == c.EGL_NO_CONTEXT) return error.EglContextFailed;
    errdefer _ = c.eglDestroyContext(display, context);
    if (c.eglMakeCurrent(display, surface, surface, context) == c.EGL_FALSE) return error.EglMakeCurrentFailed;
    return .{ .display = display, .surface = surface, .context = context };
}

const RenderTarget = struct {
    fbo: c.GLuint = 0,
    color: c.GLuint = 0,

    fn init() !RenderTarget {
        var self = RenderTarget{};
        errdefer self.deinit();
        c.glGenTextures(1, &self.color);
        c.glBindTexture(c.GL_TEXTURE_2D, self.color);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_SRGB8_ALPHA8, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
        c.glGenFramebuffers(1, &self.fbo);
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.fbo);
        c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, self.color, 0);
        if (c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER) != c.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
        return self;
    }

    fn bind(self: *const RenderTarget) void {
        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.fbo);
    }

    fn deinit(self: *RenderTarget) void {
        c.glDeleteFramebuffers(1, &self.fbo);
        c.glDeleteTextures(1, &self.color);
    }
};

const Geometry = struct {
    vao: c.GLuint,
    vbo: c.GLuint,
    ebo: c.GLuint,

    fn deinit(self: *Geometry) void {
        c.glDeleteVertexArrays(1, &self.vao);
        c.glDeleteBuffers(1, &self.vbo);
        c.glDeleteBuffers(1, &self.ebo);
    }
};

fn initGeometry(byte_capacity: usize) Geometry {
    const Instance = snail.render.records.Instance;
    var out: Geometry = undefined;
    c.glGenVertexArrays(1, &out.vao);
    c.glGenBuffers(1, &out.vbo);
    c.glGenBuffers(1, &out.ebo);
    c.glBindVertexArray(out.vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, out.vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(byte_capacity), null, c.GL_STREAM_DRAW);
    const indices = [6]u32{ 1, 2, 0, 2, 3, 0 };
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, out.ebo);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, c.GL_STATIC_DRAW);
    const stride: c.GLsizei = snail.render.records.BYTES_PER_INSTANCE;
    floatAttribute(0, 4, c.GL_HALF_FLOAT, c.GL_FALSE, stride, @offsetOf(Instance, "rect"));
    floatAttribute(1, 4, c.GL_FLOAT, c.GL_FALSE, stride, @offsetOf(Instance, "xform"));
    floatAttribute(2, 2, c.GL_FLOAT, c.GL_FALSE, stride, @offsetOf(Instance, "origin"));
    intAttribute(3, 2, stride, @offsetOf(Instance, "glyph"));
    floatAttribute(4, 4, c.GL_FLOAT, c.GL_FALSE, stride, @offsetOf(Instance, "band"));
    floatAttribute(5, 4, c.GL_UNSIGNED_BYTE, c.GL_TRUE, stride, @offsetOf(Instance, "color"));
    floatAttribute(6, 4, c.GL_UNSIGNED_BYTE, c.GL_TRUE, stride, @offsetOf(Instance, "tint"));
    intAttribute(7, 4, stride, @offsetOf(Instance, "policy"));
    intAttribute(8, 3, stride, @offsetOf(Instance, "policy") + 16);
    inline for (0..9) |location| c.glVertexAttribDivisor(location, 1);
    return out;
}

fn floatAttribute(location: c.GLuint, count: c.GLint, ty: c.GLenum, normalized: c.GLboolean, stride: c.GLsizei, offset: usize) void {
    c.glVertexAttribPointer(location, count, ty, normalized, stride, @ptrFromInt(offset));
    c.glEnableVertexAttribArray(location);
}

fn intAttribute(location: c.GLuint, count: c.GLint, stride: c.GLsizei, offset: usize) void {
    c.glVertexAttribIPointer(location, count, c.GL_UNSIGNED_INT, stride, @ptrFromInt(offset));
    c.glEnableVertexAttribArray(location);
}

fn bindProgram(program: c.GLuint, projection: snail.Mat4) void {
    c.glUseProgram(program);
    c.glUniformMatrix4fv(c.glGetUniformLocation(program, "u_mvp"), 1, c.GL_FALSE, &projection.data);
    c.glUniform2f(c.glGetUniformLocation(program, "u_viewport"), width, height);
    c.glUniform1i(c.glGetUniformLocation(program, "u_curve_tex"), 0);
    c.glUniform1i(c.glGetUniformLocation(program, "u_band_tex"), 1);
    c.glUniform1i(c.glGetUniformLocation(program, "u_layer_tex"), 2);
    c.glUniform1i(c.glGetUniformLocation(program, "u_image_tex"), 3);
    c.glUniform1i(c.glGetUniformLocation(program, "u_layer_base"), 0);
    c.glUniform1i(c.glGetUniformLocation(program, "u_subpixel_order"), 0);
    c.glUniform1i(c.glGetUniformLocation(program, "u_output_srgb"), 0);
    c.glUniform1f(c.glGetUniformLocation(program, "u_coverage_exponent"), 1.0);
    c.glUniform1f(c.glGetUniformLocation(program, "u_dither_scale"), 0.0);
    c.glUniform1i(c.glGetUniformLocation(program, "u_mask_output"), 0);
}

fn compileShader(kind: c.GLenum, source: [:0]const u8) !c.GLuint {
    const shader = c.glCreateShader(kind);
    const ptr: [*c]const u8 = source.ptr;
    c.glShaderSource(shader, 1, &ptr, null);
    c.glCompileShader(shader);
    var ok: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        var log: [8192]u8 = undefined;
        var len: c.GLsizei = 0;
        c.glGetShaderInfoLog(shader, log.len, &len, &log);
        std.debug.print("shader error:\n{s}\n", .{log[0..@intCast(len)]});
        c.glDeleteShader(shader);
        return error.ShaderCompileFailed;
    }
    return shader;
}

fn linkProgram(vertex_source_arg: [:0]const u8, fragment_source: [:0]const u8) !c.GLuint {
    const vertex = try compileShader(c.GL_VERTEX_SHADER, vertex_source_arg);
    defer c.glDeleteShader(vertex);
    const fragment = try compileShader(c.GL_FRAGMENT_SHADER, fragment_source);
    defer c.glDeleteShader(fragment);
    const program = c.glCreateProgram();
    c.glAttachShader(program, vertex);
    c.glAttachShader(program, fragment);
    c.glLinkProgram(program);
    var ok: c.GLint = 0;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        var log: [8192]u8 = undefined;
        var len: c.GLsizei = 0;
        c.glGetProgramInfoLog(program, log.len, &len, &log);
        std.debug.print("link error:\n{s}\n", .{log[0..@intCast(len)]});
        c.glDeleteProgram(program);
        return error.ShaderLinkFailed;
    }
    return program;
}

fn setNearest(target: c.GLenum) void {
    c.glTexParameteri(target, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
    c.glTexParameteri(target, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
    c.glTexParameteri(target, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
    c.glTexParameteri(target, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
}

fn writeTga(allocator: std.mem.Allocator, path: [:0]const u8) !void {
    const pixels = try allocator.alloc(u8, width * height * 4);
    defer allocator.free(pixels);
    c.glReadPixels(0, 0, width, height, c.GL_RGBA, c.GL_UNSIGNED_BYTE, pixels.ptr);
    _ = c.mkdir("zig-out", 0o755);
    const file = c.fopen(path.ptr, "wb") orelse return error.OpenOutputFailed;
    defer _ = c.fclose(file);
    var header = [_]u8{0} ** 18;
    header[2] = 2;
    header[12] = width & 0xff;
    header[13] = (width >> 8) & 0xff;
    header[14] = height & 0xff;
    header[15] = (height >> 8) & 0xff;
    header[16] = 32;
    header[17] = 8 | 0x20; // 8 alpha bits, top-left origin
    try fwrite(file, &header);
    var row: [width * 4]u8 = undefined;
    for (0..height) |y| {
        const source = pixels[(height - 1 - y) * width * 4 ..][0 .. width * 4];
        for (0..width) |x| {
            row[x * 4 + 0] = source[x * 4 + 2];
            row[x * 4 + 1] = source[x * 4 + 1];
            row[x * 4 + 2] = source[x * 4 + 0];
            row[x * 4 + 3] = source[x * 4 + 3];
        }
        try fwrite(file, &row);
    }
}

fn fwrite(file: *c.FILE, bytes: []const u8) !void {
    if (c.fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.WriteFailed;
}

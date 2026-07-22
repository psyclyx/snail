const std = @import("std");
const snail = @import("snail");
const common = @import("common.zig");
const fixtures = @import("fixtures.zig");

const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("EGL/egl.h");
    @cInclude("EGL/eglext.h");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
});

const cases = [_][]const u8{
    "text-gray",
    "text-lcd",
    "text-tt-hint",
    "text-autohint",
    "text-autohint-fallback",
    "text-colr",
    "path",
    "text-sample-8",
    "text-sample-32",
};

const Args = struct {
    case: []const u8,
    draws: usize = 16,
    samples: usize = 15,
};

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
const autohint_fallback_vertex_source: [:0]const u8 =
    "#version 330 core\n#define SNAIL_AH_FORCE_FRAGMENT 1\n" ++
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
const subpixel_fragment_source: [:0]const u8 =
    "#version 330 core\n#define SNAIL_DUAL_SOURCE 1\n" ++
    glsl.source(.text_subpixel_interface) ++ "\n" ++
    glsl.source(.render_abi) ++ "\n" ++
    glsl.source(.coverage_common) ++ "\n" ++
    glsl.source(.color_common) ++ "\n" ++
    glsl.source(.text_subpixel_body) ++ "\n" ++
    "void main() { snailSubpixelFragment(); }\n";
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
const tt_hinted_fragment_source: [:0]const u8 =
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

// Text-as-material rows measure the generated text_sample artifact (the
// shipped module surface; the composed interface fragments are retired).
// The fullscreen vertex feeds the scene position through the generated
// module's location-0 varying (`snail_io0`); the fragment computes its own
// footprint and reads glyph records from a R32UI texel buffer.
const slang_gen = @import("snail_shaders");
const sample_vertex_source: [:0]const u8 =
    \\#version 330 core
    \\out vec2 snail_io0;
    \\const vec2 positions[4] = vec2[4](vec2(-1,-1), vec2(1,-1), vec2(1,1), vec2(-1,1));
    \\const vec2 uvs[4] = vec2[4](vec2(0,0), vec2(1,0), vec2(1,1), vec2(0,1));
    \\void main() {
    \\    vec2 uv = uvs[gl_VertexID];
    \\    snail_io0 = vec2(uv.x * 640.0, (1.0 - uv.y) * 360.0);
    \\    gl_Position = vec4(positions[gl_VertexID], 0, 1);
    \\}
;
const sample_fragment_source: [:0]const u8 = slang_gen.textSampleFragGlsl330();

pub fn main(init: std.process.Init) !void {
    const raw_args = try init.minimal.args.toSlice(init.arena.allocator());
    const args = parseArgs(raw_args) catch |err| {
        printUsage(raw_args[0]);
        std.debug.print("error: {s}\n", .{@errorName(err)});
        std.process.exit(2);
    };
    const allocator = std.heap.c_allocator;
    var egl = try initEgl();
    defer egl.deinit();

    const sample_glyphs: ?usize = if (std.mem.eql(u8, args.case, "text-sample-8"))
        8
    else if (std.mem.eql(u8, args.case, "text-sample-32"))
        32
    else
        null;
    const kind: fixtures.SceneKind = if (std.mem.eql(u8, args.case, "text-tt-hint"))
        .tt_hinted
    else if (isAutohintCase(args.case))
        .autohint
    else if (std.mem.eql(u8, args.case, "text-colr"))
        .colr
    else if (std.mem.eql(u8, args.case, "path"))
        .path
    else
        .regular;

    const pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();
    var scene = try fixtures.buildScene(allocator, pool, kind);
    defer scene.deinit();
    var gpu = try GpuAtlas.init(allocator, pool);
    defer gpu.deinit();
    try gpu.upload(&scene.atlas);
    var emitted = try fixtures.emitScene(allocator, gpu.binding.?, &scene);
    defer emitted.deinit();

    var target = try RenderTarget.init();
    defer target.deinit();
    target.bind();
    c.glViewport(0, 0, fixtures.width, fixtures.height);
    c.glEnable(c.GL_FRAMEBUFFER_SRGB);
    c.glEnable(c.GL_BLEND);
    c.glBlendFunc(c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);
    gpu.bind();

    var standard_geometry: ?Geometry = null;
    defer if (standard_geometry) |*geometry| geometry.deinit();
    var sample_geometry: ?SampleGeometry = null;
    defer if (sample_geometry) |*geometry| geometry.deinit();
    var program: c.GLuint = 0;
    defer if (program != 0) c.glDeleteProgram(program);

    var draw_context: DrawContext = undefined;
    var work_per_draw: usize = 0;
    var work_unit: []const u8 = undefined;
    var instance_count: usize = 0;
    var sampled_glyphs: usize = 0;
    var record_bytes: usize = 0;
    if (sample_glyphs) |glyph_count_requested| {
        const glyph_count = @min(glyph_count_requested, emitted.instance_len);
        program = try linkProgram(sample_vertex_source, sample_fragment_source, false);
        sample_geometry = initSampleGeometry(emitted.instances[0..glyph_count]);
        bindSampleProgram(program, sample_geometry.?.params_ubo, glyph_count);
        draw_context = .{ .sample = &sample_geometry.? };
        sampled_glyphs = glyph_count;
        record_bytes = glyph_count * snail.render.records.BYTES_PER_INSTANCE;
        work_per_draw = @as(usize, fixtures.width) * fixtures.height * glyph_count;
        work_unit = "fragment_glyph_test";
    } else {
        if (emitted.batch_len != 1) return error.ExpectedHomogeneousScene;
        const expected_kind: snail.render.records.ShapeKind = if (std.mem.eql(u8, args.case, "text-tt-hint"))
            .tt_hinted_text
        else if (isAutohintCase(args.case))
            .autohint
        else if (std.mem.eql(u8, args.case, "text-colr"))
            .colr
        else if (std.mem.eql(u8, args.case, "path"))
            .path
        else
            .regular;
        if (emitted.batches[0].kind != expected_kind) return error.UnexpectedShapeKind;
        const fragment_source = if (std.mem.eql(u8, args.case, "text-gray"))
            regular_fragment_source
        else if (std.mem.eql(u8, args.case, "text-lcd"))
            subpixel_fragment_source
        else if (isAutohintCase(args.case))
            autohint_fragment_source
        else if (std.mem.eql(u8, args.case, "text-tt-hint"))
            tt_hinted_fragment_source
        else if (std.mem.eql(u8, args.case, "text-colr"))
            colr_fragment_source
        else
            path_fragment_source;
        const dual_source = std.mem.eql(u8, args.case, "text-lcd");
        if (dual_source) {
            var max_dual_source: c.GLint = 0;
            c.glGetIntegerv(c.GL_MAX_DUAL_SOURCE_DRAW_BUFFERS, &max_dual_source);
            if (max_dual_source < 1) return error.DualSourceBlendUnavailable;
        }
        const selected_vertex_source = if (std.mem.eql(u8, args.case, "text-autohint-fallback"))
            autohint_fallback_vertex_source
        else if (isAutohintCase(args.case))
            autohint_vertex_source
        else
            vertex_source;
        program = try linkProgram(selected_vertex_source, fragment_source, dual_source);
        standard_geometry = initGeometry(emitted.instances[0..emitted.instance_len]);
        bindStandardProgram(program, dual_source);
        if (dual_source) {
            c.glBlendFuncSeparate(c.GL_ONE, c.GL_ONE_MINUS_SRC1_COLOR, c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);
        }
        draw_context = .{ .standard = .{
            .geometry = &standard_geometry.?,
            .instances = emitted.batches[0].instance_count,
        } };
        instance_count = emitted.batches[0].instance_count;
        record_bytes = emitted.instance_len * snail.render.records.BYTES_PER_INSTANCE;
        work_per_draw = instance_count;
        work_unit = "instance";
    }

    c.glClearColor(0.04, 0.05, 0.07, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    draw_context.bind();
    for (0..4) |_| draw_context.draw();
    c.glFinish();

    const timings = try allocator.alloc(u64, args.samples);
    defer allocator.free(timings);
    var query: c.GLuint = 0;
    c.glGenQueries(1, &query);
    defer c.glDeleteQueries(1, &query);
    for (timings) |*elapsed| {
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glBeginQuery(c.GL_TIME_ELAPSED, query);
        for (0..args.draws) |_| draw_context.draw();
        c.glEndQuery(c.GL_TIME_ELAPSED);
        c.glGetQueryObjectui64v(query, c.GL_QUERY_RESULT, elapsed);
    }
    std.mem.sort(u64, timings, {}, std.sort.asc(u64));

    const pixels = try allocator.alloc(u8, @as(usize, fixtures.width) * fixtures.height * 4);
    defer allocator.free(pixels);
    c.glReadPixels(0, 0, fixtures.width, fixtures.height, c.GL_RGBA, c.GL_UNSIGNED_BYTE, pixels.ptr);
    var checksum: u64 = 14695981039346656037;
    common.hashBytes(&checksum, pixels);
    const min_per_draw = timings[0] / args.draws;
    const median_per_draw = timings[timings.len / 2] / args.draws;
    const p95_index = @min(timings.len - 1, (timings.len * 95 + 99) / 100 - 1);
    const p95_per_draw = timings[p95_index] / args.draws;
    const ns_per_work = @as(f64, @floatFromInt(median_per_draw)) / @as(f64, @floatFromInt(work_per_draw));
    const em_min: usize = switch (kind) {
        .regular, .autohint, .mixed => 18,
        .tt_hinted => 20,
        .colr => 38,
        .path => 0,
    };
    const em_max: usize = switch (kind) {
        .regular, .autohint, .mixed => 22,
        .tt_hinted => 20,
        .colr => 46,
        .path => 0,
    };
    const renderer = glString(c.GL_RENDERER);
    std.debug.print(
        "benchmark=glsl/{s} median_gpu_ns={d} min_gpu_ns={d} p95_gpu_ns={d} work_per_draw={d} work_unit={s} gpu_ns_per_work={d:.3} draws_per_sample={d} samples={d} source_shapes={d} instances={d} sampled_glyphs={d} record_bytes={d} batches={d} atlas_records={d} atlas_pages={d} colr_layers_per_glyph={d} em_min_px={d} em_max_px={d} width={d} height={d} surface_pixels={d} checksum={x} renderer=\"{s}\"\n",
        .{
            args.case,
            median_per_draw,
            min_per_draw,
            p95_per_draw,
            work_per_draw,
            work_unit,
            ns_per_work,
            args.draws,
            args.samples,
            scene.shapes().len,
            instance_count,
            sampled_glyphs,
            record_bytes,
            emitted.batch_len,
            scene.atlas.recordCount(),
            scene.atlas.pageCount(),
            scene.colrLayerCount(),
            em_min,
            em_max,
            fixtures.width,
            fixtures.height,
            @as(usize, fixtures.width) * fixtures.height,
            checksum,
            renderer,
        },
    );
}

fn isAutohintCase(case: []const u8) bool {
    return std.mem.eql(u8, case, "text-autohint") or std.mem.eql(u8, case, "text-autohint-fallback");
}

const DrawContext = union(enum) {
    standard: struct { geometry: *const Geometry, instances: u32 },
    sample: *const SampleGeometry,

    fn bind(self: DrawContext) void {
        switch (self) {
            .standard => |standard| c.glBindVertexArray(standard.geometry.vao),
            .sample => |sample| c.glBindVertexArray(sample.vao),
        }
    }

    fn draw(self: DrawContext) void {
        switch (self) {
            .standard => |standard| c.glDrawElementsInstanced(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null, @intCast(standard.instances)),
            .sample => c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null),
        }
    }
};

fn parseArgs(args: []const [:0]const u8) !Args {
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list")) {
        for (cases) |case| std.debug.print("{s}\n", .{case});
        std.process.exit(0);
    }
    if (args.len < 2) return error.MissingCase;
    var known = false;
    for (cases) |case| if (std.mem.eql(u8, args[1], case)) {
        known = true;
        break;
    };
    if (!known) return error.UnknownCase;
    var out = Args{ .case = args[1] };
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--draws")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            out.draws = try std.fmt.parseUnsigned(usize, args[i], 10);
            if (out.draws == 0) return error.InvalidDrawCount;
        } else if (std.mem.eql(u8, args[i], "--samples")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            out.samples = try std.fmt.parseUnsigned(usize, args[i], 10);
            if (out.samples == 0) return error.InvalidSampleCount;
        } else return error.UnknownArgument;
    }
    return out;
}

fn printUsage(exe: []const u8) void {
    std.debug.print("usage: {s} CASE [--draws N] [--samples N]\n       {s} --list\ncases:\n", .{ exe, exe });
    for (cases) |case| std.debug.print("  {s}\n", .{case});
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
    const surface_attrs = [_]c.EGLint{ c.EGL_WIDTH, fixtures.width, c.EGL_HEIGHT, fixtures.height, c.EGL_NONE };
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
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_SRGB8_ALPHA8, fixtures.width, fixtures.height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);
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
        .max_image_width = 1,
        .max_image_height = 1,
    };

    fn init(allocator: std.mem.Allocator, pool: *snail.PagePool) !GpuAtlas {
        var self = GpuAtlas{ .pool = pool, .uploads = try snail.OwnedAtlasUploadPlanner.init(allocator, pool, options) };
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

    fn upload(self: *GpuAtlas, atlas: *const snail.Atlas) !void {
        const planned = try self.uploads.plan(atlas);
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

fn initGeometry(instances: []const snail.render.records.Instance) Geometry {
    const Instance = snail.render.records.Instance;
    var out: Geometry = undefined;
    c.glGenVertexArrays(1, &out.vao);
    c.glGenBuffers(1, &out.vbo);
    c.glGenBuffers(1, &out.ebo);
    c.glBindVertexArray(out.vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, out.vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(std.mem.sliceAsBytes(instances).len), instances.ptr, c.GL_STATIC_DRAW);
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

const SampleGeometry = struct {
    vao: c.GLuint,
    ebo: c.GLuint,
    records_buffer: c.GLuint,
    records_texture: c.GLuint,
    params_ubo: c.GLuint,

    fn deinit(self: *SampleGeometry) void {
        c.glDeleteVertexArrays(1, &self.vao);
        c.glDeleteBuffers(1, &self.ebo);
        c.glDeleteTextures(1, &self.records_texture);
        c.glDeleteBuffers(1, &self.records_buffer);
        c.glDeleteBuffers(1, &self.params_ubo);
    }
};

fn initSampleGeometry(instances: []const snail.render.records.Instance) SampleGeometry {
    var out: SampleGeometry = undefined;
    c.glGenVertexArrays(1, &out.vao);
    c.glGenBuffers(1, &out.ebo);
    c.glBindVertexArray(out.vao);
    const indices = [6]u32{ 1, 2, 0, 2, 3, 0 };
    c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, out.ebo);
    c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, c.GL_STATIC_DRAW);
    c.glGenBuffers(1, &out.records_buffer);
    c.glBindBuffer(c.GL_TEXTURE_BUFFER, out.records_buffer);
    c.glBufferData(c.GL_TEXTURE_BUFFER, @intCast(std.mem.sliceAsBytes(instances).len), instances.ptr, c.GL_STATIC_DRAW);
    c.glGenTextures(1, &out.records_texture);
    c.glActiveTexture(c.GL_TEXTURE3);
    c.glBindTexture(c.GL_TEXTURE_BUFFER, out.records_texture);
    c.glTexBuffer(c.GL_TEXTURE_BUFFER, c.GL_R32UI, out.records_buffer);
    c.glGenBuffers(1, &out.params_ubo);
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

fn bindStandardProgram(program: c.GLuint, subpixel: bool) void {
    c.glUseProgram(program);
    const projection = snail.Mat4.ortho(0, @floatFromInt(fixtures.width), @floatFromInt(fixtures.height), 0, -1, 1);
    c.glUniformMatrix4fv(c.glGetUniformLocation(program, "u_mvp"), 1, c.GL_FALSE, &projection.data);
    c.glUniform2f(c.glGetUniformLocation(program, "u_viewport"), fixtures.width, fixtures.height);
    c.glUniform1i(c.glGetUniformLocation(program, "u_curve_tex"), 0);
    c.glUniform1i(c.glGetUniformLocation(program, "u_band_tex"), 1);
    c.glUniform1i(c.glGetUniformLocation(program, "u_layer_tex"), 2);
    c.glUniform1i(c.glGetUniformLocation(program, "u_image_tex"), 4);
    c.glUniform1i(c.glGetUniformLocation(program, "u_layer_base"), 0);
    c.glUniform1i(c.glGetUniformLocation(program, "u_subpixel_order"), if (subpixel) 1 else 0);
    c.glUniform1i(c.glGetUniformLocation(program, "u_output_srgb"), 0);
    c.glUniform1f(c.glGetUniformLocation(program, "u_coverage_exponent"), 1.0);
    c.glUniform1f(c.glGetUniformLocation(program, "u_dither_scale"), 0.0);
    c.glUniform1i(c.glGetUniformLocation(program, "u_mask_output"), 0);
}

/// std140 mirror of the generated module's `SnailTextSampleParams` block.
const SampleParams = extern struct {
    glyph_count: i32,
    words_per_glyph: i32,
    layer_base: i32,
    coverage_exponent: f32,
};

fn bindSampleProgram(program: c.GLuint, params_ubo: c.GLuint, glyph_count: usize) void {
    c.glUseProgram(program);
    // Combined-sampler names are part of the generated-artifact contract.
    c.glUniform1i(c.glGetUniformLocation(program, slang_gen.glsl_curve_tex_name), 0);
    c.glUniform1i(c.glGetUniformLocation(program, slang_gen.glsl_band_tex_name), 1);
    c.glUniform1i(c.glGetUniformLocation(program, slang_gen.glsl_text_sample_records_name), 3);
    const block = c.glGetUniformBlockIndex(program, slang_gen.glsl_text_sample_block_name);
    c.glUniformBlockBinding(program, block, 0);
    const params = SampleParams{
        .glyph_count = @intCast(glyph_count),
        .words_per_glyph = snail.render.records.BYTES_PER_INSTANCE / 4,
        .layer_base = 0,
        .coverage_exponent = 1.0,
    };
    c.glBindBuffer(c.GL_UNIFORM_BUFFER, params_ubo);
    c.glBufferData(c.GL_UNIFORM_BUFFER, @sizeOf(SampleParams), &params, c.GL_STATIC_DRAW);
    c.glBindBufferBase(c.GL_UNIFORM_BUFFER, 0, params_ubo);
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

fn linkProgram(vertex_src: [:0]const u8, fragment_src: [:0]const u8, dual_source: bool) !c.GLuint {
    const vertex = try compileShader(c.GL_VERTEX_SHADER, vertex_src);
    defer c.glDeleteShader(vertex);
    const fragment = try compileShader(c.GL_FRAGMENT_SHADER, fragment_src);
    defer c.glDeleteShader(fragment);
    const program = c.glCreateProgram();
    c.glAttachShader(program, vertex);
    c.glAttachShader(program, fragment);
    if (dual_source) {
        c.glBindFragDataLocationIndexed(program, 0, 0, "frag_color");
        c.glBindFragDataLocationIndexed(program, 0, 1, "frag_blend");
    }
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

fn glString(name: c.GLenum) []const u8 {
    const ptr = c.glGetString(name) orelse return "unknown";
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

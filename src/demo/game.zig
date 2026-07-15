//! 3D-room game demo, ported to the new snail API.
//!
//! Layout:
//!   - World passes (rough wall, center panel, glass) and HUD passes (plain,
//!     translucent, solid) each carry their own atlases + pictures (paths and
//!     text). All atlases share the same `PagePool` owned by `Fonts`.
//!   - A single `embed_gl.Gl33Renderer` + `embed_gl.Gl33BackendCache` cache backs
//!     every draw. Each pass gets two cache bindings (one per atlas) at
//!     upload time, fetched again whenever the HUD is rebuilt on resize.
//!   - The rough-wall and center-panel passes additionally route their text
//!     picture through `SurfaceTextDraw`, which emits the snail GPU-instance
//!     words into a `GL_TEXTURE_BUFFER` and feeds them to the material
//!     fragment shader via `snail_text_sample_premul_linear`.

const std = @import("std");
const snail = @import("snail");
const embed_gl = @import("embed_gl");
const platform = @import("platform/gl.zig");
const gl = platform.gl;
const subpixel_detect = @import("platform/subpixel.zig");
const common = @import("game/common.zig");
const demo_passes = @import("game/passes.zig");
const demo_quad = @import("game/quad_renderer.zig");

const Camera = common.Camera;
const Vec3 = common.Vec3;
const PreparedPass = demo_passes.PreparedPass;
const HudPasses = demo_passes.HudPasses;
const PlanePass = demo_passes.PlanePass;
const WorldPasses = demo_passes.WorldPasses;
const Fonts = demo_passes.Fonts;
const QuadRenderer = demo_quad.QuadRenderer;
const RenderTarget = demo_quad.RenderTarget;
const SurfaceTextDraw = demo_quad.SurfaceTextDraw;

const CACHE_MAX_BINDINGS: u32 = 16;
const CACHE_MAX_IMAGES: u32 = 16;

fn toSnailEncoding(encoding: platform.presentation.ColorEncoding) snail.ColorEncoding {
    return switch (encoding) {
        .linear => .linear,
        .srgb => .srgb,
    };
}

fn displayTargetEncoding(info: platform.presentation.Info) snail.TargetEncoding {
    return .{
        .attachment = toSnailEncoding(info.framebuffer_encoding),
        .stored_pixels = .srgb,
    };
}

// ── Pass bindings ──

/// Snail-side bindings for one pass (path + text atlases), held inside the
/// shared `Gl33BackendCache` cache.
const PassBindings = struct {
    path: snail.Binding,
    text: snail.Binding,
};

fn uploadPass(
    allocator: std.mem.Allocator,
    cache: *embed_gl.Gl33BackendCache,
    pass: *const PreparedPass,
) !PassBindings {
    var bindings: [2]snail.Binding = undefined;
    try cache.upload(allocator, &.{ &pass.path_atlas, &pass.text_atlas }, &bindings);
    return .{ .path = bindings[0], .text = bindings[1] };
}

fn releasePass(cache: *embed_gl.Gl33BackendCache, bindings: PassBindings) void {
    cache.release(bindings.path);
    cache.release(bindings.text);
}

// ── Scratch buffer for per-frame emit ──

const ScratchBuf = struct {
    allocator: std.mem.Allocator,
    words: []u32 = &.{},
    segs: []snail.DrawSegment = &.{},

    fn init(allocator: std.mem.Allocator) ScratchBuf {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *ScratchBuf) void {
        if (self.words.len > 0) self.allocator.free(self.words);
        if (self.segs.len > 0) self.allocator.free(self.segs);
    }

    fn ensure(self: *ScratchBuf, word_count: usize, seg_count: usize) !void {
        if (self.words.len < word_count) {
            if (self.words.len > 0) self.allocator.free(self.words);
            self.words = try self.allocator.alloc(u32, word_count);
        }
        if (self.segs.len < seg_count) {
            if (self.segs.len > 0) self.allocator.free(self.segs);
            self.segs = try self.allocator.alloc(snail.DrawSegment, seg_count);
        }
    }
};

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    try platform.init(1440, 900, "snail-game-demo", .gl33);
    defer platform.deinit();

    var fonts = try demo_passes.initFonts(allocator);
    defer fonts.deinit();

    var gl_renderer = try embed_gl.Gl33Renderer.init(allocator);
    defer gl_renderer.deinit();

    var quad_renderer = try QuadRenderer.init();
    defer quad_renderer.deinit();

    var cache = try embed_gl.Gl33BackendCache.init(allocator, fonts.pool, .{
        .max_bindings = CACHE_MAX_BINDINGS,
        .layer_info_height = 256,
        .max_images = CACHE_MAX_IMAGES,
        .max_image_width = 64,
        .max_image_height = 64,
    });
    defer cache.deinit();

    var world_passes = try demo_passes.buildWorldPasses(allocator, &fonts);
    defer world_passes.deinit();

    const initial_present = platform.presentationInfo();
    const initial_window = initial_present.logical_size;
    var hud_passes = try HudPasses.init(allocator, &fonts, initial_window[0], initial_window[1]);
    defer hud_passes.deinit();

    // Upload every pass into the shared cache.
    const rough_wall_bindings = try uploadPass(allocator, &cache, &world_passes.rough_wall.prepared);
    defer releasePass(&cache, rough_wall_bindings);
    const center_panel_bindings = try uploadPass(allocator, &cache, &world_passes.center_panel.prepared);
    defer releasePass(&cache, center_panel_bindings);
    const glass_bindings = try uploadPass(allocator, &cache, &world_passes.glass.prepared);
    defer releasePass(&cache, glass_bindings);

    var hud_bindings = HudBindings{
        .plain = try uploadPass(allocator, &cache, &hud_passes.plain),
        .translucent = try uploadPass(allocator, &cache, &hud_passes.translucent),
        .solid = try uploadPass(allocator, &cache, &hud_passes.solid),
    };
    defer hud_bindings.release(&cache);

    var rough_wall_text = try SurfaceTextDraw.init(
        allocator,
        &gl_renderer,
        &cache,
        &world_passes.rough_wall.prepared.text_atlas,
        &world_passes.rough_wall.prepared.text_picture,
        rough_wall_bindings.text,
    );
    defer rough_wall_text.deinit();
    var center_panel_text = try SurfaceTextDraw.init(
        allocator,
        &gl_renderer,
        &cache,
        &world_passes.center_panel.prepared.text_atlas,
        &world_passes.center_panel.prepared.text_picture,
        center_panel_bindings.text,
    );
    defer center_panel_text.deinit();

    var scratch = ScratchBuf.init(allocator);
    defer scratch.deinit();

    var hud_window_size = initial_window;

    const initial_fb = initial_present.framebuffer_size;
    var world_buffer = try RenderTarget.init(initial_fb[0], initial_fb[1], true);
    defer world_buffer.deinit();

    var camera: Camera = .{};
    const sys_order = subpixel_detect.detect();
    var current_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
    var last_time = platform.getTime();

    std.debug.print("snail-game-demo - GL room with HUD and world-space text\n", .{});
    std.debug.print("Controls: WASD move, QE rise, arrows look, R reset camera, Esc quit\n", .{});
    const initial_scale = initial_present.scale();
    std.debug.print(
        "presentation: logical={}x{} framebuffer={}x{} scale={d:.2}x{d:.2} buffer_scale={} framebuffer={s}\n",
        .{
            initial_present.logical_size[0],
            initial_present.logical_size[1],
            initial_present.framebuffer_size[0],
            initial_present.framebuffer_size[1],
            initial_scale[0],
            initial_scale[1],
            initial_present.buffer_scale,
            @tagName(initial_present.framebuffer_encoding),
        },
    );

    while (!platform.shouldClose()) {
        const now = platform.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;

        if (platform.consumeMonitorChanged()) {
            current_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
        }

        const present = platform.presentationInfo();
        const fb_size = present.framebuffer_size;
        const target_encoding = displayTargetEncoding(present);
        if (fb_size[0] == 0 or fb_size[1] == 0) continue;
        if (fb_size[0] != world_buffer.width or fb_size[1] != world_buffer.height) {
            try world_buffer.resize(fb_size[0], fb_size[1], true);
        }

        const window_size = present.logical_size;
        if (window_size[0] != hud_window_size[0] or window_size[1] != hud_window_size[1]) {
            var next_passes = try HudPasses.init(allocator, &fonts, window_size[0], window_size[1]);
            errdefer next_passes.deinit();

            hud_bindings.release(&cache);
            hud_passes.deinit();

            hud_passes = next_passes;
            hud_bindings = HudBindings{
                .plain = try uploadPass(allocator, &cache, &hud_passes.plain),
                .translucent = try uploadPass(allocator, &cache, &hud_passes.translucent),
                .solid = try uploadPass(allocator, &cache, &hud_passes.solid),
            };
            hud_window_size = window_size;
        }

        if (platform.isKeyPressed(platform.KEY_ESCAPE)) break;
        if (platform.isKeyPressed(platform.KEY_R)) camera.reset();

        updateCamera(&camera, dt);

        const view_proj = common.buildViewProjection(camera, @as(f32, @floatFromInt(fb_size[0])) / @as(f32, @floatFromInt(fb_size[1])));
        const light_pos = Vec3{
            .x = -5.85,
            .y = 2.20,
            .z = -4.75,
        };
        const light_color = [3]f32{ 1.42, 1.22, 0.92 };

        try renderWorld(
            &quad_renderer,
            &gl_renderer,
            &cache,
            &world_passes,
            &rough_wall_text,
            &center_panel_text,
            glass_bindings,
            &scratch,
            allocator,
            world_buffer,
            view_proj,
            camera,
            light_pos,
            light_color,
            fb_size,
            current_order,
        );

        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, world_buffer.fbo);
        gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, 0);
        gl.glBlitFramebuffer(
            0,
            0,
            @intCast(world_buffer.width),
            @intCast(world_buffer.height),
            0,
            0,
            @intCast(world_buffer.width),
            @intCast(world_buffer.height),
            gl.GL_COLOR_BUFFER_BIT,
            gl.GL_NEAREST,
        );
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0);
        gl.glViewport(0, 0, @intCast(fb_size[0]), @intCast(fb_size[1]));

        const overlay_projection = snail.Mat4.ortho(
            0.0,
            @floatFromInt(window_size[0]),
            @floatFromInt(window_size[1]),
            0.0,
            -1.0,
            1.0,
        );

        // HUD passes render over the 3D scene, on the swapchain. Subpixel
        // ordering depends on whether the pass guarantees an opaque
        // backdrop under its text.
        gl.glDisable(gl.GL_DEPTH_TEST);
        try drawPassPair(
            &gl_renderer,
            &cache,
            &scratch,
            allocator,
            &hud_passes.plain,
            hud_bindings.plain,
            overlay_projection,
            demo_passes.hudTarget(window_size, fb_size, current_order, false, target_encoding, present.will_resample),
        );
        try drawPassPair(
            &gl_renderer,
            &cache,
            &scratch,
            allocator,
            &hud_passes.translucent,
            hud_bindings.translucent,
            overlay_projection,
            demo_passes.hudTarget(window_size, fb_size, current_order, false, target_encoding, present.will_resample),
        );
        try drawPassPair(
            &gl_renderer,
            &cache,
            &scratch,
            allocator,
            &hud_passes.solid,
            hud_bindings.solid,
            overlay_projection,
            demo_passes.hudTarget(window_size, fb_size, current_order, true, target_encoding, present.will_resample),
        );

        platform.swapBuffers();
    }
}

const HudBindings = struct {
    plain: PassBindings,
    translucent: PassBindings,
    solid: PassBindings,

    fn release(self: HudBindings, cache: *embed_gl.Gl33BackendCache) void {
        releasePass(cache, self.plain);
        releasePass(cache, self.translucent);
        releasePass(cache, self.solid);
    }
};

fn drawPassPair(
    gl_renderer: *embed_gl.Gl33Renderer,
    cache: *const embed_gl.Gl33BackendCache,
    scratch: *ScratchBuf,
    allocator: std.mem.Allocator,
    pass: *const PreparedPass,
    bindings: PassBindings,
    mvp: snail.Mat4,
    target: demo_passes.DrawTarget,
) !void {
    const draw_state = snail.DrawState{
        .mvp = mvp,
        .surface = target.surface,
        .raster = target.raster,
    };

    const needed_words = snail.emit.wordBudget(pass.path_picture.shapes.len, 0) + snail.emit.wordBudget(pass.text_picture.shapes.len, 0);
    try scratch.ensure(needed_words, 4);
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(scratch.words, scratch.segs, &wlen, &slen, bindings.path, &pass.path_atlas, pass.path_picture.shapes, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(scratch.words, scratch.segs, &wlen, &slen, bindings.text, &pass.text_atlas, pass.text_picture.shapes, .identity, .{ 1, 1, 1, 1 });

    gl_renderer.state.beginDraw();
    try gl_renderer.state.draw(
        allocator,
        draw_state,
        .{ .words = scratch.words[0..wlen], .segments = scratch.segs[0..slen] },
        &.{cache},
    );
}

fn updateCamera(camera: *Camera, dt: f32) void {
    const move_speed: f32 = 3.1;
    const look_speed: f32 = 1.35;

    if (platform.isKeyDown(platform.KEY_LEFT)) camera.yaw += look_speed * dt;
    if (platform.isKeyDown(platform.KEY_RIGHT)) camera.yaw -= look_speed * dt;
    if (platform.isKeyDown(platform.KEY_UP)) camera.pitch = std.math.clamp(camera.pitch + look_speed * dt, -1.1, 1.1);
    if (platform.isKeyDown(platform.KEY_DOWN)) camera.pitch = std.math.clamp(camera.pitch - look_speed * dt, -1.1, 1.1);

    var delta = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const forward = camera.forward();
    const right = camera.right();
    if (platform.isKeyDown(platform.KEY_W)) delta = Vec3.add(delta, forward);
    if (platform.isKeyDown(platform.KEY_S)) delta = Vec3.add(delta, forward.scale(-1.0));
    if (platform.isKeyDown(platform.KEY_D)) delta = Vec3.add(delta, right);
    if (platform.isKeyDown(platform.KEY_A)) delta = Vec3.add(delta, right.scale(-1.0));
    if (platform.isKeyDown(platform.KEY_E)) delta.y += 1.0;
    if (platform.isKeyDown(platform.KEY_Q)) delta.y -= 1.0;

    camera.pos = Vec3.add(camera.pos, delta.scale(move_speed * dt));
}

fn renderPlanePass(
    gl_renderer: *embed_gl.Gl33Renderer,
    cache: *const embed_gl.Gl33BackendCache,
    scratch: *ScratchBuf,
    allocator: std.mem.Allocator,
    pass: *const PlanePass,
    bindings: PassBindings,
    view_proj: snail.Mat4,
    fb_size: [2]u32,
    subpixel_order: snail.SubpixelOrder,
    pos: Vec3,
    rot_x: f32,
    rot_y: f32,
    world_width: f32,
    world_height: f32,
    depth_bias: f32,
) !void {
    const mvp = common.planeMvp(view_proj, pass.scene_width, pass.scene_height, pos, rot_x, rot_y, world_width, world_height, depth_bias);
    try drawPassPair(
        gl_renderer,
        cache,
        scratch,
        allocator,
        &pass.prepared,
        bindings,
        mvp,
        demo_passes.worldTarget(fb_size, subpixel_order, pass.opaque_backdrop),
    );
}

fn renderWorld(
    quad_renderer: *const QuadRenderer,
    gl_renderer: *embed_gl.Gl33Renderer,
    cache: *const embed_gl.Gl33BackendCache,
    world_passes: *const WorldPasses,
    rough_wall_text: *const SurfaceTextDraw,
    center_panel_text: *const SurfaceTextDraw,
    glass_bindings: PassBindings,
    scratch: *ScratchBuf,
    allocator: std.mem.Allocator,
    world_buffer: RenderTarget,
    view_proj: snail.Mat4,
    camera: Camera,
    light_pos: Vec3,
    light_color: [3]f32,
    fb_size: [2]u32,
    subpixel_order: snail.SubpixelOrder,
) !void {
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, world_buffer.fbo);
    gl.glViewport(0, 0, @intCast(world_buffer.width), @intCast(world_buffer.height));
    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glDepthMask(gl.GL_TRUE);
    gl.glDisable(gl.GL_BLEND);
    const clear = common.linearColor(12, 18, 27, 1.0);
    gl.glClearColor(clear[0], clear[1], clear[2], clear[3]);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

    try quad_renderer.drawMaterial(
        view_proj,
        common.composeModel(.{ .x = 0.0, .y = 0.0, .z = -6.3 }, -std.math.pi * 0.5, 0.0, .{ .x = 18.0, .y = 18.0, .z = 1.0 }),
        common.linearColor(34, 38, 46, 1.0),
        null,
        world_passes.material_maps.floor,
        .{ 8.5, 8.5 },
        0.24,
        0.030,
        0.016,
        0.22,
        false,
        false,
        null,
        camera.pos,
        light_pos,
        light_color,
    );
    try quad_renderer.drawMaterial(
        view_proj,
        common.composeModel(.{ .x = 0.0, .y = 3.8, .z = -6.3 }, std.math.pi * 0.5, 0.0, .{ .x = 18.0, .y = 18.0, .z = 1.0 }),
        common.linearColor(18, 22, 28, 1.0),
        null,
        world_passes.material_maps.ceiling,
        .{ 6.0, 6.0 },
        0.18,
        0.018,
        0.008,
        0.10,
        false,
        false,
        null,
        camera.pos,
        light_pos,
        light_color,
    );
    try quad_renderer.drawMaterial(
        view_proj,
        common.composeModel(.{ .x = 0.0, .y = 1.9, .z = -12.2 }, 0.0, 0.0, .{ .x = 18.0, .y = 3.8, .z = 1.0 }),
        common.linearColor(26, 31, 38, 1.0),
        null,
        world_passes.material_maps.wall,
        .{ 6.4, 1.8 },
        0.22,
        0.024,
        0.010,
        0.18,
        false,
        false,
        null,
        camera.pos,
        light_pos,
        light_color,
    );
    try quad_renderer.drawMaterial(
        view_proj,
        common.composeModel(.{ .x = -4.2, .y = 1.55, .z = -5.75 }, 0.0, 0.24, .{ .x = 3.8, .y = 2.55, .z = 1.0 }),
        common.linearColor(150, 145, 132, 1.0),
        null,
        world_passes.material_maps.rough_wall,
        .{ 3.2, 2.4 },
        0.48,
        0.0,
        0.020,
        0.46,
        false,
        false,
        .{
            .text = rough_wall_text,
            .scene_size = .{ world_passes.rough_wall.scene_width, world_passes.rough_wall.scene_height },
            .relief_strength = 0.18,
        },
        camera.pos,
        light_pos,
        light_color,
    );
    try quad_renderer.drawMaterial(
        view_proj,
        common.composeModel(.{ .x = 0.0, .y = 1.65, .z = -7.4 }, 0.0, 0.0, .{ .x = 2.65, .y = 1.45, .z = 1.0 }),
        common.linearColor(31, 35, 39, 1.0),
        null,
        world_passes.material_maps.panel,
        .{ 1.0, 1.0 },
        0.16,
        0.0,
        0.0,
        0.06,
        true,
        false,
        .{
            .text = center_panel_text,
            .scene_size = .{ world_passes.center_panel.scene_width, world_passes.center_panel.scene_height },
        },
        camera.pos,
        light_pos,
        light_color,
    );

    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
    gl.glDepthMask(gl.GL_FALSE);

    try renderPlanePass(
        gl_renderer,
        cache,
        scratch,
        allocator,
        &world_passes.glass,
        glass_bindings,
        view_proj,
        fb_size,
        subpixel_order,
        .{ .x = 2.05, .y = 1.64, .z = -4.15 },
        0.0,
        0.32,
        2.34,
        1.05,
        0.0,
    );

    gl.glDepthMask(gl.GL_TRUE);
    gl.glDisable(gl.GL_BLEND);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0);
}

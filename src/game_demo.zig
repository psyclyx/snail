const std = @import("std");
const snail = @import("snail.zig");
const platform = @import("render/platform.zig");
const gl = @import("render/gl.zig").gl;
const subpixel_detect = @import("render/subpixel_detect.zig");
const common = @import("game_demo/common.zig");
const demo_passes = @import("game_demo/passes.zig");
const demo_quad = @import("game_demo/quad_renderer.zig");

const Camera = common.Camera;
const Vec3 = common.Vec3;
const PreparedPass = demo_passes.PreparedPass;
const HudPasses = demo_passes.HudPasses;
const PlanePass = demo_passes.PlanePass;
const WorldPasses = demo_passes.WorldPasses;
const QuadRenderer = demo_quad.QuadRenderer;
const RenderTarget = demo_quad.RenderTarget;
const SurfaceTextDraw = demo_quad.SurfaceTextDraw;

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    try platform.init(1440, 900, "snail-game-demo");
    defer platform.deinit();

    var fonts = try demo_passes.initFonts(allocator);
    defer fonts.deinit();

    var gl_renderer = try snail.GlRenderer.init(allocator);
    defer gl_renderer.deinit();
    var snail_renderer = gl_renderer.asRenderer();

    var quad_renderer = try QuadRenderer.init();
    defer quad_renderer.deinit();

    var world_passes = try demo_passes.buildWorldPasses(allocator, &fonts);
    defer world_passes.deinit();
    const initial_window = platform.getWindowSize();
    var hud_passes = try HudPasses.init(allocator, &fonts, initial_window[0], initial_window[1]);
    defer hud_passes.deinit();
    var scene_resources = try uploadSceneResources(allocator, &snail_renderer, &world_passes, &hud_passes);
    defer scene_resources.deinit();
    var draw_buf: []u32 = &.{};
    defer if (draw_buf.len > 0) allocator.free(draw_buf);

    var rough_wall_text = try SurfaceTextDraw.init(allocator, &scene_resources, world_passes.rough_wall.prepared.text);
    defer rough_wall_text.deinit();
    var center_panel_text = try SurfaceTextDraw.init(allocator, &scene_resources, world_passes.center_panel.prepared.text);
    defer center_panel_text.deinit();
    var hud_window_size = initial_window;

    const initial_fb = platform.getFramebufferSize();
    var world_buffer = try RenderTarget.init(initial_fb[0], initial_fb[1], true);
    defer world_buffer.deinit();

    var camera: Camera = .{};
    const sys_order = subpixel_detect.detect();
    var current_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
    var last_time = platform.getTime();

    std.debug.print("snail-game-demo - OpenGL room with HUD and world-space text\n", .{});
    std.debug.print("Controls: WASD move, QE rise, arrows look, R reset camera, Esc quit\n", .{});

    while (!platform.shouldClose()) {
        const now = platform.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;

        if (platform.consumeMonitorChanged()) {
            current_order = platform.detectCurrentMonitorSubpixelOrder(sys_order);
        }

        const fb_size = platform.getFramebufferSize();
        if (fb_size[0] == 0 or fb_size[1] == 0) continue;
        if (fb_size[0] != world_buffer.width or fb_size[1] != world_buffer.height) {
            try world_buffer.resize(fb_size[0], fb_size[1], true);
        }

        const window_size = platform.getWindowSize();
        if (window_size[0] != hud_window_size[0] or window_size[1] != hud_window_size[1]) {
            var next_passes = try HudPasses.init(allocator, &fonts, window_size[0], window_size[1]);
            errdefer next_passes.deinit();
            var next_resources = try planSceneResources(allocator, &snail_renderer, &scene_resources, &world_passes, &next_passes);
            errdefer next_resources.deinit();
            scene_resources.retireNowOrWhenSafe(&snail_renderer);
            hud_passes.deinit();
            hud_passes = next_passes;
            scene_resources = next_resources;
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
            &snail_renderer,
            &world_passes,
            &rough_wall_text,
            &center_panel_text,
            &scene_resources,
            &draw_buf,
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

        // Direct HUD text over the 3D scene lands on final pixels, but it does
        // not have a guaranteed opaque backdrop, so LCD/subpixel stays off.
        gl.glDisable(gl.GL_DEPTH_TEST);
        try drawSnailScene(&snail_renderer, &scene_resources, &hud_passes.plain.scene, overlay_projection, demo_passes.hudTarget(window_size, fb_size, current_order, false), &draw_buf, allocator);
        // A translucent vector panel is still not LCD-safe.
        try drawSnailScene(&snail_renderer, &scene_resources, &hud_passes.translucent.scene, overlay_projection, demo_passes.hudTarget(window_size, fb_size, current_order, false), &draw_buf, allocator);
        // This panel is fully opaque and rendered directly to the swapchain, so
        // it is the reference case for LCD/subpixel HUD text.
        try drawSnailScene(&snail_renderer, &scene_resources, &hud_passes.solid.scene, overlay_projection, demo_passes.hudTarget(window_size, fb_size, current_order, true), &draw_buf, allocator);

        platform.swapBuffers();
    }
}

fn addPassResources(set: *snail.ResourceSet, key: anytype, pass: *const PreparedPass) !void {
    try set.putTextAtlas(.fonts, pass.text.atlas);
    if (pass.picture) |picture| try set.putPathPicture(key, picture);
}

fn buildSceneResourceSet(
    world_passes: *const WorldPasses,
    hud_passes: *const HudPasses,
    entries: []snail.ResourceSet.Entry,
) !snail.ResourceSet {
    var set = snail.ResourceSet.init(entries);
    try addPassResources(&set, .world_rough_wall, &world_passes.rough_wall.prepared);
    try addPassResources(&set, .world_center_panel, &world_passes.center_panel.prepared);
    try addPassResources(&set, .world_glass, &world_passes.glass.prepared);
    try addPassResources(&set, .hud_plain, &hud_passes.plain);
    try addPassResources(&set, .hud_translucent_panel, &hud_passes.translucent);
    try addPassResources(&set, .hud_solid_panel, &hud_passes.solid);
    return set;
}

fn uploadSceneResources(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    world_passes: *const WorldPasses,
    hud_passes: *const HudPasses,
) !snail.PreparedResources {
    var resource_entries: [16]snail.ResourceSet.Entry = undefined;
    var set = try buildSceneResourceSet(world_passes, hud_passes, &resource_entries);
    return renderer.uploadResourcesBlocking(allocator, &set);
}

fn planSceneResources(
    allocator: std.mem.Allocator,
    renderer: *snail.Renderer,
    current: *const snail.PreparedResources,
    world_passes: *const WorldPasses,
    hud_passes: *const HudPasses,
) !snail.PreparedResources {
    var resource_entries: [16]snail.ResourceSet.Entry = undefined;
    var changed_keys: [16]snail.ResourceKey = undefined;
    var set = try buildSceneResourceSet(world_passes, hud_passes, &resource_entries);
    const plan = try renderer.planResourceUpload(current, &set, &changed_keys);
    var pending = try renderer.beginResourceUpload(allocator, plan);
    defer pending.deinit();
    try pending.record(.{}, .{});
    return pending.publish();
}

fn drawSnailScene(
    renderer: *snail.Renderer,
    prepared: *const snail.PreparedResources,
    scene: *const snail.Scene,
    mvp: snail.Mat4,
    target: snail.ResolveTarget,
    draw_buf: *[]u32,
    allocator: std.mem.Allocator,
) !void {
    const options = snail.DrawOptions{ .mvp = mvp, .target = target };
    const needed = snail.DrawList.estimate(scene, options);
    const needed_segments = snail.DrawList.estimateSegments(scene, options);
    if (draw_buf.*.len < needed) {
        if (draw_buf.*.len > 0) allocator.free(draw_buf.*);
        draw_buf.* = try allocator.alloc(u32, needed);
    }
    const draw_segments = try allocator.alloc(snail.DrawSegment, needed_segments);
    defer allocator.free(draw_segments);
    var draw = snail.DrawList.init(draw_buf.*[0..needed], draw_segments);
    try draw.addScene(prepared, scene, options);
    try renderer.draw(prepared, draw.slice(), options);
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
    renderer: *snail.Renderer,
    prepared: *const snail.PreparedResources,
    draw_buf: *[]u32,
    allocator: std.mem.Allocator,
    pass: *const PlanePass,
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
    try drawSnailScene(renderer, prepared, &pass.prepared.scene, mvp, demo_passes.worldTarget(fb_size, subpixel_order, pass.opaque_backdrop), draw_buf, allocator);
}

fn renderWorld(
    quad_renderer: *const QuadRenderer,
    renderer: *snail.Renderer,
    world_passes: *const WorldPasses,
    rough_wall_text: *const SurfaceTextDraw,
    center_panel_text: *const SurfaceTextDraw,
    prepared: *const snail.PreparedResources,
    draw_buf: *[]u32,
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

    quad_renderer.drawMaterial(
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
        null,
        null,
        camera.pos,
        light_pos,
        light_color,
    );
    quad_renderer.drawMaterial(
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
        null,
        null,
        camera.pos,
        light_pos,
        light_color,
    );
    quad_renderer.drawMaterial(
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
        null,
        null,
        camera.pos,
        light_pos,
        light_color,
    );
    quad_renderer.drawMaterial(
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
        prepared,
        renderer,
        camera.pos,
        light_pos,
        light_color,
    );
    quad_renderer.drawMaterial(
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
        prepared,
        renderer,
        camera.pos,
        light_pos,
        light_color,
    );

    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
    gl.glDepthMask(gl.GL_FALSE);

    try renderPlanePass(
        renderer,
        prepared,
        draw_buf,
        allocator,
        &world_passes.glass,
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

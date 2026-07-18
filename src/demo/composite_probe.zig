//! Deterministic, windowless probe for the `fill_stroke_inside` composite
//! coverage bug. Renders a rounded-rect panel onto a perspective-projected
//! world plane over a sweep of camera angles, then scans the interior for
//! coverage "holes" — fragments strictly inside the fill whose output alpha
//! dropped below full coverage. Interior alpha must be exactly 1.0 everywhere
//! inside a rounded rect (see compositePathGroup: combined.a == fill_cov, and
//! fill_cov == 1 for any fragment inside the fill), so any hole is the bug.
//!
//! Two panels are built from the SAME geometry: the `fill_stroke_inside`
//! composite and the separate fill + center-stroke workaround. The separate
//! panel is the control (known clean); the composite is the subject. Prints a
//! per-angle hole count for each and the worst offender. Exits non-zero if the
//! composite still holes — this doubles as a regression gate.

const std = @import("std");
const snail = @import("snail");
const support = @import("support");
const gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
});
const offscreen_gl = @import("platform/offscreen_gl.zig");
const passes = @import("game/passes.zig");
const common = @import("game/common.zig");
const embed_gl = @import("embed_gl");

const W: u32 = 1100;
const H: u32 = 760;

// Panel authoring frame (matches scene.zig buildPanel).
const scene_w: f32 = 460.0;
const scene_h: f32 = 300.0;
const rect = snail.Rect{ .x = 16.0, .y = 16.0, .w = scene_w - 32.0, .h = 268.0 };
const radius: f32 = 22.0;
const stroke_w: f32 = 2.5;

// Opaque so the readback alpha == coverage with no blend ambiguity. The fill
// and stroke colors differ so a genuine border/interior mixup would also show
// up in RGB, but the alpha-hole test is the primary oracle.
const fill_paint = snail.Paint{ .solid = .{ 0.30, 0.60, 0.95, 1.0 } };
const stroke_paint = snail.Paint{ .solid = .{ 0.85, 0.95, 1.0, 1.0 } };

const Mode = enum { composite, separate, fill_only };

fn buildPanel(allocator: std.mem.Allocator, fonts: *passes.Fonts, mode: Mode) !passes.PreparedPass {
    var b = passes.PassBuilder.init(allocator, fonts);
    defer b.deinit();
    switch (mode) {
        .composite => try b.addRoundedRectWithInsideStroke(
            rect,
            fill_paint,
            .{ .paint = stroke_paint, .width = stroke_w, .placement = .inside },
            radius,
        ),
        .separate => try b.addRoundedRectFilledStroked(
            rect,
            fill_paint,
            stroke_paint,
            stroke_w,
            radius,
        ),
        // Same unit-frame authoring + placement as the composite's fill layer,
        // but a plain single-layer record: isolates the fill coverage.
        .fill_only => try b.addRoundedRectFilledUnit(rect, fill_paint, radius),
    }
    return b.freeze(fonts.pool);
}

const Panel = struct {
    pass: passes.PreparedPass,
    cache: embed_gl.Gl44BackendCache,
    binding: snail.render.records.Binding,
    words: []u32,
    segs: []snail.render.records.DrawSegment,
    words_len: usize,
    segs_len: usize,

    fn init(allocator: std.mem.Allocator, fonts: *passes.Fonts, mode: Mode) !Panel {
        var pass = try buildPanel(allocator, fonts, mode);
        errdefer pass.deinit();

        var cache = try embed_gl.Gl44BackendCache.init(allocator, fonts.pool, .{
            .max_bindings = 2,
            .layer_info_height = 128,
            .max_images = 1,
        });
        errdefer cache.deinit();
        var bindings: [1]snail.render.records.Binding = undefined;
        try cache.upload(allocator, &.{&pass.path_atlas}, &bindings);

        const words = try allocator.alloc(u32, snail.emit.wordBudget(pass.path_picture.shapes.len));
        errdefer allocator.free(words);
        const segs = try allocator.alloc(snail.render.records.DrawSegment, 4);
        errdefer allocator.free(segs);
        var wlen: usize = 0;
        var slen: usize = 0;
        _ = try snail.emit.emit(words, segs, &wlen, &slen, bindings[0], &pass.path_atlas, pass.path_picture.shapes, .identity, .{ 1, 1, 1, 1 });

        return .{
            .pass = pass,
            .cache = cache,
            .binding = bindings[0],
            .words = words,
            .segs = segs,
            .words_len = wlen,
            .segs_len = slen,
        };
    }

    fn deinit(self: *Panel, allocator: std.mem.Allocator) void {
        allocator.free(self.words);
        allocator.free(self.segs);
        self.cache.deinit();
        self.pass.deinit();
    }

    fn draw(self: *Panel, allocator: std.mem.Allocator, renderer: *embed_gl.Gl44Renderer, mvp: snail.Mat4) !void {
        const ds = @import("snail-raster").DrawState{
            .surface = .{ .pixel_width = @floatFromInt(W), .pixel_height = @floatFromInt(H), .encoding = .linear },
            .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
            .mvp = mvp,
        };
        renderer.state.beginDraw();
        try renderer.state.draw(
            allocator,
            ds,
            .{ .words = self.words[0..self.words_len], .segments = self.segs[0..self.segs_len] },
            &.{&self.cache},
        );
    }
};

/// Count interior coverage holes: pixels whose alpha dropped below `floor`
/// while a majority of their orthogonal neighbors are fully opaque. That
/// pattern is a speck strictly inside the fill — never a legitimate AA edge.
fn countHoles(px: []const u8, floor: u8) u32 {
    var holes: u32 = 0;
    var y: usize = 1;
    while (y < H - 1) : (y += 1) {
        var x: usize = 1;
        while (x < W - 1) : (x += 1) {
            const a = px[(y * W + x) * 4 + 3];
            if (a >= floor) continue;
            const up = px[((y - 1) * W + x) * 4 + 3];
            const dn = px[((y + 1) * W + x) * 4 + 3];
            const lf = px[(y * W + (x - 1)) * 4 + 3];
            const rt = px[(y * W + (x + 1)) * 4 + 3];
            var solid: u32 = 0;
            if (up == 255) solid += 1;
            if (dn == 255) solid += 1;
            if (lf == 255) solid += 1;
            if (rt == 255) solid += 1;
            if (solid >= 3) holes += 1;
        }
    }
    return holes;
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();
    _ = std.c.mkdir("zig-out", 0o755);

    var ctx = try offscreen_gl.Context.init(W, H, .gl44);
    defer ctx.deinit();

    // Plain (non-sRGB) RGBA8 target: alpha reads back as raw coverage.
    var fbo: gl.GLuint = 0;
    var color_tex: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &color_tex);
    gl.glBindTexture(gl.GL_TEXTURE_2D, color_tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8, @intCast(W), @intCast(H), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, color_tex, 0);
    if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
    defer {
        gl.glDeleteFramebuffers(1, &fbo);
        gl.glDeleteTextures(1, &color_tex);
    }
    gl.glViewport(0, 0, @intCast(W), @intCast(H));

    var fonts = try passes.initFonts(allocator);
    defer fonts.deinit();

    var renderer = try embed_gl.Gl44Renderer.init(allocator);
    defer renderer.deinit();

    var composite = try Panel.init(allocator, &fonts, .composite);
    defer composite.deinit(allocator);
    var separate = try Panel.init(allocator, &fonts, .separate);
    defer separate.deinit(allocator);
    var fill_only = try Panel.init(allocator, &fonts, .fill_only);
    defer fill_only.deinit(allocator);

    // Panel plane placement (matches scene.zig panel_plane), swept over yaw.
    const aspect = @as(f32, @floatFromInt(W)) / @as(f32, @floatFromInt(H));

    var worst_comp: u32 = 0;
    var worst_comp_angle: f32 = 0;
    var worst_sep: u32 = 0;
    var worst_fill: u32 = 0;
    var total_comp: u64 = 0;
    var total_fill: u64 = 0;

    const steps: u32 = 96;
    var i: u32 = 0;
    while (i < steps) : (i += 1) {
        const cam_angle = -0.9 + (1.8 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)));
        const cam = common.Camera{
            .pos = .{ .x = -3.85 + 6.2 * @sin(cam_angle), .y = 1.75, .z = 1.4 + 6.2 * @cos(cam_angle) },
            .yaw = cam_angle,
            .pitch = -0.05,
        };
        const view_proj = common.buildViewProjection(cam, aspect);
        const mvp = common.planeMvp(view_proj, scene_w, scene_h, .{ .x = -3.85, .y = 1.4, .z = 1.4 }, 0.0, 0.6, 2.25, 1.47, 0.0);

        const holes_comp = try renderAndCount(allocator, &renderer, &composite, mvp);
        const holes_sep = try renderAndCount(allocator, &renderer, &separate, mvp);
        const holes_fill = try renderAndCount(allocator, &renderer, &fill_only, mvp);
        total_comp += holes_comp;
        total_fill += holes_fill;
        if (holes_comp > worst_comp) {
            worst_comp = holes_comp;
            worst_comp_angle = cam_angle;
        }
        if (holes_sep > worst_sep) worst_sep = holes_sep;
        if (holes_fill > worst_fill) worst_fill = holes_fill;
        if (holes_comp > 0 or holes_sep > 0)
            std.debug.print("angle {d: >6.3}: composite={d: <4} separate={d}\n", .{ cam_angle, holes_comp, holes_sep });
    }

    std.debug.print("\n=== composite: total holes={d}, worst={d} at angle {d:.3}\n", .{ total_comp, worst_comp, worst_comp_angle });
    std.debug.print("=== fill_only: total holes={d}, worst={d}\n", .{ total_fill, worst_fill });
    std.debug.print("=== separate:  worst holes={d} (control — expected 0)\n", .{worst_sep});

    // Dump the worst composite frame + cross-check each hole against the
    // fill-only render (same rc): does the fill layer alone hole there?
    {
        const cam = common.Camera{
            .pos = .{ .x = -3.85 + 6.2 * @sin(worst_comp_angle), .y = 1.75, .z = 1.4 + 6.2 * @cos(worst_comp_angle) },
            .yaw = worst_comp_angle,
            .pitch = -0.05,
        };
        const view_proj = common.buildViewProjection(cam, aspect);
        const mvp = common.planeMvp(view_proj, scene_w, scene_h, .{ .x = -3.85, .y = 1.4, .z = 1.4 }, 0.0, 0.6, 2.25, 1.47, 0.0);
        const px = try renderToPixels(allocator, &renderer, &composite, mvp);
        defer allocator.free(px);
        // The fill-only render isolates whether the composite or the plain fill
        // holes: at a genuine composite hole the fill layer alone reads 0 too.
        const fpx = try renderToPixels(allocator, &renderer, &fill_only, mvp);
        defer allocator.free(fpx);
        try support.screenshot.writeTga("zig-out/composite-probe.tga", px, W, H);
        std.debug.print("wrote zig-out/composite-probe.tga (worst composite frame)\n", .{});

        var y: usize = 1;
        while (y < H - 1) : (y += 1) {
            var x: usize = 1;
            while (x < W - 1) : (x += 1) {
                const idx = (y * W + x) * 4;
                const a = px[idx + 3];
                if (a >= 235) continue;
                const up = px[((y - 1) * W + x) * 4 + 3];
                const dn = px[((y + 1) * W + x) * 4 + 3];
                const lf = px[(y * W + (x - 1)) * 4 + 3];
                const rt = px[(y * W + (x + 1)) * 4 + 3];
                var solid: u32 = 0;
                if (up == 255) solid += 1;
                if (dn == 255) solid += 1;
                if (lf == 255) solid += 1;
                if (rt == 255) solid += 1;
                if (solid < 3) continue;
                // Cross-check: at a genuine composite hole the fill layer alone
                // reads ~0 too (the bug is in the fill coverage, not the layer
                // composite).
                std.debug.print(
                    "  hole @({d},{d}) composite.a={d}  fill_only.a={d}\n",
                    .{ x, y, a, fpx[idx + 3] },
                );
            }
        }
    }

    if (worst_comp > 0) {
        std.debug.print("\nFAIL: fill_stroke_inside composite still holes under perspective\n", .{});
        std.process.exit(1);
    }
    std.debug.print("\nOK: no composite interior holes across the sweep\n", .{});
}

fn renderToPixels(allocator: std.mem.Allocator, renderer: *embed_gl.Gl44Renderer, panel: *Panel, mvp: snail.Mat4) ![]u8 {
    gl.glClearColor(0, 0, 0, 0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);
    try panel.draw(allocator, renderer, mvp);
    return support.screenshot.captureFramebuffer(allocator, W, H);
}

fn renderAndCount(allocator: std.mem.Allocator, renderer: *embed_gl.Gl44Renderer, panel: *Panel, mvp: snail.Mat4) !u32 {
    const px = try renderToPixels(allocator, renderer, panel, mvp);
    defer allocator.free(px);
    return countHoles(px, 235);
}

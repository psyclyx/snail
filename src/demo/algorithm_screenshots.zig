const std = @import("std");
const snail = @import("snail");
const assets_data = @import("assets");
const screenshot = @import("support").screenshot;
const egl_offscreen = @import("platform/offscreen_gl.zig");
const gl = @import("support").gl;

const Allocator = std.mem.Allocator;

const WIDTH: u32 = 320;
const HEIGHT: u32 = 200;
const GL_SRGB8_ALPHA8: gl.GLenum = 0x8C43;

const bg = [4]f32{ 0.96, 0.965, 0.975, 1.0 };
const surface = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
const border = [4]f32{ 0.82, 0.85, 0.90, 1.0 };
const ink = [4]f32{ 0.09, 0.10, 0.14, 1.0 };
const muted = [4]f32{ 0.38, 0.43, 0.50, 1.0 };
const blue = [4]f32{ 0.13, 0.36, 0.84, 1.0 };
const blue_soft = [4]f32{ 0.80, 0.88, 1.0, 1.0 };
const teal = [4]f32{ 0.09, 0.58, 0.52, 1.0 };
const teal_soft = [4]f32{ 0.77, 0.94, 0.91, 1.0 };
const rose = [4]f32{ 0.84, 0.22, 0.42, 1.0 };
const rose_soft = [4]f32{ 1.0, 0.82, 0.87, 1.0 };
const amber = [4]f32{ 0.86, 0.60, 0.14, 1.0 };
const amber_soft = [4]f32{ 1.0, 0.92, 0.72, 1.0 };

fn declareTextBlobResources(set: *snail.ResourceManifest, keys: snail.TextResourceKeys, blob: *const snail.TextBlob) !void {
    try set.putTextAtlas(keys.atlas, blob.atlas);
    if (keys.paint) |paint_key| try set.putTextPaint(paint_key, blob);
}

const Diagram = enum {
    atlas,
    coverage,
};

const Assets = struct {
    fonts: snail.TextAtlas,

    fn init(allocator: Allocator) !Assets {
        var fonts = try snail.TextAtlas.init(allocator, &.{
            .{ .data = assets_data.noto_sans_regular },
            .{ .data = assets_data.noto_sans_bold, .weight = .bold },
        });
        errdefer fonts.deinit();

        const text =
            "1. Prep curves and bands 2. Evaluate coverage" ++
            "outline curves bands quad sample roots blend alpha";
        if (try fonts.ensureText(.{}, text)) |next| {
            fonts.deinit();
            fonts = next;
        }
        if (try fonts.ensureText(.{ .weight = .bold }, text)) |next| {
            fonts.deinit();
            fonts = next;
        }
        if (try fonts.ensureText(.{ .weight = .bold }, "A")) |next| {
            fonts.deinit();
            fonts = next;
        }

        return .{ .fonts = fonts };
    }

    fn deinit(self: *Assets) void {
        self.fonts.deinit();
    }
};

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gl_ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT);
    defer gl_ctx.deinit();

    var fbo: gl.GLuint = 0;
    var fbo_tex: gl.GLuint = 0;
    gl.glGenFramebuffers(1, &fbo);
    gl.glGenTextures(1, &fbo_tex);
    defer gl.glDeleteFramebuffers(1, &fbo);
    defer gl.glDeleteTextures(1, &fbo_tex);

    gl.glBindTexture(gl.GL_TEXTURE_2D, fbo_tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, WIDTH, HEIGHT, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, fbo);
    gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, fbo_tex, 0);
    if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) return error.FramebufferIncomplete;
    gl.glViewport(0, 0, WIDTH, HEIGHT);

    var scene_assets = try Assets.init(allocator);
    defer scene_assets.deinit();

    var gl_renderer = try snail.GlRenderer.init(allocator);
    defer gl_renderer.deinit();
    var renderer = gl_renderer.asRenderer();

    try renderDiagram(allocator, &scene_assets, &renderer, .atlas, "zig-out/algorithm-atlas.png");
    try renderDiagram(allocator, &scene_assets, &renderer, .coverage, "zig-out/algorithm-coverage.png");
}

fn renderDiagram(
    allocator: Allocator,
    scene_assets: *Assets,
    renderer: *snail.Renderer,
    diagram: Diagram,
    path: [*:0]const u8,
) !void {
    var text_builder = snail.TextBlobBuilder.init(allocator, &scene_assets.fonts);
    defer text_builder.deinit();
    switch (diagram) {
        .atlas => try buildAtlasText(&text_builder),
        .coverage => try buildCoverageText(&text_builder),
    }
    var text_blob = try text_builder.finish();
    defer text_blob.deinit();

    var path_builder = snail.PathPictureBuilder.init(allocator);
    defer path_builder.deinit();
    switch (diagram) {
        .atlas => try buildAtlasPaths(&path_builder),
        .coverage => try buildCoveragePaths(&path_builder),
    }
    var path_picture = try path_builder.freeze(.{ .persistent_allocator = allocator, .scratch_allocator = allocator });
    defer path_picture.deinit();

    var resource_entries: [8]snail.ResourceManifest.Entry = undefined;
    var resources = snail.ResourceManifest.init(&resource_entries);
    try resources.putPathPicture(snail.ResourceKey.named("diagram_paths"), &path_picture);
    const text_keys = snail.ResourceManifest.textBlobResourceKeys(snail.ResourceKey.named("diagram_fonts"), snail.ResourceKey.named("diagram_text"), &text_blob);
    try declareTextBlobResources(&resources, text_keys, &text_blob);

    var scene = snail.Scene.init(allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &path_picture, .resource_key = snail.ResourceKey.named("diagram_paths") });
    try scene.addText(.{ .blob = &text_blob, .resources = text_keys });
    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &resources);
    defer prepared.deinit();

    const clear = srgbToLinearColor(bg);
    gl.glClearColor(clear[0], clear[1], clear[2], clear[3]);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    const w: f32 = @floatFromInt(WIDTH);
    const h: f32 = @floatFromInt(HEIGHT);
    const draw_state = snail.DrawState{
        .mvp = snail.Mat4.ortho(0, w, h, 0, -1, 1),
        .surface = .{
            .pixel_width = w,
            .pixel_height = h,
            .encoding = .srgb,
        },
    };
    var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, &scene);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, draw_state);

    const pixels = try screenshot.captureFramebuffer(allocator, WIDTH, HEIGHT);
    defer allocator.free(pixels);
    try screenshot.writePng(allocator, path, pixels, WIDTH, HEIGHT);
    std.debug.print("wrote {s}\n", .{std.mem.span(path)});
}

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

fn srgbToLinearColor(c: [4]f32) [4]f32 {
    return .{ srgbToLinear(c[0]), srgbToLinear(c[1]), srgbToLinear(c[2]), c[3] };
}

fn fill(color: [4]f32) snail.FillStyle {
    return .{ .paint = .{ .solid = color } };
}

fn stroke(color: [4]f32, width: f32) snail.StrokeStyle {
    return .{ .paint = .{ .solid = color }, .width = width, .cap = .round, .join = .round };
}

fn point(x: f32, y: f32) snail.Vec2 {
    return .{ .x = x, .y = y };
}

fn rect(x: f32, y: f32, w: f32, h: f32) snail.Rect {
    return .{ .x = x, .y = y, .w = w, .h = h };
}

fn appendText(
    builder: *snail.TextBlobBuilder,
    style: snail.FontStyle,
    text: []const u8,
    x: f32,
    y: f32,
    em: f32,
    color: [4]f32,
) !void {
    var shaped = try builder.atlas.shapeText(builder.allocator, style, text);
    defer shaped.deinit();
    _ = try builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = x, .y = y }, .em = em },
        .fill = .{ .solid = color },
    });
}

fn card(builder: *snail.PathPictureBuilder, r: snail.Rect) !void {
    try builder.addRoundedRect(r, fill(surface), .{
        .paint = .{ .solid = border },
        .width = 1.0,
        .join = .round,
        .placement = .inside,
    }, 6, .identity);
}

fn line(builder: *snail.PathPictureBuilder, a: snail.Vec2, b: snail.Vec2, color: [4]f32, width: f32) !void {
    var path = snail.Path.init(builder.allocator);
    defer path.deinit();
    try path.moveTo(a);
    try path.lineTo(b);
    try builder.addStrokedPath(&path, stroke(color, width), .identity);
}

fn arrow(builder: *snail.PathPictureBuilder, a: snail.Vec2, b: snail.Vec2, color: [4]f32) !void {
    try line(builder, a, b, color, 1.5);
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = @max(@sqrt(dx * dx + dy * dy), 0.001);
    const ux = dx / len;
    const uy = dy / len;
    const px = -uy;
    const py = ux;
    const back = 7.0;
    const wing = 3.5;
    var head = snail.Path.init(builder.allocator);
    defer head.deinit();
    try head.moveTo(b);
    try head.lineTo(point(b.x - ux * back + px * wing, b.y - uy * back + py * wing));
    try head.lineTo(point(b.x - ux * back - px * wing, b.y - uy * back - py * wing));
    try head.close();
    try builder.addFilledPath(&head, fill(color), .identity);
}

fn dot(builder: *snail.PathPictureBuilder, center: snail.Vec2, radius: f32, color: [4]f32) !void {
    try builder.addFilledEllipse(rect(center.x - radius, center.y - radius, radius * 2, radius * 2), fill(color), .identity);
}

const Layout = struct {
    const title_x: f32 = 14;
    const title_baseline: f32 = 25;
    const title_size: f32 = 15;
    const label_size: f32 = 8;
    const content_top: f32 = 40;
    const panel_h: f32 = 126;
    const margin: f32 = 12;
    const gap: f32 = 8;
    const card_radius: f32 = 6;

    const Atlas = struct {
        outline: snail.Rect,
        curves: snail.Rect,
        bands: snail.Rect,
        quad: snail.Rect,
    };

    const Coverage = struct {
        plot: snail.Rect,
        flow: snail.Rect,
    };

    fn atlas() Atlas {
        const panel_w: f32 = 68;
        return .{
            .outline = rect(margin, content_top, panel_w, panel_h),
            .curves = rect(margin + (panel_w + gap), content_top, panel_w, panel_h),
            .bands = rect(margin + (panel_w + gap) * 2, content_top, panel_w, panel_h),
            .quad = rect(margin + (panel_w + gap) * 3, content_top, panel_w, panel_h),
        };
    }

    fn coverage() Coverage {
        return .{
            .plot = rect(margin, content_top, 178, panel_h),
            .flow = rect(202, content_top, 106, panel_h),
        };
    }

    fn labelBaseline(panel: snail.Rect) f32 {
        return panel.y + 13;
    }

    fn labelX(panel: snail.Rect) f32 {
        return panel.x + 14;
    }
};

fn rel(r: snail.Rect, x: f32, y: f32) snail.Vec2 {
    return point(r.x + r.w * x, r.y + r.h * y);
}

fn relRect(r: snail.Rect, x: f32, y: f32, w: f32, h: f32) snail.Rect {
    return rect(r.x + r.w * x, r.y + r.h * y, r.w * w, r.h * h);
}

fn innerRect(r: snail.Rect, pad_x: f32, pad_y: f32) snail.Rect {
    return rect(r.x + pad_x, r.y + pad_y, r.w - pad_x * 2, r.h - pad_y * 2);
}

fn connectPanels(builder: *snail.PathPictureBuilder, from: snail.Rect, to: snail.Rect) !void {
    try arrow(builder, point(from.x + from.w + 2, from.y + from.h * 0.5), point(to.x - 2, to.y + to.h * 0.5), muted);
}

fn buildAtlasText(builder: *snail.TextBlobBuilder) !void {
    const panels = Layout.atlas();
    try appendText(builder, .{ .weight = .bold }, "1. Prep curves and bands", Layout.title_x, Layout.title_baseline, Layout.title_size, ink);
    try appendText(builder, .{}, "outline", Layout.labelX(panels.outline), Layout.labelBaseline(panels.outline), Layout.label_size, ink);
    try appendText(builder, .{}, "curves", Layout.labelX(panels.curves), Layout.labelBaseline(panels.curves), Layout.label_size, ink);
    try appendText(builder, .{}, "bands", Layout.labelX(panels.bands), Layout.labelBaseline(panels.bands), Layout.label_size, ink);
    try appendText(builder, .{}, "quad", Layout.labelX(panels.quad), Layout.labelBaseline(panels.quad), Layout.label_size, ink);

    const glyph_baseline = rel(panels.quad, 0.20, 0.86);
    try appendText(builder, .{ .weight = .bold }, "A", glyph_baseline.x, glyph_baseline.y, 66, blue);
}

fn buildCoverageText(builder: *snail.TextBlobBuilder) !void {
    const panels = Layout.coverage();
    try appendText(builder, .{ .weight = .bold }, "2. Evaluate coverage", Layout.title_x, Layout.title_baseline, Layout.title_size, ink);
    try appendText(builder, .{}, "sample", Layout.labelX(panels.plot), Layout.labelBaseline(panels.plot), Layout.label_size, ink);
    try appendText(builder, .{}, "roots", panels.plot.x + panels.plot.w * 0.61, Layout.labelBaseline(panels.plot), Layout.label_size, ink);
    try appendText(builder, .{}, "blend", panels.flow.x + panels.flow.w * 0.24, Layout.labelBaseline(panels.flow), Layout.label_size, ink);
    try appendText(builder, .{}, "alpha", panels.flow.x + panels.flow.w * 0.46, panels.flow.y + panels.flow.h + 3, Layout.label_size, ink);
}

fn buildAtlasPaths(builder: *snail.PathPictureBuilder) !void {
    try builder.addFilledRect(rect(0, 0, @floatFromInt(WIDTH), @floatFromInt(HEIGHT)), fill(bg), .identity);

    const panels = Layout.atlas();
    const panel_list = [_]snail.Rect{ panels.outline, panels.curves, panels.bands, panels.quad };
    for (panel_list) |r| try card(builder, r);
    try connectPanels(builder, panels.outline, panels.curves);
    try connectPanels(builder, panels.curves, panels.bands);
    try connectPanels(builder, panels.bands, panels.quad);

    var glyph = snail.Path.init(builder.allocator);
    defer glyph.deinit();
    const outline_body = relRect(panels.outline, 0.28, 0.24, 0.46, 0.53);
    const outline_hole = relRect(panels.outline, 0.41, 0.38, 0.20, 0.26);
    try glyph.addEllipse(outline_body);
    try glyph.addEllipseReversed(outline_hole);
    try builder.addPath(&glyph, fill(blue_soft), stroke(blue, 1.4), .identity);

    var curve = snail.Path.init(builder.allocator);
    defer curve.deinit();
    const p0 = rel(panels.outline, 0.31, 0.73);
    const p1 = rel(panels.outline, 0.46, 0.21);
    const p2 = rel(panels.outline, 0.77, 0.28);
    const p3 = rel(panels.outline, 0.73, 0.68);
    try curve.moveTo(p0);
    try curve.cubicTo(p1, p2, p3);
    try builder.addStrokedPath(&curve, stroke(rose, 1.5), .identity);
    try dot(builder, p0, 2.3, rose);
    try dot(builder, p1, 1.8, amber);
    try dot(builder, p2, 1.8, amber);
    try dot(builder, p3, 2.3, rose);
    try line(builder, p0, p1, amber, 0.7);
    try line(builder, p1, p2, amber, 0.7);
    try line(builder, p2, p3, amber, 0.7);

    const cell_colors = [_][4]f32{ blue_soft, teal_soft, amber_soft, rose_soft };
    const tex_origin = rel(panels.curves, 0.13, 0.30);
    const tex_cell = snail.Vec2{ .x = panels.curves.w * 0.16, .y = panels.curves.h * 0.14 };
    const tex_gap = panels.curves.w * 0.04;
    const tex_row_gap = panels.curves.h * 0.21;
    for (0..2) |row| {
        for (0..4) |i| {
            const x = tex_origin.x + @as(f32, @floatFromInt(i)) * (tex_cell.x + tex_gap);
            const y = tex_origin.y + @as(f32, @floatFromInt(row)) * tex_row_gap;
            try builder.addRoundedRect(rect(x, y, tex_cell.x, tex_cell.y), fill(cell_colors[i]), null, 2, .identity);
        }
        try builder.addFilledRect(rect(tex_origin.x, tex_origin.y + tex_cell.y + 4 + @as(f32, @floatFromInt(row)) * tex_row_gap, panels.curves.w * 0.76, 2), fill(if (row == 0) blue else teal), .identity);
    }

    const grid = relRect(panels.bands, 0.17, 0.23, 0.63, 0.53);
    try builder.addRoundedRect(grid, fill(.{ 0.98, 0.99, 1.0, 1.0 }), stroke(border, 0.8), 3, .identity);
    for (1..4) |i| {
        const f: f32 = @floatFromInt(i);
        try line(builder, rel(grid, 0, f / 4), rel(grid, 1, f / 4), border, 0.7);
        try line(builder, rel(grid, f / 4, 0), rel(grid, f / 4, 1), border, 0.7);
    }
    try builder.addFilledRect(relRect(grid, 0, 0.50, 1, 0.25), fill(.{ 0.80, 0.88, 1.0, 0.58 }), .identity);
    try builder.addFilledRect(relRect(grid, 0.50, 0, 0.25, 1), fill(.{ 0.77, 0.94, 0.91, 0.58 }), .identity);

    var quad = snail.Path.init(builder.allocator);
    defer quad.deinit();
    try quad.moveTo(rel(panels.quad, 0.18, 0.24));
    try quad.lineTo(rel(panels.quad, 0.83, 0.21));
    try quad.lineTo(rel(panels.quad, 0.91, 0.79));
    try quad.lineTo(rel(panels.quad, 0.11, 0.83));
    try quad.close();
    try builder.addPath(&quad, fill(.{ 0.91, 0.95, 1.0, 1.0 }), stroke(blue, 1.4), .identity);
    try dot(builder, rel(panels.quad, 0.24, 0.51), 1.8, rose);
    try dot(builder, rel(panels.quad, 0.56, 0.50), 1.8, rose);
    try dot(builder, rel(panels.quad, 0.27, 0.67), 1.8, rose);
    try dot(builder, rel(panels.quad, 0.62, 0.67), 1.8, rose);
}

fn buildCoveragePaths(builder: *snail.PathPictureBuilder) !void {
    try builder.addFilledRect(rect(0, 0, @floatFromInt(WIDTH), @floatFromInt(HEIGHT)), fill(bg), .identity);
    const panels = Layout.coverage();
    try card(builder, panels.plot);
    try card(builder, panels.flow);

    const plot = innerRect(panels.plot, 28, 28);
    for (0..6) |i| {
        const u = @as(f32, @floatFromInt(i)) / 5.0;
        try line(builder, rel(plot, u, 0), rel(plot, u, 1), .{ 0.90, 0.92, 0.95, 1.0 }, 0.7);
    }
    for (0..4) |i| {
        const v = @as(f32, @floatFromInt(i)) / 3.0;
        try line(builder, rel(plot, 0, v), rel(plot, 1, v), .{ 0.90, 0.92, 0.95, 1.0 }, 0.7);
    }

    var glyph_curve = snail.Path.init(builder.allocator);
    defer glyph_curve.deinit();
    try glyph_curve.moveTo(rel(plot, 0.08, 0.94));
    try glyph_curve.cubicTo(rel(plot, 0.15, -0.15), rel(plot, 0.86, -0.15), rel(plot, 0.98, 0.94));
    try builder.addStrokedPath(&glyph_curve, stroke(blue, 2.2), .identity);

    const sample = rel(plot, 0.51, 0.50);
    const sample_box = 16.0;
    try builder.addRoundedRect(rect(sample.x - sample_box * 0.5, sample.y - sample_box * 0.5, sample_box, sample_box), fill(.{ 1.0, 0.96, 0.82, 0.70 }), stroke(amber, 1.0), 2, .identity);
    try arrow(builder, rel(plot, 0.05, 0.50), rel(plot, 1.12, 0.50), rose);
    try arrow(builder, rel(plot, 0.51, 1.10), rel(plot, 0.51, -0.10), teal);
    try dot(builder, sample, 3.0, ink);
    try dot(builder, rel(plot, 0.22, 0.50), 2.2, rose);
    try dot(builder, rel(plot, 0.81, 0.50), 2.2, rose);
    try dot(builder, rel(plot, 0.51, -0.01), 2.2, teal);
    try dot(builder, rel(plot, 0.51, 0.95), 2.2, teal);

    try arrow(builder, point(panels.plot.x + panels.plot.w - 1, sample.y), point(panels.flow.x - 1, sample.y), muted);

    const flow_w: f32 = panels.flow.w * 0.65;
    const flow_h: f32 = 24;
    const flow_x = panels.flow.x + panels.flow.w * 0.13;
    const first_y = panels.flow.y + panels.flow.h * 0.20;
    const flow_step = panels.flow.h * 0.24;
    const flow_blocks = [_]struct { y: f32, color: [4]f32 }{
        .{ .y = first_y, .color = blue_soft },
        .{ .y = first_y + flow_step, .color = rose_soft },
        .{ .y = first_y + flow_step * 2, .color = teal_soft },
    };
    for (flow_blocks) |block| {
        try builder.addRoundedRect(rect(flow_x, block.y, flow_w, flow_h), fill(block.color), stroke(border, 0.8), 4, .identity);
    }
    try arrow(builder, point(flow_x + flow_w * 0.5, first_y + flow_h + 1), point(flow_x + flow_w * 0.5, first_y + flow_step - 1), muted);
    try arrow(builder, point(flow_x + flow_w * 0.5, first_y + flow_step + flow_h + 1), point(flow_x + flow_w * 0.5, first_y + flow_step * 2 - 1), muted);

    for (0..6) |i| {
        const alpha = (@as(f32, @floatFromInt(i)) + 1.0) / 6.0;
        try builder.addRoundedRect(
            rect(flow_x + 6 + @as(f32, @floatFromInt(i)) * 12, panels.flow.y + panels.flow.h - 10, 9, 9),
            fill(.{ 0.13, 0.36, 0.84, alpha }),
            null,
            1.5,
            .identity,
        );
    }
}

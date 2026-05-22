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

fn declareTextBlobResources(set: *snail.ResourceManifest, atlas_key: snail.ResourceKey, blob_key: snail.ResourceKey, blob: *const snail.TextBlob) !snail.TextResourceKeys {
    const resources = blob.resourceKeys(atlas_key, blob_key);
    try set.putTextBlob(resources, blob);
    return resources;
}

const Diagram = enum {
    prep_curves,
    prep_bands,
    draw_quad,
    sample_bands,
    solve_roots,
    winding,
    fill_alpha,
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
            "1. Store curves 2. Build bands 3. Draw quads 4. Pick bands " ++
            "5. Solve roots 6. Add winding 7. Fill alpha " ++
            "outline curve record bands band lists bounds quad local coords sample candidates ray roots " ++
            "signed roots winding fill rule alpha h roots v roots filled +1 hole +1 -1 = 0 w=+1 w=0 edge 0..1 alpha 0.58";
        if (try fonts.ensureText(.{}, text)) |next| {
            fonts.deinit();
            fonts = next;
        }
        if (try fonts.ensureText(.{ .weight = .bold }, text)) |next| {
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

    var gl_ctx = try egl_offscreen.Context.init(WIDTH, HEIGHT, .gl33);
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

    var gl_renderer = try snail.Gl33Renderer.init(allocator);
    defer gl_renderer.deinit();
    var renderer = gl_renderer.asRenderer();

    try renderDiagram(allocator, &scene_assets, &renderer, .prep_curves, "zig-out/algorithm-curves.png");
    try renderDiagram(allocator, &scene_assets, &renderer, .prep_bands, "zig-out/algorithm-bands.png");
    try renderDiagram(allocator, &scene_assets, &renderer, .draw_quad, "zig-out/algorithm-quad.png");
    try renderDiagram(allocator, &scene_assets, &renderer, .sample_bands, "zig-out/algorithm-sample-bands.png");
    try renderDiagram(allocator, &scene_assets, &renderer, .solve_roots, "zig-out/algorithm-roots.png");
    try renderDiagram(allocator, &scene_assets, &renderer, .winding, "zig-out/algorithm-winding.png");
    try renderDiagram(allocator, &scene_assets, &renderer, .fill_alpha, "zig-out/algorithm-alpha.png");
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
    try buildDiagramText(&text_builder, diagram);
    var text_blob = try text_builder.finish();
    defer text_blob.deinit();

    var path_builder = snail.PathPictureBuilder.init(allocator);
    defer path_builder.deinit();
    try buildDiagramPaths(&path_builder, diagram);
    var path_picture = try path_builder.freeze(.{ .persistent_allocator = allocator, .scratch_allocator = allocator });
    defer path_picture.deinit();

    var resource_entries: [8]snail.ResourceManifest.Entry = undefined;
    var resources = snail.ResourceManifest.init(&resource_entries);
    try resources.putPathPicture(snail.ResourceKey.named("diagram_paths"), &path_picture);
    const text_keys = try declareTextBlobResources(&resources, snail.ResourceKey.named("diagram_fonts"), snail.ResourceKey.named("diagram_text"), &text_blob);

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
        .source = .{ .shaped = shaped.glyphs },
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

fn buildDiagramText(builder: *snail.TextBlobBuilder, diagram: Diagram) !void {
    switch (diagram) {
        .prep_curves => {
            try appendText(builder, .{ .weight = .bold }, "1. Store curves", Layout.title_x, Layout.title_baseline, Layout.title_size, ink);
            try appendText(builder, .{}, "outline", 38, 60, 12, ink);
            try appendText(builder, .{}, "curve record", 202, 60, 12, ink);
        },
        .prep_bands => {
            try appendText(builder, .{ .weight = .bold }, "2. Build bands", Layout.title_x, Layout.title_baseline, Layout.title_size, ink);
            try appendText(builder, .{}, "bands", 55, 60, 12, ink);
            try appendText(builder, .{}, "band lists", 209, 60, 12, ink);
        },
        .draw_quad => {
            try appendText(builder, .{ .weight = .bold }, "3. Draw quads", Layout.title_x, Layout.title_baseline, Layout.title_size, ink);
            try appendText(builder, .{}, "bounds quad", 36, 60, 12, ink);
            try appendText(builder, .{}, "local coords", 204, 60, 12, ink);
        },
        .sample_bands => {
            try appendText(builder, .{ .weight = .bold }, "4. Pick bands", Layout.title_x, Layout.title_baseline, Layout.title_size, ink);
            try appendText(builder, .{}, "sample", 50, 60, 12, ink);
            try appendText(builder, .{}, "candidates", 206, 60, 12, ink);
        },
        .solve_roots => {
            try appendText(builder, .{ .weight = .bold }, "5. Solve roots", Layout.title_x, Layout.title_baseline, Layout.title_size, ink);
            try appendText(builder, .{}, "ray roots", 54, 60, 12, ink);
            try appendText(builder, .{}, "h roots", 222, 78, 11, rose);
            try appendText(builder, .{}, "v roots", 222, 123, 11, teal);
        },
        .winding => {
            try appendText(builder, .{ .weight = .bold }, "6. Add winding", Layout.title_x, Layout.title_baseline, Layout.title_size, ink);
            try appendText(builder, .{}, "signed roots", 52, 60, 12, ink);
            try appendText(builder, .{}, "winding", 226, 60, 12, ink);
            try appendText(builder, .{ .weight = .bold }, "+1", 142, 91, 11, rose);
            try appendText(builder, .{ .weight = .bold }, "-1", 110, 123, 11, teal);
            try appendText(builder, .{ .weight = .bold }, "+1", 144, 123, 11, rose);
            try appendText(builder, .{}, "filled", 214, 92, 11, ink);
            try appendText(builder, .{}, "w=+1", 259, 92, 11, ink);
            try appendText(builder, .{}, "hole", 214, 125, 11, ink);
            try appendText(builder, .{}, "w=0", 263, 125, 11, ink);
        },
        .fill_alpha => {
            try appendText(builder, .{ .weight = .bold }, "7. Fill alpha", Layout.title_x, Layout.title_baseline, Layout.title_size, ink);
            try appendText(builder, .{}, "fill rule", 48, 60, 12, ink);
            try appendText(builder, .{}, "alpha", 230, 60, 12, ink);
            try appendText(builder, .{}, "w=+1  fill", 61, 88, 11, ink);
            try appendText(builder, .{}, "w=0  empty", 61, 116, 11, ink);
            try appendText(builder, .{}, "edge  0..1", 61, 144, 11, ink);
            try appendText(builder, .{}, "alpha 0.58", 222, 146, 11, ink);
        },
    }
}

fn buildDiagramPaths(builder: *snail.PathPictureBuilder, diagram: Diagram) !void {
    try builder.addFilledRect(rect(0, 0, @floatFromInt(WIDTH), @floatFromInt(HEIGHT)), fill(bg), .identity);
    switch (diagram) {
        .prep_curves => try buildPrepCurvesPaths(builder),
        .prep_bands => try buildPrepBandsPaths(builder),
        .draw_quad => try buildDrawQuadPaths(builder),
        .sample_bands => try buildSampleBandsPaths(builder),
        .solve_roots => try buildSolveRootsPaths(builder),
        .winding => try buildWindingPaths(builder),
        .fill_alpha => try buildFillAlphaPaths(builder),
    }
}

const UnitPoint = struct {
    x: f32,
    y: f32,
};

const UnitCubic = struct {
    p0: UnitPoint,
    p1: UnitPoint,
    p2: UnitPoint,
    p3: UnitPoint,
};

const highlighted_curve_index: usize = 0;
const sample_unit = UnitPoint{ .x = 0.79, .y = 0.37 };
const glyph_curve_colors = [_][4]f32{ rose, amber, teal, blue, rose, amber, teal, blue };
const outer_curves = [_]UnitCubic{
    .{ .p0 = .{ .x = 0.50, .y = 0.13 }, .p1 = .{ .x = 0.688, .y = 0.13 }, .p2 = .{ .x = 0.84, .y = 0.305 }, .p3 = .{ .x = 0.84, .y = 0.52 } },
    .{ .p0 = .{ .x = 0.84, .y = 0.52 }, .p1 = .{ .x = 0.84, .y = 0.735 }, .p2 = .{ .x = 0.688, .y = 0.91 }, .p3 = .{ .x = 0.50, .y = 0.91 } },
    .{ .p0 = .{ .x = 0.50, .y = 0.91 }, .p1 = .{ .x = 0.312, .y = 0.91 }, .p2 = .{ .x = 0.16, .y = 0.735 }, .p3 = .{ .x = 0.16, .y = 0.52 } },
    .{ .p0 = .{ .x = 0.16, .y = 0.52 }, .p1 = .{ .x = 0.16, .y = 0.305 }, .p2 = .{ .x = 0.312, .y = 0.13 }, .p3 = .{ .x = 0.50, .y = 0.13 } },
};
const inner_curves = [_]UnitCubic{
    .{ .p0 = .{ .x = 0.50, .y = 0.35 }, .p1 = .{ .x = 0.428, .y = 0.35 }, .p2 = .{ .x = 0.37, .y = 0.426 }, .p3 = .{ .x = 0.37, .y = 0.52 } },
    .{ .p0 = .{ .x = 0.37, .y = 0.52 }, .p1 = .{ .x = 0.37, .y = 0.614 }, .p2 = .{ .x = 0.428, .y = 0.69 }, .p3 = .{ .x = 0.50, .y = 0.69 } },
    .{ .p0 = .{ .x = 0.50, .y = 0.69 }, .p1 = .{ .x = 0.572, .y = 0.69 }, .p2 = .{ .x = 0.63, .y = 0.614 }, .p3 = .{ .x = 0.63, .y = 0.52 } },
    .{ .p0 = .{ .x = 0.63, .y = 0.52 }, .p1 = .{ .x = 0.63, .y = 0.426 }, .p2 = .{ .x = 0.572, .y = 0.35 }, .p3 = .{ .x = 0.50, .y = 0.35 } },
};
const glyph_curves = outer_curves ++ inner_curves;

fn withAlpha(color: [4]f32, alpha: f32) [4]f32 {
    return .{ color[0], color[1], color[2], alpha };
}

fn curveColor(index: usize) [4]f32 {
    return glyph_curve_colors[index % glyph_curve_colors.len];
}

fn unitRel(area: snail.Rect, p: UnitPoint) snail.Vec2 {
    return rel(area, p.x, p.y);
}

fn appendUnitCubic(path: *snail.Path, area: snail.Rect, curve: UnitCubic) !void {
    try path.cubicTo(unitRel(area, curve.p1), unitRel(area, curve.p2), unitRel(area, curve.p3));
}

fn appendContour(path: *snail.Path, area: snail.Rect, curves: []const UnitCubic) !void {
    try path.moveTo(unitRel(area, curves[0].p0));
    for (curves) |curve| try appendUnitCubic(path, area, curve);
    try path.close();
}

fn appendGlyphOutline(path: *snail.Path, area: snail.Rect) !void {
    try appendContour(path, area, outer_curves[0..]);
    try appendContour(path, area, inner_curves[0..]);
}

fn addUnitCubic(builder: *snail.PathPictureBuilder, area: snail.Rect, curve: UnitCubic, color: [4]f32, width: f32) !void {
    var path = snail.Path.init(builder.allocator);
    defer path.deinit();
    try path.moveTo(unitRel(area, curve.p0));
    try appendUnitCubic(&path, area, curve);
    try builder.addStrokedPath(&path, stroke(color, width), .identity);
}

fn addUnitCubicControls(builder: *snail.PathPictureBuilder, area: snail.Rect, curve: UnitCubic) !void {
    const p0 = unitRel(area, curve.p0);
    const p1 = unitRel(area, curve.p1);
    const p2 = unitRel(area, curve.p2);
    const p3 = unitRel(area, curve.p3);
    try line(builder, p0, p1, withAlpha(amber, 0.86), 0.8);
    try line(builder, p1, p2, withAlpha(amber, 0.86), 0.8);
    try line(builder, p2, p3, withAlpha(amber, 0.86), 0.8);
    try dot(builder, p0, 2.6, rose);
    try dot(builder, p1, 2.0, amber);
    try dot(builder, p2, 2.0, amber);
    try dot(builder, p3, 2.6, rose);
}

fn addGlyphFill(builder: *snail.PathPictureBuilder, area: snail.Rect, alpha: f32) !void {
    var glyph = snail.Path.init(builder.allocator);
    defer glyph.deinit();
    try appendGlyphOutline(&glyph, area);
    try builder.addPath(&glyph, fill(withAlpha(blue_soft, alpha)), stroke(withAlpha(blue, @min(alpha + 0.18, 1.0)), 1.6), .identity);
}

fn addGlyphCurves(builder: *snail.PathPictureBuilder, area: snail.Rect, highlight: bool) !void {
    for (glyph_curves, 0..) |curve, i| {
        const is_highlight = highlight and i == highlighted_curve_index;
        const color = if (is_highlight) rose else withAlpha(curveColor(i), 0.72);
        const width: f32 = if (is_highlight) 2.4 else 1.35;
        try addUnitCubic(builder, area, curve, color, width);
    }
    if (highlight) try addUnitCubicControls(builder, area, glyph_curves[highlighted_curve_index]);
}

fn addOutlineGlyph(builder: *snail.PathPictureBuilder, area: snail.Rect) !void {
    try addGlyphFill(builder, area, 1.0);
    try addGlyphCurves(builder, area, true);
}

fn addCurveAtlas(builder: *snail.PathPictureBuilder, area: snail.Rect) !void {
    const plot = rect(area.x + 13, area.y + 2, area.w - 26, area.h - 24);
    try builder.addRoundedRect(plot, fill(.{ 0.985, 0.99, 1.0, 1.0 }), stroke(border, 0.8), 3, .identity);
    try addUnitCubic(builder, plot, glyph_curves[highlighted_curve_index], rose, 2.4);
    try addUnitCubicControls(builder, plot, glyph_curves[highlighted_curve_index]);

    const cell_w: f32 = 11;
    const cell_h: f32 = 9;
    const gap: f32 = 5;
    const start_x = area.x + (area.w - cell_w * 4 - gap * 3) * 0.5;
    const y = area.y + area.h - 15;
    const cell_colors = [_][4]f32{ rose_soft, amber_soft, teal_soft, blue_soft };
    for (0..4) |i| {
        const x = start_x + @as(f32, @floatFromInt(i)) * (cell_w + gap);
        try builder.addRoundedRect(rect(x, y, cell_w, cell_h), fill(cell_colors[i]), stroke(border, 0.7), 2, .identity);
    }
}

fn addGridLines(builder: *snail.PathPictureBuilder, grid: snail.Rect, cols: u32, rows: u32) !void {
    var i: u32 = 1;
    while (i < cols) : (i += 1) {
        const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(cols));
        try line(builder, rel(grid, u, 0), rel(grid, u, 1), border, 0.7);
    }
    i = 1;
    while (i < rows) : (i += 1) {
        const v = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rows));
        try line(builder, rel(grid, 0, v), rel(grid, 1, v), border, 0.7);
    }
}

fn addSampleMarker(builder: *snail.PathPictureBuilder, area: snail.Rect, unit: UnitPoint, size: f32) !void {
    const sample = unitRel(area, unit);
    try builder.addRoundedRect(rect(sample.x - size * 0.5, sample.y - size * 0.5, size, size), fill(.{ 1.0, 0.94, 0.72, 0.74 }), stroke(amber, 1.0), 2, .identity);
    try dot(builder, sample, 3.0, ink);
}

fn addBandGrid(builder: *snail.PathPictureBuilder, area: snail.Rect, with_sample: bool) !void {
    const grid = rect(area.x + 22, area.y + 32, area.w - 44, area.h - 50);
    try builder.addRoundedRect(grid, fill(.{ 0.985, 0.99, 1.0, 1.0 }), stroke(border, 0.9), 4, .identity);

    if (with_sample) {
        const cols: f32 = 5;
        const rows: f32 = 5;
        const col: f32 = 3;
        const row: f32 = 1;
        try builder.addFilledRect(rect(grid.x + grid.w * col / cols, grid.y, grid.w / cols, grid.h), fill(.{ 0.77, 0.94, 0.91, 0.64 }), .identity);
        try builder.addFilledRect(rect(grid.x, grid.y + grid.h * row / rows, grid.w, grid.h / rows), fill(.{ 0.80, 0.88, 1.0, 0.64 }), .identity);
    } else {
        try builder.addFilledRect(relRect(grid, 0, 0.20, 1, 0.20), fill(.{ 0.80, 0.88, 1.0, 0.34 }), .identity);
        try builder.addFilledRect(relRect(grid, 0.60, 0, 0.20, 1), fill(.{ 0.77, 0.94, 0.91, 0.34 }), .identity);
    }
    try addGridLines(builder, grid, 5, 5);
    try addGlyphFill(builder, innerRect(grid, 3, 1), 0.55);
    try addGlyphCurves(builder, innerRect(grid, 3, 1), with_sample);
    if (with_sample) try addSampleMarker(builder, innerRect(grid, 3, 1), sample_unit, 13);
}

fn addBandLists(builder: *snail.PathPictureBuilder, area: snail.Rect, compact: bool) !void {
    const row_h: f32 = if (compact) 16 else 13;
    const row_gap: f32 = if (compact) 7 else 5;
    const row_count: usize = if (compact) 4 else 5;
    const start_offset: f32 = if (compact) 32.0 else 30.0;
    const start_y = area.y + start_offset;
    const row_x = area.x + 16;
    const row_w = area.w - 32;
    const records = [_][]const usize{
        &.{ 0, 3 },
        &.{ 0, 1, 6 },
        &.{ 1, 2, 5 },
        &.{ 2, 3 },
        &.{ 0, 1, 4 },
    };

    for (0..row_count) |row| {
        const y = start_y + @as(f32, @floatFromInt(row)) * (row_h + row_gap);
        try builder.addRoundedRect(rect(row_x, y, row_w, row_h), fill(.{ 0.985, 0.99, 1.0, 1.0 }), stroke(border, 0.75), 3, .identity);
        try builder.addFilledRect(rect(row_x + 6, y + 4, 10, row_h - 8), fill(withAlpha(muted, 0.32)), .identity);
        var x = row_x + 22;
        for (records[row]) |curve_index| {
            const chip_w: f32 = if (compact) 14 else 12;
            try builder.addRoundedRect(rect(x, y + 4, chip_w, row_h - 8), fill(withAlpha(curveColor(curve_index), 0.78)), null, 2, .identity);
            x += chip_w + 5;
        }
    }
}

fn addCandidateList(builder: *snail.PathPictureBuilder, area: snail.Rect) !void {
    try addBandLists(builder, area, true);
}

fn addLocalGlyphGrid(builder: *snail.PathPictureBuilder, area: snail.Rect, show_sample: bool) !void {
    try builder.addRoundedRect(area, fill(.{ 0.985, 0.99, 1.0, 1.0 }), stroke(border, 0.8), 3, .identity);
    try addGridLines(builder, area, 4, 4);
    try addGlyphFill(builder, innerRect(area, 4, 2), 0.38);
    try addGlyphCurves(builder, innerRect(area, 4, 2), false);
    if (show_sample) try addSampleMarker(builder, innerRect(area, 4, 2), sample_unit, 12);
}

fn addHorizontalEllipseRoots(builder: *snail.PathPictureBuilder, area: snail.Rect, cx: f32, cy: f32, rx: f32, ry: f32, y: f32) !void {
    const n = (y - cy) / ry;
    if (@abs(n) > 1.0) return;
    const dx = rx * @sqrt(@max(0.0, 1.0 - n * n));
    try dot(builder, rel(area, cx - dx, y), 2.4, rose);
    try dot(builder, rel(area, cx + dx, y), 2.4, rose);
}

fn addVerticalEllipseRoots(builder: *snail.PathPictureBuilder, area: snail.Rect, cx: f32, cy: f32, rx: f32, ry: f32, x: f32) !void {
    const n = (x - cx) / rx;
    if (@abs(n) > 1.0) return;
    const dy = ry * @sqrt(@max(0.0, 1.0 - n * n));
    try dot(builder, rel(area, x, cy - dy), 2.4, teal);
    try dot(builder, rel(area, x, cy + dy), 2.4, teal);
}

fn addSampleRoots(builder: *snail.PathPictureBuilder, area: snail.Rect, unit: UnitPoint) !void {
    try addHorizontalEllipseRoots(builder, area, 0.50, 0.52, 0.34, 0.39, unit.y);
    try addHorizontalEllipseRoots(builder, area, 0.50, 0.52, 0.13, 0.17, unit.y);
    try addVerticalEllipseRoots(builder, area, 0.50, 0.52, 0.34, 0.39, unit.x);
    try addVerticalEllipseRoots(builder, area, 0.50, 0.52, 0.13, 0.17, unit.x);
}

fn addRayRootPlot(builder: *snail.PathPictureBuilder, plot: snail.Rect) !snail.Rect {
    try addLocalGlyphGrid(builder, plot, false);
    const glyph_area = innerRect(plot, 4, 2);
    try line(builder, rel(glyph_area, 0.07, sample_unit.y), rel(glyph_area, 0.95, sample_unit.y), rose, 1.3);
    try line(builder, rel(glyph_area, sample_unit.x, 0.08), rel(glyph_area, sample_unit.x, 0.94), teal, 1.3);
    try addSampleRoots(builder, glyph_area, sample_unit);
    try addSampleMarker(builder, glyph_area, sample_unit, 12);
    return glyph_area;
}

fn addRootList(builder: *snail.PathPictureBuilder, area: snail.Rect) !void {
    const rows = [_]struct { y: f32, color: [4]f32, count: usize }{
        .{ .y = area.y + 43, .color = rose, .count = 4 },
        .{ .y = area.y + 88, .color = teal, .count = 2 },
    };
    for (rows) |row| {
        const rail = rect(area.x + 20, row.y, area.w - 40, 8);
        try builder.addRoundedRect(rail, fill(.{ 0.90, 0.92, 0.95, 1.0 }), null, 3, .identity);
        for (0..row.count) |i| {
            const denom = @as(f32, @floatFromInt(row.count + 1));
            const x = rail.x + rail.w * (@as(f32, @floatFromInt(i + 1)) / denom);
            try dot(builder, point(x, rail.y + rail.h * 0.5), 3.0, row.color);
        }
    }
}

fn addWindingPlot(builder: *snail.PathPictureBuilder, plot: snail.Rect) !void {
    try addLocalGlyphGrid(builder, plot, false);
    const glyph_area = innerRect(plot, 4, 2);
    const filled_sample = sample_unit;
    const hole_sample = UnitPoint{ .x = 0.50, .y = 0.52 };

    try line(builder, unitRel(glyph_area, filled_sample), rel(glyph_area, 0.95, filled_sample.y), rose, 1.4);
    try line(builder, unitRel(glyph_area, hole_sample), rel(glyph_area, 0.95, hole_sample.y), muted, 1.2);
    try addSampleMarker(builder, glyph_area, filled_sample, 11);
    try dot(builder, unitRel(glyph_area, hole_sample), 3.2, ink);

    try dot(builder, rel(glyph_area, 0.814, filled_sample.y), 2.8, rose);
    try dot(builder, rel(glyph_area, 0.63, hole_sample.y), 2.8, teal);
    try dot(builder, rel(glyph_area, 0.84, hole_sample.y), 2.8, rose);
}

fn addFillRuleRows(builder: *snail.PathPictureBuilder, panel: snail.Rect) !void {
    const rows = [_]struct { y: f32, color: [4]f32, fill_w: f32 }{
        .{ .y = panel.y + 34, .color = blue, .fill_w = 1.0 },
        .{ .y = panel.y + 62, .color = muted, .fill_w = 0.0 },
        .{ .y = panel.y + 90, .color = blue, .fill_w = 0.58 },
    };
    for (rows) |row| {
        const box = rect(panel.x + 20, row.y, 18, 18);
        try builder.addRoundedRect(box, fill(.{ 0.90, 0.92, 0.95, 1.0 }), stroke(border, 0.8), 3, .identity);
        if (row.fill_w > 0.0) {
            try builder.addRoundedRect(rect(box.x + 2, box.y + 2, (box.w - 4) * row.fill_w, box.h - 4), fill(withAlpha(row.color, if (row.fill_w < 1.0) 0.58 else 0.80)), null, 2, .identity);
        }
    }
}

fn buildPrepCurvesPaths(builder: *snail.PathPictureBuilder) !void {
    const outline_panel = rect(14, 42, 128, 124);
    const atlas_panel = rect(178, 42, 128, 124);
    try card(builder, outline_panel);
    try card(builder, atlas_panel);
    try addOutlineGlyph(builder, innerRect(outline_panel, 18, 26));
    try addCurveAtlas(builder, innerRect(atlas_panel, 18, 26));
    try arrow(builder, point(outline_panel.x + outline_panel.w + 10, outline_panel.y + outline_panel.h * 0.52), point(atlas_panel.x - 10, atlas_panel.y + atlas_panel.h * 0.52), muted);
}

fn buildPrepBandsPaths(builder: *snail.PathPictureBuilder) !void {
    const bands_panel = rect(14, 42, 146, 124);
    const ids_panel = rect(188, 42, 118, 124);
    try card(builder, bands_panel);
    try card(builder, ids_panel);
    try addBandGrid(builder, bands_panel, false);
    try addBandLists(builder, ids_panel, false);
    try arrow(builder, point(bands_panel.x + bands_panel.w + 8, bands_panel.y + bands_panel.h * 0.52), point(ids_panel.x - 8, ids_panel.y + ids_panel.h * 0.52), muted);
}

fn buildDrawQuadPaths(builder: *snail.PathPictureBuilder) !void {
    const quad_panel = rect(16, 42, 136, 124);
    const local_panel = rect(190, 42, 112, 124);
    try card(builder, quad_panel);
    try card(builder, local_panel);

    const screen_quad = rect(36, 72, 96, 74);
    try builder.addRoundedRect(screen_quad, fill(.{ 0.91, 0.95, 1.0, 0.82 }), stroke(blue, 1.5), 3, .identity);
    try addGlyphFill(builder, innerRect(screen_quad, 6, 3), 0.42);
    try addGlyphCurves(builder, innerRect(screen_quad, 6, 3), false);
    try addSampleMarker(builder, innerRect(screen_quad, 6, 3), sample_unit, 12);
    try dot(builder, point(screen_quad.x, screen_quad.y), 2.0, blue);
    try dot(builder, point(screen_quad.x + screen_quad.w, screen_quad.y), 2.0, blue);
    try dot(builder, point(screen_quad.x + screen_quad.w, screen_quad.y + screen_quad.h), 2.0, blue);
    try dot(builder, point(screen_quad.x, screen_quad.y + screen_quad.h), 2.0, blue);
    try arrow(builder, point(152, 112), point(190, 112), muted);

    try addLocalGlyphGrid(builder, rect(212, 72, 68, 68), true);
}

fn buildSampleBandsPaths(builder: *snail.PathPictureBuilder) !void {
    const sample_panel = rect(14, 42, 146, 124);
    const candidates_panel = rect(188, 42, 118, 124);
    try card(builder, sample_panel);
    try card(builder, candidates_panel);
    try addBandGrid(builder, sample_panel, true);
    try addCandidateList(builder, candidates_panel);
    try arrow(builder, point(sample_panel.x + sample_panel.w + 8, sample_panel.y + sample_panel.h * 0.52), point(candidates_panel.x - 8, candidates_panel.y + candidates_panel.h * 0.52), muted);
}

fn buildSolveRootsPaths(builder: *snail.PathPictureBuilder) !void {
    const roots_panel = rect(14, 42, 184, 124);
    const list_panel = rect(224, 42, 82, 124);
    try card(builder, roots_panel);
    try card(builder, list_panel);

    const plot = rect(48, 72, 118, 72);
    _ = try addRayRootPlot(builder, plot);
    try arrow(builder, point(roots_panel.x + roots_panel.w + 5, roots_panel.y + roots_panel.h * 0.52), point(list_panel.x - 7, list_panel.y + list_panel.h * 0.52), muted);
    try addRootList(builder, list_panel);
}

fn buildWindingPaths(builder: *snail.PathPictureBuilder) !void {
    const roots_panel = rect(14, 42, 174, 124);
    const winding_panel = rect(202, 42, 104, 124);
    try card(builder, roots_panel);
    try card(builder, winding_panel);

    try addWindingPlot(builder, rect(45, 72, 108, 72));
    try builder.addRoundedRect(rect(137, 79, 24, 16), fill(rose_soft), stroke(border, 0.7), 4, .identity);
    try builder.addRoundedRect(rect(105, 111, 24, 16), fill(teal_soft), stroke(border, 0.7), 4, .identity);
    try builder.addRoundedRect(rect(139, 111, 24, 16), fill(rose_soft), stroke(border, 0.7), 4, .identity);
    try arrow(builder, point(roots_panel.x + roots_panel.w + 6, roots_panel.y + roots_panel.h * 0.52), point(winding_panel.x - 7, winding_panel.y + winding_panel.h * 0.52), muted);
    try builder.addRoundedRect(rect(winding_panel.x + 52, winding_panel.y + 36, 42, 22), fill(blue_soft), stroke(border, 0.8), 4, .identity);
    try builder.addRoundedRect(rect(winding_panel.x + 52, winding_panel.y + 70, 42, 22), fill(.{ 0.90, 0.92, 0.95, 1.0 }), stroke(border, 0.8), 4, .identity);
}

fn buildFillAlphaPaths(builder: *snail.PathPictureBuilder) !void {
    const rule_panel = rect(14, 42, 154, 124);
    const alpha_panel = rect(202, 42, 104, 124);
    try card(builder, rule_panel);
    try card(builder, alpha_panel);

    try addFillRuleRows(builder, rule_panel);
    try arrow(builder, point(rule_panel.x + rule_panel.w + 7, rule_panel.y + rule_panel.h * 0.52), point(alpha_panel.x - 8, alpha_panel.y + alpha_panel.h * 0.52), muted);

    const pixel = rect(alpha_panel.x + 24, alpha_panel.y + 52, 34, 34);
    try builder.addRoundedRect(rect(pixel.x - 6, pixel.y - 6, pixel.w + 12, pixel.h + 12), fill(.{ 0.985, 0.99, 1.0, 1.0 }), stroke(border, 0.8), 4, .identity);
    try builder.addRoundedRect(pixel, fill(withAlpha(blue, 0.58)), stroke(blue, 1.2), 3, .identity);
    const bar = rect(alpha_panel.x + 22, alpha_panel.y + 112, 38, 8);
    try builder.addRoundedRect(bar, fill(.{ 0.90, 0.92, 0.95, 1.0 }), null, 3, .identity);
    try builder.addRoundedRect(rect(bar.x, bar.y, bar.w * 0.58, bar.h), fill(blue), null, 3, .identity);
    try builder.addRoundedRect(bar, null, stroke(border, 0.7), 3, .identity);
}

const std = @import("std");

const build_options = @import("build_options");
const snail = @import("root.zig");
const bezier = @import("math/bezier.zig");
const resource_key = @import("resource_key.zig");
const vertex_mod = @import("renderer/vertex.zig");

const Mat4 = snail.Mat4;
const Vec2 = snail.Vec2;
const Path = snail.Path;
const PathPicture = snail.PathPicture;
const PathPictureBuilder = snail.PathPictureBuilder;
const TextAtlas = snail.TextAtlas;
const TextBlob = snail.TextBlob;
const TextBlobBuilder = snail.TextBlobBuilder;
const TextAppendResult = snail.TextAppendResult;
const FontStyle = snail.FontStyle;
const Paint = snail.Paint;
const Image = snail.Image;
const ResourceKey = snail.ResourceKey;
const ResourceStamp = snail.ResourceStamp;
const ResourceSet = snail.ResourceSet;
const PreparedResources = snail.PreparedResources;
const PreparedResourceRetirementQueue = snail.PreparedResourceRetirementQueue;
const PendingResourceUpload = snail.PendingResourceUpload;
const Renderer = snail.Renderer;
const CpuRenderer = snail.CpuRenderer;
const DrawSegment = snail.DrawSegment;
const DrawRecords = snail.DrawRecords;
const DrawOptions = snail.DrawOptions;
const DrawList = snail.DrawList;
const Scene = snail.Scene;
const CoverageTransfer = snail.CoverageTransfer;
const PixelGrid = snail.PixelGrid;
const SubpixelOrder = snail.SubpixelOrder;
const FillRule = snail.FillRule;
const TargetEncoding = snail.TargetEncoding;
const Resolve = snail.Resolve;
const TargetStamp = snail.TargetStamp;
const TextCoverageRecords = snail.coverage.TextCoverageRecords;
const TEXT_WORDS_PER_GLYPH = snail.lowlevel.TEXT_WORDS_PER_GLYPH;
const pointerResourceKey = resource_key.pointerResourceKey;

test {
    _ = @import("math/vec.zig");
    _ = @import("math/bezier.zig");
    _ = @import("math/roots.zig");
    _ = @import("font/ttf.zig");
    _ = @import("renderer/curve_texture.zig");
    _ = @import("renderer/band_texture.zig");
    _ = @import("font/opentype.zig");
    _ = @import("renderer/vertex.zig");
    if (build_options.enable_cpu) _ = @import("renderer/cpu.zig");
    _ = @import("torture_test.zig");
    _ = @import("fonts.zig");
}

test "vector path approximates cubic commands into quadratic segments and reports bounds" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();

    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.cubicTo(.{ .x = 8, .y = 20 }, .{ .x = 16, .y = -20 }, .{ .x = 24, .y = 0 });

    try std.testing.expect(path.curves.items.len > 0);
    const last = path.curves.items[path.curves.items.len - 1];
    try std.testing.expectEqual(bezier.CurveKind.quadratic, last.kind);
    try std.testing.expectApproxEqAbs(@as(f32, 24), last.p2.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), last.p2.y, 0.001);

    const bounds = path.bounds() orelse return error.TestExpectedEqual;
    try std.testing.expect(bounds.max.y > 0);
    try std.testing.expect(bounds.min.y < 0);
}

fn testRectPicture(allocator: std.mem.Allocator, x: f32) !PathPicture {
    var path = Path.init(allocator);
    defer path.deinit();
    try path.addRect(.{ .x = x, .y = 0, .w = 20, .h = 10 });

    var builder = PathPictureBuilder.init(allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .paint = .{ .solid = .{ 0.2, 0.4, 0.8, 1.0 } } }, .identity);
    return builder.freeze(.{ .persistent_allocator = allocator, .scratch_allocator = allocator });
}

test "draw with missing prepared resources fails" {
    if (comptime !build_options.enable_cpu) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const width: u32 = 4;
    const height: u32 = 4;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = cpu.asRenderer();
    defer renderer.deinit();

    var prepared = PreparedResources{ .allocator = allocator };
    var words: [TEXT_WORDS_PER_GLYPH]u32 = undefined;
    const segments = [_]DrawSegment{.{
        .kind = .text,
        .offset = 0,
        .len = TEXT_WORDS_PER_GLYPH,
        .key = ResourceKey.named("missing"),
        .resource_stamp = .{},
        .target_stamp = .{},
    }};
    const records = DrawRecords{ .words = &words, .segments = &segments };
    try std.testing.expectError(error.MissingPreparedResource, renderer.draw(&prepared, records, .{
        .mvp = Mat4.identity,
        .target = .{ .pixel_width = width, .pixel_height = height, .encoding = .srgb },
    }));
}

test "draw dispatch uses only prepared stamps and caller records" {
    const FakeState = struct {
        begin_count: u32 = 0,
        text_count: u32 = 0,
        path_count: u32 = 0,
        words_seen: usize = 0,
        viewport_seen: [2]f32 = .{ 0, 0 },
        subpixel_order: SubpixelOrder = .none,
        fill_rule: FillRule = .non_zero,
        target_encoding: TargetEncoding = .linear,
        resolve: Resolve = .{ .direct = .{} },
        coverage_transfer: CoverageTransfer = .identity,
        saw_backend_prepared: bool = true,
    };
    const Fake = struct {
        fn state(ptr: *anyopaque) *FakeState {
            return @ptrCast(@alignCast(ptr));
        }
        fn deinit(_: *anyopaque) void {}
        fn draw(renderer: *Renderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) anyerror!void {
            try renderer.validateRecords(prepared, records, options);
            renderer.iterateRecords(records, options, null);
        }
        fn drawText(ptr: *anyopaque, backend_prepared: ?*const anyopaque, vertices: []const u32, _: Mat4, viewport_w: f32, viewport_h: f32, _: u32) void {
            const s = state(ptr);
            s.text_count += 1;
            s.words_seen += vertices.len;
            s.viewport_seen = .{ viewport_w, viewport_h };
            s.saw_backend_prepared = backend_prepared != null;
        }
        fn drawPaths(ptr: *anyopaque, backend_prepared: ?*const anyopaque, vertices: []const u32, _: Mat4, viewport_w: f32, viewport_h: f32, _: u32) void {
            const s = state(ptr);
            s.path_count += 1;
            s.words_seen += vertices.len;
            s.viewport_seen = .{ viewport_w, viewport_h };
            s.saw_backend_prepared = backend_prepared != null;
        }
        fn beginFrame(ptr: *anyopaque) void {
            state(ptr).begin_count += 1;
        }
        fn setSubpixelOrder(ptr: *anyopaque, order: SubpixelOrder) void {
            state(ptr).subpixel_order = order;
        }
        fn getSubpixelOrder(ptr: *anyopaque) SubpixelOrder {
            return state(ptr).subpixel_order;
        }
        fn setFillRule(ptr: *anyopaque, rule: FillRule) void {
            state(ptr).fill_rule = rule;
        }
        fn getFillRule(ptr: *anyopaque) FillRule {
            return state(ptr).fill_rule;
        }
        fn setTargetEncoding(ptr: *anyopaque, encoding: TargetEncoding) void {
            state(ptr).target_encoding = encoding;
        }
        fn getTargetEncoding(ptr: *anyopaque) TargetEncoding {
            return state(ptr).target_encoding;
        }
        fn setResolve(ptr: *anyopaque, resolve: Resolve) void {
            state(ptr).resolve = resolve;
        }
        fn getResolve(ptr: *anyopaque) Resolve {
            return state(ptr).resolve;
        }
        fn setCoverageTransfer(ptr: *anyopaque, transfer: CoverageTransfer) void {
            state(ptr).coverage_transfer = transfer;
        }
        fn getCoverageTransfer(ptr: *anyopaque) CoverageTransfer {
            return state(ptr).coverage_transfer;
        }
        fn backendName(_: *anyopaque) []const u8 {
            return "fake";
        }
    };
    const fake_vtable = Renderer.VTable{
        .backend = .cpu,
        .deinit = Fake.deinit,
        .draw = Fake.draw,
        .drawText = Fake.drawText,
        .drawPaths = Fake.drawPaths,
        .beginFrame = Fake.beginFrame,
        .setSubpixelOrder = Fake.setSubpixelOrder,
        .getSubpixelOrder = Fake.getSubpixelOrder,
        .setFillRule = Fake.setFillRule,
        .getFillRule = Fake.getFillRule,
        .setTargetEncoding = Fake.setTargetEncoding,
        .getTargetEncoding = Fake.getTargetEncoding,
        .setResolve = Fake.setResolve,
        .getResolve = Fake.getResolve,
        .setCoverageTransfer = Fake.setCoverageTransfer,
        .getCoverageTransfer = Fake.getCoverageTransfer,
        .backendName = Fake.backendName,
    };

    const key = ResourceKey.named("shape");
    const stamp = ResourceStamp{ .identity = 1, .layout = 2, .content = 3 };
    var image: Image = .{ .allocator = std.testing.allocator, .width = 1, .height = 1, .pixels = &.{ 255, 255, 255, 255 } };
    var image_resources = [_]PreparedResources.PreparedImageResource{.{
        .key = key,
        .image = &image,
        .stamp = stamp,
    }};
    var prepared = PreparedResources{
        .allocator = std.testing.allocator,
        .images = image_resources[0..],
    };

    const options = DrawOptions{
        .mvp = Mat4.identity,
        .target = .{
            .pixel_width = 8,
            .pixel_height = 8,
            .subpixel_order = .rgb,
            .fill_rule = .even_odd,
            .encoding = .srgb,
            .coverage_transfer = .{ .exponent = 0.875 },
        },
    };
    var words = [_]u32{ 1, 2, 3, 4 };
    const segments = [_]DrawSegment{.{
        .kind = .text,
        .offset = 0,
        .len = words.len,
        .key = key,
        .resource_stamp = stamp,
        .target_stamp = TargetStamp.from(options.mvp, options.target),
    }};
    const records = DrawRecords{ .words = &words, .segments = &segments };

    var state: FakeState = .{};
    var renderer = Renderer{ .ptr = @ptrCast(&state), .vtable = &fake_vtable };
    try renderer.draw(&prepared, records, options);

    try std.testing.expectEqual(@as(u32, 1), state.begin_count);
    try std.testing.expectEqual(@as(u32, 1), state.text_count);
    try std.testing.expectEqual(@as(u32, 0), state.path_count);
    try std.testing.expectEqual(words.len, state.words_seen);
    try std.testing.expectEqual(SubpixelOrder.rgb, state.subpixel_order);
    try std.testing.expectEqual(FillRule.even_odd, state.fill_rule);
    try std.testing.expectEqual(TargetEncoding.srgb, state.target_encoding);
    try std.testing.expect(std.meta.eql(Resolve{ .direct = .{} }, state.resolve));
    try std.testing.expectEqual(@as(f32, 0.875), state.coverage_transfer.exponent);
    try std.testing.expectEqual(@as(f32, 8), state.viewport_seen[0]);
    try std.testing.expectEqual(@as(f32, 8), state.viewport_seen[1]);
    try std.testing.expect(!state.saw_backend_prepared);
}

test "coverage transfer is explicit and clamps invalid exponents" {
    try std.testing.expectEqual(@as(f32, 1.0), CoverageTransfer.identity.shaderExponent());
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), CoverageTransfer.identity.apply(0.25), 0.0001);
    try std.testing.expect(CoverageTransfer.power(0.5).apply(0.25) > 0.25);
    try std.testing.expect(CoverageTransfer.power(2.0).apply(0.25) < 0.25);
    try std.testing.expectEqual(@as(f32, 1.0), CoverageTransfer.power(std.math.nan(f32)).shaderExponent());
}

test "pixel grid snaps logical coordinates to backing pixels" {
    const grid = PixelGrid.init(.{ 100.0, 50.0 }, .{ 200, 150 });
    try std.testing.expectApproxEqAbs(@as(f32, 10.5), grid.snapX(10.4), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 10.333333), grid.snapY(10.4), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 12.5), grid.snapLengthX(12.4), 0.0001);
}

test "Renderer.draw source stays free of upload allocation" {
    const source = @embedFile("render.zig");
    const start = std.mem.indexOf(u8, source, "pub fn draw(self: *Renderer").?;
    const end = start + std.mem.indexOf(u8, source[start..], "pub fn drawPrepared").?;
    const draw_source = source[start..end];
    try std.testing.expect(std.mem.indexOf(u8, draw_source, "uploadResources") == null);
    try std.testing.expect(std.mem.indexOf(u8, draw_source, ".alloc(") == null);
}

test "Vulkan renderer path contains no device or queue idle" {
    const source = @embedFile("renderer/vulkan.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, "vkDeviceWaitIdle") == null);
    try std.testing.expect(std.mem.indexOf(u8, source, "vkQueueWaitIdle") == null);
}

test "Vulkan scheduled upload path records without internal submit" {
    const source = @embedFile("renderer/vulkan.zig");
    const start = std.mem.indexOf(u8, source, "fn finishTransferCommand").?;
    const end = start + std.mem.indexOf(u8, source[start..], "fn submitTransferAndWait").?;
    const scheduled_finish = source[start..end];
    try std.testing.expect(std.mem.indexOf(u8, source, "beginResourceUploadRecording") != null);
    try std.testing.expect(std.mem.indexOf(u8, scheduled_finish, "if (!transfer.owned) return;") != null);
    try std.testing.expect(std.mem.indexOf(u8, scheduled_finish, "vkQueueSubmit") == null);
    try std.testing.expect(std.mem.indexOf(u8, scheduled_finish, "vkWaitForFences") == null);
}

fn appendRootTestText(
    builder: *TextBlobBuilder,
    style: FontStyle,
    text: []const u8,
    baseline: Vec2,
    em: f32,
    color: [4]f32,
) !TextAppendResult {
    return appendRootTestTextPaint(builder, style, text, baseline, em, .{ .solid = color });
}

fn appendRootTestTextPaint(
    builder: *TextBlobBuilder,
    style: FontStyle,
    text: []const u8,
    baseline: Vec2,
    em: f32,
    paint: Paint,
) !TextAppendResult {
    var shaped = try builder.atlas.shapeText(builder.allocator, style, text);
    defer shaped.deinit();
    return builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = baseline, .em = em },
        .fill = paint,
    });
}

test "TextBlob validation catches wrong atlas snapshot" {
    const assets_data = @import("assets");
    var atlas = try TextAtlas.init(std.testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer atlas.deinit();

    if (try atlas.ensureText(.{}, "A")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var builder = TextBlobBuilder.init(std.testing.allocator, &atlas);
    defer builder.deinit();
    _ = try appendRootTestText(&builder, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ 1, 1, 1, 1 });
    var blob = try builder.finish();
    defer blob.deinit();
    try blob.validate();

    if (try atlas.ensureText(.{}, "B")) |next| {
        atlas.deinit();
        atlas = next;
    }
    try std.testing.expectError(error.WrongTextAtlasSnapshot, blob.validate());
}

test "ResourceSet discovers and draws text paint resources" {
    if (comptime !build_options.enable_cpu) return error.SkipZigTest;

    const assets_data = @import("assets");
    const allocator = std.testing.allocator;

    var atlas = try TextAtlas.init(allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer atlas.deinit();

    if (try atlas.ensureText(.{}, "A")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var builder = TextBlobBuilder.init(allocator, &atlas);
    defer builder.deinit();
    _ = try appendRootTestTextPaint(&builder, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ .linear_gradient = .{
        .start = .{ .x = 0, .y = 0 },
        .end = .{ .x = 20, .y = 0 },
        .start_color = .{ 1, 0, 0, 1 },
        .end_color = .{ 0, 0, 1, 1 },
    } });
    var blob = try builder.finish();
    defer blob.deinit();
    try std.testing.expect(blob.hasPaintRecords());

    var scene = Scene.init(allocator);
    defer scene.deinit();
    try scene.addText(.{ .blob = &blob });

    var set_entries: [2]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(&set_entries);
    try set.addScene(&scene);
    try std.testing.expectEqual(@as(usize, 2), set.slice().len);
    try std.testing.expect(std.meta.activeTag(set.slice()[0]) == .text_atlas);
    try std.testing.expect(std.meta.activeTag(set.slice()[1]) == .text_paint);

    const footprint = try set.estimateUploadFootprint();
    try std.testing.expectEqual(blob.paint_layer_info_data.?.len * @sizeOf(f32), footprint.layer_info_bytes_used);

    const width: u32 = 32;
    const height: u32 = 32;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);
    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = cpu.asRenderer();
    defer renderer.deinit();

    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set);
    defer prepared.deinit();
    try std.testing.expectEqual(@as(usize, 1), prepared.atlases.len);
    try std.testing.expectEqual(@as(usize, 1), prepared.layer_infos.len);

    const options = DrawOptions{
        .mvp = Mat4.identity,
        .target = .{ .pixel_width = width, .pixel_height = height, .encoding = .srgb },
    };
    const words = try allocator.alloc(u32, DrawList.estimate(&scene, options));
    defer allocator.free(words);
    const segments = try allocator.alloc(DrawSegment, DrawList.estimateSegments(&scene, options));
    defer allocator.free(segments);
    var draw = DrawList.init(words, segments);
    try draw.addScene(&prepared, &scene, options);

    try std.testing.expectEqual(@as(usize, 1), draw.slice().segments.len);
    try std.testing.expect(draw.slice().segments[0].key.eql(pointerResourceKey("scene.text_paint", &blob)));
    const decoded = vertex_mod.decodeInstance(draw.slice().words);
    try std.testing.expectEqual(@as(u32, 0xFF), decoded.glyph[1] >> 24);
    try std.testing.expectEqual(@as(u32, @intFromEnum(vertex_mod.SpecialGlyphKind.path)), (decoded.glyph[1] >> 16) & 0xFF);
}

test "ResourceSet footprint counts text image paint payloads" {
    const assets_data = @import("assets");
    const allocator = std.testing.allocator;
    var image = try Image.initSrgba8(allocator, 1, 1, &.{ 255, 64, 32, 255 });
    defer image.deinit();

    var atlas = try TextAtlas.init(allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer atlas.deinit();

    if (try atlas.ensureText(.{}, "A")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var builder = TextBlobBuilder.init(allocator, &atlas);
    defer builder.deinit();
    _ = try appendRootTestTextPaint(&builder, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ .image = .{ .image = &image } });
    var blob = try builder.finish();
    defer blob.deinit();

    var scene = Scene.init(allocator);
    defer scene.deinit();
    try scene.addText(.{ .blob = &blob });

    var set_entries: [2]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(&set_entries);
    try set.addScene(&scene);
    const footprint = try set.estimateUploadFootprint();
    try std.testing.expectEqual(image.pixelSlice().len, footprint.image_bytes_used);
    try std.testing.expect(footprint.image_bytes_allocated >= footprint.image_bytes_used);
}

test "ResourceSet footprint image accounting has no fixed slot cap" {
    const allocator = std.testing.allocator;
    const image_count = 300;

    var images: [image_count]Image = undefined;
    var initialized: usize = 0;
    defer {
        for (images[0..initialized]) |*image| image.deinit();
    }

    var entries: [image_count]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(entries[0..]);
    for (0..image_count) |i| {
        const px = [_]u8{ @intCast(i % 251), 64, 32, 255 };
        images[i] = try Image.initSrgba8(allocator, 1, 1, px[0..]);
        initialized += 1;
        try set.putImage(ResourceKey.fromId(@intCast(i + 1)), &images[i]);
    }

    const footprint = try set.estimateUploadFootprint();
    try std.testing.expectEqual(@as(usize, image_count * 4), footprint.image_bytes_used);
    try std.testing.expectEqual(@as(usize, image_count * 4), footprint.image_bytes_allocated);
}

test "DrawList estimate upper-bounds ranged text draw output" {
    if (comptime !build_options.enable_cpu) return error.SkipZigTest;

    const assets_data = @import("assets");
    const allocator = std.testing.allocator;

    var atlas = try TextAtlas.init(allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer atlas.deinit();

    if (try atlas.ensureText(.{}, "A")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var sample_builder = TextBlobBuilder.init(allocator, &atlas);
    defer sample_builder.deinit();
    _ = try appendRootTestText(&sample_builder, .{}, "A", .{ .x = 0, .y = 20 }, 16, .{ 1, 1, 1, 1 });
    var sample_blob = try sample_builder.finish();
    defer sample_blob.deinit();
    try std.testing.expectEqual(@as(usize, 1), sample_blob.glyphCount());
    const sample_glyph = sample_blob.glyphs[0];
    try std.testing.expect(sample_glyph.glyph_id != 0);

    const glyph_count: usize = 64;
    const selected_glyph_index: usize = 47;
    const glyphs = try allocator.alloc(TextBlob.Glyph, glyph_count);
    const empty_glyph = TextBlob.Glyph{
        .face_index = sample_glyph.face_index,
        .glyph_id = 0,
        .transform = sample_glyph.transform,
        .embolden = 0,
        .color = sample_glyph.color,
    };
    for (glyphs) |*glyph| glyph.* = empty_glyph;
    glyphs[selected_glyph_index] = sample_glyph;
    glyphs[selected_glyph_index].embolden = 1.0;

    var blob = TextBlob{
        .allocator = allocator,
        .atlas = &atlas,
        .atlas_identity = atlas.snapshotIdentity(),
        .glyphs = glyphs,
        .gpu_instance_budget = 2,
    };
    defer blob.deinit();

    var scene = Scene.init(allocator);
    defer scene.deinit();
    try scene.addText(.{
        .blob = &blob,
        .glyphs = .{ .start = selected_glyph_index, .count = 1 },
    });

    const width: u32 = 16;
    const height: u32 = 16;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);
    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = cpu.asRenderer();
    defer renderer.deinit();

    var set_entries: [1]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(&set_entries);
    try set.addScene(&scene);
    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set);
    defer prepared.deinit();

    const options = DrawOptions{
        .mvp = Mat4.identity,
        .target = .{ .pixel_width = width, .pixel_height = height, .encoding = .srgb },
    };
    const needed = DrawList.estimate(&scene, options);
    const needed_segments = DrawList.estimateSegments(&scene, options);
    try std.testing.expectEqual(@as(usize, 2 * TEXT_WORDS_PER_GLYPH), needed);
    try std.testing.expectEqual(@as(usize, 1), needed_segments);

    const draw_buf = try allocator.alloc(u32, needed);
    defer allocator.free(draw_buf);
    const draw_segments = try allocator.alloc(DrawSegment, needed_segments);
    defer allocator.free(draw_segments);
    var draw = DrawList.init(draw_buf, draw_segments);
    try draw.addScene(&prepared, &scene, options);
    try std.testing.expectEqual(needed, draw.slice().words.len);
    try std.testing.expectEqual(@as(usize, 1), draw.slice().segments.len);
}

test "replacing path-picture key does not invalidate unrelated text coverage records" {
    if (comptime !build_options.enable_cpu) return error.SkipZigTest;

    const assets_data = @import("assets");
    const allocator = std.testing.allocator;

    var atlas = try TextAtlas.init(allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, "Hello")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var builder = TextBlobBuilder.init(allocator, &atlas);
    defer builder.deinit();
    _ = try appendRootTestText(&builder, .{}, "Hello", .{ .x = 0, .y = 24 }, 18, .{ 1, 1, 1, 1 });
    var blob = try builder.finish();
    defer blob.deinit();

    var picture_a = try testRectPicture(allocator, 0);
    defer picture_a.deinit();
    var picture_b = try testRectPicture(allocator, 40);
    defer picture_b.deinit();

    const width: u32 = 16;
    const height: u32 = 16;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);
    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = cpu.asRenderer();
    defer renderer.deinit();

    var set_a_entries: [4]ResourceSet.Entry = undefined;
    var set_a = ResourceSet.init(&set_a_entries);
    try set_a.putTextAtlas(.fonts, &atlas);
    try set_a.putPathPicture(.hud_panel, &picture_a);
    var prepared_a = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set_a);
    defer prepared_a.deinit();

    const coverage_words = try allocator.alloc(u32, TextCoverageRecords.wordCapacityForBlob(&blob));
    defer allocator.free(coverage_words);
    var records = TextCoverageRecords.init(coverage_words);
    try records.buildLocal(&prepared_a, &blob, .{});
    try std.testing.expect(records.validFor(&prepared_a));

    var set_b_entries: [4]ResourceSet.Entry = undefined;
    var set_b = ResourceSet.init(&set_b_entries);
    try set_b.putTextAtlas(.fonts, &atlas);
    try set_b.putPathPicture(.hud_panel, &picture_b);
    var prepared_b = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set_b);
    defer prepared_b.deinit();

    try std.testing.expect(records.validFor(&prepared_b));
}

test "draw rejects stale records when a resource key is replaced" {
    if (comptime !build_options.enable_cpu) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var picture_a = try testRectPicture(allocator, 0);
    defer picture_a.deinit();
    var picture_b = try testRectPicture(allocator, 40);
    defer picture_b.deinit();

    const width: u32 = 32;
    const height: u32 = 32;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = cpu.asRenderer();
    defer renderer.deinit();

    var scene = Scene.init(allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture_a });

    var set_a_entries: [2]ResourceSet.Entry = undefined;
    var set_a = ResourceSet.init(&set_a_entries);
    try set_a.putPathPicture(.hud_panel, &picture_a);
    var prepared_a = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set_a);
    defer prepared_a.deinit();

    const draw_options = DrawOptions{
        .mvp = Mat4.identity,
        .target = .{ .pixel_width = width, .pixel_height = height, .encoding = .srgb },
    };
    const needed = DrawList.estimate(&scene, draw_options);
    const needed_segments = DrawList.estimateSegments(&scene, draw_options);
    const draw_buf = try allocator.alloc(u32, needed);
    defer allocator.free(draw_buf);
    const draw_segments = try allocator.alloc(DrawSegment, needed_segments);
    defer allocator.free(draw_segments);
    var draw = DrawList.init(draw_buf, draw_segments);
    try draw.addScene(&prepared_a, &scene, draw_options);

    var set_b_entries: [2]ResourceSet.Entry = undefined;
    var set_b = ResourceSet.init(&set_b_entries);
    try set_b.putPathPicture(.hud_panel, &picture_b);
    var prepared_b = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set_b);
    defer prepared_b.deinit();

    try std.testing.expectError(error.StaleDrawRecords, renderer.draw(&prepared_b, draw.slice(), draw_options));
}

test "resource upload plan reports changed keys and enforces budget" {
    if (comptime !build_options.enable_cpu) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var picture_a = try testRectPicture(allocator, 0);
    defer picture_a.deinit();
    var picture_b = try testRectPicture(allocator, 40);
    defer picture_b.deinit();

    const width: u32 = 16;
    const height: u32 = 16;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = cpu.asRenderer();
    defer renderer.deinit();

    var set_a_entries: [2]ResourceSet.Entry = undefined;
    var set_a = ResourceSet.init(&set_a_entries);
    try set_a.putPathPicture(.hud_panel, &picture_a);
    var prepared_a = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set_a);
    defer prepared_a.deinit();

    var changed_same: [2]ResourceKey = undefined;
    const plan_same = try renderer.planResourceUpload(&prepared_a, &set_a, &changed_same);
    try std.testing.expect(plan_same.upload_bytes > 0);
    try std.testing.expectEqual(plan_same.upload_footprint.allocatedBytes(), plan_same.upload_bytes);
    try std.testing.expect(plan_same.upload_footprint.curve_bytes_allocated > 0);
    try std.testing.expectEqual(@as(usize, 0), plan_same.changedKeys().len);
    try std.testing.expectEqual(@as(usize, 0), plan_same.changed_bytes);

    var set_b_entries: [2]ResourceSet.Entry = undefined;
    var set_b = ResourceSet.init(&set_b_entries);
    try set_b.putPathPicture(.hud_panel, &picture_b);
    var changed_b: [2]ResourceKey = undefined;
    const plan_b = try renderer.planResourceUpload(&prepared_a, &set_b, &changed_b);
    try std.testing.expect(plan_b.upload_bytes > 0);
    try std.testing.expectEqual(plan_b.upload_footprint.allocatedBytes(), plan_b.upload_bytes);
    try std.testing.expect(plan_b.upload_footprint.curve_bytes_allocated > 0);
    try std.testing.expect(plan_b.changed_bytes > 0);
    try std.testing.expectEqual(@as(usize, 1), plan_b.changedKeys().len);
    try std.testing.expect(plan_b.changedKeys()[0].eql(ResourceKey.named("hud_panel")));

    var pending = try renderer.beginResourceUpload(.{ .persistent = allocator, .scratch = allocator }, plan_b);
    defer pending.deinit();
    try std.testing.expectError(error.ResourceUploadBudgetExceeded, pending.record(.no_command, .{ .budget_bytes = 0 }));
    try std.testing.expect(!pending.ready(.pending));

    try pending.record(.no_command, .{ .budget_bytes = plan_b.upload_bytes });
    try std.testing.expect(pending.ready(.immediate));
    var prepared_b = try pending.publish();
    defer prepared_b.deinit();
    try std.testing.expect(prepared_b.stampForKey(.hud_panel) != null);
}

test "pending upload publish waits for external completion marker" {
    if (comptime !build_options.enable_cpu) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var picture = try testRectPicture(allocator, 0);
    defer picture.deinit();

    const width: u32 = 16;
    const height: u32 = 16;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = cpu.asRenderer();
    defer renderer.deinit();

    var set_entries: [2]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(&set_entries);
    try set.putPathPicture(.hud_panel, &picture);
    var changed_keys: [2]ResourceKey = undefined;
    const plan = try renderer.planResourceUpload(null, &set, &changed_keys);

    var pending = PendingResourceUpload{
        .renderer = renderer,
        .plan = plan,
        .allocators = .{ .persistent = allocator, .scratch = allocator },
        .prepared = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set),
        .external_completion_required = true,
    };
    defer pending.deinit();

    try std.testing.expect(!pending.ready(.pending));
    try std.testing.expectError(error.ResourceUploadNotReady, pending.publish());
    try std.testing.expect(pending.ready(.complete));
    var prepared = try pending.publish();
    defer prepared.deinit();
    try std.testing.expect(prepared.stampForKey(.hud_panel) != null);
}

test "pending upload stores renderer handle by value" {
    try std.testing.expectEqual(Renderer, @TypeOf(@as(PendingResourceUpload, undefined).renderer));
}

test "prepared resource retirement queue is caller-owned" {
    if (comptime !build_options.enable_cpu) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var picture = try testRectPicture(allocator, 0);
    defer picture.deinit();

    const width: u32 = 16;
    const height: u32 = 16;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = cpu.asRenderer();
    defer renderer.deinit();

    var set_entries: [2]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(&set_entries);
    try set.putPathPicture(.hud_panel, &picture);

    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set);
    var queue = PreparedResourceRetirementQueue.init(allocator);
    defer queue.deinit();
    try prepared.retireAfter(&queue, .{});
    queue.sweep();
}

test "CPU draw uses prepared resource views" {
    if (comptime !build_options.enable_cpu) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var picture = try testRectPicture(allocator, 0);
    defer picture.deinit();

    const width: u32 = 32;
    const height: u32 = 32;
    const stride: u32 = width * 4;
    const pixels = try allocator.alloc(u8, stride * height);
    defer allocator.free(pixels);
    @memset(pixels, 0);

    var cpu = CpuRenderer.init(pixels.ptr, width, height, stride);
    var renderer = cpu.asRenderer();
    defer renderer.deinit();

    var scene = Scene.init(allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture });

    var set_entries: [2]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(&set_entries);
    try set.putPathPicture(.panel, &picture);
    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set);
    defer prepared.deinit();

    const draw_options = DrawOptions{
        .mvp = Mat4.identity,
        .target = .{ .pixel_width = width, .pixel_height = height, .encoding = .srgb },
    };
    const needed = DrawList.estimate(&scene, draw_options);
    const needed_segments = DrawList.estimateSegments(&scene, draw_options);
    const draw_buf = try allocator.alloc(u32, needed);
    defer allocator.free(draw_buf);
    const draw_segments = try allocator.alloc(DrawSegment, needed_segments);
    defer allocator.free(draw_segments);
    var draw = DrawList.init(draw_buf, draw_segments);
    try draw.addScene(&prepared, &scene, draw_options);
    try renderer.draw(&prepared, draw.slice(), draw_options);

    var changed = false;
    for (pixels) |byte| {
        if (byte != 0) {
            changed = true;
            break;
        }
    }
    try std.testing.expect(changed);
}

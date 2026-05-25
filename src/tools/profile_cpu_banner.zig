//! Tight loop that renders the actual demo banner scene (snail vector
//! illustration, rounded-rect cards, decoration lines, multi-script text)
//! through the CPU backend. Designed for `perf record` / `perf stat`.
//! Not part of the public benchmark suite.

const std = @import("std");
const assets_data = @import("assets");
const snail = @import("snail");
const demo_banner = @import("banner");

const DEFAULT_WIDTH: u32 = 1880;
const DEFAULT_HEIGHT: u32 = 2472;
const DEFAULT_ITERS: usize = 100;
const DEFAULT_THREADED = true;

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usage() void {
    std.debug.print(
        "usage: snail-profile-cpu-banner [iters] [serial|threaded] [width] [height] [grayscale|subpixel]\n",
        .{},
    );
}

fn parseUnsigned(comptime T: type, arg: []const u8) !T {
    return std.fmt.parseUnsigned(T, arg, 10) catch error.InvalidArgument;
}

fn parseThreaded(arg: []const u8) !bool {
    if (std.mem.eql(u8, arg, "threaded")) return true;
    if (std.mem.eql(u8, arg, "serial")) return false;
    return error.InvalidArgument;
}

fn parseSubpixel(arg: []const u8) !snail.SubpixelOrder {
    if (std.mem.eql(u8, arg, "grayscale")) return .none;
    if (std.mem.eql(u8, arg, "subpixel")) return .rgb;
    return error.InvalidArgument;
}

fn declareTextBlobResources(
    set: *snail.ResourceManifest,
    atlas_key: snail.ResourceKey,
    blob_key: snail.ResourceKey,
    blob: *const snail.TextBlob,
) !snail.TextResourceKeys {
    const resources = blob.resourceKeys(atlas_key, blob_key);
    try set.putTextBlob(resources, blob);
    return resources;
}

const SceneAssets = struct {
    fonts: snail.TextAtlas,
    paint_image: snail.Image,

    fn init(allocator: std.mem.Allocator) !SceneAssets {
        var fonts = try snail.TextAtlas.init(allocator, &.{
            .{ .data = assets_data.noto_sans_regular },
            .{ .data = assets_data.noto_sans_bold, .weight = .bold },
            .{ .data = assets_data.noto_sans_regular, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
            .{ .data = assets_data.noto_sans_bold, .weight = .bold, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
            .{ .data = assets_data.noto_sans_regular, .weight = .semi_bold, .synthetic = .{ .embolden = 0.5 } },
            .{ .data = assets_data.noto_sans_arabic, .fallback = true },
            .{ .data = assets_data.noto_sans_devanagari, .fallback = true },
            .{ .data = assets_data.noto_sans_symbols, .fallback = true },
            .{ .data = assets_data.noto_sans_thai, .fallback = true },
            .{ .data = assets_data.twemoji_mozilla, .fallback = true },
        });
        errdefer fonts.deinit();

        const ascii = &snail.ASCII_PRINTABLE;
        const styles = [_]snail.FontStyle{
            .{},
            .{ .weight = .bold },
            .{ .italic = true },
            .{ .weight = .bold, .italic = true },
            .{ .weight = .semi_bold },
        };
        for (styles) |style| {
            if (try fonts.ensureText(style, ascii)) |new_fonts| {
                fonts.deinit();
                fonts = new_fonts;
            }
        }
        const extra = [_][]const u8{
            "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7",
            "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87",
            "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5",
            "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x8e\xa8\xf0\x9f\x9a\x80\xf0\x9f\x90\x8c\xf0\x9f\x8c\x88",
            " \xe2\x86\x92 ",
            "office ffi fl ffl",
        };
        for (extra) |txt| {
            if (try fonts.ensureText(.{}, txt)) |new_fonts| {
                fonts.deinit();
                fonts = new_fonts;
            }
        }

        var pixels: [16 * 16 * 4]u8 = undefined;
        const colors = [_][4]u8{
            .{ 36, 92, 220, 255 },
            .{ 242, 88, 142, 255 },
            .{ 255, 210, 80, 255 },
            .{ 40, 176, 132, 255 },
        };
        for (0..16) |py| {
            for (0..16) |px| {
                const diagonal = ((px + py) / 4) % 2;
                const quadrant = @as(usize, @intFromBool(px >= 8)) + @as(usize, @intFromBool(py >= 8)) * 2;
                const color = colors[(quadrant + diagonal) % colors.len];
                const i = (py * 16 + px) * 4;
                pixels[i + 0] = color[0];
                pixels[i + 1] = color[1];
                pixels[i + 2] = color[2];
                pixels[i + 3] = color[3];
            }
        }
        const paint_image = try snail.Image.initSrgba8(allocator, 16, 16, &pixels);
        return .{ .fonts = fonts, .paint_image = paint_image };
    }

    fn deinit(self: *SceneAssets) void {
        self.fonts.deinit();
        self.paint_image.deinit();
    }
};

pub fn main(init: std.process.Init.Minimal) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var args = std.process.Args.Iterator.init(init.args);
    _ = args.skip();
    const iters_arg = args.next();
    const threaded_arg = args.next();
    const width_arg = args.next();
    const height_arg = args.next();
    const subpixel_arg = args.next();
    if ((width_arg == null) != (height_arg == null) or args.next() != null) {
        usage();
        return error.InvalidArgument;
    }

    const iters = if (iters_arg) |arg| try parseUnsigned(usize, arg) else DEFAULT_ITERS;
    const threaded = if (threaded_arg) |arg| try parseThreaded(arg) else DEFAULT_THREADED;
    const width = if (width_arg) |arg| try parseUnsigned(u32, arg) else DEFAULT_WIDTH;
    const height = if (height_arg) |arg| try parseUnsigned(u32, arg) else DEFAULT_HEIGHT;
    const subpixel = if (subpixel_arg) |arg| try parseSubpixel(arg) else .none;

    var scene_assets = try SceneAssets.init(arena);
    defer scene_assets.deinit();

    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const layout = demo_banner.buildLayout(wf, hf);

    var text_bundle = snail.TextBlobBundle.init(arena, &scene_assets.fonts);
    defer text_bundle.deinit();

    var bip = try text_bundle.startBlob();
    errdefer bip.abort();
    var dec_rects: [8]snail.Rect = undefined;
    const text_result = try demo_banner.buildTextBlob(bip, layout, .{ .x = 1.0, .y = 1.0 }, &scene_assets.fonts, null, &scene_assets.paint_image, &dec_rects, .{});
    const text_blob_key = snail.ResourceKey.named("banner_text");
    const text_blob = try bip.finish(text_blob_key);
    const fonts_key = snail.ResourceKey.named("banner_fonts");

    var picture = try demo_banner.buildPathPicture(arena, layout, &scene_assets.paint_image, dec_rects[0..text_result.decoration_count]);
    defer picture.deinit();

    var scene = snail.Scene.init(arena);
    defer scene.deinit();
    const paths_key = snail.ResourceKey.named("banner_paths");
    try scene.addPath(.{ .picture = &picture, .resource_key = paths_key });
    try scene.addText(.{ .blob = text_blob, .resources = text_blob.resourceKeys(fonts_key, text_blob_key) });

    const pixel_count = @as(usize, width) * @as(usize, height) * 4;
    const pixels = try arena.alloc(u8, pixel_count);
    var cpu = snail.CpuRenderer.init(pixels.ptr, width, height, width * 4);

    var pool: snail.ThreadPool = undefined;
    try pool.init(arena, .{});
    defer pool.deinit();
    if (threaded) cpu.setThreadPool(&pool);

    var entries: [8]snail.ResourceManifest.Entry = undefined;
    var set = snail.ResourceManifest.init(&entries);
    try set.putPathPicture(paths_key, &picture);
    _ = try declareTextBlobResources(&set, fonts_key, text_blob_key, text_blob);

    var resources = try cpu.uploadResourcesBlocking(.{ .persistent = arena, .scratch = arena }, &set);
    defer resources.deinit();

    const options = snail.DrawState{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .surface = .{
            .pixel_width = wf,
            .pixel_height = hf,
            .encoding = .srgb,
        },
        .raster = .{ .subpixel_order = subpixel },
    };

    var prepared = try snail.PreparedScene.initOwned(arena, &resources, &scene);
    defer prepared.deinit();

    for (0..3) |_| {
        @memset(pixels, 0);
        try cpu.drawPrepared(&resources, &prepared, options);
    }

    const start = nowNs();
    for (0..iters) |_| {
        @memset(pixels, 0);
        try cpu.drawPrepared(&resources, &prepared, options);
    }
    const elapsed_ns = nowNs() - start;
    const per_frame_us = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iters)) / 1000.0;

    const aa_label: []const u8 = if (subpixel == .none) "grayscale" else "subpixel";
    std.debug.print(
        "{s} {s}: {d}x{d}, {d} iters, {d:.2} us/frame, {d:.2} fps, threads={d}\n",
        .{
            if (threaded) "threaded" else "serial",
            aa_label,
            width,
            height,
            iters,
            per_frame_us,
            1_000_000.0 / per_frame_us,
            pool.threadCount(),
        },
    );
}

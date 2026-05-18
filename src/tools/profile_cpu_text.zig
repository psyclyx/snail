//! Tight loop that exercises the threaded CPU text rendering path.
//! Designed for use under `perf record` / `perf stat` to pinpoint hot
//! symbols and microarchitectural bottlenecks. Not part of the public
//! benchmark suite.

const std = @import("std");
const assets = @import("assets");
const snail = @import("snail");

const DEFAULT_WIDTH: u32 = 640;
const DEFAULT_HEIGHT: u32 = 360;
const DEFAULT_ITERS: usize = 2000;
const DEFAULT_THREADED = true;

const SHORT = "Hello, world!";
const SENTENCE = "The quick brown fox jumps over the lazy dog 0123456789";
const PARAGRAPH =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
    "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";

const TextLine = struct {
    text: []const u8,
    x: f32,
    y: f32,
    size: f32,
    color: [4]f32 = .{ 1, 1, 1, 1 },
};

const text_lines = [_]TextLine{
    .{ .text = "Score: 12345  FPS: 60  Level 7", .x = 18, .y = 30, .size = 18 },
    .{ .text = "Health: 100%  Ammo: 42/120", .x = 18, .y = 56, .size = 18, .color = .{ 0.9, 0.35, 0.3, 1 } },
    .{ .text = SENTENCE, .x = 18, .y = 96, .size = 22 },
    .{ .text = PARAGRAPH, .x = 18, .y = 130, .size = 16, .color = .{ 0.92, 0.92, 0.92, 1 } },
};

fn textResourceKey(index: usize) snail.ResourceKey {
    return snail.ResourceKey.fromId(@intCast(index + 1));
}

fn declareTextBlobResources(set: *snail.ResourceManifest, keys: snail.TextResourceKeys, blob: *const snail.TextBlob) !void {
    try set.putTextAtlas(keys.atlas, blob.atlas);
    if (keys.paint) |paint_key| try set.putTextPaint(paint_key, blob);
}

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usage() void {
    std.debug.print(
        "usage: snail-profile-cpu-text [iters] [serial|threaded] [width] [height]\n",
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

fn ensureText(atlas: *snail.TextAtlas, style: snail.FontStyle, text: []const u8) !void {
    if (try atlas.ensureText(style, text)) |next| {
        atlas.deinit();
        atlas.* = next;
    }
}

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
    if ((width_arg == null) != (height_arg == null) or args.next() != null) {
        usage();
        return error.InvalidArgument;
    }

    const iters = if (iters_arg) |arg| try parseUnsigned(usize, arg) else DEFAULT_ITERS;
    const threaded = if (threaded_arg) |arg| try parseThreaded(arg) else DEFAULT_THREADED;
    const width = if (width_arg) |arg| try parseUnsigned(u32, arg) else DEFAULT_WIDTH;
    const height = if (height_arg) |arg| try parseUnsigned(u32, arg) else DEFAULT_HEIGHT;

    var atlas = try snail.TextAtlas.init(arena, &.{.{ .data = assets.noto_sans_regular }});
    defer atlas.deinit();

    for (text_lines) |line| try ensureText(&atlas, .{}, line.text);

    var blob_builder = snail.TextBlobBuilder.init(arena, &atlas);
    defer blob_builder.deinit();

    var blobs = try arena.alloc(snail.TextBlob, text_lines.len);
    for (text_lines, 0..) |line, i| {
        var shaped = try atlas.shapeText(arena, .{}, line.text);
        defer shaped.deinit();
        var local_builder = snail.TextBlobBuilder.init(arena, &atlas);
        _ = try local_builder.append(.{
            .shaped = &shaped,
            .placement = .{ .baseline = .{ .x = line.x, .y = line.y }, .em = line.size },
            .fill = .{ .solid = line.color },
        });
        blobs[i] = try local_builder.finish();
    }

    var scene = snail.Scene.init(arena);
    defer scene.deinit();
    for (blobs, 0..) |*blob, i| {
        try scene.addText(.{ .blob = blob, .resources = snail.ResourceManifest.textBlobResourceKeys(snail.ResourceKey.named("fonts"), textResourceKey(i), blob) });
    }

    const pixel_count = @as(usize, width) * @as(usize, height) * 4;
    const pixels = try arena.alloc(u8, pixel_count);
    var cpu = snail.CpuRenderer.init(pixels.ptr, width, height, width * 4);

    var pool: snail.ThreadPool = undefined;
    try pool.init(arena, .{});
    defer pool.deinit();

    if (threaded) cpu.setThreadPool(&pool);

    var entries: [8]snail.ResourceManifest.Entry = undefined;
    var set = snail.ResourceManifest.init(&entries);
    for (blobs, 0..) |*blob, i| {
        try declareTextBlobResources(&set, snail.ResourceManifest.textBlobResourceKeys(snail.ResourceKey.named("fonts"), textResourceKey(i), blob), blob);
    }

    var resources = try cpu.uploadResourcesBlocking(.{ .persistent = arena, .scratch = arena }, &set);
    defer resources.deinit();

    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const options = snail.DrawState{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .surface = .{
            .pixel_width = wf,
            .pixel_height = hf,
            .encoding = .srgb,
        },
        .raster = .{ .subpixel_order = .rgb },
    };

    var prepared = try snail.PreparedScene.initOwned(arena, &resources, &scene);
    defer prepared.deinit();

    // Warmup
    for (0..10) |_| {
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

    std.debug.print(
        "{s}: {d}x{d}, {d} iters, {d:.2} us/frame, {d:.2} fps, threads={d}\n",
        .{
            if (threaded) "threaded" else "serial",
            width,
            height,
            iters,
            per_frame_us,
            1_000_000.0 / per_frame_us,
            pool.threadCount(),
        },
    );
}

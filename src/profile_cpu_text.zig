//! Tight loop that exercises the threaded CPU text rendering path.
//! Designed for use under `perf record` / `perf stat` to pinpoint hot
//! symbols and microarchitectural bottlenecks. Not part of the public
//! benchmark suite.

const std = @import("std");
const assets = @import("assets");
const snail = @import("snail.zig");

const WIDTH: u32 = 640;
const HEIGHT: u32 = 360;

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

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn ensureText(atlas: *snail.TextAtlas, style: snail.FontStyle, text: []const u8) !void {
    if (try atlas.ensureText(style, text)) |next| {
        atlas.deinit();
        atlas.* = next;
    }
}

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Compile-time knobs. Edit and rebuild for different runs; not worth
    // pulling in std.Io for arg parsing in a profile target.
    const iters: usize = 2000;
    const threaded: bool = true;

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
        _ = try atlas.appendShapedTextBlob(&local_builder, &shaped, .{
            .x = line.x,
            .y = line.y,
            .size = line.size,
            .color = line.color,
        }, true);
        blobs[i] = try local_builder.finish();
    }

    var scene = snail.Scene.init(arena);
    defer scene.deinit();
    for (blobs) |*blob| try scene.addText(.{ .blob = blob });

    const pixels = try arena.alloc(u8, WIDTH * HEIGHT * 4);
    var cpu = snail.CpuRenderer.init(pixels.ptr, WIDTH, HEIGHT, WIDTH * 4);

    var pool: snail.ThreadPool = undefined;
    try pool.init(arena, .{});
    defer pool.deinit();

    if (threaded) cpu.setThreadPool(&pool);

    var entries: [8]snail.ResourceSet.Entry = undefined;
    var set = snail.ResourceSet.init(&entries);
    try set.addScene(&scene);

    var resources = try cpu.uploadResourcesBlocking(arena, &set);
    defer resources.deinit();

    const wf: f32 = @floatFromInt(WIDTH);
    const hf: f32 = @floatFromInt(HEIGHT);
    const options = snail.DrawOptions{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .target = .{
            .pixel_width = wf,
            .pixel_height = hf,
            .subpixel_order = .rgb,
            .is_final_composite = true,
            .opaque_backdrop = true,
        },
    };

    var prepared = try snail.PreparedScene.initOwned(arena, &resources, &scene, options);
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
        "{s}: {d} iters, {d:.2} us/frame, {d:.2} fps, threads={d}\n",
        .{
            if (threaded) "threaded" else "serial",
            iters,
            per_frame_us,
            1_000_000.0 / per_frame_us,
            pool.threadCount(),
        },
    );
}

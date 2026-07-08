//! Headless CPU render of the auto-light comparison overlay, for verifying
//! hinting quality without the interactive Wayland loop. Writes
//! zig-out/autohint-screenshot.tga. Each ppem shows two rows: unhinted (top)
//! then auto_light (bottom).

const std = @import("std");
const snail = @import("snail");
const helpers = @import("snail-helpers");
const compare_mod = @import("autohint_compare.zig");
const harness = @import("screenshot_harness.zig");

const W: u32 = 1040;
const H: u32 = 440;
const OUT_PATH = "zig-out/autohint-screenshot.tga";

const ppems = [_]f32{ 12, 18, 28, 52 };

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();

    var compare = try compare_mod.Compare.init(allocator, pool);
    defer compare.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();

    // One 2-row picture per ppem, stacked, concatenated into a single picture.
    var pictures: std.ArrayList(helpers.Picture) = .empty;
    defer {
        for (pictures.items) |*p| p.deinit();
        pictures.deinit(allocator);
    }

    var y: f32 = 40;
    for (ppems) |ppem| {
        const pic = try compare.buildPicture(arena.allocator(), scratch.allocator(), ppem, y);
        try pictures.append(allocator, pic);
        y += ppem * 3.4 + 16;
    }

    var refs: std.ArrayList(*const helpers.Picture) = .empty;
    defer refs.deinit(allocator);
    for (pictures.items) |*p| try refs.append(allocator, p);
    var text_picture = try helpers.Picture.concat(allocator, refs.items);
    defer text_picture.deinit();

    var empty_atlas = snail.Atlas.empty(allocator);
    defer empty_atlas.deinit();
    var empty_picture = try helpers.Picture.from(allocator, &.{});
    defer empty_picture.deinit();

    try harness.renderCpu(allocator, .{
        .pool = pool,
        .paths_atlas = &empty_atlas,
        .text_atlas = &compare.atlas,
        .paths_picture = &empty_picture,
        .text_picture = &text_picture,
    }, W, H, OUT_PATH, .{});

    std.debug.print("autohint-screenshot: wrote {s} ({d}x{d}); ppems {any}\n", .{ OUT_PATH, W, H, ppems });
}

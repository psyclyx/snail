//! Spot-check the autohint policies on a PROPORTIONAL, TrueType-hinted face
//! (NotoSans-Regular) — the demo grid otherwise only exercises monospace fonts.
//! Renders the un/y/xn/xf/df/tt rows across the grid ppems with per-glyph ORIGIN
//! snapping (correct for variable advances) and writes zig-out/autohint-prop.tga.
//!
//! Run: zig build run-autohint-prop

const std = @import("std");
const snail = @import("snail");
const demo_support = @import("support");
const compare_mod = @import("../../autohint/compare.zig");
const harness = @import("../../screenshot/harness.zig");

const W: u32 = 460;
const H: u32 = compare_mod.default_viewport_height;
const OUT_PATH = "zig-out/autohint-prop.tga";

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

    var compare = try compare_mod.Compare.initFontMode(allocator, pool, @import("assets").noto_sans_regular, "NotoProp", true);
    defer compare.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();

    var text_picture = try compare.buildGridAt(arena.allocator(), scratch.allocator(), 1.0, 0);
    defer text_picture.deinit();

    var empty_atlas = snail.Atlas.empty(allocator);
    defer empty_atlas.deinit();
    var empty_pic = try demo_support.Picture.from(allocator, &.{});
    defer empty_pic.deinit();

    const scene = harness.Scene{
        .pool = pool,
        .paths_atlas = &empty_atlas,
        .text_atlas = &compare.atlas,
        .paths_picture = &empty_pic,
        .text_picture = &text_picture,
    };
    try harness.renderCpu(allocator, scene, W, H, OUT_PATH, .{});
    std.debug.print("autohint-prop: wrote {s} ({d}x{d}), tt-hinted={}\n", .{ OUT_PATH, W, H, compare.tt != null });
}

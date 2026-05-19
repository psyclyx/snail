//! Tight loop for profiling TrueType hint execution and hint-plan packaging.
//! Designed for callgrind/perf-style tools; not part of the public benchmark.

const std = @import("std");
const assets = @import("assets");
const snail = @import("snail");

const DEFAULT_ITERS: usize = 1000;
const DEFAULT_MODE: Mode = .plan;

const Mode = enum {
    execute,
    plan,

    fn parse(arg: []const u8) !Mode {
        if (std.mem.eql(u8, arg, "execute")) return .execute;
        if (std.mem.eql(u8, arg, "plan")) return .plan;
        return error.InvalidArgument;
    }

    fn name(self: Mode) []const u8 {
        return switch (self) {
            .execute => "execute",
            .plan => "plan",
        };
    }
};

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

fn usage() void {
    std.debug.print("usage: snail-profile-tt-hint [iters] [execute|plan]\n", .{});
}

fn parseUnsigned(comptime T: type, arg: []const u8) !T {
    return std.fmt.parseUnsigned(T, arg, 10) catch error.InvalidArgument;
}

fn ensureText(atlas: *snail.TextAtlas, text: []const u8) !void {
    if (try atlas.ensureText(.{}, text)) |next| {
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
    const mode_arg = args.next();
    if (args.next() != null) {
        usage();
        return error.InvalidArgument;
    }

    const iters = if (iters_arg) |arg| try parseUnsigned(usize, arg) else DEFAULT_ITERS;
    const mode = if (mode_arg) |arg| try Mode.parse(arg) else DEFAULT_MODE;

    var atlas = try snail.TextAtlas.init(arena, &.{.{ .data = assets.noto_sans_regular }});
    defer atlas.deinit();
    try ensureText(&atlas, &snail.ASCII_PRINTABLE);

    const face = &atlas.config.faces[0];
    var topology_cache = try snail.TrueTypeGlyphTopologyCache.init(arena, face);
    defer topology_cache.deinit();
    try preloadAsciiTopology(&atlas, &topology_cache);

    var machine = try snail.TrueTypeHintMachine.init(arena, face, snail.TrueTypeHintPpem.uniform(12 * 64));
    defer machine.deinit();

    var scratch_state = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer scratch_state.deinit();

    for (0..10) |_| try runOnce(mode, &machine, &scratch_state, &atlas, &topology_cache);

    const start = nowNs();
    for (0..iters) |_| try runOnce(mode, &machine, &scratch_state, &atlas, &topology_cache);
    const elapsed_ns = nowNs() - start;
    const per_run_us = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iters)) / 1000.0;

    std.debug.print(
        "tt hint {s}: {d} ASCII glyphs, {d} iters, {d:.2} us/run, {d:.2} us/glyph\n",
        .{
            mode.name(),
            snail.ASCII_PRINTABLE.len,
            iters,
            per_run_us,
            per_run_us / @as(f64, @floatFromInt(snail.ASCII_PRINTABLE.len)),
        },
    );
}

fn preloadAsciiTopology(atlas: *snail.TextAtlas, cache: *snail.TrueTypeGlyphTopologyCache) !void {
    for (snail.ASCII_PRINTABLE) |ch| {
        const glyph_id = (try atlas.glyphIndex(0, ch)) orelse continue;
        _ = try cache.get(glyph_id);
    }
}

fn runOnce(
    mode: Mode,
    machine: *snail.TrueTypeHintMachine,
    scratch_state: *std.heap.ArenaAllocator,
    atlas: *snail.TextAtlas,
    cache: *snail.TrueTypeGlyphTopologyCache,
) !void {
    switch (mode) {
        .execute => try executeOnce(machine, atlas, cache),
        .plan => try planOnce(machine, scratch_state, atlas, cache),
    }
}

fn executeOnce(
    machine: *snail.TrueTypeHintMachine,
    atlas: *snail.TextAtlas,
    cache: *snail.TrueTypeGlyphTopologyCache,
) !void {
    for (snail.ASCII_PRINTABLE) |ch| {
        const glyph_id = (try atlas.glyphIndex(0, ch)) orelse continue;
        const executed = machine.executeCachedGlyph(cache, glyph_id) catch |err| switch (err) {
            error.UnsupportedCompoundHinting => continue,
            else => return err,
        };
        keepExecutedGlyphAlive(executed);
    }
}

fn planOnce(
    machine: *snail.TrueTypeHintMachine,
    scratch_state: *std.heap.ArenaAllocator,
    atlas: *snail.TextAtlas,
    cache: *snail.TrueTypeGlyphTopologyCache,
) !void {
    for (snail.ASCII_PRINTABLE) |ch| {
        _ = scratch_state.reset(.retain_capacity);
        const scratch = scratch_state.allocator();
        const glyph_id = (try atlas.glyphIndex(0, ch)) orelse continue;
        const info = atlas.face_glyphs[0].getGlyph(glyph_id) orelse continue;
        const hint = machine.hintCachedGlyph(scratch, cache, glyph_id, .{
            .base = .{ .info = info, .page = atlas.pages[info.page_index] },
        }) catch |err| switch (err) {
            error.UnsupportedCompoundHinting => continue,
            else => return err,
        };
        std.mem.doNotOptimizeAway(hint.curveDeltaBytes());
    }
}

fn keepExecutedGlyphAlive(executed: snail.TrueTypeExecutedGlyph) void {
    switch (executed) {
        .empty => |advance| std.mem.doNotOptimizeAway(advance.x),
        .simple => |hinted| std.mem.doNotOptimizeAway(hinted.advance_x_26_6),
    }
}

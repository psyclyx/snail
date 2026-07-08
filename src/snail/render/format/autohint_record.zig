//! Layer-slab record for the `autohint` special kind.
//!
//! Unlike `text_hint` (which stores absolute moved control points), an
//! autohint record keeps NO geometry — the glyph's real curves live once in
//! the shared atlas as a normal unhinted glyph. The record only carries what
//! the warp needs: the base glyph's band entry (so coverage can find its
//! curves) plus the two per-axis warp-knot runs. The shader warps the sample
//! coordinate with those knots and then runs ordinary coverage against the
//! base glyph — so nothing is baked per ppem.
//!
//! Layout (flat f32; on the GPU the same run is fetched as RGBA texels, four
//! floats per texel):
//!   [0..2)  glyph_x, glyph_y            (base glyph band location)
//!   [2]     packed band counts (h,v)    (bitcast u32)
//!   [3]     reserved
//!   [4..8)  band scale/offset x,y
//!   [8..]   x-knot run: [count, (base,target)×count]   (see warp.packAxis)
//!   [ ..]   y-knot run: [count, (base,target)×count]
//!
//! The y-run start isn't stored — it's `header + 1 + 2*x_count`, which both
//! the CPU reader and the shader recompute from the x count.

const std = @import("std");

const render_abi = @import("abi.zig");
const warp = @import("../../font/autohint/warp.zig");

pub const header_floats: usize = 8;

/// The base glyph's band entry — everything ordinary coverage needs to locate
/// and bucket its curves in the atlas.
pub const BandEntry = struct {
    glyph_x: u16,
    glyph_y: u16,
    h_band_count: u16,
    v_band_count: u16,
    band_scale_x: f32,
    band_scale_y: f32,
    band_offset_x: f32,
    band_offset_y: f32,
};

/// Floats occupied by a record with the given per-axis knot counts.
pub fn recordFloatCount(x_count: usize, y_count: usize) usize {
    return header_floats + (1 + 2 * x_count) + (1 + 2 * y_count);
}

/// Float offset of the y-knot run within a record (relative to its start).
pub fn yRunOffset(x_count: usize) usize {
    return header_floats + 1 + 2 * x_count;
}

/// Write a record at `off` into the flat slab `data`.
pub fn writeRecord(
    data: []f32,
    off: usize,
    be: BandEntry,
    x_knots: []const warp.Knot,
    y_knots: []const warp.Knot,
) void {
    data[off + 0] = @floatFromInt(be.glyph_x);
    data[off + 1] = @floatFromInt(be.glyph_y);
    data[off + 2] = @bitCast(render_abi.packBandCounts(be.h_band_count, be.v_band_count));
    data[off + 3] = 0;
    data[off + 4] = be.band_scale_x;
    data[off + 5] = be.band_scale_y;
    data[off + 6] = be.band_offset_x;
    data[off + 7] = be.band_offset_y;
    const xn = warp.packAxis(x_knots, data[off + header_floats ..]);
    _ = warp.packAxis(y_knots, data[off + header_floats + xn ..]);
}

pub fn readBandEntry(data: []const f32, off: usize) BandEntry {
    const counts = render_abi.unpackBandCounts(@bitCast(data[off + 2]));
    return .{
        .glyph_x = @intFromFloat(data[off + 0]),
        .glyph_y = @intFromFloat(data[off + 1]),
        .h_band_count = counts.h,
        .v_band_count = counts.v,
        .band_scale_x = data[off + 4],
        .band_scale_y = data[off + 5],
        .band_offset_x = data[off + 6],
        .band_offset_y = data[off + 7],
    };
}

/// The x-knot run slice (`[count, pairs…]`) for `warp.inverseWarpPacked`.
pub fn xRun(data: []const f32, off: usize) []const f32 {
    const count: usize = @intFromFloat(data[off + header_floats]);
    return data[off + header_floats ..][0 .. 1 + 2 * count];
}

/// The y-knot run slice for `warp.inverseWarpPacked`.
pub fn yRun(data: []const f32, off: usize) []const f32 {
    const x_count: usize = @intFromFloat(data[off + header_floats]);
    const y_off = off + yRunOffset(x_count);
    const y_count: usize = @intFromFloat(data[y_off]);
    return data[y_off..][0 .. 1 + 2 * y_count];
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;

test "autohint record round-trips band entry and both knot runs" {
    const x_knots = [_]warp.Knot{ .{ .base = 40, .target = 39 }, .{ .base = 220, .target = 224 } };
    const y_knots = [_]warp.Knot{
        .{ .base = 0, .target = 0 },
        .{ .base = 500, .target = 512 },
        .{ .base = 700, .target = 704 },
    };
    const be = BandEntry{
        .glyph_x = 12,
        .glyph_y = 34,
        .h_band_count = 5,
        .v_band_count = 3,
        .band_scale_x = 1.5,
        .band_scale_y = 2.5,
        .band_offset_x = -0.25,
        .band_offset_y = 0.75,
    };

    const n = recordFloatCount(x_knots.len, y_knots.len);
    const buf = try testing.allocator.alloc(f32, n + 16); // + slop to exercise offset
    defer testing.allocator.free(buf);
    @memset(buf, -999);
    const off: usize = 8;
    writeRecord(buf, off, be, &x_knots, &y_knots);

    const back = readBandEntry(buf, off);
    try testing.expectEqual(be.glyph_x, back.glyph_x);
    try testing.expectEqual(be.h_band_count, back.h_band_count);
    try testing.expectEqual(be.v_band_count, back.v_band_count);
    try testing.expectApproxEqAbs(be.band_scale_y, back.band_scale_y, 1e-6);
    try testing.expectApproxEqAbs(be.band_offset_x, back.band_offset_x, 1e-6);

    // The extracted runs must warp identically to the source knots.
    const xr = xRun(buf, off);
    const yr = yRun(buf, off);
    for ([_]f32{ -50, 60, 224, 300, 512, 900 }) |h| {
        try testing.expectApproxEqAbs(
            warp.inverseWarp(&x_knots, h).base,
            warp.inverseWarpPacked(xr, h).base,
            1e-3,
        );
        try testing.expectApproxEqAbs(
            warp.inverseWarp(&y_knots, h).base,
            warp.inverseWarpPacked(yr, h).base,
            1e-3,
        );
    }
}

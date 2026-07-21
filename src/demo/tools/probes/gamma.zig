//! Gamma conformance gate — distinct from `backend_compare` (which is
//! AA-tolerant and blind to gamma). Renders a *controlled* scene of solid
//! mid-gray bands and checks **interior** (full-coverage) pixels, where gamma
//! is analytic and there is no AA to confound the comparison.
//!
//! For each band, a known sRGB input color must survive the encode/decode
//! round-trip back to (approximately) its input byte — and must do so
//! **identically on CPU, GL 3.3, and GLES 3.0**. A missing encode stores the
//! linear value (too dark); a double encode stores it too bright; GLES30's
//! shader-encode-vs-sRGB-attachment path (which has historically "lied") would
//! diverge from CPU/GL. Any of those fails this gate; AA-edge differences,
//! which `backend_compare` tolerates, never touch these interior samples.

const std = @import("std");
const snail = @import("snail");
const demo_support = @import("support");
const harness = @import("../../screenshot/harness.zig");
const egl_offscreen = @import("../../platform/offscreen_gl.zig");

const W: u32 = 96;
const H: u32 = 48;

// Three sRGB grays spanning the tone range. Solids upload as linear, the
// shader outputs linear, and an sRGB attachment re-encodes on store, so a
// correct pipeline round-trips each back to ~round(v*255).
const bands = [_]f32{ 0.25, 0.5, 0.75 };
const tolerance: i32 = 2; // encode LUT / driver rounding

const GammaScene = struct {
    pool: *snail.PagePool,
    paths_atlas: snail.Atlas,
    text_atlas: snail.Atlas, // empty; the harness draws two atlases
    paths_picture: demo_support.Picture,
    text_picture: demo_support.Picture, // empty
    curves: []snail.GlyphCurves,
    allocator: std.mem.Allocator,

    fn deinit(self: *GammaScene) void {
        self.paths_picture.deinit();
        self.text_picture.deinit();
        self.paths_atlas.deinit();
        self.text_atlas.deinit();
        for (self.curves) |*c| c.deinit();
        self.allocator.free(self.curves);
        self.pool.deinit();
    }
};

fn buildScene(allocator: std.mem.Allocator) !GammaScene {
    const pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 17,
        .band_words_per_page = 1 << 14,
    });
    errdefer pool.deinit();

    const curves = try allocator.alloc(snail.GlyphCurves, bands.len);
    errdefer allocator.free(curves);
    var built: usize = 0;
    errdefer for (curves[0..built]) |*c| c.deinit();

    var entries: [bands.len]snail.AtlasEntry = undefined;
    var shapes: [bands.len]snail.Shape = undefined;
    const band_w = @as(f32, @floatFromInt(W)) / bands.len;

    for (bands, 0..) |v, i| {
        var p = try demo_support.unitRectPath(allocator);
        defer p.deinit();
        var prepared = try p.prepare(allocator);
        defer prepared.deinit();
        curves[i] = try prepared.fillCurves(allocator, allocator);
        built += 1;
        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = @intCast(i) };
        entries[i] = .{ .key = key, .curves = curves[i], .paint = .{ .solid = .{ v, v, v, 1 } } };
        shapes[i] = .{
            .key = key,
            .local_transform = prepared.placedBy(demo_support.placeRect(.{ .x = @as(f32, @floatFromInt(i)) * band_w, .y = 0, .w = band_w, .h = @floatFromInt(H) })),
            .local_color = .{ 1, 1, 1, 1 },
        };
    }

    var paths_atlas = try snail.Atlas.from(allocator, pool, &entries);
    errdefer paths_atlas.deinit();
    var text_atlas = try snail.Atlas.from(allocator, pool, &.{});
    errdefer text_atlas.deinit();
    const paths_picture = try demo_support.Picture.from(allocator, &shapes);
    const text_picture = try demo_support.Picture.from(allocator, &.{});

    return .{
        .pool = pool,
        .paths_atlas = paths_atlas,
        .text_atlas = text_atlas,
        .paths_picture = paths_picture,
        .text_picture = text_picture,
        .curves = curves,
        .allocator = allocator,
    };
}

fn scene(gs: *const GammaScene) harness.Scene {
    return .{
        .pool = gs.pool,
        .paths_atlas = &gs.paths_atlas,
        .text_atlas = &gs.text_atlas,
        .paths_picture = &gs.paths_picture,
        .text_picture = &gs.text_picture,
    };
}

/// Sample the interior pixel at the center of band `i` (top-down RGBA8).
fn bandCenter(px: []const u8, i: usize) u8 {
    const band_w = W / bands.len;
    const cx = @as(u32, @intCast(i)) * band_w + band_w / 2;
    const cy = H / 2;
    return px[(cy * W + cx) * 4]; // red channel (gray → all equal)
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gs = try buildScene(allocator);
    defer gs.deinit();
    const s = scene(&gs);

    // CPU (no GL context needed).
    const cpu_px = try harness.renderCpuToPixels(allocator, s, W, H, .{});
    defer allocator.free(cpu_px);

    // GLES 3.0 then GL 3.3 — the two GL encode paths, one context at a time.
    const gles_px = try renderGl(allocator, s, .gles30);
    defer allocator.free(gles_px);
    const gl_px = try renderGl(allocator, s, .gl33);
    defer allocator.free(gl_px);

    var failed = false;
    std.debug.print("gamma-probe {d}x{d} (interior, sRGB target):\n", .{ W, H });
    for (bands, 0..) |v, i| {
        const expected: i32 = @intFromFloat(@round(v * 255.0));
        const c: i32 = bandCenter(cpu_px, i);
        const e: i32 = bandCenter(gles_px, i);
        const g: i32 = bandCenter(gl_px, i);
        std.debug.print("  band {d} sRGB {d:.2}: expect~{d}  cpu={d} gl33={d} gles30={d}\n", .{ i, v, expected, c, g, e });
        for ([_]struct { name: []const u8, got: i32 }{
            .{ .name = "cpu", .got = c },
            .{ .name = "gl33", .got = g },
            .{ .name = "gles30", .got = e },
        }) |bk| {
            if (@abs(bk.got - expected) > tolerance) {
                std.debug.print("  FAIL: {s} band {d} = {d}, expected ~{d} (encode/gamma regression)\n", .{ bk.name, i, bk.got, expected });
                failed = true;
            }
        }
    }
    // ── per-format end-to-end round-trip (CPU) ──
    // Band 1 is sRGB 0.5. Render the scene into each non-rgba8 format and
    // decode band 1's center to confirm the full emit→draw→write pipeline
    // threads the format and sizes the buffer correctly.
    const band1 = 1;
    const band_w = W / bands.len;
    const cx = @as(u32, band1) * band_w + band_w / 2;
    const cy = H / 2;
    const px_index = cy * W + cx;

    // BGRA8: gray, so any color byte ≈ 128 (swizzle is unit-tested separately).
    {
        const p = try harness.renderCpuToPixelsFmt(allocator, s, W, H, .bgra8_unorm, .{});
        defer allocator.free(p);
        const v: i32 = p[px_index * 4];
        std.debug.print("  bgra8   band1 ~128: {d}\n", .{v});
        if (@abs(v - 128) > tolerance) failed = true;
    }
    // RGB10A2: 10-bit R ≈ 0.5 × 1023 = 512.
    {
        const p = try harness.renderCpuToPixelsFmt(allocator, s, W, H, .rgb10a2_unorm, .{});
        defer allocator.free(p);
        const word = std.mem.readInt(u32, p[px_index * 4 ..][0..4], .little);
        const r10: i32 = @intCast(word & 0x3FF);
        std.debug.print("  rgb10a2 band1 ~512: {d}\n", .{r10});
        if (@abs(r10 - 512) > 8) failed = true;
    }
    // RGBA16F: float targets store linear, so band 1 holds srgbToLinear(0.5).
    {
        const p = try harness.renderCpuToPixelsFmt(allocator, s, W, H, .rgba16f, .{});
        defer allocator.free(p);
        const h = std.mem.readInt(u16, p[px_index * 8 ..][0..2], .little);
        const f: f32 = @floatCast(@as(f16, @bitCast(h)));
        const expected = harness.srgbToLinear(0.5);
        std.debug.print("  rgba16f band1 ~{d:.3} (linear): {d:.3}\n", .{ expected, f });
        if (@abs(f - expected) > 0.02) failed = true;
    }
    // A8/R8 mask: the bands are opaque, so painted alpha = 1 → 255.
    inline for (.{ @import("snail-raster").PixelFormat.a8_unorm, @import("snail-raster").PixelFormat.r8_unorm }) |fmt| {
        const p = try harness.renderCpuToPixelsFmt(allocator, s, W, H, fmt, .{});
        defer allocator.free(p);
        const v: i32 = p[px_index];
        std.debug.print("  {s} band1 ~255: {d}\n", .{ @tagName(fmt), v });
        if (@abs(v - 255) > tolerance) failed = true;
    }

    // GPU mask: render the opaque bands into a GL R8 target. The shader routes
    // painted alpha (coverage × paint.alpha = 1 for opaque interior) to .r.
    {
        var ctx = try egl_offscreen.Context.init(W, H, .gl33);
        defer ctx.deinit();
        var target = try harness.OffscreenGlTarget.initR8(W, H);
        defer target.deinit();
        const p = try harness.renderGlR8Mask(allocator, s, W, H, .{});
        defer allocator.free(p);
        const v: i32 = p[px_index]; // R8: 1 byte/pixel
        std.debug.print("  gl33 R8 mask band1 ~255: {d}\n", .{v});
        if (@abs(v - 255) > tolerance) failed = true;
    }

    if (failed) return error.GammaMismatch;
    std.debug.print("gamma-probe: PASS\n", .{});
}

fn renderGl(allocator: std.mem.Allocator, s: harness.Scene, comptime backend: harness.GlBackend) ![]u8 {
    var ctx = try egl_offscreen.Context.init(W, H, switch (backend) {
        .gl33 => .gl33,
        .gles30 => .gles30,
    });
    defer ctx.deinit();
    var target = try harness.OffscreenGlTarget.init(W, H);
    defer target.deinit();
    return harness.renderGlToPixels(backend, allocator, s, W, H, .{});
}

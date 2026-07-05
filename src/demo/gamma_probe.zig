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
const snail_helpers = @import("snail-helpers");
const harness = @import("screenshot_harness.zig");
const egl_offscreen = @import("platform/offscreen_gl.zig");

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
    paths_picture: snail_helpers.Picture,
    text_picture: snail_helpers.Picture, // empty
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
        var p = try snail_helpers.unitRectPath(allocator);
        defer p.deinit();
        curves[i] = try p.toCurves(allocator, allocator);
        built += 1;
        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = @intCast(i) };
        entries[i] = .{ .key = key, .curves = curves[i], .paint = .{ .solid = .{ v, v, v, 1 } } };
        shapes[i] = .{
            .key = key,
            .local_transform = snail_helpers.placeRect(.{ .x = @as(f32, @floatFromInt(i)) * band_w, .y = 0, .w = band_w, .h = @floatFromInt(H) }),
            .local_color = .{ 1, 1, 1, 1 },
        };
    }

    var paths_atlas = try snail.Atlas.from(allocator, pool, &entries);
    errdefer paths_atlas.deinit();
    var text_atlas = try snail.Atlas.from(allocator, pool, &.{});
    errdefer text_atlas.deinit();
    const paths_picture = try snail_helpers.Picture.from(allocator, &shapes);
    const text_picture = try snail_helpers.Picture.from(allocator, &.{});

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

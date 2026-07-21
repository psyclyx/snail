//! CPU twin of the composite coverage probe (`run-composite-probe`).
//!
//! The GL/Vulkan conic coverage-hole fix (sign-of-zero line ownership +
//! calcRootCode-gated conic) was verified under a perspective sweep the
//! CPU rasterizer cannot run (`NonAffineMvp`). This probe gates the CPU
//! solver on the same geometry under the transforms it *does* support:
//! rotations, anisotropic scales, shear, and subpixel offsets — the same
//! shared-vertex root-ownership hazards, minus perspective.
//!
//! Renders the `fill_stroke_inside` composite panel, the separate
//! fill+stroke control, and the plain fill through `snail-raster` over
//! the sweep and scans interiors for coverage holes (a sub-full pixel
//! whose orthogonal neighbors are mostly opaque — never a legitimate AA
//! edge). Exits non-zero on any hole: a regression gate for CPU/GPU
//! coverage parity.

const std = @import("std");
const snail = @import("snail");
const raster = @import("snail-raster");
const support = @import("support");
const passes = @import("../../game/passes.zig");

const W: u32 = 900;
const H: u32 = 700;

// Panel authoring frame (matches the composite probe).
const scene_w: f32 = 460.0;
const scene_h: f32 = 300.0;
const rect = snail.Rect{ .x = 16.0, .y = 16.0, .w = scene_w - 32.0, .h = 268.0 };
const radius: f32 = 22.0;
const stroke_w: f32 = 2.5;

const fill_paint = snail.Paint{ .solid = snail.color.srgbToLinearColor(.{ 0.30, 0.60, 0.95, 1.0 }) };
const stroke_paint = snail.Paint{ .solid = snail.color.srgbToLinearColor(.{ 0.85, 0.95, 1.0, 1.0 }) };

const Mode = enum { composite, separate, fill_only };

fn buildPanel(allocator: std.mem.Allocator, fonts: *passes.Fonts, mode: Mode) !passes.PreparedPass {
    var b = passes.PassBuilder.init(allocator, fonts);
    defer b.deinit();
    switch (mode) {
        .composite => try b.addRoundedRectWithInsideStroke(
            rect,
            fill_paint,
            .{ .paint = stroke_paint, .width = stroke_w, .placement = .inside },
            radius,
        ),
        .separate => try b.addRoundedRectFilledStroked(rect, fill_paint, stroke_paint, stroke_w, radius),
        .fill_only => try b.addRoundedRectFilledUnit(rect, fill_paint, radius),
    }
    return b.freeze(fonts.pool);
}

const Panel = struct {
    pass: passes.PreparedPass,
    cache: raster.DeviceAtlas,
    instances: []snail.render.records.Instance,
    batches: []snail.render.records.DrawBatch,
    instances_len: usize,
    batches_len: usize,

    fn init(allocator: std.mem.Allocator, fonts: *passes.Fonts, mode: Mode) !Panel {
        var pass = try buildPanel(allocator, fonts, mode);
        errdefer pass.deinit();

        var cache = try raster.DeviceAtlas.init(allocator, fonts.pool, .{
            .max_bindings = 2,
            .layer_info_height = 128,
            .max_images = 1,
        });
        errdefer cache.deinit();
        var bindings: [1]snail.render.records.Binding = undefined;
        try cache.upload(allocator, &.{&pass.path_atlas}, &bindings);

        const instances = try allocator.alloc(snail.render.records.Instance, pass.path_picture.shapes.len);
        errdefer allocator.free(instances);
        const batches = try allocator.alloc(snail.render.records.DrawBatch, @max(pass.path_picture.shapes.len, 4));
        errdefer allocator.free(batches);
        var wlen: usize = 0;
        var slen: usize = 0;
        _ = try snail.emit.emit(instances, batches, &wlen, &slen, bindings[0], &pass.path_atlas, pass.path_picture.shapes, .identity, .{ 1, 1, 1, 1 });

        return .{
            .pass = pass,
            .cache = cache,
            .instances = instances,
            .batches = batches,
            .instances_len = wlen,
            .batches_len = slen,
        };
    }

    fn deinit(self: *Panel, allocator: std.mem.Allocator) void {
        allocator.free(self.instances);
        allocator.free(self.batches);
        self.cache.deinit();
        self.pass.deinit();
    }

    /// Render into `pixels` (RGBA8, linear target: alpha == raw coverage).
    fn draw(self: *Panel, pixels: []u8, mvp: snail.Mat4) !void {
        @memset(pixels, 0);
        var renderer = raster.Renderer.init(pixels.ptr, W, H, W * 4);
        const ds = raster.DrawState{
            .surface = .{ .pixel_width = @floatFromInt(W), .pixel_height = @floatFromInt(H), .encoding = .linear },
            .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
            .mvp = mvp,
        };
        try raster.draw(
            &renderer,
            ds,
            .{ .instances = self.instances[0..self.instances_len], .batches = self.batches[0..self.batches_len] },
            &.{&self.cache},
            null,
        );
    }
};

/// 2D affine, column-vector convention: p' = {a c; b d} p + {tx ty}.
const Affine = struct {
    a: f32 = 1,
    b: f32 = 0,
    c: f32 = 0,
    d: f32 = 1,
    tx: f32 = 0,
    ty: f32 = 0,

    fn mul(m: Affine, n: Affine) Affine {
        return .{
            .a = m.a * n.a + m.c * n.b,
            .b = m.b * n.a + m.d * n.b,
            .c = m.a * n.c + m.c * n.d,
            .d = m.b * n.c + m.d * n.d,
            .tx = m.a * n.tx + m.c * n.ty + m.tx,
            .ty = m.b * n.tx + m.d * n.ty + m.ty,
        };
    }

    fn toMat4(m: Affine) snail.Mat4 {
        var out = snail.Mat4.identity;
        out.data[0] = m.a;
        out.data[1] = m.b;
        out.data[4] = m.c;
        out.data[5] = m.d;
        out.data[12] = m.tx;
        out.data[13] = m.ty;
        return out;
    }
};

/// Panel-frame → device MVP for sweep step `i`: rotate about the panel
/// center with anisotropic scale, shear, and a subpixel drift, centered
/// on the target.
fn sweepMvp(i: u32, steps: u32) snail.Mat4 {
    const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
    const angle = t * std.math.pi / 2.0;
    const sx = 1.15 + 0.35 * @sin(t * 12.3);
    const sy = 0.72 + 0.28 * @cos(t * 9.1);
    const shear = 0.18 * @sin(t * 7.7);
    const sub_x = 0.37 * @sin(t * 41.0);
    const sub_y = 0.53 * @cos(t * 33.0);

    const center = Affine{ .tx = @as(f32, W) / 2.0 + sub_x, .ty = @as(f32, H) / 2.0 + sub_y };
    const rot = Affine{ .a = @cos(angle), .b = @sin(angle), .c = -@sin(angle), .d = @cos(angle) };
    const sh = Affine{ .c = shear };
    const sc = Affine{ .a = sx, .d = sy };
    const uncenter = Affine{ .tx = -scene_w / 2.0, .ty = -scene_h / 2.0 };
    const model = center.mul(rot).mul(sh).mul(sc).mul(uncenter);

    const projection = snail.Mat4.ortho(0, @floatFromInt(W), @floatFromInt(H), 0, -1, 1);
    return snail.Mat4.multiply(projection, model.toMat4());
}

/// Interior coverage holes: sub-full pixels with >=3 fully opaque
/// orthogonal neighbors (same oracle as the composite probe).
fn countHoles(px: []const u8, floor: u8) u32 {
    var holes: u32 = 0;
    var y: usize = 1;
    while (y < H - 1) : (y += 1) {
        var x: usize = 1;
        while (x < W - 1) : (x += 1) {
            const a = px[(y * W + x) * 4 + 3];
            if (a >= floor) continue;
            const up = px[((y - 1) * W + x) * 4 + 3];
            const dn = px[((y + 1) * W + x) * 4 + 3];
            const lf = px[(y * W + (x - 1)) * 4 + 3];
            const rt = px[(y * W + (x + 1)) * 4 + 3];
            var solid: u32 = 0;
            if (up == 255) solid += 1;
            if (dn == 255) solid += 1;
            if (lf == 255) solid += 1;
            if (rt == 255) solid += 1;
            if (solid >= 3) holes += 1;
        }
    }
    return holes;
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();
    _ = std.c.mkdir("zig-out", 0o755);

    var fonts = try passes.initFonts(allocator);
    defer fonts.deinit();

    var composite = try Panel.init(allocator, &fonts, .composite);
    defer composite.deinit(allocator);
    var separate = try Panel.init(allocator, &fonts, .separate);
    defer separate.deinit(allocator);
    var fill_only = try Panel.init(allocator, &fonts, .fill_only);
    defer fill_only.deinit(allocator);

    const pixels = try allocator.alloc(u8, @as(usize, W) * H * 4);
    defer allocator.free(pixels);

    var worst_comp: u32 = 0;
    var worst_step: u32 = 0;
    var totals = [3]u64{ 0, 0, 0 };
    var worsts = [3]u32{ 0, 0, 0 };

    const steps: u32 = 64;
    var i: u32 = 0;
    while (i < steps) : (i += 1) {
        const mvp = sweepMvp(i, steps);
        const panels = [3]*Panel{ &composite, &separate, &fill_only };
        for (panels, 0..) |panel, pi| {
            try panel.draw(pixels, mvp);
            const holes = countHoles(pixels, 235);
            totals[pi] += holes;
            if (holes > worsts[pi]) worsts[pi] = holes;
            if (pi == 0 and holes > worst_comp) {
                worst_comp = holes;
                worst_step = i;
            }
            if (holes > 0)
                std.debug.print("step {d: >3} panel {d}: holes={d}\n", .{ i, pi, holes });
        }
    }

    std.debug.print(
        "coverage-parity (CPU) {d}x{d}, {d} affine steps: composite total={d} worst={d}, separate total={d}, fill_only total={d}\n",
        .{ W, H, steps, totals[0], worsts[0], totals[1], totals[2] },
    );

    if (totals[0] + totals[1] + totals[2] > 0) {
        try composite.draw(pixels, sweepMvp(worst_step, steps));
        try support.screenshot.writeTga("zig-out/coverage-parity.tga", pixels, W, H);
        std.debug.print("coverage-parity: FAIL (wrote zig-out/coverage-parity.tga, worst step {d})\n", .{worst_step});
        std.process.exit(1);
    }
    std.debug.print("coverage-parity: PASS\n", .{});
}

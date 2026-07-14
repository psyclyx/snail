//! Vulkan embeddable-path byte-diff test.
//!
//! Drives the reusable reference caller renderer (`vulkan_caller.VulkanCaller`)
//! and byte-diffs it against the all-in-one `VulkanRenderer` into the same
//! offscreen target. The caller side is fully standalone — its own resource
//! layout + transfer command pool + cache (via `embeddable.cachePipelineShape`)
//! + pipelines — so nothing but the reference touches the all-in-one renderer.
//!
//! Prints `PASS` when every pass matches within the GPU ±1-LSB AA tolerance,
//! `FAIL` (exit non-zero) otherwise.

const std = @import("std");
const snail = @import("snail");
const demo_content = @import("content.zig");
const harness = @import("screenshot_harness.zig");
const vulkan_demo_platform = @import("demo_platform_vulkan");
const vulkan_caller = @import("vulkan_caller.zig");
const platform = vulkan_demo_platform.offscreen;

const vk = vulkan_caller.vk;

const W: u32 = 400;
const H: u32 = 240;

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const vk_ctx = try platform.initOffscreen(W, H);
    defer platform.deinitOffscreen();

    var content = try demo_content.build(allocator, W, H);
    defer content.deinit();

    const cache_opts: snail.vulkan.backend_cache.CacheOptions = .{
        .max_bindings = 4,
        .layer_info_height = 64,
        .max_images = 8,
        .max_image_width = 256,
        .max_image_height = 256,
    };

    // ── Reference path: the all-in-one renderer + its own cache ──
    var vk_renderer = try snail.VulkanRenderer.init(allocator, vk_ctx);
    defer vk_renderer.deinit();
    var ref_cache = try snail.VulkanBackendCache.init(allocator, content.pool, vk_renderer.state.pipelineShape(), cache_opts);
    defer ref_cache.deinit();
    var ref_bindings: [2]snail.Binding = undefined;
    try ref_cache.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &ref_bindings);

    // ── Standalone embeddable path: our OWN resource layout + transfer pool +
    //    cache + caller renderer, built via the public contract ──
    var layout: snail.vulkan.VulkanResourceLayout = undefined;
    try layout.init(vk_ctx);
    defer layout.deinit();
    const transfer_pool = try vulkan_caller.createTransferPool(vk_ctx);
    defer vk.vkDestroyCommandPool(vk_ctx.device, transfer_pool, null);
    var sa_cache = try snail.VulkanBackendCache.init(allocator, content.pool, snail.vulkan.embeddable.cachePipelineShape(vk_ctx, &layout, transfer_pool), cache_opts);
    defer sa_cache.deinit();
    var sa_bindings: [2]snail.Binding = undefined;
    try sa_cache.upload(allocator, &.{ &content.paths_atlas, &content.text_atlas }, &sa_bindings);

    const budget = snail.emit.wordBudget(content.paths_picture.shapes.len, 0) + snail.emit.wordBudget(content.text_picture.shapes.len, 0);
    var caller = try vulkan_caller.VulkanCaller.init(vk_ctx, sa_cache.descriptorSetLayout(), budget * @sizeOf(u32));
    defer caller.deinit();

    const clear = [4]f32{
        harness.srgbToLinear(harness.bg_srgb_f32[0]),
        harness.srgbToLinear(harness.bg_srgb_f32[1]),
        harness.srgbToLinear(harness.bg_srgb_f32[2]),
        harness.bg_srgb_f32[3],
    };
    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const gray_ds = harness.drawState(W, H);
    const sub_ds = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .rgb, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };

    var buf = try EmitBuffers.init(allocator, budget);
    defer buf.deinit(allocator);

    var worst: u32 = 0;

    // Paths only (single path segment).
    {
        const r = try buf.emitPicture(.ref, ref_bindings[0], &content.paths_atlas, content.paths_picture.shapes);
        const c = try buf.emitPicture(.caller, sa_bindings[0], &content.paths_atlas, content.paths_picture.shapes);
        worst = @max(worst, (try renderAndDiff(allocator, &vk_renderer, &ref_cache, &caller, &sa_cache, clear, gray_ds, r, c, "paths        ")).max);
    }
    // Text only — grayscale and subpixel reuse one emit per side.
    {
        const r = try buf.emitPicture(.ref, ref_bindings[1], &content.text_atlas, content.text_picture.shapes);
        const c = try buf.emitPicture(.caller, sa_bindings[1], &content.text_atlas, content.text_picture.shapes);
        worst = @max(worst, (try renderAndDiff(allocator, &vk_renderer, &ref_cache, &caller, &sa_cache, clear, gray_ds, r, c, "text gray    ")).max);
        worst = @max(worst, (try renderAndDiff(allocator, &vk_renderer, &ref_cache, &caller, &sa_cache, clear, sub_ds, r, c, "text subpixel")).max);
    }
    // Full scene: paths + text in one frame (two segments, run-dispatched).
    {
        const r = try buf.emitScene(.ref, &content, ref_bindings);
        const c = try buf.emitScene(.caller, &content, sa_bindings);
        worst = @max(worst, (try renderAndDiff(allocator, &vk_renderer, &ref_cache, &caller, &sa_cache, clear, gray_ds, r, c, "full scene   ")).max);
    }

    if (worst <= 1) {
        std.debug.print("PASS: caller pipelines match the all-in-one within ±1 LSB\n", .{});
    } else {
        std.debug.print("FAIL: caller pipelines diverge from the all-in-one (max delta {d})\n", .{worst});
        return error.EmbeddableMismatch;
    }
}

fn renderAndDiff(
    allocator: std.mem.Allocator,
    vk_renderer: *snail.VulkanRenderer,
    ref_cache: *snail.VulkanBackendCache,
    caller: *vulkan_caller.VulkanCaller,
    sa_cache: *snail.VulkanBackendCache,
    clear: [4]f32,
    draw_state: snail.DrawState,
    ref: Emitted,
    call: Emitted,
    label: []const u8,
) !Diff {
    const glyph_count: u32 = @intCast(ref.words.len / snail.WORDS_PER_INSTANCE);

    // Reference: the all-in-one VulkanRenderer + its cache.
    {
        const cmd = platform.beginFrameOffscreenWithClear(clear);
        vk_renderer.state.setCommandBuffer(cmd);
        defer vk_renderer.state.clearCommandBuffer();
        vk_renderer.state.setFrameSlot(platform.currentOffscreenFrameIndex());
        try vk_renderer.state.draw(allocator, draw_state, .{ .words = ref.words, .segments = ref.segs }, &.{ref_cache});
        platform.endFrameOffscreen();
        platform.queueWaitIdle();
    }
    const pixels_ref = try platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels_ref);

    // Caller: standalone cache + the reference caller renderer.
    {
        const platform_cmd = platform.beginFrameOffscreenWithClear(clear);
        const cmd: vk.VkCommandBuffer = @ptrCast(platform_cmd);
        caller.render(cmd, sa_cache.descriptorSet(), draw_state, call.words, call.segs);
        platform.endFrameOffscreen();
        platform.queueWaitIdle();
    }
    const pixels_emb = try platform.captureOffscreenRgba8(allocator);
    defer allocator.free(pixels_emb);

    const d = diff(pixels_ref, pixels_emb);
    std.debug.print("embeddable-vulkan [{s}]: {d} glyphs, max delta={d}, mean={d:.4}\n", .{ label, glyph_count, d.max, d.mean });
    return d;
}

const Emitted = struct { words: []const u32, segs: []const snail.DrawSegment };

const Side = enum { ref, caller };

// Two emit buffer sets — the reference emits against its cache's bindings, the
// caller against the standalone cache's.
const EmitBuffers = struct {
    ref_words: []u32,
    ref_segs: []snail.DrawSegment,
    ca_words: []u32,
    ca_segs: []snail.DrawSegment,

    fn init(a: std.mem.Allocator, budget: usize) !EmitBuffers {
        return .{
            .ref_words = try a.alloc(u32, budget),
            .ref_segs = try a.alloc(snail.DrawSegment, 16),
            .ca_words = try a.alloc(u32, budget),
            .ca_segs = try a.alloc(snail.DrawSegment, 16),
        };
    }

    fn deinit(self: *EmitBuffers, a: std.mem.Allocator) void {
        a.free(self.ref_words);
        a.free(self.ref_segs);
        a.free(self.ca_words);
        a.free(self.ca_segs);
    }

    fn pick(self: *EmitBuffers, side: Side) struct { w: []u32, s: []snail.DrawSegment } {
        return switch (side) {
            .ref => .{ .w = self.ref_words, .s = self.ref_segs },
            .caller => .{ .w = self.ca_words, .s = self.ca_segs },
        };
    }

    fn emitPicture(self: *EmitBuffers, side: Side, binding: snail.Binding, atlas: *const snail.Atlas, shapes: anytype) !Emitted {
        const b = self.pick(side);
        var wl: usize = 0;
        var sl: usize = 0;
        _ = try snail.emit.emit(b.w, b.s, &wl, &sl, binding, atlas, shapes, .identity, .{ 1, 1, 1, 1 });
        return .{ .words = b.w[0..wl], .segs = b.s[0..sl] };
    }

    fn emitScene(self: *EmitBuffers, side: Side, content: anytype, bindings: [2]snail.Binding) !Emitted {
        const b = self.pick(side);
        const scene = harness.Scene{
            .pool = content.pool,
            .paths_atlas = &content.paths_atlas,
            .text_atlas = &content.text_atlas,
            .paths_picture = &content.paths_picture,
            .text_picture = &content.text_picture,
        };
        const e = try harness.emitScene(b.w, b.s, scene, bindings[0], bindings[1]);
        return .{ .words = b.w[0..e.words_len], .segs = b.s[0..e.segs_len] };
    }
};

const Diff = struct { max: u32, mean: f64 };

fn diff(a: []const u8, b: []const u8) Diff {
    var max: u32 = 0;
    var total: u64 = 0;
    const n = @min(a.len, b.len);
    for (0..n) |i| {
        const dd = if (a[i] > b[i]) a[i] - b[i] else b[i] - a[i];
        if (dd > max) max = dd;
        total += dd;
    }
    return .{ .max = max, .mean = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(n)) };
}

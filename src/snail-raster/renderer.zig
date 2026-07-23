//! Software rasterizer for snail glyph data.
//! Evaluates the same Bezier curve/band data the GPU shaders use, but per-pixel
//! into a caller-owned, explicitly formatted memory buffer. Intended for
//! headless rendering and bootstrap frames (before EGL/Vulkan is available).
//!
//! Pixel parity vs GL/Vulkan: matches within 1 sRGB LSB on virtually every
//! pixel; near-tangent conic edges may diverge by a few LSB due to differing
//! float-op orderings between CPU code and the SPIR-V/GLSL pipeline.

const std = @import("std");
const snail = @import("snail");
const render_state = @import("render-state");
const bezier = @import("snail").render.geometry;
const band_tex = @import("snail").render.geometry;
const render_abi = @import("snail").render.records;
const autohint_record = @import("snail").render.geometry.autohint;
const autohint_warp = @import("snail-raster-support").autohint.warp;
const autohint_policy = @import("snail").autohint.policy;
const vertex = @import("snail").render.records;
const ThreadPool = @import("thread_pool.zig").ThreadPool;

/// Caller-owned transient fitted knots for one glyph draw.
pub const AutohintWarp = struct {
    x: []const autohint_warp.Knot,
    y: []const autohint_warp.Knot,
};
const GlyphBandEntry = band_tex.GlyphBandEntry;
const Vec2 = snail.Vec2;
const Transform2D = snail.Transform2D;
const FillRule = snail.FillRule;
const SubpixelOrder = render_state.SubpixelOrder;
const blend_mod = @import("blend.zig");
const color_mod = @import("color.zig");
const coverage_mod = @import("coverage.zig");
const geometry_mod = @import("geometry.zig");
const path_paint_mod = @import("path_paint.zig");
const resources_mod = @import("resources.zig");
const texture_mod = @import("texture.zig");

const SubpixelCoverage = coverage_mod.SubpixelCoverage;
const SubpixelCoveragePlan = coverage_mod.SubpixelCoveragePlan;
const addColors = path_paint_mod.addColors;
const advanceLocalPixel = geometry_mod.advanceLocalPixel;
const compositeOver = path_paint_mod.compositeOver;
const compositeSubpixelOver = coverage_mod.compositeSubpixelOver;
const evalGlyphCoverage = coverage_mod.evalGlyphCoverage;
const evalGlyphCoverageBandSpan = coverage_mod.evalGlyphCoverageBandSpan;
const evalGlyphCoverageBandSpanRowH = coverage_mod.evalGlyphCoverageBandSpanRowH;
const evalGlyphCoverageRowH = coverage_mod.evalGlyphCoverageRowH;
const evalGlyphCoverageSaturatedRowH = coverage_mod.evalGlyphCoverageSaturatedRowH;
const evalGlyphCoverageSubpixel = coverage_mod.evalGlyphCoverageSubpixel;
const evalGlyphCoverageSubpixelRowH = coverage_mod.evalGlyphCoverageSubpixelRowH;
const prepareRowHorizSpanState = coverage_mod.prepareRowHorizSpanState;
const prepareRowHorizState = coverage_mod.prepareRowHorizState;
const prepareSaturatedRowState = coverage_mod.prepareSaturatedRowState;
const RowHorizState = coverage_mod.RowHorizState;
const SaturatedRowState = coverage_mod.SaturatedRowState;
const expandBoundsForCoverageSupport = geometry_mod.expandBoundsForCoverageSupport;
const f16ToF32 = texture_mod.f16ToF32;
const fetchLayerInfoTexel = path_paint_mod.fetchLayerInfoTexel;
const glyphEdgePixelsPerPixel = geometry_mod.glyphEdgePixelsPerPixel;
const inverseTransform = geometry_mod.inverseTransform;
const LayerInfoEntry = path_paint_mod.LayerInfoEntry;
const max3 = color_mod.max3;
const multiplyLinearColor = color_mod.multiplyLinearColor;
const premultiplyCoverage = coverage_mod.premultiplyCoverage;
const premultiplySubpixelCoverage = coverage_mod.premultiplySubpixelCoverage;
const PreparedPathPaint = path_paint_mod.PreparedPathPaint;
const PreparedPathLayer = path_paint_mod.PreparedPathLayer;
const PreparedPathRecord = path_paint_mod.PreparedPathRecord;
const PreparedAtlasPage = resources_mod.PreparedAtlasPage;
const ScreenBounds = geometry_mod.ScreenBounds;

fn halfColor(encoded: [4]u16) [4]f32 {
    return .{ f16ToF32(encoded[0]), f16ToF32(encoded[1]), f16ToF32(encoded[2]), f16ToF32(encoded[3]) };
}

fn bandPayload(encoded: [4]u32) [4]f32 {
    return .{ @bitCast(encoded[0]), @bitCast(encoded[1]), @bitCast(encoded[2]), @bitCast(encoded[3]) };
}

fn expandDeviceBounds(bounds: *ScreenBounds, pixels: f32) void {
    bounds.min.x -= pixels;
    bounds.min.y -= pixels;
    bounds.max.x += pixels;
    bounds.max.y += pixels;
}

const PixelAxisRange = struct { min: u32, max: u32 };

/// Floor/ceil a floating bound only after clipping it to a representable pixel
/// interval. This keeps off-screen Inf and extreme finite transforms from
/// reaching a trapping float-to-int conversion.
fn clippedPixelAxis(min_value: f32, max_value: f32, clip_min: u32, clip_max: u32) ?PixelAxisRange {
    if (clip_min >= clip_max or std.math.isNan(min_value) or std.math.isNan(max_value) or min_value > max_value)
        return null;
    const min_wide: f64 = min_value;
    const max_wide: f64 = max_value;
    const clip_min_wide: f64 = @floatFromInt(clip_min);
    const clip_max_wide: f64 = @floatFromInt(clip_max);
    const first = if (min_wide <= clip_min_wide)
        clip_min
    else if (min_wide >= clip_max_wide)
        clip_max
    else
        @as(u32, @intFromFloat(@floor(min_wide)));
    const end = if (max_wide <= clip_min_wide)
        clip_min
    else if (max_wide >= clip_max_wide)
        clip_max
    else
        @as(u32, @intFromFloat(@ceil(max_wide)));
    return if (first < end) .{ .min = first, .max = end } else null;
}

fn pixelExtent(min_value: f32, max_value: f32) u32 {
    if (std.math.isNan(min_value) or std.math.isNan(max_value) or max_value <= min_value) return 0;
    const extent = @as(f64, max_value) - @as(f64, min_value);
    if (!std.math.isFinite(extent) or extent >= @as(f64, @floatFromInt(std.math.maxInt(u32))))
        return std.math.maxInt(u32);
    return @intFromFloat(@ceil(extent));
}
const subpixelBlendCoverage = coverage_mod.subpixelBlendCoverage;
const transformedGlyphBounds = geometry_mod.transformedGlyphBounds;

pub const PreparedResources = resources_mod.PreparedResources;

// ── Per-instance profiling (diagnostic) ──
//
// When `instance_profile` is non-null, the SERIAL `drawBatchInstances`
// path times each instance individually and appends an entry. The
// threaded path (`drawBatchInstancesParallel` → `tileWorker`) skips the
// hook — per-instance timing in a tiled-parallel dispatch would be
// misleading (each strip processes every instance over a fraction of
// the surface, so per-strip-per-instance numbers don't compose into
// "how much did this instance cost"). Force the `cpu_unthreaded`
// backend to get a meaningful breakdown.

pub const InstanceProfileEntry = struct {
    /// Position in this drawBatch's vertex stream.
    index: u32,
    us: f64,
    /// Screen-space bbox extents after the scene-to-pixel transform,
    /// for distinguishing "this is a huge fill" from "this is a glyph".
    pixel_w: u32,
    pixel_h: u32,
};

pub const InstanceProfileBuffer = struct {
    entries: []InstanceProfileEntry,
    count: usize = 0,

    pub fn reset(self: *InstanceProfileBuffer) void {
        self.count = 0;
    }
};

/// Monotonic clock in nanoseconds. Used by the per-instance profiler
/// to time each `renderBatchInstance` call. Zig 0.16 dropped
/// `std.time.Instant`/`Timer`; this drops to `std.c.clock_gettime`
/// directly, same as the demo's wayland platform. Windows has no
/// clock_gettime (std.c.clockid_t is void there, which fails analysis,
/// not just linking), so it uses QueryPerformanceCounter instead.
fn monotonicNanos() u64 {
    if (@import("builtin").os.tag == .windows) {
        const windows = std.os.windows;
        var qpc: windows.LARGE_INTEGER = undefined;
        var qpf: windows.LARGE_INTEGER = undefined;
        if (!windows.ntdll.RtlQueryPerformanceCounter(&qpc).toBool()) return 0;
        if (!windows.ntdll.RtlQueryPerformanceFrequency(&qpf).toBool()) return 0;
        const ticks: u128 = @intCast(qpc);
        return @intCast(ticks * 1_000_000_000 / @as(u128, @intCast(qpf)));
    }
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

/// Skip threshold for coverage/alpha values below one 8-bit LSB: anything
/// smaller rounds to zero in the final sRGB8 output, so the composite would
/// be a no-op.
const one_lsb_8bit: f32 = 1.0 / 255.0;
var linear_resolve_token_nonce: std.atomic.Value(u64) = .init(1);

pub const Renderer = struct {
    pixels: []u8, // caller-owned; validated before every operation that writes
    width: u32,
    height: u32,
    stride: u32, // bytes per row (at least width * format.bytesPerPixel())
    subpixel_order: SubpixelOrder,
    /// Encoding of the caller-owned pixel buffer. The unified `Renderer.draw`
    /// path sets this from `DrawState.surface.encoding` every frame.
    target_encoding: render_state.TargetEncoding,
    /// Byte layout declared when the caller attaches the pixel buffer. The
    /// blend path comptime-specializes on it once per draw.
    format: render_state.PixelFormat = .rgba8_unorm,
    target_resolve: blend_mod.ResolveMode,
    linear_resolve_active: bool,
    linear_resolve_restore: ?LinearResolveState,
    linear_resolve_token: ?LinearResolveToken,
    coverage_transfer: render_state.CoverageTransfer,
    // Half-open row window [row_clip_min, row_clip_max). Pixel writes outside
    // this range are skipped. Used by tile workers to claim disjoint scanline
    // bands; defaults to the full image for single-threaded callers.
    row_clip_min: u32,
    row_clip_max: u32,
    col_clip_min: u32,
    col_clip_max: u32,
    /// Optional per-instance timing sink. Per-renderer (not a process global)
    /// so independent renderers on separate threads profile independently.
    /// Only the serial `drawBatchInstances` path records; wire a buffer in to
    /// start, clear to stop. The caller owns the buffer's storage/lifetime.
    instance_profile: ?*InstanceProfileBuffer = null,

    pub const TILE_ROWS: u32 = 2;

    // Stack-allocated row-state array for composite paths. Most COLR / outline
    // groups have far fewer layers than this; spillover falls back to per-pixel
    // evaluation.
    const MAX_COMPOSITE_LAYERS: usize = 8;

    pub const BufferError = error{
        /// The byte slice is too short for `stride * height`, or that product
        /// cannot be represented by the host.
        InvalidBuffer,
        /// A row cannot hold `width` pixels in the selected format, or its
        /// required byte count overflows.
        InvalidStride,
        /// Target dimensions or format do not match the attached buffer, or
        /// select an invalid/empty resolve surface.
        InvalidTargetSurface,
    };

    pub const LinearResolveError = BufferError || error{
        UnsupportedResolve,
        LinearResolveAlreadyActive,
        InvalidBackdrop,
    };

    pub const EndLinearResolveError = error{
        LinearResolveNotActive,
        InvalidLinearResolveToken,
    };

    pub const ReinitBufferError = BufferError || error{LinearResolveActive};

    /// Opaque capability for exactly one active resolve scope. All restoration
    /// state stays private inside the renderer.
    pub const LinearResolveToken = enum(u64) { _ };

    const LinearResolveState = struct {
        row_clip_min: u32,
        row_clip_max: u32,
        col_clip_min: u32,
        col_clip_max: u32,
        target_encoding: render_state.TargetEncoding,
        target_resolve: blend_mod.ResolveMode,
    };

    pub const DrawBatchError = BufferError || error{
        InvalidInstance,
        NonAffineMvp,
        TextureLayerOverflow,
    };

    /// Attach a caller-owned pixel buffer with its exact storage format.
    pub fn init(pixels: []u8, width: u32, height: u32, stride: u32, format: render_state.PixelFormat) BufferError!Renderer {
        try validateBuffer(pixels, width, height, stride, format);
        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .stride = stride,
            .subpixel_order = .none,
            // CPU's pixel-buffer contract is sRGB bytes (cf. the file-level
            // doc). The unified `Renderer.draw` path overrides this from
            // `DrawState.surface.encoding` per frame.
            .target_encoding = .srgb,
            .target_resolve = .{ .direct = {} },
            .linear_resolve_active = false,
            .linear_resolve_restore = null,
            .linear_resolve_token = null,
            .format = format,
            .coverage_transfer = .identity,
            .row_clip_min = 0,
            .row_clip_max = height,
            .col_clip_min = 0,
            .col_clip_max = width,
        };
    }

    /// Replace the caller-owned pixel buffer and dimensions while retaining
    /// renderer configuration and profiling state. Failure leaves the existing
    /// buffer intact.
    pub fn reinitBuffer(self: *Renderer, pixels: []u8, width: u32, height: u32, stride: u32, format: render_state.PixelFormat) ReinitBufferError!void {
        if (self.linear_resolve_active) return error.LinearResolveActive;
        try validateBuffer(pixels, width, height, stride, format);
        self.pixels = pixels;
        self.width = width;
        self.height = height;
        self.stride = stride;
        self.format = format;
        self.row_clip_min = 0;
        self.row_clip_max = height;
        self.col_clip_min = 0;
        self.col_clip_max = width;
    }

    fn validateBuffer(pixels: []u8, width: u32, height: u32, stride: u32, format: render_state.PixelFormat) BufferError!void {
        const min_row_bytes = std.math.mul(u32, width, format.bytesPerPixel()) catch
            return error.InvalidStride;
        if (stride < min_row_bytes) return error.InvalidStride;
        const required = std.math.mul(usize, @as(usize, stride), @as(usize, height)) catch
            return error.InvalidBuffer;
        if (pixels.len < required) return error.InvalidBuffer;
    }

    /// Validate that `surface` exactly matches the attached dimensions and
    /// format. Called before every public operation that writes pixels.
    pub fn validateTarget(self: *const Renderer, surface: render_state.TargetSurface) BufferError!void {
        if (surface.pixel_width != self.width or surface.pixel_height != self.height or surface.format != self.format)
            return error.InvalidTargetSurface;
        if (self.row_clip_min > self.row_clip_max or self.row_clip_max > self.height or
            self.col_clip_min > self.col_clip_max or self.col_clip_max > self.width)
            return error.InvalidTargetSurface;
        if (self.linear_resolve_active) {
            if (self.linear_resolve_restore == null or self.linear_resolve_token == null)
                return error.InvalidTargetSurface;
            switch (self.target_resolve) {
                .linear => {},
                .direct => return error.InvalidTargetSurface,
            }
        } else if (self.linear_resolve_restore != null or self.linear_resolve_token != null) {
            return error.InvalidTargetSurface;
        }
        try validateBuffer(self.pixels, self.width, self.height, self.stride, surface.format);
    }

    /// Begin the CPU emulation of a linear intermediate resolve, restrict writes
    /// to its resolve rectangle, and seed the requested backdrop. The software
    /// backend currently supports only `.rgba16f` as `intermediate_format`;
    /// other intermediate formats return `UnsupportedResolve`. Nested passes
    /// return `LinearResolveAlreadyActive`. Errors occur before renderer state
    /// or target pixels are changed.
    pub fn beginLinearResolve(self: *Renderer, surface: render_state.TargetSurface, resolve: render_state.LinearResolve) LinearResolveError!LinearResolveToken {
        try self.validateTarget(surface);
        if (!surface.supportsLinearResolve()) return error.UnsupportedResolve;
        if (resolve.intermediate_format != .rgba16f) return error.UnsupportedResolve;
        if (self.linear_resolve_active) return error.LinearResolveAlreadyActive;
        const rect = render_state.resolveRect(surface, resolve);
        if (rect.w == 0 or rect.h == 0) return error.InvalidTargetSurface;
        resolve.backdrop.validate() catch return error.InvalidBackdrop;
        const restore = LinearResolveState{
            .row_clip_min = self.row_clip_min,
            .row_clip_max = self.row_clip_max,
            .col_clip_min = self.col_clip_min,
            .col_clip_max = self.col_clip_max,
            .target_encoding = self.target_encoding,
            .target_resolve = self.target_resolve,
        };
        const token = mintLinearResolveToken();
        self.linear_resolve_restore = restore;
        self.linear_resolve_token = token;
        self.col_clip_min = @intCast(rect.x);
        self.row_clip_min = @intCast(rect.y);
        self.col_clip_max = self.col_clip_min + rect.w;
        self.row_clip_max = self.row_clip_min + rect.h;
        self.target_encoding = surface.encoding;
        self.format = surface.format;
        self.target_resolve = .{ .linear = resolve };
        self.linear_resolve_active = true;
        self.seedLinearResolveBackdrop(surface.encoding, rect, resolve.backdrop);
        return token;
    }

    /// End a successful linear-resolve scope and restore the renderer state
    /// captured by `beginLinearResolve`. Tokens are renderer- and
    /// generation-specific; stale, copied-after-use, or cross-renderer tokens
    /// return an error without modifying state.
    pub fn endLinearResolve(self: *Renderer, token: LinearResolveToken) EndLinearResolveError!void {
        if (!self.linear_resolve_active) return error.LinearResolveNotActive;
        if (self.linear_resolve_token == null or self.linear_resolve_token.? != token)
            return error.InvalidLinearResolveToken;
        const restore = self.linear_resolve_restore orelse return error.LinearResolveNotActive;
        self.row_clip_min = restore.row_clip_min;
        self.row_clip_max = restore.row_clip_max;
        self.col_clip_min = restore.col_clip_min;
        self.col_clip_max = restore.col_clip_max;
        self.target_encoding = restore.target_encoding;
        self.target_resolve = restore.target_resolve;
        self.linear_resolve_active = false;
        self.linear_resolve_restore = null;
        self.linear_resolve_token = null;
    }

    fn mintLinearResolveToken() LinearResolveToken {
        while (true) {
            const raw = linear_resolve_token_nonce.fetchAdd(1, .monotonic);
            if (raw != 0) return @enumFromInt(raw);
        }
    }

    fn seedLinearResolveBackdrop(self: *Renderer, _: render_state.TargetEncoding, rect: render_state.PixelRect, backdrop: render_state.LinearResolve.Backdrop) void {
        switch (backdrop) {
            .target, .dont_care => return,
            .transparent => self.fillResolveRect(rect, .{ 0, 0, 0, 0 }),
            .clear => |color| self.fillResolveRect(rect, color),
        }
    }

    fn fillResolveRect(self: *Renderer, rect: render_state.PixelRect, color: [4]f32) void {
        if (rect.w == 0 or rect.h == 0) return;
        var row: u32 = @intCast(rect.y);
        const y1 = row + rect.h;
        while (row < y1) : (row += 1) {
            var col: u32 = @intCast(rect.x);
            const x1 = col + rect.w;
            while (col < x1) : (col += 1) {
                switch (self.format) {
                    inline else => |fmt| blend_mod.writeClearPixel(fmt, self.blendTarget(), row, col, color),
                }
            }
        }
    }

    inline fn applyCoverageTransfer(self: *const Renderer, cov: f32) f32 {
        const exponent = self.coverage_transfer.exponent;
        if (@abs(exponent - 1.0) <= 1.0e-6 or !std.math.isFinite(exponent)) return cov;
        return std.math.pow(f32, std.math.clamp(cov, 0.0, 1.0), @max(exponent, 1.0 / 65536.0));
    }

    fn applySubpixelCoverageTransfer(self: *const Renderer, cov: SubpixelCoverage) SubpixelCoverage {
        return .{
            .rgb = .{
                self.applyCoverageTransfer(cov.rgb[0]),
                self.applyCoverageTransfer(cov.rgb[1]),
                self.applyCoverageTransfer(cov.rgb[2]),
            },
            .alpha = self.applyCoverageTransfer(cov.alpha),
        };
    }

    fn drawPreparedBatch(self: *Renderer, prepared: *const PreparedResources, instances: []const vertex.Instance, state: render_state.DrawState, texture_layer_base: u32, thread_pool: ?*ThreadPool) DrawBatchError!void {
        try self.validateTarget(state.surface);
        for (instances) |*instance| {
            vertex.validateInstance(instance) catch return error.InvalidInstance;
            _ = std.math.add(
                u32,
                texture_layer_base,
                @as(u32, render_abi.glyphWordAtlasLayer(instance.glyph[1])),
            ) catch return error.TextureLayerOverflow;
        }
        // Drive the four fields the rendering helpers read off `self` from
        // `state`. There's no save/restore: each `drawBatch` overwrites
        // them from scratch, and `beginLinearResolve` owns `target_resolve`
        // for the duration of a linear-resolve pass (so we leave it alone
        // when one is active).
        self.subpixel_order = state.raster.subpixel_order;
        self.target_encoding = state.surface.encoding;
        self.format = state.surface.format;
        if (!self.linear_resolve_active) self.target_resolve = .{ .direct = {} };
        self.coverage_transfer = state.raster.coverage_transfer;

        // Apply `state.scissor_rect` by intersecting with the current
        // clip window. Restore unconditionally — works inside or outside
        // a linear-resolve pass, since the resolve has already set the
        // outer clip to the resolve region. A non-overlapping scissor
        // collapses to a no-op (clip min == max), which the per-pixel
        // writes skip anyway, so an empty intersection is cheap.
        const clip_save = if (state.scissor_rect != null) ClipSave{
            .row_clip_min = self.row_clip_min,
            .row_clip_max = self.row_clip_max,
            .col_clip_min = self.col_clip_min,
            .col_clip_max = self.col_clip_max,
        } else null;
        defer if (clip_save) |s| s.restore(self);
        if (state.scissor_rect) |sr| {
            self.intersectClip(sr);
        }

        // The CPU rasterizer doesn't do per-pixel 1/w, so a non-affine MVP
        // would silently disagree with the GPU backends. Refuse — but as a
        // returned error, not a process abort: an embedder feeding matrices
        // from its own camera code shouldn't be able to crash the host.
        const scene = snail.mvpToScenePixel(
            state.mvp,
            @floatFromInt(state.surface.pixel_width),
            @floatFromInt(state.surface.pixel_height),
        ) orelse
            return error.NonAffineMvp;
        if (thread_pool) |pool| {
            if (pool.threadCount() > 0 and self.row_clip_max > self.row_clip_min + TILE_ROWS) {
                self.drawBatchInstancesParallel(pool, prepared, instances, scene, texture_layer_base, true);
                return;
            }
        }
        // Serial path: enable the profile hook if the caller has wired
        // up `instance_profile`. The threaded path above skips it
        // intentionally — see `instance_profile` docs.
        self.drawBatchInstances(prepared, instances, scene, texture_layer_base, true, true);
    }

    const ClipSave = struct {
        row_clip_min: u32,
        row_clip_max: u32,
        col_clip_min: u32,
        col_clip_max: u32,

        fn restore(self: ClipSave, r: *Renderer) void {
            r.row_clip_min = self.row_clip_min;
            r.row_clip_max = self.row_clip_max;
            r.col_clip_min = self.col_clip_min;
            r.col_clip_max = self.col_clip_max;
        }
    };

    fn intersectClip(self: *Renderer, rect: render_state.PixelRect) void {
        const cur = render_state.PixelRect{
            .x = @intCast(self.col_clip_min),
            .y = @intCast(self.row_clip_min),
            .w = self.col_clip_max - self.col_clip_min,
            .h = self.row_clip_max - self.row_clip_min,
        };
        const sx0 = @max(@as(i64, rect.x), @as(i64, cur.x));
        const sy0 = @max(@as(i64, rect.y), @as(i64, cur.y));
        const sx1 = @min(@as(i64, rect.x) + @as(i64, rect.w), @as(i64, cur.x) + @as(i64, cur.w));
        const sy1 = @min(@as(i64, rect.y) + @as(i64, rect.h), @as(i64, cur.y) + @as(i64, cur.h));
        if (sx0 >= sx1 or sy0 >= sy1) {
            self.col_clip_min = self.col_clip_max;
            self.row_clip_min = self.row_clip_max;
            return;
        }
        self.col_clip_min = @intCast(sx0);
        self.row_clip_min = @intCast(sy0);
        self.col_clip_max = @intCast(sx1);
        self.row_clip_max = @intCast(sy1);
    }

    /// Compatibility hook for renderer-generic drivers; the CPU backend has no
    /// command-buffer state to begin.
    pub fn beginDraw(_: *Renderer) void {}

    /// Stable diagnostic backend name.
    pub fn backendName(_: *const Renderer) [:0]const u8 {
        return "CPU";
    }

    fn drawBatchInstances(self: *Renderer, prepared: *const PreparedResources, instances: []const vertex.Instance, scene_to_pixel: Transform2D, texture_layer_base: u32, allow_subpixel: bool, profile_enabled: bool) void {
        const profile = if (profile_enabled) self.instance_profile else null;
        var idx: u32 = 0;
        for (instances) |*inst| {
            if (profile) |p| {
                const start_ns = monotonicNanos();
                self.renderBatchInstance(prepared, inst, scene_to_pixel, texture_layer_base, allow_subpixel);
                const end_ns = monotonicNanos();
                if (p.count < p.entries.len) {
                    const decoded = decodeBatchInstance(inst, scene_to_pixel);
                    var bounds = geometry_mod.transformedGlyphBounds(decoded.bbox, decoded.transform);
                    geometry_mod.expandBoundsForCoverageSupport(&bounds, self.subpixel_order, allow_subpixel);
                    p.entries[p.count] = .{
                        .index = idx,
                        .us = @as(f64, @floatFromInt(end_ns -% start_ns)) / 1000.0,
                        .pixel_w = pixelExtent(bounds.min.x, bounds.max.x),
                        .pixel_h = pixelExtent(bounds.min.y, bounds.max.y),
                    };
                    p.count += 1;
                }
            } else {
                self.renderBatchInstance(prepared, inst, scene_to_pixel, texture_layer_base, allow_subpixel);
            }
            idx += 1;
        }
    }

    const TileCtx = struct {
        base: *const Renderer,
        prepared: *const PreparedResources,
        instances: []const vertex.Instance,
        scene_to_pixel: Transform2D,
        texture_layer_base: u32,
        allow_subpixel: bool,
        strip_rows: u32,
        y0: u32,
        y1: u32,
    };

    fn tileWorker(ctx_opaque: *anyopaque, idx: u32) void {
        const ctx: *const TileCtx = @ptrCast(@alignCast(ctx_opaque));
        const strip_y0 = ctx.y0 + idx * ctx.strip_rows;
        if (strip_y0 >= ctx.y1) return;
        const strip_y1 = @min(strip_y0 + ctx.strip_rows, ctx.y1);

        var worker = ctx.base.*;
        worker.row_clip_min = strip_y0;
        worker.row_clip_max = strip_y1;
        worker.drawBatchInstances(ctx.prepared, ctx.instances, ctx.scene_to_pixel, ctx.texture_layer_base, ctx.allow_subpixel, false);
    }

    fn drawBatchInstancesParallel(
        self: *Renderer,
        pool: *ThreadPool,
        prepared: *const PreparedResources,
        instances: []const vertex.Instance,
        scene_to_pixel: Transform2D,
        texture_layer_base: u32,
        allow_subpixel: bool,
    ) void {
        // Tighten the dispatch range to the union pixel-Y bounds of the
        // actual instances. Without this we fan out one tile per
        // TILE_ROWS rows across the full row_clip range; a HUD-style
        // batch that only covers the top 100 rows would otherwise spawn
        // hundreds of empty tiles and let thread-pool barrier overhead
        // dominate the real rasterization.
        const dispatch_range = batchPixelRowRange(
            instances,
            scene_to_pixel,
            self.subpixel_order,
            allow_subpixel,
            self.row_clip_min,
            self.row_clip_max,
        );
        const y0 = dispatch_range.min;
        const y1 = dispatch_range.max;
        if (y1 <= y0) return;
        const rows = y1 - y0;
        // Bound the number of jobs that each rescan the instance stream. Tiny
        // two-row jobs are useful for load balancing, but become quadratic
        // overhead on tall targets with large batches.
        const worker_limit: usize = std.math.maxInt(u32) / 4;
        const worker_count: u32 = @intCast(@min(@max(pool.threadCount(), 1), worker_limit));
        const target_jobs = worker_count * 4;
        const adaptive_rows = rows / target_jobs + @intFromBool(rows % target_jobs != 0);
        const strip_rows = @max(TILE_ROWS, adaptive_rows);
        const strip_count: u32 = rows / strip_rows + @intFromBool(rows % strip_rows != 0);
        var ctx = TileCtx{
            .base = self,
            .prepared = prepared,
            .instances = instances,
            .scene_to_pixel = scene_to_pixel,
            .texture_layer_base = texture_layer_base,
            .allow_subpixel = allow_subpixel,
            .strip_rows = strip_rows,
            .y0 = y0,
            .y1 = y1,
        };
        pool.dispatch(strip_count, @ptrCast(&ctx), tileWorker);
    }

    /// Union of every instance's pixel-Y bounds, clamped to u32 row
    /// indices. Returns the full possible range on an empty batch so
    /// the caller's row_clip intersection short-circuits naturally.
    fn batchPixelRowRange(
        instances: []const vertex.Instance,
        scene_to_pixel: Transform2D,
        subpixel_order: SubpixelOrder,
        allow_subpixel: bool,
        clip_min: u32,
        clip_max: u32,
    ) PixelAxisRange {
        var min_y: f32 = std.math.floatMax(f32);
        var max_y: f32 = -std.math.floatMax(f32);

        for (instances) |*inst| {
            const decoded = decodeBatchInstance(inst, scene_to_pixel);
            var bounds = geometry_mod.transformedGlyphBounds(decoded.bbox, decoded.transform);
            geometry_mod.expandBoundsForCoverageSupport(&bounds, subpixel_order, allow_subpixel);
            if (decoded.isAutohint()) expandDeviceBounds(&bounds, 2.0);
            if (std.math.isNan(bounds.min.y) or std.math.isNan(bounds.max.y))
                return .{ .min = clip_min, .max = clip_max };
            if (bounds.min.y < min_y) min_y = bounds.min.y;
            if (bounds.max.y > max_y) max_y = bounds.max.y;
        }

        return clippedPixelAxis(min_y, max_y, clip_min, clip_max) orelse
            .{ .min = clip_min, .max = clip_min };
    }

    const BatchInstance = struct {
        bbox: snail.BBox,
        transform: Transform2D,
        glyph: [2]u32,
        band: [4]f32,
        color: [4]f32,
        tint: [4]f32,
        policy: [4]u32,

        fn atlasLayerByte(self: BatchInstance) u8 {
            return render_abi.glyphWordAtlasLayer(self.glyph[1]);
        }

        fn isSpecialLayer(self: BatchInstance) bool {
            return render_abi.glyphWordIsSpecial(self.glyph[1]);
        }

        fn isAutohint(self: BatchInstance) bool {
            return self.isSpecialLayer() and render_abi.specialGlyphWordKind(self.glyph[1]) == .autohint;
        }
    };

    fn decodeBatchInstance(inst: *const vertex.Instance, scene_to_pixel: Transform2D) BatchInstance {
        const encoded = inst;
        const instance_transform = Transform2D{
            .xx = encoded.xform[0],
            .xy = encoded.xform[1],
            .yx = encoded.xform[2],
            .yy = encoded.xform[3],
            .tx = encoded.origin[0],
            .ty = encoded.origin[1],
        };
        return .{
            .bbox = .{
                .min = .{ .x = f16ToF32(encoded.rect[0]), .y = f16ToF32(encoded.rect[1]) },
                .max = .{ .x = f16ToF32(encoded.rect[2]), .y = f16ToF32(encoded.rect[3]) },
            },
            // GPU backends compose this with the MVP uniform in the vertex
            // shader. The CPU backend renders in pixel space directly.
            .transform = Transform2D.multiply(scene_to_pixel, instance_transform),
            .glyph = encoded.glyph,
            .band = bandPayload(encoded.payload),
            .color = halfColor(encoded.color),
            .tint = halfColor(encoded.tint),
            .policy = encoded.payload,
        };
    }

    fn renderBatchInstance(self: *Renderer, prepared: *const PreparedResources, inst: *const vertex.Instance, scene_to_pixel: Transform2D, texture_layer_base: u32, allow_subpixel: bool) void {
        const decoded = decodeBatchInstance(inst, scene_to_pixel);
        if (decoded.isSpecialLayer()) {
            self.renderSpecialBatchInstance(prepared, decoded, texture_layer_base, allow_subpixel);
        } else {
            self.renderRegularBatchInstance(prepared, decoded, texture_layer_base, allow_subpixel);
        }
    }

    fn renderRegularBatchInstance(self: *Renderer, prepared: *const PreparedResources, decoded: BatchInstance, texture_layer_base: u32, allow_subpixel: bool) void {
        const gz = decoded.glyph[0];
        const gw = decoded.glyph[1];
        const be = GlyphBandEntry{
            .glyph_x = render_abi.glyphLocationX(gz),
            .glyph_y = render_abi.glyphLocationY(gz),
            .h_band_count = render_abi.regularGlyphWordHBandCount(gw),
            .v_band_count = render_abi.regularGlyphWordVBandCount(gw),
            .band_scale_x = decoded.band[0],
            .band_scale_y = decoded.band[1],
            .band_offset_x = decoded.band[2],
            .band_offset_y = decoded.band[3],
        };

        const atlas_layer = texture_layer_base + @as(u32, decoded.atlasLayerByte());
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;
        self.renderTransformedGlyph(page, decoded.bbox, be, decoded.transform, multiplyLinearColor(decoded.color, decoded.tint), allow_subpixel);
    }

    fn renderSpecialBatchInstance(self: *Renderer, prepared: *const PreparedResources, decoded: BatchInstance, texture_layer_base: u32, allow_subpixel: bool) void {
        const gz = decoded.glyph[0];
        const gw = decoded.glyph[1];
        const info_x = render_abi.glyphLocationX(gz);
        const info_y = render_abi.glyphLocationY(gz);
        const atlas_layer = texture_layer_base + @as(u32, decoded.atlasLayerByte());

        const resolved = prepared.resolveLayerInfo(info_y) orelse return;
        const entry = resolved.entry;
        const special_kind = render_abi.specialGlyphWordKind(gw) orelse return;
        if (special_kind == .tt_hinted_text) {
            self.renderTtHintedTextBatchInstance(prepared, decoded, atlas_layer, entry, info_x, resolved.local_y, allow_subpixel);
            return;
        }
        if (special_kind == .autohint) {
            self.renderAutohintBatchInstance(prepared, decoded, atlas_layer, entry, info_x, resolved.local_y, allow_subpixel);
            return;
        }

        const first_tag = (fetchLayerInfoTexel(entry.data, entry.width, info_x, resolved.local_y, 0) orelse return)[3];
        if ((special_kind == .path or special_kind == .colr) and first_tag < 0.0) {
            const record = entry.pathRecordAt(info_x, resolved.local_y) orelse return;
            self.renderPathBatchLayers(prepared, decoded.bbox, decoded.transform, decoded.tint, atlas_layer, entry, record, false);
        }
    }

    fn renderTtHintedTextBatchInstance(
        self: *Renderer,
        prepared: *const PreparedResources,
        decoded: BatchInstance,
        atlas_layer: u32,
        entry: *const LayerInfoEntry,
        info_x: u16,
        info_y: u16,
        allow_subpixel: bool,
    ) void {
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;
        const header = fetchLayerInfoTexel(entry.data, entry.width, info_x, info_y, 0) orelse return;
        const band = fetchLayerInfoTexel(entry.data, entry.width, info_x, info_y, 1) orelse return;
        const band_counts = render_abi.unpackBandCounts(@bitCast(header[2])) orelse return;
        // Slab floats are caller-controlled bit patterns, legitimately NaN in
        // some words. Decode the glyph location with the same validated
        // conversion the autohint sibling uses, and require a finite band
        // transform; anything else skips the instance instead of trapping.
        const glyph_x = path_paint_mod.exactUnsigned(header[0], std.math.maxInt(u16)) orelse return;
        const glyph_y = path_paint_mod.exactUnsigned(header[1], std.math.maxInt(u16)) orelse return;
        for (band) |value| if (!std.math.isFinite(value)) return;
        const be = GlyphBandEntry{
            .glyph_x = @intCast(glyph_x),
            .glyph_y = @intCast(glyph_y),
            .h_band_count = band_counts.h,
            .v_band_count = band_counts.v,
            .band_scale_x = band[0],
            .band_scale_y = band[1],
            .band_offset_x = band[2],
            .band_offset_y = band[3],
        };
        self.renderTransformedGlyph(
            page,
            decoded.bbox,
            be,
            decoded.transform,
            multiplyLinearColor(decoded.color, decoded.tint),
            allow_subpixel,
        );
    }

    fn renderAutohintBatchInstance(
        self: *Renderer,
        prepared: *const PreparedResources,
        decoded: BatchInstance,
        atlas_layer: u32,
        entry: *const LayerInfoEntry,
        info_x: u16,
        info_y: u16,
        allow_subpixel: bool,
    ) void {
        const page = (if (atlas_layer < prepared.atlas_pages.len) prepared.atlas_pages[atlas_layer] else null) orelse return;
        const off = (@as(usize, info_y) * entry.width + @as(usize, info_x)) * 4;
        const record = autohint_record.decode(entry.data, off) catch return;
        const rec = record.band_entry;
        const be = GlyphBandEntry{
            .glyph_x = rec.glyph_x,
            .glyph_y = rec.glyph_y,
            .h_band_count = rec.h_band_count,
            .v_band_count = rec.v_band_count,
            .band_scale_x = rec.band_scale_x,
            .band_scale_y = rec.band_scale_y,
            .band_offset_x = rec.band_offset_x,
            .band_offset_y = rec.band_offset_y,
        };
        const policy = autohint_policy.AutohintPolicy.unpack(decoded.policy) catch return;
        self.renderTransformedAutohintGlyph(
            page,
            decoded.bbox,
            be,
            decoded.transform,
            multiplyLinearColor(decoded.color, decoded.tint),
            record,
            policy,
            allow_subpixel,
        );
    }

    const PathRasterState = struct {
        inverse: Transform2D,
        x0: u32,
        x1: u32,
        y0: u32,
        y1: u32,
        epp: Vec2,
        ppe: Vec2,
        sample_dx: Vec2,
        subpixel_plan: SubpixelCoveragePlan,
        use_subpixel: bool,
    };

    const PathCompositePrograms = struct {
        outline: bool,
        fill: PreparedPathPaint = .{},
        stroke: PreparedPathPaint = .{},
    };

    const PathCompositeAccum = struct {
        result: [4]f32 = .{ 0, 0, 0, 0 },
        result_blend: [3]f32 = .{ 0, 0, 0 },
        fill_cov: SubpixelCoverage = .{ .rgb = .{ 0, 0, 0 }, .alpha = 0 },
        stroke_cov: SubpixelCoverage = .{ .rgb = .{ 0, 0, 0 }, .alpha = 0 },
        fill_paint: [4]f32 = .{ 0, 0, 0, 0 },
        stroke_paint: [4]f32 = .{ 0, 0, 0, 0 },
        fill_apply_dither: bool = false,
        stroke_apply_dither: bool = false,
        has_gradient: bool = false,
    };

    const PathCompositePixel = struct {
        color: [4]f32,
        blend: [3]f32,
        has_gradient: bool,
    };

    fn preparedAtlasPage(prepared: *const PreparedResources, atlas_layer: u32) ?*const PreparedAtlasPage {
        if (atlas_layer >= prepared.atlas_pages.len) return null;
        if (prepared.atlas_pages[atlas_layer]) |*page| return page;
        return null;
    }

    fn pathRasterState(self: *const Renderer, bbox: snail.BBox, transform: Transform2D, allow_subpixel: bool) ?PathRasterState {
        const inverse = inverseTransform(transform) orelse return null;
        var bounds = transformedGlyphBounds(bbox, transform);
        expandBoundsForCoverageSupport(&bounds, self.subpixel_order, allow_subpixel);

        const x_range = clippedPixelAxis(bounds.min.x, bounds.max.x, self.col_clip_min, self.col_clip_max) orelse return null;
        const y_range = clippedPixelAxis(bounds.min.y, bounds.max.y, self.row_clip_min, self.row_clip_max) orelse return null;

        const epp = glyphEdgePixelsPerPixel(inverse);
        const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
        const sample_dx = Vec2.new(inverse.xx, inverse.yx);
        const sample_dy = Vec2.new(inverse.xy, inverse.yy);
        return .{
            .inverse = inverse,
            .x0 = x_range.min,
            .x1 = x_range.max,
            .y0 = y_range.min,
            .y1 = y_range.max,
            .epp = epp,
            .ppe = ppe,
            .sample_dx = sample_dx,
            .subpixel_plan = SubpixelCoveragePlan.init(sample_dx, sample_dy, self.subpixel_order),
            .use_subpixel = allow_subpixel and self.subpixel_order != .none,
        };
    }

    fn recordCompositeSubpixelLayer(
        self: *Renderer,
        accum: *PathCompositeAccum,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        layer: PreparedPathLayer,
        layer_index: usize,
        programs: PathCompositePrograms,
        local: Vec2,
        tint: [4]f32,
        row_state: ?*const RowHorizState,
    ) void {
        const cov = if (row_state) |rs|
            self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixelRowH(
                page,
                local.x,
                local.y,
                rs,
                raster.subpixel_plan,
                layer.band_entry,
                layer.band_max_v,
                layer.fill_rule,
            ))
        else
            self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
                page,
                local,
                raster.subpixel_plan,
                layer.band_entry,
                layer.band_max_h,
                layer.band_max_v,
                layer.fill_rule,
            ));

        if (programs.outline and layer_index < 2) {
            if (layer_index == 0) {
                accum.fill_cov = cov;
                if (max3(cov.rgb) > 0.0 or cov.alpha > 0.0) {
                    const paint = programs.fill.sample(local);
                    accum.fill_paint = multiplyLinearColor(paint.color, tint);
                    accum.fill_apply_dither = paint.apply_dither;
                }
            } else {
                accum.stroke_cov = cov;
                if (max3(cov.rgb) > 0.0 or cov.alpha > 0.0) {
                    const paint = programs.stroke.sample(local);
                    accum.stroke_paint = multiplyLinearColor(paint.color, tint);
                    accum.stroke_apply_dither = paint.apply_dither;
                }
            }
            return;
        }

        if (max3(cov.rgb) <= 0.0 and cov.alpha <= 0.0) return;
        var paint = layer.paint.sample(local);
        paint.color = multiplyLinearColor(paint.color, tint);
        if (paint.apply_dither and cov.alpha > 1e-6) accum.has_gradient = true;
        compositeSubpixelOver(
            premultiplySubpixelCoverage(paint.color, cov.rgb, cov.alpha),
            subpixelBlendCoverage(paint.color, cov.rgb),
            &accum.result,
            &accum.result_blend,
        );
    }

    fn scalarPathLayerCoverage(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        layer: PreparedPathLayer,
        local: Vec2,
    ) f32 {
        return self.applyCoverageTransfer(evalGlyphCoverageBandSpan(
            page,
            local.x,
            local.y,
            raster.epp.x,
            raster.epp.y,
            raster.ppe.x,
            raster.ppe.y,
            layer.band_entry,
            layer.band_max_h,
            layer.band_max_v,
            layer.fill_rule,
        ));
    }

    fn recordCompositeScalarLayer(
        self: *Renderer,
        accum: *PathCompositeAccum,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        layer: PreparedPathLayer,
        layer_index: usize,
        programs: PathCompositePrograms,
        local: Vec2,
        tint: [4]f32,
        row_state: ?*const RowHorizState,
        sat_state: ?*const SaturatedRowState,
    ) void {
        const cov = if (row_state) |rs| blk: {
            if (sat_state) |ss| {
                break :blk self.applyCoverageTransfer(evalGlyphCoverageSaturatedRowH(
                    page,
                    local.x,
                    local.y,
                    rs,
                    ss,
                    raster.epp.x,
                    raster.ppe.x,
                    raster.ppe.y,
                    layer.band_entry,
                    layer.band_max_h,
                    layer.band_max_v,
                    layer.fill_rule,
                ));
            }
            break :blk self.applyCoverageTransfer(evalGlyphCoverageBandSpanRowH(
                page,
                local.x,
                local.y,
                rs,
                raster.epp.x,
                raster.ppe.x,
                raster.ppe.y,
                layer.band_entry,
                layer.band_max_h,
                layer.band_max_v,
                layer.fill_rule,
            ));
        } else self.scalarPathLayerCoverage(page, raster, layer, local);

        if (programs.outline and layer_index < 2) {
            const subpixel_cov: SubpixelCoverage = .{ .rgb = .{ cov, cov, cov }, .alpha = cov };
            if (layer_index == 0) {
                accum.fill_cov = subpixel_cov;
                if (cov > 0.0) {
                    const paint = programs.fill.sample(local);
                    accum.fill_paint = multiplyLinearColor(paint.color, tint);
                }
            } else {
                accum.stroke_cov = subpixel_cov;
                if (cov > 0.0) {
                    const paint = programs.stroke.sample(local);
                    accum.stroke_paint = multiplyLinearColor(paint.color, tint);
                }
            }
            return;
        }

        if (cov <= 0.0) return;
        var paint = layer.paint.sample(local);
        paint.color = multiplyLinearColor(paint.color, tint);
        accum.result = compositeOver(premultiplyCoverage(paint.color, cov), accum.result);
    }

    fn finishOutlineComposite(accum: *PathCompositeAccum, use_subpixel: bool) void {
        if (use_subpixel) {
            const border_cov = [3]f32{
                @min(accum.fill_cov.rgb[0], accum.stroke_cov.rgb[0]),
                @min(accum.fill_cov.rgb[1], accum.stroke_cov.rgb[1]),
                @min(accum.fill_cov.rgb[2], accum.stroke_cov.rgb[2]),
            };
            const interior_cov = [3]f32{
                @max(accum.fill_cov.rgb[0] - border_cov[0], 0.0),
                @max(accum.fill_cov.rgb[1] - border_cov[1], 0.0),
                @max(accum.fill_cov.rgb[2] - border_cov[2], 0.0),
            };
            const border_alpha = @min(accum.fill_cov.alpha, accum.stroke_cov.alpha);
            const interior_alpha = @max(accum.fill_cov.alpha - border_alpha, 0.0);
            if (accum.fill_apply_dither and interior_alpha > 1e-6) accum.has_gradient = true;
            if (accum.stroke_apply_dither and border_alpha > 1e-6) accum.has_gradient = true;
            const fill_blend = subpixelBlendCoverage(accum.fill_paint, interior_cov);
            const stroke_blend = subpixelBlendCoverage(accum.stroke_paint, border_cov);
            compositeSubpixelOver(
                addColors(
                    premultiplySubpixelCoverage(accum.fill_paint, interior_cov, interior_alpha),
                    premultiplySubpixelCoverage(accum.stroke_paint, border_cov, border_alpha),
                ),
                .{
                    fill_blend[0] + stroke_blend[0],
                    fill_blend[1] + stroke_blend[1],
                    fill_blend[2] + stroke_blend[2],
                },
                &accum.result,
                &accum.result_blend,
            );
        } else {
            const border_cov = @min(accum.fill_cov.alpha, accum.stroke_cov.alpha);
            const interior_cov = @max(accum.fill_cov.alpha - border_cov, 0.0);
            const combined = addColors(premultiplyCoverage(accum.fill_paint, interior_cov), premultiplyCoverage(accum.stroke_paint, border_cov));
            accum.result = compositeOver(combined, accum.result);
        }
    }

    fn sampleCompositePathPixel(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        layers: []const PreparedPathLayer,
        programs: PathCompositePrograms,
        local: Vec2,
        tint: [4]f32,
        row_states: ?[]const RowHorizState,
        sat_states: ?[]const SaturatedRowState,
    ) PathCompositePixel {
        var accum: PathCompositeAccum = .{};
        for (layers, 0..) |layer, layer_index| {
            const rs: ?*const RowHorizState = if (row_states) |states| &states[layer_index] else null;
            const ss: ?*const SaturatedRowState = if (sat_states) |states| &states[layer_index] else null;
            if (raster.use_subpixel) {
                self.recordCompositeSubpixelLayer(&accum, page, raster, layer, layer_index, programs, local, tint, rs);
            } else {
                self.recordCompositeScalarLayer(&accum, page, raster, layer, layer_index, programs, local, tint, rs, ss);
            }
        }
        if (programs.outline) finishOutlineComposite(&accum, raster.use_subpixel);
        return .{
            .color = accum.result,
            .blend = accum.result_blend,
            .has_gradient = accum.has_gradient,
        };
    }

    fn renderPathBatchLayers(
        self: *Renderer,
        prepared: *const PreparedResources,
        union_bbox: snail.BBox,
        transform: Transform2D,
        tint: [4]f32,
        atlas_layer: u32,
        entry: *const LayerInfoEntry,
        record: *const PreparedPathRecord,
        allow_subpixel: bool,
    ) void {
        const page = preparedAtlasPage(prepared, atlas_layer) orelse return;

        if (record.tag == @intFromEnum(render_abi.PaintRecordKind.composite_group)) {
            self.renderCompositePathBatchLayers(page, union_bbox, transform, tint, entry, record, allow_subpixel);
        } else {
            self.renderSinglePathBatchLayer(page, union_bbox, transform, tint, entry, record, allow_subpixel);
        }
    }

    fn renderScalarInsideStrokeCompositePathBatchLayers(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        raster: PathRasterState,
        tint: [4]f32,
        fill_layer: PreparedPathLayer,
        stroke_layer: PreparedPathLayer,
        fill_program: PreparedPathPaint,
        stroke_program: PreparedPathPaint,
    ) void {
        const axis_aligned = @abs(raster.sample_dx.y) < 1e-9;

        var row: u32 = raster.y0;
        while (row < raster.y1) : (row += 1) {
            var col: u32 = raster.x0;
            var local = raster.inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });

            var fill_state: RowHorizState = undefined;
            var stroke_state: RowHorizState = undefined;
            const row_state_ready = axis_aligned and blk: {
                fill_state = prepareRowHorizSpanState(page, local.y, raster.epp.y, fill_layer.band_entry, fill_layer.band_max_h);
                if (!fill_state.valid) break :blk false;
                stroke_state = prepareRowHorizSpanState(page, local.y, raster.epp.y, stroke_layer.band_entry, stroke_layer.band_max_h);
                break :blk stroke_state.valid;
            };
            var fill_sat: SaturatedRowState = undefined;
            var stroke_sat: SaturatedRowState = undefined;
            const sat_state_ready = row_state_ready and blk: {
                fill_sat = prepareSaturatedRowState(page, local.y, raster.ppe.y, fill_layer.band_entry, fill_layer.band_max_v);
                if (!fill_sat.valid) break :blk false;
                stroke_sat = prepareSaturatedRowState(page, local.y, raster.ppe.y, stroke_layer.band_entry, stroke_layer.band_max_v);
                break :blk stroke_sat.valid;
            };

            // Inside-stroke composite fast path.
            //
            // For axis-aligned rounded-rect cards the body rows have a
            // predictable "stroke at edges, fill in middle" pattern:
            //   stroke_cov = 1   in [edge_left, edge_left + w)
            //   stroke_cov = 0   in the interior
            //   stroke_cov = 1   in [edge_right - w, edge_right)
            // With both fill_state and stroke_state h_uniform (their
            // H-band carries only vertical-line curves), the only X
            // transitions in coverage are at the path's left/right
            // extents — exactly the two stroke band edges. So a probe at
            // 8 evenly spaced columns can identify:
            //   * which probes sit in the interior (stroke = 0, fill = 1),
            //   * which probes sit in a stroke border (stroke = 1).
            // The range from the first interior probe to the last
            // interior probe is safe to fast-path with the fill paint;
            // the per-pixel loop handles the leftmost / rightmost stroke
            // borders (and the AA transition pixel) normally.
            //
            // Targets the six card body rows (each contributing ~20-80 ms
            // unthreaded at 4K). A 1-2 px stroke leaves 6/8 probes in the
            // interior, so the fast path covers ~75% of each row's pixels.
            // Gate on contribution counts (see the equivalent comment in
            // `renderSinglePathBatchLayer`). For an axis-aligned
            // rounded-rect card body row, the FILL has 2 contributing
            // curves (left + right verticals) and the STROKE has 4
            // (the four vertical edges of the inside-stroke band:
            // outer-left, inner-left, inner-right, outer-right). Glyph
            // / complex shape rows easily exceed both bounds, where the
            // probe-based pattern detection becomes unsafe.
            // The fill contrib bound (4) matches the relaxed bound in
            // `renderSinglePathBatchLayer` — a fractionally-positioned
            // axis-aligned rect can span two H-bands per pixel
            // footprint, doubling the contribution count even though
            // the underlying shape is still 2 vertical edges. The
            // stroke bound (8) is the same doubling applied to the
            // canonical 4-edge inside-stroke band. Glyph / complex
            // shape rows easily exceed both. The 8-probe pattern check
            // (all fills full + run_clean) still gates correctness.
            const fp_fill_contrib = if (row_state_ready) rowStateSignedContributionCount(fill_state) else 0;
            const fp_stroke_contrib = if (row_state_ready) rowStateSignedContributionCount(stroke_state) else 0;
            var fp_active = false;
            var fp_start: u32 = 0;
            var fp_end_excl: u32 = 0;
            no_fp: {
                if (!(row_state_ready and fp_fill_contrib <= 4 and fp_stroke_contrib <= 8 and raster.x1 > raster.x0 + 8)) break :no_fp;
                const ProbeFn = struct {
                    fn cov(
                        s_self: *Renderer,
                        p: *const PreparedAtlasPage,
                        loc: Vec2,
                        row_st: *const RowHorizState,
                        sat_st: *const SaturatedRowState,
                        r: PathRasterState,
                        layer: PreparedPathLayer,
                        sat_ready: bool,
                    ) f32 {
                        if (sat_ready) return s_self.applyCoverageTransfer(evalGlyphCoverageSaturatedRowH(
                            p,
                            loc.x,
                            loc.y,
                            row_st,
                            sat_st,
                            r.epp.x,
                            r.ppe.x,
                            r.ppe.y,
                            layer.band_entry,
                            layer.band_max_h,
                            layer.band_max_v,
                            layer.fill_rule,
                        ));
                        return s_self.applyCoverageTransfer(evalGlyphCoverageBandSpanRowH(
                            p,
                            loc.x,
                            loc.y,
                            row_st,
                            r.epp.x,
                            r.ppe.x,
                            r.ppe.y,
                            layer.band_entry,
                            layer.band_max_h,
                            layer.band_max_v,
                            layer.fill_rule,
                        ));
                    }
                };
                const n_probes: u32 = 8;
                var probe_col: [n_probes]u32 = undefined;
                var probe_loc: [n_probes]Vec2 = undefined;
                var probe_fill: [n_probes]f32 = undefined;
                var probe_stroke: [n_probes]f32 = undefined;
                // Inset probes by 2 pixels: at the bbox's first / last
                // pixel the fill itself has partial AA (rect's left /
                // right edge), so probing there fails `all_fills_full`
                // even on a clean axis-aligned card. The per-pixel loop
                // still handles those edge pixels correctly.
                const inset: u32 = 2;
                if (raster.x1 < raster.x0 + 2 * inset + n_probes) break :no_fp;
                const inset_start = raster.x0 + inset;
                const span = raster.x1 - raster.x0 - 1 - 2 * inset;
                inline for (0..n_probes) |i| {
                    const col_off: u32 = @intCast((@as(u64, span) * i) / (n_probes - 1));
                    probe_col[i] = inset_start + col_off;
                    probe_loc[i] = raster.inverse.applyPoint(.{
                        .x = @as(f32, @floatFromInt(probe_col[i])) + 0.5,
                        .y = @as(f32, @floatFromInt(row)) + 0.5,
                    });
                    probe_fill[i] = ProbeFn.cov(self, page, probe_loc[i], &fill_state, &fill_sat, raster, fill_layer, sat_state_ready);
                    probe_stroke[i] = ProbeFn.cov(self, page, probe_loc[i], &stroke_state, &stroke_sat, raster, stroke_layer, sat_state_ready);
                }
                const full_thresh: f32 = 1.0 - 1.0e-4;
                const empty_thresh: f32 = 1.0e-4;
                var all_fills_full = true;
                for (probe_fill) |f| {
                    if (f < full_thresh) {
                        all_fills_full = false;
                        break;
                    }
                }
                if (all_fills_full) {
                    // Find the first and last probes with stroke ~ 0.
                    var first_zero: ?u32 = null;
                    var last_zero: ?u32 = null;
                    for (probe_stroke, 0..) |s, i| {
                        if (s <= empty_thresh) {
                            if (first_zero == null) first_zero = @intCast(i);
                            last_zero = @intCast(i);
                        }
                    }
                    if (first_zero != null and last_zero != null and first_zero.? < last_zero.?) {
                        // Verify the run between first_zero and last_zero is
                        // all stroke≈0; if any probe in that interval has
                        // stroke>0, the pattern doesn't match the simple
                        // "stroke at edges" model and falling through to
                        // per-pixel is safer.
                        var run_clean = true;
                        var k: usize = first_zero.?;
                        while (k <= last_zero.?) : (k += 1) {
                            if (probe_stroke[k] > empty_thresh) {
                                run_clean = false;
                                break;
                            }
                        }
                        if (run_clean) {
                            fp_active = true;
                            fp_start = probe_col[first_zero.?];
                            fp_end_excl = probe_col[last_zero.?] + 1;
                        }
                    }
                }
            }

            // If a fast-path range was detected for this row, handle it
            // up front as a single batch (memset for solid+opaque, a
            // tight per-pixel blend loop for gradients/images). The
            // per-pixel loop below then `continue`s over those columns.
            if (fp_active) {
                const cov = self.applyCoverageTransfer(1.0);
                if (cov >= one_lsb_8bit) {
                    if (!self.tryFillRowSolidOpaque(row, fp_start, fp_end_excl, fill_program, tint)) {
                        var c: u32 = fp_start;
                        var local_at = raster.inverse.applyPoint(.{
                            .x = @as(f32, @floatFromInt(c)) + 0.5,
                            .y = @as(f32, @floatFromInt(row)) + 0.5,
                        });
                        while (c < fp_end_excl) : (advanceLocalPixel(&c, &local_at, raster.sample_dx)) {
                            const fill = fill_program.sample(local_at);
                            self.blendPremultipliedPixel(row, c, premultiplyCoverage(multiplyLinearColor(fill.color, tint), cov), false);
                        }
                    }
                }
            }

            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
                if (fp_active and col >= fp_start and col < fp_end_excl) continue;
                const fill_cov = if (sat_state_ready)
                    self.applyCoverageTransfer(evalGlyphCoverageSaturatedRowH(
                        page,
                        local.x,
                        local.y,
                        &fill_state,
                        &fill_sat,
                        raster.epp.x,
                        raster.ppe.x,
                        raster.ppe.y,
                        fill_layer.band_entry,
                        fill_layer.band_max_h,
                        fill_layer.band_max_v,
                        fill_layer.fill_rule,
                    ))
                else if (row_state_ready)
                    self.applyCoverageTransfer(evalGlyphCoverageBandSpanRowH(
                        page,
                        local.x,
                        local.y,
                        &fill_state,
                        raster.epp.x,
                        raster.ppe.x,
                        raster.ppe.y,
                        fill_layer.band_entry,
                        fill_layer.band_max_h,
                        fill_layer.band_max_v,
                        fill_layer.fill_rule,
                    ))
                else
                    self.scalarPathLayerCoverage(page, raster, fill_layer, local);
                if (fill_cov <= 0.0) continue;

                const stroke_cov = if (sat_state_ready)
                    self.applyCoverageTransfer(evalGlyphCoverageSaturatedRowH(
                        page,
                        local.x,
                        local.y,
                        &stroke_state,
                        &stroke_sat,
                        raster.epp.x,
                        raster.ppe.x,
                        raster.ppe.y,
                        stroke_layer.band_entry,
                        stroke_layer.band_max_h,
                        stroke_layer.band_max_v,
                        stroke_layer.fill_rule,
                    ))
                else if (row_state_ready)
                    self.applyCoverageTransfer(evalGlyphCoverageBandSpanRowH(
                        page,
                        local.x,
                        local.y,
                        &stroke_state,
                        raster.epp.x,
                        raster.ppe.x,
                        raster.ppe.y,
                        stroke_layer.band_entry,
                        stroke_layer.band_max_h,
                        stroke_layer.band_max_v,
                        stroke_layer.fill_rule,
                    ))
                else
                    self.scalarPathLayerCoverage(page, raster, stroke_layer, local);
                const border_cov = @min(fill_cov, stroke_cov);
                const interior_cov = @max(fill_cov - border_cov, 0.0);
                if (interior_cov <= 0.0 and border_cov <= 0.0) continue;

                var combined = [4]f32{ 0, 0, 0, 0 };
                if (interior_cov > 0.0) {
                    const fill = fill_program.sample(local);
                    combined = addColors(combined, premultiplyCoverage(multiplyLinearColor(fill.color, tint), interior_cov));
                }
                if (border_cov > 0.0) {
                    const stroke = stroke_program.sample(local);
                    combined = addColors(combined, premultiplyCoverage(multiplyLinearColor(stroke.color, tint), border_cov));
                }
                if (combined[3] < one_lsb_8bit) continue;
                self.blendPremultipliedPixel(row, col, combined, false);
            }
        }
    }

    fn renderCompositePathBatchLayers(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        union_bbox: snail.BBox,
        transform: Transform2D,
        tint: [4]f32,
        entry: *const LayerInfoEntry,
        record: *const PreparedPathRecord,
        allow_subpixel: bool,
    ) void {
        // Composite group: header at offset 0, then 6 texels per layer starting at offset 1.
        const layer_count = record.layer_count;
        const layers = entry.path_layers[record.layer_start..][0..layer_count];
        const raster = self.pathRasterState(union_bbox, transform, allow_subpixel) orelse return;
        const outline_composite = record.composite_mode == render_abi.composite_mode_fill_stroke_inside and layer_count >= 2;
        const programs = PathCompositePrograms{
            .outline = outline_composite,
            .fill = if (outline_composite) layers[0].paint else .{},
            .stroke = if (outline_composite) layers[1].paint else .{},
        };
        if (outline_composite and !raster.use_subpixel and layer_count == 2) {
            self.renderScalarInsideStrokeCompositePathBatchLayers(page, raster, tint, layers[0], layers[1], programs.fill, programs.stroke);
            return;
        }

        // For axis-aligned + RGB/BGR-subpixel-or-grayscale, pre-solve every
        // layer's H-axis curves once per row. Up to MAX_COMPOSITE_LAYERS is
        // bounded so the state array sits on the stack; rarely-exceeded.
        const axis_aligned = @abs(raster.sample_dx.y) < 1e-9;
        const subpixel_rgb = raster.use_subpixel and (self.subpixel_order == .rgb or self.subpixel_order == .bgr) and raster.subpixel_plan.step.y == 0.0;
        const grayscale_path = !raster.use_subpixel;
        const can_row_batch = axis_aligned and (subpixel_rgb or grayscale_path) and layer_count <= MAX_COMPOSITE_LAYERS;

        var row: u32 = raster.y0;
        while (row < raster.y1) : (row += 1) {
            var col: u32 = raster.x0;
            var local = raster.inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });

            var row_states_storage: [MAX_COMPOSITE_LAYERS]RowHorizState = undefined;
            var row_states_ready: bool = false;
            if (can_row_batch) {
                row_states_ready = true;
                for (layers, 0..) |layer, i| {
                    row_states_storage[i] = if (subpixel_rgb)
                        prepareRowHorizState(page, local.y, layer.band_entry, layer.band_max_h)
                    else
                        prepareRowHorizSpanState(page, local.y, raster.epp.y, layer.band_entry, layer.band_max_h);
                    if (!row_states_storage[i].valid) {
                        row_states_ready = false;
                        break;
                    }
                }
            }
            const row_states: ?[]const RowHorizState = if (row_states_ready) row_states_storage[0..layer_count] else null;

            var sat_states_storage: [MAX_COMPOSITE_LAYERS]SaturatedRowState = undefined;
            var sat_states_ready: bool = false;
            if (row_states_ready and grayscale_path) {
                sat_states_ready = true;
                for (layers, 0..) |layer, i| {
                    sat_states_storage[i] = prepareSaturatedRowState(page, local.y, raster.ppe.y, layer.band_entry, layer.band_max_v);
                    if (!sat_states_storage[i].valid) {
                        sat_states_ready = false;
                        break;
                    }
                }
            }
            const sat_states: ?[]const SaturatedRowState = if (sat_states_ready) sat_states_storage[0..layer_count] else null;

            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
                const pixel = self.sampleCompositePathPixel(page, raster, layers, programs, local, tint, row_states, sat_states);
                if (pixel.color[3] < one_lsb_8bit) continue;
                if (raster.use_subpixel) {
                    self.blendSubpixelPremultipliedPixel(row, col, pixel.color, pixel.blend, pixel.has_gradient);
                } else {
                    self.blendPremultipliedPixel(row, col, pixel.color, false);
                }
            }
        }
    }

    fn renderSinglePathBatchLayer(
        self: *Renderer,
        page: *const PreparedAtlasPage,
        union_bbox: snail.BBox,
        transform: Transform2D,
        tint: [4]f32,
        entry: *const LayerInfoEntry,
        record: *const PreparedPathRecord,
        allow_subpixel: bool,
    ) void {
        if (record.layer_count == 0) return;
        const layer = entry.path_layers[record.layer_start];
        const be = layer.band_entry;
        const raster = self.pathRasterState(union_bbox, transform, allow_subpixel) orelse return;
        const band_max_h = layer.band_max_h;
        const band_max_v = layer.band_max_v;
        const paint_program = layer.paint;

        const axis_aligned = @abs(raster.sample_dx.y) < 1e-9;
        const subpixel_rgb = raster.use_subpixel and (self.subpixel_order == .rgb or self.subpixel_order == .bgr) and raster.subpixel_plan.step.y == 0.0;
        // Subpixel path uses single-band evalGlyphCoverageSubpixel internally,
        // so the existing single-band row state applies. Non-subpixel path
        // uses the band-span variant and needs the span-aware state.
        const use_row_h_subpixel = axis_aligned and subpixel_rgb;
        const use_row_h_span = axis_aligned and !raster.use_subpixel;

        var row: u32 = raster.y0;
        while (row < raster.y1) : (row += 1) {
            var col: u32 = raster.x0;
            var local = raster.inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });

            var row_state: RowHorizState = undefined;
            const row_state_ready = blk: {
                if (use_row_h_subpixel) {
                    row_state = prepareRowHorizState(page, local.y, be, band_max_h);
                    break :blk row_state.valid;
                } else if (use_row_h_span) {
                    row_state = prepareRowHorizSpanState(page, local.y, raster.epp.y, be, band_max_h);
                    break :blk row_state.valid;
                }
                break :blk false;
            };
            var sat_state: SaturatedRowState = undefined;
            const sat_state_ready = use_row_h_span and row_state_ready and blk: {
                sat_state = prepareSaturatedRowState(page, local.y, raster.ppe.y, be, band_max_v);
                break :blk sat_state.valid;
            };

            // Row-uniformity fast path — same shape as the one in
            // `renderTransformedGlyphMaybeHinted`, see that comment for the
            // h_uniform/three-probe argument. Targets the banner background
            // fill (single-layer rect, ~30% of pass0 at 4K): interior rows
            // have only vertical-line H-band curves, all of which carry
            // zero signed contribution at any Y, so probing first/mid/last
            // is enough to confirm a fully-covered row and skip the
            // per-pixel coverage evaluation.
            // Gate on "≤ 2 H-band curves contribute signed coverage":
            // matches axis-aligned rect / rounded-rect interior rows
            // (their two vertical edges, opposite signs), excludes
            // glyph / curved-path rows (typically 5+ contributing
            // curves, where the 3-sample probe is unsafe — disjoint
            // strokes can land all three probes in solid sections while
            // skipping a hole between them). A naive
            // `rowStateHasNoSignedContribution` gate ("verticals don't
            // contribute") was inverted: vertical lines have a_root =
            // dy ≠ 0 so they DO produce signed crossings, which is
            // exactly what makes the rect's coverage well-defined.
            const fp_contrib = if (row_state_ready) rowStateSignedContributionCount(row_state) else 0;
            // Both gates required:
            //   state.count <= 3 excludes complex shapes (glyphs with
            //     6-30 curves per band, snail-illustration body rows
            //     with multiple disjoint inside regions);
            //   contributing <= 2 confirms the row has at most one
            //     "outside → inside" and one "inside → outside"
            //     transition along X — the rect/rounded-rect interior
            //     pattern the probes are designed for.
            // For axis-aligned rects at fractional scene-Y the band-span
            // walk and the `isBandSpanOwner` dedup still give
            // count == 2, so this gate covers both pan'd and stationary
            // rects.
            const fast_eligible = !raster.use_subpixel and row_state_ready and
                row_state.count <= 3 and fp_contrib <= 2;
            // Insert a 2-pixel safety margin: at the row's first / last
            // pixel the rect's vertical edge sits within the pixel
            // footprint, so AA gives partial coverage there. Probing one
            // pixel deeper guarantees deep-interior pixels for any
            // axis-aligned shape, while leaving the edge pixels for the
            // per-pixel loop to handle correctly.
            const inset: u32 = 2;
            var fp_start: u32 = raster.x1; // default: no fast-path range
            var fp_end_excl: u32 = raster.x1;
            if (fast_eligible and raster.x1 >= raster.x0 + 2 * inset + 2) {
                const probe_first: u32 = raster.x0 + inset;
                const probe_last: u32 = raster.x1 - 1 - inset;
                const probe_mid: u32 = probe_first + (probe_last - probe_first) / 2;
                const loc_pf = raster.inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(probe_first)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const loc_pm = raster.inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(probe_mid)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const loc_pl = raster.inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(probe_last)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const probe = struct {
                    fn cov(
                        p: anytype,
                        loc: Vec2,
                        row_st: *const RowHorizState,
                        sat_st: *const SaturatedRowState,
                        r: PathRasterState,
                        b_e: GlyphBandEntry,
                        bmh: i32,
                        bmv: i32,
                        fill_rule: FillRule,
                        sat_ready: bool,
                        row_ready: bool,
                    ) f32 {
                        if (sat_ready) return evalGlyphCoverageSaturatedRowH(p, loc.x, loc.y, row_st, sat_st, r.epp.x, r.ppe.x, r.ppe.y, b_e, bmh, bmv, fill_rule);
                        if (row_ready) return evalGlyphCoverageBandSpanRowH(p, loc.x, loc.y, row_st, r.epp.x, r.ppe.x, r.ppe.y, b_e, bmh, bmv, fill_rule);
                        return evalGlyphCoverageBandSpan(p, loc.x, loc.y, r.epp.x, r.epp.y, r.ppe.x, r.ppe.y, b_e, bmh, bmv, fill_rule);
                    }
                }.cov;
                const cov_first = probe(page, loc_pf, &row_state, &sat_state, raster, be, band_max_h, band_max_v, layer.fill_rule, sat_state_ready, row_state_ready);
                const cov_mid = probe(page, loc_pm, &row_state, &sat_state, raster, be, band_max_h, band_max_v, layer.fill_rule, sat_state_ready, row_state_ready);
                const cov_last = probe(page, loc_pl, &row_state, &sat_state, raster, be, band_max_h, band_max_v, layer.fill_rule, sat_state_ready, row_state_ready);
                const full_thresh: f32 = 1.0 - 1.0e-4;
                if (cov_first >= full_thresh and cov_mid >= full_thresh and cov_last >= full_thresh) {
                    const cov = self.applyCoverageTransfer(1.0);
                    if (cov >= one_lsb_8bit) {
                        fp_start = probe_first;
                        fp_end_excl = probe_last + 1;
                        if (self.tryFillRowSolidOpaque(row, fp_start, fp_end_excl, paint_program, tint)) {
                            // Fast-path-of-the-fast-path: solid + opaque +
                            // cov == 1 collapses the blend to a u32 memset.
                        } else {
                            var c: u32 = fp_start;
                            var local_at = loc_pf;
                            while (c < fp_end_excl) : (advanceLocalPixel(&c, &local_at, raster.sample_dx)) {
                                var paint = paint_program.sample(local_at);
                                paint.color = multiplyLinearColor(paint.color, tint);
                                self.blendPremultipliedPixel(row, c, premultiplyCoverage(paint.color, cov), paint.apply_dither);
                            }
                        }
                    }
                }
            }

            while (col < raster.x1) : (advanceLocalPixel(&col, &local, raster.sample_dx)) {
                if (col >= fp_start and col < fp_end_excl) continue;
                if (!raster.use_subpixel) {
                    const raw_cov = if (sat_state_ready)
                        evalGlyphCoverageSaturatedRowH(page, local.x, local.y, &row_state, &sat_state, raster.epp.x, raster.ppe.x, raster.ppe.y, be, band_max_h, band_max_v, layer.fill_rule)
                    else if (row_state_ready)
                        evalGlyphCoverageBandSpanRowH(page, local.x, local.y, &row_state, raster.epp.x, raster.ppe.x, raster.ppe.y, be, band_max_h, band_max_v, layer.fill_rule)
                    else
                        evalGlyphCoverageBandSpan(page, local.x, local.y, raster.epp.x, raster.epp.y, raster.ppe.x, raster.ppe.y, be, band_max_h, band_max_v, layer.fill_rule);
                    const cov = self.applyCoverageTransfer(raw_cov);
                    if (cov < one_lsb_8bit) continue;
                    var paint = paint_program.sample(local);
                    paint.color = multiplyLinearColor(paint.color, tint);
                    self.blendPremultipliedPixel(row, col, premultiplyCoverage(paint.color, cov), paint.apply_dither);
                } else {
                    const raw_cov = if (row_state_ready)
                        evalGlyphCoverageSubpixelRowH(page, local.x, local.y, &row_state, raster.subpixel_plan, be, band_max_v, layer.fill_rule)
                    else
                        evalGlyphCoverageSubpixel(page, local, raster.subpixel_plan, be, band_max_h, band_max_v, layer.fill_rule);
                    const cov = self.applySubpixelCoverageTransfer(raw_cov);
                    if (max3(cov.rgb) < one_lsb_8bit) continue;
                    var paint = paint_program.sample(local);
                    paint.color = multiplyLinearColor(paint.color, tint);
                    self.blendSubpixelPremultipliedPixel(
                        row,
                        col,
                        premultiplySubpixelCoverage(paint.color, cov.rgb, cov.alpha),
                        subpixelBlendCoverage(paint.color, cov.rgb),
                        paint.apply_dither,
                    );
                }
            }
        }
    }

    fn renderTransformedGlyph(
        self: *Renderer,
        page: anytype,
        bbox: snail.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        allow_subpixel: bool,
    ) void {
        self.renderTransformedGlyphMaybeHinted(page, bbox, be, transform, color, allow_subpixel, null);
    }

    /// Fit the immutable analysis once for this draw, then render the shared
    /// base glyph through caller-owned transient knots.
    fn renderTransformedAutohintGlyph(
        self: *Renderer,
        page: anytype,
        bbox: snail.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        record: autohint_record.DecodedRecord,
        policy: autohint_policy.AutohintPolicy,
        allow_subpixel: bool,
    ) void {
        const scale = Vec2.new(
            @sqrt(transform.xx * transform.xx + transform.yx * transform.yx),
            @sqrt(transform.xy * transform.xy + transform.yy * transform.yy),
        );
        var x_out: [autohint_warp.max_knots]autohint_warp.Knot = undefined;
        var y_out: [autohint_warp.max_knots]autohint_warp.Knot = undefined;
        const fitted = autohint_warp.fitGlyph(record.glyph, record.font, policy, scale, &x_out, &y_out);
        self.renderTransformedGlyphMaybeHinted(page, bbox, be, transform, color, allow_subpixel, .{ .x = fitted.x, .y = fitted.y });
    }

    fn renderTransformedGlyphMaybeHinted(
        self: *Renderer,
        page: anytype,
        bbox: snail.BBox,
        be: GlyphBandEntry,
        transform: Transform2D,
        color: [4]f32,
        allow_subpixel: bool,
        warp: ?AutohintWarp,
    ) void {
        const inverse = inverseTransform(transform) orelse return;
        var bounds = transformedGlyphBounds(bbox, transform);
        expandBoundsForCoverageSupport(&bounds, self.subpixel_order, allow_subpixel);
        if (warp != null) expandDeviceBounds(&bounds, 2.0);

        const x_range = clippedPixelAxis(bounds.min.x, bounds.max.x, self.col_clip_min, self.col_clip_max) orelse return;
        const y_range = clippedPixelAxis(bounds.min.y, bounds.max.y, self.row_clip_min, self.row_clip_max) orelse return;

        const epp = glyphEdgePixelsPerPixel(inverse);
        const ppe = Vec2.new(1.0 / epp.x, 1.0 / epp.y);
        const band_max_h: i32 = @as(i32, @intCast(be.h_band_count)) - 1;
        const band_max_v: i32 = @as(i32, @intCast(be.v_band_count)) - 1;
        const sample_dx = Vec2.new(inverse.xx, inverse.yx);
        const sample_dy = Vec2.new(inverse.xy, inverse.yy);
        const subpixel_plan = SubpixelCoveragePlan.init(sample_dx, sample_dy, self.subpixel_order);

        // Row-batched H-axis fast path. Applies when (a) the transform is
        // axis-aligned (sample_dx.y == 0 so em_y is row-constant), (b) the
        // atlas page is prepared, and (c) no draw-time warp is active. For
        // RGB/BGR subpixel we additionally
        // require plan.step.y == 0 so all 7 subpixel samples share em_y too;
        // the non-subpixel path needs only the row-constant em_y. When any
        // condition fails we fall back to per-pixel evaluation.
        const PageType = switch (@typeInfo(@TypeOf(page))) {
            .pointer => |ptr| ptr.child,
            else => @TypeOf(page),
        };
        const prepared_page = comptime @hasField(PageType, "axis_curves");
        const axis_aligned = @abs(sample_dx.y) < 1e-9;
        const subpixel_rgb = allow_subpixel and (self.subpixel_order == .rgb or self.subpixel_order == .bgr) and subpixel_plan.step.y == 0.0;
        const grayscale_path = !allow_subpixel or self.subpixel_order == .none;
        const use_row_h_subpixel = prepared_page and axis_aligned and subpixel_rgb and warp == null;
        const use_row_h_grayscale = prepared_page and axis_aligned and grayscale_path and warp == null;
        const use_row_h = use_row_h_subpixel or use_row_h_grayscale;

        var row = y_range.min;
        while (row < y_range.max) : (row += 1) {
            var col = x_range.min;
            var display_local = inverse.applyPoint(.{
                .x = @as(f32, @floatFromInt(col)) + 0.5,
                .y = @as(f32, @floatFromInt(row)) + 0.5,
            });

            var row_state: RowHorizState = undefined;
            const row_state_ready = use_row_h and blk: {
                row_state = prepareRowHorizState(page, display_local.y, be, band_max_h);
                break :blk row_state.valid;
            };

            // Row-uniformity fast path.
            //
            // Slug coverage = resolveCoverage(H, V). When every curve in
            // this row's H-band has zero signed contribution at this row
            // (vertical lines, or curves whose root-hull misses the row
            // entirely), the H half is constant across the row's X. Any
            // remaining per-pixel variation comes only from the V-band —
            // which for axis-aligned fills changes only at the path's
            // left/right extent. So three probes at the row's first /
            // middle / last pixel suffice:
            //
            //   * all ~1.0  → row's interior is fully covered. Fill with
            //                 the premultiplied color, skipping the
            //                 ~30 ns/px of curve solves the per-pixel
            //                 loop would otherwise spend.
            //   * all ~0.0  → row is entirely outside the path. Skip it.
            //   * mixed     → fall through to the per-pixel loop.
            //
            // The `h_uniform` gate is what makes three samples safe:
            // without it, a glyph with holes (O, P, R) could land all
            // three probes on "inside" pixels with the hole between them
            // staying uncovered. With the H-band carrying no per-X
            // variation, that ambiguity can't happen — any X-variation
            // in coverage comes from the V-band, which for the targets
            // of this fast path (big axis-aligned fills) has at most one
            // left→inside and one inside→right transition across the
            // row's X-extent.
            //
            // Targets the seven big offenders on the banner: background
            // fill + six card fills are axis-aligned rect / rounded-rect
            // paths whose interior rows have only vertical-line curves
            // in the H-band — those contribute nothing to row-level H.
            const h_uniform = row_state_ready and rowStateHasNoSignedContribution(row_state);
            const fast_row_eligible =
                grayscale_path and
                h_uniform and
                warp == null and
                x_range.max > x_range.min + 2;
            if (fast_row_eligible) {
                const px_first = x_range.min;
                const px_last = x_range.max - 1;
                const px_mid: u32 = px_first + (px_last - px_first) / 2;
                const loc_first = display_local;
                const loc_mid = inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(px_mid)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const loc_last = inverse.applyPoint(.{
                    .x = @as(f32, @floatFromInt(px_last)) + 0.5,
                    .y = @as(f32, @floatFromInt(row)) + 0.5,
                });
                const cov_first = evalGlyphCoverageRowH(page, loc_first.x, loc_first.y, &row_state, ppe.x, ppe.y, be, band_max_h, band_max_v, .non_zero);
                const cov_mid = evalGlyphCoverageRowH(page, loc_mid.x, loc_mid.y, &row_state, ppe.x, ppe.y, be, band_max_h, band_max_v, .non_zero);
                const cov_last = evalGlyphCoverageRowH(page, loc_last.x, loc_last.y, &row_state, ppe.x, ppe.y, be, band_max_h, band_max_v, .non_zero);
                // Only the all-full branch is safe under `h_uniform`
                // alone. An all-empty branch would mis-classify rows
                // whose three probes coincidentally land in
                // outside-stroke gaps (e.g. between the verticals of
                // "H" or "N") even though pixels between the probes
                // sit inside a stroke. The per-pixel loop's existing
                // `cov < one_lsb_8bit` check still skips empty pixels
                // individually, so dropping the row-skip costs nothing
                // beyond a missed micro-optimization.
                const full_thresh: f32 = 1.0 - 1.0e-4;
                if (cov_first >= full_thresh and cov_mid >= full_thresh and cov_last >= full_thresh) {
                    const cov = self.applyCoverageTransfer(1.0);
                    if (cov >= one_lsb_8bit) {
                        const premul = premultiplyCoverage(color, cov);
                        var c: u32 = px_first;
                        while (c <= px_last) : (c += 1) {
                            self.blendPremultipliedPixel(row, c, premul, false);
                        }
                    }
                    continue;
                }
            }

            while (col < x_range.max) : (advanceLocalPixel(&col, &display_local, sample_dx)) {
                // Warp the sample coordinate back into base-outline space and
                // rescale the AA footprint by the local inverse slope (ppe_base
                // = ppe_screen / inv_slope). Identity when there's no warp.
                var sample = display_local;
                var sppe = ppe;
                var warp_slope = Vec2.new(1.0, 1.0);
                if (warp) |w| {
                    const sx = autohint_warp.inverseWarp(w.x, display_local.x);
                    const sy = autohint_warp.inverseWarp(w.y, display_local.y);
                    sample = .{ .x = sx.base, .y = sy.base };
                    sppe = .{ .x = ppe.x / sx.inv_slope, .y = ppe.y / sy.inv_slope };
                    warp_slope = .{ .x = sx.inv_slope, .y = sy.inv_slope };
                }
                if (!allow_subpixel or self.subpixel_order == .none) {
                    // Glyphs from fonts use non-zero winding by convention.
                    const raw_cov = if (row_state_ready)
                        evalGlyphCoverageRowH(page, sample.x, sample.y, &row_state, sppe.x, sppe.y, be, band_max_h, band_max_v, .non_zero)
                    else
                        evalGlyphCoverage(page, sample.x, sample.y, sppe.x, sppe.y, be, band_max_h, band_max_v, .non_zero);
                    const cov = self.applyCoverageTransfer(raw_cov);
                    if (cov < one_lsb_8bit) continue;
                    self.blendPremultipliedPixel(row, col, premultiplyCoverage(color, cov), false);
                } else if (row_state_ready) {
                    const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixelRowH(
                        page,
                        display_local.x,
                        display_local.y,
                        &row_state,
                        subpixel_plan,
                        be,
                        band_max_v,
                        .non_zero,
                    ));
                    if (max3(cov.rgb) < one_lsb_8bit) continue;
                    self.blendSubpixelPixel(row, col, color, cov.rgb, cov.alpha);
                } else {
                    // Subpixel under a warp linearizes around the pixel
                    // center: evaluate the 7 lanes from the warped sample
                    // with the lane step and footprint scaled by the local
                    // inverse-warp slope per axis — the same approximation
                    // the GPU fragment applies to its derivatives
                    // (autohint_subpixel_frag.slang). Identity when no
                    // warp is active (`sample` == `display_local`,
                    // slope 1).
                    var plan = subpixel_plan;
                    if (warp != null) {
                        plan.step = .{ .x = plan.step.x * warp_slope.x, .y = plan.step.y * warp_slope.y };
                        plan.ppe = .{ .x = plan.ppe.x / warp_slope.x, .y = plan.ppe.y / warp_slope.y };
                    }
                    const cov = self.applySubpixelCoverageTransfer(evalGlyphCoverageSubpixel(
                        page,
                        sample,
                        plan,
                        be,
                        band_max_h,
                        band_max_v,
                        .non_zero,
                    ));
                    if (max3(cov.rgb) < one_lsb_8bit) continue;
                    self.blendSubpixelPixel(row, col, color, cov.rgb, cov.alpha);
                }
            }
        }
    }

    /// Helper for the row-uniformity fast paths: returns true when no
    /// curve in this row's H-band contributes signed X-axis coverage at
    /// the row's Y (e.g. all entries are vertical lines, or all curves
    /// in the band miss the row entirely). When true, per-pixel
    /// variation in the row's coverage can come only from the V-band,
    /// which for axis-aligned fills changes only at the path's left /
    /// right extents — so a small set of probes is enough to confirm
    /// uniformity. See `renderTransformedGlyphMaybeHinted` for the call
    /// site (the path-namespace renderers use the contribution-count
    /// helper below instead, since axis-aligned rects DO have signed
    /// vertical-edge contributions).
    inline fn rowStateHasNoSignedContribution(state: RowHorizState) bool {
        var c: usize = 0;
        while (c < state.count) : (c += 1) {
            const e = state.curves[c];
            if (e.sign[0] != 0.0 or e.sign[1] != 0.0 or e.sign[2] != 0.0) return false;
        }
        return true;
    }

    /// Helper for the path-namespace row-uniformity fast paths: counts
    /// curves in this row's H-band that contribute *any* signed X-axis
    /// crossing. An axis-aligned rect interior row has exactly 2 (its
    /// two vertical edges, sloping in opposite directions); a
    /// rounded-rect interior row between corners has the same; a corner
    /// row adds the corner curves; a glyph row easily has 5+ contributing
    /// curves. Gating on `count <= 2` lets through the axis-aligned
    /// rect / rounded-rect shapes the fast path targets while excluding
    /// the complex / glyph paths whose interior pixels can't be inferred
    /// from a small probe.
    inline fn rowStateSignedContributionCount(state: RowHorizState) usize {
        var n: usize = 0;
        var c: usize = 0;
        while (c < state.count) : (c += 1) {
            const e = state.curves[c];
            if (e.sign[0] != 0.0 or e.sign[1] != 0.0 or e.sign[2] != 0.0) n += 1;
        }
        return n;
    }

    /// Fill row pixels `[col_start, col_end_excl)` with `paint`'s solid
    /// color via `@memset`, IF the inputs collapse to "write the same
    /// 4 bytes everywhere":
    ///   * `paint.kind == .solid` (paint sample is constant across X)
    ///   * `linear_resolve_active == false` (the resolve pass writes
    ///     fp16, not u8 — the memset would corrupt it)
    ///   * the source after tint multiply has alpha ≈ 1 (opaque, so
    ///     blendPremultipliedPixel's fast path is just "write src")
    /// Returns true when the memset ran; false when the caller must
    /// fall back to per-pixel blending (gradient/image paints; partial
    /// alpha; linear-resolve mode).
    ///
    /// Targets the demo's banner background + card fills, which are
    /// the dominant cost in `pass0` even after the row-uniformity
    /// fast path skipped their coverage solves: each remaining pixel
    /// was still doing a linear→sRGB conversion + byte writes. This
    /// collapses the loop to a u32 memset — same shape as the
    /// framebuffer clear, which runs at memory bandwidth.
    fn tryFillRowSolidOpaque(
        self: *Renderer,
        row: u32,
        col_start: u32,
        col_end_excl: u32,
        paint: PreparedPathPaint,
        tint: [4]f32,
    ) bool {
        if (paint.kind != .solid) return false;
        if (self.linear_resolve_active) return false;
        const linear = multiplyLinearColor(paint.color0, tint);
        if (linear[3] < 1.0 - 1.0e-4) return false;
        switch (self.format) {
            inline else => |fmt| {
                // The u32 memset only applies to 4-byte formats (rgba8/bgra8/
                // rgb10a2, whose packed pixel is one word). Others fall back to
                // the per-pixel path.
                if (comptime fmt.bytesPerPixel() != 4) return false;
                const bytes = blend_mod.opaqueBytesForTarget(fmt, self.blendTarget(), .{ linear[0], linear[1], linear[2] });
                const word: u32 = @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16) | (@as(u32, bytes[3]) << 24);
                const offset = @as(usize, row) * self.stride + @as(usize, col_start) * 4;
                const pixel_count: usize = col_end_excl - col_start;
                const dst = self.pixels[offset..][0 .. pixel_count * 4];
                if (@intFromPtr(dst.ptr) % @alignOf(u32) == 0) {
                    const dst_u32: [*]u32 = @ptrCast(@alignCast(dst.ptr));
                    @memset(dst_u32[0..pixel_count], word);
                } else {
                    for (0..pixel_count) |i| @memcpy(dst[i * 4 ..][0..4], &bytes);
                }
                return true;
            },
        }
    }

    inline fn blendTarget(self: *Renderer) blend_mod.Target {
        return .{
            .pixels = self.pixels.ptr,
            .stride = self.stride,
            .height = self.height,
            .target_encoding = self.target_encoding,
            .target_resolve = self.target_resolve,
        };
    }

    // The three pixel-write wrappers dispatch on the runtime format once here;
    // `inline else` gives each format a comptime-specialized (branch-free)
    // blend body. The format is constant per draw, so the branch predicts.
    inline fn blendPremultipliedPixel(self: *Renderer, row: u32, col: u32, src: [4]f32, apply_dither: bool) void {
        switch (self.format) {
            inline else => |fmt| blend_mod.blendPremultipliedPixel(fmt, self.blendTarget(), row, col, src, apply_dither),
        }
    }

    inline fn blendSubpixelPremultipliedPixel(self: *Renderer, row: u32, col: u32, src: [4]f32, src_blend: [3]f32, apply_dither: bool) void {
        switch (self.format) {
            inline else => |fmt| blend_mod.blendSubpixelPremultipliedPixel(fmt, self.blendTarget(), row, col, src, src_blend, apply_dither),
        }
    }

    /// Per-channel subpixel blend (equivalent to GPU dual-source blending).
    /// Each RGB channel has its own coverage, so the destination attenuation
    /// is per-channel: out.r = src.r * alpha_r + dst.r * (1 - alpha_r), etc.
    inline fn blendSubpixelPixel(self: *Renderer, row: u32, col: u32, color: [4]f32, cov: [3]f32, alpha_cov: f32) void {
        switch (self.format) {
            inline else => |fmt| blend_mod.blendSubpixelPixel(fmt, self.blendTarget(), row, col, color, cov, alpha_cov),
        }
    }
};

/// Package bridge used by the high-level draw entry. It deliberately lives on
/// the unexported implementation module so `Renderer` does not expose a method
/// whose prepared-resource argument callers cannot construct.
pub fn drawPreparedBatch(
    renderer: *Renderer,
    prepared: *const PreparedResources,
    instances: []const vertex.Instance,
    state: render_state.DrawState,
    texture_layer_base: u32,
    thread_pool: ?*ThreadPool,
) Renderer.DrawBatchError!void {
    return renderer.drawPreparedBatch(prepared, instances, state, texture_layer_base, thread_pool);
}

const testing = std.testing;

test "pixel bounds saturate extreme values before integer conversion" {
    try testing.expectEqual(
        PixelAxisRange{ .min = 3, .max = 9 },
        clippedPixelAxis(-std.math.inf(f32), std.math.inf(f32), 3, 9).?,
    );
    try testing.expectEqual(@as(?PixelAxisRange, null), clippedPixelAxis(1.0e30, std.math.inf(f32), 3, 9));
    try testing.expectEqual(@as(?PixelAxisRange, null), clippedPixelAxis(std.math.nan(f32), 8, 3, 9));
    try testing.expectEqual(std.math.maxInt(u32), pixelExtent(-std.math.inf(f32), std.math.inf(f32)));
}

test "renderer validates slice length and format-specific stride" {
    var pixels: [8]u8 = .{0} ** 8;
    try testing.expectError(error.InvalidStride, Renderer.init(&pixels, 4, 2, 3, .r8_unorm));
    try testing.expectError(error.InvalidBuffer, Renderer.init(pixels[0..7], 4, 2, 4, .r8_unorm));

    var renderer = try Renderer.init(&pixels, 4, 2, 4, .r8_unorm);
    var prepared = PreparedResources{ .allocator = testing.allocator };
    const wf: f32 = 4;
    const hf: f32 = 2;
    var state = render_state.DrawState{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .surface = .{
            .pixel_width = 4,
            .pixel_height = 2,
            .encoding = .linear,
            .format = .rgba8_unorm,
        },
    };
    try testing.expectError(error.InvalidTargetSurface, renderer.drawPreparedBatch(&prepared, &.{}, state, 0, null));
    state.surface.format = .r8_unorm;
    try renderer.drawPreparedBatch(&prepared, &.{}, state, 0, null);
    try testing.expectEqual(render_state.PixelFormat.r8_unorm, renderer.format);
}

test "renderer rejects corrupted internal clip bounds before writes" {
    var pixels: [4]u8 = .{ 1, 2, 3, 4 };
    var renderer = try Renderer.init(&pixels, 1, 1, 4, .rgba8_unorm);
    renderer.row_clip_max = 2;
    const surface = render_state.TargetSurface{
        .pixel_width = 1,
        .pixel_height = 1,
        .encoding = .linear,
    };
    try testing.expectError(error.InvalidTargetSurface, renderer.validateTarget(surface));
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, &pixels);
}

test "drawBatch rejects texture layer addition overflow before mutation" {
    var pixels: [4]u8 = .{0} ** 4;
    var renderer = try Renderer.init(&pixels, 1, 1, 4, .rgba8_unorm);
    var prepared = PreparedResources{ .allocator = testing.allocator };
    var instance = std.mem.zeroes(vertex.Instance);
    instance.xform = .{ 1, 0, 0, 1 };
    instance.glyph[1] = @as(u32, 1) << 8;
    const state = render_state.DrawState{
        .mvp = snail.Mat4.identity,
        .surface = .{ .pixel_width = 1, .pixel_height = 1, .encoding = .linear },
    };
    try testing.expectError(
        error.TextureLayerOverflow,
        renderer.drawPreparedBatch(&prepared, &.{instance}, state, std.math.maxInt(u32), null),
    );
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &pixels);
}

test "drawBatch rejects malformed instances before mutation" {
    var pixels: [4]u8 = .{ 11, 22, 33, 44 };
    var renderer = try Renderer.init(&pixels, 1, 1, 4, .rgba8_unorm);
    var prepared = PreparedResources{ .allocator = testing.allocator };
    const instance = std.mem.zeroes(vertex.Instance);
    const state = render_state.DrawState{
        .mvp = snail.Mat4.identity,
        .surface = .{ .pixel_width = 1, .pixel_height = 1, .encoding = .linear },
    };
    try testing.expectError(
        error.InvalidInstance,
        renderer.drawPreparedBatch(&prepared, &.{instance}, state, 0, null),
    );
    try testing.expectEqualSlices(u8, &.{ 11, 22, 33, 44 }, &pixels);
}

test "drawBatch skips special instances whose info coordinates fall outside the layer-info slab" {
    var pixels: [4]u8 = .{ 11, 22, 33, 44 };
    var renderer = try Renderer.init(&pixels, 1, 1, 4, .rgba8_unorm);

    // A minimal 2x1 layer-info slab with no valid records, plus one empty
    // atlas page so the hinted-text path passes its page lookup before
    // fetching the header texel.
    const slab = [_]f32{0} ** 8;
    var infos = [_]LayerInfoEntry{.{ .data = &slab, .width = 2, .height = 1 }};
    var pages = [_]?PreparedAtlasPage{
        try PreparedAtlasPage.initFromView(testing.allocator, .{
            .curve_data = &[_]u16{},
            .band_data = &[_]u16{},
            .curve_width = @as(u32, 0),
            .curve_height = @as(u32, 0),
            .band_width = @as(u32, 0),
            .band_height = @as(u32, 0),
        }),
    };
    defer if (pages[0]) |*page| page.deinit(testing.allocator);
    var prepared = PreparedResources{
        .allocator = testing.allocator,
        .atlas_pages = &pages,
        .layer_infos = &infos,
        .layer_info_count = 1,
    };
    const state = render_state.DrawState{
        .mvp = snail.Mat4.identity,
        .surface = .{ .pixel_width = 1, .pixel_height = 1, .encoding = .linear },
    };

    // info_x = 65535 points far outside the 2x1 slab; both special kinds
    // must skip the instance rather than read out of bounds.
    var instance = std.mem.zeroes(vertex.Instance);
    instance.xform = .{ 1, 0, 0, 1 };
    instance.glyph[0] = @as(u32, 65535); // info_x = 65535, info_y = 0
    instance.glyph[1] = testSpecialGlyphWord(1, .path);
    try renderer.drawPreparedBatch(&prepared, &.{instance}, state, 0, null);

    instance.glyph[1] = testSpecialGlyphWord(1, .tt_hinted_text);
    try renderer.drawPreparedBatch(&prepared, &.{instance}, state, 0, null);

    try testing.expectEqualSlices(u8, &.{ 11, 22, 33, 44 }, &pixels);
}

fn testSpecialGlyphWord(layer_count: u16, kind: render_abi.SpecialLayerKind) u32 {
    // Same packing as the private abi special-word constructor, which is not
    // re-exported through render.records: count | kind << 16 | marker bit 31.
    return @as(u32, layer_count) | (@as(u32, @intFromEnum(kind)) << 16) | (@as(u32, 1) << 31);
}

test "drawBatch skips hinted-text instances with non-canonical header floats" {
    var pixels: [4]u8 = .{ 11, 22, 33, 44 };
    var renderer = try Renderer.init(&pixels, 1, 1, 4, .rgba8_unorm);

    var slab = [_]f32{0} ** 8;
    var infos = [_]LayerInfoEntry{.{ .data = &slab, .width = 2, .height = 1 }};
    var pages = [_]?PreparedAtlasPage{
        try PreparedAtlasPage.initFromView(testing.allocator, .{
            .curve_data = &[_]u16{},
            .band_data = &[_]u16{},
            .curve_width = @as(u32, 0),
            .curve_height = @as(u32, 0),
            .band_width = @as(u32, 0),
            .band_height = @as(u32, 0),
        }),
    };
    defer if (pages[0]) |*page| page.deinit(testing.allocator);
    var prepared = PreparedResources{
        .allocator = testing.allocator,
        .atlas_pages = &pages,
        .layer_infos = &infos,
        .layer_info_count = 1,
    };
    const state = render_state.DrawState{
        .mvp = snail.Mat4.identity,
        .surface = .{ .pixel_width = 1, .pixel_height = 1, .encoding = .linear },
    };

    var instance = std.mem.zeroes(vertex.Instance);
    instance.xform = .{ 1, 0, 0, 1 };
    instance.glyph[0] = 0; // info_x = 0, info_y = 0: inside the slab
    instance.glyph[1] = testSpecialGlyphWord(1, .tt_hinted_text);

    // NaN, negative, fractional, and out-of-range glyph coordinates must all
    // skip the instance rather than trap in float→int conversion.
    for ([_]f32{ std.math.nan(f32), -1, 1.5, 65536 }) |bad_x| {
        slab[0] = bad_x;
        try renderer.drawPreparedBatch(&prepared, &.{instance}, state, 0, null);
    }
    // A non-finite band transform word bails out the same way.
    slab[0] = 0;
    slab[4] = std.math.inf(f32);
    try renderer.drawPreparedBatch(&prepared, &.{instance}, state, 0, null);

    try testing.expectEqualSlices(u8, &.{ 11, 22, 33, 44 }, &pixels);
}

test "linear resolve clear honors target pixel format" {
    var pixels: [2]u8 = .{ 0, 0 };
    var renderer = try Renderer.init(&pixels, 2, 1, 2, .a8_unorm);
    const surface = render_state.TargetSurface{
        .pixel_width = 2,
        .pixel_height = 1,
        .encoding = .srgb_pixels_on_linear_attachment,
        .format = .a8_unorm,
    };
    const restore = try renderer.beginLinearResolve(surface, .{ .backdrop = .{ .clear = .{ 1, 0, 0, 0.5 } } });
    defer renderer.endLinearResolve(restore) catch unreachable;
    try testing.expectApproxEqAbs(@as(f32, 0.5), @as(f32, @floatFromInt(pixels[0])) / 255.0, 1.0 / 255.0);
    try testing.expectEqual(pixels[0], pixels[1]);
    try testing.expectError(error.LinearResolveAlreadyActive, renderer.beginLinearResolve(surface, .{}));
}

test "linear resolve rejects an unsupported intermediate format" {
    var pixels: [4]u8 = .{0} ** 4;
    var renderer = try Renderer.init(&pixels, 1, 1, 4, .rgba8_unorm);
    const surface = render_state.TargetSurface{
        .pixel_width = 1,
        .pixel_height = 1,
        .encoding = .srgb_pixels_on_linear_attachment,
    };
    try testing.expectError(error.UnsupportedResolve, renderer.beginLinearResolve(surface, .{ .intermediate_format = .rgba32f }));
}

test "linear resolve rejects an invalid clear before state or pixel mutation" {
    var pixels = [_]u8{0x5a} ** 4;
    var renderer = try Renderer.init(&pixels, 1, 1, 4, .rgba8_unorm);
    const surface = render_state.TargetSurface{
        .pixel_width = 1,
        .pixel_height = 1,
        .encoding = .srgb_pixels_on_linear_attachment,
    };
    try testing.expectError(error.InvalidBackdrop, renderer.beginLinearResolve(surface, .{
        .backdrop = .{ .clear = .{ std.math.nan(f32), 0, 0, 1 } },
    }));
    try testing.expect(!renderer.linear_resolve_active);
    try testing.expectEqualSlices(u8, &.{ 0x5a, 0x5a, 0x5a, 0x5a }, &pixels);
}

test "linear resolve end rejects cross-renderer, stale, and reused tokens" {
    var pixels_a: [4]u8 = .{0} ** 4;
    var pixels_b: [4]u8 = .{0} ** 4;
    var renderer = try Renderer.init(&pixels_a, 1, 1, 4, .rgba8_unorm);
    var other = try Renderer.init(&pixels_b, 1, 1, 4, .rgba8_unorm);
    const surface = render_state.TargetSurface{
        .pixel_width = 1,
        .pixel_height = 1,
        .encoding = .srgb_pixels_on_linear_attachment,
    };

    const token = try renderer.beginLinearResolve(surface, .{});
    const other_token = try other.beginLinearResolve(surface, .{});
    try testing.expectError(error.InvalidLinearResolveToken, renderer.endLinearResolve(other_token));
    try renderer.endLinearResolve(token);
    try testing.expectError(error.LinearResolveNotActive, renderer.endLinearResolve(token));
    try other.endLinearResolve(other_token);

    const next_token = try renderer.beginLinearResolve(surface, .{});
    try testing.expectError(error.InvalidLinearResolveToken, renderer.endLinearResolve(token));
    try renderer.endLinearResolve(next_token);
}

test "reinitBuffer rejects an active linear resolve without mutation" {
    var pixels: [4]u8 = .{0} ** 4;
    var replacement: [16]u8 = .{0} ** 16;
    var renderer = try Renderer.init(&pixels, 1, 1, 4, .rgba8_unorm);
    const surface = render_state.TargetSurface{
        .pixel_width = 1,
        .pixel_height = 1,
        .encoding = .srgb_pixels_on_linear_attachment,
    };
    const token = try renderer.beginLinearResolve(surface, .{});
    try testing.expectError(error.LinearResolveActive, renderer.reinitBuffer(&replacement, 2, 2, 8, .rgba8_unorm));
    try testing.expectEqual(@as(u32, 1), renderer.width);
    try testing.expect(renderer.pixels.ptr == pixels[0..].ptr);
    try renderer.endLinearResolve(token);
}

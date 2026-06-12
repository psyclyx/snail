//! Interactive demo entry point.
//!
//! Opens a Wayland window and renders the shared banner content
//! (rounded-rect card + wordmark + tagline + vector snail + multi-script
//! row) via the new snail API. Backed by `renderer_driver.zig`, which
//! wraps each backend's `Renderer` + `BackendCache` cache + emit/draw
//! shim. Keys cycle backend (C), AA mode (B), and hinting (H); arrows
//! pan; Z/X zoom; R toggles rotate; L dumps a brief repro frame; Esc
//! quits.

const std = @import("std");
const snail = @import("snail");
const snail_helpers = @import("snail-helpers");
const build_options = @import("build_options");
const assets_data = @import("assets");
const renderer_driver = @import("renderer_driver.zig");
const demo_banner = @import("banner.zig");
const hud_mod = @import("hud.zig");
const subpixel_detect = @import("platform/subpixel.zig");
const wayland = @import("platform/wayland.zig");
const presentation = @import("platform/presentation.zig");

const KEY_R = wayland.KEY_R;
const KEY_L = wayland.KEY_L;
const KEY_Z = wayland.KEY_Z;
const KEY_X = wayland.KEY_X;
const KEY_H = wayland.KEY_H;
const KEY_B = wayland.KEY_B;
const KEY_C = wayland.KEY_C;
const KEY_T = wayland.KEY_T;
const KEY_O = wayland.KEY_O;
const KEY_ESCAPE = wayland.KEY_ESCAPE;
const KEY_LEFT = wayland.KEY_LEFT;
const KEY_RIGHT = wayland.KEY_RIGHT;
const KEY_UP = wayland.KEY_UP;
const KEY_DOWN = wayland.KEY_DOWN;

const HintMode = enum {
    always,
    never,
    still,

    fn next(self: HintMode) HintMode {
        return switch (self) {
            .always => .never,
            .never => .still,
            .still => .always,
        };
    }

    fn name(self: HintMode) []const u8 {
        return switch (self) {
            .always => "always-tt",
            .never => "never-tt",
            .still => "tt-when-still",
        };
    }

    fn active(self: HintMode, moving: bool) bool {
        return switch (self) {
            .always => true,
            .never => false,
            .still => !moving,
        };
    }
};

fn cycleSubpixelOrder(o: snail.SubpixelOrder) snail.SubpixelOrder {
    return switch (o) {
        .none => .rgb,
        .rgb => .bgr,
        .bgr => .vrgb,
        .vrgb => .vbgr,
        .vbgr => .none,
    };
}

fn aaName(o: snail.SubpixelOrder) []const u8 {
    return switch (o) {
        .none => "grayscale",
        .rgb => "subpixel-RGB",
        .bgr => "subpixel-BGR",
        .vrgb => "subpixel-VRGB",
        .vbgr => "subpixel-VBGR",
    };
}

fn toSnailEncoding(encoding: presentation.ColorEncoding) snail.ColorEncoding {
    return switch (encoding) {
        .linear => .linear,
        .srgb => .srgb,
    };
}

fn displayTargetEncoding(info: presentation.Info) snail.TargetEncoding {
    return .{
        .attachment = toSnailEncoding(info.framebuffer_encoding),
        .stored_pixels = .srgb,
    };
}

fn logPresentationInfo(info: presentation.Info) void {
    const scale = info.scale();
    std.debug.print(
        "presentation: logical={}x{} framebuffer={}x{} scale={d:.2}x{d:.2} buffer_scale={} framebuffer={s} resample={}\n",
        .{
            info.logical_size[0],
            info.logical_size[1],
            info.framebuffer_size[0],
            info.framebuffer_size[1],
            scale[0],
            scale[1],
            info.buffer_scale,
            @tagName(info.framebuffer_encoding),
            info.will_resample,
        },
    );
}

fn dumpReproFrame(
    frame_count: u32,
    backend: []const u8,
    current_order: snail.SubpixelOrder,
    hint_mode: HintMode,
    hint_active: bool,
    present: presentation.Info,
    pan_x: f32,
    pan_y: f32,
    zoom: f32,
    angle: f32,
) void {
    std.debug.print("\n--- snail repro frame {} ---\n", .{frame_count});
    std.debug.print("backend={s} aa={s} hint={s}{s}\n", .{
        backend,
        aaName(current_order),
        hint_mode.name(),
        if (hint_active) "" else " (off)",
    });
    std.debug.print("logical_size={}x{} framebuffer={}x{}\n", .{
        present.logical_size[0],   present.logical_size[1],
        present.framebuffer_size[0], present.framebuffer_size[1],
    });
    std.debug.print("pan=({d:.2},{d:.2}) zoom={d:.4} angle={d:.4}\n", .{ pan_x, pan_y, zoom, angle });
    std.debug.print("--- end snail repro frame ---\n", .{});
}

const ContentCache = struct {
    allocator: std.mem.Allocator,
    pool: *snail.PagePool,
    assets: demo_banner.Assets,
    content: ?demo_banner.Content = null,
    last_size: [2]u32 = .{ 0, 0 },
    last_hint_active: bool = false,
    last_hint_ppem_bits: u32 = 0,
    last_world_to_pixel: ?snail.Transform2D = null,

    fn init(allocator: std.mem.Allocator) !ContentCache {
        const pool = try snail.PagePool.init(allocator, .{
            .max_layers = 24,
            .curve_words_per_page = 1 << 18,
            .band_words_per_page = 1 << 16,
        });
        errdefer pool.deinit();
        const assets = try demo_banner.Assets.init(allocator);
        return .{ .allocator = allocator, .pool = pool, .assets = assets };
    }

    fn deinit(self: *ContentCache) void {
        if (self.content) |*c| c.deinit();
        self.assets.deinit();
        self.pool.deinit();
    }

    /// Get or rebuild the full banner content. Cache key is
    /// (size, hint_active, hint_ppem). `world_to_pixel` is *not* part of
    /// the key: panning during hinted rendering doesn't rebuild, though
    /// the hinted text's baked baseline can drift sub-pixel during pan
    /// (next dirty rebuild picks up whatever transform is current then).
    ///
    /// The long-lived `Assets` (fonts, hinter, hinted-glyph cache) and
    /// `PagePool` survive across rebuilds, so the TT VM only runs once
    /// per `(glyph_id, ppem)`. Returns `dirty=true` when content was
    /// rebuilt.
    fn get(
        self: *ContentCache,
        width: u32,
        height: u32,
        hint_active: bool,
        hint_ppem_scale: f32,
        world_to_pixel: ?snail.Transform2D,
    ) !struct { content: *demo_banner.Content, dirty: bool } {
        const ppem_bits: u32 = @bitCast(hint_ppem_scale);
        const same = self.content != null and
            self.last_size[0] == width and
            self.last_size[1] == height and
            self.last_hint_active == hint_active and
            (!hint_active or self.last_hint_ppem_bits == ppem_bits);
        if (same) return .{ .content = &self.content.?, .dirty = false };

        if (self.content) |*old| old.deinit();
        self.content = null;

        const hint_opts: demo_banner.HintOptions = .{
            .enabled = hint_active,
            .ppem_scale = hint_ppem_scale,
            .world_to_pixel = if (hint_active) world_to_pixel else null,
        };
        self.content = try demo_banner.build(
            self.allocator,
            self.pool,
            &self.assets,
            @floatFromInt(width),
            @floatFromInt(height),
            .{ .x = 1, .y = 1 },
            hint_opts,
        );
        self.last_size = .{ width, height };
        self.last_hint_active = hint_active;
        self.last_hint_ppem_bits = ppem_bits;
        self.last_world_to_pixel = world_to_pixel;
        return .{ .content = &self.content.?, .dirty = true };
    }
};

fn transform2DEql(a: ?snail.Transform2D, b: ?snail.Transform2D) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    const x = a.?;
    const y = b.?;
    return x.xx == y.xx and x.xy == y.xy and x.yx == y.yx and x.yy == y.yy and x.tx == y.tx and x.ty == y.ty;
}

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();
    return mainLoop(allocator);
}

fn mainLoop(allocator: std.mem.Allocator) !void {
    const window = try wayland.Window.init(1280, 720, "snail");
    defer window.deinit();

    var active = try renderer_driver.Driver.init(allocator, window, renderer_driver.defaultKind());
    var active_valid = true;
    defer if (active_valid) active.deinit();

    const sys_order = subpixel_detect.detect();
    const detected_order = window.currentSubpixelOrder(sys_order);
    var current_order: snail.SubpixelOrder = .none;
    std.debug.print(
        "snail: detected subpixel order: system={s} monitor={s} (starting in {s})\n",
        .{ @tagName(sys_order), @tagName(detected_order), @tagName(current_order) },
    );

    var content_cache = try ContentCache.init(allocator);
    defer content_cache.deinit();

    var hud = try hud_mod.Overlay.init(allocator, &content_cache.assets.faces, content_cache.pool, 0);
    defer hud.deinit();
    var hud_arena = std.heap.ArenaAllocator.init(allocator);
    defer hud_arena.deinit();
    var hud_scratch = std.heap.ArenaAllocator.init(allocator);
    defer hud_scratch.deinit();

    var timing_enabled = false;
    var timing_frames: u32 = 0;
    var timing_window_start: f64 = 0;
    var timing_hud_build_us: f64 = 0;
    var timing_pass_us: [renderer_driver.MAX_PASSES]f64 = [_]f64{0} ** renderer_driver.MAX_PASSES;
    var timing_frame_us: f64 = 0;
    var hud_enabled = true;

    var angle: f32 = 0.0;
    var zoom: f32 = 1.0;
    var pan_x: f32 = 0.0;
    var pan_y: f32 = 0.0;
    var rotate = false;
    var last_time = wayland.getTime();
    var frame_count: u32 = 0;
    var fps_timer: f64 = 0.0;
    var fps_frames: u32 = 0;
    var fps_display: f32 = 0.0;
    var last_presentation: ?presentation.Info = null;
    var hint_mode: HintMode = .never;

    std.debug.print("snail - GPU text & vector rendering\n", .{});
    std.debug.print("Backend: {s}, HarfBuzz: {s}\n", .{
        active.backendName(),
        if (build_options.enable_harfbuzz) "ON" else "OFF",
    });
    renderer_driver.warnIfDebugCpu(active.kind());
    std.debug.print(
        "Keys: arrows pan, Z/X zoom, R rotate, H TT hinting, B AA mode, C backend, O HUD on/off, T timing prints, L dump repro, Esc quit\n",
        .{},
    );
    std.debug.print("aa={s}\n", .{aaName(current_order)});
    std.debug.print("hinting={s}\n", .{hint_mode.name()});

    while (!active.shouldClose()) {
        const now = wayland.getTime();
        const dt: f32 = @floatCast(now - last_time);
        last_time = now;
        fps_timer += dt;
        fps_frames += 1;
        if (fps_timer >= 1.0) {
            fps_display = @as(f32, @floatFromInt(fps_frames)) / @as(f32, @floatCast(fps_timer));
            fps_timer = 0.0;
            fps_frames = 0;
        }

        _ = window.consumeMonitorChanged();

        const dump_repro = window.isKeyPressed(KEY_L);
        if (window.isKeyPressed(KEY_R)) rotate = !rotate;
        if (window.isKeyPressed(KEY_H)) {
            hint_mode = hint_mode.next();
            std.debug.print("\nhinting={s}\n", .{hint_mode.name()});
        }
        if (window.isKeyPressed(KEY_ESCAPE)) break;
        if (window.isKeyPressed(KEY_O)) {
            hud_enabled = !hud_enabled;
            std.debug.print("\nhud={s}\n", .{if (hud_enabled) "on" else "off"});
        }
        if (window.isKeyPressed(KEY_T)) {
            timing_enabled = !timing_enabled;
            timing_frames = 0;
            timing_hud_build_us = 0;
            timing_pass_us = [_]f64{0} ** renderer_driver.MAX_PASSES;
            timing_frame_us = 0;
            timing_window_start = now;
            std.debug.print("\ntiming={s}\n", .{if (timing_enabled) "on" else "off"});
        }
        if (window.isKeyPressed(KEY_B)) {
            current_order = cycleSubpixelOrder(current_order);
            std.debug.print("\naa={s}\n", .{aaName(current_order)});
        }
        if (window.isKeyPressed(KEY_C)) {
            const next_kind = renderer_driver.nextKind(active.kind());
            if (next_kind != active.kind()) {
                active.deinit();
                active_valid = false;
                active = try renderer_driver.Driver.init(allocator, window, next_kind);
                active_valid = true;
                last_presentation = null;
                last_time = wayland.getTime();
                frame_count = 0;
                // Force a content re-upload by invalidating the cache pool match
                // on the new backend's first frame (we set dirty=true unconditionally
                // when the backend was swapped; see below).
                std.debug.print("\nBackend: {s}\n", .{active.backendName()});
                renderer_driver.warnIfDebugCpu(active.kind());
                continue;
            }
        }
        const zoom_in = window.isKeyDown(KEY_Z);
        const zoom_out = window.isKeyDown(KEY_X);
        const pan_left = window.isKeyDown(KEY_LEFT);
        const pan_right = window.isKeyDown(KEY_RIGHT);
        const pan_up = window.isKeyDown(KEY_UP);
        const pan_down = window.isKeyDown(KEY_DOWN);
        const moving = rotate or zoom_in or zoom_out or pan_left or pan_right or pan_up or pan_down;

        if (rotate) angle += dt * 0.5;
        if (zoom_in) zoom *= 1.0 + dt * 2.0;
        if (zoom_out) zoom *= 1.0 - dt * 2.0;
        const pan_step = 900.0 * dt;
        if (pan_left) pan_x += pan_step;
        if (pan_right) pan_x -= pan_step;
        if (pan_up) pan_y += pan_step;
        if (pan_down) pan_y -= pan_step;

        const present = active.presentationInfo();
        if (last_presentation == null or !std.meta.eql(last_presentation.?, present)) {
            logPresentationInfo(present);
            last_presentation = present;
        }
        const size = present.logical_size;
        const fb_size = present.framebuffer_size;
        const target_encoding = displayTargetEncoding(present);
        const w: f32 = @floatFromInt(size[0]);
        const h: f32 = @floatFromInt(size[1]);
        const viewport_w: f32 = @floatFromInt(fb_size[0]);
        const viewport_h: f32 = @floatFromInt(fb_size[1]);
        if (w < 1.0 or h < 1.0 or viewport_w < 1.0 or viewport_h < 1.0) continue;

        const hint_active = hint_mode.active(moving);
        // Hint at the *framebuffer* ppem the glyph will occupy, not the
        // logical-pixel ppem. On a HiDPI display the framebuffer is wider
        // than the logical size; hinting at logical ppem would render every
        // hint pixel as a buffer_scale-sized block (i.e. half-resolution
        // glyphs on a 2× display). Factor in framebuffer/logical so the
        // hinter targets the real pixel grid the GPU writes to.
        const hint_ppem_scale: f32 = zoom * (viewport_h / h);

        // MVP first — the hinted-text picture builder needs the
        // world→pixel transform to snap each shaped run's baseline onto
        // the screen pixel grid (without quantizing per-glyph kerning).
        const projection = snail.Mat4.ortho(0, w, h, 0, -1, 1);
        const cx = w * 0.5;
        const cy = h * 0.5;
        const scene_transform = snail.Mat4.multiply(
            snail.Mat4.translate(pan_x, pan_y, 0),
            snail.Mat4.multiply(
                snail.Mat4.translate(cx, cy, 0),
                snail.Mat4.multiply(
                    snail.Mat4.scaleUniform(zoom),
                    snail.Mat4.multiply(
                        snail.Mat4.rotateZ(angle),
                        snail.Mat4.translate(-cx, -cy, 0),
                    ),
                ),
            ),
        );
        const mvp = snail.Mat4.multiply(projection, scene_transform);
        const world_to_pixel = snail.mvpToScenePixel(mvp, viewport_w, viewport_h);

        const cached = try content_cache.get(size[0], size[1], hint_active, hint_ppem_scale, world_to_pixel);

        if (dump_repro) {
            dumpReproFrame(frame_count, active.backendName(), current_order, hint_mode, hint_active, present, pan_x, pan_y, zoom, angle);
        }

        const draw_state = snail.DrawState{
            .mvp = mvp,
            .surface = .{
                .pixel_width = viewport_w,
                .pixel_height = viewport_h,
                .encoding = target_encoding,
            },
            .raster = .{
                .subpixel_order = if (present.will_resample) .none else current_order,
                .coverage_transfer = .{ .exponent = 1.0 },
            },
        };

        // Background color (light cream — the card sits on top).
        const clear_srgb = [4]f32{ 245.0 / 255.0, 246.0 / 255.0, 249.0 / 255.0, 1.0 };

        // HUD: build a fresh screen-space picture each frame. Atlas
        // grows the first time each glyph is encountered; the
        // recordCount delta tells the driver when to re-upload.
        _ = hud_arena.reset(.retain_capacity);
        _ = hud_scratch.reset(.retain_capacity);
        const hud_before = hud.atlas.recordCount();
        const hud_build_t0 = if (timing_enabled) wayland.getTime() else 0;
        var hud_picture = try hud.buildPicture(
            hud_arena.allocator(),
            hud_scratch.allocator(),
            .{
                .fps = fps_display,
                .backend = active.backendName(),
                .aa = aaName(current_order),
                .hint = if (hint_active) hint_mode.name() else "Hint: off",
            },
            w,
            h,
        );
        defer hud_picture.deinit();
        const hud_build_us = if (timing_enabled) (wayland.getTime() - hud_build_t0) * 1_000_000.0 else 0;
        const hud_after = hud.atlas.recordCount();

        // HUD MVP: projection only — no scene_transform, so the
        // overlay doesn't pan/zoom/rotate with the world.
        const hud_draw_state = snail.DrawState{
            .mvp = projection,
            .surface = draw_state.surface,
            .raster = .{
                .subpixel_order = if (present.will_resample) .none else current_order,
                .coverage_transfer = .{ .exponent = 1.0 },
            },
        };
        const content_atlases = [_]*const snail.Atlas{ &cached.content.paths_atlas, &cached.content.text_atlas };
        const content_pictures = [_]*const snail_helpers.Picture{ &cached.content.paths_picture, &cached.content.text_picture };
        const hud_atlases = [_]*const snail.Atlas{&hud.atlas};
        const hud_pictures = [_]*const snail_helpers.Picture{&hud_picture};
        const all_passes = [_]renderer_driver.Pass{
            .{
                .atlases = &content_atlases,
                .pictures = &content_pictures,
                .draw_state = draw_state,
                .dirty = cached.dirty,
            },
            .{
                .atlases = &hud_atlases,
                .pictures = &hud_pictures,
                .draw_state = hud_draw_state,
                .dirty = hud_after != hud_before,
            },
        };
        const passes: []const renderer_driver.Pass = if (hud_enabled) all_passes[0..2] else all_passes[0..1];
        const frame_t0 = if (timing_enabled) wayland.getTime() else 0;
        _ = try active.renderFrame(allocator, passes, clear_srgb);
        if (timing_enabled) {
            const frame_us = (wayland.getTime() - frame_t0) * 1_000_000.0;
            timing_frames += 1;
            timing_hud_build_us += hud_build_us;
            timing_frame_us += frame_us;
            const pass_us = active.lastPassUs();
            for (&timing_pass_us, pass_us) |*acc, v| acc.* += v;
            if (now - timing_window_start >= 1.0 and timing_frames > 0) {
                const frames_f: f64 = @floatFromInt(timing_frames);
                const fps_measured: f64 = frames_f / (now - timing_window_start);
                std.debug.print(
                    "\n[timing] {d} frames @ {d:.1} FPS | avg µs/frame: hud_build={d:.1} content_draw={d:.1} hud_draw={d:.1} renderFrame={d:.1}\n",
                    .{
                        timing_frames,
                        fps_measured,
                        timing_hud_build_us / frames_f,
                        timing_pass_us[0] / frames_f,
                        timing_pass_us[1] / frames_f,
                        timing_frame_us / frames_f,
                    },
                );
                timing_frames = 0;
                timing_hud_build_us = 0;
                timing_pass_us = [_]f64{0} ** renderer_driver.MAX_PASSES;
                timing_frame_us = 0;
                timing_window_start = now;
            }
        }

        if (frame_count % 60 == 0 and fps_display > 0.0) {
            std.debug.print("\rFPS: {d:.0}  Backend: {s}  AA: {s}  Hint: {s}{s}   ", .{
                fps_display,
                active.backendName(),
                aaName(current_order),
                hint_mode.name(),
                if (hint_active) "" else " (off)",
            });
        }
        frame_count += 1;
    }
}

test {
    _ = @import("snail");
}

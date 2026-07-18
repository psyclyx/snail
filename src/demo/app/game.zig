//! Interactive game demo: a small 3D scene that showcases the ways to use
//! snail, rendered through a backend the user cycles at runtime (`C`) across
//! the GL family and Vulkan — the 3D analog of the 2D banner demo's trick.
//!
//! Scene (see `game/scene.zig`):
//!   - a custom material shader samples snail glyph coverage at arbitrary UVs
//!     (the "custom shader" showcase),
//!   - a depth-tested world label occluded by that opaque quad,
//!   - a translucent world panel drawn through snail's own pipeline,
//!   - a HUD whose top line is the live renderer + perf readout.

const std = @import("std");
const wayland = @import("../platform/wayland.zig");
const driver_common = @import("../driver/common.zig");
const game_driver = @import("../game/driver.zig");
const passes = @import("../game/passes.zig");
const scene_mod = @import("../game/scene.zig");

const KEY_C = wayland.KEY_C;
const KEY_R = wayland.KEY_R;
const KEY_ESCAPE = wayland.KEY_ESCAPE;

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const window = try wayland.Window.init(1440, 900, "snail-game-demo");
    defer window.deinit();

    var fonts = try passes.initFonts(allocator);
    defer fonts.deinit();

    const init_present_size = [2]u32{ 1440, 900 };
    var scene = try scene_mod.Scene.init(allocator, &fonts, init_present_size[0], init_present_size[1]);
    defer scene.deinit();

    // Initial backend: SNAIL_GAME_BACKEND env (gl44/gl33/gles30/vulkan) or default.
    var initial_kind = game_driver.defaultKind();
    if (std.c.getenv("SNAIL_GAME_BACKEND")) |name| {
        if (game_driver.kindFromName(std.mem.span(name))) |k| initial_kind = k;
    }

    var driver = try game_driver.Driver.init(allocator, window, &scene, initial_kind);
    defer driver.deinit();

    std.debug.print("snail-game-demo — custom-shader coverage across GL/Vulkan backends\n", .{});
    std.debug.print("Keys: C cycle backend, R toggle spin, Esc quit\n", .{});
    std.debug.print("Backend: {s}\n", .{driver.backendName()});

    var stats: driver_common.FrameTimeStats = .{};
    var last = wayland.getTime();
    var hud_timer: f64 = 0;
    const hud_period: f64 = 0.4;
    var perf_buf: [96]u8 = undefined;
    var perf_str: []const u8 = "";

    while (true) {
        if (driver.shouldClose()) break;
        const now = wayland.getTime();
        const dt: f32 = @floatCast(now - last);
        last = now;
        const dt_us: u32 = @intFromFloat(std.math.clamp(dt * 1_000_000.0, 0, 1.0e9));
        stats.record(dt_us);

        if (window.isKeyPressed(KEY_ESCAPE)) break;
        if (window.isKeyPressed(KEY_R)) scene.cam.spinning = !scene.cam.spinning;

        const present = driver.presentationInfo();
        const logical_w = if (present.logical_size[0] > 0) present.logical_size[0] else init_present_size[0];

        if (window.isKeyPressed(KEY_C)) {
            const nk = game_driver.nextKind(driver.kind());
            if (nk != driver.kind()) {
                // Set the HUD to the new backend's name *before* init so the new
                // driver uploads it (matters for Vulkan's upload-once HUD).
                try scene.rebuildHud(logical_w, game_driver.label(nk), perf_str);
                driver.deinit();
                driver = try game_driver.Driver.init(allocator, window, &scene, nk);
                std.debug.print("Backend: {s}\n", .{driver.backendName()});
                last = wayland.getTime();
                continue;
            }
        }

        scene.cam.update(dt);

        hud_timer += dt;
        if (hud_timer >= hud_period) {
            hud_timer = 0;
            const snap = stats.snapshot();
            perf_str = std.fmt.bufPrint(&perf_buf, "{d:.0} fps   {d:.1} p50  {d:.1} p95 ms", .{
                snap.fps,
                @as(f32, @floatFromInt(snap.p50_us)) / 1000.0,
                @as(f32, @floatFromInt(snap.p95_us)) / 1000.0,
            }) catch "";
            // Vulkan's HUD is static after init (upload-once cache); only the
            // GL family rebuilds the live perf line each tick.
            if (driver.wantsHudRebuild()) try scene.rebuildHud(logical_w, driver.backendName(), perf_str);
        }

        try driver.renderFrame(&scene);
    }
}

test {
    _ = @import("../game/scene.zig");
    _ = @import("../game/driver.zig");
}

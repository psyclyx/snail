//! Interactive 2D terminal-text integration demo.
//!
//! This is not a terminal emulator. It is a compact example of the ownership
//! boundaries a terminal would use: `Simulation` mutates a cell grid, `View`
//! shapes dirty style runs and grows a retained atlas, and the ordinary demo
//! driver uploads/draws the resulting picture.

const std = @import("std");
const snail = @import("snail");
const raster = @import("snail-raster");
const wayland = @import("../platform/wayland.zig");
const renderer_driver = @import("../driver/renderer.zig");
const Simulation = @import("../terminal/simulation.zig").Simulation;
const TerminalView = @import("../terminal/view.zig").View;
const Picture = @import("support").Picture;

const initial_size = [2]u32{ 1180, 760 };

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const window = try wayland.Window.init(
        initial_size[0],
        initial_size[1],
        "snail terminal text",
    );
    defer window.deinit();

    var simulation = Simulation.init();
    var view = try TerminalView.init(allocator);
    defer view.deinit();

    var driver = try renderer_driver.Driver.init(
        allocator,
        window,
        renderer_driver.defaultKind(),
    );
    defer driver.deinit();

    var scratch_arena = std.heap.ArenaAllocator.init(allocator);
    defer scratch_arena.deinit();
    var picture: ?Picture = null;
    defer if (picture) |*value| value.deinit();

    var rebuild_picture = true;
    var atlas_dirty = true;
    var last_presentation: ?@import("../platform/presentation.zig").Info = null;
    var last_time = wayland.getTime();

    std.debug.print(
        "snail terminal text demo\nKeys: R reset, P pause, C cycle backend, Esc quit\nBackend: {s}\n",
        .{driver.backendName()},
    );

    while (!driver.shouldClose()) {
        const now = wayland.getTime();
        const dt = std.math.clamp(now - last_time, 0, 0.1);
        last_time = now;

        if (window.isKeyPressed(wayland.KEY_ESCAPE)) break;
        if (window.isKeyPressed(wayland.KEY_R)) {
            simulation.reset();
            rebuild_picture = true;
        }
        if (window.isKeyPressed(wayland.KEY_P)) {
            simulation.paused = !simulation.paused;
            std.debug.print("simulation: {s}\n", .{if (simulation.paused) "paused" else "running"});
        }
        if (window.isKeyPressed(wayland.KEY_C)) {
            const next = renderer_driver.nextKind(driver.kind());
            driver.deinit();
            driver = try renderer_driver.Driver.init(allocator, window, next);
            atlas_dirty = true;
            last_presentation = null;
            last_time = wayland.getTime();
            std.debug.print("Backend: {s}\n", .{driver.backendName()});
            renderer_driver.warnIfDebugCpu(driver.kind());
            continue;
        }

        if (try simulation.update(dt)) rebuild_picture = true;

        const present = driver.presentationInfo();
        if (present.logical_size[0] == 0 or
            present.logical_size[1] == 0 or
            present.framebuffer_size[0] == 0 or
            present.framebuffer_size[1] == 0)
        {
            continue;
        }
        if (last_presentation == null or !std.meta.eql(last_presentation.?, present)) {
            last_presentation = present;
            rebuild_picture = true;
        }

        const logical_w: f32 = @floatFromInt(present.logical_size[0]);
        const logical_h: f32 = @floatFromInt(present.logical_size[1]);
        const framebuffer_w: f32 = @floatFromInt(present.framebuffer_size[0]);
        const framebuffer_h: f32 = @floatFromInt(present.framebuffer_size[1]);
        const projection = snail.Mat4.ortho(0, logical_w, logical_h, 0, -1, 1);
        const world_to_pixel = snail.mvpToScenePixel(
            projection,
            framebuffer_w,
            framebuffer_h,
        ) orelse continue;

        if (rebuild_picture) {
            _ = scratch_arena.reset(.retain_capacity);
            const built = try view.buildPicture(
                allocator,
                scratch_arena.allocator(),
                &simulation.screen,
                world_to_pixel,
            );
            if (picture) |*old| old.deinit();
            picture = built.picture;
            if (built.records_added != 0) {
                atlas_dirty = true;
                std.debug.print(
                    "atlas: +{} records ({} resident, {} pages)\n",
                    .{
                        built.records_added,
                        view.atlas.recordCount(),
                        view.atlas.pageCount(),
                    },
                );
            }
            rebuild_picture = false;
        }

        const target_encoding = raster.TargetEncoding{
            .attachment = switch (present.framebuffer_encoding) {
                .linear => .linear,
                .srgb => .srgb,
            },
            .stored_pixels = .srgb,
        };
        const draw_state = raster.DrawState{
            .mvp = projection,
            .surface = .{
                .pixel_width = present.framebuffer_size[0],
                .pixel_height = present.framebuffer_size[1],
                .encoding = target_encoding,
            },
            .raster = .{
                .subpixel_order = if (present.will_resample) .none else .rgb,
                .coverage_transfer = .{ .exponent = 0.8 },
            },
        };

        const atlases = [_]*const snail.Atlas{&view.atlas};
        const pictures = [_]*const Picture{&picture.?};
        const passes = [_]renderer_driver.Pass{.{
            .atlases = &atlases,
            .pictures = &pictures,
            .draw_state = draw_state,
            .dirty = atlas_dirty,
            .binding_update = .incremental,
        }};
        _ = try driver.renderFrame(
            allocator,
            &passes,
            .{ 0.025, 0.035, 0.055, 1 },
        );
        atlas_dirty = false;
    }
}

test {
    _ = @import("../terminal/screen.zig");
    _ = @import("../terminal/simulation.zig");
    _ = @import("../terminal/view.zig");
}

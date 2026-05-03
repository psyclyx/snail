const std = @import("std");
const snail = @import("snail.zig");
const demo_banner = @import("demo_banner.zig");
const demo_banner_scene = @import("demo_banner_scene.zig");
const CpuRenderer = @import("cpu_renderer.zig").CpuRenderer;

const SCREENSHOT_WIDTH: u32 = 1680;
const SCREENSHOT_HEIGHT: u32 = 874;
const SCREENSHOT_PATH = "zig-out/demo-screenshot-cpu.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var scene_assets = try demo_banner_scene.Assets.init(allocator);
    defer scene_assets.deinit();

    const w: f32 = @floatFromInt(SCREENSHOT_WIDTH);
    const h: f32 = @floatFromInt(SCREENSHOT_HEIGHT);
    const layout = demo_banner.buildLayout(w, h, scene_assets.metrics);

    const assets = @import("assets");
    var tile_image = try snail.Image.initSrgba8(allocator, 16, 16, assets.checkerboard_rgba);
    defer tile_image.deinit();

    var path_picture = try demo_banner_scene.buildPathPicture(allocator, layout, .normal, &tile_image);
    defer path_picture.deinit();

    const pixels = try allocator.alloc(u8, SCREENSHOT_WIDTH * SCREENSHOT_HEIGHT * 4);
    defer allocator.free(pixels);
    var cpu = CpuRenderer.init(pixels.ptr, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT, SCREENSHOT_WIDTH * 4);

    const clear = demo_banner.clearColor();
    cpu.clear(
        @intFromFloat(clear[0] * 255),
        @intFromFloat(clear[1] * 255),
        @intFromFloat(clear[2] * 255),
        @intFromFloat(clear[3] * 255),
    );

    // Vector paths
    cpu.drawPathPicture(&path_picture);

    // Text — same layout as the GPU demo, rendered with the CPU renderer
    demo_banner.drawTextCpu(&cpu, layout, scene_assets.metrics, .{
        .latin_font = &scene_assets.latin_font,
        .latin_atlas = &scene_assets.latin_atlas,
        .arabic = &scene_assets.arabic,
        .devanagari = &scene_assets.devanagari,
        .mongolian = &scene_assets.mongolian,
        .thai = &scene_assets.thai,
        .emoji = &scene_assets.emoji,
    });

    writeTga(SCREENSHOT_PATH, pixels, SCREENSHOT_WIDTH, SCREENSHOT_HEIGHT);
    std.debug.print("wrote {s}\n", .{SCREENSHOT_PATH});
}

fn writeTga(path: [*:0]const u8, pixels: []const u8, width: u32, height: u32) void {
    const c_file = std.c.fopen(path, "wb") orelse return;
    defer _ = std.c.fclose(c_file);

    var header: [18]u8 = .{0} ** 18;
    header[2] = 2;
    header[12] = @intCast(width & 0xFF);
    header[13] = @intCast((width >> 8) & 0xFF);
    header[14] = @intCast(height & 0xFF);
    header[15] = @intCast((height >> 8) & 0xFF);
    header[16] = 32;
    header[17] = 0x28;

    _ = std.c.fwrite(&header, 1, 18, c_file);

    var row: u32 = 0;
    while (row < height) : (row += 1) {
        const off = row * width * 4;
        var col: u32 = 0;
        while (col < width) : (col += 1) {
            const i = off + col * 4;
            const bgra = [4]u8{ pixels[i + 2], pixels[i + 1], pixels[i + 0], pixels[i + 3] };
            _ = std.c.fwrite(&bgra, 1, 4, c_file);
        }
    }
}

//! Compact README banner. Smaller and tighter than the full 2D demo so it
//! displays cleanly when GitHub resizes it down. Composes the vector snail
//! from `demo_banner.addVectorSnail` with a wordmark + multi-script sample.

const std = @import("std");
const snail = @import("snail.zig");
const demo_banner = @import("demo_banner.zig");
const assets_data = @import("assets");

const Allocator = std.mem.Allocator;

pub const WIDTH: u32 = 960;
pub const HEIGHT: u32 = 320;

pub fn clearColor() [4]f32 {
    return .{ 0.96, 0.965, 0.975, 1.0 };
}

pub const Assets = struct {
    fonts: snail.TextAtlas,

    pub fn init(allocator: Allocator) !Assets {
        var fonts = try snail.TextAtlas.init(allocator, &.{
            .{ .data = assets_data.noto_sans_regular },
            .{ .data = assets_data.noto_sans_bold, .weight = .bold },
            .{ .data = assets_data.noto_sans_arabic, .fallback = true },
            .{ .data = assets_data.noto_sans_devanagari, .fallback = true },
            .{ .data = assets_data.noto_sans_thai, .fallback = true },
            .{ .data = assets_data.twemoji_mozilla, .fallback = true },
        });
        errdefer fonts.deinit();

        const ensure_styles = [_]struct { style: snail.FontStyle, text: []const u8 }{
            .{ .style = .{ .weight = .bold }, .text = "snail" },
            .{ .style = .{}, .text = "GPU text and vector rendering" },
            .{ .style = .{}, .text = "Hello, world!" },
            .{ .style = .{}, .text = "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7" }, // مرحبا
            .{ .style = .{}, .text = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87" }, // नमस्ते
            .{ .style = .{}, .text = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5" }, // สวัสดี
            .{ .style = .{}, .text = "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x9a\x80\xf0\x9f\x90\x8c\xf0\x9f\x8c\x88" }, // ✨🌍🚀🐌🌈
        };
        for (ensure_styles) |entry| {
            if (try fonts.ensureText(entry.style, entry.text)) |next| {
                fonts.deinit();
                fonts = next;
            }
        }
        return .{ .fonts = fonts };
    }

    pub fn deinit(self: *Assets) void {
        self.fonts.deinit();
    }
};

const wordmark_color = [4]f32{ 0.10, 0.10, 0.14, 1.0 };
const tagline_color = [4]f32{ 0.42, 0.46, 0.52, 1.0 };
const sample_color = [4]f32{ 0.15, 0.18, 0.24, 1.0 };
const sep_color = [4]f32{ 0.65, 0.70, 0.78, 1.0 };

const left_pad: f32 = 56.0;
const wordmark_size: f32 = 96.0;
const wordmark_baseline: f32 = 130.0;
const tagline_size: f32 = 22.0;
const tagline_baseline: f32 = wordmark_baseline + 36.0;
const sample_size: f32 = 28.0;
const sample_baseline: f32 = 256.0;

pub fn buildTextBlob(builder: *snail.TextBlobBuilder) !void {
    var x = left_pad;
    const advance = try builder.addText(
        .{ .weight = .bold },
        "snail",
        x,
        wordmark_baseline,
        wordmark_size,
        wordmark_color,
    );
    x += advance.advance;

    _ = try builder.addText(
        .{},
        "GPU text and vector rendering",
        left_pad,
        tagline_baseline,
        tagline_size,
        tagline_color,
    );

    // Multi-script sample row, separated by middle-dots.
    const samples = [_][]const u8{
        "Hello, world!",
        "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7", // مرحبا
        "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87", // नमस्ते
        "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5", // สวัสดี
        "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x90\x8c\xf0\x9f\x8c\x88", // ✨🌍🐌🌈
    };
    var sx = left_pad;
    for (samples, 0..) |sample, i| {
        if (i != 0) {
            const sep = try builder.addText(.{}, " · ", sx, sample_baseline, sample_size, sep_color);
            sx += sep.advance;
        }
        const result = try builder.addText(.{}, sample, sx, sample_baseline, sample_size, sample_color);
        sx += result.advance;
    }
}

pub fn buildPathPicture(allocator: Allocator) !snail.PathPicture {
    var builder = snail.PathPictureBuilder.init(allocator);
    defer builder.deinit();

    // The vector snail lives in the right ~280 px of the canvas.
    const stage = snail.Rect{
        .x = @as(f32, @floatFromInt(WIDTH)) - 320.0,
        .y = 30.0,
        .w = 300.0,
        .h = 260.0,
    };
    try demo_banner.addVectorSnail(&builder, stage);

    return builder.freeze(allocator);
}

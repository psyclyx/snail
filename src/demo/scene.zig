const std = @import("std");
const snail = @import("snail");
const demo_banner = @import("banner.zig");
const assets_data = @import("assets");
const Allocator = std.mem.Allocator;

pub const ViewMode = enum {
    normal,

    pub fn pathDebugView(self: ViewMode) snail.PathPictureDebugView {
        _ = self;
        return .normal;
    }
};

/// Demo assets: shared text atlas snapshot and image paint texture.
pub const Assets = struct {
    fonts: snail.TextAtlas,
    paint_image: snail.Image,

    pub fn init(allocator: Allocator) !Assets {
        var fonts = try snail.TextAtlas.init(allocator, &.{
            .{ .data = assets_data.noto_sans_regular },
            .{ .data = assets_data.noto_sans_bold, .weight = .bold },
            .{ .data = assets_data.noto_sans_regular, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
            .{ .data = assets_data.noto_sans_bold, .weight = .bold, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
            .{ .data = assets_data.noto_sans_regular, .weight = .semi_bold, .synthetic = .{ .embolden = 0.5 } },
            .{ .data = assets_data.noto_sans_arabic, .fallback = true },
            .{ .data = assets_data.noto_sans_devanagari, .fallback = true },
            .{ .data = assets_data.noto_sans_symbols, .fallback = true },
            .{ .data = assets_data.noto_sans_thai, .fallback = true },
            .{ .data = assets_data.twemoji_mozilla, .fallback = true },
        });
        errdefer fonts.deinit();

        // Ensure glyphs for every style used in the demo.
        const ascii = &snail.ASCII_PRINTABLE;
        const styles = [_]snail.FontStyle{
            .{},
            .{ .weight = .bold },
            .{ .italic = true },
            .{ .weight = .bold, .italic = true },
            .{ .weight = .semi_bold },
        };
        for (styles) |style| {
            if (try fonts.ensureText(style, ascii)) |new_fonts| {
                fonts.deinit();
                fonts = new_fonts;
            }
        }
        // Script/emoji fallback text + ligature contexts.
        const extra = [_][]const u8{
            "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7", // مرحبا
            "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87", // नमस्ते
            "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5", // สวัสดี
            "\xe2\x9c\xa8\xf0\x9f\x8c\x8d\xf0\x9f\x8e\xa8\xf0\x9f\x9a\x80\xf0\x9f\x90\x8c\xf0\x9f\x8c\x88", // ✨🌍🎨🚀🐌🌈
            " \xe2\x86\x92 ", // →
            "office ffi fl ffl", // ligature contexts
        };
        for (extra) |txt| {
            if (try fonts.ensureText(.{}, txt)) |new_fonts| {
                fonts.deinit();
                fonts = new_fonts;
            }
        }

        const paint_image = try initPaintImage(allocator);

        return .{
            .fonts = fonts,
            .paint_image = paint_image,
        };
    }

    pub fn deinit(self: *Assets) void {
        self.fonts.deinit();
        self.paint_image.deinit();
    }
};

fn initPaintImage(allocator: Allocator) !snail.Image {
    var pixels: [16 * 16 * 4]u8 = undefined;
    const colors = [_][4]u8{
        .{ 36, 92, 220, 255 },
        .{ 242, 88, 142, 255 },
        .{ 255, 210, 80, 255 },
        .{ 40, 176, 132, 255 },
    };
    for (0..16) |py| {
        for (0..16) |px| {
            const diagonal = ((px + py) / 4) % 2;
            const quadrant = @as(usize, @intFromBool(px >= 8)) + @as(usize, @intFromBool(py >= 8)) * 2;
            const color = colors[(quadrant + diagonal) % colors.len];
            const i = (py * 16 + px) * 4;
            pixels[i + 0] = color[0];
            pixels[i + 1] = color[1];
            pixels[i + 2] = color[2];
            pixels[i + 3] = color[3];
        }
    }
    return snail.Image.initSrgba8(allocator, 16, 16, &pixels);
}

pub fn buildPathPicture(allocator: Allocator, layout: demo_banner.Layout, assets_ref: *const Assets, decoration_rects: []const snail.Rect) !snail.PathPicture {
    return demo_banner.buildPathPicture(allocator, layout, &assets_ref.paint_image, decoration_rects);
}

/// Build the demo's prepared text blob and collect decoration rects.
pub fn buildTextBlob(builder: *snail.TextBlobBuilder, layout: demo_banner.Layout, snap_step: snail.Vec2, assets_ref: *const Assets, decoration_rects: []snail.Rect) demo_banner.TextBuildResult {
    return buildTextBlobWithHinting(builder, layout, snap_step, assets_ref, null, decoration_rects, .{});
}

pub fn buildTextBlobWithHinting(
    builder: *snail.TextBlobBuilder,
    layout: demo_banner.Layout,
    snap_step: snail.Vec2,
    assets_ref: *const Assets,
    hint_context: ?*snail.TrueTypeHintContext,
    decoration_rects: []snail.Rect,
    hint_options: demo_banner.TextHintOptions,
) demo_banner.TextBuildResult {
    return demo_banner.buildTextBlob(builder, layout, snap_step, &assets_ref.fonts, hint_context, &assets_ref.paint_image, decoration_rects, hint_options) catch .{ .decoration_count = 0, .missing = false };
}

const std = @import("std");
const snail = @import("snail.zig");
const demo_banner = @import("demo_banner.zig");
const assets_data = @import("assets");
const Allocator = std.mem.Allocator;

pub const ViewMode = enum {
    normal,

    pub fn pathDebugView(self: ViewMode) snail.PathPictureDebugView {
        _ = self;
        return .normal;
    }
};

/// Demo assets: unified Fonts and tile image.
pub const Assets = struct {
    fonts: snail.Fonts,
    tile_image: snail.Image,

    pub fn init(allocator: Allocator) !Assets {
        var fonts = try snail.Fonts.init(allocator, &.{
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

        return .{
            .fonts = fonts,
            .tile_image = try snail.Image.initSrgba8(allocator, 16, 16, assets_data.dots_rgba),
        };
    }

    pub fn deinit(self: *Assets) void {
        self.fonts.deinit();
        self.tile_image.deinit();
    }

    /// Upload Fonts pages + PathPicture atlas as a combined texture array.
    pub fn uploadAtlases(self: *Assets, renderer: *snail.Renderer, path_picture: *const snail.PathPicture) snail.AtlasHandle {
        // Create a temporary Atlas wrapping the Fonts pages for upload.
        var font_wrapper = self.fonts.uploadAtlas();
        defer self.fonts.deinitUploadAtlas(&font_wrapper);

        var all_atlases = [2]*const snail.Atlas{ &font_wrapper, &path_picture.atlas };
        var all_handles: [2]snail.AtlasHandle = undefined;
        renderer.uploadAtlases(&all_atlases, &all_handles);

        // Store layer_base so FaceView can compute correct texture layers.
        self.fonts.layer_base = all_handles[0].layer_base;
        self.fonts.info_row_base = all_handles[0].info_row_base;

        return all_handles[1]; // PathPicture handle
    }
};

pub fn buildPathPicture(allocator: Allocator, layout: demo_banner.Layout, assets_ref: *const Assets, decoration_rects: []const snail.Rect) !snail.PathPicture {
    return demo_banner.buildPathPicture(allocator, layout, &assets_ref.tile_image, decoration_rects);
}

/// Draw text and collect decoration rects.
pub fn populateTextBatch(batch: *snail.TextBatch, layout: demo_banner.Layout, assets_ref: *const Assets, decoration_rects: []snail.Rect) demo_banner.DrawTextResult {
    return demo_banner.drawText(batch, layout, &assets_ref.fonts, decoration_rects) catch .{ .decoration_count = 0, .missing = false };
}

const std = @import("std");
const snail = @import("snail.zig");
const demo_banner = @import("demo_banner.zig");
const assets = @import("assets");

pub const Assets = struct {
    latin_font: snail.Font,
    latin_atlas: snail.Atlas,
    arabic: demo_banner.ScriptFont,
    devanagari: demo_banner.ScriptFont,
    mongolian: demo_banner.ScriptFont,
    thai: demo_banner.ScriptFont,
    emoji: demo_banner.ScriptFont,
    metrics: demo_banner.TextMetrics,

    pub fn init(allocator: std.mem.Allocator) !Assets {
        var latin_font = try snail.Font.init(assets.noto_sans_regular);
        errdefer latin_font.deinit();

        var latin_atlas = try snail.Atlas.initAscii(allocator, &latin_font, &snail.ASCII_PRINTABLE);
        errdefer latin_atlas.deinit();

        var arabic = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_arabic, demo_banner.arabic_text);
        errdefer arabic.deinit();
        var devanagari = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_devanagari, demo_banner.devanagari_text);
        errdefer devanagari.deinit();
        var mongolian = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_mongolian, demo_banner.mongolian_text);
        errdefer mongolian.deinit();
        var thai = try demo_banner.ScriptFont.init(allocator, assets.noto_sans_thai, demo_banner.thai_text);
        errdefer thai.deinit();
        var emoji = try demo_banner.ScriptFont.init(allocator, assets.twemoji_mozilla, demo_banner.emoji_text);
        errdefer emoji.deinit();

        return .{
            .latin_font = latin_font,
            .latin_atlas = latin_atlas,
            .arabic = arabic,
            .devanagari = devanagari,
            .mongolian = mongolian,
            .thai = thai,
            .emoji = emoji,
            .metrics = demo_banner.measureMetrics(&latin_atlas, &latin_font),
        };
    }

    pub fn deinit(self: *Assets) void {
        self.emoji.deinit();
        self.thai.deinit();
        self.mongolian.deinit();
        self.devanagari.deinit();
        self.arabic.deinit();
        self.latin_atlas.deinit();
        self.latin_font.deinit();
    }

    pub fn uploadAtlases(
        self: *const Assets,
        renderer: *snail.Renderer,
        picture: *const snail.PathPicture,
        atlas_views: *[7]snail.AtlasView,
    ) void {
        renderer.uploadAtlases(&[_]*const snail.Atlas{
            &self.latin_atlas,
            &self.arabic.atlas,
            &self.devanagari.atlas,
            &self.mongolian.atlas,
            &self.thai.atlas,
            &self.emoji.atlas,
            &picture.atlas,
        }, atlas_views);
    }

    pub fn textResources(self: *const Assets, atlas_views: *const [7]snail.AtlasView) demo_banner.TextResources {
        return .{
            .latin_font = &self.latin_font,
            .latin_view = &atlas_views[0],
            .arabic_font = &self.arabic,
            .arabic_view = &atlas_views[1],
            .devanagari_font = &self.devanagari,
            .devanagari_view = &atlas_views[2],
            .mongolian_font = &self.mongolian,
            .mongolian_view = &atlas_views[3],
            .thai_font = &self.thai,
            .thai_view = &atlas_views[4],
            .emoji_font = &self.emoji,
            .emoji_view = &atlas_views[5],
        };
    }
};

pub fn buildPathPicture(
    allocator: std.mem.Allocator,
    layout: demo_banner.Layout,
) !snail.PathPicture {
    var picture_builder = snail.PathPictureBuilder.init(allocator);
    defer picture_builder.deinit();
    try demo_banner.buildPathShowcase(&picture_builder, layout);
    return picture_builder.freeze(allocator);
}

pub fn populateTextBatch(
    batch: *snail.Batch,
    h: f32,
    layout: demo_banner.Layout,
    scene_assets: *const Assets,
    atlas_views: *const [7]snail.AtlasView,
) void {
    demo_banner.drawText(batch, h, layout, scene_assets.textResources(atlas_views));
}

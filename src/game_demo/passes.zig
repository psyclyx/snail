const std = @import("std");
const snail = @import("../snail.zig");
const assets = @import("assets");
const gl = @import("../render/gl.zig").gl;
const common = @import("common.zig");

const MATERIAL_TEXTURE_SIZE: u32 = 1024;

pub const PreparedPass = struct {
    allocator: std.mem.Allocator,
    picture: ?*snail.PathPicture = null,
    text: *snail.TextBlob,
    scene: snail.Scene,

    pub fn init(
        allocator: std.mem.Allocator,
        text: snail.TextBlob,
        picture: ?snail.PathPicture,
        resolve: snail.TextResolveOptions,
    ) !PreparedPass {
        const owned_text = try allocator.create(snail.TextBlob);
        errdefer allocator.destroy(owned_text);
        owned_text.* = text;

        var owned_picture: ?*snail.PathPicture = null;
        if (picture) |value| {
            owned_picture = try allocator.create(snail.PathPicture);
            errdefer if (owned_picture) |ptr| allocator.destroy(ptr);
            owned_picture.?.* = value;
        }

        var pass = PreparedPass{
            .allocator = allocator,
            .picture = owned_picture,
            .text = owned_text,
            .scene = snail.Scene.init(allocator),
        };
        errdefer {
            pass.scene.deinit();
            pass.text.deinit();
            allocator.destroy(pass.text);
            if (pass.picture) |owned_picture_ptr| {
                owned_picture_ptr.deinit();
                allocator.destroy(owned_picture_ptr);
            }
        }

        if (pass.picture) |owned_picture_ptr| try pass.scene.addPathPicture(owned_picture_ptr);
        try pass.scene.addTextOptions(pass.text, resolve);
        return pass;
    }

    pub fn deinit(self: *PreparedPass) void {
        self.scene.deinit();
        self.text.deinit();
        self.allocator.destroy(self.text);
        if (self.picture) |picture| {
            picture.deinit();
            self.allocator.destroy(picture);
        }
        self.* = undefined;
    }
};

pub const HudPasses = struct {
    plain: PreparedPass,
    translucent: PreparedPass,
    solid: PreparedPass,

    pub fn init(allocator: std.mem.Allocator, fonts: *snail.TextAtlas, window_w: u32, window_h: u32) !HudPasses {
        return .{
            .plain = try buildHudPlainPass(allocator, fonts, window_w),
            .translucent = try buildHudTranslucentPass(allocator, fonts, window_w),
            .solid = try buildHudSolidPass(allocator, fonts, window_w, window_h),
        };
    }

    pub fn deinit(self: *HudPasses) void {
        self.plain.deinit();
        self.translucent.deinit();
        self.solid.deinit();
    }
};

pub const PlanePass = struct {
    prepared: PreparedPass,
    scene_width: f32,
    scene_height: f32,
    opaque_backdrop: bool,

    pub fn deinit(self: *PlanePass) void {
        self.prepared.deinit();
        self.* = undefined;
    }
};

pub const WorldPasses = struct {
    rough_wall: PlanePass,
    center_panel: PlanePass,
    glass: PlanePass,
    material_maps: MaterialMaps,

    pub fn deinit(self: *WorldPasses) void {
        self.rough_wall.deinit();
        self.center_panel.deinit();
        self.glass.deinit();
        self.material_maps.deinit();
        self.* = undefined;
    }
};

pub fn buildWorldPasses(allocator: std.mem.Allocator, fonts: *snail.TextAtlas) !WorldPasses {
    var material_maps = try MaterialMaps.init(allocator, MATERIAL_TEXTURE_SIZE);
    errdefer material_maps.deinit();

    var rough_wall = try buildRoughWallTextPass(allocator, fonts);
    errdefer rough_wall.deinit();

    var center_panel = try buildCenterPanelPass(allocator, fonts);
    errdefer center_panel.deinit();

    var glass = try buildGlassPass(allocator, fonts);
    errdefer glass.deinit();

    return .{
        .rough_wall = rough_wall,
        .center_panel = center_panel,
        .glass = glass,
        .material_maps = material_maps,
    };
}

pub fn initFonts(allocator: std.mem.Allocator) !snail.TextAtlas {
    var fonts = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets.noto_sans_regular },
        .{ .data = assets.noto_sans_bold, .weight = .bold },
    });

    try ensureGameDemoText(&fonts);
    return fonts;
}

fn replaceEnsuredText(fonts: *snail.TextAtlas, style: snail.FontStyle, text: []const u8) !void {
    if (try fonts.ensureText(style, text)) |next| {
        fonts.deinit();
        fonts.* = next;
    }
}

fn ensureGameDemoText(fonts: *snail.TextAtlas) !void {
    try replaceEnsuredText(fonts, .{}, &snail.ASCII_PRINTABLE);
    try replaceEnsuredText(fonts, .{ .weight = .bold }, &snail.ASCII_PRINTABLE);

    const regular_text = [_][]const u8{
        "WASD move  QE rise  Arrows look  R reset",
        "Final pixels, but no opaque backdrop under the glyphs.",
        "Restore power and reach the observation deck.",
        "Translucent vector backing keeps LCD text disabled.",
        "HEALTH  83",
        "AMMO    42",
        "Opaque vector backing: LCD-safe HUD text.",
        "Text tinted directly onto the normal-mapped wall material.",
        "The wall keeps its surface detail; the glyphs are not billboarded.",
        "Opaque vector paint applied directly to the wall.",
        "Analytic vector text sampled in the material shader.",
        "Lit by the room; never flattened into a texture.",
        "Translucent glass overlay in front of the wall.",
        "Still direct-rendered, but LCD remains off on translucent backing.",
    };
    for (regular_text) |text| try replaceEnsuredText(fonts, .{}, text);

    const bold_text = [_][]const u8{
        "HUD text / no backing",
        "Quest Log",
        "Status Panel",
        "AUTHORIZED ONLY",
        "SECTOR A",
        "OBSERVATION",
    };
    for (bold_text) |text| try replaceEnsuredText(fonts, .{ .weight = .bold }, text);
}

fn measureTextWidth(
    allocator: std.mem.Allocator,
    fonts: *snail.TextAtlas,
    style: snail.FontStyle,
    text: []const u8,
    font_size: f32,
) !f32 {
    var probe = snail.TextBlobBuilder.init(allocator, fonts);
    defer probe.deinit();
    return (try probe.addText(style, text, 0.0, font_size, font_size, .{ 1, 1, 1, 1 })).advance;
}

fn max3(a: f32, b: f32, c: f32) f32 {
    return @max(a, @max(b, c));
}

fn max4(a: f32, b: f32, c: f32, d: f32) f32 {
    return @max(@max(a, b), @max(c, d));
}

fn buildHudPlainPass(allocator: std.mem.Allocator, fonts: *snail.TextAtlas, window_w: u32) !PreparedPass {
    var builder = snail.TextBlobBuilder.init(allocator, fonts);
    defer builder.deinit();

    const x = 34.0;
    _ = try builder.addText(.{ .weight = .bold }, "HUD text / no backing", x, 52.0, 22.0, .{ 1, 1, 1, 1 });
    _ = try builder.addText(.{}, "WASD move  QE rise  Arrows look  R reset", x, 84.0, 17.0, .{ 0.86, 0.90, 0.96, 1.0 });
    _ = try builder.addText(.{}, "Final pixels, but no opaque backdrop under the glyphs.", x, 108.0, 15.0, .{ 0.68, 0.75, 0.84, 1.0 });
    const text = try builder.finish();

    _ = window_w;
    return PreparedPass.init(allocator, text, null, .{ .hinting = .metrics });
}

fn buildHudTranslucentPass(allocator: std.mem.Allocator, fonts: *snail.TextAtlas, window_w: u32) !PreparedPass {
    const title = "Quest Log";
    const body = "Restore power and reach the observation deck.";
    const note = "Translucent vector backing keeps LCD text disabled.";
    const pad_x = 22.0;
    const pad_y = 18.0;
    const title_size = 24.0;
    const body_size = 17.0;
    const note_size = 14.0;
    const inner_w = max3(
        try measureTextWidth(allocator, fonts, .{ .weight = .bold }, title, title_size),
        try measureTextWidth(allocator, fonts, .{}, body, body_size),
        try measureTextWidth(allocator, fonts, .{}, note, note_size),
    );
    const rect_w = inner_w + pad_x * 2.0;
    const rect_h = 112.0;
    const rect = snail.Rect{
        .x = @as(f32, @floatFromInt(window_w)) * 0.5 - rect_w * 0.5,
        .y = 26.0,
        .w = rect_w,
        .h = rect_h,
    };

    var path_builder = snail.PathPictureBuilder.init(allocator);
    defer path_builder.deinit();
    try path_builder.addRoundedRect(
        rect,
        .{
            .color = .{ 0.18, 0.32, 0.44, 0.34 },
        },
        .{
            .color = .{ 0.56, 0.82, 1.0, 0.52 },
            .width = 2.0,
            .placement = .inside,
        },
        18.0,
        .identity,
    );
    try path_builder.addFilledRect(
        .{ .x = rect.x + 22.0, .y = rect.y + 18.0, .w = 90.0, .h = 6.0 },
        .{ .color = .{ 0.56, 0.82, 1.0, 0.78 } },
        .identity,
    );
    var picture = try path_builder.freeze(allocator);
    errdefer picture.deinit();

    var builder = snail.TextBlobBuilder.init(allocator, fonts);
    defer builder.deinit();
    const tx = rect.x + pad_x;
    _ = try builder.addText(.{ .weight = .bold }, title, tx, rect.y + pad_y + title_size, title_size, .{ 0.97, 0.99, 1.0, 1.0 });
    _ = try builder.addText(.{}, body, tx, rect.y + pad_y + title_size + 30.0, body_size, .{ 0.88, 0.94, 0.98, 1.0 });
    _ = try builder.addText(.{}, note, tx, rect.y + pad_y + title_size + 54.0, note_size, .{ 0.73, 0.82, 0.90, 1.0 });
    const text = try builder.finish();

    return PreparedPass.init(allocator, text, picture, .{ .hinting = .metrics });
}

fn buildHudSolidPass(allocator: std.mem.Allocator, fonts: *snail.TextAtlas, window_w: u32, _: u32) !PreparedPass {
    const title = "Status Panel";
    const line_one = "HEALTH  83";
    const line_two = "AMMO    42";
    const note = "Opaque vector backing: LCD-safe HUD text.";
    const pad_x = 20.0;
    const title_size = 24.0;
    const body_size = 18.0;
    const note_size = 13.0;
    const inner_w = max4(
        try measureTextWidth(allocator, fonts, .{ .weight = .bold }, title, title_size),
        try measureTextWidth(allocator, fonts, .{}, line_one, body_size),
        try measureTextWidth(allocator, fonts, .{}, line_two, body_size),
        try measureTextWidth(allocator, fonts, .{}, note, note_size),
    );
    const rect_w = inner_w + pad_x * 2.0;
    const rect = snail.Rect{
        .x = @as(f32, @floatFromInt(window_w)) - rect_w - 30.0,
        .y = 24.0,
        .w = rect_w,
        .h = 132.0,
    };

    var path_builder = snail.PathPictureBuilder.init(allocator);
    defer path_builder.deinit();
    try path_builder.addRoundedRect(
        rect,
        .{
            .color = .{ 0.08, 0.11, 0.14, 1.0 },
        },
        .{
            .color = .{ 0.24, 0.36, 0.44, 1.0 },
            .width = 2.0,
            .placement = .inside,
        },
        16.0,
        .identity,
    );
    try path_builder.addFilledRect(
        .{ .x = rect.x, .y = rect.y + rect.h - 26.0, .w = rect.w, .h = 26.0 },
        .{ .color = .{ 0.14, 0.20, 0.25, 1.0 } },
        .identity,
    );
    var picture = try path_builder.freeze(allocator);
    errdefer picture.deinit();

    var builder = snail.TextBlobBuilder.init(allocator, fonts);
    defer builder.deinit();
    const tx = rect.x + pad_x;
    _ = try builder.addText(.{ .weight = .bold }, title, tx, rect.y + 42.0, title_size, .{ 1.0, 1.0, 1.0, 1.0 });
    _ = try builder.addText(.{}, line_one, tx, rect.y + 74.0, body_size, .{ 0.92, 0.96, 0.98, 1.0 });
    _ = try builder.addText(.{}, line_two, tx, rect.y + 98.0, body_size, .{ 0.92, 0.96, 0.98, 1.0 });
    _ = try builder.addText(.{}, note, tx, rect.y + 124.0, note_size, .{ 0.78, 0.86, 0.92, 1.0 });
    const text = try builder.finish();

    return PreparedPass.init(allocator, text, picture, .{ .hinting = .metrics });
}

fn buildRoughWallTextPass(allocator: std.mem.Allocator, fonts: *snail.TextAtlas) !PlanePass {
    const scene_w = 760.0;
    const scene_h = 300.0;
    var builder = snail.TextBlobBuilder.init(allocator, fonts);
    defer builder.deinit();
    _ = try builder.addText(.{ .weight = .bold }, "AUTHORIZED ONLY", 46.0, 118.0, 56.0, .{ 0.06, 0.055, 0.05, 1.0 });
    _ = try builder.addText(.{}, "Text tinted directly onto the normal-mapped wall material.", 46.0, 168.0, 22.0, .{ 0.08, 0.07, 0.06, 0.96 });
    _ = try builder.addText(.{}, "The wall keeps its surface detail; the glyphs are not billboarded.", 46.0, 198.0, 18.0, .{ 0.08, 0.07, 0.06, 0.92 });
    const text = try builder.finish();

    return .{
        .prepared = try PreparedPass.init(allocator, text, null, .{ .hinting = .none }),
        .scene_width = scene_w,
        .scene_height = scene_h,
        .opaque_backdrop = true,
    };
}

fn buildCenterPanelPass(allocator: std.mem.Allocator, fonts: *snail.TextAtlas) !PlanePass {
    const scene_w = 960.0;
    const scene_h = 360.0;
    const title = "SECTOR A";
    const kicker = "OBSERVATION";
    const body = "Analytic vector text sampled in the material shader.";
    const note = "Lit by the room; never flattened into a texture.";
    const pad_x = 42.0;
    const title_size = 58.0;
    const kicker_size = 22.0;
    const body_size = 23.0;
    const note_size = 17.0;
    const inner_w = max3(
        try measureTextWidth(allocator, fonts, .{ .weight = .bold }, title, title_size),
        try measureTextWidth(allocator, fonts, .{}, body, body_size),
        try measureTextWidth(allocator, fonts, .{}, note, note_size),
    );
    const panel = snail.Rect{
        .x = @max(34.0, (scene_w - (inner_w + pad_x * 2.0)) * 0.5),
        .y = 36.0,
        .w = @min(scene_w - 68.0, inner_w + pad_x * 2.0),
        .h = 278.0,
    };

    var builder = snail.TextBlobBuilder.init(allocator, fonts);
    defer builder.deinit();
    const tx = panel.x + pad_x;
    _ = try builder.addText(.{ .weight = .bold }, kicker, panel.x + 42.0, panel.y + 76.0, kicker_size, .{ 0.10, 0.12, 0.14, 1.0 });
    _ = try builder.addText(.{ .weight = .bold }, title, tx, panel.y + 154.0, title_size, .{ 0.93, 0.96, 0.96, 1.0 });
    _ = try builder.addText(.{}, body, tx, panel.y + 204.0, body_size, .{ 0.82, 0.87, 0.88, 1.0 });
    _ = try builder.addText(.{}, note, tx, panel.y + 236.0, note_size, .{ 0.66, 0.72, 0.75, 1.0 });
    const text = try builder.finish();

    return .{
        .prepared = try PreparedPass.init(allocator, text, null, .{ .hinting = .metrics }),
        .scene_width = scene_w,
        .scene_height = scene_h,
        .opaque_backdrop = true,
    };
}

fn buildGlassPass(allocator: std.mem.Allocator, fonts: *snail.TextAtlas) !PlanePass {
    const scene_w = 760.0;
    const scene_h = 260.0;
    const title = "OBSERVATION";
    const body = "Translucent glass overlay in front of the wall.";
    const note = "Still direct-rendered, but LCD remains off on translucent backing.";
    const pad_x = 24.0;
    const inner_w = max3(
        try measureTextWidth(allocator, fonts, .{ .weight = .bold }, title, 42.0),
        try measureTextWidth(allocator, fonts, .{}, body, 21.0),
        try measureTextWidth(allocator, fonts, .{}, note, 16.0),
    );
    const rect = snail.Rect{
        .x = (scene_w - (inner_w + pad_x * 2.0)) * 0.5,
        .y = 30.0,
        .w = inner_w + pad_x * 2.0,
        .h = 196.0,
    };

    var path_builder = snail.PathPictureBuilder.init(allocator);
    defer path_builder.deinit();
    try path_builder.addRoundedRect(
        rect,
        .{
            .color = .{ 0.38, 0.70, 1.0, 0.16 },
        },
        .{
            .color = .{ 0.72, 0.90, 1.0, 0.62 },
            .width = 2.0,
            .placement = .inside,
        },
        22.0,
        .identity,
    );
    try path_builder.addFilledRect(
        .{ .x = rect.x + 24.0, .y = rect.y + 24.0, .w = rect.w - 48.0, .h = 1.5 },
        .{ .color = .{ 0.85, 0.95, 1.0, 0.55 } },
        .identity,
    );
    var picture = try path_builder.freeze(allocator);
    errdefer picture.deinit();

    var builder = snail.TextBlobBuilder.init(allocator, fonts);
    defer builder.deinit();
    const tx = rect.x + pad_x;
    _ = try builder.addText(.{ .weight = .bold }, title, tx, rect.y + 72.0, 42.0, .{ 0.92, 0.98, 1.0, 1.0 });
    _ = try builder.addText(.{}, body, tx, rect.y + 114.0, 21.0, .{ 0.84, 0.93, 0.98, 1.0 });
    _ = try builder.addText(.{}, note, tx, rect.y + 144.0, 16.0, .{ 0.72, 0.84, 0.92, 1.0 });
    const text = try builder.finish();

    return .{
        .prepared = try PreparedPass.init(allocator, text, picture, .{ .hinting = .none }),
        .scene_width = scene_w,
        .scene_height = scene_h,
        .opaque_backdrop = false,
    };
}

pub fn hudTarget(window_size: [2]u32, fb_size: [2]u32, subpixel_order: snail.SubpixelOrder, opaque_backdrop: bool) snail.ResolveTarget {
    _ = window_size;
    return .{
        .pixel_width = @floatFromInt(fb_size[0]),
        .pixel_height = @floatFromInt(fb_size[1]),
        .subpixel_order = subpixel_order,
        .is_final_composite = true,
        .opaque_backdrop = opaque_backdrop,
        .will_resample = false,
    };
}

pub fn worldTarget(fb_size: [2]u32, subpixel_order: snail.SubpixelOrder, opaque_backdrop: bool) snail.ResolveTarget {
    return .{
        .pixel_width = @floatFromInt(fb_size[0]),
        .pixel_height = @floatFromInt(fb_size[1]),
        .subpixel_order = subpixel_order,
        .is_final_composite = true,
        .opaque_backdrop = opaque_backdrop,
        .will_resample = false,
    };
}

const MaterialKind = enum {
    floor,
    ceiling,
    wall,
    rough_wall,
    panel,
};

pub const MaterialMaps = struct {
    floor: gl.GLuint = 0,
    ceiling: gl.GLuint = 0,
    wall: gl.GLuint = 0,
    rough_wall: gl.GLuint = 0,
    panel: gl.GLuint = 0,

    pub fn init(allocator: std.mem.Allocator, size: u32) !MaterialMaps {
        var maps: MaterialMaps = .{};
        errdefer maps.deinit();

        maps.floor = try createMaterialNormalMapTexture(allocator, size, .floor);
        maps.ceiling = try createMaterialNormalMapTexture(allocator, size, .ceiling);
        maps.wall = try createMaterialNormalMapTexture(allocator, size, .wall);
        maps.rough_wall = try createMaterialNormalMapTexture(allocator, size, .rough_wall);
        maps.panel = try createMaterialNormalMapTexture(allocator, size, .panel);
        return maps;
    }

    pub fn deinit(self: *MaterialMaps) void {
        if (self.floor != 0) gl.glDeleteTextures(1, &self.floor);
        if (self.ceiling != 0) gl.glDeleteTextures(1, &self.ceiling);
        if (self.wall != 0) gl.glDeleteTextures(1, &self.wall);
        if (self.rough_wall != 0) gl.glDeleteTextures(1, &self.rough_wall);
        if (self.panel != 0) gl.glDeleteTextures(1, &self.panel);
        self.* = .{};
    }
};

fn createMaterialNormalMapTexture(allocator: std.mem.Allocator, size: u32, kind: MaterialKind) !gl.GLuint {
    const side: usize = @intCast(size);
    const texel_count = side * side;
    const pixel_count = texel_count * 4;
    const heights = try allocator.alloc(f32, texel_count);
    defer allocator.free(heights);
    const data = try allocator.alloc(u8, pixel_count);
    defer allocator.free(data);

    var min_height: f32 = std.math.inf(f32);
    var max_height: f32 = -std.math.inf(f32);
    for (0..side) |y| {
        for (0..side) |x| {
            const index = y * side + x;
            const h = materialHeight(kind, @floatFromInt(x), @floatFromInt(y), size);
            heights[index] = h;
            min_height = @min(min_height, h);
            max_height = @max(max_height, h);
        }
    }
    const height_scale = if (max_height - min_height > 1e-5) 1.0 / (max_height - min_height) else 1.0;
    const normal_scale = materialNormalScale(kind);

    for (0..side) |y| {
        for (0..side) |x| {
            const xi: i32 = @intCast(x);
            const yi: i32 = @intCast(y);
            const h = sampleMaterialHeight(heights, side, xi, yi);
            const h_l = sampleMaterialHeight(heights, side, xi - 1, yi);
            const h_r = sampleMaterialHeight(heights, side, xi + 1, yi);
            const h_d = sampleMaterialHeight(heights, side, xi, yi - 1);
            const h_u = sampleMaterialHeight(heights, side, xi, yi + 1);
            const dx = h_r - h_l;
            const dy = h_u - h_d;

            var nx: f32 = -dx * normal_scale;
            var ny: f32 = -dy * normal_scale;
            var nz: f32 = 1.0;
            const len = @sqrt(nx * nx + ny * ny + nz * nz);
            nx /= len;
            ny /= len;
            nz /= len;

            const encoded_h = std.math.clamp((((h - min_height) * height_scale) - 0.5) * 1.42 + 0.5, 0.0, 1.0);

            const base = (y * side + x) * 4;
            data[base + 0] = encodeUnorm8(nx * 0.5 + 0.5);
            data[base + 1] = encodeUnorm8(ny * 0.5 + 0.5);
            data[base + 2] = encodeUnorm8(nz * 0.5 + 0.5);
            data[base + 3] = encodeUnorm8(encoded_h);
        }
    }

    var texture: gl.GLuint = 0;
    gl.glGenTextures(1, &texture);
    gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        gl.GL_RGBA8,
        @intCast(size),
        @intCast(size),
        0,
        gl.GL_RGBA,
        gl.GL_UNSIGNED_BYTE,
        data.ptr,
    );
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR_MIPMAP_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_REPEAT);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_REPEAT);
    gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
    return texture;
}

fn sampleMaterialHeight(heights: []const f32, side: usize, x: i32, y: i32) f32 {
    const s: i32 = @intCast(side);
    const wrapped_x: usize = @intCast(@mod(x, s));
    const wrapped_y: usize = @intCast(@mod(y, s));
    return heights[wrapped_y * side + wrapped_x];
}

fn materialHeight(kind: MaterialKind, x: f32, y: f32, size: u32) f32 {
    const s = @as(f32, @floatFromInt(size));
    const ux = x / s;
    const uy = y / s;
    return switch (kind) {
        .floor => floorHeight(ux, uy),
        .ceiling => ceilingHeight(ux, uy),
        .wall => plasterHeight(ux, uy, 301, 0.62),
        .rough_wall => plasterHeight(ux, uy, 907, 1.0) - cellularPits(ux, uy, 58, 44, 1193) * 0.16 + crackMask(ux, uy, 1609) * 0.08,
        .panel => panelHeight(ux, uy),
    };
}

fn materialNormalScale(kind: MaterialKind) f32 {
    return switch (kind) {
        .floor => 8.8,
        .ceiling => 4.8,
        .wall => 6.6,
        .rough_wall => 9.4,
        .panel => 4.2,
    };
}

fn floorHeight(ux: f32, uy: f32) f32 {
    const seams = gridGroove(ux, uy, 6, 6, 0.018);
    const slab = tileFbm2(ux, uy, 14, 14, 5, 101, 0.53);
    const aggregate = tileFbm2(ux, uy, 72, 64, 4, 211, 0.48);
    const scuffs = scratchLines(ux, uy, 96, 307) * 0.10;
    const pits = cellularPits(ux, uy, 46, 46, 409) * 0.12;
    return slab * 0.34 + aggregate * 0.10 - seams * 0.58 - pits - scuffs;
}

fn ceilingHeight(ux: f32, uy: f32) f32 {
    const panels = gridGroove(ux, uy, 8, 4, 0.010);
    const broad = tileFbm2(ux, uy, 7, 5, 4, 503, 0.55);
    const stipple = tileFbm2(ux, uy, 96, 88, 3, 607, 0.46);
    return broad * 0.22 + stipple * 0.08 - panels * 0.20;
}

fn plasterHeight(ux: f32, uy: f32, seed: u32, roughness: f32) f32 {
    const warp_x = tileFbm2(ux, uy, 3, 4, 4, seed + 11, 0.54) * 0.035;
    const warp_y = tileFbm2(ux, uy, 4, 3, 4, seed + 29, 0.54) * 0.030;
    const u = common.fract(ux + warp_x);
    const v = common.fract(uy + warp_y);
    const broad = tileFbm2(u, v, 5, 4, 5, seed + 41, 0.55);
    const trowel = @abs(tileFbm2(u, v, 16, 11, 4, seed + 71, 0.50)) * 2.0 - 1.0;
    const grit = tileFbm2(u, v, 88, 76, 3, seed + 97, 0.45);
    const pores = cellularPits(u, v, 72, 56, seed + 131);
    return broad * 0.38 + trowel * 0.18 * roughness + grit * 0.08 * roughness - pores * 0.10 * roughness;
}

fn panelHeight(ux: f32, uy: f32) f32 {
    const brushed = tileFbm2(ux, uy, 112, 9, 4, 709, 0.50);
    const fine = tileFbm2(ux, uy, 180, 36, 3, 811, 0.42);
    const scratches = scratchLines(ux, uy, 128, 919);
    const pressed = gridGroove(ux, uy, 1, 1, 0.018) * 0.10;
    return brushed * 0.18 + fine * 0.06 - scratches * 0.14 - pressed;
}

fn tileFbm2(ux: f32, uy: f32, base_cells_x: u32, base_cells_y: u32, octaves: u32, seed: u32, gain: f32) f32 {
    var sum: f32 = 0.0;
    var amplitude: f32 = 0.55;
    var norm: f32 = 0.0;
    var cells_x = base_cells_x;
    var cells_y = base_cells_y;
    var i: u32 = 0;
    while (i < octaves) : (i += 1) {
        sum += tileValueNoise2(ux, uy, cells_x, cells_y, seed + i * 131) * amplitude;
        norm += amplitude;
        amplitude *= gain;
        cells_x *= 2;
        cells_y *= 2;
    }
    return if (norm > 1e-6) sum / norm else 0.0;
}

fn tileValueNoise2(ux: f32, uy: f32, cells_x: u32, cells_y: u32, seed: u32) f32 {
    const x = common.fract(ux) * @as(f32, @floatFromInt(cells_x));
    const y = common.fract(uy) * @as(f32, @floatFromInt(cells_y));
    const x0f = @floor(x);
    const y0f = @floor(y);
    const x0: i32 = @intFromFloat(x0f);
    const y0: i32 = @intFromFloat(y0f);
    const tx = smoother01(x - x0f);
    const ty = smoother01(y - y0f);

    const v00 = hashCell(wrapCell(x0, cells_x), wrapCell(y0, cells_y), seed);
    const v10 = hashCell(wrapCell(x0 + 1, cells_x), wrapCell(y0, cells_y), seed);
    const v01 = hashCell(wrapCell(x0, cells_x), wrapCell(y0 + 1, cells_y), seed);
    const v11 = hashCell(wrapCell(x0 + 1, cells_x), wrapCell(y0 + 1, cells_y), seed);

    const ix0 = std.math.lerp(v00, v10, tx);
    const ix1 = std.math.lerp(v01, v11, tx);
    return std.math.lerp(ix0, ix1, ty) * 2.0 - 1.0;
}

fn cellularPits(ux: f32, uy: f32, cells_x: u32, cells_y: u32, seed: u32) f32 {
    const x = common.fract(ux) * @as(f32, @floatFromInt(cells_x));
    const y = common.fract(uy) * @as(f32, @floatFromInt(cells_y));
    const xi: i32 = @intFromFloat(@floor(x));
    const yi: i32 = @intFromFloat(@floor(y));

    var min_dist2: f32 = 100.0;
    var oy: i32 = -1;
    while (oy <= 1) : (oy += 1) {
        var ox: i32 = -1;
        while (ox <= 1) : (ox += 1) {
            const cx = xi + ox;
            const cy = yi + oy;
            const wx = wrapCell(cx, cells_x);
            const wy = wrapCell(cy, cells_y);
            const jx = hashCell(wx, wy, seed + 17);
            const jy = hashCell(wx, wy, seed + 53);
            const dx = (@as(f32, @floatFromInt(cx)) + jx) - x;
            const dy = (@as(f32, @floatFromInt(cy)) + jy) - y;
            min_dist2 = @min(min_dist2, dx * dx + dy * dy);
        }
    }

    return 1.0 - smoothstep(0.06, 0.42, @sqrt(min_dist2));
}

fn gridGroove(ux: f32, uy: f32, cells_x: u32, cells_y: u32, width: f32) f32 {
    const fx = common.fract(ux * @as(f32, @floatFromInt(cells_x)));
    const fy = common.fract(uy * @as(f32, @floatFromInt(cells_y)));
    const dx = @min(fx, 1.0 - fx);
    const dy = @min(fy, 1.0 - fy);
    const gx = 1.0 - smoothstep(width, width * 2.8, dx);
    const gy = 1.0 - smoothstep(width, width * 2.8, dy);
    return @max(gx, gy);
}

fn scratchLines(ux: f32, uy: f32, rows: u32, seed: u32) f32 {
    const y = common.fract(uy) * @as(f32, @floatFromInt(rows));
    const row_i: i32 = @intFromFloat(@floor(y));
    const row = wrapCell(row_i, rows);
    const fy = y - @floor(y);
    const center = 0.18 + hashCell(row, 0, seed) * 0.64;
    const width = 0.020 + hashCell(row, 1, seed) * 0.035;
    const line = 1.0 - smoothstep(width, width * 2.5, @abs(fy - center));
    const broken = smoothstep(0.28, 0.78, tileValueNoise2(ux, uy, 48, rows, seed + 101) * 0.5 + 0.5);
    return line * broken;
}

fn crackMask(ux: f32, uy: f32, seed: u32) f32 {
    const web = @abs(tileFbm2(ux, uy, 18, 14, 4, seed, 0.50));
    return 1.0 - smoothstep(0.015, 0.085, web);
}

fn smoother01(t: f32) f32 {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

fn wrapCell(v: i32, period: u32) u32 {
    const p: i32 = @intCast(period);
    return @intCast(@mod(v, p));
}

fn hashCell(x: u32, y: u32, seed: u32) f32 {
    var h = x *% 0x8da6b343;
    h ^= y *% 0xd8163841;
    h ^= seed *% 0xcb1ab31f;
    h ^= h >> 16;
    h *%= 0x7feb352d;
    h ^= h >> 15;
    h *%= 0x846ca68b;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h & 0x00ffffff)) / 16777215.0;
}

fn encodeUnorm8(v: f32) u8 {
    return @intFromFloat(std.math.clamp(v, 0.0, 1.0) * 255.0 + 0.5);
}

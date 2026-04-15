//! HarfBuzz text shaping integration.
//! Provides full OpenType shaping (Arabic, Devanagari, etc.)
//! via the HarfBuzz library. Compile with -Dharfbuzz=true.

const std = @import("std");
const hb = @cImport({
    @cInclude("hb.h");
});
const ttf = @import("ttf.zig");

pub const ShapedGlyph = struct {
    glyph_id: u16,
    x_offset: f32,
    y_offset: f32,
};

pub const HarfBuzzShaper = struct {
    hb_face: *hb.hb_face_t,
    hb_font: *hb.hb_font_t,
    hb_buffer: *hb.hb_buffer_t,
    units_per_em: u16,

    pub fn init(font_data: []const u8, units_per_em: u16) !HarfBuzzShaper {
        const blob = hb.hb_blob_create(
            font_data.ptr,
            @intCast(font_data.len),
            hb.HB_MEMORY_MODE_READONLY,
            null,
            null,
        ) orelse return error.HarfBuzzInitFailed;

        const face = hb.hb_face_create(blob, 0) orelse {
            hb.hb_blob_destroy(blob);
            return error.HarfBuzzInitFailed;
        };
        hb.hb_blob_destroy(blob);

        const font = hb.hb_font_create(face) orelse {
            hb.hb_face_destroy(face);
            return error.HarfBuzzInitFailed;
        };

        const buffer = hb.hb_buffer_create() orelse {
            hb.hb_font_destroy(font);
            hb.hb_face_destroy(face);
            return error.HarfBuzzInitFailed;
        };

        const upem: c_int = @intCast(units_per_em);
        hb.hb_font_set_scale(font, upem, upem);

        return .{
            .hb_face = face,
            .hb_font = font,
            .hb_buffer = buffer,
            .units_per_em = units_per_em,
        };
    }

    pub fn deinit(self: *HarfBuzzShaper) void {
        hb.hb_buffer_destroy(self.hb_buffer);
        hb.hb_font_destroy(self.hb_font);
        hb.hb_face_destroy(self.hb_face);
    }

    /// Shape text into the reusable buffer. Returns glyph count, infos, and positions.
    fn shapeText(self: *const HarfBuzzShaper, text: []const u8) struct {
        count: c_uint,
        infos: [*c]hb.hb_glyph_info_t,
        positions: [*c]hb.hb_glyph_position_t,
    } {
        hb.hb_buffer_clear_contents(self.hb_buffer);
        hb.hb_buffer_add_utf8(self.hb_buffer, text.ptr, @intCast(text.len), 0, @intCast(text.len));
        hb.hb_buffer_guess_segment_properties(self.hb_buffer);
        hb.hb_shape(self.hb_font, self.hb_buffer, null, 0);

        var count: c_uint = 0;
        const infos = hb.hb_buffer_get_glyph_infos(self.hb_buffer, &count);
        const positions = hb.hb_buffer_get_glyph_positions(self.hb_buffer, &count);
        return .{ .count = count, .infos = infos, .positions = positions };
    }

    /// Shape text and emit glyphs directly into a vertex buffer.
    /// Zero-allocation: reuses internal HarfBuzz buffer, iterates output in-place.
    /// Returns the total advance width in pixels.
    pub fn shapeAndEmit(
        self: *const HarfBuzzShaper,
        text: []const u8,
        font_size: f32,
        x: f32,
        y: f32,
        color: [4]f32,
        atlas: anytype,
        batch: anytype,
        atlas_layer: u8,
    ) f32 {
        const shaped = self.shapeText(text);
        if (shaped.count == 0 or shaped.infos == null or shaped.positions == null) return 0;

        const scale = font_size / @as(f32, @floatFromInt(self.units_per_em));
        var cursor_x: f32 = 0;
        var cursor_y: f32 = 0;

        for (0..shaped.count) |i| {
            const gid: u16 = @intCast(shaped.infos[i].codepoint);
            const pos = shaped.positions[i];

            const glyph_x = x + (cursor_x + @as(f32, @floatFromInt(pos.x_offset))) * scale;
            const glyph_y = y + (cursor_y + @as(f32, @floatFromInt(pos.y_offset))) * scale;

            // COLRv0: expand base glyph into per-layer outline glyphs with palette colors
            var layer_buf: [64]ttf.Font.ColrLayer = undefined;
            const layers = atlas.getColrLayers(gid, &layer_buf);
            if (layers.len > 0) {
                for (layers) |layer| {
                    if (atlas.getGlyph(layer.glyph_id)) |linfo| {
                        if (linfo.band_entry.h_band_count > 0 and linfo.band_entry.v_band_count > 0) {
                            const lcolor: [4]f32 = if (layer.color[0] < 0) color else layer.color;
                            if (!batch.addGlyph(glyph_x, glyph_y, font_size, linfo.bbox, linfo.band_entry, lcolor, atlas_layer)) break;
                        }
                    }
                }
            } else if (atlas.getGlyph(gid)) |info| {
                if (!batch.addGlyph(glyph_x, glyph_y, font_size, info.bbox, info.band_entry, color, atlas_layer)) break;
            }

            cursor_x += @as(f32, @floatFromInt(pos.x_advance));
            cursor_y += @as(f32, @floatFromInt(pos.y_advance));
        }

        return cursor_x * scale;
    }

    /// Measure the advance width of shaped text without emitting vertices.
    pub fn measureWidth(self: *const HarfBuzzShaper, text: []const u8, font_size: f32) f32 {
        const shaped = self.shapeText(text);
        if (shaped.count == 0 or shaped.positions == null) return 0;

        const scale = font_size / @as(f32, @floatFromInt(self.units_per_em));
        var width: f32 = 0;
        for (0..shaped.count) |i| {
            width += @as(f32, @floatFromInt(shaped.positions[i].x_advance));
        }
        return width * scale;
    }

    /// Discover all glyph IDs that HarfBuzz produces for the given text.
    /// Caller owns returned slice.
    pub fn discoverGlyphs(self: *const HarfBuzzShaper, allocator: std.mem.Allocator, text: []const u8) ![]u16 {
        const shaped = self.shapeText(text);
        if (shaped.count == 0 or shaped.infos == null) return &.{};

        // Deduplicate
        var seen = std.AutoHashMap(u16, void).init(allocator);
        defer seen.deinit();

        for (0..shaped.count) |i| {
            const gid: u16 = @intCast(shaped.infos[i].codepoint);
            if (gid != 0) try seen.put(gid, {});
        }

        var result = try allocator.alloc(u16, seen.count());
        var idx: usize = 0;
        var it = seen.keyIterator();
        while (it.next()) |k| {
            result[idx] = k.*;
            idx += 1;
        }
        return result;
    }
};

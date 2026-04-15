//! HarfBuzz text shaping integration.
//! Provides full OpenType shaping (Arabic, Devanagari, etc.)
//! via the HarfBuzz library. Compile with -Dharfbuzz=true.

const std = @import("std");
const hb = @cImport({
    @cInclude("hb.h");
});

pub const ShapedGlyph = struct {
    glyph_id: u16,
    x_offset: f32,
    y_offset: f32,
};

pub const HarfBuzzShaper = struct {
    hb_face: *hb.hb_face_t,
    hb_font: *hb.hb_font_t,
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

        const upem: c_int = @intCast(units_per_em);
        hb.hb_font_set_scale(font, upem, upem);

        return .{
            .hb_face = face,
            .hb_font = font,
            .units_per_em = units_per_em,
        };
    }

    pub fn deinit(self: *HarfBuzzShaper) void {
        hb.hb_font_destroy(self.hb_font);
        hb.hb_face_destroy(self.hb_face);
    }

    /// Shape text and emit glyphs directly into a vertex buffer via the callback.
    /// Zero-allocation: iterates HarfBuzz's internal output arrays.
    /// Returns the total advance width in pixels.
    pub fn shapeAndEmit(
        self: *const HarfBuzzShaper,
        text: []const u8,
        font_size: f32,
        x: f32,
        y: f32,
        color: [4]f32,
        atlas_glyph_map: anytype,
        batch: anytype,
    ) f32 {
        const buf = hb.hb_buffer_create() orelse return 0;
        defer hb.hb_buffer_destroy(buf);

        hb.hb_buffer_add_utf8(buf, text.ptr, @intCast(text.len), 0, @intCast(text.len));
        hb.hb_buffer_guess_segment_properties(buf);
        hb.hb_shape(self.hb_font, buf, null, 0);

        var glyph_count: c_uint = 0;
        const infos = hb.hb_buffer_get_glyph_infos(buf, &glyph_count);
        const positions = hb.hb_buffer_get_glyph_positions(buf, &glyph_count);

        if (glyph_count == 0 or infos == null or positions == null) return 0;

        const scale = font_size / @as(f32, @floatFromInt(self.units_per_em));
        var cursor_x: f32 = 0;
        var cursor_y: f32 = 0;

        for (0..glyph_count) |i| {
            const gid: u16 = @intCast(infos[i].codepoint);
            const pos = positions[i];

            const glyph_x = x + (cursor_x + @as(f32, @floatFromInt(pos.x_offset))) * scale;
            const glyph_y = y + (cursor_y + @as(f32, @floatFromInt(pos.y_offset))) * scale;

            if (atlas_glyph_map.get(gid)) |info| {
                if (info.band_entry.h_band_count > 0 and info.band_entry.v_band_count > 0) {
                    if (!batch.addGlyph(glyph_x, glyph_y, font_size, info.bbox, info.band_entry, color)) break;
                }
            }

            cursor_x += @as(f32, @floatFromInt(pos.x_advance));
            cursor_y += @as(f32, @floatFromInt(pos.y_advance));
        }

        return cursor_x * scale;
    }

    /// Discover all glyph IDs that HarfBuzz produces for the given text.
    /// Caller owns returned slice.
    pub fn discoverGlyphs(self: *const HarfBuzzShaper, allocator: std.mem.Allocator, text: []const u8) ![]u16 {
        const buf = hb.hb_buffer_create() orelse return error.HarfBuzzShapeFailed;
        defer hb.hb_buffer_destroy(buf);

        hb.hb_buffer_add_utf8(buf, text.ptr, @intCast(text.len), 0, @intCast(text.len));
        hb.hb_buffer_guess_segment_properties(buf);
        hb.hb_shape(self.hb_font, buf, null, 0);

        var glyph_count: c_uint = 0;
        const infos = hb.hb_buffer_get_glyph_infos(buf, &glyph_count);
        if (glyph_count == 0 or infos == null) return &.{};

        // Deduplicate
        var seen = std.AutoHashMap(u16, void).init(allocator);
        defer seen.deinit();

        for (0..glyph_count) |i| {
            const gid: u16 = @intCast(infos[i].codepoint);
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

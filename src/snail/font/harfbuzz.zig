//! HarfBuzz text shaping integration.
//! Provides full OpenType shaping (Arabic, Devanagari, etc.)
//! via the HarfBuzz library. Compile with -Dharfbuzz=true.

const std = @import("std");
const hb = @cImport({
    @cInclude("hb.h");
});

pub const Feature = hb.hb_feature_t;
pub const FEATURE_GLOBAL_START: c_uint = 0;
pub const FEATURE_GLOBAL_END: c_uint = 0xFFFFFFFF;

pub fn makeTag(tag: [4]u8) u32 {
    return (@as(u32, tag[0]) << 24) | (@as(u32, tag[1]) << 16) |
        (@as(u32, tag[2]) << 8) | @as(u32, tag[3]);
}

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
    pub fn shapeText(self: *const HarfBuzzShaper, text: []const u8) struct {
        count: c_uint,
        infos: [*c]hb.hb_glyph_info_t,
        positions: [*c]hb.hb_glyph_position_t,
    } {
        return self.shapeTextWithFeatures(text, &.{});
    }

    /// Shape text with explicit OpenType feature requests. `features` are in
    /// the buffer's local coordinates (start/end indices into `text`).
    pub fn shapeTextWithFeatures(
        self: *const HarfBuzzShaper,
        text: []const u8,
        features: []const hb.hb_feature_t,
    ) struct {
        count: c_uint,
        infos: [*c]hb.hb_glyph_info_t,
        positions: [*c]hb.hb_glyph_position_t,
    } {
        hb.hb_buffer_clear_contents(self.hb_buffer);
        hb.hb_buffer_add_utf8(self.hb_buffer, text.ptr, @intCast(text.len), 0, @intCast(text.len));
        hb.hb_buffer_guess_segment_properties(self.hb_buffer);
        const features_ptr: [*c]const hb.hb_feature_t = if (features.len == 0) null else features.ptr;
        hb.hb_shape(self.hb_font, self.hb_buffer, features_ptr, @intCast(features.len));

        var count: c_uint = 0;
        const infos = hb.hb_buffer_get_glyph_infos(self.hb_buffer, &count);
        const positions = hb.hb_buffer_get_glyph_positions(self.hb_buffer, &count);
        return .{ .count = count, .infos = infos, .positions = positions };
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

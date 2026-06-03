const std = @import("std");
const tt_outline = @import("truetype/outline.zig");
const vec = @import("../math/vec.zig");
const bezier_mod = @import("../math/bezier.zig");
const Vec2 = vec.Vec2;
const QuadBezier = bezier_mod.QuadBezier;
const BBox = bezier_mod.BBox;

pub const GlyphMetrics = struct {
    advance_width: u16,
    lsb: i16,
    bbox: BBox,
};

pub const LineMetrics = struct {
    ascent: i16,
    descent: i16,
    line_gap: i16,
};

/// Text decoration metrics from the OS/2 and post tables.
/// All values are in font units — scale by (font_size / units_per_em).
pub const DecorationMetrics = struct {
    /// Top of underline stroke relative to baseline; negative = below (from post table).
    underline_position: i16,
    /// Underline stroke thickness (from post table).
    underline_thickness: i16,
    /// Strikethrough stroke position above baseline (from OS/2 table).
    strikethrough_position: i16,
    /// Strikethrough stroke thickness (from OS/2 table).
    strikethrough_thickness: i16,
};

/// Superscript or subscript metrics from the OS/2 table.
/// All values are in font units.
pub const ScriptMetrics = struct {
    x_size: i16,
    y_size: i16,
    x_offset: i16,
    y_offset: i16,
};

pub const Contour = struct {
    curves: []const QuadBezier,
};

pub const Glyph = struct {
    contours: []const Contour,
    metrics: GlyphMetrics,
};

fn freeContourCurves(allocator: std.mem.Allocator, contours: []const Contour) void {
    for (contours) |contour| {
        if (contour.curves.len > 0) allocator.free(contour.curves);
    }
}

/// Parsed TrueType font. Immutable after init — all methods are const.
/// Thread-safe for concurrent reads (glyphIndex, getKerning, parseGlyph
/// with separate scratch allocators per thread).
pub const Font = struct {
    data: []const u8,
    units_per_em: u16 = 1000,
    num_glyphs: u16 = 0,
    cmap_offset: u32 = 0,
    glyf_offset: u32 = 0,
    loca_offset: u32 = 0,
    head_offset: u32 = 0,
    hhea_offset: u32 = 0,
    hmtx_offset: u32 = 0,
    maxp_offset: u32 = 0,
    kern_offset: u32 = 0,
    gsub_offset: u32 = 0,
    gpos_offset: u32 = 0,
    colr_offset: u32 = 0,
    cpal_offset: u32 = 0,
    os2_offset: u32 = 0,
    post_offset: u32 = 0,
    index_to_loc_format: i16 = 0,
    num_h_metrics: u16 = 0,
    cmap_subtable_offset: u32 = 0,
    cmap_subtable_format: u16 = 0,
    ascii_glyph_lut: [128]u16 = .{0} ** 128,

    pub fn init(data: []const u8) !Font {
        var font = Font{ .data = data };
        try font.parseTableDirectory();
        try font.parseHead();
        try font.parseMaxp();
        try font.parseHhea();
        try font.initCmapLookup();
        return font;
    }

    fn readU16(data: []const u8, offset: usize) !u16 {
        if (offset + 2 > data.len) return error.UnexpectedEof;
        return std.mem.readInt(u16, data[offset..][0..2], .big);
    }

    fn readI16(data: []const u8, offset: usize) !i16 {
        if (offset + 2 > data.len) return error.UnexpectedEof;
        return std.mem.readInt(i16, data[offset..][0..2], .big);
    }

    fn readU32(data: []const u8, offset: usize) !u32 {
        if (offset + 4 > data.len) return error.UnexpectedEof;
        return std.mem.readInt(u32, data[offset..][0..4], .big);
    }

    fn tableFields(self: *Font) [14]struct { tag: *const [4]u8, dest: *u32 } {
        return .{
            .{ .tag = "head", .dest = &self.head_offset },
            .{ .tag = "maxp", .dest = &self.maxp_offset },
            .{ .tag = "cmap", .dest = &self.cmap_offset },
            .{ .tag = "glyf", .dest = &self.glyf_offset },
            .{ .tag = "loca", .dest = &self.loca_offset },
            .{ .tag = "hhea", .dest = &self.hhea_offset },
            .{ .tag = "hmtx", .dest = &self.hmtx_offset },
            .{ .tag = "kern", .dest = &self.kern_offset },
            .{ .tag = "GSUB", .dest = &self.gsub_offset },
            .{ .tag = "GPOS", .dest = &self.gpos_offset },
            .{ .tag = "COLR", .dest = &self.colr_offset },
            .{ .tag = "CPAL", .dest = &self.cpal_offset },
            .{ .tag = "OS/2", .dest = &self.os2_offset },
            .{ .tag = "post", .dest = &self.post_offset },
        };
    }

    fn parseTableDirectory(self: *Font) !void {
        if (self.data.len < 12) return error.InvalidFont;
        const num_tables = try readU16(self.data, 4);
        const fields = self.tableFields();
        var offset: usize = 12;
        for (0..num_tables) |_| {
            if (offset + 16 > self.data.len) return error.UnexpectedEof;
            const tag = self.data[offset .. offset + 4];
            const table_offset = try readU32(self.data, offset + 8);
            for (fields) |entry| {
                if (std.mem.eql(u8, tag, entry.tag)) {
                    entry.dest.* = table_offset;
                    break;
                }
            }
            offset += 16;
        }
        if (self.head_offset == 0 or self.glyf_offset == 0 or self.loca_offset == 0)
            return error.MissingRequiredTable;
    }

    fn parseHead(self: *Font) !void {
        self.units_per_em = try readU16(self.data, self.head_offset + 18);
        self.index_to_loc_format = try readI16(self.data, self.head_offset + 50);
    }

    fn parseMaxp(self: *Font) !void {
        self.num_glyphs = try readU16(self.data, self.maxp_offset + 4);
    }

    fn parseHhea(self: *Font) !void {
        self.num_h_metrics = try readU16(self.data, self.hhea_offset + 34);
    }

    fn validateGlyphId(self: *const Font, glyph_id: u16) ParseError!void {
        if (glyph_id >= self.num_glyphs) return error.InvalidFont;
    }

    fn initCmapLookup(self: *Font) !void {
        if (self.cmap_offset == 0) return error.MissingRequiredTable;

        const base = self.cmap_offset;
        const num_subtables = try readU16(self.data, base + 2);
        var best_offset: u32 = 0;
        var best_format: u16 = 0;

        for (0..num_subtables) |i| {
            const rec = base + 4 + @as(u32, @intCast(i)) * 8;
            const platform_id = try readU16(self.data, rec);
            const encoding_id = try readU16(self.data, rec + 2);
            const sub_offset = try readU32(self.data, rec + 4);
            if ((platform_id == 0) or (platform_id == 3 and (encoding_id == 1 or encoding_id == 10))) {
                const fmt = try readU16(self.data, base + sub_offset);
                if (fmt == 4 or fmt == 12) {
                    if (fmt > best_format or best_offset == 0) {
                        best_offset = base + sub_offset;
                        best_format = fmt;
                    }
                }
            }
        }

        if (best_offset == 0) return error.NoCmapSubtable;

        self.cmap_subtable_offset = best_offset;
        self.cmap_subtable_format = best_format;

        for (0..self.ascii_glyph_lut.len) |i| {
            self.ascii_glyph_lut[i] = try self.glyphIndexSlow(@intCast(i));
        }
    }

    pub fn glyphIndex(self: *const Font, codepoint: u32) !u16 {
        if (codepoint < self.ascii_glyph_lut.len) {
            return self.ascii_glyph_lut[@intCast(codepoint)];
        }
        return self.glyphIndexSlow(codepoint);
    }

    fn glyphIndexSlow(self: *const Font, codepoint: u32) !u16 {
        if (self.cmap_subtable_offset == 0) return error.NoCmapSubtable;
        return switch (self.cmap_subtable_format) {
            4 => self.cmapFormat4Lookup(self.cmap_subtable_offset, codepoint),
            12 => self.cmapFormat12Lookup(self.cmap_subtable_offset, codepoint),
            else => error.UnsupportedCmapFormat,
        };
    }

    fn cmapFormat4Lookup(self: *const Font, offset: u32, codepoint: u32) !u16 {
        if (codepoint > 0xFFFF) return 0;
        const cp: u16 = @intCast(codepoint);
        const seg_count = (try readU16(self.data, offset + 6)) / 2;
        const end_codes = offset + 14;
        const start_codes = end_codes + @as(u32, seg_count) * 2 + 2;
        const id_deltas = start_codes + @as(u32, seg_count) * 2;
        const id_range_offsets = id_deltas + @as(u32, seg_count) * 2;
        var lo: u32 = 0;
        var hi: u32 = seg_count;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            const end_code = try readU16(self.data, end_codes + mid * 2);
            if (end_code < cp) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        if (lo >= seg_count) return 0;

        const idx = lo;
        const start_code = try readU16(self.data, start_codes + idx * 2);
        if (start_code > cp) return 0;

        const range_offset = try readU16(self.data, id_range_offsets + idx * 2);
        if (range_offset == 0) {
            const delta = try readI16(self.data, id_deltas + idx * 2);
            return @bitCast(@as(i16, @bitCast(cp)) +% delta);
        }

        const glyph_addr = id_range_offsets + idx * 2 + range_offset + (cp - start_code) * 2;
        const glyph_id = try readU16(self.data, glyph_addr);
        if (glyph_id == 0) return 0;
        const delta = try readI16(self.data, id_deltas + idx * 2);
        return @bitCast(@as(i16, @bitCast(glyph_id)) +% delta);
    }

    fn cmapFormat12Lookup(self: *const Font, offset: u32, codepoint: u32) !u16 {
        const n_groups = try readU32(self.data, offset + 12);
        const groups_base = offset + 16;
        var lo: u32 = 0;
        var hi: u32 = n_groups;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            const start_char = try readU32(self.data, groups_base + mid * 12);
            if (start_char <= codepoint) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        if (lo == 0) return 0;

        const idx = lo - 1;
        const g = groups_base + idx * 12;
        const start_char = try readU32(self.data, g);
        const end_char = try readU32(self.data, g + 4);
        if (codepoint > end_char) return 0;
        const start_glyph = try readU32(self.data, g + 8);
        return @intCast(start_glyph + (codepoint - start_char));
    }

    fn glyphOffset(self: *const Font, glyph_id: u16) !u32 {
        if (self.index_to_loc_format == 0) {
            const off = try readU16(self.data, self.loca_offset + @as(u32, glyph_id) * 2);
            return @as(u32, off) * 2;
        } else {
            return try readU32(self.data, self.loca_offset + @as(u32, glyph_id) * 4);
        }
    }

    fn glyphLength(self: *const Font, glyph_id: u16) !u32 {
        const off0 = try self.glyphOffset(glyph_id);
        const off1 = try self.glyphOffset(glyph_id + 1);
        if (off1 < off0) return error.InvalidFont;
        return off1 - off0;
    }

    fn getHMetrics(self: *const Font, glyph_id: u16) !GlyphMetrics {
        var advance: u16 = 0;
        var lsb: i16 = 0;
        if (glyph_id < self.num_h_metrics) {
            const off = self.hmtx_offset + @as(u32, glyph_id) * 4;
            advance = try readU16(self.data, off);
            lsb = try readI16(self.data, off + 2);
        } else {
            const off = self.hmtx_offset + (@as(u32, self.num_h_metrics) - 1) * 4;
            advance = try readU16(self.data, off);
            const lsb_off = self.hmtx_offset + @as(u32, self.num_h_metrics) * 4 +
                (@as(u32, glyph_id) - self.num_h_metrics) * 2;
            lsb = try readI16(self.data, lsb_off);
        }
        return .{ .advance_width = advance, .lsb = lsb, .bbox = .{ .min = Vec2.zero, .max = Vec2.zero } };
    }

    pub const ParseError = error{
        UnexpectedEof,
        InvalidFont,
        MissingRequiredTable,
        NoCmapSubtable,
        UnsupportedCmapFormat,
        OutOfMemory,
    };

    /// Read per-glyph metrics directly from font tables without building an atlas.
    pub fn glyphMetrics(self: *const Font, glyph_id: u16) ParseError!GlyphMetrics {
        try self.validateGlyphId(glyph_id);

        var metrics = try self.getHMetrics(glyph_id);
        const glyph_len = try self.glyphLength(glyph_id);
        if (glyph_len == 0) return metrics;

        const base = self.glyf_offset + try self.glyphOffset(glyph_id);
        const xmin: f32 = @floatFromInt(try readI16(self.data, base + 2));
        const ymin: f32 = @floatFromInt(try readI16(self.data, base + 4));
        const xmax: f32 = @floatFromInt(try readI16(self.data, base + 6));
        const ymax: f32 = @floatFromInt(try readI16(self.data, base + 8));
        const scale = 1.0 / @as(f32, @floatFromInt(self.units_per_em));
        metrics.bbox = .{
            .min = Vec2.new(xmin * scale, ymin * scale),
            .max = Vec2.new(xmax * scale, ymax * scale),
        };
        return metrics;
    }

    pub fn advanceWidth(self: *const Font, glyph_id: u16) ParseError!i16 {
        try self.validateGlyphId(glyph_id);
        const metrics = try self.getHMetrics(glyph_id);
        return std.math.cast(i16, metrics.advance_width) orelse error.InvalidFont;
    }

    pub fn lineMetrics(self: *const Font) ParseError!LineMetrics {
        if (self.hhea_offset == 0) return error.MissingRequiredTable;
        return .{
            .ascent = try readI16(self.data, self.hhea_offset + 4),
            .descent = try readI16(self.data, self.hhea_offset + 6),
            .line_gap = try readI16(self.data, self.hhea_offset + 8),
        };
    }

    /// Underline and strikethrough metrics from the post and OS/2 tables.
    pub fn decorationMetrics(self: *const Font) ParseError!DecorationMetrics {
        if (self.post_offset == 0 or self.os2_offset == 0) return error.MissingRequiredTable;
        return .{
            .underline_position = try readI16(self.data, self.post_offset + 8),
            .underline_thickness = try readI16(self.data, self.post_offset + 10),
            .strikethrough_position = try readI16(self.data, self.os2_offset + 28),
            .strikethrough_thickness = try readI16(self.data, self.os2_offset + 26),
        };
    }

    /// Superscript size and offset from the OS/2 table.
    pub fn superscriptMetrics(self: *const Font) ParseError!ScriptMetrics {
        if (self.os2_offset == 0) return error.MissingRequiredTable;
        return .{
            .x_size = try readI16(self.data, self.os2_offset + 18),
            .y_size = try readI16(self.data, self.os2_offset + 20),
            .x_offset = try readI16(self.data, self.os2_offset + 22),
            .y_offset = try readI16(self.data, self.os2_offset + 24),
        };
    }

    /// Subscript size and offset from the OS/2 table.
    pub fn subscriptMetrics(self: *const Font) ParseError!ScriptMetrics {
        if (self.os2_offset == 0) return error.MissingRequiredTable;
        return .{
            .x_size = try readI16(self.data, self.os2_offset + 10),
            .y_size = try readI16(self.data, self.os2_offset + 12),
            .x_offset = try readI16(self.data, self.os2_offset + 14),
            .y_offset = try readI16(self.data, self.os2_offset + 16),
        };
    }

    pub fn bbox(self: *const Font, glyph_id: u16) ParseError!BBox {
        return (try self.glyphMetrics(glyph_id)).bbox;
    }

    /// Parse a glyph's outlines on `scratch`. The returned glyph (and
    /// every transitively-allocated contour/curve buffer) lives on
    /// `scratch`; the caller is expected to read it and then drop the
    /// scratch arena. Thread-safe given a per-thread scratch allocator.
    ///
    /// Compound glyphs use a `scratch`-backed component cache so
    /// repeat references inside one compound (e.g. accent + base seen
    /// multiple times) don't re-parse — but the cache is bounded to
    /// this call: no state survives `parseGlyph`.
    pub fn parseGlyph(self: *const Font, scratch: std.mem.Allocator, glyph_id: u16) ParseError!Glyph {
        var cache = std.AutoHashMap(u16, Glyph).init(scratch);
        defer cache.deinit();
        return self.parseGlyphInner(scratch, &cache, glyph_id);
    }

    fn parseGlyphInner(self: *const Font, scratch: std.mem.Allocator, cache: *std.AutoHashMap(u16, Glyph), glyph_id: u16) ParseError!Glyph {
        if (cache.get(glyph_id)) |cached| return cached;

        const metrics = try self.glyphMetrics(glyph_id);
        const glyph_len = try self.glyphLength(glyph_id);

        if (glyph_len == 0) {
            const glyph = Glyph{ .contours = &.{}, .metrics = metrics };
            try cache.put(glyph_id, glyph);
            return glyph;
        }

        const base = self.glyf_offset + try self.glyphOffset(glyph_id);
        const num_contours = try readI16(self.data, base);

        if (num_contours < 0) {
            return self.parseCompoundGlyph(scratch, cache, glyph_id, base, metrics);
        }
        return self.parseSimpleGlyph(scratch, cache, glyph_id, base, @intCast(num_contours), metrics);
    }

    fn buildSimpleGlyphContours(
        allocator: std.mem.Allocator,
        outline: *const tt_outline.SimpleGlyph,
        scale: f32,
    ) ParseError![]Contour {
        var contours: std.ArrayList(Contour) = .empty;
        errdefer {
            freeContourCurves(allocator, contours.items);
            contours.deinit(allocator);
        }

        for (outline.contours) |range| {
            const curves = try contourToCurves(
                allocator,
                outline.points[range.start..range.end],
                scale,
            );
            contours.append(allocator, .{ .curves = curves }) catch |err| {
                if (curves.len > 0) allocator.free(curves);
                return err;
            };
        }

        return contours.toOwnedSlice(allocator);
    }

    fn cacheParsedGlyph(cache: *std.AutoHashMap(u16, Glyph), glyph_id: u16, glyph: Glyph) ParseError!Glyph {
        try cache.put(glyph_id, glyph);
        return glyph;
    }

    fn parseSimpleGlyph(self: *const Font, scratch: std.mem.Allocator, cache: *std.AutoHashMap(u16, Glyph), glyph_id: u16, base: u32, num_contours: u16, metrics: GlyphMetrics) ParseError!Glyph {
        if (num_contours == 0) {
            return cacheParsedGlyph(cache, glyph_id, .{ .contours = &.{}, .metrics = metrics });
        }

        const scale = 1.0 / @as(f32, @floatFromInt(self.units_per_em));
        var outline = try tt_outline.parseSimpleGlyph(scratch, self.data, base, num_contours);
        defer outline.deinit();
        const contours = try buildSimpleGlyphContours(scratch, &outline, scale);
        return cacheParsedGlyph(cache, glyph_id, .{ .contours = contours, .metrics = metrics });
    }

    fn parseCompoundGlyph(self: *const Font, scratch: std.mem.Allocator, cache: *std.AutoHashMap(u16, Glyph), glyph_id: u16, base: u32, metrics: GlyphMetrics) ParseError!Glyph {
        var all_contours: std.ArrayList(Contour) = .empty;

        const sf = 1.0 / @as(f32, @floatFromInt(self.units_per_em));
        var compound = try tt_outline.parseCompoundGlyph(scratch, self.data, base, sf);
        defer compound.deinit();

        for (compound.components) |component_ref| {
            const component = try self.parseGlyphInner(scratch, cache, component_ref.glyph_id);
            for (component.contours) |contour| {
                var transformed = try scratch.alloc(QuadBezier, contour.curves.len);
                const d = Vec2.new(component_ref.dx, component_ref.dy);
                for (contour.curves, 0..) |curve, ci| {
                    transformed[ci] = .{
                        .p0 = transformComponentPoint(component_ref.transform, curve.p0, d),
                        .p1 = transformComponentPoint(component_ref.transform, curve.p1, d),
                        .p2 = transformComponentPoint(component_ref.transform, curve.p2, d),
                    };
                }
                try all_contours.append(scratch, .{ .curves = transformed });
            }
        }

        const contours = try all_contours.toOwnedSlice(scratch);
        const glyph = Glyph{ .contours = contours, .metrics = metrics };
        return cacheParsedGlyph(cache, glyph_id, glyph);
    }

    fn transformComponentPoint(transform: tt_outline.ComponentTransform, point: Vec2, offset: Vec2) Vec2 {
        return Vec2.add(transform.apply(point), offset);
    }

    /// A single COLRv0 layer: the outline glyph to render and its RGBA color.
    /// color = (-1,-1,-1,-1) is a sentinel meaning "use the text foreground color".
    pub const ColrLayer = struct {
        glyph_id: u16,
        color: [4]f32,
    };

    const ColrRecord = struct {
        first_layer: u16,
        num_layers: u16,
        layer_off: u32,
        color_recs_off: u32,
    };

    pub const ColrLayerIterator = struct {
        data: []const u8,
        colr_offset: u32 = 0,
        layer_off: u32 = 0,
        first_layer: u16 = 0,
        num_layers: u16 = 0,
        color_recs_off: u32 = 0,
        index: u16 = 0,

        pub fn count(self: *const ColrLayerIterator) u16 {
            return self.num_layers;
        }

        pub fn next(self: *ColrLayerIterator) ?ColrLayer {
            if (self.index >= self.num_layers) return null;

            const layer_index = self.index;
            self.index += 1;

            const layer_rec = self.colr_offset + self.layer_off + (@as(u32, self.first_layer) + @as(u32, layer_index)) * 4;
            const layer_gid = readU16(self.data, layer_rec) catch {
                self.index = self.num_layers;
                return null;
            };
            const pal_idx = readU16(self.data, layer_rec + 2) catch {
                self.index = self.num_layers;
                return null;
            };

            if (pal_idx == 0xFFFF) {
                return .{ .glyph_id = layer_gid, .color = .{ -1, -1, -1, -1 } };
            }

            const entry = self.color_recs_off + @as(u32, pal_idx) * 4;
            if (entry + 3 >= self.data.len) {
                self.index = self.num_layers;
                return null;
            }

            return .{
                .glyph_id = layer_gid,
                .color = .{
                    @as(f32, @floatFromInt(self.data[entry + 2])) / 255.0,
                    @as(f32, @floatFromInt(self.data[entry + 1])) / 255.0,
                    @as(f32, @floatFromInt(self.data[entry + 0])) / 255.0,
                    @as(f32, @floatFromInt(self.data[entry + 3])) / 255.0,
                },
            };
        }
    };

    fn findColrRecord(self: *const Font, base_glyph_id: u16) ?ColrRecord {
        if (self.colr_offset == 0 or self.cpal_offset == 0) return null;
        const colr = self.colr_offset;
        const cpal = self.cpal_offset;

        const num_base = readU16(self.data, colr + 2) catch return null;
        if (num_base == 0) return null;
        const base_off = readU32(self.data, colr + 4) catch return null;
        const layer_off = readU32(self.data, colr + 8) catch return null;

        var lo: u32 = 0;
        var hi: u32 = num_base;
        const rec = blk: {
            while (lo < hi) {
                const mid = (lo + hi) / 2;
                const off = colr + base_off + mid * 6;
                const g = readU16(self.data, off) catch return null;
                if (g == base_glyph_id) break :blk off;
                if (g < base_glyph_id) lo = mid + 1 else hi = mid;
            }
            return null;
        };

        const first_layer = readU16(self.data, rec + 2) catch return null;
        const num_layers = readU16(self.data, rec + 4) catch return null;
        if (num_layers == 0) return null;

        const color_recs_off = readU32(self.data, cpal + 8) catch return null;
        return .{
            .first_layer = first_layer,
            .num_layers = num_layers,
            .layer_off = layer_off,
            .color_recs_off = cpal + color_recs_off,
        };
    }

    pub fn colrLayers(self: *const Font, base_glyph_id: u16) ColrLayerIterator {
        const rec = self.findColrRecord(base_glyph_id) orelse return .{ .data = self.data };
        return .{
            .data = self.data,
            .colr_offset = self.colr_offset,
            .layer_off = rec.layer_off,
            .first_layer = rec.first_layer,
            .num_layers = rec.num_layers,
            .color_recs_off = rec.color_recs_off,
        };
    }

    pub fn colrLayerCount(self: *const Font, base_glyph_id: u16) u16 {
        const rec = self.findColrRecord(base_glyph_id) orelse return 0;
        return rec.num_layers;
    }

    pub fn getKerning(self: *const Font, left: u16, right: u16) !i16 {
        if (self.kern_offset == 0) return 0;
        const base = self.kern_offset;
        const n_tables = try readU16(self.data, base + 2);
        var offset: u32 = base + 4;
        for (0..n_tables) |_| {
            const coverage = try readU16(self.data, offset + 4);
            if (coverage & 1 == 1) {
                const n_pairs = try readU16(self.data, offset + 6);
                const pairs_base = offset + 14;
                var lo: u32 = 0;
                var hi: u32 = n_pairs;
                const key: u32 = (@as(u32, left) << 16) | right;
                while (lo < hi) {
                    const mid = (lo + hi) / 2;
                    const pair_off = pairs_base + mid * 6;
                    const pair_key = try readU32(self.data, pair_off);
                    if (pair_key == key) return try readI16(self.data, pair_off + 4) else if (pair_key < key) lo = mid + 1 else hi = mid;
                }
            }
            const table_len = try readU16(self.data, offset + 2);
            offset += table_len;
        }
        return 0;
    }
};

fn contourToCurves(
    allocator: std.mem.Allocator,
    points: []const tt_outline.Point,
    scale: f32,
) ![]QuadBezier {
    return tt_outline.contourToCurves(allocator, points, scale);
}

test "font basic validation" {
    const invalid_data = "not a font";
    const result = Font.init(invalid_data);
    try std.testing.expectError(error.InvalidFont, result);
}

test "parse real font" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    try std.testing.expect(font.units_per_em > 0);
    try std.testing.expect(font.num_glyphs > 0);

    const glyph_id = try font.glyphIndex('A');
    try std.testing.expect(glyph_id > 0);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const glyph = try font.parseGlyph(arena.allocator(), glyph_id);
    try std.testing.expect(glyph.contours.len > 0);
    try std.testing.expect(glyph.metrics.advance_width > 0);

    var total_curves: usize = 0;
    for (glyph.contours) |contour| total_curves += contour.curves.len;
    try std.testing.expect(total_curves > 0);
}

test "COLR iterator exposes full layer count" {
    const font_data = @import("assets").twemoji_mozilla;
    const font = try Font.init(font_data);
    const glyph_id = try font.glyphIndex(0x1F600);
    const expected = font.colrLayerCount(glyph_id);
    try std.testing.expect(expected > 0);

    var it = font.colrLayers(glyph_id);
    var actual: u16 = 0;
    while (it.next()) |_| actual += 1;

    try std.testing.expectEqual(expected, actual);
}

test "parse multiple glyphs" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const test_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    for (test_chars) |ch| {
        const glyph_id = try font.glyphIndex(ch);
        _ = try font.parseGlyph(arena.allocator(), glyph_id);
        _ = arena.reset(.retain_capacity);
    }
}

test "space glyph has no contours" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const space_id = try font.glyphIndex(' ');
    const glyph = try font.parseGlyph(arena.allocator(), space_id);
    try std.testing.expectEqual(@as(usize, 0), glyph.contours.len);
    try std.testing.expect(glyph.metrics.advance_width > 0);
}

test "direct glyph metrics match parsed glyph metrics" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const glyph_id = try font.glyphIndex('M');
    const direct = try font.glyphMetrics(glyph_id);
    const glyph = try font.parseGlyph(arena.allocator(), glyph_id);

    try std.testing.expectEqual(direct.advance_width, glyph.metrics.advance_width);
    try std.testing.expectEqual(direct.lsb, glyph.metrics.lsb);
    try std.testing.expectApproxEqAbs(direct.bbox.min.x, glyph.metrics.bbox.min.x, 1e-6);
    try std.testing.expectApproxEqAbs(direct.bbox.min.y, glyph.metrics.bbox.min.y, 1e-6);
    try std.testing.expectApproxEqAbs(direct.bbox.max.x, glyph.metrics.bbox.max.x, 1e-6);
    try std.testing.expectApproxEqAbs(direct.bbox.max.y, glyph.metrics.bbox.max.y, 1e-6);

    try std.testing.expectEqual(try font.advanceWidth(glyph_id), @as(i16, @intCast(direct.advance_width)));
    const bbox = try font.bbox(glyph_id);
    try std.testing.expectApproxEqAbs(direct.bbox.min.x, bbox.min.x, 1e-6);
    try std.testing.expectApproxEqAbs(direct.bbox.max.y, bbox.max.y, 1e-6);
}

test "line metrics expose hhea ascent descent and gap" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    const metrics = try font.lineMetrics();

    try std.testing.expect(metrics.ascent > 0);
    try std.testing.expect(metrics.descent < 0);
    try std.testing.expect(metrics.line_gap >= 0);
}

test "decoration metrics from OS/2 and post tables" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    const dm = try font.decorationMetrics();

    // Underline position should be below baseline (negative in OpenType convention)
    try std.testing.expect(dm.underline_position < 0);
    try std.testing.expect(dm.underline_thickness > 0);
    // Strikethrough position should be above baseline
    try std.testing.expect(dm.strikethrough_position > 0);
    try std.testing.expect(dm.strikethrough_thickness > 0);
}

test "superscript metrics from OS/2 table" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    const sm = try font.superscriptMetrics();

    // Superscript should have positive size and offset
    try std.testing.expect(sm.x_size > 0);
    try std.testing.expect(sm.y_size > 0);
    try std.testing.expect(sm.y_offset > 0);
}

test "subscript metrics from OS/2 table" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    const sm = try font.subscriptMetrics();

    // Subscript should have positive size and offset
    try std.testing.expect(sm.x_size > 0);
    try std.testing.expect(sm.y_size > 0);
    try std.testing.expect(sm.y_offset > 0);
}

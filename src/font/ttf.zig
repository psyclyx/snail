const std = @import("std");
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

pub const Contour = struct {
    curves: []const QuadBezier,
};

pub const Glyph = struct {
    contours: []const Contour,
    metrics: GlyphMetrics,
};

const PointInfo = struct { pos: Vec2, on_curve: bool };

/// Glyph cache for parsed glyph outlines. Caller-owned, enabling thread-safe
/// usage patterns: each thread (or Atlas) gets its own cache.
pub const GlyphCache = struct {
    map: std.AutoHashMap(u16, Glyph),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GlyphCache {
        return .{ .map = std.AutoHashMap(u16, Glyph).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *GlyphCache) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.contours) |contour| {
                self.allocator.free(contour.curves);
            }
            self.allocator.free(entry.value_ptr.contours);
        }
        self.map.deinit();
    }
};

/// Parsed TrueType font. Immutable after init — all methods are const.
/// Thread-safe for concurrent reads (glyphIndex, getKerning, parseGlyph
/// with separate GlyphCache instances).
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

    fn parseTableDirectory(self: *Font) !void {
        if (self.data.len < 12) return error.InvalidFont;
        const num_tables = try readU16(self.data, 4);
        var offset: usize = 12;
        for (0..num_tables) |_| {
            if (offset + 16 > self.data.len) return error.UnexpectedEof;
            const tag = self.data[offset .. offset + 4];
            const table_offset = try readU32(self.data, offset + 8);
            if (std.mem.eql(u8, tag, "head")) self.head_offset = table_offset else if (std.mem.eql(u8, tag, "maxp")) self.maxp_offset = table_offset else if (std.mem.eql(u8, tag, "cmap")) self.cmap_offset = table_offset else if (std.mem.eql(u8, tag, "glyf")) self.glyf_offset = table_offset else if (std.mem.eql(u8, tag, "loca")) self.loca_offset = table_offset else if (std.mem.eql(u8, tag, "hhea")) self.hhea_offset = table_offset else if (std.mem.eql(u8, tag, "hmtx")) self.hmtx_offset = table_offset else if (std.mem.eql(u8, tag, "kern")) self.kern_offset = table_offset else if (std.mem.eql(u8, tag, "GSUB")) self.gsub_offset = table_offset else if (std.mem.eql(u8, tag, "GPOS")) self.gpos_offset = table_offset else if (std.mem.eql(u8, tag, "COLR")) self.colr_offset = table_offset else if (std.mem.eql(u8, tag, "CPAL")) self.cpal_offset = table_offset;
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

    pub fn bbox(self: *const Font, glyph_id: u16) ParseError!BBox {
        return (try self.glyphMetrics(glyph_id)).bbox;
    }

    /// Parse a glyph's outlines. Uses cache for compound glyph component lookups.
    /// Thread-safe when each caller uses a separate cache and allocator.
    pub fn parseGlyph(self: *const Font, allocator: std.mem.Allocator, cache: *GlyphCache, glyph_id: u16) ParseError!Glyph {
        if (cache.map.get(glyph_id)) |cached| return cached;

        const metrics = try self.glyphMetrics(glyph_id);
        const glyph_len = try self.glyphLength(glyph_id);

        if (glyph_len == 0) {
            const glyph = Glyph{ .contours = &.{}, .metrics = metrics };
            try cache.map.put(glyph_id, glyph);
            return glyph;
        }

        const base = self.glyf_offset + try self.glyphOffset(glyph_id);
        const num_contours = try readI16(self.data, base);

        if (num_contours < 0) {
            return self.parseCompoundGlyph(allocator, cache, glyph_id, base, metrics);
        }
        return self.parseSimpleGlyph(allocator, cache, glyph_id, base, @intCast(num_contours), metrics);
    }

    fn parseSimpleGlyph(self: *const Font, allocator: std.mem.Allocator, cache: *GlyphCache, glyph_id: u16, base: u32, num_contours: u16, metrics: GlyphMetrics) ParseError!Glyph {
        if (num_contours == 0) {
            const glyph = Glyph{ .contours = &.{}, .metrics = metrics };
            try cache.map.put(glyph_id, glyph);
            return glyph;
        }

        const scale = 1.0 / @as(f32, @floatFromInt(self.units_per_em));

        var end_pts = try allocator.alloc(u16, num_contours);
        defer allocator.free(end_pts);
        for (0..num_contours) |i| {
            end_pts[i] = try readU16(self.data, base + 10 + @as(u32, @intCast(i)) * 2);
        }

        const num_points = @as(u32, end_pts[num_contours - 1]) + 1;
        const instr_len_off = base + 10 + @as(u32, num_contours) * 2;
        const instr_len = try readU16(self.data, instr_len_off);
        var offset = instr_len_off + 2 + instr_len;

        var flags = try allocator.alloc(u8, num_points);
        defer allocator.free(flags);
        {
            var i: u32 = 0;
            while (i < num_points) {
                if (offset >= self.data.len) return error.UnexpectedEof;
                const flag = self.data[offset];
                offset += 1;
                flags[i] = flag;
                i += 1;
                if (flag & 8 != 0) {
                    if (offset >= self.data.len) return error.UnexpectedEof;
                    const repeat = self.data[offset];
                    offset += 1;
                    for (0..repeat) |_| {
                        if (i >= num_points) break;
                        flags[i] = flag;
                        i += 1;
                    }
                }
            }
        }

        var x_coords = try allocator.alloc(i16, num_points);
        defer allocator.free(x_coords);
        {
            var x: i16 = 0;
            for (0..num_points) |i| {
                const flag = flags[i];
                if (flag & 2 != 0) {
                    if (offset >= self.data.len) return error.UnexpectedEof;
                    const dx: i16 = @intCast(self.data[offset]);
                    offset += 1;
                    if (flag & 16 != 0) x += dx else x -= dx;
                } else if (flag & 16 == 0) {
                    x += try readI16(self.data, offset);
                    offset += 2;
                }
                x_coords[i] = x;
            }
        }

        var y_coords = try allocator.alloc(i16, num_points);
        defer allocator.free(y_coords);
        {
            var y: i16 = 0;
            for (0..num_points) |i| {
                const flag = flags[i];
                if (flag & 4 != 0) {
                    if (offset >= self.data.len) return error.UnexpectedEof;
                    const dy: i16 = @intCast(self.data[offset]);
                    offset += 1;
                    if (flag & 32 != 0) y += dy else y -= dy;
                } else if (flag & 32 == 0) {
                    y += try readI16(self.data, offset);
                    offset += 2;
                }
                y_coords[i] = y;
            }
        }

        var contours: std.ArrayList(Contour) = .empty;
        errdefer {
            for (contours.items) |cont| allocator.free(cont.curves);
            contours.deinit(allocator);
        }

        var contour_start: u32 = 0;
        for (end_pts) |end_pt| {
            const contour_end: u32 = @as(u32, end_pt) + 1;
            const curves = try contourToCurves(
                allocator,
                flags[contour_start..contour_end],
                x_coords[contour_start..contour_end],
                y_coords[contour_start..contour_end],
                scale,
            );
            try contours.append(allocator, .{ .curves = curves });
            contour_start = contour_end;
        }

        const glyph = Glyph{
            .contours = try contours.toOwnedSlice(allocator),
            .metrics = metrics,
        };
        try cache.map.put(glyph_id, glyph);
        return glyph;
    }

    fn parseCompoundGlyph(self: *const Font, allocator: std.mem.Allocator, cache: *GlyphCache, glyph_id: u16, base: u32, metrics: GlyphMetrics) ParseError!Glyph {
        var all_contours: std.ArrayList(Contour) = .empty;
        errdefer {
            for (all_contours.items) |cont| allocator.free(cont.curves);
            all_contours.deinit(allocator);
        }

        var offset: u32 = base + 10;
        var more = true;
        while (more) {
            const comp_flags = try readU16(self.data, offset);
            const component_glyph_id = try readU16(self.data, offset + 2);
            offset += 4;
            var dx: f32 = 0;
            var dy: f32 = 0;
            const sf = 1.0 / @as(f32, @floatFromInt(self.units_per_em));
            if (comp_flags & 1 != 0) {
                dx = @as(f32, @floatFromInt(try readI16(self.data, offset))) * sf;
                dy = @as(f32, @floatFromInt(try readI16(self.data, offset + 2))) * sf;
                offset += 4;
            } else {
                const b1: i8 = @bitCast(self.data[offset]);
                const b2: i8 = @bitCast(self.data[offset + 1]);
                dx = @as(f32, @floatFromInt(b1)) * sf;
                dy = @as(f32, @floatFromInt(b2)) * sf;
                offset += 2;
            }
            if (comp_flags & 8 != 0) offset += 2 else if (comp_flags & 64 != 0) offset += 4 else if (comp_flags & 128 != 0) offset += 8;

            const component = try self.parseGlyph(allocator, cache, component_glyph_id);
            for (component.contours) |contour| {
                var transformed = try allocator.alloc(QuadBezier, contour.curves.len);
                const d = Vec2.new(dx, dy);
                for (contour.curves, 0..) |curve, ci| {
                    transformed[ci] = .{
                        .p0 = Vec2.add(curve.p0, d),
                        .p1 = Vec2.add(curve.p1, d),
                        .p2 = Vec2.add(curve.p2, d),
                    };
                }
                try all_contours.append(allocator, .{ .curves = transformed });
            }
            more = (comp_flags & 32 != 0);
        }

        const glyph = Glyph{
            .contours = try all_contours.toOwnedSlice(allocator),
            .metrics = metrics,
        };
        try cache.map.put(glyph_id, glyph);
        return glyph;
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

    /// Fill buf with the COLRv0 layers for base_glyph_id.
    /// Returns the populated prefix of buf; empty if the glyph has no COLR data.
    /// Binary-searches the (sorted) base glyph record table, then resolves colors
    /// from CPAL palette 0.  All offsets in the COLR/CPAL tables are relative to
    /// their respective table starts, as the spec requires.
    pub fn getColrLayers(self: *const Font, base_glyph_id: u16, buf: []ColrLayer) []ColrLayer {
        if (buf.len == 0) return buf[0..0];
        var it = self.colrLayers(base_glyph_id);
        var count: usize = 0;
        while (count < buf.len) : (count += 1) {
            buf[count] = it.next() orelse break;
        }
        return buf[0..count];
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

fn contourToCurves(allocator: std.mem.Allocator, point_flags: []const u8, x_coords: []const i16, y_coords: []const i16, scale: f32) ![]QuadBezier {
    const n = point_flags.len;
    if (n < 2) return &.{};

    var points: std.ArrayList(PointInfo) = .empty;
    defer points.deinit(allocator);
    for (0..n) |i| {
        const px = @as(f32, @floatFromInt(x_coords[i])) * scale;
        const py = @as(f32, @floatFromInt(y_coords[i])) * scale;
        try points.append(allocator, .{ .pos = Vec2.new(px, py), .on_curve = (point_flags[i] & 1) != 0 });
    }

    var expanded: std.ArrayList(PointInfo) = .empty;
    defer expanded.deinit(allocator);
    for (0..points.items.len) |i| {
        const curr = points.items[i];
        try expanded.append(allocator, curr);
        if (!curr.on_curve) {
            const next = points.items[(i + 1) % points.items.len];
            if (!next.on_curve) {
                try expanded.append(allocator, .{
                    .pos = Vec2.lerp(curr.pos, next.pos, 0.5),
                    .on_curve = true,
                });
            }
        }
    }

    var curves: std.ArrayList(QuadBezier) = .empty;
    errdefer curves.deinit(allocator);
    const pts = expanded.items;
    if (pts.len < 2) return &.{};

    var start_idx: usize = 0;
    for (0..pts.len) |i| {
        if (pts[i].on_curve) {
            start_idx = i;
            break;
        }
    }

    var idx = start_idx;
    var iterations: usize = 0;
    while (iterations < pts.len + 1) {
        const p0 = pts[idx % pts.len];
        if (!p0.on_curve) {
            idx += 1;
            iterations += 1;
            continue;
        }
        const next1 = pts[(idx + 1) % pts.len];
        if (next1.on_curve) {
            try curves.append(allocator, .{ .p0 = p0.pos, .p1 = Vec2.lerp(p0.pos, next1.pos, 0.5), .p2 = next1.pos });
            idx += 1;
        } else {
            const next2 = pts[(idx + 2) % pts.len];
            try curves.append(allocator, .{ .p0 = p0.pos, .p1 = next1.pos, .p2 = next2.pos });
            idx += 2;
        }
        iterations += 1;
        if (idx % pts.len == start_idx) break;
    }

    return curves.toOwnedSlice(allocator);
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

    var cache = GlyphCache.init(std.testing.allocator);
    defer cache.deinit();
    const glyph = try font.parseGlyph(std.testing.allocator, &cache, glyph_id);
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
    var cache = GlyphCache.init(std.testing.allocator);
    defer cache.deinit();

    const test_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    for (test_chars) |ch| {
        const glyph_id = try font.glyphIndex(ch);
        _ = try font.parseGlyph(std.testing.allocator, &cache, glyph_id);
    }
}

test "space glyph has no contours" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    var cache = GlyphCache.init(std.testing.allocator);
    defer cache.deinit();

    const space_id = try font.glyphIndex(' ');
    const glyph = try font.parseGlyph(std.testing.allocator, &cache, space_id);
    try std.testing.expectEqual(@as(usize, 0), glyph.contours.len);
    try std.testing.expect(glyph.metrics.advance_width > 0);
}

test "direct glyph metrics match parsed glyph metrics" {
    const font_data = @import("assets").noto_sans_regular;
    const font = try Font.init(font_data);
    var cache = GlyphCache.init(std.testing.allocator);
    defer cache.deinit();

    const glyph_id = try font.glyphIndex('M');
    const direct = try font.glyphMetrics(glyph_id);
    const glyph = try font.parseGlyph(std.testing.allocator, &cache, glyph_id);

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

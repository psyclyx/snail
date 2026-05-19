const std = @import("std");

pub const ParseError = error{
    UnexpectedEof,
    InvalidFont,
    MissingRequiredTable,
};

pub const TableRecord = struct {
    offset: u32,
    length: u32,

    pub fn validate(self: TableRecord, data: []const u8) ParseError!void {
        _ = try self.bytes(data);
    }

    pub fn bytes(self: TableRecord, data: []const u8) ParseError![]const u8 {
        const start: usize = self.offset;
        const len: usize = self.length;
        if (start > data.len or len > data.len - start) return error.UnexpectedEof;
        return data[start..][0..len];
    }
};

pub const Head = struct {
    units_per_em: u16,
    index_to_loc_format: i16,
};

pub const MaxProfile = struct {
    num_glyphs: u16,
    max_points: u16 = 0,
    max_contours: u16 = 0,
    max_composite_points: u16 = 0,
    max_composite_contours: u16 = 0,
    max_zones: u16 = 0,
    max_twilight_points: u16 = 0,
    max_storage: u16 = 0,
    max_function_defs: u16 = 0,
    max_instruction_defs: u16 = 0,
    max_stack_elements: u16 = 0,
    max_size_of_instructions: u16 = 0,
    max_component_elements: u16 = 0,
    max_component_depth: u16 = 0,
};

pub const HorizontalHeader = struct {
    ascent: i16,
    descent: i16,
    line_gap: i16,
    number_of_h_metrics: u16,
};

pub const HorizontalMetrics = struct {
    advance_width: u16,
    left_side_bearing: i16,
};

pub const ProgramTables = struct {
    data: []const u8,
    head: TableRecord,
    maxp: TableRecord,
    hhea: ?TableRecord = null,
    hmtx: ?TableRecord = null,
    glyf: ?TableRecord = null,
    loca: ?TableRecord = null,
    cvt: ?TableRecord = null,
    fpgm: ?TableRecord = null,
    prep: ?TableRecord = null,
    gasp: ?TableRecord = null,

    pub fn init(data: []const u8) ParseError!ProgramTables {
        if (data.len < 12) return error.InvalidFont;

        var out = ProgramTables{
            .data = data,
            .head = undefined,
            .maxp = undefined,
        };
        var have_head = false;
        var have_maxp = false;

        const num_tables = try readU16(data, 4);
        var offset: usize = 12;
        for (0..num_tables) |_| {
            if (offset + 16 > data.len) return error.UnexpectedEof;
            const tag = data[offset..][0..4];
            const record = TableRecord{
                .offset = try readU32(data, offset + 8),
                .length = try readU32(data, offset + 12),
            };
            try record.validate(data);

            if (tagEql(tag, "head")) {
                out.head = record;
                have_head = true;
            } else if (tagEql(tag, "maxp")) {
                out.maxp = record;
                have_maxp = true;
            } else if (tagEql(tag, "hhea")) {
                out.hhea = record;
            } else if (tagEql(tag, "hmtx")) {
                out.hmtx = record;
            } else if (tagEql(tag, "glyf")) {
                out.glyf = record;
            } else if (tagEql(tag, "loca")) {
                out.loca = record;
            } else if (tagEql(tag, "cvt ")) {
                out.cvt = record;
            } else if (tagEql(tag, "fpgm")) {
                out.fpgm = record;
            } else if (tagEql(tag, "prep")) {
                out.prep = record;
            } else if (tagEql(tag, "gasp")) {
                out.gasp = record;
            }

            offset += 16;
        }

        if (!have_head or !have_maxp) return error.MissingRequiredTable;
        return out;
    }

    pub fn horizontalHeader(self: ProgramTables) ParseError!HorizontalHeader {
        const record = self.hhea orelse return error.MissingRequiredTable;
        const bytes = try record.bytes(self.data);
        if (bytes.len < 36) return error.UnexpectedEof;
        return .{
            .ascent = try readI16(bytes, 4),
            .descent = try readI16(bytes, 6),
            .line_gap = try readI16(bytes, 8),
            .number_of_h_metrics = try readU16(bytes, 34),
        };
    }

    pub fn horizontalMetrics(
        self: ProgramTables,
        glyph_id: u16,
        num_glyphs: u16,
        number_of_h_metrics: u16,
    ) ParseError!HorizontalMetrics {
        if (glyph_id >= num_glyphs or number_of_h_metrics == 0) return error.InvalidFont;
        const bytes = try self.tableBytes(self.hmtx);
        if (glyph_id < number_of_h_metrics) return readLongHorizontalMetric(bytes, glyph_id);
        return .{
            .advance_width = (try readLongHorizontalMetric(bytes, number_of_h_metrics - 1)).advance_width,
            .left_side_bearing = try readLeftSideBearing(bytes, glyph_id, number_of_h_metrics),
        };
    }

    pub fn headInfo(self: ProgramTables) ParseError!Head {
        const bytes = try self.head.bytes(self.data);
        if (bytes.len < 54) return error.UnexpectedEof;
        return .{
            .units_per_em = try readU16(bytes, 18),
            .index_to_loc_format = try readI16(bytes, 50),
        };
    }

    pub fn maxProfile(self: ProgramTables) ParseError!MaxProfile {
        const bytes = try self.maxp.bytes(self.data);
        if (bytes.len < 6) return error.UnexpectedEof;

        var out = MaxProfile{ .num_glyphs = try readU16(bytes, 4) };
        if (bytes.len < 32) return out;

        out.max_points = try readU16(bytes, 6);
        out.max_contours = try readU16(bytes, 8);
        out.max_composite_points = try readU16(bytes, 10);
        out.max_composite_contours = try readU16(bytes, 12);
        out.max_zones = try readU16(bytes, 14);
        out.max_twilight_points = try readU16(bytes, 16);
        out.max_storage = try readU16(bytes, 18);
        out.max_function_defs = try readU16(bytes, 20);
        out.max_instruction_defs = try readU16(bytes, 22);
        out.max_stack_elements = try readU16(bytes, 24);
        out.max_size_of_instructions = try readU16(bytes, 26);
        out.max_component_elements = try readU16(bytes, 28);
        out.max_component_depth = try readU16(bytes, 30);
        return out;
    }

    pub fn tableBytes(self: ProgramTables, record: ?TableRecord) ParseError![]const u8 {
        return if (record) |r| try r.bytes(self.data) else &.{};
    }
};

fn tagEql(actual: []const u8, comptime expected: *const [4]u8) bool {
    return std.mem.eql(u8, actual, expected);
}

fn readU16(data: []const u8, offset: usize) ParseError!u16 {
    if (offset + 2 > data.len) return error.UnexpectedEof;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readI16(data: []const u8, offset: usize) ParseError!i16 {
    if (offset + 2 > data.len) return error.UnexpectedEof;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) ParseError!u32 {
    if (offset + 4 > data.len) return error.UnexpectedEof;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

fn readLongHorizontalMetric(bytes: []const u8, glyph_id: u16) ParseError!HorizontalMetrics {
    const offset = @as(usize, glyph_id) * 4;
    if (offset + 4 > bytes.len) return error.UnexpectedEof;
    return .{
        .advance_width = try readU16(bytes, offset),
        .left_side_bearing = try readI16(bytes, offset + 2),
    };
}

fn readLeftSideBearing(bytes: []const u8, glyph_id: u16, number_of_h_metrics: u16) ParseError!i16 {
    const offset = @as(usize, number_of_h_metrics) * 4 +
        (@as(usize, glyph_id) - @as(usize, number_of_h_metrics)) * 2;
    return readI16(bytes, offset);
}

test "read TT program tables from bundled font" {
    const tables = try ProgramTables.init(@import("assets").noto_sans_regular);
    const head = try tables.headInfo();
    const maxp = try tables.maxProfile();
    const hhea = try tables.horizontalHeader();
    const hmtx = try tables.horizontalMetrics(36, maxp.num_glyphs, hhea.number_of_h_metrics);

    try std.testing.expect(head.units_per_em > 0);
    try std.testing.expect(maxp.num_glyphs > 0);
    try std.testing.expect(hhea.number_of_h_metrics > 0);
    try std.testing.expect(hmtx.advance_width > 0);
    try std.testing.expect(tables.glyf != null);
    try std.testing.expect(tables.loca != null);
    try std.testing.expect((try tables.tableBytes(tables.fpgm)).len > 0);
    try std.testing.expect((try tables.tableBytes(tables.prep)).len > 0);
}

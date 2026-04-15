//! OpenType GSUB/GPOS table parser.
//! Supports: ligature substitution (GSUB type 4), pair adjustment (GPOS type 2).
//! Sufficient for Latin/Cyrillic/Greek text shaping.

const std = @import("std");

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

// ── Coverage ──

/// Returns the coverage index for a glyph, or null if not covered.
pub fn coverageIndex(data: []const u8, coverage_offset: usize, glyph_id: u16) !?u16 {
    const format = try readU16(data, coverage_offset);
    switch (format) {
        1 => {
            // Format 1: glyph array (binary search)
            const count = try readU16(data, coverage_offset + 2);
            var lo: u16 = 0;
            var hi = count;
            while (lo < hi) {
                const mid = (lo + hi) / 2;
                const g = try readU16(data, coverage_offset + 4 + @as(usize, mid) * 2);
                if (g == glyph_id) return mid;
                if (g < glyph_id) lo = mid + 1 else hi = mid;
            }
            return null;
        },
        2 => {
            // Format 2: range array (binary search)
            const count = try readU16(data, coverage_offset + 2);
            var lo: u16 = 0;
            var hi = count;
            while (lo < hi) {
                const mid = (lo + hi) / 2;
                const rec = coverage_offset + 4 + @as(usize, mid) * 6;
                const start = try readU16(data, rec);
                const end = try readU16(data, rec + 2);
                if (glyph_id < start) {
                    hi = mid;
                } else if (glyph_id > end) {
                    lo = mid + 1;
                } else {
                    const start_idx = try readU16(data, rec + 4);
                    return start_idx + (glyph_id - start);
                }
            }
            return null;
        },
        else => return null,
    }
}

// ── Class Definition ──

pub fn classValue(data: []const u8, classdef_offset: usize, glyph_id: u16) !u16 {
    const format = try readU16(data, classdef_offset);
    switch (format) {
        1 => {
            const start = try readU16(data, classdef_offset + 2);
            const count = try readU16(data, classdef_offset + 4);
            if (glyph_id >= start and glyph_id < start + count) {
                return try readU16(data, classdef_offset + 6 + @as(usize, glyph_id - start) * 2);
            }
            return 0;
        },
        2 => {
            const count = try readU16(data, classdef_offset + 2);
            var lo: u16 = 0;
            var hi = count;
            while (lo < hi) {
                const mid = (lo + hi) / 2;
                const rec = classdef_offset + 4 + @as(usize, mid) * 6;
                const start = try readU16(data, rec);
                const end = try readU16(data, rec + 2);
                if (glyph_id < start) hi = mid
                else if (glyph_id > end) lo = mid + 1
                else return try readU16(data, rec + 4);
            }
            return 0;
        },
        else => return 0,
    }
}

// ── ValueRecord ──

fn valueRecordSize(format: u16) usize {
    var size: usize = 0;
    var f = format;
    while (f != 0) : (f &= f - 1) size += 2;
    return size;
}

pub const ValueRecord = struct {
    x_placement: i16 = 0,
    y_placement: i16 = 0,
    x_advance: i16 = 0,
    y_advance: i16 = 0,
};

fn readValueRecord(data: []const u8, offset: usize, format: u16) !ValueRecord {
    var rec = ValueRecord{};
    var off = offset;
    if (format & 0x0001 != 0) { rec.x_placement = try readI16(data, off); off += 2; }
    if (format & 0x0002 != 0) { rec.y_placement = try readI16(data, off); off += 2; }
    if (format & 0x0004 != 0) { rec.x_advance = try readI16(data, off); off += 2; }
    if (format & 0x0008 != 0) { rec.y_advance = try readI16(data, off); off += 2; }
    // Skip device table offsets (0x0010-0x0080)
    return rec;
}

// ── Feature/Lookup navigation ──

/// Find a feature tag in the feature list. Returns the lookup indices.
pub fn findFeatureLookups(
    allocator: std.mem.Allocator,
    data: []const u8,
    table_offset: usize,
    tag: *const [4]u8,
) ![]u16 {
    const feature_list_off = table_offset + try readU16(data, table_offset + 6);
    const feature_count = try readU16(data, feature_list_off);

    for (0..feature_count) |i| {
        const rec = feature_list_off + 2 + @as(usize, @intCast(i)) * 6;
        if (std.mem.eql(u8, data[rec .. rec + 4], tag)) {
            const feat_off = feature_list_off + try readU16(data, rec + 4);
            // FeatureParams offset at feat_off, then lookup count
            const lookup_count = try readU16(data, feat_off + 2);
            var lookups = try allocator.alloc(u16, lookup_count);
            for (0..lookup_count) |li| {
                lookups[li] = try readU16(data, feat_off + 4 + @as(usize, @intCast(li)) * 2);
            }
            return lookups;
        }
    }
    return &.{};
}

/// Get lookup table offset and type
fn getLookup(data: []const u8, table_offset: usize, lookup_index: u16) !struct { offset: usize, lookup_type: u16, flag: u16, subtable_count: u16 } {
    const lookup_list_off = table_offset + try readU16(data, table_offset + 8);
    const lookup_off = lookup_list_off + try readU16(data, lookup_list_off + 2 + @as(usize, lookup_index) * 2);
    return .{
        .offset = lookup_off,
        .lookup_type = try readU16(data, lookup_off),
        .flag = try readU16(data, lookup_off + 2),
        .subtable_count = try readU16(data, lookup_off + 4),
    };
}

fn getSubtableOffset(data: []const u8, lookup_offset: usize, subtable_index: u16) !usize {
    return lookup_offset + try readU16(data, lookup_offset + 6 + @as(usize, subtable_index) * 2);
}

// ── GSUB: Ligature Substitution ──

pub const LigatureResult = struct {
    output_glyph: u16,
    consumed: u16, // number of input glyphs consumed (including first)
};

/// Try to apply ligature substitution at position in glyph sequence.
pub fn tryLigature(
    data: []const u8,
    gsub_offset: usize,
    lookup_indices: []const u16,
    glyphs: []const u16,
    pos: usize,
) !?LigatureResult {
    if (pos >= glyphs.len) return null;
    const first = glyphs[pos];

    for (lookup_indices) |li| {
        const lookup = try getLookup(data, gsub_offset, li);
        if (lookup.lookup_type != 4) continue; // Only ligature substitution

        for (0..lookup.subtable_count) |si| {
            const st = try getSubtableOffset(data, lookup.offset, @intCast(si));
            const format = try readU16(data, st);
            if (format != 1) continue;

            const cov_off = st + try readU16(data, st + 2);
            const cov_idx = try coverageIndex(data, cov_off, first) orelse continue;

            const lig_set_count = try readU16(data, st + 4);
            if (cov_idx >= lig_set_count) continue;

            const lig_set_off = st + try readU16(data, st + 6 + @as(usize, cov_idx) * 2);
            const lig_count = try readU16(data, lig_set_off);

            for (0..lig_count) |lj| {
                const lig_off = lig_set_off + try readU16(data, lig_set_off + 2 + @as(usize, @intCast(lj)) * 2);
                const output = try readU16(data, lig_off);
                const comp_count = try readU16(data, lig_off + 2);

                if (pos + comp_count > glyphs.len) continue;

                // Check if remaining components match
                var match = true;
                for (1..comp_count) |ci| {
                    const expected = try readU16(data, lig_off + 4 + (@as(usize, @intCast(ci)) - 1) * 2);
                    if (glyphs[pos + ci] != expected) {
                        match = false;
                        break;
                    }
                }
                if (match) return .{ .output_glyph = output, .consumed = comp_count };
            }
        }
    }
    return null;
}

// ── GPOS: Pair Adjustment ──

/// Get pair adjustment for two adjacent glyphs via GPOS.
pub fn pairAdjustment(
    data: []const u8,
    gpos_offset: usize,
    lookup_indices: []const u16,
    first: u16,
    second: u16,
) !ValueRecord {
    for (lookup_indices) |li| {
        const lookup = try getLookup(data, gpos_offset, li);
        if (lookup.lookup_type != 2) continue;

        for (0..lookup.subtable_count) |si| {
            const st = try getSubtableOffset(data, lookup.offset, @intCast(si));
            const format = try readU16(data, st);

            const cov_off = st + try readU16(data, st + 2);
            const cov_idx = try coverageIndex(data, cov_off, first) orelse continue;

            const vf1 = try readU16(data, st + 4);
            const vf2 = try readU16(data, st + 6);

            if (format == 1) {
                // Format 1: individual pairs
                const pair_set_count = try readU16(data, st + 8);
                if (cov_idx >= pair_set_count) continue;
                const pair_set_off = st + try readU16(data, st + 10 + @as(usize, cov_idx) * 2);
                const pair_count = try readU16(data, pair_set_off);
                const rec_size = 2 + valueRecordSize(vf1) + valueRecordSize(vf2);

                // Binary search on secondGlyph
                var lo: u16 = 0;
                var hi = pair_count;
                while (lo < hi) {
                    const mid = (lo + hi) / 2;
                    const rec_off = pair_set_off + 2 + @as(usize, mid) * rec_size;
                    const sg = try readU16(data, rec_off);
                    if (sg == second) return try readValueRecord(data, rec_off + 2, vf1);
                    if (sg < second) lo = mid + 1 else hi = mid;
                }
            } else if (format == 2) {
                // Format 2: class-based
                const cd1_off = st + try readU16(data, st + 8);
                const cd2_off = st + try readU16(data, st + 10);
                const c1_count = try readU16(data, st + 12);
                const c2_count = try readU16(data, st + 14);

                const class1 = try classValue(data, cd1_off, first);
                const class2 = try classValue(data, cd2_off, second);

                if (class1 < c1_count and class2 < c2_count) {
                    const vr_size = valueRecordSize(vf1) + valueRecordSize(vf2);
                    const rec_off = st + 16 + (@as(usize, class1) * @as(usize, c2_count) + @as(usize, class2)) * vr_size;
                    return try readValueRecord(data, rec_off, vf1);
                }
            }
        }
    }
    return ValueRecord{};
}

// ── Ligature glyph discovery ──

/// Scan GSUB ligature tables and return all output glyph IDs whose
/// input components are all in the provided glyph set.
pub fn discoverLigatureGlyphs(
    allocator: std.mem.Allocator,
    data: []const u8,
    gsub_offset: u32,
    input_glyphs: *const std.AutoHashMap(u16, void),
) ![]u16 {
    if (gsub_offset == 0) return &.{};

    const liga_lookups = findFeatureLookups(allocator, data, gsub_offset, "liga") catch return &.{};
    defer if (liga_lookups.len > 0) allocator.free(liga_lookups);

    var output: std.ArrayList(u16) = .empty;
    errdefer output.deinit(allocator);

    for (liga_lookups) |li| {
        const lookup = getLookup(data, gsub_offset, li) catch continue;
        if (lookup.lookup_type != 4) continue;

        for (0..lookup.subtable_count) |si| {
            const st = getSubtableOffset(data, lookup.offset, @intCast(si)) catch continue;
            const format = readU16(data, st) catch continue;
            if (format != 1) continue;

            const cov_off = st + (readU16(data, st + 2) catch continue);
            const lig_set_count = readU16(data, st + 4) catch continue;

            for (0..lig_set_count) |lsi| {
                // Check if the first glyph (covered glyph) is in our set
                const first_glyph = coveredGlyphAt(data, cov_off, @intCast(lsi)) catch continue;
                if (!input_glyphs.contains(first_glyph)) continue;

                const lig_set_off = st + (readU16(data, st + 6 + @as(usize, @intCast(lsi)) * 2) catch continue);
                const lig_count = readU16(data, lig_set_off) catch continue;

                for (0..lig_count) |lj| {
                    const lig_off = lig_set_off + (readU16(data, lig_set_off + 2 + @as(usize, @intCast(lj)) * 2) catch continue);
                    const out_glyph = readU16(data, lig_off) catch continue;
                    const comp_count = readU16(data, lig_off + 2) catch continue;

                    // Check all components are in our set
                    var all_present = true;
                    for (1..comp_count) |ci| {
                        const comp = readU16(data, lig_off + 4 + (@as(usize, @intCast(ci)) - 1) * 2) catch {
                            all_present = false;
                            break;
                        };
                        if (!input_glyphs.contains(comp)) {
                            all_present = false;
                            break;
                        }
                    }
                    if (all_present and !input_glyphs.contains(out_glyph)) {
                        try output.append(allocator, out_glyph);
                    }
                }
            }
        }
    }

    return output.toOwnedSlice(allocator);
}

/// Get the glyph ID at a specific coverage index.
fn coveredGlyphAt(data: []const u8, coverage_offset: usize, index: u16) !u16 {
    const format = try readU16(data, coverage_offset);
    switch (format) {
        1 => return try readU16(data, coverage_offset + 4 + @as(usize, index) * 2),
        2 => {
            const count = try readU16(data, coverage_offset + 2);
            var accumulated: u16 = 0;
            for (0..count) |i| {
                const rec = coverage_offset + 4 + @as(usize, @intCast(i)) * 6;
                const start = try readU16(data, rec);
                const end = try readU16(data, rec + 2);
                const range_len = end - start + 1;
                if (index < accumulated + range_len) {
                    return start + (index - accumulated);
                }
                accumulated += range_len;
            }
            return error.UnexpectedEof;
        },
        else => return error.UnexpectedEof,
    }
}

// ── High-level shaper ──

pub const Shaper = struct {
    data: []const u8,
    gsub_offset: u32,
    gpos_offset: u32,
    liga_lookups: []const u16,
    kern_lookups: []const u16,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, font_data: []const u8, gsub_offset: u32, gpos_offset: u32) !Shaper {
        var liga_lookups: []u16 = &.{};
        var kern_lookups: []u16 = &.{};

        if (gsub_offset != 0) {
            liga_lookups = findFeatureLookups(allocator, font_data, gsub_offset, "liga") catch &.{};
        }
        if (gpos_offset != 0) {
            kern_lookups = findFeatureLookups(allocator, font_data, gpos_offset, "kern") catch &.{};
        }

        return .{
            .data = font_data,
            .gsub_offset = gsub_offset,
            .gpos_offset = gpos_offset,
            .liga_lookups = liga_lookups,
            .kern_lookups = kern_lookups,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Shaper) void {
        if (self.liga_lookups.len > 0) self.allocator.free(@constCast(self.liga_lookups));
        if (self.kern_lookups.len > 0) self.allocator.free(@constCast(self.kern_lookups));
    }

    /// Apply ligature substitution to a glyph array in-place.
    /// Returns the new length.
    pub fn applyLigatures(self: *const Shaper, glyphs: []u16) !usize {
        if (self.gsub_offset == 0 or self.liga_lookups.len == 0) return glyphs.len;

        var read: usize = 0;
        var write: usize = 0;
        while (read < glyphs.len) {
            const result = try tryLigature(self.data, self.gsub_offset, self.liga_lookups, glyphs[0..glyphs.len], read);
            if (result) |lig| {
                glyphs[write] = lig.output_glyph;
                write += 1;
                read += lig.consumed;
            } else {
                glyphs[write] = glyphs[read];
                write += 1;
                read += 1;
            }
        }
        return write;
    }

    /// Get GPOS kern adjustment between two glyphs.
    pub fn getKernAdjustment(self: *const Shaper, first: u16, second: u16) !i16 {
        if (self.gpos_offset == 0 or self.kern_lookups.len == 0) return 0;
        const vr = try pairAdjustment(self.data, self.gpos_offset, self.kern_lookups, first, second);
        return vr.x_advance;
    }
};

const std = @import("std");

const atlas_curve_mod = @import("../render/format/atlas/curve.zig");
const ttf = @import("../font/ttf.zig");
const opentype = @import("../font/opentype.zig");
const build_options = @import("build_options");
const harfbuzz = if (build_options.enable_harfbuzz) @import("../font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};

const Allocator = std.mem.Allocator;
const GlyphInfo = atlas_curve_mod.CurveAtlas.GlyphInfo;
const ColrBaseInfo = atlas_curve_mod.CurveAtlas.ColrBaseInfo;

pub const FaceIndex = u16;

pub const FontWeight = enum(u4) {
    thin = 1,
    extra_light = 2,
    light = 3,
    regular = 4,
    medium = 5,
    semi_bold = 6,
    bold = 7,
    extra_bold = 8,
    black = 9,
};

pub const FontStyle = struct {
    weight: FontWeight = .regular,
    italic: bool = false,
};

/// Synthetic style transforms applied at the vertex level during glyph emission.
pub const SyntheticStyle = struct {
    /// Extra stroke offset in pixels (scaled by font_size / units_per_em). 0 = none.
    embolden: f32 = 0,
    /// Horizontal shear factor. 0.2 ~= 12 degrees synthetic italic. 0 = upright.
    skew_x: f32 = 0,
};

pub const FaceSpec = struct {
    data: []const u8,
    weight: FontWeight = .regular,
    italic: bool = false,
    fallback: bool = false,
    synthetic: SyntheticStyle = .{},
};

pub const ItemizedRun = struct {
    face_index: FaceIndex,
    text_start: u32,
    text_end: u32,
};

pub fn isRenderableTextCodepoint(codepoint: u32) bool {
    if (codepoint > std.math.maxInt(u21)) return false;
    if (!std.unicode.utf8ValidCodepoint(@intCast(codepoint))) return false;
    if (codepoint < 0x20) return false;
    if (codepoint >= 0x7F and codepoint < 0xA0) return false;
    return true;
}

// ── Internal types ──

/// Immutable font configuration shared across snapshots via refcount.
/// Created once during TextAtlas.init, never modified.
pub const FontConfig = struct {
    ref_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    allocator: Allocator,
    faces: []FaceConfig,
    style_chains: std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)),
    global_chain: []FaceIndex,
    primary_face: ?FaceIndex,

    pub fn retain(self: *FontConfig) *FontConfig {
        _ = self.ref_count.fetchAdd(1, .monotonic);
        return self;
    }

    pub fn release(self: *FontConfig) void {
        if (self.ref_count.fetchSub(1, .acq_rel) == 1) {
            const allocator = self.allocator;
            for (self.faces) |*fc| fc.deinit();
            allocator.free(self.faces);

            var it = self.style_chains.iterator();
            while (it.next()) |entry| entry.value_ptr.deinit(allocator);
            self.style_chains.deinit(allocator);

            allocator.free(self.global_chain);
            allocator.destroy(self);
        }
    }
};

/// Per-face immutable data: parsed font, shapers, style metadata.
pub const FaceConfig = struct {
    font: ttf.Font,
    font_data: []const u8,
    weight: FontWeight,
    italic: bool,
    synthetic: SyntheticStyle,
    shaper: ?opentype.Shaper,
    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void,
    owns_shapers: bool, // false when sharing with another face (dedup)

    fn deinit(self: *FaceConfig) void {
        if (!self.owns_shapers) return;
        if (self.shaper) |*s| s.deinit();
        if (comptime build_options.enable_harfbuzz) {
            if (self.hb_shaper) |*hbs| hbs.deinit();
        }
    }
};

/// Per-face, per-snapshot glyph data. Rebuilt when the atlas is extended.
pub const FaceGlyphData = struct {
    glyph_map: std.AutoHashMap(u16, GlyphInfo),
    glyph_lut: ?[]GlyphInfo = null,
    /// Parallel presence bitset for `glyph_lut`: bit `gid` is set iff `glyph_map`
    /// has an entry for `gid`. Required because a present-but-empty glyph (e.g.
    /// space, with `h_band_count == 0`) is indistinguishable in the LUT from an
    /// absent gid that landed in the zero-initialised slot.
    glyph_lut_present: ?[]u64 = null,
    glyph_lut_len: u32 = 0,
    colr_base_map: ?std.AutoHashMap(u16, ColrBaseInfo) = null,

    pub fn deinit(self: *FaceGlyphData, allocator: Allocator) void {
        self.glyph_map.deinit();
        if (self.glyph_lut) |lut| allocator.free(lut);
        if (self.glyph_lut_present) |bits| allocator.free(bits);
        if (self.colr_base_map) |*cbm| cbm.deinit();
    }

    pub fn clone(self: *const FaceGlyphData, allocator: Allocator) !FaceGlyphData {
        var glyph_map = std.AutoHashMap(u16, GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();
        var it = self.glyph_map.iterator();
        while (it.next()) |entry| try glyph_map.put(entry.key_ptr.*, entry.value_ptr.*);

        var colr_base_map: ?std.AutoHashMap(u16, ColrBaseInfo) = null;
        if (self.colr_base_map) |cbm| {
            colr_base_map = std.AutoHashMap(u16, ColrBaseInfo).init(allocator);
            var cit = cbm.iterator();
            while (cit.next()) |entry| try colr_base_map.?.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var result = FaceGlyphData{
            .glyph_map = glyph_map,
            .colr_base_map = colr_base_map,
        };
        try result.buildGlyphLut(allocator);
        return result;
    }

    pub fn getGlyph(self: *const FaceGlyphData, gid: u16) ?GlyphInfo {
        if (self.glyph_lut) |lut| {
            if (gid >= self.glyph_lut_len) return null;
            if (self.glyph_lut_present) |bits| {
                const word = bits[gid >> 6];
                if ((word >> @intCast(gid & 63)) & 1 == 0) return null;
            }
            return lut[gid];
        }
        return self.glyph_map.get(gid);
    }

    pub fn buildGlyphLut(self: *FaceGlyphData, allocator: Allocator) !void {
        if (self.glyph_lut) |lut| allocator.free(lut);
        self.glyph_lut = null;
        if (self.glyph_lut_present) |bits| allocator.free(bits);
        self.glyph_lut_present = null;
        self.glyph_lut_len = 0;

        if (self.glyph_map.count() == 0) return;

        var max_gid: u32 = 0;
        var it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.* > max_gid) max_gid = entry.key_ptr.*;
        }

        const size = max_gid + 1;
        const lut = try allocator.alloc(GlyphInfo, size);
        errdefer allocator.free(lut);
        @memset(lut, std.mem.zeroes(GlyphInfo));

        const word_count = (size + 63) / 64;
        const present = try allocator.alloc(u64, word_count);
        @memset(present, 0);

        it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            const gid = entry.key_ptr.*;
            lut[gid] = entry.value_ptr.*;
            present[gid >> 6] |= @as(u64, 1) << @intCast(gid & 63);
        }

        self.glyph_lut = lut;
        self.glyph_lut_present = present;
        self.glyph_lut_len = @intCast(size);
    }
};

// ── FontConfig construction ──

pub fn buildFontConfig(allocator: Allocator, specs: []const FaceSpec) !*FontConfig {
    const config = try allocator.create(FontConfig);
    errdefer allocator.destroy(config);

    const faces = try allocator.alloc(FaceConfig, specs.len);
    errdefer allocator.free(faces);

    // Parse fonts, deduplicating by data pointer.
    var parsed_cache = std.AutoHashMap([*]const u8, struct { font: ttf.Font, shaper: ?opentype.Shaper, hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void }).init(allocator);
    defer parsed_cache.deinit();

    for (specs, 0..) |spec, i| {
        if (parsed_cache.get(spec.data.ptr)) |cached| {
            faces[i] = .{
                .font = cached.font,
                .font_data = spec.data,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .shaper = cached.shaper,
                .hb_shaper = cached.hb_shaper,
                .owns_shapers = false,
            };
        } else {
            const font = try ttf.Font.init(spec.data);
            const shaper = opentype.Shaper.init(allocator, spec.data, font.gsub_offset, font.gpos_offset) catch null;
            const hb_shaper = if (comptime build_options.enable_harfbuzz)
                harfbuzz.HarfBuzzShaper.init(spec.data, font.units_per_em) catch null
            else {};

            try parsed_cache.put(spec.data.ptr, .{ .font = font, .shaper = shaper, .hb_shaper = hb_shaper });

            faces[i] = .{
                .font = font,
                .font_data = spec.data,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .shaper = shaper,
                .hb_shaper = hb_shaper,
                .owns_shapers = true,
            };
        }
    }

    // Build style chains and global fallback chain.
    var style_chains = std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)).empty;
    errdefer {
        var it = style_chains.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        style_chains.deinit(allocator);
    }

    var global_chain_list = std.ArrayListUnmanaged(FaceIndex).empty;
    errdefer global_chain_list.deinit(allocator);

    var primary_face: ?FaceIndex = null;

    for (specs, 0..) |spec, i| {
        const fi: FaceIndex = @intCast(i);

        if (spec.fallback) {
            try global_chain_list.append(allocator, fi);
            if (primary_face == null) primary_face = fi;
        } else {
            const key = packStyle(.{ .weight = spec.weight, .italic = spec.italic });
            const gop = try style_chains.getOrPut(allocator, key);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(allocator, fi);

            if (primary_face == null and spec.weight == .regular and !spec.italic) {
                primary_face = fi;
            }
        }
    }

    const global_chain = try allocator.alloc(FaceIndex, global_chain_list.items.len);
    @memcpy(global_chain, global_chain_list.items);
    global_chain_list.deinit(allocator);

    config.* = .{
        .allocator = allocator,
        .faces = faces,
        .style_chains = style_chains,
        .global_chain = global_chain,
        .primary_face = primary_face,
    };

    return config;
}

// ── Resolution helpers ──

pub fn resolveInner(config: *const FontConfig, style: FontStyle, codepoint: u21, depth: u8) ?FaceIndex {
    if (depth > 3) return null;

    // 1. Style-specific chain
    if (config.style_chains.get(packStyle(style))) |chain| {
        for (chain.items) |fi| {
            if (faceHasGlyph(config, fi, codepoint)) return fi;
        }
    }

    // 2. Global fallbacks
    for (config.global_chain) |fi| {
        if (faceHasGlyph(config, fi, codepoint)) return fi;
    }

    // 3. Style degradation
    const next_depth = depth + 1;
    if (style.italic and style.weight != .regular) {
        if (resolveInner(config, .{ .weight = style.weight, .italic = false }, codepoint, next_depth)) |fi| return fi;
        if (resolveInner(config, .{ .weight = .regular, .italic = true }, codepoint, next_depth)) |fi| return fi;
        return resolveInner(config, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.italic) {
        return resolveInner(config, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.weight != .regular) {
        return resolveInner(config, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    }

    return null;
}

fn faceHasGlyph(config: *const FontConfig, fi: FaceIndex, codepoint: u21) bool {
    const gid = config.faces[fi].font.glyphIndex(codepoint) catch return false;
    return gid != 0;
}

fn packStyle(style: FontStyle) u8 {
    return @as(u8, @intFromEnum(style.weight)) | (@as(u8, @intFromBool(style.italic)) << 4);
}

// ── Itemization ──

pub fn itemizeText(allocator: Allocator, config: *const FontConfig, style: FontStyle, text: []const u8) ![]ItemizedRun {
    _ = std.unicode.Utf8View.init(text) catch return error.InvalidUtf8;
    var runs = std.ArrayListUnmanaged(ItemizedRun).empty;
    errdefer runs.deinit(allocator);

    var byte_offset: u32 = 0;
    var current_face: ?FaceIndex = null;
    var run_start: u32 = 0;

    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch return error.InvalidUtf8;
        if (i + cp_len > text.len) return error.InvalidUtf8;
        const cp: u21 = std.unicode.utf8Decode(text[i..][0..cp_len]) catch return error.InvalidUtf8;

        const face_idx = resolveInner(config, style, cp, 0) orelse
            if (config.primary_face) |pf| pf else {
                i += cp_len;
                byte_offset += @intCast(cp_len);
                continue;
            };

        if (current_face == null) {
            current_face = face_idx;
            run_start = byte_offset;
        } else if (current_face.? != face_idx) {
            try runs.append(allocator, .{
                .face_index = current_face.?,
                .text_start = run_start,
                .text_end = byte_offset,
            });
            current_face = face_idx;
            run_start = byte_offset;
        }

        i += cp_len;
        byte_offset += @intCast(cp_len);
    }

    if (current_face) |fi| {
        try runs.append(allocator, .{
            .face_index = fi,
            .text_start = run_start,
            .text_end = byte_offset,
        });
    }

    return try runs.toOwnedSlice(allocator);
}

pub fn glyphIndexForCellMetrics(fc: *const FaceConfig) !u16 {
    const candidates = [_]u21{ 'M', 'W', ' ', '0' };
    for (candidates) |cp| {
        const gid = try fc.font.glyphIndex(cp);
        if (gid != 0) return gid;
    }
    return error.MissingCellMetricsGlyph;
}

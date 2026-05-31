//! Text shaping for snail.
//!
//! `Shaper` owns a list of fonts (with style + fallback metadata) and turns a
//! UTF-8 string into a `ShapedText` glyph stream via HarfBuzz (when enabled)
//! with a basic in-tree fallback. Callers feed `ShapedText` into
//! `shapedRunPicture` / `hintedShapedRunPicture` to build a `Picture`, and
//! drive curve insertion into an `Atlas` themselves.

const std = @import("std");
const build_options = @import("build_options");

const ttf = @import("font/ttf.zig");
const opentype = @import("font/opentype.zig");
const hinter_mod = @import("font/hinter.zig");
const harfbuzz = if (build_options.enable_harfbuzz) @import("font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};
const vec = @import("math/vec.zig");

pub const Hinter = hinter_mod.Hinter;
pub const HintPpem = hinter_mod.HintPpem;

const Allocator = std.mem.Allocator;
const Vec2 = vec.Vec2;

// ── Public types ──

pub const FaceIndex = u16;

/// Half-open source-byte range, in the coordinate system of the text passed
/// to `Shaper.shape` / `Shaper.shapeOpts`. `end` is exclusive.
pub const SourceRange = struct {
    start: u32,
    end: u32,
};

/// An OpenType feature request forwarded to the shaper. `tag` is the 4-byte
/// feature tag in font-canonical order (e.g. `.{ 'l', 'i', 'g', 'a' }`).
/// `value = 0` disables, `value >= 1` enables (some features take an index).
/// `range = null` applies the feature to the entire text; a non-null range
/// restricts it to those source bytes.
pub const OpenTypeFeature = struct {
    tag: [4]u8,
    value: u32 = 1,
    range: ?SourceRange = null,
};

pub const ShapeOptions = struct {
    features: []const OpenTypeFeature = &.{},
    /// When set, faces with an attached `Hinter` (see `Shaper.attachHinter`)
    /// route shaping through HarfBuzz's `glyph_h_advance` font_func that
    /// returns hint-quantized advances at this ppem. Faces without a
    /// hinter fall back to em-space shaping transparently. The returned
    /// `ShapedText` is always em-space (the hinted advances are converted
    /// via `1 / ppem_26_6` so that multiplying by `ppem_px` downstream
    /// recovers the original 26.6 pixel positions exactly).
    target_ppem: ?HintPpem = null,
};

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

/// Synthetic style hints attached to a face spec. The shaper carries them on
/// the `Face` so callers can read them back when laying out glyphs.
pub const SyntheticStyle = struct {
    embolden: f32 = 0,
    skew_x: f32 = 0,
};

pub const FaceSpec = struct {
    data: []const u8,
    weight: FontWeight = .regular,
    italic: bool = false,
    fallback: bool = false,
    synthetic: SyntheticStyle = .{},
};

pub const MissingGlyphReplacement = struct {
    face_index: FaceIndex,
    glyph_id: u16,
    codepoint: u21,
};

pub const ShapedText = struct {
    allocator: Allocator,
    glyphs: []Glyph,

    pub const Glyph = struct {
        face_index: FaceIndex,
        glyph_id: u16,
        x_offset: f32,
        y_offset: f32,
        x_advance: f32,
        y_advance: f32,
        source_start: u32,
        source_end: u32,
    };

    pub fn advanceX(self: *const ShapedText) f32 {
        var sum: f32 = 0;
        for (self.glyphs) |g| sum += g.x_advance;
        return sum;
    }

    pub fn advanceY(self: *const ShapedText) f32 {
        var sum: f32 = 0;
        for (self.glyphs) |g| sum += g.y_advance;
        return sum;
    }

    pub fn deinit(self: *ShapedText) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub fn isRenderableTextCodepoint(codepoint: u32) bool {
    if (codepoint > std.math.maxInt(u21)) return false;
    if (!std.unicode.utf8ValidCodepoint(@intCast(codepoint))) return false;
    if (codepoint < 0x20) return false;
    if (codepoint >= 0x7F and codepoint < 0xA0) return false;
    return true;
}

// ── Shaper ──

/// One parsed face inside a `Shaper`. Owns the font + (optionally shared)
/// HarfBuzz / OpenType shapers driven from the underlying font data.
const Face = struct {
    font: ttf.Font,
    font_data: []const u8,
    weight: FontWeight,
    italic: bool,
    synthetic: SyntheticStyle,
    shaper: ?opentype.Shaper,
    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void,
    owns_shapers: bool,

    fn deinit(self: *Face) void {
        if (!self.owns_shapers) return;
        if (self.shaper) |*s| s.deinit();
        if (comptime build_options.enable_harfbuzz) {
            if (self.hb_shaper) |*hbs| hbs.deinit();
        }
    }
};

const FontDataKey = struct {
    ptr: [*]const u8,
    len: usize,
};

const ParsedFont = struct {
    font: ttf.Font,
    shaper: ?opentype.Shaper,
    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void,

    fn deinit(self: *ParsedFont) void {
        if (self.shaper) |*s| s.deinit();
        if (comptime build_options.enable_harfbuzz) {
            if (self.hb_shaper) |*hbs| hbs.deinit();
        }
    }
};

/// Owns a list of fonts and turns text into a glyph stream. Construct once
/// per font set, share the resulting `Shaper` across calls.
pub const Shaper = struct {
    allocator: Allocator,
    faces: []Face,
    /// One slot per face. Populated lazily by `attachHinter`. The
    /// Hinter is owned heap-side so the pointer is stable across
    /// `Face` value copies and gets shared between shape-time advance
    /// queries (via HB font_func) and render-time curve extraction.
    hinters: []?*Hinter,
    style_chains: std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)),
    global_chain: []FaceIndex,
    primary_face: ?FaceIndex,
    missing_glyph_replacement: ?MissingGlyphReplacement,

    pub fn init(allocator: Allocator, specs: []const FaceSpec) !Shaper {
        const faces = try buildFaces(allocator, specs);
        errdefer deinitFaces(allocator, faces);

        var chains = try buildChains(allocator, specs);
        errdefer chains.deinit(allocator);

        const hinters = try allocator.alloc(?*Hinter, faces.len);
        @memset(hinters, null);
        errdefer allocator.free(hinters);

        return .{
            .allocator = allocator,
            .faces = faces,
            .hinters = hinters,
            .style_chains = chains.style_chains,
            .global_chain = chains.global_chain,
            .primary_face = chains.primary_face,
            .missing_glyph_replacement = findMissingGlyphReplacement(faces, &chains),
        };
    }

    pub fn deinit(self: *Shaper) void {
        for (self.hinters) |maybe_hinter| {
            if (maybe_hinter) |h| {
                h.deinit();
                self.allocator.destroy(h);
            }
        }
        self.allocator.free(self.hinters);
        for (self.faces) |*f| f.deinit();
        self.allocator.free(self.faces);
        var it = self.style_chains.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(self.allocator);
        self.style_chains.deinit(self.allocator);
        self.allocator.free(self.global_chain);
        self.* = undefined;
    }

    /// Try to attach a TT bytecode hinter to `face_index`. Returns
    /// `error.NoHinting` for fonts that lack `fpgm`/`prep`/`cvt`. On
    /// success, the hinter is owned by the Shaper and the face's HB
    /// shaper (if any) gets a `glyph_h_advance` callback wired to it.
    /// Idempotent: calling twice on the same face is a no-op.
    pub fn attachHinter(self: *Shaper, face_index: FaceIndex) !void {
        if (self.hinters[face_index] != null) return;
        const fc = &self.faces[face_index];
        const wrapped = hinter_mod.Font{ .inner = fc.font };
        const hinter_ptr = try self.allocator.create(Hinter);
        errdefer self.allocator.destroy(hinter_ptr);
        hinter_ptr.* = try Hinter.init(self.allocator, &wrapped);
        errdefer hinter_ptr.deinit();
        if (comptime build_options.enable_harfbuzz) {
            if (fc.hb_shaper) |*hbs| try hbs.attachHinter(self.allocator, hinter_ptr);
        }
        self.hinters[face_index] = hinter_ptr;
    }

    pub fn hinterForFace(self: *const Shaper, face_index: FaceIndex) ?*Hinter {
        return self.hinters[face_index];
    }

    pub fn faceCount(self: *const Shaper) usize {
        return self.faces.len;
    }

    pub fn face(self: *const Shaper, index: FaceIndex) *const Face {
        return &self.faces[index];
    }

    pub fn shape(
        self: *const Shaper,
        allocator: Allocator,
        style: FontStyle,
        text: []const u8,
    ) !ShapedText {
        return self.shapeOpts(allocator, style, text, .{});
    }

    pub fn shapeOpts(
        self: *const Shaper,
        allocator: Allocator,
        style: FontStyle,
        text: []const u8,
        opts: ShapeOptions,
    ) !ShapedText {
        const runs = try itemizeText(allocator, self, style, text);
        defer allocator.free(runs);

        var glyphs: std.ArrayListUnmanaged(ShapedText.Glyph) = .empty;
        errdefer glyphs.deinit(allocator);

        var cursor_x: f32 = 0;
        var cursor_y: f32 = 0;
        for (runs) |run| {
            const fc = &self.faces[run.face_index];
            const segment = text[run.text_start..run.text_end];
            const shaped_run = try shapeRunForFace(
                allocator,
                fc,
                run.face_index,
                segment,
                run.text_start,
                self.missing_glyph_replacement,
                opts,
            );
            defer if (shaped_run.glyphs.len > 0) allocator.free(shaped_run.glyphs);

            for (shaped_run.glyphs) |g| {
                try glyphs.append(allocator, .{
                    .face_index = g.face_index,
                    .glyph_id = g.glyph_id,
                    .x_offset = cursor_x + g.x_offset,
                    .y_offset = cursor_y + g.y_offset,
                    .x_advance = g.x_advance,
                    .y_advance = g.y_advance,
                    .source_start = g.source_start,
                    .source_end = g.source_end,
                });
            }
            cursor_x += shaped_run.advance_x;
            cursor_y += shaped_run.advance_y;
        }

        return .{
            .allocator = allocator,
            .glyphs = try glyphs.toOwnedSlice(allocator),
        };
    }
};

// ── Face construction ──

fn buildFaces(allocator: Allocator, specs: []const FaceSpec) ![]Face {
    const faces = try allocator.alloc(Face, specs.len);
    errdefer allocator.free(faces);
    var initialized: usize = 0;
    errdefer for (faces[0..initialized]) |*f| f.deinit();

    var parsed_cache: std.AutoHashMap(FontDataKey, ParsedFont) = .init(allocator);
    defer parsed_cache.deinit();

    for (specs, 0..) |spec, i| {
        const key = FontDataKey{ .ptr = spec.data.ptr, .len = spec.data.len };
        if (parsed_cache.get(key)) |cached| {
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
            var parsed = try parseFont(allocator, spec.data);
            errdefer parsed.deinit();
            try parsed_cache.put(key, parsed);
            faces[i] = .{
                .font = parsed.font,
                .font_data = spec.data,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .shaper = parsed.shaper,
                .hb_shaper = parsed.hb_shaper,
                .owns_shapers = true,
            };
        }
        initialized += 1;
    }

    return faces;
}

fn deinitFaces(allocator: Allocator, faces: []Face) void {
    for (faces) |*f| f.deinit();
    allocator.free(faces);
}

fn parseFont(allocator: Allocator, data: []const u8) !ParsedFont {
    var parsed = ParsedFont{
        .font = try ttf.Font.init(data),
        .shaper = null,
        .hb_shaper = if (comptime build_options.enable_harfbuzz) null else {},
    };
    errdefer parsed.deinit();
    parsed.shaper = opentype.Shaper.init(allocator, data, parsed.font.gsub_offset, parsed.font.gpos_offset) catch null;
    if (comptime build_options.enable_harfbuzz) {
        parsed.hb_shaper = harfbuzz.HarfBuzzShaper.init(data, parsed.font.units_per_em) catch null;
    }
    return parsed;
}

// ── Chain / itemization ──

const Chains = struct {
    style_chains: std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)),
    global_chain: []FaceIndex,
    primary_face: ?FaceIndex,

    fn deinit(self: *Chains, allocator: Allocator) void {
        var it = self.style_chains.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        self.style_chains.deinit(allocator);
        allocator.free(self.global_chain);
    }
};

fn buildChains(allocator: Allocator, specs: []const FaceSpec) !Chains {
    var style_chains: std.AutoHashMapUnmanaged(u8, std.ArrayListUnmanaged(FaceIndex)) = .empty;
    errdefer {
        var it = style_chains.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        style_chains.deinit(allocator);
    }

    var global_list: std.ArrayListUnmanaged(FaceIndex) = .empty;
    errdefer global_list.deinit(allocator);

    var primary_face: ?FaceIndex = null;

    for (specs, 0..) |spec, i| {
        const fi: FaceIndex = @intCast(i);
        if (spec.fallback) {
            try global_list.append(allocator, fi);
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

    const global_chain = try global_list.toOwnedSlice(allocator);
    return .{
        .style_chains = style_chains,
        .global_chain = global_chain,
        .primary_face = primary_face,
    };
}

fn packStyle(style: FontStyle) u8 {
    return @as(u8, @intFromEnum(style.weight)) | (@as(u8, @intFromBool(style.italic)) << 4);
}

const missing_glyph_replacement_codepoints = [_]u21{ 0xFFFD, 0x25A1 };

fn findMissingGlyphReplacement(faces: []const Face, chains: *const Chains) ?MissingGlyphReplacement {
    for (missing_glyph_replacement_codepoints) |codepoint| {
        if (chains.primary_face) |fi| {
            if (replacementInFace(faces, fi, codepoint)) |r| return r;
        }
        for (chains.global_chain) |fi| {
            if (replacementInFace(faces, fi, codepoint)) |r| return r;
        }
        for (faces, 0..) |_, i| {
            const fi: FaceIndex = @intCast(i);
            if (replacementInFace(faces, fi, codepoint)) |r| return r;
        }
    }
    return null;
}

fn replacementInFace(faces: []const Face, face_index: FaceIndex, codepoint: u21) ?MissingGlyphReplacement {
    const gid = faces[face_index].font.glyphIndex(codepoint) catch return null;
    if (gid == 0) return null;
    return .{ .face_index = face_index, .glyph_id = gid, .codepoint = codepoint };
}

fn faceHasGlyph(shaper: *const Shaper, fi: FaceIndex, codepoint: u21) bool {
    const gid = shaper.faces[fi].font.glyphIndex(codepoint) catch return false;
    return gid != 0;
}

fn resolveFace(shaper: *const Shaper, style: FontStyle, codepoint: u21, depth: u8) ?FaceIndex {
    if (depth > 3) return null;

    if (shaper.style_chains.get(packStyle(style))) |chain| {
        for (chain.items) |fi| if (faceHasGlyph(shaper, fi, codepoint)) return fi;
    }
    for (shaper.global_chain) |fi| {
        if (faceHasGlyph(shaper, fi, codepoint)) return fi;
    }

    const next_depth = depth + 1;
    if (style.italic and style.weight != .regular) {
        if (resolveFace(shaper, .{ .weight = style.weight, .italic = false }, codepoint, next_depth)) |fi| return fi;
        if (resolveFace(shaper, .{ .weight = .regular, .italic = true }, codepoint, next_depth)) |fi| return fi;
        return resolveFace(shaper, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.italic) {
        return resolveFace(shaper, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.weight != .regular) {
        return resolveFace(shaper, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    }
    return null;
}

const ItemizedRun = struct {
    face_index: FaceIndex,
    text_start: u32,
    text_end: u32,
};

fn itemizeText(
    allocator: Allocator,
    shaper: *const Shaper,
    style: FontStyle,
    text: []const u8,
) ![]ItemizedRun {
    _ = std.unicode.Utf8View.init(text) catch return error.InvalidUtf8;
    var runs: std.ArrayListUnmanaged(ItemizedRun) = .empty;
    errdefer runs.deinit(allocator);

    var byte_offset: u32 = 0;
    var current_face: ?FaceIndex = null;
    var run_start: u32 = 0;

    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch return error.InvalidUtf8;
        if (i + cp_len > text.len) return error.InvalidUtf8;
        const cp: u21 = std.unicode.utf8Decode(text[i..][0..cp_len]) catch return error.InvalidUtf8;

        const face_idx = resolveFace(shaper, style, cp, 0) orelse unresolvedCodepointFace(shaper) orelse {
            i += cp_len;
            byte_offset += @intCast(cp_len);
            continue;
        };

        if (current_face == null) {
            current_face = face_idx;
            run_start = byte_offset;
        } else if (current_face.? != face_idx) {
            try runs.append(allocator, .{ .face_index = current_face.?, .text_start = run_start, .text_end = byte_offset });
            current_face = face_idx;
            run_start = byte_offset;
        }

        i += cp_len;
        byte_offset += @intCast(cp_len);
    }

    if (current_face) |fi| {
        try runs.append(allocator, .{ .face_index = fi, .text_start = run_start, .text_end = byte_offset });
    }

    return try runs.toOwnedSlice(allocator);
}

fn unresolvedCodepointFace(shaper: *const Shaper) ?FaceIndex {
    if (shaper.missing_glyph_replacement) |r| return r.face_index;
    return shaper.primary_face;
}

// ── Per-run shaping ──

const ShapeRunResult = struct {
    glyphs: []ShapedText.Glyph,
    advance_x: f32,
    advance_y: f32,
};

fn emptyRun() ShapeRunResult {
    return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };
}

fn shapeRunForFace(
    allocator: Allocator,
    fc: *const Face,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
    replacement: ?MissingGlyphReplacement,
    opts: ShapeOptions,
) !ShapeRunResult {
    if (text.len == 0) return emptyRun();
    const missing_replacement = if (replacement) |r|
        if (r.face_index == face_index) r.glyph_id else null
    else
        null;
    if (try shapeWithHarfbuzz(allocator, fc, face_index, text, source_base, missing_replacement, opts)) |r| return r;
    const inv_upem = 1.0 / @as(f32, @floatFromInt(fc.font.units_per_em));
    return shapeWithFallback(allocator, fc, face_index, text, source_base, inv_upem, missing_replacement);
}

fn shapeWithHarfbuzz(
    allocator: Allocator,
    fc: *const Face,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
    missing_replacement: ?u16,
    opts: ShapeOptions,
) !?ShapeRunResult {
    if (comptime !build_options.enable_harfbuzz) return null;
    const hbs = fc.hb_shaper orelse return null;

    var feature_buf: [32]harfbuzz.Feature = undefined;
    const hb_features = buildHbFeatures(opts.features, source_base, @intCast(text.len), &feature_buf);

    // Pick em-space or hinted shaping. The hinted path needs the face's HB
    // shaper to have an attached hinter (sub_font with overridden
    // glyph_h_advance), otherwise we silently fall back to em-space.
    const use_hinted = if (opts.target_ppem) |_| hbs.hasHinter() else false;
    const shaped = if (use_hinted)
        hbs.shapeTextHinted(text, hb_features, opts.target_ppem.?)
    else
        hbs.shapeTextWithFeatures(text, hb_features);

    // HB output is in whatever units we asked of `hb_font_set_scale`:
    //   • em path → upem units (divide by upem to reach em-space float).
    //   • hinted path → ppem_26_6 units (divide by ppem_26_6 to reach
    //     em-space). Both end up in the same em-space coordinate system
    //     so downstream code is unit-agnostic; the hinted path simply
    //     bakes hint quantization into the values it carries.
    const inv: f32 = if (use_hinted)
        1.0 / @as(f32, @floatFromInt(opts.target_ppem.?.x_26_6))
    else
        1.0 / @as(f32, @floatFromInt(fc.font.units_per_em));

    if (shaped.count == 0 or shaped.infos == null or shaped.positions == null) return emptyRun();

    const out = try allocator.alloc(ShapedText.Glyph, shaped.count);
    errdefer allocator.free(out);

    var cursor_x: f32 = 0;
    var cursor_y: f32 = 0;
    for (0..shaped.count) |i| {
        const info = shaped.infos[i];
        const pos = shaped.positions[i];
        const cluster = @min(@as(u32, @intCast(info.cluster)), @as(u32, @intCast(text.len)));
        const raw_gid: u16 = @intCast(info.codepoint);
        const glyph_id = replacementGlyphId(raw_gid, missing_replacement);
        const advance_x: f32 = if (raw_gid != 0 or glyph_id == 0)
            @floatFromInt(pos.x_advance)
        else
            @floatFromInt(fc.font.advanceWidth(glyph_id) catch 500);
        out[i] = .{
            .face_index = face_index,
            .glyph_id = glyph_id,
            .x_offset = (cursor_x + @as(f32, @floatFromInt(pos.x_offset))) * inv,
            .y_offset = -(cursor_y + @as(f32, @floatFromInt(pos.y_offset))) * inv,
            .x_advance = advance_x * inv,
            .y_advance = -@as(f32, @floatFromInt(pos.y_advance)) * inv,
            .source_start = source_base + cluster,
            .source_end = source_base + @as(u32, @intCast(text.len)),
        };
        cursor_x += advance_x;
        cursor_y += @as(f32, @floatFromInt(pos.y_advance));
    }

    return .{
        .glyphs = out,
        .advance_x = cursor_x * inv,
        .advance_y = -cursor_y * inv,
    };
}

fn replacementGlyphId(glyph_id: u16, missing_replacement: ?u16) u16 {
    if (glyph_id != 0) return glyph_id;
    return missing_replacement orelse 0;
}

fn buildHbFeatures(
    features: []const OpenTypeFeature,
    source_base: u32,
    segment_len: u32,
    out_buf: []harfbuzz.Feature,
) []const harfbuzz.Feature {
    if (comptime !build_options.enable_harfbuzz) return &.{};
    if (features.len == 0) return &.{};
    var n: usize = 0;
    for (features) |f| {
        if (n == out_buf.len) break;
        var start: c_uint = harfbuzz.FEATURE_GLOBAL_START;
        var end: c_uint = harfbuzz.FEATURE_GLOBAL_END;
        if (f.range) |r| {
            const seg_end = source_base + segment_len;
            if (r.end <= source_base or r.start >= seg_end) continue;
            const lo = if (r.start > source_base) r.start - source_base else 0;
            const hi = if (r.end < seg_end) r.end - source_base else segment_len;
            start = @intCast(lo);
            end = @intCast(hi);
        }
        out_buf[n] = .{
            .tag = harfbuzz.makeTag(f.tag),
            .value = f.value,
            .start = start,
            .end = end,
        };
        n += 1;
    }
    return out_buf[0..n];
}

const FallbackRun = struct {
    gids: []u16,
    src_starts: []u32,
    src_ends: []u32,
    glyph_count: usize,

    fn deinit(self: *FallbackRun, allocator: Allocator) void {
        allocator.free(self.gids);
        allocator.free(self.src_starts);
        allocator.free(self.src_ends);
        self.* = undefined;
    }
};

fn shapeWithFallback(
    allocator: Allocator,
    fc: *const Face,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
    inv_upem: f32,
    missing_replacement: ?u16,
) !ShapeRunResult {
    var cp_count: usize = 0;
    {
        const utf8_view = std.unicode.Utf8View.initUnchecked(text);
        var it = utf8_view.iterator();
        while (it.nextCodepoint()) |_| cp_count += 1;
    }
    if (cp_count == 0) return emptyRun();

    var run = try buildFallbackRun(allocator, fc, text, source_base, cp_count);
    defer run.deinit(allocator);
    applyFallbackLigatures(fc, &run);

    const out = try allocator.alloc(ShapedText.Glyph, run.glyph_count);
    errdefer allocator.free(out);

    var cursor_x: f32 = 0;
    var prev_gid: u16 = 0;
    for (run.gids[0..run.glyph_count], 0..) |gid, i| {
        if (gid == 0) {
            const glyph_id = missing_replacement orelse 0;
            const advance = if (glyph_id == 0)
                500.0 * inv_upem
            else
                @as(f32, @floatFromInt(fc.font.advanceWidth(glyph_id) catch 500)) * inv_upem;
            out[i] = .{
                .face_index = face_index,
                .glyph_id = glyph_id,
                .x_offset = cursor_x,
                .y_offset = 0,
                .x_advance = advance,
                .y_advance = 0,
                .source_start = run.src_starts[i],
                .source_end = run.src_ends[i],
            };
            cursor_x += advance;
            prev_gid = 0;
            continue;
        }

        cursor_x += @as(f32, @floatFromInt(fallbackKerning(fc, prev_gid, gid))) * inv_upem;
        const advance = @as(f32, @floatFromInt(fc.font.advanceWidth(gid) catch 500)) * inv_upem;
        out[i] = .{
            .face_index = face_index,
            .glyph_id = gid,
            .x_offset = cursor_x,
            .y_offset = 0,
            .x_advance = advance,
            .y_advance = 0,
            .source_start = run.src_starts[i],
            .source_end = run.src_ends[i],
        };
        cursor_x += advance;
        prev_gid = gid;
    }

    return .{ .glyphs = out, .advance_x = cursor_x, .advance_y = 0 };
}

fn buildFallbackRun(allocator: Allocator, fc: *const Face, text: []const u8, source_base: u32, cp_count: usize) !FallbackRun {
    const gids = try allocator.alloc(u16, cp_count);
    errdefer allocator.free(gids);
    const src_starts = try allocator.alloc(u32, cp_count);
    errdefer allocator.free(src_starts);
    const src_ends = try allocator.alloc(u32, cp_count);
    errdefer allocator.free(src_ends);

    var glyph_count: usize = 0;
    const utf8_view = std.unicode.Utf8View.initUnchecked(text);
    var it = utf8_view.iterator();
    while (it.nextCodepointSlice()) |cp_slice| {
        const byte_pos = @intFromPtr(cp_slice.ptr) - @intFromPtr(text.ptr);
        const cp = std.unicode.utf8Decode(cp_slice) catch 0;
        gids[glyph_count] = fc.font.glyphIndex(@intCast(cp)) catch 0;
        src_starts[glyph_count] = source_base + @as(u32, @intCast(byte_pos));
        src_ends[glyph_count] = source_base + @as(u32, @intCast(byte_pos + cp_slice.len));
        glyph_count += 1;
    }
    return .{ .gids = gids, .src_starts = src_starts, .src_ends = src_ends, .glyph_count = glyph_count };
}

fn applyFallbackLigatures(fc: *const Face, run: *FallbackRun) void {
    if (fc.shaper) |shaper| {
        run.glyph_count = shaper.applyLigaturesTracked(
            run.gids[0..run.glyph_count],
            run.src_starts[0..run.glyph_count],
            run.src_ends[0..run.glyph_count],
        ) catch run.glyph_count;
    }
}

fn fallbackKerning(fc: *const Face, prev_gid: u16, gid: u16) i16 {
    if (prev_gid == 0) return 0;
    var kern: i16 = 0;
    if (fc.shaper) |shaper| kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
    if (kern == 0) kern = fc.font.getKerning(prev_gid, gid) catch 0;
    return kern;
}

// ── Tests ──

const testing = std.testing;

test "Shaper shapes a basic latin run" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;
    var shaper = try Shaper.init(allocator, &.{.{ .data = font_data }});
    defer shaper.deinit();

    var shaped = try shaper.shape(allocator, .{}, "Hi");
    defer shaped.deinit();
    try testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
}

test "Shaper itemizes across fallback fonts" {
    const allocator = testing.allocator;
    var shaper = try Shaper.init(allocator, &.{
        .{ .data = @import("assets").noto_sans_regular },
        .{ .data = @import("assets").noto_sans_arabic, .fallback = true },
    });
    defer shaper.deinit();

    var shaped = try shaper.shape(allocator, .{}, "A\xd9\x85"); // 'A' + Arabic meem
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len >= 2);
    try testing.expectEqual(@as(FaceIndex, 0), shaped.glyphs[0].face_index);
    try testing.expectEqual(@as(FaceIndex, 1), shaped.glyphs[shaped.glyphs.len - 1].face_index);
}

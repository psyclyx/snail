//! Shaping context built from caller-owned `*const Font` values.
//!
//! `Faces` is the new-API replacement for `Shaper`. Differences:
//!
//! - Caller owns every `Font`. `Faces` borrows pointers; nothing is
//!   parsed inside.
//! - `face_index → font_id` is auto-derived by `*const Font` pointer
//!   identity, replacing the explicit `face_to_font_id` array the old
//!   picture builders required.
//! - No hinter slots, no `attachHinter`. Hinted advances are routed at
//!   shape time via `ShapeOptions.advance_provider` (typically backed
//!   by `snail.HintedGlyphCache`).
//!
//! Per-face HB and OpenType shapers are still parsed once at `build`
//! time and reused across `shape()` calls — that's the "owns" part of
//! `Faces`.
//!
//! Thread safety: not thread-safe. The per-face HarfBuzz shapers carry
//! HB-internal mutable state, and `shape()` configures the active
//! sub-font per call. Construct one `Faces` per thread that calls
//! `shape()`. The `*const Font` pointers each `Faces` borrows are
//! parse-only and freely shareable between threads.

const std = @import("std");
const build_options = @import("build_options");

const font_mod = @import("../font.zig");
const opentype = @import("../font/opentype.zig");
const harfbuzz = if (build_options.enable_harfbuzz) @import("../font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
    pub const Feature = void;
};

const text_mod = @import("../text.zig");

const Allocator = std.mem.Allocator;

pub const Font = font_mod.Font;
pub const FaceIndex = text_mod.FaceIndex;
pub const FontWeight = text_mod.FontWeight;
pub const FontStyle = text_mod.FontStyle;
pub const SyntheticStyle = text_mod.SyntheticStyle;
pub const MissingGlyphReplacement = text_mod.MissingGlyphReplacement;
pub const ShapedText = text_mod.ShapedText;
pub const ShapeOptions = text_mod.ShapeOptions;
pub const OpenTypeFeature = text_mod.OpenTypeFeature;
pub const AdvanceProvider = text_mod.AdvanceProvider;

/// Caller-provided face description. The `font` pointer must outlive
/// the `Faces` value built from it. `fallback` marks faces used for
/// scripts outside the styled chain (e.g. an Arabic or emoji face that
/// participates in fallback resolution for every style).
pub const Face = struct {
    font: *const Font,
    weight: FontWeight = .regular,
    italic: bool = false,
    fallback: bool = false,
    synthetic: SyntheticStyle = .{},
};

/// Internal per-face state. Owns the OT / HB shapers parsed from the
/// underlying font data; multiple `FaceState`s with the same `*const
/// Font` share one parse (the `owns_shapers` flag tracks that).
pub const FaceState = struct {
    font: *const Font,
    weight: FontWeight,
    italic: bool,
    synthetic: SyntheticStyle,
    shaper: ?opentype.Shaper,
    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void,
    owns_shapers: bool,

    fn deinit(self: *FaceState) void {
        if (!self.owns_shapers) return;
        if (self.shaper) |*s| s.deinit();
        if (comptime build_options.enable_harfbuzz) {
            if (self.hb_shaper) |*hbs| hbs.deinit();
        }
    }
};

const ParsedShapers = struct {
    shaper: ?opentype.Shaper,
    hb_shaper: if (build_options.enable_harfbuzz) ?harfbuzz.HarfBuzzShaper else void,

    fn deinit(self: *ParsedShapers) void {
        if (self.shaper) |*s| s.deinit();
        if (comptime build_options.enable_harfbuzz) {
            if (self.hb_shaper) |*hbs| hbs.deinit();
        }
    }
};

pub const Chains = struct {
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

pub const Faces = struct {
    allocator: Allocator,
    faces: []FaceState,
    chains: Chains,
    missing_glyph_replacement: ?MissingGlyphReplacement,
    /// Auto-derived from `Face.font` pointer identity. Indexed by face
    /// index; two faces backed by the same `*const Font` share a font id.
    face_to_font_id: []u32,
    /// Number of distinct fonts referenced (i.e. max(face_to_font_id) + 1
    /// when non-empty). Useful for sizing per-font helper caches.
    font_count: u32,

    pub fn build(allocator: Allocator, specs: []const Face) !Faces {
        const faces = try buildFaceStates(allocator, specs);
        errdefer deinitFaceStates(allocator, faces);

        var chains = try buildChains(allocator, specs);
        errdefer chains.deinit(allocator);

        const mapping = try buildFontIdMap(allocator, specs);

        return .{
            .allocator = allocator,
            .faces = faces,
            .chains = chains,
            .missing_glyph_replacement = findMissingGlyphReplacement(faces, &chains),
            .face_to_font_id = mapping.face_to_font_id,
            .font_count = mapping.font_count,
        };
    }

    pub fn deinit(self: *Faces) void {
        deinitFaceStates(self.allocator, self.faces);
        self.chains.deinit(self.allocator);
        self.allocator.free(self.face_to_font_id);
        self.* = undefined;
    }

    pub fn faceCount(self: *const Faces) usize {
        return self.faces.len;
    }

    pub fn fontIdForFace(self: *const Faces, face_index: FaceIndex) u32 {
        return self.face_to_font_id[face_index];
    }

    pub fn face(self: *const Faces, index: FaceIndex) *const FaceState {
        return &self.faces[index];
    }
};

// ── Face state construction (per-Font* parse dedup) ──

fn buildFaceStates(allocator: Allocator, specs: []const Face) ![]FaceState {
    const out = try allocator.alloc(FaceState, specs.len);
    errdefer allocator.free(out);
    var initialized: usize = 0;
    errdefer for (out[0..initialized]) |*f| f.deinit();

    var parsed_cache: std.AutoHashMap(*const Font, ParsedShapers) = .init(allocator);
    defer parsed_cache.deinit();

    for (specs, 0..) |spec, i| {
        if (parsed_cache.get(spec.font)) |cached| {
            out[i] = .{
                .font = spec.font,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .shaper = cached.shaper,
                .hb_shaper = cached.hb_shaper,
                .owns_shapers = false,
            };
        } else {
            var parsed = try parseShapers(allocator, spec.font);
            errdefer parsed.deinit();
            try parsed_cache.put(spec.font, parsed);
            out[i] = .{
                .font = spec.font,
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

    return out;
}

fn deinitFaceStates(allocator: Allocator, faces: []FaceState) void {
    for (faces) |*f| f.deinit();
    allocator.free(faces);
}

fn parseShapers(allocator: Allocator, font: *const Font) !ParsedShapers {
    var parsed = ParsedShapers{
        .shaper = null,
        .hb_shaper = if (comptime build_options.enable_harfbuzz) null else {},
    };
    errdefer parsed.deinit();
    parsed.shaper = opentype.Shaper.init(allocator, font.inner.data, font.inner.gsub_offset, font.inner.gpos_offset) catch null;
    if (comptime build_options.enable_harfbuzz) {
        parsed.hb_shaper = harfbuzz.HarfBuzzShaper.initFace(
            font.inner.data,
            font.inner.face_index,
            font.inner.units_per_em,
        ) catch null;
    }
    return parsed;
}

// ── Fallback chains ──

fn buildChains(allocator: Allocator, specs: []const Face) !Chains {
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

fn findMissingGlyphReplacement(faces: []const FaceState, chains: *const Chains) ?MissingGlyphReplacement {
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

fn replacementInFace(faces: []const FaceState, face_index: FaceIndex, codepoint: u21) ?MissingGlyphReplacement {
    const gid = faces[face_index].font.glyphIndex(codepoint) catch return null;
    if (gid == 0) return null;
    return .{ .face_index = face_index, .glyph_id = gid, .codepoint = codepoint };
}

fn faceHasGlyph(faces: []const FaceState, fi: FaceIndex, codepoint: u21) bool {
    const gid = faces[fi].font.glyphIndex(codepoint) catch return false;
    return gid != 0;
}

fn resolveFace(faces: []const FaceState, chains: *const Chains, style: FontStyle, codepoint: u21, depth: u8) ?FaceIndex {
    if (depth > 3) return null;
    if (chains.style_chains.get(packStyle(style))) |chain| {
        for (chain.items) |fi| if (faceHasGlyph(faces, fi, codepoint)) return fi;
    }
    for (chains.global_chain) |fi| {
        if (faceHasGlyph(faces, fi, codepoint)) return fi;
    }
    const next_depth = depth + 1;
    if (style.italic and style.weight != .regular) {
        if (resolveFace(faces, chains, .{ .weight = style.weight, .italic = false }, codepoint, next_depth)) |fi| return fi;
        if (resolveFace(faces, chains, .{ .weight = .regular, .italic = true }, codepoint, next_depth)) |fi| return fi;
        return resolveFace(faces, chains, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.italic) {
        return resolveFace(faces, chains, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    } else if (style.weight != .regular) {
        return resolveFace(faces, chains, .{ .weight = .regular, .italic = false }, codepoint, next_depth);
    }
    return null;
}

fn unresolvedCodepointFace(faces_value: *const Faces) ?FaceIndex {
    if (faces_value.missing_glyph_replacement) |r| return r.face_index;
    return faces_value.chains.primary_face;
}

// ── Itemization ──

const ItemizedRun = struct {
    face_index: FaceIndex,
    text_start: u32,
    text_end: u32,
};

fn itemizeText(allocator: Allocator, faces_value: *const Faces, style: FontStyle, text: []const u8) ![]ItemizedRun {
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

        const face_idx = resolveFace(faces_value.faces, &faces_value.chains, style, cp, 0) orelse unresolvedCodepointFace(faces_value) orelse {
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

// ── Per-run shaping (HB + analytic fallback) ──

const ShapeRunResult = struct {
    glyphs: []ShapedText.Glyph,
    advance_x: f32,
    advance_y: f32,
};

fn emptyRun() ShapeRunResult {
    return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };
}

fn shapeRun(
    allocator: Allocator,
    faces_value: *Faces,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
    opts: ShapeOptions,
) !ShapeRunResult {
    if (text.len == 0) return emptyRun();
    const fc = &faces_value.faces[face_index];
    const font_id = faces_value.face_to_font_id[face_index];
    const missing_replacement = if (faces_value.missing_glyph_replacement) |r|
        if (r.face_index == face_index) r.glyph_id else null
    else
        null;
    if (try shapeWithHarfbuzz(allocator, fc, face_index, font_id, faces_value.allocator, text, source_base, missing_replacement, opts)) |r| return r;
    const inv_upem = 1.0 / @as(f32, @floatFromInt(fc.font.inner.units_per_em));
    return shapeWithFallback(allocator, fc, face_index, font_id, text, source_base, inv_upem, missing_replacement);
}

fn shapeWithHarfbuzz(
    allocator: Allocator,
    fc: *FaceState,
    face_index: FaceIndex,
    font_id: u32,
    hb_allocator: Allocator,
    text: []const u8,
    source_base: u32,
    missing_replacement: ?u16,
    opts: ShapeOptions,
) !?ShapeRunResult {
    if (comptime !build_options.enable_harfbuzz) return null;
    if (fc.hb_shaper == null) return null;
    const hbs: *harfbuzz.HarfBuzzShaper = &fc.hb_shaper.?;

    var feature_buf: [32]harfbuzz.Feature = undefined;
    const hb_features = buildHbFeatures(opts.features, source_base, @intCast(text.len), &feature_buf);

    // `opts.advance_provider` is the new path: HB's hooks get attached
    // lazily and the provider routes through caller-owned state. The
    // provider is invoked at `opts.target_ppem`; absent that we use the
    // upem (a 1:1 em-space identity that still measures correctly).
    // The `covers` predicate gates per-face: faces the provider doesn't
    // cover shape em-space rather than getting wrong advances from the
    // provider's underlying VM/cache.
    var use_provider = false;
    if (opts.advance_provider) |provider| {
        if (provider.covers(provider.context, font_id)) {
            try hbs.attachAdvanceProvider(hb_allocator, provider, font_id);
            use_provider = true;
        }
    }

    const shaped = if (use_provider)
        // Provider ppem comes from the provider itself — but HB needs a
        // numeric ppem to set scale. The provider closure gets called
        // with this ppem; snail.HintedGlyphCache typically encodes the
        // active ppem in its context. We forward opts.target_ppem if
        // present, else the default em scale (units_per_em as 1:1).
        hbs.shapeTextWithProvider(text, hb_features, opts.target_ppem orelse defaultEmPpem(fc))
    else
        hbs.shapeTextWithFeatures(text, hb_features);

    const inv: f32 = if (use_provider)
        1.0 / @as(f32, @floatFromInt((opts.target_ppem orelse defaultEmPpem(fc)).x_26_6))
    else
        1.0 / @as(f32, @floatFromInt(fc.font.inner.units_per_em));

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
            .font_id = font_id,
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

fn defaultEmPpem(fc: *const FaceState) text_mod.HintPpem {
    const upem = fc.font.inner.units_per_em;
    return .{ .x_26_6 = upem, .y_26_6 = upem };
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
    fc: *const FaceState,
    face_index: FaceIndex,
    font_id: u32,
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
                .font_id = font_id,
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
            .font_id = font_id,
        };
        cursor_x += advance;
        prev_gid = gid;
    }
    return .{ .glyphs = out, .advance_x = cursor_x, .advance_y = 0 };
}

fn buildFallbackRun(allocator: Allocator, fc: *const FaceState, text: []const u8, source_base: u32, cp_count: usize) !FallbackRun {
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

fn applyFallbackLigatures(fc: *const FaceState, run: *FallbackRun) void {
    if (fc.shaper) |shaper| {
        run.glyph_count = shaper.applyLigaturesTracked(
            run.gids[0..run.glyph_count],
            run.src_starts[0..run.glyph_count],
            run.src_ends[0..run.glyph_count],
        ) catch run.glyph_count;
    }
}

fn fallbackKerning(fc: *const FaceState, prev_gid: u16, gid: u16) i16 {
    if (prev_gid == 0) return 0;
    var kern: i16 = 0;
    if (fc.shaper) |shaper| kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
    if (kern == 0) kern = fc.font.getKerning(prev_gid, gid) catch 0;
    return kern;
}

// ── Font-id derivation ──

const FontIdMap = struct {
    face_to_font_id: []u32,
    font_count: u32,
};

fn buildFontIdMap(allocator: Allocator, specs: []const Face) !FontIdMap {
    const out = try allocator.alloc(u32, specs.len);
    errdefer allocator.free(out);

    var by_ptr: std.AutoHashMap(*const Font, u32) = .init(allocator);
    defer by_ptr.deinit();

    var next_id: u32 = 0;
    for (specs, 0..) |spec, i| {
        const gop = try by_ptr.getOrPut(spec.font);
        if (!gop.found_existing) {
            gop.value_ptr.* = next_id;
            next_id += 1;
        }
        out[i] = gop.value_ptr.*;
    }

    return .{ .face_to_font_id = out, .font_count = next_id };
}

// ── Public free shape() ──

/// Shape `text` against `faces` with `opts`. Each glyph in the returned
/// `ShapedText` carries its resolved `font_id` (looked up via
/// `faces.fontIdForFace(face_index)`); picture builders read `g.font_id`
/// directly to key atlas records.
///
/// `opts.advance_provider`, if set, routes HarfBuzz's `glyph_h_advance`
/// font_func through the provider — typically a
/// `snail.HintedGlyphCache` closure — for hinted advances.
/// `opts.target_ppem` selects the ppem the provider is asked about and
/// the HB scale to set on the sub-font; the returned `ShapedText` is
/// em-space, so callers multiply by `font_size_px` downstream as
/// usual.
pub fn shape(
    allocator: Allocator,
    faces_value: *Faces,
    text: []const u8,
    opts: ShapeOptions,
) !ShapedText {
    const runs = try itemizeText(allocator, faces_value, opts.style, text);
    defer allocator.free(runs);

    var glyphs: std.ArrayListUnmanaged(ShapedText.Glyph) = .empty;
    errdefer glyphs.deinit(allocator);

    var cursor_x: f32 = 0;
    var cursor_y: f32 = 0;
    for (runs) |run| {
        const segment = text[run.text_start..run.text_end];
        const shaped_run = try shapeRun(
            allocator,
            faces_value,
            run.face_index,
            segment,
            run.text_start,
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
                .font_id = g.font_id,
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

// ── Tests ──

const testing = std.testing;
const assets = @import("assets");

test "Faces builds, dedups font_id by pointer identity, exposes fontIdForFace" {
    var font_a = try Font.init(assets.noto_sans_regular);
    var font_b = try Font.init(assets.noto_sans_bold);

    var faces = try Faces.build(testing.allocator, &.{
        .{ .font = &font_a },
        .{ .font = &font_b, .weight = .bold },
        .{ .font = &font_a, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
    });
    defer faces.deinit();

    try testing.expectEqual(@as(usize, 3), faces.faceCount());
    try testing.expectEqual(@as(u32, 2), faces.font_count);
    try testing.expectEqual(@as(u32, 0), faces.fontIdForFace(0));
    try testing.expectEqual(@as(u32, 1), faces.fontIdForFace(1));
    try testing.expectEqual(@as(u32, 0), faces.fontIdForFace(2));
}

test "Faces with fallback face populates global chain and missing-glyph replacement" {
    var font_regular = try Font.init(assets.noto_sans_regular);
    var font_arabic = try Font.init(assets.noto_sans_arabic);

    var faces = try Faces.build(testing.allocator, &.{
        .{ .font = &font_regular },
        .{ .font = &font_arabic, .fallback = true },
    });
    defer faces.deinit();

    try testing.expect(faces.missing_glyph_replacement != null);
    try testing.expectEqual(@as(usize, 1), faces.chains.global_chain.len);
}

test "shape produces ShapedText with font_id populated" {
    var font_regular = try Font.init(assets.noto_sans_regular);
    var font_arabic = try Font.init(assets.noto_sans_arabic);

    var faces = try Faces.build(testing.allocator, &.{
        .{ .font = &font_regular },
        .{ .font = &font_arabic, .fallback = true },
    });
    defer faces.deinit();

    var shaped = try shape(testing.allocator, &faces, "Hello", .{});
    defer shaped.deinit();

    try testing.expect(shaped.glyphs.len > 0);
    for (shaped.glyphs) |g| {
        try testing.expectEqual(@as(u32, 0), g.font_id);
    }
}

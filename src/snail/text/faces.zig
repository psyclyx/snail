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
//!   by `snail.TtAdvanceSource`..
//!
//! Per-face HarfBuzz shapers are parsed once at `build` time and reused
//! across `shape()` calls — that's the "owns" part of `Faces`.
//!
//! Thread safety: not thread-safe. The per-face HarfBuzz shapers carry
//! HB-internal mutable state, and `shape()` configures the active
//! sub-font per call. Construct one `Faces` per thread that calls
//! `shape()`. The `*const Font` pointers each `Faces` borrows are
//! parse-only and freely shareable between threads.

const std = @import("std");

const font_mod = @import("../font.zig");
const harfbuzz = @import("../font/harfbuzz.zig");

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
pub const TextDirection = text_mod.TextDirection;

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

/// Internal per-face state. Owns the HarfBuzz shaper parsed from the
/// underlying font data; multiple `FaceState`s with the same `*const
/// Font` share one parse (the `owns_shaper` flag tracks that).
pub const FaceState = struct {
    font: *const Font,
    weight: FontWeight,
    italic: bool,
    synthetic: SyntheticStyle,
    hb_shaper: harfbuzz.HarfBuzzShaper,
    owns_shaper: bool,

    fn deinit(self: *FaceState) void {
        if (self.owns_shaper) self.hb_shaper.deinit();
    }
};

const ParsedShaper = struct {
    hb_shaper: harfbuzz.HarfBuzzShaper,

    fn deinit(self: *ParsedShaper) void {
        self.hb_shaper.deinit();
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

    var parsed_cache: std.AutoHashMap(*const Font, ParsedShaper) = .init(allocator);
    defer parsed_cache.deinit();

    for (specs, 0..) |spec, i| {
        if (parsed_cache.get(spec.font)) |cached| {
            out[i] = .{
                .font = spec.font,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .hb_shaper = cached.hb_shaper,
                .owns_shaper = false,
            };
        } else {
            var parsed = try parseShaper(spec.font);
            errdefer parsed.deinit();
            try parsed_cache.put(spec.font, parsed);
            out[i] = .{
                .font = spec.font,
                .weight = spec.weight,
                .italic = spec.italic,
                .synthetic = spec.synthetic,
                .hb_shaper = parsed.hb_shaper,
                .owns_shaper = true,
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

fn parseShaper(font: *const Font) !ParsedShaper {
    return .{
        .hb_shaper = try harfbuzz.HarfBuzzShaper.initInstance(
            font.inner.data,
            font.inner.face_index,
            font.inner.units_per_em,
            font.variations,
        ),
    };
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

const DecodedCodepoint = struct {
    value: u21,
    end: usize,
};

fn decodeCodepoint(text: []const u8, start: usize) !DecodedCodepoint {
    const len = std.unicode.utf8ByteSequenceLength(text[start]) catch return error.InvalidUtf8;
    if (start + len > text.len) return error.InvalidUtf8;
    return .{
        .value = std.unicode.utf8Decode(text[start..][0..len]) catch return error.InvalidUtf8,
        .end = start + len,
    };
}

fn isRegionalIndicator(cp: u21) bool {
    return cp >= 0x1F1E6 and cp <= 0x1F1FF;
}

fn isIndicLinker(cp: u21) bool {
    return switch (cp) {
        0x094D,
        0x09CD,
        0x0A4D,
        0x0ACD,
        0x0B4D,
        0x0BCD,
        0x0C4D,
        0x0CCD,
        0x0D3B,
        0x0D3C,
        0x0D4D,
        0x0DCA,
        0x0E3A,
        0x0F84,
        0x1039,
        0x103A,
        0x1714,
        0x1734,
        0x17D2,
        0x1A60,
        0x1B44,
        0x1BAA,
        0x1BAB,
        0xA9C0,
        0xAAF6,
        0xABED,
        0x10A3F,
        0x11046,
        0x11070,
        0x11133,
        0x11134,
        0x111C0,
        0x11235,
        0x112EA,
        0x1134D,
        0x11442,
        0x114C2,
        0x115BF,
        0x1163F,
        0x116B6,
        0x1172B,
        0x11839,
        0x1193D,
        0x1193E,
        0x119E0,
        0x11A34,
        0x11A47,
        0x11A99,
        0x11C3F,
        0x11D44,
        0x11D45,
        0x11D97,
        0x11F41,
        0x11F42,
        => true,
        else => false,
    };
}

/// The fallback itemizer only needs the parts of extended-grapheme
/// segmentation that can otherwise split a font-sensitive sequence. HarfBuzz
/// remains the authority for shaping and its cluster values remain the
/// authority for returned source ranges.
fn isGraphemeExtend(cp: u21) bool {
    return (cp >= 0x0300 and cp <= 0x036F) or
        (cp >= 0x0483 and cp <= 0x0489) or
        (cp >= 0x0591 and cp <= 0x05BD) or cp == 0x05BF or
        (cp >= 0x05C1 and cp <= 0x05C2) or (cp >= 0x05C4 and cp <= 0x05C5) or cp == 0x05C7 or
        (cp >= 0x0610 and cp <= 0x061A) or (cp >= 0x064B and cp <= 0x065F) or cp == 0x0670 or
        (cp >= 0x06D6 and cp <= 0x06ED) or
        (cp >= 0x0711 and cp <= 0x0711) or (cp >= 0x0730 and cp <= 0x074A) or
        (cp >= 0x07A6 and cp <= 0x07B0) or (cp >= 0x07EB and cp <= 0x07F3) or
        (cp >= 0x0816 and cp <= 0x082D) or (cp >= 0x0859 and cp <= 0x085B) or
        (cp >= 0x08D3 and cp <= 0x0903) or
        (cp >= 0x093A and cp <= 0x094F) or (cp >= 0x0951 and cp <= 0x0957) or
        (cp >= 0x0962 and cp <= 0x0963) or
        (cp >= 0x0981 and cp <= 0x0983) or (cp >= 0x09BC and cp <= 0x09CD) or
        (cp >= 0x09D7 and cp <= 0x09D7) or (cp >= 0x09E2 and cp <= 0x09E3) or
        (cp >= 0x0A01 and cp <= 0x0A03) or (cp >= 0x0A3C and cp <= 0x0A4D) or
        (cp >= 0x0A51 and cp <= 0x0A51) or (cp >= 0x0A70 and cp <= 0x0A71) or cp == 0x0A75 or
        (cp >= 0x0A81 and cp <= 0x0A83) or (cp >= 0x0ABC and cp <= 0x0ACD) or
        (cp >= 0x0AE2 and cp <= 0x0AE3) or
        (cp >= 0x0B01 and cp <= 0x0B03) or (cp >= 0x0B3C and cp <= 0x0B4D) or
        (cp >= 0x0B55 and cp <= 0x0B57) or (cp >= 0x0B62 and cp <= 0x0B63) or
        (cp >= 0x0B82 and cp <= 0x0B82) or (cp >= 0x0BBE and cp <= 0x0BCD) or cp == 0x0BD7 or
        (cp >= 0x0C00 and cp <= 0x0C04) or (cp >= 0x0C3C and cp <= 0x0C4D) or
        (cp >= 0x0C55 and cp <= 0x0C56) or (cp >= 0x0C62 and cp <= 0x0C63) or
        (cp >= 0x0C81 and cp <= 0x0C83) or (cp >= 0x0CBC and cp <= 0x0CCD) or
        (cp >= 0x0CD5 and cp <= 0x0CD6) or (cp >= 0x0CE2 and cp <= 0x0CE3) or
        (cp >= 0x0D00 and cp <= 0x0D03) or (cp >= 0x0D3B and cp <= 0x0D4D) or
        (cp >= 0x0D57 and cp <= 0x0D57) or (cp >= 0x0D62 and cp <= 0x0D63) or
        (cp >= 0x0D81 and cp <= 0x0D83) or (cp >= 0x0DCA and cp <= 0x0DDF) or
        (cp >= 0x0DF2 and cp <= 0x0DF3) or
        (cp >= 0x1AB0 and cp <= 0x1AFF) or (cp >= 0x1DC0 and cp <= 0x1DFF) or
        (cp >= 0x20D0 and cp <= 0x20FF) or (cp >= 0xFE00 and cp <= 0xFE0F) or
        (cp >= 0xFE20 and cp <= 0xFE2F) or (cp >= 0x1F3FB and cp <= 0x1F3FF) or
        (cp >= 0xE0020 and cp <= 0xE007F) or (cp >= 0xE0100 and cp <= 0xE01EF);
}

fn graphemeClusterEnd(text: []const u8, start: usize) !usize {
    const first = try decodeCodepoint(text, start);
    if (first.value == '\r' and first.end < text.len) {
        const next = try decodeCodepoint(text, first.end);
        if (next.value == '\n') return next.end;
    }

    var end = first.end;
    var previous = first.value;
    var regional_count: u2 = if (isRegionalIndicator(first.value)) 1 else 0;
    while (end < text.len) {
        const next = try decodeCodepoint(text, end);
        const joins_previous = isGraphemeExtend(next.value) or
            next.value == 0x200D or
            previous == 0x200D or
            isIndicLinker(previous) or
            (isRegionalIndicator(next.value) and regional_count == 1);
        if (!joins_previous) break;
        end = next.end;
        previous = next.value;
        if (isRegionalIndicator(next.value)) {
            regional_count +%= 1;
        } else if (!isGraphemeExtend(next.value)) {
            regional_count = 0;
        }
    }
    return end;
}

fn coverageIgnorable(cp: u21) bool {
    return cp == 0x200D or
        (cp >= 0xFE00 and cp <= 0xFE0F) or
        (cp >= 0xE0020 and cp <= 0xE007F) or
        (cp >= 0xE0100 and cp <= 0xE01EF);
}

fn faceCoversCluster(face: *const FaceState, cluster: []const u8) bool {
    var offset: usize = 0;
    while (offset < cluster.len) {
        const decoded = decodeCodepoint(cluster, offset) catch return false;
        offset = decoded.end;
        if (coverageIgnorable(decoded.value)) continue;
        if ((face.font.glyphIndex(decoded.value) catch return false) == 0) return false;
    }
    return true;
}

fn clusterHasEmojiPresentation(cluster: []const u8) bool {
    var offset: usize = 0;
    while (offset < cluster.len) {
        const decoded = decodeCodepoint(cluster, offset) catch return false;
        if (decoded.value == 0xFE0F) return true;
        offset = decoded.end;
    }
    return false;
}

fn findCoveringFace(faces: []const FaceState, chain: []const FaceIndex, cluster: []const u8) ?FaceIndex {
    for (chain) |fi| if (faceCoversCluster(&faces[fi], cluster)) return fi;
    return null;
}

fn resolveClusterFace(
    faces: []const FaceState,
    chains: *const Chains,
    style: FontStyle,
    cluster: []const u8,
    depth: u8,
) ?FaceIndex {
    if (depth > 3) return null;
    const prefer_global = clusterHasEmojiPresentation(cluster);
    if (prefer_global) {
        if (findCoveringFace(faces, chains.global_chain, cluster)) |fi| return fi;
    }
    if (chains.style_chains.get(packStyle(style))) |chain| {
        if (findCoveringFace(faces, chain.items, cluster)) |fi| return fi;
    }
    if (!prefer_global) {
        if (findCoveringFace(faces, chains.global_chain, cluster)) |fi| return fi;
    }

    const next_depth = depth + 1;
    if (style.italic and style.weight != .regular) {
        if (resolveClusterFace(faces, chains, .{ .weight = style.weight, .italic = false }, cluster, next_depth)) |fi| return fi;
        if (resolveClusterFace(faces, chains, .{ .weight = .regular, .italic = true }, cluster, next_depth)) |fi| return fi;
        return resolveClusterFace(faces, chains, .{ .weight = .regular, .italic = false }, cluster, next_depth);
    } else if (style.italic) {
        return resolveClusterFace(faces, chains, .{ .weight = .regular, .italic = false }, cluster, next_depth);
    } else if (style.weight != .regular) {
        return resolveClusterFace(faces, chains, .{ .weight = .regular, .italic = false }, cluster, next_depth);
    }
    return null;
}

fn itemizeText(allocator: Allocator, faces_value: *const Faces, style: FontStyle, text: []const u8) ![]ItemizedRun {
    _ = std.unicode.Utf8View.init(text) catch return error.InvalidUtf8;
    var runs: std.ArrayListUnmanaged(ItemizedRun) = .empty;
    errdefer runs.deinit(allocator);

    var current_face: ?FaceIndex = null;
    var run_start: u32 = 0;

    var i: usize = 0;
    while (i < text.len) {
        const cluster_end = try graphemeClusterEnd(text, i);
        const cluster = text[i..cluster_end];
        const first = try decodeCodepoint(text, i);
        const face_idx = resolveClusterFace(faces_value.faces, &faces_value.chains, style, cluster, 0) orelse
            resolveFace(faces_value.faces, &faces_value.chains, style, first.value, 0) orelse
            unresolvedCodepointFace(faces_value) orelse {
            i = cluster_end;
            continue;
        };

        if (current_face == null) {
            current_face = face_idx;
            run_start = @intCast(i);
        } else if (current_face.? != face_idx) {
            try runs.append(allocator, .{ .face_index = current_face.?, .text_start = run_start, .text_end = @intCast(i) });
            current_face = face_idx;
            run_start = @intCast(i);
        }
        i = cluster_end;
    }
    if (current_face) |fi| {
        try runs.append(allocator, .{ .face_index = fi, .text_start = run_start, .text_end = @intCast(text.len) });
    }
    return try runs.toOwnedSlice(allocator);
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
    return shapeWithHarfbuzz(allocator, fc, face_index, font_id, faces_value.allocator, text, source_base, missing_replacement, opts);
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
) !ShapeRunResult {
    const hbs: *harfbuzz.HarfBuzzShaper = &fc.hb_shaper;

    var feature_stack: [32]harfbuzz.Feature = undefined;
    var feature_heap: ?[]harfbuzz.Feature = null;
    defer if (feature_heap) |buf| allocator.free(buf);
    const feature_buf: []harfbuzz.Feature = if (opts.features.len <= feature_stack.len)
        feature_stack[0..opts.features.len]
    else blk: {
        const buf = try allocator.alloc(harfbuzz.Feature, opts.features.len);
        feature_heap = buf;
        break :blk buf;
    };
    const hb_features = buildHbFeatures(opts.features, source_base, @intCast(text.len), feature_buf);
    const properties: harfbuzz.SegmentProperties = .{
        .direction = opts.direction,
        .script = opts.script,
        .language = opts.language,
    };

    // `opts.advance_provider` is the new path: HB's hooks get attached
    // lazily and the provider routes through caller-owned state. The
    // provider is invoked at `opts.target_ppem`.
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
        hbs.shapeTextWithProviderProperties(text, hb_features, opts.target_ppem.?, properties)
    else
        hbs.shapeTextWithProperties(text, hb_features, properties);

    const inv: f32 = if (use_provider)
        1.0 / @as(f32, @floatFromInt(opts.target_ppem.?.x_26_6))
    else
        1.0 / @as(f32, @floatFromInt(fc.font.inner.units_per_em));

    if (shaped.count == 0 or shaped.infos == null or shaped.positions == null) return emptyRun();

    const out = try allocator.alloc(ShapedText.Glyph, shaped.count);
    errdefer allocator.free(out);
    const cluster_starts = try allocator.alloc(u32, shaped.count);
    defer allocator.free(cluster_starts);

    for (0..shaped.count) |i| {
        cluster_starts[i] = @min(@as(u32, @intCast(shaped.infos[i].cluster)), @as(u32, @intCast(text.len)));
    }
    std.mem.sort(u32, cluster_starts, {}, std.sort.asc(u32));

    var cursor_x: f32 = 0;
    var cursor_y: f32 = 0;
    for (0..shaped.count) |i| {
        const info = shaped.infos[i];
        const pos = shaped.positions[i];
        const cluster = @min(@as(u32, @intCast(info.cluster)), @as(u32, @intCast(text.len)));
        const cluster_end = nextClusterStart(cluster_starts, cluster, @intCast(text.len));
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
            .source_end = source_base + cluster_end,
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

fn nextClusterStart(sorted_starts: []const u32, cluster: u32, text_len: u32) u32 {
    var lo: usize = 0;
    var hi = sorted_starts.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (sorted_starts[mid] <= cluster) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return if (lo < sorted_starts.len) sorted_starts[lo] else text_len;
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
/// `snail.TtAdvanceSource`.closure — for hinted advances.
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
    if (text.len > std.math.maxInt(u32) or text.len > std.math.maxInt(c_int)) return error.TextTooLong;
    if (opts.features.len > std.math.maxInt(c_uint)) return error.TooManyFeatures;
    for (opts.features) |feature| {
        if (feature.range) |range| if (range.end < range.start) return error.InvalidFeatureRange;
    }
    if (opts.language) |language| {
        if (language.len == 0 or language.len > std.math.maxInt(c_int)) return error.InvalidLanguage;
    }
    if (opts.advance_provider != null and opts.target_ppem == null) return error.MissingTargetPpem;
    if (opts.target_ppem) |ppem| try ppem.validate();

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

test "shape preserves HarfBuzz complex-script behavior" {
    const Case = struct {
        font_data: []const u8,
        text: []const u8,
        glyph_count: usize,
    };
    const cases = [_]Case{
        .{ .font_data = assets.noto_sans_arabic, .text = "بسم الله", .glyph_count = 9 },
        .{ .font_data = assets.noto_sans_devanagari, .text = "नमस्ते", .glyph_count = 5 },
        .{ .font_data = assets.noto_sans_thai, .text = "สวัสดี", .glyph_count = 6 },
        .{ .font_data = assets.noto_sans_mongolian, .text = "ᠮᠣᠩᠭᠣᠯ", .glyph_count = 5 },
    };

    for (cases) |case| {
        var font = try Font.init(case.font_data);
        var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
        defer faces.deinit();
        var shaped = try shape(testing.allocator, &faces, case.text, .{});
        defer shaped.deinit();
        try testing.expectEqual(case.glyph_count, shaped.glyphs.len);
        try testing.expect(shaped.advanceX() > 0);
    }
}

test "shape forwards OpenType feature overrides" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var default = try shape(testing.allocator, &faces, "office", .{});
    defer default.deinit();
    const no_liga = [_]OpenTypeFeature{.{ .tag = "liga".*, .value = 0 }};
    var expanded = try shape(testing.allocator, &faces, "office", .{ .features = &no_liga });
    defer expanded.deinit();

    try testing.expect(expanded.glyphs.len > default.glyphs.len);
}

test "shape forwards feature lists larger than the stack fast path" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var default = try shape(testing.allocator, &faces, "office", .{});
    defer default.deinit();

    var features: [33]OpenTypeFeature = undefined;
    for (&features) |*feature| feature.* = .{ .tag = "kern".*, .value = 1 };
    features[features.len - 1] = .{ .tag = "liga".*, .value = 0 };
    var expanded = try shape(testing.allocator, &faces, "office", .{ .features = &features });
    defer expanded.deinit();

    try testing.expect(expanded.glyphs.len > default.glyphs.len);
}

test "shape reports the logical source extent of each HarfBuzz cluster" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var shaped = try shape(testing.allocator, &faces, "abc", .{});
    defer shaped.deinit();
    try testing.expectEqual(@as(usize, 3), shaped.glyphs.len);
    for (shaped.glyphs, 0..) |glyph, i| {
        try testing.expectEqual(@as(u32, @intCast(i)), glyph.source_start);
        try testing.expectEqual(@as(u32, @intCast(i + 1)), glyph.source_end);
    }
}

test "shape accepts explicit HarfBuzz segment properties" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var ltr = try shape(testing.allocator, &faces, "abc", .{});
    defer ltr.deinit();
    var rtl = try shape(testing.allocator, &faces, "abc", .{
        .direction = .rtl,
        .script = "Latn".*,
        .language = "en-US",
    });
    defer rtl.deinit();

    try testing.expectEqual(ltr.glyphs.len, rtl.glyphs.len);
    try testing.expect(ltr.glyphs[0].source_start < ltr.glyphs[ltr.glyphs.len - 1].source_start);
    try testing.expect(rtl.glyphs[0].source_start > rtl.glyphs[rtl.glyphs.len - 1].source_start);
    for (rtl.glyphs) |glyph| try testing.expect(glyph.source_end > glyph.source_start);
}

test "shape rejects invalid shaping options" {
    var font = try Font.init(assets.noto_sans_regular);
    var faces = try Faces.build(testing.allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    try testing.expectError(error.InvalidPpem, shape(testing.allocator, &faces, "a", .{
        .target_ppem = text_mod.TtHintPpem.uniform(0),
    }));
    try testing.expectError(error.InvalidPpem, shape(testing.allocator, &faces, "a", .{
        .target_ppem = text_mod.TtHintPpem.uniform(text_mod.TtHintPpem.max_26_6 + 1),
    }));
    try testing.expectError(error.InvalidLanguage, shape(testing.allocator, &faces, "a", .{
        .language = "",
    }));

    const Provider = struct {
        fn covers(_: *anyopaque, _: u32) bool {
            return false;
        }
        fn advance(_: *anyopaque, _: u32, _: u16, _: text_mod.TtHintPpem) ?i32 {
            return null;
        }
    };
    var context: u8 = 0;
    try testing.expectError(error.MissingTargetPpem, shape(testing.allocator, &faces, "a", .{
        .advance_provider = .{
            .context = &context,
            .covers = Provider.covers,
            .get_advance = Provider.advance,
        },
    }));
}

test "fallback itemization keeps emoji-presentation clusters together" {
    var regular = try Font.init(assets.noto_sans_regular);
    var emoji = try Font.init(assets.twemoji_mozilla);
    var faces = try Faces.build(testing.allocator, &.{
        .{ .font = &regular },
        .{ .font = &emoji, .fallback = true },
    });
    defer faces.deinit();

    var shaped = try shape(testing.allocator, &faces, "\u{2764}\u{FE0F}", .{});
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len > 0);
    for (shaped.glyphs) |glyph| {
        try testing.expectEqual(@as(u32, 1), glyph.font_id);
        try testing.expectEqual(@as(u32, 0), glyph.source_start);
        try testing.expectEqual(@as(u32, 6), glyph.source_end);
    }
}

test "HarfBuzz shaping uses variable font coordinates" {
    const light_coords = [_]font_mod.Variation{.{ .tag = "wght".*, .value = 200 }};
    const heavy_coords = [_]font_mod.Variation{.{ .tag = "wght".*, .value = 900 }};
    var light_font = try Font.initWithOptions(assets.source_serif_cff2_variable, .{ .variations = &light_coords });
    var heavy_font = try Font.initWithOptions(assets.source_serif_cff2_variable, .{ .variations = &heavy_coords });

    var light_faces = try Faces.build(testing.allocator, &.{.{ .font = &light_font }});
    defer light_faces.deinit();
    var heavy_faces = try Faces.build(testing.allocator, &.{.{ .font = &heavy_font }});
    defer heavy_faces.deinit();

    var light_text = try shape(testing.allocator, &light_faces, "m", .{});
    defer light_text.deinit();
    var heavy_text = try shape(testing.allocator, &heavy_faces, "m", .{});
    defer heavy_text.deinit();
    try testing.expectEqual(@as(usize, 1), light_text.glyphs.len);
    try testing.expectEqual(@as(usize, 1), heavy_text.glyphs.len);
    try testing.expect(light_text.glyphs[0].x_advance != heavy_text.glyphs[0].x_advance);
}

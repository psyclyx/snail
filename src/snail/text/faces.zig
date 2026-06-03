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
//!   shape time via `ShapeOptions.advance_provider` (see Layer 5 of
//!   the rewrite plan).
//!
//! Per-face HB and OpenType shapers are still parsed once at `build`
//! time and reused across `shape()` calls — that's the "owns" part of
//! `Faces`.

const std = @import("std");
const build_options = @import("build_options");

const font_mod = @import("../font.zig");
const opentype = @import("../font/opentype.zig");
const harfbuzz = if (build_options.enable_harfbuzz) @import("../font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};

const text_mod = @import("../text.zig");

const Allocator = std.mem.Allocator;

pub const Font = font_mod.Font;
pub const FaceIndex = text_mod.FaceIndex;
pub const FontWeight = text_mod.FontWeight;
pub const FontStyle = text_mod.FontStyle;
pub const SyntheticStyle = text_mod.SyntheticStyle;
pub const MissingGlyphReplacement = text_mod.MissingGlyphReplacement;

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
        parsed.hb_shaper = harfbuzz.HarfBuzzShaper.init(font.inner.data, font.inner.units_per_em) catch null;
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

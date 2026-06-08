//! Screen-space HUD overlay for the interactive banner demo.
//!
//! Renders FPS / Backend / AA / Hint status in the top-right corner.
//! The overlay is drawn as a second pass after the world content with a
//! projection-only MVP, so it never zooms / pans / rotates with the
//! scene.
//!
//! Resource policy:
//!   - Caller owns the `PagePool` and the `*Faces` — we just hold
//!     references.
//!   - The HUD's `Atlas` is sticky: it grows as new glyphs are
//!     encountered (a digit's first appearance) and never resets.
//!     `Atlas.extend` is HAMT-backed (O(log32 N) per new entry), so
//!     each frame's extension is cheap.
//!   - `UnhintedGlyphCache` memoises curve extraction per glyph so a
//!     digit's curves are decoded once per session.
//!   - `ShapedRunCache` memoises `snail.shape` per text string so
//!     repeat-frame text re-uses the cached `ShapedText`.
//!   - Per-frame `Picture` building uses the caller-provided frame
//!     allocator. A typical caller passes an arena that resets at
//!     frame end.
//!
//! The HUD is intentionally tiny — four lines, one font face, one
//! color — so it doesn't justify a generic "overlay framework". If a
//! future demo needs richer screen-space text, this file is the
//! template.

const std = @import("std");
const snail = @import("snail");
const helpers = @import("snail-helpers");

const Allocator = std.mem.Allocator;

const ShapedRunCache = helpers.ShapedRunCache;
const UnhintedGlyphCache = helpers.UnhintedGlyphCache;

/// Live state the HUD reads each frame. Strings the caller already
/// has (backend name, AA label, hint label) come through by slice;
/// the HUD borrows them for the call's duration and copies whatever
/// it needs to cache.
pub const State = struct {
    fps: f32,
    backend: []const u8,
    aa: []const u8,
    hint: []const u8,
};

/// Long-lived HUD-side resources. The `BackendCache` (per-backend GPU
/// upload state) is owned by the renderer driver, not here — keeps the
/// HUD backend-agnostic.
pub const Overlay = struct {
    allocator: Allocator,
    faces: *snail.Faces,
    pool: *snail.PagePool,
    /// Font id used for HUD glyphs. The caller picks which face to use
    /// from the shared `Faces`; we resolve and cache its font id once.
    face_index: snail.FaceIndex,
    font_id: u32,
    font: *const snail.Font,

    shape_cache: ShapedRunCache,
    glyph_cache: UnhintedGlyphCache,
    atlas: snail.Atlas,
    /// Buffer reused for FPS string formatting (avoids alloc).
    fps_buf: [16]u8,

    pub fn init(
        allocator: Allocator,
        faces: *snail.Faces,
        pool: *snail.PagePool,
        face_index: snail.FaceIndex,
    ) !Overlay {
        const face = faces.face(face_index);
        const font_id = faces.fontIdForFace(face_index);
        return .{
            .allocator = allocator,
            .faces = faces,
            .pool = pool,
            .face_index = face_index,
            .font_id = font_id,
            .font = face.font,
            .shape_cache = ShapedRunCache.init(allocator),
            .glyph_cache = UnhintedGlyphCache.init(allocator, face.font),
            .atlas = snail.Atlas.empty(allocator),
            .fps_buf = undefined,
        };
    }

    pub fn deinit(self: *Overlay) void {
        self.atlas.deinit();
        self.glyph_cache.deinit();
        self.shape_cache.deinit();
        self.* = undefined;
    }

    /// Build the HUD picture for one frame.
    ///
    /// On return:
    ///   - `self.atlas` has been extended with any glyphs the picture
    ///     needs. Caller passes `self.atlas` to its `BackendCache` and
    ///     emits against the returned `Picture`.
    ///   - The returned `Picture` is owned by `frame_alloc`. Caller
    ///     calls `picture.deinit()` when done with the frame.
    ///   - Resources used during the call: `frame_alloc` (for the
    ///     picture's shape array and any shape-cache miss work) and
    ///     `scratch_alloc` (for curve extraction temporaries — freed
    ///     before returning).
    pub fn buildPicture(
        self: *Overlay,
        frame_alloc: Allocator,
        scratch_alloc: Allocator,
        state: State,
        viewport_w: f32,
        viewport_h: f32,
    ) !snail.Picture {
        const fps_text = std.fmt.bufPrint(&self.fps_buf, "FPS: {d:.0}", .{state.fps}) catch "FPS: ?";

        const lines = [_]Line{
            .{ .text = fps_text, .y = 0 },
            .{ .text = state.backend, .y = 1 },
            .{ .text = state.aa, .y = 2 },
            .{ .text = state.hint, .y = 3 },
        };

        // Anchor the block to the top-right. line_h is body-of-text
        // spacing; em is the per-glyph scale (logical pixels).
        const em: f32 = 20.0;
        const line_h: f32 = em * 1.3;
        const padding: f32 = 20.0;
        const right_edge: f32 = viewport_w - padding;
        const top_edge: f32 = padding + em; // baseline of first line

        _ = viewport_h;

        // Build one Picture per non-empty line, then concat. Each
        // shapedRunPicture call allocates a small Shape buffer in
        // `frame_alloc`; the concat allocates one final buffer; the
        // per-line pictures get freed before return.
        var line_pictures: [lines.len]snail.Picture = undefined;
        var line_count: usize = 0;
        defer for (line_pictures[0..line_count]) |*p| p.deinit();

        for (lines) |line| {
            if (line.text.len == 0) continue;
            const shaped = try self.shape_cache.shape(
                self.faces,
                line.text,
                .{ .style = .{ .weight = .regular } },
            );
            try self.ensureAtlasContains(scratch_alloc, shaped);

            const run_width = em * shaped.advanceX();
            const baseline_x = right_edge - run_width;
            const baseline_y = top_edge + @as(f32, @floatFromInt(line.y)) * line_h;

            line_pictures[line_count] = try snail.shapedRunPicture(frame_alloc, shaped, self.faces, .{
                .baseline = .{ .x = baseline_x, .y = baseline_y },
                .em = em,
                .color = hud_color,
            });
            line_count += 1;
        }

        // One concat over all non-empty lines.
        var refs: [lines.len]*const snail.Picture = undefined;
        for (line_pictures[0..line_count], 0..) |*p, i| refs[i] = p;
        return snail.Picture.concat(frame_alloc, refs[0..line_count]);
    }

    /// Walk `shaped`'s glyphs and add any missing keys to `self.atlas`.
    /// On exit, every `(font_id, glyph_id)` referenced by `shaped`
    /// resolves through `self.atlas.lookupRecord`.
    fn ensureAtlasContains(self: *Overlay, scratch_alloc: Allocator, shaped: *const snail.ShapedText) !void {
        // HUD strings are short — a single call rarely introduces more
        // than a handful of new glyphs; 64 is more than enough.
        const max_new = 64;
        var entries_buf: [max_new]snail.AtlasEntry = undefined;
        var curves_buf: [max_new]snail.GlyphCurves = undefined;
        var n: usize = 0;

        for (shaped.glyphs) |g| {
            // Only the HUD's chosen face is supported. If shape() picked
            // a fallback (shouldn't happen for ASCII), skip — the emit
            // will then surface MissingRecord rather than us silently
            // dropping the glyph.
            if (g.font_id != self.font_id) continue;
            const key = snail.recordKey.unhintedGlyph(g.font_id, g.glyph_id);
            if (self.atlas.contains(key)) continue;
            // Avoid duplicating within this same call.
            if (containsKey(entries_buf[0..n], key)) continue;
            if (n >= max_new) break;

            const curves_cached = try self.glyph_cache.getOrInsert(self.allocator, scratch_alloc, g.glyph_id);
            curves_buf[n] = curves_cached.*;
            entries_buf[n] = .{ .key = key, .curves = curves_buf[n] };
            n += 1;
        }

        if (n == 0) return;

        // Atlas.extend wants a non-null pool — empty atlases have no
        // pool. Construct from() on first growth, then extend()
        // afterwards.
        if (self.atlas.pool == null) {
            const fresh = try snail.Atlas.from(self.allocator, self.pool, entries_buf[0..n]);
            self.atlas.deinit();
            self.atlas = fresh;
            return;
        }

        const grown = try self.atlas.extend(self.allocator, entries_buf[0..n]);
        self.atlas.deinit();
        self.atlas = grown;
    }
};

const Line = struct {
    text: []const u8,
    y: u8,
};

/// Off-white at ~85% opacity. Sits cleanly on the banner's cream
/// background and the game demo's darker scenes alike.
const hud_color = [4]f32{ 0.06, 0.07, 0.09, 0.85 };

fn containsKey(entries: []const snail.AtlasEntry, key: snail.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}


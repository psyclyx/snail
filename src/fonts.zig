//! Immutable text-atlas snapshots with structural sharing.
//!
//! `snail.TextAtlas` is the public API name for this type. It manages multiple
//! font faces with style-specific and global fallback chains, a shared glyph
//! atlas, and automatic text itemization. Extending the atlas returns a new
//! immutable snapshot; the old snapshot remains valid for in-flight readers and
//! for other renderers that still reference it.

const std = @import("std");
const snail = @import("snail.zig");
const ttf = @import("font/ttf.zig");
const opentype = @import("font/opentype.zig");
const glyph_emit = @import("glyph_emit.zig");
const build_options = @import("build_options");
const harfbuzz = if (build_options.enable_harfbuzz) @import("font/harfbuzz.zig") else struct {
    pub const HarfBuzzShaper = void;
};

const Allocator = std.mem.Allocator;
const AtlasPage = snail.lowlevel.AtlasPage;
const GlyphInfo = snail.lowlevel.CurveAtlas.GlyphInfo;
const ColrBaseInfo = snail.lowlevel.CurveAtlas.ColrBaseInfo;
const TextBatch = snail.lowlevel.TextBatch;
const bezier = @import("math/bezier.zig");
const band_tex = @import("render/band_texture.zig");

// ── Public types ──

pub const FaceIndex = u16;

pub const FaceSpec = struct {
    data: []const u8,
    weight: snail.FontWeight = .regular,
    italic: bool = false,
    fallback: bool = false,
    synthetic: snail.SyntheticStyle = .{},
};

pub const AddTextResult = struct {
    advance: f32,
    missing: bool,
};

pub const ItemizedRun = struct {
    face_index: FaceIndex,
    text_start: u32,
    text_end: u32,
};

pub const ScriptTransform = struct {
    x: f32,
    y: f32,
    font_size: f32,
};

fn preparedViewLayerBase(view: anytype) u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "layer_base")) view.layer_base else 0,
        else => 0,
    };
}

fn preparedViewInfoRowBase(view: anytype) u32 {
    const T = @TypeOf(view);
    return switch (@typeInfo(T)) {
        .@"struct" => if (@hasField(T, "info_row_base")) view.info_row_base else 0,
        else => 0,
    };
}

pub const ShapedText = struct {
    allocator: Allocator,
    atlas_identity: u64,
    config: *const FontConfig,
    glyphs: []Glyph,
    advance_x: f32,
    advance_y: f32,

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

    pub fn deinit(self: *ShapedText) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub const TextBlobOptions = struct {
    x: f32,
    y: f32,
    size: f32,
    color: [4]f32,
};

pub const TextBlob = struct {
    allocator: Allocator,
    /// Borrowed exact TextAtlas snapshot used to build this blob. The pointer
    /// and snapshot identity must remain valid until the blob is destroyed.
    atlas: *const TextAtlas,
    atlas_identity: u64,
    glyphs: []Glyph,
    instance_count_hint: usize,

    pub const Glyph = struct {
        face_index: FaceIndex,
        glyph_id: u16,
        transform: snail.Transform2D,
        embolden: f32,
        color: [4]f32,
    };

    pub fn deinit(self: *TextBlob) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }

    pub fn glyphCount(self: *const TextBlob) usize {
        return self.glyphs.len;
    }

    pub fn validate(self: *const TextBlob) !void {
        if (self.atlas.snapshotIdentity() != self.atlas_identity) return error.WrongTextAtlasSnapshot;
    }

    pub fn fromShaped(
        allocator: Allocator,
        atlas: *const TextAtlas,
        shaped: *const ShapedText,
        options: TextBlobOptions,
    ) !TextBlob {
        var builder = TextBlobBuilder.init(allocator, atlas);
        errdefer builder.deinit();
        _ = try atlas.appendShapedTextBlob(&builder, shaped, options, false);
        return builder.finish();
    }

    pub const AppendResult = struct {
        emitted: usize,
        next_glyph: usize,
        completed: bool,
        layer_window_base: u32,
    };

    pub fn appendToBatch(
        self: *const TextBlob,
        batch: *TextBatch,
        view: anytype,
        transform: snail.Transform2D,
        resolve: snail.TextResolveOptions,
        target: snail.ResolveTarget,
        scene_to_screen: ?snail.Transform2D,
    ) !usize {
        const result = try self.appendToBatchFrom(batch, view, transform, resolve, target, scene_to_screen, 0);
        if (!result.completed) return error.DrawListFull;
        return result.emitted;
    }

    pub fn appendToBatchFrom(
        self: *const TextBlob,
        batch: *TextBatch,
        view: anytype,
        transform: snail.Transform2D,
        resolve: snail.TextResolveOptions,
        target: snail.ResolveTarget,
        scene_to_screen: ?snail.Transform2D,
        start_glyph: usize,
    ) !AppendResult {
        try self.validate();
        var count: usize = 0;
        const has_outer_transform = !isIdentityTransform(transform);
        var glyph_index = start_glyph;
        while (glyph_index < self.glyphs.len) : (glyph_index += 1) {
            const glyph = self.glyphs[glyph_index];
            const face_view = self.atlas.faceView(glyph.face_index, view);
            const glyph_layer_base = try textBlobGlyphLayerWindowBase(&face_view, glyph.glyph_id) orelse continue;
            if (batch.layer_window_base) |base| {
                if (base != glyph_layer_base) break;
            } else {
                batch.layer_window_base = glyph_layer_base;
            }

            var final_transform = glyph.transform;
            if (has_outer_transform) {
                final_transform = snail.Transform2D.multiply(transform, final_transform);
            }
            const hinted = resolveTextHinting(&face_view, glyph.glyph_id, final_transform, resolve, target, scene_to_screen);

            switch (glyph_emit.emitGlyphWithTransform(batch, &face_view, glyph.glyph_id, glyph.color, hinted.transform)) {
                .emitted => count += 1,
                .skipped => {},
                .buffer_full => return error.DrawListFull,
                .layer_window_changed => break,
                .invalid_transform => return error.InvalidTransform,
            }

            if (glyph.embolden != 0) {
                var bold_transform = glyph.transform;
                bold_transform.tx += glyph.embolden;
                if (has_outer_transform) {
                    bold_transform = snail.Transform2D.multiply(transform, bold_transform);
                }
                const bold_hinted = resolveTextHinting(&face_view, glyph.glyph_id, bold_transform, resolve, target, scene_to_screen);
                switch (glyph_emit.emitGlyphWithTransform(batch, &face_view, glyph.glyph_id, glyph.color, bold_hinted.transform)) {
                    .emitted, .skipped => {},
                    .buffer_full => return error.DrawListFull,
                    .layer_window_changed => return error.GlyphSpansTextureLayerWindows,
                    .invalid_transform => return error.InvalidTransform,
                }
            }
        }
        return .{
            .emitted = count,
            .next_glyph = glyph_index,
            .completed = glyph_index >= self.glyphs.len,
            .layer_window_base = batch.currentLayerWindowBase(),
        };
    }
};

fn textBlobGlyphLayerWindowBase(view: *const FaceView, glyph_id: u16) !?u32 {
    if (view.getColrBase(glyph_id)) |cbi| {
        return view.glyphLayerWindowBase(cbi.page_index);
    }

    var layer_it = view.colrLayers(glyph_id);
    var base: ?u32 = null;
    if (layer_it.count() > 0) {
        while (layer_it.next()) |layer| {
            const linfo = view.getGlyph(layer.glyph_id) orelse continue;
            if (linfo.band_entry.h_band_count == 0 or linfo.band_entry.v_band_count == 0) continue;
            const layer_base = view.glyphLayerWindowBase(linfo.page_index);
            if (base) |existing| {
                if (existing != layer_base) return error.GlyphSpansTextureLayerWindows;
            } else {
                base = layer_base;
            }
        }
        return base;
    }

    const info = view.getGlyph(glyph_id) orelse return null;
    if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return null;
    return view.glyphLayerWindowBase(info.page_index);
}

pub const TextBlobBuilder = struct {
    allocator: Allocator,
    atlas: *const TextAtlas,
    glyphs: std.ArrayListUnmanaged(TextBlob.Glyph) = .empty,
    instance_count_hint: usize = 0,

    pub fn init(allocator: Allocator, atlas: *const TextAtlas) TextBlobBuilder {
        return .{
            .allocator = allocator,
            .atlas = atlas,
        };
    }

    pub fn deinit(self: *TextBlobBuilder) void {
        self.glyphs.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *TextBlobBuilder) void {
        self.glyphs.clearRetainingCapacity();
        self.instance_count_hint = 0;
    }

    pub fn glyphCount(self: *const TextBlobBuilder) usize {
        return self.glyphs.items.len;
    }

    pub fn finish(self: *TextBlobBuilder) !TextBlob {
        const owned = try self.glyphs.toOwnedSlice(self.allocator);
        const instance_count_hint = self.instance_count_hint;
        self.glyphs = .empty;
        self.instance_count_hint = 0;
        return .{
            .allocator = self.allocator,
            .atlas = self.atlas,
            .atlas_identity = self.atlas.snapshotIdentity(),
            .glyphs = owned,
            .instance_count_hint = instance_count_hint,
        };
    }

    pub fn addText(
        self: *TextBlobBuilder,
        style: snail.FontStyle,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) !AddTextResult {
        var shaped = try self.atlas.shapeText(self.allocator, style, text);
        defer shaped.deinit();
        return self.atlas.appendShapedTextBlob(self, &shaped, .{
            .x = x,
            .y = y,
            .size = font_size,
            .color = color,
        }, true);
    }
};

pub const Decoration = enum {
    underline,
    strikethrough,
};

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
    weight: snail.FontWeight,
    italic: bool,
    synthetic: snail.SyntheticStyle,
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
    glyph_lut_len: u32 = 0,
    colr_base_map: ?std.AutoHashMap(u16, ColrBaseInfo) = null,

    fn deinit(self: *FaceGlyphData, allocator: Allocator) void {
        self.glyph_map.deinit();
        if (self.glyph_lut) |lut| allocator.free(lut);
        if (self.colr_base_map) |*cbm| cbm.deinit();
    }

    fn clone(self: *const FaceGlyphData, allocator: Allocator) !FaceGlyphData {
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
            if (gid < self.glyph_lut_len) {
                const info = lut[gid];
                if (info.band_entry.h_band_count > 0) return info;
            }
            return null;
        }
        return self.glyph_map.get(gid);
    }

    fn buildGlyphLut(self: *FaceGlyphData, allocator: Allocator) !void {
        if (self.glyph_lut) |lut| allocator.free(lut);
        self.glyph_lut = null;

        if (self.glyph_map.count() == 0) return;

        var max_gid: u32 = 0;
        var it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.* > max_gid) max_gid = entry.key_ptr.*;
        }

        const size = max_gid + 1;
        const lut = try allocator.alloc(GlyphInfo, size);
        @memset(lut, std.mem.zeroes(GlyphInfo));

        it = self.glyph_map.iterator();
        while (it.next()) |entry| {
            lut[entry.key_ptr.*] = entry.value_ptr.*;
        }

        self.glyph_lut = lut;
        self.glyph_lut_len = @intCast(size);
    }
};

/// View into one face's glyph data within a TextAtlas snapshot.
/// Implements the interface expected by glyph_emit.emitGlyph.
pub const FaceView = struct {
    face_glyphs: *const FaceGlyphData,
    face_config: *const FaceConfig,
    layer_base: u32,
    info_row_base: u32,

    pub fn getGlyph(self: *const FaceView, gid: u16) ?GlyphInfo {
        return self.face_glyphs.getGlyph(gid);
    }

    pub fn getColrBase(self: *const FaceView, gid: u16) ?ColrBaseInfo {
        if (self.face_glyphs.colr_base_map) |cbm| return cbm.get(gid);
        return null;
    }

    pub fn colrLayers(self: *const FaceView, gid: u16) ttf.Font.ColrLayerIterator {
        if (self.face_config.font.colr_offset == 0) return .{ .data = self.face_config.font_data };
        const temp = ttf.Font{ .data = self.face_config.font_data, .colr_offset = self.face_config.font.colr_offset, .cpal_offset = self.face_config.font.cpal_offset };
        return temp.colrLayers(gid);
    }

    pub fn glyphLayer(self: *const FaceView, page_index: u16) u32 {
        const layer = self.layer_base + page_index;
        return layer;
    }

    pub fn glyphLayerWindowBase(self: *const FaceView, page_index: u16) u32 {
        return snail.lowlevel.textureLayerWindowBase(self.glyphLayer(page_index));
    }

    pub fn layerInfoLoc(self: *const FaceView, info_x: u16, info_y: u16) struct { x: u16, y: u16 } {
        return .{
            .x = info_x,
            .y = @intCast(self.info_row_base + info_y),
        };
    }
};

// ── TextAtlas ──

/// Multi-font text rendering with immutable snapshot semantics.
///
/// Create with `init`, populate glyphs with `ensureText`, render with `addText`.
/// All rendering methods are read-only and safe for concurrent use.
/// `ensureText` returns a new snapshot; the old one remains valid.
pub const TextAtlas = struct {
    allocator: Allocator,
    config: *FontConfig,
    pages: []*AtlasPage,
    face_glyphs: []FaceGlyphData,

    // Merged COLR layer info across all faces.
    layer_info_data: ?[]f32 = null,
    layer_info_width: u32 = 0,
    layer_info_height: u32 = 0,

    // GPU handle state (set after upload).
    layer_base: u16 = 0,
    info_row_base: u16 = 0,

    pub fn init(allocator: Allocator, specs: []const FaceSpec) !TextAtlas {
        const config = try buildFontConfig(allocator, specs);
        errdefer config.release();

        const face_glyphs = try allocator.alloc(FaceGlyphData, config.faces.len);
        for (face_glyphs) |*fg| {
            fg.* = .{ .glyph_map = std.AutoHashMap(u16, GlyphInfo).init(allocator) };
        }

        const pages = try allocator.alloc(*AtlasPage, 0);

        return .{
            .allocator = allocator,
            .config = config,
            .pages = pages,
            .face_glyphs = face_glyphs,
        };
    }

    pub fn snapshotIdentity(self: *const TextAtlas) u64 {
        var h: u64 = 0x9e3779b97f4a7c15;
        h ^= @as(u64, @intCast(@intFromPtr(self.config))) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(@intFromPtr(self.pages.ptr))) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(self.pages.len)) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(@intFromPtr(self.face_glyphs.ptr))) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        h ^= @as(u64, @intCast(self.face_glyphs.len)) +% 0x9e3779b97f4a7c15 +% (h << 6) +% (h >> 2);
        return h;
    }

    pub fn deinit(self: *TextAtlas) void {
        for (self.face_glyphs) |*fg| fg.deinit(self.allocator);
        self.allocator.free(self.face_glyphs);

        for (self.pages) |p| p.release();
        self.allocator.free(self.pages);

        if (self.layer_info_data) |lid| self.allocator.free(lid);

        self.config.release();
    }

    // ── Resolution ──

    pub fn resolve(self: *const TextAtlas, style: snail.FontStyle, codepoint: u21) ?FaceIndex {
        return resolveInner(self.config, style, codepoint, 0);
    }

    // ── Metrics ──

    pub fn lineMetrics(self: *const TextAtlas) !snail.LineMetrics {
        const pf = self.config.primary_face orelse return error.NoFaces;
        return self.config.faces[pf].font.lineMetrics();
    }

    pub fn unitsPerEm(self: *const TextAtlas) !u16 {
        const pf = self.config.primary_face orelse return error.NoFaces;
        return self.config.faces[pf].font.units_per_em;
    }

    pub fn decorationRect(self: *const TextAtlas, decoration: Decoration, x: f32, y: f32, advance: f32, font_size: f32) !snail.Rect {
        const pf = self.config.primary_face orelse return error.NoFaces;
        const fc = &self.config.faces[pf];
        const dm = try fc.font.decorationMetrics();
        const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
        return switch (decoration) {
            .underline => .{
                .x = x,
                .y = y - @as(f32, @floatFromInt(dm.underline_position)) * scale,
                .w = advance,
                .h = @max(1.0, @as(f32, @floatFromInt(dm.underline_thickness)) * scale),
            },
            .strikethrough => .{
                .x = x,
                .y = y - @as(f32, @floatFromInt(dm.strikethrough_position)) * scale,
                .w = advance,
                .h = @max(1.0, @as(f32, @floatFromInt(dm.strikethrough_thickness)) * scale),
            },
        };
    }

    pub fn superscriptTransform(self: *const TextAtlas, x: f32, y: f32, font_size: f32) !ScriptTransform {
        const pf = self.config.primary_face orelse return error.NoFaces;
        const fc = &self.config.faces[pf];
        const sm = try fc.font.superscriptMetrics();
        const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
        return .{
            .x = x + @as(f32, @floatFromInt(sm.x_offset)) * scale,
            .y = y - @as(f32, @floatFromInt(sm.y_offset)) * scale,
            .font_size = @as(f32, @floatFromInt(sm.y_size)) * scale,
        };
    }

    pub fn subscriptTransform(self: *const TextAtlas, x: f32, y: f32, font_size: f32) !ScriptTransform {
        const pf = self.config.primary_face orelse return error.NoFaces;
        const fc = &self.config.faces[pf];
        const sm = try fc.font.subscriptMetrics();
        const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
        return .{
            .x = x + @as(f32, @floatFromInt(sm.x_offset)) * scale,
            .y = y + @as(f32, @floatFromInt(sm.y_offset)) * scale,
            .font_size = @as(f32, @floatFromInt(sm.y_size)) * scale,
        };
    }

    // ── Itemization ──

    /// Split text into runs where each run maps to one face.
    pub fn itemize(self: *const TextAtlas, style: snail.FontStyle, text: []const u8) ![]ItemizedRun {
        return itemizeText(self.allocator, self.config, style, text);
    }

    pub fn faceView(self: *const TextAtlas, face_index: FaceIndex, atlas_view: anytype) FaceView {
        return .{
            .face_glyphs = &self.face_glyphs[face_index],
            .face_config = &self.config.faces[face_index],
            .layer_base = preparedViewLayerBase(atlas_view),
            .info_row_base = preparedViewInfoRowBase(atlas_view),
        };
    }

    // ── Rendering ──

    pub fn shapeText(
        self: *const TextAtlas,
        allocator: Allocator,
        style: snail.FontStyle,
        text: []const u8,
    ) !ShapedText {
        const runs = try itemizeText(allocator, self.config, style, text);
        defer allocator.free(runs);

        var glyphs = std.ArrayListUnmanaged(ShapedText.Glyph).empty;
        errdefer glyphs.deinit(allocator);

        var cursor_x: f32 = 0;
        var cursor_y: f32 = 0;
        for (runs) |run| {
            const fc = &self.config.faces[run.face_index];
            const segment = text[run.text_start..run.text_end];
            const shaped_run = try shapeRunForFace(allocator, fc, run.face_index, segment, run.text_start);
            defer if (shaped_run.glyphs.len > 0) allocator.free(shaped_run.glyphs);

            for (shaped_run.glyphs) |glyph| {
                try glyphs.append(allocator, .{
                    .face_index = glyph.face_index,
                    .glyph_id = glyph.glyph_id,
                    .x_offset = cursor_x + glyph.x_offset,
                    .y_offset = cursor_y + glyph.y_offset,
                    .x_advance = glyph.x_advance,
                    .y_advance = glyph.y_advance,
                    .source_start = glyph.source_start,
                    .source_end = glyph.source_end,
                });
            }
            cursor_x += shaped_run.advance_x;
            cursor_y += shaped_run.advance_y;
        }

        return .{
            .allocator = allocator,
            .atlas_identity = self.snapshotIdentity(),
            .config = self.config,
            .glyphs = try glyphs.toOwnedSlice(allocator),
            .advance_x = cursor_x,
            .advance_y = cursor_y,
        };
    }

    pub fn appendShapedTextBlob(
        self: *const TextAtlas,
        builder: *TextBlobBuilder,
        shaped: *const ShapedText,
        options: TextBlobOptions,
        allow_missing: bool,
    ) !AddTextResult {
        std.debug.assert(builder.atlas == self);
        if (shaped.config != self.config) return error.WrongTextAtlasSnapshot;

        var missing = false;
        for (shaped.glyphs) |glyph| {
            const fc = &self.config.faces[glyph.face_index];
            const face_view = self.faceView(glyph.face_index, .{});
            if (!shapedGlyphAvailable(&face_view, glyph.glyph_id)) {
                missing = true;
                if (!allow_missing) return error.MissingPreparedGlyph;
            }
            const x = options.x + glyph.x_offset * options.size;
            const y = options.y + glyph.y_offset * options.size;
            try appendBlobGlyph(
                builder,
                glyph.face_index,
                &face_view,
                glyph.glyph_id,
                x,
                y,
                options.size,
                options.color,
                fc.synthetic,
            );
        }

        return .{
            .advance = shaped.advance_x * options.size,
            .missing = missing,
        };
    }

    pub fn appendTextBlob(
        self: *const TextAtlas,
        builder: *TextBlobBuilder,
        style: snail.FontStyle,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) !AddTextResult {
        var shaped = try self.shapeText(self.allocator, style, text);
        defer shaped.deinit();
        return self.appendShapedTextBlob(builder, &shaped, .{
            .x = x,
            .y = y,
            .size = font_size,
            .color = color,
        }, true);
    }

    /// Itemize, shape, and emit text into a low-level TextBatch. Returns advance
    /// width and whether any glyphs were missing from the atlas.
    pub fn addText(
        self: *const TextAtlas,
        batch: *TextBatch,
        style: snail.FontStyle,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        color: [4]f32,
    ) !AddTextResult {
        const runs = try itemizeText(self.allocator, self.config, style, text);
        defer self.allocator.free(runs);

        var cx = x;
        var missing = false;
        for (runs) |run| {
            const fc = &self.config.faces[run.face_index];
            const fg = &self.face_glyphs[run.face_index];
            const segment = text[run.text_start..run.text_end];

            if (hasMissingGlyphs(fc, fg, segment))
                missing = true;

            const face_view = FaceView{
                .face_glyphs = fg,
                .face_config = fc,
                .layer_base = self.layer_base,
                .info_row_base = self.info_row_base,
            };

            const has_synthetic = fc.synthetic.skew_x != 0 or fc.synthetic.embolden != 0;

            if (!has_synthetic) {
                cx += addTextForFace(batch, &face_view, fc, fg, segment, cx, y, font_size, color);
            } else {
                cx += addTextForFaceSynthetic(self.allocator, batch, &face_view, fc, fg, segment, cx, y, font_size, color);
            }
        }

        return .{ .advance = cx - x, .missing = missing };
    }

    /// Measure advance width without emitting vertices.
    pub fn measureText(
        self: *const TextAtlas,
        style: snail.FontStyle,
        text: []const u8,
        font_size: f32,
    ) !f32 {
        const runs = try itemizeText(self.allocator, self.config, style, text);
        defer self.allocator.free(runs);

        var width: f32 = 0;
        for (runs) |run| {
            const fc = &self.config.faces[run.face_index];
            const fg = &self.face_glyphs[run.face_index];
            const segment = text[run.text_start..run.text_end];

            if (comptime build_options.enable_harfbuzz) {
                if (fc.hb_shaper) |hbs| {
                    width += hbs.measureWidth(segment, font_size);
                    continue;
                }
            }

            const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
            const utf8_view = std.unicode.Utf8View.initUnchecked(segment);
            var it = utf8_view.iterator();
            while (it.nextCodepoint()) |cp| {
                const gid = fc.font.glyphIndex(cp) catch 0;
                if (gid == 0) {
                    width += scale * 500;
                    continue;
                }
                if (fg.getGlyph(gid)) |info| {
                    width += @as(f32, @floatFromInt(info.advance_width)) * scale;
                } else {
                    width += @as(f32, @floatFromInt(fc.font.advanceWidth(gid) catch 500)) * scale;
                }
            }
        }
        return width;
    }

    // ── Atlas extension ──

    /// Return a new TextAtlas snapshot with atlas extended for the given text.
    /// Returns null if all glyphs are already present. The old snapshot stays valid.
    pub fn ensureText(self: *const TextAtlas, style: snail.FontStyle, text: []const u8) !?TextAtlas {
        var shaped = try self.shapeText(self.allocator, style, text);
        defer shaped.deinit();
        return self.ensureShaped(&shaped);
    }

    /// Return a new TextAtlas snapshot with all glyphs referenced by `shaped`
    /// available. Returns null if the current snapshot already contains them.
    pub fn ensureShaped(self: *const TextAtlas, shaped: *const ShapedText) !?TextAtlas {
        if (shaped.config != self.config) return error.WrongTextAtlasSnapshot;

        // Discover missing glyphs per face.
        var any_missing = false;
        const face_new_gids = try self.allocator.alloc(?std.AutoHashMap(u16, void), self.config.faces.len);
        defer self.allocator.free(face_new_gids);
        @memset(face_new_gids, null);
        defer for (face_new_gids) |*m| {
            if (m.*) |*map| map.deinit();
        };

        for (shaped.glyphs) |glyph| {
            if (glyph.glyph_id == 0) continue;
            const fg = &self.face_glyphs[glyph.face_index];
            if (fg.getGlyph(glyph.glyph_id) != null) continue;
            const has_colr = if (fg.colr_base_map) |cbm| cbm.contains(glyph.glyph_id) else false;
            if (has_colr) continue;
            if (face_new_gids[glyph.face_index] == null)
                face_new_gids[glyph.face_index] = std.AutoHashMap(u16, void).init(self.allocator);
            try face_new_gids[glyph.face_index].?.put(glyph.glyph_id, {});
            any_missing = true;
        }

        if (!any_missing) return null;

        // Build new pages for each face with missing glyphs.
        var new_pages_list = std.ArrayListUnmanaged(*AtlasPage).empty;
        defer new_pages_list.deinit(self.allocator);

        const new_face_glyphs = try self.allocator.alloc(FaceGlyphData, self.config.faces.len);
        const new_face_glyphs_initialized = try self.allocator.alloc(bool, self.config.faces.len);
        defer self.allocator.free(new_face_glyphs_initialized);
        @memset(new_face_glyphs_initialized, false);
        errdefer {
            for (new_face_glyphs, new_face_glyphs_initialized) |*fg, initialized| {
                if (initialized) fg.deinit(self.allocator);
            }
            self.allocator.free(new_face_glyphs);
        }

        for (self.config.faces, 0..) |*fc, fi| {
            if (face_new_gids[fi]) |*new_gids| {
                // Expand COLR layers.
                try snail.lowlevel.CurveAtlas.expandColrLayersInner(&fc.font, self.allocator, new_gids);

                // Filter out glyph IDs already in the atlas.
                var filtered = std.AutoHashMap(u16, void).init(self.allocator);
                defer filtered.deinit();
                var git = new_gids.keyIterator();
                while (git.next()) |gid_ptr| {
                    if (!self.face_glyphs[fi].glyph_map.contains(gid_ptr.*))
                        try filtered.put(gid_ptr.*, {});
                }

                if (filtered.count() == 0) {
                    new_face_glyphs[fi] = try self.face_glyphs[fi].clone(self.allocator);
                    new_face_glyphs_initialized[fi] = true;
                    continue;
                }

                // Build page for the new glyphs.
                const page_index: u16 = @intCast(self.pages.len + new_pages_list.items.len);
                const page_result = try snail.lowlevel.CurveAtlas.buildPageDataInner(self.allocator, &fc.font, &filtered, page_index);
                try new_pages_list.append(self.allocator, page_result.page);

                // Merge glyph maps.
                var merged = std.AutoHashMap(u16, GlyphInfo).init(self.allocator);
                var eit = self.face_glyphs[fi].glyph_map.iterator();
                while (eit.next()) |entry| try merged.put(entry.key_ptr.*, entry.value_ptr.*);
                var nit = page_result.glyph_map.iterator();
                while (nit.next()) |entry| try merged.put(entry.key_ptr.*, entry.value_ptr.*);
                var pm = page_result.glyph_map;
                pm.deinit();

                new_face_glyphs[fi] = .{ .glyph_map = merged };
                new_face_glyphs_initialized[fi] = true;
                try new_face_glyphs[fi].buildGlyphLut(self.allocator);
            } else {
                new_face_glyphs[fi] = try self.face_glyphs[fi].clone(self.allocator);
                new_face_glyphs_initialized[fi] = true;
            }
        }

        // Assemble new pages array: retain old + own new.
        const total_pages = self.pages.len + new_pages_list.items.len;
        const new_pages = try self.allocator.alloc(*AtlasPage, total_pages);
        for (self.pages, 0..) |p, i| new_pages[i] = p.retain();
        for (new_pages_list.items, 0..) |p, i| new_pages[self.pages.len + i] = p;

        return .{
            .allocator = self.allocator,
            .config = self.config.retain(),
            .pages = new_pages,
            .face_glyphs = new_face_glyphs,
        };
    }

    // ── GPU upload helpers ──

    pub fn pageCount(self: *const TextAtlas) usize {
        return self.pages.len;
    }

    pub fn page(self: *const TextAtlas, index: usize) *const AtlasPage {
        return self.pages[index];
    }

    pub fn pageSlice(self: *const TextAtlas) []*AtlasPage {
        return self.pages;
    }

    /// Create a temporary Atlas wrapper for GPU upload. The wrapper borrows
    /// pages from this TextAtlas snapshot — do NOT deinit it (use deinitUploadAtlas).
    /// Upload alongside PathPicture atlases via Renderer.uploadAtlases.
    pub fn uploadAtlas(self: *const TextAtlas) snail.lowlevel.CurveAtlas {
        return .{
            .allocator = self.allocator,
            .font = null,
            .pages = self.pages,
            .glyph_map = .init(self.allocator), // empty — glyph lookup goes through FaceView
            .shaper = null,
            .layer_info_data = self.layer_info_data,
            .layer_info_width = self.layer_info_width,
            .layer_info_height = self.layer_info_height,
        };
    }

    /// Clean up a wrapper Atlas from uploadAtlas(). Only frees the empty glyph_map,
    /// NOT the shared pages.
    pub fn deinitUploadAtlas(_: *const TextAtlas, wrapper: *snail.lowlevel.CurveAtlas) void {
        wrapper.glyph_map.deinit();
        // Don't free pages — they belong to TextAtlas.
        wrapper.pages = &.{};
        // Don't call wrapper.deinit() — that would release shared pages.
    }
};

// ── FontConfig construction ──

fn buildFontConfig(allocator: Allocator, specs: []const FaceSpec) !*FontConfig {
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

fn resolveInner(config: *const FontConfig, style: snail.FontStyle, codepoint: u21, depth: u8) ?FaceIndex {
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

fn packStyle(style: snail.FontStyle) u8 {
    return @as(u8, @intFromEnum(style.weight)) | (@as(u8, @intFromBool(style.italic)) << 4);
}

// ── Itemization ──

fn itemizeText(allocator: Allocator, config: *const FontConfig, style: snail.FontStyle, text: []const u8) ![]ItemizedRun {
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

// ── Missing glyph detection ──

fn hasMissingGlyphs(fc: *const FaceConfig, fg: *const FaceGlyphData, segment: []const u8) bool {
    var i: usize = 0;
    while (i < segment.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(segment[i]) catch {
            i += 1;
            continue;
        };
        if (i + cp_len > segment.len) break;
        const cp: u21 = std.unicode.utf8Decode(segment[i..][0..cp_len]) catch {
            i += cp_len;
            continue;
        };
        i += cp_len;
        if (!snail.isRenderableTextCodepoint(cp)) continue;
        const gid = fc.font.glyphIndex(cp) catch continue;
        if (gid == 0) continue;
        if (fg.getGlyph(gid) != null) continue;
        const has_colr = if (fg.colr_base_map) |cbm| cbm.contains(gid) else false;
        if (!has_colr) return true;
    }
    return false;
}

fn isIdentityTransform(transform: snail.Transform2D) bool {
    return transform.xx == 1 and transform.xy == 0 and transform.tx == 0 and transform.yx == 0 and transform.yy == 1 and transform.ty == 0;
}

fn snapToGrid(value: f32, step: f32) f32 {
    if (step <= 0) return value;
    return @round(value / step) * step;
}

const HintGrid = struct { x: f32, y: f32 };

fn hintGrid(order: snail.SubpixelOrder) HintGrid {
    return switch (order) {
        .rgb, .bgr => .{ .x = 1.0 / 3.0, .y = 1.0 },
        .vrgb, .vbgr => .{ .x = 1.0, .y = 1.0 / 3.0 },
        .none => .{ .x = 1.0, .y = 1.0 },
    };
}

fn effectiveHintOrder(target: snail.ResolveTarget) snail.SubpixelOrder {
    if (!target.opaque_backdrop) return .none;
    return target.subpixel_order;
}

fn glyphAdvanceEm(face_view: *const FaceView, glyph_id: u16) f32 {
    if (glyph_id == 0) return 0;
    const advance_units: f32 = if (face_view.getGlyph(glyph_id)) |info|
        @floatFromInt(info.advance_width)
    else
        @floatFromInt(face_view.face_config.font.advanceWidth(glyph_id) catch 0);
    return advance_units / @as(f32, @floatFromInt(face_view.face_config.font.units_per_em));
}

const ResolvedTextHinting = struct {
    transform: snail.Transform2D,
    screen_transform: snail.Transform2D,
};

fn resolveTextHinting(
    face_view: *const FaceView,
    glyph_id: u16,
    scene_transform: snail.Transform2D,
    resolve: snail.TextResolveOptions,
    target: snail.ResolveTarget,
    scene_to_screen: ?snail.Transform2D,
) ResolvedTextHinting {
    var result = ResolvedTextHinting{
        .transform = scene_transform,
        .screen_transform = scene_transform,
    };
    if (resolve.hinting == .none) return result;
    if (!target.is_final_composite) return result;
    if (target.will_resample) return result;
    const map = scene_to_screen orelse return result;
    if (@abs(map.xy) > 1e-5 or @abs(map.yx) > 1e-5) return result;
    if (@abs(map.xx) <= 1e-5 or @abs(map.yy) <= 1e-5) return result;

    var screen = snail.Transform2D.multiply(map, scene_transform);
    if (@abs(screen.xy) > 1e-5 or @abs(screen.yx) > 1e-5) return result;

    const ppem = @max(@abs(screen.xx), @abs(screen.yy));
    if (ppem < 4.0 or ppem > 48.0) return result;

    const grid = hintGrid(effectiveHintOrder(target));
    screen.tx = snapToGrid(screen.tx, grid.x);
    screen.ty = snapToGrid(screen.ty, grid.y);

    if (resolve.hinting == .metrics) {
        const advance_em = glyphAdvanceEm(face_view, glyph_id);
        if (@abs(advance_em) > 1e-5) {
            const start = screen.tx;
            var end = snapToGrid(screen.tx + advance_em * screen.xx, grid.x);
            if (@abs(end - start) < grid.x * 0.5) {
                end = start + (if (screen.xx >= 0) grid.x else -grid.x);
            }
            screen.xx = (end - start) / advance_em;
        }
    }

    result.screen_transform = screen;
    result.transform = .{
        .xx = screen.xx / map.xx,
        .xy = screen.xy / map.xx,
        .tx = (screen.tx - map.tx) / map.xx,
        .yx = screen.yx / map.yy,
        .yy = screen.yy / map.yy,
        .ty = (screen.ty - map.ty) / map.yy,
    };

    return result;
}

fn glyphPlacementTransform(x: f32, y: f32, font_size: f32, skew_x: f32) snail.Transform2D {
    return .{
        .xx = font_size,
        .xy = skew_x * font_size,
        .tx = x,
        .yx = 0,
        .yy = -font_size,
        .ty = y,
    };
}

const ShapeRunResult = struct {
    glyphs: []ShapedText.Glyph,
    advance_x: f32,
    advance_y: f32,
};

fn shapeRunForFace(
    allocator: Allocator,
    fc: *const FaceConfig,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
) !ShapeRunResult {
    if (text.len == 0) return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };
    const inv_upem = 1.0 / @as(f32, @floatFromInt(fc.font.units_per_em));

    if (comptime build_options.enable_harfbuzz) {
        if (fc.hb_shaper) |hbs| {
            const shaped = hbs.shapeText(text);
            if (shaped.count == 0 or shaped.infos == null or shaped.positions == null)
                return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };

            const out = try allocator.alloc(ShapedText.Glyph, shaped.count);
            errdefer allocator.free(out);

            var cursor_x: f32 = 0;
            var cursor_y: f32 = 0;
            for (0..shaped.count) |i| {
                const info = shaped.infos[i];
                const pos = shaped.positions[i];
                const cluster = @min(@as(u32, @intCast(info.cluster)), @as(u32, @intCast(text.len)));
                out[i] = .{
                    .face_index = face_index,
                    .glyph_id = @intCast(info.codepoint),
                    .x_offset = (cursor_x + @as(f32, @floatFromInt(pos.x_offset))) * inv_upem,
                    .y_offset = -(cursor_y + @as(f32, @floatFromInt(pos.y_offset))) * inv_upem,
                    .x_advance = @as(f32, @floatFromInt(pos.x_advance)) * inv_upem,
                    .y_advance = -@as(f32, @floatFromInt(pos.y_advance)) * inv_upem,
                    .source_start = source_base + cluster,
                    .source_end = source_base + @as(u32, @intCast(text.len)),
                };
                cursor_x += @as(f32, @floatFromInt(pos.x_advance));
                cursor_y += @as(f32, @floatFromInt(pos.y_advance));
            }

            return .{
                .glyphs = out,
                .advance_x = cursor_x * inv_upem,
                .advance_y = -cursor_y * inv_upem,
            };
        }
    }

    var cp_count: usize = 0;
    {
        const utf8_view = std.unicode.Utf8View.initUnchecked(text);
        var it = utf8_view.iterator();
        while (it.nextCodepoint()) |_| cp_count += 1;
    }
    if (cp_count == 0) return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };

    const gids = try allocator.alloc(u16, cp_count);
    defer allocator.free(gids);
    const src_starts = try allocator.alloc(u32, cp_count);
    defer allocator.free(src_starts);
    const src_ends = try allocator.alloc(u32, cp_count);
    defer allocator.free(src_ends);

    var glyph_count: usize = 0;
    {
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
    }

    if (fc.shaper) |shaper| {
        glyph_count = shaper.applyLigaturesTracked(
            gids[0..glyph_count],
            src_starts[0..glyph_count],
            src_ends[0..glyph_count],
        ) catch glyph_count;
    }

    const out = try allocator.alloc(ShapedText.Glyph, glyph_count);
    errdefer allocator.free(out);

    var cursor_x: f32 = 0;
    var prev_gid: u16 = 0;
    for (gids[0..glyph_count], 0..) |gid, i| {
        if (gid == 0) {
            const advance = 500.0 * inv_upem;
            out[i] = .{
                .face_index = face_index,
                .glyph_id = 0,
                .x_offset = cursor_x,
                .y_offset = 0,
                .x_advance = advance,
                .y_advance = 0,
                .source_start = src_starts[i],
                .source_end = src_ends[i],
            };
            cursor_x += advance;
            prev_gid = 0;
            continue;
        }

        if (prev_gid != 0) {
            var kern: i16 = 0;
            if (fc.shaper) |shaper| kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
            if (kern == 0) kern = fc.font.getKerning(prev_gid, gid) catch 0;
            cursor_x += @as(f32, @floatFromInt(kern)) * inv_upem;
        }

        const advance = @as(f32, @floatFromInt(fc.font.advanceWidth(gid) catch 500)) * inv_upem;
        out[i] = .{
            .face_index = face_index,
            .glyph_id = gid,
            .x_offset = cursor_x,
            .y_offset = 0,
            .x_advance = advance,
            .y_advance = 0,
            .source_start = src_starts[i],
            .source_end = src_ends[i],
        };
        cursor_x += advance;
        prev_gid = gid;
    }

    return .{ .glyphs = out, .advance_x = cursor_x, .advance_y = 0 };
}

fn shapedGlyphAvailable(face_view: *const FaceView, glyph_id: u16) bool {
    if (glyph_id == 0) return true;
    if (face_view.getGlyph(glyph_id) != null) return true;
    if (face_view.getColrBase(glyph_id) != null) return true;
    var layers = face_view.colrLayers(glyph_id);
    if (layers.count() == 0) return false;
    var has_renderable_layer = false;
    while (layers.next()) |layer| {
        const info = face_view.getGlyph(layer.glyph_id) orelse return false;
        if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return false;
        has_renderable_layer = true;
    }
    return has_renderable_layer;
}

fn glyphInstanceBudget(face_view: *const FaceView, glyph_id: u16) usize {
    if (glyph_id == 0) return 0;
    if (face_view.getColrBase(glyph_id) != null) return 1;

    var layer_it = face_view.colrLayers(glyph_id);
    const layer_count = layer_it.count();
    if (layer_count > 0) return layer_count;

    return if (face_view.getGlyph(glyph_id) != null) 1 else 0;
}

fn appendBlobGlyph(
    builder: *TextBlobBuilder,
    face_index: FaceIndex,
    face_view: *const FaceView,
    glyph_id: u16,
    x: f32,
    y: f32,
    font_size: f32,
    color: [4]f32,
    synthetic: snail.SyntheticStyle,
) !void {
    try builder.glyphs.append(builder.allocator, .{
        .face_index = face_index,
        .glyph_id = glyph_id,
        .transform = glyphPlacementTransform(x, y, font_size, synthetic.skew_x),
        .embolden = synthetic.embolden,
        .color = color,
    });
    builder.instance_count_hint += glyphInstanceBudget(face_view, glyph_id);
    if (synthetic.embolden != 0 and glyph_id != 0) {
        builder.instance_count_hint += glyphInstanceBudget(face_view, glyph_id);
    }
}

// ── Per-face text rendering ──

fn addTextForFace(
    batch: *TextBatch,
    face_view: *const FaceView,
    fc: *const FaceConfig,
    fg: *const FaceGlyphData,
    text: []const u8,
    x: f32,
    y: f32,
    font_size: f32,
    color: [4]f32,
) f32 {
    if (comptime build_options.enable_harfbuzz) {
        if (fc.hb_shaper) |hbs| {
            return hbs.shapeAndEmit(text, font_size, x, y, color, face_view, batch);
        }
    }

    const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
    var cursor_x = x;

    var glyph_buf: [256]u16 = undefined;
    var glyph_count: usize = 0;
    const utf8_view = std.unicode.Utf8View.initUnchecked(text);
    var it = utf8_view.iterator();
    while (it.nextCodepoint()) |cp| {
        if (glyph_count >= glyph_buf.len) break;
        glyph_buf[glyph_count] = fc.font.glyphIndex(cp) catch 0;
        glyph_count += 1;
    }

    if (fc.shaper) |shaper| {
        glyph_count = shaper.applyLigatures(glyph_buf[0..glyph_count]) catch glyph_count;
    }

    var prev_gid: u16 = 0;
    for (glyph_buf[0..glyph_count]) |gid| {
        if (gid == 0) {
            cursor_x += scale * 500;
            prev_gid = 0;
            continue;
        }

        if (prev_gid != 0) {
            var kern: i16 = 0;
            if (fc.shaper) |shaper| {
                kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
            }
            if (kern == 0) {
                kern = fc.font.getKerning(prev_gid, gid) catch 0;
            }
            cursor_x += @as(f32, @floatFromInt(kern)) * scale;
        }

        if (glyph_emit.emitGlyph(batch, face_view, gid, cursor_x, y, font_size, color) == .buffer_full) break;

        const advance = faceGlyphAdvance(fc, fg, gid) orelse {
            cursor_x += scale * 500;
            prev_gid = gid;
            continue;
        };
        cursor_x += @as(f32, @floatFromInt(advance)) * scale;
        prev_gid = gid;
    }

    return cursor_x - x;
}

fn addTextForFaceSynthetic(
    allocator: Allocator,
    batch: *TextBatch,
    face_view: *const FaceView,
    fc: *const FaceConfig,
    fg: *const FaceGlyphData,
    text: []const u8,
    x: f32,
    y: f32,
    font_size: f32,
    color: [4]f32,
) f32 {
    // For synthetic styles, we need per-glyph positioning then emitStyledGlyph.
    const scale = font_size / @as(f32, @floatFromInt(fc.font.units_per_em));
    var cursor_x = x;

    var glyph_buf: [256]u16 = undefined;
    var glyph_count: usize = 0;
    const utf8_view = std.unicode.Utf8View.initUnchecked(text);
    var it = utf8_view.iterator();
    while (it.nextCodepoint()) |cp| {
        if (glyph_count >= glyph_buf.len) break;
        glyph_buf[glyph_count] = fc.font.glyphIndex(cp) catch 0;
        glyph_count += 1;
    }

    if (fc.shaper) |shaper| {
        glyph_count = shaper.applyLigatures(glyph_buf[0..glyph_count]) catch glyph_count;
    }

    _ = allocator; // reserved for future heap shaping path

    var prev_gid: u16 = 0;
    for (glyph_buf[0..glyph_count]) |gid| {
        if (gid == 0) {
            cursor_x += scale * 500;
            prev_gid = 0;
            continue;
        }

        if (prev_gid != 0) {
            var kern: i16 = 0;
            if (fc.shaper) |shaper| {
                kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
            }
            if (kern == 0) {
                kern = fc.font.getKerning(prev_gid, gid) catch 0;
            }
            cursor_x += @as(f32, @floatFromInt(kern)) * scale;
        }

        if (glyph_emit.emitStyledGlyph(batch, face_view, gid, cursor_x, y, font_size, color, fc.synthetic) == .buffer_full) break;

        const advance = faceGlyphAdvance(fc, fg, gid) orelse {
            cursor_x += scale * 500;
            prev_gid = gid;
            continue;
        };
        cursor_x += @as(f32, @floatFromInt(advance)) * scale;
        prev_gid = gid;
    }

    return cursor_x - x;
}

fn faceGlyphAdvance(fc: *const FaceConfig, fg: *const FaceGlyphData, gid: u16) ?u16 {
    if (fg.glyph_map.get(gid)) |info| return info.advance_width;
    if (fc.font.colr_offset != 0 and fc.font.colrLayerCount(gid) > 0) return fc.font.units_per_em;
    return null;
}

// ── Tests ──

const testing = std.testing;

test "TextAtlas.init with single face" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(?FaceIndex, 0), fonts.config.primary_face);
    try testing.expectEqual(@as(usize, 1), fonts.config.faces.len);
    try testing.expectEqual(@as(usize, 0), fonts.pageCount());
}

test "TextAtlas.ensureText adds missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    try testing.expectEqual(@as(usize, 0), fonts.pageCount());

    if (try fonts.ensureText(.{}, "Hello")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }
    try testing.expect(fonts.pageCount() > 0);

    // Ensuring the same text again returns null (nothing new).
    const again = try fonts.ensureText(.{}, "Hello");
    try testing.expectEqual(@as(?TextAtlas, null), again);
}

test "TextAtlas.ensureText snapshot immutability" {
    const assets_data = @import("assets");
    var fonts1 = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts1.deinit();

    if (try fonts1.ensureText(.{}, "AB")) |new_fonts| {
        fonts1.deinit();
        fonts1 = new_fonts;
    }
    const pages_before = fonts1.pageCount();

    const maybe_fonts2 = try fonts1.ensureText(.{}, "CDEFGHIJKLMNOP");
    try testing.expect(maybe_fonts2 != null);
    var fonts2 = maybe_fonts2.?;
    defer fonts2.deinit();

    try testing.expectEqual(pages_before, fonts1.pageCount());
    try testing.expect(fonts2.pageCount() >= pages_before);
}

test "TextAtlas.addText renders and reports advance" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "Hello")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    var buf: [64 * snail.lowlevel.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.lowlevel.TextBatch.init(&buf);
    const result = try fonts.addText(&batch, .{}, "Hello", 0, 100, 24, .{ 1, 1, 1, 1 });

    try testing.expect(result.advance > 0);
    try testing.expect(batch.glyphCount() > 0);
    try testing.expect(!result.missing);
}

test "TextAtlas.addText reports missing glyphs" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    // Atlas is empty; addText should report missing glyphs.
    var buf: [64 * snail.lowlevel.TEXT_WORDS_PER_GLYPH]u32 = undefined;
    var batch = snail.lowlevel.TextBatch.init(&buf);
    const result = try fonts.addText(&batch, .{}, "Hello", 0, 100, 24, .{ 1, 1, 1, 1 });

    try testing.expect(result.missing);
    try testing.expectEqual(@as(usize, 0), batch.glyphCount());
}

test "TextAtlas.lineMetrics returns primary face metrics" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    const lm = try fonts.lineMetrics();
    try testing.expect(lm.ascent > 0);
    try testing.expect(lm.descent < 0);
}

test "TextAtlas with multiple faces and fallback" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_arabic, .fallback = true },
    });
    defer fonts.deinit();

    // Arabic codepoint should resolve to the Arabic face (index 1).
    const face = fonts.resolve(.{}, 0x0645); // م
    try testing.expectEqual(@as(?FaceIndex, 1), face);

    // Latin codepoint should resolve to the primary face (index 0).
    const latin = fonts.resolve(.{}, 'A');
    try testing.expectEqual(@as(?FaceIndex, 0), latin);
}

test "TextAtlas deduplicates same font data" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_regular, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
    });
    defer fonts.deinit();

    // Both faces share the same parsed font (data pointer equality).
    try testing.expectEqual(fonts.config.faces[0].font.data.ptr, fonts.config.faces[1].font.data.ptr);
}

test "phase hinting snaps final text origin without changing scale" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "H")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    const gid = try fonts.config.faces[0].font.glyphIndex('H');
    const view = fonts.faceView(0, .{});
    const transform = glyphPlacementTransform(10.2, 20.49, 12.0, 0.0);
    const hinted = resolveTextHinting(&view, gid, transform, .{ .hinting = .phase }, .{
        .pixel_width = 800,
        .pixel_height = 600,
        .subpixel_order = .rgb,
    }, .identity).transform;

    try testing.expectApproxEqAbs(@as(f32, 31.0 / 3.0), hinted.tx, 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 20.0), hinted.ty, 0.0001);
    try testing.expectApproxEqAbs(transform.xx, hinted.xx, 0.0001);
    try testing.expectApproxEqAbs(transform.yy, hinted.yy, 0.0001);
}

test "metrics hinting snaps final text advance span" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "H")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    const gid = try fonts.config.faces[0].font.glyphIndex('H');
    const view = fonts.faceView(0, .{});
    const transform = glyphPlacementTransform(10.2, 20.49, 12.0, 0.0);
    const hinted = resolveTextHinting(&view, gid, transform, .{ .hinting = .metrics }, .{
        .pixel_width = 800,
        .pixel_height = 600,
        .subpixel_order = .rgb,
    }, .identity).transform;
    const advance_em = glyphAdvanceEm(&view, gid);

    try testing.expectApproxEqAbs(snapToGrid(hinted.tx, 1.0 / 3.0), hinted.tx, 0.0001);
    try testing.expectApproxEqAbs(snapToGrid(hinted.tx + advance_em * hinted.xx, 1.0 / 3.0), hinted.tx + advance_em * hinted.xx, 0.0001);
    try testing.expect(@abs(hinted.xx - transform.xx) > 0.0001);
}

test "hinting skips intermediate targets" {
    const assets_data = @import("assets");
    var fonts = try TextAtlas.init(testing.allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
    });
    defer fonts.deinit();

    if (try fonts.ensureText(.{}, "H")) |new_fonts| {
        fonts.deinit();
        fonts = new_fonts;
    }

    const gid = try fonts.config.faces[0].font.glyphIndex('H');
    const view = fonts.faceView(0, .{});
    const transform = glyphPlacementTransform(10.2, 20.49, 12.0, 0.0);
    const hinted = resolveTextHinting(&view, gid, transform, .{ .hinting = .metrics }, .{
        .pixel_width = 800,
        .pixel_height = 600,
        .subpixel_order = .rgb,
        .is_final_composite = false,
    }, .identity).transform;

    try testing.expectApproxEqAbs(transform.xx, hinted.xx, 0.0001);
    try testing.expectApproxEqAbs(transform.xy, hinted.xy, 0.0001);
    try testing.expectApproxEqAbs(transform.tx, hinted.tx, 0.0001);
    try testing.expectApproxEqAbs(transform.yx, hinted.yx, 0.0001);
    try testing.expectApproxEqAbs(transform.yy, hinted.yy, 0.0001);
    try testing.expectApproxEqAbs(transform.ty, hinted.ty, 0.0001);
}


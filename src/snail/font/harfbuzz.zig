//! HarfBuzz text shaping integration.
//! Provides full OpenType shaping (Arabic, Devanagari, etc.)
//! via the HarfBuzz library. Compile with -Dharfbuzz=true.
//!
//! Each `HarfBuzzShaper` carries an em-scale font (`hb_font_em`, default OT
//! funcs, scale = upem) used for normal shaping. When an `AdvanceProvider`
//! is attached via `attachAdvanceProvider`, a lazily-created sub-font
//! (`hb_font_hinted`) is given a single overridden font-func —
//! `glyph_h_advance` — that routes through the provider closure. Hinted
//! shape calls set the sub-font's scale to `ppem_26_6` so HB's advances
//! land in 26.6-pixel units; the caller divides them back to em-space and
//! the round-trip preserves the hint-quantized positioning.

const std = @import("std");
const text_types = @import("../text.zig");
const font_types = @import("types.zig");
const hb = @cImport({
    @cInclude("hb.h");
});

pub const Feature = hb.hb_feature_t;
pub const FEATURE_GLOBAL_START: c_uint = 0;
pub const FEATURE_GLOBAL_END: c_uint = 0xFFFFFFFF;

pub const HintPpem = text_types.HintPpem;
pub const AdvanceProvider = text_types.AdvanceProvider;

pub fn makeTag(tag: [4]u8) u32 {
    return (@as(u32, tag[0]) << 24) | (@as(u32, tag[1]) << 16) |
        (@as(u32, tag[2]) << 8) | @as(u32, tag[3]);
}

/// What backs the `glyph_h_advance` font_func. `shape(faces, ...)`
/// attaches a closure that typically routes into a
/// `snail.HintedGlyphCache`.
const AdvanceSource = union(enum) {
    none,
    provider: struct { provider: AdvanceProvider, font_id: u32 },
};

/// User-data passed to our custom HB font_funcs. Heap-allocated so the
/// pointer stays valid across `HarfBuzzShaper` moves. The fields are
/// mutated in-place per shape call.
const HintHooks = struct {
    source: AdvanceSource,
    ppem_x_26_6: u32,
    ppem_y_26_6: u32,
};

pub const HarfBuzzShaper = struct {
    hb_face: *hb.hb_face_t,
    hb_font_em: *hb.hb_font_t,
    /// Sub-font of `hb_font_em` used for hinted shaping. Lazily created
    /// by `attachAdvanceProvider`. Inherits parent's OT defaults for
    /// everything except `glyph_h_advance`, which routes through the
    /// attached `AdvanceProvider`.
    hb_font_hinted: ?*hb.hb_font_t,
    hb_funcs_hinted: ?*hb.hb_font_funcs_t,
    hb_buffer: *hb.hb_buffer_t,
    units_per_em: u16,
    hooks: ?*HintHooks,
    hooks_allocator: ?std.mem.Allocator,

    pub fn init(font_data: []const u8, units_per_em: u16) !HarfBuzzShaper {
        return initFace(font_data, 0, units_per_em);
    }

    pub fn initFace(font_data: []const u8, face_index: u32, units_per_em: u16) !HarfBuzzShaper {
        return initInstance(font_data, face_index, units_per_em, &.{});
    }

    pub fn initInstance(
        font_data: []const u8,
        face_index: u32,
        units_per_em: u16,
        variations: []const font_types.Variation,
    ) !HarfBuzzShaper {
        const blob = hb.hb_blob_create(
            font_data.ptr,
            @intCast(font_data.len),
            hb.HB_MEMORY_MODE_READONLY,
            null,
            null,
        ) orelse return error.HarfBuzzInitFailed;

        const face = hb.hb_face_create(blob, face_index) orelse {
            hb.hb_blob_destroy(blob);
            return error.HarfBuzzInitFailed;
        };
        hb.hb_blob_destroy(blob);

        const font = hb.hb_font_create(face) orelse {
            hb.hb_face_destroy(face);
            return error.HarfBuzzInitFailed;
        };

        const buffer = hb.hb_buffer_create() orelse {
            hb.hb_font_destroy(font);
            hb.hb_face_destroy(face);
            return error.HarfBuzzInitFailed;
        };

        const upem: c_int = @intCast(units_per_em);
        hb.hb_font_set_scale(font, upem, upem);
        for (variations) |variation| {
            hb.hb_font_set_variation(font, makeTag(variation.tag), variation.value);
        }

        return .{
            .hb_face = face,
            .hb_font_em = font,
            .hb_font_hinted = null,
            .hb_funcs_hinted = null,
            .hb_buffer = buffer,
            .units_per_em = units_per_em,
            .hooks = null,
            .hooks_allocator = null,
        };
    }

    pub fn deinit(self: *HarfBuzzShaper) void {
        hb.hb_buffer_destroy(self.hb_buffer);
        if (self.hb_font_hinted) |f| hb.hb_font_destroy(f);
        if (self.hb_funcs_hinted) |f| hb.hb_font_funcs_destroy(f);
        hb.hb_font_destroy(self.hb_font_em);
        hb.hb_face_destroy(self.hb_face);
        if (self.hooks) |h| if (self.hooks_allocator) |a| a.destroy(h);
    }

    /// Bind an advance-provider closure. Subsequent
    /// `shapeTextWithProvider` calls route `glyph_h_advance` through it.
    /// The provider closure (and its context) is borrowed; the caller
    /// keeps it valid for the lifetime of subsequent shape calls.
    pub fn attachAdvanceProvider(
        self: *HarfBuzzShaper,
        allocator: std.mem.Allocator,
        provider: AdvanceProvider,
        font_id: u32,
    ) !void {
        try self.ensureHintFunnel(allocator);
        self.hooks.?.source = .{ .provider = .{ .provider = provider, .font_id = font_id } };
    }

    /// Idempotent allocation of the sub-font + funcs + hooks.
    fn ensureHintFunnel(self: *HarfBuzzShaper, allocator: std.mem.Allocator) !void {
        if (self.hooks != null) return;
        const hooks = try allocator.create(HintHooks);
        errdefer allocator.destroy(hooks);
        hooks.* = .{
            .source = .none,
            .ppem_x_26_6 = self.units_per_em,
            .ppem_y_26_6 = self.units_per_em,
        };

        const sub_font = hb.hb_font_create_sub_font(self.hb_font_em) orelse return error.HarfBuzzInitFailed;
        errdefer hb.hb_font_destroy(sub_font);

        const funcs = hb.hb_font_funcs_create() orelse return error.HarfBuzzInitFailed;
        errdefer hb.hb_font_funcs_destroy(funcs);

        hb.hb_font_funcs_set_glyph_h_advance_func(funcs, hbGetGlyphHAdvance, hooks, null);
        hb.hb_font_funcs_make_immutable(funcs);
        hb.hb_font_set_funcs(sub_font, funcs, hooks, null);

        self.hb_font_hinted = sub_font;
        self.hb_funcs_hinted = funcs;
        self.hooks = hooks;
        self.hooks_allocator = allocator;
    }

    pub fn hasAdvanceProvider(self: *const HarfBuzzShaper) bool {
        if (self.hooks) |h| return h.source == .provider;
        return false;
    }

    /// Shape `text` in em-space (HB scale = upem). Output advances/offsets
    /// are font units; callers divide by upem to get em-space floats.
    pub fn shapeText(self: *const HarfBuzzShaper, text: []const u8) ShapedRaw {
        return self.shapeTextWithFeatures(text, &.{});
    }

    pub fn shapeTextWithFeatures(
        self: *const HarfBuzzShaper,
        text: []const u8,
        features: []const hb.hb_feature_t,
    ) ShapedRaw {
        return self.shapeIntoBuffer(self.hb_font_em, text, features);
    }

    /// Shape `text` through HB with the attached `AdvanceProvider`
    /// routing `glyph_h_advance`. Requires `attachAdvanceProvider` to
    /// have been called. If none is attached the call falls through to
    /// em-space shaping.
    pub fn shapeTextWithProvider(
        self: *const HarfBuzzShaper,
        text: []const u8,
        features: []const hb.hb_feature_t,
        ppem: HintPpem,
    ) ShapedRaw {
        const font = self.hb_font_hinted orelse return self.shapeTextWithFeatures(text, features);
        if (self.hooks) |h| {
            if (h.source != .provider) return self.shapeTextWithFeatures(text, features);
            h.ppem_x_26_6 = ppem.x_26_6;
            h.ppem_y_26_6 = ppem.y_26_6;
        } else {
            return self.shapeTextWithFeatures(text, features);
        }
        hb.hb_font_set_scale(font, @intCast(ppem.x_26_6), @intCast(ppem.y_26_6));
        return self.shapeIntoBuffer(font, text, features);
    }

    fn shapeIntoBuffer(
        self: *const HarfBuzzShaper,
        font: *hb.hb_font_t,
        text: []const u8,
        features: []const hb.hb_feature_t,
    ) ShapedRaw {
        hb.hb_buffer_clear_contents(self.hb_buffer);
        hb.hb_buffer_add_utf8(self.hb_buffer, text.ptr, @intCast(text.len), 0, @intCast(text.len));
        hb.hb_buffer_guess_segment_properties(self.hb_buffer);
        const features_ptr: [*c]const hb.hb_feature_t = if (features.len == 0) null else features.ptr;
        hb.hb_shape(font, self.hb_buffer, features_ptr, @intCast(features.len));

        var count: c_uint = 0;
        const infos = hb.hb_buffer_get_glyph_infos(self.hb_buffer, &count);
        const positions = hb.hb_buffer_get_glyph_positions(self.hb_buffer, &count);
        return .{ .count = count, .infos = infos, .positions = positions };
    }

    /// Discover all glyph IDs that HarfBuzz produces for the given text.
    /// Caller owns returned slice.
    pub fn discoverGlyphs(self: *const HarfBuzzShaper, allocator: std.mem.Allocator, text: []const u8) ![]u16 {
        const shaped = self.shapeText(text);
        if (shaped.count == 0 or shaped.infos == null) return &.{};

        // Deduplicate
        var seen = std.AutoHashMap(u16, void).init(allocator);
        defer seen.deinit();

        for (0..shaped.count) |i| {
            const gid: u16 = @intCast(shaped.infos[i].codepoint);
            if (gid != 0) try seen.put(gid, {});
        }

        var result = try allocator.alloc(u16, seen.count());
        var idx: usize = 0;
        var it = seen.keyIterator();
        while (it.next()) |k| {
            result[idx] = k.*;
            idx += 1;
        }
        return result;
    }
};

pub const ShapedRaw = struct {
    count: c_uint,
    infos: [*c]hb.hb_glyph_info_t,
    positions: [*c]hb.hb_glyph_position_t,
};

fn hbGetGlyphHAdvance(
    font: ?*hb.hb_font_t,
    font_data: ?*anyopaque,
    glyph: hb.hb_codepoint_t,
    user_data: ?*anyopaque,
) callconv(.c) hb.hb_position_t {
    _ = font;
    _ = font_data;
    const hooks: *HintHooks = @ptrCast(@alignCast(user_data orelse return 0));
    const gid: u16 = @intCast(glyph & 0xFFFF);
    const ppem = HintPpem{ .x_26_6 = hooks.ppem_x_26_6, .y_26_6 = hooks.ppem_y_26_6 };
    const adv = switch (hooks.source) {
        .none => return 0,
        .provider => |p| p.provider.get_advance(p.provider.context, p.font_id, gid, ppem),
    };
    return @intCast(adv);
}

const std = @import("std");
const curves_mod = @import("../atlas/curves.zig");
const curve_tex = @import("../format/curve_texture.zig");
const render_abi = @import("../format/abi.zig");
const bezier = @import("../math/bezier.zig");
const autohint = @import("../font/autohint/producer.zig");
const blue = @import("../font/autohint/blue.zig");
const key_mod = @import("key.zig");

pub const Key = key_mod.Key;
pub const GlyphCurves = curves_mod.GlyphCurves;
pub const FeatureEdge = autohint.FeatureEdge;
pub const FeatureZone = blue.FeatureZone;

/// Borrowed prepared curve payload. It contains no allocator or ownership.
pub const GeometryView = struct {
    curve_words: []const u16,
    band_words: []const u16,
    curve_count: u16,
    encoding: curve_tex.Encoding,
    path_curve_class: render_abi.PathCurveClass,
    h_band_count: u16,
    v_band_count: u16,
    band_scale_x: f32,
    band_scale_y: f32,
    band_offset_x: f32,
    band_offset_y: f32,
    bbox: bezier.BBox,

    pub fn fromGlyphCurves(curves: *const GlyphCurves) GeometryView {
        return .{
            .curve_words = curves.curve_bytes,
            .band_words = curves.band_bytes,
            .curve_count = curves.curve_count,
            .encoding = curves.encoding,
            .path_curve_class = curves.path_curve_class,
            .h_band_count = curves.h_band_count,
            .v_band_count = curves.v_band_count,
            .band_scale_x = curves.band_scale_x,
            .band_scale_y = curves.band_scale_y,
            .band_offset_x = curves.band_offset_x,
            .band_offset_y = curves.band_offset_y,
            .bbox = curves.bbox,
        };
    }

    /// Adapt this borrowed prepared value to the ownership-free atlas input.
    pub fn atlasView(self: GeometryView) curves_mod.GeometryView {
        return .{
            .curve_bytes = self.curve_words,
            .band_bytes = self.band_words,
            .curve_count = self.curve_count,
            .encoding = self.encoding,
            .path_curve_class = self.path_curve_class,
            .h_band_count = self.h_band_count,
            .v_band_count = self.v_band_count,
            .band_scale_x = self.band_scale_x,
            .band_scale_y = self.band_scale_y,
            .band_offset_x = self.band_offset_x,
            .band_offset_y = self.band_offset_y,
            .bbox = self.bbox,
        };
    }

    pub fn validate(self: GeometryView) GlyphCurves.ValidationError!void {
        try self.atlasView().validate();
    }

    pub fn clone(self: GeometryView, allocator: std.mem.Allocator) !Geometry {
        return .{ .curves = try self.atlasView().clone(allocator) };
    }
};

/// Owned, transferable prepared geometry.
pub const Geometry = struct {
    curves: GlyphCurves,

    /// Takes ownership without copying, regardless of whether `curves` uses
    /// one combined backing allocation or two producer allocations.
    pub fn fromGlyphCurves(curves: GlyphCurves) Geometry {
        return .{ .curves = curves };
    }

    pub fn view(self: *const Geometry) GeometryView {
        return .fromGlyphCurves(&self.curves);
    }

    pub fn intoGlyphCurves(self: *Geometry) GlyphCurves {
        const result = self.curves;
        self.* = undefined;
        return result;
    }

    pub fn deinit(self: *Geometry) void {
        self.curves.deinit();
        self.* = undefined;
    }
};

pub const AutohintModelView = struct {
    blues: []const FeatureZone,
    std_x: f32,
    std_y: f32,

    pub fn validate(self: AutohintModelView) error{InvalidValue}!void {
        if (!std.math.isFinite(self.std_x) or !std.math.isFinite(self.std_y) or
            self.std_x < 0 or self.std_y < 0 or
            self.blues.len > @as(usize, std.math.maxInt(i16)) + 1)
            return error.InvalidValue;
        for (self.blues) |zone| {
            if (!std.math.isFinite(zone.ref) or !std.math.isFinite(zone.shoot))
                return error.InvalidValue;
        }
    }
};

pub const AutohintGlyphView = struct {
    x: []const FeatureEdge,
    y: []const FeatureEdge,
    left: f32,

    pub fn validate(self: AutohintGlyphView) error{InvalidValue}!void {
        if (!std.math.isFinite(self.left)) return error.InvalidValue;
        try validateEdges(self.x);
        try validateEdges(self.y);
    }
};

fn validateEdges(edges: []const FeatureEdge) error{InvalidValue}!void {
    if (edges.len > autohint.max_features_per_axis) return error.InvalidValue;
    for (edges, 0..) |edge, index| {
        if (!std.math.isFinite(edge.pos) or !std.math.isFinite(edge.width) or
            edge.width < 0 or edge.stem < -1 or edge.blue < -1 or
            edge.flags._reserved != 0)
            return error.InvalidValue;
        if (edge.flags.semantics_resolved) {
            const grid = edge.flags.grid_companion;
            const blue_companion = edge.flags.blue_companion;
            if ((grid < 62 and (grid >= edges.len or grid == index)) or
                (blue_companion < 62 and
                    (blue_companion >= edges.len or blue_companion == index)))
                return error.InvalidValue;
        } else if (edge.flags.grid_companion != 63 or
            edge.flags.blue_companion != 63)
        {
            return error.InvalidValue;
        }
        if (edge.stem >= 0) {
            const partner_index: usize = @intCast(edge.stem);
            if (partner_index >= edges.len or partner_index == index)
                return error.InvalidValue;
            const partner = edges[partner_index];
            if (partner.stem != @as(i16, @intCast(index)) or
                !std.math.isFinite(partner.pos) or partner.pos == edge.pos or
                !std.math.isFinite(partner.width) or partner.width != edge.width)
                return error.InvalidValue;
        }
    }
}

pub const TtGlyphView = struct {
    geometry: GeometryView,
    advance_x_26_6: i32,
};

pub const ValueView = union(enum) {
    geometry: GeometryView,
    autohint_model: AutohintModelView,
    autohint_glyph: AutohintGlyphView,
    tt_glyph: TtGlyphView,
    tt_advance: i32,

    pub fn validate(self: ValueView) !void {
        switch (self) {
            .geometry => |geometry| try geometry.validate(),
            .autohint_model => |model| try model.validate(),
            .autohint_glyph => |glyph| try glyph.validate(),
            .tt_glyph => |glyph| try glyph.geometry.validate(),
            .tt_advance => {},
        }
    }
};

pub const RecordView = struct {
    key: Key,
    value: ValueView,

    pub fn validate(self: RecordView) !void {
        try self.value.validate();
    }
};

const OwnedAutohintModel = struct {
    allocator: std.mem.Allocator,
    blues: []FeatureZone,
    std_x: f32,
    std_y: f32,

    fn view(self: *const OwnedAutohintModel) AutohintModelView {
        return .{ .blues = self.blues, .std_x = self.std_x, .std_y = self.std_y };
    }

    fn deinit(self: *OwnedAutohintModel) void {
        self.allocator.free(self.blues);
        self.* = undefined;
    }
};

const OwnedAutohintGlyph = struct {
    allocator: std.mem.Allocator,
    x: []FeatureEdge,
    y: []FeatureEdge,
    left: f32,

    fn view(self: *const OwnedAutohintGlyph) AutohintGlyphView {
        return .{ .x = self.x, .y = self.y, .left = self.left };
    }

    fn deinit(self: *OwnedAutohintGlyph) void {
        self.allocator.free(self.x);
        self.allocator.free(self.y);
        self.* = undefined;
    }
};

const OwnedTtGlyph = struct {
    geometry: Geometry,
    advance_x_26_6: i32,
};

/// Owned counterpart to `ValueView`. Owned values can cross worker threads.
pub const OwnedValue = union(enum) {
    geometry: Geometry,
    autohint_model: OwnedAutohintModel,
    autohint_glyph: OwnedAutohintGlyph,
    tt_glyph: OwnedTtGlyph,
    tt_advance: i32,

    pub fn fromGeometry(geometry: Geometry) OwnedValue {
        return .{ .geometry = geometry };
    }

    pub fn cloneAutohintModel(
        allocator: std.mem.Allocator,
        source: AutohintModelView,
    ) !OwnedValue {
        try source.validate();
        return .{ .autohint_model = .{
            .allocator = allocator,
            .blues = try allocator.dupe(FeatureZone, source.blues),
            .std_x = source.std_x,
            .std_y = source.std_y,
        } };
    }

    pub fn cloneAutohintGlyph(
        allocator: std.mem.Allocator,
        source: AutohintGlyphView,
    ) !OwnedValue {
        try source.validate();
        const x = try allocator.dupe(FeatureEdge, source.x);
        errdefer allocator.free(x);
        return .{ .autohint_glyph = .{
            .allocator = allocator,
            .x = x,
            .y = try allocator.dupe(FeatureEdge, source.y),
            .left = source.left,
        } };
    }

    pub fn fromTtGlyph(geometry: Geometry, advance_x_26_6: i32) OwnedValue {
        return .{ .tt_glyph = .{
            .geometry = geometry,
            .advance_x_26_6 = advance_x_26_6,
        } };
    }

    pub fn fromTtAdvance(advance_x_26_6: i32) OwnedValue {
        return .{ .tt_advance = advance_x_26_6 };
    }

    pub fn clone(allocator: std.mem.Allocator, source: ValueView) !OwnedValue {
        return switch (source) {
            .geometry => |geometry| .{ .geometry = try geometry.clone(allocator) },
            .autohint_model => |model| cloneAutohintModel(allocator, model),
            .autohint_glyph => |glyph| cloneAutohintGlyph(allocator, glyph),
            .tt_glyph => |glyph| fromTtGlyph(
                try glyph.geometry.clone(allocator),
                glyph.advance_x_26_6,
            ),
            .tt_advance => |advance| fromTtAdvance(advance),
        };
    }

    pub fn view(self: *const OwnedValue) ValueView {
        return switch (self.*) {
            .geometry => |*geometry| .{ .geometry = geometry.view() },
            .autohint_model => |*model| .{ .autohint_model = model.view() },
            .autohint_glyph => |*glyph| .{ .autohint_glyph = glyph.view() },
            .tt_glyph => |*glyph| .{ .tt_glyph = .{
                .geometry = glyph.geometry.view(),
                .advance_x_26_6 = glyph.advance_x_26_6,
            } },
            .tt_advance => |advance| .{ .tt_advance = advance },
        };
    }

    pub fn deinit(self: *OwnedValue) void {
        switch (self.*) {
            .geometry => |*geometry| geometry.deinit(),
            .autohint_model => |*model| model.deinit(),
            .autohint_glyph => |*glyph| glyph.deinit(),
            .tt_glyph => |*glyph| glyph.geometry.deinit(),
            .tt_advance => {},
        }
        self.* = undefined;
    }
};

pub const OwnedRecord = struct {
    key: Key,
    value: OwnedValue,

    pub fn init(key: Key, value: OwnedValue) OwnedRecord {
        return .{ .key = key, .value = value };
    }

    pub fn clone(allocator: std.mem.Allocator, source: RecordView) !OwnedRecord {
        return .{ .key = source.key, .value = try .clone(allocator, source.value) };
    }

    pub fn view(self: *const OwnedRecord) RecordView {
        return .{ .key = self.key, .value = self.value.view() };
    }

    pub fn deinit(self: *OwnedRecord) void {
        self.value.deinit();
        self.* = undefined;
    }
};

test "autohint glyph validation rejects non-canonical feature links" {
    var edge = FeatureEdge{
        .pos = 0,
        .width = 0,
        .stem = -1,
        .blue = -1,
        .flags = .{ .round = false },
    };
    try (AutohintGlyphView{ .x = &.{edge}, .y = &.{}, .left = 0 }).validate();

    edge.flags._reserved = 1;
    try std.testing.expectError(
        error.InvalidValue,
        (AutohintGlyphView{ .x = &.{edge}, .y = &.{}, .left = 0 }).validate(),
    );
    edge.flags = .{
        .round = false,
        .semantics_resolved = true,
        .grid_companion = 0,
    };
    try std.testing.expectError(
        error.InvalidValue,
        (AutohintGlyphView{ .x = &.{edge}, .y = &.{}, .left = 0 }).validate(),
    );
}

const std = @import("std");
const analysis = @import("../font/autohint/analysis.zig");

/// Stable identity supplied by the application for one exact font instance.
///
/// It must cover the font bytes, face index, and variation coordinates. Snail
/// deliberately does not hide a whole-font hash in preparation hot paths.
pub const FontKey = [16]u8;

/// Stable identity for caller-authored, non-font geometry.
pub const GeometrySourceKey = [16]u8;

/// Format and producer revision mixed into every artifact key.
pub const producer_version: u32 = 1;

/// Opaque, deterministic identity of one prepared producer artifact.
pub const Key = extern struct {
    value: [32]u8,

    pub fn asBytes(self: *const Key) []const u8 {
        return &self.value;
    }

    pub fn eql(a: Key, b: Key) bool {
        return std.mem.eql(u8, &a.value, &b.value);
    }

    pub fn order(a: Key, b: Key) std.math.Order {
        return std.mem.order(u8, &a.value, &b.value);
    }

    pub fn format(self: Key, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{x}", .{self.value});
    }
};

pub const GeometryOptions = struct {
    /// Source-space maximum error used when lowering cubics to quadratics.
    cubic_tolerance: f32,

    pub fn validate(self: GeometryOptions) error{InvalidOptions}!void {
        if (!std.math.isFinite(self.cubic_tolerance) or self.cubic_tolerance <= 0)
            return error.InvalidOptions;
    }
};

pub const AutohintOptions = struct {
    params: analysis.Params = .default,
    blue_tolerance_em: f32 = 1.0 / 24.0,

    pub fn validate(self: AutohintOptions) error{InvalidOptions}!void {
        const floats = [_]f32{
            self.params.flat_ratio,
            self.params.flat_ratio_x,
            self.params.min_len_em,
            self.params.merge_em,
            self.params.min_overlap_em,
            self.params.max_stem_em,
            self.blue_tolerance_em,
        };
        for (floats) |value| {
            if (!std.math.isFinite(value) or value < 0) return error.InvalidOptions;
        }
        if (self.params.curve_steps == 0) return error.InvalidOptions;
    }
};

const Kind = enum(u8) {
    unhinted = 1,
    geometry = 2,
    autohint_model = 3,
    autohint_glyph = 4,
    tt_glyph = 5,
    tt_advance = 6,
};

const KeyHasher = struct {
    state: std.crypto.hash.Blake3,

    fn init(kind: Kind) KeyHasher {
        var state = std.crypto.hash.Blake3.init(.{});
        state.update("snail prepared artifact key\x00");
        var version_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &version_bytes, producer_version, .little);
        state.update(&version_bytes);
        state.update(&.{@intFromEnum(kind)});
        return .{ .state = state };
    }

    fn bytes(self: *KeyHasher, value: []const u8) void {
        self.state.update(value);
    }

    fn u16Value(self: *KeyHasher, value: u16) void {
        var buffer: [2]u8 = undefined;
        std.mem.writeInt(u16, &buffer, value, .little);
        self.bytes(&buffer);
    }

    fn u32Value(self: *KeyHasher, value: u32) void {
        var buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &buffer, value, .little);
        self.bytes(&buffer);
    }

    fn f32Value(self: *KeyHasher, value: f32) void {
        self.u32Value(@bitCast(value));
    }

    fn finish(self: *KeyHasher) Key {
        var result: Key = undefined;
        self.state.final(&result.value);
        return result;
    }
};

fn addGeometryOptions(hasher: *KeyHasher, options: GeometryOptions) void {
    hasher.f32Value(options.cubic_tolerance);
}

fn addAutohintOptions(hasher: *KeyHasher, options: AutohintOptions) void {
    hasher.f32Value(options.params.flat_ratio);
    hasher.f32Value(options.params.flat_ratio_x);
    hasher.u32Value(options.params.curve_steps);
    hasher.f32Value(options.params.min_len_em);
    hasher.f32Value(options.params.merge_em);
    hasher.f32Value(options.params.min_overlap_em);
    hasher.f32Value(options.params.max_stem_em);
    hasher.f32Value(options.blue_tolerance_em);
}

pub fn unhintedKey(
    font: FontKey,
    glyph_id: u16,
    options: GeometryOptions,
) error{InvalidOptions}!Key {
    try options.validate();
    var hasher = KeyHasher.init(.unhinted);
    hasher.bytes(&font);
    hasher.u16Value(glyph_id);
    addGeometryOptions(&hasher, options);
    return hasher.finish();
}

pub fn geometryKey(
    source: GeometrySourceKey,
    options: GeometryOptions,
) error{InvalidOptions}!Key {
    try options.validate();
    var hasher = KeyHasher.init(.geometry);
    hasher.bytes(&source);
    addGeometryOptions(&hasher, options);
    return hasher.finish();
}

pub fn autohintModelKey(
    font: FontKey,
    options: AutohintOptions,
) error{InvalidOptions}!Key {
    try options.validate();
    var hasher = KeyHasher.init(.autohint_model);
    hasher.bytes(&font);
    addAutohintOptions(&hasher, options);
    return hasher.finish();
}

pub fn autohintGlyphKey(
    font: FontKey,
    glyph_id: u16,
    options: AutohintOptions,
) error{InvalidOptions}!Key {
    try options.validate();
    var hasher = KeyHasher.init(.autohint_glyph);
    hasher.bytes(&font);
    hasher.u16Value(glyph_id);
    addAutohintOptions(&hasher, options);
    return hasher.finish();
}

pub fn ttGlyphKey(
    font: FontKey,
    glyph_id: u16,
    ppem: anytype,
) error{InvalidPpem}!Key {
    try validatePpem(ppem);
    if (ppem.x_26_6 != ppem.y_26_6) return error.InvalidPpem;
    var hasher = KeyHasher.init(.tt_glyph);
    hasher.bytes(&font);
    hasher.u16Value(glyph_id);
    hasher.u32Value(ppem.x_26_6);
    return hasher.finish();
}

pub fn ttAdvanceKey(
    font: FontKey,
    glyph_id: u16,
    ppem: anytype,
) error{InvalidPpem}!Key {
    try validatePpem(ppem);
    var hasher = KeyHasher.init(.tt_advance);
    hasher.bytes(&font);
    hasher.u16Value(glyph_id);
    hasher.u32Value(ppem.x_26_6);
    hasher.u32Value(ppem.y_26_6);
    return hasher.finish();
}

fn validatePpem(ppem: anytype) error{InvalidPpem}!void {
    if (ppem.x_26_6 == 0 or ppem.y_26_6 == 0 or
        ppem.x_26_6 > 0xffff or ppem.y_26_6 > 0xffff)
        return error.InvalidPpem;
}

test "keys cover producer kind and bit-exact output options" {
    const font: FontKey = [_]u8{0x42} ** 16;
    const a = try unhintedKey(font, 7, .{ .cubic_tolerance = 0.25 });
    const b = try unhintedKey(font, 7, .{ .cubic_tolerance = 0.125 });
    const c = try unhintedKey(font, 8, .{ .cubic_tolerance = 0.25 });
    const d = try autohintGlyphKey(font, 7, .{});
    try std.testing.expect(!a.eql(b));
    try std.testing.expect(!a.eql(c));
    try std.testing.expect(!a.eql(d));
    try std.testing.expect(a.eql(try unhintedKey(font, 7, .{ .cubic_tolerance = 0.25 })));

    const hint_a = try autohintGlyphKey(font, 7, .{});
    var hint_options: AutohintOptions = .{};
    hint_options.params.flat_ratio_x = 0.121;
    const hint_b = try autohintGlyphKey(font, 7, hint_options);
    try std.testing.expect(!hint_a.eql(hint_b));
    hint_options = .{};
    hint_options.blue_tolerance_em = 0.05;
    const hint_c = try autohintGlyphKey(font, 7, hint_options);
    try std.testing.expect(!hint_a.eql(hint_c));
}

test "key constructors reject invalid output options" {
    const font: FontKey = [_]u8{0x42} ** 16;
    try std.testing.expectError(
        error.InvalidOptions,
        unhintedKey(font, 7, .{ .cubic_tolerance = 0 }),
    );
    try std.testing.expectError(
        error.InvalidOptions,
        unhintedKey(font, 7, .{ .cubic_tolerance = std.math.nan(f32) }),
    );
    var hint: AutohintOptions = .{};
    hint.params.curve_steps = 0;
    try std.testing.expectError(error.InvalidOptions, autohintModelKey(font, hint));
}

test "TT geometry is uniform but advance identity preserves both axes" {
    const font: FontKey = [_]u8{0x11} ** 16;
    try std.testing.expectError(
        error.InvalidPpem,
        ttGlyphKey(font, 2, .{ .x_26_6 = 64, .y_26_6 = 128 }),
    );
    const a = try ttAdvanceKey(font, 2, .{ .x_26_6 = 64, .y_26_6 = 128 });
    const b = try ttAdvanceKey(font, 2, .{ .x_26_6 = 128, .y_26_6 = 64 });
    try std.testing.expect(!a.eql(b));
}

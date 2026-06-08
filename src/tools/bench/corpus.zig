//! Bench corpus: text strings, scenario enums, scene definitions.
//!
//! Pure data, no logic. Pulled out of the main `bench.zig` driver so
//! the data-shaped portion is independently navigable and a new
//! scenario or workload doesn't touch the rest of the file.

const snail = @import("snail");

pub const PRINTABLE_ASCII = blk: {
    var chars: [95]u8 = undefined;
    for (0..95) |i| chars[i] = @intCast(32 + i);
    break :blk chars;
};

pub const SHORT = "Hello, world!";
pub const SENTENCE = "The quick brown fox jumps over the lazy dog 0123456789";
pub const PARAGRAPH =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " ++
    "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " ++
    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.";
pub const ARABIC_TEXT = "\xd8\xa8\xd8\xb3\xd9\x85 \xd8\xa7\xd9\x84\xd9\x84\xd9\x87 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x85\xd9\x86 \xd8\xa7\xd9\x84\xd8\xb1\xd8\xad\xd9\x8a\xd9\x85";
pub const DEVANAGARI_TEXT = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87 \xe0\xa4\xb8\xe0\xa4\x82\xe0\xa4\xb8\xe0\xa4\xbe\xe0\xa4\xb0";
pub const THAI_TEXT = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5\xe0\xb8\x84\xe0\xb8\xa3\xe0\xb8\xb1\xe0\xb8\x9a";
pub const SIZES = [_]u32{ 12, 18, 24, 36, 48, 72, 96 };

pub const TextLine = struct {
    text: []const u8,
    x: f32,
    y: f32,
    size: f32,
    color: [4]f32 = .{ 1, 1, 1, 1 },
    style: snail.FontStyle = .{},
};

pub const TextWorkload = enum {
    short,
    sentence,
    paragraph,
    paragraph_sizes,

    pub fn name(self: TextWorkload) []const u8 {
        return switch (self) {
            .short => "Short string",
            .sentence => "Sentence",
            .paragraph => "Paragraph",
            .paragraph_sizes => "Paragraph x 7 sizes",
        };
    }
};

pub const text_workloads = [_]TextWorkload{ .short, .sentence, .paragraph, .paragraph_sizes };
pub const hinted_text_workloads = text_workloads;

pub const SceneKind = enum {
    text,
    rich_text,
    vector,
    mixed,
    multi_script,
    hinted_text,
    hinted_mixed,
    hinted_multi_script,

    pub fn name(self: SceneKind) []const u8 {
        return switch (self) {
            .text => "Text",
            .rich_text => "Rich text",
            .vector => "Vector paths",
            .mixed => "Mixed text + vector",
            .multi_script => "Multi-script text",
            .hinted_text => "Text (TT hinted)",
            .hinted_mixed => "Mixed text + vector (TT hinted)",
            .hinted_multi_script => "Multi-script text (TT hinted)",
        };
    }

    pub fn isHinted(self: SceneKind) bool {
        return switch (self) {
            .hinted_text, .hinted_mixed, .hinted_multi_script => true,
            else => false,
        };
    }

    pub fn needsText(self: SceneKind) bool {
        return switch (self) {
            .vector => false,
            else => true,
        };
    }

    pub fn needsVector(self: SceneKind) bool {
        return switch (self) {
            .vector, .mixed, .hinted_mixed => true,
            else => false,
        };
    }

    pub fn isMultiScript(self: SceneKind) bool {
        return switch (self) {
            .multi_script, .hinted_multi_script => true,
            else => false,
        };
    }

    pub fn isRich(self: SceneKind) bool {
        return self == .rich_text;
    }
};

pub const scene_kinds = [_]SceneKind{
    .text,
    .rich_text,
    .vector,
    .mixed,
    .multi_script,
    .hinted_text,
    .hinted_mixed,
    .hinted_multi_script,
};

pub const RenderMode = struct {
    aa: snail.SubpixelOrder,

    pub fn aaName(self: RenderMode) []const u8 {
        return subpixelOrderName(self.aa);
    }
};

pub const render_modes = [_]RenderMode{
    .{ .aa = .none },
    .{ .aa = .rgb },
};

pub const mode_scene_kinds = [_]SceneKind{ .text, .rich_text, .multi_script };

pub fn subpixelOrderName(order: snail.SubpixelOrder) []const u8 {
    return switch (order) {
        .none => "grayscale",
        .rgb => "subpixel rgb",
        .bgr => "subpixel bgr",
        .vrgb => "subpixel vrgb",
        .vbgr => "subpixel vbgr",
    };
}

pub fn effectiveAaLabel(order: snail.SubpixelOrder, supports_lcd: bool) []const u8 {
    if (order == .none) return "grayscale";
    if (supports_lcd) return subpixelOrderName(order);
    return "grayscale (LCD unavailable)";
}

pub const scene_text_lines = [_]TextLine{
    .{ .text = "Score: 12345  FPS: 60  Level 7", .x = 18, .y = 30, .size = 18 },
    .{ .text = "Health: 100%  Ammo: 42/120", .x = 18, .y = 56, .size = 18, .color = .{ 0.9, 0.35, 0.3, 1 } },
    .{ .text = SENTENCE, .x = 18, .y = 96, .size = 22 },
    .{ .text = PARAGRAPH, .x = 18, .y = 130, .size = 16, .color = .{ 0.92, 0.92, 0.92, 1 } },
};

pub const scene_multi_script_lines = [_]TextLine{
    .{ .text = "Latin: " ++ SENTENCE, .x = 18, .y = 34, .size = 18 },
    .{ .text = ARABIC_TEXT, .x = 18, .y = 72, .size = 22 },
    .{ .text = DEVANAGARI_TEXT, .x = 18, .y = 112, .size = 22 },
    .{ .text = THAI_TEXT, .x = 18, .y = 152, .size = 22 },
};

pub const rich_text_strings = [_][]const u8{
    "RICH",
    "gradient",
    "runs",
    "status",
    "HP",
    "83",
    "shield",
    "online",
    "per-letter",
    "snail",
    "alerts",
    "OK",
    "WARN",
    "CRIT",
};

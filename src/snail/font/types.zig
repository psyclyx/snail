/// A design-space coordinate for a variable font. Tags are OpenType axis
/// tags such as `wght`, `wdth`, or `opsz`; values are in the font's design
/// coordinate space.
pub const Variation = struct {
    tag: [4]u8,
    value: f32,
};

pub const VariationAxis = struct {
    tag: [4]u8,
    min_value: f32,
    default_value: f32,
    max_value: f32,
    hidden: bool,
};

pub const MetricTag = enum {
    subscript_x_size,
    subscript_y_size,
    subscript_x_offset,
    subscript_y_offset,
    superscript_x_size,
    superscript_y_size,
    superscript_x_offset,
    superscript_y_offset,
    strikeout_size,
    strikeout_offset,
    underline_size,
    underline_offset,
};

pub const Options = struct {
    /// Zero-based face in a TTC/OTC. Standalone fonts only accept zero.
    face_index: u32 = 0,
    /// Borrowed for the lifetime of the Font, just like the font bytes.
    variations: []const Variation = &.{},
};

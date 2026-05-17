pub const View = enum(u8) {
    normal,
    fill_mask,
    stroke_mask,
    layer_tint,
};

pub const BoundsOverlayOptions = struct {
    stroke_color: [4]f32 = .{ 1.0, 0.36, 0.24, 0.95 },
    stroke_width: f32 = 1.0,
    origin_color: [4]f32 = .{ 1.0, 0.78, 0.22, 0.95 },
    origin_size: f32 = 6.0,
};

fn paletteColor(index: usize) [4]f32 {
    const palette = [_][4]f32{
        .{ 0.27, 0.86, 0.98, 0.96 },
        .{ 0.98, 0.54, 0.29, 0.96 },
        .{ 0.58, 0.94, 0.43, 0.96 },
        .{ 0.95, 0.39, 0.77, 0.96 },
        .{ 0.99, 0.86, 0.28, 0.96 },
        .{ 0.56, 0.66, 0.98, 0.96 },
    };
    return palette[index % palette.len];
}

fn blendColor(a: [4]f32, b: [4]f32, t: f32) [4]f32 {
    return .{
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    };
}

pub fn paintColor(view: View, is_fill_layer: bool, shape_index: usize) [4]f32 {
    const base = paletteColor(shape_index);
    return switch (view) {
        .normal => .{ 0, 0, 0, 0 },
        .fill_mask => if (is_fill_layer) base else .{ 0.0, 0.0, 0.0, 0.0 },
        .stroke_mask => if (is_fill_layer) .{ 0.0, 0.0, 0.0, 0.0 } else base,
        .layer_tint => if (is_fill_layer)
            blendColor(base, .{ 0.15, 0.90, 0.98, 0.96 }, 0.45)
        else
            blendColor(base, .{ 0.98, 0.24, 0.82, 0.96 }, 0.55),
    };
}

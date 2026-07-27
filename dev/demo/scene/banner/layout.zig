//! Banner layout + palette.
//!
//! `Layout` is the per-frame slot layout (one Rect per card on a
//! reference canvas, scaled to fit). The palette + sizing constants
//! live here too so the text / vector helpers in banner.zig can
//! consult one source of truth.

const snail = @import("snail");

// Reference canvas the layout is sized to.
pub const REF_W: f32 = 1680;
pub const REF_H: f32 = 874;

// Light-theme palette.
pub const bg = [4]f32{ 0.96, 0.965, 0.975, 1.0 };
pub const text_color = [4]f32{ 0.10, 0.10, 0.14, 1.0 };
pub const muted = [4]f32{ 0.42, 0.46, 0.52, 1.0 };
pub const accent = [4]f32{ 0.15, 0.38, 0.85, 1.0 };
pub const surface = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
pub const border = [4]f32{ 0.84, 0.86, 0.89, 1.0 };

// Shared sizing — must match between text + vector helpers.
pub const card_pad: f32 = 20;
pub const heading_size: f32 = 15;
pub const sub_heading_size: f32 = 13;
pub const body_text_size: f32 = 22;
pub const body_line_h: f32 = 28;
pub const shape_sz: f32 = 56;
pub const shape_gap: f32 = 14;

pub const Layout = struct {
    scale: f32,
    canvas: snail.Rect,
    title: snail.Rect,
    styles: snail.Rect,
    decorations: snail.Rect,
    shaping: snail.Rect,
    scripts: snail.Rect,
    vectors: snail.Rect,
    snail_stage: snail.Rect,
};

pub fn buildLayout(w: f32, h: f32) Layout {
    const scale = @min(w / REF_W, h / REF_H);
    const margin = 48 * scale;
    const col_gap = 28 * scale;
    const row_gap = 24 * scale;

    const cx = (w - REF_W * scale) * 0.5;
    const cy = (h - REF_H * scale) * 0.5;

    // Title row
    const title_h = 100 * scale;
    const title = snail.Rect{ .x = cx + margin, .y = cy + margin, .w = REF_W * scale - margin * 2, .h = title_h };

    // Content row: 4 columns
    const content_top = title.y + title.h + row_gap;
    const content_w = REF_W * scale - margin * 2;
    const col_w = (content_w - col_gap * 3) / 4;
    const content_h = 300 * scale;

    const col_x = cx + margin;
    const styles = snail.Rect{ .x = col_x, .y = content_top, .w = col_w, .h = content_h };
    const decorations = snail.Rect{ .x = col_x + col_w + col_gap, .y = content_top, .w = col_w, .h = content_h };
    const shaping = snail.Rect{ .x = col_x + (col_w + col_gap) * 2, .y = content_top, .w = col_w, .h = content_h };
    const scripts = snail.Rect{ .x = col_x + (col_w + col_gap) * 3, .y = content_top, .w = col_w, .h = content_h };

    // Vectors row
    const vectors_top = content_top + content_h + row_gap;
    const vectors_h = REF_H * scale - (vectors_top - cy) - margin;
    const vectors_w = content_w * 0.55;
    const vectors = snail.Rect{ .x = col_x, .y = vectors_top, .w = vectors_w, .h = vectors_h };

    const snail_stage = snail.Rect{
        .x = col_x + vectors_w + col_gap,
        .y = vectors_top,
        .w = content_w - vectors_w - col_gap,
        .h = vectors_h,
    };

    return .{
        .scale = scale,
        .canvas = .{ .x = cx, .y = cy, .w = REF_W * scale, .h = REF_H * scale },
        .title = title,
        .styles = styles,
        .decorations = decorations,
        .shaping = shaping,
        .scripts = scripts,
        .vectors = vectors,
        .snail_stage = snail_stage,
    };
}

pub fn clearColor() [4]f32 {
    return bg;
}

const cluster_mod = @import("cluster.zig");
const types_mod = @import("types.zig");

const ShapedText = types_mod.ShapedText;

/// Add `em` of horizontal space at every cluster boundary, in em units.
///
/// Letter-spacing / tracking. Applied **between clusters**, so ligatures and
/// composed graphemes are not pulled apart. Each cluster's last glyph carries
/// the extra advance; each non-first cluster's glyphs have their x_offset
/// pushed right by the cumulative spacing.
///
/// Negative values tighten. Zero is a no-op.
pub fn track(shaped: *ShapedText, em: f32) void {
    if (em == 0 or shaped.glyphs.len == 0) return;
    var it = cluster_mod.clusters(shaped);
    var k: f32 = 0;
    while (it.next()) |cluster| {
        if (k != 0) {
            for (cluster.glyphs) |*g| g.x_offset += k * em;
        }
        cluster.glyphs[cluster.glyphs.len - 1].x_advance += em;
        k += 1;
    }
}

/// Shift every glyph vertically by `em`. Positive moves text up
/// (typographic convention: superscript), negative moves text down.
///
/// Does not touch advance, x_offset, or any horizontal metric.
pub fn shiftBaseline(shaped: *ShapedText, em: f32) void {
    if (em == 0) return;
    for (shaped.glyphs) |*g| g.y_offset -= em;
}

/// Add `em` of horizontal space after every cluster whose source bytes are
/// ASCII whitespace (space, tab, CR, LF). Subsequent clusters shift right by
/// the cumulative spacing.
///
/// `source` must be the same byte slice that produced `shaped`. Clusters
/// whose source range falls outside `source` are skipped.
pub fn spaceWords(shaped: *ShapedText, source: []const u8, em: f32) void {
    if (em == 0 or shaped.glyphs.len == 0) return;
    var it = cluster_mod.clusters(shaped);
    var cum: f32 = 0;
    while (it.next()) |cluster| {
        if (cum != 0) {
            for (cluster.glyphs) |*g| g.x_offset += cum;
        }
        if (isAsciiWhitespaceRange(source, cluster.source_start, cluster.source_end)) {
            cluster.glyphs[cluster.glyphs.len - 1].x_advance += em;
            cum += em;
        }
    }
}

fn isAsciiWhitespaceRange(source: []const u8, start: u32, end: u32) bool {
    if (end <= start or end > source.len) return false;
    for (source[start..end]) |b| {
        switch (b) {
            ' ', '\t', '\r', '\n' => {},
            else => return false,
        }
    }
    return true;
}

/// Round each cluster's total horizontal advance to the nearest multiple of
/// `em_step`. The rounded delta is baked into the cluster's last glyph's
/// x_advance; subsequent clusters shift by the cumulative delta.
///
/// Useful for terminal-style cell snapping: a 1-em-wide cell uses
/// `em_step = 1`; a half-em cell uses `em_step = 0.5`. Wide clusters round
/// to 2 (or more) cells naturally. `em_step <= 0` is a no-op.
pub fn snapAdvances(shaped: *ShapedText, em_step: f32) void {
    if (em_step <= 0 or shaped.glyphs.len == 0) return;
    var it = cluster_mod.clusters(shaped);
    var cum: f32 = 0;
    while (it.next()) |cluster| {
        if (cum != 0) {
            for (cluster.glyphs) |*g| g.x_offset += cum;
        }
        var cluster_adv: f32 = 0;
        for (cluster.glyphs) |g| cluster_adv += g.x_advance;
        const snapped = @round(cluster_adv / em_step) * em_step;
        const delta = snapped - cluster_adv;
        if (delta != 0) {
            cluster.glyphs[cluster.glyphs.len - 1].x_advance += delta;
            cum += delta;
        }
    }
}

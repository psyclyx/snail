const types_mod = @import("types.zig");

const ShapedText = types_mod.ShapedText;

/// A maximal run of consecutive glyphs sharing the same `source_start`.
/// Mirrors HarfBuzz's cluster contract: multiple glyphs in one cluster
/// indicates a ligature, a composed grapheme, or a reordering — caller-visible
/// "atom" of the source text.
pub const Cluster = struct {
    glyphs: []ShapedText.Glyph,
    source_start: u32,
    /// Exclusive end byte offset in the original source text. For non-final
    /// clusters this is the next cluster's `source_start`; for the final
    /// cluster it's the maximum `source_end` of glyphs in the cluster.
    source_end: u32,
};

pub const ClusterIterator = struct {
    glyphs: []ShapedText.Glyph,
    i: usize = 0,

    pub fn next(self: *ClusterIterator) ?Cluster {
        if (self.i >= self.glyphs.len) return null;
        const start = self.i;
        const source_start = self.glyphs[start].source_start;
        var end = start + 1;
        while (end < self.glyphs.len and self.glyphs[end].source_start == source_start) : (end += 1) {}

        var source_end: u32 = source_start;
        if (end < self.glyphs.len) {
            source_end = self.glyphs[end].source_start;
        } else {
            for (self.glyphs[start..end]) |g| {
                if (g.source_end > source_end) source_end = g.source_end;
            }
        }

        self.i = end;
        return .{
            .glyphs = self.glyphs[start..end],
            .source_start = source_start,
            .source_end = source_end,
        };
    }
};

/// Walk `shaped` by cluster. Returns an iterator yielding one `Cluster`
/// per HarfBuzz cluster boundary. The iterator borrows the glyph slice;
/// it stays valid as long as `shaped` does.
pub fn clusters(shaped: *const ShapedText) ClusterIterator {
    return .{ .glyphs = shaped.glyphs };
}

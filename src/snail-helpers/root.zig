//! snail-helpers — caches that wrap core snail primitives.
//!
//! Core snail intentionally owns no per-(font, glyph) memoization: every
//! `extractCurves` call re-walks the glyph outline. This is the right
//! default for one-shot rendering, but a long-running session (terminal,
//! editor, animation) wants to amortize. The helpers here are the
//! recommended pattern, but they are not in core — callers who want a
//! different policy (LRU, bounded, generation-tagged) can replace them
//! without touching the library.
//!
//! Boundary rule (enforced by build.zig): core snail cannot import
//! helpers; helpers may import core.

const std = @import("std");
const snail = @import("snail");

pub const UnhintedGlyphCache = @import("unhinted_glyph_cache.zig").UnhintedGlyphCache;
pub const HintedGlyphCache = @import("hinted_glyph_cache.zig").HintedGlyphCache;

test {
    _ = UnhintedGlyphCache;
    _ = HintedGlyphCache;
}

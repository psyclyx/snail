//! snail-helpers — opinionated conveniences layered over core snail primitives.
//!
//! Core snail intentionally exposes only the primitives needed to drive
//! its renderer: `Shape`, `RecordKey`, `Atlas`, `Fonts`, `shape()` →
//! `ShapedText`, `snap.*` helpers, `emit(...)`, and the backend draw
//! functions. Anything that can be expressed *on top of* those primitives
//! — caches, Picture-shaped containers, text-builder sugar — lives here.
//!
//! Callers with a custom scene-graph or memory policy can ignore this
//! module and target core directly. Callers who want batteries-included
//! conveniences (per-font glyph caches, a Picture-style flat shape array
//! with composition helpers, a shaped-run cache) reach for these.
//!
//! Boundary rule (enforced by build.zig): core snail cannot import
//! helpers; helpers may import core.

const std = @import("std");
const snail = @import("snail");

pub const UnhintedGlyphCache = @import("unhinted_glyph_cache.zig").UnhintedGlyphCache;
pub const HintedGlyphCache = @import("hinted_glyph_cache.zig").HintedGlyphCache;
pub const ShapedRunCache = @import("shaped_run_cache.zig").ShapedRunCache;
pub const Picture = @import("picture.zig").Picture;
pub const computePictureBBox = @import("picture.zig").computeBBox;

const text_picture_mod = @import("text_picture.zig");
pub const shapedRunPicture = text_picture_mod.shapedRunPicture;
pub const hintedShapedRunPicture = text_picture_mod.hintedShapedRunPicture;
pub const ShapedRunOptions = text_picture_mod.ShapedRunOptions;
pub const HintedShapedRunOptions = text_picture_mod.HintedShapedRunOptions;
pub const ShapedRunError = text_picture_mod.ShapedRunError;

test {
    _ = UnhintedGlyphCache;
    _ = HintedGlyphCache;
    _ = ShapedRunCache;
    _ = @import("picture.zig");
    _ = text_picture_mod;
}

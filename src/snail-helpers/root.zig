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
pub const GlyphAtlasCache = @import("glyph_atlas_cache.zig").GlyphAtlasCache;
pub const Picture = @import("picture.zig").Picture;
pub const computePictureBBox = @import("picture.zig").computeBBox;

const text_picture_mod = @import("text_picture.zig");
pub const shapedRunPicture = text_picture_mod.shapedRunPicture;
pub const hintedShapedRunPicture = text_picture_mod.hintedShapedRunPicture;
pub const ShapedRunOptions = text_picture_mod.ShapedRunOptions;
pub const HintedShapedRunOptions = text_picture_mod.HintedShapedRunOptions;
pub const ShapedRunError = text_picture_mod.ShapedRunError;
/// Unified run placement (supersedes the two builders above).
pub const placeRun = text_picture_mod.placeRun;
pub const RunPlacement = text_picture_mod.RunPlacement;
pub const HintMode = text_picture_mod.HintMode;
pub const RunSnap = text_picture_mod.RunSnap;

/// Batteries-included facade: producers + one GlyphAtlasCache + placeRun.
pub const TextAtlas = @import("text_atlas.zig").TextAtlas;

const path_shape_mod = @import("path_shape.zig");
pub const PathShapeCache = path_shape_mod.PathShapeCache;
pub const placeRect = path_shape_mod.placeRect;
pub const placeRectUniform = path_shape_mod.placeRectUniform;
pub const unitEllipsePath = path_shape_mod.unitEllipsePath;
pub const unitRectPath = path_shape_mod.unitRectPath;
pub const unitRoundedRectPath = path_shape_mod.unitRoundedRectPath;
pub const unitRoundedRectPathFor = path_shape_mod.unitRoundedRectPathFor;
pub const unitStrokeWidth = path_shape_mod.unitStrokeWidth;
pub const pathShapeKey = path_shape_mod.key;

test {
    _ = UnhintedGlyphCache;
    _ = HintedGlyphCache;
    _ = ShapedRunCache;
    _ = GlyphAtlasCache;
    _ = TextAtlas;
    _ = @import("picture.zig");
    _ = text_picture_mod;
    _ = path_shape_mod;
}

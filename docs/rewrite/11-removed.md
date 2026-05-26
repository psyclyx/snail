# What the rewrite deletes

The clean end state has no backwards-compatibility shims, no parallel
implementations, no deprecated re-exports. This file lists every public type
and module that the rewrite removes.

## Public types removed

### Text API surface

| Removed type | Replaced by |
|---|---|
| `TextAtlas` | `Atlas` |
| `TextBlob` | `Picture` |
| `TextBlobBundle` | (gone — caller owns picture storage) |
| `BlobInProgress` | (gone — caller composes shapes directly) |
| `TextBatch` | (internal: `[]u32` emit buffer; no longer public) |
| `TextAppend` | (gone — caller writes shapes directly) |
| `TextAppendResult` | (gone) |
| `TextPlacement` | (gone — caller composes transforms) |
| `TextDraw` | (gone — emit produces segments) |
| `TextBatchAppend` | (gone) |
| `TextBlobBundle.HintBinding` (none/borrowed/auto) | (gone — keys carry ppem) |
| `TextResourceKeys` | (gone — `RecordKey` is the only key) |
| `TextBlobResourceKeys` | (gone) |

### Hinting surface

| Removed type | Replaced by |
|---|---|
| `TrueTypeHintContext` | `Hinter` |
| `TrueTypeHintContextOptions` | `Hinter.Options` |
| `TrueTypeHintCacheFootprint` | `Hinter.Footprint` |
| `TrueTypeHintSizeKeyEntry`, `*Iterator` | `Hinter.SizeKeyEntry`, `*Iterator` |
| `TrueTypeHintGlyphKeyEntry`, `*Iterator`, `Key` | `Hinter.GlyphKeyEntry`, `*Iterator`, `Key` |
| `TrueTypeHintReject`, `RejectReason` | (gone — hint() returns error) |
| `TrueTypeHintedGlyph` | (gone — output is `GlyphCurves`) |
| `TrueTypePreparedHintGlyph`, `Run`, `Stats`, `PrepareRunOptions` | (gone — no "prepared run" concept) |
| `GlyphHintSnapshot`, `BuilderOptions` | (gone — atlas absorbs role) |
| `TextHintGlyphRecord` | (gone) |
| `TrueTypeHintMachine` | (internal: `font/tt_vm.zig`) |
| `TrueTypeGlyphHint`, `GlyphHintPatch` | (internal) |
| `TrueTypeExecutedGlyph` | (internal) |
| `TrueTypeHintPpem` | `HintPpem` |
| `TrueTypeBaseGlyphHint` | (internal) |
| `TrueTypeGlyphTopologyCache` | (internal) |
| `patchTrueTypeGlyphHint` | (internal) |

### Resource and scene surface

| Removed type | Replaced by |
|---|---|
| `Scene` | (gone — caller emits directly into DrawRecords) |
| `PreparedScene` | (gone) |
| `DrawList` | `DrawRecords` |
| `PathDraw` | (gone — emit consumes pictures) |
| `Override` (the old slice form on draws) | `Override` (per-instance on emitInstanced) |
| `ResourceManifest` | (gone — `Atlas` is the resource) |
| `PreparedResources` | `Binding` |
| `PreparedResourceRetirementQueue` | `RetirementQueue` |
| `ResourceCacheStats` | `PoolStats` |
| `ResourceFootprint`, `ResourceCapacityMode` | (gone) |
| `ResourceStamp` | (replaced by `page_generation` on `AtlasRecord`) |
| `ResourceKey` | `RecordKey` |
| `UploadAllocators` | `UploadAllocators` (kept; same type) |
| `ResourceUploadPlan`, `PendingResourceUpload` | (TBD — likely simpler equivalents) |

### Path surface

| Removed type | Replaced by |
|---|---|
| `PathPicture` | `Picture` |
| `PathPictureBuilder` | (gone — caller composes shapes directly) |
| `PathPictureDebugView` | (TBD: internal-only or removed) |
| `PathPictureBoundsOverlayOptions` | (gone) |
| `PathBatch` | (internal) |

### Other

| Removed type | Replaced by |
|---|---|
| `Atlas` (the old `CurveAtlas` alias) | `Atlas` (new value type) |
| `Font` (the old wrapper) | `Font` (new public type) |
| `tt` (re-export of TrueType internals) | (internal — `font/ttf.zig`) |

## Modules removed entirely

```
src/snail/text/atlas.zig
src/snail/text/blob.zig
src/snail/text/batch.zig
src/snail/text/glyph_atlas.zig
src/snail/text/hint_context.zig
src/snail/text/hint_snapshot.zig
src/snail/text/tt_hint.zig
src/snail/text/view.zig
src/snail/text/types.zig                  (most contents → picture.zig)
src/snail/text/config.zig                 (FaceConfig, etc. → font.zig)
src/snail/text.zig                        (root)
src/snail/scene.zig
src/snail/draw.zig                        (replaced by draw_records.zig)
src/snail/upload.zig
src/snail/resources/                      (whole directory)
src/snail/resources.zig
src/snail/resource_key.zig                (replaced by record_key.zig)
src/snail/paint_records.zig
src/snail/glyph_emit.zig
src/snail/path/picture.zig
src/snail/path/picture_compile.zig
src/snail/path/picture_debug.zig
src/snail/path/batch.zig
src/snail/path/tests.zig                  (replaced)
src/snail/api_tests.zig                   (replaced)
src/snail/path_picture_tests.zig
src/snail/torture_test.zig                (replaced)
```

Approximate LOC removed: 13,000.

## Modules kept (and unchanged or lightly updated)

```
src/snail/math/                           (unchanged)
src/snail/math.zig                        (unchanged)
src/snail/font/ttf.zig                    (unchanged — Font wraps this)
src/snail/font/opentype.zig               (unchanged)
src/snail/font/harfbuzz.zig               (unchanged)
src/snail/font/tt_*.zig                   (unchanged — Hinter wraps these)
src/snail/font.zig                        (rewritten as public Font)
src/snail/text/shape.zig                  (kept; shape() is still pure)
src/snail/text/cluster.zig                (kept; cluster iterator is pure)
src/snail/text/transform.zig              (kept; track/etc. are pure)
src/snail/image.zig                       (kept)
src/snail/paint.zig                       (kept)
src/snail/path/core.zig                   (kept — Path geometry)
src/snail/path/geometry.zig               (kept)
src/snail/coverage.zig                    (kept — algorithm only)
src/snail/target.zig                      (kept — DrawState etc.)
src/snail/render/coverage.zig             (kept — coverage algorithm)
src/snail/render/format/curve_texture.zig (kept — internal format)
src/snail/render/format/band_texture.zig  (kept)
src/snail/render/format/vertex.zig        (kept — 64-byte instance format)
src/snail/render/format/instance_emit.zig (kept — internal cursor)
src/snail/render/format/abi.zig           (kept)
src/snail/render/format/atlas/page.zig    (replaced by src/snail/page.zig)
src/snail/render/backend/                 (substantially updated, not deleted)
src/snail/thread_pool.zig                 (kept)
src/snail/backend_kind.zig                (kept)
```

## What stays public in root.zig

After the rewrite:

```
// Math.
Vec2, Mat4, BBox, Transform2D, Rect

// Sources.
Font

// Shaping.
ShapedRun, Glyph, ShapeOptions, OpenTypeFeature, FontStyle, FontWeight
SyntheticStyle, MissingGlyphReplacement
shape, itemize, clusters
track, shiftBaseline, spaceWords, snapAdvances

// Geometry production.
GlyphCurves
extractCurves            (on Font)
pathToCurves, strokeToCurves

// Hinting.
Hinter, HintPpem

// Paint and paths.
Paint, LinearGradient, RadialGradient, ImagePaint
StrokeStyle, StrokeCap, StrokeJoin, StrokePlacement, FillStyle, FillRule
Path

// Atlas.
RecordKey, ns
AtlasRecord
Atlas
PagePool

// Picture.
Picture, Shape, Override

// Emit.
DrawRecords, DrawSegment, Kind
emit, emitInstanced
wordBudget, segmentBudget

// Drawing.
Renderer, Binding, RetirementQueue
DrawState, DrawPass, TargetSurface, TargetEncoding
LinearResolve, CoverageTransfer, SubpixelOrder, RasterOptions
PixelRect, ResolveRegion, ResolveBackdrop, IntermediateFormat
pixelStep, snapToStep, snapPointToStep, snapRectToStep, snapLengthToStep

// Backend constructors.
CpuRenderer, Gl33Renderer, Gl44Renderer, Gles30Renderer, VulkanRenderer
BackendKind

// Stats.
PoolStats, PageStats

// Public ABI (for custom-shader path).
format.curve_texture
format.band_texture
format.layer_info
shader.glsl, shader.hlsl

// Image.
Image
```

Approximately 60 top-level exports, down from ~110 in the current code.

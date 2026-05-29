# Implementation plan

Phased build. Each phase ends at a coherent commit boundary. The build stays
green throughout (the old API keeps working until its final phase, then is
deleted in one go).

This plan assumes a single feature branch (`rewrite`) for phases 1-5; the
old code stays on `main` and consumers keep working. Phases 6+ happen on
`main` after the branch merges.

## Phase 0: foundation (committed)

Status: ✅ Done.

- `src/snail/record_key.zig` (130 lines, tested)
- `src/snail/curves.zig` (60 lines, tested)

These compile and pass tests but are not yet wired into `root.zig` or
consumed by any code.

## Phase 1: page pool and append-only pages

Status: ✅ Done. Two commits:
- "rewrite: add AtlasPage, PagePool, AtlasRecord foundation"
- "rewrite: add Atlas value type with combine, extend, compact"

Built sibling types alongside the existing
`render/format/atlas/page.zig` (kept intact for the old API). All
tests pass, including multi-threaded reserve, generation-on-recycle,
combine remap, extend dedup, and compact key preservation. `extendWith`
is the one item from the spec deferred to Phase 3 (it composes with
the provider trait that the hinter wraps).

## Phase 2: curves producers

Status: ✅ Done. Three commits:
- "rewrite: add Font.extractCurves producer"
- "rewrite: add pathToCurves and strokeToCurves producers"
- "rewrite: add Hinter curves producer"

`Font.extractCurves` lives on the existing `Font` public type rather
than a fresh `font.zig` — the public API surface for outline metrics
is unchanged, and the new extractor sits next to its peers.
`paths.zig` and `hinter.zig` are new top-level modules. All three
producers funnel through `buildCurveTexture` / `buildGlyphBandData`
so the curve+band byte format is shared verbatim with the existing
TextAtlas path. Byte-for-byte equivalence is tested for the font
producer; the others reuse the same packing path implicitly.

The `Hinter` deferred a few inspection helpers (byteFootprint,
size/glyph key iterators, providerAt) to Phase 3 / later; the core
mechanism — per-ppem cached VM producing `GlyphCurves` — is in place.

## Phase 3: picture, emit, draw records

Status: ✅ Done. Four commits' worth of changes landed:
- `src/snail/shape.zig` (Shape + Override value types).
- `src/snail/picture.zig` (empty/from/concat/append/transformed/tinted).
- `src/snail/draw_records.zig` (DrawRecords, DrawSegment, Kind,
  Binding, mergeIfAdjacent).
- `src/snail/emit.zig` (emit, emitInstanced, wordBudget, segmentBudget).

The packed instance format in `src/snail/render/format/vertex.zig`
(64-byte instance) is unchanged; emit goes through
`generateGlyphVerticesTransformedTinted` so the heterogeneous case is
byte-for-byte equivalent (verified in `emit.zig`'s
"matches generateGlyphVerticesTransformedTinted byte-for-byte" test).
Coalescing of adjacent same-binding segments and multi-binding
separation are both covered. `shapedRunKeys` / `shapedRunPicture` are
deferred to Phase 6 (they connect the new picture layer to the existing
shape() function, which is a migration concern not a foundation one).

The replicated layout in `emitInstanced` is N shape blocks (each a
16-word Instance with identity tint) followed by M override blocks
(8 words: 6 f32 transform + packed u8x4 tint + 1 reserved). The
backend that consumes this lands in Phase 5.

## Phase 4: rewire one backend (CPU)

Status: 🟢 Substantially complete end-to-end. Demo content recognizable
on the new API; pixel parity still unwound.

CPU-side machinery (committed):
- `CpuPreparedPages` (`src/snail/cpu_upload.zig`) is the CPU-side
  "upload": per-layer `PreparedAtlasPage` built from the new
  `AtlasPage`'s byte buffers via `PreparedAtlasPage.initFromView`,
  plus the atlas's `layer_info_data` baked into a single
  `LayerInfoEntry`. Returns a `Binding`.
- `drawCpu` (`src/snail/cpu_draw.zig`) walks `DrawRecords.segments`,
  matches each segment's `Binding.pool` to a caller-supplied cache,
  and dispatches through `CpuRenderer.drawTextPrepared`.
  - Heterogeneous segments: direct dispatch.
  - Replicated segments: materializes N×M composed instances in a
    scratch buffer (transform-compose + tint override) then dispatches.
- `Atlas` (`src/snail/atlas.zig`) carries paint records in
  byte-compatible legacy format (`layer_info_data` + `paint_lookup`),
  populated automatically by `Atlas.from` when entries carry
  `.paint`. Combine/extend carry forward both.
- `emit` (`src/snail/emit.zig`) checks `atlas.lookupPaintRecord`
  per shape and encodes a `.path` special-layer instance when set,
  via the existing `generatePathRecordVerticesTransformedTinted`.
- `shapedRunPicture` (`src/snail/text_picture.zig`) bridges
  `TextAtlas.shapeText` output to the new `Picture` model.
- New public surface added to `root.zig` alongside the legacy types.

Picture construction layer:
- `shapedRunPicture` (`src/snail/text_picture.zig`) bridges
  `TextAtlas.shapeText` output to the new `Picture`. COLR base
  glyphs expand into N shapes when `colr_fonts` is supplied (per
  Q5). Foreground sentinel falls back to the run color.
- `Font.colrLayers` / `colrLayerCount` re-exported on the public
  wrapper so callers can drive the corresponding curve extraction.
- No PictureBuilder. Callers compose primitives directly:
  build a `Path`, call `pathToCurves` / `strokeToCurves`, construct
  `Atlas.Entry` + `Shape` inline. The screenshot demo demonstrates
  this for a card + ellipse.

Demo (committed):
- `src/demo/screenshot_new.zig` + `zig build run-screenshot-new`
  exercises the new path end-to-end:
  - Rounded-rect card background (path fill + stroke)
  - Wordmark with linear-gradient paint record
  - Tagline with shaped text
  - Multi-script row (Hello + Arabic + Devanagari + Thai + emoji)
    including COLR-expanded color emoji glyphs
  - Radial-gradient ellipse placeholder for the vector snail body
- Single pool serves both text and path atlases via the cache's
  `layer_info_slots` generation index.

What's NOT yet in Phase 4 (known limitations):
- Full banner_snail vector content (currently one placeholder
  ellipse). Just needs more inline `pathToCurves`/`strokeToCurves`
  calls — no missing mechanism, just demo work.
- Pixel parity with the legacy baseline. Differences come from:
  per-face em scaling (emoji nominal-em differs from Latin; the demo
  uses a uniform em across all faces), subtle gradient hue (legacy
  did sRGB→linear once in writeTga's GL path; we round-trip through
  Atlas paint records), and font ascender alignment.
- Image paints. Atlas supports the `.image` tag in the paint record
  format but the atlas-side `paint_image_records` slot isn't
  populated yet, and CpuPreparedPages doesn't carry images.

Investigated and resolved during 2026-05-29 session:
- "Arabic visual order" — `shapedRunPicture` places each shaped
  glyph at byte-identical pixel coordinates to the legacy
  `appendShapedSlice`; the prior cropped-screenshot observation was
  dominated by `.rgb` subpixel fringing in the new demo vs `.none` in
  the legacy demo. screenshot_new now uses `.none` to match.

## Phase 5: rewire GPU backends

Three sub-phases, one per backend family.

Phase 4's CPU work showed the shape: a `*PreparedPages` per pool that
holds backend-specific resident state, an `upload(atlas) -> Binding`
that pushes deltas, and a `draw(state, records, pools)` that walks
the new `DrawRecords.segments`. Each GPU backend follows that
pattern with its own resident-state shape (texture handles, fences,
descriptor sets).

### 5a. GL 3.3 + GL 4.4

Status: 🟡 Not started. Plan and risk surface:

The existing `gl/resources.zig` (~1150 LOC) and `gl/state.zig`
(~840 LOC) are intricately woven through `CurveAtlas`-typed
`AtlasSlot`s, refcounted `AtlasTextureBank` generations, and a
decision matrix (clear / rebuild / append_overflow_bank /
append_pages) that hangs off `ResourceManifest`. The new model is
simpler — pages are append-only with stable `layer_index`, generation
flips only on recycle — but a clean refactor requires rewiring all
five of those concepts plus the legacy `uploadAtlases` /
`drawTextPrepared` API surface that demos and `run-backend-compare`
depend on until Phase 6.

Concretely, refactor-in-place means:
- Change `AtlasSlot`'s element type from `CurveAtlas` to `Atlas`.
- Replace `upload_common.decideAtlasUpload` with PagePool's "any
  page where `usedWords > uploadedWords`" delta-push model.
- Retire (or repurpose) `AtlasTextureBank` — pool generation
  replaces bank generation; layer_index replaces bank-local layer.
- Adapt `bindProgramState` / `drawTextPrepared` to consume the new
  `Binding` (one pool ref + generation) rather than the
  `texture_layer_base` + bank-id encoding.
- Keep legacy `uploadAtlases` working until Phase 6 by adapting at
  the boundary: build a temporary `PagePool` + `Atlas` from each
  legacy `CurveAtlas` at upload time and dispatch through the new
  path.

Shaders unchanged (they still consume the 64-byte instance format).

Validation: `run-backend-compare` runs CPU vs GL vs GLES vs Vulkan
headlessly and asserts pixel match — that's the gate per backend
once the legacy adapter at the upload boundary is in place.

Estimated effort: 2-3 days of focused work, dominated by the
slot/bank refactor and adapting the legacy decision logic. Not
attempted in this session.

### 5b. GLES30

Mirror of 5a for the ES profile.

### 5c. Vulkan

Pipeline + descriptor sets need to be updated to bind from `PagePool`
texture handles. Add fence-based retirement for `PagePool` free-list
returns.

End-of-phase commit per backend: "rewrite: <backend> on new API."

## Phase 6: migrate consumers, delete old API

Files to delete (after every consumer is migrated):
- `src/snail/text/atlas.zig` (TextAtlas)
- `src/snail/text/blob.zig` (TextBlob, TextBlobBundle, BlobInProgress)
- `src/snail/text/batch.zig`
- `src/snail/text/glyph_atlas.zig`
- `src/snail/text/hint_context.zig` (replaced by hinter.zig)
- `src/snail/text/hint_snapshot.zig`
- `src/snail/text/tt_hint.zig` (moved into hinter.zig)
- `src/snail/text/view.zig`
- `src/snail/text/types.zig` (most contents moved to picture.zig, etc.)
- `src/snail/text/config.zig` (parts move to font.zig)
- `src/snail/text.zig`
- `src/snail/scene.zig`
- `src/snail/draw.zig` (replaced by draw_records.zig)
- `src/snail/upload.zig`
- `src/snail/resources/*` (entire directory)
- `src/snail/resources.zig`
- `src/snail/resource_key.zig` (replaced by record_key.zig)
- `src/snail/paint_records.zig` (logic moves into picture.zig + emit)
- `src/snail/glyph_emit.zig`
- `src/snail/path/picture.zig`
- `src/snail/path/picture_compile.zig`
- `src/snail/path/picture_debug.zig`
- `src/snail/path/batch.zig`
- `src/snail/path_picture_tests.zig`
- `src/snail/api_tests.zig` (replaced by phase-3 tests)
- `src/snail/torture_test.zig` (replaced)

Files to update:
- `src/snail/root.zig` — keep only new public types.
- Tests — migrate to new API.
- Demos — migrate to new API.

End-of-phase commit: "rewrite: delete obsolete API surface; clean end state."

## Phase 7: C API regeneration

The C API (`src/snail/c_api/*`) is generated from Zig types via the
existing `build-generate-c-api` step. After phase 6, regenerate:

```sh
zig build generate-c-api
zig build check-c-api
```

The headers will differ substantially. Update `include/snail/snail.h`
template and `src/snail/c_api/handles.zig` to match the new types.

End-of-phase commit: "rewrite: regenerate C API for new public surface."

## Phase 8: documentation update

- Update `README.md` examples to the new API.
- Update `CHANGELOG.md` with the breaking change notice.
- Update this docs directory's `README.md` to point at the new code.

## Validation gates per phase

After each phase:
- `zig build test` passes.
- `zig build run-screenshot` produces a pixel-identical TGA to the
  pre-phase baseline (or, if not identical, the diff is reviewed).
- `zig build run-backend-compare` passes (cross-backend parity).
- `zig build run-bench` shows no regression > 10% from baseline.

If any gate fails, the phase doesn't merge.

## Estimated effort

Conservative estimates per phase (one focused engineer, no surprises):

| Phase | Estimated effort |
|---|---|
| 0 | ✅ 1 hour (done) |
| 1 | 2-3 days |
| 2 | 2-3 days |
| 3 | 2-3 days |
| 4 | 2-3 days |
| 5a | 2-3 days |
| 5b | 1-2 days |
| 5c | 3-4 days |
| 6 | 1-2 days |
| 7 | 1-2 days |
| 8 | 1 day |

Total: ~3-4 weeks. Add ~50% for shader debugging, format edge cases,
backend parity surprises.

## Risks

1. **The existing curve+band format is more intertwined with the existing
   atlas builder than expected.** The new `AtlasPage` may need to embed
   more format-specific knowledge than the design suggests, or the format
   helpers may need surgery to accept caller-driven page byte budgets.
   Mitigation: Phase 1 explicitly verifies byte-for-byte equivalence
   with the existing producers' output.

2. **CPU renderer's inner sampling loop might depend on
   atlas-page-pointer-stability in ways that don't survive the new
   refcount-driven retirement model.** Mitigation: Phase 4 carefully
   reviews `cpu/coverage.zig` for assumed page lifetime.

3. **Vulkan retirement queue interactions with `Hinter` cache eviction.**
   If a user calls `Hinter.evictPpem` while a frame is in flight that
   refers to atlas pages built from those hints, the pages must still
   live until the frame completes. Mitigation: pages outlive hint
   evictions naturally because the atlas (not the hinter) owns the page
   refs; verify this in Phase 2.

4. **shoal's consumer code is intricate.** Migrating it is part of
   Phase 6's effort estimate but may surface API gaps. Mitigation: walk
   shoal's `renderer.zig` against the new API one function at a time
   before declaring Phase 6 done.

## What this plan doesn't include

- A WebGPU backend (could be added post-rewrite).
- A WASM target (unchanged from current).
- Profiling/tracing improvements (separate work).
- Path-related improvements like stroke join variants (separate work).

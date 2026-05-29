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

Status: 🟡 Plumbing landed (MVP). Two commits:
- "rewrite: add CpuPreparedPages for CPU-side page preparation"
- "rewrite: add drawCpu entry consuming DrawRecords and CpuPreparedPages"

`CpuPreparedPages` (in `src/snail/cpu_upload.zig`) is the CPU-side
"upload": it builds a per-layer `PreparedAtlasPage` from the new
`AtlasPage`'s byte buffers, reusing `cpu_resources.PreparedAtlasPage`
(promoted to `initFromView(anytype)` so it consumes both the legacy
and new page shapes). `cache.upload(atlas)` returns a `Binding`.

`drawCpu` (in `src/snail/cpu_draw.zig`) walks `DrawRecords.segments`,
matches each segment's `Binding.pool` to a caller-supplied cache, and
dispatches per-instance through the existing
`CpuRenderer.drawTextPrepared`. Only `.heterogeneous` segments are
supported; the replicated path needs per-shape × per-override outer
product materialization on the CPU side and is deferred.

What's NOT yet done in Phase 4:
- The CPU rasterizer still consumes `prepared.atlas_pages` indexed by
  a flat texture-layer base of `0`. Multi-pool scenes work (one cache
  per pool, one segment per pool) but a single `PreparedResources`
  spanning multiple pools is not built.
- Path / paint / COLR special-layer rendering is *not* wired through
  the new path. The new draw entry assumes `local_paint == null` on
  each shape and dispatches only the regular text path.
- `run-screenshot` still runs through the legacy demo path; migration
  of the demo to the new API is part of Phase 6.

## Phase 5: rewire GPU backends

Three sub-phases, one per backend family:

### 5a. GL 3.3 + GL 4.4

Existing `src/snail/render/backend/gl/state.zig` and
`src/snail/render/backend/gl/resources.zig` know how to upload texture
arrays and bind them. Adapt to:
- Take a `PagePool` instead of an internal cache.
- Upload pages from the pool's CPU side, push delta when `data_len > uploaded_len`.
- Walk `DrawRecords.segments` from emit instead of the old segments.

Shaders unchanged (they still consume the 64-byte instance format).

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

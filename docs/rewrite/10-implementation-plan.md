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

Files to write:
- `src/snail/page.zig` — `AtlasPage` with append-only bytes, atomic
  `data_len`, refcount, generation.
- `src/snail/page_pool.zig` — `PagePool` with explicit capacity, free
  list, stats tracking.
- `src/snail/atlas.zig` — `Atlas` with `empty`, `from`, `combine`,
  `extend`, `extendWith`, `lookup`, `compact`, `deinit`.
- `src/snail/atlas_record.zig` — `AtlasRecord`.

The `AtlasPage` here is structurally different from the existing
`src/snail/render/format/atlas/page.zig`. Build it as a sibling type;
keep the existing one for the old API.

Tests:
- Append concurrency (two threads extending atlases sharing a tail page).
- Combine union semantics.
- Extend with conflicting keys (existing wins).
- Compact preserves keys.
- Refcount-based page reclamation.

Builds on Phase 0. Does not touch any existing code. End-of-phase commit:
"rewrite: add Atlas, AtlasPage, PagePool foundation types."

## Phase 2: curves producers

Files to write:
- `src/snail/font.zig` (new) — public `Font` with `init`, `extractCurves`,
  metrics queries. Wraps `src/snail/font/ttf.zig` internally.
- `src/snail/paths.zig` — `pathToCurves`, `strokeToCurves`.
- `src/snail/hinter.zig` — simpler `Hinter` (see [05-hinting.md](05-hinting.md)).
  Wraps existing `src/snail/font/tt_*.zig` VM verbatim.

Each producer returns the unified `GlyphCurves` type. Tests verify the
output renders identically to the existing producers' outputs (byte-for-byte
of curve_bytes and band_bytes).

End-of-phase commit: "rewrite: add curves producers (font, paths, hinter)."

## Phase 3: picture, emit, draw records

Files to write:
- `src/snail/shape.zig` — keep existing `shape()` function but expose it
  cleanly; add `shapedRunKeys`, `shapedRunPicture`.
- `src/snail/picture.zig` — `Picture` with monoidal ops and sub-picture
  manipulation.
- `src/snail/emit.zig` — `emit`, `emitInstanced`, `wordBudget`,
  `segmentBudget`.
- `src/snail/draw_records.zig` — `DrawRecords`, `DrawSegment`, `Kind`.

The packed instance format in `src/snail/render/format/vertex.zig`
(64-byte instance) is unchanged. The emit primitives write into that
format. Shaders don't need changes.

Tests:
- Emit produces same bytes as existing `appendTextDrawIntoBatch` for
  equivalent inputs.
- Coalescing of adjacent same-binding segments.
- Multi-atlas pictures (one emit call per atlas).

End-of-phase commit: "rewrite: add Picture, emit primitives, DrawRecords."

## Phase 4: rewire one backend (CPU)

The CPU renderer's existing `draw` walks `DrawRecords`-shaped data already.
Adapter work:
- `renderer.createPagePool(.{...})` creates the CPU pool (CPU pool has
  no GPU backing — pages are CPU-resident byte slices).
- `pool.upload(allocs, &atlas)` returns a `Binding` containing the pool ref.
- `renderer.draw(state, records, &.{&pool})` does the validation and
  walks segments.

The CPU renderer's coverage evaluation already consumes curve and band
bytes via the existing format helpers; switching it to read from the
new `PagePool` pages requires updating where it looks up curve data, but
the inner sampling loop is unchanged.

End-of-phase commit: "rewrite: CPU backend on new API; one demo green."

This is the first phase where a demo can run end-to-end on the new API.
The chosen demo is `run-screenshot` (CPU-only, offscreen, deterministic).

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

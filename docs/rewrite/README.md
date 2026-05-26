# snail rewrite — design and implementation plan

This directory contains the design for a value-oriented rewrite of snail's public
API. The current implementation has a working renderer but a public surface
shaped by incremental growth — `TextAtlas`, `TextBlob`, `TextBlobBundle`,
`BlobInProgress`, `Scene`, `PreparedScene`, `DrawList`, `ResourceManifest`,
`PreparedResources`, `GlyphHintSnapshot`, and 25+ TrueType hint types — that
overlaps and complects in ways the new design corrects.

The rewrite keeps the rendering algorithm (Slug coverage), the curve+band atlas
format, and the existing shaders. It replaces the API layer and the resource
management story with a small set of value types that compose monoidally,
explicit GPU memory ownership, and a clean separation between content
(`Picture`), identity (`RecordKey`), and storage (`Atlas`).

## Reading order

1. [00-principles.md](00-principles.md) — the non-negotiable design rules
2. [01-value-types.md](01-value-types.md) — `RecordKey`, `AtlasRecord`, `GlyphCurves`, `Shape`, `Override`
3. [02-atlas-and-pages.md](02-atlas-and-pages.md) — `Atlas`, `AtlasPage`, `PagePool`, GPU upload, retirement
4. [03-picture-and-emit.md](03-picture-and-emit.md) — `Picture`, two emit primitives, `DrawRecords`, shader specialization
5. [04-curves-producers.md](04-curves-producers.md) — `font.extractCurves`, `pathToCurves`, `strokeToCurves`
6. [05-hinting.md](05-hinting.md) — `Hinter`, hinted ppem lifecycle, cache control
7. [06-compaction.md](06-compaction.md) — fragmentation stats, `Atlas.compact`, page reuse
8. [07-subpixel.md](07-subpixel.md) — subpixel coverage as a draw-state shader variant
9. [08-custom-shader.md](08-custom-shader.md) — first-class consumer of the same data
10. [09-workloads.md](09-workloads.md) — how each target workload composes the primitives
11. [10-implementation-plan.md](10-implementation-plan.md) — phased build plan
12. [11-removed.md](11-removed.md) — what the rewrite deletes
13. [12-open-questions.md](12-open-questions.md) — unresolved holes flagged for resolution before commit

## Status

As of this document being written:
- Design is finalized through review iterations (workload review, Hickey-style
  architectural review, compaction model).
- Two foundation files are committed: `src/snail/record_key.zig` and
  `src/snail/curves.zig`. Both are standalone — not yet imported into the
  public API or consumed by existing code.
- The remainder of the work is described in
  [10-implementation-plan.md](10-implementation-plan.md).

# Open questions

Holes the design acknowledges but does not yet answer. Each needs to be
resolved during implementation, ideally before the corresponding phase.

## Q1: `Atlas.extend` lookup table semantics

**The question.** When `extend` produces a new atlas, does the new atlas's
lookup hashmap share structure with the old, or is it a deep copy?

**Why it matters.** Deep copy is O(N) per extend; for high-frequency
extension (animation, streaming), this is hot. Persistent hashmap (HAMT-style
overlay) is O(log N) and shares structure with the old.

**Trade-offs.**
- Deep copy: simple, no dependencies, predictable performance, no per-frame
  allocation churn beyond the lookup copy itself.
- HAMT: more code, requires writing/importing a persistent map for Zig (none
  in stdlib), but the right answer for animation workloads.

**Recommendation.** Ship Phase 1 with deep-copy lookups. Benchmark a churn
workload (animation, zoom scrubbing). If extend dominates frame time, add
a HAMT-backed lookup as an internal optimization — the API doesn't change.

**Phase to resolve.** Phase 1, before merging the rewrite branch.

## Q2: Clip / scissor support

**The question.** Where does per-draw clipping live? `DrawState.scissor_rect`?
`Picture.clip(rect)`? Multiple draws with different scissors?

**Why it matters.** shoal uses scissor today (raw `glScissor`). Without
snail-side support, callers either drop down to raw GL (gross — defeats the
abstraction) or simulate clipping by emitting only in-bounds shapes (CPU cost).

**Trade-offs.**
- `DrawState.scissor_rect: ?PixelRect`: simple, matches today's API
  shape, fits the "subpixel as draw-state" pattern. Per-draw, not per-segment.
- `Picture.clip(rect)`: per-shape, allows different clips for different parts
  of the same draw. More flexible but more code.

**Recommendation.** Add `DrawState.scissor_rect`. Per-shape clipping can be
emulated by splitting into multiple draws. If real workloads need per-shape
clip, add it later as a `Shape.clip: ?Rect` field.

**Phase to resolve.** Phase 4 (CPU backend), to be exercised by shoal in
Phase 6.

## Q3: World-space text (multi-MVP)

**The question.** Can one frame have many different MVPs cheaply? A game
HUD drawing 50 world-space signs needs 50 different view matrices.

**Status.** "Multiple `draw()` calls with different `DrawState`s" works
correctness-wise. Performance depends on backend; Vulkan with descriptor
sets is cheap, GL is more expensive.

**What's unanswered.** Whether the design should support per-instance MVPs
(via `Override.transform` being a 3D matrix) or per-segment MVPs (one
`DrawState` per group of same-MVP shapes).

**Recommendation.** Ship without per-instance 3D transforms. If a game
workload pushes on it, add `Override3D` and `emitInstanced3D` as parallel
primitives — doubles `Override` size from 40 bytes to ~70, so a separate
type is justified.

**Phase to resolve.** Post-Phase 8; not a blocker for the rewrite.

## Q4: `PagePool` capacity sizing

**The question.** Pool capacity is fixed at creation. How does a caller
handle workloads where N is data-driven (e.g., a PDF viewer that doesn't
know how many fonts and glyphs it'll see)?

**Status.** Documented as "explicit but unhelpful." The caller either
oversizes the pool, or handles `error.OutOfLayers` by reconstructing the
pool with more capacity (re-upload everything).

**What's unanswered.** Whether to provide a documented recovery pattern
(e.g., `pool.grow(new_capacity)` that rebuilds GPU resources and copies
data) or leave it entirely to the caller.

**Recommendation.** Ship without `grow`. Document the recovery pattern
(deinit old pool, init new pool, re-upload all atlases — bindings change
generation, so all DrawRecords need re-emit). If real workloads hit this
often, add `grow` later.

**Phase to resolve.** Phase 1, with explicit error documentation.

## Q5: COLR layer fan-out

**The question.** Color emoji glyphs have multiple layers (one per color).
Today's code expands one logical glyph into N instances at append time
(`textBlobGpuInstanceBudgetForAtlas`). Where does this live in the new
design?

**Recommendation.** At the picture-construction layer. `buildTextPicture`
expands a COLR glyph into N shapes (one per layer), each with its own
`local_color`. Each shape references a different `(font_id, layer_glyph_id)`
unhinted-glyph key.

A caller who wants the expansion to happen automatically uses
`buildTextPicture`. A caller who wants control (e.g., a custom-shader user
who handles color compositing differently) decomposes manually.

**Phase to resolve.** Phase 3 (Picture construction).

## Q6: Image-paint slot management

**The question.** Image paints reference image pixel data. In the current
code, that's `*const Image`. In the new design, paint records are entries
in an atlas (or in a separate `GpuImageArray`). How does the user manage
image lifetimes vs. atlas lifetimes?

**Recommendation.** Image paint records live in the same atlas as curve
records, under `ns.paint_record`. The atlas builder takes the image's
pixel bytes and copies them into a separate "image layer" of the pool
(or into the layer-info texture, depending on size).

This means images are subject to the same refcount-based reclamation as
curves. Drop the atlases that reference an image; its bytes go.

**Phase to resolve.** Phase 1 / Phase 3.

## Q7: Hinter cache eviction vs. in-flight Vulkan frames

**The question.** If a user calls `Hinter.evictPpem(p)` while a Vulkan frame
in flight references atlas pages whose curves were produced from that ppem,
is anything broken?

**Recommendation.** No. The Hinter's cache is the *VM state + curve-point
cache* — it produces `GlyphCurves` on demand, but those `GlyphCurves` are
*copied* into atlas page bytes when added via `Atlas.from` / `extend`. The
atlas page bytes live in the `PagePool`, refcounted by atlases. Evicting
from the Hinter doesn't touch the pool.

The atlas page is alive as long as some atlas holds a ref. The retirement
queue handles in-flight Vulkan frames. So evicting from the hinter is safe
at any time.

**Phase to resolve.** Documented in Phase 2 with a test.

## Q8: `emit` validation of cross-atlas pictures

**The question.** A `Picture` whose shapes reference keys from multiple
atlases must be emitted via multiple `emit()` calls, one per atlas. What
happens if a caller passes such a picture with only one atlas?

**Recommendation.** `emit` returns `error.MissingRecord` for any shape
whose key doesn't resolve. The `EmitResult` includes the shape index that
failed. Callers either:
- Split their picture by atlas before emitting (preferred — caller intent
  is explicit).
- Try emit; on `MissingRecord`, retry with a different atlas. (Reasonable
  for systems where the caller doesn't know which atlas has which keys.)

**Phase to resolve.** Phase 3 (emit primitives).

## Q9: Synthetic styles (faux-bold, skew) placement

**The question.** Today's `FaceConfig` carries `SyntheticStyle { embolden,
skew_x }`. In the new design, where do these live? On `Font`? On `Hinter`?
On `Shape`?

**Recommendation.** On `Shape`. `Shape.embolden: f32` and
`Shape.skew_x: f32`, both with defaults of 0. The emit primitive applies
them at vertex time (one extra position for embolden, transform shear for
skew).

This keeps `Font` immutable and free of style state, lets a single font
produce both regular and faux-bold output, and matches the per-instance
concept.

**Phase to resolve.** Phase 3 (Shape definition).

## Q10: Backend feature parity

**The question.** Some backends today support features others don't (e.g.,
GL 4.4 has bindless textures, GLES30 doesn't). Does the new `PagePool` mask
these differences, or does the caller choose a backend that supports their
needs?

**Recommendation.** The pool API is the same across backends. Backend
constructors take their own options for backend-specific tuning. The
pool's capacity and behavior are uniform; what differs is performance
characteristics and texture array limits.

**Phase to resolve.** Phase 5 (per-backend), documented per backend.

## Q11: `Picture.bbox` recomputation

**The question.** When a picture is constructed via `concat` / `append` /
`transformed`, its bbox needs updating. Is it recomputed eagerly on
construction, or lazily on first query?

**Recommendation.** Eager. The bbox is needed by emit for culling and
draw-record bounds; lazy computation would force emit to recompute or
accept stale values. Construction cost (O(shapes)) is paid once per
picture; emit happens many times per frame. Eager wins.

**Phase to resolve.** Phase 3.

## Q12: `Atlas.compact` and `PagePool` mismatch

**The question.** `compact` allocates new pages from a `PagePool`. Which
pool? The same one the original atlas used, or a caller-provided one?

**Recommendation.** Same one. The atlas tracks its pool; `compact(allocator)`
uses the recorded pool. No flexibility to compact "into a different pool"
because that's a different operation (atlas migration) the design doesn't
provide.

If a caller really wants to migrate to a different pool, they decompose:
walk records, extract their byte equivalents (via the `extractRecord`
helper from `compact`'s internals), build new entries, call
`Atlas.from(new_pool, entries)`. This is a rare enough operation to be
caller code rather than a library primitive.

**Phase to resolve.** Phase 1.

---

These twelve questions are the design's honest debt. They need to be
addressed during the relevant phase, but none are show-stoppers for the
overall approach. The core decisions — value-oriented `Atlas`, key-based
`Picture`, append-only pages, monoidal composition, two emit primitives —
are stable.

# Design principles

These rules are non-negotiable for the rewrite. Every decision in the rest of
the design follows from them. Where the existing code breaks one of these
rules, the rewrite corrects it.

## 1. Values, not containers

A blob is a glyph list. A scene is a record list. An atlas is a curve store.
None of these owns a builder, an arena, or a state machine. Operations on
these values return new values; the input is untouched.

The current code has `TextBlobBundle` (an arena + builder state + freeze flag +
generation counter + three-mode hint binding), `BlobInProgress` (in-flight
mutation state), `Scene` (a borrowed command list), `PreparedScene` (a
validated cache of records). The rewrite replaces these with `Picture` (data),
`Atlas` (data + monoidal ops), and free emit functions.

## 2. Allocations are visible

Every function that allocates takes an `Allocator`. Every function that
doesn't, takes a caller-provided buffer and reports how much it filled.

There is no hidden cache inside the renderer. There is no implicit growth of
GPU resources. There is no allocator stashed inside a type that quietly grabs
memory at unexpected times.

## 3. One primitive per concept, plus the fewest justified helpers

If a helper can't be written as `fn(primitives) -> result`, the primitive is
wrong. The helper layer above primitives is small and each helper has a
documented justification.

## 4. The unhinted hot path pays nothing for hinting

Hinted glyphs and unhinted glyphs produce the same `GlyphCurves` type and live
in the same `Atlas` shape. The renderer does not have to know which is which.
The TrueType bytecode VM is a *producer* of curves, on par with the raw outline
extractor and the path-to-curves converter.

The current code has `hint_record_texel` on every `TextBlob.Glyph` (whether
hinted or not), a three-mode `HintBinding` on every bundle, a parallel
`GlyphHintSnapshot` resource, and 25+ public TrueType-hint types. All of this
goes away.

## 5. The renderer never discovers, parses, allocates, or schedules

`renderer.draw()` takes prepared data and writes pixels. It does not extract
fonts, upload textures, allocate memory, or check for missing resources. Those
are separate explicit steps the caller performs.

## 6. The custom-shader path is first-class

A user with their own renderer who wants to use snail purely as a CPU-side
data producer has access to the same primitives, in the same shape, with the
same lifetime semantics as the internal renderer. The atlas exposes its byte
layouts publicly. The coverage helpers are callable from any shader code.

## 7. Shader specialization is API-visible

Splitting shaders along the heterogeneous-vs-replicated axis is load-bearing:
specialized shaders compile in milliseconds; merged shaders compile in
minutes. The API surfaces this split (two emit primitives, two segment kinds)
because the data shape difference matches the GPU work pattern.

This is the one place where implementation reality shapes the API
intentionally. It's not leakage — it's the data shape exposed honestly.

## 8. AtlasRecord stability is conditional on compaction

The previous design promised forever-stable `AtlasRecord` handles. That
implies unbounded memory in churn workloads. The rewrite makes the contract
honest: records are stable for the atlas's lifetime *unless the caller
compacts*. Because pictures hold `RecordKey`s (not `AtlasRecord`s), compaction
is transparent to picture-holders — the atlas resolves keys to records at emit
time.

## 9. No backwards-compatibility shims

The rewrite removes the old API surface entirely. There are no aliases, no
deprecated wrappers, no parallel implementations. The clean end state has only
the new types.

The existing internal infrastructure (curve+band format, shaders, hint VM, ttf
parser) is reused as implementation detail. It is not re-exposed under the
new API surface. Callers see only the new types.

# Hinting

Hinting is the one place snail deliberately gives up PPEM-independence: hinted
curves depend on the rasterization size. The current code handles this with a
parallel resource lifecycle (`GlyphHintSnapshot`, `PreparedHintRun`, per-blob
hint binding, separate manifest entry). The rewrite collapses this to: hinted
curves are just curves, in just an atlas, keyed by `(font_id, glyph_id, ppem)`.

## What stays unchanged

The TT bytecode VM in `src/snail/font/tt_*.zig` is the load-bearing
correctness component. It's kept verbatim. ~5000 lines of bytecode
interpretation that has been debugged against real fonts; touching it would
be a different project.

What changes is the wrapper around it.

## What "simpler" means

The current `TrueTypeHintContext` (`src/snail/text/hint_context.zig`,
~1087 lines) exposes 25+ public types:

```
TrueTypeHintContext              TrueTypeHintMachine
TrueTypeHintContextOptions       TrueTypeGlyphHint
TrueTypeHintCacheFootprint       TrueTypeGlyphHintPatch
TrueTypeHintSizeKeyEntry         TrueTypeExecutedGlyph
TrueTypeHintSizeKeyIterator      TrueTypeHintPpem
TrueTypeHintGlyphKeyEntry        TrueTypeBaseGlyphHint
TrueTypeHintGlyphKeyIterator     TrueTypeGlyphTopologyCache
TrueTypeHintGlyphKey             GlyphHintSnapshot
TrueTypeHintReject               GlyphHintSnapshotBuilderOptions
TrueTypeHintRejectReason         TextHintGlyphRecord
TrueTypeHintedGlyph              ...
TrueTypePreparedHintGlyph
TrueTypePreparedHintRun
TrueTypeHintRunStats
TrueTypeHintPrepareRunOptions
```

Most of this surface exists because hinting today is a parallel resource
lifecycle:

```
font outline
  ↓ TT bytecode (interpreter)
HintedGlyphValue
  ↓ packaged into per-run
PreparedHintRun.Glyph
  ↓ frozen
GlyphHintSnapshot
  ↓ bound to bundle
TextBlobBundle.hint_binding
  ↓ uploaded as separate resource
TextHintEntry in ResourceManifest
  ↓ referenced by
TextBlob.Glyph.hint_record_texel
```

Six intermediate types and lifecycles, plus reject/fallback machinery and
"prepared run" stats that callers must consume.

## What replaces it

Hinted glyphs become `GlyphCurves`, indistinguishable from any other curves
once produced. The `Hinter` is a producer, just like `font.extractCurves` and
`pathToCurves`.

```zig
pub const Hinter = struct {
    pub fn init(allocator: Allocator, font: *const Font) !Hinter;
    pub fn deinit(self: *Hinter) void;

    /// The single producer: run TT bytecode for `glyph_id` at `ppem` and
    /// return the resulting curves. Uses cached VM state and curve points
    /// when available; produces fresh values on miss.
    pub fn hint(self: *Hinter, scratch: Allocator, glyph_id: u16, ppem: HintPpem) !GlyphCurves;

    /// Curry over a ppem so `atlas.extendWith` can call .produce(scratch, key).
    pub fn providerAt(self: *Hinter, ppem: HintPpem) HintProvider;

    // Eviction (mechanism, not policy — unchanged in spirit from today).
    pub fn evictPpem(self: *Hinter, ppem: HintPpem) void;
    pub fn evictSize(self: *Hinter, ppem: HintPpem) void;       // alias
    pub fn clearGlyphs(self: *Hinter) void;
    pub fn clear(self: *Hinter) void;

    // Inspection.
    pub fn byteFootprint(self: *const Hinter) Footprint;
    pub fn sizeKeyIterator(self: *const Hinter) SizeKeyIterator;
    pub fn glyphKeyIterator(self: *const Hinter) GlyphKeyIterator;
};

pub const HintPpem = struct {
    x_26_6: u32,
    y_26_6: u32,
    pub fn uniform(p_26_6: u32) HintPpem;
    pub fn packed(self: HintPpem) u32;    // for RecordKey.c
};

pub const Footprint = struct {
    face_program_bytes: u64,
    size_state_bytes:   u64,
    glyph_value_bytes:  u64,
    pub fn totalBytes(self: Footprint) u64;
};
```

What goes away:
- `TrueTypeHintedGlyph`, `TrueTypePreparedHintGlyph` — the output is
  `GlyphCurves`, full stop. No intermediate per-glyph wrapper.
- `PreparedHintRun`, `PreparedHintRun.Glyph`, `PreparedHintRun.Stats`,
  `PrepareRunOptions` — there is no "prepared run" concept. Callers hint
  glyphs one at a time, or use a provider to drive bulk hint-on-miss via
  `atlas.extendWith`.
- `GlyphHintSnapshot`, `BuilderOptions` — the atlas absorbs the role of
  "the per-ppem hint state visible to the renderer." The atlas resolves
  `(font_id, glyph_id, ppem)` keys to records; no parallel snapshot needed.
- `HintReject`, `HintRejectReason`, fallback markers — `hint()` either
  produces curves or returns an error. If hinting fails (no bytecode,
  topology mismatch, etc.), the caller falls back to
  `font.extractCurves(scratch, glyph_id)`. Both produce `GlyphCurves`.
- `HintMachine`, `GlyphHint`, `GlyphHintPatch`, `ExecutedGlyph`,
  `BaseGlyph`, `GlyphTopologyCache` — TT VM internals that should never
  have been public.

## Lifecycle, illustrated

### One ppem, sticky (terminal)

```zig
var hinter = try Hinter.init(gpa, &font);
defer hinter.deinit();

const ppem_12 = HintPpem.uniform(12 * 64);

var atlas = Atlas.empty(gpa, &pool);
defer atlas.deinit();

// Per render of a string at ppem_12:
const shaped = try shape(gpa, &chain, text, .{});
defer shaped.deinit();

const keys = try shapedKeysHinted(gpa, &shaped, font_id, ppem_12);
defer gpa.free(keys);

const result = try atlas.extendWith(gpa, scratch, keys, hinter.providerAt(ppem_12));
if (result.new_atlas.recordCount() != atlas.recordCount()) {
    var old = atlas;
    atlas = result.new_atlas;
    old.deinit();
} else {
    result.new_atlas.deinit();
}

// build picture, emit, draw.
```

The hinter caches: per-font face program, per-ppem VM state, per-(glyph,ppem)
curve points. Subsequent calls for the same glyph at the same ppem are
cache hits.

### Multiple ppems, sticky (editor split panes)

Same atlas, different ppems use different keys. Caller maintains one or
more atlases depending on lifecycle preferences:

```zig
// One atlas per ppem (so drop-on-leave is efficient):
var atlas_12: Atlas = .empty(gpa, &pool);
var atlas_16: Atlas = .empty(gpa, &pool);

// Or one atlas across ppems (so combine is cheap):
var atlas_all: Atlas = .empty(gpa, &pool);
```

### Animation through ppems

Aggressive eviction matches the current code's pattern:

```zig
fn afterFrame(state: *State) void {
    // Drop curve points across all ppems; keep VM state warm.
    state.hinter.clearGlyphs();

    // Drop atlases for ppems we're not near.
    var it = state.atlas_per_ppem.iterator();
    while (it.next()) |entry| {
        if (distance(entry.key_ptr.*, state.current_ppem) > scrub_window) {
            entry.value_ptr.deinit();
            _ = state.atlas_per_ppem.remove(entry.key_ptr.*);
        }
    }
}
```

The library provides mechanism; the caller defines the policy.

## Faux-bold

The current code applies emboldening as a render-time second copy. The new
model preserves this: `Shape.local_color` carries the base color; the
caller adds a second shape with the embolden offset applied to
`Shape.local_transform` (or uses an `Override.transform` with the embolden
delta). The hinter doesn't know about emboldening; it just hints the base
outline.

## Fonts with no hinting

If a font has no bytecode table (`fpgm`/`prep`), `Hinter.init` succeeds (the
font has no VM to set up). `hint()` will return `error.NoHinting` for any
glyph. Callers either fall back to unhinted curves or never call the hinter
for that font.

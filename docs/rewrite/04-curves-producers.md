# Curves producers

Four functions produce `GlyphCurves`. All are interchangeable downstream — the
atlas takes whatever you give it; the renderer doesn't know which producer
made the bytes.

## Unhinted glyphs

```zig
pub fn Font.extractCurves(self: *const Font, scratch: Allocator, glyph_id: u16) !GlyphCurves;
```

Reads the glyph's outline from the TTF tables, converts to curve segments,
builds band lookup, packs into a `GlyphCurves`. Pure: same input → same
output. No caching at this layer (the atlas is the cache).

The font's `font_id` is whatever the caller assigned (typically an index in
their font chain). The producer doesn't know it; only the caller does.

## Hinted glyphs

```zig
pub fn Hinter.hint(self: *Hinter, scratch: Allocator, glyph_id: u16, ppem: HintPpem) !GlyphCurves;
```

Runs the TrueType bytecode interpreter at the given ppem against the cached
VM state. The output is also a `GlyphCurves` — same shape as unhinted, just
derived differently.

`Hinter` is the only producer with mutable cache state. See
[05-hinting.md](05-hinting.md).

## Filled paths

```zig
pub fn pathToCurves(
    scratch: Allocator,
    path:    *const Path,
    opts:    struct {
        fill_rule: FillRule = .non_zero,
    },
) !GlyphCurves;
```

Walks the path's segments, converts them into the curve representation, and
builds the band lookup. The fill rule is baked into the band layout (which
records cross which bands and in which direction).

## Stroked paths

```zig
pub fn strokeToCurves(
    scratch: Allocator,
    path:    *const Path,
    style:   StrokeStyle,
) !GlyphCurves;
```

Expands the path into offset curves with the requested cap, join, miter
limit, and stroke placement. Output is a fill of the expanded contour
treated as a closed region.

A stroked path is, at the GPU level, just a filled shape with weird
geometry. Once `strokeToCurves` returns, the result is indistinguishable
from any other `GlyphCurves`.

## Provider interface

The atlas's `extendWith` takes a duck-typed provider:

```zig
const Provider = struct {
    pub fn produce(self: @This(), scratch: Allocator, key: RecordKey) !GlyphCurves;
};
```

Each producer wraps as a provider:

```zig
// Unhinted: closes over the font.
pub const UnhintedProvider = struct {
    font: *const Font,
    font_id: u32,
    pub fn produce(self: UnhintedProvider, scratch: Allocator, key: RecordKey) !GlyphCurves {
        std.debug.assert(key.namespace == ns.unhinted_glyph);
        std.debug.assert(key.a == self.font_id);
        return self.font.extractCurves(scratch, @intCast(key.b));
    }
};

// Hinted: closes over the hinter and a ppem.
pub const HintedProvider = struct {
    hinter: *Hinter,
    font_id: u32,
    ppem: HintPpem,
    pub fn produce(self: HintedProvider, scratch: Allocator, key: RecordKey) !GlyphCurves {
        std.debug.assert(key.namespace == ns.hinted_glyph);
        std.debug.assert(key.a == self.font_id);
        std.debug.assert(key.c == self.ppem.packed());
        return self.hinter.hint(scratch, @intCast(key.b), self.ppem);
    }
};
```

Callers compose these naturally. For mixed content (paths + glyphs in one
extension call), the caller writes a multi-producer dispatcher:

```zig
const MixedProvider = struct {
    font: *const Font,
    font_id: u32,
    path_table: *const PathTable,
    pub fn produce(self: MixedProvider, scratch: Allocator, key: RecordKey) !GlyphCurves {
        return switch (key.namespace) {
            ns.unhinted_glyph => self.font.extractCurves(scratch, @intCast(key.b)),
            ns.path_fill      => self.path_table.fillToCurves(scratch, key.a, key.b),
            ns.path_stroke    => self.path_table.strokeToCurves(scratch, key.a, key.b),
            else              => error.UnknownNamespace,
        };
    }
};
```

This is the "polymorphism a la carte" pattern. The provider isn't an
interface implemented via vtable; it's whatever type happens to have a
`produce` method. The caller assembles it from primitives.

## Helper: `buildTextPicture` (justified convenience)

For the common case of "shape text, ensure glyphs in atlas, build picture",
a convenience helper exists:

```zig
pub fn buildTextPicture(
    alloc: Allocator,
    scratch: Allocator,
    atlas: *Atlas,           // mut: may be extended
    shaped: *const ShapedRun,
    font_chain: *const FontChain,
    opts: struct {
        baseline:  Vec2,
        em:        f32,
        color:     [4]f32,
        hinted:    ?HintPpem = null,    // null = unhinted
        hinter:    ?*Hinter = null,
    },
) !Picture;
```

This is the *only* helper that fuses multiple steps. It's justified because
shaping → key derivation → atlas extension → picture construction is the
operation 90% of callers want, and the manual decomposition is verbose:

```zig
// Manual form (always available):
const shaped = try shape(alloc, &chain, text, .{});
defer shaped.deinit();
const keys = try shapedRunKeys(alloc, &shaped, namespace, variant);
defer alloc.free(keys);
const result = try atlas.extendWith(alloc, scratch, keys, provider);
const picture = try shapedRunPicture(alloc, &shaped, .{
    .baseline = baseline, .em = em, .color = color, .ns = namespace, .variant = variant,
});

// Helper form (for the common case):
const picture = try buildTextPicture(alloc, scratch, &atlas, &shaped, &chain, .{
    .baseline = baseline, .em = em, .color = color,
});
```

The decomposed form is exposed as separate public functions; the helper just
fuses them. Custom-shader users who want to do paint binding themselves use
the decomposed form.

## What's *not* a producer

- `Picture` construction is not a producer — it's caller-side composition.
- COLR layer fan-out is not a producer at this layer. A COLR glyph's layers
  are produced individually by the same `font.extractCurves` (each layer is
  a separate glyph_id). The atlas key for each layer carries the layer's
  glyph_id; the picture's shapes reference all of them with their relative
  transforms and colors.

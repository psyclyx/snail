# Font format support

Snail delegates shaping, modern outline extraction, and variation application
to HarfBuzz, then converts the result into its own backend-neutral curves,
paints, atlas records, and draw records.

## Current support

| Area | Status |
|---|---|
| Containers | OpenType fonts and TTC/OTC collections |
| Monochrome outlines | TrueType `glyf`, CFF, and CFF2 |
| Variable instances | Explicit `fvar` coordinates, with outlines and metrics resolved by HarfBuzz |
| Layout | HarfBuzz GSUB/GPOS shaping, features, direction, script, language, and fallback |
| Color | COLRv0 solid palette layers, including foreground-color layers |
| Embedded bitmap glyphs | PNG CBDT/CBLC and `sbix`, via `Font.colorBitmap` + a host image decoder; monochrome EBDT/EBLC not surfaced |
| Other color glyphs | Not supported: COLRv1 and OpenType SVG |
| Palette selection | CPAL palette zero only; no named/custom palette API |

The unsupported color formats fall back to the font's ordinary outline when
one exists. Snail does not decode PNG, JPEG, TIFF, or SVG documents.

## Planned color-font integration

PNG bitmap strikes (CBDT/CBLC and `sbix`) are now extracted through HarfBuzz's
OT color API rather than a snail-owned table parser: `Font.colorBitmap` returns
the encoded bytes plus an em-space placement box, a host `ImageDecoder` turns
those bytes into a `snail.Image`, and the glyph is recorded as an image-painted
rect keyed by `(font, glyph, ppem)`. This deliberately reuses the existing
image-paint path — a bitmap glyph is a placed image, not a new coverage
primitive — so no renderer or shader changes were needed. Points 2–4 below are
the shape that landed; the remaining work is the vector color formats.

The broader integration still needs to cover COLRv1, SVG, palette selection,
and whatever representation a font makes available for one glyph, ideally
through one traversal rather than per-format branches.

The intended front end for that is HarfBuzz's paint API. A single
`hb_font_paint_glyph_or_fail` traversal normalizes:

- COLRv0 and COLRv1 into transforms, clips, solid/gradient paints, nested
  color glyphs, and compositing groups;
- CBDT/CBLC and `sbix` into tagged encoded-image callbacks (commonly PNG,
  with other standard formats possible for `sbix`) or premultiplied BGRA,
  with dimensions and glyph extents;
- OpenType SVG into an SVG image callback.

That traversal should feed a Snail-owned, backend-neutral prepared
presentation, not a renderer:

1. Vector clips and paints become prepared paths and paint records. COLRv1 is
   the best fit for Snail's resolution-independent model and should be the
   first complete color-font target.
2. Image callbacks go through a caller-supplied decoder selected by the
   HarfBuzz format tag. Snail can normalize raw BGRA itself, but PNG, other
   encoded bitmap formats, and SVG decoding remain optional host services.
   The decoder returns straight-alpha sRGBA texels suitable for `snail.Image`.
3. Bitmap records are ppem-specific. Their keys must include the requested
   size/selected strike, and placement must use the image extents supplied by
   HarfBuzz rather than the fallback outline bounds.
4. Decoded image ownership remains explicit. The host cache owns decoded
   `Image` values for at least as long as every atlas snapshot that references
   them.
5. Unsupported paint operations fail as an entire color presentation.
   Policy may then choose the monochrome outline; Snail must not silently
   render a partial COLRv1/SVG glyph.

This calls for a presentation policy at record time—prefer color, require
color, or use outlines—plus an optional image-decoder interface. It does not
call for a GPU backend or an image codec inside Snail.

## Other gaps

After a unified paint traversal, the remaining modern-font work is mostly
surface and policy:

- expose CPAL palette enumeration/selection and foreground overrides;
- expose variable-font named instances and STAT names in addition to raw
  axes;
- make color-presentation cache identity include palette, foreground, ppem,
  and variation coordinates;
- add corpus tests covering COLRv1 gradients/transforms/clips/composites,
  CBDT and `sbix` strikes, SVG fallback, malformed tables, and mixed
  outline/color runs.

HarfBuzz already applies the core `avar`/`gvar`/HVAR/VVAR/MVAR/CFF2
variation machinery used by Snail's selected instances; reimplementing those
tables is not a priority.

Specifications:

- [OpenType font tables](https://learn.microsoft.com/en-us/typography/opentype/spec/otff)
- [CBDT](https://learn.microsoft.com/en-us/typography/opentype/otspec182/cbdt)
  and [CBLC](https://learn.microsoft.com/en-us/typography/opentype/spec/cblc)
- [`sbix`](https://learn.microsoft.com/en-us/typography/opentype/otspec180/sbix)
- [COLR](https://learn.microsoft.com/en-us/typography/opentype/otspec190/colr)
- [OpenType SVG](https://learn.microsoft.com/en-us/typography/opentype/otspec190/svg)
- [OpenType variations](https://learn.microsoft.com/en-us/typography/opentype/spec/otvaroverview)

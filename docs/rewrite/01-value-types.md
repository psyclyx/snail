# Core value types

These are the pure-data types. They have no methods that mutate the instance,
no hidden state, no lifetime coupling beyond the obvious (a record's bytes
must be alive on a page; the atlas containing the page must be alive).

## `RecordKey`

Caller-namespaced identity for atlas records. 16 bytes.

```zig
pub const RecordKey = extern struct {
    namespace: u32,
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0,
};
```

The atlas dedups on the whole key. Same key in two atlases is assumed to
represent the same content (and combining the atlases keeps one entry).

### Reserved namespaces

Snail reserves namespaces `1..1023`. Callers use `>= 1024`.

| Namespace | Meaning | Schema |
|---|---|---|
| `ns.unhinted_glyph` (1) | Glyph from raw TTF outlines | a=font_id, b=glyph_id |
| `ns.hinted_glyph` (2) | Glyph from TT bytecode at a ppem | a=font_id, b=glyph_id, c=ppem_26_6 |
| `ns.path_fill` (3) | Filled path | caller-chosen |
| `ns.path_stroke` (4) | Stroked path | caller-chosen |
| `ns.paint_record` (5) | Paint record (gradient, image) | caller-chosen |
| `>= ns.user_base` (1024) | Caller-defined | caller-defined |

`font_id` is a caller-assigned u32 stable for the lifetime of the atlas (it
identifies which `Font` produced the curves). Snail does not assign font IDs;
callers do, typically by index in their font chain.

### Design notes

The 16-byte flat shape is a deliberate trade. A parameterized
`Atlas(comptime KeyType)` would be cleaner but prevents mixing key types in a
single atlas — a real constraint when combining text and vector records. The
flat tagged-tuple shape supports mixing, at the cost of carrying meaningless
`c` field bytes for namespaces that only use `a` and `b`.

## `AtlasRecord`

A resolved handle to one record on one atlas page.

```zig
pub const AtlasRecord = struct {
    page_index: u16,         // index into Atlas.pages
    page_generation: u16,    // matches AtlasPage.generation at issue
    curve_texel: u32,        // offset into the page's curve texture
    curve_count: u16,        // number of curve segments
    bands: GlyphBandEntry,   // band-lookup metadata
    bbox: BBox,
};
```

Callers don't normally see `AtlasRecord`s. Pictures hold `RecordKey`s; the
atlas resolves them at emit time. `AtlasRecord` is exposed for the
custom-shader path, where the caller may want to pack their own vertex data.

`page_generation` lets emit-time validation catch records that were issued
against an old generation of a page that has since been reused. This is only
possible if a caller stores `AtlasRecord`s outside the live reference graph
(e.g., serializes one to disk).

## `GlyphCurves`

The renderable form of any shape. The single value type produced by all four
producers (font extract, hinter, path fill, path stroke).

```zig
pub const GlyphCurves = struct {
    allocator: std.mem.Allocator,
    curve_bytes: []const u16,   // packed RGBA16F curve segments
    band_bytes: []const u16,    // packed RG16UI band lookup
    curve_count: u16,
    h_band_count: u16,
    v_band_count: u16,
    bbox: BBox,

    pub fn deinit(self: *GlyphCurves) void;
    pub fn isEmpty(self: *const GlyphCurves) bool;
};
```

The byte representations exactly match the existing `curve_texture.zig` and
`band_texture.zig` formats. A producer returns a `GlyphCurves`; the atlas
copies its bytes into a page; the producer's `GlyphCurves` can then be
deinit'd.

## `Shape`

One element of a picture.

```zig
pub const Shape = struct {
    key:             RecordKey,
    local_transform: Transform2D = .identity,
    local_color:     [4]f32 = .{ 1, 1, 1, 1 },
    local_paint:     ?RecordKey = null,
};
```

`local_transform` positions the shape within the picture's local coordinate
space. `local_color` is multiplied by the per-instance `Override.tint` at emit
time. `local_paint`, if set, references a paint record (gradient stops,
image-paint metadata) that lives in some atlas alongside the curve records.

## `Override`

A per-instance modifier applied to a whole picture during instanced emit.

```zig
pub const Override = struct {
    transform: Transform2D = .identity,
    tint:      [4]f32       = .{ 1, 1, 1, 1 },
};
```

For an instanced draw of a picture with N shapes and M overrides, the final
GPU instance count is N×M. Each instance composes the override's transform
with the shape's local transform, and multiplies the override's tint with the
shape's local color.

## What's not in this layer

- `Picture` — see [03-picture-and-emit.md](03-picture-and-emit.md). Picture is
  a small value type (`{ shapes: []Shape, bbox: BBox }`) plus monoidal
  operations, separated for organizational reasons.
- `AtlasPage` — implementation detail of `Atlas`; see
  [02-atlas-and-pages.md](02-atlas-and-pages.md).
- Identity-bearing types (`Atlas`, `PagePool`, `Hinter`) are *not* in this
  layer. They carry lifetime semantics and so live in their own files.

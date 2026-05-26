# Custom shader path

A first-class use of snail. The caller has their own GL / Vulkan / Metal /
WebGPU renderer and wants snail's curve data + coverage helpers to draw text
and vector graphics in their pipeline alongside their own content.

## What snail exposes

Everything the internal renderer uses, in public form:

### 1. Atlas byte layouts

```zig
pub const format = struct {
    pub const curve_texture = @import("render/format/curve_texture.zig");
    pub const band_texture  = @import("render/format/band_texture.zig");
    pub const layer_info    = @import("render/format/layer_info.zig");
};
```

These modules document the exact byte layouts of each texture:
- `curve_texture`: RGBA16F, packed Bezier segments (4 texels each).
- `band_texture`: RG16UI, band lookup tables.
- `layer_info`: RGBA32F, per-record metadata (bbox, band offsets, paint).

The byte layouts are part of the public ABI. They change only with a
major version bump.

### 2. Raw page bytes

```zig
pub fn Atlas.uploadDescriptor(self: *const Atlas) UploadDescriptor;

pub const UploadDescriptor = struct {
    pages: []const PageBytes,
};

pub const PageBytes = struct {
    layer_index: u16,
    curve_data:  []const u8,    // raw bytes ready to push to GPU
    band_data:   []const u8,
};
```

The custom-shader user uploads these to their own texture handles via
`glTexImage3D` / `vkCmdCopyBufferToImage` / equivalent.

### 3. Record metadata

```zig
pub fn Atlas.lookupRecord(self: *const Atlas, key: RecordKey) ?AtlasRecord;
```

Same function the internal `emit()` uses. The custom-shader user looks up
each shape's record, then packs the record's metadata (layer_index,
curve_texel, bbox, band offsets) into their own per-instance vertex data.

### 4. Coverage helpers

```zig
pub const shader = struct {
    pub const glsl = struct {
        pub const coverage:          [:0]const u8 = @embedFile("...");
        pub const coverage_subpixel: [:0]const u8 = @embedFile("...");
    };
    pub const hlsl = struct { /* equivalent */ };
};
```

These are string constants the custom-shader user pastes into their own
shader source. They expose a function like:

```glsl
// From snail.shader.glsl.coverage:
float snail_evaluate(
    vec2 sample_local,           // sample point in record local space
    sampler2DArray curve_tex,    // curve texture array
    sampler2DArray band_tex,     // band texture array
    uint layer,
    uint curve_texel,
    uint h_band_count,
    uint v_band_count,
    vec2 band_offset,
    vec2 band_scale,
    int fill_rule                // 0 = non-zero, 1 = even-odd
);
```

The signature is fixed; the body changes with major versions. The
custom-shader user calls this from their fragment shader, then applies
their own paint (gradients, blends, post-effects).

## Lifecycle for a custom-shader user

```zig
// Init: caller manages their own GPU resources.
var pool = try snail.PagePool.initOffline(gpa, .{ .max_layers = 32 });
defer pool.deinit();

// Build an atlas the normal way.
var atlas = try Atlas.from(gpa, &pool, entries);
defer atlas.deinit();

// Get raw bytes.
const desc = atlas.uploadDescriptor();
for (desc.pages) |page| {
    myGlTexSubImage3D(my_curve_tex, page.layer_index, page.curve_data);
    myGlTexSubImage3D(my_band_tex,  page.layer_index, page.band_data);
}

// Per-frame: look up records, pack own vertex data.
for (picture.shapes) |shape| {
    const rec = atlas.lookupRecord(shape.key) orelse continue;
    myPushInstance(.{
        .layer       = rec.page_index,
        .curve_texel = rec.curve_texel,
        .bbox        = rec.bbox,
        .h_bands     = rec.bands.h_band_count,
        .v_bands     = rec.bands.v_band_count,
        .band_x      = rec.bands.glyph_x,
        .band_y      = rec.bands.glyph_y,
        .transform   = my_compose(world, shape.local_transform),
        .color       = shape.local_color,
        // ...whatever custom fields they want
    });
}

myDrawInstanced();
```

## What an offline `PagePool` is

The internal `renderer.createPagePool()` creates a pool backed by GPU
textures via the renderer's backend. For custom-shader users, snail also
provides:

```zig
pub fn PagePool.initOffline(allocator: Allocator, opts: PoolOptions) !PagePool;
```

This creates a pool with no GPU backing — pages live entirely in CPU
memory. The custom-shader user reads the bytes via `uploadDescriptor()`
and manages GPU memory themselves.

Apart from the absence of GPU backing, an offline pool behaves identically:
same monotonic `layer_index` assignment, same refcount-based reclamation,
same `generation` semantics. Atlases built against an offline pool work
with `Picture` and `lookupRecord` exactly like atlases built against a
backend pool.

## What the custom shader writes

Their vertex shader reads their own per-instance attributes (whatever
they packed). Their fragment shader calls `snail_evaluate(...)` with the
record metadata, gets a coverage value in `[0, 1]`, and composes it with
their own paint logic:

```glsl
void main() {
    vec2 sample_local = ...; // computed from gl_FragCoord and the inverse of the per-instance transform
    float coverage = snail_evaluate(sample_local, /* ... */);

    vec4 my_paint = computeMyPaint(sample_local, ...); // their own logic
    out_color = my_paint * coverage;
}
```

## What snail does *not* try to do

- Provide a `Renderer` trait that custom-shader users implement. They
  don't implement a renderer; they *write* one.
- Provide a "headless" `emit()` that produces their custom vertex format.
  They write their own packing loop over `picture.shapes` and
  `atlas.lookupRecord`.
- Abstract over GL / Vulkan / WebGPU. The custom-shader user is already
  in one of those worlds; snail's job is to give them data, not graft a
  cross-API renderer on top.

## What this means for the internal renderer

The internal `Renderer` (CPU, GL, GLES, Vulkan backends) is just one
particular custom-shader consumer that happens to ship with snail.
Everything it does is doable from the public API. There is no privileged
path. If something is internal-only, that's a bug in the API surface, not
a design choice.

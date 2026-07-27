# Embedding snail

This document collects the detailed host contracts behind the shorter
integration overview in the [README](README.md). The core flow is:

**shape → record → upload → emit → draw**

snail owns the CPU-side font, path, atlas, upload-planning, and draw-record
logic. A GPU host owns its textures, pipelines, uploads, command buffers, and
draw calls. `snail-raster` is the optional CPU backend.

## Software renderer

`snail-raster` uses the same `Atlas`, `Binding`, instances, and batches as a
GPU backend:

```zig
const raster = @import("snail-raster");

var device = try raster.DeviceAtlas.init(alloc, pool, .{});
defer device.deinit();
var bindings: [1]snail.render.records.Binding = undefined;
try device.upload(alloc, &.{&atlas}, &bindings);

var raster_ni: usize = 0;
var raster_nb: usize = 0;
_ = try snail.emit.emit(instances, batches, &raster_ni, &raster_nb,
    bindings[0], &atlas, shapes, world_xform, .{ 1, 1, 1, 1 });
const raster_records: raster.DrawRecords = .{
    .instances = instances[0..raster_ni],
    .batches = batches[0..raster_nb],
};

var renderer = try raster.Renderer.init(
    pixels, width, height, stride, .rgba8_unorm,
);
try raster.draw(&renderer, .{
    .mvp = mvp,
    .surface = .{
        .pixel_width = width,
        .pixel_height = height,
        .encoding = .srgb,
        .format = .rgba8_unorm,
    },
}, raster_records, &.{&device}, null);
```

`Renderer.init` and `reinitBuffer` validate the caller-owned byte length and
stride. Every draw also validates the declared surface size and
`PixelFormat`; the stride must be at least
`width * format.bytesPerPixel()`.

`DeviceAtlas.upload` requires one output binding per input atlas. If a
multi-atlas call fails, none of the bindings planned by that call remain
live, although successfully prepared shared-page data may stay cached.
`snail-raster` supports affine scene-to-pixel transforms. A perspective MVP
returns `error.NonAffineMvp`.

## Capacity and eviction

`PagePool` is the resident page budget. Recording is idempotent: an existing
record key is skipped. When a new record cannot acquire a page, recording
returns `error.OutOfLayers`; eviction policy belongs to the host.

`Atlas.compact(allocator, scratch, filter)` creates a new, fully repacked
snapshot. A `RecordFilter` chooses the records that survive; `null` keeps
everything and performs pure defragmentation. Autohint dependencies are
closed automatically, paint and analysis records are retained, and TT
advance-only records pass through the same filter.

Compaction acquires the new pages before the old atlas releases its pages.
Keep enough `pool.stats().pages_free` headroom for the compacted result
instead of waiting until the pool is completely full. `PagePool.config()`
returns the immutable capacity configuration. Atlas page handles are opaque;
renderer integrations receive immutable `atlas_upload.Region` copies.
[`dev/support/working_set.zig`](dev/support/working_set.zig) is a demo-only
working-set example.

Each non-empty `Atlas.extendInPlace` call commits one persistent snapshot and
copies the atlas's flat page-pointer and paint-side-data arrays once. Bulk
callers should pass one entry slice or use `extendBatchesInPlace`; do not put
`extendInPlace` in a one-entry loop.

## Upload planning and bindings

`atlas_upload.OwnedPlanner.plan` reserves a binding and emits complete upload
regions. On a direct append-only child snapshot,
`planDelta(previous_binding, atlas)` emits only changed curve/band regions
and newly appended side data.

Layer-info rows and image layers are fixed reservations made by the original
`plan`. If later side data outgrows that reservation, release the binding and
make a fresh plan. Branches and unrelated snapshots replace side data
conservatively within the same reservation.

If copying a successful `plan` or `planDelta` result to the device fails,
call `planner.invalidateUploads()` before retrying
`planDelta(binding, &atlas)`, or release the binding before a fresh `plan`.
This clears the planner's page and side-data watermarks so bytes that never
reached the device are emitted again.

A `Binding` is meaningful only to the planner or `DeviceAtlas` that issued
it. Its identity includes the `PagePool`, the issuer's `source_id`, a 64-bit
slot generation, the layer-info row, and the image-layer offset. Do not
synthesize bindings or compare only part of one in a device cache.

Upload `Region` payloads borrow one of three owners:

- planner scratch for layer-info data;
- live atlas page memory for curve and band data;
- caller-owned `Image` texels.

Apply the regions before the next `plan` or `planDelta`, and keep the
referenced atlas and images alive and unchanged until copying finishes.

## Color

Paint, tint, placement, and emitted instance colors are linear-light
`[4]f32` values with straight (non-premultiplied) alpha. snail does not
automatically convert them. Gradients interpolate and tints multiply in
linear light; coverage produces premultiplied linear color. CPAL colors are
specified by OpenType as sRGB and are converted to linear during extraction.

`LinearResolve.Backdrop.clear` is the deliberate exception: it accepts an
sRGB straight-alpha color, matching an application-authored clear color.

Use `snail.color.srgbToLinearColor` for sRGB-authored paint and tint values.
Blend shader output with `ONE, ONE_MINUS_SRC_ALPHA`. `TargetEncoding`
selects the output path: a linear attachment receives linear values; an sRGB
attachment encodes in hardware; and
`.srgb_pixels_on_linear_attachment` asks the shader to encode before writing.
That last single-pass compatibility mode blends in storage space.

For linear-correct overlapping translucency, blend into a linear
intermediate and encode once afterward with the generated linear-resolve
stages or another final pass. Encoding each layer before blending makes
overlaps too dark.

## Coordinates

Font geometry is stored y-up. `RunPlacement.y_axis` and
`CellRunPlacement.y_axis` orient it into either a y-down scene (the default)
or a y-up scene. Coverage is orientation-independent.

`mvpToScenePixel` maps an affine MVP into framebuffer pixels with a top-left
origin. That framebuffer convention is separate from the scene's y-axis.
It returns `null` for perspective or degenerate transforms.

## Images

`Image` copies and stores tightly packed raw texel bytes; the core does not
parse an image-file format or reinterpret the texel layout. The sampling
contract is that a backend produces linear color with straight alpha:

- upload sRGB bytes to an sRGB texture format, or
- upload pre-linearized values to a UNORM or floating-point format.

`atlas_upload.Options.image_bytes_per_texel` declares the host array format
(four by default). Every image in a plan must match it and fit
`max_image_width × max_image_height`. `snail-raster` accepts four-byte sRGBA
texels and decodes RGB to linear for each sample.

## GPU resources and shaders

The atlas uses:

- an `RGBA16F` curve texture array;
- an `RG16UI` band texture array;
- an `RGBA32F` layer-info texture;
- an optional host-formatted image texture array.

These are the atlas resources, not the complete GPU footprint. A host also
provides the 72-byte-per-instance stream, the shared parameter block,
pipelines, samplers where required, and ordinary command-buffer state.

The native Slang modules under
[`src/snail/shader/slang`](src/snail/shader/slang) are the authored source
of truth. Generated `snail-shaders` modules provide complete stages and
binding-name contracts for:

- Vulkan SPIR-V;
- WGSL;
- GLSL 330 and GLES 300;
- D3D11 HLSL;
- Metal MSL.

Artifacts are generated in the Zig cache only for an imported shader module.
`snail` and `snail-raster` alone do not require `slangc`. Per-target scopes
are `snail-shaders-gl`, `snail-shaders-glsl330`,
`snail-shaders-wgsl`, `snail-shaders-hlsl`, and `snail-shaders-msl`;
`snail-shaders` is the aggregate scope. Consumer scopes run `slangc` but not
the repository's additional `naga` validation step.

For custom materials, caller-authored Slang can `import text_sample` and
sample glyph coverage inside its own fragment shader. The worked example is
[`dev/demo/game/slang/game_material.slang`](dev/demo/game/slang/game_material.slang).

## Render ABI

The render ABI is versioned. Each packed instance is 72 bytes (18 32-bit
words): an outward-rounded f16 local bounding box, affine transform and
origin, glyph words, four payload words, and linear-f16 color/tint. All 256
atlas layers are representable. Backends validate packed records before
consuming them.

The public byte-layout and decoding contracts live in `snail.render`; shader
binding contracts live in `snail-shaders`; the canonical shader-side layout
lives under `src/snail/shader/slang`.

## Ownership, failure, and threading

Allocating constructors and operations either accept an allocator or use
the allocator retained by their owning value. `Font` borrows its source
bytes and, for selected variable instances, its variation slice. `Faces`
borrows stable `Font` pointers. A `PagePool` must outlive every atlas, upload
planner, and device cache created from it.

`Atlas` is a persistent value: `extend` and `compact` return new snapshots
that share retained, reference-counted page storage while preserving the old
snapshot. Lookups return records by value, avoiding an entry-versus-eviction
lifetime hazard.

Construction and validation errors are typed. Atlas insertion, draw
emission, device resize, and renderer buffer replacement preflight or stage
their work so published state is unchanged on failure. Paths, paints,
transforms, colors, packed records, and upload data are validated at their
public boundaries.

The core `snail` module does not create threads. Separate atlas handles,
including children of the same persistent snapshot, may be extended and
destroyed on different threads. Do not mutate or destroy the same handle
concurrently, and use distinct allocators or a thread-safe allocator.

`Faces`, `TtHintVm`, planners, and other mutable working values are
single-threaded unless their documentation says otherwise. Construct one
`Faces` per shaping thread. `snail-raster` provides an optional,
caller-driven `ThreadPool`.

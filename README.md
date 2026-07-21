# snail

Text and vector rendering via direct Bezier curve evaluation, built to embed in your engine.

<img src="assets/demo_screenshot.png?raw=true" alt="snail demo scene">

snail renders text and vector art by evaluating Bezier curves at draw time. No bitmap glyph atlases, no signed distance fields. Glyphs and paths are resolution-independent and render correctly at any size, rotation, or perspective transform.

snail is a library, not a renderer: it owns no GPU objects, threads, caches, or eviction policy. It prepares data on the CPU and hands you texture contents, typed draw records, and entry-point-free shader fragments; your engine owns the textures, pipelines, uploads, and draw calls. An optional software renderer (`snail-raster`) covers hosts without a GPU.

This is alpha-quality software. The Zig API is settling but not yet stable; a C API will be re-cut against the current primitives.

## Algorithm

This is an implementation of the [Slug algorithm](https://sluglibrary.com/):

- Eric Lengyel, ["GPU-Centered Font Rendering Directly from Glyph Outlines"](https://jcgt.org/published/0006/02/02/), JCGT 2017
- Eric Lengyel, ["A Decade of Slug"](https://terathon.com/blog/decade-slug.html), 2026
- [Reference HLSL shaders](https://github.com/EricLengyel/Slug) (MIT / Apache-2.0)

The Slug patent (US 10,373,352) was [dedicated to the public domain](https://terathon.com/blog/decade-slug.html) in March 2026. This implementation is original code, not derived from the Slug Library product. Licensed under MIT.

### How it works

Rendering splits into a **preparation** phase (CPU, once per glyph or path)
and a **draw** phase (every frame, in a shader or the CPU rasterizer).
Nothing is ever rasterized ahead of time — what the atlas stores is
geometry. The diagrams below are rendered by snail itself
(`zig build run-algorithm-diagrams`).

**1. Prepare: outlines stay curves.** A glyph is quadratic Béziers in em
coordinates. Preparation packs the segments — four texels each — into the
curve texture. One record per glyph, reused at every size and transform.

<img src="assets/algorithm-curves.png?raw=true" alt="a glyph outline with one highlighted quadratic segment, and its four texels in the curve texture" width="320">

**2. Prepare: bands index the curves.** The glyph's box is sliced into
horizontal and vertical bands; each band lists only the segments whose
bounds overlap it. This band texture is the lookup structure that makes
per-fragment evaluation cheap.

<img src="assets/algorithm-bands.png?raw=true" alt="horizontal and vertical bands over the glyph, one band highlighted with the curves it references" width="320">

Curves (RGBA16F), bands (RG16UI), and layer-info rows (RGBA32F — bounds,
band transforms, paint records, color-font layers) are the whole GPU
footprint, plus an optional host-formatted image array for image paints.
The upload planner emits the texel regions; the host copies them into
textures it owns.

**3. Draw: one instanced quad per glyph.** Each placed shape is one
instance of a quad bounding the outline under its transform — `emit`
produces typed instances and coalesced batches, one instanced draw per
batch. A fragment maps its position back to glyph-local coordinates through
the inverse transform, which is why any affine or perspective transform
(and either y-axis convention) renders exactly: all the math from here on
happens in the glyph's own space.

<img src="assets/algorithm-quad.png?raw=true" alt="a transformed glyph in its bounding quad on screen, and a fragment mapped back to glyph space" width="320">

**4. Draw: the sample picks two bands.** The fragment's local position
selects one horizontal and one vertical band; only the curves those bands
list are candidates — a handful of segments instead of the whole glyph.

<img src="assets/algorithm-sample-bands.png?raw=true" alt="a sample point with its horizontal and vertical band highlighted and their candidate curves emphasized" width="320">

**5. Draw: solve ray roots per candidate.** Cast axis-aligned rays through
the sample and solve the ray/Bézier equation for each candidate — a
quadratic for text (the TrueType fast path); vector paths add lines,
rational conics, and cubics. Every root in range is a crossing, signed by
the direction the curve crosses the ray.

<img src="assets/algorithm-roots.png?raw=true" alt="horizontal and vertical rays through the sample with signed root crossings marked" width="320">

**6. Draw: signed roots sum to winding.** The crossing signs accumulate
into a winding number, and the fill rule (`non_zero` or `even_odd`) maps
winding to inside/outside — the hole's crossings cancel to zero on their
own. The horizontal and vertical estimates are weighted together for
robustness near tangencies.

<img src="assets/algorithm-winding.png?raw=true" alt="two samples with their rays: crossings sum to w=1 in the ring and cancel to w=0 in the hole" width="320">

**7. Draw: roots near the pixel become coverage.** A root within half a
pixel of the sample contributes fractional coverage instead of a binary
in/out — analytic antialiasing, no supersampling, no prefiltered bitmap.
Coverage multiplies the paint resolved from the layer-info record (solid,
gradient, or image) and composites as premultiplied linear. Grayscale AA
takes one sample per pixel; LCD subpixel modes evaluate per-channel
offsets.

<img src="assets/algorithm-alpha.png?raw=true" alt="device pixels along a zoomed edge shaded by their true fractional coverage" width="320">

## The pipeline

Everything is **prepare → record → upload → draw**. The `Atlas` is the store
of prepared records — a persistent, value-typed CPU artifact. Producers are
pure; nothing in the shipped API is a cache.

```zig
const snail = @import("snail");

// Prepare: parse fonts, shape text.
var font = try snail.Font.init(font_bytes);            // borrows the bytes
var faces = try snail.Faces.build(alloc, &.{.{ .font = &font }});
var shaped = try snail.shape(alloc, &faces, "Hello, world", .{});

// Record: commit prepared glyph records into the store.
var pool = try snail.PagePool.init(alloc, .{
    .max_layers = 8, .curve_words_per_page = 1 << 17, .band_words_per_page = 1 << 14,
});
var atlas = snail.Atlas.init(alloc, pool);
try snail.recordUnhintedRun(&atlas, alloc, &faces, &shaped, .{});

// Upload: plan backend-neutral texel regions, copy them into YOUR textures.
// (Planner state is caller-owned and allocation-free; see atlas_upload.sizes.)
var n: usize = 0;
const binding = try planner.plan(&atlas, regions_buf, &n, info_scratch);
for (regions_buf[0..n]) |r| myEngine.texSubImage(r); // curve/band/layer_info/image
// Next frame's hot path: planDelta uploads only what grew.

// Place + emit: shaped run -> Shapes -> typed instances and batches.
const shapes = try snail.placeRunAlloc(alloc, &shaped, null, .{
    .baseline = .{ .x = 48, .y = 92 }, .em = 34,
});
_ = try snail.emit.emit(instances, batches, &ni, &nb,
    binding, &atlas, shapes, world_xform, .{ 1, 1, 1, 1 });

// Draw: your pipeline, your command buffer. One instanced quad per batch,
// vertex/fragment stages composed from snail.shader.glsl fragments.
```

The complete, runnable version of this flow against a raw GL context is
[`src/demo/app/minimal_gl.zig`](src/demo/app/minimal_gl.zig) (`zig build
run-minimal-gl`) — it exercises all four record verbs, paths, COLR, and the
delta-upload hot path. For a full engine-shaped integration (descriptor
layouts, multi-pass, Vulkan), read the demo's reference callers in
[`src/demo/render/gl/`](src/demo/render/gl) and
[`src/demo/render/vulkan/`](src/demo/render/vulkan). The software-renderer
flow is `snail-raster`'s `DeviceAtlas.upload` + `draw`.

### Capacity and eviction

The `PagePool` is the residency budget. Recording is idempotent (existing
keys are skipped) and fails with `error.OutOfLayers` when the pool is
exhausted — that is your eviction moment, and the policy is yours:
`Atlas.compact(alloc, scratch, filter)` rebuilds the store full-fidelity,
keeping only records the `RecordFilter` accepts (pass `null` to keep
everything, i.e. pure defragmentation). Compact acquires new pages before
releasing old ones, so evict on `free_count` headroom, not on failure.
`src/support/working_set.zig` is a worked example (demo-only, not shipped).

## Contracts

These are the fixed points a host must know. Everything else is explicit
per-call configuration.

**Colors are linear.** Every `[4]f32` color crossing the API is linear light
with straight (non-premultiplied) alpha. snail never interprets your colors;
gradients interpolate and tints multiply in linear light, and fragment output
is **premultiplied linear** — encode via an sRGB framebuffer or your own
resolve pass (blend state: `ONE, ONE_MINUS_SRC_ALPHA`). If you author in
sRGB, convert once at the boundary with `snail.color.srgbToLinearColor`.
Font palette colors (CPAL, spec-defined sRGB) are converted at extraction.

**Y axis is yours.** Glyph geometry is stored y-up (font units);
`RunPlacement.y_axis` selects the scene orientation (`.down` default for
top-left-origin UI, `.up` for y-up worlds). Coverage is
orientation-independent, so both fill identically. `mvpToScenePixel` maps an
MVP to viewport pixels with a top-left origin — that's the framebuffer texel
convention, separate from the scene axis.

**Image texels are opaque.** `Image` holds raw texel bytes; snail never
decodes them. The contract is that *sampling yields linear color* — bind an
sRGB texture format for sRGB bytes, or a UNORM/float format for
pre-linearized data. `snail-raster` documents its own device format: 4
bytes/texel RGBA, sRGB-encoded, straight alpha.

**Texture ABI.** Curves RGBA16F, bands RG16UI, layer-info RGBA32F, plus the
host-formatted image array. Layouts are stable and documented in
`snail.render` (byte-layout contract for caller-owned renderers) and
`snail.shader.glsl` (fragments + binding contracts per GL/GLES/Vulkan).

**Ownership and lifetimes.** Every allocating call takes an explicit
allocator; there is no global or threadlocal state. `Atlas` is value-typed
and persistent — `extend`/`compact`/`combine` return new snapshots sharing
unchanged pages, and lookups return records **by value**, so there is no
entry-vs-eviction lifetime hazard. Upload `Region`s alias planner scratch
(`layer_info`/`image`) or live page memory (`curve`/`band`): apply them
before the next `plan`/`planDelta`, and don't free or compact the atlas in
between. `Font` borrows the font bytes you pass it.

**Threading.** snail does not create threads. Values are single-threaded
unless documented; `PagePool` acquire/release is the one internally
synchronized boundary, so independent atlases over one pool can be built on
different threads. `snail-raster` has an optional caller-driven `ThreadPool`.

## Text and hinting

`Faces.build` + `shape()` produce a `ShapedText` (HarfBuzz shaping, style
selection, fallback chains, OpenType features, source-range metadata).
`placeRun`/`placeRunAlloc` turn a run into `Shape`s under one of three modes,
each pairing a record namespace with a population verb:

| `HintMode` | Records | Character |
|---|---|---|
| `.unhinted` | `recordUnhintedRun` | ppem-independent; cacheable at any subpixel position; COLR via composite records (default) or per-layer fanout (`ColrHandling.layers` + `colr = true`) |
| `.autohint = policy` | `recordAutohintRun` | one immutable per-glyph analysis, ppem-independent; the fitting `AutohintPolicy` is draw-time instance state (GPU runtime warp / CPU parity) |
| `.tt_hint = .{ .ppem_26_6 }` | `recordTtHintRun` | authentic TrueType bytecode via the pure `TtHintVm`; per-ppem curve records, hinted advances recorded for free |

Grid-fit hinting needs integer device-pixel origins: pair strong policies or
`tt_hint` with `RunSnap.origins` (proportional) or `.columns` (monospace
terminals), passing `world_to_pixel = mvpToScenePixel(mvp, fb_w, fb_h)`.
Snapped runs are tied to that transform (per-frame); unsnapped runs are
content-only and cacheable. For hinted measurement without drawing,
`recordTtAdvanceRun` stores advances only, and `TtAdvanceSource` feeds them
back into `shape()` as an `AdvanceProvider` (VM fallback failures are
observable via `last_error`/`fallback_count`).

Paths (`Path` → `PreparedPath`) and image/gradient paints ride the same
store: author paths in a unit frame and place them with a transform, exactly
like glyphs. `snail.snap` has pure pixel-grid helpers for rect edges and
baselines.

## Modules

- **`snail`** — everything above: fonts, shaping, placement, atlas store,
  upload planning, emit, render/shader contracts. Links libc and system
  HarfBuzz; no GPU or windowing dependencies.
- **`snail-raster`** — optional software renderer consuming only the public
  API: `DeviceAtlas` (host-side texture analog), `Renderer`, `draw`, explicit
  `TargetEncoding`/`PixelFormat`, linear-light blending, optional subpixel AA.
- `src/demo`, `src/support`, `src/tools` — demos, reference GPU callers, and
  internal conveniences. Not published; copy freely.

Public-surface encapsulation is enforced by
[`src/tests/public_renderer_api.zig`](src/tests/public_renderer_api.zig),
which compile-errors if internals leak.

## Build

Requires [Zig 0.16](https://ziglang.org/download/) and HarfBuzz (via
pkg-config). The demos additionally need Wayland + EGL, Vulkan headers/loader,
and `glslc`.

```sh
zig build test                    # unit tests (includes shader-parity and public-API gates)
zig build run                     # interactive Wayland banner demo (C cycles backends)
zig build run-game                # interactive 3D scene: world-space text, custom material shader
zig build run-minimal-gl          # one-file public-API GL example → zig-out/minimal-gl.tga
zig build run-banner-screenshot   # headless CPU render (also -gl, -gles30, -vulkan variants)
zig build run-algorithm-diagrams  # regenerate the README diagrams (snail rendering itself)
zig build run-backend-compare     # CPU vs GL divergence gate
zig build run-gamma-probe         # linear-blending / encode round-trip gate
zig build run-composite-probe     # perspective coverage-hole gate
zig build install-perf            # performance regression runners
```

With Nix: `nix-build -A demo`, or `nix-shell` for a dev shell with all
dependencies.

### As a dependency

```sh
zig fetch --save git+https://github.com/psyclyx/snail
```

```zig
const snail_dep = b.dependency("snail", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("snail", snail_dep.module("snail"));
// Optional software renderer:
exe.root_module.addImport("snail-raster", snail_dep.module("snail-raster"));
```

Workspace builds that import `snail/build.zig` directly can call `module()` /
`rasterModule()` instead.

## Status

Alpha. The embeddable-only rewrite is complete (see
[CHANGELOG](CHANGELOG.md)); the Zig API is settling but breaking changes are
still expected. A C API against the current primitives is planned. Rendering
correctness is gated in CI-style build steps: CPU/GL/GLES/Vulkan
backend-compare, gamma and composite probes, and byte-identity checks for
`compact` and delta uploads.

## License

MIT.

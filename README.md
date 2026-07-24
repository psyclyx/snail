# snail

Text and vector rendering via direct Bezier curve evaluation, built to embed in your engine.

<img src="assets/banner.png?raw=true" alt="snail banner scene: styled and decorated text, complex-script shaping, vector primitives, gradients, and image paints">

snail renders text and vector art by evaluating Bezier curves at draw time. No bitmap glyph atlases, no signed distance fields. Glyphs and paths are resolution-independent and render correctly at any size, rotation, or perspective transform.

snail is a library, not a renderer: it owns no GPU objects, threads, caches, or eviction policy. It prepares data on the CPU and hands you texture contents, typed draw records, and entry-point-free shader fragments; your engine owns the textures, pipelines, uploads, and draw calls. An optional software renderer (`snail-raster`) covers hosts without a GPU.

This is alpha-quality software; see [Status](#status).

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

**3. Draw: one instanced quad per emitted record.** Each placed shape whose
atlas record contains curves becomes one instance of a quad bounding the
outline under its transform; empty records produce no draw work. `emit`
produces typed instances and coalesced batches, one instanced draw per batch.
A fragment maps its position back to glyph-local coordinates through the
inverse transform, which is why any affine or perspective transform (and
either y-axis convention) renders exactly on the GPU pipelines: all the math
from here on happens in the record's own space. The optional CPU rasterizer is
affine-only and reports `NonAffineMvp` for a perspective MVP.

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
var faces = try snail.Faces.build(alloc, &.{.{ .font = &font, .font_id = 0 }});
defer faces.deinit();
var shaped = try snail.shape(alloc, &faces, "Hello, world", .{});
defer shaped.deinit();

// Record: commit prepared glyph records into the store.
var pool = try snail.PagePool.init(alloc, .{
    .max_layers = 8, .curve_words_per_page = 1 << 17, .band_words_per_page = 1 << 14,
});
defer pool.deinit();
var atlas = try snail.Atlas.init(alloc, pool);
defer atlas.deinit();
try snail.recordUnhintedRun(&atlas, alloc, &faces, &shaped, .{});

// Upload: plan backend-neutral texel regions, copy them into YOUR textures.
const upload_options: snail.atlas_upload.Options = .{
    .max_bindings = 16,
    .layer_info_height = 64,
    .max_images = 16,
    .max_image_width = 2048,
    .max_image_height = 2048,
};
var planner = try snail.atlas_upload.OwnedPlanner.init(alloc, pool, upload_options);
defer planner.deinit();
const upload = try planner.plan(&atlas);
for (upload.regions) |r| try myEngine.texSubImage(r); // curve/band/layer_info/image
const binding = upload.binding;
// On a direct append-only child, planDelta emits only changed regions.
// Side-data growth must fit this binding's original fixed reservation;
// release and plan a fresh binding when it does not.

// Place + emit: shaped run -> Shapes -> typed instances and batches.
const shapes = try snail.placeRunAlloc(alloc, &shaped, null, .{
    .baseline = .{ .x = 48, .y = 92 }, .em = 34,
});
defer alloc.free(shapes);
_ = try snail.emit.emit(instances, batches, &ni, &nb,
    binding, &atlas, shapes, world_xform, .{ 1, 1, 1, 1 });
const records: snail.render.records.DrawRecords = .{
    .instances = instances[0..ni], .batches = batches[0..nb],
};

// Draw: your pipeline, your command buffer. One draw per batch and one quad
// per instance, using the generated stages from @import("snail_shaders").
```

If applying a successful `plan`/`planDelta` result fails, call
`planner.invalidateUploads()`, then retry the allocated slot with
`planDelta(binding, &atlas)`. Alternatively, release that binding before a
fresh `plan`. A returned `Binding` is valid only for the issuing planner/device
cache: identity includes the `PagePool`, the planner's `source_id`, a 64-bit
slot generation, and both storage offsets. Do not synthesize or partially
compare bindings in a device cache.

The complete, runnable version of this flow against a raw GL context is
[`src/demo/app/minimal_gl.zig`](src/demo/app/minimal_gl.zig) (`zig build
run-minimal-gl`) — it exercises the record verbs, paths, COLR, and the
delta-upload hot path. For a full engine-shaped integration (descriptor
layouts, multi-pass, Vulkan), read the demo's reference callers in
[`src/demo/render/gl/`](src/demo/render/gl) and
[`src/demo/render/vulkan/`](src/demo/render/vulkan). The software-renderer
flow is `snail-raster`'s `DeviceAtlas.upload` + `draw`:

```zig
const raster = @import("snail-raster");

var device = try raster.DeviceAtlas.init(alloc, pool, .{});
defer device.deinit();
var bindings: [1]snail.render.records.Binding = undefined;
try device.upload(alloc, &.{&atlas}, &bindings);

// Bindings are cache-specific, so emit against the DeviceAtlas binding.
var raster_ni: usize = 0;
var raster_nb: usize = 0;
_ = try snail.emit.emit(instances, batches, &raster_ni, &raster_nb,
    bindings[0], &atlas, shapes, world_xform, .{ 1, 1, 1, 1 });
const raster_records: raster.DrawRecords = .{
    .instances = instances[0..raster_ni], .batches = batches[0..raster_nb],
};

var renderer = try raster.Renderer.init(pixels, width, height, stride, .rgba8_unorm);
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
stride. Every draw also validates the declared surface size and selected
`PixelFormat`; choose a stride of at least
`width * format.bytesPerPixel()`. `DeviceAtlas.upload` requires exactly one
output binding per input atlas. If a multi-atlas call fails, none of the
bindings it planned remain live and every output entry from that call is
unusable, though successfully prepared shared page data may remain cached.
`raster.draw` supports affine scene-to-pixel transforms; a perspective MVP
returns `NonAffineMvp`.

### Capacity and eviction

The `PagePool` is the residency budget. Recording is idempotent (existing
keys are skipped) and fails with `error.OutOfLayers` when the pool is
exhausted — that is your eviction moment, and the policy is yours:
`Atlas.compact(alloc, scratch, filter)` rebuilds the store full-fidelity,
keeping only records the `RecordFilter` accepts (pass `null` to keep
everything, i.e. pure defragmentation). Compact acquires new pages before
releasing old ones, so evict while `pool.stats().pages_free` still provides
headroom, not only after failure. `PagePool.config()` returns the immutable
capacity configuration. Atlas page handles are opaque: storage, reservation,
publication, reference counting, and recycling stay private, and renderer
integrations receive immutable `atlas_upload.Region` copies.
`src/support/working_set.zig` is a worked example (demo-only, not shipped).

Each non-empty `Atlas.extendInPlace` call commits one persistent snapshot and
copies the atlas's flat page-pointer and paint-side-data arrays once. Bulk
callers should not put it in a one-entry loop: pass one entry slice, or use
`extendBatchesInPlace` to consume several producer slices in one transaction
without allocating a flattened array.

## Contracts

These are the fixed points a host must know. Everything else is explicit
per-call configuration.

**Colors are linear.** Every `[4]f32` color crossing the API is linear light
with straight (non-premultiplied) alpha. snail never interprets your colors;
gradients interpolate and tints multiply in linear light, and fragment output
is **premultiplied linear** — encode via an sRGB framebuffer or a resolve
pass (blend state: `ONE, ONE_MINUS_SRC_ALPHA`). For targets without
hardware sRGB encode, `snail-shaders` ships the generated linear-resolve
stages (float-intermediate seed/encode with premultiplication handled
correctly); the demo GL renderers show the orchestration. If you author in sRGB, convert once at the boundary with
`snail.color.srgbToLinearColor`.
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
pre-linearized data. `atlas_upload.Options.image_bytes_per_texel` declares the
host array format (4 by default); every planned image must match it and fit
`max_image_width` × `max_image_height`. `snail-raster` uses 4-byte RGBA,
sRGB-encoded, straight alpha.

**Shader targets.** The native Slang modules in `src/snail/shader/slang/`
are the source of truth. From them, the separate `snail-shaders` module
(`@import("snail_shaders")`) provides complete shaders for every supported
family/target combination across Vulkan SPIR-V, WGSL, GLSL 330, GLES 300,
D3D11 HLSL, and Metal MSL (generated/cross-checked on Linux and exercised by
the macOS GPU CI gate) — plus the binding-name contracts loaders bind by.
Artifacts are not checked in: they are generated at build time, in the zig
cache, only for builds that actually import the module — and per-target
scopes of the same API (`snail-shaders-gl`, `-glsl330`, `-wgsl`, `-hlsl`,
`-msl`) generate only their own targets, so e.g. a WebGPU consumer runs
`slangc` alone; the direct GLSL/GLES path also needs no second shader
compiler. Consumers of `snail`/`snail-raster` alone never need `slangc`.
Composition is
Slang-level too: a caller-authored family can `import text_sample` and
sample glyph coverage inside its own material shader — the game demo's
[`game_material.slang`](src/demo/game/slang/game_material.slang) is the
worked example. For OpenGL, prefer the driver-oriented complete stages in
the `snail-shaders-glsl330` / `snail-shaders-gl` module scopes. Slang emits
them directly, preserving authored helpers and structured control flow;
`colrFrag*` is specialized for solid-layer COLRv0 glyphs while `pathFrag*`
retains the general cubic/conic/gradient/image path engine. Compile only the
families a renderer actually draws; the reference GL/GLES renderer does this
lazily. `run-minimal-gl` demonstrates the generated-GL consumer route. WebGPU
is validated by the `run-minimal-wgpu` example against the GL reference.

**Render ABI.** Each packed instance is 72 bytes (18 words): an outward-rounded
f16 local bbox, affine transform/origin, glyph words, four payload words, and
linear-f16 color/tint. All 256 atlas layers are directly representable; packed
records are validated before a backend consumes them. Curves are RGBA16F,
bands RG16UI, layer-info RGBA32F, plus the host-formatted image array. Layouts
are versioned and documented in
`snail.render` (byte-layout contract for caller-owned renderers), the
`snail-shaders` module (per-target binding/name contracts of the generated
shaders), and the canonical Slang modules under `src/snail/shader/slang`.

**Ownership and lifetimes.** Every allocating call takes an explicit
allocator; the core preparation APIs keep no global or thread-local mutable
state. `Atlas` is value-typed
and persistent — `extend`/`compact` return new snapshots sharing retained,
refcounted page storage while preserving prior logical snapshot contents, and
lookups return records **by value**, so there is no entry-vs-eviction lifetime
hazard. Upload `Region`s alias planner scratch
(`layer_info`), live page memory (`curve`/`band`), or caller-owned `Image`
texels: apply them before the next `plan`/`planDelta`, and keep the atlas and
images alive and unchanged until the copies finish. A `PagePool` must outlive
every atlas, binding planner, and device cache created from it. `Font` borrows
the font bytes you pass it.

**Validation is part of the API.** `PagePool.init`, `Atlas.init`, upload
planner sizing/initialization, and software-renderer attachment are fallible.
Atlas insertion rejects malformed curve/band payloads; paints reject non-finite
parameters, invalid alpha/radius/image payloads, and strokes with invalid
widths or miter limits; paths reject non-finite geometry, invalid
rational-conic weights, and unrepresentable complexity;
`emit` rejects stale/foreign atlas records, invalid transforms, colors,
policies, cursors, and insufficient output. Atlas insertion, draw emission,
device resize, and renderer buffer replacement preflight or stage their work
so failure leaves their published state unchanged; a failed multi-atlas upload
releases every binding it planned but may retain prepared shared-page work.
Fixed-size multi-segment path commands reserve their complete append capacity
before mutation; lower-level adaptive construction remains explicitly
incremental. Propagate typed errors instead of treating them as asserts.

**Threading.** The core `snail` module does not create threads. Separate atlas handles, including
children of the same persistent snapshot, may be extended and destroyed on
different threads: shared HAMT/page references are atomic, `PagePool`
acquisition and identity minting are synchronized, and initialized curve/band
ranges are published as one ordered pair. Do not mutate or destroy the *same*
handle concurrently. Each concurrent build must also use a distinct allocator
or an allocator whose implementation is thread-safe; atomic atlas references
cannot make a caller's allocator safe. Planners and other mutable values remain
single-threaded unless documented. `snail-raster` has an optional caller-driven
`ThreadPool`.

## Text and hinting

`Faces.build` + `shape()` produce a `ShapedText` (HarfBuzz shaping, style
selection, fallback chains, OpenType features, source-range metadata).
Direction, script, and language can be explicit or left for HarfBuzz to infer:

```zig
const features = [_]snail.OpenTypeFeature{
    .{ .tag = "liga".*, .value = 1 },
    .{ .tag = "kern".*, .value = 0, .range = .{ .start = 0, .end = 8 } },
};
var shaped = try snail.shape(alloc, &faces, text, .{
    .direction = .rtl,
    .script = "Arab".*,
    .language = "ar",
    .features = &features,
});
defer shaped.deinit();
```

`direction` is run-level shaping direction, not paragraph bidi layout.
Feature ranges and each glyph's half-open `source_start..source_end` are UTF-8
byte offsets into the original input. Cluster ranges are complete in both LTR
and RTL output; glyph order follows HarfBuzz within each fallback-font run.
Every face supplies a stable `font_id`; all `Faces` values that feed the same
atlas must use the same id for the same font instance. Conflicting ids and
empty face sets are rejected. The fallback itemizer keeps font-sensitive
Unicode marks (using HarfBuzz's Unicode database), emoji, and Indic sequences
together; it is not a general-purpose UAX #29 segmenter. Invalid UTF-8,
feature ranges, empty/oversized language strings, ppem values, and missing
ppem for an advance provider are reported as errors. `Faces.fontIdForFace`
and `Faces.fontForFace` return `null` for an invalid index; HarfBuzz and
fallback-chain ownership stays in type-erased storage inside `Faces` rather
than leaking through inferable fields.

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
like glyphs. Paint remapping is fallible: radial records accept similarities,
and conic records accept orientation-preserving similarities; transforms that
would produce an ellipse, shear, or reversed conic sweep report
`UnsupportedTransform`.
`snail.snap` has pure pixel-grid helpers for rect edges and baselines.

## Modules

- **`snail`** — everything above: fonts, shaping, placement, atlas store,
  upload planning, emit, render/shader contracts. Links libc and system
  HarfBuzz; no GPU or windowing dependencies.
- **`snail-raster`** — optional software renderer: `DeviceAtlas` (host-side
  texture analog), `Renderer`, `draw`, explicit `TargetEncoding`/`PixelFormat`,
  linear-light blending, and optional subpixel AA. Its runtime fitter is wired
  as package-private build support and adds no caller-visible module.
- `src/demo`, `src/support`, `src/tools` — demos, reference GPU callers, and
  internal conveniences. Not published; copy freely.

Public-surface encapsulation is enforced by the source-only
[`src/tests/public_renderer_api.zig`](src/tests/public_renderer_api.zig) gate
and the generated-artifact
[`src/tests/public_shader_api.zig`](src/tests/public_shader_api.zig) gate,
which compile-error if internals leak or module boundaries regress.

## Build

Requires [Zig 0.16](https://ziglang.org/download/) and HarfBuzz (via
pkg-config). The complete shader-contract suite additionally needs `slangc`
and `naga`. Interactive demos need their corresponding window
system and graphics APIs (Wayland + EGL/OpenGL or Vulkan on Linux).

```sh
zig build test-core               # library/raster tests; no shader-generation tools required
zig build test                    # complete suite, including generated-shader and public-API gates
zig build run                     # interactive Wayland banner demo (C cycles backends)
zig build run-game                # interactive 3D scene: world-space text, custom material shader
zig build run-minimal-gl          # one-file public-API GL example → zig-out/minimal-gl.tga
zig build run-minimal-wgpu        # same scene through wgpu-native (WebGPU) → zig-out/minimal-wgpu.tga
zig build run-minimal-d3d11       # same scene through D3D11 (cross-compiled, runs under Wine) → zig-out/minimal-d3d11.tga
zig build run-minimal-metal       # same scene through Metal (macOS hosts; GPU-gated in CI) → zig-out/minimal-metal.tga
zig build check-metal-demo        # cross-compile the Metal example for aarch64-macos (any host)
zig build gen-shaders             # materialize generated shader artifacts into zig-out/shaders (needs slang+naga)
zig build run-banner-screenshot   # headless CPU render (also -gl, -gles30, -vulkan variants)
zig build run-algorithm-diagrams  # regenerate the README diagrams (snail rendering itself)
zig build run-backend-compare     # CPU vs GL divergence gate
zig build run-gamma-probe         # linear-blending / encode round-trip gate
zig build run-composite-probe     # perspective coverage-hole gate (GL)
zig build run-coverage-parity     # affine coverage-hole gate (CPU rasterizer)
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
correctness is gated in CI (GitHub Actions; the toolchain is the same
nix-pinned shell.nix used for local dev): the Linux job runs the unit
tests (including the byte-identity checks for `compact` and delta uploads),
the CPU-vs-GL backend-compare, the composite/coverage/coverage-parity
probes, the minimal GL example under llvmpipe, and the minimal D3D11
example under Wine, gated against `src/demo/app/minimal_reference.png`;
a Windows job re-runs the same cross-built D3D11 exe on a real Windows
runner (no Windows-side toolchain — it only executes artifacts built by
the nix job) and gates it with a dependency-free pixel comparator; a
macOS job runs the Metal example on a real GPU and gates it against the
same reference. The gamma probe and the GLES/Vulkan screenshot variants
remain local build steps.

## License

MIT.

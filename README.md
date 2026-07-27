<img src="assets/banner.png?raw=true" alt="snail banner: every size fits, illustrated by a blue-gray vector snail carrying a detailed golden-ratio shell construction" width="1280">

# snail

Text and vector rendering from Bézier curves, built to embed in an engine.

snail stores glyph outlines and vector paths as curves, then evaluates those
curves while drawing. It does not pre-render glyphs into bitmap atlases or
signed distance fields. An unhinted record has no baked pixel resolution: the
same prepared data can be reused across sizes, rotations, affine transforms,
and projective transforms on the GPU.

snail does not provide or own a GPU backend. The core library prepares CPU
data and emits texture uploads, typed draw records, native Slang modules, and
complete generated shader stages. Your engine owns GPU textures, pipelines,
uploads, command buffers, and draw calls. The optional `snail-raster` module
is an affine-only CPU backend.

This is alpha-quality software; see [Status](#status).

## Start here

### Text rendering in one minute

A **character** is part of a text encoding; a **glyph** is a drawable shape
chosen from a font. They are not one-to-one: a ligature can turn several
characters into one glyph, while a base character plus marks can produce
several positioned glyphs.

Text rendering therefore has two separate jobs:

1. **Shaping** turns UTF-8 text into glyph IDs, positions, and advances,
   following script, language, direction, OpenType features, and font
   fallback. snail uses HarfBuzz for this.
2. **Rasterization** determines how much of each screen pixel those glyphs
   cover. snail does this from the glyphs' mathematical outlines.

A font outline is one or more closed **contours** made from lines and Bézier
curves. Font coordinates are measured relative to the **em**, the font's
design-space unit square. **ppem** means pixels per em: roughly the rendered
text size in device pixels. **Hinting** moves outline features onto the pixel
grid at small sizes; unhinted outlines retain their natural geometry.

The word **atlas** here means a packed GPU lookup store, not a bitmap glyph
sheet. snail's atlas contains curves, band indexes, and optional paint
records.

| Work | Owner |
|---|---|
| Paragraph bidi, line breaking, wrapping, cursor/grapheme policy | Host |
| UTF-8 → positioned glyphs, style selection, font fallback | snail + HarfBuzz |
| Glyph/path preparation and persistent record storage | snail on the CPU |
| GPU resources, uploads, pipelines, and submission | Host |
| Optional affine software rendering | `snail-raster` |

snail is aimed at text or vector art that changes scale or orientation,
especially world-space and perspective-projected content. The tradeoff is
that the fragment shader solves candidate curve intersections instead of
performing a small fixed number of bitmap/SDF samples. Benchmark the actual
content and target hardware; a conventional cached bitmap renderer can be a
better fit for static, fixed-size UI text.

### Supported scope

- TrueType, CFF, and CFF2 outlines in OpenType containers, including font
  collections and selected variable-font instances.
- HarfBuzz shaping with styled face chains, fallback, explicit or inferred
  direction/script/language, OpenType features, and UTF-8 source ranges.
- Unhinted rendering, a resolution-independent draw-time autohinter, and
  TrueType bytecode hinting.
- General paths containing lines, quadratics, cubics, and rational conics;
  fills, strokes, solid colors, linear/radial/conic gradients, and images.
- COLRv0 color fonts. Other color-font formats are not currently supported.
- Grayscale analytic AA and optional LCD subpixel AA.

snail does not perform paragraph bidi, line breaking, wrapping, Unicode
grapheme or terminal-width policy, cursor movement, or image-file decoding.
See [Font format support](FONT_SUPPORT.md) for the detailed matrix and the
planned unified COLRv1/CBDT/`sbix`/SVG integration boundary.

## The pipeline

Everything is **shape → record → upload → emit → draw**.

`Atlas` is a persistent, value-typed CPU store. Recording and residency are
explicit: there is no hidden application-level glyph cache or eviction
policy.

```zig
const snail = @import("snail");

// Shape: parse fonts and turn UTF-8 into positioned glyphs.
var font = try snail.Font.init(font_bytes); // borrows font_bytes
var faces = try snail.Faces.build(alloc, &.{
    .{ .font = &font, .font_id = 0 },
});
defer faces.deinit();
var shaped = try snail.shape(alloc, &faces, "Hello, world", .{});
defer shaped.deinit();

// Record: prepare missing glyphs and commit them to the persistent store.
var pool = try snail.PagePool.init(alloc, .{
    .max_pages = 8, // may exceed 256 with a banked/flat backend
    .curve_words_per_page = 1 << 17,
    .band_words_per_page = 1 << 14,
});
defer pool.deinit();
var atlas = try snail.Atlas.initWithPacking(
    alloc, pool, .{ .recent_page_limit = 12 },
);
defer atlas.deinit();
try snail.recordUnhintedRun(&atlas, alloc, &faces, &shaped, .{});

// Upload: copy backend-neutral regions into textures owned by your engine.
const upload_options: snail.atlas_upload.Options = .{
    .max_bindings = 16,
    .layer_info_height = 64,
    .max_images = 16,
    .max_image_width = 2048,
    .max_image_height = 2048,
};
var planner = try snail.atlas_upload.OwnedPlanner.init(
    alloc, pool, upload_options,
);
defer planner.deinit();
const upload = try planner.plan(&atlas);
for (upload.regions) |region| try myEngine.texSubImage(region);

// Emit: place glyphs, then produce typed instances and coalesced batches.
const shapes = try snail.placeRunAlloc(alloc, &shaped, null, .{
    .baseline = .{ .x = 48, .y = 92 },
    .em = 34,
});
defer alloc.free(shapes);
_ = try snail.emit.emit(
    instances, batches, &instance_count, &batch_count,
    upload.binding, &atlas, shapes, world_xform, .{ 1, 1, 1, 1 },
);
const records: snail.render.records.DrawRecords = .{
    .instances = instances[0..instance_count],
    .batches = batches[0..batch_count],
};

// Draw: bind the generated stages from @import("snail_shaders").
// Submit one instanced draw per batch and one quad per instance.
```

The complete raw-OpenGL version is
[`dev/demo/app/minimal_gl.zig`](dev/demo/app/minimal_gl.zig), runnable with
`zig build run-minimal-gl`. Reference GPU integrations live under
[`dev/demo/render/gl`](dev/demo/render/gl) and
[`dev/demo/render/vulkan`](dev/demo/render/vulkan). The software-renderer
flow and the detailed upload, lifetime, color, threading, and ABI contracts
are in [Embedding snail](INTEGRATION.md).

`PagePool` is the resident page budget. Recording is idempotent and returns
`error.OutOfLayers` when a new record cannot acquire a page. The host chooses
what to evict; `Atlas.compact(..., filter)` rebuilds a retained working set.
Compaction needs free-page headroom because it acquires replacement pages
before the old snapshot releases its pages.

Font outlines containing only lines and quadratics use a two-texel dense
segment format; general paths retain the four-texel format. Page height is a
host budget (`curve_words_per_page` / `band_words_per_page`), not a fixed
shader dimension. Logical pages are allocated lazily. Array backends bank
them in groups of 256; flat typed-buffer backends address them with fixed
page strides. Either path avoids eviction solely because one texture array
is full. The default packer considers only the 12 most recent pages and
chooses the tightest fit across both curve and band capacity; set
`Atlas.Packing{ .recent_page_limit = 1 }` selects tail-only placement. The bounded window makes
insertion cost independent of total atlas size.

On a direct append-only atlas child, `planDelta` emits only changed page
regions and appended side data. Layer-info and image storage are fixed
reservations made by the original plan; release and create a fresh binding
if later side data no longer fits.

## Algorithm

snail implements the core coverage method described by Eric Lengyel:

- ["GPU-Centered Font Rendering Directly from Glyph Outlines"](https://jcgt.org/published/0006/02/02/), JCGT 2017
- ["A Decade of Slug"](https://terathon.com/blog/decade-slug.html), 2026
- [Public reference HLSL shaders](https://github.com/EricLengyel/Slug)

The Slug patent (US 10,373,352) was permanently dedicated to the public
domain effective March 17, 2026. snail is original code rather than code
copied from the Slug Library product or public reference shaders, and is
licensed under MIT.

### How it works

Rendering splits into a **preparation** phase on the CPU, once per record,
and a **draw** phase for every covered fragment. Outlines are not rasterized
ahead of time: the atlas stores curves and indexes. Caller-provided image
paints remain raster images.

**1. Prepare: outlines remain curves.** TrueType outlines use lines and
quadratic Béziers. CFF/CFF2 outlines and caller-authored paths can contain
cubics; paths can also contain rational conics. Cubics are split at axis
extrema and inflections, then adaptively approximated by tangent-preserving
quadratic chains. Endpoints and joins are preserved, and the approximation
uses a conservative error bound with a default tolerance of `1/8192` in
prepared coordinates (one em for normalized font outlines) and a maximum
subdivision depth of 10.

Every prepared line, quadratic, or conic segment occupies four `RGBA16F`
texels. Unhinted and autohint records are ppem-independent. TrueType
grid-fitted curve records are ppem-specific.

<img src="assets/algorithm-curves.png?raw=true" alt="a glyph outline with one highlighted quadratic segment, and its four texels in the curve texture" width="640">

**2. Prepare: bands index the curves.** The record's box is divided into
equal horizontal and vertical bands. Each band lists the segments whose
bounds overlap it, sorted by decreasing maximum coordinate so the evaluator
can stop once the remaining curves lie more than half a pixel behind the
sample.

The current packer chooses 1–12 bands per axis from the logical curve count;
the packed record format accepts up to 16. A curve that crosses several bands
appears in each of their lists and records its first member band for
draw-time deduplication.

<img src="assets/algorithm-bands.png?raw=true" alt="horizontal and vertical bands over the glyph, one band highlighted with the curves it references" width="640">

The atlas textures are curves (`RGBA16F`), bands (`RG16UI`), and layer-info
rows (`RGBA32F`), plus an optional host-formatted image array. Instance data,
the shared parameter block, samplers, pipelines, and command state are
separate host resources.

**3. Draw: emit one quad per non-empty instance.** A placed shape with curves
becomes one instance of a bounding quad; empty records produce no instance.
The vertex shader dynamically dilates the quad far enough in device space to
cover the grayscale-AA or LCD-filter footprint, including under perspective.

The fragment receives the corresponding record-local position and
derivatives. GPU pipelines support affine and projective transforms; the CPU
rasterizer supports affine transforms only and reports `NonAffineMvp` for a
perspective MVP.

<img src="assets/algorithm-quad.png?raw=true" alt="a transformed glyph in its bounding quad on screen, and a fragment mapped back to glyph space" width="640">

**4. Draw: the pixel footprint selects band spans.** This is a deliberate
departure from the public Slug shader. That shader selects one horizontal
band and one vertical band. snail instead maps both edges of the fragment's
record-local pixel footprint to band indexes and visits every band between
them.

This is not limited to two band lists: an extremely minified footprint can
span every band on either axis. Curves duplicated across touched bands are
evaluated once, at `max(first_member_band, first_touched_band)`.

<img src="assets/algorithm-sample-bands.png?raw=true" alt="a sample footprint with its horizontal and vertical band spans highlighted and their candidate curves emphasized" width="640">

**5. Draw: classify and solve ray crossings.** The evaluator casts
axis-aligned rays through the sample. For a quadratic, the signs of its three
sample-relative control coordinates index Slug's `0x2E74` eligibility table.
That exact classification says whether zero, one, or two roots contribute
before the polynomial roots are used for their crossing positions.

snail normalizes sample-relative coordinates within `1/65536` of zero to
positive zero so adjacent segments retain one half-open shared-endpoint
decision after f16 storage and transform/subtraction drift. The quadratic
solver uses a cancellation-resistant Vieta form. Lines use the same
half-open sign convention; rational conics use the quadratic eligibility
code on their weighted control values before solving their rational
crossings.

<img src="assets/algorithm-roots.png?raw=true" alt="horizontal and vertical rays through the sample with signed root crossings marked" width="640">

**6. Draw: signed crossings produce winding coverage.** A crossing adds or
subtracts according to its direction. Horizontal and vertical results are
combined using edge-proximity weights, with a conservative fallback near
tangencies. General paths then apply their `non_zero` or `even_odd` fill rule
once to the resolved winding coverage. Oppositely wound hole contours cancel
without special hole handling.

<img src="assets/algorithm-winding.png?raw=true" alt="two samples with their rays: crossings sum to w=1 in the ring and cancel to w=0 in the hole" width="640">

**7. Draw: nearby crossings become fractional coverage.** A crossing within
half a device pixel of the sample contributes a fraction rather than a
binary inside/outside value. This is analytic antialiasing without a
prefiltered glyph image.

Coverage multiplies the resolved solid, gradient, or image paint, producing
premultiplied linear color. The stage can leave that value linear for a
linear or hardware-sRGB attachment, or encode it when sRGB pixels must be
written through a linear attachment. Grayscale AA evaluates one analytic
sample per pixel. LCD modes evaluate seven samples at one-third-pixel phases
along the display stripe axis, then use a five-tap filter to form RGB
coverage.

<img src="assets/algorithm-alpha.png?raw=true" alt="device pixels along a zoomed edge shaded by fractional analytic coverage" width="640">

The diagrams are rendered by snail itself. `zig build
run-algorithm-diagrams` writes their TGA sources to `zig-out/`.

### Differences from the public Slug reference

The winding method, `0x2E74` root eligibility, directional coverage
combination, half-pixel analytic ramp, sorted-curve early-out, `RG16UI` band
data, and dynamic dilation follow the current public reference.

| Public reference shader | snail |
|---|---|
| Selects one horizontal and one vertical band list at the sample center | Visits every band touched by the local pixel footprint and deduplicates shared curves |
| Evaluates quadratic Béziers | Evaluates lines, quadratics, and rational conics; cubics are lowered on the CPU |
| Stores a quadratic in two curve texels, often sharing endpoints | Uses two direct texels for font lines/quadratics; general paths use four for kind and conic metadata |
| Uses raw floating-point sign bits for root eligibility | Snaps values within `1/65536` of the ray to positive zero before using the same table |
| Uses the direct quadratic formula | Uses a cancellation-resistant, order-preserving Vieta form |
| Accepts a caller-built bounding polygon | `emit` always produces a simple quad and the vertex shader dilates its four corners |
| Covers the core GPU quadratic renderer | Adds shaping, fallback, CFF/CFF2, paths and paints, hinting, LCD modes, persistent atlas/upload APIs, and a CPU backend |

The band-span behavior is implemented in
[`coverage_common.slang`](src/snail/shader/slang/coverage_common.slang) and
used by regular text, COLRv0, hinted text, subpixel text, sampled text, and
general paths. The CPU mirror is
[`src/snail-raster/coverage.zig`](src/snail-raster/coverage.zig). Band
construction and its 12-band heuristic are in
[`band_texture.zig`](src/snail/format/band_texture.zig).

## Text and hinting

`Faces.build` creates reusable HarfBuzz shaping state over caller-owned
`Font` values. `shape()` performs style selection, fallback itemization, and
shaping, returning glyph IDs, em-space positions, resolved `font_id` values,
and half-open UTF-8 source-byte ranges.

Direction, script, and language can be explicit or inferred:

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

`direction` is run-level shaping direction, not paragraph bidi. Glyph order
follows HarfBuzz within each fallback-font run. The fallback itemizer keeps
its supported font-sensitive marks, emoji sequences, and Indic sequences
together; it is not a general UAX #29 segmenter.

Every face has a caller-assigned `font_id`. Within one retained atlas, the
same ID must always identify the same stable `Font` pointer, including its
selected face and variable coordinates.

Choose a hinting path according to the content:

| Mode | Use it for | Record and placement behavior |
|---|---|---|
| `.unhinted` | Scalable or transformed content; the default | `recordUnhintedRun`; one ppem-independent curve record reusable at subpixel positions |
| `.autohint = policy` | Small UI/terminal text without relying on font bytecode | `recordAutohintRun`; one ppem-independent analysis, fitted at draw time by the instance policy |
| `.tt_hint = .{ .ppem_26_6 }` | TrueType fonts whose native instructions should control small-size fitting | `recordTtHintRun`; ppem-specific curves and advances produced by `TtHintVm` |

TrueType bytecode hinting applies only to TrueType outlines and rejects a
selected variable-font instance. The autohinter is outline-format agnostic
and supports TrueType, CFF/CFF2, and selected variable instances.

Strong x-axis autohint policies and TrueType hinting need integer
device-pixel glyph origins. Use `RunSnap.origins` for proportional text or
`.columns` for monospace grids, supplying
`world_to_pixel = mvpToScenePixel(mvp, fb_width, fb_height)`. Snapped shapes
are tied to that transform; unsnapped shapes remain content-only.

For measurement with TrueType-hinted advances,
`recordTtAdvanceRun` stores page-free advance records and
`TtAdvanceSource` feeds them back into `shape()` as an `AdvanceProvider`.

Terminal integrations should use `placeCellRun`, which preserves HarfBuzz
cluster offsets while the host supplies exact source ranges and columns. See
[Terminal-style cell grids](TERMINAL.md) and the
[`run-terminal`](dev/demo/app/terminal.zig) example.

General paths use the same atlas and draw pipeline. Author a `Path`, call
`prepare`, obtain fill or stroke curves, and place the result with a
transform. Paint remapping can fail: radial records accept similarities and
conic records accept orientation-preserving similarities; an ellipse, shear,
or reversed conic sweep returns `UnsupportedTransform`.

## Integration contracts

The full contracts are in [Embedding snail](INTEGRATION.md). The points
most likely to affect a first integration are:

- **Colors:** paint, tint, placement, and instance `[4]f32` colors are
  linear-light with straight alpha. Coverage first produces premultiplied
  linear color; the target policy decides whether the stage encodes it.
  `LinearResolve.Backdrop.clear` is the explicit sRGB-input exception. CPAL
  colors are converted from sRGB during extraction.
- **Y axis:** font geometry is y-up; placement selects a y-down or y-up scene.
- **Images:** the core stores opaque tightly packed texels. The backend must
  sample them as linear color with straight alpha.
- **Lifetimes:** `Font` borrows bytes; `Faces` borrows `Font` pointers;
  upload regions borrow planner, atlas, or image memory; `PagePool` outlives
  every related atlas/planner/device cache.
- **Threading:** separate atlas handles may be used on separate threads, but
  the same mutable handle may not. `Faces`, `TtHintVm`, and planners are
  single-threaded unless documented otherwise.
- **CPU transform limit:** `snail-raster` supports affine transforms, not
  perspective.

Generated complete shaders cover Vulkan SPIR-V, WGSL, GLSL 330, GLES 300,
D3D11 HLSL, and Metal MSL. The authored source of truth is
[`src/snail/shader/slang`](src/snail/shader/slang). The render ABI is
versioned; each packed instance is 72 bytes (18 words). Instances carry an
8-bit bank-local layer while draw batches carry the aligned logical-page
base, so one pool can address up to 65,536 pages.

## Modules

- **`snail`** — fonts, shaping, placement, paths, paints, atlas storage,
  upload planning, draw emission, and render contracts. It links libc and
  system HarfBuzz, with no GPU or window-system dependency.
- **`snail-raster`** — optional software `DeviceAtlas`, `Renderer`, and
  `draw`, including linear-light blending and subpixel AA.
- **`snail-shaders*`** — generated complete stages and reflected binding
  contracts. Import only the target scope needed by the host.
- `src/snail` and `src/snail-raster` — the only hand-written runtime
  packages. The raster package's helper modules are private implementation
  details wired into the published `snail-raster` module.
- `dev` — development-only tests, tools, asset support, demos, and complete
  reference renderers. In particular, the OpenGL and Vulkan code here is
  caller-owned example code, not a Snail GPU backend or public runtime
  module.

Public module boundaries are gated by
[`dev/tests/public_renderer_api.zig`](dev/tests/public_renderer_api.zig) and
[`dev/tests/public_shader_api.zig`](dev/tests/public_shader_api.zig).

## Build

The core requires [Zig 0.16](https://ziglang.org/download/) and HarfBuzz via
pkg-config. Shader generation requires `slangc`; the repository's complete
shader-validation suite also uses `naga`. Interactive demos require the
corresponding window system and graphics API.

```sh
zig build test-core               # core + software renderer; no shader tools
zig build test                    # complete generated-shader/API suite
zig build run-minimal-gl          # public-API GL example → zig-out/minimal-gl.tga
zig build run-terminal            # incremental terminal cell grid
zig build run-game                # perspective text in a custom material
zig build run-banner-screenshot   # headless CPU reference render
zig build run-backend-compare     # CPU/GL divergence gate
zig build gen-shaders             # materialize every generated shader target
```

Other useful gates include `run-minimal-wgpu`, `run-minimal-d3d11`,
`run-minimal-metal`, `check-metal-demo`, `run-composite-probe`,
`run-coverage-parity`, and `run-gamma-probe`. Run `zig build -l` for the full
list.

With Nix: `nix-build -A demo`, or enter `nix-shell` for the complete
development toolchain.

To regenerate the README images after rendering their TGA sources:

```sh
magick zig-out/banner.tga assets/banner.png
for image in curves bands quad sample-bands roots winding alpha; do
  magick "zig-out/algorithm-${image}.tga" "assets/algorithm-${image}.png"
done
```

### As a dependency

```sh
zig fetch --save git+https://github.com/psyclyx/snail
```

```zig
const snail_dep = b.dependency("snail", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("snail", snail_dep.module("snail"));
exe.root_module.addImport("snail-raster", snail_dep.module("snail-raster"));
exe.root_module.addImport(
    "snail_shaders",
    snail_dep.module("snail-shaders-glsl330"),
);
```

Use these named modules instead of constructing modules from
`snail_dep.path("src/...")`. The named `snail-raster` module already contains
all of its implementation wiring and depends only on the named `snail`
module. Shared backend-neutral target values live at `snail.render.target`.
Passing `target` and `optimize` to `b.dependency` binds all selected Snail
modules to the consumer's build configuration.

Other shader scopes are `snail-shaders-vk` (Vulkan SPIR-V only),
`snail-shaders-gl` (GLSL 330 + GLES 300), `snail-shaders-wgsl`,
`snail-shaders-hlsl`, and `snail-shaders-msl`. `snail-shaders` includes every
target and runs the generated-artifact validations. Omit shader imports when
using only `snail` or `snail-raster`.

### Custom shader families

To draw your own effects through snail's pipeline, author a Slang family that
`import`s snail's caller-facing modules — the pattern the game demo uses in
[`dev/demo/game/slang/game_material.slang`](dev/demo/game/slang/game_material.slang).
snail publishes its Slang module catalog as the `snail_slang` named lazy path;
hand it to `slangc` via `-I` and compile for your target:

```zig
const snail_dep = b.dependency("snail", .{ .target = target, .optimize = optimize });

const compile = b.addSystemCommand(&.{
    "slangc",
    "-DSNAIL_TARGET_VULKAN", "-target", "spirv", "-profile", "spirv_1_3", "-O2",
    "-default-image-format-unknown",
    "-entry", "fragmentMain", "-stage", "fragment",
    "-I",
});
compile.addDirectoryArg(snail_dep.namedLazyPath("snail_slang"));
compile.addFileArg(b.path("shaders/my_material.slang"));
const spv = compile.addPrefixedOutputFileArg("-o", "my_material.frag.spv");
// embed `spv` in your app.
```

The reflected `snail-shaders*` binding contract still describes the vertex
format and push constants, so a family that reuses snail's inputs stays
layout-compatible with the built-in ones. The complete per-target flag matrix
(defines, profiles, and GL/WGSL/Metal quirks) lives in
[`build/slang_shaders.zig`](build/slang_shaders.zig), and the
[`src/snail/shader/slang/README.md`](src/snail/shader/slang/README.md)
lists the public modules you can `import`.

## Status

Alpha. The embeddable-only rewrite is complete; the Zig API is settling but
breaking changes remain possible. See the [changelog](CHANGELOG.md).

CI runs the unit/public-API suites and generated shader contracts; CPU/GPU
image comparison; coverage, composite, gamma, and screenshot probes; Vulkan,
WebGPU, D3D11, and software consumer builds; and real Metal execution on
macOS. The pinned local toolchain is the same one described by `shell.nix`.

## License

MIT.

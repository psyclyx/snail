# snail

Text and vector rendering via direct Bezier curve evaluation.

<img src="assets/demo_screenshot.png?raw=true" alt="snail demo scene">

snail renders text and vector art by evaluating Bezier curves at draw time. No bitmap glyph atlases, no signed distance fields. Glyphs and paths are resolution-independent and render correctly at any size, rotation, or perspective transform. GPU backends run this in shaders; the CPU backend uses the same prepared atlas data in software.

This is alpha-quality software. The Zig API and C API are settling but not yet stable, and breaking changes are expected.

## Algorithm

This is an implementation of the [Slug algorithm](https://sluglibrary.com/):

- Eric Lengyel, ["GPU-Centered Font Rendering Directly from Glyph Outlines"](https://jcgt.org/published/0006/02/02/), JCGT 2017
- Eric Lengyel, ["A Decade of Slug"](https://terathon.com/blog/decade-slug.html), 2026
- [Reference HLSL shaders](https://github.com/EricLengyel/Slug) (MIT / Apache-2.0)

The Slug patent (US 10,373,352) was [dedicated to the public domain](https://terathon.com/blog/decade-slug.html) in March 2026. This implementation is original code, not derived from the Slug Library product. Licensed under MIT.

### How it works

snail turns immutable text, path, and image inputs into renderer-specific
prepared resources, then draws compact records that reference those resources.
The draw call itself does not parse fonts, upload textures, allocate memory, or
discover missing resources.

**Text input.** `TextAtlas` parses TrueType `cmap`, `glyf`/`loca`, metrics,
legacy `kern`, decoration/script metrics, and `COLR` color layers. HarfBuzz is
used when enabled; otherwise the built-in shaper covers GSUB ligatures (type 4)
and GPOS pair positioning (type 2). `shapeText` is the default; `shapeTextOpts`
threads explicit `OpenTypeFeature` requests (tag + value + optional source
range) when callers need to toggle ligatures, alternates, etc. The result is a
`ShapedText` whose glyph stream is the single source of truth for advance;
free-function transforms (`snail.track`, `snapAdvances`, `shiftBaseline`,
`spaceWords`) mutate it in place between shape and blob construction.
`ensureText`, `ensureShaped`, and `ensureGlyphs` extend the immutable atlas by
returning a new snapshot.

**Vector input.** `PathPictureBuilder` freezes filled/stroked `Path` geometry
into an immutable `PathPicture`. Fills preserve line, quadratic, rational conic,
and cubic segments; strokes are expanded into offset curves with the requested
caps and joins.

**Atlas data.** Glyph and path outlines stay as curves. Preparation packs those
curves plus a small lookup structure into atlas pages:

- *Curve texture* (RGBA16F): one curve segment occupies four texels, localized to
  a glyph/path origin and stored directly or as an anchor plus f16 deltas.
- *Band texture* (RG16UI): horizontal and vertical bands list only the curves
  that can affect samples in that band.
- *Layer records* (RGBA32F): bounds, band transforms, paint records, color-font
  layers, composite groups, and optional per-size TrueType hint records.

The first preparation step keeps the outline as curve data. The highlighted
outline segment below is the same curve shown as a stored atlas record; there is
no pre-rendered glyph bitmap.

<img src="assets/algorithm-curves.png?raw=true" alt="snail-rendered diagram of a highlighted outline curve stored as an atlas curve record" width="320">

The second preparation step builds lookup bands. A band stores the IDs of curves
that can affect samples in that horizontal or vertical slice.

<img src="assets/algorithm-bands.png?raw=true" alt="snail-rendered diagram of horizontal and vertical bands producing band lists of curve records" width="320">

This preprocessing is CPU-only. GPU backends upload the prepared data into 2D
texture arrays, one layer per atlas page. The CPU backend reads equivalent
prepared snapshots in software.

**Draw records.** A `Scene` borrows `TextBlob` and `PathPicture` values.
`PreparedScene` or `DrawList.addScene` resolves those submissions against
`PreparedResources` into packed draw records. Records are validated with resource
stamps before drawing, so stale or missing resources fail explicitly.

**Coverage evaluation.** Text glyphs and path shapes are emitted as ordinary
quads. The quad only bounds where the outline may appear; each fragment/sample
is mapped back into local outline coordinates.

<img src="assets/algorithm-quad.png?raw=true" alt="snail-rendered diagram of a glyph drawn as a quad with a fragment mapped to local coordinates" width="320">

The shader or CPU rasterizer chooses the horizontal and vertical bands touched
by that local sample and walks only the candidate curves referenced by those
band lists.

<img src="assets/algorithm-sample-bands.png?raw=true" alt="snail-rendered diagram of a sample selecting horizontal and vertical bands to find candidate curves" width="320">

For each candidate curve, snail solves the ray/Bezier root equation at the
sample coordinate. The text path uses the TrueType quadratic fast path; vector
paths handle lines, quadratics, rational conics, and cubics.

<img src="assets/algorithm-roots.png?raw=true" alt="snail-rendered diagram of horizontal and vertical ray roots through a local sample" width="320">

Each root has a sign. The signed crossings accumulate into a winding value: in
the toy outline below, the filled sample has `w=+1`, while the hole sample has
opposite crossings that cancel to `w=0`.

<img src="assets/algorithm-winding.png?raw=true" alt="snail-rendered diagram of signed curve roots accumulating to winding values" width="320">

Horizontal and vertical estimates are weighted together. The configured fill
rule (`nonzero` or `even_odd`) maps the winding value to inside/outside, and
roots within half a pixel of the sample produce fractional edge coverage for
the final alpha.

<img src="assets/algorithm-alpha.png?raw=true" alt="snail-rendered diagram of winding and edge coverage mapping to final alpha" width="320">

Grayscale antialiasing samples once per pixel. LCD subpixel modes take offset
samples along the display's RGB/BGR or vertical subpixel axis and filter them
into per-channel coverage. There is no bitmap glyph atlas, no distance field,
and no texture sample that represents a pre-rasterized glyph shape.

**Optional TrueType hints.** The default text path is unhinted and
resolution-independent. Zig callers can opt into per-size TrueType
bytecode execution with `TrueTypeHintContext`, then freeze the result
into a **`GlyphHintSnapshot`** — an immutable, per-(atlas, hint-context,
ppem) value that carries absolute hinted control points. A hinted draw
consults the atlas (band lookup) and the snapshot (outline geometry);
the snapshot is bound to a `TextBlobBundle` via `bindHintSnapshot`, and
many bundles can share one snapshot. The atlas itself stays
PPEM-independent — hinting introduces a parallel resource, not a
mutation. `prepareRun` is whole-run: every glyph comes back either
hinted or with a per-glyph `.fallback` marker. Fallback glyphs render
unhinted curves but their advances are still snapped to whole pixels at
the chosen PPEM, so columns of text grid-align even when individual
glyphs can't be hinted (font has no bytecode, hits a topology mismatch,
etc.). Faux-bold faces hint normally; the embolden offset is applied as
a render-time second copy. Faces whose `gasp` table explicitly disables
grid-fitting at a given size keep their original advances.

## Color convention

All color parameters are **sRGB, straight (unpremultiplied) alpha**, as `[4]f32` in the range 0.0–1.0. This applies to `Paint.solid`, gradient stops, `ImagePaint.tint`, and text color arguments. The renderer premultiplies alpha and linearizes for blending internally.

**Images** (`Image.initSrgba8`) expect sRGB-encoded RGBA8 pixel data (4 bytes per pixel, 0–255). This is what most image decoders produce. Linear-space pixel buffers will appear too bright.

**Gradients** interpolate in sRGB space, which gives perceptually smooth results for UI use. `LinearGradient` and `RadialGradient` provide extend modes for clamp, repeat, and reflect behavior.

**Blending** uses premultiplied alpha. Shaders decode sRGB inputs to linear before applying coverage. On GL/Vulkan sRGB attachments, fixed-function attachment encoding handles linear->sRGB storage and gamma-correct blending. On linear attachments or CPU buffers, `DrawState.surface.encoding` states what the attachment accepts and what final pixel bytes the consumer expects.

**Output encoding.** `TargetSurface.encoding` is required on every draw:

- `TargetEncoding.srgb`: normal GL/Vulkan `_SRGB` attachment or swapchain image; the attachment does the final encode.
- `TargetEncoding.linear`: linear UNORM/float targets or CPU buffers whose bytes should stay linear.
- `TargetEncoding.srgb_pixels_on_linear_attachment`: linear-format storage, including CPU byte buffers, whose consumer expects sRGB bytes. With the default direct resolve, fixed-function blending happens in storage space; this is a compatibility path for targets that cannot be tagged as sRGB, not a gamma-correct composition path.

`LinearResolve` is an explicit backend pass for gamma-correct Snail composition into sRGB pixels on a linear attachment:

- Draw with `DrawPass.linear(state, resolve)` and `TargetEncoding.srgb_pixels_on_linear_attachment`.
- `LinearResolve.backdrop` chooses whether to seed from the target, a clear color, transparent black, or unspecified contents.
- `LinearResolve.region` can restrict the resolve to a pixel rectangle.
- `LinearResolve.intermediate_format` selects RGBA16F or RGBA32F for GL.

The CPU renderer has no format-level encoder: it writes RGBA8 bytes according to `encoding.stored_pixels`. It uses an exact 256-entry sRGB->linear LUT for u8 texels and the IEC 61966-2-1 formula directly for linear->sRGB output, with round-to-nearest rounding.

**Coverage transfer.** `DrawState.raster.coverage_transfer` optionally remaps analytic coverage before blending. The default is identity; `CoverageTransfer.power(exponent)` exposes explicit display tuning when a target benefits from slightly stronger or lighter antialiasing.

## Ownership and Lifetimes

Snail separates immutable source values, resource declaration, backend
residency, and draw commands. Keep those roles distinct when building an
application around it.

| Type | Owns | Borrows | Lifetime rule |
|------|------|---------|---------------|
| `TextAtlas` | Atlas pages and metadata allocated by its allocator. | Text configuration and source font data through the configuration. | Immutable snapshot. Any blob or manifest entry that points at it must not outlive it. |
| `TextBlobBundle` | Arena holding many `TextBlob`s and their glyph/paint content. Holds an optional `*const GlyphHintSnapshot` reference for hinted text. | A compatible `TextAtlas`; optionally a `GlyphHintSnapshot` derived from that atlas. | Owns blob lifetimes. `reset` invalidates every outstanding blob borrowed from the bundle; `rebindAtlas` retargets to a compatible superset; `bindHintSnapshot` pins the bundle's hinted-outline source. The snapshot uploads once per `(atlas, hint-context, ppem)` — many bundles can share one. |
| `GlyphHintSnapshot` | Immutable per-(atlas, hint-context, ppem) snapshot of hinted outlines: absolute control points and band-reuse tags. | Built by `TrueTypeHintContext.snapshot(allocator, options)`. | Bound to a `TextBlobBundle` via `bindHintSnapshot`; many bundles can share one snapshot. The manifest dedupes on snapshot identity. |
| `TextBlob` | A view into bundle-owned glyph/paint storage. | The bundle that produced it and that bundle's `TextAtlas`. | Immutable snapshot, pointer-stable until the bundle is reset/deinit'd. |
| `PathPicture` | Frozen path atlas/layer records allocated by its allocator. | Nothing after freeze. | Immutable snapshot. Can be declared in a manifest by pointer. |
| `Image` | Pixel storage according to the image constructor. | Nothing unless explicitly documented by the constructor. | Immutable render resource while it is declared in a manifest. |
| `ResourceManifest` | Only its caller-provided entry buffer. | `TextBlob`/`TextAtlas`, `PathPicture`, and `Image` values. | A declaration list. Upload planning may inspect it, but insertion should not imply backend effects. |
| `PreparedResources` | Logical resource bindings plus backend residency state. | Renderer-owned GPU caches where applicable. | Draw APIs take this value so logical validation and backend sampling stay together at the call boundary. Retire it only after no in-flight draw can reference it. |
| `Scene` | Command storage. | Submitted `TextBlob`/`PathPicture` values and override slices. | A borrowed command list; it does not make resources resident or keep them alive. |
| `PreparedScene` | Draw-record words and segments. | `PreparedResources` compatibility through recorded stamps. | Rebuild it when the source scene or prepared resources change. |

Upload has one ordered ownership flow: inspect a manifest, plan resource work,
allocate scratch for that plan, execute backend upload, then publish prepared
views. Scheduled uploads own their plan and destination resources until they are
published or cancelled; the renderer/backend they borrow must outlive them.

C handles are owned by Snail and must be released by the matching `*_deinit`
function. The C API copies the `SnailAllocator` descriptor when a handle is
created; the descriptor pointer may be stack-local, but its callbacks and
`ctx` must remain valid until every handle or derived snapshot using it has
been destroyed. Resetting a handle may retain capacity; destroying it releases
that capacity.

## Hinting And Pixel Snapping

Snail's default text path is unhinted. It does not apply hidden render-time
snapping or mutate glyph positions during draw. For static UI text, align the
values you care about before building a `TextBlob`. The snapping API is
deliberately value-based: compute a step for the coordinate space you are using,
then snap positions, lengths, or rectangles.

```zig
const step = snail.pixelSteps(.{ logical_w, logical_h }, .{ framebuffer_w, framebuffer_h });

var baseline = snail.Vec2{ .x = raw_x, .y = raw_y };
baseline = snail.snapPointToStep(baseline, step, .nearest);

const em = snail.snapLengthToStep(raw_em, step.y, .nearest, 1.0);

_ = try bip.append(.{
    .source = .{ .shaped = shaped.glyphs },
    .placement = .{ .baseline = baseline, .em = em },
    .fill = .{ .solid = color },
});
```

For LCD text, snap the stripe axis to thirds of a pixel and the other axis to a
full pixel:

```zig
baseline.x = snail.snapToStep(raw_x, step.x / 3.0, .nearest);
baseline.y = snail.snapToStep(raw_y, step.y, .nearest);
```

For decorations, snap the geometry separately:

```zig
var underline = try atlas.decorationRect(.underline, baseline.x, baseline.y, advance, em);
underline.y = snail.snapToStep(underline.y, step.y, .nearest);
underline.h = snail.snapLengthToStep(underline.h, step.y, .nearest, 1.0);
```

For terminal or grid layouts, snap the cell metrics you use for placement, then
advance by those snapped values:

```zig
const raw_cell = try atlas.cellMetrics(.{ .style = .{}, .em = raw_em });
const cell_w = snail.snapLengthToStep(raw_cell.cell_width, step.x, .nearest, 1.0);
const line_h = snail.snapLengthToStep(raw_cell.line_height, step.y, .nearest, 1.0);
```

Callers that want grid-fitted small text can opt into explicit TrueType
hinting for a chosen ppem. Hinting is the one place snail deliberately
gives up PPEM-independence: the atlas (`TextAtlas`) stays the same
immutable, PPEM-independent value, but rendering also needs a
**`GlyphHintSnapshot`** — an immutable, per-(atlas, hint-context, ppem)
value carrying absolute hinted control points derived from that atlas at
that ppem. A hinted draw consults both the atlas (band lookup) and the
snapshot (outline geometry). A bundle binds one snapshot; many bundles
can share one snapshot, and the manifest dedupes on snapshot identity.

```zig
var hint_context = snail.TrueTypeHintContext.init(allocator, &atlas);
defer hint_context.deinit();

var shaped = try atlas.shapeText(allocator, .{}, "Small text");
defer shaped.deinit();

var hinted = try hint_context.prepareRun(allocator, .{
    .shaped = &shaped,
    .ppem = snail.TrueTypeHintPpem.uniform(12 * 64),
});
defer hinted.deinit();

// Freeze the hint context's cache into an immutable snapshot, then bind
// it to the bundle. The snapshot is the per-PPEM hinted-outline value.
var hint_snapshot = try hint_context.snapshot(allocator, .{});
defer hint_snapshot.deinit();
try bundle.bindHintSnapshot(&hint_snapshot);

_ = try bip.append(.{
    .source = .{ .hinted = hinted.glyphs },
    .placement = .{ .baseline = baseline, .em = 12 },
    .fill = .{ .solid = color },
});
```

`prepareRun` always covers every glyph of `shaped`; each entry carries
either a hint pointer or a `.fallback` marker. Strict callers check
`hinted.stats.fallback_count == 0` before consuming the run. Fallback
glyphs render via unhinted curves but their advances are pixel-snapped
at the hint context's PPEM so adjacent glyphs still grid-align.

Band reuse: a snapshot reuses the atlas's per-glyph band table when the
hinted outline preserves band membership and ordering. When hinting
shifts a curve across a band boundary (rare at typical body-text ppems),
the snapshot records an `expanded_bands` padding count and the renderer
expands its sampling span accordingly; ordering breaks are flagged with
`unordered_bands` and disable the early-exit on each band scan. Both are
contractual properties of the snapshot, not implementation tricks: a
snapshot whose `proveBandReuse` succeeds is bit-for-bit cheaper to
render than one that needs padding, but both produce the same coverage.

Snapshot dedup: many `TextBlobBundle`s built from the same
`(atlas, hint_context, ppem)` reference one snapshot; the manifest
dedupes on the snapshot's identity, so the GPU upload is one hint slab
per snapshot rather than per bundle — important for terminals, chat/log
windows, and other workloads with many small blobs over the same
character set.

C uses the same model through `SnailTrueTypeHintContext`,
`SnailTrueTypePreparedHintRun`, `SnailGlyphHintSnapshot`, and the
`SnailTextBlobBundle`/`SnailBlobInProgress` builder pair. Call
`snail_true_type_hint_context_snapshot` after preparing hint runs, bind
it via `snail_text_blob_bundle_bind_hint_snapshot`, then append. If
`snail_true_type_hint_context_init` returns `SNAIL_ERR_HINT_UNAVAILABLE`
for a face with no TrueType bytecode, fall back to
`snail_blob_in_progress_append_shaped` or
`snail_text_blob_init_from_shaped`.

The usual rule is to snap the run baseline and preserve glyph advances.
Per-glyph origin snapping or hinted runs can make tiny static text look more
grid-fitted, but both are per-size choices. If text is later rotated, scaled,
animated, or drawn through a non-axis-aligned MVP, snap in the final space or
leave it unhinted.

## Hint Cache Lifecycle

`TrueTypeHintContext` caches three independent tiers as you call
`prepareRun`/`computeGlyph`:

| Tier | Keyed by | Cost to build | Cost per entry | Reuse pattern |
|---|---|---|---|---|
| Face programs | `face` | One-time bytecode parse | Small (kilobytes) | Bounded by font count; never needs eviction. |
| Size states | `(face, ppem)` | Expensive — runs `fpgm`/`prep` setup, allocates VM tables | ~5–50 KB | Reusable across every glyph at that PPEM. |
| Glyph values | `(face, ppem, glyph_id)` | Cheap once the size state is warm | ~80–800 B (curve points) | Populous. The tier that actually grows. |

Snail ships **mechanism, not policy**: the context exposes inspection and
eviction verbs but does not auto-evict, set capacity limits, or apply LRU.
Pick a policy that matches your workload.

| Verb | Effect |
|---|---|
| `ctx.byteFootprint() Footprint` | Per-tier counts and byte totals. Drives any eviction decision. |
| `ctx.sizeKeyIterator()` / `ctx.glyphKeyIterator()` | Walk cached entries to choose victims; collect keys first, then evict. |
| `ctx.evictSize(face, ppem)` | Drop the PPEM's VM state and every glyph value at that `(face, ppem)`. |
| `ctx.evictPpem(ppem)` | Same as `evictSize` across every face. |
| `ctx.clearGlyphs()` | Drop every glyph value; keep size states warm. Optimised for zoom-scrubbing where outlines churn but VMs are reused. |
| `ctx.clear()` | Wholesale: every tier dropped. Equivalent to a fresh `init`. |

**Invariant.** Cache entries are eligible for eviction at any point
between `prepareRun`/`computeGlyph` calls. `TextBlobBundle`s built via
`bindHintContext` copy their pending hint points into bundle-owned
storage at append time, so eviction during bundle construction is safe
— it never produces dangling references.

Consumer recipes:

```zig
// Terminal at one PPEM, session-stable (escarghost). Default behaviour;
// no eviction verbs needed.
var ctx = snail.TrueTypeHintContext.init(allocator, &atlas);
defer ctx.deinit();
// ... draw frames forever; cache size is bounded by character set.

// Editor with 3–10 zoom levels: drop levels the user leaves.
fn onZoomChange(ctx: *snail.TrueTypeHintContext, old_ppem: snail.TrueTypeHintPpem) void {
    ctx.evictSize(0, old_ppem);
}

// Animation/scrubbing through many PPEMs: drop outlines per frame,
// keep VMs warm so the recent PPEM neighbourhood stays responsive.
fn afterFrame(ctx: *snail.TrueTypeHintContext, current_ppem_26_6: u32) void {
    ctx.clearGlyphs();
    var it = ctx.sizeKeyIterator();
    while (it.next()) |entry| {
        const distance = if (entry.ppem.x_26_6 > current_ppem_26_6)
            entry.ppem.x_26_6 - current_ppem_26_6
        else
            current_ppem_26_6 - entry.ppem.x_26_6;
        if (distance > 5 * 64) ctx.evictSize(entry.face_index, entry.ppem);
    }
}

// Server-side renderer in a tight loop: reset at request boundary.
fn handleRequest(ctx: *snail.TrueTypeHintContext) !void {
    defer ctx.clear();
    // ... build snapshots, render, drop.
}
```

The `Footprint.totalBytes()` value is a hint for when to act, not a
guarantee. Snail measures the major allocations (VM stack/storage/points,
curve point slices) but does not chase every hash-map bucket overhead;
use the number as a workload-relative signal, not as an exact RSS attribution.

## Build

Requires [Zig 0.16](https://ziglang.org/download/), a GL 3.3 context for `Gl33Renderer`, a GL 4.4 context for `Gl44Renderer`, an OpenGL ES 3.0 context for `Gles30Renderer`, Vulkan headers/loader, `glslc`, and pkg-config. Vulkan and HarfBuzz are enabled by default but can be disabled (see flags below). The interactive demo requires Wayland, plus EGL for the GL 3.3, GL 4.4, and OpenGL ES 3.0 modes.

```sh
zig build test                                  # unit tests
zig build demo                                  # build/install the interactive demo executable
zig build run                                   # interactive 2D demo; press C to cycle enabled backends
zig build run -Dvulkan=false                    # demo without Vulkan
zig build run -Dgl33=false -Dgl44=false         # demo without GL 3.3/GL 4.4
zig build run -Dcpu-renderer=false              # demo without CPU rendering
zig build run-game-demo                         # 3D scene with HUD + world-space text on walls
zig build run-screenshot                        # 2D demo offscreen → zig-out/demo-screenshot.tga
zig build run-algorithm-screenshots             # README algorithm diagrams → zig-out/algorithm-*.png
zig build run-backend-compare                   # CPU/GL/GLES/Vulkan parity
zig build run-bench                             # benchmarks all enabled backends
zig build install --release=fast                # install libsnail, enabled C headers, and snail.pc
zig build generate-c-api                        # emit generated C API artifacts into the Zig cache
zig build check-c-api                           # verify C headers against generated handles and Zig exports
```

Library backend flags:

- `-Dgl33=true` (default) — GL 3.3 backend (`Gl33Renderer`); installs `snail_gl33.h` when the C API is enabled.
- `-Dgl44=true` (default) — GL 4.4 backend (`Gl44Renderer`); installs `snail_gl44.h` when the C API is enabled.
- `-Dgles30=true` (default) — OpenGL ES 3.0 backend (`Gles30Renderer`); installs `snail_gles30.h` when the C API is enabled.
- `-Dvulkan=true` (default) — Vulkan backend (`VulkanRenderer`); pass `=false` for a slimmer non-Vulkan build. SPIR-V shaders are compiled at build time via `glslc`; installs `snail_vulkan.h` when the C API is enabled. That extension header includes Vulkan headers.
- `-Dcpu-renderer=true` (default) — CPU backend (`CpuRenderer`); pass `=false` to drop it. Installs `snail_cpu.h` when the C API is enabled.
- `-Dharfbuzz=true` (default) — pass `=false` for a HarfBuzz-free build using the built-in GSUB type 4 / GPOS type 2 shaper.
- `-Dprofile=false` (default) — pass `=true` to enable the comptime CPU timers.
- `-Dc-api=true` (default) — pass `=false` for a Zig-module-only build (skips `libsnail.{a,so}` and the header install).
- `-Dc-api-shared=true` / `-Dc-api-static=true` (default to `-Dc-api`) — pass either `=false` to install only the library form you need.

The generated API files (`snail_generated.h` and `c_api_generated.zig`) are
build artifacts. They are emitted into the Zig cache and installed into the
prefix when the C API is enabled; they are intentionally not checked in. C
consumers should use the installed headers rather than the source-tree
`include/` directory by itself.

The checked-in screenshot at `assets/demo_screenshot.png` is regenerated from
the `zig build run-screenshot` TGA output. The checked-in algorithm diagrams at
`assets/algorithm-*.png` are generated by `zig build run-algorithm-screenshots`;
the committed copies are PNG-optimized to keep the repository small.

### Nix

```sh
nix-shell           # dev shell with all dependencies
nix-build -A lib    # build libsnail + enabled C headers
nix-build -A demo   # build snail-demo
```

The Nix library package is defined in `nix/snail.nix`; the demo executable is
defined separately in `nix/snail-demo.nix`. Both are wired through
`callPackage` from `default.nix`. The library defaults mirror the Zig build
defaults: GL 3.3 on, GL 4.4 on, GLES30 on, Vulkan on, CPU renderer on,
HarfBuzz on, and the C API enabled with both shared and static libraries.
Override `enableGL33`, `enableGL44`, `enableGLES30`, `enableVulkan`,
`enableCpu`, `enableHarfBuzz`, `enableCApi`, `cApiShared`, or `cApiStatic`
when calling the library package directly.
The demo package builds with the same backend flags by default and cycles
between the enabled windowed demo renderers at runtime.

### Using as a Zig dependency

Add snail to your `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/psyclyx/snail
```

Then in your `build.zig`:

```zig
const snail_dep = b.dependency("snail", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("snail", snail_dep.module("snail"));
```

The default dependency module enables OpenGL, Vulkan, CPU rendering, and HarfBuzz. Workspace builds that import `snail/build.zig` directly can call `moduleWithOptions` to trim backend support explicitly. On NixOS/nix-shell, system libraries are provided automatically; on other systems, install the development packages for your distro.

## Using the API

The Zig and C APIs use the same explicit resource model:

1. Build immutable CPU values: `TextAtlas`/`TextBlob`, `PathPicture`, and
   `Image`. Use `TextBlobBundle` + `BlobInProgress` to compose one or many
   blobs into a shared arena, including prepared TrueType hint runs.
2. Put the values a scene may sample into a `ResourceManifest` using stable
   `ResourceKey` / `TextResourceKeys` identities.
3. Upload the manifest with a renderer to get `PreparedResources`.
4. Add borrowed `TextDraw` and `PathDraw` submissions to a `Scene`.
5. Convert the scene into either a caller-buffered `DrawList` or an owned
   `PreparedScene`, then draw with a per-call `DrawState` or `DrawPass`.
6. When resources change, upload a replacement `PreparedResources`, rebuild
   stale draw records, and retire the old prepared resources after in-flight
   frames are done.

The simple path is `uploadResourcesBlocking` + `PreparedScene.initOwned` +
`drawPrepared`. Engines that need upload scheduling can use the plan / begin /
record / publish flow described below.

## Example: Zig

```zig
const snail = @import("snail");

// Create an immutable TextAtlas snapshot with a fallback chain.
var atlas = try snail.TextAtlas.init(allocator, &.{
    .{ .data = noto_sans_regular },
    .{ .data = noto_sans_bold, .weight = .bold },
    .{ .data = noto_sans_regular, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
    .{ .data = noto_sans_arabic, .fallback = true },
    .{ .data = twemoji, .fallback = true },
});
defer atlas.deinit();

if (try atlas.ensureText(.{}, "Hello, world!")) |next| {
    atlas.deinit();
    atlas = next;
}

var bundle = snail.TextBlobBundle.init(allocator, &atlas);
defer bundle.deinit();

var shaped = try atlas.shapeText(allocator, .{}, "Hello, world!");
defer shaped.deinit();

var bip = try bundle.startBlob();
errdefer bip.abort();
_ = try bip.append(.{
    .source = .{ .shaped = shaped.glyphs },
    .placement = .{ .baseline = .{ .x = 10, .y = 400 }, .em = 48 },
    .fill = .{ .solid = .{ 1, 1, 1, 1 } },
});
const blob = try bip.finish(snail.ResourceKey.named("hello_text"));

var resource_entries: [8]snail.ResourceManifest.Entry = undefined;
var resources = snail.ResourceManifest.init(&resource_entries);
const text_resources = blob.resourceKeys(
    snail.ResourceKey.named("fonts"),
    snail.ResourceKey.named("hello_text"),
);
try resources.putTextBlob(text_resources, blob);

var scene = snail.Scene.init(allocator);
defer scene.deinit();
try scene.addText(.{ .blob = blob, .resources = text_resources });
// (See "Vector Paths" below for adding a PathPicture to the same scene.)

// Requires an active GL context. Vulkan uses snail.VulkanRenderer.init(allocator, ctx).
var gl = try snail.Gl33Renderer.init(allocator);
defer gl.deinit();
var prepared = try gl.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &resources);
defer prepared.deinit();

const viewport_wf: f32 = @floatFromInt(viewport_w);
const viewport_hf: f32 = @floatFromInt(viewport_h);
const state = snail.DrawState{
    .mvp = snail.Mat4.ortho(0, viewport_wf, viewport_hf, 0, -1, 1),
    .surface = .{
        .pixel_width = viewport_wf,
        .pixel_height = viewport_hf,
        .encoding = .srgb,
    },
    .raster = .{ .subpixel_order = .rgb },
};

var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, &scene);
defer prepared_scene.deinit();
try gl.drawPrepared(&prepared, &prepared_scene, state);
```

### On-demand Atlas Extension

`ensureText`, `ensureShaped`, and `ensureGlyphs` return a new immutable snapshot; the old one remains valid for in-flight readers. Existing `TextBlob`s keep working with the snapshot they were built against as long as that snapshot and its prepared backend resources stay alive.

```zig
if (try atlas.ensureText(.{}, text)) |next| {
    atlas.deinit();  // safe only after readers of the old snapshot are done
    atlas = next;
}
```

`bundle.rebindAtlas` and `bundle.rebound` are the cache/lifetime helpers.
`rebindAtlas` retargets the whole bundle to a compatible superset snapshot
in place; `rebound` copies one blob from a source bundle into a target bundle
that's already bound to the new atlas. Use either when you want to release
the old atlas snapshot and retire its prepared resources without reshaping
unchanged text rows.

If you already have shaped glyph IDs, extend the atlas directly and either
rebind the existing bundle or copy specific blobs into a new one:

```zig
if (try atlas.ensureGlyphs(face_index, glyph_ids)) |next| {
    atlas.deinit();
    atlas = next;
    try bundle.rebindAtlas(&atlas);
}
```

### Vector Paths

A `PathPicture` is built once and submitted to a `Scene` like a `TextBlob`. Add
the path picture, text blob resources, and images your scene uses to a
`ResourceManifest` before uploading.

```zig
var path = snail.Path.init(allocator);
defer path.deinit();
try path.addRoundedRect(.{ .x = 0, .y = 0, .w = 200, .h = 80 }, 12);

var builder = snail.PathPictureBuilder.init(allocator);
defer builder.deinit();
try builder.addPath(&path,
    .{ .paint = .{ .solid = .{ 0.1, 0.1, 0.2, 0.9 } } },    // fill
    .{ .paint = .{ .solid = .{ 0.4, 0.6, 1, 1 } }, .width = 2, .join = .round }, // stroke
    .identity,
);

var picture = try builder.freeze(.{
    .persistent_allocator = allocator,
    .scratch_allocator = allocator,
});
defer picture.deinit();

// Submit before uploading (see the Zig example above).
try scene.addPath(.{ .picture = &picture, .resource_key = snail.ResourceKey.named("logo_paths") });
```

## Example: C

The installed C API consists of `snail.h`, generated `snail_generated.h`, and
one backend header for each enabled backend. Pass `NULL` for `SnailAllocator` to
use libc allocation; otherwise the allocator callbacks and `ctx` must outlive
every handle created from that descriptor.

This example uses the GL 3.3 backend and requires an active GL 3.3 context. CPU
callers include `snail_cpu.h`, provide a caller-owned RGBA8 buffer, and may
attach a caller-owned `SnailThreadPool`; Vulkan callers include
`snail_vulkan.h`, provide `SnailVulkanContext`, and draw through
`SnailVulkanFrame`. Error checks are omitted here for brevity.

```c
#include "snail.h"
#include "snail_gl33.h"

SnailFaceSpec faces[] = {{
    .data = ttf_data,
    .len = ttf_len,
    .weight = SNAIL_FONT_WEIGHT_REGULAR,
}};

SnailTextAtlas *atlas = NULL;
snail_text_atlas_init(NULL, faces, 1, &atlas);

SnailFontStyle style = {.weight = SNAIL_FONT_WEIGHT_REGULAR, .italic = false};

SnailTextAtlas *next = NULL;
snail_text_atlas_ensure_text(atlas, style, "Hello", 5, &next);
if (next) {
    snail_text_atlas_deinit(atlas);
    atlas = next;
}

// Shape text with source-span metadata.
SnailShapedText *shaped = NULL;
snail_text_atlas_shape_utf8(atlas, style, "Hello", 5, &shaped);
size_t n = snail_shaped_text_glyph_count(shaped);
SnailShapedGlyph g;
for (size_t i = 0; i < n; i++) {
    snail_shaped_text_glyph(shaped, i, &g);
    // g.glyph_id, g.x_offset, g.source_start, g.source_end ...
}

SnailTextBlob *blob = NULL;
SnailTextAppendOptions text_options = {
    .placement = {.baseline_x = 10, .baseline_y = 400, .em = 48},
    .fill = {.kind = SNAIL_PAINT_SOLID, .paint_solid = {1, 1, 1, 1}},
};
snail_text_blob_init_from_shaped(NULL, atlas, shaped, text_options, &blob);

// Optional: build a hinted solid-color run for small static text.
SnailTrueTypeHintContext *hint_context = NULL;
SnailTrueTypePreparedHintRun *hinted = NULL;
SnailTextBlob *hinted_blob = NULL;
float white[4] = {1, 1, 1, 1};
if (snail_true_type_hint_context_init(NULL, atlas, &hint_context) == SNAIL_OK &&
    snail_true_type_hint_context_prepare_run(
        hint_context, NULL, shaped,
        snail_true_type_hint_ppem_uniform(12 * 64), &hinted) == SNAIL_OK) {
    snail_text_blob_init_from_prepared_hint_run(
        NULL, hinted, (SnailTextPlacement){10, 430, 12}, white, &hinted_blob);
}
if (hinted_blob) {
    snail_text_blob_deinit(blob);
    blob = hinted_blob;
}
snail_true_type_prepared_hint_run_deinit(hinted);
snail_true_type_hint_context_deinit(hint_context);
snail_shaped_text_deinit(shaped);

// Vector path
SnailPath *path = NULL;
snail_path_init(NULL, &path);
snail_path_add_rounded_rect(path, (SnailRect){0, 0, 200, 80}, 12);

SnailPathPictureBuilder *builder = NULL;
snail_path_picture_builder_init(NULL, &builder);
SnailFillStyle fill = {
    .paint = {.kind = SNAIL_PAINT_SOLID, .paint_solid = {0.1, 0.1, 0.2, 0.9}},
};
snail_path_picture_builder_add_filled_path(builder, path, fill,
                                           SNAIL_TRANSFORM2D_IDENTITY);

SnailPathPicture *picture = NULL;
snail_path_picture_builder_freeze(builder, NULL, NULL, &picture);

SnailResourceManifest *resources = NULL;
snail_resource_manifest_init(NULL, 8, &resources);
SnailTextResourceKeys text_resources = {0};
snail_text_resource_keys_for_blob(1, 3, blob, &text_resources);
snail_resource_manifest_put_text_blob(resources, text_resources, blob);
snail_resource_manifest_put_path_picture(resources, 2, picture);

SnailScene *scene = NULL;
snail_scene_init(NULL, &scene);
snail_scene_add_text_draw(scene, (SnailTextDraw){
    .blob = blob,
    .resources = text_resources,
});
snail_scene_add_path_picture_draw(scene, (SnailPathPictureDraw){
    .picture = picture,
    .key = 2,
});

SnailRenderer *renderer = NULL;
snail_gl33_renderer_init(&renderer);

SnailDrawState draw_state = {
    .mvp = snail_mat4_identity(), // replace with your pixel-to-clip projection
    .surface = {
        .pixel_width = 1280,
        .pixel_height = 720,
        .attachment_encoding = SNAIL_COLOR_ENCODING_SRGB,
        .stored_pixel_encoding = SNAIL_COLOR_ENCODING_SRGB,
    },
    .raster = {
        .subpixel_order = SNAIL_SUBPIXEL_RGB,
        .fill_rule = SNAIL_FILL_NONZERO,
        .coverage_exponent = 1.0f,
    },
};

SnailPreparedResources *prepared = NULL;
snail_renderer_upload_resources_blocking(renderer, NULL, resources, &prepared);

SnailPreparedScene *prepared_scene = NULL;
snail_prepared_scene_init(NULL, prepared, scene, &prepared_scene);
snail_renderer_draw_prepared(renderer, prepared, prepared_scene, draw_state);

// Cleanup
snail_prepared_scene_deinit(prepared_scene);
snail_prepared_resources_deinit(prepared);
snail_renderer_deinit(renderer);
snail_resource_manifest_deinit(resources);
snail_scene_deinit(scene);
snail_text_blob_deinit(blob);
snail_path_picture_deinit(picture);
snail_path_picture_builder_deinit(builder);
snail_path_deinit(path);
snail_text_atlas_deinit(atlas);
```

The C scene API submits `SnailTextDraw` and `SnailPathPictureDraw` directly.
When `has_override` is true, the scene copies that one override value into
scene-owned storage; blob, picture, and resource handles are still borrowed
until `snail_scene_reset` or `snail_scene_deinit`.

## API reference

### Types

| Type | Description |
|------|-------------|
| `TextAtlas` | Immutable CPU font/glyph snapshot. `ensureText`, `ensureShaped`, and `ensureGlyphs` return a new snapshot; old stays valid. |
| `ShapedText` | Shaped glyph placements for a string/run. |
| `TextBlob` | Bundle-owned positioned-text view: glyph indices, transforms, and paint records into the bundle's arena. Accessed via `blob.atlas()` and the rendering APIs; not directly destructible (the bundle owns its lifetime). |
| `TextBlobBundle` / `BlobInProgress` | Arena-backed builder for one or many `TextBlob`s sharing a `TextAtlas`. `bundle.startBlob()` returns a `BlobInProgress`; finish it with `bip.finish(key)` to get a bundle-owned `*const TextBlob`, or abort with `bip.abort()`. `bundle.rebindAtlas` / `bundle.rebound` are the cache/lifetime helpers. Hinted text requires `bundle.bindHintSnapshot(snapshot)` first; the bundle references a single `GlyphHintSnapshot` and many bundles can share one — terminal-style workloads with many small blobs at the same PPEM upload the snapshot's slab once per `(atlas, ppem)` rather than per blob. C API: `SnailTextBlobBundle` + `SnailBlobInProgress`. |
| `Font` | Stable parsed-font helper for `unitsPerEm`, `glyphIndex`, and `advanceWidth` when callers manage raw font data directly. |
| `FaceSpec` | `{ .data, .weight, .italic, .fallback, .synthetic }` — font face specification for `TextAtlas.init`. |
| `FaceIndex` | `u16` face handle returned by atlas resolution/itemization and accepted by per-face metric helpers. |
| `FontStyle` | `{ .weight: FontWeight, .italic: bool }` — selects a face for rendering. |
| `FontWeight` | `.regular`, `.bold`, `.semi_bold`, etc. |
| `SyntheticStyle` | `{ .skew_x, .embolden }` — synthetic italic shear and bold offset. |
| `ItemizedRun` | `{ .face_index, .text_start, .text_end }` run returned by `atlas.itemize`. |
| `Decoration`, `ScriptTransform`, `CellMetrics` | Text-layout helper types for decorations, superscript/subscript placement, and monospace-style cell sizing. |
| `Image` | Immutable sRGB RGBA8 raster image. Created with `initSrgba8`. |
| `Path` | Mutable path builder: `moveTo`, `lineTo`, `quadTo`, `cubicTo`, `close`, plus shape helpers. |
| `PathPictureBuilder` | Accumulates filled/stroked paths and shapes with paint styles. |
| `PathPicture` | Immutable frozen vector art. |
| `Scene` | Borrowed command list of `TextDraw` and `PathDraw` submissions. |
| `PathDraw`, `TextDraw` | Submission record: resource pointer plus an `[]const Override` array (length = GPU instance count). Sub-selection happens at composition time — build a smaller `TextBlob`/`PathPicture` rather than passing a range. |
| `Override` | Per-instance composition: `transform` composed onto baked transform, `tint` multiplied onto the resource's baked color or paint, including color-font palette layers. |
| `Range` | `{ start, count }` value type, used internally by `PathPictureBuilder.rangeFrom` / `rangeBetween` when composing paths. Not part of any draw-time field. |
| `ResourceKey` | Explicit resource identity. `fromId`, `named`/`fromName`, and derived keys use distinct namespaces. |
| `ResourceManifest` | Fixed-capacity borrowed manifest of CPU values. |
| `ResourceFootprint` | Used and allocated upload bytes split by curve, band, layer-info, and image storage. |
| `PreparedResources` | Logical prepared views plus backend-specific residency state used by draw APIs. |
| `DrawList` | Caller-buffered draw records. |
| `PreparedScene` | Optional owned draw-record cache for static scenes. |
| `DrawState` | Per-draw transform, target surface metadata, and rasterization policy. |
| `DrawPass` | A draw state plus resolve mode. The default is direct; `.linear(state, resolve)` runs an explicit linear resolve pass. |
| `TargetSurface` | Per-draw target pixel size and color encoding. |
| `RasterOptions` | Per-draw raster policy: subpixel order, fill rule, and coverage transfer. |
| `TargetEncoding` | Pair of color encodings for attachment interpretation and final stored pixels. Common presets are `.srgb`, `.linear`, and `.srgb_pixels_on_linear_attachment`. |
| `LinearResolve` | Explicit resolve-pass options for gamma-correct Snail composition into sRGB pixels on a linear attachment. |
| `ResolveBackdrop` | Backdrop contract for a linear resolve: `.target`, `.clear`, `.transparent`, or `.dont_care`. |
| `ResolveRegion` | Full-target or pixel-rectangle bounds for a resolve. |
| `PixelRect` | Integer pixel rectangle `{ .x, .y, .w, .h }` used by `ResolveRegion.pixel_rect`. |
| `IntermediateFormat` | GL linear intermediate precision: `.rgba16f` or `.rgba32f`. |
| `CoverageTransfer` | Optional analytic coverage remap. `.identity` is the default; `.power(exponent)` is explicit display tuning. |
| `TrueTypeHintContext`, `TrueTypeHintPpem`, `PreparedHintRun` | Opt-in TrueType bytecode hinting helpers for building hinted `TextBlob` records at a chosen ppem. `prepareRun` always covers every glyph of the source shaped text; each entry carries either a hint pointer or a `.fallback` marker with a pixel-snapped advance. Strict callers check `stats.fallback_count == 0`. The C API exposes matching `SnailTrueTypeHintContext`, `SnailTrueTypeHintPpem`, and `SnailTrueTypePreparedHintRun` handles/types. |
| `SnapRule` | Quantization rule for explicit snapping: `.floor`, `.nearest`, or `.ceil`. |
| `pixelStep` / `pixelSteps` | Compute logical-coordinate size of one backing pixel from logical and pixel extents. |
| `snapToStep` / `snapDeltaToStep` | Snap a scalar to an explicit step, or return the delta needed to reach that snap. |
| `snapLengthToStep` | Snap a length to an explicit step with a caller-provided minimum step count. |
| `snapPointToStep` / `snapRectToStep` | Snap a point or rectangle using explicit per-axis steps. |
| `Gl33Renderer`, `Gl44Renderer`, `Gles30Renderer`, `VulkanRenderer`, `CpuRenderer` | First-class backend renderers. |
| `Renderer` | Type-erased convenience wrapper around a backend renderer. |
| `Rect` | `{ x, y, w, h }` rectangle. |
| `Transform2D` | 2x3 affine matrix `{ xx, xy, tx, yx, yy, ty }`. |
| `FillStyle` | Fill `Paint`. |
| `StrokeStyle` | Stroke `Paint`, width, cap, join, miter limit, placement. |
| `Paint` | Tagged union: `.solid`, `.linear_gradient`, `.radial_gradient`, `.image`. |

### Text

| Method | Description |
|--------|-------------|
| `TextAtlas.init(alloc, faces) !TextAtlas` | Parse font faces. Atlas starts empty. |
| `atlas.deinit()` | Release this snapshot. Pages shared with other snapshots stay alive. |
| `atlas.shapeText(alloc, style, text) !ShapedText` | Shape text without growing the atlas. Caller frees `ShapedText`. |
| `atlas.ensureShaped(shaped) !?TextAtlas` | Return a new snapshot with the shaped glyphs present. Null if already present. |
| `atlas.ensureText(style, text) !?TextAtlas` | Shape-and-ensure helper. |
| `atlas.ensureGlyphs(face_index, glyph_ids) !?TextAtlas` | Extend one face by resolved glyph IDs without reshaping. |
| `atlas.resolve(style, codepoint) ?FaceIndex` / `atlas.itemize(alloc, style, text) ![]ItemizedRun` | Choose fallback faces for layout code that wants explicit run control. |
| `atlas.faceCount() usize` / `atlas.primaryFaceIndex() !FaceIndex` | Inspect configured faces for layout code that caches face indices. |
| `atlas.lineMetrics() !LineMetrics` / `atlas.unitsPerEm() !u16` | Primary-face metrics. |
| `atlas.faceLineMetrics(face_index) !LineMetrics` / `atlas.faceUnitsPerEm(face_index) !u16` / `atlas.glyphIndex(face_index, cp) !?u16` / `atlas.advanceWidth(face_index, gid) !i16` | Stable per-face font metrics for layout code. |
| `atlas.cellMetrics(.{ .style, .em }) !CellMetrics` | Resolve the styled primary face and return `{ .cell_width, .line_height }` in caller units. |
| `atlas.decorationRect(decoration, x, y, advance, em) !Rect` | Underline/strikethrough rectangle using primary-face font metrics. |
| `atlas.superscriptTransform(x, y, em) !ScriptTransform` / `atlas.subscriptTransform(x, y, em) !ScriptTransform` | Script placement and em-size from primary-face OS/2 metrics. |
| `atlas.measureText(style, text, em) !f32` | Shape text and return horizontal advance in caller units. |
| `atlas.shapeTextOpts(alloc, style, text, opts) !ShapedText` | Shape with explicit `ShapeOptions` (HarfBuzz feature requests). `shapeText` is the zero-options shorthand. |
| `ShapedText.advanceX() f32` / `ShapedText.advanceY() f32` | Total advance summed from the glyph stream. The glyph slice is the single source of truth — no field/stream desync is representable. |
| `snail.clusters(&shaped) ClusterIterator` | Walk a `ShapedText` by HarfBuzz cluster (maximal runs of glyphs sharing a `source_start`). Used by the post-shape transforms below; downstream layout code that needs to map shaped glyphs back to source bytes. |
| `snail.track` / `snail.shiftBaseline` / `snail.spaceWords` / `snail.snapAdvances` | Free-function post-shape transforms over `*ShapedText`. Cluster-aware (ligature internals stay intact); per-cluster deltas are baked into the cluster's last glyph's advance. |
| `TextBlobBundle.init(gpa, atlas) TextBlobBundle` / `bundle.startBlob() !BlobInProgress` / `bip.append(TextAppend) !TextAppendResult` / `bip.finish(key) !*const TextBlob` / `bip.abort() void` | Streaming blob construction. The bundle owns blob lifetimes; multiple blobs sharing one atlas live in one arena. `bundle.buildBlob(key, []TextAppend, ?[]TextAppendResult)` is the bulk variant. |
| `bundle.rebindAtlas(new_atlas)` / `target_bundle.rebound(key, src_blob, new_atlas) !*const TextBlob` | Cache/lifetime helpers for atlas extension. `rebindAtlas` retargets the whole bundle in place when the new snapshot is prefix-compatible; `rebound` copies one blob from a source bundle into a target bundle already bound to `new_atlas`. |
| `bundle.reset()` / `bundle.freeze()` / `bundle.unfreeze()` / `bundle.isFrozen()` / `bundle.blobCount()` / `bundle.currentGeneration()` | Bundle lifecycle: `reset` invalidates every outstanding blob, the generation counter advances so callers can detect use-after-reset. C handles compare-and-validate against `snail_text_blob_bundle_generation`. |
| `blob.resourceKeys(atlas_key, blob_key) TextResourceKeys` | Build the resource binding used by both `scene.addText` and `ResourceManifest.putTextBlob`. Returns `{ atlas, paint?, hint? }`. The hint key is the bound `GlyphHintSnapshot`'s own key, so blobs across many bundles that share one snapshot collapse to one `text_hint` manifest entry; the snapshot slab uploads once per `(atlas, hint-context, ppem)`. |
| `TrueTypeHintContext.init(alloc, atlas)` / `context.prepareRun(alloc, .{ .shaped, .ppem })` | Whole-run TrueType hinting. The result covers every input glyph; rejected glyphs become `.fallback` entries with pixel-snapped advances rather than aborting the whole run. Strict callers check `stats.fallback_count == 0`. Append the run via `bip.append(.{ .source = .{ .hinted = run.glyphs }, .placement, .fill = .{ .solid = color } })`. C callers use `snail_true_type_hint_context_prepare_run` + `snail_blob_in_progress_append_prepared_hint_run` (or the standalone `snail_text_blob_init_from_prepared_hint_run`). |
| `context.rebindAtlas(new_atlas)` | Preserve cached hint values, face programs, and size states across atlas extensions when the new snapshot is prefix-compatible with the old. Eliminates the warmup rehint storm on `ensureText`-style growth. |
| `TextAppend` | `{ .source, .placement = .{ .baseline, .em }, .fill }` where `source` is `.{ .shaped = []const ShapedText.Glyph }` or `.{ .hinted = []const PreparedHintRun.Glyph }`. Slice notation handles sub-selection (`shaped.glyphs[a..b]`). Hinted runs require a solid `Paint`. |
| `TextAppendResult` | `{ .advance: Vec2, .missing: bool }` — pen advance and whether any referenced glyph was absent from the current atlas snapshot. |
| `ShapeOptions` / `OpenTypeFeature` / `SourceRange` | Shape-time inputs. Features carry a 4-byte tag, value, and optional source-byte range; ranges outside an itemized segment are silently dropped. |

### Scene

A scene is a borrowed list of `PathDraw` / `TextDraw` submissions. Each submission selects a sub-range of an immutable resource and emits one GPU instance per `Override` (default: a single identity instance). The scene borrows the `picture` / `blob` pointer *and* the `instances` slice on each submission — all three must stay live until `scene.reset()` or `scene.deinit()`. `addPath` / `addText` use the allocator captured by `Scene.init` only when growing the command list.

| Method | Description |
|--------|-------------|
| `Scene.init(alloc) Scene` | New empty scene. |
| `scene.addPath(PathDraw) !void` | Submit a path draw. Borrows `picture` and `instances`; `resource_key` selects the prepared path resource. |
| `scene.addText(TextDraw) !void` | Submit a text draw. Borrows `blob` and `instances`; `resources` selects the prepared atlas and optional paint records. |
| `scene.reset()` | Clear commands; capacity is retained. |
| `scene.deinit()` | Free the command list. |

```zig
// Trivial draw.
try scene.addPath(.{ .picture = &picture, .resource_key = snail.ResourceKey.named("picture") });

// One transform.
const overrides = [_]snail.Override{.{ .transform = transform }};
try scene.addPath(.{ .picture = &picture, .resource_key = snail.ResourceKey.named("picture"), .instances = &overrides });

// Sub-range of shapes.
try scene.addPath(.{
    .picture = &picture,
    .resource_key = snail.ResourceKey.named("picture"),
    .shapes = .{ .start = 4, .count = 12 },
});

// Many instances (tile / sprite / particle batch).
try scene.addPath(.{ .picture = &sprite, .resource_key = snail.ResourceKey.named("sprite"), .instances = entity_overrides });
```

### ResourceManifest

`ResourceManifest` is a caller-buffered manifest of CPU resources to prepare for a renderer. Entries borrow their source objects; keep those objects alive through the blocking upload or through `pending.record` for a scheduled upload. GPU backends copy texture payload during upload into renderer-owned caches. CPU-backed `PreparedResources` own the prepared snapshots they sample at draw time.

| Method | Description |
|--------|-------------|
| `ResourceManifest.init(entries)` | Wrap a caller-owned `[]ResourceManifest.Entry` buffer. |
| `set.reset()` | Clear entries; capacity is retained. |
| `set.putTextBlob(resources, blob)` / `set.putTextBlobOptions(resources, blob, options)` | Add a text blob's atlas, optional paint records, and optional `GlyphHintSnapshot` under the same `TextResourceKeys` used by `scene.addText`. Blobs sharing one snapshot dedupe to a single `text_hint` manifest entry, regardless of which bundle each blob belongs to. Options can override atlas capacity mode. |
| `set.putPathPicture(key, picture)` / `set.putPathPictureOptions(key, picture, options)` | Add a path picture, optionally overriding atlas capacity mode. |
| `set.putImage(key, image)` | Add an image resource. |
| `set.estimateUploadFootprint() !ResourceFootprint` | Allocation-free estimate for a resource manifest before upload. |

### Renderer

`Gl33Renderer`, `Gl44Renderer`, `Gles30Renderer`, `VulkanRenderer`, and `CpuRenderer` are first-class types; `Renderer` is the type-erased backend-agnostic API for upload, cache inspection, and draw submission.

| Method | Description |
|--------|-------------|
| `Gl33Renderer.init(alloc) !Gl33Renderer` | Initialize the GL 3.3 backend. Requires a current GL 3.3 context. |
| `Gl44Renderer.init(alloc) !Gl44Renderer` | Initialize the GL 4.4 backend. Requires a current GL 4.4 context. |
| `Gles30Renderer.init(alloc) !Gles30Renderer` | Initialize the OpenGL ES 3.0 backend. Requires an OpenGL ES 3.0 context to be current. |
| `VulkanRenderer.init(alloc, ctx) !VulkanRenderer` | Initialize the Vulkan backend from a caller-owned `VulkanContext`. |
| `CpuRenderer.init(pixels, w, h, stride) CpuRenderer` | Initialize the CPU backend over a caller-owned RGBA8 buffer. |
| `cpu.setThreadPool(?*snail.ThreadPool)` | Opt into scanline-tiled multithreaded rendering using a caller-owned `snail.ThreadPool`. Byte-identical output to the single-threaded path; the draw call itself stays allocation-free. |
| `vk.frame(.{ .cmd, .slot })` | Create a Vulkan frame encoder for a caller-recorded command buffer and upload-ring slot. |
| `renderer.uploadResourcesBlocking(.{ .persistent, .scratch }, set) !PreparedResources` | Blocking upload + view construction. Persistent allocations live with `PreparedResources`; scratch allocations end when upload returns. |
| `renderer.planResourceUpload(alloc, current, next_set) !ResourceUploadPlan` | Snapshot and diff a new resource manifest against existing prepared resources. |
| `renderer.beginResourceUpload(.{ .persistent, .scratch }, &plan) !PendingResourceUpload` | Start a scheduled upload; record it, wait for completion if needed, then call `pending.publish()`. |
| `DrawList.init(words, segments)` | Wrap a caller-buffered word + segment buffer for `addScene`. |
| `DrawList.estimate(scene)` | Upper bound for the word buffer required by `draw.addScene(prepared, scene)`. |
| `DrawList.estimateSegments(scene)` | Upper bound for the segment buffer required by `draw.addScene(prepared, scene)`. |
| `PreparedScene.initOwned(alloc, prepared, scene) !PreparedScene` | Build an owned draw-record cache for a static scene. |
| `renderer.draw(prepared, list, state)` | Execute a `DrawList` on CPU/GL or other renderer-owned draw contexts. No resource discovery or upload. |
| `renderer.drawPrepared(prepared, prepared_scene, state)` | Draw a `PreparedScene` cache. For Vulkan, call `vk.frame(.{ .cmd, .slot }).drawPrepared(...)`. |
| `renderer.drawPass(prepared, list, pass)` / `renderer.drawPreparedPass(...)` | Execute an explicit draw pass, including linear resolve when requested. Vulkan currently rejects linear resolve with `error.UnsupportedResolve`. |
| `prepared.retireNow()` | Retire backend resources immediately once no in-flight frame references them. |
| `PreparedResourceRetirementQueue.init(alloc)` / `queue.sweep()` | Caller-owned queue for prepared resources that must retire after a fence completes. |
| `prepared.retireAfter(&queue, fence_or_frame)` | Move prepared resources into the caller-owned retirement queue. |

### Scheduled resource upload

`uploadResourcesBlocking` is the simple path; for engines that want to overlap
upload with the main render queue (Vulkan in particular) there is an explicit
`Renderer` plan / record / publish flow, including CPU-backed uploads.

1. **Plan.** `renderer.planResourceUpload(allocator, current, next_set)`
   diffs `next_set` against the existing `PreparedResources` (or `null` for a
   first upload) and records which `ResourceKey` entries changed. The result
   owns a snapshot of the resource entries, so callers may reset or reuse the
   original `ResourceManifest` after planning. `ResourceUploadPlan` is split
   into `manifest`, `diff`, `footprint`, `cache`, and `upload` fields. Use
   `plan.diff.keys()` / `plan.diff.changed_bytes` for logical changes,
   `plan.cache` for resource-cache admission decisions, and
   `plan.upload.bytes` for budget checks. For non-cached backends,
   `plan.upload.bytes` is `plan.footprint.allocatedBytes()`.
   Call `plan.deinit()` when the plan is no longer needed.
2. **Begin + record.** `renderer.beginResourceUpload(.{ .persistent = allocator, .scratch = allocator }, &plan)` returns
   a `PendingResourceUpload`. Call `pending.record(.{ .budget_bytes = N })`
   for backend-owned synchronization. CPU and GL complete during `record`;
   Vulkan uses its internal transfer path and waits before returning. If a
   Vulkan caller wants upload commands in a caller-owned command buffer, use the
   typed Vulkan renderer's `recordResourceUpload(&pending, command_buffer, .{ .budget_bytes = N })`.
3. **Wait + publish.** For backend-owned synchronization, publish immediately
   after `record` returns; `pending.readyNow()` also reports true. For
   caller-synchronized Vulkan recording, call
   `vulkan.resourceUploadReadyFence(&pending, fence)` until it reports true.
   Once ready, `pending.publish()` returns the new `PreparedResources`. Call
   `pending.deinit()` if you need to abandon the upload before publishing.

The new `PreparedResources` replaces the old one; retire the old one via
`old.retireNow()` once no in-flight frame still references it. For Vulkan
resources that need fence retirement, keep a caller-owned
`PreparedResourceRetirementQueue`, call `old.retireAfter(&queue, fence)`, and
sweep the queue explicitly.

C callers use the same flow through `SnailResourceUploadPlan` and
`SnailPendingResourceUpload`. Use `snail_resource_upload_plan_summary` for the
budget/cache/diff totals and `snail_resource_upload_plan_changed_key` to walk
the changed keys. `snail_pending_resource_upload_record` covers CPU/GL and
backend-owned Vulkan transfers; Vulkan callers that record into their own
command buffer use
`snail_vulkan_pending_resource_upload_record(pending, command_buffer, budget_bytes)` and
`snail_vulkan_pending_resource_upload_ready_fence(pending, fence)`. Vulkan drawing in C is also
frame-scoped: create `SnailVulkanFrame` with
`snail_vulkan_renderer_frame(renderer, command_buffer, frame_slot, &frame)`,
then call `snail_vulkan_frame_draw`, `snail_vulkan_frame_draw_pass`, or their
prepared-scene variants.

### Text coverage in custom shaders

`snail.coverage.Shader`, `snail.coverage.TextCoverageRecords`, and
`snail.coverage.Backend` let a material shader sample snail's exact glyph
coverage without going through `Renderer.draw`. Use this when text is part of a
3D material, mask, custom compositor, or post-process pass instead of a normal
2D scene draw.

- `snail.coverage.Shader.gl33` and `snail.coverage.Shader.gl44` expose the
  GLSL sources you can `@embedFile`-style splice into your own program:
  `vertex_interface`,
  `fragment_interface`, `resource_interface`, `coverage_functions`, and
  `fragment_body`. For material shaders that sample text coverage from their
  own geometry, include `resource_interface`, `coverage_functions`,
  `sample_interface`, and `sample_functions`; upload `records.slice()` as a
  `GL_R32UI` texture buffer and call
  `snail_text_sample_premul_linear(scene_pos)`.
- `snail.coverage.Shader.gles30` exposes the matching GLSL ES 300 sources for
  OpenGL ES 3.0 programs. The uniform/resource contract matches the GL 3.3 and GL 4.4
  coverage backends.
- `snail.coverage.Shader.vulkan` exposes the Vulkan shader sources and descriptor
  binding numbers. The Vulkan coverage backend binds Snail's descriptor set
  into a caller-owned compatible pipeline layout.
- `snail.coverage.TextCoverageRecords` is the per-glyph vertex stream over a caller-owned
  `[]u32`. Size it with `snail.coverage.TextCoverageRecords.wordCapacityForBlob(blob)`,
  initialize with `snail.coverage.TextCoverageRecords.init(buffer)`, then call
  `records.buildLocal(prepared, blob, .{ .resources = text_resources, .transform = ... })`. `buildLocal`
  does not allocate; it returns `error.DrawListFull` if the buffer is too
  small. Pass `records.layerWindowBase()` to custom shaders as `u_layer_base`.
  Call `records.validFor(prepared)` after a re-upload and
  `records.buildLocal(prepared, blob, options)` with the same text resource keys if the atlas has moved.
- `snail.coverage.Backend` is the backend hook. Get one from
  `prepared.coverageBackend(renderer)` (or `gl.coverageBackend(prepared)`
  on typed renderers, or `vk.frame(.{ .cmd, .slot }).coverageBackend(prepared)`
  for Vulkan). Bind the shader resource program with `bindProgram`, bind
  per-draw uniforms with `bindDrawState(program, snail.coverage.drawStateFor(&records, draw_state))`, then
  `drawCoverage(&records)` or `drawVertices` with your own buffer.

C callers use `SnailTextCoverageRecords` and `SnailCoverageBackend` from
`snail.h`; derive `SnailCoverageDrawState` with
`snail_text_coverage_records_draw_state`. GL shader snippets and program
uniform bindings live in `snail_gl33.h` and `snail_gl44.h`; OpenGL ES 3.0 equivalents live in
`snail_gles30.h`. Vulkan shader snippets, descriptor binding numbers, and
frame-scoped coverage programs live in `snail_vulkan.h`. The CPU backend has no
custom shader hook.

### Path

| Method | Description |
|--------|-------------|
| `Path.init(alloc) Path` | New empty path. |
| `path.deinit()` | Free curves. |
| `path.reset()` | Clear curves; capacity is retained. |
| `path.isEmpty() bool` | True when no curves have been emitted. |
| `path.bounds() ?BBox` | Tight bounding box of all curves, or null when empty. |
| `path.moveTo(point)` | Begin subpath. |
| `path.lineTo(point)` | Line segment. |
| `path.quadTo(control, point)` | Quadratic Bezier. |
| `path.cubicTo(c1, c2, point)` | Cubic Bezier; fills preserve cubic segments, and stroked offset geometry is approximated as needed. |
| `path.close()` | Close current subpath. |
| `path.addRect(rect)` / `path.addRectReversed(rect)` | Append rectangle subpath. The `Reversed` variant emits the opposite winding (use it to punch a hole through a fill of the same path under nonzero fill rule). |
| `path.addRoundedRect(rect, radius)` / `path.addRoundedRectReversed(rect, radius)` | Append rounded rectangle (and reversed-winding form). |
| `path.addEllipse(rect)` / `path.addEllipseReversed(rect)` | Append ellipse inscribed in rect (and reversed-winding form). |

### PathPictureBuilder

| Method | Description |
|--------|-------------|
| `PathPictureBuilder.init(alloc)` | New builder. |
| `builder.addPath(path, fill, stroke, transform)` | Add path with optional fill and/or stroke. |
| `builder.addFilledPath(path, fill, transform)` | Fill-only convenience. |
| `builder.addStrokedPath(path, stroke, transform)` | Stroke-only convenience. |
| `builder.addRect(rect, fill, stroke, transform)` | Direct rectangle. |
| `builder.addRoundedRect(rect, fill, stroke, radius, transform)` | Direct rounded rectangle. |
| `builder.addEllipse(rect, fill, stroke, transform)` | Direct ellipse. |
| `builder.addFilledRect` / `addFilledRoundedRect` / `addFilledEllipse` | Fill-only shape conveniences. |
| `builder.addStrokedRect` / `addStrokedRoundedRect` / `addStrokedEllipse` | Stroke-only shape conveniences. |
| `builder.shapeCount() usize` | Number of shapes added so far (matches indices used by `Range`). |
| `builder.mark() ShapeMark` | Capture the current shape count for later range construction. |
| `builder.rangeFrom(mark) !Range` | Build a shape range from a mark to the current end. |
| `builder.rangeBetween(start, end) !Range` | Build a shape range between two marks. |
| `builder.freeze(.{ .persistent_allocator, .scratch_allocator }) !PathPicture` | Compile to immutable atlas with explicit persistent and temporary allocation. |

### Advanced Building Blocks

Building blocks for callers who need direct atlas data, want to emit glyph or
path vertices outside the `Scene`/`DrawList` pipeline, or build a custom
backend on top of snail's rasterization. Most apps should not need these.

Raw platform/rendering imports such as OpenGL bindings, TrueType parser
internals, texture-layer windowing, and vertex-layout internals are not part of
the public API; repo demos and tools keep those needs in local shims or
build-only internal modules.

| Symbol | Use |
|--------|-----|
| `CurveAtlas` / `Atlas`, `AtlasPage` | Raw atlas storage exposed for backend authors. |
| `curveAtlasFootprint` | Raw atlas upload-footprint helper for custom backend/resource code. |
| `TextBatch`, `TextAtlas.appendTextBatch`, `PathBatch` | Caller-buffered glyph/shape vertex emission below the `DrawList` layer. |
| `TEXT_WORDS_PER_GLYPH`, `PATH_WORDS_PER_SHAPE`, related sizing constants | `u32` word budget per record (prefer `DrawList.estimate` when possible). |
| `PATH_PAINT_*` constants | Path-paint texel tags used by `PathPicture` records. |
| `PathPictureDebugView`, `PathPictureBoundsOverlayOptions` | Debug overlays for vector authoring. |

## Thread safety

| Type | Rule |
|------|------|
| `TextAtlas` | Immutable snapshot. Safe for concurrent reads. `ensureText`, `ensureShaped`, and `ensureGlyphs` return a new snapshot; old remains valid for in-flight readers. |
| `TextBlob`, `PathPicture`, `Image` | Safe for concurrent reads while the borrowed atlas / pictures / pixels outlive the reader. `bundle.rebound` produces a new blob in a target bundle instead of mutating the source. |
| `ResourceManifest`, `Scene` | Borrowed manifests/lists. Source values must outlive upload/record building. |
| `PreparedResources` | Backend/context-specific. GPU prepared resources reference renderer-owned residency; CPU prepared resources own the prepared snapshots they sample. |
| `DrawList` | Caller-owned buffer. Thread-local — no sharing needed. |
| `Renderer` | Single-threaded. Must be called from the GL/Vulkan context thread. |
| `CpuRenderer` | Single-threaded by default. Pass a `*snail.ThreadPool` via `cpu.setThreadPool` to enable internal scanline-tiled parallelism; the renderer fans tile work out and joins before each draw returns, so calls remain serial from the caller's perspective. |

Typical pattern: build `TextAtlas` and call `ensureText` / `ensureShaped` on a loading thread, publish a new `ResourceManifest` to the render thread, upload into `PreparedResources`, build `DrawList` records or a `PreparedScene`, then draw. The draw call does not allocate, upload, discover resources, or invalidate caches.

For CPU-backend speed, hand the renderer a `snail.ThreadPool`. The pool allocates once at `init` (a `[]std.Thread` slice); `dispatch` and the draw path itself are heap-free.

```zig
var pool: snail.ThreadPool = undefined;
try pool.init(allocator, .{}); // defaults to ncpu - 1 worker threads
defer pool.deinit();

var cpu = snail.CpuRenderer.init(pixels.ptr, w, h, stride);
cpu.setThreadPool(&pool);
// draws now fan out across scanline tiles
```

C callers use the same ownership model through `snail_cpu.h`: initialize a
`SnailThreadPool`, attach it with `snail_cpu_renderer_set_thread_pool(renderer,
pool)`, and either detach it with `NULL` or destroy the renderer before
destroying the pool.

## Status

snail is used in development but is not yet stable. The Zig API is settling and follows the explicit-resource model described above. Known gaps:

- Built-in OpenType shaping covers GSUB type 4 (ligatures) and GPOS type 2 (pair positioning) only; complex scripts (Arabic, Devanagari, Thai, etc.) require building with `-Dharfbuzz=true`.
- TrueType outlines only — no CFF/CFF2.
- No variable fonts.
- The C API exposes the same main workflow as Zig: CPU/OpenGL/Vulkan backend
  constructors, blocking and scheduled upload, prepared-resource retirement,
  owned draw-list records, prepared-scene drawing, CPU thread pools, and
  GL/Vulkan text coverage hooks for custom shaders. It also exposes
  `SnailTextBlobBundle` + `SnailBlobInProgress`, post-shape transforms
  (`snail_shaped_text_track` / `_shift_baseline` / `_space_words` /
  `_snap_advances`), `SnailClusterIterator`, `SnailShapeOptions` +
  `SnailOpenTypeFeature` for shape-time feature requests, and the explicit
  TrueType hint-run helpers.

## Benchmarks

```sh
zig build run-bench
zig build run-bench -Dgl44=false -Dgles30=false -Dvulkan=false  # trim backend rows
```

Last run: 2026-05-22, `zig build run-bench`, ReleaseFast benchmark build. Lower
times are better. These numbers are one local machine/run, not a portability
guarantee.

NotoSans-Regular, 20 prep runs, 1000 text iterations, 1000 draw-record iterations.

The vector workload contains filled and stroked rounded rectangles, ellipses, and custom cubic/quadratic paths. Backend rows follow the enabled build flags.

### Hardware

| Component | Detected |
|---|---|
| CPU | AMD Ryzen 9 5950X 16-Core Processor |
| GL 3.3 renderer | NVIDIA GeForce RTX 3090/PCIe/SSE2 |
| GL 3.3 version | 3.3.0 NVIDIA 595.71.05 |
| GL 4.4 (persistent mapped) renderer | NVIDIA GeForce RTX 3090/PCIe/SSE2 |
| GL 4.4 (persistent mapped) version | 4.4.0 NVIDIA 595.71.05 |
| OpenGL ES 3.0 renderer | NVIDIA GeForce RTX 3090/PCIe/SSE2 |
| OpenGL ES 3.0 version | OpenGL ES 3.2 NVIDIA 595.71.05 |
| Vulkan device | NVIDIA GeForce RTX 3090 |

### Preparation

| Workload | Snail | FreeType | FreeType / Snail |
|---|---:|---:|---:|
| Font load | 1.61 us | 8.87 us | 5.49x |
| Glyph prep, ASCII | 419.84 us | 1028.71 us | 2.45x |
| Glyph prep, 7 sizes | 419.84 us | 7233.28 us | 17.23x |
| TT hint setup @ 12px | 22.13 us | n/a | n/a |
| TT hint execute, ASCII @ 12px | 484.61 us | n/a | n/a |
| TT hint plan, ASCII @ 12px | 855.09 us | n/a | n/a |
| TT hint context cold, paragraph @ 12px | 246.96 us | n/a | n/a |
| TT hint context warm, paragraph @ 12px | 1.59 us | n/a | n/a |
| PathPicture freeze, 25 shapes | 178.69 us | n/a | n/a |

### Prepared Resource Memory

| Resource | Used bytes | Allocated GPU bytes | Used KiB | Allocated KiB |
|---|---:|---:|---:|---:|
| Snail text textures | 98304 | 196608 | 96.0 | 192.0 |
| Snail vector textures | 54352 | 54352 | 53.1 | 53.1 |
| FreeType bitmaps, one size | 65001 | 65001 | 63.5 | 63.5 |
| FreeType bitmaps, seven sizes | 538020 | 538020 | 525.4 | 525.4 |

### Text Creation And Layout

| Workload | Snail TextBlob | FreeType layout | FreeType / Snail |
|---|---:|---:|---:|
| Short string | 1.60 us | 82.59 us | 51.76x |
| Sentence | 5.38 us | 397.40 us | 73.93x |
| Paragraph | 18.30 us | 1419.90 us | 77.60x |
| Paragraph x 7 sizes | 126.78 us | 10188.98 us | 80.37x |
| Short string (TT hinted @ 24px) | 1.68 us | n/a | n/a |
| Sentence (TT hinted @ 48px) | 5.92 us | n/a | n/a |
| Paragraph (TT hinted @ 18px) | 17.59 us | n/a | n/a |
| Paragraph x 7 sizes (TT hinted) | 126.33 us | n/a | n/a |

### Draw Record Creation

| Scene | Commands | Words | Segments | PreparedScene.initOwned |
|---|---:|---:|---:|---:|
| Text | 4 | 4048 | 1 | 8.57 us |
| Rich text | 1 | 1136 | 1 | 2.24 us |
| Vector paths | 1 | 400 | 1 | 0.32 us |
| Mixed text + vector | 5 | 4448 | 2 | 9.20 us |
| Multi-script text | 4 | 1488 | 1 | 3.11 us |
| Text (TT hinted) | 4 | 4048 | 1 | 8.11 us |
| Mixed text + vector (TT hinted) | 5 | 4448 | 2 | 8.26 us |
| Multi-script text (TT hinted) | 4 | 1488 | 1 | 2.90 us |

### Prepared Render

Target: 640x360. Requested AA is grayscale. CPU uses 20 measured frames; GPU backends use 500 measured frames.

| Backend | Scene | Effective AA | Frames | Commands | Words | Segments | Instance bytes/frame | Draw prepared scene |
|---|---|---|---:|---:|---:|---:|---:|---:|
| CPU | Text | grayscale | 20 | 4 | 4048 | 1 | 16192 | 1701.86 us |
| CPU | Rich text | grayscale | 20 | 1 | 1136 | 1 | 4544 | 1459.42 us |
| CPU | Vector paths | grayscale | 20 | 1 | 400 | 1 | 1600 | 14999.43 us |
| CPU | Mixed text + vector | grayscale | 20 | 5 | 4448 | 2 | 17792 | 16529.82 us |
| CPU | Multi-script text | grayscale | 20 | 4 | 1488 | 1 | 5952 | 1019.34 us |
| CPU | Text (TT hinted) | grayscale | 20 | 4 | 4048 | 1 | 16192 | 4613.37 us |
| CPU | Mixed text + vector (TT hinted) | grayscale | 20 | 5 | 4448 | 2 | 17792 | 19732.49 us |
| CPU | Multi-script text (TT hinted) | grayscale | 20 | 4 | 1488 | 1 | 5952 | 2819.80 us |
| CPU (threaded) | Text | grayscale | 20 | 4 | 4048 | 1 | 16192 | 827.71 us |
| CPU (threaded) | Rich text | grayscale | 20 | 1 | 1136 | 1 | 4544 | 766.88 us |
| CPU (threaded) | Vector paths | grayscale | 20 | 1 | 400 | 1 | 1600 | 3220.73 us |
| CPU (threaded) | Mixed text + vector | grayscale | 20 | 5 | 4448 | 2 | 17792 | 3684.15 us |
| CPU (threaded) | Multi-script text | grayscale | 20 | 4 | 1488 | 1 | 5952 | 508.30 us |
| CPU (threaded) | Text (TT hinted) | grayscale | 20 | 4 | 4048 | 1 | 16192 | 2039.77 us |
| CPU (threaded) | Mixed text + vector (TT hinted) | grayscale | 20 | 5 | 4448 | 2 | 17792 | 4540.15 us |
| CPU (threaded) | Multi-script text (TT hinted) | grayscale | 20 | 4 | 1488 | 1 | 5952 | 1308.29 us |
| GL 3.3 | Text | grayscale | 500 | 4 | 4048 | 1 | 16192 | 23.42 us |
| GL 3.3 | Rich text | grayscale | 500 | 1 | 1136 | 1 | 4544 | 113.08 us |
| GL 3.3 | Vector paths | grayscale | 500 | 1 | 400 | 1 | 1600 | 94.58 us |
| GL 3.3 | Mixed text + vector | grayscale | 500 | 5 | 4448 | 2 | 17792 | 105.39 us |
| GL 3.3 | Multi-script text | grayscale | 500 | 4 | 1488 | 1 | 5952 | 20.13 us |
| GL 3.3 | Text (TT hinted) | grayscale | 500 | 4 | 4048 | 1 | 16192 | 60.56 us |
| GL 3.3 | Mixed text + vector (TT hinted) | grayscale | 500 | 5 | 4448 | 2 | 17792 | 141.83 us |
| GL 3.3 | Multi-script text (TT hinted) | grayscale | 500 | 4 | 1488 | 1 | 5952 | 51.13 us |
| GL 4.4 (persistent mapped) | Text | grayscale | 500 | 4 | 4048 | 1 | 16192 | 21.68 us |
| GL 4.4 (persistent mapped) | Rich text | grayscale | 500 | 1 | 1136 | 1 | 4544 | 40.21 us |
| GL 4.4 (persistent mapped) | Vector paths | grayscale | 500 | 1 | 400 | 1 | 1600 | 82.92 us |
| GL 4.4 (persistent mapped) | Mixed text + vector | grayscale | 500 | 5 | 4448 | 2 | 17792 | 89.07 us |
| GL 4.4 (persistent mapped) | Multi-script text | grayscale | 500 | 4 | 1488 | 1 | 5952 | 22.17 us |
| GL 4.4 (persistent mapped) | Text (TT hinted) | grayscale | 500 | 4 | 4048 | 1 | 16192 | 64.87 us |
| GL 4.4 (persistent mapped) | Mixed text + vector (TT hinted) | grayscale | 500 | 5 | 4448 | 2 | 17792 | 109.83 us |
| GL 4.4 (persistent mapped) | Multi-script text (TT hinted) | grayscale | 500 | 4 | 1488 | 1 | 5952 | 57.81 us |
| OpenGL ES 3.0 | Text | grayscale | 500 | 4 | 4048 | 1 | 16192 | 17.19 us |
| OpenGL ES 3.0 | Rich text | grayscale | 500 | 1 | 1136 | 1 | 4544 | 93.34 us |
| OpenGL ES 3.0 | Vector paths | grayscale | 500 | 1 | 400 | 1 | 1600 | 80.60 us |
| OpenGL ES 3.0 | Mixed text + vector | grayscale | 500 | 5 | 4448 | 2 | 17792 | 97.97 us |
| OpenGL ES 3.0 | Multi-script text | grayscale | 500 | 4 | 1488 | 1 | 5952 | 18.82 us |
| OpenGL ES 3.0 | Text (TT hinted) | grayscale | 500 | 4 | 4048 | 1 | 16192 | 59.83 us |
| OpenGL ES 3.0 | Mixed text + vector (TT hinted) | grayscale | 500 | 5 | 4448 | 2 | 17792 | 138.73 us |
| OpenGL ES 3.0 | Multi-script text (TT hinted) | grayscale | 500 | 4 | 1488 | 1 | 5952 | 50.44 us |
| Vulkan | Text | grayscale | 500 | 4 | 4048 | 1 | 16192 | 23.94 us |
| Vulkan | Rich text | grayscale | 500 | 1 | 1136 | 1 | 4544 | 39.87 us |
| Vulkan | Vector paths | grayscale | 500 | 1 | 400 | 1 | 1600 | 71.42 us |
| Vulkan | Mixed text + vector | grayscale | 500 | 5 | 4448 | 2 | 17792 | 75.29 us |
| Vulkan | Multi-script text | grayscale | 500 | 4 | 1488 | 1 | 5952 | 23.91 us |
| Vulkan | Text (TT hinted) | grayscale | 500 | 4 | 4048 | 1 | 16192 | 62.35 us |
| Vulkan | Mixed text + vector (TT hinted) | grayscale | 500 | 5 | 4448 | 2 | 17792 | 108.91 us |
| Vulkan | Multi-script text (TT hinted) | grayscale | 500 | 4 | 1488 | 1 | 5952 | 57.35 us |

### Render Modes

Per-AA timings for the text and multi-script scenes. Requested AA is
the draw-state request; effective AA shows backend fallbacks such as
GLES30 rendering grayscale when LCD dual-source blending is unavailable.

| Backend | Scene | Requested AA | Effective AA | Words | Segments | PreparedScene | Draw |
|---|---|---|---|---:|---:|---:|---:|
| CPU | Text | grayscale | grayscale | 4048 | 1 | 8.19 us | 1632.09 us |
| CPU | Text | subpixel rgb | subpixel rgb | 4048 | 1 | 8.17 us | 8299.91 us |
| CPU | Rich text | grayscale | grayscale | 1136 | 1 | 2.13 us | 1506.68 us |
| CPU | Rich text | subpixel rgb | subpixel rgb | 1136 | 1 | 2.11 us | 4385.59 us |
| CPU | Multi-script text | grayscale | grayscale | 1488 | 1 | 2.87 us | 1030.27 us |
| CPU | Multi-script text | subpixel rgb | subpixel rgb | 1488 | 1 | 2.89 us | 5001.23 us |
| CPU (threaded) | Text | grayscale | grayscale | 4048 | 1 | 8.48 us | 798.84 us |
| CPU (threaded) | Text | subpixel rgb | subpixel rgb | 4048 | 1 | 8.16 us | 3504.50 us |
| CPU (threaded) | Rich text | grayscale | grayscale | 1136 | 1 | 2.19 us | 651.73 us |
| CPU (threaded) | Rich text | subpixel rgb | subpixel rgb | 1136 | 1 | 2.23 us | 2168.48 us |
| CPU (threaded) | Multi-script text | grayscale | grayscale | 1488 | 1 | 2.98 us | 488.95 us |
| CPU (threaded) | Multi-script text | subpixel rgb | subpixel rgb | 1488 | 1 | 2.98 us | 2124.47 us |
| GL 3.3 | Text | grayscale | grayscale | 4048 | 1 | 8.50 us | 16.80 us |
| GL 3.3 | Text | subpixel rgb | subpixel rgb | 4048 | 1 | 8.55 us | 74.06 us |
| GL 3.3 | Rich text | grayscale | grayscale | 1136 | 1 | 2.25 us | 93.42 us |
| GL 3.3 | Rich text | subpixel rgb | subpixel rgb | 1136 | 1 | 2.31 us | 214.71 us |
| GL 3.3 | Multi-script text | grayscale | grayscale | 1488 | 1 | 3.02 us | 17.50 us |
| GL 3.3 | Multi-script text | subpixel rgb | subpixel rgb | 1488 | 1 | 3.01 us | 92.24 us |
| GL 4.4 (persistent mapped) | Text | grayscale | grayscale | 4048 | 1 | 8.49 us | 25.39 us |
| GL 4.4 (persistent mapped) | Text | subpixel rgb | subpixel rgb | 4048 | 1 | 8.44 us | 79.48 us |
| GL 4.4 (persistent mapped) | Rich text | grayscale | grayscale | 1136 | 1 | 2.97 us | 51.90 us |
| GL 4.4 (persistent mapped) | Rich text | subpixel rgb | subpixel rgb | 1136 | 1 | 2.31 us | 68.60 us |
| GL 4.4 (persistent mapped) | Multi-script text | grayscale | grayscale | 1488 | 1 | 2.97 us | 26.11 us |
| GL 4.4 (persistent mapped) | Multi-script text | subpixel rgb | subpixel rgb | 1488 | 1 | 2.99 us | 87.50 us |
| OpenGL ES 3.0 | Text | grayscale | grayscale | 4048 | 1 | 8.75 us | 16.77 us |
| OpenGL ES 3.0 | Text | subpixel rgb | grayscale (LCD unavailable) | 4048 | 1 | 8.79 us | 18.31 us |
| OpenGL ES 3.0 | Rich text | grayscale | grayscale | 1136 | 1 | 2.34 us | 96.61 us |
| OpenGL ES 3.0 | Rich text | subpixel rgb | grayscale (LCD unavailable) | 1136 | 1 | 2.26 us | 97.84 us |
| OpenGL ES 3.0 | Multi-script text | grayscale | grayscale | 1488 | 1 | 3.39 us | 24.56 us |
| OpenGL ES 3.0 | Multi-script text | subpixel rgb | grayscale (LCD unavailable) | 1488 | 1 | 3.64 us | 17.15 us |
| Vulkan | Text | grayscale | grayscale | 4048 | 1 | 9.05 us | 24.26 us |
| Vulkan | Text | subpixel rgb | subpixel rgb | 4048 | 1 | 9.10 us | 94.39 us |
| Vulkan | Rich text | grayscale | grayscale | 1136 | 1 | 2.32 us | 35.51 us |
| Vulkan | Rich text | subpixel rgb | subpixel rgb | 1136 | 1 | 2.57 us | 76.76 us |
| Vulkan | Multi-script text | grayscale | grayscale | 1488 | 1 | 3.20 us | 27.27 us |
| Vulkan | Multi-script text | subpixel rgb | subpixel rgb | 1488 | 1 | 3.23 us | 77.24 us |

## Architecture

```
src/
  snail/
    root.zig             public API facade and domain-module exports
    font.zig             public font wrapper and font metric aliases
    text.zig             public text API facade
    text/                text atlases, shaping, TT hint helpers, blobs, batches, and tests
    target.zig           render-target geometry, explicit snapping, resolve, and AA policy types
    math.zig             math facade for vectors, matrices, bounds, and curves
    path.zig             public vector path API facade
    path/                path storage, picture freezing, batches, debug overlays, and tests
    paint.zig            paint, gradient, image-paint public types
    image.zig            immutable image resource wrapper
    resources.zig        public resource manifest/prepared-resource facade
    resources/           prepared resources, views, stamps, manifests, and footprint accounting
    upload.zig           resource upload batches and prepared-resource upload execution
    draw.zig             draw options and public draw-record types
    scene.zig            immutable ordered draw scene
    c_api.zig            C ABI over the explicit resource model
    c_api/               generated-manifest, handles, conversion, domains, tests, and runtime
    glyph_emit.zig       glyph -> vertex dispatch (plain, COLR, painted, multi-layer)
    paint_records.zig    shared paint-record encoding for text and vector draws
    resource_key.zig     stable resource-key helpers
    font/                TrueType/OpenType/HarfBuzz font primitives
    math/                Bezier, vector, matrix, and root-solving implementations
    render/
      interface.zig      renderer interface and draw entry points
      adapter/           public CPU/GL/GLES/Vulkan renderer adapters
      format/            shared packed atlas, vertex, and upload formats
      upload_plan.zig    prepared upload planning shared by backends
      backend/
        atlas/           backend-facing atlas helpers
        cpu/             software rasterizer implementation and resources
        gl/              OpenGL state, resources, bindings, programs, shaders
        vulkan/          Vulkan pipeline, resources, types, SPIR-V loader
        subpixel_policy.zig subpixel rendering policy logic
        glsl/            shared GLSL bodies for GL and Vulkan backends
        vulkan_glsl/     Vulkan shader wrappers (compiled to SPIR-V at build time)
  demo/
    main.zig             interactive renderer demo
    game.zig             game-style OpenGL demo entry point
    screenshot.zig       headless screenshot demo
    algorithm_screenshots.zig README algorithm diagram renderer
    renderer_driver.zig  backend-selection glue for the interactive demo
    banner.zig           reusable demo layout
    scene.zig            interactive demo scene construction
    platform/            demo-only Wayland/EGL/Vulkan/offscreen support
      gl.zig             Wayland + EGL platform for the GL demo
      vulkan.zig         Wayland + Vulkan swapchain/offscreen setup
      cpu.zig            Wayland shared-memory platform for the CPU demo
      wayland.zig        Wayland window + input handling
      egl.zig            shared EGL setup
      offscreen_gl.zig   headless EGL context
      subpixel.zig       display subpixel-layout detection
      presentation.zig   demo presentation metadata
    profile/
      timer.zig          comptime-gated CPU timers
  tools/
    bench.zig            benchmark tool used to refresh README tables
    bench/               benchmark timing, report, and FreeType comparison helpers
    backend_compare.zig  CPU/GL/GLES/Vulkan pixel comparison check
    profile_cpu_text.zig CPU text-rendering profile target
  support/
    root.zig             shared support module for demos/tools only
    gl.zig               shared OpenGL C imports for demos/tools
    screenshot.zig       shared framebuffer capture and TGA/PNG writers
include/
  snail.h                shared C API: resources, upload, draw records, coverage records
  snail_generated.h      generated by build/install; not checked in
  snail_cpu.h            CPU backend C constructor and thread-pool hook
  snail_gl33.h           GL 3.3 backend C constructor and coverage bindings
  snail_gl44.h           GL 4.4 backend C constructor and coverage bindings
  snail_gles30.h         OpenGL ES 3.0 backend C constructor and coverage bindings
  snail_vulkan.h         Vulkan backend C constructor, upload, and coverage hooks
```

## License

snail source code is MIT licensed; see `LICENSE`.

Bundled demo/test fonts and emoji assets have separate notices in
`assets/LICENSES.md`. In short, the Noto fonts are under the SIL Open Font
License 1.1, and `TwemojiMozilla.ttf` includes Twemoji artwork under CC BY 4.0.

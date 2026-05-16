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

**Font loading.** snail parses TrueType fonts directly: `cmap` for codepoint-to-glyph mapping, `glyf`/`loca` for outlines, `hhea`/`hmtx` for metrics, `kern` for legacy kerning, and `OS/2` + `post` for underline/strikethrough/superscript/subscript metrics. `COLR` is parsed for color emoji. Optional OpenType shaping applies GSUB ligature substitution (type 4) and GPOS pair positioning (type 2). HarfBuzz can be compiled in for full complex-script shaping.

**Atlas preparation.** Each glyph's quadratic Bezier curves are packed into two GPU textures at load time:

- *Curve texture* (RGBA16F): control points for every curve segment, stored as f16 in font-unit coordinates.
- *Band texture* (RG16UI): spatial subdivision indices. The glyph bounding box is split into horizontal and vertical bands; each band records which curve segments intersect it.

This preprocessing is CPU-only and runs once per glyph set. GPU backends upload the prepared data into 2D texture arrays (one layer per atlas page); the CPU backend reads the same arrays directly without uploading.

**Fragment shader.** At draw time, each glyph is a screen-space quad. The fragment shader:

1. Reads the band indices for this fragment's position.
2. For each curve in the active bands, evaluates a quadratic Bezier root equation to count ray crossings.
3. Applies the winding rule (non-zero or even-odd) to determine inside/outside.
4. Outputs analytic coverage as alpha, optionally with per-channel LCD subpixel offsets for horizontal RGB/BGR or vertical VRGB/VBGR subpixel rendering.

There is no rasterization, no texture sampling for glyph shapes, and no distance field approximation.

**Vector paths.** Filled and stroked `Path` geometry shares the curve/band texture format with text; only the fragment shader differs (the path shader handles per-shape paint records and composite groups, while the text shader fast-paths plain coverage). Cubic Bezier inputs are adaptively approximated to quadratics. Strokes are expanded into offset curves with joins (miter, bevel, round) and caps (butt, square, round). The `PathPicture` type freezes a set of styled paths into an immutable atlas snapshot that can be instanced cheaply per frame.

## Color convention

All color parameters are **sRGB, straight (unpremultiplied) alpha**, as `[4]f32` in the range 0.0–1.0. This applies to `Paint.solid`, gradient stops, `ImagePaint.tint`, and text color arguments. The renderer premultiplies alpha and linearizes for blending internally.

**Images** (`Image.initSrgba8`) expect sRGB-encoded RGBA8 pixel data (4 bytes per pixel, 0–255). This is what most image decoders produce. Linear-space pixel buffers will appear too bright.

**Gradients** interpolate in sRGB space, which gives perceptually smooth results for UI use. `LinearGradient` and `RadialGradient` provide extend modes for clamp, repeat, and reflect behavior.

**Blending** uses premultiplied alpha. Shaders decode sRGB inputs to linear before applying coverage. On GL/Vulkan sRGB attachments, fixed-function attachment encoding handles linear->sRGB storage and gamma-correct blending. On linear attachments or CPU buffers, `ResolveTarget.encoding` states what the attachment accepts and what final pixel bytes the consumer expects.

**Output encoding.** `ResolveTarget.encoding` is required on every draw:

- `TargetEncoding.srgb`: normal GL/Vulkan `_SRGB` attachment or swapchain image; the attachment does the final encode.
- `TargetEncoding.linear`: linear UNORM/float targets or CPU buffers whose bytes should stay linear.
- `TargetEncoding.srgb_pixels_on_linear_attachment`: linear-format storage, including CPU byte buffers, whose consumer expects sRGB bytes. With the default direct resolve, fixed-function blending happens in storage space; this is a compatibility path for targets that cannot be tagged as sRGB, not a gamma-correct composition path.

`ResolveTarget.resolve` selects how Snail resolves into the target:

- `.direct`: draw straight into the target. This is the default.
- `.linear`: valid with `TargetEncoding.srgb_pixels_on_linear_attachment`. Snail resolves through a linear intermediate, then encodes the result into the linear-format target as sRGB pixels. `LinearResolve.backdrop` chooses whether to seed from the target, a clear color, transparent black, or unspecified contents; `LinearResolve.region` can restrict the resolve to a pixel rectangle; `LinearResolve.intermediate_format` selects RGBA16F or RGBA32F. GL supports the full contract, CPU uses the equivalent linear decode/blend/encode path, and Vulkan currently reports `error.UnsupportedResolve` because its renderer records inside a caller-owned render pass.

The CPU renderer has no format-level encoder: it writes RGBA8 bytes according to `encoding.stored_pixels`. It uses an exact 256-entry sRGB->linear LUT for u8 texels and the IEC 61966-2-1 formula directly for linear->sRGB output, with round-to-nearest rounding.

**Coverage transfer.** `ResolveTarget.coverage_transfer` optionally remaps analytic coverage before blending. The default is identity; `CoverageTransfer.power(exponent)` exposes explicit display tuning when a target benefits from slightly stronger or lighter antialiasing.

## Build

Requires [Zig 0.16](https://ziglang.org/download/), OpenGL 3.3+, Vulkan headers/loader, `glslc`, and pkg-config. Vulkan and HarfBuzz are enabled by default but can be disabled (see flags below). The interactive demo requires Wayland, plus EGL for OpenGL mode.

```sh
zig build test                                  # unit tests
zig build run                                   # interactive 2D demo; press C to cycle enabled backends
zig build run -Dvulkan=false                    # demo without Vulkan
zig build run -Dopengl=false                    # demo without OpenGL
zig build run -Dcpu-renderer=false              # demo without CPU rendering
zig build run-game-demo                         # 3D scene with HUD + world-space text on walls
zig build screenshot                            # 2D demo offscreen → zig-out/demo-screenshot.tga
zig build backend-compare                       # CPU/GL/Vulkan parity
zig build bench                                 # benchmarks, including Vulkan rows when a Vulkan device is available
zig build install --release=fast                # install libsnail, enabled C headers, and snail.pc
zig build gen-c-api                             # emit generated C API artifacts into the Zig cache
```

Library backend flags:

- `-Dopengl=true` (default) — OpenGL backend (`GlRenderer`); installs `snail_gl.h` when the C API is enabled.
- `-Dgl33=false` (default) — pass `=true` to force an OpenGL 3.3 context/backend path where OpenGL is used.
- `-Dvulkan=true` (default) — Vulkan backend (`VulkanRenderer`); pass `=false` for a slimmer OpenGL/CPU-only build. SPIR-V shaders are compiled at build time via `glslc`; installs `snail_vulkan.h` when the C API is enabled. That extension header includes Vulkan headers.
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

The checked-in screenshot at `assets/demo_screenshot.png` is regenerated from the `zig build screenshot` TGA output.

### Nix

```sh
nix-shell           # dev shell with all dependencies
nix-build -A lib    # build libsnail + enabled C headers
nix-build -A demo   # build snail-demo
```

The Nix library package is defined in `nix/snail.nix`; the demo executable is
defined separately in `nix/snail-demo.nix`. Both are wired through
`callPackage` from `default.nix`. The library defaults mirror the Zig build
defaults: OpenGL on, Vulkan on, CPU renderer on, HarfBuzz on, and the C API
enabled with both shared and static libraries. Override `enableVulkan`,
`enableOpenGL`, `enableCpu`, `enableHarfBuzz`, `enableCApi`, `cApiShared`, or
`cApiStatic` when calling the library package directly.
The demo package also enables all three renderers by default and cycles between
the enabled set at runtime.

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

var blob_builder = snail.TextBlobBuilder.init(allocator, &atlas);
defer blob_builder.deinit();
var shaped = try atlas.shapeText(allocator, .{}, "Hello, world!");
defer shaped.deinit();
_ = try blob_builder.append(.{
    .shaped = &shaped,
    .placement = .{ .baseline = .{ .x = 10, .y = 400 }, .em = 48 },
    .fill = .{ .solid = .{ 1, 1, 1, 1 } },
});

var blob = try blob_builder.finish();
defer blob.deinit();

var scene = snail.Scene.init(allocator);
defer scene.deinit();
try scene.addText(.{ .blob = &blob });
// (See "Vector Paths" below for adding a PathPicture to the same scene.)

var resource_entries: [8]snail.ResourceSet.Entry = undefined;
var resources = snail.ResourceSet.init(&resource_entries);
try resources.addScene(&scene);

// Requires an active GL context. Vulkan uses snail.VulkanRenderer.init(allocator, ctx).
var gl = try snail.GlRenderer.init(allocator);
defer gl.deinit();
var prepared = try gl.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &resources);
defer prepared.deinit();

const viewport_wf: f32 = @floatFromInt(viewport_w);
const viewport_hf: f32 = @floatFromInt(viewport_h);
const options = snail.DrawOptions{
    .mvp = snail.Mat4.ortho(0, viewport_wf, viewport_hf, 0, -1, 1),
    .target = .{
        .pixel_width = viewport_wf,
        .pixel_height = viewport_hf,
        .subpixel_order = .rgb,
        .encoding = .srgb,
    },
};

var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, &scene, options);
defer prepared_scene.deinit();
try gl.drawPrepared(&prepared, &prepared_scene, options);
```

### On-demand Atlas Extension

`ensureText`, `ensureShaped`, and `ensureGlyphs` return a new immutable snapshot; the old one remains valid for in-flight readers. Existing `TextBlob`s keep working with the snapshot they were built against as long as that snapshot and its prepared backend resources stay alive.

```zig
if (try atlas.ensureText(.{}, text)) |next| {
    atlas.deinit();  // safe only after readers of the old snapshot are done
    atlas = next;
}
```

`TextBlob.rebound` is optional. Use it when you cache blobs across atlas extension and want a new blob that borrows the compatible superset snapshot, usually so the old snapshot can be released and old prepared resources retired without reshaping unchanged text rows.

If you already have shaped glyph IDs, extend the atlas directly and create rebound copies only for the cached blobs you plan to keep:

```zig
if (try atlas.ensureGlyphs(face_index, glyph_ids)) |next| {
    var next_blob = try blob.rebound(allocator, &next);
    blob.deinit();
    blob = next_blob;
    atlas.deinit();
    atlas = next;
}
```

### Vector Paths

A `PathPicture` is built once and submitted to a `Scene` like a `TextBlob`. Add
all draws to the scene **before** calling `resources.addScene` and uploading —
`PreparedResources` is a snapshot of the scene's resource set at upload time.

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
try scene.addPath(.{ .picture = &picture });
```

## Example: C

> **Note:** This example uses the OpenGL C backend and requires an active OpenGL context. CPU callers include `snail_cpu.h`, provide a caller-owned RGBA8 buffer, and may attach a caller-owned `SnailThreadPool`; Vulkan callers include `snail_vulkan.h` and provide a `SnailVulkanContext`. Error checks are omitted here for brevity.

```c
#include "snail.h"
#include "snail_gl.h"

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

SnailScene *scene = NULL;
snail_scene_init(NULL, &scene);
snail_scene_add_text(scene, blob);
snail_scene_add_path_picture(scene, picture);

SnailResourceSet *resources = NULL;
snail_resource_set_init(NULL, 8, &resources);
snail_resource_set_add_scene(resources, scene);

SnailRenderer *renderer = NULL;
snail_gl_renderer_init(&renderer);

SnailDrawOptions draw_options = {
    .mvp = snail_mat4_identity(), // replace with your pixel-to-clip projection
    .target = {
        .pixel_width = 1280,
        .pixel_height = 720,
        .subpixel_order = SNAIL_SUBPIXEL_RGB,
        .fill_rule = SNAIL_FILL_NONZERO,
        .is_final_composite = true,
        .opaque_backdrop = true,
        .will_resample = false,
        .attachment_encoding = SNAIL_COLOR_ENCODING_SRGB,
        .stored_pixel_encoding = SNAIL_COLOR_ENCODING_SRGB,
        .resolve_kind = SNAIL_RESOLVE_DIRECT,
        .resolve_backdrop = SNAIL_RESOLVE_BACKDROP_TARGET,
        .resolve_region = SNAIL_RESOLVE_REGION_FULL_TARGET,
        .resolve_intermediate_format = SNAIL_INTERMEDIATE_FORMAT_RGBA16F,
        .coverage_exponent = 1.0f,
    },
};

SnailPreparedResources *prepared = NULL;
snail_renderer_upload_resources_blocking(renderer, NULL, resources, &prepared);

SnailPreparedScene *prepared_scene = NULL;
snail_prepared_scene_init(NULL, prepared, scene, draw_options, &prepared_scene);
snail_renderer_draw_prepared(renderer, prepared, prepared_scene, draw_options);

// Cleanup
snail_prepared_scene_deinit(prepared_scene);
snail_prepared_resources_deinit(prepared);
snail_renderer_deinit(renderer);
snail_resource_set_deinit(resources);
snail_scene_deinit(scene);
snail_text_blob_deinit(blob);
snail_path_picture_deinit(picture);
snail_path_picture_builder_deinit(builder);
snail_path_deinit(path);
snail_text_atlas_deinit(atlas);
```

The C scene API includes C-only helper variants for common cases such as a
single transform, a sub-range, or an owned override copy. Those helpers exist
to make FFI lifetime management explicit; the core model is still the same
borrowed `Scene` + `PathDraw` / `TextDraw` primitive used by Zig.

## API reference

### Types

| Type | Description |
|------|-------------|
| `TextAtlas` | Immutable CPU font/glyph snapshot. `ensureText`, `ensureShaped`, and `ensureGlyphs` return a new snapshot; old stays valid. |
| `ShapedText` | Shaped glyph placements for a string/run. |
| `TextBlob` | Positioned text that borrows a `TextAtlas` snapshot. It can be rebound to a compatible superset snapshot when cache lifetime needs it. |
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
| `PathDraw`, `TextDraw` | Submission record: resource pointer, optional sub-range, and an `[]const Override` array (length = GPU instance count). |
| `Override` | Per-instance composition: `transform` composed onto baked transform, `tint` multiplied onto the resource's baked color or paint, including color-font palette layers. |
| `Range` | `{ start, count }` slice into a `PathPicture`'s shapes or a `TextBlob`'s glyphs. |
| `ResourceSet` | Fixed-capacity borrowed manifest of CPU values. |
| `ResourceFootprint` | Used and allocated upload bytes split by curve, band, layer-info, and image storage. |
| `PreparedResources` | Backend realization for one renderer/context. |
| `DrawList` | Caller-buffered draw records. |
| `PreparedScene` | Optional owned draw-record cache for static scenes. |
| `TargetEncoding` | Pair of color encodings for attachment interpretation and final stored pixels. Common presets are `.srgb`, `.linear`, and `.srgb_pixels_on_linear_attachment`. |
| `Resolve` | Per-target resolve path: `.direct` or `.linear` for gamma-correct Snail composition into sRGB pixels on a linear attachment. |
| `LinearResolve` | Options for `.linear`: `backdrop`, `region`, and `intermediate_format`. |
| `ResolveBackdrop` | Backdrop contract for a linear resolve: `.target`, `.clear`, `.transparent`, or `.dont_care`. |
| `ResolveRegion` | Full-target or pixel-rectangle bounds for a resolve. |
| `PixelRect` | Integer pixel rectangle `{ .x, .y, .w, .h }` used by `ResolveRegion.pixel_rect`. |
| `IntermediateFormat` | GL linear intermediate precision: `.rgba16f` or `.rgba32f`. |
| `CoverageTransfer` | Optional analytic coverage remap. `.identity` is the default; `.power(exponent)` is explicit display tuning. |
| `ResolveTarget` | Final target metadata: pixel size, subpixel order, fill rule, composite safety flags, required `encoding`, explicit `resolve`, and optional `coverage_transfer`. |
| `GlRenderer`, `VulkanRenderer`, `CpuRenderer` | First-class backend renderers. |
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
| `TextBlob.init(alloc, atlas, append) !TextBlob` | Build one positioned, painted `TextAppend` from a `ShapedText`. The blob borrows `atlas`. |
| `blob.rebound(alloc, new_atlas) !TextBlob` | Optional cache/lifetime helper: return a blob bound to a compatible atlas snapshot that retains old pages and contains all referenced glyphs. |
| `TextBlobBuilder.init(alloc, atlas)` / `builder.append(TextAppend) !TextAppendResult` / `builder.finish() !TextBlob` | Append shaped runs with explicit placement and fill. Call `atlas.ensureText`/`ensureShaped`/`ensureGlyphs` first if all glyphs must be renderable. |
| `TextAppend` | `{ .shaped, .glyphs, .placement = .{ .baseline, .em }, .fill }` — appends a whole shaped run or glyph subrange with independent position/scale and paint. Fill accepts the same `Paint` union used by paths, in the same coordinate space as `placement`. |
| `TextAppendResult` | `{ .advance: Vec2, .missing: bool }` — pen advance and whether any referenced glyph was absent from the current atlas snapshot. |

### Scene

A scene is a borrowed list of `PathDraw` / `TextDraw` submissions. Each submission selects a sub-range of an immutable resource and emits one GPU instance per `Override` (default: a single identity instance). The scene borrows the `picture` / `blob` pointer *and* the `instances` slice on each submission — all three must stay live until `scene.reset()` or `scene.deinit()`. `addPath` / `addText` use the allocator captured by `Scene.init` only when growing the command list.

| Method | Description |
|--------|-------------|
| `Scene.init(alloc) Scene` | New empty scene. |
| `scene.addPath(PathDraw) !void` | Submit a path draw. Borrows `picture` and `instances`. |
| `scene.addText(TextDraw) !void` | Submit a text draw. Borrows `blob` and `instances`. |
| `scene.reset()` | Clear commands; capacity is retained. |
| `scene.deinit()` | Free the command list. |

```zig
// Trivial draw.
try scene.addPath(.{ .picture = &picture });

// One transform.
const overrides = [_]snail.Override{.{ .transform = transform }};
try scene.addPath(.{ .picture = &picture, .instances = &overrides });

// Sub-range of shapes.
try scene.addPath(.{
    .picture = &picture,
    .shapes = .{ .start = 4, .count = 12 },
});

// Many instances (tile / sprite / particle batch).
try scene.addPath(.{ .picture = &sprite, .instances = entity_overrides });
```

### ResourceSet

`ResourceSet` is a caller-buffered manifest of CPU resources to prepare for a renderer. Entries borrow their source objects; keep those objects alive through the blocking upload or through `pending.record` for a scheduled upload. GPU backends copy texture payload during upload. CPU-backed `PreparedResources` still borrow uploaded atlas band/layer-info data and image pixels, so keep uploaded `TextAtlas`, painted `TextBlob`, `PathPicture`, and `Image` values alive until those CPU prepared resources are retired.

| Method | Description |
|--------|-------------|
| `ResourceSet.init(entries)` | Wrap a caller-owned `[]ResourceSet.Entry` buffer. |
| `set.reset()` | Clear entries; capacity is retained. |
| `set.putTextAtlas(key, atlas)` / `set.putTextAtlasOptions(key, atlas, options)` | Add a text atlas, optionally overriding atlas capacity mode. |
| `set.putPathPicture(key, picture)` / `set.putPathPictureOptions(key, picture, options)` | Add a path picture, optionally overriding atlas capacity mode. |
| `set.putImage(key, image)` | Add an image resource. |
| `set.addScene(scene)` | Discover and add all resources referenced by a scene. |
| `set.estimateUploadFootprint() !ResourceFootprint` | Allocation-free estimate for a resource set before upload. |

### Renderer

`GlRenderer`, `VulkanRenderer`, and `CpuRenderer` are first-class types; `Renderer` is a type-erased wrapper for backend-agnostic code. Blocking upload and draw methods are present on each concrete renderer and on `Renderer`; scheduled upload is exposed on `Renderer`, `GlRenderer`, and `VulkanRenderer`.

| Method | Description |
|--------|-------------|
| `GlRenderer.init(alloc) !GlRenderer` | Initialize the OpenGL backend. Requires the GL context to be current. |
| `VulkanRenderer.init(alloc, ctx) !VulkanRenderer` | Initialize the Vulkan backend from a caller-owned `VulkanContext`. |
| `CpuRenderer.init(pixels, w, h, stride) CpuRenderer` | Initialize the CPU backend over a caller-owned RGBA8 buffer. |
| `cpu.setThreadPool(?*snail.ThreadPool)` | Opt into scanline-tiled multithreaded rendering using a caller-owned `snail.ThreadPool`. Byte-identical output to the single-threaded path; the draw call itself stays allocation-free. |
| `vk.beginFrame(.{ .cmd, .frame_index })` | Bind a caller-recorded Vulkan command buffer + frame index for the current frame. |
| `renderer.uploadResourcesBlocking(.{ .persistent, .scratch }, set) !PreparedResources` | Blocking upload + view construction. Persistent allocations live with `PreparedResources`; scratch allocations end when upload returns. |
| `renderer.planResourceUpload(current, next_set, changed_keys) !ResourceUploadPlan` | Diff a new resource set against existing prepared resources. |
| `renderer.beginResourceUpload(.{ .persistent, .scratch }, plan) !PendingResourceUpload` | Start a scheduled upload; record into a caller command buffer for Vulkan, then call `pending.publish()`. |
| `DrawList.init(words, segments)` | Wrap a caller-buffered word + segment buffer for `addScene`. |
| `DrawList.estimate(scene, options)` | Upper bound for the word buffer required by `draw.addScene(prepared, scene, options)`. |
| `DrawList.estimateSegments(scene, options)` | Upper bound for the segment buffer required by `draw.addScene(prepared, scene, options)`. |
| `PreparedScene.initOwned(alloc, prepared, scene, options) !PreparedScene` | Build an owned draw-record cache for a static scene. |
| `renderer.draw(prepared, records, options)` | Execute prebuilt draw records. No resource discovery or upload. |
| `renderer.drawPrepared(prepared, prepared_scene, options)` | Draw a `PreparedScene` cache. |
| `prepared.retireNow()` | Retire backend resources immediately once no in-flight frame references them. |
| `PreparedResourceRetirementQueue.init(alloc)` / `queue.sweep()` | Caller-owned queue for prepared resources that must retire after a fence completes. |
| `prepared.retireAfter(&queue, fence_or_frame)` | Move prepared resources into the caller-owned retirement queue. |

### Scheduled resource upload

`uploadResourcesBlocking` is the simple path; for engines that want to overlap
upload with the main render queue (Vulkan in particular) there is an explicit
plan / record / publish flow. Use a type-erased `Renderer` for backend-agnostic
scheduled uploads, including CPU-backed uploads.

1. **Plan.** `renderer.planResourceUpload(current, next_set, changed_keys_buf)`
   diffs `next_set` against the existing `PreparedResources` (or `null` for a
   first upload) and records which `ResourceKey` entries changed. The result
   is a `ResourceUploadPlan` whose `upload_footprint`, `upload_bytes`, and
   `changedKeys()` are informational. `upload_bytes` is
   `upload_footprint.allocatedBytes()` for simple budget checks.
   `changed_keys_buf` is caller-owned scratch — size it to the number of
   distinct resources you might submit.
2. **Begin + record.** `renderer.beginResourceUpload(.{ .persistent = allocator, .scratch = allocator }, plan)` returns
   a `PendingResourceUpload`. Call `pending.record(.no_command, .{ .budget_bytes = N })`
   for GL/CPU. For Vulkan, pass `.{ .vulkan = command_buffer }` while recording
   the caller-owned command buffer.
3. **Wait + publish.** Call `pending.ready(.complete)`, `.pending`, or
   `.{ .vulkan_fence = fence }` to report external completion. GL/CPU report
   ready immediately after record. Once true, `pending.publish()` returns the new `PreparedResources`. Call
   `pending.deinit()` if you need to abandon the upload before publishing.

The new `PreparedResources` replaces the old one; retire the old one via
`old.retireNow()` once no in-flight frame still references it. For Vulkan
resources that need fence retirement, keep a caller-owned
`PreparedResourceRetirementQueue`, call `old.retireAfter(&queue, fence)`, and
sweep the queue explicitly.

C callers use the same flow through `SnailResourceUploadPlan` and
`SnailPendingResourceUpload`. `snail_pending_resource_upload_record` covers
CPU/GL; Vulkan callers use
`snail_vulkan_pending_resource_upload_record(command_buffer, budget_bytes)` and
`snail_vulkan_pending_resource_upload_ready_fence`.

### Text coverage in custom shaders

`snail.coverage.Shader`, `snail.coverage.TextCoverageRecords`, and
`snail.coverage.Backend` let a
material shader sample snail's exact glyph coverage without going through
`Renderer.draw`. The typical use is layering text with custom lighting,
masking, or compositing.

- `snail.coverage.Shader.gl` exposes GLSL 330 sources you can `@embedFile`-style
  splice into your own program: `vertex_interface`,
  `fragment_interface`, `resource_interface`, `coverage_functions`, and
  `fragment_body`.
- `snail.coverage.Shader.vulkan` exposes the Vulkan shader sources and descriptor
  binding numbers. The Vulkan coverage backend binds Snail's descriptor set
  into a caller-owned compatible pipeline layout.
- `snail.coverage.TextCoverageRecords` is the per-glyph vertex stream over a caller-owned
  `[]u32`. Size it with `snail.coverage.TextCoverageRecords.wordCapacityForBlob(blob)`,
  initialize with `snail.coverage.TextCoverageRecords.init(buffer)`, then call
  `records.buildLocal(prepared, blob, .{ .transform = ... })`. `buildLocal`
  does not allocate; it returns `error.DrawListFull` if the buffer is too
  small. Call `records.validFor(prepared)` after a re-upload and
  `records.buildLocal(prepared, blob, options)` if the atlas has moved. Use
  `records.glyph(i)` when a shader needs a decoded, random-access metadata
  buffer instead of Snail's native vertex stream.
- `snail.coverage.Backend` is the backend hook. Get one from
  `prepared.coverageBackend(renderer)` (or `gl.coverageBackend(prepared)`
  / `vk.coverageBackend(prepared)` on typed renderers). Call
  `bindResources(.{ .gl = bindings })` or `bindResources(.{ .vulkan = bindings })`, then
  `drawCoverage(&records)` or `drawVertices` with your own buffer.

C callers use `SnailTextCoverageRecords`, `snail_text_coverage_records_glyph`,
and `SnailCoverageBackend` from `snail.h`; GL binding uniforms and shader
snippets live in `snail_gl.h`, and Vulkan descriptor layout helpers live in
`snail_vulkan.h`.

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
| `path.cubicTo(c1, c2, point)` | Cubic Bezier (adaptively approximated to quadratics). |
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

### `snail.lowlevel`

Building blocks for callers who need direct curve/band data, want to emit
glyph vertices outside the `Scene`/`DrawList` pipeline, or build a custom
backend on top of snail's rasterization. Most apps should not need this.

Raw platform/rendering imports such as OpenGL bindings, TrueType parser
internals, and vertex-layout internals are not re-exported here; repo demos
and tools keep those needs in local shims or build-only internal modules.

| Symbol | Use |
|--------|-----|
| `lowlevel.bezier`, `lowlevel.curve_tex` | Geometry math and curve-page packing primitives. |
| `lowlevel.CurveAtlas`/`Atlas`, `lowlevel.AtlasPage` | Raw atlas storage exposed for backend authors. |
| `lowlevel.curveAtlasFootprint` | Raw atlas upload-footprint helper for custom backend/resource code. |
| `lowlevel.TextBatch`, `TextAtlas.appendTextBatch`, `lowlevel.PathBatch` | Caller-buffered glyph/shape vertex emission below the `DrawList` layer. |
| `lowlevel.TEXT_WORDS_PER_GLYPH`, `lowlevel.PATH_WORDS_PER_SHAPE`, related sizing constants | `u32` word budget per record (prefer `DrawList.estimate` when possible). |
| `lowlevel.PATH_PAINT_*` constants | Path-paint texel tags used by `PathPicture` records. |
| `lowlevel.PathPictureDebugView`, `lowlevel.PathPictureBoundsOverlayOptions` | Debug overlays for vector authoring. |
| `lowlevel.textureLayerWindowBase`, `lowlevel.textureLayerLocal`, `lowlevel.TEXTURE_LAYER_WINDOW_SIZE` | Texture-array layer windowing helpers. |

## Thread safety

| Type | Rule |
|------|------|
| `TextAtlas` | Immutable snapshot. Safe for concurrent reads. `ensureText`, `ensureShaped`, and `ensureGlyphs` return a new snapshot; old remains valid for in-flight readers. |
| `TextBlob`, `PathPicture`, `Image` | Safe for concurrent reads while the borrowed atlas / pictures / pixels outlive the reader. `TextBlob.rebound` returns a new blob instead of mutating the existing one. |
| `ResourceSet`, `Scene` | Borrowed manifests/lists. Source values must outlive upload/record building; CPU prepared resources extend some source lifetimes as described below. |
| `PreparedResources` | Backend/context-specific. GPU prepared resources own backend texture uploads. CPU prepared resources own prepared curve sidecars but still borrow atlas band/layer-info data, painted `TextBlob` layer-info data, and image pixels. |
| `DrawList` | Caller-owned buffer. Thread-local — no sharing needed. |
| `Renderer` | Single-threaded. Must be called from the GL/Vulkan context thread. |
| `CpuRenderer` | Single-threaded by default. Pass a `*snail.ThreadPool` via `cpu.setThreadPool` to enable internal scanline-tiled parallelism; the renderer fans tile work out and joins before each draw returns, so calls remain serial from the caller's perspective. |

Typical pattern: build `TextAtlas` and call `ensureText` / `ensureShaped` on a loading thread, publish a new `ResourceSet` to the render thread, upload into `PreparedResources`, build `DrawList` records or a `PreparedScene`, then draw. The draw call does not allocate, upload, discover resources, or invalidate caches.

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
  GL/Vulkan text coverage hooks for custom shaders.

## Benchmarks

```sh
zig build bench
zig build bench -Dvulkan=false  # skip Vulkan rows
```

Last run: 2026-05-16, `zig build bench`, ReleaseFast benchmark build. Lower
times are better. These numbers are one local machine/run, not a portability
guarantee.

NotoSans-Regular, 20 prep runs, 1000 text iterations, 1000 draw-record iterations.

The vector workload contains filled and stroked rounded rectangles, ellipses, and custom cubic/quadratic paths. Vulkan rows are emitted unless the build is configured with `-Dvulkan=false`.

### Hardware

| Component | Detected |
|---|---|
| CPU | AMD Ryzen 9 5950X 16-Core Processor |
| OpenGL renderer | NVIDIA GeForce RTX 3090/PCIe/SSE2 |
| OpenGL version | 4.4.0 NVIDIA 595.71.05 |
| Vulkan device | NVIDIA GeForce RTX 3090 |

### Preparation

| Workload | Snail | FreeType | FreeType / Snail |
|---|---:|---:|---:|
| Font load | 1.79 us | 8.68 us | 4.85x |
| Glyph prep, ASCII | 423.87 us | 1054.34 us | 2.49x |
| Glyph prep, 7 sizes | 423.87 us | 6965.33 us | 16.43x |
| PathPicture freeze, 25 shapes | 133.57 us | n/a | n/a |

### Prepared Resource Memory

| Resource | Bytes | KiB |
|---|---:|---:|
| Snail text curve/band textures | 98304 | 96.0 |
| Snail vector curve/band textures | 54352 | 53.1 |
| FreeType bitmaps, one size | 65001 | 63.5 |
| FreeType bitmaps, seven sizes | 538020 | 525.4 |

### Text Creation And Layout

| Workload | Snail TextBlob | FreeType layout | FreeType / Snail |
|---|---:|---:|---:|
| Short string | 1.71 us | 77.39 us | 45.33x |
| Sentence | 5.77 us | 377.71 us | 65.49x |
| Paragraph | 19.77 us | 1386.03 us | 70.09x |
| Paragraph x 7 sizes | 140.73 us | 10047.97 us | 71.40x |

### Draw Record Creation

| Scene | Commands | Words | Segments | PreparedScene.initOwned |
|---|---:|---:|---:|---:|
| Text | 4 | 4048 | 1 | 8.06 us |
| Rich text | 1 | 1136 | 1 | 2.14 us |
| Vector paths | 1 | 400 | 1 | 0.23 us |
| Mixed text + vector | 5 | 4448 | 2 | 7.94 us |
| Multi-script text | 4 | 1488 | 1 | 2.82 us |

### Prepared Render

Target: 640x360. CPU uses 20 measured frames; GPU backends use 500 measured frames.

| Backend | Scene | Frames | Commands | Words | Segments | Draw prepared scene |
|---|---|---:|---:|---:|---:|---:|
| CPU | Text | 20 | 4 | 4048 | 1 | 8043.31 us |
| CPU | Rich text | 20 | 1 | 1136 | 1 | 4203.87 us |
| CPU | Vector paths | 20 | 1 | 400 | 1 | 16398.11 us |
| CPU | Mixed text + vector | 20 | 5 | 4448 | 2 | 24645.27 us |
| CPU | Multi-script text | 20 | 4 | 1488 | 1 | 4886.27 us |
| CPU (threaded) | Text | 20 | 4 | 4048 | 1 | 3314.75 us |
| CPU (threaded) | Rich text | 20 | 1 | 1136 | 1 | 2146.50 us |
| CPU (threaded) | Vector paths | 20 | 1 | 400 | 1 | 3382.64 us |
| CPU (threaded) | Mixed text + vector | 20 | 5 | 4448 | 2 | 5594.72 us |
| CPU (threaded) | Multi-script text | 20 | 4 | 1488 | 1 | 2108.47 us |
| GL 4.4 (persistent mapped) | Text | 500 | 4 | 4048 | 1 | 101.68 us |
| GL 4.4 (persistent mapped) | Rich text | 500 | 1 | 1136 | 1 | 85.84 us |
| GL 4.4 (persistent mapped) | Vector paths | 500 | 1 | 400 | 1 | 100.10 us |
| GL 4.4 (persistent mapped) | Mixed text + vector | 500 | 5 | 4448 | 2 | 167.02 us |
| GL 4.4 (persistent mapped) | Multi-script text | 500 | 4 | 1488 | 1 | 84.30 us |
| Vulkan | Text | 500 | 4 | 4048 | 1 | 82.50 us |
| Vulkan | Rich text | 500 | 1 | 1136 | 1 | 97.17 us |
| Vulkan | Vector paths | 500 | 1 | 400 | 1 | 81.73 us |
| Vulkan | Mixed text + vector | 500 | 5 | 4448 | 2 | 137.60 us |
| Vulkan | Multi-script text | 500 | 4 | 1488 | 1 | 89.78 us |

### Render Modes

Per-AA timings for the text and multi-script scenes. AA controls
the fragment-shader path (grayscale vs LCD subpixel).

| Backend | Scene | AA | Words | Segments | PreparedScene | Draw |
|---|---|---|---:|---:|---:|---:|
| CPU | Text | grayscale | 4048 | 1 | 7.92 us | 1671.07 us |
| CPU | Text | subpixel rgb | 4048 | 1 | 7.63 us | 8138.35 us |
| CPU | Rich text | grayscale | 1136 | 1 | 2.11 us | 1392.81 us |
| CPU | Rich text | subpixel rgb | 1136 | 1 | 2.11 us | 4230.81 us |
| CPU | Multi-script text | grayscale | 1488 | 1 | 2.73 us | 1002.55 us |
| CPU | Multi-script text | subpixel rgb | 1488 | 1 | 2.76 us | 4863.81 us |
| GL 4.4 (persistent mapped) | Text | grayscale | 4048 | 1 | 7.64 us | 34.34 us |
| GL 4.4 (persistent mapped) | Text | subpixel rgb | 4048 | 1 | 7.52 us | 80.20 us |
| GL 4.4 (persistent mapped) | Rich text | grayscale | 1136 | 1 | 2.09 us | 29.40 us |
| GL 4.4 (persistent mapped) | Rich text | subpixel rgb | 1136 | 1 | 2.09 us | 91.82 us |
| GL 4.4 (persistent mapped) | Multi-script text | grayscale | 1488 | 1 | 2.72 us | 28.35 us |
| GL 4.4 (persistent mapped) | Multi-script text | subpixel rgb | 1488 | 1 | 2.73 us | 91.96 us |
| Vulkan | Text | grayscale | 4048 | 1 | 7.72 us | 28.40 us |
| Vulkan | Text | subpixel rgb | 4048 | 1 | 7.49 us | 85.93 us |
| Vulkan | Rich text | grayscale | 1136 | 1 | 2.15 us | 33.59 us |
| Vulkan | Rich text | subpixel rgb | 1136 | 1 | 2.18 us | 89.25 us |
| Vulkan | Multi-script text | grayscale | 1488 | 1 | 3.01 us | 33.11 us |
| Vulkan | Multi-script text | subpixel rgb | 1488 | 1 | 2.78 us | 79.38 us |

## Architecture

```
src/
  snail/
    root.zig             public API facade and domain-module exports
    text.zig             text-domain public aliases
    paint.zig            paint, gradient, image-paint public types
    fonts.zig            TextAtlas internals: multi-font manager with immutable snapshot atlas
    c_api.zig            C ABI over the explicit resource model
    glyph_emit.zig       glyph -> vertex dispatch (plain, COLR, painted, multi-layer)
    paint_records.zig    shared paint-record encoding for text and vector draws
    resource_key.zig     stable resource-key helpers
    font/                TrueType/OpenType/HarfBuzz text primitives
    math/                Bezier, vector, matrix, and root-solving primitives
    renderer/
      gl.zig             OpenGL renderer and prepared resource state
      vulkan.zig         Vulkan renderer and prepared resource state (optional)
      cpu.zig            software rasterizer (same atlas data, no GPU)
      gl_bindings.zig    OpenGL C imports
      gl_backend.zig     GL version detection and backend selection
      shaders.zig        GLSL 330 vertex + fragment shaders (GL backend)
      vulkan_shaders.zig SPIR-V bytecode loader (Vulkan backend)
      curve_texture.zig  RGBA16F curve control point packing
      band_texture.zig   RG16UI spatial band subdivision
      vertex.zig         glyph quad vertex generation
      upload_common.zig  shared texture upload logic
      subpixel_order.zig RGB/BGR/VRGB/VBGR enum
      subpixel_policy.zig subpixel rendering policy logic
      glsl/              shared GLSL bodies for GL and Vulkan backends
      vulkan_glsl/       Vulkan shader wrappers (compiled to SPIR-V at build time)
  demo/
    main.zig             interactive renderer demo
    game.zig             game-style OpenGL demo entry point
    screenshot.zig       headless screenshot demo
    internal_gl.zig      demo-local OpenGL C imports; not part of Snail API
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
    backend_compare.zig  CPU/GL/Vulkan pixel comparison check
    profile_cpu_text.zig CPU text-rendering profile target
    internal_gl.zig      tool-local OpenGL C imports
    screenshot.zig       tool-local framebuffer capture/TGA writer
include/
  snail.h                shared C API: resources, upload, draw records, coverage records
  snail_generated.h      generated by build/install; not checked in
  snail_cpu.h            CPU backend C constructor and thread-pool hook
  snail_gl.h             OpenGL backend C constructor and coverage bindings
  snail_vulkan.h         Vulkan backend C constructor, upload, and coverage hooks
```

## License

MIT

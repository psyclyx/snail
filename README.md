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

**Vector paths.** Filled and stroked `Path` geometry shares the curve/band texture format with text; only the fragment shader differs (the path shader handles per-glyph paint records and composite groups, while the text shader fast-paths plain coverage). Cubic Bezier inputs are adaptively approximated to quadratics. Strokes are expanded into offset curves with joins (miter, bevel, round) and caps (butt, square, round). The `PathPicture` type freezes a set of styled paths into an immutable atlas snapshot that can be instanced cheaply per frame.

## Color convention

All color parameters are **sRGB, straight (unpremultiplied) alpha**, as `[4]f32` in the range 0.0–1.0. This applies to `FillStyle.color`, `StrokeStyle.color`, gradient stops, `ImagePaint.tint`, and text color arguments. The renderer premultiplies alpha and linearizes for blending internally.

**Images** (`Image.initSrgba8`) expect sRGB-encoded RGBA8 pixel data (4 bytes per pixel, 0–255). This is what most image decoders produce. Linear-space pixel buffers will appear too bright.

**Gradients** interpolate in sRGB space, which gives perceptually smooth results for UI use. `LinearGradient` and `RadialGradient` provide extend modes for clamp, repeat, and reflect behavior.

**Blending** uses premultiplied alpha with gamma-correct (linear-space) compositing. On GPU the fragment shader explicitly `srgbDecode`s vertex / texture colors and writes premultiplied linear values; `GL_FRAMEBUFFER_SRGB` and the Vulkan sRGB swapchain image handle the final linear→sRGB store on framebuffer write. The CPU renderer uses an exact 256-entry sRGB→linear LUT for u8 texels and the IEC 61966-2-1 formula directly for the linear→sRGB output, with round-to-nearest output rounding.

## Build

Requires [Zig 0.16](https://ziglang.org/download/), OpenGL 3.3+, and pkg-config. HarfBuzz is enabled by default but can be disabled (see flags below). The interactive demo requires Wayland + EGL. Vulkan support is optional.

```sh
zig build test                                  # unit tests
zig build run                                   # interactive 2D demo (GL 4.4, Wayland)
zig build run -Drenderer=gl33                   # force OpenGL 3.3
zig build run -Drenderer=vulkan -Dvulkan=true   # Vulkan backend
zig build run -Drenderer=cpu                    # CPU renderer
zig build run-game-demo                         # 3D scene with HUD + world-space text on walls
zig build screenshot                            # 2D demo offscreen → zig-out/demo-screenshot.tga
zig build backend-compare                       # CPU/GL pixel parity; add -Dvulkan=true for Vulkan
zig build bench                                 # benchmarks; add -Dvulkan=true for Vulkan rows
zig build install --release=fast                # install libsnail + include/snail.h
```

Library backend flags:

- `-Dopengl=true` (default) — OpenGL backend (`GlRenderer` and the C API today require this).
- `-Dvulkan=false` (default) — pass `=true` to enable the Vulkan backend; SPIR-V shaders are compiled at build time via `glslc`.
- `-Dcpu-renderer=true` (default) — pass `=false` to drop `CpuRenderer`.
- `-Dharfbuzz=true` (default) — pass `=false` for a HarfBuzz-free build using the built-in GSUB type 4 / GPOS type 2 shaper.
- `-Dprofile=false` (default) — pass `=true` to enable the comptime CPU timers.
- `-Dc-api=true` (default) — pass `=false` for a Zig-module-only build (skips `libsnail.{a,so}` and the header install).

The checked-in screenshot at `assets/demo_screenshot.png` is regenerated from the `zig build screenshot` TGA output.

### Nix

```sh
nix-shell           # dev shell with all dependencies
nix-build -A lib    # build libsnail + header
nix-build -A demo   # build snail-demo
```

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

The dependency module links OpenGL and HarfBuzz by default. On NixOS/nix-shell, these are provided automatically; on other systems, install the development packages for your distro.

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
_ = try blob_builder.addText(.{}, "Hello, world!", 10, 400, 48, .{ 1, 1, 1, 1 });

var blob = try blob_builder.finish();
defer blob.deinit();

var scene = snail.Scene.init(allocator);
defer scene.deinit();
try scene.addText(.{ .blob = &blob });
// (See "Vector Paths" below for adding a PathPicture to the same scene.)

var resource_entries: [8]snail.ResourceSet.Entry = undefined;
var resources = snail.ResourceSet.init(&resource_entries);
try resources.addScene(&scene);

// Requires an active GL context. Vulkan uses snail.VulkanRenderer.init(ctx).
var gl = try snail.GlRenderer.init(allocator);
defer gl.deinit();
var prepared = try gl.uploadResourcesBlocking(allocator, &resources);
defer prepared.deinit();

const viewport_wf: f32 = @floatFromInt(viewport_w);
const viewport_hf: f32 = @floatFromInt(viewport_h);
const options = snail.DrawOptions{
    .mvp = snail.Mat4.ortho(0, viewport_wf, viewport_hf, 0, -1, 1),
    .target = .{ .pixel_width = viewport_wf, .pixel_height = viewport_hf, .subpixel_order = .rgb },
};

var prepared_scene = try snail.PreparedScene.initOwned(allocator, &prepared, &scene, options);
defer prepared_scene.deinit();
try gl.drawPrepared(&prepared, &prepared_scene, options);
```

### On-demand Atlas Extension

`ensureText` and `ensureShaped` return a new immutable snapshot; the old one remains valid for in-flight readers. `TextBlob` borrows the exact atlas snapshot used to build it, so rebuild blobs after publishing a new atlas snapshot.

```zig
if (try atlas.ensureText(.{}, text)) |next| {
    atlas.deinit();  // safe only after readers of the old snapshot are done
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
    .{ .color = .{ 0.1, 0.1, 0.2, 0.9 } },                 // fill
    .{ .color = .{ 0.4, 0.6, 1, 1 }, .width = 2, .join = .round }, // stroke
    .identity,
);

var picture = try builder.freeze(allocator);
defer picture.deinit();

// Submit before uploading (see the Zig example above).
try scene.addPath(.{ .picture = &picture });
```

## Example: C

> **Note:** The C renderer entry point currently targets OpenGL and requires an active OpenGL context. Error checks are omitted here for brevity.

```c
#include "snail.h"

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
SnailTextBlobOptions text_options = {
    .x = 10,
    .y = 400,
    .size = 48,
    .color = {1, 1, 1, 1},
};
snail_text_blob_init_from_shaped(NULL, atlas, shaped, text_options, &blob);
snail_shaped_text_deinit(shaped);

// Vector path
SnailPath *path = NULL;
snail_path_init(NULL, &path);
snail_path_add_rounded_rect(path, (SnailRect){0, 0, 200, 80}, 12);

SnailPathPictureBuilder *builder = NULL;
snail_path_picture_builder_init(NULL, &builder);
SnailFillStyle fill = {.color = {0.1, 0.1, 0.2, 0.9}, .paint_kind = -1};
snail_path_picture_builder_add_filled_path(builder, path, fill,
                                           SNAIL_TRANSFORM2D_IDENTITY);

SnailPathPicture *picture = NULL;
snail_path_picture_builder_freeze(builder, NULL, &picture);

SnailScene *scene = NULL;
snail_scene_init(NULL, &scene);
snail_scene_add_text(scene, blob);
snail_scene_add_path_picture(scene, picture);

SnailResourceSet *resources = NULL;
snail_resource_set_init(NULL, 8, &resources);
snail_resource_set_add_scene(resources, scene);

SnailRenderer *renderer = NULL;
snail_renderer_init(&renderer);

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

## API reference

### Types

| Type | Description |
|------|-------------|
| `TextAtlas` | Immutable CPU font/glyph snapshot. `ensureText` and `ensureShaped` return a new snapshot; old stays valid. |
| `ShapedText` | Shaped glyph placements for a string/run. |
| `TextBlob` | Positioned text that borrows the exact `TextAtlas` snapshot used to build it. |
| `FaceSpec` | `{ .data, .weight, .italic, .fallback, .synthetic }` — font face specification for `TextAtlas.init`. |
| `FontStyle` | `{ .weight: FontWeight, .italic: bool }` — selects a face for rendering. |
| `FontWeight` | `.regular`, `.bold`, `.semi_bold`, etc. |
| `SyntheticStyle` | `{ .skew_x, .embolden }` — synthetic italic shear and bold offset. |
| `Image` | Immutable sRGB RGBA8 raster image. Created with `initSrgba8`. |
| `Path` | Mutable path builder: `moveTo`, `lineTo`, `quadTo`, `cubicTo`, `close`, plus shape helpers. |
| `PathPictureBuilder` | Accumulates filled/stroked paths and shapes with paint styles. |
| `PathPicture` | Immutable frozen vector art. |
| `Scene` | Borrowed command list of `TextDraw` and `PathDraw` submissions. |
| `PathDraw`, `TextDraw` | Submission record: resource pointer, optional sub-range, and an `[]const Override` array (length = GPU instance count). |
| `Override` | Per-instance composition: `transform` composed onto baked transform, `tint` multiplied onto baked color. |
| `Range` | `{ start, count }` slice into a `PathPicture`'s shapes or a `TextBlob`'s glyphs. |
| `ResourceSet` | Fixed-capacity borrowed manifest of CPU values. |
| `PreparedResources` | Backend realization for one renderer/context. |
| `DrawList` | Caller-buffered draw records. |
| `PreparedScene` | Optional owned draw-record cache for static scenes. |
| `ResolveTarget` | Final target metadata: pixel size, subpixel order, fill rule, and composite safety flags. |
| `GlRenderer`, `VulkanRenderer`, `CpuRenderer` | First-class backend renderers. |
| `Renderer` | Type-erased convenience wrapper around a backend renderer. |
| `Rect` | `{ x, y, w, h }` rectangle. |
| `Transform2D` | 2x3 affine matrix `{ xx, xy, tx, yx, yy, ty }`. |
| `FillStyle` | sRGB fill color (straight alpha) with optional `Paint`. |
| `StrokeStyle` | sRGB stroke color (straight alpha), width, optional paint, cap, join, miter limit, placement. |
| `Paint` | Tagged union: `.solid`, `.linear_gradient`, `.radial_gradient`, `.image`. |

### Text

| Method | Description |
|--------|-------------|
| `TextAtlas.init(alloc, faces) !TextAtlas` | Parse font faces. Atlas starts empty. |
| `atlas.deinit()` | Release this snapshot. Pages shared with other snapshots stay alive. |
| `atlas.shapeText(alloc, style, text) !ShapedText` | Shape text without growing the atlas. Caller frees `ShapedText`. |
| `atlas.ensureShaped(shaped) !?TextAtlas` | Return a new snapshot with the shaped glyphs present. Null if already present. |
| `atlas.ensureText(style, text) !?TextAtlas` | Shape-and-ensure helper. |
| `TextBlob.fromShaped(alloc, atlas, shaped, options) !TextBlob` | Build positioned text from a `ShapedText`. The blob borrows `atlas`. |
| `TextBlobBuilder.init(alloc, atlas)` / `builder.addText(style, text, x, y, size, color) !AddTextResult` / `builder.finish() !TextBlob` | Convenience: shape + position in one pass. Call `atlas.ensureText`/`ensureShaped` first if all glyphs must be renderable. |
| `AddTextResult` | `{ .advance: f32, .missing: bool }` — pen advance and whether any glyph fell back to `.notdef`. |

### Scene

A scene is a borrowed list of `PathDraw` / `TextDraw` submissions. Each submission selects a sub-range of an immutable resource and emits one GPU instance per `Override` (default: a single identity instance). The scene borrows the `picture` / `blob` pointer *and* the `instances` slice on each submission — all three must stay live until `scene.reset()` or `scene.deinit()`. `addPath` / `addText` perform no allocation beyond growing the command list.

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

### Renderer

`GlRenderer`, `VulkanRenderer`, and `CpuRenderer` are first-class types; `Renderer` is a type-erased wrapper that exposes the same surface for backend-agnostic code. The methods below are present on each concrete renderer and on `Renderer`.

| Method | Description |
|--------|-------------|
| `GlRenderer.init(alloc) !GlRenderer` | Initialize the OpenGL backend. Requires the GL context to be current. |
| `VulkanRenderer.init(ctx) !VulkanRenderer` | Initialize the Vulkan backend from a caller-owned `VulkanContext`. |
| `CpuRenderer.init(pixels, w, h, stride) CpuRenderer` | Initialize the CPU backend over a caller-owned RGBA8 buffer. |
| `cpu.setThreadPool(?*snail.ThreadPool)` | Opt into scanline-tiled multithreaded rendering using a caller-owned `snail.ThreadPool`. Byte-identical output to the single-threaded path; the draw call itself stays allocation-free. |
| `vk.beginFrame(.{ .cmd, .frame_index })` | Bind a caller-recorded Vulkan command buffer + frame index for the current frame. |
| `renderer.uploadResourcesBlocking(alloc, set) !PreparedResources` | Blocking upload + view construction. The simple path. |
| `renderer.planResourceUpload(current, next_set, changed_keys) !ResourceUploadPlan` | Diff a new resource set against existing prepared resources. |
| `renderer.beginResourceUpload(alloc, plan) !PendingResourceUpload` | Start a scheduled upload; record into a caller command buffer for Vulkan, then call `pending.publish()`. |
| `DrawList.init(words, segments)` | Wrap a caller-buffered word + segment buffer for `addScene`. |
| `PreparedScene.initOwned(alloc, prepared, scene, options) !PreparedScene` | Build an owned draw-record cache for a static scene. |
| `renderer.draw(prepared, records, options)` | Execute prebuilt draw records. No resource discovery or upload. |
| `renderer.drawPrepared(prepared, prepared_scene, options)` | Draw a `PreparedScene` cache. |
| `prepared.retireNowOrWhenSafe(renderer)` | Retire backend resources once no in-flight frame still references them. |
| `prepared.retireAfter(alloc, fence_or_frame)` | Retire after a caller-supplied backend fence / frame index has completed. |

### Scheduled resource upload

`uploadResourcesBlocking` is the simple path; for engines that want to overlap
upload with the main render queue (Vulkan in particular) there is an explicit
plan / record / publish flow:

1. **Plan.** `renderer.planResourceUpload(current, next_set, changed_keys_buf)`
   diffs `next_set` against the existing `PreparedResources` (or `null` for a
   first upload) and records which `ResourceKey` entries changed. The result
   is a `ResourceUploadPlan` whose `upload_bytes` and `changedKeys()` are
   informational. `changed_keys_buf` is caller-owned scratch — size it to the
   number of distinct resources you might submit.
2. **Begin + record.** `renderer.beginResourceUpload(allocator, plan)` returns
   a `PendingResourceUpload`. Call `pending.record(ctx, .{ .budget_bytes = N })`
   to do the work. For Vulkan, `ctx` carries the caller-recorded
   `VkCommandBuffer` (e.g. `.{ .cmd = my_cmd }`); for GL and CPU, `record`
   completes synchronously and `ctx` is ignored.
3. **Wait + publish.** Call `pending.ready(fence_or_frame)` to poll for
   external completion (Vulkan only — GL/CPU report ready immediately). Once
   true, `pending.publish()` returns the new `PreparedResources`. Call
   `pending.deinit()` if you need to abandon the upload before publishing.

The new `PreparedResources` replaces the old one; retire the old one via
`old.retireNowOrWhenSafe(renderer)` or `old.retireAfter(allocator, fence)` once
no in-flight frame still references it.

### Text coverage in custom shaders

`TextCoverageShader`, `TextCoverageRecords`, and `TextCoverageBackend` let a
material shader sample snail's exact glyph coverage without going through
`Renderer.draw`. The typical use is layering text with custom lighting,
masking, or compositing.

- `TextCoverageShader` exposes GLSL 330 sources you can `@embedFile`-style
  splice into your own program: `glsl330_vertex_interface`,
  `glsl330_fragment_interface`, `glsl330_fragment_body` (gives you
  `snail_text_coverage()`, `snail_text_color_srgb()`,
  `snail_text_color_linear()`), plus `glsl330_resource_interface` and
  `glsl330_coverage_functions` for materials that don't use snail's text
  varyings.
- `TextCoverageRecords` is the per-glyph vertex stream. Build it with
  `records.buildLocal(prepared, blob, .{ .transform = ... })`; it allocates
  internally. Call `records.validFor(prepared)` after a re-upload and
  `rebuildLocal` if the atlas has moved.
- `TextCoverageBackend` is the GL hook. Get one from
  `prepared.textCoverageBackend(renderer)` (or `gl.textCoverageBackend(prepared)`
  on the typed renderer). Call `bind(bindings)` to bind your material's
  curve/band texture units, then `drawCoverage(&records)` (or `drawVertices`
  with your own buffer). Currently GL-only.

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
| `builder.shapeCount() usize` | Number of shapes added so far (matches indices used by `Range`). |
| `builder.freeze(alloc) !PathPicture` | Compile to immutable atlas. |

### `snail.lowlevel`

Building blocks for callers who need direct curve/band data, want to emit
glyph vertices outside the `Scene`/`DrawList` pipeline, or build a custom
backend on top of snail's rasterization. Most apps should not need this.

| Symbol | Use |
|--------|-----|
| `lowlevel.bezier`, `lowlevel.curve_tex` | Geometry math and curve-page packing primitives. |
| `lowlevel.Font`, `lowlevel.CurveAtlas`/`Atlas`, `lowlevel.AtlasPage` | Raw font + atlas storage exposed for backend authors. |
| `lowlevel.TextBatch`, `lowlevel.PathBatch` | Caller-buffered glyph/shape vertex emission below the `DrawList` layer. |
| `lowlevel.TEXT_WORDS_PER_GLYPH`, `lowlevel.PATH_WORDS_PER_SHAPE`, related sizing constants | `u32` word budget per record (prefer `DrawList.estimate` when possible). |
| `lowlevel.PATH_PAINT_*` constants | Path-paint texel tags used by `PathPicture` records. |
| `lowlevel.PathPictureDebugView`, `lowlevel.PathPictureBoundsOverlayOptions` | Debug overlays for vector authoring. |
| `lowlevel.textureLayerWindowBase`, `lowlevel.textureLayerLocal`, `lowlevel.TEXTURE_LAYER_WINDOW_SIZE` | Texture-array layer windowing helpers. |

## Thread safety

| Type | Rule |
|------|------|
| `TextAtlas` | Immutable snapshot. Safe for concurrent reads. `ensureText` returns a new snapshot; old remains valid for in-flight readers. |
| `TextBlob`, `PathPicture`, `Image` | Immutable after init/freeze. Safe for concurrent reads while the borrowed atlas / pictures / pixels outlive the reader. |
| `ResourceSet`, `Scene` | Borrowed manifests/lists. CPU values must outlive them. |
| `PreparedResources` | Backend/context-specific. CPU values must outlive it unless a backend explicitly copies them. |
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

## Status

snail is used in development but is not yet stable. The Zig API is settling and follows the explicit-resource model described above. Known gaps:

- Built-in OpenType shaping covers GSUB type 4 (ligatures) and GPOS type 2 (pair positioning) only; complex scripts (Arabic, Devanagari, Thai, etc.) require building with `-Dharfbuzz=true`.
- TrueType outlines only — no CFF/CFF2.
- No variable fonts.
- The C API exposes the unified `SnailRenderer` (currently OpenGL-backed) and the blocking `snail_renderer_upload_resources_blocking` upload path. Vulkan and the Zig-side scheduled upload (`planResourceUpload` / `beginResourceUpload` / `pending.publish`) are not yet exposed to C callers.

## Benchmarks

```sh
zig build bench
zig build bench -Dvulkan=true  # include Vulkan rows when a Vulkan device is available
```

The bench prints Markdown tables that paste directly into docs. The
output below was captured with `zig build bench -Dvulkan=true` on the
machine listed under Hardware; numbers will vary across hardware,
driver, and load.

NotoSans-Regular, 20 prep runs, 1000 text iterations, 1000 draw-record iterations.

The vector workload contains filled and stroked rounded rectangles, ellipses, and custom cubic/quadratic paths. Vulkan rows are emitted only when built with `-Dvulkan=true`.

### Hardware

| Component | Detected |
|---|---|
| CPU | AMD Ryzen 9 5950X 16-Core Processor |
| OpenGL renderer | NVIDIA GeForce RTX 3090/PCIe/SSE2 |
| OpenGL version | 4.4.0 NVIDIA 595.58.03 |
| Vulkan device | NVIDIA GeForce RTX 3090 |

### Preparation

| Workload | Snail | FreeType | FreeType / Snail |
|---|---:|---:|---:|
| Font load | 1.43 us | 8.69 us | 6.10x |
| Glyph prep, ASCII | 469.88 us | 1040.38 us | 2.21x |
| Glyph prep, 7 sizes | 469.88 us | 7248.15 us | 15.43x |
| PathPicture freeze, 25 shapes | 206.08 us | n/a | n/a |

### Prepared Resource Memory

| Resource | Bytes | KiB |
|---|---:|---:|
| Snail text curve/band textures | 98304 | 96.0 |
| Snail vector curve/band textures | 114688 | 112.0 |
| FreeType bitmaps, one size | 65001 | 63.5 |
| FreeType bitmaps, seven sizes | 538020 | 525.4 |

### Text Creation And Layout

| Workload | Snail TextBlob | FreeType layout | FreeType / Snail |
|---|---:|---:|---:|
| Short string | 1.33 us | 80.10 us | 60.06x |
| Sentence | 4.40 us | 390.94 us | 88.77x |
| Paragraph | 15.16 us | 1356.56 us | 89.48x |
| Paragraph x 7 sizes | 106.03 us | 9925.10 us | 93.60x |

### Draw Record Creation

| Scene | Commands | Words | Segments | PreparedScene.initOwned |
|---|---:|---:|---:|---:|
| Text | 4 | 3795 | 4 | 7.52 us |
| Vector paths | 1 | 375 | 1 | 0.23 us |
| Mixed text + vector | 5 | 4170 | 5 | 7.74 us |
| Multi-script text | 4 | 1395 | 4 | 2.64 us |

### Prepared Render

Target: 640x360. CPU uses 20 measured frames; GPU backends use 500 measured frames. The `CPU (threaded)` rows use a `snail.ThreadPool` for scanline-tiled parallel rendering, fanning out once per frame across the entire prepared scene.

| Backend | Scene | Frames | Commands | Words | Segments | Draw prepared scene |
|---|---|---:|---:|---:|---:|---:|
| CPU | Text | 20 | 4 | 3795 | 4 | 17442.20 us |
| CPU | Vector paths | 20 | 1 | 375 | 1 | 49515.86 us |
| CPU | Mixed text + vector | 20 | 5 | 4170 | 5 | 66732.57 us |
| CPU | Multi-script text | 20 | 4 | 1395 | 4 | 10343.15 us |
| CPU (threaded) | Text | 20 | 4 | 3795 | 4 | 6874.31 us |
| CPU (threaded) | Vector paths | 20 | 1 | 375 | 1 | 9095.72 us |
| CPU (threaded) | Mixed text + vector | 20 | 5 | 4170 | 5 | 13859.52 us |
| CPU (threaded) | Multi-script text | 20 | 4 | 1395 | 4 | 4241.57 us |
| GL 4.4 (persistent mapped) | Text | 500 | 4 | 3795 | 4 | 310.05 us |
| GL 4.4 (persistent mapped) | Vector paths | 500 | 1 | 375 | 1 | 65.82 us |
| GL 4.4 (persistent mapped) | Mixed text + vector | 500 | 5 | 4170 | 5 | 345.57 us |
| GL 4.4 (persistent mapped) | Multi-script text | 500 | 4 | 1395 | 4 | 290.01 us |
| Vulkan | Text | 500 | 4 | 3795 | 4 | 77.36 us |
| Vulkan | Vector paths | 500 | 1 | 375 | 1 | 83.76 us |
| Vulkan | Mixed text + vector | 500 | 5 | 4170 | 5 | 106.20 us |
| Vulkan | Multi-script text | 500 | 4 | 1395 | 4 | 78.99 us |

### Render Modes

Per-AA timings for the text and multi-script scenes. AA controls the
fragment-shader path (grayscale vs LCD subpixel).

| Backend | Scene | AA | Words | Segments | PreparedScene | Draw |
|---|---|---|---:|---:|---:|---:|
| CPU | Text | grayscale | 3795 | 4 | 7.52 us | 3413.73 us |
| CPU | Text | subpixel rgb | 3795 | 4 | 7.81 us | 17721.75 us |
| CPU | Multi-script text | grayscale | 1395 | 4 | 2.60 us | 1990.67 us |
| CPU | Multi-script text | subpixel rgb | 1395 | 4 | 2.66 us | 10506.53 us |
| GL 4.4 (persistent mapped) | Text | grayscale | 3795 | 4 | 7.70 us | 90.37 us |
| GL 4.4 (persistent mapped) | Text | subpixel rgb | 3795 | 4 | 8.10 us | 289.94 us |
| GL 4.4 (persistent mapped) | Multi-script text | grayscale | 1395 | 4 | 2.73 us | 92.67 us |
| GL 4.4 (persistent mapped) | Multi-script text | subpixel rgb | 1395 | 4 | 2.71 us | 288.37 us |
| Vulkan | Text | grayscale | 3795 | 4 | 7.22 us | 23.70 us |
| Vulkan | Text | subpixel rgb | 3795 | 4 | 7.55 us | 81.08 us |
| Vulkan | Multi-script text | grayscale | 1395 | 4 | 2.65 us | 25.47 us |
| Vulkan | Multi-script text | subpixel rgb | 1395 | 4 | 2.67 us | 82.70 us |

## Architecture

```
src/
  snail.zig              public API: TextAtlas, TextBlob, ResourceSet, DrawList, Renderer, Path, ...
  fonts.zig              TextAtlas internals: multi-font manager with immutable snapshot atlas
  c_api.zig              C ABI over the explicit resource model
  glyph_emit.zig         glyph → vertex dispatch (plain, COLR, multi-layer)
  cpu_renderer.zig       software rasterizer (same atlas data, no GPU)
  font/
    ttf.zig              TrueType parser (cmap, glyf, loca, hhea, hmtx, kern, COLR)
    opentype.zig         OpenType shaper (GSUB ligatures, GPOS kerning)
    harfbuzz.zig         HarfBuzz integration (optional)
  math/
    bezier.zig           quadratic/cubic Bezier curves, bounding boxes
    vec.zig              Vec2, Mat4, Transform2D
    roots.zig            quadratic equation solver
  render/
    pipeline.zig         OpenGL renderer and prepared resource state
    gl.zig               OpenGL C function imports
    gl_backend.zig       GL version detection and backend selection
    shaders.zig          GLSL 330 vertex + fragment shaders (GL backend)
    vulkan_pipeline.zig  Vulkan renderer and prepared resource state (optional)
    vulkan_shaders.zig   SPIR-V bytecode loader (Vulkan backend)
    vulkan_platform.zig  Vulkan WSI platform integration
    curve_texture.zig    RGBA16F curve control point packing
    band_texture.zig     RG16UI spatial band subdivision
    vertex.zig           glyph quad vertex generation
    upload_common.zig    shared texture upload logic
    platform.zig         platform abstraction (GL/Vulkan/CPU)
    cpu_platform.zig     CPU backend platform layer
    egl_common.zig       shared EGL setup
    egl_offscreen.zig    headless EGL context
    wayland_window.zig   Wayland window + input handling
    xdg-shell-client-protocol.{c,h}  generated xdg-shell protocol bindings
    screenshot.zig       framebuffer capture + TGA writing
    subpixel_order.zig   RGB/BGR/VRGB/VBGR enum
    subpixel_detect.zig  auto-detect display subpixel layout
    subpixel_policy.zig  subpixel rendering policy logic
    glsl/                shared GLSL bodies for GL and Vulkan backends
  profile/
    timer.zig            comptime-gated CPU timers
shaders/
  snail.vert             Vulkan vertex shader (GLSL 450, compiled to SPIR-V at build time)
  snail.frag             Vulkan fragment shader (vector paths, grayscale AA)
  snail_text.frag        Vulkan fragment shader (text, grayscale AA)
  snail_text_subpixel.frag  Vulkan fragment shader (text, dual-source LCD subpixel AA)
  snail_colr.frag        Vulkan fragment shader (COLR multi-layer color emoji)
include/
  snail.h                public C header
```

## License

MIT

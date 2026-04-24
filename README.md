# snail

GPU font rendering via direct Bézier curve evaluation. A Zig implementation of the [Slug algorithm](https://sluglibrary.com/).

![snail demo scene rendered offscreen](assets/demo_screenshot.png)

Text is rendered by evaluating quadratic Bézier curves per-pixel in a fragment shader. No pre-rasterized glyph bitmaps, no signed distance fields. Glyphs are resolution-independent and render correctly at any size, rotation, or perspective transform. Curve geometry is packed into GPU textures at load time; coverage is computed analytically at runtime.

## Based on

This is an independent implementation of the algorithm described in:

- Eric Lengyel, ["GPU-Centered Font Rendering Directly from Glyph Outlines"](https://jcgt.org/published/0006/02/02/), JCGT 2017
- Eric Lengyel, ["A Decade of Slug"](https://terathon.com/blog/decade-slug.html), 2026
- [Reference HLSL shaders](https://github.com/EricLengyel/Slug) (MIT / Apache-2.0)
- [Sluggish](https://github.com/mightycow/Sluggish) reference C implementation (Unlicense)

The Slug patent (US 10,373,352) was [dedicated to the public domain](https://terathon.com/blog/decade-slug.html) on March 17, 2026 via terminal disclaimer filed with the USPTO. This implementation is original code, not derived from the Slug Library product. Licensed under MIT.

## Build

```sh
zig build test                      # unit tests
zig build bench                     # CPU microbenchmarks (font prep, atlas build, math, vector packing)
zig build bench-compare             # CPU prep/layout comparison vs FreeType (no GPU draw)
zig build bench-headless            # offscreen OpenGL end-to-end frame timing
zig build bench-headless -Dvulkan=true # offscreen OpenGL + Vulkan end-to-end frame timing
zig build bench-suite               # combined layout + rendering suite (text + vectors)
zig build bench-suite -Dvulkan=true # combined suite with additional Vulkan text/vector passes
zig build demo                      # build the interactive demo (Wayland + EGL)
zig build run                       # run the interactive demo (Wayland + EGL)
zig build run -Dvulkan=true         # Vulkan demo backend (Wayland surface)
zig build screenshot                # render the demo scene offscreen to zig-out/demo-screenshot.tga
zig build run -Dharfbuzz=false      # disable HarfBuzz and use the built-in shaper only
zig build install --release=fast    # install libsnail + header to zig-out/
```

Core library builds require [Zig 0.16](https://ziglang.org/download/), OpenGL, HarfBuzz, and pkg-config. The interactive demo is Linux/Wayland-only and adds Wayland + EGL for the OpenGL path. Headless OpenGL benchmarks use EGL offscreen contexts and do not require a window system. Vulkan loader + headers and shaderc are only needed with `-Dvulkan=true`.

**Nix** — reproducible dev shell and build:

```sh
nix-shell               # dev shell with all deps
nix-build -A lib        # build libsnail + header
nix-build -A demo       # build snail-demo
```

**Arch Linux** — install as a system package:

```sh
cd pkg/arch && makepkg -si
```

Demo controls: arrow keys pan, `Z`/`X` zoom, `R` rotate, `S` stress test, `L` cycle subpixel order (none → RGB → BGR → VRGB → VBGR), `M` toggle subpixel mode (`safe` ↔ `legacy-unsafe`).

## Usage

```zig
const snail = @import("snail");

// Parse font (one-time)
var font = try snail.Font.init(ttf_bytes);
defer font.deinit();

const line_metrics = try font.lineMetrics();
const cell_gid = try font.glyphIndex('M');
const cell_advance = try font.advanceWidth(cell_gid);
const cell_bbox = try font.bbox(cell_gid);
_ = .{ line_metrics, cell_advance, cell_bbox };

// Build an immutable atlas snapshot for the glyphs you want
var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
defer atlas.deinit();

// Create renderer and upload atlas pages (requires GL 3.3+ context)
var renderer = try snail.Renderer.init();
defer renderer.deinit();
var atlas_handle = renderer.uploadAtlas(&atlas);

// Build a vertex batch (per-frame for dynamic text, or once for static)
var buf: [5000 * snail.TEXT_FLOATS_PER_GLYPH]f32 = undefined;
var batch = snail.TextBatch.init(&buf);
_ = batch.addText(atlas_handle, &font, "Hello, world!", x, y, 48.0, .{ 1, 1, 1, 1 });

// Draw (call beginFrame() once per frame when sharing a GL context with other renderers)
renderer.beginFrame();
renderer.drawText(batch.slice(), mvp, viewport_w, viewport_h);
```

`font.lineMetrics()` returns `hhea` ascent / descent / line gap in font units. Convert to pixels with the same `font_size / font.unitsPerEm()` scale you use for advances and glyph bounds.

Atlas uploads now return lightweight `AtlasHandle` values. Existing glyph handles remain stable across `extendGlyphIds()`, `extendCodepoints()`, and `extendGlyphsForText()` because those operations return a new atlas snapshot that shares old pages. `compact()` returns a new snapshot too, but may repack handles.

### Path pictures

snail's production vector path is `PathPicture`: freeze vector art once into the same curve/band atlas format used by text, upload that atlas once, then instance it through `PathBatch` each frame. That means vector draws reuse the text pipeline and avoid a separate vector shader compile/pipeline at startup.

`PathPictureBuilder` can add rectangles / rounded rectangles / ellipses directly, or ingest arbitrary `Path` outlines. `PathBatch` writes caller-owned draw vertices, so the per-frame cost is just instancing frozen assets into a reusable float buffer.

```zig
var picture_builder = snail.PathPictureBuilder.init(allocator);
defer picture_builder.deinit();

try picture_builder.addRoundedRect(
    .{ .x = 24, .y = 24, .w = 240, .h = 96 },
    .{ .color = .{ 0.12, 0.16, 0.22, 0.92 } },
    .{ .color = .{ 0.35, 0.55, 0.95, 1.0 }, .width = 2.0, .placement = .inside },
    18.0,
    .identity,
);
try picture_builder.addEllipse(
    .{ .x = 300, .y = 32, .w = 72, .h = 72 },
    .{ .color = .{ 0.95, 0.72, 0.28, 0.2 } },
    .{ .color = .{ 0.95, 0.72, 0.28, 0.9 }, .width = 1.5 },
    .identity,
);

var picture = try picture_builder.freeze(allocator);
defer picture.deinit();

const picture_view = renderer.uploadPathPicture(&picture);

var path_buf: [256 * snail.PATH_FLOATS_PER_SHAPE]f32 = undefined;
var paths = snail.PathBatch.init(&path_buf);
_ = paths.addPicture(&picture_view, &picture);

renderer.beginFrame();
renderer.drawPaths(paths.slice(), mvp, viewport_w, viewport_h);
renderer.drawText(text_batch.slice(), mvp, viewport_w, viewport_h);
```

For non-trivial artwork, build a `Path` with `moveTo`, `lineTo`, `quadTo`, and `cubicTo`, then pass it to `PathPictureBuilder.addPath()`. The fill/stroke model is the same either way: fills can be solid colors, linear gradients, radial gradients, or image paints via `FillStyle.paint`, and `StrokeStyle` adds width, cap, join, miter limit, and inside/center placement.

Open-path strokes generate proper caps instead of rectangular hacks, and the frozen picture can be instantiated again later with either `PathBatch.addPicture()` or `PathBatch.addPictureTransformed()`.

```zig
var logo = snail.Path.init(allocator);
defer logo.deinit();

try logo.moveTo(.{ .x = 0, .y = 0 });
try logo.lineTo(.{ .x = 44, .y = 0 });
try logo.cubicTo(.{ .x = 56, .y = 0 }, .{ .x = 56, .y = 28 }, .{ .x = 44, .y = 28 });
try logo.lineTo(.{ .x = 0, .y = 28 });
try logo.close();

var picture_builder = snail.PathPictureBuilder.init(allocator);
defer picture_builder.deinit();
try picture_builder.addPath(
    &logo,
    .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 44, .y = 28 },
            .start_color = .{ 0.98, 0.68, 0.29, 1.0 },
            .end_color = .{ 0.86, 0.21, 0.14, 1.0 },
        } },
    },
    .{
        .paint = .{ .radial_gradient = .{
            .center = .{ .x = 22, .y = 14 },
            .radius = 22,
            .inner_color = .{ 0.05, 0.07, 0.1, 1.0 },
            .outer_color = .{ 0.12, 0.16, 0.22, 1.0 },
        } },
        .width = 3.0,
        .join = .round,
        .cap = .round,
    },
    snail.Transform2D.translate(40, 32),
);

var picture = try picture_builder.freeze(allocator);
defer picture.deinit();

const picture_view = renderer.uploadPathPicture(&picture);

var path_buf: [64 * snail.PATH_FLOATS_PER_SHAPE]f32 = undefined;
var path_batch = snail.PathBatch.init(&path_buf);
_ = path_batch.addPicture(&picture_view, &picture);

renderer.beginFrame();
renderer.drawPaths(path_batch.slice(), mvp, viewport_w, viewport_h);
```

Convenience wrappers are available when you only want one side of the style:

```zig
try picture_builder.addFilledRoundedRect(rect, fill, 12.0, .identity);
try picture_builder.addStrokedPath(&path, stroke, .identity);
```

`PathPicture` is immutable after freezing. Reuse it like a sprite sheet: upload its atlas once, rebuild the `PathBatch` only when transforms or instance placement change. GPU and CPU rendering both understand solid, linear-gradient, radial-gradient, and image path paints.

### Images and sprites

Raster images live in a separate renderer-owned image array. Upload them with `Renderer.uploadImage()` / `uploadImages()`, then build quads with `SpriteBatch` or freeze them into a `SpritePicture` for reuse:

```zig
var icon = try snail.Image.initRgba8(allocator, 32, 32, rgba_pixels);
defer icon.deinit();

const icon_view = renderer.uploadImage(&icon);

var sprite_buf: [16 * snail.SPRITE_FLOATS_PER_SPRITE]f32 = undefined;
var sprites = snail.SpriteBatch.init(&sprite_buf);
_ = sprites.addSpriteRect(
    icon_view,
    .{ .x = 12, .y = 18, .w = 24, .h = 24 },
    .{ 1, 1, 1, 1 },
    .{},
    .linear,
);
_ = sprites.addSpriteAt(
    icon_view,
    .{ .x = 200, .y = 120 },
    .{ .x = 32, .y = 32 },
    std.math.pi / 8.0,
    .center,
    .{ 1, 1, 1, 0.85 },
    .{},
    .nearest,
);

renderer.beginFrame();
renderer.drawSprites(sprites.slice(), viewport_w, viewport_h);
```

`SpriteBatch.addSpriteRect()` covers UI/icon quads. `addSpriteAt()` is the point-style convenience for games, and `addSpriteTransformed()` accepts a full affine `Transform2D` when you need direct control.

When the renderer grows its internal image array to accommodate a newly uploaded larger image, previously returned `ImageHandle`s should be reacquired with `uploadImage()` / `uploadImages()` before building the next sprite batch.

### CPU renderer

For headless output or bootstrap frames, `src/extra/cpu_renderer.zig` exposes a software raster path that shares Snail's atlas data and frozen path-picture model:

```zig
const cpu_renderer = @import("extra/cpu_renderer.zig");

var soft = cpu_renderer.CpuRenderer.init(pixel_buf.ptr, width, height, stride);
soft.clear(0, 0, 0, 0);
soft.drawGlyphId(&atlas, try font.glyphIndex('A'), 12, 28, 24, .{ 1, 1, 1, 1 });
soft.drawPathPicture(&path_picture);
```

`drawPathPicture()` uses the same frozen `PathPicture` data as the GPU path, including gradients and image paints. `drawPathPictureTransformed()` applies an extra affine transform at draw time. Fill rule still matches the GPU renderer.

### Performance model

| Operation | Frequency | Cost |
|-----------|-----------|------|
| `Font.init` | Once per font | ~1.7 us |
| `Atlas.init` | Once per glyph set | ~1.7 ms for 95 ASCII glyphs |
| `Atlas.extendCodepoints` | On late glyph discovery | Allocates a new snapshot, preserving old handles |
| `Renderer.uploadAtlas` | Once per atlas generation | GPU texture upload for atlas pages |
| `Renderer.uploadPathPicture` | Once per frozen vector asset | Uploads the picture's atlas pages and returns an `AtlasHandle` |
| `TextBatch.addText` | Per-frame (dynamic) or once (static) | ~1.2 us for 13 chars, ~13.8 us for 175 chars |
| `PathBatch.addPicture` | Per-frame | ~13 ns per shape instanced from a frozen picture |
| `PathPictureBuilder.freeze` | Static UI / icons | ~29 us per shape on the current bench; amortize by freezing once |
| `Renderer.beginFrame` | Per-frame | Resets cached GL state (call before `drawText` when sharing a GL context) |
| `Renderer.drawText` | Per-frame | Single draw call per text batch |
| `Renderer.drawPaths` | Per-frame | Single draw call per path batch, grayscale AA |

For static UI text, build the `TextBatch` once and call `Renderer.drawText` each frame with the same `batch.slice()`. The vertex buffer is caller-owned and zero-allocation.

For dynamic text (input fields, counters, chat), rebuild the `TextBatch` each frame. On this machine, Latin layout is roughly `0.08 us/glyph`, so 1000 glyphs stays comfortably sub-millisecond.

For static vector UI and icons, freeze `PathPicture`s ahead of first paint when possible, upload them once, and reuse the returned `AtlasHandle` plus `PathBatch` every frame. That keeps startup work on the shared text/path shaders instead of paying for a second vector-specific pipeline.

### Dynamic glyph loading

Add glyphs at runtime by creating a new snapshot, then swap the atlas pointer and re-upload the returned pages:

```zig
if (try atlas.extendText("مرحبا بالعالم")) |next| {
    snail.replaceAtlas(&atlas, next);
    atlas_handle = renderer.uploadAtlas(&atlas);
}
```

`Atlas.extendText()` is the high-level entry point for UTF-8 strings. It uses HarfBuzz shaping when available, otherwise it falls back to codepoint discovery plus built-in ligature loading.

Lower-level entry points are available when you already have codepoints or shaped glyph runs:

```zig
const new_codepoints = [_]u32{ 0x00E9, 0x00F1, 0x00FC }; // é, ñ, ü
if (try atlas.extendCodepoints(&new_codepoints)) |next| {
    snail.replaceAtlas(&atlas, next);
    atlas_handle = renderer.uploadAtlas(&atlas);
}

const glyph_ids = [_]u16{ try font.glyphIndex('M'), try font.glyphIndex('W') };
if (try atlas.extendGlyphIds(&glyph_ids)) |next| {
    snail.replaceAtlas(&atlas, next);
    atlas_handle = renderer.uploadAtlas(&atlas);
}
```

All public color inputs are straight RGBA. snail premultiplies internally before blending on both GPU and CPU paths.

### Fill rule

Supports both non-zero winding (TrueType default) and even-odd fill rules:

```zig
renderer.setFillRule(.even_odd);
```

### Subpixel rendering

`renderer.setSubpixelOrder(.rgb)` requests LCD subpixel antialiasing. In the default `.safe` mode, snail uses LCD AA for axis-aligned text when the backend supports safe per-channel blending; otherwise it can still resolve against a declared opaque solid backdrop, and falls back to grayscale AA when neither path is valid. `drawPaths()` always stays grayscale.

`renderer.setSubpixelMode(.legacy_unsafe)` restores the old behavior if you explicitly want the extra sharpness and accept incorrect compositing on arbitrary backgrounds.

All five orders are supported: `.none` (off), `.rgb`, `.bgr`, `.vrgb`, `.vbgr`. The demo auto-detects the system base order via fontconfig, and the `L` key cycles orders at runtime.

```zig
renderer.setSubpixelOrder(.rgb);   // horizontal RGB (most common)
renderer.setSubpixelOrder(.vrgb);  // vertical RGB (rotated display)
renderer.setSubpixelOrder(.none);  // disable (OLED/HiDPI)

renderer.setSubpixelMode(.safe);   // default
renderer.setSubpixelBackdrop(.{ 0.08, 0.09, 0.12, 1.0 }); // opaque solid background under the text

// Escape hatch: preserves the old LCD path, including its compositing artifacts.
renderer.setSubpixelMode(.legacy_unsafe);
```

### OpenType shaping

Built-in ligature substitution (GSUB type 4) and kerning (GPOS type 2) with kern table fallback. Sufficient for Latin, Cyrillic, and Greek text.

For complex scripts (Arabic, Devanagari, Thai, etc.), compile with `-Dharfbuzz=true`:

```zig
// HarfBuzz is used automatically by addText() when enabled
if (try atlas.extendText("مرحبا بالعالم")) |next| {
    snail.replaceAtlas(&atlas, next);
    atlas_handle = renderer.uploadAtlas(&atlas);
}
_ = batch.addText(atlas_handle, &font, "مرحبا بالعالم", x, y, 32, color);
```

When HarfBuzz is not compiled in, `addText` uses the built-in shaper. The `addRun()` API is always available for callers who bring their own shaped `ShapedRun`.

### C API

`#include "snail.h"` — see [`include/snail.h`](include/snail.h) for the full interface.

```c
#include "snail.h"

SnailFont *font;
snail_font_init(ttf_data, ttf_len, &font);

SnailLineMetrics line_metrics;
snail_font_line_metrics(font, &line_metrics);

uint32_t codepoints[] = { 'A', 'B', 'C', /* ... */ };
SnailAtlas *atlas;
snail_atlas_init(NULL, font, codepoints, num_codepoints, &atlas);  // NULL = libc malloc

// GL thread
snail_renderer_init();
snail_renderer_upload_atlas(atlas);

float vertices[5000 * snail_floats_per_glyph()];
size_t len = 0;
float color[] = {1, 1, 1, 1};
snail_batch_add_string(vertices, sizeof(vertices)/sizeof(float), &len,
                       atlas, font, "Hello", 5, x, y, 48.0f, color);

snail_renderer_draw(vertices, len, mvp, viewport_w, viewport_h);
```

Pass a `SnailAllocator` to `snail_atlas_init` for custom allocation, or `NULL` for libc malloc/free. The C API is OpenGL-only and currently text-focused; frozen path-picture vectors are exposed through the Zig API. Vulkan also requires the Zig API.

### Using as a Zig dependency

Add snail to your `build.zig.zon`:

```zig
.dependencies = .{
    .snail = .{ .path = "../snail" },  // or .url for remote
},
```

In your `build.zig`, the simplest path is to use snail's helper module. This links OpenGL and enables HarfBuzz by default, but does not pull in the demo's Wayland/EGL deps:

```zig
const snail_dep = b.dependency("snail", .{});
const snail_mod = @import("snail").module(snail_dep.builder, target, optimize);
root_module.addImport("snail", snail_mod);
```

If you need non-default build options, construct the module manually:

```zig
const snail_dep = b.dependency("snail", .{});

const snail_opts = b.addOptions();
snail_opts.addOption(bool, "enable_profiling", false);
snail_opts.addOption(bool, "enable_harfbuzz", false);
snail_opts.addOption(bool, "enable_vulkan", false);
snail_opts.addOption(bool, "force_gl33", true);

const vk_stub = b.createModule(.{
    .root_source_file = b.addWriteFiles().add("vk_stub.zig", ""),
});
const snail_mod = b.createModule(.{
    .root_source_file = snail_dep.path("src/snail.zig"),
    .target = target,
    .optimize = optimize,
    .link_libc = true,
});
snail_mod.addOptions("build_options", snail_opts);
snail_mod.linkSystemLibrary("OpenGL", .{});
snail_mod.addImport("vulkan_shaders", vk_stub);
root_module.addImport("snail", snail_mod);
```

The caller must have an active OpenGL 3.3+ context before calling `Renderer.init()`. snail manages its own GL state (shader programs, VAOs, textures, blend/depth) per draw call. If other renderers share the GL context, call `renderer.beginFrame()` once per frame before `draw()`, `drawPaths()`, or `drawSprites()` so snail re-binds its cached state.

### Thread safety

| Type | Thread model |
|------|-------------|
| `Font` | Immutable after init. Safe for concurrent reads from any thread. |
| `Atlas` | Immutable snapshot. `extend*()` returns a new snapshot that preserves existing handles; `compact()` returns a new snapshot and may repack them. Safe for concurrent reads. |
| `TextBatch` | Operates on caller-owned buffers. Multiple batches reading the same `AtlasHandle` from different threads is safe. |
| `PathPicture` | Immutable after creation. Safe for concurrent reads from any thread. |
| `Renderer` | **Single-thread per context.** GL: all calls must be on the thread with the active GL context. Vulkan: all calls must be externally synchronized. |

Typical game pattern:
1. **Load thread**: `Font.init` + `Atlas.init` (CPU-only, no GPU context needed)
2. **Render thread**: `Renderer.uploadAtlas` (once), `Renderer.drawText` (per frame)
3. **Any thread(s)**: `TextBatch.addText` into thread-local buffers, submit to render thread for drawing

Static text (HUD, menus): build the `TextBatch` once, reuse the vertex slice every frame. The draw call is a VBO upload + single `glDrawElements`.

## Architecture

```
src/
  snail.zig              public API: Font, Atlas, Renderer, TextBatch
  c_api.zig              C bindings (extern functions)
  font/ttf.zig           TrueType parser (head, maxp, cmap, glyf, loca, hhea, hmtx, kern)
  font/opentype.zig      OpenType shaper (GSUB ligatures, GPOS kerning)
  font/harfbuzz.zig      HarfBuzz integration (optional, -Dharfbuzz=true)
  font/snail_file.zig    .snail preprocessed format (zero-parse loading)
  math/                  Vec2, Mat4, QuadBezier, quadratic root solver
  render/
    gl.zig               OpenGL cImport (shared by pipeline and library consumers)
    platform.zig         demo OpenGL platform (Wayland + EGL)
    wayland_window.zig   demo Wayland window/input glue
    egl_offscreen.zig    offscreen EGL context helper for benchmarks
    shaders.zig          GLSL 330 vertex + fragment shaders (Slug algorithm)
    pipeline.zig         OpenGL state management (GL 3.3/4.4)
    vulkan_pipeline.zig  Vulkan state management (optional, -Dvulkan=true)
    vulkan_shaders.zig   SPIR-V shaders (compiled from GLSL at build time)
    curve_texture.zig    RGBA16F curve control point texture
    band_texture.zig     RG16UI spatial band subdivision texture
    vertex.zig           glyph quad vertex generation (5x vec4 per vertex)
  profile/timer.zig      comptime-gated CPU timers (zero overhead when disabled)
include/
  snail.h                C header
```

### How it works

1. **TTF parsing**: extract glyph outlines as quadratic Bézier curves from TrueType font files.

2. **Curve texture**: pack all control points into an RGBA16F texture. Each curve occupies two texels: `(p1.x, p1.y, p2.x, p2.y)` and `(p3.x, p3.y, -, -)`.

3. **Band texture**: subdivide each glyph's bounding box into horizontal and vertical bands. Each band stores which curves intersect it. This reduces per-pixel work from O(all curves) to O(curves in band).

4. **Vertex shader**: apply dynamic dilation (expand glyph quads by ~0.5px along normals using the inverse Jacobian of the MVP transform) to prevent dropped pixels at edges. Vector primitives keep the same one-quad envelope idea so edge coverage is not clipped.

5. **Fragment shader**: for each pixel, determine its band, fetch the relevant curves, cast horizontal and vertical rays, solve the resulting quadratic equations, classify roots via control point sign patterns (the core Slug technique), accumulate a winding number, and convert to fractional coverage for antialiasing. Vector primitives follow the same coverage model, but generate their quadratic curves procedurally from the packed rect / rounded-rect / ellipse parameters instead of looking them up from the glyph atlas.

Curves within each band are sorted by descending maximum coordinate, enabling early exit when no further curves can affect the pixel.

## Benchmarks

There are four benchmark entry points. They answer different questions.

- `zig build bench`
  CPU-only microbenchmarks for isolated code paths: font init, glyph parsing, atlas texture preparation, math kernels, and vector vertex packing. No renderer, no GPU draw, and no FreeType comparison.
- `zig build bench-compare`
  CPU-side prep and layout comparison against FreeType. This measures font load, glyph prep, and layout cost. GPU drawing is intentionally excluded.
- `zig build bench-headless`
  Fully offscreen end-to-end frame timing. This is the command to use when you want per-frame numbers for text rendering. It includes layout, batch generation, uploads, draw, and explicit GPU synchronization. OpenGL runs by default; `-Dvulkan=true` adds the Vulkan offscreen path.
- `zig build bench-suite`
  Combined regression suite. It includes the FreeType layout comparison plus text and vector rendering scenarios in one run. Use it when you want one broad pass instead of one focused benchmark. `-Dvulkan=true` adds Vulkan text and vector passes after the OpenGL pass.

What to watch in the output:

- `bench`: `Parse 62 glyphs` and `Band texture` are the main atlas/prep lines.
- `bench-compare`: `Glyph prep (7 sizes)`, `Paragraph`, and `Torture` are the lines that usually move first.
- `bench-headless`: `Body text`, `Torture`, and `Chat` are the most useful text-rendering lines. Compare `static` vs `dynamic`.
- `bench-suite`: watch `Paragraph`, `Body text`, `Multi-font torture`, and `Primitive stress`. This is the best single regression pass.

Current sampling defaults:

- `bench`: hot-loop iteration counts are 10x higher than before, and prep timings are averaged across repeated runs where applicable.
- `bench-compare`: 5,000 layout samples per scenario.
- `bench-headless`: 1,000 warmup frames and 20,000 measured frames per scenario.
- `bench-suite`: 5,000 layout samples plus 1,000 warmup and 20,000 measured frames per rendering scenario.

For `bench-headless` and `bench-suite`:

- `static` means the vertex buffer is built once and reused every frame.
- `dynamic` means vertices are rebuilt every frame before drawing.

`bench-headless` uses fully offscreen backends:

- OpenGL: EGL pbuffer + FBO.
- Vulkan: offscreen `VkImage`; no window, surface, or swapchain in the measured path.

Benchmark results are machine-specific. Rerun the commands locally and compare the same lines when checking regressions.

### Other GPU font renderers

| Project | Language | GPU API | Notes |
|---------|----------|---------|-------|
| [Slug Library](https://sluglibrary.com/) | C++ | Vulkan/D3D/GL/Metal | Commercial. The reference implementation (10 years of optimization). |
| [slug_wgpu](https://github.com/santiagosantos08/slug_wgpu) | Rust | wgpu | FOSS Slug implementation. |
| [gpu-font-rendering](https://github.com/GreenLightning/gpu-font-rendering) | C++ | OpenGL | Dobbie/Lengyel technique. |
| [Pathfinder](https://github.com/pcwalton/pathfinder) | Rust | GL/Metal | General vector graphics GPU rasterizer. |
| **snail** | **Zig** | **OpenGL 3.3+ / Vulkan** | **This project. C API. MIT licensed.** |

## License

MIT. See [LICENSE](LICENSE).

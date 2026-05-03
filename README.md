# snail

GPU text and vector rendering via direct Bezier curve evaluation.

![snail demo scene](assets/demo_screenshot.png)

snail renders text by evaluating quadratic Bezier curves per-pixel in a fragment shader. No bitmap atlases, no signed distance fields. Glyphs are resolution-independent and render correctly at any size, rotation, or perspective transform. The same curve evaluation pipeline also renders filled and stroked vector paths with solid, gradient, and image paints.

This is alpha-quality software. The Zig API is settling but not yet stable. The C API tracks the Zig surface. Breaking changes are expected.

## Algorithm

This is an implementation of the [Slug algorithm](https://sluglibrary.com/):

- Eric Lengyel, ["GPU-Centered Font Rendering Directly from Glyph Outlines"](https://jcgt.org/published/0006/02/02/), JCGT 2017
- Eric Lengyel, ["A Decade of Slug"](https://terathon.com/blog/decade-slug.html), 2026
- [Reference HLSL shaders](https://github.com/EricLengyel/Slug) (MIT / Apache-2.0)

The Slug patent (US 10,373,352) was [dedicated to the public domain](https://terathon.com/blog/decade-slug.html) in March 2026. This implementation is original code, not derived from the Slug Library product. Licensed under MIT.

### How it works

**Font loading.** snail parses TrueType fonts directly: `cmap` for codepoint-to-glyph mapping, `glyf`/`loca` for outlines, `hhea`/`hmtx` for metrics, `kern` for legacy kerning. Optional OpenType shaping applies GSUB ligature substitution (type 4) and GPOS pair positioning (type 2). HarfBuzz can be compiled in for full complex-script shaping.

**Atlas preparation.** Each glyph's quadratic Bezier curves are packed into two GPU textures at load time:

- *Curve texture* (RGBA16F): control points for every curve segment, stored as f16 in font-unit coordinates.
- *Band texture* (RG16UI): spatial subdivision indices. The glyph bounding box is split into horizontal and vertical bands; each band records which curve segments intersect it.

This preprocessing is CPU-only and runs once per glyph set. The textures are uploaded as 2D texture arrays, one layer per atlas page.

**Fragment shader.** At draw time, each glyph is a screen-space quad. The fragment shader:

1. Reads the band indices for this fragment's position.
2. For each curve in the active bands, evaluates a quadratic Bezier root equation to count ray crossings.
3. Applies the winding rule (non-zero or even-odd) to determine inside/outside.
4. Outputs analytic coverage as alpha, optionally with per-channel LCD subpixel offsets for horizontal RGB/BGR or vertical VRGB/VBGR subpixel rendering.

There is no rasterization, no texture sampling for glyph shapes, and no distance field approximation. Coverage is exact at every resolution.

**Vector paths.** Filled and stroked `Path` geometry goes through the same pipeline. Paths are decomposed into quadratic curves (cubics are adaptively approximated), packed into the same curve/band texture format, and drawn with the same fragment shader. Strokes are expanded into offset curves with proper joins (miter, bevel, round) and caps (butt, square, round). The `PathPicture` type freezes a set of styled paths into an immutable atlas snapshot that can be instanced cheaply per frame.

## Color convention

All color parameters are **sRGB, straight (unpremultiplied) alpha**, as `[4]f32` in the range 0.0–1.0. This applies to `FillStyle.color`, `StrokeStyle.color`, gradient stops, `ImagePaint.tint`, and text color arguments. The renderer premultiplies alpha and linearizes for blending internally.

**Images** (`Image.initSrgba8`) expect sRGB-encoded RGBA8 pixel data (4 bytes per pixel, 0–255). This is what most image decoders produce. Linear-space pixel buffers will appear too bright.

**Gradients** interpolate in sRGB space by default, which gives perceptually smooth results for UI use. Set `color_space = .linear_rgb` on `LinearGradient` or `RadialGradient` for physically correct interpolation (avoids dark bands between complementary hues).

**Blending** uses premultiplied alpha with gamma-correct (linear-space) compositing. On GPU, `GL_FRAMEBUFFER_SRGB` / Vulkan sRGB swapchain handles linearization automatically. The CPU renderer uses equivalent lookup tables.

## Build

Requires [Zig 0.16](https://ziglang.org/download/), OpenGL 3.3+, HarfBuzz, and pkg-config. The interactive demo requires Wayland + EGL. Vulkan support is optional.

```sh
zig build test                                  # unit tests
zig build run                                   # interactive demo (GL 4.4, Wayland)
zig build run -Drenderer=gl33                   # force OpenGL 3.3
zig build run -Drenderer=vulkan -Dvulkan=true   # Vulkan backend
zig build run -Drenderer=cpu                    # CPU renderer (headless)
zig build screenshot                            # GL screenshot → zig-out/demo-screenshot.tga
zig build screenshot-cpu                        # CPU screenshot (no GPU)
zig build bench-suite                           # layout + rendering benchmarks
zig build bench-suite -Dvulkan=true             # includes Vulkan passes
zig build install --release=fast                # install libsnail.a + snail.h
```

Library backend flags: `-Dopengl=true` (default), `-Dvulkan=false`, `-Dcpu-renderer=true` (default).

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

Your project needs OpenGL and HarfBuzz available via pkg-config. On NixOS/nix-shell, these are provided automatically. On other systems, install the development packages for your distro.

## Example: Zig

```zig
const snail = @import("snail");

// Create fonts with fallback chain (data slices must outlive Fonts)
var fonts = try snail.Fonts.init(allocator, &.{
    .{ .data = noto_sans_regular },
    .{ .data = noto_sans_bold, .weight = .bold },
    .{ .data = noto_sans_regular, .italic = true, .synthetic = .{ .skew_x = 0.2 } },
    .{ .data = noto_sans_arabic, .fallback = true },
    .{ .data = twemoji, .fallback = true },
});
defer fonts.deinit();

// Populate atlas — starts empty, ensureText returns a new snapshot
fonts = (try fonts.ensureText(.{}, "Hello, world!")) orelse fonts;

// Initialize renderer (requires active GL 3.3+ context)
var renderer = try snail.Renderer.init();
defer renderer.deinit();

// Upload font textures
var font_atlas = fonts.uploadAtlas();
defer fonts.deinitUploadAtlas(&font_atlas);
renderer.uploadAtlases(&.{&font_atlas}, &.{});

// Build text vertices (zero allocations, caller-owned buffer)
var buf: [4096 * snail.TEXT_FLOATS_PER_GLYPH]f32 = undefined;
var batch = snail.TextBatch.init(&buf);
_ = try fonts.addText(&batch, .{}, "Hello, world!", 10, 400, 48, .{ 1, 1, 1, 1 });

// Draw
renderer.beginFrame();
renderer.drawText(batch.slice(), mvp, viewport_w, viewport_h);
```

### On-demand atlas extension

`ensureText` returns a new immutable snapshot; the old one remains valid for in-flight readers.

```zig
// Render — text is automatically itemized across fonts
const result = try fonts.addText(&batch, .{}, text, 10, 400, 24, color);

// If glyphs were missing, extend and re-render next frame
if (result.missing) {
    if (try fonts.ensureText(.{}, text)) |new_fonts| {
        fonts.deinit();  // safe: no other readers
        fonts = new_fonts;
        // re-upload and redraw
    }
}
```

### Vector paths

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
const pic_handle = renderer.uploadPathPicture(&picture);

var pbuf: [64 * snail.PATH_FLOATS_PER_SHAPE]f32 = undefined;
var paths = snail.PathBatch.init(&pbuf);
_ = paths.addPicture(&pic_handle, &picture);
renderer.drawPaths(paths.slice(), mvp, viewport_w, viewport_h);
```

## Example: C

> **Note:** The C API still uses the lower-level `Font`/`Atlas` types. A `snail_fonts_*` C API is planned.

```c
#include "snail.h"

SnailFont *font;
snail_font_init(ttf_data, ttf_len, &font);

SnailAtlas *atlas;
snail_atlas_init_ascii(NULL, font, &atlas);

snail_renderer_init();
snail_renderer_upload_atlas(atlas);

// Render text
float buf[4096 * 80]; // 80 = TEXT_FLOATS_PER_GLYPH
size_t buf_len = 0;
float color[] = {1, 1, 1, 1};
snail_batch_add_text(buf, sizeof(buf)/sizeof(float), &buf_len,
                     atlas, font, "Hello", 5, 10, 400, 48, color);

float mvp[16]; // column-major 4x4
snail_renderer_draw_text(buf, buf_len, mvp, 1280, 720);

// Shape text with source-span metadata
SnailShapedRun *run;
snail_atlas_shape_utf8(atlas, font, "Hello", 5, 48.0, &run);
size_t n = snail_shaped_run_glyph_count(run);
SnailGlyphPlacement g;
for (size_t i = 0; i < n; i++) {
    snail_shaped_run_glyph(run, i, &g);
    // g.glyph_id, g.x_offset, g.source_start, g.source_end ...
}
snail_shaped_run_deinit(run);

// Vector path
SnailPath *path;
snail_path_init(NULL, &path);
snail_path_add_rounded_rect(path, (SnailRect){0, 0, 200, 80}, 12);

SnailPathPictureBuilder *builder;
snail_path_picture_builder_init(NULL, &builder);
SnailFillStyle fill = {.color = {0.1, 0.1, 0.2, 0.9}, .paint_kind = -1};
snail_path_picture_builder_add_filled_path(builder, path, fill,
                                           SNAIL_TRANSFORM2D_IDENTITY);

SnailPathPicture *picture;
snail_path_picture_builder_freeze(builder, NULL, &picture);
snail_renderer_upload_path_picture(picture);

float pbuf[64 * 80];
size_t pbuf_len = 0;
snail_path_batch_add_picture(pbuf, sizeof(pbuf)/sizeof(float), &pbuf_len, picture);
snail_renderer_draw_paths(pbuf, pbuf_len, mvp, 1280, 720);

// Cleanup
snail_path_picture_deinit(picture);
snail_path_picture_builder_deinit(builder);
snail_path_deinit(path);
snail_atlas_deinit(atlas);
snail_font_deinit(font);
snail_renderer_deinit();
```

## API reference

### Types

| Type | Description |
|------|-------------|
| `Fonts` | Multi-font manager. Immutable snapshot with shared glyph atlas. `ensureText` returns a new snapshot; old stays valid. |
| `FaceSpec` | `{ .data, .weight, .italic, .fallback, .synthetic }` — font face specification for `Fonts.init`. |
| `FontStyle` | `{ .weight: FontWeight, .italic: bool }` — selects a face for rendering. |
| `FontWeight` | `.regular`, `.bold`, `.semi_bold`, etc. |
| `SyntheticStyle` | `{ .skew_x, .embolden }` — synthetic italic shear and bold offset. |
| `AddTextResult` | `{ .advance: f32, .missing: bool }` — returned by `Fonts.addText`. |
| `TextBatch` | Writes glyph vertices into a caller-owned `[]f32`. Zero allocations. |
| `Image` | sRGB RGBA8 raster image. Created with `initSrgba8`. |
| `Path` | Mutable path builder: `moveTo`, `lineTo`, `quadTo`, `cubicTo`, `close`, plus shape helpers. |
| `PathPictureBuilder` | Accumulates filled/stroked paths and shapes with paint styles. |
| `PathPicture` | Immutable frozen vector art. Upload once, instance cheaply per frame. |
| `PathBatch` | Writes path instance vertices into a caller-owned `[]f32`. |
| `Renderer` | Owns GPU state (shaders, textures). One per GL/Vulkan context. |
| `Rect` | `{ x, y, w, h }` rectangle. |
| `Transform2D` | 2x3 affine matrix `{ xx, xy, tx, yx, yy, ty }`. |
| `FillStyle` | sRGB fill color (straight alpha) with optional `Paint`. |
| `StrokeStyle` | sRGB stroke color (straight alpha), width, optional paint, cap, join, miter limit, placement. |
| `Paint` | Tagged union: `.solid`, `.linear_gradient`, `.radial_gradient`, `.image`. |
| `ColorSpace` | Gradient interpolation space: `.srgb` (default) or `.linear_rgb`. |

### Fonts

| Method | Description |
|--------|-------------|
| `Fonts.init(alloc, faces) !Fonts` | Parse font faces. Atlas starts empty. |
| `fonts.deinit()` | Release resources. Shared pages remain valid for other snapshots. |
| `fonts.ensureText(style, text) !?Fonts` | Return new snapshot with glyphs for `text`. Null if already present. |
| `fonts.addText(batch, style, text, x, y, size, color) !AddTextResult` | Itemize + shape + emit. Returns advance and whether any glyphs were missing. |
| `fonts.measureText(style, text, size) !f32` | Measure advance width without emitting vertices. |
| `fonts.lineMetrics() !LineMetrics` | Primary face `hhea` ascent, descent, line gap in font units. |
| `fonts.decorationRect(kind, x, y, advance, size) !Rect` | Compute underline or strikethrough rect from font metrics. |
| `fonts.superscriptTransform(x, y, size) !ScriptTransform` | Adjusted position and size for superscript text. |
| `fonts.subscriptTransform(x, y, size) !ScriptTransform` | Adjusted position and size for subscript text. |
| `fonts.uploadAtlas() Atlas` | Temporary Atlas wrapper for GPU upload. Call `deinitUploadAtlas` after. |
| `fonts.pageCount() usize` | Number of texture pages. |

### TextBatch

| Method | Description |
|--------|-------------|
| `TextBatch.init(buf) TextBatch` | Wrap a caller-owned `[]f32`. |
| `batch.glyphCount() usize` | Glyphs written so far. |
| `batch.slice() []const f32` | Vertex data for `Renderer.drawText`. |
| `batch.reset()` | Clear without reallocating. |

### Renderer

| Method | Description |
|--------|-------------|
| `Renderer.init() !Renderer` | Initialize OpenGL backend. |
| `Renderer.initVulkan(ctx) !Renderer` | Initialize Vulkan backend. |
| `renderer.uploadAtlas(atlas) AtlasHandle` | Upload atlas textures. |
| `renderer.uploadImage(image) ImageHandle` | Upload raster image. |
| `renderer.uploadPathPicture(pic) AtlasHandle` | Upload path picture atlas. |
| `renderer.beginFrame()` | Reset cached GPU state. Call once per frame. |
| `renderer.drawText(verts, mvp, w, h)` | Draw text batch vertices. |
| `renderer.drawPaths(verts, mvp, w, h)` | Draw path batch vertices (always grayscale AA). |
| `renderer.setSubpixelOrder(order)` | `.none`, `.rgb`, `.bgr`, `.vrgb`, `.vbgr`. |
| `renderer.setFillRule(rule)` | `.non_zero` (default) or `.even_odd`. |

### Path

| Method | Description |
|--------|-------------|
| `Path.init(alloc) Path` | New empty path. |
| `path.moveTo(point)` | Begin subpath. |
| `path.lineTo(point)` | Line segment. |
| `path.quadTo(control, point)` | Quadratic Bezier. |
| `path.cubicTo(c1, c2, point)` | Cubic Bezier (adaptively approximated to quadratics). |
| `path.close()` | Close current subpath. |
| `path.addRect(rect)` | Append rectangle subpath. |
| `path.addRoundedRect(rect, radius)` | Append rounded rectangle. |
| `path.addEllipse(rect)` | Append ellipse inscribed in rect. |

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
| `builder.freeze(alloc) !PathPicture` | Compile to immutable atlas. |

### Constants

| Constant | Value | Use |
|----------|-------|-----|
| `TEXT_FLOATS_PER_GLYPH` | 80 | Buffer sizing for `TextBatch`. |
| `PATH_FLOATS_PER_SHAPE` | 80 | Buffer sizing for `PathBatch`. |

## Benchmarks

All numbers from a single machine (Ryzen 7 / RTX 3080, NotoSans-Regular, 1280x720 offscreen). Rerun locally with `zig build bench-suite` for your hardware.

**Layout** — CPU text shaping and vertex generation, no GPU draw. Compared against FreeType.

| Scenario | snail | FreeType | Speedup |
|----------|-------|----------|---------|
| Short string (13 chars) | 1.2 us | 109 us | 93x |
| Sentence (53 chars) | 3.9 us | 540 us | 137x |
| Paragraph (175 chars) | 13.8 us | 1920 us | 140x |
| Torture (para x7 sizes) | 96 us | 13942 us | 145x |

**Rendering (OpenGL)** — full frame: vertex build + GPU draw + sync. Static = pre-built buffer, draw only. Dynamic = rebuild vertices every frame.

| Scenario | Glyphs | Static FPS | Dynamic FPS |
|----------|--------|-----------|-------------|
| Game HUD (2 lines) | 45 | 34,820 | 46,381 |
| Body text (6 paragraphs) | 978 | 15,432 | 9,702 |
| Torture (fill screen) | 4,075 | 4,935 | 2,501 |
| Arabic (12 lines, HarfBuzz) | 264 | 44,127 | 20,829 |
| Multi-font torture (4 fonts) | 522 | 24,595 | 10,953 |

**Rendering (Vulkan)** — same scenarios, Vulkan offscreen backend.

| Scenario | Glyphs | Static FPS | Dynamic FPS |
|----------|--------|-----------|-------------|
| Game HUD (2 lines) | 45 | 35,228 | 36,460 |
| Body text (6 paragraphs) | 978 | 12,355 | 9,995 |
| Torture (fill screen) | 4,075 | 3,910 | 2,497 |

**Vectors (OpenGL)** — path fill + stroke rendering.

| Scenario | Shapes | Static FPS | Dynamic FPS |
|----------|--------|-----------|-------------|
| Primitive showcase | 10 | 13,832 | 13,951 |
| Primitive stress | 587 | 4,753 | 4,800 |

## Architecture

```
src/
  snail.zig              public API: Fonts, Renderer, TextBatch, Path, ...
  fonts.zig              Fonts type: multi-font manager with immutable snapshot atlas
  c_api.zig              C bindings
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
    pipeline.zig         OpenGL state (GL 3.3 / 4.4 persistent mapped)
    gl.zig               OpenGL C function imports
    gl_backend.zig       GL version detection and backend selection
    shaders.zig          GLSL 330 vertex + fragment shaders
    vulkan_pipeline.zig  Vulkan state (optional)
    vulkan_shaders.zig   SPIR-V / Vulkan shader modules
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
    screenshot.zig       framebuffer capture + TGA writing
    subpixel_order.zig   RGB/BGR/VRGB/VBGR enum
    subpixel_detect.zig  auto-detect display subpixel layout
    subpixel_policy.zig  subpixel rendering policy logic
  profile/
    timer.zig            comptime-gated CPU timers
include/
  snail.h                C header
```

## Thread safety

| Type | Rule |
|------|------|
| `Fonts` | Immutable snapshot. Safe for concurrent reads. `ensureText` returns a new snapshot; old remains valid. |
| `TextBatch`, `PathBatch` | Caller-owned buffers. Thread-local — no sharing needed. |
| `PathPicture` | Immutable after freeze. Safe for concurrent reads. |
| `Renderer` | Single-threaded. Must be called from the GL/Vulkan context thread. |

Typical pattern: build `Fonts` and call `ensureText` on a loading thread, upload and draw on the render thread, fill batches on any thread(s) into thread-local buffers. When new text arrives, `ensureText` on any thread returns a new snapshot; swap it in on the render thread between frames.

## Status and roadmap

snail is used in development but is not yet stable. Current limitations:

- OpenType shaping is limited to GSUB type 4 (ligatures) and GPOS type 2 (pair positioning). Complex scripts require `-Dharfbuzz=true`.
- No CFF/CFF2 support (TrueType outlines only).
- No variable fonts.
- One renderer per process (pipeline state is module-scoped, tied to the GL/Vulkan context).
- C API is GL-only (no Vulkan bindings yet).

Planned:
- Vulkan C API parity.
- C API for `Fonts` type.

## License

MIT

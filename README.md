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

**Sprites.** Raster images use a separate vertex format and shader. `SpriteBatch` writes positioned, tinted, UV-mapped quads into a caller-owned buffer. Images are uploaded into a shared texture array. Supports nearest/linear filtering, UV sub-rects, rotation, anchors, and full affine transforms.

## Build

Requires [Zig 0.16](https://ziglang.org/download/), OpenGL 3.3+, HarfBuzz, and pkg-config. The interactive demo requires Wayland + EGL. Vulkan support is optional.

```sh
zig build test                       # unit tests
zig build bench                      # CPU microbenchmarks
zig build bench-compare              # layout comparison vs FreeType
zig build bench-headless             # offscreen end-to-end frame timing
zig build bench-suite                # combined layout + rendering suite
zig build bench-suite -Dvulkan=true  # includes Vulkan passes
zig build run                        # interactive demo (Wayland + EGL)
zig build run -Dvulkan=true          # Vulkan demo backend
zig build screenshot                 # render demo scene to zig-out/demo-screenshot.tga
zig build install --release=fast     # install libsnail.a + snail.h to zig-out/
```

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

// Parse font (data slice must outlive the Font)
var font = try snail.Font.init(ttf_bytes);
defer font.deinit();

// Build glyph atlas for the characters you need
var atlas = try snail.Atlas.init(allocator, &font, &codepoints);
defer atlas.deinit();

// Initialize renderer (requires active GL 3.3+ context)
var renderer = try snail.Renderer.init();
defer renderer.deinit();
const atlas_handle = renderer.uploadAtlas(&atlas);

// Build text vertices (zero allocations, caller-owned buffer)
var buf: [4096 * snail.TEXT_FLOATS_PER_GLYPH]f32 = undefined;
var batch = snail.TextBatch.init(&buf);
_ = batch.addText(atlas_handle, &font, "Hello, world!", 10, 400, 48, .{ 1, 1, 1, 1 });

// Draw
renderer.beginFrame();
renderer.drawText(batch.slice(), mvp, viewport_w, viewport_h);
```

### Shaped-run API

For terminals, editors, and other callers that need per-glyph metadata:

```zig
// Shape text into positioned glyphs with source-span metadata
const run = try atlas.shapeUtf8(&font, text, 24.0, allocator);
defer allocator.free(run.glyphs);

// Each glyph carries byte offsets into the source text,
// so callers can reason about ligatures, cells, and selection
for (run.glyphs) |g| {
    // g.glyph_id, g.x_offset, g.y_offset
    // g.x_advance, g.y_advance
    // g.source_start, g.source_end  (byte range in input)
}

// Ensure atlas has all needed glyphs, then render
var missing: [256]u16 = undefined;
const n = atlas.collectMissingGlyphIds(&run, &missing);
if (n > 0) {
    if (try atlas.extendGlyphIds(missing[0..n])) |next| {
        snail.replaceAtlas(&atlas, next);
        atlas_handle = renderer.uploadAtlas(&atlas);
    }
}
_ = batch.addRun(atlas_handle, &run, 0, 0, 24, color);
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

### Sprites

```zig
var icon = try snail.Image.initRgba8(allocator, 32, 32, pixels);
defer icon.deinit();
const img_handle = renderer.uploadImage(&icon);

var sbuf: [16 * snail.SPRITE_FLOATS_PER_SPRITE]f32 = undefined;
var sprites = snail.SpriteBatch.init(&sbuf);
_ = sprites.addSprite(img_handle, .{ .x = 10, .y = 10 }, .{ .x = 32, .y = 32 }, .{ 1, 1, 1, 1 });
renderer.drawSprites(sprites.slice(), mvp, viewport_w, viewport_h);
```

## Example: C

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
| `Font` | Parsed TrueType font. Immutable, thread-safe for reads. |
| `Atlas` | Immutable GPU texture data for a set of glyphs. Extending returns a new snapshot sharing old pages. |
| `AtlasHandle` | Lightweight token returned by `Renderer.uploadAtlas`, encoding texture-array base layer. |
| `GlyphPlacement` | Positioned glyph with `glyph_id`, pixel offsets/advances, and source byte span. |
| `ShapedRun` | Slice of `GlyphPlacement` plus total advance. Output of `Atlas.shapeUtf8`. |
| `TextBatch` | Writes glyph vertices into a caller-owned `[]f32`. Zero allocations. |
| `Image` | RGBA8 raster image. |
| `ImageHandle` | Token returned by `Renderer.uploadImage`, encoding texture-array layer and UV scale. |
| `SpriteBatch` | Writes sprite vertices into a caller-owned `[]f32`. |
| `Path` | Mutable path builder: `moveTo`, `lineTo`, `quadTo`, `cubicTo`, `close`, plus shape helpers. |
| `PathPictureBuilder` | Accumulates filled/stroked paths and shapes with paint styles. |
| `PathPicture` | Immutable frozen vector art. Upload once, instance cheaply per frame. |
| `PathBatch` | Writes path instance vertices into a caller-owned `[]f32`. |
| `Renderer` | Owns GPU state (shaders, textures). One per GL/Vulkan context. |
| `Rect` | `{ x, y, w, h }` rectangle. |
| `Transform2D` | 2x3 affine matrix `{ xx, xy, tx, yx, yy, ty }`. |
| `FillStyle` | Fill color with optional `Paint` (solid, linear gradient, radial gradient, image). |
| `StrokeStyle` | Stroke width, color, optional paint, cap, join, miter limit, placement. |
| `Paint` | Tagged union: `.solid`, `.linear_gradient`, `.radial_gradient`, `.image`. |

### Font

| Method | Description |
|--------|-------------|
| `Font.init(data) !Font` | Parse TTF from raw bytes. Data must outlive the font. |
| `font.unitsPerEm() u16` | Font design units per em. |
| `font.glyphIndex(codepoint) !u16` | Map Unicode codepoint to glyph ID. |
| `font.getKerning(left, right) !i16` | Kern table pair adjustment in font units. |
| `font.advanceWidth(glyph_id) !i16` | Horizontal advance in font units. |
| `font.lineMetrics() !LineMetrics` | `hhea` ascent, descent, line gap in font units. |
| `font.glyphMetrics(glyph_id) !GlyphMetrics` | Advance, LSB, bounding box. |

### Atlas

| Method | Description |
|--------|-------------|
| `Atlas.init(alloc, font, codepoints) !Atlas` | Build atlas for specific codepoints. |
| `Atlas.initAscii(alloc, font, chars) !Atlas` | Build atlas for ASCII byte values. |
| `atlas.extendGlyphIds(ids) !?Atlas` | New snapshot with additional glyphs. Returns `null` if all present. |
| `atlas.extendCodepoints(cps) !?Atlas` | Extend by codepoints. |
| `atlas.extendText(utf8) !?Atlas` | Extend by UTF-8 string (with ligature/shaping discovery). |
| `atlas.extendRun(run) !?Atlas` | Extend by all glyph IDs in a `ShapedRun`. |
| `atlas.shapeUtf8(font, text, font_size, alloc) !ShapedRun` | Shape text into positioned glyphs. Caller frees `run.glyphs`. |
| `atlas.collectMissingGlyphIds(run, out) usize` | Write unique missing glyph IDs to `out`. Returns count. |
| `atlas.compact() !Atlas` | Repack into minimal pages. May invalidate handles. |
| `atlas.pageCount() usize` | Number of texture pages. |
| `atlas.textureByteLen() usize` | Total GPU texture bytes. |
| `replaceAtlas(current, next) bool` | Swap atlas in place (deinits old). |

### TextBatch

| Method | Description |
|--------|-------------|
| `TextBatch.init(buf) TextBatch` | Wrap a caller-owned `[]f32`. |
| `batch.addText(atlas, font, text, x, y, size, color) f32` | Lay out + emit UTF-8. Returns advance. |
| `batch.addRun(atlas, run, x, y, size, color) usize` | Emit a pre-shaped run. Returns glyph count. |
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
| `renderer.drawSprites(verts, mvp, w, h)` | Draw sprite batch vertices. |
| `renderer.setSubpixelOrder(order)` | `.none`, `.rgb`, `.bgr`, `.vrgb`, `.vbgr`. |
| `renderer.setSubpixelMode(mode)` | `.safe` (default) or `.legacy_unsafe`. |
| `renderer.setSubpixelBackdrop(color)` | Declare opaque backdrop for safe LCD fallback. |
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

### SpriteBatch

| Method | Description |
|--------|-------------|
| `SpriteBatch.init(buf) SpriteBatch` | Wrap a caller-owned `[]f32`. |
| `sprites.addSprite(image, pos, size, tint) bool` | Simple positioned sprite. |
| `sprites.addSpriteRect(image, rect, tint, uv, filter) bool` | UV-mapped rect sprite. |
| `sprites.addSpriteTransformed(image, size, tint, uv, filter, anchor, transform) bool` | Full affine transform. |

### Constants

| Constant | Value | Use |
|----------|-------|-----|
| `TEXT_FLOATS_PER_GLYPH` | 80 | Buffer sizing for `TextBatch`. |
| `PATH_FLOATS_PER_SHAPE` | 80 | Buffer sizing for `PathBatch`. |
| `SPRITE_FLOATS_PER_SPRITE` | 64 | Buffer sizing for `SpriteBatch`. |

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
  snail.zig              public API: Font, Atlas, Renderer, TextBatch, Path, ...
  c_api.zig              C bindings (91 exported functions)
  glyph_emit.zig         glyph → vertex dispatch (plain, COLR, multi-layer)
  font/
    ttf.zig              TrueType parser (cmap, glyf, loca, hhea, hmtx, kern, COLR)
    opentype.zig         OpenType shaper (GSUB ligatures, GPOS kerning)
    harfbuzz.zig         HarfBuzz integration (optional)
    snail_file.zig       .snail preprocessed format
  math/
    bezier.zig           quadratic/cubic Bezier curves, bounding boxes
    vec.zig              Vec2, Mat4, Transform2D
    roots.zig            quadratic equation solver
  render/
    pipeline.zig         OpenGL state (GL 3.3 / 4.4 persistent mapped)
    vulkan_pipeline.zig  Vulkan state (optional)
    shaders.zig          GLSL 330 vertex + fragment shaders
    curve_texture.zig    RGBA16F curve control point packing
    band_texture.zig     RG16UI spatial band subdivision
    vertex.zig           glyph quad vertex generation
    sprite_pipeline.zig  sprite rendering pipeline
    sprite_vertex.zig    sprite quad vertex generation
  extra/
    cpu_renderer.zig     software rasterizer (same atlas data, no GPU)
  profile/
    timer.zig            comptime-gated CPU timers
include/
  snail.h                C header
```

## Thread safety

| Type | Rule |
|------|------|
| `Font` | Immutable after init. Safe for concurrent reads. |
| `Atlas` | Immutable after creation. Safe for concurrent reads. |
| `TextBatch`, `PathBatch`, `SpriteBatch` | Caller-owned buffers. Multiple batches reading the same atlas from different threads is safe. |
| `PathPicture` | Immutable after freeze. Safe for concurrent reads. |
| `Renderer` | Single-threaded. Must be called from the GL/Vulkan context thread. |

Typical pattern: load fonts and build atlases on any thread, upload and draw on the render thread, build batches on any thread(s) into thread-local buffers.

## Status and roadmap

snail is used in development but is not yet stable. Current limitations:

- OpenType shaping is limited to GSUB type 4 (ligatures) and GPOS type 2 (pair positioning). Complex scripts require `-Dharfbuzz=true`.
- No CFF/CFF2 support (TrueType outlines only).
- No variable fonts.
- One renderer per process (pipeline state is module-scoped, tied to the GL/Vulkan context).
- C API is GL-only (no Vulkan bindings yet).

Planned:
- DynamicAtlas / AtlasCache for high-churn glyph sets.
- Vulkan C API parity.

## License

MIT

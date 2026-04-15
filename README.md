# snail

GPU font rendering via direct Bézier curve evaluation. A Zig implementation of the [Slug algorithm](https://sluglibrary.com/).

![snail rendering text at multiple sizes](assets/screenshot_sizes.png)

Text is rendered by evaluating quadratic Bézier curves per-pixel in a fragment shader. No texture atlases, no signed distance fields, no pre-rasterization. Glyphs are resolution-independent and render correctly at any size, rotation, or perspective transform.

## Based on

This is an independent implementation of the algorithm described in:

- Eric Lengyel, ["GPU-Centered Font Rendering Directly from Glyph Outlines"](https://jcgt.org/published/0006/02/02/), JCGT 2017
- Eric Lengyel, ["A Decade of Slug"](https://terathon.com/blog/decade-slug.html), 2026
- [Reference HLSL shaders](https://github.com/EricLengyel/Slug) (MIT / Apache-2.0)
- [Sluggish](https://github.com/mightycow/Sluggish) reference C implementation (Unlicense)

The Slug patent (US 10,373,352) was [dedicated to the public domain](https://terathon.com/blog/decade-slug.html) on March 17, 2026 via terminal disclaimer filed with the USPTO. This implementation is original code, not derived from the Slug Library product. Licensed under MIT.

## Build

Requires [Nix](https://nixos.org/) (provides Zig 0.16, GLFW, OpenGL):

```sh
nix-shell
zig build run            # interactive demo
zig build test           # unit tests
zig build bench          # benchmarks
zig build -Dprofile=true   # enable profiling instrumentation
zig build -Dharfbuzz=true  # enable HarfBuzz text shaping
zig build valgrind         # run tests under valgrind
```

Demo controls: `Z`/`X` zoom, `R` rotate, `S` stress test, `L` cycle subpixel order (none → RGB → BGR → VRGB → VBGR).

## Usage

```zig
const snail = @import("snail");

// Parse font (one-time)
var font = try snail.Font.init(allocator, ttf_bytes);
defer font.deinit();

// Build GPU textures for desired glyphs (one-time)
var atlas = try snail.Atlas.initAscii(allocator, &font, &snail.ASCII_PRINTABLE);
defer atlas.deinit();

// Create renderer and upload atlas (requires GL 3.3+ context)
var renderer = try snail.Renderer.init();
defer renderer.deinit();
renderer.uploadAtlas(&atlas);

// Build a vertex batch (per-frame for dynamic text, or once for static)
var buf: [5000 * snail.FLOATS_PER_GLYPH]f32 = undefined;
var batch = snail.Batch.init(&buf);
_ = batch.addString(&atlas, &font, "Hello, world!", x, y, 48.0, .{ 1, 1, 1, 1 });

// Draw
renderer.draw(batch.slice(), mvp, viewport_w, viewport_h);
```

### Performance model

| Operation | Frequency | Cost |
|-----------|-----------|------|
| `Font.init` | Once per font | ~1 us |
| `Atlas.init` | Once per glyph set | ~500 us for 95 ASCII glyphs |
| `Renderer.uploadAtlas` | Once (or on atlas rebuild) | GPU texture upload |
| `Batch.addString` | Per-frame (dynamic) or once (static) | ~0.5 us per glyph |
| `Renderer.draw` | Per-frame | Single draw call per batch |

For static UI text, build the `Batch` once and call `Renderer.draw` each frame with the same `batch.slice()`. The vertex buffer is caller-owned and zero-allocation.

For dynamic text (input fields, counters, chat), rebuild the `Batch` each frame. At ~0.5 us/glyph, laying out 1000 glyphs costs ~0.5 ms.

### Dynamic glyph loading

Add glyphs to an existing atlas at runtime without rebuilding from scratch:

```zig
const new_codepoints = [_]u32{ 0x00E9, 0x00F1, 0x00FC }; // é, ñ, ü
if (try atlas.addCodepoints(&new_codepoints)) {
    renderer.uploadAtlas(&atlas); // re-upload only if new glyphs were added
}
```

### Word wrapping

```zig
_ = batch.addStringWrapped(&atlas, &font, paragraph, x, y, 14.0, max_width, 20.0, color);
```

### Fill rule

Supports both non-zero winding (TrueType default) and even-odd fill rules:

```zig
renderer.setFillRule(.even_odd);
```

### Subpixel rendering

`renderer.setSubpixelOrder(.rgb)` enables LCD subpixel antialiasing. The fragment shader evaluates coverage at three sub-pixel offsets, tripling effective resolution in the subpixel axis. Most visible on standard-DPI displays at small font sizes.

All five orders are supported: `.none` (off), `.rgb`, `.bgr`, `.vrgb`, `.vbgr`. The demo auto-detects the system order via fontconfig and corrects for rotated monitors; the L key cycles orders at runtime.

```zig
renderer.setSubpixelOrder(.rgb);   // horizontal RGB (most common)
renderer.setSubpixelOrder(.vrgb);  // vertical RGB (rotated display)
renderer.setSubpixelOrder(.none);  // disable (OLED/HiDPI)
```

### OpenType shaping

Built-in ligature substitution (GSUB type 4) and kerning (GPOS type 2) with kern table fallback. Sufficient for Latin, Cyrillic, and Greek text.

For complex scripts (Arabic, Devanagari, Thai, etc.), compile with `-Dharfbuzz=true`:

```zig
// HarfBuzz is used automatically by addString() when enabled
_ = try atlas.addGlyphsForText("مرحبا بالعالم"); // discover Arabic glyphs
renderer.uploadAtlas(&atlas);
_ = batch.addString(&atlas, &font, "مرحبا بالعالم", x, y, 32, color);
```

When HarfBuzz is not compiled in, `addString` uses the built-in shaper. The `addShaped()` API is always available for callers who use an external shaper.

### C API

`#include "snail.h"` — see [`include/snail.h`](include/snail.h) for the full interface.

```c
#include "snail.h"

SnailFont *font;
snail_font_init(ttf_data, ttf_len, &font);

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

Pass a `SnailAllocator` to `snail_atlas_init` for custom allocation, or `NULL` for libc malloc/free.

### Thread safety

| Type | Thread model |
|------|-------------|
| `Font` | Immutable after init. Safe for concurrent reads from any thread. |
| `Atlas` | Immutable after init. Safe for concurrent reads from any thread. |
| `Batch` | Operates on caller-owned buffers. Multiple batches reading the same Atlas from different threads is safe. |
| `Renderer` | **GL thread only.** `init`, `uploadAtlas`, `draw`, `setSubpixel` must all be called from the thread with the active GL context. |

Typical game pattern:
1. **Load thread**: `Font.init` + `Atlas.init` (CPU-only, no GL needed)
2. **GL thread**: `Renderer.uploadAtlas` (once), `Renderer.draw` (per frame)
3. **Any thread(s)**: `Batch.addString` into thread-local buffers, submit to GL thread for drawing

Static text (HUD, menus): build the `Batch` once, reuse the vertex slice every frame. The draw call is just a VBO upload + single `glDrawArrays`.

## Architecture

```
src/
  snail.zig              public API: Font, Atlas, Renderer, Batch
  c_api.zig              C bindings (extern functions)
  font/ttf.zig           TrueType parser (head, maxp, cmap, glyf, loca, hhea, hmtx, kern)
  font/opentype.zig      OpenType shaper (GSUB ligatures, GPOS kerning)
  font/harfbuzz.zig      HarfBuzz integration (optional, -Dharfbuzz=true)
  font/snail_file.zig    .snail preprocessed format (zero-parse loading)
  math/                  Vec2, Mat4, QuadBezier, quadratic root solver
  render/
    shaders.zig          GLSL 330 vertex + fragment shaders (Slug algorithm)
    pipeline.zig         OpenGL state management
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

4. **Vertex shader**: apply dynamic dilation (expand glyph quads by ~0.5px along normals using the inverse Jacobian of the MVP transform) to prevent dropped pixels at edges.

5. **Fragment shader**: for each pixel, determine its band, fetch the relevant curves, cast horizontal and vertical rays, solve the resulting quadratic equations, classify roots via control point sign patterns (the core Slug technique), accumulate a winding number, and convert to fractional coverage for antialiasing.

Curves within each band are sorted by descending maximum coordinate, enabling early exit when no further curves can affect the pixel.

## Benchmarks

`zig build bench` — internal microbenchmarks. `zig build bench-compare` — head-to-head vs FreeType.

### snail vs FreeType (`zig build bench-compare`)

NotoSans-Regular.ttf, 95 ASCII glyphs, ReleaseFast:

| Metric | snail | FreeType |
|--------|-------|----------|
| Font load | 2 us | 31 us |
| Glyph prep (1 size) | 1,665 us | 1,319 us |
| Glyph prep (7 sizes) | **1,665 us** | 8,508 us |
| Layout: 13-char string | **1.0 us** | 101 us |
| Layout: 53-char sentence | **4.4 us** | 506 us |
| Layout: 175-char paragraph | **15.5 us** | 1,804 us |
| Layout: paragraph × 7 sizes | **105 us** | 13,060 us |
| Texture memory | 96 KB (all sizes) | 63 KB (1 size) / 525 KB (7 sizes) |
| Re-rasterize for new size | **0** (resolution-independent) | ~1,200 us per size |

Layout is **100–124x faster**: snail reads pre-parsed metrics; FreeType calls `FT_Load_Glyph` per character through the hinting engine.

### End-to-end rendering (`zig build bench-headless`)

**Methodology**: fully headless — no display, no window system involvement in the measured path.

- **OpenGL**: hidden GLFW window (`GLFW_VISIBLE=false`) with a 1280×720 FBO. Each frame renders into the FBO, then calls `glFinish` to wait for GPU completion before timing the next frame. The window never appears on screen; GLFW is used only to obtain a GL context.
- **Vulkan**: no window, no surface, no swapchain. Renders into a `VkImage` (`VK_FORMAT_R8G8B8A8_UNORM`) allocated in device memory. `vkQueueWaitIdle` after each submit ensures full CPU+GPU frame time is measured with no pipelining. This is a conservative lower bound — real applications pipeline CPU and GPU work across frames.

Both backends render 2000 frames per scenario at 1280×720, ReleaseFast. Frame time = wall time / 2000.

**Static**: vertex buffer built once, reused every frame — simulates a game HUD or static menu.  
**Dynamic**: vertex buffer rebuilt from glyph metrics every frame — simulates chat, debug overlay, or any text that changes each frame.

#### OpenGL 4.4 (persistent mapped)

| Scenario | Glyphs | Static FPS | Static frame | Dynamic FPS | Dynamic frame |
|----------|--------|-----------|-------------|------------|--------------|
| Game HUD (2 lines) | 45 | 40,008 | 25.0 us | 41,794 | 23.9 us |
| Multi-size (6 sizes) | 270 | 25,473 | 39.3 us | 25,608 | 39.1 us |
| Body text (6 paragraphs) | 978 | 14,836 | 67.4 us | 8,891 | 112.5 us |
| Torture (fill screen) | 4,075 | 4,901 | 204.0 us | 2,212 | 452.1 us |
| Arabic (12 lines) | 228 | 29,875 | 33.5 us | 25,913 | 38.6 us |
| Devanagari (12 lines) | 132 | 35,880 | 27.9 us | 36,706 | 27.2 us |
| Game UI (3 fonts) | 54 | 39,856 | 25.1 us | 39,408 | 25.4 us |
| Chat (6 msgs, 4 fonts) | 104 | 36,193 | 27.6 us | 36,927 | 27.1 us |
| Multi-font torture (24 lines) | 510 | 21,700 | 46.1 us | 16,724 | 59.8 us |

#### Vulkan (offscreen, per-frame sync)

| Scenario | Glyphs | Static FPS | Static frame | Dynamic FPS | Dynamic frame |
|----------|--------|-----------|-------------|------------|--------------|
| Game HUD (2 lines) | 45 | 21,455 | 46.6 us | 21,392 | 46.7 us |
| Multi-size (6 sizes) | 270 | 15,156 | 66.0 us | 14,971 | 66.8 us |
| Body text (6 paragraphs) | 978 | 9,066 | 110.3 us | 6,630 | 150.8 us |
| Torture (fill screen) | 4,075 | 3,409 | 293.3 us | 1,998 | 500.5 us |
| Arabic (12 lines) | 228 | 16,345 | 61.2 us | 15,757 | 63.5 us |
| Devanagari (12 lines) | 132 | 18,191 | 55.0 us | 18,199 | 54.9 us |
| Game UI (3 fonts) | 54 | 19,785 | 50.5 us | 17,550 | 57.0 us |
| Chat (6 msgs, 4 fonts) | 104 | 18,449 | 54.2 us | 15,089 | 66.3 us |
| Multi-font torture (24 lines) | 510 | 12,355 | 80.9 us | 7,581 | 131.9 us |

### Other GPU font renderers

| Project | Language | GPU API | Notes |
|---------|----------|---------|-------|
| [Slug Library](https://sluglibrary.com/) | C++ | Vulkan/D3D/GL/Metal | Commercial. The reference implementation (10 years of optimization). |
| [slug_wgpu](https://github.com/santiagosantos08/slug_wgpu) | Rust | wgpu | FOSS Slug implementation. |
| [gpu-font-rendering](https://github.com/GreenLightning/gpu-font-rendering) | C++ | OpenGL | Dobbie/Lengyel technique. |
| [Pathfinder](https://github.com/pcwalton/pathfinder) | Rust | GL/Metal | General vector graphics GPU rasterizer. |
| **snail** | **Zig** | **OpenGL 3.3+ / Vulkan** | **This project. C API. MIT licensed.** |

## Packaging

### Arch Linux

```sh
cd pkg/arch && makepkg -si
```

Installs `libsnail.so`, `libsnail.a`, and `snail.h` to `/usr/lib` and `/usr/include`.

## License

MIT. See [LICENSE](LICENSE).

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
zig build -Dprofile=true # enable profiling instrumentation
```

Demo controls: `Z`/`X` zoom, `R` rotate, `S` stress test, `L` toggle subpixel rendering.

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

### Subpixel rendering

`renderer.setSubpixel(true)` enables LCD subpixel antialiasing. The fragment shader evaluates coverage at three horizontal offsets (one per RGB subpixel), tripling effective horizontal resolution. Most visible on standard-DPI displays at small font sizes.

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
  math/                  Vec2, Mat4, QuadBezier, quadratic root solver
  render/
    shaders.zig          GLSL 330 vertex + fragment shaders (Slug algorithm)
    pipeline.zig         OpenGL state management
    curve_texture.zig    RGBA32F curve control point texture
    band_texture.zig     RG16UI spatial band subdivision texture
    vertex.zig           glyph quad vertex generation (5x vec4 per vertex)
  profile/timer.zig      comptime-gated CPU timers (zero overhead when disabled)
include/
  snail.h                C header
```

### How it works

1. **TTF parsing**: extract glyph outlines as quadratic Bézier curves from TrueType font files.

2. **Curve texture**: pack all control points into an RGBA32F texture. Each curve occupies two texels: `(p1.x, p1.y, p2.x, p2.y)` and `(p3.x, p3.y, -, -)`.

3. **Band texture**: subdivide each glyph's bounding box into horizontal and vertical bands. Each band stores which curves intersect it. This reduces per-pixel work from O(all curves) to O(curves in band).

4. **Vertex shader**: apply dynamic dilation (expand glyph quads by ~0.5px along normals using the inverse Jacobian of the MVP transform) to prevent dropped pixels at edges.

5. **Fragment shader**: for each pixel, determine its band, fetch the relevant curves, cast horizontal and vertical rays, solve the resulting quadratic equations, classify roots via control point sign patterns (the core Slug technique), accumulate a winding number, and convert to fractional coverage for antialiasing.

Curves within each band are sorted by descending maximum coordinate, enabling early exit when no further curves can affect the pixel.

## Benchmarks

`zig build bench` — internal microbenchmarks. `zig build bench-compare` — head-to-head vs FreeType.

### snail vs FreeType

NotoSans-Regular.ttf, 73 ASCII glyphs, ReleaseFast:

| Metric | snail (GPU Slug) | FreeType (CPU) |
|--------|-----------------|----------------|
| Font load | 1 us | 31 us |
| Glyph prep (73 glyphs) | 1,377 us (all sizes) | 1,265 us (48px only) |
| Layout throughput | **1.2 us/string** | 516 us/string |
| Texture memory | 96 KB (all sizes) | 56 KB (single size) |
| Re-rasterize for new size | **0** (resolution-independent) | ~1,000 us per size |

Layout is **430x faster** because snail reads metrics from parsed data while FreeType must load each glyph via its hinting engine. snail's glyph preparation is a one-time cost that covers all sizes — FreeType must re-rasterize the entire glyph set for each pixel size (~1ms per size).

### End-to-end rendering (`zig build bench-headless`)

Headless FBO, 1280x720, 2000 frames per scenario, ReleaseFast:

| Scenario | Glyphs | Static FPS | Static frame | Dynamic FPS | Dynamic frame |
|----------|--------|-----------|-------------|------------|--------------|
| Game HUD (2 lines) | 45 | 279,622 | 3.6 us | 205,414 | 4.9 us |
| Multi-size (6 sizes) | 270 | 98,689 | 10.1 us | 53,018 | 18.9 us |
| Body text (6 paragraphs) | 978 | 30,249 | 33.1 us | 15,707 | 63.7 us |
| Torture (fill screen) | 4,075 | 8,121 | 123.1 us | 3,899 | 256.5 us |

**Static**: pre-built vertex buffer, draw call only (game HUD, menus).
**Dynamic**: rebuild vertices + draw every frame (chat, editor, debug text).

### Other GPU font renderers

| Project | Language | GPU API | Notes |
|---------|----------|---------|-------|
| [Slug Library](https://sluglibrary.com/) | C++ | Vulkan/D3D/GL/Metal | Commercial. The reference implementation (10 years of optimization). |
| [slug_wgpu](https://github.com/santiagosantos08/slug_wgpu) | Rust | wgpu | FOSS Slug implementation. |
| [gpu-font-rendering](https://github.com/GreenLightning/gpu-font-rendering) | C++ | OpenGL | Dobbie/Lengyel technique. |
| [Pathfinder](https://github.com/pcwalton/pathfinder) | Rust | GL/Metal | General vector graphics GPU rasterizer. |
| **snail** | **Zig** | **OpenGL 3.3** | **This project. C API. MIT licensed.** |

## Packaging

### Arch Linux

```sh
cd pkg/arch && makepkg -si
```

Installs `libsnail.so`, `libsnail.a`, and `snail.h` to `/usr/lib` and `/usr/include`.

## License

MIT. See [LICENSE](LICENSE).

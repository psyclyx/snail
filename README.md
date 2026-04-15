# snail

GPU font rendering via direct Bézier curve evaluation. A Zig implementation of the [Slug algorithm](https://sluglibrary.com/).

![snail rendering text at multiple sizes](assets/screenshot_sizes.png)

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
zig build run                       # interactive demo (OpenGL)
zig build run -Dvulkan=true         # Vulkan backend
zig build run -Dharfbuzz=true       # full OpenType shaping (Arabic, Devanagari, Thai…)
zig build test                      # unit tests
zig build bench                     # GPU frame-time benchmarks
zig build install --release=fast    # install libsnail + header to zig-out/
```

Requires [Zig 0.16](https://ziglang.org/download/), GLFW, OpenGL, and pkg-config. Vulkan loader + headers and shaderc are only needed with `-Dvulkan=true`.

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

Demo controls: `Z`/`X` zoom, `R` rotate, `S` stress test, `L` cycle subpixel order (none → RGB → BGR → VRGB → VBGR).

## Usage

```zig
const snail = @import("snail");

// Parse font (one-time)
var font = try snail.Font.init(ttf_bytes);
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

// Draw (call beginFrame() once per frame when sharing a GL context with other renderers)
renderer.beginFrame();
renderer.draw(batch.slice(), mvp, viewport_w, viewport_h);
```

### Performance model

| Operation | Frequency | Cost |
|-----------|-----------|------|
| `Font.init` | Once per font | ~1 us |
| `Atlas.init` | Once per glyph set | ~500 us for 95 ASCII glyphs |
| `Renderer.uploadAtlas` | Once (or on atlas rebuild) | GPU texture upload |
| `Batch.addString` | Per-frame (dynamic) or once (static) | ~0.5 us per glyph |
| `Renderer.beginFrame` | Per-frame | Resets cached GL state (call before `draw` when sharing a GL context) |
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

Pass a `SnailAllocator` to `snail_atlas_init` for custom allocation, or `NULL` for libc malloc/free. The C API is OpenGL-only; Vulkan requires the Zig API.

### Using as a Zig dependency

Add snail to your `build.zig.zon`:

```zig
.dependencies = .{
    .snail = .{ .path = "../snail" },  // or .url for remote
},
```

In your `build.zig`, create a snail module configured for your project. The library only requires OpenGL — no GLFW, no Vulkan:

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
snail_mod.linkSystemLibrary("gl", .{});
snail_mod.addImport("vulkan_shaders", vk_stub);
root_module.addImport("snail", snail_mod);
```

The caller must have an active OpenGL 3.3+ context before calling `Renderer.init()`. snail manages its own GL state (shader programs, VAOs, textures, blend/depth) per draw call. If other renderers share the GL context, call `renderer.beginFrame()` once per frame before `draw()` so snail re-binds its cached state.

### Thread safety

| Type | Thread model |
|------|-------------|
| `Font` | Immutable after init. Safe for concurrent reads from any thread. |
| `Atlas` | Immutable after init. Safe for concurrent reads from any thread. |
| `Batch` | Operates on caller-owned buffers. Multiple batches reading the same Atlas from different threads is safe. |
| `Renderer` | **Single-thread per context.** GL: all calls must be on the thread with the active GL context. Vulkan: all calls must be externally synchronized. |

Typical game pattern:
1. **Load thread**: `Font.init` + `Atlas.init` (CPU-only, no GPU context needed)
2. **Render thread**: `Renderer.uploadAtlas` (once), `Renderer.draw` (per frame)
3. **Any thread(s)**: `Batch.addString` into thread-local buffers, submit to render thread for drawing

Static text (HUD, menus): build the `Batch` once, reuse the vertex slice every frame. The draw call is a VBO upload + single `glDrawElements`.

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
    gl.zig               OpenGL cImport (shared by pipeline and library consumers)
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
| Game HUD (2 lines) | 45 | 39,690 | 25.2 us | 41,073 | 24.3 us |
| Multi-size (6 sizes) | 270 | 26,337 | 38.0 us | 26,888 | 37.2 us |
| Body text (6 paragraphs) | 978 | 15,170 | 65.9 us | 8,734 | 114.5 us |
| Torture (fill screen) | 4,075 | 12,316 | 81.2 us | 2,145 | 466.3 us |
| Arabic (12 lines) | 228 | 30,072 | 33.3 us | 25,296 | 39.5 us |
| Devanagari (12 lines) | 132 | 37,482 | 26.7 us | 37,184 | 26.9 us |
| Game UI (3 fonts) | 54 | 41,363 | 24.2 us | 41,154 | 24.3 us |
| Chat (6 msgs, 4 fonts) | 104 | 37,305 | 26.8 us | 37,877 | 26.4 us |
| Multi-font torture (24 lines) | 510 | 22,037 | 45.4 us | 15,682 | 63.8 us |

#### Vulkan (offscreen, per-frame sync)

| Scenario | Glyphs | Static FPS | Static frame | Dynamic FPS | Dynamic frame |
|----------|--------|-----------|-------------|------------|--------------|
| Game HUD (2 lines) | 45 | 21,609 | 46.3 us | 21,909 | 45.6 us |
| Multi-size (6 sizes) | 270 | 15,560 | 64.3 us | 15,222 | 65.7 us |
| Body text (6 paragraphs) | 978 | 9,438 | 106.0 us | 6,627 | 150.9 us |
| Torture (fill screen) | 4,075 | 6,513 | 153.5 us | 1,957 | 511.1 us |
| Arabic (12 lines) | 228 | 16,953 | 59.0 us | 15,820 | 63.2 us |
| Devanagari (12 lines) | 132 | 19,005 | 52.6 us | 19,255 | 51.9 us |
| Game UI (3 fonts) | 54 | 20,925 | 47.8 us | 18,013 | 55.5 us |
| Chat (6 msgs, 4 fonts) | 104 | 19,581 | 51.1 us | 15,601 | 64.1 us |
| Multi-font torture (24 lines) | 510 | 12,729 | 78.6 us | 7,428 | 134.6 us |

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

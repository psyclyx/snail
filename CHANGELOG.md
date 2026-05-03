# Changelog

## 0.3.0

### Public API
- Trim public surface: low-level glyph batching, raw `Atlas`/`Font` wrappers,
  vertex sizing constants, paint-tag enums, debug-overlay options and other
  building blocks now live exclusively under `snail.lowlevel`. The top-level
  re-exports were removed.
- Removed dead helpers: `ShapedRun`, `GlyphPlacement`, `Atlas.extendRun`,
  `Atlas.collectMissingGlyphIds`, `Atlas.shapeUtf8`, `TextBatch.addRun`,
  `TextBatch.addStyledRun`, `replaceAtlas`.
- The Slug Library shader-coverage hook (`TextCoverageShader` /
  `TextCoverageRecords` / `TextCoverageBackend`) is unchanged for users who
  embed snail glyph coverage in their own GL pipelines.

### Backend parity
- CPU vs GL/Vulkan output is byte-identical on virtually every pixel; remaining
  drift is bounded to 1 sRGB LSB plus a handful of near-tangent conic outliers.
- CPU sRGB encode now uses the exact IEC 61966-2-1 curve and round-to-nearest
  output rounding instead of an interpolated 4096-entry LUT and truncation.
- `zig build backend-compare -Dvulkan=true` now exercises Vulkan and
  cross-compares Vulkan vs OpenGL alongside CPU.

### Bug fixes
- Vulkan vertex format dropped phantom `hint_*` attributes that referenced
  removed fields and made the Vulkan backend fail to compile.
- Vulkan upload no longer overflows fixed `[256]VkBufferImageCopy` arrays when
  many atlas pages are uploaded at once.
- Wayland `wl_shm` global is now released in `Window.deinit`.
- Fragment shaders pass `(v_count - 1, h_count - 1)` to `evalGlyphCoverage`
  so `band_max` semantics match the CPU and the existing `band_max.y + 1`
  vertical-header offset.
- Conic denominator clamp uses the same epsilon (1/65536) on CPU and GPU.

### Cleanup
- Removed unused `assets/checkerboard_16x16.rgba`.
- `CLAUDE.md` is no longer tracked.
- Library no longer prints to stderr from non-fatal GL/EGL fallback paths.

## 0.2.0

### CPU renderer
- Software rasterizer backend — no GPU required (`-Drenderer=cpu`)
- Interactive CPU demo via `wl_shm` Wayland buffers
- HarfBuzz shaping, COLR emoji, and composite group support in CPU path
- Image paint support in CPU renderer

### Rendering
- Tuned subpixel LCD filter weights to reduce color fringing
- Unified coordinate system to Y-down top-left origin

### Cleanup
- Removed dead `.snail` file format module
- Removed unused helpers and dead GPU timer module

## 0.1.0

Initial release.

### Text rendering
- Direct Bezier curve evaluation in the fragment shader (Slug algorithm) — no texture atlas rasterization
- Subpixel LCD antialiasing (RGB/BGR/VRGB/VBGR) with safe dual-source blending
- Grayscale AA fallback for rotated/scaled text
- HarfBuzz integration for full OpenType shaping (optional, `-Dharfbuzz=true`)
- Built-in GSUB/GPOS shaping and kerning when HarfBuzz is disabled
- COLR/CPAL color emoji support
- Multi-font rendering via texture arrays (no atlas switching overhead)

### Vector paths
- Filled and stroked paths with analytic antialiasing
- Shape primitives: rect, rounded rect, ellipse, arbitrary cubic Bezier paths
- Paint types: solid color, linear gradient, radial gradient, image fill
- Even-odd and non-zero fill rules
- Frozen path pictures for static scene reuse

### API
- Zero-allocation batch API: caller owns vertex buffers, can pre-build static batches
- Shaped-run API for terminal/editor use (caller owns runs, snail owns shaping)
- C API with shared library (`libsnail.so` / `libsnail.a`) and pkg-config
- Zig package module (`zig fetch --save`)
- OpenGL 3.3+ and Vulkan backends

### Performance
- GL 4.4 persistent mapped buffer path when available
- Comptime-gated CPU profiling timers
- Benchmarks against FreeType + HarfBuzz

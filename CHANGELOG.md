# Changelog

## 0.3.0

### Public API
- Replace `Font` + `Atlas` + `FontCollection` with a single immutable
  `TextAtlas` snapshot type. `ensureText` and `ensureShaped` return new
  snapshots; old snapshots stay valid for in-flight readers.
  `FaceSpec` deduplicates fonts that share the same TTF data pointer.
- Redesign rendering around an explicit, layered resource pipeline:
  `Scene` (borrowed command list) → `ResourceSet` (caller-buffered
  manifest) → `PreparedResources` (backend-specific realization) →
  `DrawList` / `PreparedScene` (caller-buffered or owned draw records).
  `renderer.draw(prepared, records, options)` no longer discovers,
  uploads, allocates, or invalidates anything.
- Add `TextBlob` / `TextBlobBuilder` for caller-owned positioned text
  that borrows a specific atlas snapshot, plus
  `PathPicture` / `PathPictureBuilder` as the immutable counterpart for
  vector art.
- Add `TextResolveOptions` with `.none` / `.phase` / `.metrics` stem
  hinting resolved at `PreparedScene` build time.
- New type-erased `Renderer` wrapper plus first-class `GlRenderer`,
  `VulkanRenderer`, and `CpuRenderer` backends.
- Move low-level building blocks (`Font`, `CurveAtlas` / `Atlas`,
  `AtlasPage`, `TextBatch`, `PathBatch`, vertex sizing constants,
  paint-tag enums, debug-overlay options, layer-window helpers, the
  `bezier` and `curve_tex` modules) under `snail.lowlevel`. Top-level
  re-exports of these are gone.
- Remove dead helpers: `ShapedRun`, `GlyphPlacement`,
  `Atlas.extendRun`, `Atlas.collectMissingGlyphIds`, `Atlas.shapeUtf8`,
  `TextBatch.addRun`, `TextBatch.addStyledRun`, `replaceAtlas`.
- Slug Library shader-coverage hook (`TextCoverageShader` /
  `TextCoverageRecords` / `TextCoverageBackend`) for embedding snail
  glyph coverage in caller-owned GL pipelines.
- C API tracks the new model: opaque `SnailTextAtlas`, `SnailScene`,
  `SnailResourceSet`, `SnailPreparedResources`, `SnailPreparedScene`,
  unified `SnailRenderer`. Allocator parameter (NULL → libc) is
  uniform across init/builder calls.

### Backends
- Add a Vulkan backend (`-Dvulkan=true`). SPIR-V shaders compiled at
  build with `glslc`; shares the `PreparedResources` upload model with
  the GL backend. Caller drives frame ownership via
  `vk.beginFrame(.{ .cmd, .frame_index })`.
- Demo selectable backend: `zig build run -Drenderer={gl44,gl33,vulkan,cpu}`.
- Unified renderer interface across CPU, GL, and Vulkan.

### Rendering quality
- Numerically stable quadratic-root solver (Vieta form, sign-aware
  sqrt) shared by CPU, GLSL, and SPIR-V paths.
- Per-axis AA width derived from `dFdx`/`dFdy` so rotated/scaled text
  stays crisp without overdarkening.
- LCD subpixel AA (RGB/BGR/VRGB/VBGR) with dual-source blending; tuned
  filter weights to suppress color fringing.
- Single-pass COLR/CPAL emoji through a layer-info texture.
- Composite path groups for fill+stroke combos; image paint; linear
  and radial gradients with sRGB interpolation; sRGB clear.
- Snap rounded-rect corner-arc endpoints to exact axis-aligned values
  so the line→arc join no longer leaves a faint seam in translucent
  strokes.
- Switch to instanced rendering for text and path quads.

### Backend parity
- CPU vs GL vs Vulkan output is byte-identical on virtually every
  pixel. Remaining drift is bounded to 1 sRGB LSB plus a handful of
  near-tangent conic outliers (4–7 outlier pixels per case in the
  backend-compare scene). Vulkan and GL agree to within one pixel.
- Replace the LUT-based `linearToSrgb` + truncating `@intFromFloat` in
  the CPU renderer with the exact IEC 61966-2-1 curve and
  round-to-nearest output.
- Fragment shaders pass `(v_count - 1, h_count - 1)` to
  `evalGlyphCoverage` so the `band_max` convention matches the CPU and
  the existing `band_max.y + 1` vertical-header offset.
- Conic denominator clamp uses the same epsilon (1/65536) on CPU and
  GPU.
- New `zig build backend-compare` target renders a fixed scene through
  CPU and every available GPU backend and asserts pixel parity.
  `-Dvulkan=true` adds Vulkan and a Vulkan-vs-GL cross-check.

### Bug fixes
- Vulkan vertex format dropped phantom `hint_*` attributes that
  referenced removed fields and made the Vulkan backend fail to
  compile.
- Vulkan staging upload allocates `VkBufferImageCopy` regions per page
  instead of overflowing fixed-size 256-element stack arrays.
- Wayland `Window.deinit` releases its `wl_shm` global.
- Game demo's wall-text material shader was reading 7 vec4s per glyph
  from a samplerBuffer of 60-byte packed instances; widened to 5 vec4s
  per glyph with the correct slot layout so wall text renders again.
- Library no longer prints to stderr from non-fatal GL/EGL fallback
  paths.

### Demos
- 2D demo defaults to grayscale AA. `B` cycles through the detected
  subpixel orderings; the auto-reset on monitor change was dropped so
  dragging the window between displays no longer overrides the user's
  chosen mode.
- Game demo glass panel is slightly more opaque and its text fades to
  match.

### Tooling
- `zig build bench` cross-products AA × hinting per backend for the
  text and multi-script scenes; the (`grayscale`, `subpixel rgb`) ×
  (`unhinted`, `phase`, `metrics`) matrix shows the cost of LCD
  subpixel and stem hinting relative to the grayscale unhinted
  baseline.
- Bench output now includes a `Hardware` section with the CPU model,
  OpenGL renderer / version, and Vulkan device name so pasted results
  carry their context.
- Consolidated benchmark runner (replaces the prior split bench
  binaries).
- README has actual bench output pasted in.
- CI exercises Vulkan, both `-Dharfbuzz=true` and `=false`, and runs
  backend-compare via llvmpipe. Release workflow extracts the
  matching CHANGELOG section and ships a sha256 alongside the
  tarball.

### Cleanup
- Removed unused `assets/checkerboard_16x16.rgba`.
- `CLAUDE.md` is no longer tracked.
- Trimmed ~130 lines of redundant code comments.
- Version markers synced to 0.3.0 across `build.zig.zon`,
  `default.nix`, `snail.pc.in`, and `pkg/arch/PKGBUILD`.

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

# Changelog

## 0.4.0

### Unified draw-submission API

- New `PathDraw` and `TextDraw` value types replace the family of
  per-shape `Scene.add*` overloads. Each carries a resource pointer,
  an optional `Range` sub-selection, and an `[]Override` slice of
  per-instance composition (transform + tint).
- `Scene.addText(*const TextBlob)` / `addTextOptions` /
  `addTextTransformed` / `addTextTransformedOptions` collapse into
  `Scene.addText(TextDraw)`.
- `Scene.addPathPicture` / `addPathPictureTransformed` collapse into
  `Scene.addPath(PathDraw)`.
- New `Range { start, count }` selects a sub-range of a `PathPicture`'s
  shapes or a `TextBlob`'s glyphs.
- New `Override { transform, tint }` composes onto the baked transform
  and multiplies the baked color per GPU instance. `tint` is a
  first-class capability across both text and vector paths.
- `Scene` now owns an `ArenaAllocator` so `addPath` / `addText` can
  copy the caller's `instances` slice into per-scene storage; stack
  arrays are safe.

### Renames

- `PathPicture.Instance` → `PathPicture.Shape`; field `.instances` →
  `.shapes`. Reflects the new vocabulary where "instances" are
  per-call GPU instances and "shapes" are entries in a frozen picture.
- `PathBatch.addPicture` / `addPictureTransformed` /
  `addPictureTransformedFrom` → `PathBatch.addDraw(view, PathDraw,
  override_index, shape_start) !AppendResult`.
- `PathBatch.AppendResult.next_instance` → `next_shape`.
- `TextBlob.appendToBatch` / `appendToBatchFrom` →
  `TextBlob.appendDrawFrom(batch, view, TextDraw, override_index,
  target, scene_to_screen, start_glyph)`.
- New `PathPictureBuilder.shapeCount()` for callers building `Range`
  selections at picture-build time.

### C API

- `snail_scene_add_text_options` and
  `snail_scene_add_path_picture_transformed` keep their export names
  but route through the new draw structs internally; semantics are
  preserved for existing callers.

### CPU renderer threading

- New `snail.ThreadPool`: a tiny caller-owned pool that allocates
  exactly twice (one `[]std.Thread` slice at `init`, freed at
  `deinit`). `dispatch` is heap-free.
- `CpuRenderer.setThreadPool(?*snail.ThreadPool)` opts the software
  backend into scanline-tiled multithreading. Output is byte-identical
  to the single-threaded path; the draw call remains
  allocation-free (`backend-compare` still passes; a parity test in
  `cpu_renderer.zig` asserts byte-equality vs the serial path).
- The pool's mutex / condvar are built directly on Linux futex
  (`std.os.linux.futex_4arg`); no libc dependency is added to snail's
  core. Zig 0.16 ships standalone blocking sync primitives only behind
  `std.Io`, which would re-introduce per-task allocations on the draw
  path. Linux-only for now — porting to other OSes means adding
  futex equivalents in `src/thread_pool.zig`.

### Docs

- README banner switches from a fixed `width` attribute to GitHub's
  `?raw=true` query so the embedded image renders at native
  resolution without HTML sizing.
- Bench output regenerated against the new draw-submission API.

## 0.3.0

### Rendering API rewrite
- New `TextAtlas` immutable snapshot type replaces the previous
  `Font` + `Atlas` + `AtlasHandle` triplet. `ensureText` /
  `ensureShaped` return a new snapshot; the old one stays valid for
  in-flight readers.
- New `FaceSpec` for multi-font fallback chains
  (`{ .data, .weight, .italic, .fallback, .synthetic }`); fonts that
  share a data pointer are deduplicated so synthetic italic / bold
  styles don't double-parse.
- New explicit, layered resource pipeline: `Scene` (borrowed command
  list) → `ResourceSet` (caller-buffered manifest of CPU values) →
  `PreparedResources` (backend-specific realization) → `DrawList`
  (caller-buffered draw records) or `PreparedScene` (owned cache).
  `renderer.draw(prepared, records, options)` no longer discovers,
  uploads, allocates, or invalidates anything.
- New `TextBlob` / `TextBlobBuilder` for caller-owned positioned text
  that borrows a specific atlas snapshot.
- New `ResolveTarget` carries final-target metadata (pixel size,
  subpixel order, fill rule, composite-safety flags); `DrawOptions`
  bundles it with the MVP for a draw call.
- New `TextResolveOptions` with `.none` / `.phase` / `.metrics` stem
  hinting, resolved at `PreparedScene` build time so per-glyph snaps
  are stable for the chosen target.
- New first-class backends: `GlRenderer`, `VulkanRenderer`,
  `CpuRenderer`. The previous unified `Renderer` is now a type-erased
  convenience wrapper over them.
- New `snail.lowlevel` namespace for advanced building blocks
  (`Font`, `CurveAtlas` / `Atlas`, `AtlasPage`, `TextBatch`,
  `PathBatch`, vertex sizing constants, paint-tag enums, debug
  overlays, layer-window helpers, the `bezier` and `curve_tex`
  modules). Top-level re-exports of these are gone.
- New `TextCoverageShader` / `TextCoverageRecords` /
  `TextCoverageBackend` hook for embedding snail glyph coverage in a
  caller-owned GL material shader.
- The C API tracks the new model: opaque `SnailTextAtlas`,
  `SnailScene`, `SnailResourceSet`, `SnailPreparedResources`,
  `SnailPreparedScene`, plus the unified `SnailRenderer`. Allocator
  parameter (NULL → libc) is honored uniformly across init/builder
  calls.
- Removed dead helpers: `ShapedRun`, `GlyphPlacement`,
  `Atlas.extendRun`, `Atlas.collectMissingGlyphIds`,
  `Atlas.shapeUtf8`, `TextBatch.addRun`, `TextBatch.addStyledRun`,
  `replaceAtlas`.

### Backends
- Vulkan backend now actually works. SPIR-V shaders compile at build
  via `glslc` (`-Dvulkan=true`). Shares the `PreparedResources`
  upload model with the GL backend. Caller drives frame ownership via
  `vk.beginFrame(.{ .cmd, .frame_index })`.
- 2D demo gains a `-Drenderer={gl44,gl33,vulkan,cpu}` flag.
- New OpenGL game-style demo (`zig build run-game-demo`): a 3D scene
  with HUD overlays, world-space text on normal-mapped walls (via
  the `TextCoverageShader` hook), and a translucent glass panel.

### Rendering quality
- Numerically stable quadratic-root solver (Vieta form, sign-aware
  sqrt) shared across CPU, GLSL, and SPIR-V paths.
- Per-axis AA width derived from `dFdx` / `dFdy`, keeping rotated /
  scaled text crisp without overdarkening.
- Single-pass COLR/CPAL color emoji rendering through a layer-info
  texture.
- Composite path groups for fill+stroke combinations.
- Snap rounded-rect / ellipse corner-arc endpoints to exact
  axis-aligned values so the line→arc join no longer leaves a faint
  seam in translucent strokes.
- Switch text and vector path quads to instanced rendering.

### Backend parity
- CPU vs GL vs Vulkan output is byte-identical on virtually every
  pixel. Remaining drift is bounded to 1 sRGB LSB plus a handful of
  near-tangent conic outliers (4–7 outlier pixels per case in the
  backend-compare scene). Vulkan and GL agree to within one pixel.
- CPU sRGB encode now uses the exact IEC 61966-2-1 curve and
  round-to-nearest output, replacing the interpolated 4096-entry LUT
  and truncating `@intFromFloat`.
- Fragment shaders pass `(v_count - 1, h_count - 1)` to
  `evalGlyphCoverage` so the `band_max` convention matches the CPU
  and the existing `band_max.y + 1` vertical-header offset.
- Conic denominator clamp uses the same epsilon (1/65536) on CPU and
  GPU.
- New `zig build backend-compare` target renders a fixed scene
  through CPU and every available GPU backend and asserts pixel
  parity. `-Dvulkan=true` adds Vulkan and a Vulkan-vs-GL cross-check.

### Bug fixes
- Vulkan vertex format dropped phantom `hint_*` attributes that
  referenced removed fields and made the Vulkan backend fail to
  compile.
- Vulkan staging upload allocates `VkBufferImageCopy` regions per
  page instead of overflowing fixed-size 256-element stack arrays.
- Wayland `Window.deinit` now releases its `wl_shm` global.
- Library no longer prints to stderr from non-fatal GL/EGL fallback
  paths.

### Demos
- The 2D demo defaults to grayscale AA. `B` cycles through the
  detected subpixel orderings; the auto-reset on monitor change was
  dropped so dragging the window between displays no longer
  overrides the chosen mode. `H` cycles hinting modes.
- Demo screenshot regenerated for the new look.

### Tooling
- Benchmark runner consolidated into a single `zig build bench`
  target (`bench-compare`, `bench-headless`, `bench-suite`,
  `bench-all`, `screenshot-cpu` are gone).
- Bench cross-products AA × hinting per backend for the text and
  multi-script scenes; the (`grayscale`, `subpixel rgb`) ×
  (`unhinted`, `phase`, `metrics`) matrix shows the cost of LCD
  subpixel and stem hinting relative to the grayscale unhinted
  baseline.
- Bench output begins with a `Hardware` section reporting the CPU
  model, OpenGL renderer/version, and Vulkan device name so pasted
  results carry their context.
- README ships actual pasted bench output (no more "run this to see
  numbers").
- CI exercises Vulkan, both `-Dharfbuzz=true` and `=false`, and runs
  `backend-compare` via llvmpipe. Release workflow extracts the
  matching CHANGELOG section into the GitHub release notes and ships
  a sha256 alongside the tarball.

### Cleanup
- Removed unused `assets/checkerboard_16x16.rgba`.
- Removed `src/screenshot_cpu.zig` (`zig build backend-compare`
  covers the same ground).
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

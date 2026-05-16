# Changelog

## Unreleased

### Changed

- Replaced the resolve-strategy enum with an explicit `Resolve` contract on
  `ResolveTarget`: `.direct` draws into the attachment, while `.linear` carries
  `LinearResolve.backdrop`, `LinearResolve.region`, and
  `LinearResolve.intermediate_format`.
- Renamed `TargetEncoding.framebuffer` / `pixels` to `attachment` /
  `stored_pixels`, and renamed the compatibility preset to
  `TargetEncoding.srgb_pixels_on_linear_attachment`.
- The C API now mirrors the resolve contract with `resolve_kind`,
  `resolve_backdrop`, `resolve_region`, `resolve_intermediate_format`, and
  `attachment_encoding` / `stored_pixel_encoding` fields.
- Removed legacy Zig compatibility aliases from the coverage API. Use
  `CoverageShader`, `CoverageBackend`, `coverageBackend`, `bindResources`,
  `drawCoverage`, `drawVertices`, and `TextCoverageRecords.buildLocal`.
- Removed the unused `snail.backend.*` namespace. Use `BackendKind` and the
  direct `GlRenderer`, `VulkanRenderer`, and `CpuRenderer` types.

### Fixed

- GL `.linear` resolves can now seed their linear intermediate from the caller's
  existing sRGB pixels before drawing Snail content, then overwrite the target
  with one final sRGB encode pass. This keeps Snail composition gamma-correct
  over pre-existing contents in linear-format attachments rather than blending
  encoded edge pixels in storage space.
- GL and CPU linear resolves now support explicit target, clear, transparent,
  and don't-care backdrops plus full-target or pixel-rect resolve regions. GL
  can use RGBA16F or RGBA32F intermediates; CPU follows the same contract in its
  RGBA8 buffer. Vulkan still reports `error.UnsupportedResolve` for `.linear`.

## 0.8.0 - 2026-05-15

### Added

- `ResolveTarget.resolve_strategy` / `ResolveStrategy` selects direct rendering
  or a linear intermediate resolve. The GL backend now supports
  `.linear_intermediate` for `TargetEncoding.srgb_pixels_on_linear_framebuffer`,
  rendering Snail content into a linear RGBA16F target before encoding sRGB
  pixels into the caller's linear-format framebuffer. The CPU backend uses its
  existing linear decode/blend/encode path for the same strategy; Vulkan reports
  `error.UnsupportedResolveStrategy` until its caller-owned render-pass contract
  grows an intermediate-resolve seam.
- The C API mirrors the resolve strategy with
  `SnailResolveTarget.resolve_strategy` and `SNAIL_RESOLVE_*` constants.

### Changed

- CPU direct rendering to `TargetEncoding.srgb_pixels_on_linear_framebuffer`
  now matches GL/Vulkan semantics: it reads destination bytes as storage values,
  encodes the premultiplied source into sRGB storage space, blends there, and
  writes the storage value directly. Use `.linear_intermediate` when CPU output
  should stay gamma-correct for overlapping Snail draws.
- The demos now request `.linear_intermediate` when presenting sRGB pixels on a
  linear framebuffer for backends that support it, keeping the CPU demo aligned
  with GL/Vulkan output.

## 0.7.0 - 2026-05-14

### Added

- Text blobs can now use the full `Paint` union, including linear/radial
  gradients and image paints, with the same paint-record path used by vector
  draws.
- The demo and benchmark suite now include a rich-text scene that exercises
  mixed styles and painted text runs.
- C callers now construct renderers through backend-specific headers:
  `snail_cpu.h`, `snail_gl.h`, and `snail_vulkan.h`. The C API exposes CPU
  renderer construction/rebuffering, explicit GL/Vulkan constructors, and
  generated backend constants/handles.
- Nix packaging is split into `nix/snail.nix` for the library and
  `nix/snail-demo.nix` for the interactive demo, both wired through
  `callPackage` and sharing backend option handling.
- The interactive demo can cycle the enabled CPU/OpenGL/Vulkan renderers at
  runtime while sharing one Wayland window.

### Changed

- The Zig public surface is now organized as a small facade in `root.zig` with
  domain modules (`text`, `paint`, `scene`, `resources`, `render`, `coverage`,
  etc.) and top-level aliases retained for existing callers.
- Backend build options were cleaned up. OpenGL, Vulkan, CPU rendering,
  HarfBuzz, and the C API are enabled by default; backend-disabled
  combinations are covered by CI.
- Renderer handles now carry an explicit backend kind and borrowed backend
  state. Scheduled uploads use explicit completion tokens instead of implicit
  backend synchronization.
- Text coverage hooks are backend-neutral through `CoverageShader`,
  `CoverageBackend`, and typed GL/Vulkan coverage programs; legacy text
  coverage aliases still point at the new names.
- Resource upload staging now separates persistent and scratch allocation more
  consistently, and fixed upload slot limits were removed.
- The legacy generic C renderer constructor was removed; include the desired
  backend header and call that backend's constructor instead.

### Fixed

- Gradient and image paint coordinates for text draws now map correctly, and
  text paint records route through the backend paint path instead of the solid
  text-only shader path.
- `TextBlob.rebound` now keeps rebound storage persistent across atlas
  extension.
- The demo no longer unmaps the shared Wayland window when switching to the CPU
  renderer.
- Backend staging lists now use caller-provided upload scratch storage instead
  of longer-lived allocation.

### Docs and tooling

- README benchmarks were deduplicated and refreshed from `zig build bench` on
  the documented machine.
- README API and architecture docs were refreshed for the facade/domain-module
  split and backend-specific C constructors.
- CI now checks generated C API sync, default/no-HarfBuzz/backend-disabled
  builds, demo builds, backend pixel comparison, and Nix library/demo
  derivations.

## 0.6.1 - 2026-05-13

### Fixed

- `PendingResourceUpload` now stores the erased renderer handle by value
  instead of keeping a pointer to a temporary wrapper. Typed GL and Vulkan
  `beginResourceUpload` callers no longer risk stale vtable reads that could
  make resource uploads fail with `error.UnsupportedRenderer`.

## 0.6.0 - 2026-05-12

### Fixed

- GL and Vulkan atlas uploads now accept empty `TextAtlas` snapshots.
  Uploading a resource set that contains zero-page atlases no longer reads
  `page(0)` while creating texture arrays; all-empty uploads keep prepared
  atlas views valid and otherwise no-op until glyph pages are added.
- GL and Vulkan uploads now pack immutable `PathPicture` atlases exactly
  instead of reserving growable 4-layer texture-array capacity for every
  one-page picture. `TextAtlas` uploads keep growable capacity for snapshot
  extension.
- `PathPicture` paint-info tables now use the narrowest width needed by the
  picture, and GL/Vulkan layer-info uploads allocate the max width required by
  the current resource set instead of forcing every tiny path picture to pay
  for a 4096-texel row.
- GL and Vulkan image-array uploads now pack immutable `Image` resources
  exactly instead of reserving a minimum 4-layer array for small image sets.
- Selecting the Vulkan demo renderer now enables the Vulkan backend by default,
  so `zig build demo -Drenderer=vulkan` builds without a separate
  `-Dvulkan=true`.
- GL, Vulkan, CPU, and game-demo material grayscale text now use the same
  derivative-length AA footprint, and the GL/material text paths now pass
  glyph band maxima in the same order as the shared evaluator.
- The GL demo platform now preserves the EGL surface colorspace it requested
  when reporting presentation encoding. This avoids treating an sRGB EGL
  default framebuffer as linear and double-encoding shader output.

### Added

- `ResourceFootprint` plus allocation-free upload footprint queries on
  `TextAtlas`, `PathPicture`, `Image`, `ResourceSet`, and low-level
  `CurveAtlas`. Footprints report used source bytes and allocated backend
  texture bytes by curve, band, layer-info, and image class.
- `ResourceSet.putTextAtlasOptions` and `putPathPictureOptions` expose the
  atlas upload capacity policy (`.exact` or `.growable`) per entry while the
  existing `putTextAtlas` / `putPathPicture` calls keep their defaults.
- `PathPictureBuilder` shape marks produce allocation-free `Range` values for
  drawing subsets of a larger immutable path picture; the C API exposes the
  same marks and path-picture range submission calls.
- `ResourceUploadPlan.upload_footprint` exposes the full planned backend
  allocation footprint; `upload_bytes` is now the footprint's allocated total
  for budget checks.
- The C API now exposes resource upload footprints plus explicit atlas capacity
  options for text atlas and path picture resource-set entries.
- `PreparedResourceRetirementQueue` is a caller-owned queue for explicit
  deferred retirement of prepared backend resources.
- `PixelGrid` exposes allocation-free logical-to-backing-pixel snapping
  primitives for callers that want text/layout origins or lengths aligned to
  the actual framebuffer grid.
- `CoverageTransfer` exposes an explicit per-target analytic coverage exponent
  for GL, Vulkan, CPU, and custom GL text-coverage shaders; the C API mirrors it
  with `SnailResolveTarget.coverage_exponent`.
- Demo platform backends now expose `presentation.Info`, including logical
  size, framebuffer size, integer Wayland buffer scale, framebuffer color
  encoding, and resampling status.

### Changed

- Source files are now split by ownership: `src/snail` contains only the
  library, `src/snail/renderer/{gl,vulkan,cpu}.zig` contains the renderer
  backends, and demo/window/offscreen platform code lives under
  `src/demo/platform` as demo-private support code.
- `backend-compare -Dvulkan=true` now applies a dedicated GL-vs-Vulkan
  consistency check. GL and Vulkan may differ by at most 2 LSB per channel;
  the looser near-tangent CPU-vs-GPU outlier budget no longer applies to that
  pair.
- `ResolveTarget` now takes an explicit `TargetEncoding` with separate
  framebuffer and stored-pixel encodings. This replaces the public
  `output_srgb` flag and the renderer-global sRGB-format target knobs; GL,
  Vulkan, and CPU draws now derive shader/CPU encoding behavior from the
  per-draw target.
- The main demo now snaps text layout with `PixelGrid` and opts into a
  per-target `CoverageTransfer` instead of relying on implicit renderer tuning.
- The main and game demos now derive `ResolveTarget.encoding` from explicit
  presentation data. The CPU Wayland demo buffer now follows framebuffer size
  and buffer-scale changes instead of staying at logical window size.
- The CPU Wayland demo now double-buffers wl_shm presentation buffers and
  paces presentation with compositor frame callbacks, avoiding render-ahead
  and busy-buffer reuse during interactive panning.
- The main demo now reuses draw-list segment scratch instead of allocating it
  every frame.
- `PathPictureBuilder.freeze` now requires explicit persistent and scratch
  allocators. Scratch memory is used only while compiling the immutable picture;
  `PathPicture` owns only the persistent allocations after `freeze` returns.
- Low-level curve and band texture builders now take separate data and scratch
  allocators, matching the same explicit memory model.
- The C `snail_path_picture_builder_freeze` entry point now takes both
  `alloc` and `scratch_alloc`.
- Prepared resource retirement no longer uses a process-global queue or hidden
  sweeps on renderer calls. Use `PreparedResources.retireNow()` for immediate
  retirement or `retireAfter(&queue, fence)` with an explicit caller-owned
  `PreparedResourceRetirementQueue`.
- Vulkan resource-upload staging metadata and layer-info scratch now use the
  caller-provided prepared-resource allocator instead of process allocators.
- Vulkan no longer reads or writes a persistent pipeline cache in process-global
  cache directories during renderer init/deinit; it keeps only an in-memory
  `VkPipelineCache`.
- CPU prepared-resource upload now builds renderer-owned sidecars for path
  layer records, paint records, and axis-local prepared curve records. CPU
  draws still consume the same atlas/layer-info data model as GL/Vulkan, but
  avoid per-pixel layer-info decoding, repeated texture-coordinate wrapping,
  and curve-texel decoding in the coverage hot path.
- CPU prepared text drawing now predecodes glyph-band curve references into
  axis-local hot records with separate cold conic/cubic coefficient storage,
  and transformed glyph spans advance local coordinates incrementally across
  each scanline instead of recomputing the inverse transform per pixel.

## 0.5.0

### Fixed

- `TextAtlas.appendShapedTextBlob` (and therefore `TextBlobBuilder.addText`)
  no longer appends missing glyphs to the blob when `allow_missing` is true.
  Previously the loop set `missing = true` and then fell through to
  `appendBlobGlyph`, leaving the resulting blob with entries that referenced
  unrasterized GIDs — `TextBlob.validate` would reject the blob and
  draw paths could emit garbage. Missing glyphs are now skipped; the
  returned `advance` still spans the full shaped run so the caller's cursor
  lands in the right place for the next text segment.
- `FaceGlyphData.getGlyph` no longer reports rasterised-but-empty glyphs
  (e.g. space, with `h_band_count == 0`) as absent. The dense LUT used
  `h_band_count > 0` as a presence sentinel, which collided with the
  zero-initialised "absent" slots and disagreed with `glyph_map.contains`.
  The two predicates now agree, so `shapedGlyphAvailable` and
  `ensureGlyphMaps` can no longer take opposite sides on the same gid —
  previously, calling `ensureText` on a run containing such a glyph
  republished a functionally identical snapshot every time, spinning any
  caller that rebound on snapshot identity. Presence is now tracked via
  a separate bitset alongside the LUT. As part of the same fix,
  `glyphInstanceBudget` checks `band_entry` renderability so present-
  but-empty glyphs do not over-allocate the GPU instance buffer.

### Added

- `ResolveTarget.output_srgb` describes what encoding the consumer
  expects in the final pixel bytes (`true` = sRGB-encoded, `false` =
  linear). Each backend composes it with its own destination format:
  - GL/Vulkan: `setSrgbFormatTarget(bool)` (default `true`) declares
    whether the framebuffer/attachment auto-encodes on write
    (`GL_FRAMEBUFFER_SRGB` against an `_SRGB` target, or an `_SRGB`
    Vulkan attachment). The shader encodes iff
    `output_srgb && !srgb_format_target` — so default GL/Vulkan with an
    sRGB-format target gets sRGB output without shader-side encoding,
    and a linear-format target (e.g. an EGL dmabuf import that mesa
    won't tag as sRGB) opts in to shader-side encoding by setting
    `srgb_format_target = false`. Linear blending always happens
    inside the shader.
  - CPU: the pixel buffer is the storage and there is no format-level
    encoder. `output_srgb = true` writes sRGB-encoded bytes;
    `output_srgb = false` writes linear bytes. Both byte formats are
    first-class.
- `Renderer.setOutputSrgb` / `Renderer.outputSrgb` on the unified
  vtable-erased renderer; matching `setOutputSrgb` / `getOutputSrgb`
  on `GlRenderer`, `CpuRenderer`, and `VulkanPipeline`;
  `setSrgbFormatTarget` / `getSrgbFormatTarget` on `GlRenderer` and
  `VulkanPipeline`.
- The C API mirrors `output_srgb` on `SnailResolveTarget`.

### Changed

- `ResolveTarget.output_srgb` has no default — every call site must
  pick deliberately, since the right answer differs per destination.
- The Vulkan push-constant block grew by 4 bytes (84 → 88) to carry
  the composed shader-encode flag. Callers that hardcode the
  push-constant size against the previous layout need updating.

## 0.4.2

### Added

- `TextAtlas` now exposes stable per-face layout metrics:
  `faceCount`, `primaryFaceIndex`, `faceLineMetrics`, `faceUnitsPerEm`,
  `glyphIndex(face_index, codepoint)`, `advanceWidth(face_index, glyph_id)`,
  and `cellMetrics(.{ .style, .em })`.
- `snail.Font` is public again for callers that manage raw font data directly;
  `init`, `deinit`, `unitsPerEm`, `glyphIndex`, and `advanceWidth` are the
  stable surface.
- `TextAtlas.ensureGlyphs(face_index, glyph_ids)` extends a snapshot from
  already resolved glyph IDs without reshaping text.
- `TextBlob.rebind(new_atlas)` retargets cached blobs to a compatible superset
  atlas snapshot, after verifying the new snapshot shares the font config,
  retains old pages, and contains every referenced glyph.
- The C API mirrors the new text-atlas metrics, `ensure_glyphs`, and text-blob
  rebind helpers.
- The C API now exposes `SnailOverride` plus
  `snail_scene_add_text_override` / `snail_scene_add_path_picture_override`
  for per-submission transform and tint.

### Changed

- `TextCoverageRecords` is now caller-buffered. Use
  `TextCoverageRecords.wordCapacityForBlob(blob)` to size the `[]u32`, then
  initialize with `TextCoverageRecords.init(buffer)`. `buildLocal` and
  `rebuildLocal` no longer allocate.
- Draw records now store base color and instance tint separately so `Override.tint`
  composes correctly with text foreground colors, COLR palette layers, and
  vector paints. This changes `lowlevel.TEXT_WORDS_PER_GLYPH` /
  `lowlevel.PATH_WORDS_PER_SHAPE`; prefer `DrawList.estimate`.
- README benchmark tables were refreshed from a `zig build bench -Dvulkan=true`
  run on the documented machine.

### Fixed

- `Override.tint` now affects prepared vector path draws on GL, Vulkan, and CPU
  backends. It also tints explicit COLR palette layers instead of only
  foreground-color text layers.
- The game demo material-text shader now uses the widened text-record stride,
  fixing missing glyphs on the world-space text panels.

## 0.4.1

### Fixed

- `DrawList.estimate` now computes text budgets over the exact resolved
  `TextDraw.glyphs` range instead of prorating the whole blob budget, so
  ranged text draws can use it as the word-buffer upper bound even when
  high-fanout glyphs are concentrated in a small slice.

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
- `PathDraw.instances` / `TextDraw.instances` default to a single-
  identity slice; the field's length is always the GPU instance count
  (no empty-means-one sentinel).
- `Scene` borrows the `instances` slice along with `picture` / `blob`;
  all three must outlive the scene (or live until `scene.reset()`).
  No hidden per-call allocation. The C-API binding keeps a small arena
  inside `SceneImpl` to bridge stack lifetimes across the FFI boundary;
  `snail_scene_reset` releases its capacity.

### Renames

- `PathPicture.Instance` → `PathPicture.Shape`; field `.instances` →
  `.shapes`. Reflects the new vocabulary where "instances" are
  per-call GPU instances and "shapes" are entries in a frozen picture.
- `PathBatch.addPicture` / `addPictureTransformed` /
  `addPictureTransformedFrom` → `PathBatch.addDraw(view, PathDraw,
  override_index, shape_start) !AppendResult`.
- `PathBatch.AppendResult.next_instance` → `next_shape`.
- `TextBlob.appendToBatch` / `appendToBatchFrom` →
  `TextBatch.addDraw(view, TextDraw, override_index, start_glyph)`,
  mirroring `PathBatch.addDraw`. The text submission helper now lives
  on the batch (where you write into) rather than on the blob (what
  you read from).
- `TextBlob.instance_count_hint` → `TextBlob.gpu_instance_budget`.
  Same value (upper bound on emitted GPU vertex-output instances per
  blob), clearer name — disambiguates from `TextDraw.instances`,
  which counts per-draw `Override` entries.
- New `PathPictureBuilder.shapeCount()` for callers building `Range`
  selections at picture-build time.
- `Range.start` / `Range.count` are `usize` (was `u32`) to match the
  resource lengths they index into.

### Hinting removed

- `TextHinting`, `TextResolveOptions`, `TextDraw.resolve`,
  `TargetStamp.hinting`, the `H` key in the 2D demo, the bench
  AA × hinting matrix, and the related `SNAIL_TEXT_HINT_*` constants
  / `SnailTextResolveOptions` in the C API are gone. The 0.3.0
  metrics/phase modes never matched their advertised behavior cleanly
  — the underlying snap kept producing visible regressions on rotated
  / animated text and across drivers — and 0.4.0 ships unhinted
  rendering as the only mode rather than carrying a feature that
  needed an asterisk on every recommendation. Callers that want
  pixel-perfect static text should align baselines to integer
  coordinates themselves.

### Limits and error reporting

- `TextAtlas.addText` no longer silently drops codepoints past 256 in
  any single itemized run. The per-face glyph buffer falls back to the
  heap (via the atlas allocator) for longer runs and surfaces
  `error.OutOfMemory` if that allocation fails.
- Atlas page allocation in `CurveAtlas.cloneWithAppendedGlyphs` and
  `TextAtlas.ensureText` checks before narrowing to `u16` and returns
  `error.AtlasPageLimitExceeded` instead of panicking. The 16-bit
  width itself is dictated by the on-GPU vertex encoding (`Shape` /
  `GlyphPlacement` carry `page_index: u16`).

### C API

- `snail_scene_add_text_options` is gone. Its only purpose was the
  `SnailTextResolveOptions` parameter (now removed); the transform
  case it covered moves to `snail_scene_add_text_transformed`,
  mirroring `snail_scene_add_path_picture_transformed`.
- `snail_scene_add_path_picture_transformed` keeps its export name
  but routes through the new `PathDraw` struct internally; semantics
  are preserved.

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
- Tile fan-out happens once per frame, not once per segment. The
  earlier per-segment design paid the wake / join cost for every text
  or path command in the prepared scene, which made small-glyph text
  scenes (~4 segments × ~32 instances) effectively serial. With one
  fan-out per frame, text scales 2.4x and mixed scales 4.9x on the
  bench instead of 1.0x / 2.6x.
- The CPU prepared-path renderer now resolves image paints against the
  uploaded `Image` views and samples them as part of fill, replacing
  the placeholder pink-square output and bringing parity with the GL
  / Vulkan paths for image-fill `PathPicture` content. The MVP is
  applied per shape (the previous shortcut assumed an orthographic
  projection and broke under arbitrary affines).

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

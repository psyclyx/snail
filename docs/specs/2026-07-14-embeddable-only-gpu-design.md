# Embeddable-only GPU rendering — design

Status: LANDED (2026-07-21). The staged arc (§8, stages A–F) shipped: the
public surface exposes no all-in-one renderers (`src/snail/root.zig`), the
ex-renderers live on as demo reference callers (`src/demo/render/{gl,vulkan}/`),
and the caller-owned upload planner (`src/snail/atlas/upload_plan.zig`)
replaced the backend caches. The §9 open questions were either resolved
(linear-resolve recipe → the linear color boundary contract in
`src/snail/color.zig`) or dropped. Kept as design rationale.

## 1. Goal & boundary

snail is a font-rendering **library, not a renderer**. The caller owns the
GPU: instance, device, queues, command buffers, render pass (or dynamic
rendering), **and the pipeline**. snail owns the font data — the atlas, the
coverage math, the shader chunks, and the `emit` byte-stream — and hands the
caller resources to sample.

Decision: **remove the all-in-one GPU renderers** (`Gl33/44/Gles30Renderer`,
`VulkanRenderer`/`VulkanPipeline` draw path) from the public API. Keep
`CpuRenderer` (it rasterizes into a caller-owned buffer — already the
embeddable CPU path). GPU public surface becomes: `coverage` (shader chunks +
contract) + the backend cache (resource management + resource handles) +
`emit` (byte stream, core).

## 2. Current state (grounded)

**All-in-one renderers to remove (~2,625 LoC):** `vulkan/pipeline.zig`,
`vulkan/draw.zig`, `vulkan/graphics_pipeline.zig`, `gl/state.zig`,
`gl/gles30/state.zig`.

**What they do that the embeddable API must cover:** text coverage, hinted
text, autohint warp, COLR color layers, path fills (solid / linear+radial
gradient / image paints, via the layer_info texture), subpixel AA
(dual-source blend), and the linear-resolve pre/post passes.

**What `coverage` exposes today:** a *text-coverage-sampling* API. `Shader`
gives GLSL chunks for text coverage + sampling; `GlProgram` + `Gl*Backend`
(`bindProgram`/`bindDrawState`) are real and validated by the game demo
(`src/demo/game/quad_renderer.zig` samples `coverage.Shader.gl33.sample_functions`
into a `GL_R32UI` texture buffer). The **Vulkan side is an empty stub**
(`VulkanBackend = struct {}`, no-op binds; `VulkanProgram` carries only a
descriptor-set index). Path/COLR/subpixel/linear-resolve are **not** exposed
at all — they live only inside the all-in-one draw.

**Consumers to migrate (9):** `renderer_driver`, `screenshot_vulkan`,
`banner_screenshot_vulkan`, `screenshot_harness`, `game`, `game/passes`,
`game/quad_renderer`, `bench`, `bench/render_timing`.

## 3. Target public GPU API

Per backend, snail exposes exactly these, and nothing that owns a pipeline:

1. **Resource management** — the backend cache (`VulkanBackendCache`,
   `GlBackendCache`): uploads atlases → GPU textures/images, hands back a
   `Binding`. Already exists; keep. Uploads must not steal the caller's
   queue (§6).
2. **Resource handles** — `curveTexHandle()` / `bandTexHandle()` /
   `layerInfoTexHandle()` / `imageArrayHandle()` (GL: `GLuint`; Vulkan:
   `VkImageView`), plus Vulkan `descriptorSet()`. Mostly exist.
3. **The pipeline contract** the caller needs to build a *compatible*
   pipeline:
   - Vertex-input layout: the `Instance` (and `Override`) attribute
     descriptors — today private in `graphics_pipeline.zig`
     (`replicatedVertexInputAttributes`) / the GL VAO setup.
   - Push-constant / uniform contract: the 96-byte `PushConstants` struct
     (private in `pipeline.zig`) + its stage flags, or the GL uniform-name
     set (`GlProgram`).
   - Descriptor-set layout (Vulkan): binding order 0=curve, 1=band,
     2=layer_info, 3=image sampler — today built internally
     (`initDescriptorSetLayout`); must be exposed or documented so the
     caller can build a matching `VkPipelineLayout`.
   - Required blend / device features per shape family (§4).
4. **Shader chunks per shape family** — GLSL (GL) and SPIR-V modules
   (Vulkan) for: text coverage, hinted text, autohint, COLR, path, subpixel.
   GL has `Shader.<backend>.*`; Vulkan has compiled SPIR-V
   (`vulkan_shaders` module) but does not expose it as a caller contract.
5. **`emit` byte stream** — core, already public.

## 4. The crux: it's a family of pipeline recipes, not one shader

The all-in-one draw switches pipeline/blend per shape family. The embeddable
contract must document each as a recipe the caller reproduces:

| Family        | Shader        | Blend                              | Notes |
|---------------|---------------|------------------------------------|-------|
| text coverage | text          | premultiplied over                 | the one case `coverage` handles today |
| hinted text   | hinted_text   | premultiplied over                 | + hint VM record in layer_info |
| autohint      | autohint      | premultiplied over                 | + warp knots |
| COLR          | colr          | premultiplied over, multi-layer    | multiple draws per glyph |
| path paint    | path          | premultiplied over                 | samples layer_info for gradient/solid/image |
| subpixel      | text_subpixel | **dual-source** `ONE`/`ONE_MINUS_SRC1_COLOR` | requires `dualSrcBlend` device feature |
| linear resolve| resolve       | intermediate float target + encode | a pre/post pass around the frame |

Design implication: the embeddable API is a set of `PipelineRecipe`
descriptors (shader module(s) + blend state + vertex layout + which
descriptor bindings), one per family. The caller builds N pipelines from the
recipes against *their* render pass / dynamic-rendering formats, then per
draw binds snail's descriptor set + pushes constants + issues
`emit`-produced vertices. Subpixel and linear-resolve are the two that carry
real pipeline-state opinions the caller must match; both must be documented
as explicit caller requirements (and the caller opts out of subpixel if the
device lacks `dualSrcBlend`).

## 5. Vulkan-specific work (the from-scratch half)

- Make `PushConstants` public (or a stable mirror) + its range/stage flags.
- Expose the descriptor-set layout handle from the cache/pipeline, or a
  documented spec the caller builds from.
- Expose vertex-input descriptors for `Instance`/`Override`.
- Expose the SPIR-V modules per family as a caller-consumable set (they exist
  in `vulkan_shaders`; today only the internal pipeline binds them).
- Replace `coverage.VulkanBackend` stub with the real surface (no bind-by-
  uniform-location like GL — the Vulkan "bind" is: caller binds
  `descriptorSet()`, pushes `PushConstants`, draws). The `coverage.Backend`
  union's Vulkan arm becomes real.
- Images are left in `VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL` after upload
  — document; no caller transition needed post-upload-completion.

## 6. Queue decoupling (sub-project)

Today the cache submits uploads on `ctx.graphics_queue` and CPU-blocks on a
fence (`device.zig` `submitTransferAndWait`). Embeddable hosts can't cede
their queue. Target: the cache records uploads into a **caller-provided
command buffer** (caller submits + synchronizes), or accepts a caller
transfer queue. This is independent of the pipeline work and can land
separately.

## 7. Test strategy (holds the byte-verification bar)

The migration is safe *because* the all-in-one renderer stays as the
reference until each consumer is migrated:
- **During migration**, for each consumer: render via the all-in-one path
  and via the new embeddable path, diff byte-for-byte. CPU is the
  deterministic reference; GPU tolerates the known ~±1-LSB AA noise
  (`project_module_graph`).
- **Vulkan embeddable** needs its own test vehicle: a Vulkan custom-shader
  offscreen render (mirroring the GL game/`quad_renderer` pattern) that
  builds a caller pipeline from the recipes and renders text, diffed against
  the current all-in-one Vulkan banner output *before* the all-in-one is
  removed.
- The ex-all-in-one renderer code does **not** become dead: it moves into the
  demo as a **reference caller renderer** — the canonical worked example of
  "how to drive snail from your own pipeline." That keeps every demo working
  and gives integrators a copy-paste starting point.

## 8. Staged plan

- **A. Design** — this doc.
- **B. Vulkan text-coverage parity** — wire the `coverage` Vulkan stub to
  match GL's text-coverage embeddable path; build the Vulkan custom-shader
  offscreen test; diff vs all-in-one Vulkan. First proven brick.
- **C. Full-parity embeddable API** — the big one. Expose the
  `PipelineRecipe` set for all shape families (path/COLR/subpixel/
  linear-resolve), GL + Vulkan, with the contract in §3–§4.
- **D. Queue decoupling** — §6, independent, can interleave.
- **E. Migrate consumers** — one at a time, byte-diff each: `screenshot_gl`
  → `screenshot_vulkan` → banners → `game` (partial already) → `bench` →
  `renderer_driver`. Move the reference renderer into the demo.
- **F. Remove** the all-in-one GPU renderers from the public API; `root.zig`
  GPU surface = `coverage` + caches + `emit`.

## 9. Risks / open questions

- **Parity surface is large** — COLR (multi-layer) and linear-resolve
  (multi-pass) are not single-shader contracts; their embeddable recipes are
  the hardest design work in Stage C.
- **Dual-source subpixel** requires a device feature + exact blend state;
  must be an explicit, documented caller requirement with a graceful
  non-subpixel fallback.
- **Reference-renderer boundary** — recommend keeping the ex-all-in-one code
  as a demo-side reference renderer (worked example), not deleting it, so the
  demos keep working and integrators have a template.
- **`color_format`** is redundant for the (removed) all-in-one path; in the
  embeddable path the caller owns pipeline/format entirely, so snail needs no
  format field at all — drop `VulkanContext.color_format` at Stage F.

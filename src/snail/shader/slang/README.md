# Slang shader source

This directory is snail's only authored shader source. Entry points live in
`families/*.slang`; shared modules contain the coverage, color, sampling, and
render-ABI logic used by those families.

`build/slang_shaders.zig` is the source of truth for the exact compiler flags
and family matrix. It generates these targets directly from Slang:

- Vulkan SPIR-V 1.3
- WGSL
- D3D11 HLSL Shader Model 5.0
- Metal Shading Language
- desktop GLSL 330
- GLES 300

Generated artifacts are lazy Zig build outputs in the cache, not checked-in
source. `zig build gen-shaders` materializes the full matrix under
`zig-out/shaders/` for inspection.

## Build modules

The generated accessor is published in target-scoped modules so consumers only
run the tools needed by their backend:

- `snail-shaders`: every target, including artifact validation
- `snail-shaders-vk`: Vulkan SPIR-V
- `snail-shaders-gl`: GLSL 330 and GLES 300
- `snail-shaders-glsl330`: desktop GLSL only
- `snail-shaders-wgsl`: WGSL
- `snail-shaders-hlsl`: D3D11 HLSL
- `snail-shaders-msl`: Metal
- `snail-shaders-reflection`: generated parameter ABI without shader artifacts

A consumer that imports only `snail` or `snail-raster` does not run shader
generation and does not need the shader toolchain.

Each shader module includes a generated `reflection.zig`. Its
`PushConstants` extern struct and binding constants are derived from
`slangc -reflection-json`; consumers should use those definitions rather than
copying offsets or binding numbers. Snail separately owns the data ABI:
instance records, atlas texel layouts, and blend semantics.

## Custom families

Callers can compose their own family over snail's shader helpers. The package
exports this directory as the named lazy path `snail_slang`:

```zig
const snail_dep = b.dependency("snail", .{
    .target = target,
    .optimize = optimize,
});

const compile = b.addSystemCommand(&.{
    "slangc",
    "-DSNAIL_TARGET_VULKAN",
    "-target", "spirv",
    "-profile", "spirv_1_3",
    "-O2",
    "-default-image-format-unknown",
    "-entry", "fragmentMain",
    "-stage", "fragment",
    "-I",
});
compile.addDirectoryArg(snail_dep.namedLazyPath("snail_slang"));
compile.addFileArg(b.path("shaders/my_material.slang"));
const spv = compile.addPrefixedOutputFileArg("-o", "my_material.frag.spv");
```

The caller's family owns its resource bindings, parameter block, and entry
points. Shared modules take textures and scalar values as parameters rather
than declaring global resources. Use Slang reflection from the caller's own
compile to wire those bindings.

The stable caller-facing modules are:

- `render_abi`: shared render-ABI constants
- `color_common`: sRGB transfer and premultiplication helpers
- `coverage_common`: root-code, band-span, and coverage-transfer machinery
- `text_coverage`: grayscale glyph coverage evaluation
- `subpixel_body`: LCD subpixel evaluation and dual-source packing
- `text_sample`: text-as-material sampling

Other modules, including `families/*.slang`, are implementation details. They
track snail's own record layouts and generated bindings and may change with
the render ABI.

The in-tree reference for a caller-owned family is
`src/demo/game/slang/game_material.slang`. A custom family that consumes
snail's instance records should assert its stride against
`snail.render.records.BYTES_PER_INSTANCE`.

## Cross-target rules

- Use Slang's default matrix layout. Snail's CPU matrices are column-major
  bytes and the native Slang output has been verified to preserve the intended
  `M * v` result on every target.
- Vulkan uses raw `VertexIndex` through `spirv_asm`; direct GL uses
  `gl_VertexID`; WGSL, D3D11, and Metal use the `SV_VertexID` source branch.
- WGSL, D3D11, and Metal clip space is y-up for snail's projections, so their
  family entry points apply the explicit y flip.
- Paint families deliberately alias image and sampler declarations onto the
  combined Vulkan descriptor at set 0, binding 3.
- Direct GLSL output passes through `build/glsl_patch_direct.zig` to normalize
  the dialect and stage interface. The patcher performs no IR translation.
- Compact autohint data is decoded with 32-bit operations so baseline GL 3.3
  and GLES 3.0 do not require native 16-bit arithmetic.

The detailed, version-sensitive rationale for flags and backend workarounds
stays beside their implementation in `build/slang_shaders.zig`.

## WGSL dual source

Slang does not emit WGSL's `@blend_src` form. For subpixel families,
`build/wgsl_gen_dual_entry.zig` derives `fragmentDualMain` from the emitted
`fragmentMain` after generation and adds the dual-source output attributes.
Naga validates every final WGSL artifact, including this transform.

## Metal

The Metal target uses `-ignore-capabilities` because the pinned Slang compiler
incorrectly rejects imported fragment helpers that use derivatives or
`discard`. Other targets retain capability checking.

The generated binding contract is:

- parameter block: `[[buffer(0)]]`
- curve, band, layer/record, and image textures: `[[texture(0...3)]]`
- image sampler: `[[sampler(0)]]`
- instance attributes: `[[attribute(0...6)]]`

The host chooses the vertex-buffer index for the instance stream; it must not
collide with buffer 0. Entry points remain `vertexMain` and `fragmentMain`.
`text_sample` uses `texture_buffer` and therefore requires MSL 2.1 or newer.

Slang drops the secondary color index for Metal and emits the subpixel result
as ordinary MRT outputs. A Metal consumer using dual-source blending must
rewrite the second output to `[[color(0), index(1)]]` before compiling.

`zig build check-metal-demo` cross-compiles the host code on non-macOS systems.
macOS CI additionally compiles every generated MSL artifact, creates the
scene-used pipelines, renders on Metal, and pixel-gates the result.

## Verification

Run `zig build test` for the public API, generated artifact contracts,
reflection agreement, and final WGSL validation. Use
`zig build gen-shaders` when the generated source itself needs inspection.

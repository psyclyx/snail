//! Generated, complete per-family WGSL shader catalog.
//!
//! Unlike the GLSL fragment catalog (`shader.glsl`), these are finished
//! shaders — entry points included, always named `main` — one module per
//! family and stage, generated from the same composed Vulkan GLSL the demo
//! SPIR-V path compiles. They are checked-in artifacts; regenerate with
//!
//!     zig build gen-wgsl
//!
//! inside `nix-shell` (needs `slangc`, `glslang`, `spirv-opt`, and `naga`;
//! see build/wgsl_shaders.zig for the full pipeline and the reasons slangc's
//! own `-target wgsl` backend cannot be used directly: its GLSL front end
//! miscompiles `texelFetch` on combined samplers and renumbers stage IO
//! locations per stage). The slangc leg keeps the Vulkan footgun flags:
//! `-lang glsl -stage <s> -entry main -matrix-layout-row-major
//! -warnings-disable 39001,41018` — `-matrix-layout-row-major` names Slang's
//! *logical* convention and maps inverted onto the SPIR-V decoration; without
//! it every matrix is silently transposed — plus `-emit-spirv-via-glsl`,
//! equally load-bearing: slang's direct SPIR-V backend produces loop
//! constructs whose break edges naga drops, yielding WGSL loops that never
//! terminate.
//!
//! ## Binding contract
//!
//! Bindings correspond 1:1 to the Vulkan GLSL contract
//! (`src/demo/render/vulkan/contract.zig`), adapted to WebGPU's model:
//!
//! - `@group(0) @binding(N)` — the four atlas *textures*, N = the Vulkan
//!   set-0 binding: 0 curve (`texture_2d_array<f32>`, rgba16float),
//!   1 band (`texture_2d_array<u32>`, rg16uint), 2 layer-info
//!   (`texture_2d<f32>`, rgba32float), 3 image array
//!   (`texture_2d_array<f32>`, rgba8unorm-srgb).
//! - `@group(1) @binding(N)` — the *samplers* split out of the Vulkan
//!   combined image samplers (WGSL has none), same N as their texture.
//!   Filtering only matters for the image array (binding 3, linear); the
//!   others are only ever `textureLoad`ed.
//! - `@group(2) @binding(0)` — the Vulkan push-constant block as a uniform
//!   buffer (WebGPU has no push constants). Layout is std140, 96 bytes,
//!   identical to the Vulkan `PushConstants`: mvp `mat4x4<f32>` @ 0,
//!   viewport `vec2<f32>` @ 64, subpixel_order `i32` @ 72, output_srgb
//!   `i32` @ 76, layer_base `i32` @ 80, coverage_exponent `f32` @ 84,
//!   dither_scale `f32` @ 88, mask_output `i32` @ 92. Stages declare prefixes
//!   of this block (the vertex stage stops after subpixel_order); one 96-byte
//!   buffer bound to both stages satisfies every module.
//!
//! Vertex input locations 0–8 and the inter-stage varyings keep the exact
//! locations of the Vulkan contract (`contract.zig:vertexInputAttributes`).
//!
//! `.subpixel` needs the `dual-source-blending` WebGPU feature (the module
//! says `enable dual_source_blending;` and writes `@blend_src(0)`/
//! `@blend_src(1)` outputs at location 0).

/// A pipeline family, mirroring the Vulkan contract's `Family`. Every family
/// except `.autohint` shares the `.text` vertex stage; `.autohint` fits knot
/// targets in its own vertex stage.
pub const Family = enum {
    text,
    colr,
    path,
    tt_hinted_text,
    autohint,
    subpixel,
};

pub const Stage = enum { vertex, fragment };

/// Complete WGSL source for one family + stage. Entry point is `main`.
pub fn source(comptime family: Family, comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => switch (family) {
            .autohint => @embedFile("wgsl/autohint.vert.wgsl"),
            else => @embedFile("wgsl/text.vert.wgsl"),
        },
        .fragment => switch (family) {
            .text => @embedFile("wgsl/text.frag.wgsl"),
            .colr => @embedFile("wgsl/colr.frag.wgsl"),
            .path => @embedFile("wgsl/path.frag.wgsl"),
            .tt_hinted_text => @embedFile("wgsl/tt_hinted_text.frag.wgsl"),
            .autohint => @embedFile("wgsl/autohint.frag.wgsl"),
            .subpixel => @embedFile("wgsl/subpixel.frag.wgsl"),
        },
    };
}

test "every family has non-empty vertex and fragment sources with entry points" {
    const std = @import("std");
    inline for (comptime std.meta.tags(Family)) |family| {
        inline for (comptime std.meta.tags(Stage)) |stage| {
            const text = source(family, stage);
            try std.testing.expect(text.len != 0);
            try std.testing.expect(std.mem.indexOf(u8, text, "fn main(") != null);
        }
    }
    // The uniform replacing the Vulkan push-constant block.
    try std.testing.expect(std.mem.indexOf(u8, source(.text, .vertex), "@group(2) @binding(0)") != null);
    // Dual-source subpixel needs the WebGPU extension.
    try std.testing.expect(std.mem.indexOf(u8, source(.subpixel, .fragment), "enable dual_source_blending;") != null);
}

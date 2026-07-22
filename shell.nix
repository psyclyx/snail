{ pkgs ? import (import ./npins).nixpkgs { } }:

let
  # Unpacked HarfBuzz source tree: the cross-compiled Windows demo
  # (`zig build run-minimal-d3d11`) compiles the single-file amalgam
  # (src/harfbuzz.cc) for x86_64-windows-gnu instead of linking the host
  # library. Same nixpkgs pin as the `harfbuzz` package below, so shaping
  # behavior matches the native demos.
  harfbuzzSrc = pkgs.runCommand "harfbuzz-src-${pkgs.harfbuzz.version}" { } ''
    mkdir -p $out
    tar --strip-components=1 -xf ${pkgs.harfbuzz.src} -C $out
  '';
in
pkgs.mkShell {
  packages = with pkgs; [
    zig_0_16
    pkg-config
    libGL
    wayland
    wayland-protocols
    wayland-scanner
    harfbuzz
    vulkan-loader
    vulkan-headers
    vulkan-validation-layers
    # Shader artifact regeneration (`zig build gen-shaders`): slangc for
    # every target, spirv-cross for the GL dialects.
    shader-slang
    spirv-cross
    # naga CLI (`naga <file>.wgsl`): validation tripwire for the generated
    # WGSL artifacts (the subpixel module's prelude entry in particular).
    wgpu-utils
    # Headless WebGPU reference example (`zig build run-minimal-wgpu`).
    wgpu-native
    # Headless D3D11 reference example (`zig build run-minimal-d3d11`):
    # runs the cross-compiled Windows exe; Wine's built-in d3dcompiler_47
    # is the FXC-class compiler for the generated HLSL artifacts. Needs
    # the development branch: stable wine 11.0's bundled vkd3d-shader
    # crashes compiling autohint.vert.hlsl (11.6 compiles all nine).
    wine64Packages.unstable
  ];

  LD_LIBRARY_PATH = with pkgs; pkgs.lib.makeLibraryPath [
    libGL
    wayland
    harfbuzz
    vulkan-loader
    wgpu-native
  ];

  # wgpu-native ships no pkg-config file; build.zig picks these up for the
  # minimal WebGPU example.
  WGPU_NATIVE_INCLUDE = "${pkgs.wgpu-native.dev}/include";
  WGPU_NATIVE_LIB = "${pkgs.wgpu-native}/lib";

  # HarfBuzz amalgam source for the Windows cross-build (run-minimal-d3d11).
  HARFBUZZ_SRC = "${harfbuzzSrc}";
}

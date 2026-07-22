{ pkgs ? import (import ./npins).nixpkgs { } }:

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
}

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
    shader-slang
    # WGSL catalog regeneration (`zig build gen-wgsl`):
    # spirv-opt + glslang + naga.
    spirv-tools
    spirv-cross
    glslang
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

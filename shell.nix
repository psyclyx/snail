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
    shaderc
  ];

  LD_LIBRARY_PATH = with pkgs; pkgs.lib.makeLibraryPath [
    libGL
    wayland
    harfbuzz
    vulkan-loader
  ];
}

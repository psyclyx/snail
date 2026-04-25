let
  sources = import ./npins;
  pkgs = import sources.nixpkgs {};
in
pkgs.mkShell {
  packages = with pkgs; [
    zig_0_16
    pkg-config
    libGL
    wayland
    wayland-protocols
    wayland-scanner
    freetype
    harfbuzz
    vulkan-loader
    vulkan-headers
    vulkan-validation-layers
    shaderc
    # For competitor benchmarks
    cmake
    gnumake
    gcc
    rustc
    cargo
    git
    glew
    glm
  ];

  LD_LIBRARY_PATH = with pkgs; pkgs.lib.makeLibraryPath [
    libGL
    wayland
    harfbuzz
    vulkan-loader
  ];
}

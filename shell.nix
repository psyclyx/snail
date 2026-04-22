let
  sources = import ./npins;
  flake-compat = import sources.flake-compat;
  zig-flake = (flake-compat { src = sources.zig-overlay; }).defaultNix;
  pkgs = import sources.nixpkgs {
    overlays = [ zig-flake.overlays.default ];
  };
in
pkgs.mkShell {
  packages = with pkgs; [
    zigpkgs.master
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

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
    glfw
    libGL
    wayland
    wayland-protocols
    wayland-scanner
    libxkbcommon
    freetype
    harfbuzz
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
    glfw
    wayland
    libxkbcommon
    harfbuzz
  ];
}

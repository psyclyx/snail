let
  sources = import ./npins;
  flake-compat = import sources.flake-compat;
  zig-flake = (flake-compat { src = sources.zig-overlay; }).defaultNix;
  pkgs = import sources.nixpkgs {
    overlays = [ zig-flake.overlays.default ];
  };
in
pkgs.stdenv.mkDerivation {
  pname = "snail";
  version = "0.0.1";
  src = ./.;

  nativeBuildInputs = with pkgs; [
    zigpkgs.master
    pkg-config
  ];

  buildInputs = with pkgs; [
    glfw
    libGL
    wayland
    wayland-protocols
    libxkbcommon
  ];

  buildPhase = ''
    export XDG_CACHE_HOME="$TMPDIR/.cache"
    zig build --release=fast
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp zig-out/bin/snail $out/bin/
  '';
}

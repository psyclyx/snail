let
  sources = import ./npins;
  flake-compat = import sources.flake-compat;
  zig-flake = (flake-compat { src = sources.zig-overlay; }).defaultNix;
  pkgs = import sources.nixpkgs {
    overlays = [ zig-flake.overlays.default ];
  };
  zig = pkgs.zigpkgs.master;

  common = {
    version = "0.0.1";
    src = ./.;
    nativeBuildInputs = [ zig pkgs.pkg-config ];
    preBuild = "export XDG_CACHE_HOME=$TMPDIR/.cache";
  };

  lib = pkgs.stdenv.mkDerivation (common // {
    pname = "snail";
    buildInputs = with pkgs; [ libGL harfbuzz ];
    buildPhase = "zig build --release=fast";
    installPhase = ''
      mkdir -p $out/{lib,include,lib/pkgconfig}
      cp zig-out/lib/libsnail.so  $out/lib/
      cp zig-out/lib/libsnail.a   $out/lib/
      cp zig-out/include/snail.h  $out/include/
      sed "s|@PREFIX@|$out|g" snail.pc.in > $out/lib/pkgconfig/snail.pc
    '';
  });

  demo = pkgs.stdenv.mkDerivation (common // {
    pname = "snail-demo";
    buildInputs = with pkgs; [ libGL harfbuzz wayland ];
    buildPhase = "zig build demo --release=fast";
    installPhase = ''
      mkdir -p $out/bin
      cp zig-out/bin/snail-demo $out/bin/snail-demo
    '';
  });

  shell = import ./shell.nix;

in { inherit lib demo shell; default = lib; }

let
  sources = import ./npins;
  pkgs = import sources.nixpkgs {};
  zig = pkgs.zig_0_16;

  lib = pkgs.stdenv.mkDerivation {
    pname = "snail";
    version = "0.4.1";
    src = ./.;
    nativeBuildInputs = [ zig.hook pkgs.pkg-config ];
    buildInputs = with pkgs; [ libGL harfbuzz ];
    zigBuildFlags = [ "-Doptimize=ReleaseFast" "-Dharfbuzz=true" ];
    dontUseZigCheck = true;
    postInstall = ''
      mkdir -p $out/lib/pkgconfig
      sed "s|@PREFIX@|$out|g" snail.pc.in > $out/lib/pkgconfig/snail.pc
    '';
  };

  demo = pkgs.stdenv.mkDerivation {
    pname = "snail-demo";
    version = "0.4.1";
    src = ./.;
    nativeBuildInputs = [ zig.hook pkgs.pkg-config ];
    buildInputs = with pkgs; [ libGL harfbuzz wayland ];
    zigBuildFlags = [ "demo" "-Doptimize=ReleaseFast" "-Dharfbuzz=true" ];
    dontUseZigCheck = true;
  };

  shell = import ./shell.nix;

in { inherit lib demo shell; default = lib; }

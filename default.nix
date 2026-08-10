let
  npins = import ./npins;

  mkPackages = pkgs: {
    # Pass src explicitly: snail-demo.nix has a `src` formal arg, and without
    # this callPackage would fill it from pkgs.src (a throwing alias).
    snail-demo = pkgs.callPackage ./nix/snail-demo.nix { src = ./.; };
  };

  # Scoped against `final` so packages can reference each other; lazy, so no
  # infinite recursion. Consumers apply this overlay to their own pkgs to get
  # snail's packages by name.
  overlay = final: _prev: mkPackages final;
in
{
  nixpkgs ? npins.nixpkgs,
  pkgs ? import nixpkgs { },
}:
let
  finalPkgs = pkgs.extend overlay;
in
{
  packages = mkPackages finalPkgs;
  inherit overlay;
  shell = import ./shell.nix { pkgs = finalPkgs; };
  default = finalPkgs.snail-demo;
}

let
  npins = import ./npins;

  mkPackages = pkgs: {
    # The derivation fileset-scopes its own src (see nix/snail-demo.nix), so
    # no src plumbing is needed here.
    snail-demo = pkgs.callPackage ./nix/snail-demo.nix { };
  };

  # Scoped against `final` so packages can reference each other; lazy, so no
  # infinite recursion. Consumers apply this overlay to their own pkgs to get
  # snail's packages by name.
  overlay = final: _prev: mkPackages final;
in
{
  sources ? npins,
  nixpkgs ? sources.nixpkgs,
  pkgs ? import nixpkgs { },
  ...
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

{ pkgs ? import (import ./npins).nixpkgs { }
, src ? ./.
}:

let
  snail = pkgs.callPackage ./nix/snail.nix {
    inherit src;
  };

  demo = pkgs.callPackage ./nix/snail.nix {
    inherit src;
    pname = "snail-demo";
    buildDemo = true;
    enableCApi = false;
  };

  shell = import ./shell.nix {
    inherit pkgs;
  };
in
{
  inherit demo shell;

  lib = snail;
  default = snail;

  packages = {
    inherit snail demo;
  };
}

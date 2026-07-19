{ pkgs ? import (import ./npins).nixpkgs { }
, src ? ./.
}:

let
  cleanSrc = pkgs.lib.cleanSourceWith {
    inherit src;
    filter = path: type:
      let
        name = builtins.baseNameOf path;
      in
      !(builtins.elem name [ ".direnv" ".worktrees" ".zig-cache" "zig-out" ])
      && pkgs.lib.cleanSourceFilter path type;
  };

  demo = pkgs.callPackage ./nix/snail-demo.nix {
    src = cleanSrc;
  };

  shell = import ./shell.nix {
    inherit pkgs;
  };
in
{
  inherit demo shell;

  default = demo;

  packages = {
    inherit demo;
  };
}

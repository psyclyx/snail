{
  description = "GPU font rendering via direct Bézier curve evaluation (Slug algorithm)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, zig-overlay, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };
        zig = pkgs.zigpkgs.master;

        buildDeps = with pkgs; [
          glfw libGL vulkan-loader vulkan-headers shaderc pkg-config
        ];

        common = {
          version = "0.0.1";
          src = ./.;
          nativeBuildInputs = [ zig pkg-config ];
          buildInputs = buildDeps;
          env.XDG_CACHE_HOME = "$TMPDIR/.cache";
        };

        lib = pkgs.stdenv.mkDerivation (common // {
          pname = "snail";
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
          buildPhase = "zig build --release=fast";
          installPhase = ''
            mkdir -p $out/bin
            cp zig-out/bin/snail-demo $out/bin/snail-demo
          '';
        });
      in {
        packages = {
          inherit lib demo;
          default = lib;
        };

        devShells.default = pkgs.mkShell {
          packages = [ zig ] ++ buildDeps ++ (with pkgs; [
            freetype harfbuzz vulkan-validation-layers
          ]);
          LD_LIBRARY_PATH = with pkgs; pkgs.lib.makeLibraryPath [
            libGL glfw vulkan-loader harfbuzz
          ];
        };
      });
}

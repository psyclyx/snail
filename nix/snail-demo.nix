{
  lib,
  stdenv,
  zig_0_16,
  pkg-config,
  libGL,
  harfbuzz,
  vulkan-loader,
  vulkan-headers,
  shader-slang,
  wayland,
  wayland-protocols,
  src ? ../.,
  pname ? "snail-demo",
  version ? "0.18.0",
  optimize ? "fast",
  cpu ? "baseline",
}:

let
  zig = zig_0_16;

  cleanSrc = lib.cleanSourceWith {
    inherit src;
    filter =
      path: type:
      let
        name = builtins.baseNameOf path;
      in
      !(builtins.elem name [
        ".direnv"
        ".worktrees"
        ".zig-cache"
        "zig-out"
      ])
      && lib.cleanSourceFilter path type;
  };
in
stdenv.mkDerivation {
  inherit pname version;
  src = cleanSrc;

  nativeBuildInputs = [
    zig.hook
    pkg-config
    shader-slang
  ];

  buildInputs = [
    harfbuzz
    libGL
    vulkan-loader
    vulkan-headers
    wayland
    wayland-protocols
  ];

  zigBuildFlags = [
    "install-demo"
    "--release=${optimize}"
    "-Dcpu=${cpu}"
  ];

  dontUseZigCheck = true;
  dontSetZigDefaultFlags = true;

  hardeningDisable = [
    "fortify"
  ];

  meta = {
    description = "Interactive demo for snail";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}

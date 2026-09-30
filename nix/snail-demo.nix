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
  pname ? "snail-demo",
  version ? "0.20.0",
  optimize ? "fast",
  cpu ? "baseline",
}:

let
  zig = zig_0_16;
in
stdenv.mkDerivation {
  inherit pname version;
  # Only the files the `install-demo` build actually consumes: the build
  # graph (build.zig + build/), the library sources and shader families
  # (src/), the shared font/image assets (assets/), and the demo + support
  # sources the demo links (dev/demo, dev/support). Entry points
  # (default.nix, shell.nix), npins/, docs, and test/CI scaffolding are not
  # package inputs, so editing them must not churn the source hash.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../build.zig
      ../build.zig.zon
      ../build
      ../src
      ../assets
      ../dev/demo
      ../dev/support
    ];
  };

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

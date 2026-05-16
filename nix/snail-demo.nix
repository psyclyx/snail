{ lib
, stdenv
, zig_0_16
, pkg-config
, libGL
, harfbuzz
, vulkan-loader
, vulkan-headers
, shaderc
, wayland
, wayland-protocols
, src ? ../.
, pname ? "snail-demo"
, version ? "0.9.0"
, enableOpenGL ? true
, enableVulkan ? true
, enableCpu ? true
, enableHarfBuzz ? true
, optimize ? "fast"
, cpu ? "baseline"
}:

let
  zig = zig_0_16;
  backendOptions = import ./backend-options.nix { inherit lib; } {
    inherit
      enableOpenGL
      enableVulkan
      enableCpu
      enableHarfBuzz
      optimize
      cpu;
    enableCApi = false;
    cApiShared = false;
    cApiStatic = false;
  };
in
assert enableOpenGL || enableVulkan || enableCpu;
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    zig.hook
    pkg-config
  ] ++ lib.optionals enableVulkan [
    shaderc
  ];

  buildInputs =
    lib.optionals enableOpenGL [
      libGL
    ]
    ++ lib.optionals enableHarfBuzz [
      harfbuzz
    ]
    ++ lib.optionals enableVulkan [
      vulkan-loader
      vulkan-headers
    ]
    ++ [
      wayland
      wayland-protocols
    ];

  zigBuildFlags = [
    "demo"
  ] ++ backendOptions.zigBuildFlags;

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

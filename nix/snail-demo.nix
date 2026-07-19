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
, version ? "0.12.1"
, enableGL33 ? true
, enableGL44 ? true
, enableGLES30 ? true
, enableVulkan ? true
, enableRaster ? true
, optimize ? "fast"
, cpu ? "baseline"
}:

let
  zig = zig_0_16;
  backendOptions = import ./backend-options.nix { inherit lib; } {
    inherit
      enableGL33
      enableGL44
      enableGLES30
      enableVulkan
      enableRaster
      optimize
      cpu;
    enableCApi = false;
    cApiShared = false;
    cApiStatic = false;
  };
in
assert enableGL33 || enableGL44 || enableGLES30 || enableVulkan || enableRaster;
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    zig.hook
    pkg-config
  ] ++ lib.optionals enableVulkan [
    shaderc
  ];

  buildInputs =
    [
      harfbuzz
    ]
    ++ lib.optionals (enableGL33 || enableGL44 || enableGLES30) [
      libGL
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

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
, version ? "0.6.1"
, enableOpenGL ? true
, enableVulkan ? true
, enableCpu ? true
, enableHarfBuzz ? true
, renderer ? (
    if enableVulkan then "vulkan"
    else if enableOpenGL then "gl44"
    else "cpu"
  )
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
      cpu
      ;
    enableCApi = false;
    cApiShared = false;
    cApiStatic = false;
  };
in
assert lib.elem renderer [ "gl44" "gl33" "vulkan" "cpu" ];
assert renderer != "vulkan" || enableVulkan;
assert !(lib.elem renderer [ "gl44" "gl33" ]) || enableOpenGL;
assert renderer != "cpu" || enableCpu;
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
  ] ++ backendOptions.zigBuildFlags ++ [
    "-Drenderer=${renderer}"
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

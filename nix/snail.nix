{ lib
, stdenv
, zig_0_16
, pkg-config
, libGL
, harfbuzz
, vulkan-loader
, vulkan-headers
, shaderc
, src ? ../.
, pname ? "snail"
, version ? "0.12.1"
, enableGL33 ? true
, enableGL44 ? true
, enableGLES30 ? true
, enableVulkan ? true
, enableRaster ? true
, enableHarfBuzz ? true
, enableCApi ? true
, cApiShared ? enableCApi
, cApiStatic ? enableCApi
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
      enableHarfBuzz
      enableCApi
      cApiShared
      cApiStatic
      optimize
      cpu;
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    zig.hook
    pkg-config
  ] ++ lib.optionals enableVulkan [
    shaderc
  ];

  buildInputs =
    lib.optionals (enableGL33 || enableGL44 || enableGLES30) [
      libGL
    ]
    ++ lib.optionals enableHarfBuzz [
      harfbuzz
    ]
    ++ lib.optionals enableVulkan [
      vulkan-loader
      vulkan-headers
    ];

  zigBuildFlags = backendOptions.zigBuildFlags;

  dontUseZigCheck = true;
  dontSetZigDefaultFlags = true;

  meta = {
    description = "GPU font and vector rendering via direct Bezier curve evaluation";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}

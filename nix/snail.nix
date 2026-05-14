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
, version ? "0.7.0"
, enableOpenGL ? true
, enableVulkan ? true
, enableCpu ? true
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
      enableOpenGL
      enableVulkan
      enableCpu
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
    lib.optionals enableOpenGL [
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

  postInstall = lib.optionalString enableCApi ''
    mkdir -p $out/lib/pkgconfig
    substitute snail.pc.in $out/lib/pkgconfig/snail.pc \
      --replace-fail @PREFIX@ $out \
      --replace-fail @REQUIRES@ "${backendOptions.cApiRequires}"
  '';

  meta = {
    description = "GPU font and vector rendering via direct Bezier curve evaluation";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}

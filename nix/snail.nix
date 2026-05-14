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
, pname ? "snail"
, version ? "0.6.1"
, buildDemo ? false
, enableOpenGL ? true
, enableVulkan ? true
, enableCpu ? true
, enableHarfBuzz ? true
, enableCApi ? (!buildDemo)
, cApiShared ? enableCApi
, cApiStatic ? enableCApi
, optimize ? "fast"
, cpu ? "baseline"
}:

let
  zig = zig_0_16;

  boolFlag = name: value: "-D${name}=${if value then "true" else "false"}";

  demoRenderer =
    if enableVulkan then "vulkan"
    else if enableOpenGL then "gl44"
    else "cpu";

  cApiRequires = lib.concatStringsSep " " (
    lib.optionals enableOpenGL [ "gl" ]
    ++ lib.optionals enableHarfBuzz [ "harfbuzz" ]
    ++ lib.optionals enableVulkan [ "vulkan" ]
  );
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
    ]
    ++ lib.optionals buildDemo [
      wayland
      wayland-protocols
    ];

  zigBuildFlags =
    lib.optional buildDemo "demo"
    ++ [
      "--release=${optimize}"
      "-Dcpu=${cpu}"
      (boolFlag "opengl" enableOpenGL)
      (boolFlag "vulkan" enableVulkan)
      (boolFlag "cpu-renderer" enableCpu)
      (boolFlag "harfbuzz" enableHarfBuzz)
      (boolFlag "c-api" enableCApi)
      (boolFlag "c-api-shared" cApiShared)
      (boolFlag "c-api-static" cApiStatic)
    ]
    ++ lib.optional buildDemo "-Drenderer=${demoRenderer}";

  dontUseZigCheck = true;
  dontSetZigDefaultFlags = true;

  hardeningDisable = lib.optionals buildDemo [
    "fortify"
  ];

  postInstall = lib.optionalString enableCApi ''
    mkdir -p $out/lib/pkgconfig
    substitute snail.pc.in $out/lib/pkgconfig/snail.pc \
      --replace-fail @PREFIX@ $out \
      --replace-fail @REQUIRES@ "${cApiRequires}"
  '';

  meta = {
    description = "GPU font and vector rendering via direct Bezier curve evaluation";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}

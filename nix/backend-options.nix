{ lib }:

{ enableOpenGL ? true
, enableOpenGLES ? true
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
  boolFlag = name: value: "-D${name}=${if value then "true" else "false"}";
in
{
  zigBuildFlags = [
    "--release=${optimize}"
    "-Dcpu=${cpu}"
    (boolFlag "opengl" enableOpenGL)
    (boolFlag "opengl-es" enableOpenGLES)
    (boolFlag "vulkan" enableVulkan)
    (boolFlag "cpu-renderer" enableCpu)
    (boolFlag "harfbuzz" enableHarfBuzz)
    (boolFlag "c-api" enableCApi)
    (boolFlag "c-api-shared" cApiShared)
    (boolFlag "c-api-static" cApiStatic)
  ];
}

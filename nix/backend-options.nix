{ lib }:

{ enableGL33 ? true
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
  boolFlag = name: value: "-D${name}=${if value then "true" else "false"}";
in
{
  zigBuildFlags = [
    "--release=${optimize}"
    "-Dcpu=${cpu}"
    (boolFlag "gl33" enableGL33)
    (boolFlag "gl44" enableGL44)
    (boolFlag "gles30" enableGLES30)
    (boolFlag "vulkan" enableVulkan)
    (boolFlag "raster" enableRaster)
    (boolFlag "harfbuzz" enableHarfBuzz)
    (boolFlag "c-api" enableCApi)
    (boolFlag "c-api-shared" cApiShared)
    (boolFlag "c-api-static" cApiStatic)
  ];
}

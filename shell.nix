{ pkgs ? import (import ./npins).nixpkgs { } }:

let
  inherit (pkgs) lib stdenv;

  # Unpacked HarfBuzz source tree: the cross-compiled demos
  # (`zig build run-minimal-d3d11`, `check-metal-demo`/`run-minimal-metal`)
  # compile the single-file amalgam (src/harfbuzz.cc) for the foreign
  # target instead of linking the host library. Same nixpkgs pin as the
  # `harfbuzz` package below, so shaping behavior matches the native demos.
  harfbuzzSrc = pkgs.runCommand "harfbuzz-src-${pkgs.harfbuzz.version}" { } ''
    mkdir -p $out
    tar --strip-components=1 -xf ${pkgs.harfbuzz.src} -C $out
  '';

  # Upstream wgpu-native Windows (x86_64-gnu) release: mingw import lib +
  # wgpu_native.dll for the cross-built Windows WebGPU gate
  # (`install-windows-gates` in build.zig). Version-matched to the nixpkgs
  # wgpu-native used by the native `run-minimal-wgpu` (27.0.4.0), so both
  # legs exercise the same wgpu.
  wgpuNativeWindows = pkgs.fetchzip {
    url = "https://github.com/gfx-rs/wgpu-native/releases/download/v27.0.4.0/wgpu-windows-x86_64-gnu-release.zip";
    sha256 = "0fdjfhha27mfwvqcnyvy8c0yj8gjd4782yfm7sq3pc1al4m52cil";
    stripRoot = false;
  };
in
pkgs.mkShell ({
  packages = with pkgs; [
    zig_0_16
    pkg-config
    harfbuzz
    # Pixel gates (CI + local): explicit differing-pixel counts via `magick`.
    imagemagick
    # Headless WebGPU reference example (`zig build run-minimal-wgpu`):
    # Vulkan/GL backends on Linux, Metal on macOS.
    wgpu-native
    # Build-time shader generation (the `snail-shaders*` modules): slangc
    # for every target, spirv-cross for the GL dialects. Needed on every
    # platform since generation moved out of git — the aggregate contract
    # tests (zig build test) and the Metal demo's MSL both generate.
    shader-slang
    spirv-cross
    # naga CLI: static-validation tripwire for the subpixel WGSL artifact
    # (prelude-injected dual-source entry) — run by `zig build test` and
    # `gen-shaders` on every platform, never by consumer scopes.
    wgpu-utils
  ] ++ lib.optionals stdenv.isLinux [
    libGL
    # DRI drivers + EGL vendor file for the headless GL gates (llvmpipe);
    # see the env vars below.
    mesa
    wayland
    wayland-protocols
    wayland-scanner
    vulkan-loader
    vulkan-headers
    vulkan-validation-layers
    # Headless D3D11 reference example (`zig build run-minimal-d3d11`):
    # runs the cross-compiled Windows exe; Wine's built-in d3dcompiler_47
    # is the FXC-class compiler for the generated HLSL artifacts. Needs
    # the development branch: stable wine 11.0's bundled vkd3d-shader
    # crashes compiling autohint.vert.hlsl (11.6 compiles all nine).
    wine64Packages.unstable
    # Wine's D3D11 needs a display connection to enumerate a GPU adapter;
    # on displayless machines (CI) run the gate as
    # `xvfb-run -a zig build run-minimal-d3d11` (GL goes to llvmpipe).
    xvfb-run
  ];

  # HarfBuzz amalgam source for the cross-compiled demos (see above).
  HARFBUZZ_SRC = "${harfbuzzSrc}";

  # wgpu-native ships no pkg-config file; build.zig picks these up for the
  # minimal WebGPU example (all platforms — Metal backend on macOS).
  WGPU_NATIVE_INCLUDE = "${pkgs.wgpu-native.dev}/include";
  WGPU_NATIVE_LIB = "${pkgs.wgpu-native}/lib";
} // lib.optionalAttrs stdenv.isLinux {
  LD_LIBRARY_PATH = lib.makeLibraryPath (with pkgs; [
    libGL
    wayland
    harfbuzz
    vulkan-loader
    wgpu-native
  ]);

  # The wgpu-native Windows release tree (include/ + lib/ with the mingw
  # import lib and wgpu_native.dll) for the cross-built Windows WebGPU gate.
  SNAIL_WGPU_WINDOWS = "${wgpuNativeWindows}";

  # GL comes fully from the pin: glvnd dispatches to this mesa (llvmpipe
  # under LIBGL_ALWAYS_SOFTWARE for the headless gates) instead of
  # whatever the host happens to ship — CI runners ship nothing.
  __EGL_VENDOR_LIBRARY_DIRS = "${pkgs.mesa}/share/glvnd/egl_vendor.d";
  LIBGL_DRIVERS_PATH = "${pkgs.mesa}/lib/dri";

  # The pinned mesa's lavapipe (software Vulkan) ICD manifest. Not exported
  # as VK_DRIVER_FILES directly so local machines keep their real GPU by
  # default; the headless Vulkan gates opt in with
  #   VK_DRIVER_FILES=$SNAIL_LAVAPIPE_ICD zig build run-screenshot-vulkan
  SNAIL_LAVAPIPE_ICD = "${pkgs.mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json";
})

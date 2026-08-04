#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repo_root"

# Failure diff images land here and are uploaded as a CI artifact, so a red
# image gate is adjudicated from the artifact instead of a local re-render.
ci_diff_dir="${CI_DIFF_DIR:-zig-out/ci-diffs}"

group() {
    printf '\n==> %s\n' "$1"
}

run() {
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
    "$@"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ci: missing %s; enter nix-shell first\n' "$1" >&2
        exit 1
    fi
}

require_variable() {
    if [[ -z "${!1:-}" ]]; then
        printf 'ci: missing %s; enter nix-shell first\n' "$1" >&2
        exit 1
    fi
}

configure_linux_software_rendering() {
    if [[ "$(uname -s)" != Linux ]]; then
        printf 'ci: %s requires a Linux host\n' "$mode" >&2
        exit 1
    fi

    require_variable SNAIL_MESA_EGL_VENDOR_DIR
    require_variable SNAIL_MESA_DRI_DIR
    require_variable SNAIL_LAVAPIPE_ICD

    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    export __EGL_VENDOR_LIBRARY_DIRS="$SNAIL_MESA_EGL_VENDOR_DIR"
    export LIBGL_DRIVERS_PATH="$SNAIL_MESA_DRI_DIR"
}

# On a failed image gate, write a visual diff + side-by-side into ci_diff_dir
# so the failure is legible from the uploaded artifact. Best-effort: no magick,
# missing inputs, or a convert error never masks the underlying gate failure.
emit_diff() {
    local reference=$1
    local actual=$2
    local label
    command -v magick >/dev/null 2>&1 || return 0
    [[ -f "$reference" && -f "$actual" ]] || return 0
    label="$(basename "${actual%.*}")"
    mkdir -p "$ci_diff_dir"
    magick "$reference" "$actual" -alpha off -compose difference -composite \
        -auto-level "$ci_diff_dir/${label}.diff.png" 2>/dev/null || true
    magick "$reference" "$actual" +append \
        "$ci_diff_dir/${label}.side-by-side.png" 2>/dev/null || true
    printf 'ci: wrote %s/%s.{diff,side-by-side}.png\n' "$ci_diff_dir" "$label" >&2
}

# Byte-exact gate for the deterministic CPU rasterizer. On mismatch, point at
# the bless command and emit a diff image.
gate_exact() {
    local reference=$1
    local actual=$2
    if cmp -s "$reference" "$actual"; then
        printf '%s matches %s (exact)\n' "$actual" "$reference"
        return 0
    fi
    printf 'FAIL: %s differs from %s (exact gate).\n' "$actual" "$reference" >&2
    printf "      If the render change is intended, run 'zig build update-goldens' and commit.\n" >&2
    emit_diff "$reference" "$actual"
    return 1
}

pixel_count() {
    local reference=$1
    local actual=$2
    local threshold=$3

    magick "$reference" "$actual" \
        -alpha off \
        -compose difference \
        -composite \
        -separate \
        -evaluate-sequence max \
        -threshold "${threshold}%" \
        -format '%[fx:round(mean*w*h)]' \
        info:
}

gate_pixels() {
    local reference=$1
    local actual=$2
    local threshold=$3
    local limit=$4
    local measured

    measured="$(pixel_count "$reference" "$actual" "$threshold")"
    case "$measured" in
        ''|*[!0-9]*)
            printf 'ci: unexpected ImageMagick output: %q\n' "$measured" >&2
            exit 1
            ;;
    esac
    printf '%s vs %s: %s pixels over %s%% channel delta (limit %s)\n' \
        "$actual" "$reference" "$measured" "$threshold" "$limit"
    if (( measured > limit )); then
        emit_diff "$reference" "$actual"
        return 1
    fi
}

ci_tests() {
    group 'Formatting and public modules'
    run actionlint
    run shellcheck dev/ci.sh
    run zig fmt --check build.zig build src dev
    run zig build test -Dcpu=baseline
}

ci_linux_gl() {
    configure_linux_software_rendering
    group 'GL / GLES / CPU gates (llvmpipe)'
    run zig build run-backend-compare -Dcpu=baseline
    run zig build run-composite-probe -Dcpu=baseline
    run zig build run-coverage-probe -Dcpu=baseline
    run zig build run-coverage-parity -Dcpu=baseline
    run zig build run-gamma-probe -Dcpu=baseline
    run zig build run-minimal-gl -Dcpu=baseline
}

ci_linux_vulkan() {
    configure_linux_software_rendering
    require_command magick
    require_command cmp

    group 'CPU rasterizer screenshots'
    run zig build run-screenshot -Dcpu=baseline
    run zig build run-banner-screenshot -Dcpu=baseline
    gate_exact zig-out/demo-screenshot.tga dev/demo/tools/screenshots/demo_cpu_reference.tga

    group 'Vulkan screenshots (lavapipe)'
    run env VK_DRIVER_FILES="$SNAIL_LAVAPIPE_ICD" zig build run-screenshot-vulkan -Dcpu=baseline
    run env VK_DRIVER_FILES="$SNAIL_LAVAPIPE_ICD" zig build run-banner-screenshot-vulkan -Dcpu=baseline
    gate_pixels zig-out/demo-screenshot.tga zig-out/demo-screenshot-vulkan.tga 4 2000
    gate_pixels zig-out/banner-screenshot.tga zig-out/banner-screenshot-vulkan.tga 4 2000

    group 'Game-scene screenshots (GL33 / GL44 / GLES30 / Vulkan)'
    run zig build run-game-screenshot -Dcpu=baseline
    run env VK_DRIVER_FILES="$SNAIL_LAVAPIPE_ICD" zig build run-game-screenshot-vulkan -Dcpu=baseline
    gate_pixels zig-out/game-gl33.tga zig-out/game-gl44.tga 4 4000
    gate_pixels zig-out/game-gl33.tga zig-out/game-gles30.tga 4 4000
    gate_pixels zig-out/game-gl33.tga zig-out/game-vulkan.tga 4 4000
}

ci_linux_wgpu_wine() {
    local wine_prefix="$repo_root/zig-out/wineprefix"

    configure_linux_software_rendering
    require_command magick
    require_command xvfb-run
    require_command timeout
    require_command wine

    group 'WebGPU GL backend (llvmpipe)'
    run env SNAIL_WGPU_BACKEND=gl zig build run-minimal-wgpu -Dcpu=baseline
    gate_pixels dev/demo/app/minimal_reference.png zig-out/minimal-wgpu.tga 4 2000

    group 'D3D11 under Wine'
    run xvfb-run -a zig build run-minimal-d3d11 -Dcpu=baseline
    gate_pixels dev/demo/app/minimal_reference.png zig-out/minimal-d3d11.tga 4 2000

    group 'Windows gate artifacts'
    run zig build install-windows-gates -Dcpu=baseline

    group 'Windows WebGPU D3D12 under Wine / vkd3d / lavapipe'
    (
        cd zig-out/windows-gates
        run env \
            WINEPREFIX="$wine_prefix" \
            WINEDEBUG=-all \
            VK_DRIVER_FILES="$SNAIL_LAVAPIPE_ICD" \
            SNAIL_WGPU_BACKEND=d3d12 \
            xvfb-run -a timeout 600 wine snail-minimal-wgpu.exe
    )
    gate_pixels \
        dev/demo/app/minimal_reference.png \
        zig-out/windows-gates/zig-out/minimal-wgpu.tga \
        4 \
        2000
}

ci_windows_wine_smoke() {
    local wine_prefix="$repo_root/zig-out/wineprefix"

    configure_linux_software_rendering
    require_command xvfb-run
    require_command wine

    group 'Prebuilt Windows D3D11 and CPU gates under Wine'
    (
        cd zig-out/windows-gates
        run env WINEPREFIX="$wine_prefix" WINEDEBUG=-all xvfb-run -a wine snail-minimal-d3d11.exe
        run env WINEPREFIX="$wine_prefix" WINEDEBUG=-all wine pixelgate.exe minimal_reference.tga zig-out/minimal-d3d11.tga 2000
        run env WINEPREFIX="$wine_prefix" WINEDEBUG=-all wine snail-screenshot-cpu.exe
        run env WINEPREFIX="$wine_prefix" WINEDEBUG=-all wine pixelgate.exe demo_cpu_reference.tga zig-out/demo-screenshot.tga 0
    )
}

ci_consumer_builds() {
    group 'Release-mode consumer builds'
    run zig build install-demo --release=fast -Dcpu=baseline
    run zig build install-game --release=fast -Dcpu=baseline
    run zig build install-perf --release=fast -Dcpu=baseline
}

ci_cross() {
    group 'Cross-platform compile gates'
    run zig build check-metal-demo -Dcpu=baseline
}

ci_nix() {
    require_command nix-build
    group 'Nix package'
    run nix-build default.nix --no-out-link -A demo
}

ci_all() {
    ci_tests
    ci_linux_gl
    ci_linux_vulkan
    ci_linux_wgpu_wine
    ci_windows_wine_smoke
    ci_consumer_builds
    ci_cross
    ci_nix
}

mode=${1:-all}
require_command zig
if [[ "$mode" == all || "$mode" == tests ]]; then
    require_command actionlint
    require_command shellcheck
fi
case "$mode" in
    all) ci_all ;;
    tests) ci_tests ;;
    linux-gl) ci_linux_gl ;;
    linux-vulkan) ci_linux_vulkan ;;
    linux-wgpu-wine) ci_linux_wgpu_wine ;;
    windows-wine-smoke) ci_windows_wine_smoke ;;
    consumer-builds) ci_consumer_builds ;;
    cross) ci_cross ;;
    nix) ci_nix ;;
    *)
        printf 'usage: %s {all|tests|linux-gl|linux-vulkan|linux-wgpu-wine|windows-wine-smoke|consumer-builds|cross|nix}\n' "$0" >&2
        exit 2
        ;;
esac

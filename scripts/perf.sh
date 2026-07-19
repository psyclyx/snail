#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
current_prefix=${PERF_PREFIX:-"$repo_dir/zig-out/perf"}
baseline_prefix=
run_gpu=1
quick=0

usage() {
  cat <<'EOF'
usage: scripts/perf.sh [--baseline PREFIX] [--no-gpu] [--quick]

Builds ReleaseFast, native-CPU regression runners. CPU runners time public
operations internally after fixture setup and print normalized workload
counters. PREFIX is a previously built install-perf prefix containing the same
runners. GPU cases use GL timer queries over the shipped GLSL draw calls.
EOF
}

while (($#)); do
  case "$1" in
    --baseline)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      baseline_prefix=$2
      shift 2
      ;;
    --no-gpu)
      run_gpu=0
      shift
      ;;
    --quick)
      quick=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v zig >/dev/null || { echo "zig is required" >&2; exit 1; }

cd "$repo_dir"
zig build install-perf --release=fast -Dcpu=native --prefix "$current_prefix"

required_runners=(snail-perf-prep snail-perf-raster)
if ((run_gpu)); then required_runners+=(snail-perf-glsl); fi
for runner in "${required_runners[@]}"; do
  [[ -x "$current_prefix/bin/$runner" ]] || { echo "missing runner: $current_prefix/bin/$runner" >&2; exit 1; }
  if [[ -n "$baseline_prefix" && ! -x "$baseline_prefix/bin/$runner" ]]; then
    echo "missing baseline runner: $baseline_prefix/bin/$runner" >&2
    exit 1
  fi
done

if ((quick)); then
  cpu_samples=3
  gpu_draws=8
  gpu_samples=5
else
  cpu_samples=15
  gpu_draws=32
  gpu_samples=15
fi

run_cpu_case() {
  local runner=$1
  local case_name=$2
  shift 2
  echo "current/$runner/$case_name"
  "$current_prefix/bin/$runner" "$case_name" --samples "$cpu_samples" "$@"
  if [[ -n "$baseline_prefix" ]]; then
    echo "baseline/$runner/$case_name"
    "$baseline_prefix/bin/$runner" "$case_name" --samples "$cpu_samples" "$@"
  fi
}

prep_cases=(
  shape-latin
  shape-multiscript
  place-run
  curves-unhinted
  truetype-prepare
  curves-truetype
  autohint-setup
  autohint-setup-nonlatin
  analyze-autohint
  path-prepare
  path-pack
  atlas-build-text
  atlas-build-truetype
  atlas-build-autohint
  atlas-build-path
  atlas-build-mixed
  atlas-build-colr
  atlas-upload-plan
  emit-text
  emit-truetype
  emit-autohint
  emit-path
  emit-mixed
  emit-colr
)

echo "CPU preparation microbenchmarks"
for case_name in "${prep_cases[@]}"; do
  run_cpu_case snail-perf-prep "$case_name"
done

raster_cases=(
  "text-gray|serial"
  "text-lcd|serial"
  "text-truetype|serial"
  "text-autohint|serial"
  "text-colr|serial"
  "path|serial"
  "mixed|serial"
  "mixed|auto"
)

echo
echo "CPU raster microbenchmarks"
for spec in "${raster_cases[@]}"; do
  IFS='|' read -r case_name threads <<<"$spec"
  run_cpu_case snail-perf-raster "$case_name" --threads "$threads"
done

if ((run_gpu)); then
  gpu_cases=(text-gray text-lcd text-truetype text-autohint text-autohint-fallback text-colr path text-sample-8 text-sample-32)
  echo
  echo "GPU timer-query microbenchmarks"
  for case_name in "${gpu_cases[@]}"; do
    echo "current/snail-perf-glsl/$case_name"
    "$current_prefix/bin/snail-perf-glsl" "$case_name" --draws "$gpu_draws" --samples "$gpu_samples"
    if [[ -n "$baseline_prefix" ]]; then
      echo "baseline/snail-perf-glsl/$case_name"
      "$baseline_prefix/bin/snail-perf-glsl" "$case_name" --draws "$gpu_draws" --samples "$gpu_samples"
    fi
  done
fi

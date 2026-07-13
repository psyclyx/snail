#!/usr/bin/env bash
set -euo pipefail
zig build run-autohint-character-diff >/tmp/snail-autohint-research.log 2>&1
TSV=zig-out/autohint-character-diff/metrics.tsv
awk -F '\t' '
NR>1 {
  if ($1=="dejavu") { total += $6; by_policy[$5] += $6 }
  if ($1=="noto") noto += $6
}
END {
  printf "METRIC dejavu_total=%d\n", total
  printf "METRIC dejavu_y=%d\n", by_policy["y"]
  printf "METRIC dejavu_x_natural=%d\n", by_policy["x-natural"]
  printf "METRIC dejavu_x_full=%d\n", by_policy["x-full"]
  printf "METRIC dejavu_xy_registered=%d\n", by_policy["xy-registered"]
  printf "METRIC noto_total=%d\n", noto
}' "$TSV"

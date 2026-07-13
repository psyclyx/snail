#!/usr/bin/env bash
set -euo pipefail
zig build test >/tmp/snail-autohint-checks.log 2>&1 || { tail -80 /tmp/snail-autohint-checks.log; exit 1; }

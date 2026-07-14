#!/usr/bin/env bash
set -euo pipefail
zig build test >/tmp/snail-autohint-checks.log 2>&1 || { tail -80 /tmp/snail-autohint-checks.log; exit 1; }
# Smoke-test the demo too: `zig build test` doesn't compile src/demo, so a
# stale demo (e.g. against a changed hinting API) would otherwise rot unseen.
zig build run-screenshot >/tmp/snail-autohint-checks.log 2>&1 || { tail -80 /tmp/snail-autohint-checks.log; exit 1; }

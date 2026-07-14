# Autohint Quality Optimization

Status: completed

## Result

25 experiments were evaluated against the fixed per-character harness.

- Baseline `dejavu_total`: 3,601,838
- Final `dejavu_total`: 3,572,829
- Improvement: 29,009 (0.805%, lower is better)
- Final `noto_total`: 2,471,489

Retained changes and discarded experiments are documented in `.auto/prompt.md` and branch history.

## Final externally rerunnable verification

Working directory:

```text
/home/psyc/projects/snail
```

Branch:

```text
autoresearch/autohint-quality-2026-07-13
```

Environment variables: none required beyond the project development shell.

Command:

```bash
./.auto/checks.sh && ./.auto/measure.sh
```

Output summary:

```text
checks: passed
METRIC dejavu_total=3572829
METRIC dejavu_y=1049115
METRIC dejavu_x_natural=889926
METRIC dejavu_x_full=816894
METRIC dejavu_xy_registered=816894
METRIC noto_total=2471489
```

Required artifacts are preserved in `.auto/`, the Zig build cache, and `zig-out/autohint-character-diff/`.

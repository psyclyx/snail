# Autohint Character Diff Harness

## Goal

Create a deterministic CPU harness for iterating on composable autohint quality character by character. It compares explicit harness-local policies against the TrueType path for `a-zA-Z0-9!@#$%^*()[]{}+=` at integer PPEMs 9 through 14.

## Comparisons

The harness evaluates DejaVu Sans Mono and Noto Sans Mono. It marks Noto's TrueType-path reference as a fallback because that variable font has no TrueType VM.

Four harness-local policies isolate fitting operations:

- `y`: blue-zone/light y fitting; identity x.
- `x-natural`: `y` plus x-grid alignment with natural stem widths.
- `x-full`: `y` plus full x width fitting with independently positioned stems.
- `xy-relative`: `y` plus full x width fitting, relative positioning, and round-left registration.

These are diagnostic constants, not library presets.

## Isolation and rendering

Each corpus character is shaped and rendered alone in an identical fixed cell. Candidate and reference use the same origin, baseline, em, coverage transfer, and explicit origin snapping. A character never shares a render target with a neighbor, so neighboring glyph overlap cannot affect its metric.

The primary metric uses zero registration correction. A bounded rigid-shift search is reported separately as a diagnostic.

## Metrics

For every `(font, PPEM, character, policy)`, report:

- summed absolute ink difference;
- pixels whose difference exceeds 40;
- normalized error divided by total TrueType ink (zero-safe);
- candidate-only ink;
- reference-only ink;
- best rigid x/y shift and residual.

Terminal output prints totals and worst characters. A TSV contains one row per comparison in stable corpus/policy order.

## Visual output

For every font and PPEM, write one TGA contact sheet under `zig-out/autohint-character-diff/`. Rows follow corpus order. Columns contain:

1. character/index label;
2. TrueType reference;
3. each of the four policy renders;
4. one red/green diff for each policy.

Red is reference-only ink, green is candidate-only ink, and gray is agreement. Dimensions and filenames are deterministic.

## Build integration and tests

Add `zig build run-autohint-character-diff`.

Tests cover exact corpus/order, policy names/order, metric arithmetic, output naming/dimensions, isolated shaping/rendering assumptions, immutable analysis reuse, and an explicit 12-PPEM `m` row. The full project tests and harness command must pass before completion.

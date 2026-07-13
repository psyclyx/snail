# Autoresearch: composable autohint quality

## Objective
Minimize per-character pixel disagreement between composable autohint policies and DejaVu Sans Mono's TrueType rendering for corpus `a-zA-Z0-9!@#$%^*()[]{}+=` at 9–14 PPEM. Use the generated contact sheets and TSV to localize regressions. Preserve caller-explicit composability and PPEM-independent resources.

## Metrics
- Primary: `dejavu_total` summed absolute per-pixel ink difference across y, x-natural, x-full, and xy-relative (lower is better).
- Secondary: each DejaVu policy total and `noto_total` (Noto reference is unhinted fallback, so treat it as a distortion monitor, not the target).

## How to Run
`./.auto/measure.sh`

## Files in Scope
- `src/snail/font/autohint/warp.zig`: policy-driven transient fitting.
- `src/snail/font/autohint/analysis.zig`: immutable edge/stem analysis.
- `src/snail/font/autohint/blue.zig`: blue-zone derivation.
- `src/snail/font/autohint/producer.zig`: immutable glyph/font features and regression tests.
- `src/snail/render/backend/glsl/snail_autohint_warp.glsl`: exact GPU mirror of retained fitting changes.
- `src/demo/autohint_character_diff.zig`: diagnostic harness-local policies/metrics.
- `src/demo/autohint_compare.zig`: demo-local policy constants, updated only when a generally better policy is retained.

## Off Limits
- Per-PPEM or per-policy atlas resources/caches.
- TrueType VM behavior or reference rendering.
- Corpus, PPEM range, coverage exponent, cell registration, metric calculation, or reference images.
- New dependencies.

## Constraints
- Primary metric decides keep/discard; do not hide regressions by changing measurement.
- CPU and GLSL behavior must remain equivalent.
- `./.auto/checks.sh` must pass for retained changes.
- Inspect worst-character rows in TSV/contact sheets; avoid trading catastrophic glyph regressions for tiny aggregate wins.
- Prefer simple general fitting rules over font/character-specific exceptions.

## What's Been Tried
- Baseline uses adjacent-pitch rounding with a post-translation that keeps repeated stems evenly spaced and right-bounded.
- Discarded: lowered light y stem cutoff 1.6→1.4. All metrics were bit-identical, so current corpus y stems do not cross that threshold.

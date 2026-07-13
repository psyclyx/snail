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
- Discarded: raised overshoot suppression threshold 0.5→0.75px. Metrics were bit-identical; no corpus overshoot lies in that interval at 9–14 PPEM.
- Discarded: natural y stem widths (blue positioning only). DejaVu worsened 3,601,838→3,747,906 across every policy, although Noto distortion improved; light y width fitting is valuable for TT agreement.
- Kept: full y stem-width fitting instead of the 1.6px light cutoff. Deterministic DejaVu total improved 3,601,838→3,600,874 (241 per policy), Noto unchanged. Synced demo y/xy examples.
- Kept: independent x-stem positioning with round-left registration. DejaVu strong policy improved 821,686→819,196 and Noto total improved 2,478,278→2,463,025. Renamed the diagnostic policy from `xy-relative` to `xy-registered` so its name remains truthful; this isolates registration beyond `x-full`.
- Discarded: disabled x standard-width matching (`std_snap_ratio=0`). Metrics were bit-identical; all affected stems quantize to the same pixel widths at 9–14 PPEM.
- Discarded: removed round-left registration from xy-relative. DejaVu xy worsened 821,686→832,766; registration is a clear win, despite a 488-point Noto improvement.
- Kept: round-left registration on x-full. DejaVu x-full improved 830,276→819,196 (total 3,598,384→3,587,304); Noto rose only 488. x-full temporarily duplicates xy-registered, so the next experiment must repurpose one diagnostic policy.
- Kept: round-left registration on x-natural. DejaVu x-natural improved 899,313→888,233 (total 3,587,304→3,576,224); Noto rose 488. Registration is independently beneficial with natural and full widths.
- Discarded: natural-width relative x positioning with registration for the fourth policy. DejaVu policy worsened 819,196→889,710, though Noto improved strongly; relative positioning is not TT-like for this corpus.
- Discarded: y grid alignment without blue zones (overshoot preserved for validity). DejaVu worsened 3,576,224→3,740,105 across all policies; font-global blues are essential. Noto again preferred less intervention.
- Discarded: suppress all overshoots with a 10px threshold. Metrics were bit-identical; DejaVu/Noto overshoots are already suppressed throughout 9–14 PPEM.
- Kept: disabled y standard-width substitution while retaining full pixel fitting (`std_snap_ratio=0`). DejaVu total improved 3,576,224→3,573,547; y -484, x-natural -693, each registered full mode -750. Noto unchanged. Synced demo policies.
- Discarded: translate round-left outline by first-stem fitted delta instead of independently snapping it. DejaVu worsened 3,573,547→3,606,787; direct bowl snapping is substantially more TT-like. Noto improved only 1,464.

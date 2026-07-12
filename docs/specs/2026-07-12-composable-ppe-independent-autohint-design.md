# Composable PPEM-Independent Autohinting

## Goal

Provide autohinting as explicit rendering building blocks rather than opinionated named modes, while restoring the intended resource contract: changing effective pixels-per-em or autohint policy must not require atlas extension or resource upload.

TrueType hinting remains the only hinting path that prepares and stores separate per-PPEM glyph geometry.

## Public API

`HintMode` will expose three paths:

- `unhinted`: unchanged generic glyph rendering;
- `autohint`: generic glyph rendering plus a caller-supplied `AutohintPolicy`;
- `truetype`: existing per-PPEM TrueType preparation and baked curves.

The library will not define `auto`, `auto_light`, `normal`, or similar presets. Applications may define their own policy constants.

`AutohintPolicy` contains typed, per-axis policy structs. Enums are preferred over a loose boolean bitset so unsupported or contradictory combinations are not representable. The initial policy surface exposes the independent operations already implemented by the current autohinter:

- edge alignment: none, device grid, or blue zones where applicable;
- stem-width treatment: natural, light thresholded fitting, or full fitting;
- stem positioning: independent or relative to an anchor stem;
- overshoot treatment: preserve or suppress below an explicit threshold;
- outline registration: none or left-round-outline registration.

Axis types may differ where an operation is meaningful on only one axis. For example, blue-zone alignment and overshoot treatment belong to the y policy, while left-outline registration belongs to the x policy. Every numeric threshold that affects behavior is caller-visible or supplied explicitly through the policy; no named strength level hides tuned values.

A representative conservative application configuration can select y blue-zone alignment and light y stem treatment while leaving x untouched. A stronger configuration can additionally select full x stem fitting, relative x positioning, and round-left registration. These are examples and demo-local constants, not public presets.

## Policy validation

Construction or preparation validates dependencies between operations. Invalid combinations produce a clear error or are excluded by the type structure rather than silently changing policy. Examples include relative stem positioning without x stem alignment, or overshoot suppression without blue-zone alignment.

The renderer treats `none` operations as identity. Empty, unsupported, malformed, degenerate, or over-feature-limit analysis falls back to ordinary unhinted rendering.

## Resource architecture

The current autohint atlas entry stores final `(base, target)` warp knots for a particular PPEM. It will be replaced by one PPEM-independent analysis record per glyph. The record contains only facts required to derive fitting at render time:

- ordered edge positions for each relevant axis;
- stem pair and relationship information plus natural widths;
- blue-zone association and round/flat classification;
- glyph-local registration inputs;
- references to immutable font-level blue zones and standard widths.

The record aliases the ordinary unhinted glyph's curves and band placement. Its resource key identifies the font and glyph, but not PPEM and not policy. Font-global analysis metadata is likewise immutable and uploaded at most once with the font/atlas resource, never once per PPEM.

Changing size, transform, or `AutohintPolicy` must not call `Atlas.extend`, create a new glyph resource key, or upload layer-slab data. All policies share the same glyph geometry and analysis record.

## Render-time fitting

The renderer derives effective pixels-per-em independently for each glyph axis from the local-to-device transform already used to determine the analytic coverage footprint. It combines this scale, immutable analysis, font metadata, and caller policy to derive fitted targets and evaluate the inverse coordinate warp.

Derived targets may use a small fixed-size temporary array during a CPU invocation or shader invocation, but they must never become persistent atlas data or a cache keyed by PPEM or policy.

The fitting primitives remain defined once conceptually and mirrored by CPU and GLSL implementations. Their behavior includes:

- snapping selected edges or blue references to the current device grid;
- preserving or conditionally suppressing overshoot;
- retaining natural widths, threshold-fitting widths, or fully fitting widths;
- positioning stems independently or relative to the first eligible stem;
- optionally registering the leftmost round outline;
- evaluating the monotone inverse warp and adjusting the analytic AA footprint.

Non-uniform transforms use axis-specific scale. Degenerate transforms use identity fitting on the affected axis. CPU, GL, and GLES paths must produce equivalent fitting within existing numeric tolerances.

## Placement and draw data

The `AutohintPolicy` is draw/instance state, not glyph resource state. Its bounded enum values and explicit thresholds are encoded in instance data or another immutable draw parameter channel available to CPU, GL, and GLES backends. Backend dispatch must remain exhaustive.

Autohinted base curves remain in em space, so local scale remains `em`. TrueType retains `em / ppem_px` scaling and its PPEM-bearing mode value.

Origin snapping remains an explicit placement operation rather than an implicit autohint preset. Applications using strong x-grid fitting can request per-glyph origin snapping; applications using only y fitting can preserve natural horizontal placement. The API documentation will explain this interaction without forcing a policy.

## Interactive and headless comparisons

The interactive comparison toggled by **V** will show four labeled rows for every tested size:

1. `un` — unhinted;
2. `y` — a demo-local conservative policy with y blue alignment/light stem treatment and identity x;
3. `xy` — a demo-local policy reproducing the current strong x+y behavior;
4. `tt` — TrueType.

The headless comparison screenshot will use the same ordering, labels, and policies. The autohint-versus-TrueType metric tooling will compare the demo's strong `xy` policy against TrueType, preserving its current purpose. Tool names and descriptions will use `autohint` rather than a removed named mode.

The demo constants serve only as examples of composing primitives. They are not exported from the library and do not establish recommended defaults.

## Compatibility and migration

This intentionally replaces `.auto_light` with `.autohint = policy` rather than renaming it:

- current strong `.auto_light` call sites migrate to an explicit policy matching existing x+y behavior;
- callers wanting less intervention compose a smaller policy;
- per-PPEM autohint keys, target-knot records, and related atlas extension paths are removed;
- producer and documentation names are generalized from `AutoLight` to autohint analysis/fitting terminology;
- compatibility aliases are added only if required by an established public API stability policy, and must not preserve per-PPEM resources.

Documentation will describe the actual immutable-analysis/render-time-fitting split and clearly distinguish it from TrueType's prepared per-PPEM geometry.

## Testing

Automated tests will verify:

- autohint resource keys are identical across PPEMs and policies;
- preparing or drawing at a new PPEM does not extend or replace the atlas;
- changing policy does not create or upload resources;
- each fitting primitive behaves independently;
- meaningful primitive combinations compose correctly;
- invalid combinations are rejected or unrepresentable;
- a conservative y-only demo policy derives identity x fitting;
- the strong demo policy preserves representative current x/y results;
- all policies share base geometry and immutable analysis storage;
- TrueType remains distinct and per-PPEM;
- CPU and GLSL fitting/inverse-warp parity;
- GL/GLES dispatch and policy decoding are exhaustive;
- placement scale and explicit origin snapping work with all three hint paths;
- V-gated and headless comparison grids contain all four rows with correct labels and policy wiring;
- malformed, degenerate, and over-feature-limit cases fall back safely.

Visual regression output from the comparison grid will be inspected alongside the automated suite, with attention to the y-only example preserving natural horizontal proportions and the strong example retaining current crisp stem rhythm.

## Non-goals

- Defining library-owned autohint strength presets.
- Reimplementing TrueType bytecode hinting.
- Persisting or caching derived targets by PPEM or policy anywhere in the resource system.
- Adding arbitrary user-authored shader pass graphs; composition is limited to the typed fitting primitives supported consistently by every backend.
- Retuning the current strong behavior except where required to reproduce it from immutable analysis at render time.

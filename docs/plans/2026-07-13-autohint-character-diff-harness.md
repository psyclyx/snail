# Autohint Character Diff Harness Implementation Plan


**Goal:** Add a deterministic per-character autohint-versus-TrueType visual and numeric comparison harness.

**Architecture:** Reuse `Compare` atlas population and `screenshot_harness` CPU rendering. Render each character into an isolated fixed cell, calculate metrics from ink buffers, and compose per-font/PPEM TGA sheets plus a stable TSV.

**Tech Stack:** Zig, CPU renderer, existing TGA screenshot support, Zig build system.

## Global Constraints

- Corpus is exactly `a-zA-Z0-9!@#$%^*()[]{}+=` in that order.
- PPEMs are exactly 9 through 14 inclusive.
- Policies are harness-local `y`, `x-natural`, `x-full`, `xy-relative`.
- No policy/PPEM-specific autohint resource uploads.
- Character renders are isolated from neighbors.
- Primary scores use identical zero-offset registration.

### Task 1: Pure report model and metrics

**Files:** Create `src/demo/autohint_character_diff.zig`.

- [ ] Add failing tests for corpus/order, policy names, filenames/dimensions, and metric arithmetic.
- [ ] Run `zig build test` and confirm failure because the harness module is not imported.
- [ ] Implement constants, `Metrics`, ink extraction, diff calculation, stable TSV formatting helpers, and contact-sheet geometry.
- [ ] Import the module from the demo/core test root used by `zig build test`.
- [ ] Run tests and commit.

### Task 2: Isolated rendering and resource preparation

**Files:** Modify `src/demo/autohint_character_diff.zig`; reuse `src/demo/autohint_compare.zig` interfaces.

- [ ] Add failing tests proving each row shapes one character and that 12-PPEM `m` has its own row.
- [ ] Implement per-font setup, corpus shaping, one-time atlas analysis/TT preparation for 9–14, fixed-cell CPU rendering, empty-outline fallback, and bounded best-shift diagnostics.
- [ ] Assert atlas record count does not grow while iterating policies/sizes.
- [ ] Run tests and commit.

### Task 3: Contact sheets, TSV, and build step

**Files:** Modify `src/demo/autohint_character_diff.zig`, `build.zig`.

- [ ] Add failing build/output tests for deterministic paths and sheet dimensions.
- [ ] Compose label/reference/candidate/diff columns, write TGA sheets and `metrics.tsv`, print totals/worst characters.
- [ ] Add `zig build run-autohint-character-diff` with the same module imports/options as the existing diff executable.
- [ ] Run `zig build test` and the new harness; inspect one DejaVu and one Noto sheet.
- [ ] Commit.

### Task 4: Final verification

- [ ] Run `zig fmt --check` on changed Zig files and `git diff --check`.
- [ ] Run `zig build test --summary all`, `zig build`, and `zig build run-autohint-character-diff`.
- [ ] Confirm TSV row count is `2 * 6 * corpus_len * 4 + 1`, all expected sheets exist, and the worktree is clean after commit.

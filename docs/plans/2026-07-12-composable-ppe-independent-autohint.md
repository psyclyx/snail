# Composable PPEM-Independent Autohinting Implementation Plan


**Goal:** Replace the named, per-PPEM `auto_light` path with explicit composable autohint policies over one immutable per-glyph analysis resource, deriving all fitted targets at render time.

**Architecture:** Analyze each glyph once into em-normalized axis features and pack those features beside the shared unhinted glyph reference. Carry a validated `AutohintPolicy` as instance state; CPU and GPU backends combine that policy, the transform-derived axis scale, and immutable features to build transient inverse-warp data. TrueType remains the only per-PPEM resource path.

**Tech Stack:** Zig, immutable atlas/page resources, CPU analytic renderer, GLSL 330/GLES 3.0/Vulkan GLSL shaders, Zig build/test tooling.

## Global Constraints

- The library defines no named autohint strength presets.
- Autohint resource identity contains font and glyph identity only—never PPEM or policy.
- Changing transform, effective PPEM, or policy must not extend or upload the atlas.
- Derived targets are invocation-local and must not be persisted or cached by PPEM/policy.
- CPU, GL, GLES, and Vulkan implementations must remain behaviorally equivalent.
- Unsupported, malformed, degenerate, and over-feature-limit input falls back to identity/unhinted rendering.
- Origin snapping remains explicit placement policy.
- Existing strong autohint behavior is preserved as a demo-local policy, not a public preset.

---

## File Structure

- `src/snail/font/autohint/policy.zig`: public typed policy and validation/packing.
- `src/snail/font/autohint/analysis.zig`: existing edge detection; expose stable serializable edge facts.
- `src/snail/font/autohint/producer.zig`: produce immutable glyph/font analysis without PPEM.
- `src/snail/font/autohint/warp.zig`: transient target derivation and inverse warp from features + policy + axis scale.
- `src/snail/render/format/autohint_record.zig`: immutable feature-record ABI, replacing target-knot records.
- `src/snail/atlas.zig`, `src/snail/atlas/builder.zig`, `src/snail/atlas/record_key.zig`: PPEM-independent analysis entries and lookup.
- `src/snail/picture/shape.zig`, `src/snail/picture/emit.zig`, `src/snail/render/format/vertex.zig`: carry policy as instance state.
- `src/snail/render/backend/cpu/renderer.zig`: transient CPU fitting.
- `src/snail/render/backend/glsl/snail_autohint_warp.glsl`, `snail_autohint_main.glsl`, `src/snail/render/backend/vulkan_glsl/snail_autohint.frag`: transient GPU fitting.
- `src/snail-helpers/text_picture.zig`, `src/snail-helpers/glyph_atlas_cache.zig`: public placement/cache migration.
- `src/demo/autohint_compare.zig`, `autohint_screenshot.zig`, `autohint_diff.zig`, `main.zig`: four-row policy comparison and tooling.
- `src/snail/root.zig`, `src/snail-helpers/root.zig`, `README.md`, `build.zig`: exports and documentation/tool naming.

---

### Task 1: Define the explicit policy API

**Files:**
- Create: `src/snail/font/autohint/policy.zig`
- Modify: `src/snail/root.zig`
- Test: `src/snail/font/autohint/policy.zig`

**Interfaces:**
- Produces: `AutohintPolicy`, `XPolicy`, `YPolicy`, `StemWidth`, `StemPositioning`, `Overshoot`, `OutlineRegistration`, `PolicyError`, `validate`, `pack`, and `unpack`.
- Packing contract: a policy round-trips through a fixed four-word representation suitable for instance data; threshold floats remain exact bit patterns.

- [ ] **Step 1: Write failing policy construction and round-trip tests**

```zig
test "policy round-trips without named presets" {
    const p: AutohintPolicy = .{
        .x = .{
            .align = .grid,
            .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
            .positioning = .relative,
            .registration = .left_round_outline,
        },
        .y = .{
            .align = .blue_zones,
            .stem_width = .{ .light = .{ .std_snap_ratio = 0.4, .max_px = 1.6 } },
            .overshoot = .{ .suppress_below_px = 0.5 },
        },
    };
    try p.validate();
    try testing.expectEqualDeep(p, try AutohintPolicy.unpack(p.pack()));
}

test "dependent operations reject missing alignment" {
    const p: AutohintPolicy = .{ .x = .{ .positioning = .relative } };
    try testing.expectError(error.PositioningRequiresAlignment, p.validate());
}

test "overshoot suppression requires blue zones" {
    const p: AutohintPolicy = .{ .y = .{ .align = .grid, .overshoot = .{ .suppress_below_px = 0.5 } } };
    try testing.expectError(error.OvershootRequiresBlueZones, p.validate());
}
```

- [ ] **Step 2: Run the tests and verify the missing module/API failure**

Run: `zig build test`

Expected: FAIL because `policy.zig` and its exported types do not exist.

- [ ] **Step 3: Implement typed policies and fixed packing**

Use tagged unions for threshold-bearing choices, not public preset constants:

```zig
pub const StemWidth = union(enum) {
    natural,
    light: struct { std_snap_ratio: f32, max_px: f32 },
    full: struct { std_snap_ratio: f32 },
};

pub const Overshoot = union(enum) {
    preserve,
    suppress_below_px: f32,
};

pub const XPolicy = struct {
    align: enum { none, grid } = .none,
    stem_width: StemWidth = .natural,
    positioning: enum { independent, relative } = .independent,
    registration: enum { none, left_round_outline } = .none,
};

pub const YPolicy = struct {
    align: enum { none, grid, blue_zones } = .none,
    stem_width: StemWidth = .natural,
    overshoot: Overshoot = .preserve,
};
```

Implement `validate()` with finite/non-negative threshold checks and the dependencies asserted above. Implement `pack()`/`unpack()` with explicit masks and `@bitCast` threshold words; reserve invalid enum patterns and return `error.InvalidEncoding` rather than coercing them.

- [ ] **Step 4: Export the policy API and run tests**

Add under `snail.autohint` in `src/snail/root.zig`:

```zig
pub const policy = @import("font/autohint/policy.zig");
pub const AutohintPolicy = policy.AutohintPolicy;
```

Run: `zig build test`

Expected: PASS, including policy validation and exact round trips.

- [ ] **Step 5: Commit**

```bash
git add src/snail/font/autohint/policy.zig src/snail/root.zig
git commit -m "feat(autohint): add composable policy API"
```

---

### Task 2: Produce immutable PPEM-independent analysis

**Files:**
- Modify: `src/snail/font/autohint/analysis.zig`
- Modify: `src/snail/font/autohint/blue.zig`
- Modify: `src/snail/font/autohint/producer.zig`
- Modify: `src/snail/root.zig`
- Test: `src/snail/font/autohint/producer.zig`

**Interfaces:**
- Consumes: policy-independent edge facts from `analysis.zig`.
- Produces: `AutohintAnalyzer.init(allocator, font_data)`, `analyzeGlyph(scratch, glyph_id, x_buf, y_buf) !GlyphFeatures`, and `fontFeatures() FontFeatures`.
- `GlyphFeatures` is em-normalized and owns no PPEM-derived targets: `{ x: []const FeatureEdge, y: []const FeatureEdge, left: f32 }`.
- `FontFeatures` carries em-normalized blue references/shoots and standard x/y widths.

- [ ] **Step 1: Write failing PPEM-independence tests**

```zig
test "glyph analysis contains features but no fitted targets" {
    var analyzer = try AutohintAnalyzer.init(testing.allocator, test_font);
    defer analyzer.deinit();
    var xb: [warp.max_knots]FeatureEdge = undefined;
    var yb: [warp.max_knots]FeatureEdge = undefined;
    const a = try analyzer.analyzeGlyph(testing.allocator, glyph_h, &xb, &yb);
    try testing.expect(a.x.len > 0);
    try testing.expect(a.y.len > 0);
    try testing.expect(@hasField(FeatureEdge, "pos"));
    try testing.expect(!@hasField(FeatureEdge, "target"));
}

test "repeated analysis has one result independent of size" {
    const a = try analyzer.analyzeGlyph(testing.allocator, glyph_h, &xb, &yb);
    const b = try analyzer.analyzeGlyph(testing.allocator, glyph_h, &xb2, &yb2);
    try testing.expectEqualSlices(FeatureEdge, a.x, b.x);
    try testing.expectEqualSlices(FeatureEdge, a.y, b.y);
}
```

Use the existing test-font fixture/import pattern already present in `producer.zig`.

- [ ] **Step 2: Run tests and verify failure on the old `glyphKnots(ppem)` API**

Run: `zig build test`

Expected: FAIL because only `AutoLight.glyphKnots(..., ppem_26_6, ...)` exists.

- [ ] **Step 3: Add a stable serializable feature type**

Define in `analysis.zig`:

```zig
pub const FeatureEdge = struct {
    pos: f32,
    width: f32,
    stem: i16,
    blue: i16,
    flags: packed struct(u16) { round: bool, _reserved: u15 = 0 },
};
```

Keep transient segment extents/directions private to analysis. Convert analyzed edges to em units in `producer.zig`, assigning y blues before conversion. Compute `left` from the flattened outline and normalize it by UPM. Normalize `Blues` and standard widths into `FontFeatures` once.

- [ ] **Step 4: Replace the PPEM-bearing producer API**

Rename `AutoLight` to `AutohintAnalyzer`, remove `ppem_26_6` from glyph production, and return immutable features rather than knots. Keep no compatibility method that computes/stores per-PPEM results. Export `AutohintAnalyzer`, `GlyphFeatures`, and `FontFeatures` from `src/snail/root.zig`.

- [ ] **Step 5: Run tests**

Run: `zig build test`

Expected: PASS. Keep the existing `glyphKnots` entry point as a private migration adapter in this task: implement it by calling `analyzeGlyph` followed by the existing fitter, and mark its removal in Task 4 when `fitGlyph` replaces it. Do not export the adapter from `root.zig` or use it to create a new resource format.

- [ ] **Step 6: Commit**

```bash
git add src/snail/font/autohint/analysis.zig src/snail/font/autohint/blue.zig src/snail/font/autohint/producer.zig src/snail/root.zig
git commit -m "refactor(autohint): make glyph analysis PPEM independent"
```

---

### Task 3: Replace per-PPEM knot records with immutable feature records

**Files:**
- Modify: `src/snail/render/format/autohint_record.zig`
- Modify: `src/snail/atlas.zig`
- Modify: `src/snail/atlas/builder.zig`
- Modify: `src/snail/atlas/record_key.zig`
- Modify: `src/snail/root.zig`
- Test: the same files' inline tests

**Interfaces:**
- Consumes: `GlyphFeatures` and `FontFeatures` from Task 2.
- Produces: `AutohintAnalysis`, `recordKey.autohintGlyph(font_id, glyph_id)` and feature-record readers for both CPU and shader ABI.
- Record layout: base band header, normalized font metrics, normalized glyph `left`, x feature run, y feature run. It contains no target and no PPEM.

- [ ] **Step 1: Replace record tests with immutable-analysis round-trip tests**

```zig
test "autohint record round-trips immutable features" {
    const x = [_]FeatureEdge{.{ .pos = 0.1, .width = 0.08, .stem = 1, .blue = -1, .flags = .{ .round = false } }};
    const y = [_]FeatureEdge{.{ .pos = 0.5, .width = 0.07, .stem = -1, .blue = 2, .flags = .{ .round = true } }};
    writeRecord(buf, off, be, font_features, .{ .x = &x, .y = &y, .left = 0.02 });
    try testing.expectEqualSlices(FeatureEdge, &x, xFeatures(buf, off));
    try testing.expectEqualSlices(FeatureEdge, &y, yFeatures(buf, off));
}

test "autohint key ignores size and policy" {
    const key = autohintGlyph(3, 42);
    try testing.expectEqual(@as(u32, 0), key.c);
}
```

- [ ] **Step 2: Run tests and confirm old record/key signatures fail**

Run: `zig build test`

Expected: FAIL because records still accept knots and keys require `ppem_26_6`.

- [ ] **Step 3: Implement immutable feature serialization**

Replace `AutohintKnots` with:

```zig
pub const AutohintAnalysis = struct {
    font: autohint.FontFeatures,
    glyph: autohint.GlyphFeatures,
};
```

Pack each `FeatureEdge` into four floats: `pos`, `width`, bitcast packed `(stem, blue)`, and bitcast flags. Store fixed font metrics before variable runs. Add bounds checks for `warp.max_knots`, blue count, and slab dimensions before mutation.

- [ ] **Step 4: Make atlas identity PPEM-independent**

Change:

```zig
pub fn autohintGlyph(font_id: u32, glyph_id: u16) RecordKey {
    return .{ .namespace = ns.autohint_glyph, .a = font_id, .b = glyph_id, .c = 0 };
}
```

Update `Atlas.Entry.autohint` to `?AutohintAnalysis`, retain `autohint_base`, and update builder insertion/lookup to write one feature record. Compute a conservative quad expansion from maximum one-device-pixel displacement rather than a fitted target; if the transform makes static bbox expansion impossible, encode/use the base bbox and expand the emitted device bounds by two pixels in Task 5.

- [ ] **Step 5: Prove one record serves multiple sizes/policies**

Add an atlas test that inserts one base plus one analysis entry, looks up the same key for two synthetic PPEMs/policies, and asserts page count, layer slab length, and lookup root identity do not change.

Run: `zig build test`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/snail/render/format/autohint_record.zig src/snail/atlas.zig src/snail/atlas/builder.zig src/snail/atlas/record_key.zig src/snail/root.zig
git commit -m "refactor(autohint): store immutable feature records"
```

---

### Task 4: Derive transient fitted targets from policy and scale

**Files:**
- Modify: `src/snail/font/autohint/warp.zig`
- Test: `src/snail/font/autohint/warp.zig`

**Interfaces:**
- Consumes: `FeatureEdge`, `FontFeatures`, `AutohintPolicy`.
- Produces: `fitAxis(features, font, axis_policy, pixels_per_em, left, out) []Knot` and `fitGlyph(..., scale: Vec2, x_out, y_out) AxisKnots`.
- `Knot` remains transient and is never accepted by atlas APIs.

- [ ] **Step 1: Write failing primitive-composition tests**

```zig
test "identity x policy emits no knots" {
    const n = fitAxis(x_edges, font, .x, .{}, 13.0, left, &out);
    try testing.expectEqual(@as(usize, 0), n.len);
}

test "light y policy leaves thick stem width natural" {
    const policy: YPolicy = .{
        .align = .blue_zones,
        .stem_width = .{ .light = .{ .std_snap_ratio = 0.4, .max_px = 1.6 } },
        .overshoot = .{ .suppress_below_px = 0.5 },
    };
    const knots = fitAxis(y_edges, font, .y, policy, 13.0, 0, &out);
    try testing.expectApproxEqAbs(natural_thick_width, fittedWidth(knots), 1e-5);
}

test "strong x composition matches prior fitting" {
    const policy: XPolicy = .{
        .align = .grid,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
        .positioning = .relative,
        .registration = .left_round_outline,
    };
    const knots = fitAxis(x_edges, font, .x, policy, 13.0, left, &out);
    try expectKnotsApproxEq(prior_expected_knots, knots, 1e-5);
}
```

Also add zero/NaN scale, too-many-edge, independent positioning, natural width, preserved overshoot, and suppressed overshoot cases.

- [ ] **Step 2: Run focused tests and confirm missing fitter failure**

Run: `zig test src/snail/font/autohint/warp.zig`

Expected: FAIL because `fitAxis`/`fitGlyph` do not exist.

- [ ] **Step 3: Refactor existing `buildKnotsReg` into policy-driven fitting**

Retain the established snapping and monotonicity math but replace internal `Params` choices with explicit policy switches. Convert normalized feature positions to current pixel phase using `pixels_per_em`; output normalized `(base, target)` knots. Return an empty slice for identity/invalid scale/feature overflow.

- [ ] **Step 4: Keep inverse warp unchanged and run focused/full tests**

Run: `zig test src/snail/font/autohint/warp.zig && zig build test`

Expected: PASS, including old inverse-warp parity tests and new composition tests.

- [ ] **Step 5: Commit**

```bash
git add src/snail/font/autohint/warp.zig
git commit -m "feat(autohint): derive fitting from policy at render time"
```

---

### Task 5: Carry policy in instances and fit in the CPU renderer

**Files:**
- Modify: `src/snail/picture/shape.zig`
- Modify: `src/snail/picture/emit.zig`
- Modify: `src/snail/render/format/vertex.zig`
- Modify: `src/snail/render/format/draw_records.zig`
- Modify: `src/snail/render/backend/cpu/renderer.zig`
- Test: inline tests in those files

**Interfaces:**
- Consumes: packed policy, immutable feature record, `fitGlyph`.
- Produces: `Shape.autohint_policy: ?AutohintPolicy`, autohint instance decoding, and CPU rendering with transient knots.

- [ ] **Step 1: Write failing emission/CPU tests**

Add tests asserting two shapes with one autohint key and different policies share atlas lookup data but emit distinct packed policies. Add a CPU test rendering one glyph at 12px then 17px from the same atlas and assert the atlas page/slab pointers and lengths are unchanged while output coverage differs.

```zig
try testing.expectEqual(shape_a.key, shape_b.key);
try testing.expect(!std.mem.eql(u32, emittedPolicy(words_a), emittedPolicy(words_b)));
try testing.expectEqual(before.layer_info_data.ptr, atlas.layer_info_data.?.ptr);
try testing.expectEqual(before.layer_info_data.len, atlas.layer_info_data.?.len);
```

- [ ] **Step 2: Run tests and verify missing shape/instance fields**

Run: `zig build test`

Expected: FAIL because policy is not carried by shapes or vertices.

- [ ] **Step 3: Add policy to shape and instance encoding**

Add nullable policy to the text shape data. Require it when the key resolves to autohint analysis; reject a policy on non-autohint records. Extend the autohint special instance payload with the four packed policy words. Update stride constants, cursors, CPU decoding, replicated-instance paths, and ABI tests together.

- [ ] **Step 4: Fit once per CPU glyph draw**

In `renderTransformedAutohintGlyph`, derive axis pixels-per-em from the transform columns, decode immutable features, call `fitGlyph` into stack arrays, and pass transient `AutohintWarp` to coverage evaluation. Expand raster bounds by two device pixels before clipping so snapped extrema cannot clip. Do not write to atlas/cache memory.

- [ ] **Step 5: Verify CPU behavior and immutability**

Run: `zig build test`

Expected: PASS; the new test proves size and policy changes do not mutate/upload resources.

- [ ] **Step 6: Commit**

```bash
git add src/snail/picture/shape.zig src/snail/picture/emit.zig src/snail/render/format/vertex.zig src/snail/render/format/draw_records.zig src/snail/render/backend/cpu/renderer.zig
git commit -m "feat(autohint): fit explicit policies in CPU renderer"
```

---

### Task 6: Mirror transient fitting in GL, GLES, and Vulkan

**Files:**
- Modify: `src/snail/render/backend/glsl/snail_autohint_warp.glsl`
- Modify: `src/snail/render/backend/glsl/snail_autohint_main.glsl`
- Modify: `src/snail/render/backend/vulkan_glsl/snail_autohint.frag`
- Modify: `src/snail/render/backend/gl/shaders.zig`
- Modify: `src/snail/render/backend/gles30/shaders.zig`
- Modify: `src/snail/render/format/abi.zig`
- Test: `src/snail/font/autohint/warp.zig`, shader compilation build steps

**Interfaces:**
- Consumes: packed policy varyings/instance words and immutable feature record.
- Produces: GLSL policy decoding and fixed-array target derivation matching Zig `fitGlyph`.

- [ ] **Step 1: Add shader-source ABI assertions before changing shaders**

Extend Zig parity/source tests to require symbols:

```zig
try testing.expect(std.mem.indexOf(u8, glsl, "snailDecodeAutohintPolicy") != null);
try testing.expect(std.mem.indexOf(u8, glsl, "snailFitAutohintAxis") != null);
try testing.expect(std.mem.indexOf(u8, glsl, "target") == null or std.mem.indexOf(u8, glsl, "storedTarget") == null);
```

Add CPU-generated fixtures covering identity x, blue y, full relative x, overshoot preserve/suppress, and degenerate scale; compare fixture targets/slopes against a host-side GLSL-equivalent evaluator already used by parity tests.

- [ ] **Step 2: Run tests and verify shader symbols are absent**

Run: `zig build test`

Expected: FAIL on new shader-source/parity assertions.

- [ ] **Step 3: Replace stored-target fetches with feature decoding and fitting**

In shared GLSL, decode feature tuples and policy words, calculate axis PPEM from `dFdx`/`dFdy` footprint, fill fixed arrays of at most `max_knots`, and evaluate inverse warp. Keep loops statically bounded for GLES 3.0. Treat invalid enum words, non-finite/zero scale, and excessive counts as identity.

Apply equivalent code to Vulkan GLSL, preserving descriptor/layout conventions. Update vertex/varying interfaces only as needed for packed policy words.

- [ ] **Step 4: Compile and test all shader variants**

Run: `zig build test && zig build`

Expected: PASS; GL 330, GLES 3.0, replicated variants, and Vulkan shader generation compile.

- [ ] **Step 5: Run headless CPU/GL parity artifact**

Run: `zig build run-autohint-screenshot`

Expected: command exits 0 and writes `zig-out/autohint-screenshot.tga` and `zig-out/autohint-screenshot-gl.tga` without shader errors.

- [ ] **Step 6: Commit**

```bash
git add src/snail/render/backend/glsl src/snail/render/backend/vulkan_glsl/snail_autohint.frag src/snail/render/backend/gl/shaders.zig src/snail/render/backend/gles30/shaders.zig src/snail/render/format/abi.zig
git commit -m "feat(autohint): fit explicit policies in GPU backends"
```

---

### Task 7: Migrate helpers and remove per-PPEM cache behavior

**Files:**
- Modify: `src/snail-helpers/text_picture.zig`
- Modify: `src/snail-helpers/glyph_atlas_cache.zig`
- Modify: `src/snail-helpers/root.zig`
- Test: inline tests in helper files

**Interfaces:**
- Consumes: `HintMode.autohint: AutohintPolicy`, PPEM-independent `recordKey.autohintGlyph`.
- Produces: unified placement using em scale and explicit `RunSnap`; cache stores one immutable analysis per glyph.

- [ ] **Step 1: Write failing helper tests**

```zig
test "autohint mode key is independent of policy" {
    const a: HintMode = .{ .autohint = y_policy };
    const b: HintMode = .{ .autohint = xy_policy };
    try testing.expect(a.key(2, 44).eql(b.key(2, 44)));
    try testing.expectEqual(@as(f32, 16), a.scale(16));
}

test "autohint cache entry is reused across sizes" {
    try ensureAutohint(&cache, analyzer, glyph, policy_a);
    const count = cache.count();
    try ensureAutohint(&cache, analyzer, glyph, policy_b);
    try testing.expectEqual(count, cache.count());
}
```

- [ ] **Step 2: Run tests and confirm old `.auto_light { ppem }` API failure**

Run: `zig build test`

Expected: FAIL at old `HintMode.auto_light` and per-PPEM cache signatures.

- [ ] **Step 3: Migrate placement and cache storage**

Change `HintMode` to:

```zig
pub const HintMode = union(enum) {
    unhinted,
    autohint: snail.autohint.AutohintPolicy,
    truetype: struct { ppem_26_6: u32 },
};
```

Make `.autohint` use em scale and `recordKey.autohintGlyph(font_id, glyph_id)`. Remove stored x/y knot arrays and PPEM from cache identity; store immutable feature arrays plus font metadata. Keep `RunSnap` independent and document why strong x policies normally pair with `.origins` or `.columns`.

- [ ] **Step 4: Run tests and inspect for forbidden PPEM autohint APIs**

Run:

```bash
zig build test
grep -R "autohintGlyph(.*ppem\|auto_light\|glyphKnots" -n src/snail src/snail-helpers
```

Expected: tests PASS; grep prints no active API/code matches (historical migration comments should also be rewritten).

- [ ] **Step 5: Commit**

```bash
git add src/snail-helpers/text_picture.zig src/snail-helpers/glyph_atlas_cache.zig src/snail-helpers/root.zig
git commit -m "refactor(helpers): reuse autohint analysis across policies and sizes"
```

---

### Task 8: Expand the V-gated demo and headless tools

**Files:**
- Modify: `src/demo/autohint_compare.zig`
- Modify: `src/demo/autohint_screenshot.zig`
- Modify: `src/demo/autohint_diff.zig`
- Modify: `src/demo/main.zig`
- Modify: `build.zig`
- Test: demo build/run steps

**Interfaces:**
- Produces only demo-local `y_policy` and `xy_policy` constants; neither is exported by library modules.
- Comparison order is exactly `un`, `y`, `xy`, `tt`.

- [ ] **Step 1: Add failing row-order and resource-reuse tests**

Expose a private testable row descriptor:

```zig
const rows = [_]Row{
    .{ .tag = "un", .mode = .unhinted, .snap = .none },
    .{ .tag = "y", .mode = .{ .autohint = y_policy }, .snap = .none },
    .{ .tag = "xy", .mode = .{ .autohint = xy_policy }, .snap = .columns },
    .{ .tag = "tt", .mode = .{ .truetype = .{ .ppem_26_6 = 0 } }, .snap = .columns },
};

test "comparison contains four policy rows" {
    try testing.expectEqualStrings("un", rows[0].tag);
    try testing.expectEqualStrings("y", rows[1].tag);
    try testing.expectEqualStrings("xy", rows[2].tag);
    try testing.expectEqualStrings("tt", rows[3].tag);
}
```

Add a comparison setup test asserting all grid PPEMs create one autohint record per unique glyph, while TrueType keys remain per-PPEM.

- [ ] **Step 2: Run tests and verify the old three-row grid fails**

Run: `zig build test`

Expected: FAIL because the comparison still has `un/au/tt` and builds autohint records per PPEM.

- [ ] **Step 3: Define explicit demo-local policies**

Define `y_policy` with identity x, blue y alignment, light thresholded y width, and 0.5px overshoot suppression. Define `xy_policy` by explicitly spelling the same y choices plus grid/full/relative/left-round x choices. Do not place these constants under `src/snail` or `src/snail-helpers`.

- [ ] **Step 4: Populate analysis once and render four rows**

Make `Compare.ensureAll` insert unhinted base + one immutable analysis per glyph outside the PPEM loop. Keep only TrueType preparation inside the grid-PPEM loop. Update labels, vertical layout, help text printed by `V`, screenshot dimensions, and comments.

- [ ] **Step 5: Migrate the diff tool to the strong demo policy**

Render `.autohint = xy_policy` against TrueType. Rename user-facing text from “auto_light vs TrueType” to “autohint xy policy vs TrueType”. Update the build-step description without changing the command name unless a rename is necessary for correctness.

- [ ] **Step 6: Run demo verification**

Run:

```bash
zig build test
zig build
zig build run-autohint-screenshot
zig build run-autohint-diff
```

Expected: all commands exit 0; screenshot has four rows per PPEM; diff output names the `xy` policy; no autohint atlas growth occurs while iterating sizes.

- [ ] **Step 7: Commit**

```bash
git add src/demo/autohint_compare.zig src/demo/autohint_screenshot.zig src/demo/autohint_diff.zig src/demo/main.zig build.zig
git commit -m "feat(demo): compare composable autohint policies"
```

---

### Task 9: Remove stale terminology, document the contract, and verify

**Files:**
- Modify: `README.md`
- Modify: comments in all autohint files changed above
- Modify: `CHANGELOG.md` only if this branch's workflow records unreleased API changes there
- Test: full build, unit tests, grep checks, visual artifacts

**Interfaces:**
- Documents: explicit policy construction, immutable resource identity, transform-derived fitting, explicit origin snapping, and TrueType distinction.

- [ ] **Step 1: Add documentation examples using explicit policy**

Include a complete snippet that builds a y-only policy, inserts one immutable analysis entry, places text with `.mode = .{ .autohint = policy }`, and chooses `.snap = .none`. Include a second short snippet showing how an application extends x policy and explicitly selects origin snapping. State that neither is a library recommendation/preset.

- [ ] **Step 2: Rewrite stale claims and names**

Run:

```bash
grep -R "auto_light\|per-ppem.*knot\|ppem.*autohintGlyph\|AutoLight" -n README.md CHANGELOG.md src build.zig
```

For every match, either migrate it to composable autohint terminology or retain it only in a clearly historical changelog sentence. Ensure current docs never call stored target knots resolution-independent because target knots are no longer stored.

- [ ] **Step 3: Run formatting and full automated verification**

Run:

```bash
zig fmt build.zig src
zig build test
zig build
zig build run-autohint-screenshot
zig build run-autohint-diff
```

Expected: formatting makes no subsequent changes; all commands exit 0; CPU and GL screenshots are generated; diff tool completes.

- [ ] **Step 4: Verify the resource contract directly**

Run: `zig build test`

Confirm the suite includes these exact test declarations in their owning files before running:

- `autohint key ignores size and policy`
- `autohint cache entry is reused across sizes`
- `changing autohint policy does not mutate atlas`
- `comparison analysis count is independent of grid PPEMs`

Expected: command exits 0, proving all four contract tests PASS.

- [ ] **Step 5: Inspect visual output**

Open or inspect `zig-out/autohint-screenshot.tga` and the GL counterpart. Confirm each PPEM shows `un`, `y`, `xy`, `tt`; `y` preserves natural horizontal proportions; `xy` retains crisp current stem rhythm; no row clips after render-time warp.

- [ ] **Step 6: Review the final diff for forbidden resource coupling**

Run:

```bash
git diff HEAD~8 -- src | grep -E "autohint.*ppem|ppem.*autohint|policy.*RecordKey|RecordKey.*policy" || true
git status --short
```

Expected: no active autohint resource key or atlas extension depends on PPEM/policy; status contains only intentional documentation changes.

- [ ] **Step 7: Commit**

```bash
git add README.md CHANGELOG.md src build.zig
git commit -m "docs: explain composable PPEM-independent autohinting"
```

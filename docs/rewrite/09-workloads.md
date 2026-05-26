# Workloads

Concrete patterns for the target consumers. Each shows how the primitives
compose for that workload's lifecycle and shape.

## Terminal emulator

Heavy text, one ppem usually, hinted, streaming new glyphs as content
scrolls in. Atlases grow monotonically; rarely shrink.

```zig
// Init.
var font = try Font.init(gpa, ttf_bytes);
var hinter = try Hinter.init(gpa, &font);
var pool = try renderer.createPagePool(.{ .max_layers = 16 });
var atlas = Atlas.empty(gpa);
var binding: ?Binding = null;

const ppem = HintPpem.uniform(13 * 64);

// Per redraw (often partial-row only).
fn redrawRow(state: *State, row: u32) !void {
    const dirty_spans = state.dirtySpansForRow(row);
    for (dirty_spans) |span| {
        const shaped = try shape(scratch, &state.font_chain, span.text, .{});
        defer shaped.deinit();
        const keys = try shapedKeysHinted(scratch, &shaped, font_id, ppem);
        defer scratch.free(keys);

        const result = try state.atlas.extendWith(gpa, scratch, keys,
            state.hinter.providerAt(ppem));
        if (result.new_atlas.recordCount() != state.atlas.recordCount()) {
            var old = state.atlas;
            state.atlas = result.new_atlas;
            old.deinit();
            state.binding = try pool.uploadIncremental(allocs, &state.atlas, state.binding);
        }

        const pic = try shapedRunPicture(scratch, &shaped, .{
            .baseline = state.baselineFor(row, span.col_start),
            .em = state.em,
            .color = state.fg_for(span),
            .ns = ns.hinted_glyph,
            .variant = ppem.packed(),
        });
        defer pic.deinit();

        try emit(state.words, state.segs, &state.wl, &state.sl,
                 state.binding.?, &state.atlas, &pic, .identity, .{1,1,1,1});
    }
}

fn finishFrame(state: *State) !void {
    try renderer.draw(state.draw_state,
        .{ .words = state.words[0..state.wl], .segments = state.segs[0..state.sl] },
        &.{ &pool });
    state.wl = 0;
    state.sl = 0;
}
```

Primitives used: `Hinter`, `Atlas.extendWith`, `shape`, `shapedRunPicture`,
`emit`, `draw`. No subpixel (most terminals run on hidpi).

Fragmentation: minimal. The atlas grows as new glyphs appear; nothing is
ever evicted (atlas is bounded by font's glyph repertoire). No compaction
needed.

## Status bar / HUD (shoal)

Mixed text+vector, sparklines (instanced), multiple data sources, layer-shell
surfaces, theme-driven repaints.

Sparkline pattern, the canonical `emitInstanced` use:

```zig
// One-time init: cache a unit-rect picture.
var rect_curves = try pathToCurves(gpa, &unit_rect_path, .{});
defer rect_curves.deinit();
var rect_atlas = try Atlas.from(gpa, &pool, &.{.{
    .key = .{ .namespace = ns.user_base, .a = 0 },   // "unit rect"
    .curves = rect_curves,
}});
defer rect_atlas.deinit();
const rect_binding = try pool.upload(allocs, &rect_atlas);

const rect_picture = try Picture.from(gpa, &.{.{
    .key = .{ .namespace = ns.user_base, .a = 0 },
    .local_transform = .identity,
    .local_color = white,
}});
defer rect_picture.deinit();

// Per-frame.
fn drawSparkline(state: *State, op: SparklineOp) !void {
    var overrides = std.ArrayList(Override).empty;
    defer overrides.deinit(scratch);
    try buildSparklineOverrides(scratch, &overrides, op);

    _ = try emitInstanced(state.words, state.segs, &state.wl, &state.sl,
        rect_binding, &rect_atlas, &rect_picture, overrides.items);
}
```

For text labels, the text atlas is a separate object with its own
binding; emit calls alternate.

Picture caching: shoal can keep a hashmap of `(content_hash -> Picture)`
across frames. Pictures hold no resource refs, so caching is trivial.

## Code editor with zoom

Multiple ppems active simultaneously, syntax highlighting, scroll, search.

Pattern: one atlas per active ppem, dropped when no longer in use.

```zig
const HintedSlot = struct {
    atlas: Atlas,
    binding: Binding,
};

var hinted: std.AutoHashMapUnmanaged(u32, HintedSlot) = .empty;

fn ensureSlot(state: *State, ppem_key: u32) !*HintedSlot {
    const gop = try state.hinted.getOrPut(state.gpa, ppem_key);
    if (!gop.found_existing) {
        const a = Atlas.empty(state.gpa);
        const b = try state.pool.upload(allocs, &a);
        gop.value_ptr.* = .{ .atlas = a, .binding = b };
    }
    return gop.value_ptr;
}

fn onFontSizeNoLongerInUse(state: *State, ppem_key: u32) void {
    if (state.hinted.fetchRemove(ppem_key)) |kv| {
        var v = kv.value;
        v.atlas.deinit();
        state.hinter.evictPpem(HintPpem.unpacked(ppem_key));
    }
}
```

Syntax highlighting: each text run gets a color baked into its
`Shape.local_color`. Picture composition combines runs.

Search highlight overlays: stroked rectangles produced by `strokeToCurves`,
added to the same atlas (different `RecordKey.namespace`), drawn in a
separate Z-layer.

## Animation / ppem scrubbing

Per-frame ppem changes. Aggressive eviction.

```zig
fn afterFrame(state: *State) !void {
    state.hinter.clearGlyphs();    // drop curve points; keep VM warm

    // Drop atlases for ppems we're not near.
    var it = state.hinted_by_ppem.iterator();
    while (it.next()) |entry| {
        if (state.distanceFromCurrentPpem(entry.key_ptr.*) > 5) {
            var slot = entry.value_ptr.*;
            slot.atlas.deinit();
            _ = state.hinted_by_ppem.remove(entry.key_ptr.*);
        }
    }

    // Periodically compact the *current* ppem's atlas if fragmentation rises.
    const stats = state.pool.poolStats();
    if (stats.fragmentation() > 0.5) {
        var current = state.hinted_by_ppem.getPtr(state.current_ppem).?;
        const new_atlas = try current.atlas.compact(state.gpa, scratch);
        current.atlas.deinit();
        current.atlas = new_atlas;
        current.binding = try state.pool.upload(allocs, &current.atlas);
    }
}
```

## Creative tool / vector graphics editor

Animated paths, gradients, images, layers, undo/redo.

Animated paths produce a new `GlyphCurves` per frame for each animated
shape. The atlas accumulates; the caller compacts periodically (e.g., on
idle, or when fragmentation crosses a threshold).

Undo retention: each undo level holds a `Picture` snapshot. Pictures hold
keys, not records. As long as some atlas resolves the keys, the
undo-level picture works. When an undo level falls out of the stack, the
picture deinits; the keys may become unreachable; the atlas's records may
become dead.

The undo stack effectively pins atlas content. The caller can choose to
let this accumulate, or aggressively compact when the stack is pruned.

## Game HUD with world-space text

2D UI overlay plus text-on-3D-surfaces (signs, screens).

```zig
// HUD draws with screen-space MVP.
try renderer.draw(.{ .mvp = screen_mvp, .surface = ..., .raster = .{} },
    hud_records, &.{ &pool });

// World-space text: one DrawState per text-bearing surface (or batch with
// same MVP).
for (world_text_items) |item| {
    try renderer.draw(.{ .mvp = item.world_mvp, .surface = ..., .raster = .{} },
        item.records, &.{ &pool });
}
```

If state-changes-per-draw become a cost, callers can batch by MVP
(several text items with the same view matrix → one draw with one
`DrawState`) or compose transforms into the picture's `Shape.local_transform`.

## Document viewer (PDF-like)

Many pages, large static content, glyph reuse across pages.

One atlas per font, shared across pages. Pages reference the atlas via
their pictures. As pages scroll into view, their pictures are constructed
(once, cached for the document's lifetime).

`PagePool.max_layers` sized generously for the worst case. The viewer
must handle `error.OutOfLayers` when opening unusually-large documents
— either by reconstructing the pool with more capacity (re-upload), or by
splitting into multiple pools (rare).

## Streaming log viewer

Append-mostly text, virtualized rendering (only visible rows are
materialized into pictures).

Same shape as terminal, but with a virtualized window over a huge
scrollback. Pictures for off-screen rows are not held. The atlas
accumulates glyphs; for an English-language log this saturates quickly at
~95 characters and the atlas stops growing.

Search/filter changes the visible set: rebuild the visible pictures from
the filtered text. Cheap because pictures are pure data.

## Custom shader path

The user has their own renderer. They use snail purely as a curve data
producer.

```zig
var pool = try PagePool.initOffline(gpa, .{ .max_layers = 16 });
defer pool.deinit();

var atlas = try Atlas.from(gpa, &pool, entries);
defer atlas.deinit();

const desc = atlas.uploadDescriptor();
for (desc.pages) |page| {
    user_gl.uploadCurveLayer(page.layer_index, page.curve_data);
    user_gl.uploadBandLayer(page.layer_index, page.band_data);
}

for (picture.shapes) |shape| {
    const rec = atlas.lookupRecord(shape.key) orelse continue;
    user_gl.pushInstance(.{ /* their format */ });
}

user_gl.drawInstanced(my_shader_with_snail_coverage_helper);
```

No `Binding`, no `renderer.draw`, no `emit`. Just CPU-side primitives
producing data the user manages.

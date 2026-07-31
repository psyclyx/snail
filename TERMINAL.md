# Terminal-style cell grids

A terminal owns columns; font advances should not decide where the next cell
begins. Shape each dirty style run normally, then describe the host's cells
with source-byte ranges and explicit column numbers:

```zig
const text = "A🌍e\u{301}";
const cells = [_]snail.Cell{
    .{ .source = .{ .start = 0, .end = 1 }, .column = 0 },
    .{ .source = .{ .start = 1, .end = 5 }, .column = 1 }, // wide: next is 3
    .{ .source = .{ .start = 5, .end = 8 }, .column = 3 },
};
var shaped = try snail.shape(alloc, &faces, text, .{});
defer shaped.deinit();

// The cache identity is independent of font_id. It covers the bytes, face,
// and variation coordinates; the application chooses how to derive it.
const sources = [_]snail.FontSource{.{
    .font_id = terminal_font_id,
    .font = &font,
    .cache_key = terminal_font_cache_key,
}};

// Plan all dirty runs together. Planning does no outline extraction.
var plan = try snail.planRuns(
    &atlas,
    persistent_alloc,
    &sources,
    &.{&shaped},
    .{ .unhinted = .{ .colr = .layers } },
);
defer plan.deinit();

const owned = try persistent_alloc.alloc(
    ?snail.prepared.OwnedRecord,
    plan.requests().len,
);
defer persistent_alloc.free(owned);
@memset(owned, null);
defer for (owned) |*record| if (record.*) |*value| value.deinit();
const results = try persistent_alloc.alloc(
    ?snail.prepared.RecordView,
    plan.requests().len,
);
defer persistent_alloc.free(results);
@memset(results, null);

// This example executes locally. A real terminal may satisfy requests from
// prepared.Archive and dispatch only misses to its worker pool.
var outlines = snail.OutlineContext.init(persistent_alloc, scratch_alloc);
defer outlines.deinit();
for (plan.requests(), 0..) |request, i| {
    owned[i] = try outlines.prepare(request);
    results[i] = owned[i].?.view();
}
try plan.applyInPlace(persistent_alloc, &atlas, results);

const shapes = try snail.placeCellRunAlloc(alloc, &shaped, &faces, &cells, .{
    .baseline = .{ .x = 24, .y = 40 },
    .cell_width = 10,
    .em = 18,
    .snap = .grid,
    .world_to_pixel = world_to_pixel,
    .colr = true,
});
defer alloc.free(shapes);
```

`placeCellRun` anchors each HarfBuzz cluster to its assigned cell while
preserving mark, ligature, and fallback-face offsets within that cluster.
Per-cell color and `HintMode` are retained. A wide cell is represented by a
later following column; snail does not decide Unicode width, grapheme or
cursor policy, tabs, wrapping, paragraph bidi, or scrollback.

For unhinted and y-only autohinted content, `CellSnap.grid` keeps the baseline
and cell advance pixel-aligned. Strong two-axis autohinting and TrueType
hinting normally use `CellSnap.glyph_origins` so fitted x-stems do not land
at fractional device positions.

A practical update loop retains `Font` storage, `Faces`, `PagePool`, and
`Atlas`; shapes only changed row/style runs; builds one `PreparePlan` in the
matching mode; resolves its requests from archives or worker contexts;
rebuilds the cheap placed picture; and applies `planDelta` or
`DeviceAtlas.uploadDelta` to the existing binding.

Planning and applying are idempotent, so repeated characters add no atlas
work. Stable `font_id` values must identify the same stable `Font` pointers in
every `Faces` and `FontSource` set that feeds an atlas. `FontSource.cache_key`
is the separate disk-cache identity. Adding or reordering fallback faces
requires a new `Faces`, but existing atlas keys remain valid while the runtime
identities do not change.

## Cell-filling symbols

Do not fit an ordinary font glyph's ink bounds to a cell. Side bearings and
overshoot are part of the design, and non-uniform fitting distorts strokes.
It also cannot guarantee that adjacent box-drawing glyphs meet on the same
device pixels.

Filled Powerline separators are a different case: author them as unit
`[0, 1] × [0, 1]` paths, prepare and record each path once, then place its
`Shape` with a non-uniform transform whose x/y scales are the cell width and
height. They contain no strokes, so this is exact, scalable, and uses only
Snail's backend-neutral path/atlas API.

Box Drawing and Block Elements that must tile seamlessly should be generated
from the host's live device-pixel cell rectangle. Emit pixel-snapped solid
rectangles (or paths for the curved/diagonal cases), with light/heavy stroke
weights chosen by the terminal. This remains host policy: font-derived
weights, fixed pixel weights, and user-configurable weights are all reasonable
and Snail cannot select among them. The same geometry can feed a GPU host's
solid-rectangle path and `snail-raster`; it does not justify a GPU renderer
inside Snail.

This split is intentional. A generic “make glyph cell-sized” API would make
Powerline slightly shorter to express while giving the wrong semantics for
font glyphs and box drawing.

The current color-font path is COLRv0. Dynamic terminals can record
`ColrHandling.layers` and place with `colr = true`; that expands solid
palette layers into ordinary glyph shapes and avoids binding-relative paint
side-data growth. Composite COLR records instead use layer-info side data and
can require a new binding when its fixed reservation is exhausted.

The full demo is [`dev/demo/app/terminal.zig`](dev/demo/app/terminal.zig),
with an independent [cell model](dev/demo/terminal/screen.zig),
[simulation](dev/demo/terminal/simulation.zig), and
[snail-backed view](dev/demo/terminal/view.zig). Run it with:

```sh
zig build run-terminal
```

`R` resets, `P` pauses, `-`/`+` changes text size, `H` cycles hinting modes,
and `C` cycles renderers.

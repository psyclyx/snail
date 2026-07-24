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

// Batch all dirty runs into one idempotent atlas transaction in real code.
try snail.recordUnhintedRuns(
    &atlas, persistent_alloc, &faces, &.{&shaped}, .{ .colr = .layers },
);
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
`Atlas`; shapes only changed row/style runs; records those runs with the
matching plural verb (`recordUnhintedRuns`, `recordAutohintRuns`, or
`recordTtHintRuns`); rebuilds the cheap placed picture; and applies
`planDelta` or `DeviceAtlas.uploadDelta` to the existing binding.

Recording is idempotent, so repeated characters add no atlas work. Stable
`font_id` values must identify the same stable `Font` pointers in every
`Faces` that feeds an atlas. Adding or reordering fallback faces requires a
new `Faces`, but existing atlas keys remain valid while those identities do
not change.

The current color-font path is COLRv0. Dynamic terminals can record
`ColrHandling.layers` and place with `colr = true`; that expands solid
palette layers into ordinary glyph shapes and avoids binding-relative paint
side-data growth. Composite COLR records instead use layer-info side data and
can require a new binding when its fixed reservation is exhausted.

The full demo is [`src/demo/app/terminal.zig`](src/demo/app/terminal.zig),
with an independent [cell model](src/demo/terminal/screen.zig),
[simulation](src/demo/terminal/simulation.zig), and
[snail-backed view](src/demo/terminal/view.zig). Run it with:

```sh
zig build run-terminal
```

`R` resets, `P` pauses, `-`/`+` changes text size, `H` cycles hinting modes,
and `C` cycles renderers.

# Picture and emit

## `Picture`

A picture is a list of shapes with a bounding box. Pure data — no refcounts,
no page references, no atlas references. It's just a sequence of
`(record_key, local_transform, local_color, local_paint)` tuples.

```zig
pub const Picture = struct {
    allocator: std.mem.Allocator,
    shapes:    []const Shape,
    bbox:      BBox,
};
```

A picture is meaningful when paired with an atlas that resolves its keys.
Without an atlas, it's still a valid value — comparable, hashable, shareable —
but emit-time resolution will fail.

### Operations

```zig
pub fn empty(allocator: Allocator) Picture;
pub fn from(allocator: Allocator, shapes: []const Shape) !Picture;
pub fn concat(allocator: Allocator, pictures: []const *const Picture) !Picture;
pub fn append(self: *const Picture, allocator: Allocator, more: []const Shape) !Picture;
pub fn deinit(self: *Picture) void;
```

`concat` is the monoidal combine. Order is preserved (z-order matters), so
`concat` is associative but not commutative.

### Sub-picture manipulation

Picture is data; manipulation is straightforward:

```zig
pub fn slice(self: *const Picture, range: Range) Picture;        // borrowed view
pub fn replaceShapes(self: *const Picture, alloc: Allocator,
                     range: Range, replacements: []const Shape) !Picture;
pub fn transformed(self: *const Picture, alloc: Allocator,
                   t: Transform2D) !Picture;
pub fn without(self: *const Picture, alloc: Allocator,
               predicate: fn(Shape) bool) !Picture;
pub fn tinted(self: *const Picture, alloc: Allocator, tint: [4]f32) !Picture;
```

These are O(N) walks over shape data. No bookkeeping. The bbox can be
recomputed on construction or lazily on first query.

## `DrawRecords`

The output of emit. Two slices:

```zig
pub const DrawRecords = struct {
    words:    []const u32,
    segments: []const DrawSegment,
};

pub const DrawSegment = struct {
    kind:          Kind,
    binding:       Binding,
    words_offset:  u32,
    words_len:     u32,
    shape_count:   u32,
    override_count: u32,
};

pub const Kind = enum { heterogeneous, replicated };
```

`words` is the packed GPU vertex data. `segments` describes how to bind
state and dispatch each segment's draw. `draw()` walks segments, binds the
relevant pool's textures for each, and issues the appropriate draw call.

## Two emit primitives

The two GPU work patterns get two specialized shaders. The API surfaces this
because forcing one path through the other costs either CPU memory (outer
product materialization) or GPU time (uniform branch in a hot shader).

### Heterogeneous: `emit`

For pictures where each shape is drawn once, with its own transform and
color. Text runs, multi-shape vector compositions, layered UI.

```zig
pub fn emit(
    words_buf:     []u32,
    segs_buf:      []DrawSegment,
    word_len:      *usize,
    seg_len:       *usize,
    binding:       Binding,
    atlas:         *const Atlas,
    picture:       *const Picture,
    world_xform:   Transform2D,
    world_tint:    [4]f32,
) !EmitResult;
```

Produces one segment of `kind = .heterogeneous` with `picture.shapes.len`
GPU instances. Each instance carries the shape's resolved `AtlasRecord`,
the world-composed transform, and the world-multiplied color.

If `picture` references keys not present in `atlas`, returns
`error.MissingRecord`. The shape causing the failure is reported in
`EmitResult.failed_shape_index` so callers can take corrective action.

### Replicated: `emitInstanced`

For pictures replicated N times via per-instance overrides. Sparklines,
particle systems, repeated logos.

```zig
pub fn emitInstanced(
    words_buf:     []u32,
    segs_buf:      []DrawSegment,
    word_len:      *usize,
    seg_len:       *usize,
    binding:       Binding,
    atlas:         *const Atlas,
    picture:       *const Picture,
    overrides:     []const Override,
) !EmitResult;
```

Produces one segment of `kind = .replicated`. The segment header carries
the picture's shape list once; the per-instance area carries one
`Override` per replication. The GPU instance count is
`picture.shapes.len * overrides.len`; the shader uses
`gl_InstanceID % shape_count` and `gl_InstanceID / shape_count` to find
the right pair.

### Why two primitives

A picture with N shapes and M overrides corresponds to N×M GPU instances.
The data needed is N + M, not N×M. The replicated emit stores N shapes
once and M overrides once; the shader does the outer product on the GPU.
The heterogeneous emit stores N pre-composed instances. Both are
information-preserving; the cost difference is the outer-product compression.

The shaders differ:
- **Heterogeneous shader**: per-instance fetch of record metadata,
  per-instance transform, per-instance color.
- **Replicated shader**: per-segment fetch of shape array, per-instance
  override fetch, compose at vertex stage.

These are distinct compiled programs. Trying to merge them into one
program with a runtime branch hurts both compile time (the optimizer has
to support both paths) and runtime (uniform branches in the vertex
stage). The existing snail codebase made the same split for text vs.
path; the new design keeps the split but along the more honest axis.

## Sizing helpers

```zig
pub fn wordBudget(picture: *const Picture, override_count: usize) usize;
pub fn segmentBudget(picture: *const Picture, override_count: usize) usize;
```

Conservative upper bounds for sizing caller-provided buffers.

## Coalescing

If two consecutive emit calls produce segments with the same binding, same
kind, and adjacent word ranges, the segments are merged into one. This
matches the existing `mergeIfAdjacent` behavior. Callers don't think about
it; it falls out of how emit appends to the segment buffer.

## Multi-atlas pictures

A picture's shapes can reference keys from multiple atlases. Emit takes a
single atlas per call, so multi-atlas content is emitted in multiple calls:

```zig
_ = try emit(buf, segs, ..., binding_a, &atlas_a, &part_a, world, tint);
_ = try emit(buf, segs, ..., binding_b, &atlas_b, &part_b, world, tint);
```

Each call produces its own segment. Coalescing skips when bindings differ.

This is the natural way to compose UI with text from a different atlas, or
icons from a different pool than glyphs. The caller decides the partition.

## What `emit` does *not* do

- Allocate. It writes into caller-provided buffers and returns counts.
- Validate atlas-vs-picture liveness (the lookup either succeeds or returns
  null; the caller handles the error).
- Track which records were used (callers needing this can scan
  `picture.shapes` themselves).
- Apply paint records (paint binding happens at the picture-construction
  layer; `local_paint` carries a `RecordKey` that the renderer resolves
  the same way it resolves curve keys).

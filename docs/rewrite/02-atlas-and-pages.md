# Atlas, pages, and GPU memory

## `AtlasPage`

A page is a packed bundle of curve+band records that becomes one layer of a
GPU texture array. Append-only at the byte level: bytes at offsets below
`data_len` are immutable; `data_len` grows monotonically via atomic CAS.

```zig
pub const AtlasPage = struct {
    capacity_bytes:   u32,
    data_len:         atomic u32,
    uploaded_len:     atomic u32,    // GPU mirror's high-water mark
    curve_bytes:      []u8,          // staging buffer
    band_bytes:       []u8,
    layer_index:      u16,           // stable for current generation
    generation:       u16,           // increments on page reuse
    refcount:         atomic u32,
    // ...
};
```

### Append-only mutation

The page mutates only through append:
- `data_len` increments atomically when a new record is added.
- Bytes at offsets `[0, old_data_len)` are immutable after writing.
- An `AtlasRecord` issued at `curve_texel = T` and `curve_count = N` reads
  bytes in `[T, T + N * SEGMENT_TEXELS * SIZEOF_TEXEL)`, which are immutable.

This makes the page a value at each `data_len` epoch: every observer sees the
same bytes at the same offsets, regardless of subsequent appends.

### Reuse

When a page's `refcount` drops to zero (no atlas references it anymore), it
goes to the `PagePool`'s free list. On reuse:
- `data_len = 0`
- `generation += 1`
- The same `layer_index` is reused (the GPU texture array slot is unchanged).

Existing `AtlasRecord`s pointing at the old generation are invalidated; their
`page_generation` field will not match the page's current generation. Live
references (held by `Atlas.lookup` entries) never see this because they hold
refcount; the only way to encounter a stale record is to have persisted one
outside the reference graph.

### Concurrency

`data_len` uses atomic CAS for multi-writer append:

```zig
fn reserve(page: *AtlasPage, needed: u32) ?u32 {
    while (true) {
        const cur = page.data_len.load(.acquire);
        if (cur + needed > page.capacity_bytes) return null;
        if (page.data_len.cmpxchgWeak(cur, cur + needed, .acq_rel, .acquire) == null)
            return cur;
    }
}
```

Two threads extending atlases that happen to share a tail page each get
non-overlapping byte ranges. No global lock.

## `PagePool`

The GPU resource. Owns the GPU texture arrays. Fixed capacity. No implicit
growth.

```zig
pub const PagePool = struct {
    backend:        BackendKind,
    max_layers:     u32,
    pages_resident: []?*AtlasPage,           // by layer_index
    pages_free:     std.SinglyLinkedList(*AtlasPage),
    // backend-specific GPU handles:
    curve_texture:  BackendTextureHandle,
    band_texture:   BackendTextureHandle,
    layer_info_tex: BackendTextureHandle,
    // ...
};
```

### Lifecycle

```zig
var pool = try renderer.createPagePool(.{
    .max_layers       = 32,
    .curve_page_bytes = 1 << 20,    // 1 MiB curve data per page
    .band_page_bytes  = 1 << 18,    // 256 KiB band data per page
});
defer pool.deinit();
```

The pool owns its GPU memory for its lifetime. Pages within it are allocated
and freed dynamically (drawn from a free list); the underlying GPU layers are
never deallocated until the pool itself is destroyed.

### Upload model

Pages have separate `data_len` (CPU-side high-water mark) and `uploaded_len`
(GPU-side high-water mark). `gpu.upload()` walks the pages an atlas
references; for each page where `uploaded_len < data_len`, it pushes the
delta to the GPU and updates `uploaded_len`.

```zig
pub fn upload(self: *PagePool, allocs: UploadAllocators, atlas: *const Atlas) !Binding;
pub fn uploadIncremental(self: *PagePool, allocs: UploadAllocators,
                         atlas: *const Atlas, prev: ?Binding) !Binding;
```

`upload` without `prev` is the same as `uploadIncremental(... , null)`. Both
return a `Binding`. (TBD whether we expose both names or just one with a
nullable param.)

### `Binding`

A small token returned by `upload`. Identifies which pool the atlas was
uploaded against and what generation of pages was current.

```zig
pub const Binding = struct {
    pool:       *PagePool,
    generation: u32,         // matches pool.generation when issued
};
```

Emit consults the binding's pool to resolve atlas records. Draw validates the
binding's generation against the pool's current generation; a mismatch means
the atlas was uploaded against a now-replaced pool snapshot.

### Retirement

For Vulkan and other backends with frames in flight, dropping a page while
the GPU is still reading it is unsafe. The pool defers reclamation via a
`RetirementQueue`:

```zig
pub const RetirementQueue = struct {
    // Holds (page, fence_or_frame) pairs.
    // sweep() called once per frame moves pages whose fences signaled
    // to the actual free list.
};
```

For backends without GPU-side coordination (CPU renderer, GL with implicit
serialization), retirement is synchronous: page refcount → 0 immediately
returns the page to the free list.

## `Atlas`

The pure value layer over pages.

```zig
pub const Atlas = struct {
    allocator: std.mem.Allocator,
    pages:     []*AtlasPage,                                    // refcounted refs
    lookup:    std.AutoHashMapUnmanaged(RecordKey, AtlasRecord),
};
```

### Construction

```zig
pub fn empty(allocator: Allocator) Atlas;
pub fn from(allocator: Allocator, pool: *PagePool, entries: []const Entry) !Atlas;
```

`from` allocates one or more pages from the pool, packs the entries into them
(filling tail pages when possible, allocating new pages when needed), and
returns an atlas value referencing those pages with their records in the
lookup.

### Monoidal composition

```zig
pub fn combine(allocator: Allocator, atlases: []const *const Atlas) !Atlas;
```

Combine is associative; identity is `empty`. The result references the union
of pages (refcounted) and the union of lookups. On a key conflict between
inputs, the first occurrence wins (callers who share keys are expected to
share content).

### Extension

```zig
pub fn extend(self: *const Atlas, allocator: Allocator, entries: []const Entry) !Atlas;
pub fn extendWith(
    self: *const Atlas,
    allocator: Allocator,
    scratch: Allocator,
    keys: []const RecordKey,
    provider: anytype,            // .produce(scratch, key) !GlyphCurves
) !ExtendResult;
```

`extend` is sugar for `combine(self, from(entries))`. `extendWith` is the
form callers use most: for each key, look it up; if missing, call
`provider.produce(scratch, key)` to derive the curves and add them.

The returned `ExtendResult` contains the new atlas plus a slice of records
(one per input key) — useful for callers building pictures from the same key
list. Both old and new atlas remain valid; the caller decides when to drop
the old.

### Queries

```zig
pub fn lookupRecord(self: *const Atlas, key: RecordKey) ?AtlasRecord;
pub fn contains(self: *const Atlas, key: RecordKey) bool;
pub fn recordCount(self: *const Atlas) u32;
pub fn pageCount(self: *const Atlas) usize;
```

### Compaction

```zig
pub fn compact(self: *const Atlas, allocator: Allocator, scratch: Allocator) !Atlas;
```

Returns a fresh atlas with the same keys mapping to (potentially different)
records, packed into the minimum number of fresh pages. The old atlas is
unaffected. Pictures referencing the old keys continue to work — they don't
hold records.

See [06-compaction.md](06-compaction.md) for the full discussion.

### Lifetime

`Atlas.deinit` releases the page refs. If a page's refcount drops to zero, it
returns to the pool. If the same page is held by another atlas, the page
stays alive.

## Inspection

The pool exposes occupancy and fragmentation stats:

```zig
pub const PoolStats = struct {
    pages_total:    u32,
    pages_active:   u32,
    pages_full:     u32,
    pages_empty:    u32,
    bytes_total:    u64,
    bytes_live:     u64,
    bytes_dead:     u64,
    bytes_free:     u64,
    pub fn fragmentation(self: PoolStats) f32;
};

pub fn poolStats(self: *const PagePool) PoolStats;
pub fn pageStats(self: *const PagePool, layer_index: u16) PageStats;
pub fn iteratePages(self: *const PagePool) PageStatsIterator;
```

Tracked incrementally via atomics on refcount transitions. Global stats are
O(1) to query.

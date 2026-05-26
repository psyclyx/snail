# Compaction and reclamation

The append-only-pages design gives stable `AtlasRecord` handles but means
dead bytes can accumulate when records die without their entire page dying.
The reclamation story addresses this without breaking value-orientation.

## The problem in detail

Pages are append-only at the byte level. When a record's last reference
drops (no atlas or picture holds it), its bytes become dead — still on the
page, occupying GPU memory, but no longer logically present.

The page itself stays alive until *every* record on it is dead. In churn
workloads, this means pages can accumulate dead bytes:

- A user zooms from ppem=12 to ppem=14 and back to ppem=12 ten times.
  Each zoom adds records to the active atlas; when the user returns to
  the previous ppem, the records from the intermediate visit are
  unreferenced but their bytes remain.
- A creative tool with an undo stack holds animated path snapshots from
  earlier in the animation. Each undo level keeps records alive; the
  stack grows; bytes accumulate.

Without a reclamation mechanism, fragmentation grows monotonically.

## Why `Picture` holds keys, not records

The fundamental insight that makes compaction work cleanly:
**`Picture.Shape` carries `RecordKey`, not `AtlasRecord`.**

This means compaction can change the underlying record (different page,
different offset) while the picture's key is unchanged. The picture is
unaffected. Emit resolves the key against the new atlas at draw time and
gets the new record automatically.

If pictures held `AtlasRecord`s (as in the current design), compaction
would invalidate them. Then either:
- The caller maintains a registry of every picture, walks it after
  compaction, and remaps each one. (Coordination burden.)
- The atlas tracks its pictures somehow. (Mutable graph, place-oriented.)

Neither is good. Holding keys instead of records lets compaction be
purely internal to the atlas.

## Per-record refcounting

The atlas tracks per-record reference counts:
- Each entry in `Atlas.lookup` is a reference.
- An atlas's `combine` / `extend` / `clone` bumps refcounts for entries
  in the new atlas's lookup.
- `deinit` decrements.

Pictures do *not* affect record refcounts. Pictures hold keys, which are
just data. A picture pointing at a missing key fails at emit time with
`error.MissingRecord`.

When a record's refcount drops to zero, it's dead. Its bytes stay on the
page (append-only) but it's no longer in any atlas's lookup.

## Page reuse via reachability

The atlas page's refcount is `count of distinct atlases holding it` —
maintained directly, not derived. When a page's refcount drops to zero:
1. The page goes to the `PagePool`'s free list.
2. Its `generation` increments.
3. The same `layer_index` is now available for reuse.

New atlas extensions can allocate pages from the free list (preferred)
or from a fresh layer if the free list is empty.

`AtlasRecord`s held in the live reference graph stay valid: as long as
some atlas holds the page they reference, the page refcount is > 0 and
the page isn't reclaimed.

`AtlasRecord`s held *outside* the live reference graph (persisted to
disk, cached in caller code without going through an atlas) can become
stale. The `page_generation` field catches this at validation time.

## Stats

```zig
pub const PoolStats = struct {
    pages_total:  u32,    // pool capacity
    pages_active: u32,    // with at least one live record
    pages_full:   u32,    // data_len == capacity_bytes
    pages_empty:  u32,    // on the free list
    bytes_total:  u64,    // sum of page capacities
    bytes_live:   u64,    // bytes used by live records
    bytes_dead:   u64,    // bytes used by dead records (refcount=0, still on page)
    bytes_free:   u64,    // bytes in unused tail of active pages + free pages

    pub fn fragmentation(self: PoolStats) f32 {
        const denom = self.bytes_live + self.bytes_dead;
        if (denom == 0) return 0;
        return @as(f32, @floatFromInt(self.bytes_dead))
             / @as(f32, @floatFromInt(denom));
    }
};

pub fn poolStats(self: *const PagePool) PoolStats;
pub fn pageStats(self: *const PagePool, layer_index: u16) PageStats;
pub fn iteratePages(self: *const PagePool) PageStatsIterator;
```

`PoolStats` is O(1) to compute — the pool tracks `bytes_live` and
`bytes_dead` incrementally via atomics on every refcount transition. The
caller queries this number, applies their own policy ("compact if
fragmentation > 30%"), and decides when to act.

## Compaction

```zig
pub fn Atlas.compact(
    self: *const Atlas,
    allocator: Allocator,
    scratch: Allocator,
) !Atlas;
```

Walks `self.lookup`. For each `(key, record)`, reads the record's bytes
from its page, packs the bytes into a fresh page allocated from the pool,
builds a new lookup entry. Returns a fresh atlas containing the same keys
and the same content, in (potentially) different `AtlasRecord` locations.

The old atlas is unaffected. Pictures referencing the old atlas's keys
continue to resolve correctly — they hold keys, not records.

After compaction, the caller drops the old atlas:

```zig
const new = try atlas.compact(gpa, scratch);
atlas.deinit();
atlas = new;
```

Pages that were exclusively referenced by the old atlas now have refcount
zero. They return to the free list; their layers become available for
reuse. Pages still referenced by other atlases (because of `combine` or
sibling extensions) stay alive.

## When to compact

This is policy, not mechanism. The library exposes `poolStats()` and the
caller decides. Common patterns:

- **Threshold**: `if (stats.fragmentation() > 0.4) compact();`
- **Idle**: compact when the app is idle (e.g., after a frame with no
  state change).
- **Pre-render**: in editors with stable redraw cadences, compact during
  long idle periods.
- **Never**: terminals at one ppem rarely need compaction; the atlas
  grows monotonically and stays compact.

## Custom-shader implications

Custom-shader users who pack their own vertex data with `AtlasRecord`s
need to be aware of compaction. They have two paths:

1. **Don't compact** — `AtlasRecord` is then stable for the atlas's
   lifetime, like the simple model assumed.
2. **Compact and re-resolve** — after `compact()`, re-walk the picture's
   shapes and re-resolve via `atlas.lookupRecord(key)`. This is exactly
   what the internal `emit()` does on every call; custom-shader users
   pay it explicitly.

## What this doesn't do

- **Slot-level reuse within a page** (overwriting individual records'
  bytes when their refcounts hit zero). This requires per-slot generation
  counters and emit-time per-shape validation. Deferred — compaction
  achieves the same end goal in larger batches with simpler bookkeeping.
- **Incremental compaction** (moving one record at a time over many
  frames). The simple wholesale rebuild is O(live records) and runs in
  single-digit milliseconds for typical workloads. If a workload pushes
  on this, incremental compaction can be added later without API change.
- **Automatic compaction triggered by the library.** The library never
  decides to compact; the caller does.

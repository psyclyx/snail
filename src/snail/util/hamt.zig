//! Persistent hash array mapped trie.
//!
//! `Hamt(K, V, Context)` is an immutable map: every mutating operation
//! returns a *new* map that shares structure with the original. Both
//! maps stay valid; the caller decides whose lifetime ends first by
//! calling `deinit` on each handle.
//!
//! Internal layout follows the standard Bagwell/Clojure design:
//! 32-way branching (5 hash bits per level), bitmap-compressed child
//! arrays (popcount addressing), `Leaf` slots holding a single
//! `(hash, key, value)`, and `Collision` slots for the rare case of
//! two distinct keys hashing to the same 64-bit value.
//!
//! Path-copy on insert is O(log32 N). Sibling subtrees are not copied;
//! they're shared by bumping their `refcount`. When the last handle to
//! a subtree is released, the subtree is recursively freed.
//!
//! Node reference counts are atomic: independent handles may be cloned,
//! extended, read, and destroyed on different threads. As with any value,
//! mutating or destroying the same handle concurrently is not supported.
//!
//! Context contract (matches `std.HashMap`):
//!     pub fn hash(self: Context, key: K) u64
//!     pub fn eql(self: Context, a: K, b: K) bool

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Hamt(comptime K: type, comptime V: type, comptime Context: type) type {
    return struct {
        const Self = @This();

        root: ?Slot,
        len: u32,
        allocator: Allocator,
        context: Context,

        // ── Trie geometry ──
        //
        // 64-bit hash divided into 13 5-bit groups (top group is only
        // 4 bits wide — the slot bit can never exceed 15 at depth 12).
        // Two distinct keys whose hashes also collide get parked in a
        // `Collision` slot — no recursion past 64 bits.
        const BRANCH_BITS: u6 = 5;
        const BRANCH_FACTOR: u6 = 1 << BRANCH_BITS; // 32
        const SLOT_MASK: u64 = BRANCH_FACTOR - 1;
        const MAX_DEPTH: u6 = 13;

        fn retainCount(refcount: *std.atomic.Value(u32)) void {
            while (true) {
                const prior = refcount.load(.acquire);
                if (prior == std.math.maxInt(u32)) @panic("HAMT reference count exhausted");
                if (refcount.cmpxchgWeak(prior, prior + 1, .acq_rel, .acquire) == null) return;
            }
        }

        fn releaseCount(refcount: *std.atomic.Value(u32)) bool {
            while (true) {
                const prior = refcount.load(.acquire);
                if (prior == 0) @panic("HAMT reference underflow");
                if (refcount.cmpxchgWeak(prior, prior - 1, .acq_rel, .acquire) == null)
                    return prior == 1;
            }
        }

        fn slotBit(hash: u64, depth: u6) u5 {
            return @intCast((hash >> @intCast(depth * BRANCH_BITS)) & SLOT_MASK);
        }

        const Slot = union(enum) {
            branch: *Branch,
            leaf: *Leaf,
            collision: *Collision,

            fn retained(self: Slot) Slot {
                switch (self) {
                    .branch => |n| retainCount(&n.refcount),
                    .leaf => |n| retainCount(&n.refcount),
                    .collision => |n| retainCount(&n.refcount),
                }
                return self;
            }

            fn release(self: Slot, alloc: Allocator) void {
                switch (self) {
                    .branch => |n| n.release(alloc),
                    .leaf => |n| n.release(alloc),
                    .collision => |n| n.release(alloc),
                }
            }
        };

        const Branch = struct {
            refcount: std.atomic.Value(u32),
            bitmap: u32,
            /// One entry per set bit in `bitmap`, in ascending bit
            /// order. Index of slot bit `b` is
            /// `@popCount(bitmap & ((1 << b) - 1))`.
            children: []Slot,

            fn release(self: *Branch, alloc: Allocator) void {
                if (releaseCount(&self.refcount)) {
                    for (self.children) |c| c.release(alloc);
                    alloc.free(self.children);
                    alloc.destroy(self);
                }
            }

            fn hasSlot(self: *const Branch, bit: u5) bool {
                return (self.bitmap & (@as(u32, 1) << bit)) != 0;
            }

            fn indexOf(self: *const Branch, bit: u5) usize {
                const mask = (@as(u32, 1) << bit) -% 1;
                return @popCount(self.bitmap & mask);
            }
        };

        const Leaf = struct {
            refcount: std.atomic.Value(u32),
            hash: u64,
            key: K,
            value: V,

            fn release(self: *Leaf, alloc: Allocator) void {
                if (releaseCount(&self.refcount)) alloc.destroy(self);
            }

            fn retained(self: *Leaf) *Leaf {
                retainCount(&self.refcount);
                return self;
            }
        };

        const KV = struct { key: K, value: V };

        const Collision = struct {
            refcount: std.atomic.Value(u32),
            hash: u64,
            entries: []KV,

            fn release(self: *Collision, alloc: Allocator) void {
                if (releaseCount(&self.refcount)) {
                    alloc.free(self.entries);
                    alloc.destroy(self);
                }
            }
        };

        // ── Allocation helpers ──

        fn allocLeaf(alloc: Allocator, hash: u64, key: K, value: V) !*Leaf {
            const node = try alloc.create(Leaf);
            node.* = .{ .refcount = std.atomic.Value(u32).init(1), .hash = hash, .key = key, .value = value };
            return node;
        }

        fn allocCollision(alloc: Allocator, hash: u64, entries: []KV) !*Collision {
            const node = try alloc.create(Collision);
            node.* = .{ .refcount = std.atomic.Value(u32).init(1), .hash = hash, .entries = entries };
            return node;
        }

        fn allocBranch(alloc: Allocator, bitmap: u32, children: []Slot) !*Branch {
            const node = try alloc.create(Branch);
            node.* = .{ .refcount = std.atomic.Value(u32).init(1), .bitmap = bitmap, .children = children };
            return node;
        }

        // ── Public API ──

        pub fn init(allocator: Allocator, context: Context) Self {
            return .{
                .root = null,
                .len = 0,
                .allocator = allocator,
                .context = context,
            };
        }

        /// Release this handle's reference to the root. Subtrees still
        /// referenced by other handles (e.g. a `put` result) remain
        /// alive until their own handles release.
        pub fn deinit(self: *Self) void {
            if (self.root) |r| r.release(self.allocator);
            self.* = undefined;
        }

        /// Produce a second handle to the same persistent structure.
        /// Both handles must be `deinit`'d.
        pub fn clone(self: *const Self) Self {
            return .{
                .root = if (self.root) |r| r.retained() else null,
                .len = self.len,
                .allocator = self.allocator,
                .context = self.context,
            };
        }

        pub fn count(self: *const Self) u32 {
            return self.len;
        }

        pub fn contains(self: *const Self, key: K) bool {
            return self.get(key) != null;
        }

        pub fn get(self: *const Self, key: K) ?V {
            const h = self.context.hash(key);
            var slot = self.root orelse return null;
            var depth: u6 = 0;
            while (true) {
                switch (slot) {
                    .leaf => |l| {
                        if (l.hash == h and self.context.eql(l.key, key)) return l.value;
                        return null;
                    },
                    .collision => |c| {
                        if (c.hash != h) return null;
                        for (c.entries) |e| {
                            if (self.context.eql(e.key, key)) return e.value;
                        }
                        return null;
                    },
                    .branch => |b| {
                        const bit = slotBit(h, depth);
                        if (!b.hasSlot(bit)) return null;
                        slot = b.children[b.indexOf(bit)];
                        depth += 1;
                    },
                }
            }
        }

        /// Return a new map containing `key → value`. Other entries
        /// and the original map are unchanged. If the key is already
        /// bound, the new map's binding wins; the old map keeps its
        /// previous value.
        pub fn put(self: *const Self, key: K, value: V) !Self {
            const h = self.context.hash(key);
            const result = blk: {
                if (self.root) |r| {
                    break :blk try self.putSlot(r, h, key, value, 0);
                } else {
                    const leaf = try allocLeaf(self.allocator, h, key, value);
                    break :blk PutResult{ .slot = .{ .leaf = leaf }, .replaced = false };
                }
            };
            const new_len = if (result.replaced)
                self.len
            else
                std.math.add(u32, self.len, 1) catch {
                    result.slot.release(self.allocator);
                    return error.MapTooLarge;
                };
            return .{
                .root = result.slot,
                .len = new_len,
                .allocator = self.allocator,
                .context = self.context,
            };
        }

        const PutResult = struct {
            slot: Slot, // refcount 1, caller owns
            replaced: bool, // true if an existing entry was overwritten
        };

        fn putSlot(self: *const Self, slot: Slot, h: u64, key: K, value: V, depth: u6) !PutResult {
            switch (slot) {
                .leaf => |old| {
                    if (old.hash == h) {
                        if (self.context.eql(old.key, key)) {
                            const new_leaf = try allocLeaf(self.allocator, h, key, value);
                            return .{ .slot = .{ .leaf = new_leaf }, .replaced = true };
                        }
                        // Same hash, different keys → collision.
                        const entries = try self.allocator.alloc(KV, 2);
                        errdefer self.allocator.free(entries);
                        entries[0] = .{ .key = old.key, .value = old.value };
                        entries[1] = .{ .key = key, .value = value };
                        const coll = try allocCollision(self.allocator, h, entries);
                        return .{ .slot = .{ .collision = coll }, .replaced = false };
                    }
                    // Different hashes: build the deepest branch that
                    // separates them and chain ancestors above it.
                    const new_leaf = try allocLeaf(self.allocator, h, key, value);
                    const inner_slot = try self.mergeDistinct(
                        Slot{ .leaf = old.retained() },
                        old.hash,
                        Slot{ .leaf = new_leaf },
                        h,
                        depth,
                    );
                    return .{ .slot = inner_slot, .replaced = false };
                },

                .collision => |old| {
                    if (old.hash == h) {
                        // Replace or append within the collision list.
                        for (old.entries, 0..) |e, i| {
                            if (self.context.eql(e.key, key)) {
                                const entries = try self.allocator.alloc(KV, old.entries.len);
                                errdefer self.allocator.free(entries);
                                @memcpy(entries, old.entries);
                                entries[i] = .{ .key = key, .value = value };
                                const coll = try allocCollision(self.allocator, h, entries);
                                return .{ .slot = .{ .collision = coll }, .replaced = true };
                            }
                        }
                        const entries = try self.allocator.alloc(KV, old.entries.len + 1);
                        errdefer self.allocator.free(entries);
                        @memcpy(entries[0..old.entries.len], old.entries);
                        entries[old.entries.len] = .{ .key = key, .value = value };
                        const coll = try allocCollision(self.allocator, h, entries);
                        return .{ .slot = .{ .collision = coll }, .replaced = false };
                    }
                    // Distinct hashes: collision becomes one child of a
                    // branch alongside the new leaf.
                    const new_leaf = try allocLeaf(self.allocator, h, key, value);
                    retainCount(&old.refcount); // new branch owns one reference
                    const inner = try self.mergeDistinct(
                        Slot{ .collision = old },
                        old.hash,
                        Slot{ .leaf = new_leaf },
                        h,
                        depth,
                    );
                    return .{ .slot = inner, .replaced = false };
                },

                .branch => |old| {
                    const bit = slotBit(h, depth);
                    if (old.hasSlot(bit)) {
                        const idx = old.indexOf(bit);
                        const sub = try self.putSlot(old.children[idx], h, key, value, depth + 1);
                        errdefer sub.slot.release(self.allocator);
                        const new_branch = try cloneBranchReplace(self.allocator, old, idx, sub.slot);
                        return .{ .slot = .{ .branch = new_branch }, .replaced = sub.replaced };
                    }
                    const new_leaf = try allocLeaf(self.allocator, h, key, value);
                    errdefer new_leaf.release(self.allocator);
                    const new_branch = try cloneBranchInsert(self.allocator, old, bit, .{ .leaf = new_leaf });
                    return .{ .slot = .{ .branch = new_branch }, .replaced = false };
                },
            }
        }

        /// Build the smallest subtree containing two slots whose hashes
        /// differ. Ownership of both `lhs` and `rhs` transfers on entry: the
        /// returned slot owns them on success, and this function releases them
        /// on failure.
        fn mergeDistinct(
            self: *const Self,
            lhs: Slot,
            lhs_hash: u64,
            rhs: Slot,
            rhs_hash: u64,
            depth: u6,
        ) !Slot {
            std.debug.assert(lhs_hash != rhs_hash);
            std.debug.assert(depth < MAX_DEPTH);
            var owns_inputs = true;
            errdefer if (owns_inputs) {
                lhs.release(self.allocator);
                rhs.release(self.allocator);
            };
            const bit_l = slotBit(lhs_hash, depth);
            const bit_r = slotBit(rhs_hash, depth);
            if (bit_l == bit_r) {
                // The recursive call now owns the two input references and
                // releases them itself if it fails.
                owns_inputs = false;
                const inner = try self.mergeDistinct(lhs, lhs_hash, rhs, rhs_hash, depth + 1);
                errdefer inner.release(self.allocator);
                const children = try self.allocator.alloc(Slot, 1);
                errdefer self.allocator.free(children);
                children[0] = inner;
                const branch = try allocBranch(self.allocator, @as(u32, 1) << bit_l, children);
                return .{ .branch = branch };
            }
            const children = try self.allocator.alloc(Slot, 2);
            errdefer self.allocator.free(children);
            if (bit_l < bit_r) {
                children[0] = lhs;
                children[1] = rhs;
            } else {
                children[0] = rhs;
                children[1] = lhs;
            }
            const bitmap = (@as(u32, 1) << bit_l) | (@as(u32, 1) << bit_r);
            const branch = try allocBranch(self.allocator, bitmap, children);
            return .{ .branch = branch };
        }

        fn cloneBranchReplace(alloc: Allocator, old: *const Branch, idx: usize, new_child: Slot) !*Branch {
            const children = try alloc.alloc(Slot, old.children.len);
            errdefer {
                for (children, 0..) |child, i| {
                    if (i != idx) child.release(alloc);
                }
                alloc.free(children);
            }
            for (old.children, 0..) |c, i| {
                children[i] = if (i == idx) new_child else c.retained();
            }
            return allocBranch(alloc, old.bitmap, children);
        }

        fn cloneBranchInsert(alloc: Allocator, old: *const Branch, bit: u5, new_child: Slot) !*Branch {
            const insert_at = old.indexOf(bit);
            const children = try alloc.alloc(Slot, old.children.len + 1);
            errdefer {
                for (children, 0..) |child, i| {
                    if (i != insert_at) child.release(alloc);
                }
                alloc.free(children);
            }
            for (old.children[0..insert_at], 0..) |c, i| children[i] = c.retained();
            children[insert_at] = new_child;
            for (old.children[insert_at..], 0..) |c, i| children[insert_at + 1 + i] = c.retained();
            const bitmap = old.bitmap | (@as(u32, 1) << bit);
            return allocBranch(alloc, bitmap, children);
        }

        // ── Iteration ──

        pub const Entry = struct {
            key_ptr: *const K,
            value_ptr: *const V,
        };

        pub const Iterator = struct {
            stack: [MAX_DEPTH]Frame,
            stack_len: u6,
            leaf_emit: ?*const Leaf, // standalone-root leaf state machine
            coll_node: ?*const Collision,
            coll_idx: usize,

            const Frame = struct {
                branch: *const Branch,
                child_idx: usize,
            };

            pub fn next(self: *Iterator) ?Entry {
                while (true) {
                    if (self.leaf_emit) |l| {
                        self.leaf_emit = null;
                        return .{ .key_ptr = &l.key, .value_ptr = &l.value };
                    }
                    if (self.coll_node) |c| {
                        if (self.coll_idx < c.entries.len) {
                            const e = &c.entries[self.coll_idx];
                            self.coll_idx += 1;
                            return .{ .key_ptr = &e.key, .value_ptr = &e.value };
                        }
                        self.coll_node = null;
                    }
                    if (self.stack_len == 0) return null;
                    const top = &self.stack[self.stack_len - 1];
                    if (top.child_idx >= top.branch.children.len) {
                        self.stack_len -= 1;
                        continue;
                    }
                    const child = top.branch.children[top.child_idx];
                    top.child_idx += 1;
                    self.descend(child);
                }
            }

            fn descend(self: *Iterator, slot: Slot) void {
                switch (slot) {
                    .leaf => |l| self.leaf_emit = l,
                    .collision => |c| {
                        self.coll_node = c;
                        self.coll_idx = 0;
                    },
                    .branch => |b| {
                        self.stack[self.stack_len] = .{ .branch = b, .child_idx = 0 };
                        self.stack_len += 1;
                    },
                }
            }
        };

        pub fn iterator(self: *const Self) Iterator {
            var it = Iterator{
                .stack = undefined,
                .stack_len = 0,
                .leaf_emit = null,
                .coll_node = null,
                .coll_idx = 0,
            };
            if (self.root) |r| it.descend(r);
            return it;
        }
    };
}

// ── Tests ──

const testing = std.testing;

fn intHash(_: void, key: u64) u64 {
    return std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
}

fn intEql(_: void, a: u64, b: u64) bool {
    return a == b;
}

const IntCtx = struct {
    pub fn hash(_: IntCtx, k: u64) u64 {
        return intHash({}, k);
    }
    pub fn eql(_: IntCtx, a: u64, b: u64) bool {
        return intEql({}, a, b);
    }
};

const IntMap = Hamt(u64, u64, IntCtx);

test "Hamt: empty map has no entries" {
    var m = IntMap.init(testing.allocator, .{});
    defer m.deinit();
    try testing.expectEqual(@as(u32, 0), m.count());
    try testing.expectEqual(@as(?u64, null), m.get(1));
}

test "Hamt: put returns a new map; original is unchanged" {
    var a = IntMap.init(testing.allocator, .{});
    defer a.deinit();
    var b = try a.put(7, 700);
    defer b.deinit();

    try testing.expectEqual(@as(u32, 0), a.count());
    try testing.expectEqual(@as(?u64, null), a.get(7));
    try testing.expectEqual(@as(u32, 1), b.count());
    try testing.expectEqual(@as(?u64, 700), b.get(7));
}

test "Hamt: put with existing key replaces value, count unchanged" {
    var a = IntMap.init(testing.allocator, .{});
    defer a.deinit();
    var b = try a.put(5, 50);
    defer b.deinit();
    var c = try b.put(5, 51);
    defer c.deinit();

    try testing.expectEqual(@as(u32, 1), c.count());
    try testing.expectEqual(@as(?u64, 51), c.get(5));
    try testing.expectEqual(@as(?u64, 50), b.get(5)); // b unaffected
}

test "Hamt: many puts preserve all keys and old maps stay queryable" {
    const N = 1024;
    var maps: [N + 1]IntMap = undefined;
    maps[0] = IntMap.init(testing.allocator, .{});
    defer for (&maps) |*m| m.deinit();

    for (0..N) |i| {
        maps[i + 1] = try maps[i].put(@intCast(i), @as(u64, @intCast(i)) * 3);
    }

    try testing.expectEqual(@as(u32, N), maps[N].count());
    for (0..N) |i| {
        try testing.expectEqual(@as(?u64, @as(u64, @intCast(i)) * 3), maps[N].get(@intCast(i)));
    }
    // Earlier snapshot still observes earlier state.
    try testing.expectEqual(@as(u32, 500), maps[500].count());
    try testing.expectEqual(@as(?u64, null), maps[500].get(600));
}

test "Hamt: clone bumps the refcount and both handles stay live" {
    var a = IntMap.init(testing.allocator, .{});
    defer a.deinit();
    var b = try a.put(1, 100);
    defer b.deinit();

    var c = b.clone();
    defer c.deinit();

    try testing.expectEqual(@as(?u64, 100), b.get(1));
    try testing.expectEqual(@as(?u64, 100), c.get(1));
}

test "Hamt: independent handles may clone extend and release concurrently" {
    const allocator = std.heap.page_allocator;
    var empty = IntMap.init(allocator, .{});
    defer empty.deinit();
    var shared = try empty.put(1, 100);
    defer shared.deinit();

    const Worker = struct {
        fn run(base: *const IntMap, worker_id: u32, failed: *std.atomic.Value(bool)) void {
            for (0..256) |i| {
                var clone = base.clone();
                defer clone.deinit();
                const key = @as(u64, worker_id) << 32 | @as(u64, @intCast(i + 2));
                var extended = clone.put(key, key * 3) catch {
                    failed.store(true, .release);
                    return;
                };
                defer extended.deinit();
                if (extended.get(1) != 100 or extended.get(key) != key * 3) {
                    failed.store(true, .release);
                    return;
                }
            }
        }
    };

    var failed = std.atomic.Value(bool).init(false);
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, Worker.run, .{ &shared, @as(u32, @intCast(i + 1)), &failed });
    }
    for (threads) |thread| thread.join();

    try testing.expect(!failed.load(.acquire));
    try testing.expectEqual(@as(?u64, 100), shared.get(1));
    try testing.expectEqual(@as(u32, 1), shared.count());
}

fn exerciseHamtAllocationFailures(allocator: Allocator) !void {
    var empty = IntMap.init(allocator, .{});
    defer empty.deinit();
    var one = try empty.put(0, 10);
    defer one.deinit();
    // These hashes share their low five bits, exercising recursive branch
    // construction as well as branch replacement and insertion.
    var deep = try one.put(1 << 20, 20);
    defer deep.deinit();
    var replaced = try deep.put(0, 11);
    defer replaced.deinit();
    var inserted = try deep.put(1, 30);
    defer inserted.deinit();

    var collide_empty = CollideMap.init(allocator, .{});
    defer collide_empty.deinit();
    var collide_one = try collide_empty.put(1, 10);
    defer collide_one.deinit();
    var collide_two = try collide_one.put(17, 20);
    defer collide_two.deinit();
    var collide_three = try collide_two.put(33, 30);
    defer collide_three.deinit();
    var collide_replaced = try collide_three.put(17, 21);
    defer collide_replaced.deinit();
    var collision_branched = try collide_three.put(2, 40);
    defer collision_branched.deinit();
}

test "Hamt: every allocation failure releases transferred ownership" {
    try testing.checkAllAllocationFailures(testing.allocator, exerciseHamtAllocationFailures, .{});
}

// Hash collision: force two distinct keys to map to the same hash via
// a custom context.
const CollideCtx = struct {
    pub fn hash(_: CollideCtx, k: u64) u64 {
        return k % 16; // tiny range → guaranteed collisions
    }
    pub fn eql(_: CollideCtx, a: u64, b: u64) bool {
        return a == b;
    }
};

const CollideMap = Hamt(u64, u64, CollideCtx);

test "Hamt: hash collisions are stored in a collision slot" {
    var a = CollideMap.init(testing.allocator, .{});
    defer a.deinit();
    // 1 and 17 both hash to 1; 2 and 18 both hash to 2.
    var b = try a.put(1, 10);
    defer b.deinit();
    var c = try b.put(17, 170);
    defer c.deinit();
    var d = try c.put(2, 20);
    defer d.deinit();
    var e = try d.put(18, 180);
    defer e.deinit();

    try testing.expectEqual(@as(u32, 4), e.count());
    try testing.expectEqual(@as(?u64, 10), e.get(1));
    try testing.expectEqual(@as(?u64, 170), e.get(17));
    try testing.expectEqual(@as(?u64, 20), e.get(2));
    try testing.expectEqual(@as(?u64, 180), e.get(18));
    try testing.expectEqual(@as(?u64, null), e.get(33));
}

test "Hamt: collision replace preserves count" {
    var a = CollideMap.init(testing.allocator, .{});
    defer a.deinit();
    var b = try a.put(1, 10);
    defer b.deinit();
    var c = try b.put(17, 170);
    defer c.deinit();
    var d = try c.put(17, 171); // replace within collision
    defer d.deinit();
    try testing.expectEqual(@as(u32, 2), d.count());
    try testing.expectEqual(@as(?u64, 171), d.get(17));
    try testing.expectEqual(@as(?u64, 170), c.get(17)); // c unaffected
}

test "Hamt: iterator visits every entry exactly once" {
    var m = IntMap.init(testing.allocator, .{});
    var prev = m.clone();
    defer prev.deinit();
    var cur = m.clone();
    defer cur.deinit();

    const N: u64 = 200;
    for (0..N) |i| {
        const next = try cur.put(i, i * 10);
        cur.deinit();
        cur = next;
    }
    m.deinit();

    var seen: [N]bool = .{false} ** N;
    var it = cur.iterator();
    var count: u32 = 0;
    while (it.next()) |e| {
        try testing.expect(e.key_ptr.* < N);
        try testing.expectEqual(@as(u64, e.key_ptr.* * 10), e.value_ptr.*);
        try testing.expect(!seen[e.key_ptr.*]);
        seen[e.key_ptr.*] = true;
        count += 1;
    }
    try testing.expectEqual(@as(u32, N), count);
}

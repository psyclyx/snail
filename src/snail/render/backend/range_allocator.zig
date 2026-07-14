//! First-fit free-list allocator over a 1-D index space, shared by every
//! backend cache. Each cache carves two disjoint spaces out of it — rows in
//! the shared layer-info storage and layers in the shared image array — and
//! both want the same thing: hand out a contiguous `[base, base+size)` run,
//! take it back on release, and coalesce adjacent free runs so long-running
//! caches don't fragment. That logic lived verbatim in three backend files;
//! it lives here once.

const std = @import("std");

pub const Range = struct { base: u32, size: u32 };

pub const RangeAllocator = struct {
    free: std.ArrayList(Range) = .empty,

    /// Seed with a single free run covering `[0, capacity)`. A zero capacity
    /// leaves the allocator empty (every `take` fails) — callers with no such
    /// storage pay nothing.
    pub fn init(allocator: std.mem.Allocator, capacity: u32) std.mem.Allocator.Error!RangeAllocator {
        var self: RangeAllocator = .{};
        try self.reset(allocator, capacity);
        return self;
    }

    pub fn deinit(self: *RangeAllocator, allocator: std.mem.Allocator) void {
        self.free.deinit(allocator);
        self.* = undefined;
    }

    /// Drop all outstanding allocations and reseed with `[0, capacity)`.
    pub fn reset(self: *RangeAllocator, allocator: std.mem.Allocator, capacity: u32) std.mem.Allocator.Error!void {
        self.free.clearRetainingCapacity();
        if (capacity > 0) try self.free.append(allocator, .{ .base = 0, .size = capacity });
    }

    /// First-fit: return the lowest free run large enough to hold `size`,
    /// splitting the remainder back onto the list. Null when nothing fits.
    /// Non-allocating — the list only ever shrinks or shifts here.
    pub fn take(self: *RangeAllocator, size: u32) ?Range {
        for (self.free.items, 0..) |r, i| {
            if (r.size < size) continue;
            if (r.size == size) {
                _ = self.free.orderedRemove(i);
            } else {
                self.free.items[i] = .{ .base = r.base + size, .size = r.size - size };
            }
            return .{ .base = r.base, .size = size };
        }
        return null;
    }

    /// Return a run to the free list, coalescing with any adjacent runs.
    pub fn release(self: *RangeAllocator, allocator: std.mem.Allocator, range: Range) std.mem.Allocator.Error!void {
        if (range.size == 0) return;
        try self.free.append(allocator, range);
        std.mem.sort(Range, self.free.items, {}, struct {
            fn lessThan(_: void, a: Range, b: Range) bool {
                return a.base < b.base;
            }
        }.lessThan);
        var write: usize = 0;
        var read: usize = 0;
        while (read < self.free.items.len) {
            var cur = self.free.items[read];
            read += 1;
            while (read < self.free.items.len) {
                const nxt = self.free.items[read];
                if (cur.base + cur.size == nxt.base) {
                    cur.size += nxt.size;
                    read += 1;
                } else break;
            }
            self.free.items[write] = cur;
            write += 1;
        }
        self.free.shrinkRetainingCapacity(write);
    }
};

test "take splits and release coalesces" {
    const testing = std.testing;
    var ra = try RangeAllocator.init(testing.allocator, 16);
    defer ra.deinit(testing.allocator);

    const a = ra.take(4).?;
    const b = ra.take(4).?;
    try testing.expectEqual(@as(u32, 0), a.base);
    try testing.expectEqual(@as(u32, 4), b.base);
    try testing.expectEqual(@as(usize, 1), ra.free.items.len);
    try testing.expectEqual(@as(u32, 8), ra.free.items[0].base);
    try testing.expectEqual(@as(u32, 8), ra.free.items[0].size);

    // Releasing both freed runs coalesces them with the tail into one [0,16).
    try ra.release(testing.allocator, a);
    try ra.release(testing.allocator, b);
    try testing.expectEqual(@as(usize, 1), ra.free.items.len);
    try testing.expectEqual(@as(u32, 0), ra.free.items[0].base);
    try testing.expectEqual(@as(u32, 16), ra.free.items[0].size);
}

test "take fails when nothing fits and empty capacity yields no runs" {
    const testing = std.testing;
    var ra = try RangeAllocator.init(testing.allocator, 0);
    defer ra.deinit(testing.allocator);
    try testing.expectEqual(@as(?Range, null), ra.take(1));

    try ra.reset(testing.allocator, 4);
    try testing.expect(ra.take(8) == null);
    try testing.expectEqual(@as(u32, 0), ra.take(4).?.base);
}

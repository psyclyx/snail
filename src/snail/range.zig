const std = @import("std");

/// Selects a contiguous slice of an immutable resource. The default
/// `count = maxInt(usize)` means "all from `start`"; `resolve` clamps to the
/// resource's actual length.
pub const Range = struct {
    start: usize = 0,
    count: usize = std.math.maxInt(usize),

    pub const Resolved = struct { start: usize, end: usize };

    pub fn resolve(self: Range, total: usize) Resolved {
        const start = @min(self.start, total);
        const remaining = total - start;
        const count = @min(self.count, remaining);
        return .{ .start = start, .end = start + count };
    }
};

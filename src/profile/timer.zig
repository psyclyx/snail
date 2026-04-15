const std = @import("std");
const build_options = @import("build_options");
const profiling_enabled = build_options.enable_profiling;

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

pub const Timer = if (profiling_enabled) struct {
    start_ns: u64,
    label: []const u8,

    pub fn begin(comptime label: []const u8) Timer {
        return .{ .start_ns = nowNs(), .label = label };
    }

    pub fn end(self: Timer) void {
        const elapsed_ns = nowNs() - self.start_ns;
        const elapsed_us: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;
        stats.record(self.label, elapsed_us);
    }
} else struct {
    pub fn begin(comptime _: []const u8) Timer {
        return .{};
    }
    pub fn end(_: Timer) void {}
};

pub const stats = if (profiling_enabled) struct {
    const max_labels = 32;
    const max_samples = 120;

    var labels: [max_labels][]const u8 = .{""} ** max_labels;
    var ring: [max_labels][max_samples]f64 = .{.{0} ** max_samples} ** max_labels;
    var write_idx: [max_labels]usize = .{0} ** max_labels;
    var count: usize = 0;

    pub fn record(label: []const u8, value_us: f64) void {
        var idx: usize = 0;
        while (idx < count) : (idx += 1) {
            if (std.mem.eql(u8, labels[idx], label)) break;
        }
        if (idx == count and count < max_labels) {
            labels[count] = label;
            count += 1;
        }
        if (idx < max_labels) {
            ring[idx][write_idx[idx] % max_samples] = value_us;
            write_idx[idx] += 1;
        }
    }

    pub fn getAverage(label: []const u8) f64 {
        for (0..count) |idx| {
            if (std.mem.eql(u8, labels[idx], label)) {
                const n = @min(write_idx[idx], max_samples);
                if (n == 0) return 0;
                var sum: f64 = 0;
                for (0..n) |i| sum += ring[idx][i];
                return sum / @as(f64, @floatFromInt(n));
            }
        }
        return 0;
    }

    pub fn printAll() void {
        std.debug.print("\n=== Profile Stats ===\n", .{});
        for (0..count) |idx| {
            const n = @min(write_idx[idx], max_samples);
            if (n == 0) continue;
            var sum: f64 = 0;
            var max_v: f64 = 0;
            for (0..n) |i| {
                sum += ring[idx][i];
                max_v = @max(max_v, ring[idx][i]);
            }
            const avg = sum / @as(f64, @floatFromInt(n));
            std.debug.print("  {s}: avg={d:.1}us max={d:.1}us\n", .{ labels[idx], avg, max_v });
        }
        std.debug.print("=====================\n", .{});
    }
} else struct {
    pub fn record(_: []const u8, _: f64) void {}
    pub fn getAverage(_: []const u8) f64 {
        return 0;
    }
    pub fn printAll() void {}
};

/// Standalone timing for benchmarks (always available, not gated by profiling flag)
pub fn timestamp() u64 {
    return nowNs();
}

const std = @import("std");

pub const default_samples: usize = 15;

pub const Args = struct {
    case: []const u8,
    iterations: ?usize = null,
    samples: usize = default_samples,
};

pub const Counter = struct {
    name: []const u8,
    value: usize,
};

pub const Result = struct {
    iterations: usize,
    samples: usize,
    min_batch_ns: u64,
    median_batch_ns: u64,
    p95_batch_ns: u64,

    pub fn minNs(self: Result) f64 {
        return @as(f64, @floatFromInt(self.min_batch_ns)) / @as(f64, @floatFromInt(self.iterations));
    }

    pub fn medianNs(self: Result) f64 {
        return @as(f64, @floatFromInt(self.median_batch_ns)) / @as(f64, @floatFromInt(self.iterations));
    }

    pub fn p95Ns(self: Result) f64 {
        return @as(f64, @floatFromInt(self.p95_batch_ns)) / @as(f64, @floatFromInt(self.iterations));
    }
};

pub fn parseArgs(args: []const [:0]const u8, cases: []const []const u8) !Args {
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list")) {
        for (cases) |case| std.debug.print("{s}\n", .{case});
        std.process.exit(0);
    }
    if (args.len < 2) return error.MissingCase;

    const case: []const u8 = args[1];
    var found = false;
    for (cases) |candidate| {
        if (std.mem.eql(u8, case, candidate)) {
            found = true;
            break;
        }
    }
    if (!found) return error.UnknownCase;

    var out = Args{ .case = case };
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--iterations")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            const iterations = try std.fmt.parseUnsigned(usize, args[i], 10);
            if (iterations == 0) return error.InvalidIterations;
            out.iterations = iterations;
        } else if (std.mem.eql(u8, args[i], "--samples")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            out.samples = try std.fmt.parseUnsigned(usize, args[i], 10);
            if (out.samples == 0) return error.InvalidSamples;
        } else {
            return error.UnknownArgument;
        }
    }
    return out;
}

pub fn printUsage(exe: []const u8, cases: []const []const u8) void {
    std.debug.print("usage: {s} CASE [--iterations N] [--samples N]\n       {s} --list\ncases:\n", .{ exe, exe });
    for (cases) |case| std.debug.print("  {s}\n", .{case});
}

/// Time a consumer-visible operation after its fixture has been constructed.
/// The context supplies `run() !void`; it may also supply `beforeSample()` for
/// untimed reset work such as clearing a destination buffer. One full batch is
/// run before sampling so lazy initialization and cold instruction pages do not
/// become part of an otherwise warm microbenchmark.
pub fn measure(
    allocator: std.mem.Allocator,
    context: anytype,
    iterations: usize,
    samples: usize,
) !Result {
    const Context = @typeInfo(@TypeOf(context)).pointer.child;
    if (@hasDecl(Context, "beforeSample")) context.beforeSample();
    for (0..iterations) |_| try context.run();

    const elapsed = try allocator.alloc(u64, samples);
    defer allocator.free(elapsed);
    for (elapsed) |*sample| {
        if (@hasDecl(Context, "beforeSample")) context.beforeSample();
        const start = monotonicNanos();
        for (0..iterations) |_| try context.run();
        sample.* = monotonicNanos() - start;
    }
    std.mem.sort(u64, elapsed, {}, std.sort.asc(u64));
    const p95_index = @min(elapsed.len - 1, (elapsed.len * 95 + 99) / 100 - 1);
    return .{
        .iterations = iterations,
        .samples = samples,
        .min_batch_ns = elapsed[0],
        .median_batch_ns = elapsed[elapsed.len / 2],
        .p95_batch_ns = elapsed[p95_index],
    };
}

pub fn report(
    benchmark: []const u8,
    result: Result,
    work_per_iteration: usize,
    work_unit: []const u8,
    counters: []const Counter,
    checksum: u64,
) void {
    std.mem.doNotOptimizeAway(checksum);
    const ns_per_work = result.medianNs() / @as(f64, @floatFromInt(work_per_iteration));
    std.debug.print(
        "benchmark={s} median_ns={d:.1} min_ns={d:.1} p95_ns={d:.1} work_per_iteration={d} work_unit={s} ns_per_work={d:.2} iterations={d} samples={d}",
        .{
            benchmark,
            result.medianNs(),
            result.minNs(),
            result.p95Ns(),
            work_per_iteration,
            work_unit,
            ns_per_work,
            result.iterations,
            result.samples,
        },
    );
    for (counters) |counter| std.debug.print(" {s}={d}", .{ counter.name, counter.value });
    std.debug.print(" checksum={x}\n", .{checksum});
}

pub fn hashBytes(hash: *u64, bytes: []const u8) void {
    for (bytes) |byte| {
        hash.* ^= byte;
        hash.* *%= 1099511628211;
    }
}

pub fn hashValue(hash: *u64, value: anytype) void {
    hashBytes(hash, std.mem.asBytes(&value));
}

fn monotonicNanos() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

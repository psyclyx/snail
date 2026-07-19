const std = @import("std");
const snail = @import("snail");
const raster = @import("snail-raster");
const common = @import("common.zig");
const fixtures = @import("fixtures.zig");

const cases = [_][]const u8{
    "text-gray",
    "text-lcd",
    "text-tt-hint",
    "text-autohint",
    "text-colr",
    "path",
    "mixed",
};

const ThreadMode = union(enum) {
    serial,
    auto,
    count: usize,
};

const Args = struct {
    case: []const u8,
    iterations: ?usize = null,
    samples: usize = common.default_samples,
    threads: ThreadMode = .serial,
};

pub fn main(init: std.process.Init) !void {
    const raw_args = try init.minimal.args.toSlice(init.arena.allocator());
    const args = parseArgs(raw_args) catch |err| {
        printUsage(raw_args[0]);
        std.debug.print("error: {s}\n", .{@errorName(err)});
        std.process.exit(2);
    };
    const allocator = std.heap.smp_allocator;
    const kind: fixtures.SceneKind = if (std.mem.eql(u8, args.case, "text-tt-hint"))
        .hinted
    else if (std.mem.eql(u8, args.case, "text-autohint"))
        .autohint
    else if (std.mem.eql(u8, args.case, "text-colr"))
        .colr
    else if (std.mem.eql(u8, args.case, "path"))
        .path
    else if (std.mem.eql(u8, args.case, "mixed"))
        .mixed
    else
        .regular;
    const subpixel = std.mem.eql(u8, args.case, "text-lcd");

    const pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 18,
        .band_words_per_page = 1 << 16,
    });
    defer pool.deinit();
    var scene = try fixtures.buildScene(allocator, pool, kind);
    defer scene.deinit();

    var cache = try raster.BackendCache.init(allocator, pool, .{
        .max_bindings = 1,
        .layer_info_height = 64,
        .max_images = 0,
    });
    defer cache.deinit();
    var bindings: [1]snail.render.records.Binding = undefined;
    try cache.upload(allocator, &.{&scene.atlas}, &bindings);
    var emitted = try fixtures.emitScene(allocator, bindings[0], &scene);
    defer emitted.deinit();

    const pixels = try allocator.alloc(u8, @as(usize, fixtures.width) * fixtures.height * 4);
    defer allocator.free(pixels);
    var renderer = raster.Renderer.init(pixels.ptr, fixtures.width, fixtures.height, fixtures.width * 4);

    var worker_pool: raster.ThreadPool = undefined;
    var worker_pool_live = false;
    defer if (worker_pool_live) worker_pool.deinit();
    const worker_pool_ptr: ?*raster.ThreadPool = switch (args.threads) {
        .serial => null,
        .auto => blk: {
            try worker_pool.init(allocator, .{});
            worker_pool_live = true;
            break :blk &worker_pool;
        },
        .count => |count| blk: {
            try worker_pool.init(allocator, .{ .threads = count });
            worker_pool_live = true;
            break :blk &worker_pool;
        },
    };

    var context = RasterContext{
        .renderer = &renderer,
        .state = drawState(subpixel),
        .records = emitted.records(),
        .cache = &cache,
        .worker_pool = worker_pool_ptr,
        .pixels = pixels,
    };
    const iteration_count = args.iterations orelse defaultIterations(args.case, args.threads);
    const result = try common.measure(allocator, &context, iteration_count, args.samples);

    var checksum: u64 = 14695981039346656037;
    common.hashBytes(&checksum, pixels);
    common.hashValue(&checksum, emitted.word_len);
    const instance_count = emitted.word_len / snail.render.records.WORDS_PER_INSTANCE;
    const thread_count = if (worker_pool_ptr) |p| p.threads.len + 1 else 1;
    const has_text = switch (kind) {
        .regular, .hinted, .autohint, .mixed => true,
        else => false,
    };
    const has_paths = kind == .path or kind == .mixed;
    const em_min: usize = switch (kind) {
        .regular, .autohint, .mixed => 18,
        .hinted => 20,
        .colr => 38,
        .path => 0,
    };
    const em_max: usize = switch (kind) {
        .regular, .autohint, .mixed => 22,
        .hinted => 20,
        .colr => 46,
        .path => 0,
    };
    var name_buffer: [128]u8 = undefined;
    const benchmark = try std.fmt.bufPrint(&name_buffer, "raster/{s}/{s}", .{ args.case, threadName(args.threads) });
    common.report(
        benchmark,
        result,
        instance_count,
        "instance",
        &.{
            .{ .name = "source_shapes", .value = scene.shapes().len },
            .{ .name = "instances", .value = instance_count },
            .{ .name = "record_bytes", .value = emitted.word_len * @sizeOf(u32) },
            .{ .name = "segments", .value = emitted.segment_len },
            .{ .name = "atlas_records", .value = scene.atlas.recordCount() },
            .{ .name = "atlas_pages", .value = scene.atlas.pageCount() },
            .{ .name = "text_rows", .value = if (has_text) 6 else 0 },
            .{ .name = "text_codepoints_per_row", .value = if (has_text) try std.unicode.utf8CountCodepoints(fixtures.paragraph) else 0 },
            .{ .name = "path_shapes", .value = if (has_paths) 24 else 0 },
            .{ .name = "path_shape_kinds", .value = if (has_paths) 3 else 0 },
            .{ .name = "colr_glyphs", .value = if (kind == .colr) 32 else 0 },
            .{ .name = "colr_layers_per_glyph", .value = scene.colrLayerCount() },
            .{ .name = "em_min_px", .value = em_min },
            .{ .name = "em_max_px", .value = em_max },
            .{ .name = "width", .value = fixtures.width },
            .{ .name = "height", .value = fixtures.height },
            .{ .name = "surface_pixels", .value = @as(usize, fixtures.width) * fixtures.height },
            .{ .name = "threads", .value = thread_count },
        },
        checksum,
    );
}

const RasterContext = struct {
    renderer: *raster.Renderer,
    state: raster.DrawState,
    records: snail.render.records.DrawRecords,
    cache: *const raster.BackendCache,
    worker_pool: ?*raster.ThreadPool,
    pixels: []u8,

    pub fn beforeSample(self: *RasterContext) void {
        @memset(self.pixels, 0);
    }

    pub fn run(self: *RasterContext) !void {
        try raster.draw(self.renderer, self.state, self.records, &.{self.cache}, self.worker_pool);
    }
};

fn drawState(subpixel: bool) raster.DrawState {
    return .{
        .mvp = snail.Mat4.ortho(0, @floatFromInt(fixtures.width), @floatFromInt(fixtures.height), 0, -1, 1),
        .surface = .{
            .pixel_width = fixtures.width,
            .pixel_height = fixtures.height,
            .encoding = .srgb,
        },
        .raster = .{ .subpixel_order = if (subpixel) .rgb else .none },
    };
}

fn defaultIterations(case: []const u8, threads: ThreadMode) usize {
    if (std.mem.eql(u8, case, "text-lcd")) return 2;
    if (std.mem.eql(u8, case, "text-colr")) return 4;
    if (std.mem.eql(u8, case, "text-autohint")) return 4;
    if (std.mem.eql(u8, case, "path")) return 4;
    if (std.mem.eql(u8, case, "mixed")) return switch (threads) {
        .serial => 4,
        else => 16,
    };
    return 8;
}

fn threadName(mode: ThreadMode) []const u8 {
    return switch (mode) {
        .serial => "serial",
        .auto => "auto",
        .count => "fixed",
    };
}

fn parseArgs(args: []const [:0]const u8) !Args {
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list")) {
        for (cases) |case| std.debug.print("{s}\n", .{case});
        std.process.exit(0);
    }
    if (args.len < 2) return error.MissingCase;
    var known = false;
    for (cases) |case| if (std.mem.eql(u8, args[1], case)) {
        known = true;
        break;
    };
    if (!known) return error.UnknownCase;
    var out = Args{ .case = args[1] };
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--iterations")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            const value = try std.fmt.parseUnsigned(usize, args[i], 10);
            if (value == 0) return error.InvalidIterations;
            out.iterations = value;
        } else if (std.mem.eql(u8, args[i], "--samples")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            out.samples = try std.fmt.parseUnsigned(usize, args[i], 10);
            if (out.samples == 0) return error.InvalidSamples;
        } else if (std.mem.eql(u8, args[i], "--threads")) {
            i += 1;
            if (i >= args.len) return error.MissingArgument;
            if (std.mem.eql(u8, args[i], "serial")) {
                out.threads = .serial;
            } else if (std.mem.eql(u8, args[i], "auto")) {
                out.threads = .auto;
            } else {
                const count = try std.fmt.parseUnsigned(usize, args[i], 10);
                if (count == 0) return error.InvalidThreadCount;
                out.threads = .{ .count = count };
            }
        } else return error.UnknownArgument;
    }
    return out;
}

fn printUsage(exe: []const u8) void {
    std.debug.print(
        "usage: {s} CASE [--iterations N] [--samples N] [--threads serial|auto|N]\n       {s} --list\ncases:\n",
        .{ exe, exe },
    );
    for (cases) |case| std.debug.print("  {s}\n", .{case});
}

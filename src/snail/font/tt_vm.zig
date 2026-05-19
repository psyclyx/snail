const std = @import("std");

const tt_exec = @import("tt_exec.zig");
const tt_outline = @import("tt_outline.zig");
const tt_tables = @import("tt_tables.zig");

pub const RenderMode = enum {
    grayscale,
    subpixel,
};

pub const SizeRequest = struct {
    ppem_x_26_6: u32,
    ppem_y_26_6: u32,
    mode: RenderMode = .grayscale,
};

pub const CvtAxis = enum {
    x,
    y,
};

pub const ExecutionBufferSizes = struct {
    stack: usize,
    storage: usize,
    functions: usize,
    twilight_points: usize,
    glyph_points: usize,
};

pub const ExecutionBuffers = struct {
    stack: []i32,
    storage: []i32,
};

pub const Program = struct {
    data: []const u8,
    tables: tt_tables.ProgramTables,
    head: tt_tables.Head,
    maxp: tt_tables.MaxProfile,

    pub fn init(data: []const u8) !Program {
        const tables = try tt_tables.ProgramTables.init(data);
        return .{
            .data = data,
            .tables = tables,
            .head = try tables.headInfo(),
            .maxp = try tables.maxProfile(),
        };
    }

    pub fn sizeState(self: *const Program, allocator: std.mem.Allocator, request: SizeRequest) !SizeState {
        const cvt_bytes = try self.tables.tableBytes(self.tables.cvt);
        return .{
            .allocator = allocator,
            .request = request,
            .units_per_em = self.head.units_per_em,
            .cvt_x = try scaledCvt(allocator, cvt_bytes, request.ppem_x_26_6, self.head.units_per_em),
            .cvt_y = try scaledCvt(allocator, cvt_bytes, request.ppem_y_26_6, self.head.units_per_em),
        };
    }

    pub fn executionBufferSizes(self: *const Program) ExecutionBufferSizes {
        return .{
            .stack = @max(@as(usize, self.maxp.max_stack_elements), 256),
            .storage = @as(usize, self.maxp.max_storage),
            .functions = @as(usize, self.maxp.max_function_defs),
            .twilight_points = @as(usize, self.maxp.max_twilight_points),
            .glyph_points = @max(
                @as(usize, self.maxp.max_points),
                @as(usize, self.maxp.max_composite_points),
            ),
        };
    }

    pub fn runFontProgram(self: *const Program, context: *tt_exec.Context) !void {
        try context.execute(try self.tables.tableBytes(self.tables.fpgm));
    }

    pub fn runControlProgram(self: *const Program, context: *tt_exec.Context) !void {
        try context.execute(try self.tables.tableBytes(self.tables.prep));
    }

    pub fn loadGlyphTopology(self: *const Program, allocator: std.mem.Allocator, glyph_id: u16) !GlyphTopology {
        if (glyph_id >= self.maxp.num_glyphs) return error.InvalidFont;
        const glyph_len = try self.glyphLength(glyph_id);
        if (glyph_len == 0) return .empty;

        const base = try self.glyphBase(glyph_id);
        const num_contours = try readI16(self.data, base);
        if (num_contours >= 0) {
            return .{ .simple = try tt_outline.parseSimpleGlyph(allocator, self.data, base, @intCast(num_contours)) };
        }

        return .{ .compound = try tt_outline.parseCompoundGlyph(
            allocator,
            self.data,
            base,
            1.0 / @as(f32, @floatFromInt(self.head.units_per_em)),
        ) };
    }

    fn glyphBase(self: *const Program, glyph_id: u16) !usize {
        const glyf = self.tables.glyf orelse return error.MissingRequiredTable;
        return @as(usize, glyf.offset) + @as(usize, try self.glyphOffset(glyph_id));
    }

    fn glyphOffset(self: *const Program, glyph_id: u16) !u32 {
        const loca = try self.tables.tableBytes(self.tables.loca);
        if (self.head.index_to_loc_format == 0) {
            const offset = @as(usize, glyph_id) * 2;
            if (offset + 2 > loca.len) return error.UnexpectedEof;
            return @as(u32, std.mem.readInt(u16, loca[offset..][0..2], .big)) * 2;
        }

        const offset = @as(usize, glyph_id) * 4;
        if (offset + 4 > loca.len) return error.UnexpectedEof;
        return std.mem.readInt(u32, loca[offset..][0..4], .big);
    }

    fn glyphLength(self: *const Program, glyph_id: u16) !u32 {
        const off0 = try self.glyphOffset(glyph_id);
        const off1 = try self.glyphOffset(glyph_id + 1);
        if (off1 < off0) return error.InvalidFont;
        return off1 - off0;
    }
};

pub const GlyphTopology = union(enum) {
    empty,
    simple: tt_outline.SimpleGlyph,
    compound: tt_outline.CompoundGlyph,

    pub fn deinit(self: *GlyphTopology) void {
        switch (self.*) {
            .empty => {},
            .simple => |*simple| simple.deinit(),
            .compound => |*compound| compound.deinit(),
        }
        self.* = undefined;
    }
};

pub const SizeState = struct {
    allocator: std.mem.Allocator,
    request: SizeRequest,
    units_per_em: u16,
    cvt_x: []i32,
    cvt_y: []i32,

    pub fn deinit(self: *SizeState) void {
        self.allocator.free(self.cvt_x);
        self.allocator.free(self.cvt_y);
        self.* = undefined;
    }

    pub fn environment(self: *const SizeState) tt_exec.Environment {
        return .{
            .ppem_x_26_6 = self.request.ppem_x_26_6,
            .ppem_y_26_6 = self.request.ppem_y_26_6,
            .units_per_em = self.units_per_em,
            .point_size_26_6 = @intCast(self.request.ppem_y_26_6),
        };
    }

    pub fn cvtForAxis(self: *SizeState, axis: CvtAxis) []i32 {
        return switch (axis) {
            .x => self.cvt_x,
            .y => self.cvt_y,
        };
    }

    pub fn executionContext(
        self: *SizeState,
        buffers: ExecutionBuffers,
        axis: CvtAxis,
        limits: tt_exec.Limits,
    ) tt_exec.Context {
        var context = tt_exec.Context.init(.{
            .stack = buffers.stack,
            .storage = buffers.storage,
            .cvt = self.cvtForAxis(axis),
        }, limits);
        context.setEnvironment(self.environment());
        switch (axis) {
            .x => context.graphics.setVectorToAxis(.x, .both),
            .y => context.graphics.setVectorToAxis(.y, .both),
        }
        return context;
    }
};

fn scaledCvt(
    allocator: std.mem.Allocator,
    cvt_bytes: []const u8,
    ppem_26_6: u32,
    units_per_em: u16,
) ![]i32 {
    if (cvt_bytes.len % 2 != 0) return error.InvalidFont;
    const values = try allocator.alloc(i32, cvt_bytes.len / 2);
    errdefer allocator.free(values);

    for (values, 0..) |*value, i| {
        const fword = std.mem.readInt(i16, cvt_bytes[i * 2 ..][0..2], .big);
        value.* = scaleFWordTo26Dot6(fword, ppem_26_6, units_per_em);
    }
    return values;
}

fn readI16(data: []const u8, offset: usize) !i16 {
    if (offset + 2 > data.len) return error.UnexpectedEof;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn scaleFWordTo26Dot6(value: i16, ppem_26_6: u32, units_per_em: u16) i32 {
    if (units_per_em == 0) return 0;

    const numerator = @as(i64, value) * @as(i64, ppem_26_6);
    const denominator = @as(i64, units_per_em);
    const half = @divTrunc(denominator, 2);
    const rounded = if (numerator >= 0)
        @divTrunc(numerator + half, denominator)
    else
        @divTrunc(numerator - half, denominator);
    return @intCast(rounded);
}

test "size state scales cvt values in 26.6 pixels" {
    const program = try Program.init(@import("assets").noto_sans_regular);
    var size = try program.sizeState(std.testing.allocator, .{
        .ppem_x_26_6 = 12 * 64,
        .ppem_y_26_6 = 14 * 64,
    });
    defer size.deinit();

    try std.testing.expectEqual(size.cvt_x.len, size.cvt_y.len);
    try std.testing.expect(size.cvt_y.len > 0);
    try std.testing.expectEqual(@as(u16, program.head.units_per_em), size.units_per_em);
}

test "scale FWORD handles signed values" {
    try std.testing.expectEqual(@as(i32, 32), scaleFWordTo26Dot6(50, 640, 1000));
    try std.testing.expectEqual(@as(i32, -32), scaleFWordTo26Dot6(-50, 640, 1000));
}

test "program loads raw glyph topology" {
    const assets = @import("assets");
    const program = try Program.init(assets.noto_sans_regular);
    const font = try @import("ttf.zig").Font.init(assets.noto_sans_regular);
    const glyph_id = try font.glyphIndex('A');

    var topology = try program.loadGlyphTopology(std.testing.allocator, glyph_id);
    defer topology.deinit();

    switch (topology) {
        .simple => |simple| {
            try std.testing.expect(simple.points.len > 0);
            try std.testing.expect(simple.contours.len > 0);
        },
        .compound => |compound| try std.testing.expect(compound.components.len > 0),
        .empty => return error.TestExpectedGlyph,
    }
}

test "program exposes execution buffer sizing" {
    const program = try Program.init(@import("assets").noto_sans_regular);
    const sizes = program.executionBufferSizes();

    try std.testing.expect(sizes.stack >= 256);
    try std.testing.expect(sizes.functions >= program.maxp.max_function_defs);
    try std.testing.expect(sizes.glyph_points >= program.maxp.max_points);
}

test "size state initializes execution context over caller buffers" {
    const program = try Program.init(@import("assets").noto_sans_regular);
    var size = try program.sizeState(std.testing.allocator, .{
        .ppem_x_26_6 = 10 * 64,
        .ppem_y_26_6 = 12 * 64,
    });
    defer size.deinit();

    var stack: [16]i32 = undefined;
    var storage: [4]i32 = .{ 0, 0, 0, 0 };
    var context = size.executionContext(.{
        .stack = &stack,
        .storage = &storage,
    }, .y, .{});

    try context.execute(&.{ 0xB1, 0, 50, 0x70, 0x4B });
    try std.testing.expectEqual(scaleFWordTo26Dot6(50, 12 * 64, program.head.units_per_em), size.cvt_y[0]);
    try std.testing.expectEqual(@as(i32, 12), try context.top());
}

test "program executes bundled font and control programs" {
    const allocator = std.testing.allocator;
    const program = try Program.init(@import("assets").noto_sans_regular);
    const sizes = program.executionBufferSizes();

    const stack = try allocator.alloc(i32, sizes.stack);
    defer allocator.free(stack);
    const storage = try allocator.alloc(i32, @max(sizes.storage, 1));
    defer allocator.free(storage);
    @memset(storage, 0);
    const function_entries = try allocator.alloc(tt_exec.Function, @max(sizes.functions, 1));
    defer allocator.free(function_entries);
    var functions: tt_exec.FunctionDefs = .{ .entries = function_entries };
    const twilight_points = try allocator.alloc(tt_exec.Point, @max(sizes.twilight_points, 1));
    defer allocator.free(twilight_points);
    var empty_glyph_points: [0]tt_exec.Point = .{};
    var zones: tt_exec.PointZones = .{
        .twilight = tt_exec.PointZone.initTwilight(twilight_points),
        .glyph = .{ .points = &empty_glyph_points },
    };

    var size = try program.sizeState(allocator, .{
        .ppem_x_26_6 = 12 * 64,
        .ppem_y_26_6 = 12 * 64,
    });
    defer size.deinit();

    var context = size.executionContext(.{
        .stack = stack,
        .storage = storage,
    }, .x, .{});
    context.setFunctions(&functions);
    context.setZones(&zones);

    try program.runFontProgram(&context);
    try std.testing.expect(functions.len > 0);

    context.reset();
    context.resetGraphics();
    context.setEnvironment(size.environment());
    context.setFunctions(&functions);
    context.setZones(&zones);
    try program.runControlProgram(&context);
}

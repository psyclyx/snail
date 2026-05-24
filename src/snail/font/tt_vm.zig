const std = @import("std");

const tt_exec = @import("tt_exec.zig");
const tt_graphics = @import("tt_graphics.zig");
const tt_outline = @import("tt_outline.zig");
const tt_points = @import("tt_points.zig");
const tt_tables = @import("tt_tables.zig");

pub const RenderMode = enum {
    grayscale,
    subpixel,
};

pub const SizeRequest = struct {
    ppem_x_26_6: u32,
    ppem_y_26_6: u32,
    mode: RenderMode = .grayscale,
    /// Extra writable CVT slots appended after the font's own cvt table.
    /// Non-zero values let WCVT*/WCVTF writes past the font's declared CVT
    /// length succeed (RCVT in that range reads as zero) — matches the
    /// tolerance behaviour of FreeType/Skia/CoreText for slightly malformed
    /// fonts. Zero (the default) keeps strict spec behaviour: any OOB CVT
    /// access surfaces as `tt_exec.Error.InvalidCvtIndex`.
    cvt_headroom: u32 = 0,
};

/// Deprecated — kept only for callers that haven't migrated. With a unified
/// CVT (FreeType-style projection-aware scaling), the axis selection at
/// context-creation time no longer affects CVT storage. Pass `.x` or `.y`
/// to seed the initial projection vector; the choice only impacts the
/// graphics state's starting axis, not which CVT buffer is used.
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

pub const ControlProgramSnapshot = struct {
    graphics: tt_exec.GraphicsState,
    storage: []i32,

    pub fn capture(self: ControlProgramSnapshot, context: *const tt_exec.Context) !void {
        if (self.storage.len != context.storage.len) return error.InvalidStorageSnapshot;
        @memcpy(self.storage, context.storage);
    }

    pub fn restore(self: ControlProgramSnapshot, context: *tt_exec.Context) !void {
        if (self.storage.len != context.storage.len) return error.InvalidStorageSnapshot;
        @memcpy(context.storage, self.storage);
        context.graphics = self.graphics;
        // Per-glyph fields reset at the start of every glyph program, regardless
        // of what prep left in the snapshot. FreeType's TT_Run_Context does the
        // same thing — without it, fonts whose prep ends with a non-default
        // projection vector (e.g. DejaVu Sans Mono leaves projection=Y) execute
        // the entire glyph program with the wrong axis.
        context.graphics.projection = tt_graphics.Vector.x_axis;
        context.graphics.freedom = tt_graphics.Vector.x_axis;
        context.graphics.dual_projection = tt_graphics.Vector.x_axis;
        context.graphics.rp0 = 0;
        context.graphics.rp1 = 0;
        context.graphics.rp2 = 0;
        context.graphics.zp0 = .glyph;
        context.graphics.zp1 = .glyph;
        context.graphics.zp2 = .glyph;
        context.graphics.loop_count = 1;
        context.reset();
    }
};

pub const GlyphBounds = struct {
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,

    pub fn fallbackAdvanceHeight(self: GlyphBounds) i32 {
        return @max(0, @as(i32, self.y_max) - @as(i32, self.y_min));
    }
};

pub const Program = struct {
    data: []const u8,
    tables: tt_tables.ProgramTables,
    head: tt_tables.Head,
    maxp: tt_tables.MaxProfile,
    hhea: tt_tables.HorizontalHeader,

    pub fn init(data: []const u8) !Program {
        const tables = try tt_tables.ProgramTables.init(data);
        return .{
            .data = data,
            .tables = tables,
            .head = try tables.headInfo(),
            .maxp = try tables.maxProfile(),
            .hhea = try tables.horizontalHeader(),
        };
    }

    pub fn sizeState(self: *const Program, allocator: std.mem.Allocator, request: SizeRequest) !SizeState {
        const cvt_bytes = try self.tables.tableBytes(self.tables.cvt);
        // CVT is stored once, in 26.6 px at the larger of the two ppems
        // (the "base ppem"). On read/write the VM scales by a per-projection
        // ratio (`Environment.projectionRatio`), matching FreeType's
        // `Read_CVT_Stretched`/`Write_CVT_Stretched`. For square pixels the
        // ratio is 1.0 and no scaling is applied. This is what fixes the
        // axis-mid-prep correctness problem that the old per-axis cvt_x /
        // cvt_y arrays could not handle: a single prep program can SVTCA
        // between axes and read/write the same CVT entries with consistent
        // scaling.
        const base_ppem = @max(request.ppem_x_26_6, request.ppem_y_26_6);
        const cvt = try scaledCvt(allocator, cvt_bytes, base_ppem, self.head.units_per_em, request.cvt_headroom);
        return .{
            .allocator = allocator,
            .request = request,
            .units_per_em = self.head.units_per_em,
            .grid_fit = try self.gridFits(request.ppem_y_26_6),
            .cvt = cvt,
        };
    }

    pub fn gridFits(self: *const Program, ppem_26_6: u32) !bool {
        const behavior = try self.tables.gaspBehavior(ppemFrom26Dot6(ppem_26_6)) orelse return true;
        return behavior.gridFits();
    }

    pub fn executionBufferSizes(self: *const Program) ExecutionBufferSizes {
        return .{
            .stack = @max(@as(usize, self.maxp.max_stack_elements), 256),
            .storage = @as(usize, self.maxp.max_storage),
            .functions = @as(usize, self.maxp.max_function_defs),
            .twilight_points = @as(usize, self.maxp.max_twilight_points),
            .glyph_points = hintedGlyphPointCapacity(
                @max(
                    @as(usize, self.maxp.max_points),
                    @as(usize, self.maxp.max_composite_points),
                ),
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

    pub fn horizontalMetrics(self: *const Program, glyph_id: u16) !tt_tables.HorizontalMetrics {
        return self.tables.horizontalMetrics(glyph_id, self.maxp.num_glyphs, self.hhea.number_of_h_metrics);
    }

    pub fn glyphBounds(self: *const Program, glyph_id: u16) !GlyphBounds {
        if (glyph_id >= self.maxp.num_glyphs) return error.InvalidFont;
        if (try self.glyphLength(glyph_id) == 0) return emptyGlyphBounds();
        const base = try self.glyphBase(glyph_id);
        return .{
            .x_min = try readI16(self.data, base + 2),
            .y_min = try readI16(self.data, base + 4),
            .x_max = try readI16(self.data, base + 6),
            .y_max = try readI16(self.data, base + 8),
        };
    }

    pub fn glyphPhantomMetrics(self: *const Program, glyph_id: u16) !tt_points.PhantomMetrics {
        const metrics = try self.horizontalMetrics(glyph_id);
        const bounds = try self.glyphBounds(glyph_id);
        return .{
            .x_min = bounds.x_min,
            .y_min = bounds.y_min,
            .x_max = bounds.x_max,
            .y_max = bounds.y_max,
            .advance_width = metrics.advance_width,
            .left_side_bearing = metrics.left_side_bearing,
            .advance_height = bounds.fallbackAdvanceHeight(),
        };
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

fn hintedGlyphPointCapacity(outline_points: usize) usize {
    return outline_points + tt_points.phantom_count;
}

fn emptyGlyphBounds() GlyphBounds {
    return .{
        .x_min = 0,
        .y_min = 0,
        .x_max = 0,
        .y_max = 0,
    };
}

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

pub const HintedSimpleGlyph = struct {
    zone: tt_exec.PointZone,
    phantom_start: usize,
    advance_x_26_6: i32,
    original_advance_x_26_6: i32,

    pub fn curves(self: *const HintedSimpleGlyph, allocator: std.mem.Allocator, scale: f32) ![]tt_points.QuadBezier {
        return self.zone.contoursToCurves(allocator, scale);
    }

    pub fn curvesXY(
        self: *const HintedSimpleGlyph,
        allocator: std.mem.Allocator,
        scale_x: f32,
        scale_y: f32,
    ) ![]tt_points.QuadBezier {
        return self.zone.contoursToCurvesXY(allocator, scale_x, scale_y);
    }
};

pub const SizeState = struct {
    allocator: std.mem.Allocator,
    request: SizeRequest,
    units_per_em: u16,
    grid_fit: bool,
    /// Single CVT stored in 26.6 px at the base ppem (max of x and y).
    /// Reads/writes are scaled by the current projection-relative ratio
    /// inside the VM. See `Program.sizeState` for rationale.
    cvt: []i32,

    pub fn deinit(self: *SizeState) void {
        self.allocator.free(self.cvt);
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

    pub fn executionContext(
        self: *SizeState,
        buffers: ExecutionBuffers,
        axis: CvtAxis,
        limits: tt_exec.Limits,
    ) tt_exec.Context {
        var context = tt_exec.Context.init(.{
            .stack = buffers.stack,
            .storage = buffers.storage,
            .cvt = self.cvt,
        }, limits);
        context.setEnvironment(self.environment());
        switch (axis) {
            .x => context.graphics.setVectorToAxis(.x, .both),
            .y => context.graphics.setVectorToAxis(.y, .both),
        }
        return context;
    }

    pub fn initSimpleGlyphZone(
        self: *const SizeState,
        buffer: []tt_exec.Point,
        glyph: *const tt_outline.SimpleGlyph,
    ) !tt_exec.PointZone {
        return tt_exec.PointZone.initGlyph(buffer, glyph.points, glyph.contours, self.environment());
    }

    pub fn initSimpleGlyphZoneWithPhantoms(
        self: *const SizeState,
        buffer: []tt_exec.Point,
        glyph: *const tt_outline.SimpleGlyph,
        phantoms: tt_points.PhantomMetrics,
    ) !tt_exec.PointZone {
        return tt_exec.PointZone.initGlyphWithPhantoms(
            buffer,
            glyph.points,
            glyph.contours,
            self.environment(),
            phantoms,
        );
    }

    pub fn executeSimpleGlyph(
        self: *const SizeState,
        context: *tt_exec.Context,
        zones: *tt_exec.PointZones,
        buffer: []tt_exec.Point,
        glyph: *const tt_outline.SimpleGlyph,
        phantoms: tt_points.PhantomMetrics,
    ) !HintedSimpleGlyph {
        zones.glyph = try self.initSimpleGlyphZoneWithPhantoms(buffer, glyph, phantoms);
        return self.executeGlyphZone(context, zones, zones.glyph, glyph.points.len, glyph.instructions);
    }

    pub fn executeGlyphZone(
        self: *const SizeState,
        context: *tt_exec.Context,
        zones: *tt_exec.PointZones,
        zone: tt_exec.PointZone,
        phantom_start: usize,
        instructions: []const u8,
    ) !HintedSimpleGlyph {
        zones.glyph = zone;
        context.reset();
        context.setZones(zones);
        if (self.grid_fit and (context.graphics.instruct_control & 1) == 0) {
            try context.execute(instructions);
        }
        return hintedSimpleGlyphView(zones.glyph, phantom_start);
    }

    pub fn captureControlProgramSnapshot(
        self: *const SizeState,
        context: *const tt_exec.Context,
        storage: []i32,
    ) !ControlProgramSnapshot {
        _ = self;
        var snapshot = ControlProgramSnapshot{
            .graphics = context.graphics,
            .storage = storage,
        };
        try snapshot.capture(context);
        return snapshot;
    }
};

fn hintedSimpleGlyphView(zone: tt_exec.PointZone, phantom_start: usize) !HintedSimpleGlyph {
    return .{
        .zone = zone,
        .phantom_start = phantom_start,
        .advance_x_26_6 = try zone.horizontalAdvance(phantom_start),
        .original_advance_x_26_6 = try zone.originalHorizontalAdvance(phantom_start),
    };
}

fn scaledCvt(
    allocator: std.mem.Allocator,
    cvt_bytes: []const u8,
    ppem_26_6: u32,
    units_per_em: u16,
    headroom: u32,
) ![]i32 {
    if (cvt_bytes.len % 2 != 0) return error.InvalidFont;
    const font_count = cvt_bytes.len / 2;
    const total = font_count + headroom;
    const values = try allocator.alloc(i32, total);
    errdefer allocator.free(values);

    for (values[0..font_count], 0..) |*value, i| {
        const fword = std.mem.readInt(i16, cvt_bytes[i * 2 ..][0..2], .big);
        value.* = scaleFWordTo26Dot6(fword, ppem_26_6, units_per_em);
    }
    @memset(values[font_count..], 0);
    return values;
}

fn ppemFrom26Dot6(ppem_26_6: u32) u16 {
    return @intCast(@min((ppem_26_6 + 32) / 64, std.math.maxInt(u16)));
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

test "size state scales cvt values in 26.6 pixels at base ppem" {
    const program = try Program.init(@import("assets").noto_sans_regular);
    var size = try program.sizeState(std.testing.allocator, .{
        .ppem_x_26_6 = 12 * 64,
        .ppem_y_26_6 = 14 * 64,
    });
    defer size.deinit();

    try std.testing.expect(size.cvt.len > 0);
    try std.testing.expectEqual(@as(u16, program.head.units_per_em), size.units_per_em);
}

test "size state appends zeroed cvt headroom" {
    const program = try Program.init(@import("assets").noto_sans_regular);
    var baseline = try program.sizeState(std.testing.allocator, .{
        .ppem_x_26_6 = 12 * 64,
        .ppem_y_26_6 = 12 * 64,
    });
    defer baseline.deinit();

    var padded = try program.sizeState(std.testing.allocator, .{
        .ppem_x_26_6 = 12 * 64,
        .ppem_y_26_6 = 12 * 64,
        .cvt_headroom = 8,
    });
    defer padded.deinit();

    try std.testing.expectEqual(baseline.cvt.len + 8, padded.cvt.len);
    for (padded.cvt[baseline.cvt.len..]) |v| try std.testing.expectEqual(@as(i32, 0), v);
    try std.testing.expectEqualSlices(i32, baseline.cvt, padded.cvt[0..baseline.cvt.len]);
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
    try std.testing.expect(sizes.glyph_points >= @as(usize, program.maxp.max_points) + tt_points.phantom_count);
}

test "program exposes horizontal metrics for phantom points" {
    const assets = @import("assets");
    const program = try Program.init(assets.noto_sans_regular);
    const font = try @import("ttf.zig").Font.init(assets.noto_sans_regular);
    const glyph_id = try font.glyphIndex('A');
    const expected = try font.glyphMetrics(glyph_id);
    const metrics = try program.horizontalMetrics(glyph_id);
    const phantoms = try program.glyphPhantomMetrics(glyph_id);

    try std.testing.expectEqual(expected.advance_width, metrics.advance_width);
    try std.testing.expectEqual(expected.lsb, metrics.left_side_bearing);
    try std.testing.expect(phantoms.x_max > phantoms.x_min);
    try std.testing.expect(phantoms.advance_width > 0);
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
    // CVT is stored in 26.6 px at the base ppem (max of x and y); for
    // ppem_x=10, ppem_y=12 the base is 12. The projection vector starts on
    // the y-axis so the projection ratio is 1.0, and the stored cell equals
    // the FUnit-to-pixel scaling at base ppem.
    try std.testing.expectEqual(scaleFWordTo26Dot6(50, 12 * 64, program.head.units_per_em), size.cvt[0]);
    try std.testing.expectEqual(@as(i32, 12), try context.top());
}

test "control program snapshot restores glyph-start state" {
    const program = try Program.init(@import("assets").noto_sans_regular);
    var size = try program.sizeState(std.testing.allocator, .{
        .ppem_x_26_6 = 10 * 64,
        .ppem_y_26_6 = 12 * 64,
    });
    defer size.deinit();

    var stack: [16]i32 = undefined;
    var storage: [3]i32 = .{ 10, 20, 30 };
    var context = size.executionContext(.{
        .stack = &stack,
        .storage = &storage,
    }, .x, .{});
    context.graphics.round_mode = .off;

    var snapshot_storage: [3]i32 = undefined;
    const snapshot = try size.captureControlProgramSnapshot(&context, &snapshot_storage);
    storage[1] = 99;
    context.graphics.round_mode = .half_grid;

    try snapshot.restore(&context);
    try std.testing.expectEqual(@as(i32, 20), storage[1]);
    try std.testing.expectEqual(@as(@TypeOf(context.graphics.round_mode), .off), context.graphics.round_mode);
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

test "program executes bundled simple glyph instructions" {
    const allocator = std.testing.allocator;
    const assets = @import("assets");
    const program = try Program.init(assets.noto_sans_regular);
    const font = try @import("ttf.zig").Font.init(assets.noto_sans_regular);
    const sizes = program.executionBufferSizes();
    const glyph_id = try font.glyphIndex('A');

    var topology = try program.loadGlyphTopology(allocator, glyph_id);
    defer topology.deinit();
    const simple = switch (topology) {
        .simple => |*glyph| glyph,
        else => return error.TestExpectedGlyph,
    };

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
    const glyph_points = try allocator.alloc(tt_exec.Point, @max(sizes.glyph_points, simple.points.len));
    defer allocator.free(glyph_points);
    var empty_glyph_points: [0]tt_exec.Point = .{};

    var size = try program.sizeState(allocator, .{
        .ppem_x_26_6 = 12 * 64,
        .ppem_y_26_6 = 12 * 64,
    });
    defer size.deinit();

    var zones: tt_exec.PointZones = .{
        .twilight = tt_exec.PointZone.initTwilight(twilight_points),
        .glyph = .{ .points = &empty_glyph_points },
    };
    var context = size.executionContext(.{
        .stack = stack,
        .storage = storage,
    }, .x, .{});
    context.setFunctions(&functions);
    context.setZones(&zones);

    try program.runFontProgram(&context);
    context.reset();
    context.resetGraphics();
    context.setEnvironment(size.environment());
    context.setFunctions(&functions);
    context.setZones(&zones);
    try program.runControlProgram(&context);

    const hinted = try size.executeSimpleGlyph(
        &context,
        &zones,
        glyph_points,
        simple,
        try program.glyphPhantomMetrics(glyph_id),
    );
    const curves = try hinted.curves(allocator, 1.0 / 64.0);
    defer allocator.free(curves);

    try std.testing.expect(hinted.zone.points.len == simple.points.len + tt_points.phantom_count);
    try std.testing.expect(hinted.advance_x_26_6 > 0);
    try std.testing.expect(hinted.original_advance_x_26_6 > 0);
    try std.testing.expect(curves.len > 0);
}

test "size state skips glyph instructions when grid fitting is disabled" {
    var cvt: [0]i32 = .{};
    var size = SizeState{
        .allocator = std.testing.allocator,
        .request = .{ .ppem_x_26_6 = 12 * 64, .ppem_y_26_6 = 12 * 64 },
        .units_per_em = 1000,
        .grid_fit = false,
        .cvt = &cvt,
    };
    var stack: [8]i32 = undefined;
    var storage: [1]i32 = .{0};
    var twilight_points: [1]tt_exec.Point = undefined;
    var glyph_points: [5]tt_exec.Point = .{
        .{ .x = 33, .y = 0, .ox = 33, .oy = 0, .on_curve = true },
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 64, .y = 0, .ox = 64, .oy = 0, .on_curve = true },
        .{ .x = 0, .y = 64, .ox = 0, .oy = 64, .on_curve = true },
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
    };
    const contours = [_]tt_outline.ContourRange{.{ .start = 0, .end = 1 }};
    var zones: tt_exec.PointZones = .{
        .twilight = tt_exec.PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points, .contours = &contours },
    };
    var context = size.executionContext(.{
        .stack = &stack,
        .storage = &storage,
    }, .x, .{});

    _ = try size.executeGlyphZone(
        &context,
        &zones,
        zones.glyph,
        1,
        &.{ 0xB0, 0, 0x2F },
    );

    try std.testing.expectEqual(@as(i32, 33), glyph_points[0].x);
}

test "size state initializes simple glyph phantom points" {
    const allocator = std.testing.allocator;
    const assets = @import("assets");
    const program = try Program.init(assets.noto_sans_regular);
    const font = try @import("ttf.zig").Font.init(assets.noto_sans_regular);
    const glyph_id = try font.glyphIndex('A');

    var topology = try program.loadGlyphTopology(allocator, glyph_id);
    defer topology.deinit();
    const simple = switch (topology) {
        .simple => |*glyph| glyph,
        else => return error.TestExpectedGlyph,
    };

    var size = try program.sizeState(allocator, .{
        .ppem_x_26_6 = 12 * 64,
        .ppem_y_26_6 = 12 * 64,
    });
    defer size.deinit();

    const phantoms = try program.glyphPhantomMetrics(glyph_id);
    const point_count = simple.points.len + tt_points.phantom_count;
    const points = try allocator.alloc(tt_exec.Point, point_count);
    defer allocator.free(points);

    const zone = try size.initSimpleGlyphZoneWithPhantoms(points, simple, phantoms);
    const phantom_start = simple.points.len;
    const left = @as(i32, phantoms.x_min) - @as(i32, phantoms.left_side_bearing);
    const right = left + @as(i32, phantoms.advance_width);

    try std.testing.expectEqual(point_count, zone.points.len);
    try std.testing.expectEqual(size.environment().scaleFUnitsX(left), zone.points[phantom_start].x);
    try std.testing.expectEqual(size.environment().scaleFUnitsX(right), zone.points[phantom_start + 1].x);
    try std.testing.expectEqual(try zone.originalHorizontalAdvance(phantom_start), try zone.horizontalAdvance(phantom_start));
}

const std = @import("std");

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

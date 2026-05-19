const std = @import("std");

const tt_graphics = @import("tt_graphics.zig");
const tt_points = @import("tt_points.zig");

pub const Error = error{
    BufferTooSmall,
    UnexpectedEof,
    StackUnderflow,
    StackOverflow,
    InvalidOpcode,
    InvalidStorageIndex,
    InvalidCvtIndex,
    InvalidPoint,
    InvalidZone,
    InvalidJump,
    MissingZones,
    UnsupportedVector,
    MissingFunctions,
    TooManyFunctions,
    UnknownFunction,
    CallDepthExceeded,
    InvalidFunctionDefinition,
    ExecutionLimitExceeded,
    DivisionByZero,
};

pub const Environment = tt_graphics.Environment;
pub const GraphicsState = tt_graphics.GraphicsState;
pub const Point = tt_points.Point;
pub const PointZone = tt_points.Zone;
pub const PointZones = tt_points.Zones;

pub const Limits = struct {
    max_steps: u32 = 100_000,
    max_call_depth: u32 = 64,
};

pub const Buffers = struct {
    stack: []i32,
    storage: []i32,
    cvt: []i32,
};

pub const Function = struct {
    id: i32,
    code: []const u8,
};

pub const FunctionDefs = struct {
    entries: []Function,
    len: usize = 0,

    pub fn reset(self: *FunctionDefs) void {
        self.len = 0;
    }

    pub fn put(self: *FunctionDefs, id: i32, code: []const u8) Error!void {
        for (self.entries[0..self.len]) |*entry| {
            if (entry.id == id) {
                entry.code = code;
                return;
            }
        }
        if (self.len >= self.entries.len) return Error.TooManyFunctions;
        self.entries[self.len] = .{ .id = id, .code = code };
        self.len += 1;
    }

    pub fn get(self: *const FunctionDefs, id: i32) ?[]const u8 {
        for (self.entries[0..self.len]) |entry| {
            if (entry.id == id) return entry.code;
        }
        return null;
    }
};

pub const Context = struct {
    stack: []i32,
    storage: []i32,
    cvt: []i32,
    limits: Limits,
    graphics: GraphicsState = .{},
    environment: Environment = .{},
    zones: ?*PointZones = null,
    functions: ?*FunctionDefs = null,
    sp: usize = 0,
    steps: u32 = 0,
    call_depth: u32 = 0,

    pub fn init(buffers: Buffers, limits: Limits) Context {
        return .{
            .stack = buffers.stack,
            .storage = buffers.storage,
            .cvt = buffers.cvt,
            .limits = limits,
        };
    }

    pub fn setEnvironment(self: *Context, environment: Environment) void {
        self.environment = environment;
    }

    pub fn setZones(self: *Context, zones: *PointZones) void {
        self.zones = zones;
    }

    pub fn clearZones(self: *Context) void {
        self.zones = null;
    }

    pub fn setFunctions(self: *Context, functions: *FunctionDefs) void {
        self.functions = functions;
    }

    pub fn clearFunctions(self: *Context) void {
        self.functions = null;
    }

    pub fn resetGraphics(self: *Context) void {
        self.graphics = .{};
    }

    pub fn reset(self: *Context) void {
        self.sp = 0;
        self.steps = 0;
        self.call_depth = 0;
    }

    pub fn stackDepth(self: *const Context) usize {
        return self.sp;
    }

    pub fn stackSlice(self: *const Context) []const i32 {
        return self.stack[0..self.sp];
    }

    pub fn top(self: *const Context) Error!i32 {
        if (self.sp == 0) return Error.StackUnderflow;
        return self.stack[self.sp - 1];
    }

    pub fn execute(self: *Context, code: []const u8) Error!void {
        try self.executeCode(code);
    }

    fn executeCode(self: *Context, code: []const u8) Error!void {
        var pc: usize = 0;
        while (pc < code.len) {
            try self.countStep();
            const op_pc = pc;
            const op = code[pc];
            pc += 1;
            try self.executeOp(code, &pc, op_pc, op);
        }
    }

    fn executeOp(self: *Context, code: []const u8, pc: *usize, op_pc: usize, op: u8) Error!void {
        if (op >= 0xB0 and op <= 0xB7) {
            return self.pushBytes(code, pc, @as(usize, op - 0xB0) + 1);
        }
        if (op >= 0xB8 and op <= 0xBF) {
            return self.pushWords(code, pc, @as(usize, op - 0xB8) + 1);
        }

        switch (op) {
            0x00...0x05, 0x0A...0x0E, 0x10...0x1A, 0x1D...0x1F => try self.executeGraphicsOp(op),
            0x20...0x26 => try self.executeStackOp(op),
            0x29, 0x2E...0x33, 0x38, 0x3A...0x3B, 0x3E...0x3F, 0x46...0x4A => try self.executePointOp(op),
            0x2A...0x2C => try self.executeFunctionOp(code, pc, op),
            0x2D => return Error.InvalidOpcode,
            0x40 => try self.pushBytes(code, pc, try readU8(code, pc)),
            0x41 => try self.pushWords(code, pc, try readU8(code, pc)),
            0x42...0x45, 0x70 => try self.executeMemoryOp(op),
            0x4B...0x4E, 0x56, 0x57, 0x68...0x6F, 0x7A, 0x7C, 0x7D, 0x85, 0x88, 0x8A, 0x8D, 0x8E => try self.executeStateOp(op),
            0x50...0x55, 0x5A...0x5C => try self.executeLogicOp(op),
            0x60...0x67, 0x8B, 0x8C => try self.executeMathOp(op),
            0x1B, 0x1C, 0x58, 0x59, 0x78, 0x79 => try self.executeFlowOp(code, pc, op_pc, op),
            else => return Error.InvalidOpcode,
        }
    }

    fn executeFunctionOp(self: *Context, code: []const u8, pc: *usize, op: u8) Error!void {
        switch (op) {
            0x2A => {
                const function_id = try self.pop();
                const count = try self.popU32();
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    try self.callFunction(function_id);
                }
            },
            0x2B => try self.callFunction(try self.pop()),
            0x2C => {
                const function_id = try self.pop();
                const body_start = pc.*;
                const body_end = try findEndf(code, body_start);
                const defs = try self.functionDefs();
                try defs.put(function_id, code[body_start..body_end]);
                pc.* = body_end + 1;
            },
            else => unreachable,
        }
    }

    fn executePointOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x29 => try self.untouchPoint(),
            0x2E, 0x2F => try self.moveDirectAbsolutePoint(op == 0x2F),
            0x30, 0x31 => try self.interpolateUntouchedPoints(op),
            0x32, 0x33 => try self.shiftPointsByReference(op),
            0x38 => try self.shiftPointsByPixels(),
            0x3A, 0x3B => try self.moveStackIndirectRelativePoint(op == 0x3B),
            0x3E, 0x3F => try self.moveIndirectAbsolutePoint(op == 0x3F),
            0x46, 0x47 => try self.getCoordinate(op == 0x47),
            0x48 => try self.setCoordinateFromStack(),
            0x49, 0x4A => try self.measureDistance(op == 0x4A),
            else => unreachable,
        }
    }

    fn executeGraphicsOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x00 => self.graphics.setVectorToAxis(.y, .both),
            0x01 => self.graphics.setVectorToAxis(.x, .both),
            0x02 => self.graphics.setVectorToAxis(.y, .projection),
            0x03 => self.graphics.setVectorToAxis(.x, .projection),
            0x04 => self.graphics.setVectorToAxis(.y, .freedom),
            0x05 => self.graphics.setVectorToAxis(.x, .freedom),
            0x0A => self.graphics.projection = try self.popVector(),
            0x0B => self.graphics.freedom = try self.popVector(),
            0x0C => try self.pushVector(self.graphics.projection),
            0x0D => try self.pushVector(self.graphics.freedom),
            0x0E => self.graphics.freedom = self.graphics.projection,
            0x10 => self.graphics.setReferencePoint(0, try self.popU32()),
            0x11 => self.graphics.setReferencePoint(1, try self.popU32()),
            0x12 => self.graphics.setReferencePoint(2, try self.popU32()),
            0x13 => self.graphics.setZone(.zp0, try zonePointer(try self.pop())),
            0x14 => self.graphics.setZone(.zp1, try zonePointer(try self.pop())),
            0x15 => self.graphics.setZone(.zp2, try zonePointer(try self.pop())),
            0x16 => self.graphics.setZone(.all, try zonePointer(try self.pop())),
            0x17 => self.graphics.loop_count = try self.popU32(),
            0x18 => self.graphics.round_mode = .grid,
            0x19 => self.graphics.round_mode = .half_grid,
            0x1A => self.graphics.minimum_distance = try self.pop(),
            0x1D => self.graphics.control_value_cut_in = try self.pop(),
            0x1E => self.graphics.single_width_cut_in = try self.pop(),
            0x1F => self.graphics.single_width_value = self.scaleFUnits(try self.pop()),
            else => unreachable,
        }
    }

    fn executeStackOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x20 => try self.push(try self.top()),
            0x21 => _ = try self.pop(),
            0x22 => self.sp = 0,
            0x23 => try self.swap(),
            0x24 => try self.push(@intCast(self.sp)),
            0x25 => try self.copyIndexed(),
            0x26 => try self.moveIndexed(),
            else => unreachable,
        }
    }

    fn executeMemoryOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x42 => {
                const value = try self.pop();
                const index = try checkedIndex(try self.pop(), self.storage.len, Error.InvalidStorageIndex);
                self.storage[index] = value;
            },
            0x43 => {
                const index = try checkedIndex(try self.pop(), self.storage.len, Error.InvalidStorageIndex);
                try self.push(self.storage[index]);
            },
            0x44 => {
                const value = try self.pop();
                const index = try checkedIndex(try self.pop(), self.cvt.len, Error.InvalidCvtIndex);
                self.cvt[index] = value;
            },
            0x45 => {
                const index = try checkedIndex(try self.pop(), self.cvt.len, Error.InvalidCvtIndex);
                try self.push(self.cvt[index]);
            },
            0x70 => {
                const value = try self.pop();
                const index = try checkedIndex(try self.pop(), self.cvt.len, Error.InvalidCvtIndex);
                self.cvt[index] = self.scaleFUnits(value);
            },
            else => unreachable,
        }
    }

    fn executeStateOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x4B => try self.push(@intCast(self.projectionPpem26Dot6() / 64)),
            0x4C => try self.push(self.environment.point_size_26_6),
            0x4D => self.graphics.auto_flip = true,
            0x4E => self.graphics.auto_flip = false,
            0x56 => try self.oddEven(.odd),
            0x57 => try self.oddEven(.even),
            0x68...0x6B => try self.push(self.graphics.round_mode.apply(try self.pop())),
            0x6C...0x6F => try self.push(try self.pop()),
            0x7A => self.graphics.round_mode = .off,
            0x7C => self.graphics.round_mode = .up_grid,
            0x7D => self.graphics.round_mode = .down_grid,
            0x85 => self.graphics.scan_control = try self.pop(),
            0x88 => try self.push(engineInfo(try self.pop())),
            0x8A => try self.roll(),
            0x8D => self.graphics.scan_type = try self.pop(),
            0x8E => try self.setInstructionControl(),
            else => unreachable,
        }
    }

    fn executeLogicOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x50 => try self.compare(.lt),
            0x51 => try self.compare(.lte),
            0x52 => try self.compare(.gt),
            0x53 => try self.compare(.gte),
            0x54 => try self.compare(.eq),
            0x55 => try self.compare(.neq),
            0x5A => try self.binaryBool(.@"and"),
            0x5B => try self.binaryBool(.@"or"),
            0x5C => try self.push(boolInt((try self.pop()) == 0)),
            else => unreachable,
        }
    }

    fn executeMathOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x60 => try self.binaryInt(.add),
            0x61 => try self.binaryInt(.sub),
            0x62 => try self.binaryInt(.div),
            0x63 => try self.binaryInt(.mul),
            0x64 => {
                const value = try self.pop();
                try self.push(if (value < 0) negWrap(value) else value);
            },
            0x65 => try self.push(negWrap(try self.pop())),
            0x66 => try self.push(floor26Dot6(try self.pop())),
            0x67 => try self.push(ceil26Dot6(try self.pop())),
            0x8B => try self.binaryInt(.max),
            0x8C => try self.binaryInt(.min),
            else => unreachable,
        }
    }

    fn executeFlowOp(self: *Context, code: []const u8, pc: *usize, op_pc: usize, op: u8) Error!void {
        switch (op) {
            0x1B => pc.* = try skipToEif(code, pc.*),
            0x1C => pc.* = try jumpTarget(code.len, op_pc, try self.pop()),
            0x58 => {
                if ((try self.pop()) == 0) pc.* = try skipToElseOrEif(code, pc.*);
            },
            0x59 => {},
            0x78 => {
                const condition = try self.pop();
                const offset = try self.pop();
                if (condition != 0) pc.* = try jumpTarget(code.len, op_pc, offset);
            },
            0x79 => {
                const condition = try self.pop();
                const offset = try self.pop();
                if (condition == 0) pc.* = try jumpTarget(code.len, op_pc, offset);
            },
            else => unreachable,
        }
    }

    inline fn countStep(self: *Context) Error!void {
        if (self.steps >= self.limits.max_steps) return Error.ExecutionLimitExceeded;
        self.steps += 1;
    }

    inline fn push(self: *Context, value: i32) Error!void {
        if (self.sp >= self.stack.len) return Error.StackOverflow;
        self.stack[self.sp] = value;
        self.sp += 1;
    }

    inline fn pop(self: *Context) Error!i32 {
        if (self.sp == 0) return Error.StackUnderflow;
        self.sp -= 1;
        return self.stack[self.sp];
    }

    inline fn popPair(self: *Context) Error!Pair {
        if (self.sp < 2) return Error.StackUnderflow;
        self.sp -= 2;
        return .{
            .lhs = self.stack[self.sp],
            .rhs = self.stack[self.sp + 1],
        };
    }

    fn swap(self: *Context) Error!void {
        if (self.sp < 2) return Error.StackUnderflow;
        std.mem.swap(i32, &self.stack[self.sp - 1], &self.stack[self.sp - 2]);
    }

    fn copyIndexed(self: *Context) Error!void {
        const index = try stackIndex(try self.pop(), self.sp);
        try self.push(self.stack[self.sp - index]);
    }

    fn moveIndexed(self: *Context) Error!void {
        const index = try stackIndex(try self.pop(), self.sp);
        const src = self.sp - index;
        const value = self.stack[src];
        var i = src;
        while (i + 1 < self.sp) : (i += 1) {
            self.stack[i] = self.stack[i + 1];
        }
        self.stack[self.sp - 1] = value;
    }

    fn roll(self: *Context) Error!void {
        if (self.sp < 3) return Error.StackUnderflow;
        const a = self.stack[self.sp - 3];
        self.stack[self.sp - 3] = self.stack[self.sp - 2];
        self.stack[self.sp - 2] = self.stack[self.sp - 1];
        self.stack[self.sp - 1] = a;
    }

    fn pushBytes(self: *Context, code: []const u8, pc: *usize, count: usize) Error!void {
        if (pc.* + count > code.len) return Error.UnexpectedEof;
        if (self.sp + count > self.stack.len) return Error.StackOverflow;
        for (code[pc.*..][0..count]) |value| {
            self.stack[self.sp] = value;
            self.sp += 1;
        }
        pc.* += count;
    }

    fn pushWords(self: *Context, code: []const u8, pc: *usize, count: usize) Error!void {
        const byte_count = count * 2;
        if (pc.* + byte_count > code.len) return Error.UnexpectedEof;
        if (self.sp + count > self.stack.len) return Error.StackOverflow;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            self.stack[self.sp] = readI16AssumeInBounds(code, pc.* + i * 2);
            self.sp += 1;
        }
        pc.* += byte_count;
    }

    fn compare(self: *Context, op: CompareOp) Error!void {
        const pair = try self.popPair();
        const result = switch (op) {
            .lt => pair.lhs < pair.rhs,
            .lte => pair.lhs <= pair.rhs,
            .gt => pair.lhs > pair.rhs,
            .gte => pair.lhs >= pair.rhs,
            .eq => pair.lhs == pair.rhs,
            .neq => pair.lhs != pair.rhs,
        };
        try self.push(boolInt(result));
    }

    fn binaryBool(self: *Context, op: BoolOp) Error!void {
        const pair = try self.popPair();
        const result = switch (op) {
            .@"and" => pair.lhs != 0 and pair.rhs != 0,
            .@"or" => pair.lhs != 0 or pair.rhs != 0,
        };
        try self.push(boolInt(result));
    }

    fn binaryInt(self: *Context, op: IntOp) Error!void {
        const pair = try self.popPair();
        const result: i32 = switch (op) {
            .add => @as(i32, @truncate(@as(i64, pair.lhs) + @as(i64, pair.rhs))),
            .sub => @as(i32, @truncate(@as(i64, pair.lhs) - @as(i64, pair.rhs))),
            .div => try div26Dot6(pair.lhs, pair.rhs),
            .mul => mul26Dot6(pair.lhs, pair.rhs),
            .max => @max(pair.lhs, pair.rhs),
            .min => @min(pair.lhs, pair.rhs),
        };
        try self.push(result);
    }

    fn oddEven(self: *Context, parity: Parity) Error!void {
        const rounded = self.graphics.round_mode.apply(try self.pop());
        const integer = @divTrunc(rounded, 64);
        try self.push(boolInt(switch (parity) {
            .odd => integer & 1 != 0,
            .even => integer & 1 == 0,
        }));
    }

    fn moveDirectAbsolutePoint(self: *Context, round: bool) Error!void {
        const point = try self.popU32();
        const projection = try self.projectionDirection(false);
        const freedom = try self.freedomDirection();
        const zone_ptr = try self.zone(self.graphics.zp0);

        var target = try zone_ptr.coordinate(projection, point, false);
        if (round) target = self.graphics.round_mode.apply(target);
        try zone_ptr.moveTo(projection, freedom, point, target);

        self.graphics.rp0 = point;
        self.graphics.rp1 = point;
    }

    fn moveIndirectAbsolutePoint(self: *Context, round: bool) Error!void {
        const cvt_index = try checkedIndex(try self.pop(), self.cvt.len, Error.InvalidCvtIndex);
        const point = try self.popU32();
        const projection = try self.projectionDirection(false);
        const freedom = try self.freedomDirection();
        const zone_ptr = try self.zone(self.graphics.zp0);

        var target = self.cvt[cvt_index];
        if (round) {
            const original = try zone_ptr.coordinate(projection, point, true);
            if (absDiffI32(target, original) > self.graphics.control_value_cut_in) {
                target = original;
            }
            target = self.graphics.round_mode.apply(target);
        }
        try zone_ptr.moveTo(projection, freedom, point, target);

        self.graphics.rp0 = point;
        self.graphics.rp1 = point;
    }

    fn moveStackIndirectRelativePoint(self: *Context, set_rp0: bool) Error!void {
        const distance = try self.pop();
        const point = try self.popU32();
        const projection = try self.projectionDirection(false);
        const freedom = try self.freedomDirection();
        const ref_zone = try self.zoneConst(self.graphics.zp0);
        const point_zone = try self.zone(self.graphics.zp1);
        const target = addWrap(try ref_zone.coordinate(projection, self.graphics.rp0, false), distance);

        try point_zone.moveTo(projection, freedom, point, target);
        self.graphics.rp1 = self.graphics.rp0;
        self.graphics.rp2 = point;
        if (set_rp0) self.graphics.rp0 = point;
    }

    fn getCoordinate(self: *Context, original: bool) Error!void {
        const point = try self.popU32();
        const projection = try self.projectionDirection(original);
        const zone_ptr = try self.zoneConst(self.graphics.zp2);
        try self.push(try zone_ptr.coordinate(projection, point, original));
    }

    fn setCoordinateFromStack(self: *Context) Error!void {
        const coordinate = try self.pop();
        const point = try self.popU32();
        const projection = try self.projectionDirection(false);
        const freedom = try self.freedomDirection();
        const zone_ptr = try self.zone(self.graphics.zp2);
        try zone_ptr.moveTo(projection, freedom, point, coordinate);
    }

    fn measureDistance(self: *Context, original: bool) Error!void {
        const p2 = try self.popU32();
        const p1 = try self.popU32();
        const projection = try self.projectionDirection(original);
        const zone1 = try self.zoneConst(self.graphics.zp0);
        const zone2 = try self.zoneConst(self.graphics.zp1);
        const c1 = try zone1.coordinate(projection, p1, original);
        const c2 = try zone2.coordinate(projection, p2, original);
        try self.push(subWrap(c2, c1));
    }

    fn shiftPointsByReference(self: *Context, op: u8) Error!void {
        const projection = try self.projectionDirection(false);
        const freedom = try self.freedomDirection();
        const ref_pointer = if (op == 0x32) self.graphics.zp1 else self.graphics.zp0;
        const ref_point = if (op == 0x32) self.graphics.rp2 else self.graphics.rp1;
        const ref_zone = try self.zoneConst(ref_pointer);
        const distance = subWrap(
            try ref_zone.coordinate(projection, ref_point, false),
            try ref_zone.coordinate(projection, ref_point, true),
        );
        const point_zone = try self.zone(self.graphics.zp2);
        try self.shiftLoopPoints(point_zone, freedom, distance);
    }

    fn shiftPointsByPixels(self: *Context) Error!void {
        const distance = try self.pop();
        const freedom = try self.freedomDirection();
        const zone_ptr = try self.zone(self.graphics.zp2);
        try self.shiftLoopPoints(zone_ptr, freedom, distance);
    }

    fn shiftLoopPoints(self: *Context, zone_ptr: *PointZone, freedom: tt_points.Direction, distance: i32) Error!void {
        const count = self.graphics.loop_count;
        if (count == 0) return Error.StackUnderflow;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try zone_ptr.shift(freedom, try self.popU32(), distance);
        }
        self.graphics.loop_count = 1;
    }

    fn untouchPoint(self: *Context) Error!void {
        const point = try self.popU32();
        const zone_ptr = try self.zone(self.graphics.zp0);
        try zone_ptr.untouch(self.graphics.freedom, point);
    }

    fn interpolateUntouchedPoints(self: *Context, op: u8) Error!void {
        const zone_ptr = try self.zone(.glyph);
        try zone_ptr.interpolateUntouched(if (op == 0x30) .y else .x);
    }

    fn callFunction(self: *Context, function_id: i32) Error!void {
        const defs = try self.functionDefs();
        const code = defs.get(function_id) orelse return Error.UnknownFunction;
        if (self.call_depth >= self.limits.max_call_depth) return Error.CallDepthExceeded;

        self.call_depth += 1;
        defer self.call_depth -= 1;
        try self.executeCode(code);
    }

    fn functionDefs(self: *Context) Error!*FunctionDefs {
        return self.functions orelse Error.MissingFunctions;
    }

    fn setInstructionControl(self: *Context) Error!void {
        const value = try self.pop();
        const selector = try self.pop();
        switch (selector) {
            1 => {
                if (value != 0) {
                    self.graphics.instruct_control |= 1;
                } else {
                    self.graphics.instruct_control &= ~@as(i32, 1);
                }
            },
            2 => {
                if (value != 0) {
                    self.graphics.instruct_control |= 2;
                } else {
                    self.graphics.instruct_control &= ~@as(i32, 2);
                }
            },
            else => {},
        }
    }

    fn popU32(self: *Context) Error!u32 {
        const value = try self.pop();
        if (value < 0) return Error.StackUnderflow;
        return @intCast(value);
    }

    fn popVector(self: *Context) Error!tt_graphics.Vector {
        const y = try self.pop();
        const x = try self.pop();
        return tt_graphics.normalizeF2Dot14(x, y);
    }

    fn pushVector(self: *Context, vector: tt_graphics.Vector) Error!void {
        try self.push(vector.x);
        try self.push(vector.y);
    }

    fn zone(self: *Context, pointer: tt_graphics.ZonePointer) Error!*PointZone {
        const zones = self.zones orelse return Error.MissingZones;
        return zones.select(pointer);
    }

    fn zoneConst(self: *const Context, pointer: tt_graphics.ZonePointer) Error!*const PointZone {
        const zones = self.zones orelse return Error.MissingZones;
        return zones.selectConst(pointer);
    }

    fn projectionDirection(self: *const Context, original: bool) Error!tt_points.Direction {
        const vector = if (original) self.graphics.dual_projection else self.graphics.projection;
        return tt_points.directionFromVector(vector) orelse Error.UnsupportedVector;
    }

    fn freedomDirection(self: *const Context) Error!tt_points.Direction {
        return tt_points.directionFromVector(self.graphics.freedom) orelse Error.UnsupportedVector;
    }

    fn scaleFUnits(self: *const Context, value: i32) i32 {
        return if (self.usesXScale())
            self.environment.scaleFUnitsX(value)
        else
            self.environment.scaleFUnitsY(value);
    }

    fn projectionPpem26Dot6(self: *const Context) u32 {
        return if (self.usesXScale())
            self.environment.ppem_x_26_6
        else
            self.environment.ppem_y_26_6;
    }

    fn usesXScale(self: *const Context) bool {
        return absI32(self.graphics.projection.x) >= absI32(self.graphics.projection.y);
    }
};

const Pair = struct {
    lhs: i32,
    rhs: i32,
};

const CompareOp = enum {
    lt,
    lte,
    gt,
    gte,
    eq,
    neq,
};

const BoolOp = enum {
    @"and",
    @"or",
};

const IntOp = enum {
    add,
    sub,
    div,
    mul,
    max,
    min,
};

const Parity = enum {
    odd,
    even,
};

inline fn readU8(code: []const u8, pc: *usize) Error!u8 {
    if (pc.* >= code.len) return Error.UnexpectedEof;
    const value = code[pc.*];
    pc.* += 1;
    return value;
}

inline fn readI16AssumeInBounds(code: []const u8, offset: usize) i32 {
    return std.mem.readInt(i16, code[offset..][0..2], .big);
}

fn checkedIndex(value: i32, len: usize, err: Error) Error!usize {
    if (value < 0) return err;
    const index: usize = @intCast(value);
    if (index >= len) return err;
    return index;
}

fn stackIndex(value: i32, depth: usize) Error!usize {
    if (value <= 0) return Error.StackUnderflow;
    const index: usize = @intCast(value);
    if (index > depth) return Error.StackUnderflow;
    return index;
}

fn boolInt(value: bool) i32 {
    return if (value) 1 else 0;
}

fn negWrap(value: i32) i32 {
    return @truncate(-@as(i64, value));
}

fn absI32(value: i32) i32 {
    return if (value < 0) negWrap(value) else value;
}

fn absDiffI32(lhs: i32, rhs: i32) i32 {
    return absI32(subWrap(lhs, rhs));
}

fn addWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) + @as(i64, rhs));
}

fn subWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) - @as(i64, rhs));
}

fn div26Dot6(lhs: i32, rhs: i32) Error!i32 {
    if (rhs == 0) return Error.DivisionByZero;
    return @truncate(@divTrunc(@as(i64, lhs) * 64, rhs));
}

fn mul26Dot6(lhs: i32, rhs: i32) i32 {
    return @truncate(@divTrunc(@as(i64, lhs) * @as(i64, rhs), 64));
}

fn floor26Dot6(value: i32) i32 {
    return value & ~@as(i32, 63);
}

fn ceil26Dot6(value: i32) i32 {
    return floor26Dot6(@truncate(@as(i64, value) + 63));
}

fn zonePointer(value: i32) Error!tt_graphics.ZonePointer {
    return switch (value) {
        0 => .twilight,
        1 => .glyph,
        else => Error.InvalidZone,
    };
}

fn engineInfo(selector: i32) i32 {
    var result: i32 = 0;
    if (selector & 1 != 0) result |= 35;
    if (selector & 32 != 0) result |= 4096;
    return result;
}

fn jumpTarget(code_len: usize, op_pc: usize, offset: i32) Error!usize {
    const target = @as(i64, @intCast(op_pc)) + @as(i64, offset);
    if (target < 0 or target > code_len) return Error.InvalidJump;
    return @intCast(target);
}

fn skipToElseOrEif(code: []const u8, pc: usize) Error!usize {
    return skipStructured(code, pc, true);
}

fn skipToEif(code: []const u8, pc: usize) Error!usize {
    return skipStructured(code, pc, false);
}

fn skipStructured(code: []const u8, start: usize, stop_at_else: bool) Error!usize {
    var pc = start;
    var depth: u32 = 0;
    while (pc < code.len) {
        const op = code[pc];
        pc += 1;

        if (op == 0x58) {
            depth += 1;
            continue;
        }
        if (op == 0x59) {
            if (depth == 0) return pc;
            depth -= 1;
            continue;
        }
        if (op == 0x1B and stop_at_else and depth == 0) return pc;

        try skipInlineOperands(code, &pc, op);
    }
    return Error.UnexpectedEof;
}

fn findEndf(code: []const u8, start: usize) Error!usize {
    var pc = start;
    while (pc < code.len) {
        const op = code[pc];
        if (op == 0x2D) return pc;
        pc += 1;
        try skipInlineOperands(code, &pc, op);
    }
    return Error.InvalidFunctionDefinition;
}

fn skipInlineOperands(code: []const u8, pc: *usize, op: u8) Error!void {
    if (op == 0x2C) {
        pc.* = (try findEndf(code, pc.*)) + 1;
        return;
    }

    const bytes = if (op >= 0xB0 and op <= 0xB7)
        @as(usize, op - 0xB0) + 1
    else if (op >= 0xB8 and op <= 0xBF)
        (@as(usize, op - 0xB8) + 1) * 2
    else switch (op) {
        0x40 => blk: {
            const count = try readU8(code, pc);
            break :blk @as(usize, count);
        },
        0x41 => blk: {
            const count = try readU8(code, pc);
            break :blk @as(usize, count) * 2;
        },
        else => 0,
    };

    if (pc.* + bytes > code.len) return Error.UnexpectedEof;
    pc.* += bytes;
}

fn expectStack(ctx: *const Context, expected: []const i32) !void {
    try std.testing.expectEqualSlices(i32, expected, ctx.stackSlice());
}

test "tt executor pushes and computes stack math" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    try ctx.execute(&.{
        0xB1, 10, 7, 0x60, // ADD
        0xB0, 4, 0x61, // SUB
        0xB1, 64, 128, 0x63, // MUL: 1.0px * 2.0px in 26.6 => 2.0px
    });

    try expectStack(&ctx, &.{ 13, 128 });
}

test "tt executor supports push words and stack indexing" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    try ctx.execute(&.{
        0xB8, 0xFF, 0xFE, // -2
        0xB2, 10,   20,
        30,
        0xB0, 2, 0x25, // CINDEX: copy 20
        0xB0, 3, 0x26, // MINDEX: move 20 to top
        0x23, // SWAP
    });

    try expectStack(&ctx, &.{ -2, 10, 30, 20, 20 });
}

test "tt executor reads and writes storage and cvt" {
    var stack: [16]i32 = undefined;
    var storage: [4]i32 = .{ 0, 0, 0, 0 };
    var cvt: [4]i32 = .{ 10, 20, 30, 40 };
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    try ctx.execute(&.{
        0xB1, 2, 99, 0x42, // WS
        0xB0, 2, 0x43, // RS
        0xB1, 1, 88, 0x44, // WCVTP
        0xB0, 1, 0x45, // RCVT
    });

    try std.testing.expectEqual(@as(i32, 99), storage[2]);
    try std.testing.expectEqual(@as(i32, 88), cvt[1]);
    try expectStack(&ctx, &.{ 99, 88 });
}

test "tt executor handles structured flow and jumps" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    try ctx.execute(&.{
        0xB0, 0, 0x58, // IF false
        0xB0, 1,
        0x1B, // ELSE
        0xB0,
        2,
        0x59, // EIF
        0xB1, 3, 1,    0x78, // JROT +1, true: skip next instruction
        0xB0, 9, 0xB0, 4,
    });

    try expectStack(&ctx, &.{ 2, 4 });
}

test "tt executor enforces execution limit" {
    var stack: [4]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{
        .stack = &stack,
        .storage = &storage,
        .cvt = &cvt,
    }, .{ .max_steps = 2 });

    try std.testing.expectError(Error.ExecutionLimitExceeded, ctx.execute(&.{ 0xB0, 1, 0xB0, 2, 0x60 }));
}

test "tt executor updates graphics vectors and round state" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    try ctx.execute(&.{
        0x00, // SVTCA[y]
        0x0C, // GPV
        0x7A, // ROFF
        0xB0, 33, 0x68, // ROUND[0] with off mode
        0x18, // RTG
        0xB0, 33, 0x68, // ROUND[0] to grid
    });

    try expectStack(&ctx, &.{ 0, 0x4000, 33, 64 });
    try std.testing.expectEqual(tt_graphics.RoundMode.grid, ctx.graphics.round_mode);
}

test "tt executor scales WCVTF through caller environment" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [2]i32 = .{ 0, 0 };
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});
    ctx.setEnvironment(.{
        .ppem_x_26_6 = 10 * 64,
        .ppem_y_26_6 = 12 * 64,
        .units_per_em = 1000,
    });

    try ctx.execute(&.{
        0x01, // SVTCA[x]
        0xB1,
        0,
        50,
        0x70,
        0x00, // SVTCA[y]
        0xB1,
        1,
        50,
        0x70,
    });

    try std.testing.expectEqual(@as(i32, 32), cvt[0]);
    try std.testing.expectEqual(@as(i32, 38), cvt[1]);
}

test "tt executor moves and measures attached point zones" {
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{90};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [1]Point = undefined;
    var glyph_points: [3]Point = .{
        .{ .x = 40, .y = 0, .ox = 40, .oy = 0, .on_curve = true },
        .{ .x = 80, .y = 0, .ox = 80, .oy = 0, .on_curve = true },
        .{ .x = 120, .y = 0, .ox = 120, .oy = 0, .on_curve = true },
    };
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 0, 0x2F, // MDAP[1]: round point 0 to x=64
        0xB0, 0, 0x46, // GC[0]
        0xB1, 1, 128, 0x48, // SCFS: move point 1 to x=128
        0xB1, 0, 1, 0x49, // MD[0]: current distance p0->p1
        0xB1, 2, 0, 0x3E, // MIAP[0]: move point 2 to cvt[0]
    });

    try expectStack(&ctx, &.{ 64, 64 });
    try std.testing.expectEqual(@as(i32, 64), glyph_points[0].x);
    try std.testing.expectEqual(@as(i32, 128), glyph_points[1].x);
    try std.testing.expectEqual(@as(i32, 90), glyph_points[2].x);
    try std.testing.expect(glyph_points[0].touched_x);
    try std.testing.expect(glyph_points[1].touched_x);
    try std.testing.expect(glyph_points[2].touched_x);
}

test "tt executor shifts looped points and requires attached zones" {
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    try std.testing.expectError(Error.MissingZones, ctx.execute(&.{ 0xB0, 0, 0x2E }));

    ctx.reset();
    var twilight_points: [1]Point = undefined;
    var glyph_points: [3]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 10, .y = 0, .ox = 10, .oy = 0, .on_curve = true },
        .{ .x = 20, .y = 0, .ox = 20, .oy = 0, .on_curve = true },
    };
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 2, 0x17, // SLOOP 2
        0xB2, 1, 2, 5, 0x38, // SHPIX: shift p1,p2 by 5 along x
    });

    try std.testing.expectEqual(@as(i32, 15), glyph_points[1].x);
    try std.testing.expectEqual(@as(i32, 25), glyph_points[2].x);
    try std.testing.expectEqual(@as(u32, 1), ctx.graphics.loop_count);
}

test "tt executor interpolates untouched glyph points" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [1]Point = undefined;
    var glyph_points: [3]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true, .touched_x = true },
        .{ .x = 50, .y = 0, .ox = 50, .oy = 0, .on_curve = true },
        .{ .x = 200, .y = 0, .ox = 100, .oy = 0, .on_curve = true, .touched_x = true },
    };
    const contours = [_]@import("tt_outline.zig").ContourRange{.{ .start = 0, .end = 3 }};
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points, .contours = &contours },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{0x31}); // IUP[x]

    try std.testing.expectEqual(@as(i32, 100), glyph_points[1].x);
}

test "tt executor records and calls function definitions" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var entries: [4]Function = undefined;
    var functions: FunctionDefs = .{ .entries = &entries };
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});
    ctx.setFunctions(&functions);

    try ctx.execute(&.{
        0xB0, 7, 0x2C, // FDEF 7
        0xB0, 1, 0x60, // add one to the caller's top stack value
        0x2D, // ENDF
        0xB0,
        41,
        0xB0, 7, 0x2B, // CALL 7
    });

    try expectStack(&ctx, &.{42});
    try std.testing.expectEqual(@as(usize, 1), functions.len);
}

test "tt executor loop-calls functions and enforces call depth" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var entries: [4]Function = undefined;
    var functions: FunctionDefs = .{ .entries = &entries };
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{ .max_call_depth = 2 });
    ctx.setFunctions(&functions);

    try ctx.execute(&.{
        0xB0, 4, 0x2C, // FDEF 4
        0xB0, 1, 0x60,
        0x2D,
        0xB2, 0, 3, 4, 0x2A, // LOOPCALL function 4 three times
    });

    try expectStack(&ctx, &.{3});

    ctx.reset();
    functions.reset();
    try ctx.execute(&.{
        0xB0, 5, 0x2C, // FDEF 5
        0xB0, 5, 0x2B, // recursive CALL 5
        0x2D,
    });
    try std.testing.expectError(Error.CallDepthExceeded, ctx.execute(&.{ 0xB0, 5, 0x2B }));
}

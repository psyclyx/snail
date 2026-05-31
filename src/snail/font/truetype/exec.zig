const std = @import("std");
const builtin = @import("builtin");

const tt_graphics = @import("graphics.zig");
const tt_points = @import("points.zig");

/// LLVM (used in Release modes) supports `@call(.always_tail, ...)`; the
/// stage2 x86_64 backend (used in Debug) does not. Gate the guaranteed
/// tail call so Debug builds compile via a regular recursive call.
const tail_calls_supported = builtin.mode != .Debug;

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
    lookup: []?[]const u8 = &.{},
    len: usize = 0,

    pub fn reset(self: *FunctionDefs) void {
        self.len = 0;
        @memset(self.lookup, null);
    }

    pub fn put(self: *FunctionDefs, id: i32, code: []const u8) Error!void {
        const direct_slot = self.lookupSlot(id);
        for (self.entries[0..self.len]) |*entry| {
            if (entry.id == id) {
                entry.code = code;
                if (direct_slot) |slot| slot.* = code;
                return;
            }
        }
        if (self.len >= self.entries.len) return Error.TooManyFunctions;
        self.entries[self.len] = .{ .id = id, .code = code };
        self.len += 1;
        if (direct_slot) |slot| slot.* = code;
    }

    pub fn get(self: *const FunctionDefs, id: i32) ?[]const u8 {
        if (self.lookupCode(id)) |code| return code;
        for (self.entries[0..self.len]) |entry| {
            if (entry.id == id) return entry.code;
        }
        return null;
    }

    fn lookupSlot(self: *FunctionDefs, id: i32) ?*?[]const u8 {
        if (id < 0) return null;
        const index: usize = @intCast(id);
        if (index >= self.lookup.len) return null;
        return &self.lookup[index];
    }

    fn lookupCode(self: *const FunctionDefs, id: i32) ?[]const u8 {
        if (id < 0) return null;
        const index: usize = @intCast(id);
        if (index >= self.lookup.len) return null;
        return self.lookup[index];
    }
};

/// Memoizes IF/ELSE-to-EIF skip targets. The TT VM scans bytes forward to
/// resolve a control-flow skip on every taken branch; for function bodies
/// (called many times across a hint pass) the work is identical each call
/// and is the single largest non-dispatch cost in the interpreter. Keyed by
/// `(code.ptr, pc, stop_at_else)` so the cache is valid for any bytecode
/// whose backing storage is stable — which covers font/control programs,
/// function bodies, and the per-glyph instruction stream as long as the
/// caller doesn't relocate the bytes underneath us.
pub const SkipCache = struct {
    map: std.AutoHashMap(Key, u32),

    pub const Key = struct {
        code_ptr: usize,
        pc: u32,
        stop_at_else: bool,
    };

    pub fn init(allocator: std.mem.Allocator) SkipCache {
        return .{ .map = std.AutoHashMap(Key, u32).init(allocator) };
    }

    pub fn deinit(self: *SkipCache) void {
        self.map.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *SkipCache) void {
        self.map.clearRetainingCapacity();
    }

    fn keyFor(code: []const u8, pc: usize, stop_at_else: bool) Key {
        return .{ .code_ptr = @intFromPtr(code.ptr), .pc = @intCast(pc), .stop_at_else = stop_at_else };
    }

    fn get(self: *const SkipCache, code: []const u8, pc: usize, stop_at_else: bool) ?u32 {
        return self.map.get(keyFor(code, pc, stop_at_else));
    }

    fn put(self: *SkipCache, code: []const u8, pc: usize, stop_at_else: bool, target: u32) !void {
        try self.map.put(keyFor(code, pc, stop_at_else), target);
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
    skip_cache: ?*SkipCache = null,
    sp: usize = 0,
    steps: u32 = 0,
    call_depth: u32 = 0,
    /// Per-distance-type rounding compensations indexed by `distance_type`
    /// (gray, black, white, undef) of MIRP/MDRP/ROUND. Bias added to the
    /// magnitude before rounding to model ink-spread compensation. FreeType
    /// keeps these but sets them to zero in practice (its caller never
    /// pokes them either); snail does the same, but the infrastructure
    /// matches so a future engine pass — or a caller wiring non-zero
    /// compensations — produces spec-compliant results.
    compensations: [4]i32 = .{ 0, 0, 0, 0 },

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

    pub fn setSkipCache(self: *Context, cache: *SkipCache) void {
        self.skip_cache = cache;
    }

    pub fn clearSkipCache(self: *Context) void {
        self.skip_cache = null;
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
        var steps = self.steps;
        defer self.steps = steps;
        try self.executeCode(code, &steps);
    }

    fn executeCode(self: *Context, code: []const u8, steps: *u32) Error!void {
        if (code.len == 0) return;
        try self.countStep(steps);
        const op = code[0];
        return tail_dispatch[op](self, code, 1, steps);
    }

    fn executeOp(self: *Context, code: []const u8, pc: *usize, op_pc: usize, op: u8, steps: *u32) Error!void {
        if (op >= 0xB0 and op <= 0xB7) {
            return self.pushBytes(code, pc, @as(usize, op - 0xB0) + 1);
        }
        if (op >= 0xB8 and op <= 0xBF) {
            return self.pushWords(code, pc, @as(usize, op - 0xB8) + 1);
        }

        switch (op) {
            0x00...0x0E, 0x10...0x1A, 0x1D...0x1F, 0x86...0x87 => try self.executeGraphicsOp(op),
            0x20...0x26 => try self.executeStackOp(op),
            0x27, 0x29, 0x2E...0x3C, 0x3E...0x3F, 0x46...0x4A, 0xC0...0xFF => try self.executePointOp(op),
            0x2A...0x2C => try self.executeFunctionOp(code, pc, op, steps),
            0x2D => return Error.InvalidOpcode,
            0x3D => self.graphics.round_mode = .double_grid, // RTDG
            0x40 => try self.pushBytes(code, pc, try readU8(code, pc)),
            0x41 => try self.pushWords(code, pc, try readU8(code, pc)),
            0x42...0x45, 0x70 => try self.executeMemoryOp(op),
            0x4B...0x4E, 0x56, 0x57, 0x5E, 0x5F, 0x68...0x6F, 0x76...0x77, 0x7A, 0x7C, 0x7D, 0x85, 0x88, 0x8A, 0x8D, 0x8E => try self.executeStateOp(op),
            0x50...0x55, 0x5A...0x5C => try self.executeLogicOp(op),
            0x5D, 0x71...0x75 => try self.executeDeltaOp(op),
            0x60...0x67, 0x8B, 0x8C => try self.executeMathOp(op),
            0x1B, 0x1C, 0x58, 0x59, 0x78, 0x79 => try self.executeFlowOp(code, pc, op_pc, op),
            else => return Error.InvalidOpcode,
        }
    }

    inline fn executeFunctionOp(self: *Context, code: []const u8, pc: *usize, op: u8, steps: *u32) Error!void {
        switch (op) {
            0x2A => {
                const function_id = try self.pop();
                const count = try self.popU32();
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    try self.callFunction(function_id, steps);
                }
            },
            0x2B => try self.callFunction(try self.pop(), steps),
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

    inline fn executePointOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x27 => try self.alignPoints(),
            0x29 => try self.untouchPoint(),
            0x2E, 0x2F => try self.moveDirectAbsolutePoint(op == 0x2F),
            0x30, 0x31 => try self.interpolateUntouchedPoints(op),
            0x32, 0x33 => try self.shiftPointsByReference(op),
            0x34, 0x35 => try self.shiftContourByReference(op),
            0x36, 0x37 => try self.shiftZoneByReference(op),
            0x38 => try self.shiftPointsByPixels(),
            0x39 => try self.interpolatePointsByReference(),
            0x3A, 0x3B => try self.moveStackIndirectRelativePoint(op == 0x3B),
            0x3C => try self.alignReferencePoints(),
            0x3E, 0x3F => try self.moveIndirectAbsolutePoint(op == 0x3F),
            0x46, 0x47 => try self.getCoordinate(op == 0x47),
            0x48 => try self.setCoordinateFromStack(),
            0x49, 0x4A => try self.measureDistance(op == 0x4A),
            0xC0...0xDF => try self.moveDirectRelativePoint(relativeFlags(op, 0xC0)),
            0xE0...0xFF => try self.moveIndirectRelativePoint(relativeFlags(op, 0xE0)),
            else => unreachable,
        }
    }

    inline fn executeGraphicsOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x00 => self.graphics.setVectorToAxis(.y, .both),
            0x01 => self.graphics.setVectorToAxis(.x, .both),
            0x02 => self.graphics.setVectorToAxis(.y, .projection),
            0x03 => self.graphics.setVectorToAxis(.x, .projection),
            0x04 => self.graphics.setVectorToAxis(.y, .freedom),
            0x05 => self.graphics.setVectorToAxis(.x, .freedom),
            0x06, 0x07 => self.setProjectionVector(try self.lineVector((op & 1) != 0, false)),
            0x08, 0x09 => self.graphics.freedom = try self.lineVector((op & 1) != 0, false),
            0x0A => self.setProjectionVector(try self.popVector()),
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
            0x86, 0x87 => {
                const points = try self.popLinePoints();
                self.graphics.projection = try self.lineVectorFromPoints(points, (op & 1) != 0, false);
                self.graphics.dual_projection = try self.lineVectorFromPoints(points, (op & 1) != 0, true);
            },
            else => unreachable,
        }
    }

    inline fn executeStackOp(self: *Context, op: u8) Error!void {
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

    inline fn executeMemoryOp(self: *Context, op: u8) Error!void {
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
                // WCVTP: write CVT in projection pixels. Per FreeType's
                // Write_CVT_Stretched the incoming value (already in the
                // current projection's 26.6) is divided by the projection
                // ratio so the cell holds canonical (base-ppem) pixels.
                const value = try self.pop();
                self.cvtWrite(try self.pop(), value);
            },
            0x45 => {
                try self.push(self.cvtRead(try self.pop()));
            },
            0x70 => {
                // WCVTF: write CVT in FUnits. Per FreeType's Ins_WCVTF the
                // value is multiplied by `tt_metrics.scale` (the base / y
                // scale) and stored *directly* in the canonical cell — no
                // projection ratio is applied, regardless of stretching.
                const value = try self.pop();
                self.cvtWriteCanonical(try self.pop(), self.scaleFUnitsBase(value));
            },
            else => unreachable,
        }
    }

    /// Write to CVT bypassing the projection-ratio rescale. Used by WCVTF
    /// (0x70) — per FreeType, only the per-pixel write path (WCVTP/Move_CVT)
    /// applies stretching.
    inline fn cvtWriteCanonical(self: *Context, raw_index: i32, value: i32) void {
        if (raw_index < 0) return;
        const index: usize = @intCast(raw_index);
        if (index >= self.cvt.len) return;
        self.cvt[index] = value;
    }

    /// Read from CVT with FreeType-style OOB tolerance: out-of-range
    /// (negative or past the end) returns 0 instead of erroring. Real fonts
    /// in the wild (e.g. NotoSansSymbols' prep program produces idx=-8)
    /// rely on this — strict spec behaviour rejects ~80% of such fonts'
    /// glyphs and degrades to unhinted curves.
    ///
    /// The cell is stored in canonical (base-ppem) 26.6 pixels. We apply
    /// the projection-relative ratio on read, matching FreeType's
    /// `Read_CVT_Stretched`. This is what makes mid-prep SVTCA switches
    /// produce consistent per-axis cut-ins and key-distance values.
    inline fn cvtRead(self: *const Context, raw_index: i32) i32 {
        if (raw_index < 0) return 0;
        const index: usize = @intCast(raw_index);
        if (index >= self.cvt.len) return 0;
        const raw = self.cvt[index];
        if (!self.environment.isStretched()) return raw;
        return tt_graphics.mulFix16Dot16(raw, self.environment.projectionRatio(self.graphics.projection));
    }

    /// Write to CVT with FreeType-style OOB tolerance: out-of-range writes
    /// are silently dropped instead of erroring. See `cvtRead`. The incoming
    /// `value` is in the *current* projection's 26.6 pixels; we divide by
    /// the projection ratio so the stored cell stays in canonical base-ppem
    /// pixels (matching FreeType's `Write_CVT_Stretched`).
    inline fn cvtWrite(self: *Context, raw_index: i32, value: i32) void {
        if (raw_index < 0) return;
        const index: usize = @intCast(raw_index);
        if (index >= self.cvt.len) return;
        if (!self.environment.isStretched()) {
            self.cvt[index] = value;
            return;
        }
        self.cvt[index] = tt_graphics.divFix16Dot16(value, self.environment.projectionRatio(self.graphics.projection));
    }

    inline fn executeStateOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x4B => try self.push(@intCast(self.projectionPpem26Dot6() / 64)),
            0x4C => try self.push(self.environment.point_size_26_6),
            0x4D => self.graphics.auto_flip = true,
            0x4E => self.graphics.auto_flip = false,
            0x56 => try self.oddEven(.odd),
            0x57 => try self.oddEven(.even),
            0x5E => self.graphics.delta_base = try self.pop(),
            0x5F => self.graphics.delta_shift = try self.pop(),
            // ROUND[distance_type] / NROUND[distance_type]: the low 2 bits of
            // the opcode select the per-color compensation (gray/black/white/
            // undef). NROUND skips the rounding step but still applies the
            // compensation (FreeType convention).
            0x68...0x6B => try self.push(self.graphics.round_mode.apply(try self.pop(), self.compensations[op & 0x03])),
            0x6C...0x6F => {
                const value = try self.pop();
                const compensated = (tt_graphics.RoundMode{ .off = {} }).apply(value, self.compensations[op & 0x03]);
                try self.push(compensated);
            },
            0x76 => self.graphics.round_mode = .{ .super = tt_graphics.decodeSuperRound(0x40, try self.pop()) },
            0x77 => self.graphics.round_mode = .{ .super = tt_graphics.decodeSuperRound(0x2D41, try self.pop()) },
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

    inline fn executeLogicOp(self: *Context, op: u8) Error!void {
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

    inline fn executeDeltaOp(self: *Context, op: u8) Error!void {
        switch (op) {
            0x5D => try self.executeDeltaPoint(0),
            0x71 => try self.executeDeltaPoint(16),
            0x72 => try self.executeDeltaPoint(32),
            0x73 => try self.executeDeltaCvt(0),
            0x74 => try self.executeDeltaCvt(16),
            0x75 => try self.executeDeltaCvt(32),
            else => unreachable,
        }
    }

    inline fn executeMathOp(self: *Context, op: u8) Error!void {
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

    inline fn executeFlowOp(self: *Context, code: []const u8, pc: *usize, op_pc: usize, op: u8) Error!void {
        switch (op) {
            0x1B => pc.* = try self.cachedSkip(code, pc.*, false),
            0x1C => pc.* = try jumpTarget(code.len, op_pc, try self.pop()),
            0x58 => {
                if ((try self.pop()) == 0) pc.* = try self.cachedSkip(code, pc.*, true);
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

    inline fn countStep(self: *Context, steps: *u32) Error!void {
        if (steps.* >= self.limits.max_steps) return Error.ExecutionLimitExceeded;
        steps.* += 1;
    }

    fn cachedSkip(self: *Context, code: []const u8, pc: usize, stop_at_else: bool) Error!usize {
        if (self.skip_cache) |cache| {
            if (cache.get(code, pc, stop_at_else)) |target| return @intCast(target);
            const target = try skipStructured(code, pc, stop_at_else);
            // Best-effort cache: an OOM here just means we'll re-scan next time.
            cache.put(code, pc, stop_at_else, @intCast(target)) catch {};
            return target;
        }
        return skipStructured(code, pc, stop_at_else);
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

    fn executeDeltaPoint(self: *Context, base_offset: i32) Error!void {
        const freedom = self.graphics.freedom;
        const zone_ptr = try self.zone(self.graphics.zp0);
        const count = try self.popU32();

        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const arg = try self.pop();
            const point = try self.popU32();
            if (self.deltaDistance(arg, base_offset)) |distance| {
                try zone_ptr.shiftVector(freedom, point, distance);
            }
        }
    }

    fn executeDeltaCvt(self: *Context, base_offset: i32) Error!void {
        const count = try self.popU32();

        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const arg = try self.pop();
            const raw_index = try self.pop();
            if (self.deltaDistance(arg, base_offset)) |distance| {
                self.cvtWrite(raw_index, addWrap(self.cvtRead(raw_index), distance));
            }
        }
    }

    fn deltaDistance(self: *const Context, arg: i32, base_offset: i32) ?i32 {
        if (arg < 0) return null;
        const encoded: u8 = @truncate(@as(u32, @intCast(arg)));
        const ppem = self.projectionPpem26Dot6() / 64;
        const target_ppem = self.graphics.delta_base + base_offset + @as(i32, encoded >> 4);
        if (@as(i32, @intCast(ppem)) != target_ppem) return null;

        // Per TrueType spec: low 4 bits encode magnitude with a forbidden 0:
        //   0..7  → -8..-1  (negative magnitudes)
        //   8..15 → +1..+8  (positive magnitudes)
        // There is no encoding for zero — every byte produces a non-zero move.
        const low = encoded & 0x0F;
        const steps: i32 = if (low > 7)
            @as(i32, low) - 7
        else
            @as(i32, low) - 8;
        return @truncate(@as(i64, steps) * deltaQuantum(self.graphics.delta_shift));
    }

    fn oddEven(self: *Context, parity: Parity) Error!void {
        // ODD/EVEN have no distance_type → no compensation, matching FreeType.
        const rounded = self.graphics.round_mode.apply(try self.pop(), 0);
        const integer = @divTrunc(rounded, 64);
        try self.push(boolInt(switch (parity) {
            .odd => integer & 1 != 0,
            .even => integer & 1 == 0,
        }));
    }

    fn moveDirectAbsolutePoint(self: *Context, round: bool) Error!void {
        const point = try self.popU32();
        const projection = self.projectionVector(false);
        const freedom = self.graphics.freedom;
        const zone_ptr = try self.zone(self.graphics.zp0);

        var target = try zone_ptr.coordinateVector(projection, point, false);
        // MDAP has no distance_type → compensation = 0 (matches FreeType).
        if (round) target = self.graphics.round_mode.apply(target, 0);
        try zone_ptr.moveToVector(projection, freedom, point, target);

        self.graphics.rp0 = point;
        self.graphics.rp1 = point;
    }

    fn moveIndirectAbsolutePoint(self: *Context, round: bool) Error!void {
        const raw_index = try self.pop();
        const cvt_value = self.cvtRead(raw_index);
        const point = try self.popU32();
        const projection = self.projectionVector(false);
        const freedom = self.graphics.freedom;
        const zone_ptr = try self.zone(self.graphics.zp0);

        var target = cvt_value;
        if (round) {
            if (self.graphics.zp0 != .twilight) {
                const original = try zone_ptr.coordinateVector(projection, point, true);
                if (absDiffI32(target, original) > self.graphics.control_value_cut_in) {
                    target = original;
                }
            }
            // MIAP has no distance_type → compensation = 0.
            target = self.graphics.round_mode.apply(target, 0);
        }
        if (self.graphics.zp0 == .twilight) {
            try zone_ptr.setOriginalCoordinateVector(projection, point, cvt_value);
        }
        try zone_ptr.moveToVector(projection, freedom, point, target);

        self.graphics.rp0 = point;
        self.graphics.rp1 = point;
    }

    fn moveDirectRelativePoint(self: *Context, flags: RelativeFlags) Error!void {
        const point = try self.popU32();
        const projection = self.projectionVector(false);
        const dual_projection = self.projectionVector(true);
        const freedom = self.graphics.freedom;
        const ref_zone = try self.zoneConst(self.graphics.zp0);
        const point_zone = try self.zone(self.graphics.zp1);

        const original_distance = subWrap(
            try point_zone.coordinateVector(dual_projection, point, true),
            try ref_zone.coordinateVector(dual_projection, self.graphics.rp0, true),
        );
        var distance = self.applySingleWidth(original_distance);
        if (flags.round) distance = self.graphics.round_mode.apply(distance, self.compensations[flags.distance_type]);
        distance = self.applyMinimumDistance(distance, original_distance, flags.minimum_distance);

        const target = addWrap(try ref_zone.coordinateVector(projection, self.graphics.rp0, false), distance);
        try point_zone.moveToVector(projection, freedom, point, target);
        self.updateRelativeReferencePoints(point, flags.set_rp0);
    }

    fn moveIndirectRelativePoint(self: *Context, flags: RelativeFlags) Error!void {
        var cvt_distance = self.cvtRead(try self.pop());
        const point = try self.popU32();
        const projection = self.projectionVector(false);
        const dual_projection = self.projectionVector(true);
        const freedom = self.graphics.freedom;
        const ref_zone = try self.zoneConst(self.graphics.zp0);
        const point_zone = try self.zone(self.graphics.zp1);
        var original_distance = subWrap(
            try point_zone.coordinateVector(dual_projection, point, true),
            try ref_zone.coordinateVector(dual_projection, self.graphics.rp0, true),
        );
        if (self.graphics.auto_flip and signsDiffer(cvt_distance, original_distance)) {
            cvt_distance = negWrap(cvt_distance);
        }
        if (self.graphics.zp1 == .twilight) {
            original_distance = cvt_distance;
            const original_target = addWrap(
                try ref_zone.coordinateVector(dual_projection, self.graphics.rp0, true),
                original_distance,
            );
            try point_zone.setOriginalCoordinateVector(dual_projection, point, original_target);
        }

        var distance = cvt_distance;
        if (flags.round and absDiffI32(cvt_distance, original_distance) > self.graphics.control_value_cut_in) {
            distance = original_distance;
        }
        distance = self.applySingleWidth(distance);
        if (flags.round) distance = self.graphics.round_mode.apply(distance, self.compensations[flags.distance_type]);
        distance = self.applyMinimumDistance(distance, original_distance, flags.minimum_distance);

        const target = addWrap(try ref_zone.coordinateVector(projection, self.graphics.rp0, false), distance);
        try point_zone.moveToVector(projection, freedom, point, target);
        self.updateRelativeReferencePoints(point, flags.set_rp0);
    }

    fn moveStackIndirectRelativePoint(self: *Context, set_rp0: bool) Error!void {
        const distance = try self.pop();
        const point = try self.popU32();
        const projection = self.projectionVector(false);
        const dual_projection = self.projectionVector(true);
        const freedom = self.graphics.freedom;
        const ref_zone = try self.zoneConst(self.graphics.zp0);
        const point_zone = try self.zone(self.graphics.zp1);
        const target = addWrap(try ref_zone.coordinateVector(projection, self.graphics.rp0, false), distance);

        if (self.graphics.zp1 == .twilight) {
            const original_target = addWrap(
                try ref_zone.coordinateVector(dual_projection, self.graphics.rp0, true),
                distance,
            );
            try point_zone.setOriginalCoordinateVector(dual_projection, point, original_target);
        }
        try point_zone.moveToVector(projection, freedom, point, target);
        self.graphics.rp1 = self.graphics.rp0;
        self.graphics.rp2 = point;
        if (set_rp0) self.graphics.rp0 = point;
    }

    fn alignPoints(self: *Context) Error!void {
        const p1 = try self.popU32();
        const p2 = try self.popU32();
        const projection = self.projectionVector(false);
        const freedom = self.graphics.freedom;
        const zone1 = try self.zone(self.graphics.zp1);
        const zone0 = try self.zone(self.graphics.zp0);
        const c1 = try zone1.coordinateVector(projection, p1, false);
        const c2 = try zone0.coordinateVector(projection, p2, false);
        const target: i32 = @truncate(@divTrunc(@as(i64, c1) + @as(i64, c2), 2));

        try zone1.moveToVector(projection, freedom, p1, target);
        try zone0.moveToVector(projection, freedom, p2, target);
    }

    fn alignReferencePoints(self: *Context) Error!void {
        const projection = self.projectionVector(false);
        const freedom = self.graphics.freedom;
        const ref_zone = try self.zoneConst(self.graphics.zp0);
        const point_zone = try self.zone(self.graphics.zp1);
        const target = try ref_zone.coordinateVector(projection, self.graphics.rp0, false);

        const count = self.graphics.loop_count;
        if (count == 0) return Error.StackUnderflow;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try point_zone.moveToVector(projection, freedom, try self.popU32(), target);
        }
        self.graphics.loop_count = 1;
    }

    fn interpolatePointsByReference(self: *Context) Error!void {
        const projection = self.projectionVector(false);
        const dual_projection = self.projectionVector(true);
        const freedom = self.graphics.freedom;
        const zone0 = try self.zoneConst(self.graphics.zp0);
        const zone1 = try self.zoneConst(self.graphics.zp1);
        const zone2 = try self.zone(self.graphics.zp2);

        const org1 = try zone0.coordinateVector(dual_projection, self.graphics.rp1, true);
        const org2 = try zone1.coordinateVector(dual_projection, self.graphics.rp2, true);
        const cur1 = try zone0.coordinateVector(projection, self.graphics.rp1, false);
        const cur2 = try zone1.coordinateVector(projection, self.graphics.rp2, false);

        const count = self.graphics.loop_count;
        if (count == 0) return Error.StackUnderflow;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const point = try self.popU32();
            const org = try zone2.coordinateVector(dual_projection, point, true);
            const target = interpolateReferenceCoord(org, org1, org2, cur1, cur2);
            try zone2.moveToVector(projection, freedom, point, target);
        }
        self.graphics.loop_count = 1;
    }

    fn getCoordinate(self: *Context, original: bool) Error!void {
        const point = try self.popU32();
        const projection = self.projectionVector(original);
        const zone_ptr = try self.zoneConst(self.graphics.zp2);
        try self.push(try zone_ptr.coordinateVector(projection, point, original));
    }

    fn setCoordinateFromStack(self: *Context) Error!void {
        const coordinate = try self.pop();
        const point = try self.popU32();
        const projection = self.projectionVector(false);
        const freedom = self.graphics.freedom;
        const zone_ptr = try self.zone(self.graphics.zp2);
        if (self.graphics.zp2 == .twilight) {
            try zone_ptr.setOriginalCoordinateVector(projection, point, coordinate);
        }
        try zone_ptr.moveToVector(projection, freedom, point, coordinate);
    }

    fn measureDistance(self: *Context, original: bool) Error!void {
        const p2 = try self.popU32();
        const p1 = try self.popU32();
        const projection = self.projectionVector(original);
        const zone1 = try self.zoneConst(self.graphics.zp0);
        const zone2 = try self.zoneConst(self.graphics.zp1);
        const c1 = try zone1.coordinateVector(projection, p1, original);
        const c2 = try zone2.coordinateVector(projection, p2, original);
        try self.push(subWrap(c1, c2));
    }

    fn shiftPointsByReference(self: *Context, op: u8) Error!void {
        const projection = self.projectionVector(false);
        const dual_projection = self.projectionVector(true);
        const freedom = self.graphics.freedom;
        const ref_pointer = if (op == 0x32) self.graphics.zp1 else self.graphics.zp0;
        const ref_point = if (op == 0x32) self.graphics.rp2 else self.graphics.rp1;
        const ref_zone = try self.zoneConst(ref_pointer);
        const distance = subWrap(
            try ref_zone.coordinateVector(projection, ref_point, false),
            try ref_zone.coordinateVector(dual_projection, ref_point, true),
        );
        const point_zone = try self.zone(self.graphics.zp2);
        try self.shiftLoopPointsProjected(point_zone, projection, freedom, distance);
    }

    fn shiftContourByReference(self: *Context, op: u8) Error!void {
        const contour = try self.popU32();
        const projection = self.projectionVector(false);
        const dual_projection = self.projectionVector(true);
        const freedom = self.graphics.freedom;
        const ref_pointer = if (op == 0x34) self.graphics.zp1 else self.graphics.zp0;
        const ref_point = if (op == 0x34) self.graphics.rp2 else self.graphics.rp1;
        const ref_zone = try self.zoneConst(ref_pointer);
        const distance = subWrap(
            try ref_zone.coordinateVector(projection, ref_point, false),
            try ref_zone.coordinateVector(dual_projection, ref_point, true),
        );
        const skip_point: ?u32 = if (ref_pointer == self.graphics.zp2) ref_point else null;
        const point_zone = try self.zone(self.graphics.zp2);
        // UNDOCUMENTED (per FreeType / Greg Hitchcock): when zp2 is the
        // twilight zone, SHC operates on a single virtual contour 0 covering
        // every twilight point. snail's twilight zones have an empty
        // contours array, so we can't go through the normal path.
        if (self.graphics.zp2 == .twilight) {
            if (contour != 0) return; // only virtual contour 0 exists in twilight.
            var i: u32 = 0;
            while (i < point_zone.points.len) : (i += 1) {
                if (skip_point) |sp| if (sp == i) continue;
                try point_zone.shiftProjectedVector(projection, freedom, i, distance);
            }
            return;
        }
        try point_zone.shiftContourProjectedVector(projection, freedom, contour, distance, skip_point);
    }

    fn shiftZoneByReference(self: *Context, op: u8) Error!void {
        const zone_value = try self.pop();
        const projection = self.projectionVector(false);
        const dual_projection = self.projectionVector(true);
        const freedom = self.graphics.freedom;
        const ref_pointer = if (op == 0x36) self.graphics.zp1 else self.graphics.zp0;
        const ref_point = if (op == 0x36) self.graphics.rp2 else self.graphics.rp1;
        const ref_zone = try self.zoneConst(ref_pointer);
        const target_pointer = try zonePointer(zone_value);
        const target_zone = try self.zone(target_pointer);
        const distance = subWrap(
            try ref_zone.coordinateVector(projection, ref_point, false),
            try ref_zone.coordinateVector(dual_projection, ref_point, true),
        );

        // UNDOCUMENTED (per FreeType): SHZ on the glyph zone does NOT shift
        // the four phantom points appended after the glyph outline. Shifting
        // them would corrupt the per-glyph LSB / advance width / TSB /
        // advance height that downstream rendering reads back.
        const limit: u32 = blk: {
            const all: u32 = @intCast(target_zone.points.len);
            if (target_pointer == .glyph and all >= tt_points.phantom_count) {
                break :blk all - tt_points.phantom_count;
            }
            break :blk all;
        };

        var point: u32 = 0;
        while (point < limit) : (point += 1) {
            if (ref_pointer == target_pointer and point == ref_point) continue;
            try target_zone.shiftProjectedVector(projection, freedom, point, distance);
        }
    }

    fn shiftPointsByPixels(self: *Context) Error!void {
        const distance = try self.pop();
        const freedom = self.graphics.freedom;
        const zone_ptr = try self.zone(self.graphics.zp2);
        try self.shiftLoopPoints(zone_ptr, freedom, distance);
    }

    fn shiftLoopPoints(self: *Context, zone_ptr: *PointZone, freedom: tt_graphics.Vector, distance: i32) Error!void {
        const count = self.graphics.loop_count;
        if (count == 0) return Error.StackUnderflow;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try zone_ptr.shiftVector(freedom, try self.popU32(), distance);
        }
        self.graphics.loop_count = 1;
    }

    fn shiftLoopPointsProjected(
        self: *Context,
        zone_ptr: *PointZone,
        projection: tt_graphics.Vector,
        freedom: tt_graphics.Vector,
        distance: i32,
    ) Error!void {
        const count = self.graphics.loop_count;
        if (count == 0) return Error.StackUnderflow;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            try zone_ptr.shiftProjectedVector(projection, freedom, try self.popU32(), distance);
        }
        self.graphics.loop_count = 1;
    }

    fn untouchPoint(self: *Context) Error!void {
        const point = try self.popU32();
        const zone_ptr = try self.zone(self.graphics.zp0);
        try zone_ptr.untouch(self.graphics.freedom, point);
    }

    fn interpolateUntouchedPoints(self: *Context, op: u8) Error!void {
        const zone_ptr = try self.zone(self.graphics.zp2);
        try zone_ptr.interpolateUntouched(if (op == 0x30) .y else .x);
    }

    fn applySingleWidth(self: *const Context, distance: i32) i32 {
        const cut_in = self.graphics.single_width_cut_in;
        if (cut_in <= 0) return distance;

        const width = absI32(self.graphics.single_width_value);
        if (absDiffI32(absI32(distance), width) >= cut_in) return distance;
        return withSign(width, distance);
    }

    fn applyMinimumDistance(self: *const Context, distance: i32, sign_hint: i32, enabled: bool) i32 {
        if (!enabled) return distance;
        const minimum = absI32(self.graphics.minimum_distance);
        if (absI32(distance) >= minimum) return distance;
        return withSign(minimum, if (distance == 0) sign_hint else distance);
    }

    fn updateRelativeReferencePoints(self: *Context, point: u32, set_rp0: bool) void {
        self.graphics.rp1 = self.graphics.rp0;
        self.graphics.rp2 = point;
        if (set_rp0) self.graphics.rp0 = point;
    }

    fn callFunction(self: *Context, function_id: i32, steps: *u32) Error!void {
        const defs = try self.functionDefs();
        const code = defs.get(function_id) orelse return Error.UnknownFunction;
        if (self.call_depth >= self.limits.max_call_depth) return Error.CallDepthExceeded;

        self.call_depth += 1;
        defer self.call_depth -= 1;
        try self.executeCode(code, steps);
    }

    fn functionDefs(self: *Context) Error!*FunctionDefs {
        return self.functions orelse Error.MissingFunctions;
    }

    fn setInstructionControl(self: *Context) Error!void {
        const value = try self.pop();
        const selector = try self.pop();
        // Per FreeType's Ins_INSTCTRL: selectors are 1..3 (not flags), and
        // the value must be either 0 (clear) or exactly `1 << (selector-1)`
        // (set the matching bit). Selector 3 is ClearType-mode and snail
        // doesn't model the backward-compatibility state, so we accept it
        // as a no-op rather than rejecting (matches FreeType's behavior on
        // builds without subpixel hinting).
        if (selector < 1 or selector > 3) return;
        const flag: i32 = @as(i32, 1) << @intCast(selector - 1);
        if (value != 0 and value != flag) return;
        if (selector == 3) return; // ClearType mode — no-op without subpixel hinting.
        self.graphics.instruct_control &= ~flag;
        self.graphics.instruct_control |= value;
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

    fn lineVector(self: *Context, perpendicular: bool, original: bool) Error!tt_graphics.Vector {
        return self.lineVectorFromPoints(try self.popLinePoints(), perpendicular, original);
    }

    const LinePoints = struct {
        p1: u32,
        p2: u32,
    };

    fn popLinePoints(self: *Context) Error!LinePoints {
        const point_1 = try self.popU32();
        const point_2 = try self.popU32();
        return .{ .p1 = point_1, .p2 = point_2 };
    }

    fn lineVectorFromPoints(self: *const Context, points: LinePoints, perpendicular: bool, original: bool) Error!tt_graphics.Vector {
        const p1 = try self.zonePoint(self.graphics.zp2, points.p1);
        const p2 = try self.zonePoint(self.graphics.zp1, points.p2);
        const p1_x = if (original) p1.ox else p1.x;
        const p1_y = if (original) p1.oy else p1.y;
        const p2_x = if (original) p2.ox else p2.x;
        const p2_y = if (original) p2.oy else p2.y;
        const dx = subWrap(p2_x, p1_x);
        const dy = subWrap(p2_y, p1_y);
        return if (perpendicular)
            tt_graphics.normalizeF2Dot14(-dy, dx)
        else
            tt_graphics.normalizeF2Dot14(dx, dy);
    }

    fn setProjectionVector(self: *Context, vector: tt_graphics.Vector) void {
        self.graphics.projection = vector;
        self.graphics.dual_projection = vector;
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

    fn zonePoint(self: *const Context, pointer: tt_graphics.ZonePointer, point_index: u32) Error!Point {
        const z = try self.zoneConst(pointer);
        const index: usize = point_index;
        if (index >= z.points.len) return Error.InvalidPoint;
        return z.points[index];
    }

    fn projectionVector(self: *const Context, original: bool) tt_graphics.Vector {
        return if (original) self.graphics.dual_projection else self.graphics.projection;
    }

    /// FUnit → 26.6 pixels in the *current projection*. Used for the
    /// single-width value (SSW, 0x1F) and other immediate-pixel writes that
    /// should match the axis the program is currently working on.
    fn scaleFUnits(self: *const Context, value: i32) i32 {
        return if (self.usesXScale())
            self.environment.scaleFUnitsX(value)
        else
            self.environment.scaleFUnitsY(value);
    }

    /// FUnit → 26.6 pixels at the *base ppem* (max of x and y). Used by
    /// WCVTF so the value stored in the canonical CVT cell can be rescaled
    /// per-projection on read, matching FreeType's Write_CVT_Stretched.
    fn scaleFUnitsBase(self: *const Context, value: i32) i32 {
        const base = self.environment.basePpem26Dot6();
        return scaleFUnitsAtPpem(value, base, self.environment.units_per_em);
    }

    /// MPPEM (0x4B). Per spec/FreeType: returns the ppem along the current
    /// projection vector. For square pixels this is just `ppem_y`; for
    /// stretched grids it interpolates via the projection ratio
    /// (matches `Current_Ppem_Stretched`).
    fn projectionPpem26Dot6(self: *const Context) u32 {
        if (!self.environment.isStretched()) return self.environment.ppem_y_26_6;
        const base = self.environment.basePpem26Dot6();
        const ratio = self.environment.projectionRatio(self.graphics.projection);
        const scaled = tt_graphics.mulFix16Dot16(@intCast(base), ratio);
        if (scaled < 0) return 0;
        return @intCast(scaled);
    }

    fn usesXScale(self: *const Context) bool {
        return absI32(self.graphics.projection.x) >= absI32(self.graphics.projection.y);
    }
};

fn scaleFUnitsAtPpem(value: i32, ppem_26_6: u32, units_per_em: u16) i32 {
    if (units_per_em == 0) return 0;
    const numerator = @as(i64, value) * @as(i64, ppem_26_6);
    const denominator = @as(i64, units_per_em);
    const half = @divTrunc(denominator, 2);
    const rounded = if (numerator >= 0)
        @divTrunc(numerator + half, denominator)
    else
        @divTrunc(numerator - half, denominator);
    return @truncate(rounded);
}

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

// ── Tail-call dispatch ──
//
// Each opcode handler ends in `@call(.always_tail, tail_dispatch[next_op], …)`.
// Each specialized handler is a distinct function, so the CPU's BTB sees a
// different indirect-branch target per opcode; the more opcodes are
// specialized, the more dispatch parallelism the predictor sees, and each
// handler skips the per-op category switch entirely.
//
// Boilerplate is kept minimal via comptime factory functions: `handleSimple`,
// `handleFlow`, and `handleFunction` accept a comptime opcode and produce a
// handler that calls the matching `inline fn` category implementation. The
// inlined category fn collapses to that op's case body when the comptime op
// is constant-propagated through its switch.

const TailHandler = *const fn (
    self: *Context,
    code: []const u8,
    pc: usize,
    steps: *u32,
) Error!void;

inline fn dispatchNext(
    self: *Context,
    code: []const u8,
    pc: usize,
    steps: *u32,
) Error!void {
    if (pc >= code.len) return;
    try self.countStep(steps);
    const op = code[pc];
    if (comptime tail_calls_supported) {
        return @call(.always_tail, tail_dispatch[op], .{ self, code, pc + 1, steps });
    } else {
        return tail_dispatch[op](self, code, pc + 1, steps);
    }
}

/// Fallback for reserved/invalid opcodes. Routes through `executeOp` so
/// any future-defined opcode still picks up the legacy switch's coverage,
/// and currently-undefined opcodes surface `Error.InvalidOpcode`.
fn handleDefault(
    self: *Context,
    code: []const u8,
    pc: usize,
    steps: *u32,
) Error!void {
    var local_pc = pc;
    const op_pc = pc - 1;
    const op = code[op_pc];
    try self.executeOp(code, &local_pc, op_pc, op, steps);
    return dispatchNext(self, code, local_pc, steps);
}

/// Handler factory for ops that don't touch pc beyond the op byte itself.
/// `exec_fn` is a category function with signature `fn(*Context, u8) Error!void`.
/// Since `op` is comptime-known and category functions are `inline fn`, the
/// category switch collapses to that op's case body.
fn handleSimple(comptime exec_fn: anytype, comptime op: u8) TailHandler {
    return struct {
        fn h(self: *Context, code: []const u8, pc: usize, steps: *u32) Error!void {
            try exec_fn(self, op);
            return dispatchNext(self, code, pc, steps);
        }
    }.h;
}

/// Handler factory for flow-control ops (ELSE/EIF/IF/JMPR/JROT/JROF). These
/// can mutate pc (jumps, skips), so the handler threads it through a local.
/// `op_pc` is `pc - 1` because pc enters positioned after the op byte.
fn handleFlow(comptime op: u8) TailHandler {
    return struct {
        fn h(self: *Context, code: []const u8, pc: usize, steps: *u32) Error!void {
            var local_pc = pc;
            try self.executeFlowOp(code, &local_pc, pc - 1, op);
            return dispatchNext(self, code, local_pc, steps);
        }
    }.h;
}

/// Handler factory for CALL/LOOPCALL/FDEF. These can recurse (callFunction)
/// and may mutate pc (FDEF skips to ENDF+1).
fn handleFunction(comptime op: u8) TailHandler {
    return struct {
        fn h(self: *Context, code: []const u8, pc: usize, steps: *u32) Error!void {
            var local_pc = pc;
            try self.executeFunctionOp(code, &local_pc, op, steps);
            return dispatchNext(self, code, local_pc, steps);
        }
    }.h;
}

// Push handlers: pc enters positioned past the op byte. Read N immediate
// bytes (or words), push them, advance pc by the consumed operand bytes.

inline fn pushBytesAt(self: *Context, code: []const u8, pc: usize, count: usize) Error!void {
    if (pc + count > code.len) return Error.UnexpectedEof;
    if (self.sp + count > self.stack.len) return Error.StackOverflow;
    for (code[pc..][0..count]) |value| {
        self.stack[self.sp] = value;
        self.sp += 1;
    }
}

inline fn pushWordsAt(self: *Context, code: []const u8, pc: usize, count: usize) Error!void {
    const byte_count = count * 2;
    if (pc + byte_count > code.len) return Error.UnexpectedEof;
    if (self.sp + count > self.stack.len) return Error.StackOverflow;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        self.stack[self.sp] = readI16AssumeInBounds(code, pc + i * 2);
        self.sp += 1;
    }
}

fn handlePushB(comptime n: usize) TailHandler {
    return struct {
        fn h(self: *Context, code: []const u8, pc: usize, steps: *u32) Error!void {
            try pushBytesAt(self, code, pc, n);
            return dispatchNext(self, code, pc + n, steps);
        }
    }.h;
}

fn handlePushW(comptime n: usize) TailHandler {
    return struct {
        fn h(self: *Context, code: []const u8, pc: usize, steps: *u32) Error!void {
            try pushWordsAt(self, code, pc, n);
            return dispatchNext(self, code, pc + n * 2, steps);
        }
    }.h;
}

fn handleNPushB(self: *Context, code: []const u8, pc: usize, steps: *u32) Error!void {
    if (pc >= code.len) return Error.UnexpectedEof;
    const count: usize = code[pc];
    try pushBytesAt(self, code, pc + 1, count);
    return dispatchNext(self, code, pc + 1 + count, steps);
}

fn handleNPushW(self: *Context, code: []const u8, pc: usize, steps: *u32) Error!void {
    if (pc >= code.len) return Error.UnexpectedEof;
    const count: usize = code[pc];
    try pushWordsAt(self, code, pc + 1, count);
    return dispatchNext(self, code, pc + 1 + count * 2, steps);
}

const tail_dispatch: [256]TailHandler = blk: {
    var t: [256]TailHandler = @splat(handleDefault);

    // The opcode ranges below mirror the legacy executeOp switch; any future
    // additions there should be reflected here too.

    // Graphics: vector setters (SVTCA/SFVTCA/SPVTCA/SDPVTL), ref-point and
    // zone setters, loop count, round mode bases, cut-in values.
    for ([_]u8{
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1A, 0x1D, 0x1E, 0x1F,
        0x86, 0x87,
    }) |op| t[op] = handleSimple(Context.executeGraphicsOp, op);

    // Stack: DUP, POP, CLEAR, SWAP, DEPTH, CINDEX, MINDEX.
    for ([_]u8{ 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26 }) |op|
        t[op] = handleSimple(Context.executeStackOp, op);

    // Memory: WS, RS, WCVTP, RCVT, WCVTF.
    for ([_]u8{ 0x42, 0x43, 0x44, 0x45, 0x70 }) |op|
        t[op] = handleSimple(Context.executeMemoryOp, op);

    // State: instruction-control, scan-control, MD, MPPEM/MPS, GETINFO,
    // GETVARIATION, AA, SROUND/S45ROUND, etc.
    for ([_]u8{
        0x4B, 0x4C, 0x4D, 0x4E,
        0x56, 0x57, 0x5E, 0x5F,
        0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F,
        0x76, 0x77,
        0x7A, 0x7C, 0x7D, 0x85, 0x88, 0x8A, 0x8D, 0x8E,
    }) |op| t[op] = handleSimple(Context.executeStateOp, op);

    // RTDG (0x3D) — round to double grid. Wired through the slow path since
    // it sits in the middle of the otherwise-point-op-only 0x2E..0x3F range.
    t[0x3D] = handleDefault;

    // Logic: LT/LTEQ/GT/GTEQ/EQ/NEQ/AND/OR/NOT.
    for ([_]u8{ 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x5A, 0x5B, 0x5C }) |op|
        t[op] = handleSimple(Context.executeLogicOp, op);

    // Math: ADD/SUB/DIV/MUL/ABS/NEG/FLOOR/CEILING/MAX/MIN.
    for ([_]u8{ 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x8B, 0x8C }) |op|
        t[op] = handleSimple(Context.executeMathOp, op);

    // Push immediates (PUSHB[1..8], PUSHW[1..8], NPUSHB, NPUSHW).
    for (0..8) |n| t[0xB0 + n] = handlePushB(n + 1);
    for (0..8) |n| t[0xB8 + n] = handlePushW(n + 1);
    t[0x40] = handleNPushB;
    t[0x41] = handleNPushW;

    // Point ops: alignment/shift/measure/move primitives plus the bulk
    // MDRP (0xC0..0xDF) / MIRP (0xE0..0xFF) blocks. Specializing MDRP/MIRP
    // is a real win — `relativeFlags(op, base)` becomes a comptime constant.
    for ([_]u8{
        0x27, 0x29,
        0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
        0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3E, 0x3F,
        0x46, 0x47, 0x48, 0x49, 0x4A,
    }) |op| t[op] = handleSimple(Context.executePointOp, op);
    for (0xC0..0x100) |op| t[op] = handleSimple(Context.executePointOp, @intCast(op));

    // Delta exceptions: DELTAP[1..3], DELTAC[1..3].
    for ([_]u8{ 0x5D, 0x71, 0x72, 0x73, 0x74, 0x75 }) |op|
        t[op] = handleSimple(Context.executeDeltaOp, op);

    // Flow control: ELSE/JMPR/IF/EIF/JROT/JROF.
    for ([_]u8{ 0x1B, 0x1C, 0x58, 0x59, 0x78, 0x79 }) |op|
        t[op] = handleFlow(op);

    // Function ops: LOOPCALL/CALL/FDEF.
    for ([_]u8{ 0x2A, 0x2B, 0x2C }) |op|
        t[op] = handleFunction(op);

    // Anything left (notably 0x2D ENDF outside FDEF, plus reserved slots)
    // falls through to handleDefault → executeOp, which produces
    // Error.InvalidOpcode for unknown bytes.

    break :blk t;
};

const RelativeFlags = struct {
    set_rp0: bool,
    minimum_distance: bool,
    round: bool,
    distance_type: u2,
};

fn relativeFlags(op: u8, base: u8) RelativeFlags {
    const flags = op - base;
    return .{
        .set_rp0 = flags & 0x10 != 0,
        .minimum_distance = flags & 0x08 != 0,
        .round = flags & 0x04 != 0,
        .distance_type = @intCast(flags & 0x03),
    };
}

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

fn withSign(magnitude: i32, sign_hint: i32) i32 {
    return if (sign_hint < 0) negWrap(magnitude) else magnitude;
}

fn signsDiffer(lhs: i32, rhs: i32) bool {
    return (lhs < 0 and rhs > 0) or (lhs > 0 and rhs < 0);
}

fn deltaQuantum(delta_shift: i32) i32 {
    if (delta_shift <= 0) return 64;
    if (delta_shift >= 6) return 1;
    return @as(i32, 64) >> @intCast(delta_shift);
}

fn addWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) + @as(i64, rhs));
}

fn subWrap(lhs: i32, rhs: i32) i32 {
    return @truncate(@as(i64, lhs) - @as(i64, rhs));
}

fn interpolateReferenceCoord(org: i32, org1: i32, org2: i32, cur1: i32, cur2: i32) i32 {
    if (org1 == org2) return addWrap(org, subWrap(cur1, org1));

    if (org1 < org2) {
        if (org <= org1) return addWrap(org, subWrap(cur1, org1));
        if (org >= org2) return addWrap(org, subWrap(cur2, org2));
        return lerpReferenceCoord(org, org1, org2, cur1, cur2);
    }

    if (org <= org2) return addWrap(org, subWrap(cur2, org2));
    if (org >= org1) return addWrap(org, subWrap(cur1, org1));
    return lerpReferenceCoord(org, org2, org1, cur2, cur1);
}

fn lerpReferenceCoord(org: i32, org1: i32, org2: i32, cur1: i32, cur2: i32) i32 {
    const numerator = (@as(i64, org) - @as(i64, org1)) * (@as(i64, cur2) - @as(i64, cur1));
    return @truncate(@as(i64, cur1) + @divTrunc(numerator, @as(i64, org2) - @as(i64, org1)));
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

/// Per-opcode inline-operand byte count. Positive values are a constant
/// number of bytes to skip; negative sentinels mean "consult slow path".
/// Built at comptime so the skip loop is a single table lookup per op.
const OP_OPERAND_NPUSHB: i16 = -1; // 0x40: next u8 = count, then `count` bytes
const OP_OPERAND_NPUSHW: i16 = -2; // 0x41: next u8 = count, then `count*2` bytes
const OP_OPERAND_FDEF: i16 = -3; // 0x2C: scan to ENDF (0x2D)

const skip_operand_table: [256]i16 = blk: {
    var t: [256]i16 = @splat(0);
    for (0..8) |i| t[0xB0 + i] = @intCast(i + 1);
    for (0..8) |i| t[0xB8 + i] = @intCast((i + 1) * 2);
    t[0x40] = OP_OPERAND_NPUSHB;
    t[0x41] = OP_OPERAND_NPUSHW;
    t[0x2C] = OP_OPERAND_FDEF;
    break :blk t;
};

fn skipStructured(code: []const u8, start: usize, stop_at_else: bool) Error!usize {
    var pc = start;
    var depth: u32 = 0;
    while (pc < code.len) {
        const op = code[pc];
        pc += 1;

        switch (op) {
            0x58 => depth += 1,
            0x59 => {
                if (depth == 0) return pc;
                depth -= 1;
            },
            0x1B => {
                if (stop_at_else and depth == 0) return pc;
            },
            else => {
                const entry = skip_operand_table[op];
                if (entry >= 0) {
                    const bytes: usize = @intCast(entry);
                    if (pc + bytes > code.len) return Error.UnexpectedEof;
                    pc += bytes;
                } else {
                    pc = try skipSpecialOperand(code, pc, entry);
                }
            },
        }
    }
    return Error.UnexpectedEof;
}

fn findEndf(code: []const u8, start: usize) Error!usize {
    var pc = start;
    while (pc < code.len) {
        const op = code[pc];
        if (op == 0x2D) return pc;
        pc += 1;

        const entry = skip_operand_table[op];
        if (entry >= 0) {
            const bytes: usize = @intCast(entry);
            if (pc + bytes > code.len) return Error.UnexpectedEof;
            pc += bytes;
        } else {
            pc = try skipSpecialOperand(code, pc, entry);
        }
    }
    return Error.InvalidFunctionDefinition;
}

fn skipSpecialOperand(code: []const u8, start: usize, entry: i16) Error!usize {
    var pc = start;
    switch (entry) {
        OP_OPERAND_NPUSHB => {
            const count: usize = try readU8(code, &pc);
            if (pc + count > code.len) return Error.UnexpectedEof;
            return pc + count;
        },
        OP_OPERAND_NPUSHW => {
            const count: usize = try readU8(code, &pc);
            const bytes = count * 2;
            if (pc + bytes > code.len) return Error.UnexpectedEof;
            return pc + bytes;
        },
        OP_OPERAND_FDEF => {
            return (try findEndf(code, pc)) + 1;
        },
        else => unreachable,
    }
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

test "function definitions use direct lookup when supplied" {
    var entries: [2]Function = undefined;
    var lookup = [_]?[]const u8{null} ** 256;
    var defs = FunctionDefs{ .entries = &entries, .lookup = &lookup };
    const code = [_]u8{0x2D};

    try defs.put(42, &code);
    try std.testing.expectEqualSlices(u8, &code, defs.get(42).?);

    defs.reset();
    try std.testing.expect(defs.get(42) == null);
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

test "tt executor tolerates out-of-bounds CVT reads and writes" {
    // Real-world fonts (e.g. NotoSansSymbols prep) compute CVT indices that
    // wander out of range (idx=-8 in that font's case). FreeType/Skia/CoreText
    // tolerate this: OOB reads return 0, OOB writes are silently dropped.
    // Snail follows the same contract so the VM doesn't abort the entire run
    // and degrade to unhinted rendering on the affected glyphs.
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [2]i32 = .{ 10, 20 };
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    // PUSHW -8, then RCVT — must yield 0, not error.
    try ctx.execute(&.{ 0xB8, 0xFF, 0xF8, 0x45 });
    try expectStack(&ctx, &.{0});
    ctx.sp = 0;

    // PUSHB index=99, value=77, WCVTP — must succeed (no-op), no error.
    try ctx.execute(&.{ 0xB1, 99, 77, 0x44 });
    try std.testing.expectEqual(@as(usize, 0), ctx.sp);
    try std.testing.expectEqual(@as(i32, 10), cvt[0]);
    try std.testing.expectEqual(@as(i32, 20), cvt[1]);

    // PUSHW -1, then RCVT — also yield 0.
    try ctx.execute(&.{ 0xB8, 0xFF, 0xFF, 0x45 });
    try expectStack(&ctx, &.{0});
    ctx.sp = 0;

    // In-bounds RCVT still works.
    try ctx.execute(&.{ 0xB0, 1, 0x45 });
    try expectStack(&ctx, &.{20});
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
    try std.testing.expectEqual(@as(u32, 2), ctx.steps);
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

test "tt executor derives vectors from point lines" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});
    var twilight_points: [1]Point = undefined;
    var glyph_points: [2]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 64, .y = 0, .ox = 64, .oy = 0, .on_curve = true },
    };
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB1, 1, 0, 0x06, 0x0C, // SPVTL[0], GPV
        0xB1, 1, 0, 0x07, 0x0C, // SPVTL[1], GPV
    });

    try expectStack(&ctx, &.{ 0x4000, 0, 0, 0x4000 });
}

test "tt executor derives line vectors from popped zp2 point toward popped zp1 point" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});
    var twilight_points: [2]Point = .{
        .{ .x = 100, .y = 0, .ox = 100, .oy = 0, .on_curve = true },
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
    };
    var glyph_points: [2]Point = .{
        .{ .x = 64, .y = 0, .ox = 64, .oy = 0, .on_curve = true },
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
    };
    var zones: PointZones = .{
        .twilight = .{ .points = &twilight_points },
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 0, 0x15, // SZP2 twilight; ZP1 remains glyph.
        0xB1, 0, 1, 0x06, 0x0C, // SPVTL[0], GPV
    });

    try expectStack(&ctx, &.{ 0x4000, 0 });
}

test "tt executor resets dual projection except for SDPVTL" {
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});
    var twilight_points: [1]Point = .{.{
        .x = 0,
        .y = 0,
        .ox = 0,
        .oy = 0,
        .on_curve = true,
    }};
    var glyph_points: [1]Point = .{.{
        .x = 0,
        .y = 64,
        .ox = 64,
        .oy = 0,
        .on_curve = true,
    }};
    var zones: PointZones = .{
        .twilight = .{ .points = &twilight_points },
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 0, 0x15, // SZP2 twilight; ZP1 remains glyph.
        0xB1, 0, 0, 0x86, // SDPVTL[0]: current projection is y, dual projection is x.
        0xB0, 1, 0x15, // GC below reads the glyph zone.
        0xB0, 0, 0x47, // GC[1] with dual projection.
        0xB0, 0, 0x46, // GC[0] with current projection.
        0x22, // CLEAR
        0xB9, 0x00, 0x00, 0x40, 0x00, 0x0A, // SPVFS[y] must reset dual projection.
        0xB0, 0, 0x47, // GC[1] now measures y, not the stale SDPVTL dual vector.
    });

    try expectStack(&ctx, &.{ 0 });
}

test "tt executor scales WCVTF and RCVT through the projection-relative ratio" {
    // WCVTF stores 26.6 pixels in the canonical CVT cell (base-ppem scaled),
    // and RCVT rescales by the current projection ratio. This matches
    // FreeType's Read_CVT_Stretched / Write_CVT_Stretched and is what
    // lets a single prep program use the same CVT entry from either axis.
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
        0xB1, 0, 50, 0x70, // WCVTF cvt[0] = 50 funits → x-pixels = 32, stored canonical
        0x00, // SVTCA[y]
        0xB1, 1, 50, 0x70, // WCVTF cvt[1] = 50 funits → y-pixels = 38, stored canonical
        // Read both back along their write axis: should round-trip.
        0x01, // SVTCA[x]
        0xB0, 0, 0x45, // RCVT cvt[0] → 32 (x-axis)
        0x00, // SVTCA[y]
        0xB0, 1, 0x45, // RCVT cvt[1] → 38 (y-axis)
        // And cross-read: cvt[1] in x-axis projection should rescale down to ~32.
        0x01,
        0xB0, 1, 0x45,
    });

    // Both cells canonical-stored at base ppem=12 → 38, regardless of write axis.
    try std.testing.expectEqual(@as(i32, 38), cvt[0]);
    try std.testing.expectEqual(@as(i32, 38), cvt[1]);
    // Stack: x-read of cvt[0] then y-read of cvt[1] then x-read of cvt[1].
    try expectStack(&ctx, &.{ 32, 38, 32 });
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
        0xB1, 0, 1, 0x49, // MD[0]: current distance from top point back to second point.
        0xB1, 2, 0, 0x3E, // MIAP[0]: move point 2 to cvt[0]
    });

    try expectStack(&ctx, &.{ 64, -64 });
    try std.testing.expectEqual(@as(i32, 64), glyph_points[0].x);
    try std.testing.expectEqual(@as(i32, 128), glyph_points[1].x);
    try std.testing.expectEqual(@as(i32, 90), glyph_points[2].x);
    try std.testing.expect(glyph_points[0].touched_x);
    try std.testing.expect(glyph_points[1].touched_x);
    try std.testing.expect(glyph_points[2].touched_x);
}

test "tt executor records original coordinates for created twilight points" {
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{90};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [3]Point = undefined;
    var glyph_points: [0]Point = .{};
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 0, 0x16, // SZPS: use the twilight zone.
        0xB1, 0, 0, 0x3F, // MIAP[1]: create p0 at cvt[0], rounded in current coords.
        0xB0, 0, 0x47, // GC[1]: original p0 coordinate remains unrounded.
        0xB0, 0, 0x46, // GC[0]: current p0 coordinate is rounded.
        0x22, // CLEAR
        0xB0, 0, 0x10, // SRP0 p0
        0xB1, 1, 32, 0x3A, // MSIRP[0]: create p1 1/2px from p0.
        0xB0, 1, 0x47, // GC[1]
        0xB0, 1, 0x46, // GC[0]
        0x22, // CLEAR
        0xB1, 2, 200, 0x48, // SCFS: create p2 at x=200.
        0xB0, 2, 0x47, // GC[1]
        0xB0, 2, 0x46, // GC[0]
    });

    try expectStack(&ctx, &.{ 200, 200 });
    try std.testing.expectEqual(@as(i32, 90), twilight_points[0].ox);
    try std.testing.expectEqual(@as(i32, 64), twilight_points[0].x);
    try std.testing.expectEqual(@as(i32, 122), twilight_points[1].ox);
    try std.testing.expectEqual(@as(i32, 96), twilight_points[1].x);
    try std.testing.expectEqual(@as(i32, 200), twilight_points[2].ox);
    try std.testing.expectEqual(@as(i32, 200), twilight_points[2].x);
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

test "tt executor shifts contours by reference movement" {
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [1]Point = undefined;
    var glyph_points: [4]Point = .{
        .{ .x = 10, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 20, .y = 0, .ox = 20, .oy = 0, .on_curve = true },
        .{ .x = 30, .y = 0, .ox = 30, .oy = 0, .on_curve = true },
        .{ .x = 40, .y = 0, .ox = 40, .oy = 0, .on_curve = true },
    };
    const contours = [_]@import("outline.zig").ContourRange{
        .{ .start = 0, .end = 2 },
        .{ .start = 2, .end = 4 },
    };
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points, .contours = &contours },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 0, 0x11, // SRP1 0
        0xB0, 1, 0x35, // SHC[1] contour 1 by rp1 delta
    });

    try std.testing.expectEqual(@as(i32, 40), glyph_points[2].x);
    try std.testing.expectEqual(@as(i32, 50), glyph_points[3].x);
}

test "tt executor interpolates untouched glyph points" {
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [1]Point = undefined;
    var glyph_points: [3]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .orus_x = 0, .on_curve = true, .touched_x = true },
        .{ .x = 50, .y = 0, .ox = 50, .oy = 0, .orus_x = 50, .on_curve = true },
        .{ .x = 200, .y = 0, .ox = 100, .oy = 0, .orus_x = 100, .on_curve = true, .touched_x = true },
    };
    const contours = [_]@import("outline.zig").ContourRange{.{ .start = 0, .end = 3 }};
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points, .contours = &contours },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{0x31}); // IUP[x]

    try std.testing.expectEqual(@as(i32, 100), glyph_points[1].x);
}

test "tt executor aligns points and reference points" {
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [1]Point = undefined;
    var glyph_points: [3]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 100, .y = 0, .ox = 100, .oy = 0, .on_curve = true },
        .{ .x = 160, .y = 0, .ox = 160, .oy = 0, .on_curve = true },
    };
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB1, 0, 1, 0x27, // ALIGNPTS point 0 and point 1 at their midpoint
        0xB0, 0, 0x10, // SRP0 0
        0xB0, 2, 0x3C, // ALIGNRP point 2 to rp0
    });

    try std.testing.expectEqual(@as(i32, 50), glyph_points[0].x);
    try std.testing.expectEqual(@as(i32, 50), glyph_points[1].x);
    try std.testing.expectEqual(@as(i32, 50), glyph_points[2].x);
    try std.testing.expectEqual(@as(u32, 1), ctx.graphics.loop_count);
}

test "tt executor handles direct and indirect relative moves" {
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [2]i32 = .{ 100, 20 };
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [1]Point = undefined;
    var glyph_points: [3]Point = .{
        .{ .x = 80, .y = 0, .ox = 40, .oy = 0, .on_curve = true },
        .{ .x = 140, .y = 0, .ox = 140, .oy = 0, .on_curve = true },
        .{ .x = 180, .y = 0, .ox = 180, .oy = 0, .on_curve = true },
    };
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 0, 0x10, // SRP0 0
        0xB0, 1, 0xD4, // MDRP[10100]: round original distance and set rp0
        0xB1, 2, 0, 0xE4, // MIRP[00100]: use cvt[0] with rounding/cut-in
    });

    try std.testing.expectEqual(@as(i32, 208), glyph_points[1].x);
    try std.testing.expectEqual(@as(i32, 336), glyph_points[2].x);
    try std.testing.expectEqual(@as(u32, 1), ctx.graphics.rp1);
    try std.testing.expectEqual(@as(u32, 2), ctx.graphics.rp2);
    try std.testing.expectEqual(@as(u32, 1), ctx.graphics.rp0);
}

test "tt executor interpolates points by reference points" {
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [1]Point = undefined;
    var glyph_points: [3]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 50, .y = 0, .ox = 50, .oy = 0, .on_curve = true },
        .{ .x = 200, .y = 0, .ox = 100, .oy = 0, .on_curve = true },
    };
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 0, 0x11, // SRP1 0
        0xB0, 2, 0x12, // SRP2 2
        0xB0, 1, 0x39, // IP point 1
    });

    try std.testing.expectEqual(@as(i32, 100), glyph_points[1].x);
    try std.testing.expect(glyph_points[1].touched_x);
    try std.testing.expectEqual(@as(u32, 1), ctx.graphics.loop_count);
}

test "tt executor applies delta point and cvt exceptions" {
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [2]i32 = .{ 100, 200 };
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});
    ctx.setEnvironment(.{
        .ppem_x_26_6 = 12 * 64,
        .ppem_y_26_6 = 12 * 64,
        .units_per_em = 1000,
    });

    var twilight_points: [1]Point = undefined;
    var glyph_points: [2]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 100, .y = 0, .ox = 100, .oy = 0, .on_curve = true },
    };
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        // DELTAP1: ppem 12, low=9 → +2 steps × quantum(delta_shift=3 → 8) = +16/64 px
        0xB2, 0, 0x39, 1, 0x5D,
        // DELTAC1: ppem 12, low=6 → -2 steps × 8 = -16/64 px
        0xB2, 0, 0x36, 1, 0x73,
        0xB0, 10, 0x5E, // SDB 10
        0xB0, 4, 0x5F, // SDS 4
        // DELTAP1: ppem 12, low=9 → +2 steps × quantum(delta_shift=4 → 4) = +8/64 px
        0xB2, 1, 0x29, 1, 0x5D,
    });

    try std.testing.expectEqual(@as(i32, 16), glyph_points[0].x);
    try std.testing.expectEqual(@as(i32, 108), glyph_points[1].x);
    try std.testing.expectEqual(@as(i32, 84), cvt[0]);
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

test "tt executor handles SROUND, S45ROUND and RTDG" {
    // SROUND/S45ROUND (0x76/0x77) and RTDG (0x3D) were previously not
    // implemented at all and would fail with InvalidOpcode on any font
    // that used them — Times, Arial, and many CFFs do.
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    // RTDG.
    try ctx.execute(&.{0x3D});
    try std.testing.expectEqual(tt_graphics.RoundMode{ .double_grid = {} }, ctx.graphics.round_mode);

    // SROUND with byte 0x48: period=1px, phase=0, threshold=4. ROUND[0] of 33 → 64.
    ctx.reset();
    ctx.graphics = .{};
    try ctx.execute(&.{ 0xB0, 0x48, 0x76, 0xB0, 33, 0x68 });
    try expectStack(&ctx, &.{64});

    // S45ROUND simply selects the 45-degree grid period; the call must
    // succeed and leave a super round mode in place.
    ctx.reset();
    ctx.graphics = .{};
    try ctx.execute(&.{ 0xB0, 0x40, 0x77 });
    try std.testing.expectEqual(@as(std.meta.Tag(tt_graphics.RoundMode), .super), std.meta.activeTag(ctx.graphics.round_mode));
}

test "tt executor INSTCTRL rejects malformed value masks" {
    // INSTCTRL value must be exactly `1 << (selector-1)` or zero. Previously
    // any non-zero value would set the bit, which differs from FreeType's
    // strict validation. Out-of-range selectors are also accepted as no-ops.
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    // selector=1, value=99 — value doesn't match 1<<0=1, so reject silently.
    try ctx.execute(&.{ 0xB1, 1, 99, 0x8E });
    try std.testing.expectEqual(@as(i32, 0), ctx.graphics.instruct_control);

    // selector=1, value=1 — valid set.
    try ctx.execute(&.{ 0xB1, 1, 1, 0x8E });
    try std.testing.expectEqual(@as(i32, 1), ctx.graphics.instruct_control);

    // selector=1, value=0 — clear bit 0.
    try ctx.execute(&.{ 0xB1, 1, 0, 0x8E });
    try std.testing.expectEqual(@as(i32, 0), ctx.graphics.instruct_control);

    // selector=2, value=2 — valid set bit 1.
    try ctx.execute(&.{ 0xB1, 2, 2, 0x8E });
    try std.testing.expectEqual(@as(i32, 2), ctx.graphics.instruct_control);

    // selector=2, value=1 — wrong mask, reject.
    try ctx.execute(&.{ 0xB1, 2, 1, 0x8E });
    try std.testing.expectEqual(@as(i32, 2), ctx.graphics.instruct_control);

    // selector=3 (ClearType) — accepted as no-op; doesn't touch instruct_control.
    try ctx.execute(&.{ 0xB1, 3, 4, 0x8E });
    try std.testing.expectEqual(@as(i32, 2), ctx.graphics.instruct_control);
}

test "tt executor SHZ leaves phantom points untouched" {
    // SHZ on the glyph zone must skip the four trailing phantom points
    // (LSB, advance, TSB, advance-height) per FreeType's undocumented
    // behaviour. Without this, hinting overwrites the per-glyph advance
    // width that downstream rendering reads back from the zone.
    var stack: [32]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [1]Point = undefined;
    var glyph_points: [6]Point = .{
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 10, .y = 0, .ox = 5, .oy = 0, .on_curve = true }, // moved (dx=+5)
        // 4 phantom points appended:
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 500, .y = 0, .ox = 500, .oy = 0, .on_curve = true },
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
    };
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 1, 0x10, // SRP0 1
        0xB0, 1, 0x11, // SRP1 1 (so SHZ[1] uses rp1 in zp0)
        0xB0, 1, 0x37, // SHZ[1] of glyph zone (1) — uses rp1 from zp0
    });

    // Non-phantom points shifted by (10 - 5) = 5; phantom points untouched.
    try std.testing.expectEqual(@as(i32, 5), glyph_points[0].x);
    try std.testing.expectEqual(@as(i32, 0), glyph_points[2].x);
    try std.testing.expectEqual(@as(i32, 500), glyph_points[3].x);
}

test "tt executor SHC in twilight zone shifts virtual contour 0" {
    // SHC on the twilight zone has an undocumented "virtual contour 0
    // contains every point" semantic (per FreeType / Greg Hitchcock).
    // Without this, snail returned InvalidPoint because the twilight zone
    // had no contours array.
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});

    var twilight_points: [3]Point = .{
        .{ .x = 100, .y = 0, .ox = 50, .oy = 0, .on_curve = true }, // moved by +50
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
        .{ .x = 0, .y = 0, .ox = 0, .oy = 0, .on_curve = true },
    };
    var glyph_points: [0]Point = .{};
    var zones: PointZones = .{
        .twilight = PointZone.initTwilight(&twilight_points),
        .glyph = .{ .points = &glyph_points },
    };
    // Twilight initTwilight zeroes the points; overwrite after.
    twilight_points[0] = .{ .x = 100, .y = 0, .ox = 50, .oy = 0, .on_curve = true };
    ctx.setZones(&zones);

    try ctx.execute(&.{
        0xB0, 0, 0x16, // SZPS twilight (all zone pointers)
        0xB0, 0, 0x10, // SRP0 0 (point 0 is the "moved" ref)
        0xB0, 0, 0x11, // SRP1 0
        0xB0, 0, 0x35, // SHC[1] contour 0 — uses rp1 in zp0
    });

    // Points 1 and 2 shift by (cur - org) of rp0 = 100 - 50 = 50. Point 0 is
    // skipped because it is the reference (zp0 == zp2 here via SZPS).
    try std.testing.expectEqual(@as(i32, 100), twilight_points[0].x); // ref, unchanged
    try std.testing.expectEqual(@as(i32, 50), twilight_points[1].x);
    try std.testing.expectEqual(@as(i32, 50), twilight_points[2].x);
}

test "tt executor cross-axis CVT round-trip with stretched pixels" {
    // FreeType-style canonical CVT storage with on-read projection ratio:
    // a single prep program can use SVTCA[x] / SVTCA[y] interchangeably and
    // every read/write of the same cell sees the per-axis scaling, even
    // when ppem_x != ppem_y. snail previously kept separate cvt_x / cvt_y
    // arrays scaled at SizeState time, which only got the result right
    // when the axis didn't change mid-prep.
    var stack: [16]i32 = undefined;
    var storage: [1]i32 = .{0};
    var cvt: [1]i32 = .{0};
    var ctx = Context.init(.{ .stack = &stack, .storage = &storage, .cvt = &cvt }, .{});
    ctx.setEnvironment(.{
        .ppem_x_26_6 = 10 * 64,
        .ppem_y_26_6 = 12 * 64,
        .units_per_em = 1000,
    });

    try ctx.execute(&.{
        0x00, // SVTCA[y]
        0xB1, 0, 64, 0x44, // WCVTP cvt[0] = 64 (=1px along y)
        0xB0, 0, 0x45, // RCVT — should round-trip to 64
        0x01, // SVTCA[x]
        0xB0, 0, 0x45, // RCVT — same canonical cell, scaled to 10/12 px = 53
    });
    try expectStack(&ctx, &.{ 64, 53 });
}

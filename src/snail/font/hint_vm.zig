//! TrueType bytecode hinting wrapped as a `GlyphCurves` producer.
//!
//! The TT VM (`src/snail/font/truetype/`) stays verbatim. This module trims
//! the wrapper layer down to a single producer call: given a glyph and a
//! ppem, return the hinted curves in the same `GlyphCurves` shape that the
//! unhinted and path producers emit. The atlas then consumes them the same
//! way it consumes anything else.
//!
//! `HintVm` owns two collocated caches, both keyed by ppem and reset
//! together by `evictPpem` / `clear`:
//!
//! 1. **`HintMachine` state.** fpgm/prep execution is expensive
//!    (thousands of cycles per ppem); amortizing across glyphs at the
//!    same size is the justified-exception cache the plan calls out.
//! 2. **`GlyphTopologyCache`.** Holds parsed glyph outlines (the
//!    `glyf`-table read; ppem-independent in content but stored per
//!    ppem to share the slot's allocator / lifetime). Saves re-parsing
//!    each glyph on every advance/render at the same size.
//!
//! Both caches surface in `HintVmStats` (`ppem_count`, `machine_bytes`,
//! `topology_glyph_count`) so callers can budget memory and evict.
//!
//! Output memoization — packed `GlyphCurves` bytes and hinted advances
//! keyed by `(ppem, glyph_id)` — is *not* in core. It lives in
//! `helpers.HintedGlyphCache`, which wraps `HintVm` and supplies the
//! `AdvanceProvider` closure for shape-time advance lookups.
//!
//! Thread safety: not thread-safe. `hintGlyph` / `hintedAdvance` /
//! `warmPpem` mutate the per-ppem machine cache on the read path, and
//! `evictPpem` / `clear` / `deinit` drop slots concurrent callers may
//! still be inside. Construct one `HintVm` per thread that needs hinting;
//! immutable snapshots between threads are not supported. The TT VM
//! itself does not block on I/O, so per-thread instances scale linearly.

const std = @import("std");
const tt_vm = @import("truetype/vm.zig");
const tt_hint = @import("truetype/hint.zig");
const tt_exec = @import("truetype/exec.zig");
const tt_tables = @import("truetype/tables.zig");
const tt_points = @import("truetype/points.zig");
const curves_mod = @import("../atlas/curves.zig");
const font_mod = @import("../font.zig");
const curve_tex = @import("../render/format/curve_texture.zig");
const band_tex = @import("../render/format/band_texture.zig");

pub const Font = font_mod.Font;
pub const HintPpem = struct {
    x_26_6: u32,
    y_26_6: u32,

    pub fn uniform(ppem_26_6: u32) HintPpem {
        return .{ .x_26_6 = ppem_26_6, .y_26_6 = ppem_26_6 };
    }

    /// Pack both axes into a single u32 for use as `RecordKey.c`. The two
    /// axes share a 16-bit slot apiece; this is enough range for the
    /// ppem values used in practice (well under 1024 px even at extreme
    /// zoom) given the 26.6 scaling factor of 64×.
    pub fn packed26Dot6(self: HintPpem) u32 {
        const x: u32 = @min(self.x_26_6, 0xFFFF);
        const y: u32 = @min(self.y_26_6, 0xFFFF);
        return (y << 16) | x;
    }
};

pub const HintVmStats = struct {
    /// Number of distinct ppems with cached VM state.
    ppem_count: u32,
    /// Bytes held by per-ppem `HintMachine` slots (the fpgm/prep amortization).
    machine_bytes: usize,
    /// Total `(ppem, glyph_id)` topology entries across all ppem slots.
    /// Grows with the per-ppem glyph working set; cleared by
    /// `evictPpem` / `clear` together with `machine_bytes`.
    topology_glyph_count: u32,
};

/// Failures returned by `HintVm` operations. Spelled out explicitly so a
/// new opcode or table-parse variant in the underlying TT VM doesn't
/// silently widen the public surface.
pub const HintError = error{
    // HintVm-specific.
    NoHinting,
    GlyphTopologyChanged,
    InvalidStorageSnapshot,
    // Allocator (mirrors std.mem.Allocator.Error).
    OutOfMemory,
    // TT VM execution (mirrors truetype/exec.zig Error).
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
    // Font-table parse (mirrors truetype/tables.zig ParseError).
    InvalidFont,
    MissingRequiredTable,
};

comptime {
    @setEvalBranchQuota(5000);
    // Compile-time guard so adding a variant to one of the underlying
    // error sets surfaces here instead of silently widening HintError.
    const expected = error{
        NoHinting,
        GlyphTopologyChanged,
        InvalidStorageSnapshot,
    } || std.mem.Allocator.Error || tt_exec.Error || tt_tables.ParseError || tt_points.Error;
    assertErrorSetsMatch(HintError, expected);
}

fn assertErrorSetsMatch(comptime A: type, comptime B: type) void {
    for (@typeInfo(A).error_set.?) |e| {
        if (!isInErrorSet(B, e.name)) {
            @compileError("HintError has extra variant '" ++ e.name ++ "' not in underlying sets");
        }
    }
    for (@typeInfo(B).error_set.?) |e| {
        if (!isInErrorSet(A, e.name)) {
            @compileError("HintError missing variant '" ++ e.name ++ "' from underlying sets");
        }
    }
}

fn isInErrorSet(comptime S: type, comptime name: []const u8) bool {
    for (@typeInfo(S).error_set.?) |e| {
        if (std.mem.eql(u8, e.name, name)) return true;
    }
    return false;
}

const MachineSlot = struct {
    machine: *tt_hint.HintMachine,
    topology: tt_hint.GlyphTopologyCache,
};

pub const HintVm = struct {
    allocator: std.mem.Allocator,
    program: tt_vm.Program,
    machines: std.AutoHashMapUnmanaged(HintPpem, MachineSlot),

    /// Inspect a font for hinting support. Returns `error.NoHinting` if the
    /// font has no `fpgm`/`prep`/`cvt` bytecode tables — the caller falls
    /// back to `font.extractCurves`.
    pub fn init(allocator: std.mem.Allocator, font: *const Font) !HintVm {
        const program = tt_vm.Program.init(font.inner.data) catch return error.NoHinting;
        return .{
            .allocator = allocator,
            .program = program,
            .machines = .{},
        };
    }

    pub fn deinit(self: *HintVm) void {
        self.clear();
        self.machines.deinit(self.allocator);
        self.* = undefined;
    }

    /// Drop the per-ppem VM state for `ppem`. Curves already extracted
    /// into atlases or held in helper caches keep working — the VM owns
    /// neither.
    pub fn evictPpem(self: *HintVm, ppem: HintPpem) void {
        if (self.machines.fetchRemove(ppem)) |removed| {
            var slot = removed.value;
            deinitSlot(self.allocator, &slot);
        }
    }

    /// Drop every cached ppem.
    pub fn clear(self: *HintVm) void {
        var it = self.machines.iterator();
        while (it.next()) |entry| {
            var slot = entry.value_ptr.*;
            deinitSlot(self.allocator, &slot);
        }
        self.machines.clearRetainingCapacity();
    }

    /// Ensure the per-ppem machine state exists for `ppem` (parses + executes
    /// fpgm/prep at this ppem if not already cached). Idempotent. Useful for
    /// preheating common ppems at startup so the first glyph at that size
    /// doesn't pay the setup cost.
    pub fn warmPpem(self: *HintVm, ppem: HintPpem) HintError!void {
        _ = try self.machineFor(ppem);
    }

    /// Return the hinted horizontal advance for `glyph_id` at `ppem`, in
    /// 26.6 fixed-point pixels. Runs the TT VM every call — output
    /// memoization is the caller's job (typically
    /// `helpers.HintedGlyphCache.advance`).
    pub fn hintedAdvance(
        self: *HintVm,
        glyph_id: u16,
        ppem: HintPpem,
    ) HintError!i32 {
        const slot = try self.machineFor(ppem);
        return try slot.machine.glyphAdvanceX26Dot6(&slot.topology, glyph_id);
    }

    /// Run the TT VM for `glyph_id` at `ppem` and pack the result as
    /// `GlyphCurves`. Caller owns the returned value.
    ///
    /// `scratch` is used for VM-internal scratch state that does not need
    /// to outlive the call. The returned `GlyphCurves` is allocated from
    /// `allocator`.
    pub fn hintGlyph(
        self: *HintVm,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        glyph_id: u16,
        ppem: HintPpem,
    ) HintError!curves_mod.GlyphCurves {
        const slot = try self.machineFor(ppem);
        const executed = try slot.machine.executeCachedGlyph(&slot.topology, glyph_id);
        var hint_value = try slot.machine.buildGlyphHint(scratch, glyph_id, executed);
        defer hint_value.deinit();

        if (hint_value.curves.len == 0) return curves_mod.GlyphCurves.empty(allocator);

        // The `GlyphHint`'s `prepared_curves` are already direct-encoded
        // (origin-zero, quantized). Pack them into the standard curve
        // bytes the atlas consumes — single-shape encoder skips the
        // `buildCurveTexture` TEX_WIDTH padding.
        const curve_count: u16 = @intCast(hint_value.prepared_curves.len);
        const curve_bytes = try curve_tex.encodeDirectSingleGlyphCurves(allocator, hint_value.prepared_curves);
        errdefer allocator.free(curve_bytes);

        const entry = curve_tex.GlyphCurveEntry{
            .start_x = 0,
            .start_y = 0,
            .count = curve_count,
            .offset = 0,
        };
        // Band data goes straight to the output allocator. The
        // BandLists / sort-array intermediates stay on scratch.
        const bd = try band_tex.buildGlyphBandDataWithPreparedCurves(
            allocator,
            scratch,
            hint_value.curves,
            hint_value.curves.len,
            hint_value.bbox,
            entry,
            .zero,
            true,
            hint_value.prepared_curves,
            null,
        );
        errdefer band_tex.freeGlyphBandData(allocator, @constCast(&bd));

        return .{
            .allocator = allocator,
            .curve_bytes = curve_bytes,
            .band_bytes = bd.data,
            .curve_count = curve_count,
            .h_band_count = bd.h_band_count,
            .v_band_count = bd.v_band_count,
            .band_scale_x = bd.band_scale_x,
            .band_scale_y = bd.band_scale_y,
            .band_offset_x = bd.band_offset_x,
            .band_offset_y = bd.band_offset_y,
            .bbox = hint_value.bbox,
        };
    }

    /// Summary of the per-ppem machine cache (the one cache `HintVm`
    /// keeps in core — see the rewrite plan's "one justified exception").
    /// Useful for cache-pressure decisions: e.g. evict the oldest ppem
    /// when `machine_bytes` crosses a budget.
    pub fn stats(self: *const HintVm) HintVmStats {
        var machine_bytes: usize = 0;
        var topology_glyph_count: u32 = 0;
        var it = self.machines.valueIterator();
        while (it.next()) |slot| {
            machine_bytes += slot.machine.byteSize();
            topology_glyph_count += @intCast(slot.topology.map.count());
        }
        return .{
            .ppem_count = self.machines.count(),
            .machine_bytes = machine_bytes,
            .topology_glyph_count = topology_glyph_count,
        };
    }

    fn machineFor(self: *HintVm, ppem: HintPpem) HintError!*MachineSlot {
        const gop = try self.machines.getOrPut(self.allocator, ppem);
        if (!gop.found_existing) {
            const machine_ptr = try self.allocator.create(tt_hint.HintMachine);
            errdefer self.allocator.destroy(machine_ptr);
            machine_ptr.* = try tt_hint.HintMachine.initForProgram(self.allocator, &self.program, .{
                .x_26_6 = ppem.x_26_6,
                .y_26_6 = ppem.y_26_6,
            });
            errdefer machine_ptr.deinit();

            const topology = tt_hint.GlyphTopologyCache.initForProgram(self.allocator, &self.program);

            gop.value_ptr.* = .{
                .machine = machine_ptr,
                .topology = topology,
            };
        }
        return gop.value_ptr;
    }
};

fn deinitSlot(allocator: std.mem.Allocator, slot: *MachineSlot) void {
    slot.topology.deinit();
    slot.machine.deinit();
    allocator.destroy(slot.machine);
}

const testing = std.testing;

test "HintVm hints DejaVu digits and letters across small ppems" {
    // Regression net for two TT-interpreter bugs that only surfaced on real
    // fonts at small sizes: SLOOP-0 handling (DejaVu '2' -> StackUnderflow at
    // every size) and DELTAP/DELTAC pop order (DejaVu 'a','m','r','0' ->
    // InvalidPoint below ~12px, where the delta exceptions fire).
    const font_data = @import("assets").dejavu_sans_mono;
    var font = try Font.init(font_data);
    var hinter = try HintVm.init(testing.allocator, &font);
    defer hinter.deinit();
    for ("2amr0Hngoe13") |ch| {
        for ([_]u32{ 8, 9, 10, 11, 12, 16 }) |px| {
            const gid = try font.glyphIndex(ch);
            var c = try hinter.hintGlyph(testing.allocator, testing.allocator, gid, HintPpem.uniform(px * 64));
            c.deinit();
        }
    }
}

test "HintVm init fails cleanly on fonts without hinting" {
    var font = Font.init(&[_]u8{ 0, 0, 0, 0 }) catch |e| {
        try testing.expect(e == error.InvalidFont or e == error.UnexpectedEof);
        return;
    };
    const res = HintVm.init(testing.allocator, &font);
    try testing.expectError(error.NoHinting, res);
}

test "HintVm produces GlyphCurves for a hinted glyph" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);

    var hinter = try HintVm.init(testing.allocator, &font);
    defer hinter.deinit();

    const ppem = HintPpem.uniform(16 * 64);
    const glyph_id = try font.glyphIndex('A');

    var curves = try hinter.hintGlyph(testing.allocator, testing.allocator, glyph_id, ppem);
    defer curves.deinit();

    try testing.expect(curves.curve_count > 0);
    try testing.expect(curves.curve_bytes.len > 0);
    try testing.expect(curves.band_bytes.len > 0);
    try testing.expect(curves.h_band_count > 0);
}

test "HintVm caches per-ppem VM state across calls" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);

    var hinter = try HintVm.init(testing.allocator, &font);
    defer hinter.deinit();

    const ppem = HintPpem.uniform(12 * 64);
    const gid_a = try font.glyphIndex('A');
    const gid_b = try font.glyphIndex('B');

    var c0 = try hinter.hintGlyph(testing.allocator, testing.allocator, gid_a, ppem);
    defer c0.deinit();
    try testing.expectEqual(@as(u32, 1), hinter.machines.count());

    var c1 = try hinter.hintGlyph(testing.allocator, testing.allocator, gid_b, ppem);
    defer c1.deinit();
    try testing.expectEqual(@as(u32, 1), hinter.machines.count());

    const ppem_other = HintPpem.uniform(24 * 64);
    var c2 = try hinter.hintGlyph(testing.allocator, testing.allocator, gid_a, ppem_other);
    defer c2.deinit();
    try testing.expectEqual(@as(u32, 2), hinter.machines.count());
}

test "HintVm.stats reports ppem, machine bytes, and topology growth" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);

    var hinter = try HintVm.init(testing.allocator, &font);
    defer hinter.deinit();

    try testing.expectEqual(@as(u32, 0), hinter.stats().ppem_count);
    try testing.expectEqual(@as(u32, 0), hinter.stats().topology_glyph_count);

    const ppem = HintPpem.uniform(16 * 64);
    var c0 = try hinter.hintGlyph(testing.allocator, testing.allocator, try font.glyphIndex('A'), ppem);
    c0.deinit();
    const after_a = hinter.stats();
    try testing.expectEqual(@as(u32, 1), after_a.ppem_count);
    try testing.expect(after_a.machine_bytes > 0);
    try testing.expectEqual(@as(u32, 1), after_a.topology_glyph_count);

    var c1 = try hinter.hintGlyph(testing.allocator, testing.allocator, try font.glyphIndex('B'), ppem);
    c1.deinit();
    const after_b = hinter.stats();
    try testing.expectEqual(@as(u32, 1), after_b.ppem_count);
    try testing.expectEqual(@as(u32, 2), after_b.topology_glyph_count);

    hinter.evictPpem(ppem);
    const after_evict = hinter.stats();
    try testing.expectEqual(@as(u32, 0), after_evict.ppem_count);
    try testing.expectEqual(@as(u32, 0), after_evict.topology_glyph_count);
}

test "HintVm.evictPpem drops one cache entry without affecting others" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);

    var hinter = try HintVm.init(testing.allocator, &font);
    defer hinter.deinit();

    const ppem_12 = HintPpem.uniform(12 * 64);
    const ppem_24 = HintPpem.uniform(24 * 64);
    const gid = try font.glyphIndex('A');

    var c0 = try hinter.hintGlyph(testing.allocator, testing.allocator, gid, ppem_12);
    c0.deinit();
    var c1 = try hinter.hintGlyph(testing.allocator, testing.allocator, gid, ppem_24);
    c1.deinit();
    try testing.expectEqual(@as(u32, 2), hinter.machines.count());

    hinter.evictPpem(ppem_12);
    try testing.expectEqual(@as(u32, 1), hinter.machines.count());
    try testing.expect(hinter.machines.contains(ppem_24));
}

test "HintVm hint output round-trips through an atlas" {
    const atlas_mod = @import("../atlas.zig");
    const record_key_mod = @import("../atlas/record_key.zig");

    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);

    var hinter = try HintVm.init(testing.allocator, &font);
    defer hinter.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    const ppem = HintPpem.uniform(18 * 64);
    const gid = try font.glyphIndex('M');
    var curves = try hinter.hintGlyph(testing.allocator, testing.allocator, gid, ppem);
    defer curves.deinit();

    const key = record_key_mod.hintedGlyph(0, gid, ppem.packed26Dot6());
    var atlas = try atlas_mod.Atlas.from(testing.allocator, pool, &.{
        .{ .key = key, .curves = curves },
    });
    defer atlas.deinit();

    const rec = atlas.lookupRecord(key) orelse return error.MissingRecord;
    try testing.expect(rec.curve_count == curves.curve_count);
    try testing.expect(rec.bands.h_band_count == curves.h_band_count);
    try testing.expect(rec.bands.v_band_count == curves.v_band_count);
}

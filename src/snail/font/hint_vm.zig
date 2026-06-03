//! TrueType bytecode hinting wrapped as a `GlyphCurves` producer.
//!
//! The TT VM (`src/snail/font/truetype/`) stays verbatim. This module trims
//! the wrapper layer down to a single producer call: given a glyph and a
//! ppem, return the hinted curves in the same `GlyphCurves` shape that the
//! unhinted and path producers emit. The atlas then consumes them the same
//! way it consumes anything else.
//!
//! `HintVm` owns one cache: per-ppem `HintMachine` state. fpgm/prep
//! execution is genuinely expensive (thousands of cycles per ppem) and
//! amortizing across glyphs at the same size is the only reason this
//! cache lives in core rather than helpers. Callers retain control via
//! `evictPpem` and `clear`.
//!
//! Output memoization — packed `GlyphCurves` bytes and hinted advances
//! keyed by `(ppem, glyph_id)` — is *not* in core. It lives in
//! `helpers.HintedGlyphCache`, which wraps `HintVm` and supplies the
//! `AdvanceProvider` closure for shape-time advance lookups.

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
    ppem_count: u32,
    machine_bytes: usize,
};

pub const HintError = error{
    NoHinting,
    GlyphTopologyChanged,
    InvalidStorageSnapshot,
} || std.mem.Allocator.Error || tt_exec.Error || tt_tables.ParseError || tt_points.Error;

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
        var it = self.machines.valueIterator();
        while (it.next()) |slot| machine_bytes += slot.machine.byteSize();
        return .{
            .ppem_count = self.machines.count(),
            .machine_bytes = machine_bytes,
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

//! TrueType bytecode hinting wrapped as a `GlyphCurves` producer.
//!
//! The TT VM (`src/snail/font/tt_*.zig`) stays verbatim. This module trims
//! the wrapper layer down to a single producer call: given a glyph and a
//! ppem, return the hinted curves in the same `GlyphCurves` shape that the
//! unhinted and path producers emit. The atlas then consumes them the same
//! way it consumes anything else.
//!
//! Per-ppem `HintMachine` state is cached internally so repeated hint calls
//! at the same size hit the cache. `evictPpem` and `clear` are the
//! mechanism; policy lives at the caller.

const std = @import("std");
const bezier = @import("math/bezier.zig");
const tt_vm = @import("font/tt_vm.zig");
const tt_hint = @import("text/tt_hint.zig");
const curves_mod = @import("curves.zig");
const font_mod = @import("font.zig");
const curve_tex = @import("render/format/curve_texture.zig");
const band_tex = @import("render/format/band_texture.zig");

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
        // ppem * 64 typically fits in 16 bits (1024 px @ 26.6 = 0x10000,
        // so we clamp to 0xFFFF for safety).
        const x: u32 = @min(self.x_26_6, 0xFFFF);
        const y: u32 = @min(self.y_26_6, 0xFFFF);
        return (y << 16) | x;
    }
};

pub const HintError = error{
    NoHinting,
    GlyphTopologyChanged,
} || std.mem.Allocator.Error || anyerror;

const MachineSlot = struct {
    machine: *tt_hint.HintMachine,
    topology: tt_hint.GlyphTopologyCache,
};

pub const Hinter = struct {
    allocator: std.mem.Allocator,
    program: tt_vm.Program,
    machines: std.AutoHashMapUnmanaged(HintPpem, MachineSlot),

    /// Inspect a font for hinting support. Returns `error.NoHinting` if the
    /// font has no `fpgm`/`prep`/`cvt` bytecode tables — the caller falls
    /// back to `font.extractCurves`.
    pub fn init(allocator: std.mem.Allocator, font: *const Font) !Hinter {
        const program = tt_vm.Program.init(font.inner.data) catch return error.NoHinting;
        return .{
            .allocator = allocator,
            .program = program,
            .machines = .{},
        };
    }

    pub fn deinit(self: *Hinter) void {
        self.clear();
        self.machines.deinit(self.allocator);
        self.* = undefined;
    }

    /// Drop the VM cache for one ppem. Curves already extracted into atlases
    /// keep working — the atlas owns its byte data, not the hinter.
    pub fn evictPpem(self: *Hinter, ppem: HintPpem) void {
        const removed = self.machines.fetchRemove(ppem) orelse return;
        var slot = removed.value;
        deinitSlot(self.allocator, &slot);
    }

    /// Drop every cached ppem. Same lifecycle guarantee as `evictPpem`.
    pub fn clear(self: *Hinter) void {
        var it = self.machines.iterator();
        while (it.next()) |entry| {
            var slot = entry.value_ptr.*;
            deinitSlot(self.allocator, &slot);
        }
        self.machines.clearRetainingCapacity();
    }

    /// Run the TT VM for `glyph_id` at `ppem` and pack the result as
    /// `GlyphCurves`. Caller owns the returned value.
    ///
    /// `scratch` is used for VM-internal scratch state that does not need
    /// to outlive the call. The returned `GlyphCurves` is allocated from
    /// `allocator`.
    pub fn hint(
        self: *Hinter,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        glyph_id: u16,
        ppem: HintPpem,
    ) HintError!curves_mod.GlyphCurves {
        const slot = try self.machineFor(ppem);
        var hint_value = try slot.machine.hintCachedGlyph(scratch, &slot.topology, glyph_id);
        defer hint_value.deinit();

        if (hint_value.curves.len == 0) return curves_mod.GlyphCurves.empty(allocator);

        // The `GlyphHint`'s `prepared_curves` are already direct-encoded
        // (origin-zero, quantized). Pack them into the standard curve and
        // band textures the atlas consumes.
        const single = [_]curve_tex.GlyphCurves{.{
            .curves = hint_value.curves,
            .bbox = hint_value.bbox,
            .logical_curve_count = hint_value.curves.len,
            .prefer_direct_encoding = true,
            .prepared_curves = hint_value.prepared_curves,
        }};

        var ct = try curve_tex.buildCurveTexture(allocator, scratch, &single);
        defer ct.texture.deinit();
        defer scratch.free(ct.entries);

        const curve_count: u16 = @intCast(hint_value.prepared_curves.len);
        const curve_used_words: usize = @as(usize, curve_count) * curve_tex.SEGMENT_TEXELS * 4;
        const curve_bytes = try allocator.dupe(u16, ct.texture.data[0..curve_used_words]);
        errdefer allocator.free(curve_bytes);

        const entry = curve_tex.GlyphCurveEntry{
            .start_x = 0,
            .start_y = 0,
            .count = curve_count,
            .offset = 0,
        };
        var bd = try band_tex.buildGlyphBandDataWithPreparedCurves(
            scratch,
            hint_value.curves,
            hint_value.curves.len,
            hint_value.bbox,
            entry,
            .zero,
            true,
            hint_value.prepared_curves,
        );
        defer band_tex.freeGlyphBandData(scratch, &bd);

        const band_bytes = try allocator.dupe(u16, bd.data);

        return .{
            .allocator = allocator,
            .curve_bytes = curve_bytes,
            .band_bytes = band_bytes,
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

    fn machineFor(self: *Hinter, ppem: HintPpem) HintError!*MachineSlot {
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

test "Hinter init fails cleanly on fonts without hinting" {
    // Use a font with no TT bytecode. Most CFF/OTF fonts qualify, but we
    // don't have one in assets; instead, build an empty buffer that
    // tt_vm.Program.init will reject.
    var font = Font.init(&[_]u8{ 0, 0, 0, 0 }) catch |e| {
        try testing.expect(e == error.InvalidFont or e == error.UnexpectedEof);
        return;
    };
    defer font.deinit();
    const res = Hinter.init(testing.allocator, &font);
    try testing.expectError(error.NoHinting, res);
}

test "Hinter produces GlyphCurves for a hinted glyph" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    defer font.deinit();

    var hinter = try Hinter.init(testing.allocator, &font);
    defer hinter.deinit();

    const ppem = HintPpem.uniform(16 * 64);
    const glyph_id = try font.glyphIndex('A');

    var curves = try hinter.hint(testing.allocator, testing.allocator, glyph_id, ppem);
    defer curves.deinit();

    try testing.expect(curves.curve_count > 0);
    try testing.expect(curves.curve_bytes.len > 0);
    try testing.expect(curves.band_bytes.len > 0);
    try testing.expect(curves.h_band_count > 0);
}

test "Hinter caches per-ppem VM state across calls" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    defer font.deinit();

    var hinter = try Hinter.init(testing.allocator, &font);
    defer hinter.deinit();

    const ppem = HintPpem.uniform(12 * 64);
    const gid_a = try font.glyphIndex('A');
    const gid_b = try font.glyphIndex('B');

    var c0 = try hinter.hint(testing.allocator, testing.allocator, gid_a, ppem);
    defer c0.deinit();
    try testing.expectEqual(@as(u32, 1), hinter.machines.count());

    var c1 = try hinter.hint(testing.allocator, testing.allocator, gid_b, ppem);
    defer c1.deinit();
    try testing.expectEqual(@as(u32, 1), hinter.machines.count());

    const ppem_other = HintPpem.uniform(24 * 64);
    var c2 = try hinter.hint(testing.allocator, testing.allocator, gid_a, ppem_other);
    defer c2.deinit();
    try testing.expectEqual(@as(u32, 2), hinter.machines.count());
}

test "Hinter.evictPpem drops one cache entry without affecting others" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    defer font.deinit();

    var hinter = try Hinter.init(testing.allocator, &font);
    defer hinter.deinit();

    const ppem_12 = HintPpem.uniform(12 * 64);
    const ppem_24 = HintPpem.uniform(24 * 64);
    const gid = try font.glyphIndex('A');

    var c0 = try hinter.hint(testing.allocator, testing.allocator, gid, ppem_12);
    c0.deinit();
    var c1 = try hinter.hint(testing.allocator, testing.allocator, gid, ppem_24);
    c1.deinit();
    try testing.expectEqual(@as(u32, 2), hinter.machines.count());

    hinter.evictPpem(ppem_12);
    try testing.expectEqual(@as(u32, 1), hinter.machines.count());
    try testing.expect(hinter.machines.contains(ppem_24));
}

test "Hinter hint output round-trips through an atlas" {
    const atlas_mod = @import("atlas.zig");
    const record_key_mod = @import("record_key.zig");

    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    defer font.deinit();

    var hinter = try Hinter.init(testing.allocator, &font);
    defer hinter.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    const ppem = HintPpem.uniform(18 * 64);
    const gid = try font.glyphIndex('M');
    var curves = try hinter.hint(testing.allocator, testing.allocator, gid, ppem);
    defer curves.deinit();

    const key = record_key_mod.hintedGlyph(0, gid, ppem.packed26Dot6());
    var atlas = try atlas_mod.Atlas.from(testing.allocator, pool, &.{
        .{ .key = key, .curves = curves },
    });
    defer atlas.deinit();

    const rec = atlas.lookupRecord(key) orelse return error.MissingRecord;
    try testing.expect(rec.curve_count == curves.curve_count);
    try testing.expect(rec.bands.h_band_count == curves.h_band_count);
}

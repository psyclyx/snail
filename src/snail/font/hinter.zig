//! TrueType bytecode hinting wrapped as a `GlyphCurves` producer.
//!
//! The TT VM (`src/snail/font/truetype/`) stays verbatim. This module trims
//! the wrapper layer down to a single producer call: given a glyph and a
//! ppem, return the hinted curves in the same `GlyphCurves` shape that the
//! unhinted and path producers emit. The atlas then consumes them the same
//! way it consumes anything else.
//!
//! Per-ppem `HintMachine` state is cached internally, *and* the packed
//! `GlyphCurves` bytes are cached per `(ppem, glyph_id)` so a repeat call
//! at the same size returns instantly via a memcpy rather than re-running
//! the VM and rebuilding the curve/band textures. `evictPpem` and `clear`
//! drop both caches; policy lives at the caller.

const std = @import("std");
const bezier = @import("../math/bezier.zig");
const tt_vm = @import("truetype/vm.zig");
const tt_hint = @import("truetype/hint.zig");
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

const CachedGlyphKey = struct {
    ppem_x_26_6: u32,
    ppem_y_26_6: u32,
    glyph_id: u16,
};

/// Pre-packed `GlyphCurves` byte arrays owned by the Hinter. `hint()` clones
/// these into the caller's allocator on cache hit so the caller still gets a
/// fully-owned `GlyphCurves` value with consistent lifecycle semantics.
const CachedGlyph = struct {
    curve_bytes: []u16,
    band_bytes: []u16,
    curve_count: u16,
    h_band_count: u16,
    v_band_count: u16,
    band_scale_x: f32,
    band_scale_y: f32,
    band_offset_x: f32,
    band_offset_y: f32,
    bbox: bezier.BBox,

    fn deinit(self: *CachedGlyph, allocator: std.mem.Allocator) void {
        allocator.free(self.curve_bytes);
        allocator.free(self.band_bytes);
        self.* = undefined;
    }

    fn cloneInto(self: *const CachedGlyph, allocator: std.mem.Allocator) !curves_mod.GlyphCurves {
        // One alloc + two memcpys instead of two alloc+memcpy. The two
        // halves are sized at the cache-write site and never resized,
        // so a single backing buffer is safe.
        const combined = try allocator.alloc(u16, self.curve_bytes.len + self.band_bytes.len);
        @memcpy(combined[0..self.curve_bytes.len], self.curve_bytes);
        @memcpy(combined[self.curve_bytes.len..], self.band_bytes);
        return .{
            .allocator = allocator,
            .backing = combined,
            .curve_bytes = combined[0..self.curve_bytes.len],
            .band_bytes = combined[self.curve_bytes.len..],
            .curve_count = self.curve_count,
            .h_band_count = self.h_band_count,
            .v_band_count = self.v_band_count,
            .band_scale_x = self.band_scale_x,
            .band_scale_y = self.band_scale_y,
            .band_offset_x = self.band_offset_x,
            .band_offset_y = self.band_offset_y,
            .bbox = self.bbox,
        };
    }
};

/// Lightweight cached per-(ppem, glyph_id) metrics. Populated either by
/// `Hinter.advanceX26Dot6` (which only runs the VM, skipping curve build)
/// or as a side-effect of `Hinter.hint`. The HarfBuzz `glyph_h_advance`
/// callback reads from this cache so per-shape advance queries don't
/// re-execute the VM.
const CachedMetrics = struct {
    advance_x_26_6: i32,
};

pub const Hinter = struct {
    allocator: std.mem.Allocator,
    program: tt_vm.Program,
    machines: std.AutoHashMapUnmanaged(HintPpem, MachineSlot),
    /// Per-(ppem, glyph_id) cache of packed hinted curves. Owned by `self
    /// .allocator`; cloned into the caller's allocator on each `hint()`
    /// hit. Lives until `evictPpem` / `clear` / `deinit`.
    glyph_cache: std.AutoHashMapUnmanaged(CachedGlyphKey, CachedGlyph),
    /// Per-(ppem, glyph_id) hinted-advance cache (and any future scalar
    /// metric). Always at least as populated as `glyph_cache` — full
    /// hint() always writes here, but advance-only queries write here
    /// without touching `glyph_cache`.
    metrics_cache: std.AutoHashMapUnmanaged(CachedGlyphKey, CachedMetrics),

    /// Inspect a font for hinting support. Returns `error.NoHinting` if the
    /// font has no `fpgm`/`prep`/`cvt` bytecode tables — the caller falls
    /// back to `font.extractCurves`.
    pub fn init(allocator: std.mem.Allocator, font: *const Font) !Hinter {
        const program = tt_vm.Program.init(font.inner.data) catch return error.NoHinting;
        return .{
            .allocator = allocator,
            .program = program,
            .machines = .{},
            .glyph_cache = .{},
            .metrics_cache = .{},
        };
    }

    pub fn deinit(self: *Hinter) void {
        self.clear();
        self.machines.deinit(self.allocator);
        self.glyph_cache.deinit(self.allocator);
        self.metrics_cache.deinit(self.allocator);
        self.* = undefined;
    }

    /// Drop the VM + glyph caches for one ppem. Curves already extracted
    /// into atlases keep working — the atlas owns its byte data, not the
    /// hinter.
    pub fn evictPpem(self: *Hinter, ppem: HintPpem) void {
        if (self.machines.fetchRemove(ppem)) |removed| {
            var slot = removed.value;
            deinitSlot(self.allocator, &slot);
        }
        // Drop every cached glyph at this ppem.
        var it = self.glyph_cache.iterator();
        var to_remove: std.ArrayListUnmanaged(CachedGlyphKey) = .empty;
        defer to_remove.deinit(self.allocator);
        while (it.next()) |entry| {
            if (entry.key_ptr.ppem_x_26_6 == ppem.x_26_6 and entry.key_ptr.ppem_y_26_6 == ppem.y_26_6) {
                to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }
        for (to_remove.items) |k| {
            if (self.glyph_cache.fetchRemove(k)) |r| {
                var v = r.value;
                v.deinit(self.allocator);
            }
        }
        var mit = self.metrics_cache.iterator();
        var metrics_to_remove: std.ArrayListUnmanaged(CachedGlyphKey) = .empty;
        defer metrics_to_remove.deinit(self.allocator);
        while (mit.next()) |entry| {
            if (entry.key_ptr.ppem_x_26_6 == ppem.x_26_6 and entry.key_ptr.ppem_y_26_6 == ppem.y_26_6) {
                metrics_to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }
        for (metrics_to_remove.items) |k| _ = self.metrics_cache.remove(k);
    }

    /// Drop every cached ppem. Same lifecycle guarantee as `evictPpem`.
    pub fn clear(self: *Hinter) void {
        var it = self.machines.iterator();
        while (it.next()) |entry| {
            var slot = entry.value_ptr.*;
            deinitSlot(self.allocator, &slot);
        }
        self.machines.clearRetainingCapacity();
        var git = self.glyph_cache.iterator();
        while (git.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.glyph_cache.clearRetainingCapacity();
        self.metrics_cache.clearRetainingCapacity();
    }

    /// Return the hinted horizontal advance for `glyph_id` at `ppem`, in
    /// 26.6 fixed-point pixels. Runs the TT VM on first call per
    /// (ppem, glyph_id) and caches; subsequent calls are a hashmap hit.
    /// Used by the HarfBuzz `glyph_h_advance` font_func.
    pub fn advanceX26Dot6(
        self: *Hinter,
        glyph_id: u16,
        ppem: HintPpem,
    ) HintError!i32 {
        const key = CachedGlyphKey{
            .ppem_x_26_6 = ppem.x_26_6,
            .ppem_y_26_6 = ppem.y_26_6,
            .glyph_id = glyph_id,
        };
        if (self.metrics_cache.get(key)) |m| return m.advance_x_26_6;
        const slot = try self.machineFor(ppem);
        const adv = try slot.machine.glyphAdvanceX26Dot6(&slot.topology, glyph_id);
        try self.metrics_cache.put(self.allocator, key, .{ .advance_x_26_6 = adv });
        return adv;
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
        const cache_key = CachedGlyphKey{
            .ppem_x_26_6 = ppem.x_26_6,
            .ppem_y_26_6 = ppem.y_26_6,
            .glyph_id = glyph_id,
        };
        if (self.glyph_cache.getPtr(cache_key)) |cached| {
            return cached.cloneInto(allocator);
        }

        const slot = try self.machineFor(ppem);
        const executed = try slot.machine.executeCachedGlyph(&slot.topology, glyph_id);
        // Populate the metrics cache up front so HB's `h_advance` callback
        // doesn't re-run the VM for any glyph we've already hinted.
        const adv_26_6 = try slot.machine.advanceX26Dot6FromExecuted(glyph_id, executed);
        try self.metrics_cache.put(self.allocator, cache_key, .{ .advance_x_26_6 = adv_26_6 });
        var hint_value = try slot.machine.buildGlyphHint(scratch, glyph_id, executed);
        defer hint_value.deinit();

        if (hint_value.curves.len == 0) {
            // Cache the empty result too — most font runs have at least one
            // empty glyph (space, NBSP) and we don't want to re-execute the
            // VM for it.
            try self.glyph_cache.put(self.allocator, cache_key, .{
                .curve_bytes = &.{},
                .band_bytes = &.{},
                .curve_count = 0,
                .h_band_count = 0,
                .v_band_count = 0,
                .band_scale_x = 0,
                .band_scale_y = 0,
                .band_offset_x = 0,
                .band_offset_y = 0,
                .bbox = .{ .min = .zero, .max = .zero },
            });
            return curves_mod.GlyphCurves.empty(allocator);
        }

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

        const band_bytes = bd.data;

        // Cache a hinter-owned copy so subsequent calls at the same
        // (ppem, glyph_id) hit the cache and skip the VM + texture build.
        const cached_curve_bytes = self.allocator.dupe(u16, curve_bytes) catch null;
        if (cached_curve_bytes) |c_bytes| {
            const cached_band_bytes = self.allocator.dupe(u16, band_bytes) catch {
                self.allocator.free(c_bytes);
                // Cache population failed; still return the freshly built
                // curves to the caller.
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
            };
            self.glyph_cache.put(self.allocator, cache_key, .{
                .curve_bytes = c_bytes,
                .band_bytes = cached_band_bytes,
                .curve_count = curve_count,
                .h_band_count = bd.h_band_count,
                .v_band_count = bd.v_band_count,
                .band_scale_x = bd.band_scale_x,
                .band_scale_y = bd.band_scale_y,
                .band_offset_x = bd.band_offset_x,
                .band_offset_y = bd.band_offset_y,
                .bbox = hint_value.bbox,
            }) catch {
                self.allocator.free(c_bytes);
                self.allocator.free(cached_band_bytes);
            };
        }

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
    const atlas_mod = @import("../atlas.zig");
    const record_key_mod = @import("../atlas/record_key.zig");

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

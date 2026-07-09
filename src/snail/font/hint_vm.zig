//! TrueType bytecode hinting wrapped as a `GlyphCurves` producer.
//!
//! `HintVm` is a PURE producer over an immutable per-ppem state:
//!
//!   var prepared = try vm.prepare(ppem);   // runs fpgm/prep once (expensive)
//!   const curves = try vm.hintGlyph(alloc, scratch, &prepared, glyph_id);
//!
//! `hintGlyph` is a function of `(prepared, glyph_id)` — a glyph program's
//! rare CVT/storage write is copy-on-write-scoped to the call, so `prepared`
//! is never mutated. That makes the output safe to memoize and lets the caller
//! own the `Prepared`-per-ppem cache (see `helpers.HintedGlyphCache`). The VM
//! itself holds no per-ppem state — only reusable per-font scratch and a
//! ppem-independent parsed-outline cache, both created lazily. This is the
//! deliberate absence of the "one justified exception" cache: hinting stays
//! pure, and the state that used to live here is now an explicit value.
//!
//! `HintVmStats` reports just the reusable scratch footprint + parsed-outline
//! count; per-ppem accounting belongs to whoever caches the `Prepared`s.
//!
//! Thread safety: not thread-safe (the reusable scratch is shared across
//! calls). Construct one `HintVm` per thread; `Prepared` values are immutable
//! and safe to hold, but hinting from one requires that thread's `HintVm`.

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
    /// Bytes held by the reusable per-font scratch (0 until first use).
    scratch_bytes: usize,
    /// Parsed glyph-outline entries in the ppem-independent topology cache.
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

pub const HintVm = struct {
    allocator: std.mem.Allocator,
    program: tt_vm.Program,
    /// Per-font reusable scratch + parsed-outline cache. Created lazily so the
    /// internal `*Program` binds to a stable `&self.program`. No per-ppem state
    /// lives here — that's `Prepared`, produced by `prepare` and owned (and
    /// cached) by the caller. So the VM is pure: `hintGlyph` is a function of
    /// `(prepared, glyph_id)`, and its output is safe to memoize.
    machine: ?*tt_hint.HintMachine = null,
    topology: ?*tt_hint.GlyphTopologyCache = null,

    /// Immutable per-ppem state (the fpgm/prep result). Cache one per ppem.
    pub const Prepared = tt_hint.Prepared;

    /// Inspect a font for hinting support. Returns `error.NoHinting` if the
    /// font has no `fpgm`/`prep`/`cvt` bytecode tables — the caller falls
    /// back to `font.extractCurves`.
    pub fn init(allocator: std.mem.Allocator, font: *const Font) !HintVm {
        const program = tt_vm.Program.init(font.inner.data) catch return error.NoHinting;
        return .{ .allocator = allocator, .program = program };
    }

    pub fn deinit(self: *HintVm) void {
        if (self.topology) |t| {
            t.deinit();
            self.allocator.destroy(t);
        }
        if (self.machine) |m| {
            m.deinit();
            self.allocator.destroy(m);
        }
        self.* = undefined;
    }

    fn ensureScratch(self: *HintVm) HintError!void {
        if (self.machine != null) return;
        const m = try self.allocator.create(tt_hint.HintMachine);
        errdefer self.allocator.destroy(m);
        m.* = try tt_hint.HintMachine.initForProgram(self.allocator, &self.program);
        errdefer m.deinit();
        const t = try self.allocator.create(tt_hint.GlyphTopologyCache);
        errdefer self.allocator.destroy(t);
        t.* = tt_hint.GlyphTopologyCache.initForProgram(self.allocator, &self.program);
        self.machine = m;
        self.topology = t;
    }

    /// Run fpgm/prep at `ppem` and return the immutable per-ppem state. The
    /// caller owns it — cache it and `deinit` it. Expensive (thousands of
    /// cycles); amortize by caching per ppem (see `helpers.HintedGlyphCache`).
    pub fn prepare(self: *HintVm, ppem: HintPpem) HintError!Prepared {
        try self.ensureScratch();
        return self.machine.?.prepare(self.allocator, .{ .x_26_6 = ppem.x_26_6, .y_26_6 = ppem.y_26_6 }, .{});
    }

    /// Hinted horizontal advance (26.6 px) for `glyph_id` from `prepared`.
    pub fn hintedAdvance(self: *HintVm, prepared: *const Prepared, glyph_id: u16) HintError!i32 {
        try self.ensureScratch();
        return self.machine.?.glyphAdvanceX26Dot6(prepared, self.topology.?, glyph_id);
    }

    /// Hint `glyph_id` from `prepared` and pack the result as `GlyphCurves`.
    /// Pure in `(prepared, glyph_id)` — the result is safe to memoize.
    ///
    /// `scratch` is used for VM-internal scratch state that does not need to
    /// outlive the call. The returned `GlyphCurves` is allocated from
    /// `allocator`.
    pub fn hintGlyph(
        self: *HintVm,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        prepared: *const Prepared,
        glyph_id: u16,
    ) HintError!curves_mod.GlyphCurves {
        try self.ensureScratch();
        const executed = try self.machine.?.executeCachedGlyph(prepared, self.topology.?, glyph_id);
        var hint_value = try self.machine.?.buildGlyphHint(scratch, glyph_id, executed);
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

    /// Footprint of the reusable scratch + parsed-outline cache (not the
    /// caller-owned `Prepared`s). For memory budgeting.
    pub fn stats(self: *const HintVm) HintVmStats {
        return .{
            .scratch_bytes = if (self.machine) |m| m.byteSize() else 0,
            .topology_glyph_count = if (self.topology) |t| @intCast(t.map.count()) else 0,
        };
    }
};

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
    for ([_]u32{ 8, 9, 10, 11, 12, 16 }) |px| {
        var prepared = try hinter.prepare(HintPpem.uniform(px * 64));
        defer prepared.deinit();
        for ("2amr0Hngoe13") |ch| {
            const gid = try font.glyphIndex(ch);
            var c = try hinter.hintGlyph(testing.allocator, testing.allocator, &prepared, gid);
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

    var prepared = try hinter.prepare(ppem);
    defer prepared.deinit();
    var curves = try hinter.hintGlyph(testing.allocator, testing.allocator, &prepared, glyph_id);
    defer curves.deinit();

    try testing.expect(curves.curve_count > 0);
    try testing.expect(curves.curve_bytes.len > 0);
    try testing.expect(curves.band_bytes.len > 0);
    try testing.expect(curves.h_band_count > 0);
}

test "HintVm is pure: one Prepared hints many glyphs, output is stable" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);

    var hinter = try HintVm.init(testing.allocator, &font);
    defer hinter.deinit();

    var prepared = try hinter.prepare(HintPpem.uniform(12 * 64));
    defer prepared.deinit();

    // Hinting 'A' then 'B' then 'A' again from the SAME const Prepared must be
    // deterministic — the second 'A' matches the first, proving no cross-glyph
    // state leaked (which is what makes the output safe to cache).
    var a0 = try hinter.hintGlyph(testing.allocator, testing.allocator, &prepared, try font.glyphIndex('A'));
    defer a0.deinit();
    var b0 = try hinter.hintGlyph(testing.allocator, testing.allocator, &prepared, try font.glyphIndex('B'));
    defer b0.deinit();
    var a1 = try hinter.hintGlyph(testing.allocator, testing.allocator, &prepared, try font.glyphIndex('A'));
    defer a1.deinit();

    try testing.expectEqual(a0.curve_count, a1.curve_count);
    try testing.expectEqualSlices(u16, a0.curve_bytes, a1.curve_bytes);
    try testing.expect(a0.curve_count != b0.curve_count or !std.mem.eql(u16, a0.curve_bytes, b0.curve_bytes));
    // The parsed-outline cache grew with the glyphs hinted (A, B).
    try testing.expectEqual(@as(u32, 2), hinter.stats().topology_glyph_count);
    try testing.expect(hinter.stats().scratch_bytes > 0);
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
    var prepared = try hinter.prepare(ppem);
    defer prepared.deinit();
    var curves = try hinter.hintGlyph(testing.allocator, testing.allocator, &prepared, gid);
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

const std = @import("std");
const builtin = @import("builtin");
const key_mod = @import("key.zig");
const value_mod = @import("value.zig");

pub const Key = key_mod.Key;
pub const RecordView = value_mod.RecordView;
pub const ValueView = value_mod.ValueView;
pub const OwnedRecord = value_mod.OwnedRecord;
pub const GeometryView = value_mod.GeometryView;
pub const FeatureZone = value_mod.FeatureZone;
pub const FeatureEdge = value_mod.FeatureEdge;

pub const format_version: u32 = 1;
const endian_tag: u32 = 0x0102_0304;
const alignment = 8;
const header_size = 64;
const record_size = 112;
const magic = "SNLPREP\x00";

const Header = struct {
    const magic_offset = 0;
    const version_offset = 8;
    const endian_offset = 12;
    const total_size_offset = 16;
    const record_count_offset = 24;
    const records_offset_offset = 28;
    const payload_offset_offset = 32;
};

const Record = struct {
    const key_offset = 0;
    const kind_offset = 32;
    const a_offset = 40;
    const a_count = 44;
    const b_offset = 48;
    const b_count = 52;
    const scalars = 56;
};

const Kind = enum(u32) {
    geometry = 1,
    autohint_model = 2,
    autohint_glyph = 3,
    tt_glyph = 4,
    tt_advance = 5,
};

/// `Archive.fromBytes` rejected the buffer: wrong endian, misaligned, a
/// structurally invalid archive, or an incompatible format version. Every one
/// of these is an ordinary cache miss — compatibility is intentionally exact.
pub const OpenError = error{
    UnsupportedEndian,
    Misaligned,
    InvalidArchive,
    VersionMismatch,
};

/// `ArchiveBuilder`/`finish*` failure: allocation, an invalid or oversized
/// record, or `ConflictingDuplicate` when the same key is added with different
/// content (adding identical content is idempotent).
pub const BuildError = std.mem.Allocator.Error || error{
    InvalidValue,
    InvalidCurves,
    ShapeTooLarge,
    ConflictingDuplicate,
    ArchiveTooLarge,
    BufferTooSmall,
    Misaligned,
    InvalidArchive,
    UnsupportedEndian,
    VersionMismatch,
};

fn readU32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}

fn readU64(bytes: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, bytes[offset..][0..8], .little);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}

fn writeU64(bytes: []u8, offset: usize, value: u64) void {
    std.mem.writeInt(u64, bytes[offset..][0..8], value, .little);
}

fn alignForward(value: usize) error{ArchiveTooLarge}!usize {
    return std.mem.alignForward(usize, value, alignment);
}

fn checkedByteLen(comptime T: type, count: u32) ?usize {
    return std.math.mul(usize, @sizeOf(T), count) catch null;
}

fn validRange(
    bytes: []const u8,
    payload_offset: usize,
    offset: u32,
    count: u32,
    comptime T: type,
) bool {
    if (count == 0) return offset == 0;
    const start: usize = offset;
    if (start < payload_offset or start % @alignOf(T) != 0) return false;
    const byte_len = checkedByteLen(T, count) orelse return false;
    const end = std.math.add(usize, start, byte_len) catch return false;
    return end <= bytes.len;
}

/// Immutable, non-owning view of a canonical prepared artifact archive.
///
/// `bytes` must remain alive and unchanged while this value or any record view
/// returned from it is used. The caller decides whether it came from mmap,
/// a read buffer, embedded data, or another transport.
pub const Archive = struct {
    bytes: []const u8,
    record_count: u32,
    records_offset: usize,
    payload_offset: usize,

    /// Validate the container without decoding or allocating artifact data.
    /// Artifact semantics are checked lazily by `RecordView.validate`.
    pub fn fromBytes(bytes: []const u8) OpenError!Archive {
        if (comptime builtin.target.cpu.arch.endian() != .little)
            return error.UnsupportedEndian;
        if (bytes.len < header_size) return error.InvalidArchive;
        if (@intFromPtr(bytes.ptr) % alignment != 0) return error.Misaligned;
        if (!std.mem.eql(u8, bytes[Header.magic_offset..][0..magic.len], magic))
            return error.InvalidArchive;
        if (readU32(bytes, Header.version_offset) != format_version)
            return error.VersionMismatch;
        if (readU32(bytes, Header.endian_offset) != endian_tag)
            return error.UnsupportedEndian;
        const total_size = readU64(bytes, Header.total_size_offset);
        if (total_size != bytes.len or total_size > std.math.maxInt(usize))
            return error.InvalidArchive;

        const record_count = readU32(bytes, Header.record_count_offset);
        const records_offset = readU32(bytes, Header.records_offset_offset);
        const payload_offset = readU32(bytes, Header.payload_offset_offset);
        if (records_offset != header_size or records_offset % alignment != 0 or
            payload_offset % alignment != 0 or payload_offset > bytes.len)
            return error.InvalidArchive;
        const table_bytes = std.math.mul(usize, record_count, record_size) catch
            return error.InvalidArchive;
        const table_end = std.math.add(usize, records_offset, table_bytes) catch
            return error.InvalidArchive;
        if (table_end > bytes.len or payload_offset < table_end)
            return error.InvalidArchive;

        var previous: ?Key = null;
        for (0..record_count) |index| {
            const base = @as(usize, records_offset) + index * record_size;
            var key: Key = undefined;
            @memcpy(&key.value, bytes[base + Record.key_offset ..][0..32]);
            if (previous) |prev| {
                if (prev.order(key) != .lt) return error.InvalidArchive;
            }
            previous = key;

            const raw_kind = readU32(bytes, base + Record.kind_offset);
            const kind = std.enums.fromInt(Kind, raw_kind) orelse
                return error.InvalidArchive;
            // Reserved word and unused tail must be canonical zero.
            if (readU32(bytes, base + 36) != 0) return error.InvalidArchive;
            for (base + Record.scalars + 14 * 4..base + record_size) |byte_index| {
                if (bytes[byte_index] != 0) return error.InvalidArchive;
            }
            const a_offset = readU32(bytes, base + Record.a_offset);
            const a_count = readU32(bytes, base + Record.a_count);
            const b_offset = readU32(bytes, base + Record.b_offset);
            const b_count = readU32(bytes, base + Record.b_count);
            switch (kind) {
                .geometry, .tt_glyph => {
                    if (!validRange(bytes, payload_offset, a_offset, a_count, u16) or
                        !validRange(bytes, payload_offset, b_offset, b_count, u16))
                        return error.InvalidArchive;
                    if (readU32(bytes, base + Record.scalars + 0 * 4) > std.math.maxInt(u16) or
                        readU32(bytes, base + Record.scalars + 3 * 4) > std.math.maxInt(u16) or
                        readU32(bytes, base + Record.scalars + 4 * 4) > std.math.maxInt(u16))
                        return error.InvalidArchive;
                    _ = std.enums.fromInt(
                        @import("../format/curve_texture.zig").Encoding,
                        readU32(bytes, base + Record.scalars + 1 * 4),
                    ) orelse return error.InvalidArchive;
                    _ = std.enums.fromInt(
                        @import("../format/abi.zig").PathCurveClass,
                        readU32(bytes, base + Record.scalars + 2 * 4),
                    ) orelse return error.InvalidArchive;
                },
                .autohint_model => {
                    if (!validRange(bytes, payload_offset, a_offset, a_count, FeatureZone) or
                        b_offset != 0 or b_count != 0)
                        return error.InvalidArchive;
                },
                .autohint_glyph => {
                    if (!validRange(bytes, payload_offset, a_offset, a_count, FeatureEdge) or
                        !validRange(bytes, payload_offset, b_offset, b_count, FeatureEdge))
                        return error.InvalidArchive;
                },
                .tt_advance => {
                    if (a_offset != 0 or a_count != 0 or b_offset != 0 or b_count != 0)
                        return error.InvalidArchive;
                },
            }
        }

        return .{
            .bytes = bytes,
            .record_count = record_count,
            .records_offset = records_offset,
            .payload_offset = payload_offset,
        };
    }

    pub fn len(self: Archive) usize {
        return self.record_count;
    }

    pub fn find(self: *const Archive, key: Key) ?RecordView {
        var low: usize = 0;
        var high: usize = self.record_count;
        while (low < high) {
            const mid = low + (high - low) / 2;
            const candidate = self.keyAt(mid);
            switch (candidate.order(key)) {
                .lt => low = mid + 1,
                .gt => high = mid,
                .eq => return self.recordAt(mid),
            }
        }
        return null;
    }

    pub fn iterator(self: *const Archive) Iterator {
        return .{ .archive = self };
    }

    pub const Iterator = struct {
        archive: *const Archive,
        index: usize = 0,

        pub fn next(self: *Iterator) ?RecordView {
            if (self.index >= self.archive.record_count) return null;
            defer self.index += 1;
            return self.archive.recordAt(self.index);
        }
    };

    fn baseAt(self: Archive, index: usize) usize {
        return self.records_offset + index * record_size;
    }

    fn keyAt(self: Archive, index: usize) Key {
        const base = self.baseAt(index);
        var result: Key = undefined;
        @memcpy(&result.value, self.bytes[base + Record.key_offset ..][0..32]);
        return result;
    }

    fn typedSlice(
        self: Archive,
        comptime T: type,
        offset: u32,
        count: u32,
    ) []const T {
        if (count == 0) return &.{};
        const pointer: [*]const T = @ptrCast(@alignCast(self.bytes.ptr + offset));
        return pointer[0..count];
    }

    fn scalar(self: Archive, base: usize, index: usize) u32 {
        return readU32(self.bytes, base + Record.scalars + index * 4);
    }

    fn geometryAt(self: Archive, base: usize) GeometryView {
        const a_offset = readU32(self.bytes, base + Record.a_offset);
        const a_count = readU32(self.bytes, base + Record.a_count);
        const b_offset = readU32(self.bytes, base + Record.b_offset);
        const b_count = readU32(self.bytes, base + Record.b_count);
        return .{
            .curve_words = self.typedSlice(u16, a_offset, a_count),
            .band_words = self.typedSlice(u16, b_offset, b_count),
            .curve_count = @intCast(self.scalar(base, 0)),
            .encoding = @enumFromInt(self.scalar(base, 1)),
            .path_curve_class = @enumFromInt(self.scalar(base, 2)),
            .h_band_count = @intCast(self.scalar(base, 3)),
            .v_band_count = @intCast(self.scalar(base, 4)),
            .band_scale_x = @bitCast(self.scalar(base, 5)),
            .band_scale_y = @bitCast(self.scalar(base, 6)),
            .band_offset_x = @bitCast(self.scalar(base, 7)),
            .band_offset_y = @bitCast(self.scalar(base, 8)),
            .bbox = .{
                .min = .{
                    .x = @bitCast(self.scalar(base, 9)),
                    .y = @bitCast(self.scalar(base, 10)),
                },
                .max = .{
                    .x = @bitCast(self.scalar(base, 11)),
                    .y = @bitCast(self.scalar(base, 12)),
                },
            },
        };
    }

    fn recordAt(self: Archive, index: usize) RecordView {
        const base = self.baseAt(index);
        const kind: Kind = @enumFromInt(readU32(self.bytes, base + Record.kind_offset));
        const a_offset = readU32(self.bytes, base + Record.a_offset);
        const a_count = readU32(self.bytes, base + Record.a_count);
        const b_offset = readU32(self.bytes, base + Record.b_offset);
        const b_count = readU32(self.bytes, base + Record.b_count);
        const value: ValueView = switch (kind) {
            .geometry => .{ .geometry = self.geometryAt(base) },
            .autohint_model => .{ .autohint_model = .{
                .blues = self.typedSlice(FeatureZone, a_offset, a_count),
                .std_x = @bitCast(self.scalar(base, 0)),
                .std_y = @bitCast(self.scalar(base, 1)),
            } },
            .autohint_glyph => .{ .autohint_glyph = .{
                .x = self.typedSlice(FeatureEdge, a_offset, a_count),
                .y = self.typedSlice(FeatureEdge, b_offset, b_count),
                .left = @bitCast(self.scalar(base, 0)),
            } },
            .tt_glyph => .{ .tt_glyph = .{
                .geometry = self.geometryAt(base),
                .advance_x_26_6 = @bitCast(self.scalar(base, 13)),
            } },
            .tt_advance => .{ .tt_advance = @bitCast(self.scalar(base, 0)) },
        };
        return .{ .key = self.keyAt(index), .value = value };
    }
};

/// Accumulates prepared records and emits a canonical `Archive`. Owns a copy of
/// every added value, sorts by key, and is idempotent on duplicate keys with
/// matching content. `finishInto` writes into caller-owned aligned storage;
/// `finishAlloc` returns an `OwnedArchive`.
pub const ArchiveBuilder = struct {
    allocator: std.mem.Allocator,
    records: std.ArrayList(OwnedRecord) = .empty,

    pub fn init(allocator: std.mem.Allocator) ArchiveBuilder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ArchiveBuilder) void {
        for (self.records.items) |*record| record.deinit();
        self.records.deinit(self.allocator);
        self.* = undefined;
    }

    /// Add a producer artifact. Equal key + equal value is idempotent; equal
    /// key + different value is rejected instead of silently poisoning cache
    /// identity.
    pub fn add(self: *ArchiveBuilder, record: RecordView) BuildError!void {
        record.validate() catch |err| return err;
        for (self.records.items) |*existing| {
            if (!existing.key.eql(record.key)) continue;
            if (!valueEql(existing.value.view(), record.value))
                return error.ConflictingDuplicate;
            return;
        }
        var cloned = try OwnedRecord.clone(self.allocator, record);
        errdefer cloned.deinit();
        try self.records.append(self.allocator, cloned);
    }

    pub fn requiredSize(self: *const ArchiveBuilder) BuildError!usize {
        var size = try alignForward(header_size + try checkedMul(
            self.records.items.len,
            record_size,
        ));
        for (self.records.items) |*record| {
            const value = record.value.view();
            const sizes = payloadSizes(value);
            if (sizes[0] != 0) size = try alignForward(try checkedAdd(size, sizes[0]));
            if (sizes[1] != 0) size = try alignForward(try checkedAdd(size, sizes[1]));
        }
        if (size > std.math.maxInt(u32)) return error.ArchiveTooLarge;
        return size;
    }

    pub fn finishInto(
        self: *ArchiveBuilder,
        destination: []u8,
    ) BuildError!Archive {
        if (comptime builtin.target.cpu.arch.endian() != .little)
            return error.UnsupportedEndian;
        if (@intFromPtr(destination.ptr) % alignment != 0) return error.Misaligned;
        const required = try self.requiredSize();
        if (destination.len < required) return error.BufferTooSmall;
        const bytes = destination[0..required];
        @memset(bytes, 0);
        std.mem.sort(OwnedRecord, self.records.items, {}, struct {
            fn lessThan(_: void, a: OwnedRecord, b: OwnedRecord) bool {
                return a.key.order(b.key) == .lt;
            }
        }.lessThan);

        @memcpy(bytes[Header.magic_offset..][0..magic.len], magic);
        writeU32(bytes, Header.version_offset, format_version);
        writeU32(bytes, Header.endian_offset, endian_tag);
        writeU64(bytes, Header.total_size_offset, required);
        writeU32(bytes, Header.record_count_offset, @intCast(self.records.items.len));
        writeU32(bytes, Header.records_offset_offset, header_size);
        const payload_start = try alignForward(header_size + self.records.items.len * record_size);
        writeU32(bytes, Header.payload_offset_offset, @intCast(payload_start));

        var cursor = payload_start;
        for (self.records.items, 0..) |*owned, index| {
            const base = header_size + index * record_size;
            const record = owned.view();
            @memcpy(bytes[base + Record.key_offset ..][0..32], &record.key.value);
            const kind: Kind = switch (record.value) {
                .geometry => .geometry,
                .autohint_model => .autohint_model,
                .autohint_glyph => .autohint_glyph,
                .tt_glyph => .tt_glyph,
                .tt_advance => .tt_advance,
            };
            writeU32(bytes, base + Record.kind_offset, @intFromEnum(kind));

            switch (record.value) {
                .geometry => |geometry| writeGeometry(bytes, base, &cursor, geometry, null),
                .autohint_model => |model| {
                    writeBlock(FeatureZone, bytes, base + Record.a_offset, base + Record.a_count, &cursor, model.blues);
                    writeU32(bytes, base + Record.scalars + 0 * 4, @bitCast(model.std_x));
                    writeU32(bytes, base + Record.scalars + 1 * 4, @bitCast(model.std_y));
                },
                .autohint_glyph => |glyph| {
                    writeBlock(FeatureEdge, bytes, base + Record.a_offset, base + Record.a_count, &cursor, glyph.x);
                    writeBlock(FeatureEdge, bytes, base + Record.b_offset, base + Record.b_count, &cursor, glyph.y);
                    writeU32(bytes, base + Record.scalars, @bitCast(glyph.left));
                },
                .tt_glyph => |glyph| writeGeometry(
                    bytes,
                    base,
                    &cursor,
                    glyph.geometry,
                    glyph.advance_x_26_6,
                ),
                .tt_advance => |advance| {
                    writeU32(bytes, base + Record.scalars, @bitCast(advance));
                },
            }
        }
        std.debug.assert(cursor == required);
        return Archive.fromBytes(bytes);
    }

    pub fn finishAlloc(
        self: *ArchiveBuilder,
        allocator: std.mem.Allocator,
    ) BuildError!OwnedArchive {
        const size = try self.requiredSize();
        const bytes = try allocator.alignedAlloc(u8, .@"8", size);
        errdefer allocator.free(bytes);
        const archive = try self.finishInto(bytes);
        return .{ .allocator = allocator, .storage = bytes, .archive = archive };
    }
};

/// An `Archive` plus the aligned byte storage it borrows, allocated together by
/// `ArchiveBuilder.finishAlloc`. `view()` yields the `Archive`; `bytes()` the
/// persistable buffer. `deinit` frees the storage, so keep it alive as long as
/// any view derived from it is in use.
pub const OwnedArchive = struct {
    allocator: std.mem.Allocator,
    storage: []align(8) u8,
    archive: Archive,

    pub fn view(self: *const OwnedArchive) Archive {
        return self.archive;
    }

    pub fn bytes(self: *const OwnedArchive) []const u8 {
        return self.storage;
    }

    pub fn deinit(self: *OwnedArchive) void {
        self.allocator.free(self.storage);
        self.* = undefined;
    }
};

fn checkedAdd(a: usize, b: usize) error{ArchiveTooLarge}!usize {
    return std.math.add(usize, a, b) catch error.ArchiveTooLarge;
}

fn checkedMul(a: usize, b: usize) error{ArchiveTooLarge}!usize {
    return std.math.mul(usize, a, b) catch error.ArchiveTooLarge;
}

fn payloadSizes(value: ValueView) [2]usize {
    return switch (value) {
        .geometry => |geometry| .{
            geometry.curve_words.len * @sizeOf(u16),
            geometry.band_words.len * @sizeOf(u16),
        },
        .autohint_model => |model| .{
            model.blues.len * @sizeOf(FeatureZone),
            0,
        },
        .autohint_glyph => |glyph| .{
            glyph.x.len * @sizeOf(FeatureEdge),
            glyph.y.len * @sizeOf(FeatureEdge),
        },
        .tt_glyph => |glyph| .{
            glyph.geometry.curve_words.len * @sizeOf(u16),
            glyph.geometry.band_words.len * @sizeOf(u16),
        },
        .tt_advance => .{ 0, 0 },
    };
}

fn writeBlock(
    comptime T: type,
    bytes: []u8,
    offset_field: usize,
    count_field: usize,
    cursor: *usize,
    source: []const T,
) void {
    if (source.len == 0) return;
    writeU32(bytes, offset_field, @intCast(cursor.*));
    writeU32(bytes, count_field, @intCast(source.len));
    const source_bytes = std.mem.sliceAsBytes(source);
    @memcpy(bytes[cursor.*..][0..source_bytes.len], source_bytes);
    cursor.* = std.mem.alignForward(usize, cursor.* + source_bytes.len, alignment);
}

fn writeGeometry(
    bytes: []u8,
    base: usize,
    cursor: *usize,
    geometry: GeometryView,
    advance: ?i32,
) void {
    writeBlock(u16, bytes, base + Record.a_offset, base + Record.a_count, cursor, geometry.curve_words);
    writeBlock(u16, bytes, base + Record.b_offset, base + Record.b_count, cursor, geometry.band_words);
    const values = [_]u32{
        geometry.curve_count,
        @intFromEnum(geometry.encoding),
        @intFromEnum(geometry.path_curve_class),
        geometry.h_band_count,
        geometry.v_band_count,
        @bitCast(geometry.band_scale_x),
        @bitCast(geometry.band_scale_y),
        @bitCast(geometry.band_offset_x),
        @bitCast(geometry.band_offset_y),
        @bitCast(geometry.bbox.min.x),
        @bitCast(geometry.bbox.min.y),
        @bitCast(geometry.bbox.max.x),
        @bitCast(geometry.bbox.max.y),
        if (advance) |value| @bitCast(value) else 0,
    };
    for (values, 0..) |value, index|
        writeU32(bytes, base + Record.scalars + index * 4, value);
}

fn floatEql(a: f32, b: f32) bool {
    return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
}

fn geometryEql(a: GeometryView, b: GeometryView) bool {
    return std.mem.eql(u16, a.curve_words, b.curve_words) and
        std.mem.eql(u16, a.band_words, b.band_words) and
        a.curve_count == b.curve_count and a.encoding == b.encoding and
        a.path_curve_class == b.path_curve_class and
        a.h_band_count == b.h_band_count and a.v_band_count == b.v_band_count and
        floatEql(a.band_scale_x, b.band_scale_x) and
        floatEql(a.band_scale_y, b.band_scale_y) and
        floatEql(a.band_offset_x, b.band_offset_x) and
        floatEql(a.band_offset_y, b.band_offset_y) and
        floatEql(a.bbox.min.x, b.bbox.min.x) and
        floatEql(a.bbox.min.y, b.bbox.min.y) and
        floatEql(a.bbox.max.x, b.bbox.max.x) and
        floatEql(a.bbox.max.y, b.bbox.max.y);
}

fn valueEql(a: ValueView, b: ValueView) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .geometry => |av| geometryEql(av, b.geometry),
        .autohint_model => |av| std.mem.eql(
            u8,
            std.mem.sliceAsBytes(av.blues),
            std.mem.sliceAsBytes(b.autohint_model.blues),
        ) and floatEql(av.std_x, b.autohint_model.std_x) and
            floatEql(av.std_y, b.autohint_model.std_y),
        .autohint_glyph => |av| std.mem.eql(
            u8,
            std.mem.sliceAsBytes(av.x),
            std.mem.sliceAsBytes(b.autohint_glyph.x),
        ) and std.mem.eql(
            u8,
            std.mem.sliceAsBytes(av.y),
            std.mem.sliceAsBytes(b.autohint_glyph.y),
        ) and floatEql(av.left, b.autohint_glyph.left),
        .tt_glyph => |av| geometryEql(av.geometry, b.tt_glyph.geometry) and
            av.advance_x_26_6 == b.tt_glyph.advance_x_26_6,
        .tt_advance => |av| av == b.tt_advance,
    };
}

fn testKey(byte: u8) Key {
    return .{ .value = [_]u8{byte} ** 32 };
}

fn testEmptyGeometry() GeometryView {
    return .{
        .curve_words = &.{},
        .band_words = &.{},
        .curve_count = 0,
        .encoding = .dense_quadratic,
        .path_curve_class = .quadratic,
        .h_band_count = 0,
        .v_band_count = 0,
        .band_scale_x = 0,
        .band_scale_y = 0,
        .band_offset_x = 0,
        .band_offset_y = 0,
        .bbox = .{ .min = .zero, .max = .zero },
    };
}

test "archive roundtrip is zero-copy, sorted, and deterministic" {
    const allocator = std.testing.allocator;
    const zones = [_]FeatureZone{
        .{ .ref = 0, .shoot = -0.01 },
        .{ .ref = 0.7, .shoot = 0.71 },
    };
    const records = [_]RecordView{
        .{ .key = testKey(0x30), .value = .{ .tt_advance = 640 } },
        .{ .key = testKey(0x10), .value = .{ .geometry = testEmptyGeometry() } },
        .{ .key = testKey(0x20), .value = .{ .autohint_model = .{
            .blues = &zones,
            .std_x = 0.08,
            .std_y = 0.09,
        } } },
        .{ .key = testKey(0x40), .value = .{ .autohint_glyph = .{
            .x = &.{},
            .y = &.{},
            .left = -0.02,
        } } },
        .{ .key = testKey(0x50), .value = .{ .tt_glyph = .{
            .geometry = testEmptyGeometry(),
            .advance_x_26_6 = 700,
        } } },
    };

    var a = ArchiveBuilder.init(allocator);
    defer a.deinit();
    for (records) |record| try a.add(record);
    var archive_a = try a.finishAlloc(allocator);
    defer archive_a.deinit();

    var b = ArchiveBuilder.init(allocator);
    defer b.deinit();
    var reverse = records;
    std.mem.reverse(RecordView, &reverse);
    for (reverse) |record| try b.add(record);
    var archive_b = try b.finishAlloc(allocator);
    defer archive_b.deinit();

    try std.testing.expectEqualSlices(u8, archive_a.bytes(), archive_b.bytes());

    const view = archive_a.view();
    try std.testing.expectEqual(@as(usize, records.len), view.len());
    const model = view.find(testKey(0x20)).?.value.autohint_model;
    try std.testing.expectEqual(@as(usize, 2), model.blues.len);
    try std.testing.expectEqual(@as(f32, 0.7), model.blues[1].ref);
    try std.testing.expectEqual(
        @as(f32, -0.02),
        view.find(testKey(0x40)).?.value.autohint_glyph.left,
    );
    try std.testing.expectEqual(
        @as(i32, 700),
        view.find(testKey(0x50)).?.value.tt_glyph.advance_x_26_6,
    );
    const bytes_start = @intFromPtr(archive_a.bytes().ptr);
    const bytes_end = bytes_start + archive_a.bytes().len;
    const zones_pointer = @intFromPtr(model.blues.ptr);
    try std.testing.expect(zones_pointer >= bytes_start and zones_pointer < bytes_end);

    var iterator = view.iterator();
    try std.testing.expect(iterator.next().?.key.eql(testKey(0x10)));
    try std.testing.expect(iterator.next().?.key.eql(testKey(0x20)));
    try std.testing.expect(iterator.next().?.key.eql(testKey(0x30)));
    try std.testing.expect(iterator.next().?.key.eql(testKey(0x40)));
    try std.testing.expect(iterator.next().?.key.eql(testKey(0x50)));
    try std.testing.expect(iterator.next() == null);
}

test "archive views borrow caller-retained mmap-like bytes" {
    const allocator = std.testing.allocator;
    var builder = ArchiveBuilder.init(allocator);
    try builder.add(.{ .key = testKey(1), .value = .{ .tt_advance = 321 } });
    var first = try builder.finishAlloc(allocator);
    const mapped = try allocator.alignedAlloc(u8, .@"8", first.bytes().len);
    defer allocator.free(mapped);
    @memcpy(mapped, first.bytes());
    first.deinit();
    builder.deinit();

    const archive = try Archive.fromBytes(mapped);
    try std.testing.expectEqual(@as(i32, 321), archive.find(testKey(1)).?.value.tt_advance);
}

test "archive duplicate identity is idempotent but conflicting content fails" {
    var builder = ArchiveBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const key = testKey(9);
    try builder.add(.{ .key = key, .value = .{ .tt_advance = 1 } });
    try builder.add(.{ .key = key, .value = .{ .tt_advance = 1 } });
    try std.testing.expectEqual(@as(usize, 1), builder.records.items.len);
    try std.testing.expectError(
        error.ConflictingDuplicate,
        builder.add(.{ .key = key, .value = .{ .tt_advance = 2 } }),
    );
}

test "archive rejects hostile container structure" {
    const allocator = std.testing.allocator;
    var builder = ArchiveBuilder.init(allocator);
    defer builder.deinit();
    try builder.add(.{ .key = testKey(1), .value = .{ .tt_advance = 1 } });
    try builder.add(.{ .key = testKey(2), .value = .{ .tt_advance = 2 } });
    var owned = try builder.finishAlloc(allocator);
    defer owned.deinit();

    try std.testing.expectError(error.InvalidArchive, Archive.fromBytes(owned.bytes()[0..20]));

    const scratch = try allocator.alignedAlloc(u8, .@"8", owned.bytes().len);
    defer allocator.free(scratch);

    @memcpy(scratch, owned.bytes());
    scratch[0] ^= 1;
    try std.testing.expectError(error.InvalidArchive, Archive.fromBytes(scratch));

    @memcpy(scratch, owned.bytes());
    writeU32(scratch, Header.version_offset, format_version + 1);
    try std.testing.expectError(error.VersionMismatch, Archive.fromBytes(scratch));

    @memcpy(scratch, owned.bytes());
    writeU32(scratch, Header.endian_offset, 0x0403_0201);
    try std.testing.expectError(error.UnsupportedEndian, Archive.fromBytes(scratch));

    @memcpy(scratch, owned.bytes());
    writeU64(scratch, Header.total_size_offset, scratch.len + 1);
    try std.testing.expectError(error.InvalidArchive, Archive.fromBytes(scratch));

    @memcpy(scratch, owned.bytes());
    writeU32(scratch, header_size + Record.kind_offset, 0xffff_ffff);
    try std.testing.expectError(error.InvalidArchive, Archive.fromBytes(scratch));

    @memcpy(scratch, owned.bytes());
    // Duplicate keys violate the archive's strict canonical ordering.
    @memcpy(
        scratch[header_size + record_size + Record.key_offset ..][0..32],
        scratch[header_size + Record.key_offset ..][0..32],
    );
    try std.testing.expectError(error.InvalidArchive, Archive.fromBytes(scratch));

    @memcpy(scratch, owned.bytes());
    writeU32(scratch, Header.record_count_offset, std.math.maxInt(u32));
    try std.testing.expectError(error.InvalidArchive, Archive.fromBytes(scratch));

    // A valid archive starting one byte into an allocation is still rejected:
    // zero-copy typed views require an aligned base.
    const unaligned = try allocator.alloc(u8, owned.bytes().len + 1);
    defer allocator.free(unaligned);
    @memcpy(unaligned[1..], owned.bytes());
    try std.testing.expectError(error.Misaligned, Archive.fromBytes(unaligned[1..]));
}

test "archive validates ranges eagerly and artifact semantics lazily" {
    const allocator = std.testing.allocator;
    var builder = ArchiveBuilder.init(allocator);
    defer builder.deinit();
    try builder.add(.{ .key = testKey(1), .value = .{ .geometry = testEmptyGeometry() } });
    var owned = try builder.finishAlloc(allocator);
    defer owned.deinit();

    const scratch = try allocator.alignedAlloc(u8, .@"8", owned.bytes().len);
    defer allocator.free(scratch);

    // Make the empty geometry claim one u16 beyond the archive.
    @memcpy(scratch, owned.bytes());
    writeU32(scratch, header_size + Record.a_offset, @intCast(scratch.len));
    writeU32(scratch, header_size + Record.a_count, 1);
    try std.testing.expectError(error.InvalidArchive, Archive.fromBytes(scratch));

    // NaN geometry metadata is structurally sound, but rejected only when the
    // consumer asks to validate the artifact.
    @memcpy(scratch, owned.bytes());
    writeU32(scratch, header_size + Record.scalars + 5 * 4, 0x7fc0_0000);
    const archive = try Archive.fromBytes(scratch);
    try std.testing.expectError(
        error.InvalidCurves,
        archive.find(testKey(1)).?.validate(),
    );
}

const std = @import("std");
const generated = @import("c_api_generated");

pub const SnailAllocFn = *const fn (ctx: ?*anyopaque, size: usize, alignment: usize) callconv(.c) ?[*]u8;
pub const SnailFreeFn = *const fn (ctx: ?*anyopaque, ptr: ?[*]u8, size: usize, alignment: usize) callconv(.c) void;

pub const SnailAllocator = extern struct {
    alloc_fn: SnailAllocFn,
    free_fn: SnailFreeFn,
    ctx: ?*anyopaque,
};

pub const SNAIL_OK = generated.SNAIL_OK;
pub const SNAIL_ERR_INVALID_FONT = generated.SNAIL_ERR_INVALID_FONT;
pub const SNAIL_ERR_OUT_OF_MEMORY = generated.SNAIL_ERR_OUT_OF_MEMORY;
pub const SNAIL_ERR_RENDERER_FAILED = generated.SNAIL_ERR_RENDERER_FAILED;
pub const SNAIL_ERR_INVALID_ARGUMENT = generated.SNAIL_ERR_INVALID_ARGUMENT;
pub const SNAIL_ERR_DRAW_FAILED = generated.SNAIL_ERR_DRAW_FAILED;
pub const SNAIL_ERR_HINT_UNAVAILABLE = generated.SNAIL_ERR_HINT_UNAVAILABLE;

fn toZigAllocator(ca: *const SnailAllocator) std.mem.Allocator {
    const S = struct {
        fn alloc(ctx_ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
            const ca_inner: *const SnailAllocator = @ptrCast(@alignCast(ctx_ptr));
            return ca_inner.alloc_fn(ca_inner.ctx, len, alignment.toByteUnits());
        }
        fn free(ctx_ptr: *anyopaque, buf: []u8, alignment: std.mem.Alignment, _: usize) void {
            const ca_inner: *const SnailAllocator = @ptrCast(@alignCast(ctx_ptr));
            ca_inner.free_fn(ca_inner.ctx, buf.ptr, buf.len, alignment.toByteUnits());
        }
        fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
            return false;
        }
        fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
            return null;
        }
    };
    return .{
        .ptr = @ptrCast(@constCast(ca)),
        .vtable = &.{ .alloc = S.alloc, .resize = S.resize, .remap = S.remap, .free = S.free },
    };
}

fn libcAlloc(_: ?*anyopaque, size: usize, _: usize) callconv(.c) ?[*]u8 {
    return @ptrCast(std.c.malloc(size) orelse return null);
}

fn libcFree(_: ?*anyopaque, ptr: ?[*]u8, _: usize, _: usize) callconv(.c) void {
    if (ptr) |p| std.c.free(p);
}

pub const default_c_allocator = SnailAllocator{
    .alloc_fn = &libcAlloc,
    .free_fn = &libcFree,
    .ctx = null,
};

pub const StoredAllocator = struct {
    ref_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    inner: SnailAllocator,

    pub fn init(ca: ?*const SnailAllocator) StoredAllocator {
        return .{ .inner = if (ca) |a| a.* else default_c_allocator };
    }

    pub fn allocator(self: *const StoredAllocator) std.mem.Allocator {
        return toZigAllocator(&self.*.inner);
    }
};

pub fn createStoredAllocator(ca: ?*const SnailAllocator) !*StoredAllocator {
    const stored = StoredAllocator.init(ca);
    const allocator = stored.allocator();
    const ptr = try allocator.create(StoredAllocator);
    ptr.* = stored;
    return ptr;
}

pub fn destroyStoredAllocator(ptr: *StoredAllocator) void {
    if (ptr.ref_count.fetchSub(1, .acq_rel) != 1) return;
    const stored = ptr.*;
    const allocator = stored.allocator();
    allocator.destroy(ptr);
}

pub fn retainStoredAllocator(ptr: *StoredAllocator) *StoredAllocator {
    _ = ptr.ref_count.fetchAdd(1, .monotonic);
    return ptr;
}

/// Adapter for temporary allocations that are fully released before the export
/// returns. Owned handles should use StoredAllocator instead.
pub fn resolveAllocator(ca: ?*const SnailAllocator) std.mem.Allocator {
    if (ca) |a| return toZigAllocator(a);
    return toZigAllocator(&default_c_allocator);
}

pub fn mapError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => SNAIL_ERR_OUT_OF_MEMORY,
        error.InvalidFont, error.NoFaces, error.MissingCellMetricsGlyph => SNAIL_ERR_INVALID_FONT,
        error.UnsupportedRenderer => SNAIL_ERR_RENDERER_FAILED,
        error.HintUnavailable,
        error.NoTrueTypeProgram,
        => SNAIL_ERR_HINT_UNAVAILABLE,
        error.InvalidEnum,
        error.InvalidArgument,
        error.InvalidFaceIndex,
        error.WrongTextAtlasSnapshot,
        error.MissingPreparedGlyph,
        error.UnsupportedTextPaint,
        error.InvalidShapeMark,
        error.InvalidShapeRange,
        error.InvalidGlyphRange,
        error.InvalidOverrideIndex,
        error.InvalidTransform,
        error.InvalidImageData,
        error.InvalidHintDeltaCount,
        error.EmptyHintedGlyph,
        error.PathMissingMoveTo,
        error.EmptyPath,
        error.EmptyStyle,
        error.ResourceManifestFull,
        error.DrawListFull,
        error.ResourceUploadPlanFull,
        error.ResourceUploadBudgetExceeded,
        error.ResourceCacheRebuildRequired,
        error.ResourceUploadNotReady,
        error.MissingUploadCommand,
        error.InvalidRetirementFence,
        => SNAIL_ERR_INVALID_ARGUMENT,
        error.MissingPreparedResource,
        error.StaleDrawRecords,
        error.StalePreparedResources,
        error.InvalidResolve,
        error.UnsupportedResolve,
        => SNAIL_ERR_DRAW_FAILED,
        else => SNAIL_ERR_DRAW_FAILED,
    };
}

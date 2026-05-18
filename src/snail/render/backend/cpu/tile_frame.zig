const snail = @import("../../../root.zig");

pub fn Context(comptime Renderer: type) type {
    return struct {
        self: *const Renderer,
        backend_prepared: ?*const anyopaque,
        records: snail.DrawRecords,
        options: snail.DrawOptions,
    };
}

pub fn callback(comptime Renderer: type, comptime tile_rows: u32) *const fn (*anyopaque, u32) void {
    return struct {
        fn run(opaque_ctx: *anyopaque, tile_index: u32) void {
            const ctx: *const Context(Renderer) = @ptrCast(@alignCast(opaque_ctx));
            var tile_renderer = ctx.self.*;
            tile_renderer.thread_pool = null;
            const tile_min = ctx.self.row_clip_min + tile_index * tile_rows;
            tile_renderer.row_clip_min = tile_min;
            tile_renderer.row_clip_max = @min(tile_min + tile_rows, ctx.self.row_clip_max);

            var renderer = tile_renderer.asRenderer();
            renderer.iterateRecords(ctx.records, ctx.options, ctx.backend_prepared) catch unreachable;
        }
    }.run;
}

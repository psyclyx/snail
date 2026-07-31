//! Synchronous executor for demos and tests.
//!
//! It drives the public plan/request/result/apply lifecycle locally; production
//! callers can replace the loop with archive lookups and their own scheduler.

const std = @import("std");
const snail = @import("snail");

pub fn run(
    allocator: std.mem.Allocator,
    atlas: *snail.Atlas,
    sources: []const snail.FontSource,
    shaped_runs: []const *const snail.ShapedText,
    mode: snail.PrepareMode,
) !void {
    var plan = try snail.planRuns(atlas, allocator, sources, shaped_runs, mode);
    defer plan.deinit();
    const owned = try allocator.alloc(?snail.prepared.OwnedRecord, plan.requests().len);
    defer allocator.free(owned);
    @memset(owned, null);
    defer for (owned) |*record| if (record.*) |*value| value.deinit();
    const results = try allocator.alloc(?snail.prepared.RecordView, plan.requests().len);
    defer allocator.free(results);
    @memset(results, null);

    var outlines = snail.OutlineContext.init(allocator, allocator);
    defer outlines.deinit();
    const AutoSlot = struct { context: snail.AutohintContext };
    const auto_slots = try allocator.alloc(?AutoSlot, sources.len);
    defer allocator.free(auto_slots);
    @memset(auto_slots, null);
    defer for (auto_slots) |*slot| if (slot.*) |*value| value.context.deinit();
    const TtSlot = struct {
        context: snail.TtHintContext,
        size: snail.TtHintSize,
    };
    const tt_slots = try allocator.alloc(?TtSlot, sources.len);
    defer allocator.free(tt_slots);
    @memset(tt_slots, null);
    defer for (tt_slots) |*slot| if (slot.*) |*value| {
        value.size.deinit();
        value.context.deinit();
    };

    for (plan.requests(), 0..) |request, request_index| {
        const source_index = switch (request.operation) {
            inline else => |operation| indexOfSource(sources, operation.source),
        };
        const record = switch (request.operation) {
            .outline => try outlines.prepare(request),
            .autohint_model => |operation| blk: {
                if (auto_slots[source_index] == null) {
                    auto_slots[source_index] = .{ .context = try .init(
                        allocator,
                        allocator,
                        operation.source,
                        operation.options,
                    ) };
                }
                break :blk try auto_slots[source_index].?.context.prepare(request);
            },
            .autohint_glyph => |operation| blk: {
                if (auto_slots[source_index] == null) {
                    const dependencies = plan.dependencies(request_index);
                    if (dependencies.len != 1) return error.InvalidPreparePlan;
                    auto_slots[source_index] = .{ .context = try .initWithModel(
                        allocator,
                        allocator,
                        operation.source,
                        operation.options,
                        results[dependencies[0]].?.value.autohint_model,
                    ) };
                }
                break :blk try auto_slots[source_index].?.context.prepare(request);
            },
            .tt_glyph => |operation| blk: {
                if (tt_slots[source_index] == null) {
                    var context = try snail.TtHintContext.init(
                        allocator,
                        allocator,
                        operation.source,
                    );
                    errdefer context.deinit();
                    tt_slots[source_index] = .{
                        .size = try context.prepareSize(operation.ppem),
                        .context = context,
                    };
                }
                break :blk try tt_slots[source_index].?.context.prepare(
                    &tt_slots[source_index].?.size,
                    request,
                );
            },
            .tt_advance => |operation| blk: {
                if (tt_slots[source_index] == null) {
                    var context = try snail.TtHintContext.init(
                        allocator,
                        allocator,
                        operation.source,
                    );
                    errdefer context.deinit();
                    tt_slots[source_index] = .{
                        .size = try context.prepareSize(operation.ppem),
                        .context = context,
                    };
                }
                break :blk try tt_slots[source_index].?.context.prepare(
                    &tt_slots[source_index].?.size,
                    request,
                );
            },
        };
        owned[request_index] = record;
        results[request_index] = owned[request_index].?.view();
    }
    try plan.applyInPlace(allocator, atlas, results);
}

fn indexOfSource(
    sources: []const snail.FontSource,
    source: *const snail.FontSource,
) usize {
    for (sources, 0..) |*candidate, index| {
        if (candidate.font_id == source.font_id) return index;
    }
    unreachable;
}

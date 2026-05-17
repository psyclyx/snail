const std = @import("std");

const coverage_mod = @import("../../coverage.zig");
const draw_mod = @import("../../draw.zig");
const interface = @import("../interface.zig");
const prepared_mod = @import("../../resources/prepared.zig");
const target_mod = @import("../../target.zig");
const upload_mod = @import("../../upload.zig");
const upload_plan = @import("../upload_plan.zig");
const vec = @import("../../math/vec.zig");

const CoverageTransfer = target_mod.CoverageTransfer;
const CoverageBackend = coverage_mod.Backend;
const DrawOptions = draw_mod.DrawOptions;
const DrawRecords = draw_mod.DrawRecords;
const FillRule = target_mod.FillRule;
const Mat4 = vec.Mat4;
const PreparedResources = prepared_mod.PreparedResources;
const Resolve = target_mod.Resolve;
const ResourceCacheStats = upload_mod.ResourceCacheStats;
const ResourceUploadBatch = upload_mod.ResourceUploadBatch;
const SubpixelOrder = target_mod.SubpixelOrder;
const TargetEncoding = target_mod.TargetEncoding;
const UploadAllocators = upload_mod.UploadAllocators;

pub fn vtable(comptime Config: type) interface.Renderer.VTable {
    const Backend = Config.Backend;
    const Prepared = Config.Prepared;
    const S = struct {
        fn cast(ptr: *anyopaque) *Backend {
            return @ptrCast(@alignCast(ptr));
        }
        fn constCast(ptr: *anyopaque) *const Backend {
            return @ptrCast(@alignCast(ptr));
        }
        fn constCastConst(ptr: *const anyopaque) *const Backend {
            return @ptrCast(@alignCast(ptr));
        }
        fn activeLayerInfo(cache: *const Prepared) bool {
            if (comptime @hasField(Prepared, "layer_info_tex")) return cache.layer_info_tex != 0;
            if (comptime @hasField(Prepared, "layer_image")) return cache.layer_image != null;
            return false;
        }
        fn deinitFn(_: *anyopaque) void {}
        fn uploadResourcesFn(ptr: *anyopaque, allocators: UploadAllocators, prepared: *PreparedResources, batch: ResourceUploadBatch) anyerror!void {
            return Config.uploadResources(cast(ptr), allocators, prepared, batch);
        }
        fn coverageBackendFn(ptr: *anyopaque, prepared: *const PreparedResources) ?CoverageBackend {
            return Config.coverageBackend(cast(ptr), prepared);
        }
        fn drawTextFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, mvp: Mat4, vw: f32, vh: f32, texture_layer_base: u32) void {
            if (prepared) |backend_prepared| {
                const typed: *const Prepared = @ptrCast(@alignCast(backend_prepared));
                cast(ptr).drawTextPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                return;
            }
            std.debug.panic("drawText requires PreparedResources ({*}, {d}, {d}, {d}, {d})", .{ ptr, verts.len, mvp.data[0], vw, vh });
        }
        fn drawPathsFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, mvp: Mat4, vw: f32, vh: f32, texture_layer_base: u32) void {
            if (prepared) |backend_prepared| {
                const typed: *const Prepared = @ptrCast(@alignCast(backend_prepared));
                cast(ptr).drawPathsPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                return;
            }
            std.debug.panic("drawPaths requires PreparedResources ({*}, {d}, {d}, {d}, {d})", .{ ptr, verts.len, mvp.data[0], vw, vh });
        }
        fn beginFrameFn(ptr: *anyopaque) void {
            cast(ptr).beginFrame();
        }
        fn setSubpixelOrderFn(ptr: *anyopaque, order: SubpixelOrder) void {
            cast(ptr).setSubpixelOrder(order);
        }
        fn getSubpixelOrderFn(ptr: *anyopaque) SubpixelOrder {
            return constCast(ptr).getSubpixelOrder();
        }
        fn setFillRuleFn(ptr: *anyopaque, rule: FillRule) void {
            cast(ptr).setFillRule(rule);
        }
        fn getFillRuleFn(ptr: *anyopaque) FillRule {
            return constCast(ptr).getFillRule();
        }
        fn setTargetEncodingFn(ptr: *anyopaque, encoding: TargetEncoding) void {
            cast(ptr).setTargetEncoding(encoding);
        }
        fn getTargetEncodingFn(ptr: *anyopaque) TargetEncoding {
            return constCast(ptr).getTargetEncoding();
        }
        fn setResolveFn(ptr: *anyopaque, next_resolve: Resolve) void {
            cast(ptr).setResolve(next_resolve);
        }
        fn getResolveFn(ptr: *anyopaque) Resolve {
            return constCast(ptr).getResolve();
        }
        fn setCoverageTransferFn(ptr: *anyopaque, transfer: CoverageTransfer) void {
            cast(ptr).setCoverageTransfer(transfer);
        }
        fn getCoverageTransferFn(ptr: *anyopaque) CoverageTransfer {
            return constCast(ptr).getCoverageTransfer();
        }
        fn resourceCacheStatsFn(ptr: *const anyopaque) ResourceCacheStats {
            if (comptime Config.uses_resource_cache) return constCastConst(ptr).resourceCacheStats();
            return .{};
        }
        fn resetResourceCacheFn(ptr: *anyopaque) void {
            if (comptime Config.uses_resource_cache) cast(ptr).resetResourceCache();
        }
        fn validateBackendGenerationFn(prepared_resources: *const PreparedResources) anyerror!void {
            if (comptime !Config.uses_resource_cache) return;
            const cache = Config.prepared(prepared_resources) orelse return error.MissingPreparedResource;
            if (cache.generation != prepared_resources.backend.generation) return error.StalePreparedResources;
        }
        fn atlasSlotCanOverflowIntoBankFn(prepared_resources: *const PreparedResources, index: usize, atlas: upload_plan.AtlasRef) bool {
            if (comptime !Config.uses_resource_cache) return false;
            if (atlas.has_layer_info_or_images) return false;
            const cache = Config.prepared(prepared_resources) orelse return false;
            if (activeLayerInfo(cache) or index >= cache.atlas_slot_count) return false;
            return upload_plan.atlasSlotCanOverflowIntoBank(cache.atlas_slots[index], atlas);
        }
        fn atlasNeedsOverflowBankFn(prepared_resources: *const PreparedResources, index: usize, atlas: upload_plan.AtlasRef) bool {
            if (comptime !Config.uses_resource_cache) return false;
            if (atlas.has_layer_info_or_images) return false;
            const cache = Config.prepared(prepared_resources) orelse return false;
            if (activeLayerInfo(cache) or index >= cache.atlas_slot_count) return false;
            return upload_plan.atlasSlotNeedsOverflowBank(
                cache.atlas_slots[index],
                cache.allocated_curve_height,
                cache.allocated_band_height,
                atlas,
            );
        }
        fn atlasWouldRebuildFn(prepared_resources: *const PreparedResources, index: usize, atlas: upload_plan.AtlasRef) bool {
            if (comptime !Config.uses_resource_cache) return false;
            const cache = Config.prepared(prepared_resources) orelse return false;
            if (index >= cache.atlas_slot_count) return true;
            if (!atlas.has_layer_info_or_images and
                !activeLayerInfo(cache) and
                upload_plan.atlasSlotCanOverflowIntoBank(cache.atlas_slots[index], atlas))
            {
                return false;
            }
            return upload_plan.atlasSlotWouldRebuild(
                cache.atlas_slots[index],
                cache.allocated_curve_height,
                cache.allocated_band_height,
                atlas,
            );
        }
        fn canUseAtlasOverflowBanksFn(prepared_resources: *const PreparedResources, atlas_count: usize) bool {
            if (comptime !Config.uses_resource_cache) return false;
            const cache = Config.prepared(prepared_resources) orelse return false;
            return !activeLayerInfo(cache) and cache.atlas_slot_count == atlas_count;
        }
        fn backendNameFn(ptr: *anyopaque) []const u8 {
            return constCast(ptr).backendName();
        }
        fn drawFn(renderer: *interface.Renderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) anyerror!void {
            return Config.draw(renderer, prepared, records, options);
        }
    };
    return .{
        .backend = Config.backend_kind,
        .deinit = &S.deinitFn,
        .uploadResources = &S.uploadResourcesFn,
        .coverageBackend = &S.coverageBackendFn,
        .draw = &S.drawFn,
        .drawText = &S.drawTextFn,
        .drawPaths = &S.drawPathsFn,
        .beginFrame = &S.beginFrameFn,
        .setSubpixelOrder = &S.setSubpixelOrderFn,
        .getSubpixelOrder = &S.getSubpixelOrderFn,
        .setFillRule = &S.setFillRuleFn,
        .getFillRule = &S.getFillRuleFn,
        .setTargetEncoding = &S.setTargetEncodingFn,
        .getTargetEncoding = &S.getTargetEncodingFn,
        .setResolve = &S.setResolveFn,
        .getResolve = &S.getResolveFn,
        .setCoverageTransfer = &S.setCoverageTransferFn,
        .getCoverageTransfer = &S.getCoverageTransferFn,
        .resource_cache = .{
            .uses_resource_cache = Config.uses_resource_cache,
            .stats = &S.resourceCacheStatsFn,
            .reset = &S.resetResourceCacheFn,
            .validateBackendGeneration = &S.validateBackendGenerationFn,
            .atlasSlotCanOverflowIntoBank = &S.atlasSlotCanOverflowIntoBankFn,
            .atlasNeedsOverflowBank = &S.atlasNeedsOverflowBankFn,
            .atlasWouldRebuild = &S.atlasWouldRebuildFn,
            .canUseAtlasOverflowBanks = &S.canUseAtlasOverflowBanksFn,
        },
        .backendName = &S.backendNameFn,
    };
}

const std = @import("std");

const coverage_mod = @import("../../coverage.zig");
const draw_mod = @import("../../draw.zig");
const interface = @import("../interface.zig");
const prepared_mod = @import("../../resources/prepared.zig");
const upload_mod = @import("../../upload.zig");
const upload_plan = @import("../upload_plan.zig");

const CoverageBackend = coverage_mod.Backend;
const DrawState = draw_mod.DrawState;
const DrawRecords = draw_mod.DrawRecords;
const PreparedResources = prepared_mod.PreparedResources;
const ResourceCacheStats = upload_mod.ResourceCacheStats;
const ResourceUploadBatch = upload_mod.ResourceUploadBatch;
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
        fn drawTextFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, state: DrawState, texture_layer_base: u32) anyerror!void {
            if (prepared) |backend_prepared| {
                const typed: *const Prepared = @ptrCast(@alignCast(backend_prepared));
                try cast(ptr).drawTextPrepared(typed, verts, state, texture_layer_base);
                return;
            }
            return error.MissingPreparedResource;
        }
        fn drawPathsFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, state: DrawState, texture_layer_base: u32) anyerror!void {
            if (prepared) |backend_prepared| {
                const typed: *const Prepared = @ptrCast(@alignCast(backend_prepared));
                try cast(ptr).drawPathsPrepared(typed, verts, state, texture_layer_base);
                return;
            }
            return error.MissingPreparedResource;
        }
        fn beginDrawFn(ptr: *anyopaque) void {
            cast(ptr).beginDraw();
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
        fn imageArrayWouldRebuildFn(prepared_resources: *const PreparedResources, capacity_count: u32, capacity_width: u32, capacity_height: u32) bool {
            if (comptime !Config.uses_resource_cache) return false;
            const cache = Config.prepared(prepared_resources) orelse return false;
            const has_active_image_array = if (comptime @hasField(Prepared, "image_array"))
                cache.image_array != 0
            else if (comptime @hasField(Prepared, "image_image"))
                cache.image_image != null
            else
                false;
            if (!has_active_image_array or capacity_count == 0) return false;
            return capacity_count > cache.allocated_image_count or
                capacity_width > cache.allocated_image_width or
                capacity_height > cache.allocated_image_height;
        }
        fn backendNameFn(ptr: *anyopaque) []const u8 {
            return constCast(ptr).backendName();
        }
        fn drawFn(renderer: *interface.Renderer, prepared: *const PreparedResources, records: DrawRecords, state: DrawState) anyerror!void {
            return Config.draw(renderer, prepared, records, state);
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
        .beginDraw = &S.beginDrawFn,
        .resource_cache = .{
            .uses_resource_cache = Config.uses_resource_cache,
            .stats = &S.resourceCacheStatsFn,
            .reset = &S.resetResourceCacheFn,
            .validateBackendGeneration = &S.validateBackendGenerationFn,
            .atlasSlotCanOverflowIntoBank = &S.atlasSlotCanOverflowIntoBankFn,
            .atlasNeedsOverflowBank = &S.atlasNeedsOverflowBankFn,
            .atlasWouldRebuild = &S.atlasWouldRebuildFn,
            .canUseAtlasOverflowBanks = &S.canUseAtlasOverflowBanksFn,
            .imageArrayWouldRebuild = &S.imageArrayWouldRebuildFn,
        },
        .backendName = &S.backendNameFn,
    };
}

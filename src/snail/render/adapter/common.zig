const coverage_mod = @import("../../coverage.zig");
const draw_mod = @import("../../draw.zig");
const interface = @import("../interface.zig");
const prepared_mod = @import("../../resources/prepared.zig");
const upload_mod = @import("../../upload.zig");
const upload_plan = @import("../upload_plan.zig");

const CoverageBackend = coverage_mod.Backend;
const DrawPass = draw_mod.DrawPass;
const DrawState = draw_mod.DrawState;
const DrawRecords = draw_mod.DrawRecords;
const PreparedResources = prepared_mod.PreparedResources;
const ResourceCacheStats = upload_mod.ResourceCacheStats;
const ResourceUploadBatch = upload_mod.ResourceUploadBatch;
const UploadAllocators = upload_mod.UploadAllocators;

pub fn vtable(comptime Config: type) interface.Renderer.VTable {
    const S = struct {
        fn deinitFn(_: *anyopaque) void {}
        fn backendNameFn(ptr: *anyopaque) []const u8 {
            return constCast(Config.Backend, ptr).backendName();
        }
    };
    return .{
        .backend = Config.backend_kind,
        .deinit = &S.deinitFn,
        .upload = uploadVTable(Config),
        .coverage = coverageVTable(Config),
        .draw = drawVTable(Config),
        .resource_cache = resourceCacheVTable(Config),
        .backendName = &S.backendNameFn,
    };
}

fn uploadVTable(comptime Config: type) interface.Renderer.UploadVTable {
    const S = struct {
        fn uploadResourcesFn(ptr: *anyopaque, allocators: UploadAllocators, prepared: *PreparedResources, batch: ResourceUploadBatch) anyerror!void {
            return Config.uploadResources(cast(Config.Backend, ptr), allocators, prepared, batch);
        }
    };
    return .{ .uploadResources = &S.uploadResourcesFn };
}

fn coverageVTable(comptime Config: type) interface.Renderer.CoverageVTable {
    const S = struct {
        fn coverageBackendFn(ptr: *anyopaque, prepared: *const PreparedResources) ?CoverageBackend {
            return Config.coverageBackend(cast(Config.Backend, ptr), prepared);
        }
    };
    return .{ .coverageBackend = &S.coverageBackendFn };
}

fn drawVTable(comptime Config: type) interface.Renderer.DrawVTable {
    const S = struct {
        fn drawFn(renderer: *interface.Renderer, prepared: *const PreparedResources, records: DrawRecords, state: DrawState) anyerror!void {
            return Config.draw(renderer, prepared, records, state);
        }

        fn drawPassFn(renderer: *interface.Renderer, prepared: *const PreparedResources, records: DrawRecords, pass: DrawPass) anyerror!void {
            if (comptime @hasDecl(Config, "drawPass")) {
                return Config.drawPass(renderer, prepared, records, pass);
            }
            return switch (pass.resolve) {
                .direct => Config.draw(renderer, prepared, records, pass.state),
                .linear => error.UnsupportedResolve,
            };
        }

        fn drawTextFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, state: DrawState, texture_layer_base: u32) anyerror!void {
            const backend_prepared = prepared orelse return error.MissingPreparedResource;
            const typed: *const Config.Prepared = @ptrCast(@alignCast(backend_prepared));
            try cast(Config.Backend, ptr).drawTextPrepared(typed, verts, state, texture_layer_base);
        }

        fn drawPathsFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, state: DrawState, texture_layer_base: u32) anyerror!void {
            const backend_prepared = prepared orelse return error.MissingPreparedResource;
            const typed: *const Config.Prepared = @ptrCast(@alignCast(backend_prepared));
            try cast(Config.Backend, ptr).drawPathsPrepared(typed, verts, state, texture_layer_base);
        }

        fn beginDrawFn(ptr: *anyopaque) void {
            cast(Config.Backend, ptr).beginDraw();
        }
    };
    return .{
        .draw = &S.drawFn,
        .drawPass = &S.drawPassFn,
        .drawText = &S.drawTextFn,
        .drawPaths = &S.drawPathsFn,
        .beginDraw = &S.beginDrawFn,
    };
}

fn resourceCacheVTable(comptime Config: type) interface.Renderer.ResourceCacheVTable {
    const S = struct {
        fn resourceCacheStatsFn(ptr: *const anyopaque) ResourceCacheStats {
            if (comptime Config.uses_resource_cache) return constCastConst(Config.Backend, ptr).resourceCacheStats();
            return .{};
        }

        fn resetResourceCacheFn(ptr: *anyopaque) void {
            if (comptime Config.uses_resource_cache) cast(Config.Backend, ptr).resetResourceCache();
        }

        fn validateBackendGenerationFn(prepared_resources: *const PreparedResources) anyerror!void {
            if (comptime !Config.uses_resource_cache) return;
            const cache = Config.prepared(prepared_resources) orelse return error.MissingPreparedResource;
            if (cache.generation != prepared_resources.resident.generation) return error.StalePreparedResources;
        }

        fn atlasCacheStatusFn(prepared_resources: *const PreparedResources, index: usize, atlas: upload_plan.AtlasRef) upload_plan.AtlasCacheStatus {
            if (comptime !Config.uses_resource_cache) return .{};
            const cache = Config.prepared(prepared_resources) orelse return .{};
            if (index >= cache.atlas_slot_count) return .{ .would_rebuild = true };
            return atlasCacheStatus(Config.Prepared, cache, index, atlas);
        }

        fn canUseAtlasOverflowBanksFn(prepared_resources: *const PreparedResources, atlas_count: usize) bool {
            if (comptime !Config.uses_resource_cache) return false;
            const cache = Config.prepared(prepared_resources) orelse return false;
            return !activeLayerInfo(Config.Prepared, cache) and cache.atlas_slot_count == atlas_count;
        }

        fn imageArrayWouldRebuildFn(prepared_resources: *const PreparedResources, capacity_count: u32, capacity_width: u32, capacity_height: u32) bool {
            if (comptime !Config.uses_resource_cache) return false;
            const cache = Config.prepared(prepared_resources) orelse return false;
            if (!hasActiveImageArray(Config.Prepared, cache) or capacity_count == 0) return false;
            return capacity_count > cache.allocated_image_count or
                capacity_width > cache.allocated_image_width or
                capacity_height > cache.allocated_image_height;
        }
    };
    return .{
        .uses_resource_cache = Config.uses_resource_cache,
        .stats = &S.resourceCacheStatsFn,
        .reset = &S.resetResourceCacheFn,
        .validateBackendGeneration = &S.validateBackendGenerationFn,
        .atlasCacheStatus = &S.atlasCacheStatusFn,
        .canUseAtlasOverflowBanks = &S.canUseAtlasOverflowBanksFn,
        .imageArrayWouldRebuild = &S.imageArrayWouldRebuildFn,
    };
}

fn atlasCacheStatus(comptime Prepared: type, cache: *const Prepared, index: usize, atlas: upload_plan.AtlasRef) upload_plan.AtlasCacheStatus {
    const can_overflow = !atlas.has_layer_info_or_images and
        !activeLayerInfo(Prepared, cache) and
        upload_plan.atlasSlotCanOverflowIntoBank(cache.atlas_slots[index], atlas);
    const needs_overflow = can_overflow and upload_plan.atlasSlotNeedsOverflowBank(
        cache.atlas_slots[index],
        cache.allocated_curve_height,
        cache.allocated_band_height,
        atlas,
    );
    const would_rebuild = upload_plan.atlasSlotWouldRebuild(
        cache.atlas_slots[index],
        cache.allocated_curve_height,
        cache.allocated_band_height,
        atlas,
    );
    return .{
        .can_overflow_into_bank = can_overflow,
        .needs_overflow_bank = needs_overflow,
        .would_rebuild = if (can_overflow) false else would_rebuild,
    };
}

fn activeLayerInfo(comptime Prepared: type, cache: *const Prepared) bool {
    if (comptime @hasField(Prepared, "layer_info_tex")) return cache.layer_info_tex != 0;
    if (comptime @hasField(Prepared, "layer_image")) return cache.layer_image != null;
    return false;
}

fn hasActiveImageArray(comptime Prepared: type, cache: *const Prepared) bool {
    if (comptime @hasField(Prepared, "image_array")) return cache.image_array != 0;
    if (comptime @hasField(Prepared, "image_image")) return cache.image_image != null;
    return false;
}

fn cast(comptime Backend: type, ptr: *anyopaque) *Backend {
    return @ptrCast(@alignCast(ptr));
}

fn constCast(comptime Backend: type, ptr: *anyopaque) *const Backend {
    return @ptrCast(@alignCast(ptr));
}

fn constCastConst(comptime Backend: type, ptr: *const anyopaque) *const Backend {
    return @ptrCast(@alignCast(ptr));
}

const std = @import("std");
const gl = @import("bindings.zig").gl;
const gl_backend = @import("backend.zig");
const gl_texture_params = @import("texture_params.zig");
const subpixel_policy = @import("../subpixel_policy.zig");
const atlas_curve_mod = @import("../../format/atlas/curve.zig");
const atlas_page_mod = @import("../../format/atlas/page.zig");
const texture_layers = @import("../../format/texture_layers.zig");
const upload_common = @import("../../format/upload_common.zig");
const snail_mod = @import("../../../root.zig");
const SubpixelOrder = @import("../../format/subpixel_order.zig").SubpixelOrder;

pub const Backend = gl_backend.Backend;
const FillRule = snail_mod.FillRule;
const CoverageTransfer = snail_mod.CoverageTransfer;
const setImageTexParams = gl_texture_params.setImageTexParams;
const setImageTexParamsDSA = gl_texture_params.setImageTexParamsDSA;
const setTexParams = gl_texture_params.setTexParams;
const setTexParamsDSA = gl_texture_params.setTexParamsDSA;

pub const TextCoverageProgram = struct {
    curve_tex_loc: gl.GLint = -1,
    band_tex_loc: gl.GLint = -1,
    layer_tex_loc: gl.GLint = -1,
    image_tex_loc: gl.GLint = -1,
    fill_rule_loc: gl.GLint = -1,
    subpixel_order_loc: gl.GLint = -1,
    output_srgb_loc: gl.GLint = -1,
    coverage_exponent_loc: gl.GLint = -1,
    layer_base_loc: gl.GLint = -1,
    curve_tex_unit: gl.GLint = 0,
    band_tex_unit: gl.GLint = 1,
    layer_tex_unit: gl.GLint = 2,
    image_tex_unit: gl.GLint = 3,
};

pub const TextCoverageDrawState = struct {
    fill_rule: FillRule = .non_zero,
    subpixel_order: SubpixelOrder = .none,
    output_srgb: bool = false,
    coverage_transfer: CoverageTransfer = .identity,
    layer_base: u32 = 0,
};

pub const CurveAtlas = atlas_curve_mod.CurveAtlas;
pub const AtlasPage = atlas_page_mod.AtlasPage;
pub const AtlasSlot = upload_common.AtlasSlot(CurveAtlas, AtlasPage);
pub const ImageSlot = upload_common.ImageSlot(snail_mod.Image);

pub fn atlasPagesInBank(slots: []const AtlasSlot, bank_id: u32) u32 {
    var total: u32 = 0;
    for (slots) |slot| {
        const layer_count = @min(slot.uploaded_pages, slot.page_layers.len);
        if (layer_count == 0 and bank_id == 0) {
            total += slot.uploaded_pages;
            continue;
        }
        for (slot.page_layers[0..layer_count]) |layer| {
            if (texture_layers.bank(layer) == bank_id) total += 1;
        }
    }
    return total;
}

pub const AtlasTextureBank = struct {
    id: u32 = 0,
    curve_array: gl.GLuint = 0,
    band_array: gl.GLuint = 0,
    layer_info_tex: gl.GLuint = 0,
    image_array: gl.GLuint = 0,
    allocated_layer_count: u32 = 0,
    allocated_image_count: u32 = 0,
    resident_atlas_pages: u32 = 0,
    resident_image_layers: u32 = 0,
    generation: u64 = 0,
    prepared_refs: u32 = 0,

    fn hasAny(self: *const AtlasTextureBank) bool {
        return self.curve_array != 0 or
            self.band_array != 0 or
            self.layer_info_tex != 0 or
            self.image_array != 0;
    }

    fn deinit(self: *AtlasTextureBank) void {
        if (self.curve_array != 0) gl.glDeleteTextures(1, &self.curve_array);
        if (self.band_array != 0) gl.glDeleteTextures(1, &self.band_array);
        if (self.layer_info_tex != 0) gl.glDeleteTextures(1, &self.layer_info_tex);
        if (self.image_array != 0) gl.glDeleteTextures(1, &self.image_array);
        self.* = .{};
    }
};

pub const PreparedResources = struct {
    allocator: std.mem.Allocator,
    backend: Backend,
    active_atlas_bank_id: u32 = 0,
    active_atlas_bank_refs: u32 = 0,
    next_atlas_bank_id: u32 = 1,
    curve_array: gl.GLuint = 0,
    band_array: gl.GLuint = 0,
    layer_info_tex: gl.GLuint = 0,
    image_array: gl.GLuint = 0,
    atlas_banks: []AtlasTextureBank = &.{},
    atlas_bank_count: usize = 0,
    atlas_slots: []AtlasSlot = &.{},
    atlas_slot_count: usize = 0,
    allocated_curve_height: u32 = 0,
    allocated_band_height: u32 = 0,
    allocated_layer_count: u32 = 0,
    atlas_has_special_text_runs: bool = false,
    image_slots: []ImageSlot = &.{},
    image_slot_count: usize = 0,
    allocated_image_width: u32 = 0,
    allocated_image_height: u32 = 0,
    allocated_image_count: u32 = 0,
    generation: u64 = 0,

    pub fn deinit(self: *PreparedResources) void {
        self.destroyAtlasTextureResources();
        self.destroyImageResources();
        self.resetAtlasUploadState();
        self.destroyRetainedBanks();
    }

    fn destroyAtlasTextureResources(self: *PreparedResources) void {
        const had_resources = self.curve_array != 0 or self.band_array != 0 or self.layer_info_tex != 0;
        if (self.curve_array != 0) gl.glDeleteTextures(1, &self.curve_array);
        if (self.band_array != 0) gl.glDeleteTextures(1, &self.band_array);
        if (self.layer_info_tex != 0) gl.glDeleteTextures(1, &self.layer_info_tex);
        self.curve_array = 0;
        self.band_array = 0;
        self.layer_info_tex = 0;
        if (had_resources) {
            self.generation +%= 1;
            self.active_atlas_bank_refs = 0;
        }
    }

    fn destroyImageResources(self: *PreparedResources) void {
        const had_resources = self.image_array != 0;
        if (self.image_array != 0) gl.glDeleteTextures(1, &self.image_array);
        self.image_array = 0;
        self.resetImageUploadState();
        if (had_resources) {
            self.generation +%= 1;
            self.active_atlas_bank_refs = 0;
        }
    }

    fn resetImageUploadState(self: *PreparedResources) void {
        self.image_slot_count = 0;
        self.allocated_image_width = 0;
        self.allocated_image_height = 0;
        self.allocated_image_count = 0;
        if (self.image_slots.len > 0) self.allocator.free(self.image_slots);
        self.image_slots = &.{};
    }

    fn destroyRetainedBanks(self: *PreparedResources) void {
        for (self.atlas_banks[0..self.atlas_bank_count]) |*bank| bank.deinit();
        if (self.atlas_banks.len > 0) self.allocator.free(self.atlas_banks);
        self.atlas_banks = &.{};
        self.atlas_bank_count = 0;
    }

    pub fn retainPreparedResources(self: *PreparedResources, manifest: anytype, generation: u64) void {
        for (manifest.atlases) |entry| self.retainAtlasViewBanks(entry.view, generation);
    }

    pub fn releasePreparedResources(self: *PreparedResources, manifest: anytype, generation: u64) void {
        for (manifest.atlases) |entry| self.releaseAtlasViewBanks(entry.view, generation);
        self.pruneReleasedRetainedBanks();
    }

    fn retainAtlasViewBanks(self: *PreparedResources, view: anytype, generation: u64) void {
        for (view.page_layers) |layer| self.retainPreparedBankId(texture_layers.bank(layer), generation);
    }

    fn releaseAtlasViewBanks(self: *PreparedResources, view: anytype, generation: u64) void {
        for (view.page_layers) |layer| self.releasePreparedBankId(texture_layers.bank(layer), generation);
    }

    fn retainPreparedBankId(self: *PreparedResources, bank_id: u32, generation: u64) void {
        if (generation == self.generation and bank_id == self.active_atlas_bank_id) {
            self.active_atlas_bank_refs += 1;
            return;
        }
        const bank = self.retainedBankForId(bank_id, generation) orelse return;
        bank.prepared_refs += 1;
    }

    fn releasePreparedBankId(self: *PreparedResources, bank_id: u32, generation: u64) void {
        if (generation == self.generation and bank_id == self.active_atlas_bank_id) {
            if (self.active_atlas_bank_refs > 0) self.active_atlas_bank_refs -= 1;
            return;
        }
        const bank = self.retainedBankForId(bank_id, generation) orelse return;
        if (bank.prepared_refs > 0) bank.prepared_refs -= 1;
    }

    fn retainedBankForId(self: *PreparedResources, bank_id: u32, generation: u64) ?*AtlasTextureBank {
        for (self.atlas_banks[0..self.atlas_bank_count]) |*bank| {
            if (bank.id == bank_id and bank.generation == generation) return bank;
        }
        return null;
    }

    fn bankIsCurrentAtlasState(self: *const PreparedResources, bank: *const AtlasTextureBank) bool {
        if (bank.generation != self.generation) return false;
        if (bank.id == self.active_atlas_bank_id) return true;
        return atlasPagesInBank(self.atlas_slots[0..self.atlas_slot_count], bank.id) > 0;
    }

    fn pruneReleasedRetainedBanks(self: *PreparedResources) void {
        var write: usize = 0;
        var read: usize = 0;
        const old_count = self.atlas_bank_count;
        while (read < old_count) : (read += 1) {
            if (self.atlas_banks[read].prepared_refs == 0 and !self.bankIsCurrentAtlasState(&self.atlas_banks[read])) {
                self.atlas_banks[read].deinit();
                continue;
            }
            if (write != read) self.atlas_banks[write] = self.atlas_banks[read];
            write += 1;
        }
        @memset(self.atlas_banks[write..old_count], AtlasTextureBank{});
        self.atlas_bank_count = write;
    }

    fn ensureRetainedBankCapacity(self: *PreparedResources, capacity: usize) !void {
        if (capacity <= self.atlas_banks.len) return;
        const next_len = @max(capacity, @max(self.atlas_banks.len * 2, 4));
        const next = try self.allocator.alloc(AtlasTextureBank, next_len);
        @memset(next, AtlasTextureBank{});
        if (self.atlas_bank_count > 0) @memcpy(next[0..self.atlas_bank_count], self.atlas_banks[0..self.atlas_bank_count]);
        if (self.atlas_banks.len > 0) self.allocator.free(self.atlas_banks);
        self.atlas_banks = next;
    }

    fn activeBankHasAnyResources(self: *const PreparedResources) bool {
        return self.curve_array != 0 or
            self.band_array != 0 or
            self.layer_info_tex != 0 or
            self.image_array != 0;
    }

    fn retainActiveBank(self: *PreparedResources) !void {
        if (!self.activeBankHasAnyResources()) return;
        try self.ensureRetainedBankCapacity(self.atlas_bank_count + 1);
        self.atlas_banks[self.atlas_bank_count] = .{
            .id = self.active_atlas_bank_id,
            .curve_array = self.curve_array,
            .band_array = self.band_array,
            .layer_info_tex = self.layer_info_tex,
            .image_array = self.image_array,
            .allocated_layer_count = self.allocated_layer_count,
            .allocated_image_count = self.allocated_image_count,
            .resident_atlas_pages = atlasPagesInBank(self.atlas_slots[0..self.atlas_slot_count], self.active_atlas_bank_id),
            .resident_image_layers = @intCast(self.image_slot_count),
            .generation = self.generation,
            .prepared_refs = self.active_atlas_bank_refs,
        };
        self.atlas_bank_count += 1;
        self.active_atlas_bank_refs = 0;
        self.curve_array = 0;
        self.band_array = 0;
        self.layer_info_tex = 0;
        self.image_array = 0;
        self.resetImageUploadState();
        self.active_atlas_bank_id = self.next_atlas_bank_id;
        self.next_atlas_bank_id +%= 1;
        self.pruneReleasedRetainedBanks();
    }

    pub fn bankForId(self: *const PreparedResources, bank_id: u32) ?AtlasTextureBank {
        if (bank_id == self.active_atlas_bank_id) {
            return .{
                .id = self.active_atlas_bank_id,
                .curve_array = self.curve_array,
                .band_array = self.band_array,
                .layer_info_tex = self.layer_info_tex,
                .image_array = self.image_array,
                .allocated_layer_count = self.allocated_layer_count,
                .allocated_image_count = self.allocated_image_count,
                .resident_atlas_pages = atlasPagesInBank(self.atlas_slots[0..self.atlas_slot_count], self.active_atlas_bank_id),
                .resident_image_layers = @intCast(self.image_slot_count),
            };
        }
        for (self.atlas_banks[0..self.atlas_bank_count]) |bank| {
            if (bank.id == bank_id) return bank;
        }
        return null;
    }

    pub fn uploadAtlases(self: *PreparedResources, atlases: []const *const CurveAtlas, out_views: anytype) !void {
        return self.uploadAtlasesWithOptionalCapacityModes(self.allocator, atlases, null, out_views);
    }

    pub fn uploadAtlasesWithCapacityModes(
        self: *PreparedResources,
        atlases: []const *const CurveAtlas,
        capacity_modes: []const upload_common.AtlasCapacityMode,
        out_views: anytype,
    ) !void {
        var layer_infos: [0]EmptyLayerInfoUpload = .{};
        var layer_info_views: [0]EmptyLayerInfoView = .{};
        return self.uploadAtlasesAndLayerInfoWithOptionalCapacityModes(self.allocator, atlases, capacity_modes, out_views, layer_infos[0..], layer_info_views[0..]);
    }

    pub fn uploadAtlasesAndLayerInfoWithCapacityModes(
        self: *PreparedResources,
        scratch: std.mem.Allocator,
        atlases: []const *const CurveAtlas,
        capacity_modes: []const upload_common.AtlasCapacityMode,
        out_views: anytype,
        layer_infos: anytype,
        out_layer_info_views: anytype,
    ) !void {
        return self.uploadAtlasesAndLayerInfoWithOptionalCapacityModes(scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
    }

    fn uploadAtlasesWithOptionalCapacityModes(
        self: *PreparedResources,
        scratch: std.mem.Allocator,
        atlases: []const *const CurveAtlas,
        capacity_modes: ?[]const upload_common.AtlasCapacityMode,
        out_views: anytype,
    ) !void {
        var layer_infos: [0]EmptyLayerInfoUpload = .{};
        var layer_info_views: [0]EmptyLayerInfoView = .{};
        return self.uploadAtlasesAndLayerInfoWithOptionalCapacityModes(scratch, atlases, capacity_modes, out_views, layer_infos[0..], layer_info_views[0..]);
    }

    const EmptyLayerInfoUpload = struct {
        data: ?[]const f32 = null,
        width: u32 = 0,
        height: u32 = 0,
        paint_image_records: ?[]const ?CurveAtlas.PaintImageRecord = null,
    };

    const EmptyLayerInfoView = struct {
        info_row_base: u32 = 0,
    };

    fn uploadAtlasesAndLayerInfoWithOptionalCapacityModes(
        self: *PreparedResources,
        scratch: std.mem.Allocator,
        atlases: []const *const CurveAtlas,
        capacity_modes: ?[]const upload_common.AtlasCapacityMode,
        out_views: anytype,
        layer_infos: anytype,
        out_layer_info_views: anytype,
    ) !void {
        std.debug.assert(atlases.len == out_views.len);
        if (capacity_modes) |modes| std.debug.assert(atlases.len == modes.len);
        std.debug.assert(layer_infos.len == out_layer_info_views.len);

        const decision = upload_common.decideAtlasUpload(.{
            .atlas_count = atlases.len,
            .layer_info_count = layer_infos.len,
            .simple_atlases = atlasesHaveNoLayerInfoOrImages(atlases),
            .no_active_layer_info = self.layer_info_tex == 0,
            .textures_ready = self.texturesReady(),
            .slots_compatible = self.atlasSlotsCompatible(atlases),
            .overflow_bank_compatible = self.atlasPrefixesCompatibleForOverflow(atlases),
        });
        switch (decision) {
            .clear => {
                self.destroyAtlasTextureResources();
                self.resetAtlasUploadState();
                return;
            },
            .rebuild => try self.rebuildTextureArrays(scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views),
            .append_overflow_bank => {
                if (!try self.appendTexturePagesIntoNewBank(scratch, atlases)) {
                    try self.rebuildTextureArrays(scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
                } else {
                    self.fillAtlasViews(atlases, out_views);
                    self.fillLayerInfoViews(self.atlasLayerInfoRows(atlases), layer_infos, out_layer_info_views);
                    try self.ensureAtlasImagesRegistered(scratch, atlases);
                    try self.ensureLayerInfoImagesRegistered(scratch, layer_infos);
                    try self.rebuildLayerInfoTexture(scratch, atlases, layer_infos, out_layer_info_views);
                    self.atlas_has_special_text_runs = subpixel_policy.resourcesHaveSpecialTextRuns(atlases, layer_infos);
                }
            },
            .append_pages => if (!try self.appendTexturePages(scratch, atlases)) {
                try self.rebuildTextureArrays(scratch, atlases, capacity_modes, out_views, layer_infos, out_layer_info_views);
            } else {
                self.fillAtlasViews(atlases, out_views);
                self.fillLayerInfoViews(self.atlasLayerInfoRows(atlases), layer_infos, out_layer_info_views);
                try self.ensureAtlasImagesRegistered(scratch, atlases);
                try self.ensureLayerInfoImagesRegistered(scratch, layer_infos);
                try self.rebuildLayerInfoTexture(scratch, atlases, layer_infos, out_layer_info_views);
                self.atlas_has_special_text_runs = subpixel_policy.resourcesHaveSpecialTextRuns(atlases, layer_infos);
            },
        }
    }

    pub fn uploadImages(self: *PreparedResources, scratch: std.mem.Allocator, images: []const *const snail_mod.Image, out_views: anytype) !void {
        std.debug.assert(images.len == out_views.len);
        try self.ensureImagesRegistered(scratch, images);
        const ImageView = upload_common.BufferElement(@TypeOf(out_views));
        for (images, 0..) |image, i| {
            out_views[i] = self.currentImageView(ImageView, image);
        }
    }

    pub fn bindTextCoverageProgram(self: *const PreparedResources, program: TextCoverageProgram) void {
        if (self.backend == .gl44) {
            gl.glBindTextureUnit(@intCast(program.curve_tex_unit), self.curve_array);
            gl.glBindTextureUnit(@intCast(program.band_tex_unit), self.band_array);
            if (program.layer_tex_loc >= 0) gl.glBindTextureUnit(@intCast(program.layer_tex_unit), self.layer_info_tex);
            if (program.image_tex_loc >= 0) gl.glBindTextureUnit(@intCast(program.image_tex_unit), self.image_array);
        } else {
            gl.glActiveTexture(textureUnitEnum(program.curve_tex_unit));
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
            gl.glActiveTexture(textureUnitEnum(program.band_tex_unit));
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
            if (program.layer_tex_loc >= 0) {
                gl.glActiveTexture(textureUnitEnum(program.layer_tex_unit));
                gl.glBindTexture(gl.GL_TEXTURE_2D, self.layer_info_tex);
            }
            if (program.image_tex_loc >= 0) {
                gl.glActiveTexture(textureUnitEnum(program.image_tex_unit));
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array);
            }
        }

        if (program.curve_tex_loc >= 0) gl.glUniform1i(program.curve_tex_loc, @intCast(program.curve_tex_unit));
        if (program.band_tex_loc >= 0) gl.glUniform1i(program.band_tex_loc, @intCast(program.band_tex_unit));
        if (program.layer_tex_loc >= 0) gl.glUniform1i(program.layer_tex_loc, @intCast(program.layer_tex_unit));
        if (program.image_tex_loc >= 0) gl.glUniform1i(program.image_tex_loc, @intCast(program.image_tex_unit));
    }

    pub fn bindTextCoverageDrawState(program: TextCoverageProgram, state: TextCoverageDrawState) void {
        if (program.fill_rule_loc >= 0) gl.glUniform1i(program.fill_rule_loc, @intFromEnum(state.fill_rule));
        if (program.subpixel_order_loc >= 0) gl.glUniform1i(program.subpixel_order_loc, @intFromEnum(state.subpixel_order));
        if (program.output_srgb_loc >= 0) gl.glUniform1i(program.output_srgb_loc, @intFromBool(state.output_srgb));
        if (program.coverage_exponent_loc >= 0) gl.glUniform1f(program.coverage_exponent_loc, state.coverage_transfer.shaderExponent());
        if (program.layer_base_loc >= 0) gl.glUniform1i(program.layer_base_loc, @intCast(state.layer_base));
    }

    fn currentImageView(self: *const PreparedResources, comptime ImageView: type, image: *const snail_mod.Image) ImageView {
        return upload_common.currentImageView(
            ImageView,
            self.image_slots[0..],
            self.image_slot_count,
            self.allocated_image_width,
            self.allocated_image_height,
            image,
        );
    }

    fn findImageSlot(self: *const PreparedResources, image: *const snail_mod.Image) ?usize {
        return upload_common.findImageSlot(self.image_slots[0..], self.image_slot_count, image);
    }

    fn ensureAtlasImagesRegistered(self: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const CurveAtlas) !void {
        var images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
        defer images.deinit(scratch);
        try upload_common.collectAtlasImages(scratch, self.image_slots, self.image_slot_count, atlases, &images);
        try self.ensureImagesRegistered(scratch, images.items);
    }

    fn ensureLayerInfoImagesRegistered(self: *PreparedResources, scratch: std.mem.Allocator, layer_infos: anytype) !void {
        var images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
        defer images.deinit(scratch);
        for (layer_infos) |info| {
            const records = info.paint_image_records orelse continue;
            for (records) |record| {
                const image = (record orelse continue).image;
                if (self.findImageSlot(image) != null) continue;
                if (!upload_common.imageListContains(images.items, image)) try images.append(scratch, image);
            }
        }
        try self.ensureImagesRegistered(scratch, images.items);
    }

    fn ensureImageSlotCapacity(self: *PreparedResources, capacity: usize) !void {
        if (capacity <= self.image_slots.len) return;
        const next = try self.allocator.alloc(ImageSlot, capacity);
        @memset(next, ImageSlot{});
        if (self.image_slot_count > 0) @memcpy(next[0..self.image_slot_count], self.image_slots[0..self.image_slot_count]);
        if (self.image_slots.len > 0) self.allocator.free(self.image_slots);
        self.image_slots = next;
    }

    fn ensureImagesRegistered(self: *PreparedResources, scratch: std.mem.Allocator, images: []const *const snail_mod.Image) !void {
        if (images.len == 0) return;

        var target_images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
        defer target_images.deinit(scratch);
        var new_images = std.ArrayListUnmanaged(*const snail_mod.Image).empty;
        defer new_images.deinit(scratch);
        var required_width = self.allocated_image_width;
        var required_height = self.allocated_image_height;
        for (images) |image| {
            required_width = @max(required_width, image.width);
            required_height = @max(required_height, image.height);
            if (!upload_common.imageListContains(target_images.items, image)) try target_images.append(scratch, image);
            if (self.findImageSlot(image) != null) continue;
            if (!upload_common.imageListContains(new_images.items, image)) try new_images.append(scratch, image);
        }

        if (new_images.items.len == 0 and self.image_array != 0) return;

        try self.ensureImageSlotCapacity(self.image_slot_count + new_images.items.len);

        const required_count: u32 = @intCast(self.image_slot_count + new_images.items.len);
        const new_width = upload_common.imageExtentCapacity(required_width);
        const new_height = upload_common.imageExtentCapacity(required_height);
        const needs_rebuild = self.image_array == 0 or
            required_count > self.allocated_image_count or
            new_width > self.allocated_image_width or
            new_height > self.allocated_image_height;

        if (needs_rebuild) {
            if (self.image_array != 0) try self.retainActiveBank();
            try self.ensureImageSlotCapacity(target_images.items.len);
            for (target_images.items, 0..) |image, i| {
                self.image_slots[i] = .{ .fingerprint = image.fingerprint() };
            }
            self.image_slot_count = target_images.items.len;
            self.rebuildImageArray(target_images.items);
            return;
        }

        for (new_images.items, 0..) |image, i| {
            const slot_index = self.image_slot_count + i;
            self.image_slots[slot_index] = .{ .fingerprint = image.fingerprint() };
            self.uploadImageLayer(image, @intCast(slot_index));
        }
        self.image_slot_count += new_images.items.len;
    }

    fn rebuildImageArray(self: *PreparedResources, images: []const *const snail_mod.Image) void {
        std.debug.assert(images.len == self.image_slot_count);
        const had_array = self.image_array != 0;
        if (self.image_array != 0) gl.glDeleteTextures(1, &self.image_array);
        self.image_array = 0;
        if (had_array) self.generation +%= 1;

        if (self.image_slot_count == 0) {
            self.allocated_image_width = 0;
            self.allocated_image_height = 0;
            self.allocated_image_count = 0;
            return;
        }

        var max_width: u32 = 1;
        var max_height: u32 = 1;
        for (images) |image| {
            max_width = @max(max_width, image.width);
            max_height = @max(max_height, image.height);
        }

        self.allocated_image_width = upload_common.imageExtentCapacity(max_width);
        self.allocated_image_height = upload_common.imageExtentCapacity(max_height);
        self.allocated_image_count = upload_common.imageCapacity(@intCast(self.image_slot_count));

        switch (self.backend) {
            .gl33 => {
                gl.glGenTextures(1, &self.image_array);
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array);
                gl.glTexImage3D(
                    gl.GL_TEXTURE_2D_ARRAY,
                    0,
                    gl.GL_SRGB8_ALPHA8,
                    @intCast(self.allocated_image_width),
                    @intCast(self.allocated_image_height),
                    @intCast(self.allocated_image_count),
                    0,
                    gl.GL_RGBA,
                    gl.GL_UNSIGNED_BYTE,
                    null,
                );
                setImageTexParams(gl.GL_TEXTURE_2D_ARRAY);
            },
            .gl44 => {
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.image_array);
                gl.glTextureStorage3D(
                    self.image_array,
                    1,
                    gl.GL_SRGB8_ALPHA8,
                    @intCast(self.allocated_image_width),
                    @intCast(self.allocated_image_height),
                    @intCast(self.allocated_image_count),
                );
                setImageTexParamsDSA(self.image_array);
                gl.glBindTextureUnit(3, self.image_array);
            },
        }

        for (images, 0..) |image, i| {
            self.uploadImageLayer(image, @intCast(i));
        }
    }

    fn uploadImageLayer(self: *const PreparedResources, image: *const snail_mod.Image, layer: u32) void {
        switch (self.backend) {
            .gl33 => {
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array);
                gl.glTexSubImage3D(
                    gl.GL_TEXTURE_2D_ARRAY,
                    0,
                    0,
                    0,
                    @intCast(layer),
                    @intCast(image.width),
                    @intCast(image.height),
                    1,
                    gl.GL_RGBA,
                    gl.GL_UNSIGNED_BYTE,
                    image.pixels.ptr,
                );
            },
            .gl44 => {
                gl.glTextureSubImage3D(
                    self.image_array,
                    0,
                    0,
                    0,
                    @intCast(layer),
                    @intCast(image.width),
                    @intCast(image.height),
                    1,
                    gl.GL_RGBA,
                    gl.GL_UNSIGNED_BYTE,
                    image.pixels.ptr,
                );
            },
        }
    }

    fn rebuildTextureArrays(
        self: *PreparedResources,
        scratch: std.mem.Allocator,
        atlases: []const *const CurveAtlas,
        capacity_modes: ?[]const upload_common.AtlasCapacityMode,
        out_views: anytype,
        layer_infos: anytype,
        out_layer_info_views: anytype,
    ) !void {
        try self.retainActiveBank();
        self.resetAtlasUploadState();

        try self.ensureAtlasSlotCount(atlases.len);
        const slot_info = if (capacity_modes) |modes|
            try upload_common.rebuildAtlasSlotsWithCapacityModes(self.allocator, self.atlas_slots, atlases, modes)
        else
            try upload_common.rebuildAtlasSlots(self.allocator, self.atlas_slots, atlases);
        self.atlas_slot_count = slot_info.atlas_slot_count;
        self.allocated_curve_height = slot_info.allocated_curve_height;
        self.allocated_band_height = slot_info.allocated_band_height;
        self.allocated_layer_count = slot_info.allocated_layer_count;
        self.encodeSlotPageLayers();
        self.fillLayerInfoViews(slot_info.layer_info_rows, layer_infos, out_layer_info_views);

        const first_atlas = upload_common.firstNonEmptyAtlas(atlases) orelse {
            self.fillAtlasViews(atlases, out_views);
            try self.ensureLayerInfoImagesRegistered(scratch, layer_infos);
            try self.rebuildLayerInfoTexture(scratch, atlases, layer_infos, out_layer_info_views);
            return;
        };

        self.createTextureArrays(first_atlas, self.allocated_layer_count, self.allocated_curve_height, self.allocated_band_height);
        self.uploadAllPages(atlases);
        try self.ensureAtlasImagesRegistered(scratch, atlases);
        try self.ensureLayerInfoImagesRegistered(scratch, layer_infos);
        try self.rebuildLayerInfoTexture(scratch, atlases, layer_infos, out_layer_info_views);
        self.atlas_has_special_text_runs = subpixel_policy.resourcesHaveSpecialTextRuns(atlases, layer_infos);
        self.fillAtlasViews(atlases, out_views);
    }

    fn appendTexturePages(self: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const CurveAtlas) !bool {
        var max_curve_h: u32 = self.allocated_curve_height;
        var max_band_h: u32 = self.allocated_band_height;
        const start_pages = try scratch.alloc(u32, atlases.len);
        defer scratch.free(start_pages);

        for (atlases, 0..) |atlas, i| {
            if (i >= self.atlas_slot_count) return false;
            const slot = &self.atlas_slots[i];
            const page_count: u32 = @intCast(atlas.pageCount());
            if (page_count < slot.uploaded_pages or page_count > slot.capacity_pages) return false;
            start_pages[i] = slot.uploaded_pages;
            if (slot.uploaded_pages > slot.page_fingerprints.len) return false;
            for (0..slot.uploaded_pages) |page_index| {
                const fingerprint = upload_common.atlasPageFingerprint(atlas, page_index);
                if (!slot.page_fingerprints[page_index].eql(fingerprint)) return false;
            }
            for (0..page_count) |page_index| {
                const page = atlas.page(@intCast(page_index));
                if (page.curve_height > max_curve_h) max_curve_h = page.curve_height;
                if (page.band_height > max_band_h) max_band_h = page.band_height;
            }
        }

        if (atlases.len != self.atlas_slot_count) return false;
        if (max_curve_h > self.allocated_curve_height or max_band_h > self.allocated_band_height) return false;

        switch (self.backend) {
            .gl33 => self.uploadTexturePagesGl33WithStarts(atlases, start_pages[0..atlases.len]),
            .gl44 => self.uploadTexturePagesGl44WithStarts(atlases, start_pages[0..atlases.len]),
        }

        try upload_common.refreshAtlasSlots(self.atlas_slots, atlases);
        self.encodeSlotPageLayersFromStarts(start_pages[0..atlases.len]);
        return true;
    }

    fn ensureSlotPageCapacity(self: *PreparedResources, slot: *AtlasSlot, capacity: u32) !void {
        return upload_common.ensureSlotPageCapacity(self.allocator, slot, capacity);
    }

    const AtlasAppendPlan = struct {
        first_page: *const AtlasPage,
        layer_count: u32,
        curve_height: u32,
        band_height: u32,
    };

    fn atlasAppendPlan(self: *const PreparedResources, atlases: []const *const CurveAtlas) !?AtlasAppendPlan {
        var page_count_total: usize = 0;
        var max_curve_h: u32 = 1;
        var max_band_h: u32 = 1;
        var first_page: ?*const AtlasPage = null;
        for (atlases, 0..) |atlas, i| {
            const slot = &self.atlas_slots[i];
            for (slot.uploaded_pages..atlas.pageCount()) |page_index| {
                const page = atlas.page(@intCast(page_index));
                first_page = first_page orelse page;
                max_curve_h = @max(max_curve_h, page.curve_height);
                max_band_h = @max(max_band_h, page.band_height);
                page_count_total += 1;
            }
        }
        if (page_count_total == 0) return null;
        if (page_count_total > std.math.maxInt(u32)) return error.PreparedResourceCapacityExceeded;
        return .{
            .first_page = first_page.?,
            .layer_count = @intCast(page_count_total),
            .curve_height = upload_common.heightCapacity(max_curve_h),
            .band_height = upload_common.heightCapacity(max_band_h),
        };
    }

    fn createAtlasTextureBank(self: *PreparedResources, plan: AtlasAppendPlan) AtlasTextureBank {
        var bank = AtlasTextureBank{
            .id = self.next_atlas_bank_id,
            .allocated_layer_count = plan.layer_count,
            .resident_atlas_pages = plan.layer_count,
            .generation = self.generation,
        };
        self.next_atlas_bank_id +%= 1;
        switch (self.backend) {
            .gl33 => self.createAtlasTextureBankGl33(&bank, plan),
            .gl44 => self.createAtlasTextureBankGl44(&bank, plan),
        }
        return bank;
    }

    fn createAtlasTextureBankGl33(self: *PreparedResources, bank: *AtlasTextureBank, plan: AtlasAppendPlan) void {
        _ = self;
        gl.glGenTextures(1, &bank.curve_array);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, bank.curve_array);
        gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RGBA16F, @intCast(plan.first_page.curve_width), @intCast(plan.curve_height), @intCast(bank.allocated_layer_count), 0, gl.GL_RGBA, gl.GL_HALF_FLOAT, null);
        setTexParams(gl.GL_TEXTURE_2D_ARRAY);

        gl.glGenTextures(1, &bank.band_array);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, bank.band_array);
        gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RG16UI, @intCast(plan.first_page.band_width), @intCast(plan.band_height), @intCast(bank.allocated_layer_count), 0, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, null);
        setTexParams(gl.GL_TEXTURE_2D_ARRAY);
    }

    fn createAtlasTextureBankGl44(self: *PreparedResources, bank: *AtlasTextureBank, plan: AtlasAppendPlan) void {
        _ = self;
        gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &bank.curve_array);
        gl.glTextureStorage3D(bank.curve_array, 1, gl.GL_RGBA16F, @intCast(plan.first_page.curve_width), @intCast(plan.curve_height), @intCast(bank.allocated_layer_count));
        setTexParamsDSA(bank.curve_array);

        gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &bank.band_array);
        gl.glTextureStorage3D(bank.band_array, 1, gl.GL_RG16UI, @intCast(plan.first_page.band_width), @intCast(plan.band_height), @intCast(bank.allocated_layer_count));
        setTexParamsDSA(bank.band_array);
    }

    fn ensureNewBankSlotCapacity(self: *PreparedResources, atlases: []const *const CurveAtlas) !void {
        for (atlases, 0..) |atlas, i| {
            const slot = &self.atlas_slots[i];
            const new_pages: u32 = @intCast(atlas.pageCount());
            try self.ensureSlotPageCapacity(slot, @max(new_pages, slot.capacity_pages));
        }
    }

    fn uploadAtlasPageToBank(self: *PreparedResources, bank: *AtlasTextureBank, page: *const AtlasPage, layer: u32) void {
        const layer_z: gl.GLint = @intCast(layer);
        switch (self.backend) {
            .gl33 => {
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, bank.curve_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, bank.band_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
            },
            .gl44 => {
                gl.glTextureSubImage3D(bank.curve_array, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
                gl.glTextureSubImage3D(bank.band_array, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
            },
        }
    }

    fn uploadNewAtlasPagesIntoBank(self: *PreparedResources, bank: *AtlasTextureBank, atlases: []const *const CurveAtlas) void {
        var layer: u32 = 0;
        for (atlases, 0..) |atlas, i| {
            const slot = &self.atlas_slots[i];
            const old_pages = slot.uploaded_pages;
            const new_pages: u32 = @intCast(atlas.pageCount());
            for (old_pages..new_pages) |page_index| {
                const page = atlas.page(@intCast(page_index));
                self.uploadAtlasPageToBank(bank, page, layer);
                slot.page_fingerprints[page_index] = page.fingerprint();
                slot.page_layers[page_index] = texture_layers.inBank(bank.id, layer);
                layer += 1;
            }
            slot.uploaded_pages = new_pages;
        }
    }

    fn appendTexturePagesIntoNewBank(self: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const CurveAtlas) !bool {
        const plan = (try self.atlasAppendPlan(atlases)) orelse return true;
        var bank = self.createAtlasTextureBank(plan);
        errdefer bank.deinit();

        try self.ensureRetainedBankCapacity(self.atlas_bank_count + 1);
        try self.ensureNewBankSlotCapacity(atlases);
        self.uploadNewAtlasPagesIntoBank(&bank, atlases);
        self.atlas_banks[self.atlas_bank_count] = bank;
        self.atlas_bank_count += 1;
        _ = scratch;
        return true;
    }

    fn texturesReady(self: *const PreparedResources) bool {
        return self.curve_array != 0 and self.band_array != 0 and self.atlas_slot_count > 0;
    }

    fn atlasSlotsCompatible(self: *const PreparedResources, atlases: []const *const CurveAtlas) bool {
        return upload_common.atlasSlotsCompatible(self.atlas_slots[0..], self.atlas_slot_count, atlases);
    }

    fn atlasesHaveNoLayerInfoOrImages(atlases: []const *const CurveAtlas) bool {
        return upload_common.atlasesHaveNoLayerInfoOrImages(atlases);
    }

    fn atlasPrefixesCompatibleForOverflow(self: *const PreparedResources, atlases: []const *const CurveAtlas) bool {
        return upload_common.atlasPrefixesCompatibleForOverflow(self.atlas_slots, self.atlas_slot_count, atlases);
    }

    fn encodeSlotPageLayers(self: *PreparedResources) void {
        upload_common.encodeSlotPageLayers(self.atlas_slots, self.atlas_slot_count, self.active_atlas_bank_id);
    }

    fn encodeSlotPageLayersFromStarts(self: *PreparedResources, start_pages: []const u32) void {
        upload_common.encodeSlotPageLayersFromStarts(self.atlas_slots, self.atlas_slot_count, self.active_atlas_bank_id, start_pages);
    }

    fn fillAtlasViews(self: *const PreparedResources, atlases: []const *const CurveAtlas, out_views: anytype) void {
        upload_common.fillAtlasViews(self.atlas_slots, atlases, out_views);
    }

    fn atlasLayerInfoRows(_: *const PreparedResources, atlases: []const *const CurveAtlas) u32 {
        return upload_common.atlasLayerInfoRows(atlases);
    }

    fn fillLayerInfoViews(_: *const PreparedResources, row_base_start: u32, layer_infos: anytype, out_views: anytype) void {
        upload_common.fillLayerInfoViews(row_base_start, layer_infos, out_views);
    }

    fn ensureAtlasSlotCount(self: *PreparedResources, count: usize) !void {
        if (self.atlas_slots.len == count) return;
        self.resetAtlasUploadState();
        if (count == 0) return;
        self.atlas_slots = try self.allocator.alloc(AtlasSlot, count);
        @memset(self.atlas_slots, AtlasSlot{});
    }

    fn resetAtlasUploadState(self: *PreparedResources) void {
        for (self.atlas_slots) |*slot| slot.deinit(self.allocator);
        if (self.atlas_slots.len > 0) self.allocator.free(self.atlas_slots);
        self.atlas_slots = &.{};
        self.atlas_slot_count = 0;
        self.allocated_curve_height = 0;
        self.allocated_band_height = 0;
        self.allocated_layer_count = 0;
        self.atlas_has_special_text_runs = false;
        self.pruneReleasedRetainedBanks();
    }

    fn createTextureArrays(self: *PreparedResources, first_atlas: *const CurveAtlas, layer_count: u32, max_curve_h: u32, max_band_h: u32) void {
        const first_page = first_atlas.page(0);

        switch (self.backend) {
            .gl33 => {
                gl.glGenTextures(1, &self.curve_array);
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
                gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RGBA16F, @intCast(first_page.curve_width), @intCast(max_curve_h), @intCast(layer_count), 0, gl.GL_RGBA, gl.GL_HALF_FLOAT, null);
                setTexParams(gl.GL_TEXTURE_2D_ARRAY);

                gl.glGenTextures(1, &self.band_array);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
                gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RG16UI, @intCast(first_page.band_width), @intCast(max_band_h), @intCast(layer_count), 0, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, null);
                setTexParams(gl.GL_TEXTURE_2D_ARRAY);
            },
            .gl44 => {
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.curve_array);
                gl.glTextureStorage3D(self.curve_array, 1, gl.GL_RGBA16F, @intCast(first_page.curve_width), @intCast(max_curve_h), @intCast(layer_count));
                setTexParamsDSA(self.curve_array);

                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.band_array);
                gl.glTextureStorage3D(self.band_array, 1, gl.GL_RG16UI, @intCast(first_page.band_width), @intCast(max_band_h), @intCast(layer_count));
                setTexParamsDSA(self.band_array);
                gl.glBindTextureUnit(0, self.curve_array);
                gl.glBindTextureUnit(1, self.band_array);
            },
        }
    }

    fn uploadAllPages(self: *PreparedResources, atlases: []const *const CurveAtlas) void {
        switch (self.backend) {
            .gl33 => self.uploadTexturePagesGl33WithStarts(atlases, null),
            .gl44 => self.uploadTexturePagesGl44WithStarts(atlases, null),
        }
    }

    fn uploadTexturePagesGl33WithStarts(self: *const PreparedResources, atlases: []const *const CurveAtlas, start_pages: ?[]const u32) void {
        for (atlases, 0..) |atlas, i| {
            const start_page = if (start_pages) |sp| sp[i] else 0;
            const base_layer = self.atlas_slots[i].base_layer;
            for (start_page..atlas.pageCount()) |page_index| {
                const page = atlas.page(@intCast(page_index));
                const layer = base_layer + @as(u32, @intCast(page_index));
                const layer_z: gl.GLint = @intCast(layer);
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
            }
        }
    }

    fn uploadTexturePagesGl44WithStarts(self: *const PreparedResources, atlases: []const *const CurveAtlas, start_pages: ?[]const u32) void {
        for (atlases, 0..) |atlas, i| {
            const start_page = if (start_pages) |sp| sp[i] else 0;
            const base_layer = self.atlas_slots[i].base_layer;
            for (start_page..atlas.pageCount()) |page_index| {
                const page = atlas.page(@intCast(page_index));
                const layer = base_layer + @as(u32, @intCast(page_index));
                const layer_z: gl.GLint = @intCast(layer);
                gl.glTextureSubImage3D(self.curve_array, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
                gl.glTextureSubImage3D(self.band_array, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
            }
        }
    }

    fn rebuildLayerInfoTexture(self: *PreparedResources, scratch: std.mem.Allocator, atlases: []const *const CurveAtlas, layer_infos: anytype, layer_info_views: anytype) !void {
        const had_layer_info = self.layer_info_tex != 0;
        if (self.layer_info_tex != 0) gl.glDeleteTextures(1, &self.layer_info_tex);
        self.layer_info_tex = 0;
        if (had_layer_info) self.generation +%= 1;

        var total_rows: u32 = 0;
        for (atlases) |atlas| total_rows += atlas.layer_info_height;
        for (layer_infos) |info| total_rows += info.height;
        if (total_rows == 0) return;

        var width = upload_common.maxLayerInfoWidth(atlases);
        for (layer_infos) |info| {
            if (info.height > 0 and info.width > width) width = info.width;
        }
        const total_texels = @as(usize, width) * @as(usize, total_rows) * 4;
        const data = try scratch.alloc(f32, total_texels);
        defer scratch.free(data);
        @memset(data, 0);

        const ImagePatchView = struct {
            image: *const snail_mod.Image,
            layer: u32 = 0,
            uv_scale: snail_mod.Vec2 = .{ .x = 1.0, .y = 1.0 },
        };
        for (atlases, 0..) |atlas, i| {
            const lid = atlas.layer_info_data orelse continue;
            const row_base = self.atlas_slots[i].info_row_base;
            const row_count = atlas.layer_info_height;
            upload_common.copyLayerInfoRows(data, width, row_base, lid, atlas.layer_info_width, row_count);

            const records = atlas.paint_image_records orelse continue;
            for (records) |record| {
                const image = (record orelse continue).image;
                const view = self.currentImageView(ImagePatchView, image);
                upload_common.patchImagePaintRecord(data, width, atlas.layer_info_width, row_base, record.?.texel_offset, view);
            }
        }
        for (layer_infos, 0..) |info, i| {
            const lid = info.data orelse continue;
            const row_base = layer_info_views[i].info_row_base;
            upload_common.copyLayerInfoRows(data, width, row_base, lid, info.width, info.height);

            const records = info.paint_image_records orelse continue;
            for (records) |record| {
                const image = (record orelse continue).image;
                const view = self.currentImageView(ImagePatchView, image);
                upload_common.patchImagePaintRecord(data, width, info.width, row_base, record.?.texel_offset, view);
            }
        }

        gl.glGenTextures(1, &self.layer_info_tex);
        gl.glActiveTexture(gl.GL_TEXTURE2);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.layer_info_tex);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA32F, @intCast(width), @intCast(total_rows), 0, gl.GL_RGBA, gl.GL_FLOAT, @ptrCast(data.ptr));
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
    }
};

test "prepared resource retirement releases unreferenced GL banks" {
    const allocator = std.testing.allocator;
    var cache = PreparedResources{ .allocator = allocator, .backend = .gl33, .active_atlas_bank_id = 99 };
    cache.atlas_banks = try allocator.alloc(AtlasTextureBank, 2);
    @memset(cache.atlas_banks, AtlasTextureBank{});
    cache.atlas_banks[0] = .{ .id = 7 };
    cache.atlas_banks[1] = .{ .id = 8 };
    cache.atlas_bank_count = 2;
    defer cache.destroyRetainedBanks();

    const layers = [_]u32{
        texture_layers.inBank(7, 0),
        texture_layers.inBank(7, 1),
        texture_layers.inBank(8, 0),
    };
    const FakeView = struct { page_layers: []const u32 = &.{} };
    const FakeEntry = struct { view: FakeView = .{} };
    const FakeManifest = struct { atlases: []const FakeEntry = &.{} };
    const entries = [_]FakeEntry{.{ .view = .{ .page_layers = layers[0..] } }};
    const manifest = FakeManifest{ .atlases = entries[0..] };

    cache.retainPreparedResources(manifest, cache.generation);
    try std.testing.expectEqual(@as(u32, 2), cache.atlas_banks[0].prepared_refs);
    try std.testing.expectEqual(@as(u32, 1), cache.atlas_banks[1].prepared_refs);

    cache.releasePreparedResources(manifest, cache.generation);
    try std.testing.expectEqual(@as(usize, 0), cache.atlas_bank_count);
}

test "released GL banks stay resident while referenced by current atlas state" {
    const allocator = std.testing.allocator;
    var cache = PreparedResources{ .allocator = allocator, .backend = .gl33, .active_atlas_bank_id = 99 };
    cache.atlas_banks = try allocator.alloc(AtlasTextureBank, 1);
    @memset(cache.atlas_banks, AtlasTextureBank{});
    cache.atlas_banks[0] = .{ .id = 7 };
    cache.atlas_bank_count = 1;
    defer cache.destroyRetainedBanks();

    cache.atlas_slots = try allocator.alloc(AtlasSlot, 1);
    defer allocator.free(cache.atlas_slots);
    const page_layers = try allocator.alloc(u32, 1);
    defer allocator.free(page_layers);
    page_layers[0] = texture_layers.inBank(7, 0);
    cache.atlas_slots[0] = .{
        .uploaded_pages = 1,
        .page_layers = page_layers,
    };
    cache.atlas_slot_count = 1;

    cache.pruneReleasedRetainedBanks();
    try std.testing.expectEqual(@as(usize, 1), cache.atlas_bank_count);
    try std.testing.expectEqual(@as(u32, 7), cache.atlas_banks[0].id);
}

test "stale GL prepared release does not touch active refs from newer generation" {
    var cache = PreparedResources{
        .allocator = std.testing.allocator,
        .backend = .gl33,
        .active_atlas_bank_id = 7,
        .active_atlas_bank_refs = 1,
        .generation = 1,
    };

    const layers = [_]u32{texture_layers.inBank(7, 0)};
    const FakeView = struct { page_layers: []const u32 = &.{} };
    const FakeEntry = struct { view: FakeView = .{} };
    const FakeManifest = struct { atlases: []const FakeEntry = &.{} };
    const entries = [_]FakeEntry{.{ .view = .{ .page_layers = layers[0..] } }};
    const manifest = FakeManifest{ .atlases = entries[0..] };

    cache.releasePreparedResources(manifest, 0);
    try std.testing.expectEqual(@as(u32, 1), cache.active_atlas_bank_refs);
}

test "stale GL prepared release still frees matching retained old-generation banks" {
    const allocator = std.testing.allocator;
    var cache = PreparedResources{
        .allocator = allocator,
        .backend = .gl33,
        .active_atlas_bank_id = 7,
        .active_atlas_bank_refs = 1,
        .generation = 1,
    };
    cache.atlas_banks = try allocator.alloc(AtlasTextureBank, 1);
    @memset(cache.atlas_banks, AtlasTextureBank{});
    cache.atlas_banks[0] = .{ .id = 7, .generation = 0, .prepared_refs = 1 };
    cache.atlas_bank_count = 1;
    defer cache.destroyRetainedBanks();

    const layers = [_]u32{texture_layers.inBank(7, 0)};
    const FakeView = struct { page_layers: []const u32 = &.{} };
    const FakeEntry = struct { view: FakeView = .{} };
    const FakeManifest = struct { atlases: []const FakeEntry = &.{} };
    const entries = [_]FakeEntry{.{ .view = .{ .page_layers = layers[0..] } }};
    const manifest = FakeManifest{ .atlases = entries[0..] };

    cache.releasePreparedResources(manifest, 0);
    try std.testing.expectEqual(@as(u32, 1), cache.active_atlas_bank_refs);
    try std.testing.expectEqual(@as(usize, 0), cache.atlas_bank_count);
}

fn textureUnitEnum(unit: gl.GLint) gl.GLenum {
    return @intCast(@as(i64, @intCast(gl.GL_TEXTURE0)) + @as(i64, unit));
}

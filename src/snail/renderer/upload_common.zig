const std = @import("std");

pub fn BufferElement(comptime Buffer: type) type {
    return switch (@typeInfo(Buffer)) {
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .array => |array| array.child,
            else => ptr.child,
        },
        .array => |array| array.child,
        else => @compileError("expected a slice, pointer, or array buffer"),
    };
}

pub fn AtlasSlot(comptime Atlas: type, comptime AtlasPage: type) type {
    return struct {
        const Self = @This();

        atlas: ?*const Atlas = null,
        base_layer: u32 = 0,
        info_row_base: u32 = 0,
        capacity_pages: u32 = 0,
        uploaded_pages: u32 = 0,
        page_ptrs: []?*const AtlasPage = &.{},

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            if (self.page_ptrs.len > 0) allocator.free(self.page_ptrs);
            self.* = .{};
        }

        fn resetForAtlas(
            self: *Self,
            allocator: std.mem.Allocator,
            atlas: *const Atlas,
            base_layer: u32,
            info_row_base: u32,
            capacity_pages: u32,
            uploaded_pages: u32,
        ) !void {
            if (self.page_ptrs.len != capacity_pages) {
                var next: []?*const AtlasPage = &.{};
                if (capacity_pages != 0) {
                    next = try allocator.alloc(?*const AtlasPage, @intCast(capacity_pages));
                }
                if (self.page_ptrs.len > 0) allocator.free(self.page_ptrs);
                self.page_ptrs = next;
            }
            @memset(self.page_ptrs, null);
            self.atlas = atlas;
            self.base_layer = base_layer;
            self.info_row_base = info_row_base;
            self.capacity_pages = capacity_pages;
            self.uploaded_pages = uploaded_pages;
        }
    };
}

pub fn ImageSlot(comptime Image: type) type {
    return struct {
        image: ?*const Image = null,
    };
}

pub const AtlasCapacityMode = union(enum) {
    growable,
    exact,
    reserve_pages: u32,
};

pub const AtlasSlotBuildInfo = struct {
    atlas_slot_count: usize,
    allocated_curve_height: u32,
    allocated_band_height: u32,
    allocated_layer_count: u32,
    layer_info_rows: u32,
};

pub fn firstNonEmptyAtlas(atlases: anytype) ?BufferElement(@TypeOf(atlases)) {
    for (atlases) |atlas| {
        if (atlas.pageCount() > 0) return atlas;
    }
    return null;
}

pub fn atlasSlotsCompatible(atlas_slots: anytype, atlas_slot_count: usize, atlases: anytype) bool {
    if (atlases.len != atlas_slot_count) return false;
    for (atlases, 0..) |atlas, i| {
        const slot = &atlas_slots[i];
        if (atlas.pageCount() > std.math.maxInt(u16)) return false;
        const page_count: u32 = @intCast(atlas.pageCount());
        if (page_count < slot.uploaded_pages or page_count > slot.capacity_pages) return false;
        if (slot.uploaded_pages > slot.page_ptrs.len) return false;
        for (0..slot.uploaded_pages) |page_index| {
            if (slot.page_ptrs[page_index] != atlas.page(@intCast(page_index))) return false;
        }
    }
    return true;
}

pub fn rebuildAtlasSlots(allocator: std.mem.Allocator, atlas_slots: anytype, atlases: anytype) !AtlasSlotBuildInfo {
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var total_layers: u32 = 0;
    var total_info_rows: u32 = 0;

    for (atlases, 0..) |atlas, i| {
        const page_count = atlas.pageCount();
        if (page_count > std.math.maxInt(u16)) return error.AtlasPageCountOverflow;
        const capacity = atlasCapacity(@intCast(page_count));
        const slot = &atlas_slots[i];
        try slot.resetForAtlas(allocator, atlas, total_layers, total_info_rows, capacity, @intCast(page_count));
        for (0..page_count) |page_index| {
            const page = atlas.page(@intCast(page_index));
            slot.page_ptrs[page_index] = page;
            if (page.curve_height > max_curve_h) max_curve_h = page.curve_height;
            if (page.band_height > max_band_h) max_band_h = page.band_height;
        }
        total_layers += capacity;
        total_info_rows += atlas.layer_info_height;
    }

    return .{
        .atlas_slot_count = atlases.len,
        .allocated_curve_height = heightCapacity(max_curve_h),
        .allocated_band_height = heightCapacity(max_band_h),
        .allocated_layer_count = total_layers,
        .layer_info_rows = total_info_rows,
    };
}

pub fn rebuildAtlasSlotsWithCapacityModes(allocator: std.mem.Allocator, atlas_slots: anytype, atlases: anytype, capacity_modes: []const AtlasCapacityMode) !AtlasSlotBuildInfo {
    std.debug.assert(atlases.len == capacity_modes.len);

    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var total_layers: u32 = 0;
    var total_info_rows: u32 = 0;

    for (atlases, capacity_modes, 0..) |atlas, mode, i| {
        const page_count = atlas.pageCount();
        if (page_count > std.math.maxInt(u16)) return error.AtlasPageCountOverflow;
        const capacity = atlasCapacityForMode(@intCast(page_count), mode);
        const slot = &atlas_slots[i];
        try slot.resetForAtlas(allocator, atlas, total_layers, total_info_rows, capacity, @intCast(page_count));
        for (0..page_count) |page_index| {
            const page = atlas.page(@intCast(page_index));
            slot.page_ptrs[page_index] = page;
            if (page.curve_height > max_curve_h) max_curve_h = page.curve_height;
            if (page.band_height > max_band_h) max_band_h = page.band_height;
        }
        total_layers += capacity;
        total_info_rows += atlas.layer_info_height;
    }

    return .{
        .atlas_slot_count = atlases.len,
        .allocated_curve_height = heightCapacity(max_curve_h),
        .allocated_band_height = heightCapacity(max_band_h),
        .allocated_layer_count = total_layers,
        .layer_info_rows = total_info_rows,
    };
}

pub fn refreshAtlasSlots(atlas_slots: anytype, atlases: anytype) !void {
    var total_info_rows: u32 = 0;
    for (atlases, 0..) |atlas, i| {
        const slot = &atlas_slots[i];
        const old_pages = slot.uploaded_pages;
        if (atlas.pageCount() > std.math.maxInt(u16)) return error.AtlasPageCountOverflow;
        const new_pages: u32 = @intCast(atlas.pageCount());
        if (new_pages > slot.page_ptrs.len) return error.AtlasSlotCapacityExceeded;
        for (old_pages..new_pages) |page_index| {
            slot.page_ptrs[page_index] = atlas.page(@intCast(page_index));
        }
        slot.atlas = atlas;
        slot.uploaded_pages = new_pages;
        slot.info_row_base = total_info_rows;
        total_info_rows += atlas.layer_info_height;
    }
}

pub fn fillAtlasViews(atlas_slots: anytype, atlases: anytype, out_views: anytype) void {
    std.debug.assert(atlases.len == out_views.len);
    for (atlases, 0..) |atlas, i| {
        out_views[i] = .{
            .atlas = atlas,
            .layer_base = atlas_slots[i].base_layer,
            .info_row_base = atlas_slots[i].info_row_base,
        };
    }
}

pub fn findImageSlot(image_slots: anytype, image_slot_count: usize, image: anytype) ?usize {
    for (image_slots[0..image_slot_count], 0..) |slot, i| {
        if (slot.image == image) return i;
    }
    return null;
}

pub fn currentImageView(
    comptime ImageView: type,
    image_slots: anytype,
    image_slot_count: usize,
    allocated_image_width: u32,
    allocated_image_height: u32,
    image: anytype,
) ImageView {
    const slot_index = findImageSlot(image_slots, image_slot_count, image) orelse return .{ .image = image };
    const width_scale = if (allocated_image_width == 0) 1.0 else @as(f32, @floatFromInt(image.width)) / @as(f32, @floatFromInt(allocated_image_width));
    const height_scale = if (allocated_image_height == 0) 1.0 else @as(f32, @floatFromInt(image.height)) / @as(f32, @floatFromInt(allocated_image_height));
    return .{
        .image = image,
        .layer = @intCast(slot_index),
        .uv_scale = .{ .x = width_scale, .y = height_scale },
    };
}

pub fn collectAtlasImages(allocator: std.mem.Allocator, image_slots: anytype, image_slot_count: usize, atlases: anytype, out: anytype) !void {
    for (atlases) |atlas| {
        const records = atlas.paint_image_records orelse continue;
        for (records) |record| {
            const image = (record orelse continue).image;
            if (findImageSlot(image_slots, image_slot_count, image) != null) continue;
            var already_queued = false;
            for (out.items) |queued| {
                if (queued == image) {
                    already_queued = true;
                    break;
                }
            }
            if (!already_queued) try out.append(allocator, image);
        }
    }
}

pub fn maxLayerInfoWidth(atlases: anytype) u32 {
    var width: u32 = 1;
    for (atlases) |atlas| {
        if (atlas.layer_info_height > 0 and atlas.layer_info_width > width) width = atlas.layer_info_width;
    }
    return width;
}

pub fn copyLayerInfoRows(
    dst: []f32,
    dst_width: u32,
    dst_row_base: u32,
    src: []const f32,
    src_width: u32,
    row_count: u32,
) void {
    const row_floats = @as(usize, src_width) * 4;
    for (0..row_count) |row| {
        const src_base = row * row_floats;
        const dst_base = (@as(usize, dst_row_base) + row) * @as(usize, dst_width) * 4;
        @memcpy(dst[dst_base..][0..row_floats], src[src_base..][0..row_floats]);
    }
}

pub fn roundUpPowerOfTwo(value: u32) u32 {
    if (value <= 1) return 1;
    var v = value - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    return v + 1;
}

pub fn atlasCapacity(page_count: u32) u32 {
    return @max(2, roundUpPowerOfTwo(page_count + 1));
}

pub fn atlasCapacityForMode(page_count: u32, mode: AtlasCapacityMode) u32 {
    return switch (mode) {
        .growable => atlasCapacity(page_count),
        .exact => page_count,
        .reserve_pages => |reserved| @max(page_count, reserved),
    };
}

pub fn imageCapacity(image_count: u32) u32 {
    return image_count;
}

pub fn imageExtentCapacity(extent: u32) u32 {
    return @max(extent, 1);
}

pub fn heightCapacity(height: u32) u32 {
    return roundUpPowerOfTwo(@max(height, 1));
}

fn layerInfoTexelBase(width: u32, x: u32, y: u32) usize {
    return (y * width + x) * 4;
}

pub fn layerInfoTexelBaseOffset(width: u32, x: u32, y: u32, texel_offset: u32) usize {
    const texel = x + texel_offset;
    const texel_x = texel % width;
    const texel_y = y + texel / width;
    return layerInfoTexelBase(width, texel_x, texel_y);
}

fn layerInfoTexelBaseFromSourceOffset(dst_width: u32, src_width: u32, row_base: u32, texel_offset: u32) usize {
    const texel_x = texel_offset % src_width;
    const texel_y = row_base + texel_offset / src_width;
    return layerInfoTexelBase(dst_width, texel_x, texel_y);
}

pub fn patchImagePaintRecord(data: []f32, dst_width: u32, src_width: u32, row_base: u32, texel_offset: u32, view: anytype) void {
    const transform_base = layerInfoTexelBaseFromSourceOffset(dst_width, src_width, row_base, texel_offset + 2);
    data[transform_base + 3] = @floatFromInt(view.layer);
    const extra_base = layerInfoTexelBaseFromSourceOffset(dst_width, src_width, row_base, texel_offset + 5);
    data[extra_base + 0] = view.uv_scale.x;
    data[extra_base + 1] = view.uv_scale.y;
}

test "zero-page atlases keep slots and views without requiring pages" {
    const Page = struct {
        curve_height: u32 = 1,
        band_height: u32 = 1,
    };
    const Atlas = struct {
        page_count: usize,
        layer_info_height: u32 = 0,

        fn pageCount(self: *const @This()) usize {
            return self.page_count;
        }

        fn page(_: *const @This(), _: u16) *const Page {
            unreachable;
        }
    };
    const View = struct {
        atlas: *const Atlas = undefined,
        layer_base: u32 = 0,
        info_row_base: u32 = 0,
    };
    const Slot = AtlasSlot(Atlas, Page);

    const atlas_a = Atlas{ .page_count = 0 };
    const atlas_b = Atlas{ .page_count = 0 };
    const atlases = [_]*const Atlas{ &atlas_a, &atlas_b };

    var slots: [2]Slot = .{ .{}, .{} };
    defer {
        for (&slots) |*slot| slot.deinit(std.testing.allocator);
    }
    const info = try rebuildAtlasSlots(std.testing.allocator, slots[0..], atlases[0..]);
    try std.testing.expectEqual(@as(usize, 2), info.atlas_slot_count);
    try std.testing.expectEqual(@as(u32, 4), info.allocated_layer_count);
    try std.testing.expect(firstNonEmptyAtlas(atlases[0..]) == null);

    var views: [2]View = undefined;
    fillAtlasViews(slots[0..], atlases[0..], views[0..]);
    try std.testing.expect(views[0].atlas == &atlas_a);
    try std.testing.expectEqual(@as(u32, 0), views[0].layer_base);
    try std.testing.expect(views[1].atlas == &atlas_b);
    try std.testing.expectEqual(@as(u32, 2), views[1].layer_base);
}

test "exact atlas capacity packs immutable one-page atlases tightly" {
    const Page = struct {
        curve_height: u32 = 7,
        band_height: u32 = 5,
    };
    const Atlas = struct {
        page_ref: *const Page,
        layer_info_height: u32 = 0,

        fn pageCount(_: *const @This()) usize {
            return 1;
        }

        fn page(self: *const @This(), _: u16) *const Page {
            return self.page_ref;
        }
    };
    const Slot = AtlasSlot(Atlas, Page);

    const page_a = Page{};
    const page_b = Page{};
    const atlas_a = Atlas{ .page_ref = &page_a };
    const atlas_b = Atlas{ .page_ref = &page_b };
    const atlases = [_]*const Atlas{ &atlas_a, &atlas_b };
    const modes = [_]AtlasCapacityMode{ .exact, .exact };

    var slots: [2]Slot = .{ .{}, .{} };
    defer {
        for (&slots) |*slot| slot.deinit(std.testing.allocator);
    }
    const info = try rebuildAtlasSlotsWithCapacityModes(std.testing.allocator, slots[0..], atlases[0..], modes[0..]);
    try std.testing.expectEqual(@as(u32, 2), info.allocated_layer_count);
    try std.testing.expectEqual(@as(u32, 1), slots[0].capacity_pages);
    try std.testing.expectEqual(@as(u32, 0), slots[0].base_layer);
    try std.testing.expectEqual(@as(u32, 1), slots[1].capacity_pages);
    try std.testing.expectEqual(@as(u32, 1), slots[1].base_layer);
    try std.testing.expectEqual(@as(u32, 8), info.allocated_curve_height);
    try std.testing.expectEqual(@as(u32, 8), info.allocated_band_height);
}

test "atlas capacity mode can reserve explicit page headroom" {
    try std.testing.expectEqual(@as(u32, 8), atlasCapacityForMode(2, .{ .reserve_pages = 8 }));
    try std.testing.expectEqual(@as(u32, 9), atlasCapacityForMode(9, .{ .reserve_pages = 8 }));
}

test "atlas slot metadata is sized from the submitted atlas set" {
    const Page = struct {
        curve_height: u32 = 3,
        band_height: u32 = 2,
    };
    const Atlas = struct {
        pages: []const Page,
        layer_info_height: u32 = 0,

        fn pageCount(self: *const @This()) usize {
            return self.pages.len;
        }

        fn page(self: *const @This(), index: u16) *const Page {
            return &self.pages[index];
        }
    };
    const Slot = AtlasSlot(Atlas, Page);

    const page_count = 300;
    var pages = [_]Page{.{}} ** page_count;
    const atlas = Atlas{ .pages = pages[0..] };
    const atlases = [_]*const Atlas{&atlas};

    var slots: [1]Slot = .{.{}};
    defer slots[0].deinit(std.testing.allocator);

    const info = try rebuildAtlasSlots(std.testing.allocator, slots[0..], atlases[0..]);
    try std.testing.expectEqual(@as(usize, 1), info.atlas_slot_count);
    try std.testing.expectEqual(@as(u32, page_count), slots[0].uploaded_pages);
    try std.testing.expect(slots[0].page_ptrs.len >= page_count);
    try std.testing.expect(slots[0].page_ptrs[page_count - 1] == &pages[page_count - 1]);
}

test "compact layer-info rows patch image records in upload texture coordinates" {
    var src = [_]f32{0} ** (6 * 4);
    src[2 * 4 + 0] = 1.0;
    src[5 * 4 + 2] = 2.0;

    var dst = [_]f32{0} ** (12 * 2 * 4);
    copyLayerInfoRows(dst[0..], 12, 1, src[0..], 6, 1);
    patchImagePaintRecord(dst[0..], 12, 6, 1, 0, .{
        .layer = @as(u16, 9),
        .uv_scale = .{ .x = 0.5, .y = 0.25 },
    });

    const copied_base = (12 + 2) * 4;
    try std.testing.expectEqual(@as(f32, 1.0), dst[copied_base + 0]);
    try std.testing.expectEqual(@as(f32, 9.0), dst[copied_base + 3]);

    const extra_base = (12 + 5) * 4;
    try std.testing.expectEqual(@as(f32, 0.5), dst[extra_base + 0]);
    try std.testing.expectEqual(@as(f32, 0.25), dst[extra_base + 1]);
    try std.testing.expectEqual(@as(f32, 2.0), dst[extra_base + 2]);
}

test "image capacity is exact for immutable image resources" {
    try std.testing.expectEqual(@as(u32, 0), imageCapacity(0));
    try std.testing.expectEqual(@as(u32, 1), imageCapacity(1));
    try std.testing.expectEqual(@as(u32, 3), imageCapacity(3));
    try std.testing.expectEqual(@as(u32, 3), imageExtentCapacity(3));
}

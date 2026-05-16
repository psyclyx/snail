const std = @import("std");

const build_options = @import("build_options");
const coverage_mod = @import("coverage.zig");
const image_mod = @import("image.zig");
const lowlevel_mod = @import("lowlevel.zig");
const path_mod = @import("path.zig");
const resource_key_mod = @import("resource_key.zig");
const render_mod = @import("render.zig");
const upload_common = @import("renderer/upload_common.zig");
const upload_mod = @import("upload.zig");
const scene_mod = @import("scene.zig");
const text_mod = @import("text.zig");

const pipeline = if (build_options.enable_opengl) @import("renderer/gl.zig") else struct {
    pub const TextCoverageBindings = struct {};
    pub const GlTextState = void;
    pub const PreparedResources = void;
    pub const text_vertex_interface = "";
    pub const text_coverage_fragment_interface = "";
    pub const text_coverage_fragment_body = "";
};
const cpu_renderer_mod = if (build_options.enable_cpu) @import("renderer/cpu.zig") else struct {
    pub const PreparedResources = void;
};
const vulkan_pipeline = if (build_options.enable_vulkan) @import("renderer/vulkan.zig") else struct {
    pub const PreparedResources = void;
    pub const VulkanPipeline = void;
};

const Atlas = lowlevel_mod.Atlas;
const AtlasPage = lowlevel_mod.AtlasPage;
const Image = image_mod.Image;
const PathPicture = path_mod.PathPicture;
const PreparedAtlasView = lowlevel_mod.PreparedAtlasView;
const PreparedImageView = lowlevel_mod.PreparedImageView;
const PreparedLayerInfoUpload = lowlevel_mod.PreparedLayerInfoUpload;
const PreparedLayerInfoView = lowlevel_mod.PreparedLayerInfoView;
const PreparedTextAtlasView = lowlevel_mod.PreparedTextAtlasView;
const Renderer = render_mod.Renderer;
const ResourceCapacityMode = upload_common.AtlasCapacityMode;
const ResourceFootprint = upload_mod.ResourceFootprint;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceStamp = resource_key_mod.ResourceStamp;
const Scene = scene_mod.Scene;
const TextAtlas = text_mod.TextAtlas;
const TextBlob = text_mod.TextBlob;
const CoverageBackend = coverage_mod.Backend;
const UploadAllocators = upload_mod.UploadAllocators;
const mix64 = resource_key_mod.mix64;
const pointerResourceKey = resource_key_mod.pointerResourceKey;
const resourceKey = resource_key_mod.resourceKey;

pub const ResourceSet = struct {
    /// Caller-buffered CPU manifest. Entries point at app-owned
    /// TextAtlas, PathPicture, and Image values; no upload happens here.
    entries: []Entry = &.{},
    len: usize = 0,

    pub const Entry = union(enum) {
        text_atlas: TextAtlasEntry,
        text_paint: TextPaintEntry,
        path_picture: PathPictureEntry,
        image: ImageEntry,
    };

    pub const TextAtlasEntry = struct {
        key: ResourceKey,
        atlas: *const TextAtlas,
        atlas_capacity: ResourceCapacityMode = .growable,
    };

    pub const PathPictureEntry = struct {
        key: ResourceKey,
        picture: *const PathPicture,
        atlas_capacity: ResourceCapacityMode = .exact,
    };

    pub const TextPaintEntry = struct {
        key: ResourceKey,
        blob: *const TextBlob,
    };

    pub const ImageEntry = struct {
        key: ResourceKey,
        image: *const Image,
    };

    pub const TextAtlasOptions = struct {
        atlas_capacity: ResourceCapacityMode = .growable,
    };

    pub const PathPictureOptions = struct {
        atlas_capacity: ResourceCapacityMode = .exact,
    };

    pub fn init(entries: []Entry) ResourceSet {
        return .{ .entries = entries };
    }

    pub fn capacity(self: *const ResourceSet) usize {
        return self.entries.len;
    }

    pub fn reset(self: *ResourceSet) void {
        self.len = 0;
    }

    pub fn putTextAtlas(self: *ResourceSet, key_value: anytype, atlas: *const TextAtlas) !void {
        try self.putTextAtlasOptions(key_value, atlas, .{});
    }

    pub fn putTextAtlasOptions(self: *ResourceSet, key_value: anytype, atlas: *const TextAtlas, options: TextAtlasOptions) !void {
        try self.put(.{ .text_atlas = .{
            .key = resourceKey(key_value),
            .atlas = atlas,
            .atlas_capacity = options.atlas_capacity,
        } });
    }

    pub fn putPathPicture(self: *ResourceSet, key_value: anytype, picture: *const PathPicture) !void {
        try self.putPathPictureOptions(key_value, picture, .{});
    }

    pub fn putPathPictureOptions(self: *ResourceSet, key_value: anytype, picture: *const PathPicture, options: PathPictureOptions) !void {
        try self.put(.{ .path_picture = .{
            .key = resourceKey(key_value),
            .picture = picture,
            .atlas_capacity = options.atlas_capacity,
        } });
    }

    pub fn putImage(self: *ResourceSet, key_value: anytype, image: *const Image) !void {
        try self.put(.{ .image = .{ .key = resourceKey(key_value), .image = image } });
    }

    pub fn addScene(self: *ResourceSet, scene: *const Scene) !void {
        for (scene.commands.items) |command| {
            switch (command) {
                .text => |text| {
                    try self.put(.{ .text_atlas = .{
                        .key = pointerResourceKey("scene.text_atlas", text.blob.atlas),
                        .atlas = text.blob.atlas,
                    } });
                    if (text.blob.hasPaintRecords()) {
                        try self.put(.{ .text_paint = .{
                            .key = pointerResourceKey("scene.text_paint", text.blob),
                            .blob = text.blob,
                        } });
                    }
                },
                .path => |path| try self.put(.{ .path_picture = .{
                    .key = pointerResourceKey("scene.path_picture", path.picture),
                    .picture = path.picture,
                } }),
            }
        }
    }

    fn put(self: *ResourceSet, entry: Entry) !void {
        const key = entryKey(entry);
        for (self.entries[0..self.len], 0..) |existing, i| {
            if (entryKey(existing).eql(key)) {
                self.entries[i] = entry;
                return;
            }
        }
        if (self.len >= self.entries.len) return error.ResourceSetFull;
        self.entries[self.len] = entry;
        self.len += 1;
    }

    fn entryKey(entry: Entry) ResourceKey {
        return switch (entry) {
            .text_atlas => |text| text.key,
            .text_paint => |text| text.key,
            .path_picture => |path| path.key,
            .image => |image| image.key,
        };
    }

    pub fn slice(self: *const ResourceSet) []const Entry {
        return self.entries[0..self.len];
    }

    pub fn estimateUploadFootprint(self: *const ResourceSet) !ResourceFootprint {
        return resourceSetUploadFootprint(self);
    }
};

pub const PreparedResources = struct {
    allocator: std.mem.Allocator,
    /// Validated bindings for one renderer/context. GPU backends point at
    /// renderer-owned resident caches; CPU prepared resources still own their
    /// prepared curve sidecars and borrow immutable source data.
    atlases: []PreparedAtlasResource = &.{},
    layer_infos: []PreparedLayerInfoResource = &.{},
    images: []PreparedImageResource = &.{},
    gl: if (build_options.enable_opengl) ?*pipeline.PreparedResources else void = if (build_options.enable_opengl) null else {},
    vulkan: if (build_options.enable_vulkan) ?*vulkan_pipeline.PreparedResources else void = if (build_options.enable_vulkan) null else {},
    cpu: if (build_options.enable_cpu) ?cpu_renderer_mod.PreparedResources else void = if (build_options.enable_cpu) null else {},
    backend_generation: u64 = 0,

    pub const PreparedAtlasKind = enum {
        text,
        path,
    };

    pub const PreparedAtlasResource = struct {
        key: ResourceKey,
        kind: PreparedAtlasKind,
        text_atlas: ?*const TextAtlas = null,
        picture: ?*const PathPicture = null,
        atlas: *const Atlas,
        wrapper: Atlas = undefined,
        owns_wrapper: bool = false,
        view: PreparedAtlasView = undefined,
        stamp: ResourceStamp,
    };

    pub const PreparedLayerInfoResource = struct {
        key: ResourceKey,
        text_blob: *const TextBlob,
        view: PreparedLayerInfoView = undefined,
        stamp: ResourceStamp,
    };

    pub const PreparedImageResource = struct {
        key: ResourceKey,
        image: *const Image,
        view: PreparedImageView = undefined,
        stamp: ResourceStamp,
    };

    pub fn deinit(self: *PreparedResources) void {
        if (comptime build_options.enable_cpu) {
            if (self.cpu) |*cpu_resources| cpu_resources.deinit();
        }
        for (self.atlases) |*entry| {
            if (entry.owns_wrapper) switch (entry.kind) {
                .text => entry.text_atlas.?.deinitUploadAtlas(&entry.wrapper),
                .path => {},
            };
        }
        if (self.atlases.len > 0) self.allocator.free(self.atlases);
        if (self.layer_infos.len > 0) self.allocator.free(self.layer_infos);
        if (self.images.len > 0) self.allocator.free(self.images);
        self.* = undefined;
    }

    pub fn retireNow(self: *PreparedResources) void {
        self.deinit();
    }

    pub fn retireAfter(self: *PreparedResources, queue: *PreparedResourceRetirementQueue, fence_or_frame: anytype) !void {
        try queue.retireAfter(self, fence_or_frame);
    }

    pub fn stampForKey(self: *const PreparedResources, key_value: anytype) ?ResourceStamp {
        const key = resourceKey(key_value);
        for (self.atlases) |entry| if (entry.key.eql(key)) return entry.stamp;
        for (self.layer_infos) |entry| if (entry.key.eql(key)) return entry.stamp;
        for (self.images) |entry| if (entry.key.eql(key)) return entry.stamp;
        return null;
    }

    pub fn coverageBackend(self: *const PreparedResources, renderer: *Renderer) ?CoverageBackend {
        switch (renderer.backend()) {
            .gl => if (comptime build_options.enable_opengl) {
                if (self.gl) |gl_resources| {
                    return .{ .gl = .{
                        .gl = @ptrCast(@alignCast(renderer.ptr)),
                        .gl_resources = gl_resources,
                        .prepared = self,
                    } };
                }
            },
            .vulkan => if (comptime build_options.enable_vulkan) {
                if (self.vulkan) |vk_resources| {
                    return .{ .vulkan = .{
                        .vk = @ptrCast(@alignCast(renderer.ptr)),
                        .vk_resources = vk_resources,
                        .prepared = self,
                    } };
                }
            },
            .cpu => {},
        }
        return null;
    }

    fn textAtlasEntry(self: *const PreparedResources, atlas: *const TextAtlas) ?*const PreparedAtlasResource {
        for (self.atlases) |*entry| {
            if (entry.kind == .text and entry.text_atlas == atlas) return entry;
        }
        return null;
    }

    fn textPaintEntry(self: *const PreparedResources, blob: *const TextBlob) ?*const PreparedLayerInfoResource {
        for (self.layer_infos) |*entry| {
            if (entry.text_blob == blob) return entry;
        }
        return null;
    }

    fn pathPictureEntry(self: *const PreparedResources, picture: *const PathPicture) ?*const PreparedAtlasResource {
        for (self.atlases) |*entry| {
            if (entry.kind == .path and entry.picture == picture) return entry;
        }
        return null;
    }

    pub fn textAtlasView(self: *const PreparedResources, atlas: *const TextAtlas) !PreparedTextAtlasView {
        const entry = self.textAtlasEntry(atlas) orelse return error.MissingPreparedResource;
        return .{
            .layer_base = entry.view.layer_base,
            .info_row_base = entry.view.info_row_base,
        };
    }

    pub fn textAtlasKey(self: *const PreparedResources, atlas: *const TextAtlas) !ResourceKey {
        return (self.textAtlasEntry(atlas) orelse return error.MissingPreparedResource).key;
    }

    pub fn textPaintView(self: *const PreparedResources, blob: *const TextBlob) !PreparedLayerInfoView {
        const entry = self.textPaintEntry(blob) orelse return error.MissingPreparedResource;
        return entry.view;
    }

    pub fn textPaintKey(self: *const PreparedResources, blob: *const TextBlob) !ResourceKey {
        return (self.textPaintEntry(blob) orelse return error.MissingPreparedResource).key;
    }

    pub fn pathAtlasView(self: *const PreparedResources, picture: *const PathPicture) !PreparedAtlasView {
        const entry = self.pathPictureEntry(picture) orelse return error.MissingPreparedResource;
        return entry.view;
    }

    pub fn pathPictureKey(self: *const PreparedResources, picture: *const PathPicture) !ResourceKey {
        return (self.pathPictureEntry(picture) orelse return error.MissingPreparedResource).key;
    }

    pub fn textStamp(self: *const PreparedResources, atlas: *const TextAtlas) !ResourceStamp {
        return (self.textAtlasEntry(atlas) orelse return error.MissingPreparedResource).stamp;
    }

    pub fn textPaintStamp(self: *const PreparedResources, blob: *const TextBlob) !ResourceStamp {
        return (self.textPaintEntry(blob) orelse return error.MissingPreparedResource).stamp;
    }

    pub fn pathStamp(self: *const PreparedResources, picture: *const PathPicture) !ResourceStamp {
        return (self.pathPictureEntry(picture) orelse return error.MissingPreparedResource).stamp;
    }
};

const VulkanRetirementFence = if (build_options.enable_vulkan) struct {
    device: vulkan_pipeline.vk.VkDevice,
    fence: vulkan_pipeline.vk.VkFence,
} else void;

pub const PreparedResourceRetirementQueue = struct {
    allocator: std.mem.Allocator,
    head: ?*Node = null,

    const Node = struct {
        resources: PreparedResources,
        vulkan_fence: if (build_options.enable_vulkan) ?VulkanRetirementFence else void = if (build_options.enable_vulkan) null else {},
        next: ?*Node = null,
    };

    pub fn init(allocator: std.mem.Allocator) PreparedResourceRetirementQueue {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PreparedResourceRetirementQueue) void {
        while (self.head) |node| {
            self.head = node.next;
            var resources = node.resources;
            resources.deinit();
            self.allocator.destroy(node);
        }
        self.* = undefined;
    }

    pub fn sweep(self: *PreparedResourceRetirementQueue) void {
        var link = &self.head;
        while (link.*) |node| {
            if (ready(node)) {
                link.* = node.next;
                var resources = node.resources;
                resources.deinit();
                self.allocator.destroy(node);
            } else {
                link = &node.next;
            }
        }
    }

    pub fn retireAfter(self: *PreparedResourceRetirementQueue, resources: *PreparedResources, fence_or_frame: anytype) !void {
        self.sweep();
        if (comptime build_options.enable_vulkan) {
            if (resources.vulkan != null) {
                const fence = preparedRetirementFence(resources, fence_or_frame) orelse return error.InvalidRetirementFence;
                const node = try self.allocator.create(Node);
                node.* = .{
                    .resources = resources.*,
                    .vulkan_fence = fence,
                    .next = self.head,
                };
                self.head = node;
                resources.* = undefined;
                return;
            }
        }
        resources.deinit();
    }

    fn ready(node: *const Node) bool {
        if (comptime build_options.enable_vulkan) {
            if (node.vulkan_fence) |fence| {
                const result = vulkan_pipeline.vk.vkGetFenceStatus(fence.device, fence.fence);
                return result == vulkan_pipeline.vk.VK_SUCCESS or result == vulkan_pipeline.vk.VK_ERROR_DEVICE_LOST;
            }
        }
        return true;
    }
};

fn preparedRetirementFence(resources: *const PreparedResources, fence_or_frame: anytype) ?VulkanRetirementFence {
    if (comptime !build_options.enable_vulkan) return null;
    const vk_resources = resources.vulkan orelse return null;
    const T = @TypeOf(fence_or_frame);
    switch (@typeInfo(T)) {
        .@"struct" => {
            if (@hasField(T, "fence")) return makeVulkanRetirementFence(vk_resources.ctx.device, fence_or_frame.fence);
            return null;
        },
        else => return makeVulkanRetirementFence(vk_resources.ctx.device, fence_or_frame),
    }
}

fn makeVulkanRetirementFence(device: if (build_options.enable_vulkan) vulkan_pipeline.vk.VkDevice else void, fence: anytype) ?VulkanRetirementFence {
    if (comptime !build_options.enable_vulkan) return null;
    const T = @TypeOf(fence);
    switch (@typeInfo(T)) {
        .pointer, .optional => {
            const vk_fence: vulkan_pipeline.vk.VkFence = @ptrCast(fence);
            if (vk_fence == null) return null;
            return .{ .device = device, .fence = vk_fence };
        },
        else => return null,
    }
}

fn textAtlasStamp(atlas: *const TextAtlas) ResourceStamp {
    var layout = mix64(@as(u64, @intCast(atlas.pageCount())), @as(u64, atlas.layer_info_width));
    layout = mix64(layout, atlas.layer_info_height);
    var content = atlas.snapshotIdentity();
    for (atlas.pageSlice()) |page| {
        content = mix64(content, @intCast(@intFromPtr(page)));
        content = mix64(content, page.textureBytes());
    }
    return .{
        .identity = atlas.snapshotIdentity(),
        .layout = layout,
        .content = content,
    };
}

fn textPaintStamp(blob: *const TextBlob) ResourceStamp {
    const atlas_stamp = textAtlasStamp(blob.atlas);
    var layout = mix64(atlas_stamp.layout, blob.paint_layer_info_width);
    layout = mix64(layout, blob.paint_layer_info_height);
    var content = atlas_stamp.content;
    if (blob.paint_layer_info_data) |data| {
        content = mix64(content, std.hash.Wyhash.hash(0x544558545041494e, std.mem.sliceAsBytes(data)));
    }
    if (blob.paint_image_records) |records| {
        for (records) |record| {
            const image = (record orelse continue).image;
            const stamp = imageStamp(image);
            content = mix64(content, stamp.identity);
            content = mix64(content, stamp.layout);
            content = mix64(content, stamp.content);
        }
    }
    return .{
        .identity = mix64(@intCast(@intFromPtr(blob)), atlas_stamp.identity),
        .layout = layout,
        .content = content,
    };
}

fn pathPictureStamp(picture: *const PathPicture) ResourceStamp {
    var layout = mix64(@as(u64, @intCast(picture.shapeCount())), picture.atlas.pageCount());
    layout = mix64(layout, picture.atlas.layer_info_width);
    layout = mix64(layout, picture.atlas.layer_info_height);
    var content = @as(u64, @intCast(@intFromPtr(picture)));
    for (picture.atlas.pages) |page| {
        content = mix64(content, @intCast(@intFromPtr(page)));
        content = mix64(content, page.textureBytes());
    }
    if (picture.atlas.layer_info_data) |data| {
        content = mix64(content, std.hash.Wyhash.hash(0x5041544850494354, std.mem.sliceAsBytes(data)));
    }
    return .{
        .identity = @intCast(@intFromPtr(picture)),
        .layout = layout,
        .content = content,
    };
}

fn imageStamp(image: *const Image) ResourceStamp {
    const pixels = image.pixelSlice();
    return .{
        .identity = @intCast(@intFromPtr(image)),
        .layout = mix64(@as(u64, image.width), image.height),
        .content = std.hash.Wyhash.hash(0x494d414745535247, pixels),
    };
}

const CURVE_TEXEL_BYTES: usize = 8; // RGBA16F
const BAND_TEXEL_BYTES: usize = 4; // RG16UI
const LAYER_INFO_TEXEL_BYTES: usize = 16; // RGBA32F
const IMAGE_TEXEL_BYTES: usize = 4; // SRGBA8

fn imageTextureBytes(image: *const Image) usize {
    return image_mod.textureBytes(image);
}

fn imageAllocatedBytes(image: *const Image) usize {
    return image_mod.allocatedBytes(image);
}

fn addLayerInfoFootprint(out: *ResourceFootprint, data: ?[]const f32, width: u32, height: u32) void {
    if (data) |d| out.layer_info_bytes_used += d.len * @sizeOf(f32);
    if (height > 0) {
        out.layer_info_bytes_allocated += @as(usize, @max(width, 1)) *
            @as(usize, height) *
            LAYER_INFO_TEXEL_BYTES;
    }
}

pub fn curveAtlasFootprint(atlas: *const Atlas, capacity_mode: ResourceCapacityMode) ResourceFootprint {
    var out: ResourceFootprint = .{};
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var first_page: ?*const AtlasPage = null;

    for (0..atlas.pageCount()) |i| {
        const page_ref = atlas.page(@intCast(i));
        if (first_page == null) first_page = page_ref;
        out.curve_bytes_used += page_ref.curveTextureBytes();
        out.band_bytes_used += page_ref.bandTextureBytes();
        max_curve_h = @max(max_curve_h, page_ref.curve_height);
        max_band_h = @max(max_band_h, page_ref.band_height);
    }

    if (first_page) |page_ref| {
        const capacity = upload_common.atlasCapacityForMode(@intCast(atlas.pageCount()), capacity_mode);
        out.curve_bytes_allocated = @as(usize, page_ref.curve_width) *
            @as(usize, upload_common.heightCapacity(max_curve_h)) *
            @as(usize, capacity) *
            CURVE_TEXEL_BYTES;
        out.band_bytes_allocated = @as(usize, page_ref.band_width) *
            @as(usize, upload_common.heightCapacity(max_band_h)) *
            @as(usize, capacity) *
            BAND_TEXEL_BYTES;
    }

    addLayerInfoFootprint(&out, atlas.layer_info_data, atlas.layer_info_width, atlas.layer_info_height);
    return out;
}

pub fn textAtlasUploadFootprint(atlas: *const TextAtlas) ResourceFootprint {
    var out: ResourceFootprint = .{};
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var first_page: ?*const AtlasPage = null;

    for (atlas.pageSlice()) |page_ref| {
        if (first_page == null) first_page = page_ref;
        out.curve_bytes_used += page_ref.curveTextureBytes();
        out.band_bytes_used += page_ref.bandTextureBytes();
        max_curve_h = @max(max_curve_h, page_ref.curve_height);
        max_band_h = @max(max_band_h, page_ref.band_height);
    }

    if (first_page) |page_ref| {
        const capacity = upload_common.atlasCapacityForMode(@intCast(atlas.pageCount()), .growable);
        out.curve_bytes_allocated = @as(usize, page_ref.curve_width) *
            @as(usize, upload_common.heightCapacity(max_curve_h)) *
            @as(usize, capacity) *
            CURVE_TEXEL_BYTES;
        out.band_bytes_allocated = @as(usize, page_ref.band_width) *
            @as(usize, upload_common.heightCapacity(max_band_h)) *
            @as(usize, capacity) *
            BAND_TEXEL_BYTES;
    }

    addLayerInfoFootprint(&out, atlas.layer_info_data, atlas.layer_info_width, atlas.layer_info_height);
    return out;
}

fn curveAtlasUploadBytes(atlas: *const Atlas) usize {
    var total: usize = 0;
    for (0..atlas.pageCount()) |i| {
        total += atlas.page(@intCast(i)).textureBytes();
    }
    if (atlas.layer_info_data) |data| total += data.len * @sizeOf(f32);
    if (atlas.paint_image_records) |records| {
        for (records) |record| {
            const image = (record orelse continue).image;
            total += image.pixelSlice().len;
        }
    }
    return total;
}

fn textAtlasUploadBytes(atlas: *const TextAtlas) usize {
    var total: usize = 0;
    for (atlas.pageSlice()) |page| total += page.textureBytes();
    if (atlas.layer_info_data) |data| total += data.len * @sizeOf(f32);
    return total;
}

fn textPaintUploadBytes(blob: *const TextBlob) usize {
    var total: usize = 0;
    if (blob.paint_layer_info_data) |data| total += data.len * @sizeOf(f32);
    if (blob.paint_image_records) |records| {
        for (records) |record| {
            const image = (record orelse continue).image;
            total += image.pixelSlice().len;
        }
    }
    return total;
}

fn textPaintLayerInfoUpload(blob: *const TextBlob) PreparedLayerInfoUpload {
    return .{
        .data = blob.paint_layer_info_data,
        .width = blob.paint_layer_info_width,
        .height = blob.paint_layer_info_height,
        .paint_image_records = blob.paint_image_records,
    };
}

pub fn resourceEntryKey(entry: ResourceSet.Entry) ResourceKey {
    return switch (entry) {
        .text_atlas => |text| text.key,
        .text_paint => |text| text.key,
        .path_picture => |path| path.key,
        .image => |image| image.key,
    };
}

pub fn resourceEntryStamp(entry: ResourceSet.Entry) ResourceStamp {
    return switch (entry) {
        .text_atlas => |text| textAtlasStamp(text.atlas),
        .text_paint => |text| textPaintStamp(text.blob),
        .path_picture => |path| pathPictureStamp(path.picture),
        .image => |image| imageStamp(image.image),
    };
}

pub fn resourceEntryUploadBytes(entry: ResourceSet.Entry) usize {
    return switch (entry) {
        .text_atlas => |text| textAtlasUploadBytes(text.atlas),
        .text_paint => |text| textPaintUploadBytes(text.blob),
        .path_picture => |path| curveAtlasUploadBytes(&path.picture.atlas),
        .image => |image| image.image.pixelSlice().len,
    };
}

fn entryPaintImageRecords(entry: ResourceSet.Entry) ?[]const ?Atlas.PaintImageRecord {
    return switch (entry) {
        .text_paint => |text| text.blob.paint_image_records,
        .path_picture => |path| path.picture.atlas.paint_image_records,
        else => null,
    };
}

fn entryReferencesImage(entry: ResourceSet.Entry, image: *const Image) bool {
    switch (entry) {
        .image => |entry_image| if (entry_image.image == image) return true,
        else => {},
    }
    const records = entryPaintImageRecords(entry) orelse return false;
    for (records) |record| {
        if ((record orelse continue).image == image) return true;
    }
    return false;
}

fn entryReferencesImageBeforeRecord(entry: ResourceSet.Entry, image: *const Image, record_limit: usize) bool {
    const records = entryPaintImageRecords(entry) orelse return false;
    for (records[0..@min(record_limit, records.len)]) |record| {
        if ((record orelse continue).image == image) return true;
    }
    return false;
}

fn resourceSetSawImageBefore(set: *const ResourceSet, entry_index: usize, record_index: ?usize, image: *const Image) bool {
    const entries = set.slice();
    for (entries[0..entry_index]) |entry| {
        if (entryReferencesImage(entry, image)) return true;
    }
    if (record_index) |limit| {
        return entryReferencesImageBeforeRecord(entries[entry_index], image, limit);
    }
    return false;
}

fn addImageFootprintIfFirst(
    out: *ResourceFootprint,
    set: *const ResourceSet,
    entry_index: usize,
    record_index: ?usize,
    image: *const Image,
    image_count: *usize,
    max_image_width: *u32,
    max_image_height: *u32,
) void {
    if (resourceSetSawImageBefore(set, entry_index, record_index, image)) return;
    out.image_bytes_used += imageTextureBytes(image);
    max_image_width.* = @max(max_image_width.*, image.width);
    max_image_height.* = @max(max_image_height.*, image.height);
    image_count.* += 1;
}

fn resourceSetUploadFootprint(set: *const ResourceSet) !ResourceFootprint {
    var out: ResourceFootprint = .{};
    var atlas_count: usize = 0;
    var total_layer_capacity: u32 = 0;
    var first_page: ?*const AtlasPage = null;
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var total_layer_info_rows: u32 = 0;
    var max_layer_info_width: u32 = 1;

    var image_count: usize = 0;
    var max_image_width: u32 = 1;
    var max_image_height: u32 = 1;

    for (set.slice(), 0..) |entry, entry_index| {
        switch (entry) {
            .text_atlas => |text| {
                atlas_count += 1;
                const atlas = text.atlas;
                if (atlas.pageCount() > std.math.maxInt(u16)) return error.AtlasPageCountOverflow;
                total_layer_capacity = try std.math.add(u32, total_layer_capacity, upload_common.atlasCapacityForMode(@intCast(atlas.pageCount()), text.atlas_capacity));
                for (atlas.pageSlice()) |page_ref| {
                    if (first_page == null) first_page = page_ref;
                    out.curve_bytes_used += page_ref.curveTextureBytes();
                    out.band_bytes_used += page_ref.bandTextureBytes();
                    max_curve_h = @max(max_curve_h, page_ref.curve_height);
                    max_band_h = @max(max_band_h, page_ref.band_height);
                }
                if (atlas.layer_info_data) |data| out.layer_info_bytes_used += data.len * @sizeOf(f32);
                if (atlas.layer_info_height > 0) {
                    total_layer_info_rows += atlas.layer_info_height;
                    max_layer_info_width = @max(max_layer_info_width, atlas.layer_info_width);
                }
            },
            .text_paint => |text| {
                atlas_count += 1;
                const blob = text.blob;
                if (blob.paint_layer_info_data) |data| out.layer_info_bytes_used += data.len * @sizeOf(f32);
                if (blob.paint_layer_info_height > 0) {
                    total_layer_info_rows += blob.paint_layer_info_height;
                    max_layer_info_width = @max(max_layer_info_width, blob.paint_layer_info_width);
                }
                if (blob.paint_image_records) |records| {
                    for (records, 0..) |record, record_index| {
                        addImageFootprintIfFirst(&out, set, entry_index, record_index, (record orelse continue).image, &image_count, &max_image_width, &max_image_height);
                    }
                }
            },
            .path_picture => |path| {
                atlas_count += 1;
                const atlas = &path.picture.atlas;
                if (atlas.pageCount() > std.math.maxInt(u16)) return error.AtlasPageCountOverflow;
                total_layer_capacity = try std.math.add(u32, total_layer_capacity, upload_common.atlasCapacityForMode(@intCast(atlas.pageCount()), path.atlas_capacity));
                for (0..atlas.pageCount()) |i| {
                    const page_ref = atlas.page(@intCast(i));
                    if (first_page == null) first_page = page_ref;
                    out.curve_bytes_used += page_ref.curveTextureBytes();
                    out.band_bytes_used += page_ref.bandTextureBytes();
                    max_curve_h = @max(max_curve_h, page_ref.curve_height);
                    max_band_h = @max(max_band_h, page_ref.band_height);
                }
                if (atlas.layer_info_data) |data| out.layer_info_bytes_used += data.len * @sizeOf(f32);
                if (atlas.layer_info_height > 0) {
                    total_layer_info_rows += atlas.layer_info_height;
                    max_layer_info_width = @max(max_layer_info_width, atlas.layer_info_width);
                }
                if (atlas.paint_image_records) |records| {
                    for (records, 0..) |record, record_index| {
                        addImageFootprintIfFirst(&out, set, entry_index, record_index, (record orelse continue).image, &image_count, &max_image_width, &max_image_height);
                    }
                }
            },
            .image => |image| addImageFootprintIfFirst(&out, set, entry_index, null, image.image, &image_count, &max_image_width, &max_image_height),
        }
    }

    if (first_page) |page_ref| {
        out.curve_bytes_allocated = @as(usize, page_ref.curve_width) *
            @as(usize, upload_common.heightCapacity(max_curve_h)) *
            @as(usize, total_layer_capacity) *
            CURVE_TEXEL_BYTES;
        out.band_bytes_allocated = @as(usize, page_ref.band_width) *
            @as(usize, upload_common.heightCapacity(max_band_h)) *
            @as(usize, total_layer_capacity) *
            BAND_TEXEL_BYTES;
    }

    if (total_layer_info_rows > 0) {
        out.layer_info_bytes_allocated = @as(usize, max_layer_info_width) *
            @as(usize, total_layer_info_rows) *
            LAYER_INFO_TEXEL_BYTES;
    }

    if (image_count > 0) {
        if (image_count > std.math.maxInt(u32)) return error.ImageLayerCountOverflow;
        out.image_bytes_allocated = @as(usize, upload_common.imageExtentCapacity(max_image_width)) *
            @as(usize, upload_common.imageExtentCapacity(max_image_height)) *
            @as(usize, upload_common.imageCapacity(@intCast(image_count))) *
            IMAGE_TEXEL_BYTES;
    }

    return out;
}

pub fn uploadPreparedResources(renderer: *Renderer, set: *const ResourceSet, allocators: UploadAllocators) !PreparedResources {
    const persistent = allocators.persistent;
    const scratch = allocators.scratch;
    var atlas_count: usize = 0;
    var layer_info_count: usize = 0;
    var image_count: usize = 0;
    for (set.slice()) |entry| switch (entry) {
        .text_atlas, .path_picture => atlas_count += 1,
        .text_paint => layer_info_count += 1,
        .image => image_count += 1,
    };

    var prepared = PreparedResources{
        .allocator = persistent,
        .atlases = try persistent.alloc(PreparedResources.PreparedAtlasResource, atlas_count),
        .layer_infos = try persistent.alloc(PreparedResources.PreparedLayerInfoResource, layer_info_count),
        .images = try persistent.alloc(PreparedResources.PreparedImageResource, image_count),
    };
    errdefer prepared.deinit();

    const upload_atlases = try scratch.alloc(*const Atlas, atlas_count);
    defer scratch.free(upload_atlases);
    const atlas_capacity_modes = try scratch.alloc(upload_common.AtlasCapacityMode, atlas_count);
    defer scratch.free(atlas_capacity_modes);
    const atlas_views = try scratch.alloc(PreparedAtlasView, atlas_count);
    defer scratch.free(atlas_views);

    const upload_layer_infos = try scratch.alloc(PreparedLayerInfoUpload, layer_info_count);
    defer scratch.free(upload_layer_infos);
    const layer_info_views = try scratch.alloc(PreparedLayerInfoView, layer_info_count);
    defer scratch.free(layer_info_views);

    const upload_images = try scratch.alloc(*const Image, image_count);
    defer scratch.free(upload_images);
    const image_views = try scratch.alloc(PreparedImageView, image_count);
    defer scratch.free(image_views);

    var atlas_i: usize = 0;
    var layer_info_i: usize = 0;
    var image_i: usize = 0;
    for (set.slice()) |entry| {
        switch (entry) {
            .text_atlas => |text| {
                prepared.atlases[atlas_i] = .{
                    .key = text.key,
                    .kind = .text,
                    .text_atlas = text.atlas,
                    .atlas = undefined,
                    .owns_wrapper = true,
                    .stamp = textAtlasStamp(text.atlas),
                };
                prepared.atlases[atlas_i].wrapper = text.atlas.uploadAtlas();
                prepared.atlases[atlas_i].atlas = &prepared.atlases[atlas_i].wrapper;
                upload_atlases[atlas_i] = prepared.atlases[atlas_i].atlas;
                atlas_capacity_modes[atlas_i] = text.atlas_capacity;
                atlas_i += 1;
            },
            .text_paint => |text| {
                prepared.layer_infos[layer_info_i] = .{
                    .key = text.key,
                    .text_blob = text.blob,
                    .stamp = textPaintStamp(text.blob),
                };
                upload_layer_infos[layer_info_i] = textPaintLayerInfoUpload(text.blob);
                layer_info_i += 1;
            },
            .path_picture => |path| {
                prepared.atlases[atlas_i] = .{
                    .key = path.key,
                    .kind = .path,
                    .picture = path.picture,
                    .atlas = &path.picture.atlas,
                    .stamp = pathPictureStamp(path.picture),
                };
                upload_atlases[atlas_i] = prepared.atlases[atlas_i].atlas;
                atlas_capacity_modes[atlas_i] = path.atlas_capacity;
                atlas_i += 1;
            },
            .image => |image| {
                prepared.images[image_i] = .{
                    .key = image.key,
                    .image = image.image,
                    .stamp = imageStamp(image.image),
                };
                upload_images[image_i] = image.image;
                image_i += 1;
            },
        }
    }

    const uploaded = blk: {
        if (comptime build_options.enable_opengl) {
            if (renderer.backend() == .gl) {
                const gl_state: *pipeline.GlTextState = @ptrCast(@alignCast(renderer.ptr));
                const gl_prepared = gl_state.resourceCache(persistent);
                if (atlas_count > 0 or layer_info_count > 0) try gl_prepared.uploadAtlasesAndLayerInfoWithCapacityModes(scratch, upload_atlases, atlas_capacity_modes[0..atlas_count], atlas_views, upload_layer_infos, layer_info_views);
                if (image_count > 0) try gl_prepared.uploadImages(scratch, upload_images, image_views);
                prepared.gl = gl_prepared;
                prepared.backend_generation = gl_prepared.generation;
                break :blk true;
            }
        }
        if (comptime build_options.enable_vulkan) {
            if (renderer.backend() == .vulkan) {
                const vk_state: *vulkan_pipeline.VulkanPipeline = @ptrCast(@alignCast(renderer.ptr));
                const vk_prepared = try vk_state.resourceCache(persistent);
                if (atlas_count > 0 or layer_info_count > 0) try vk_state.uploadPreparedAtlasesAndLayerInfoWithCapacityModes(vk_prepared, scratch, upload_atlases, atlas_capacity_modes[0..atlas_count], atlas_views, upload_layer_infos, layer_info_views);
                if (image_count > 0) try vk_state.uploadPreparedImages(vk_prepared, scratch, upload_images, image_views);
                prepared.vulkan = vk_prepared;
                prepared.backend_generation = vk_prepared.generation;
                break :blk true;
            }
        }
        if (comptime build_options.enable_cpu) {
            if (renderer.backend() == .cpu) {
                var cpu_prepared = try cpu_renderer_mod.PreparedResources.init(persistent, upload_atlases, upload_layer_infos);
                errdefer cpu_prepared.deinit();
                if (atlas_count > 0) try cpu_prepared.uploadAtlases(upload_atlases, atlas_views);
                if (layer_info_count > 0) try cpu_prepared.uploadLayerInfoBlocks(upload_layer_infos, layer_info_views);
                if (image_count > 0) cpu_prepared.uploadImages(upload_images, image_views);
                prepared.cpu = cpu_prepared;
                break :blk true;
            }
        }
        break :blk false;
    };
    if (!uploaded) return error.UnsupportedRenderer;

    for (prepared.atlases, 0..) |*entry, i| entry.view = atlas_views[i];
    for (prepared.layer_infos, 0..) |*entry, i| entry.view = layer_info_views[i];
    for (prepared.images, 0..) |*entry, i| entry.view = image_views[i];
    return prepared;
}

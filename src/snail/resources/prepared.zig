const std = @import("std");

const build_options = @import("build_options");
const coverage_mod = @import("../coverage.zig");
const resource_key_mod = @import("../resource_key.zig");
const atlas_page_mod = @import("../render/format/atlas/page.zig");
const view_mod = @import("view.zig");

const pipeline = if ((build_options.enable_gl33 or build_options.enable_gl44)) @import("../render/backend/gl/state.zig") else struct {
    pub const TextCoverageProgram = struct {};
    pub const Gl33PreparedResources = void;
    pub const Gl44PreparedResources = void;
    pub const text_vertex_interface = "";
    pub const text_coverage_fragment_interface = "";
    pub const text_coverage_fragment_body = "";
};
const gles3_pipeline = if (build_options.enable_gles3) @import("../render/backend/gles3/state.zig") else struct {
    pub const TextCoverageProgram = struct {};
    pub const Gles3TextState = void;
    pub const PreparedResources = void;
    pub const text_vertex_interface = "";
    pub const text_coverage_fragment_interface = "";
    pub const text_coverage_fragment_body = "";
};
const cpu_renderer_mod = if (build_options.enable_cpu) @import("../render/backend/cpu/renderer.zig") else struct {
    pub const PreparedResources = void;
};
const vulkan_pipeline = if (build_options.enable_vulkan) @import("../render/backend/vulkan/pipeline.zig") else struct {
    pub const PreparedResources = void;
    pub const VulkanPipeline = void;
};

const CoverageBackend = coverage_mod.Backend;
const PageFingerprint = atlas_page_mod.PageFingerprint;
const PreparedAtlasView = view_mod.PreparedAtlasView;
const PreparedLayerInfoView = view_mod.PreparedLayerInfoView;
const PreparedTextAtlasView = view_mod.PreparedTextAtlasView;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceStamp = resource_key_mod.ResourceStamp;

pub const PreparedManifest = struct {
    allocator: std.mem.Allocator,
    /// Validated bindings for one render/backend/context. GPU backends point at
    /// renderer-owned resident caches; CPU prepared resources own render-time
    /// snapshots for the data they sample.
    atlases: []PreparedAtlasResource = &.{},
    layer_infos: []PreparedLayerInfoResource = &.{},
    images: []PreparedImageResource = &.{},

    pub const PreparedAtlasKind = enum {
        text,
        path,
    };

    pub const PreparedAtlasResource = struct {
        key: ResourceKey = .{ .id = 0 },
        kind: PreparedAtlasKind = .text,
        page_fingerprints: []PageFingerprint = &.{},
        view: PreparedAtlasView = .{},
        owns_page_layers: bool = false,
        stamp: ResourceStamp = .{},
    };

    pub const PreparedLayerInfoResource = struct {
        key: ResourceKey = .{ .id = 0 },
        view: PreparedLayerInfoView = .{},
        stamp: ResourceStamp = .{},
    };

    pub const PreparedImageResource = struct {
        key: ResourceKey = .{ .id = 0 },
        stamp: ResourceStamp = .{},
    };

    pub fn deinit(self: *PreparedManifest) void {
        for (self.atlases) |*entry| {
            if (entry.page_fingerprints.len > 0) self.allocator.free(entry.page_fingerprints);
            if (entry.owns_page_layers and entry.view.page_layers.len > 0) self.allocator.free(entry.view.page_layers);
        }
        if (self.atlases.len > 0) self.allocator.free(self.atlases);
        if (self.layer_infos.len > 0) self.allocator.free(self.layer_infos);
        if (self.images.len > 0) self.allocator.free(self.images);
        self.* = undefined;
    }

    pub fn stampForKey(self: *const PreparedManifest, key: ResourceKey) ?ResourceStamp {
        for (self.atlases) |entry| if (entry.key.eql(key)) return entry.stamp;
        for (self.layer_infos) |entry| if (entry.key.eql(key)) return entry.stamp;
        for (self.images) |entry| if (entry.key.eql(key)) return entry.stamp;
        return null;
    }

    fn textAtlasEntry(self: *const PreparedManifest, key: ResourceKey) ?*const PreparedAtlasResource {
        for (self.atlases) |*entry| {
            if (entry.kind == .text and entry.key.eql(key)) return entry;
        }
        return null;
    }

    fn textPaintEntry(self: *const PreparedManifest, key: ResourceKey) ?*const PreparedLayerInfoResource {
        for (self.layer_infos) |*entry| {
            if (entry.key.eql(key)) return entry;
        }
        return null;
    }

    fn pathPictureEntry(self: *const PreparedManifest, key: ResourceKey) ?*const PreparedAtlasResource {
        for (self.atlases) |*entry| {
            if (entry.kind == .path and entry.key.eql(key)) return entry;
        }
        return null;
    }

    pub fn textAtlasView(self: *const PreparedManifest, key: ResourceKey) !PreparedTextAtlasView {
        const entry = self.textAtlasEntry(key) orelse return error.MissingPreparedResource;
        return .{
            .layer_base = entry.view.layer_base,
            .page_layers = entry.view.page_layers,
            .info_row_base = entry.view.info_row_base,
        };
    }

    pub fn textPaintView(self: *const PreparedManifest, key: ResourceKey) !PreparedLayerInfoView {
        const entry = self.textPaintEntry(key) orelse return error.MissingPreparedResource;
        return entry.view;
    }

    pub fn pathAtlasView(self: *const PreparedManifest, key: ResourceKey) !PreparedAtlasView {
        const entry = self.pathPictureEntry(key) orelse return error.MissingPreparedResource;
        return entry.view;
    }

    pub fn textStamp(self: *const PreparedManifest, key: ResourceKey) !ResourceStamp {
        return (self.textAtlasEntry(key) orelse return error.MissingPreparedResource).stamp;
    }

    pub fn textPaintStamp(self: *const PreparedManifest, key: ResourceKey) !ResourceStamp {
        return (self.textPaintEntry(key) orelse return error.MissingPreparedResource).stamp;
    }

    pub fn pathStamp(self: *const PreparedManifest, key: ResourceKey) !ResourceStamp {
        return (self.pathPictureEntry(key) orelse return error.MissingPreparedResource).stamp;
    }
};

pub const ResidentResources = struct {
    gl33: if (build_options.enable_gl33) ?*pipeline.Gl33PreparedResources else void = if (build_options.enable_gl33) null else {},
    gl44: if (build_options.enable_gl44) ?*pipeline.Gl44PreparedResources else void = if (build_options.enable_gl44) null else {},
    gles3: if (build_options.enable_gles3) ?*gles3_pipeline.PreparedResources else void = if (build_options.enable_gles3) null else {},
    vulkan: if (build_options.enable_vulkan) ?*vulkan_pipeline.PreparedResources else void = if (build_options.enable_vulkan) null else {},
    cpu: if (build_options.enable_cpu) ?cpu_renderer_mod.PreparedResources else void = if (build_options.enable_cpu) null else {},
    generation: u64 = 0,
    backend_refs_retained: bool = false,

    pub fn deinit(self: *ResidentResources) void {
        if (comptime build_options.enable_cpu) {
            if (self.cpu) |*cpu_resources| cpu_resources.deinit();
        }
        self.* = undefined;
    }
};

pub const PreparedResources = struct {
    manifest: PreparedManifest,
    resident: ResidentResources = .{},

    pub fn deinit(self: *PreparedResources) void {
        self.releaseResidentReferences();
        self.resident.deinit();
        self.manifest.deinit();
        self.* = undefined;
    }

    pub fn retainResidentReferences(self: *PreparedResources) void {
        if (self.resident.backend_refs_retained) return;
        var retained = false;
        if (comptime build_options.enable_gl33) {
            if (self.resident.gl33) |gl33_resources| {
                gl33_resources.retainPreparedResources(self.manifest, self.resident.generation);
                retained = true;
            }
        }
        if (comptime build_options.enable_gl44) {
            if (self.resident.gl44) |gl44_resources| {
                gl44_resources.retainPreparedResources(self.manifest, self.resident.generation);
                retained = true;
            }
        }
        if (comptime build_options.enable_gles3) {
            if (self.resident.gles3) |gles3_resources| {
                gles3_resources.retainPreparedResources(self.manifest, self.resident.generation);
                retained = true;
            }
        }
        if (comptime build_options.enable_vulkan) {
            if (self.resident.vulkan) |vk_resources| {
                vk_resources.retainPreparedResources(self.manifest, self.resident.generation);
                retained = true;
            }
        }
        self.resident.backend_refs_retained = retained;
    }

    fn releaseResidentReferences(self: *PreparedResources) void {
        if (!self.resident.backend_refs_retained) return;
        if (comptime build_options.enable_gl33) {
            if (self.resident.gl33) |gl33_resources| gl33_resources.releasePreparedResources(self.manifest, self.resident.generation);
        }
        if (comptime build_options.enable_gl44) {
            if (self.resident.gl44) |gl44_resources| gl44_resources.releasePreparedResources(self.manifest, self.resident.generation);
        }
        if (comptime build_options.enable_gles3) {
            if (self.resident.gles3) |gles3_resources| gles3_resources.releasePreparedResources(self.manifest, self.resident.generation);
        }
        if (comptime build_options.enable_vulkan) {
            if (self.resident.vulkan) |vk_resources| vk_resources.releasePreparedResources(self.manifest, self.resident.generation);
        }
        self.resident.backend_refs_retained = false;
    }

    pub fn retireNow(self: *PreparedResources) void {
        self.deinit();
    }

    pub fn retireAfter(self: *PreparedResources, queue: *PreparedResourceRetirementQueue, fence_or_frame: anytype) !void {
        try queue.retireAfter(self, fence_or_frame);
    }

    pub fn stampForKey(self: *const PreparedResources, key: ResourceKey) ?ResourceStamp {
        return self.manifest.stampForKey(key);
    }

    pub fn coverageBackend(self: *const PreparedResources, renderer: anytype) ?CoverageBackend {
        return renderer.coverageBackend(self);
    }

    pub fn textAtlasView(self: *const PreparedResources, key: ResourceKey) !PreparedTextAtlasView {
        return self.manifest.textAtlasView(key);
    }

    pub fn textPaintView(self: *const PreparedResources, key: ResourceKey) !PreparedLayerInfoView {
        return self.manifest.textPaintView(key);
    }

    pub fn pathAtlasView(self: *const PreparedResources, key: ResourceKey) !PreparedAtlasView {
        return self.manifest.pathAtlasView(key);
    }

    pub fn textStamp(self: *const PreparedResources, key: ResourceKey) !ResourceStamp {
        return self.manifest.textStamp(key);
    }

    pub fn textPaintStamp(self: *const PreparedResources, key: ResourceKey) !ResourceStamp {
        return self.manifest.textPaintStamp(key);
    }

    pub fn pathStamp(self: *const PreparedResources, key: ResourceKey) !ResourceStamp {
        return self.manifest.pathStamp(key);
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
            if (resources.resident.vulkan != null) {
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
    const vk_resources = resources.resident.vulkan orelse return null;
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

const std = @import("std");
const snail = @import("../root.zig");
const ttf = @import("../font/ttf.zig");

const build_options = @import("build_options");

pub const FontImpl = struct { inner: ttf.Font };
pub const TextAtlasImpl = struct { inner: snail.TextAtlas, allocator: std.mem.Allocator };
pub const ShapedTextImpl = struct { inner: snail.ShapedText };
pub const TextBlobImpl = struct { inner: snail.TextBlob };
pub const ImageImpl = struct { inner: snail.Image };
pub const PathImpl = struct { inner: snail.Path };
pub const PathPictureBuilderImpl = struct { inner: snail.PathPictureBuilder };
pub const PathPictureImpl = struct { inner: snail.PathPicture };
pub const SceneImpl = struct {
    inner: snail.Scene,
    // C callers can't keep an `[]Override` slice alive across the boundary,
    // so the C entry points that take a transform stash a single-element
    // override here and hand `inner` a slice into this arena. Reset alongside
    // `inner` so capacity is reused frame-to-frame.
    overrides_arena: std.heap.ArenaAllocator,
};
pub const ResourceSetImpl = struct {
    inner: snail.ResourceSet,
    entries: []snail.ResourceSet.Entry,
    allocator: std.mem.Allocator,
};
pub const PreparedResourcesImpl = struct { inner: snail.PreparedResources };
pub const PreparedSceneImpl = struct { inner: snail.PreparedScene };
pub const PreparedResourceRetirementQueueImpl = struct {
    inner: snail.PreparedResourceRetirementQueue,
    allocator: std.mem.Allocator,
};
pub const ResourceUploadPlanImpl = struct {
    inner: snail.ResourceUploadPlan,
};
pub const PendingResourceUploadImpl = struct {
    inner: snail.PendingResourceUpload,
};
pub const DrawListImpl = struct {
    inner: snail.DrawList,
    allocator: std.mem.Allocator,
    words: []u32,
    segments: []snail.DrawSegment,
};
pub const TextCoverageRecordsImpl = struct {
    inner: snail.coverage.TextCoverageRecords,
    allocator: std.mem.Allocator,
    words: []u32,
};
pub const CoverageBackendImpl = struct {
    inner: snail.coverage.Backend,
};
pub const ThreadPoolImpl = struct { inner: snail.ThreadPool };
pub const RendererImpl = struct {
    backend: snail.BackendKind,
    gl: if (build_options.enable_opengl) ?snail.GlRenderer else void = if (build_options.enable_opengl) null else {},
    vulkan: if (build_options.enable_vulkan) ?snail.VulkanRenderer else void = if (build_options.enable_vulkan) null else {},
    cpu: if (build_options.enable_cpu) ?snail.CpuRenderer else void = if (build_options.enable_cpu) null else {},

    pub fn asRenderer(self: *RendererImpl) snail.Renderer {
        return switch (self.backend) {
            .gl => blk: {
                if (comptime !build_options.enable_opengl) unreachable;
                if (self.gl) |*gl| break :blk gl.asRenderer();
                unreachable;
            },
            .vulkan => blk: {
                if (comptime !build_options.enable_vulkan) unreachable;
                if (self.vulkan) |*vk_renderer| break :blk vk_renderer.asRenderer();
                unreachable;
            },
            .cpu => blk: {
                if (comptime !build_options.enable_cpu) unreachable;
                if (self.cpu) |*cpu| break :blk cpu.asRenderer();
                unreachable;
            },
        };
    }

    pub fn deinit(self: *RendererImpl) void {
        switch (self.backend) {
            .gl => if (comptime build_options.enable_opengl) {
                if (self.gl) |*gl| gl.deinit();
            },
            .vulkan => if (comptime build_options.enable_vulkan) {
                if (self.vulkan) |*vk_renderer| vk_renderer.deinit();
            },
            .cpu => {},
        }
        self.* = undefined;
    }

    pub fn backendName(self: *const RendererImpl) []const u8 {
        return switch (self.backend) {
            .gl => if (comptime build_options.enable_opengl)
                self.gl.?.backendName()
            else
                "OpenGL (disabled)",
            .vulkan => if (comptime build_options.enable_vulkan)
                self.vulkan.?.backendName()
            else
                "vulkan (disabled)",
            .cpu => if (comptime build_options.enable_cpu)
                self.cpu.?.backendName()
            else
                "CPU (disabled)",
        };
    }
};

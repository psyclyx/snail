const std = @import("std");
const snail = @import("../root.zig");
const ttf = @import("../font/ttf.zig");
const c_runtime = @import("runtime.zig");

const build_options = @import("build_options");

pub const HandleAllocator = c_runtime.StoredAllocator;

pub const FontImpl = struct { handle_allocator: *HandleAllocator, inner: ttf.Font };
pub const TextAtlasImpl = struct { handle_allocator: *HandleAllocator, inner: snail.TextAtlas };
pub const ShapedTextImpl = struct { handle_allocator: *HandleAllocator, inner: snail.ShapedText };
pub const TextBlobImpl = struct {
    handle_allocator: *HandleAllocator,
    /// Snapshot of the bundle-owned blob's fields at finish/init time.
    /// All blobs come from a TextBlobBundle. Two ownership patterns:
    /// - If `owned_bundle` is non-null, this handle owns the bundle —
    ///   typically a small bundle created by the convenience init paths
    ///   (`snail_text_blob_init_*`, `snail_text_blob_rebound`). The
    ///   handle's deinit frees the bundle.
    /// - If `borrowed_from` is non-null, the bundle is externally owned
    ///   (typical for `snail_blob_in_progress_finish`). The handle's
    ///   deinit just frees the handle; the source bundle reclaims the
    ///   blob's storage on its own reset/deinit. Operations on a borrowed
    ///   blob whose `borrowed_generation` no longer matches the bundle's
    ///   `currentGeneration()` are invalid.
    inner: snail.TextBlob,
    owned_bundle: ?*snail.TextBlobBundle = null,
    borrowed_from: ?*TextBlobBundleImpl = null,
    borrowed_generation: u32 = 0,
};
pub const TextBlobBundleImpl = struct { handle_allocator: *HandleAllocator, inner: snail.TextBlobBundle };
pub const BlobInProgressImpl = struct {
    handle_allocator: *HandleAllocator,
    bundle: *TextBlobBundleImpl,
    /// Generation captured when this handle was created. Stored so the C
    /// side can detect a stray `start_blob` handle whose bundle was reset
    /// before `finish` / `abort` ran.
    generation: u32,
};
pub const TrueTypeHintContextImpl = struct { handle_allocator: *HandleAllocator, inner: snail.TrueTypeHintContext };
pub const TrueTypePreparedHintRunImpl = struct { handle_allocator: *HandleAllocator, inner: snail.TrueTypePreparedHintRun };
pub const ImageImpl = struct { handle_allocator: *HandleAllocator, inner: snail.Image };
pub const PathImpl = struct { handle_allocator: *HandleAllocator, inner: snail.Path };
pub const PathPictureBuilderImpl = struct { handle_allocator: *HandleAllocator, inner: snail.PathPictureBuilder };
pub const PathPictureImpl = struct { handle_allocator: *HandleAllocator, inner: snail.PathPicture };
pub const SceneImpl = struct {
    handle_allocator: *HandleAllocator,
    inner: snail.Scene,
    // C callers can't keep an `[]Override` slice alive across the boundary,
    // so the C entry points that take a transform stash a single-element
    // override here and hand `inner` a slice into this arena. Reset alongside
    // `inner` so capacity is reused frame-to-frame.
    overrides_arena: std.heap.ArenaAllocator,
};
pub const ResourceManifestImpl = struct {
    handle_allocator: *HandleAllocator,
    inner: snail.ResourceManifest,
    entries: []snail.ResourceManifest.Entry,
};
pub const PreparedResourcesImpl = struct { handle_allocator: *HandleAllocator, inner: snail.PreparedResources };
pub const PreparedSceneImpl = struct { handle_allocator: *HandleAllocator, inner: snail.PreparedScene };
pub const PreparedResourceRetirementQueueImpl = struct {
    handle_allocator: *HandleAllocator,
    inner: snail.PreparedResourceRetirementQueue,
    // Vulkan retirement can move PreparedResources into the core queue after
    // the C handle is destroyed. Keep those payload allocators alive until the
    // retirement queue itself is destroyed.
    retained_resource_allocators: std.ArrayListUnmanaged(*HandleAllocator) = .empty,
};
pub const ResourceUploadPlanImpl = struct {
    handle_allocator: *HandleAllocator,
    inner: snail.ResourceUploadPlan,
};
pub const PendingResourceUploadImpl = struct {
    handle_allocator: *HandleAllocator,
    inner: snail.PendingResourceUpload,
};
pub const VulkanFrameImpl = struct {
    handle_allocator: *HandleAllocator,
    inner: if (build_options.enable_vulkan) snail.VulkanRenderer.Frame else void,
};
pub const DrawListImpl = struct {
    handle_allocator: *HandleAllocator,
    inner: snail.DrawList,
    words: []u32,
    segments: []snail.DrawList.Segment,
};
pub const TextCoverageRecordsImpl = struct {
    handle_allocator: *HandleAllocator,
    inner: snail.coverage.TextCoverageRecords,
    words: []u32,
};
pub const CoverageBackendImpl = struct {
    handle_allocator: *HandleAllocator,
    inner: snail.coverage.Backend,
};
pub const ThreadPoolImpl = struct { handle_allocator: *HandleAllocator, inner: snail.ThreadPool };
pub const RendererImpl = struct {
    handle_allocator: *HandleAllocator,
    backend: snail.BackendKind,
    gl33: if (build_options.enable_gl33) ?snail.Gl33Renderer else void = if (build_options.enable_gl33) null else {},
    gl44: if (build_options.enable_gl44) ?snail.Gl44Renderer else void = if (build_options.enable_gl44) null else {},
    gles30: if (build_options.enable_gles30) ?snail.Gles30Renderer else void = if (build_options.enable_gles30) null else {},
    vulkan: if (build_options.enable_vulkan) ?snail.VulkanRenderer else void = if (build_options.enable_vulkan) null else {},
    cpu: if (build_options.enable_cpu) ?snail.CpuRenderer else void = if (build_options.enable_cpu) null else {},

    pub fn asRenderer(self: *RendererImpl) snail.Renderer {
        return switch (self.backend) {
            .gl33 => blk: {
                if (comptime !build_options.enable_gl33) unreachable;
                if (self.gl33) |*gl| break :blk gl.asRenderer();
                unreachable;
            },
            .gl44 => blk: {
                if (comptime !build_options.enable_gl44) unreachable;
                if (self.gl44) |*gl| break :blk gl.asRenderer();
                unreachable;
            },
            .gles30 => blk: {
                if (comptime !build_options.enable_gles30) unreachable;
                if (self.gles30) |*gles30| break :blk gles30.asRenderer();
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
            .gl33 => if (comptime build_options.enable_gl33) {
                if (self.gl33) |*gl| gl.deinit();
            },
            .gl44 => if (comptime build_options.enable_gl44) {
                if (self.gl44) |*gl| gl.deinit();
            },
            .gles30 => if (comptime build_options.enable_gles30) {
                if (self.gles30) |*gles30| gles30.deinit();
            },
            .vulkan => if (comptime build_options.enable_vulkan) {
                if (self.vulkan) |*vk_renderer| vk_renderer.deinit();
            },
            .cpu => {},
        }
    }

    pub fn backendName(self: *const RendererImpl) [:0]const u8 {
        return switch (self.backend) {
            .gl33 => if (comptime build_options.enable_gl33)
                self.gl33.?.backendName()
            else
                "GL 3.3 (disabled)",
            .gl44 => if (comptime build_options.enable_gl44)
                self.gl44.?.backendName()
            else
                "GL 4.4 (disabled)",
            .gles30 => if (comptime build_options.enable_gles30)
                self.gles30.?.backendName()
            else
                "OpenGL ES 3.0 (disabled)",
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

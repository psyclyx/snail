const std = @import("std");

const backend_kind_mod = @import("backend_kind.zig");
const build_options = @import("build_options");
const coverage_mod = @import("coverage.zig");
const draw_mod = @import("draw.zig");
const resource_key_mod = @import("resource_key.zig");
const resources_mod = @import("resources.zig");
const target_mod = @import("target.zig");
const upload_mod = @import("upload.zig");
const vec = @import("math/vec.zig");

const pipeline = if (build_options.enable_opengl) @import("renderer/gl.zig") else struct {
    pub const TextCoverageBindings = struct {};
    pub const GlTextState = void;
    pub const PreparedResources = void;
    pub const text_vertex_interface = "";
    pub const text_coverage_fragment_interface = "";
    pub const text_coverage_fragment_body = "";
};
const cpu_renderer_mod = if (build_options.enable_cpu) @import("renderer/cpu.zig") else struct {
    pub const CpuRenderer = void;
};
const vulkan_pipeline = if (build_options.enable_vulkan) @import("renderer/vulkan.zig") else struct {
    pub const VulkanContext = void;
    pub const PreparedResources = void;
    pub const VulkanPipeline = struct {
        subpixel_order: @import("renderer/subpixel_order.zig").SubpixelOrder = .none,
        fill_rule: target_mod.FillRule = .non_zero,
        pub fn init(_: *VulkanPipeline, _: anytype) !void {}
        pub fn deinit(_: *VulkanPipeline) void {}
        pub fn beginFrame(_: *VulkanPipeline) void {}
        pub fn backendName(_: *const VulkanPipeline) []const u8 {
            return "vulkan (disabled)";
        }
    };
};

pub const BackendKind = backend_kind_mod.BackendKind;
pub const CpuRenderer = cpu_renderer_mod.CpuRenderer;
pub const ThreadPool = @import("thread_pool.zig").ThreadPool;
pub const VulkanContext = vulkan_pipeline.VulkanContext;

const CoverageTransfer = target_mod.CoverageTransfer;
const DrawOptions = draw_mod.DrawOptions;
const DrawRecords = draw_mod.DrawRecords;
const FillRule = target_mod.FillRule;
const Mat4 = vec.Mat4;
const PendingResourceUpload = upload_mod.PendingResourceUpload;
const PreparedResources = resources_mod.PreparedResources;
const PreparedScene = draw_mod.PreparedScene;
const Resolve = target_mod.Resolve;
const ResourceKey = resource_key_mod.ResourceKey;
const ResourceSet = resources_mod.ResourceSet;
const ResourceUploadPlan = upload_mod.ResourceUploadPlan;
const SubpixelOrder = target_mod.SubpixelOrder;
const TargetStamp = target_mod.TargetStamp;
const TargetEncoding = target_mod.TargetEncoding;
const CoverageBackend = coverage_mod.Backend;
const UploadAllocators = upload_mod.UploadAllocators;
const effectiveSubpixelOrderRef = target_mod.effectiveSubpixelOrderRef;
const resourceEntryKey = resources_mod.resourceEntryKey;
const resourceEntryStamp = resources_mod.resourceEntryStamp;
const resourceEntryUploadBytes = resources_mod.resourceEntryUploadBytes;
const uploadPreparedResources = resources_mod.uploadPreparedResources;

/// Renderer execution machinery. Backend resources live in PreparedResources.
pub const Renderer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        backend: BackendKind,
        deinit: *const fn (*anyopaque) void,
        // Frame-level draw: validate, set state, walk records. Each backend
        // owns this so it can decide how to schedule the work (e.g., the CPU
        // backend fans tile work out across a caller-owned thread pool here).
        draw: *const fn (*Renderer, *const PreparedResources, DrawRecords, DrawOptions) anyerror!void,
        // Segment-level dispatch, called from `iterateRecords`. Backends that
        // delegate scheduling to the shared helper implement these only.
        drawText: *const fn (*anyopaque, ?*const anyopaque, []const u32, Mat4, f32, f32, u32) void,
        drawPaths: *const fn (*anyopaque, ?*const anyopaque, []const u32, Mat4, f32, f32, u32) void,
        beginFrame: *const fn (*anyopaque) void,
        setSubpixelOrder: *const fn (*anyopaque, SubpixelOrder) void,
        getSubpixelOrder: *const fn (*anyopaque) SubpixelOrder,
        setFillRule: *const fn (*anyopaque, FillRule) void,
        getFillRule: *const fn (*anyopaque) FillRule,
        setTargetEncoding: *const fn (*anyopaque, TargetEncoding) void,
        getTargetEncoding: *const fn (*anyopaque) TargetEncoding,
        setResolve: *const fn (*anyopaque, Resolve) void,
        getResolve: *const fn (*anyopaque) Resolve,
        setCoverageTransfer: *const fn (*anyopaque, CoverageTransfer) void,
        getCoverageTransfer: *const fn (*anyopaque) CoverageTransfer,
        backendName: *const fn (*anyopaque) []const u8,
    };

    /// Generate a VTable that type-erases calls to methods on *T.
    fn ImplVTable(comptime T: type, comptime owned: bool, comptime backend_kind: BackendKind) VTable {
        const S = struct {
            fn cast(ptr: *anyopaque) *T {
                return @ptrCast(@alignCast(ptr));
            }
            fn constCast(ptr: *anyopaque) *const T {
                return @ptrCast(@alignCast(ptr));
            }
            fn deinitFn(ptr: *anyopaque) void {
                const self = cast(ptr);
                self.deinit();
                if (owned) std.heap.smp_allocator.destroy(self);
            }
            fn noopDeinit(_: *anyopaque) void {}
            fn drawTextFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, mvp: Mat4, vw: f32, vh: f32, texture_layer_base: u32) void {
                if (prepared) |backend_prepared| {
                    if (comptime build_options.enable_cpu and T == CpuRenderer and @hasDecl(T, "drawTextPrepared")) {
                        const typed: *const cpu_renderer_mod.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawTextPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                    if (comptime build_options.enable_opengl and T == pipeline.GlTextState and @hasDecl(T, "drawTextPrepared")) {
                        const typed: *const pipeline.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawTextPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                    if (comptime build_options.enable_vulkan and T == vulkan_pipeline.VulkanPipeline and @hasDecl(T, "drawTextPrepared")) {
                        const typed: *const vulkan_pipeline.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawTextPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                }
                std.debug.panic("drawText requires PreparedResources ({*}, {d}, {d}, {d}, {d})", .{ ptr, verts.len, mvp.data[0], vw, vh });
            }
            fn drawPathsFn(ptr: *anyopaque, prepared: ?*const anyopaque, verts: []const u32, mvp: Mat4, vw: f32, vh: f32, texture_layer_base: u32) void {
                if (prepared) |backend_prepared| {
                    if (comptime build_options.enable_cpu and T == CpuRenderer and @hasDecl(T, "drawPathsPrepared")) {
                        const typed: *const cpu_renderer_mod.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawPathsPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                    if (comptime build_options.enable_opengl and T == pipeline.GlTextState and @hasDecl(T, "drawPathsPrepared")) {
                        const typed: *const pipeline.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawPathsPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
                    if (comptime build_options.enable_vulkan and T == vulkan_pipeline.VulkanPipeline and @hasDecl(T, "drawPathsPrepared")) {
                        const typed: *const vulkan_pipeline.PreparedResources = @ptrCast(@alignCast(backend_prepared));
                        cast(ptr).drawPathsPrepared(typed, verts, mvp, vw, vh, texture_layer_base);
                        return;
                    }
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
            fn backendNameFn(ptr: *anyopaque) []const u8 {
                return constCast(ptr).backendName();
            }
            // Resolve the backend's typed PreparedResources view from the
            // unified PreparedResources, returning `null` if the field is
            // missing. Backends that don't carry typed prepared state
            // (currently none) can compile down to `null`.
            fn resolveBackendPrepared(prepared: *const PreparedResources) ?*const anyopaque {
                if (comptime build_options.enable_opengl and T == pipeline.GlTextState) {
                    if (prepared.gl) |*gl_prepared| return @ptrCast(gl_prepared);
                    return null;
                }
                if (comptime build_options.enable_vulkan and T == vulkan_pipeline.VulkanPipeline) {
                    if (prepared.vulkan) |*vk_prepared| return @ptrCast(vk_prepared);
                    return null;
                }
                if (comptime build_options.enable_cpu and T == CpuRenderer) {
                    if (prepared.cpu) |*cpu_prepared| return @ptrCast(cpu_prepared);
                    return null;
                }
                return null;
            }
            fn drawFn(renderer: *Renderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) anyerror!void {
                const backend_prepared = resolveBackendPrepared(prepared) orelse return error.MissingPreparedResource;
                try renderer.validateRecords(prepared, records, options);
                switch (options.target.resolve) {
                    .direct => {},
                    .linear => |linear| {
                        if (!options.target.supportsLinearResolve()) return error.InvalidResolve;
                        if (comptime build_options.enable_opengl and T == pipeline.GlTextState) {
                            const width: u32 = @intFromFloat(@max(options.target.pixel_width, 0.0));
                            const height: u32 = @intFromFloat(@max(options.target.pixel_height, 0.0));
                            const gl_self = cast(renderer.ptr);
                            const restore = try gl_self.beginLinearResolve(width, height, linear);
                            var inner_options = options;
                            inner_options.target.encoding = .linear;
                            inner_options.target.resolve = .{ .direct = .{} };
                            renderer.iterateRecords(records, inner_options, backend_prepared);
                            gl_self.endLinearResolve(restore);
                            renderer.setTargetEncoding(options.target.encoding);
                            renderer.setResolve(options.target.resolve);
                            return;
                        }
                        if (comptime build_options.enable_vulkan and T == vulkan_pipeline.VulkanPipeline) {
                            return error.UnsupportedResolve;
                        }
                        if (comptime build_options.enable_cpu and T == CpuRenderer) {
                            const cpu_self = cast(renderer.ptr);
                            const restore = cpu_self.beginLinearResolve(options.target, linear);
                            defer cpu_self.endLinearResolve(restore);
                            if (cpu_self.thread_pool) |pool| {
                                const span = cpu_self.row_clip_max - cpu_self.row_clip_min;
                                if (span >= 2 * CpuRenderer.TILE_ROWS) {
                                    cpu_self.dispatchTiledDraw(pool, backend_prepared, records, options);
                                    return;
                                }
                            }
                            renderer.iterateRecords(records, options, backend_prepared);
                            return;
                        }
                    },
                }
                if (comptime build_options.enable_cpu and T == CpuRenderer) {
                    const cpu_self = cast(renderer.ptr);
                    if (cpu_self.thread_pool) |pool| {
                        const span = cpu_self.row_clip_max - cpu_self.row_clip_min;
                        if (span >= 2 * CpuRenderer.TILE_ROWS) {
                            cpu_self.dispatchTiledDraw(pool, backend_prepared, records, options);
                            return;
                        }
                    }
                }
                renderer.iterateRecords(records, options, backend_prepared);
            }
        };
        return .{
            .backend = backend_kind,
            .deinit = if (owned) &S.deinitFn else &S.noopDeinit,
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
            .backendName = &S.backendNameFn,
        };
    }

    fn DisabledVTable(comptime backend_kind: BackendKind) VTable {
        const S = struct {
            fn deinitFn(_: *anyopaque) void {}
            fn drawFn(_: *Renderer, _: *const PreparedResources, _: DrawRecords, _: DrawOptions) anyerror!void {
                return error.UnsupportedRenderer;
            }
            fn drawTextFn(_: *anyopaque, _: ?*const anyopaque, _: []const u32, _: Mat4, _: f32, _: f32, _: u32) void {}
            fn drawPathsFn(_: *anyopaque, _: ?*const anyopaque, _: []const u32, _: Mat4, _: f32, _: f32, _: u32) void {}
            fn beginFrameFn(_: *anyopaque) void {}
            fn setSubpixelOrderFn(_: *anyopaque, _: SubpixelOrder) void {}
            fn getSubpixelOrderFn(_: *anyopaque) SubpixelOrder {
                return .none;
            }
            fn setFillRuleFn(_: *anyopaque, _: FillRule) void {}
            fn getFillRuleFn(_: *anyopaque) FillRule {
                return .non_zero;
            }
            fn setTargetEncodingFn(_: *anyopaque, _: TargetEncoding) void {}
            fn getTargetEncodingFn(_: *anyopaque) TargetEncoding {
                return .srgb;
            }
            fn setResolveFn(_: *anyopaque, _: Resolve) void {}
            fn getResolveFn(_: *anyopaque) Resolve {
                return .{ .direct = .{} };
            }
            fn setCoverageTransferFn(_: *anyopaque, _: CoverageTransfer) void {}
            fn getCoverageTransferFn(_: *anyopaque) CoverageTransfer {
                return .identity;
            }
            fn backendNameFn(_: *anyopaque) []const u8 {
                return switch (backend_kind) {
                    .gl => "OpenGL (disabled)",
                    .vulkan => "Vulkan (disabled)",
                    .cpu => "CPU (disabled)",
                };
            }
        };
        return .{
            .backend = backend_kind,
            .deinit = &S.deinitFn,
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
            .backendName = &S.backendNameFn,
        };
    }

    const gl_borrowed_vtable = if (build_options.enable_opengl) ImplVTable(pipeline.GlTextState, false, .gl) else DisabledVTable(.gl);
    const vulkan_borrowed_vtable = if (build_options.enable_vulkan) ImplVTable(vulkan_pipeline.VulkanPipeline, false, .vulkan) else DisabledVTable(.vulkan);
    const cpu_vtable = if (build_options.enable_cpu) ImplVTable(CpuRenderer, false, .cpu) else DisabledVTable(.cpu);

    /// Blocking upload for simple programs. GL requires the target context to
    /// be current. CPU upload builds cheap views. Vulkan does not perform an
    /// implicit device/queue idle here.
    pub fn uploadResourcesBlocking(self: *Renderer, allocators: UploadAllocators, set: *const ResourceSet) !PreparedResources {
        return uploadPreparedResources(self, set, allocators);
    }

    pub fn planResourceUpload(self: *Renderer, current: ?*const PreparedResources, next_set: *const ResourceSet, changed_keys: []ResourceKey) !ResourceUploadPlan {
        _ = self;
        var plan = ResourceUploadPlan{ .set = next_set, .changed_keys = changed_keys };
        plan.upload_footprint = try next_set.estimateUploadFootprint();
        plan.upload_bytes = plan.upload_footprint.allocatedBytes();
        for (next_set.slice()) |entry| {
            const key = resourceEntryKey(entry);
            const stamp = resourceEntryStamp(entry);
            const bytes = resourceEntryUploadBytes(entry);
            const old_stamp = if (current) |prepared| prepared.stampForKey(key) else null;
            const changed = if (old_stamp) |old| !old.eql(stamp) else true;
            if (changed) {
                try plan.addChanged(key, bytes);
            }
        }
        return plan;
    }

    pub fn beginResourceUpload(self: *Renderer, allocators: UploadAllocators, plan: ResourceUploadPlan) !PendingResourceUpload {
        return .{ .renderer = self.*, .allocators = allocators, .plan = plan };
    }

    pub fn backend(self: *const Renderer) BackendKind {
        return self.vtable.backend;
    }

    /// Execute prebuilt draw records. This never discovers, uploads, allocates,
    /// or invalidates resources. The backend's vtable entry decides whether
    /// to walk records serially or fan them out across worker threads.
    pub fn draw(self: *Renderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        return self.vtable.draw(self, prepared, records, options);
    }

    pub fn drawPrepared(self: *Renderer, prepared: *const PreparedResources, scene: *const PreparedScene, options: DrawOptions) !void {
        return self.draw(prepared, scene.slice(), options);
    }

    /// Verify every segment's stamps still match the live prepared resources
    /// and the requested draw target. Returns `error.StaleDrawRecords` if a
    /// resource has been re-uploaded or the target/MVP has changed since the
    /// records were built; `error.MissingPreparedResource` if a key is gone.
    /// Vtables call this once per frame before fan-out so per-tile workers
    /// don't have to re-validate (and don't need an error path).
    pub fn validateRecords(_: *Renderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        const expected_target_stamp = TargetStamp.fromRef(&options.mvp, &options.target);
        for (records.segments) |segment| {
            const actual_stamp = prepared.stampForKey(segment.key) orelse return error.MissingPreparedResource;
            if (!actual_stamp.eql(segment.resource_stamp)) return error.StaleDrawRecords;
            if (!std.meta.eql(expected_target_stamp, segment.target_stamp)) return error.StaleDrawRecords;
        }
    }

    /// Frame-level draw: set state, walk records serially dispatching each
    /// segment to the backend's `drawText` / `drawPaths`. Used by the GL and
    /// Vulkan vtables directly, and by the CPU vtable's serial fallback /
    /// tile workers. Caller has already invoked `validateRecords`.
    pub fn iterateRecords(self: *Renderer, records: DrawRecords, options: DrawOptions, backend_prepared: ?*const anyopaque) void {
        self.setSubpixelOrder(effectiveSubpixelOrderRef(&options.target));
        self.setFillRule(options.target.fill_rule);
        self.setTargetEncoding(options.target.encoding);
        self.setResolve(options.target.resolve);
        self.setCoverageTransfer(options.target.coverage_transfer);
        self.beginFrame();
        for (records.segments) |segment| {
            const vertices = records.words[segment.offset..][0..segment.len];
            switch (segment.kind) {
                .text => if (vertices.len > 0) self.drawText(backend_prepared, vertices, options.mvp, options.target.pixel_width, options.target.pixel_height, segment.texture_layer_base),
                .path => if (vertices.len > 0) self.drawPaths(backend_prepared, vertices, options.mvp, options.target.pixel_width, options.target.pixel_height, segment.texture_layer_base),
            }
        }
    }

    /// Borrow a caller-owned CPU backend through the erased renderer interface.
    /// Prefer `CpuRenderer.asRenderer()` at call sites.
    pub fn borrowCpu(cpu: *CpuRenderer) Renderer {
        return .{ .ptr = @ptrCast(cpu), .vtable = &cpu_vtable };
    }

    pub fn deinit(self: *Renderer) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn beginFrame(self: *Renderer) void {
        self.vtable.beginFrame(self.ptr);
    }

    fn drawText(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        self.vtable.drawText(self.ptr, backend_prepared, vertices, mvp, viewport_w, viewport_h, texture_layer_base);
    }

    fn drawPaths(self: *Renderer, backend_prepared: ?*const anyopaque, vertices: []const u32, mvp: Mat4, viewport_w: f32, viewport_h: f32, texture_layer_base: u32) void {
        self.vtable.drawPaths(self.ptr, backend_prepared, vertices, mvp, viewport_w, viewport_h, texture_layer_base);
    }

    pub fn setSubpixelOrder(self: *Renderer, order: SubpixelOrder) void {
        self.vtable.setSubpixelOrder(self.ptr, order);
    }

    pub fn subpixelOrder(self: *const Renderer) SubpixelOrder {
        return self.vtable.getSubpixelOrder(@constCast(self.ptr));
    }

    pub fn setFillRule(self: *Renderer, rule: FillRule) void {
        self.vtable.setFillRule(self.ptr, rule);
    }

    pub fn setTargetEncoding(self: *Renderer, encoding: TargetEncoding) void {
        self.vtable.setTargetEncoding(self.ptr, encoding);
    }

    pub fn targetEncoding(self: *const Renderer) TargetEncoding {
        return self.vtable.getTargetEncoding(@constCast(self.ptr));
    }

    pub fn setResolve(self: *Renderer, next_resolve: Resolve) void {
        self.vtable.setResolve(self.ptr, next_resolve);
    }

    pub fn resolve(self: *const Renderer) Resolve {
        return self.vtable.getResolve(@constCast(self.ptr));
    }

    pub fn setCoverageTransfer(self: *Renderer, transfer: CoverageTransfer) void {
        self.vtable.setCoverageTransfer(self.ptr, transfer);
    }

    pub fn coverageTransfer(self: *const Renderer) CoverageTransfer {
        return self.vtable.getCoverageTransfer(@constCast(self.ptr));
    }

    pub fn fillRule(self: *const Renderer) FillRule {
        return self.vtable.getFillRule(@constCast(self.ptr));
    }

    pub fn backendName(self: *const Renderer) []const u8 {
        return self.vtable.backendName(@constCast(self.ptr));
    }
};

/// Typed handle for the GL backend.
///
/// `GlRenderer` owns the GL state; the `uploadResourcesBlocking`,
/// `planResourceUpload`, `beginResourceUpload`, `draw`, and `drawPrepared`
/// methods are thin shims over `Renderer` for callers that want to stay
/// strongly typed. `coverageBackend` is the only method that requires the
/// typed handle. Use `asRenderer()` to pass to backend-agnostic code.
pub const GlRenderer = if (build_options.enable_opengl) struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: *pipeline.GlTextState,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const text = try allocator.create(pipeline.GlTextState);
        text.* = .{};
        errdefer allocator.destroy(text);
        try text.init();
        return .{ .allocator = allocator, .state = text };
    }

    pub fn deinit(self: *Self) void {
        self.state.deinit();
        self.allocator.destroy(self.state);
        self.* = undefined;
    }

    pub fn asRenderer(self: *Self) Renderer {
        return .{ .ptr = @ptrCast(self.state), .vtable = &Renderer.gl_borrowed_vtable };
    }

    pub fn uploadResourcesBlocking(self: *Self, allocators: UploadAllocators, set: *const ResourceSet) !PreparedResources {
        var renderer = self.asRenderer();
        return renderer.uploadResourcesBlocking(allocators, set);
    }

    pub fn planResourceUpload(self: *Self, current: ?*const PreparedResources, next_set: *const ResourceSet, changed_keys: []ResourceKey) !ResourceUploadPlan {
        var renderer = self.asRenderer();
        return renderer.planResourceUpload(current, next_set, changed_keys);
    }

    pub fn beginResourceUpload(self: *Self, allocators: UploadAllocators, plan: ResourceUploadPlan) !PendingResourceUpload {
        var renderer = self.asRenderer();
        return renderer.beginResourceUpload(allocators, plan);
    }

    pub fn draw(self: *Self, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.draw(prepared, records, options);
    }

    pub fn drawPrepared(self: *Self, prepared: *const PreparedResources, scene: *const PreparedScene, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.drawPrepared(prepared, scene, options);
    }

    pub fn coverageBackend(self: *Self, prepared: *const PreparedResources) ?CoverageBackend {
        if (prepared.gl) |*gl_resources| {
            return .{ .gl = .{ .gl = self.state, .gl_resources = gl_resources, .prepared = prepared } };
        }
        return null;
    }

    pub fn backendName(self: *const Self) []const u8 {
        return self.state.backendName();
    }
} else void;

/// Typed handle for the Vulkan backend.
///
/// As with `GlRenderer`, the upload / draw methods are shims over `Renderer`;
/// the typed handle exists so `beginFrame(.{ .cmd, .frame_index })` (which
/// takes a backend-specific argument) and other Vulkan-only future hooks have
/// somewhere to live. Use `asRenderer()` for backend-agnostic code.
pub const VulkanRenderer = struct {
    state: *vulkan_pipeline.VulkanPipeline,

    pub fn init(vk_ctx: VulkanContext) !VulkanRenderer {
        const vkp = try std.heap.smp_allocator.create(vulkan_pipeline.VulkanPipeline);
        vkp.* = .{};
        errdefer std.heap.smp_allocator.destroy(vkp);
        try vkp.init(vk_ctx);
        return .{ .state = vkp };
    }

    pub fn deinit(self: *VulkanRenderer) void {
        self.state.deinit();
        std.heap.smp_allocator.destroy(self.state);
        self.* = undefined;
    }

    pub fn asRenderer(self: *VulkanRenderer) Renderer {
        return .{ .ptr = @ptrCast(self.state), .vtable = &Renderer.vulkan_borrowed_vtable };
    }

    pub fn beginFrame(self: *VulkanRenderer, frame: anytype) void {
        self.state.setCommandBuffer(frame.cmd);
        self.state.setFrameSlot(frame.frame_index);
    }

    pub fn uploadResourcesBlocking(self: *VulkanRenderer, allocators: UploadAllocators, set: *const ResourceSet) !PreparedResources {
        var renderer = self.asRenderer();
        return renderer.uploadResourcesBlocking(allocators, set);
    }

    pub fn planResourceUpload(self: *VulkanRenderer, current: ?*const PreparedResources, next_set: *const ResourceSet, changed_keys: []ResourceKey) !ResourceUploadPlan {
        var renderer = self.asRenderer();
        return renderer.planResourceUpload(current, next_set, changed_keys);
    }

    pub fn beginResourceUpload(self: *VulkanRenderer, allocators: UploadAllocators, plan: ResourceUploadPlan) !PendingResourceUpload {
        var renderer = self.asRenderer();
        return renderer.beginResourceUpload(allocators, plan);
    }

    pub fn draw(self: *VulkanRenderer, prepared: *const PreparedResources, records: DrawRecords, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.draw(prepared, records, options);
    }

    pub fn drawPrepared(self: *VulkanRenderer, prepared: *const PreparedResources, scene: *const PreparedScene, options: DrawOptions) !void {
        var renderer = self.asRenderer();
        try renderer.drawPrepared(prepared, scene, options);
    }

    pub fn coverageBackend(self: *VulkanRenderer, prepared: *const PreparedResources) ?CoverageBackend {
        if (comptime !build_options.enable_vulkan) return null;
        if (prepared.vulkan) |*vk_resources| {
            return .{ .vulkan = .{ .vk = self.state, .vk_resources = vk_resources, .prepared = prepared } };
        }
        return null;
    }

    pub fn backendName(self: *const VulkanRenderer) []const u8 {
        return self.state.backendName();
    }
};

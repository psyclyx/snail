//! Minimal Snail + WebGPU (wgpu-native) example — the headless analog of
//! `minimal_gl.zig`, rendering the identical scene with the generated WGSL
//! catalog (`snail.shader.wgsl`).
//!
//! This file intentionally imports none of the demo renderer, cache, scene,
//! platform, or support modules. It owns the WebGPU instance/adapter/device
//! (no surface), the offscreen render target, the four atlas textures per the
//! binding contract, the upload loop, pipelines, draw submission, readback,
//! and the screenshot writer. Its one frame covers unhinted, autohinted,
//! TT-hinted, and COLR text plus filled and stroked paths.
//!
//! Binding contract (see `snail.shader.wgsl`): group 0 = atlas textures at
//! the Vulkan binding numbers, group 1 = the split samplers, group 2 =
//! the Vulkan push-constant block as a 96-byte uniform buffer.
//!
//! Environment knobs (both optional): `SNAIL_WGPU_BACKEND=vulkan|gl` pins the
//! adapter's backend (useful with `VK_DRIVER_FILES` pointing at llvmpipe for
//! GPU-less CI), `SNAIL_WGPU_LOG=1` prints the chosen adapter and wgpu logs.

const std = @import("std");
const snail = @import("snail");
const assets = @import("assets");

const c = @cImport({
    @cInclude("webgpu/webgpu.h");
    @cInclude("webgpu/wgpu.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
});

fn getenv(name: [:0]const u8) ?[]const u8 {
    const value = c.getenv(name.ptr) orelse return null;
    return std.mem.span(value);
}

const width = 960;
const height = 420;
const text = "Hello, world!";
const ppem: u32 = 34 * 64;

const wgsl = snail.shader.wgsl;
const slang_gen = snail.shader.slang_generated;

/// The Vulkan push-constant block reshaped as a uniform buffer (std140; the
/// scalar fields land on the same offsets as the C struct's). Must stay in
/// sync with `SLANG_ParameterGroup_PushConstants_std140_` in the generated
/// WGSL and the Vulkan contract's `PushConstants`.
const PushConstants = extern struct {
    mvp: [16]f32,
    viewport: [2]f32,
    subpixel_order: i32 = 0,
    output_srgb: i32 = 0, // hardware-sRGB render target: emit linear
    layer_base: i32 = 0,
    coverage_exponent: f32 = 1.0,
    dither_scale: f32 = 0.0,
    mask_output: i32 = 0,
};

comptime {
    if (@sizeOf(PushConstants) != 96) @compileError("PushConstants must be 96 bytes");
}

fn sv(s: []const u8) c.WGPUStringView {
    return .{ .data = s.ptr, .length = s.len };
}

// ── Async plumbing ──

const AdapterRequest = struct { adapter: c.WGPUAdapter = null, done: bool = false };
const DeviceRequest = struct { device: c.WGPUDevice = null, done: bool = false };
const MapRequest = struct { ok: bool = false, done: bool = false };

fn onAdapter(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, message: c.WGPUStringView, ud1: ?*anyopaque, ud2: ?*anyopaque) callconv(.c) void {
    _ = ud2;
    const req: *AdapterRequest = @ptrCast(@alignCast(ud1.?));
    if (status == c.WGPURequestAdapterStatus_Success) req.adapter = adapter else printMessage("request adapter", message);
    req.done = true;
}

fn onDevice(status: c.WGPURequestDeviceStatus, device: c.WGPUDevice, message: c.WGPUStringView, ud1: ?*anyopaque, ud2: ?*anyopaque) callconv(.c) void {
    _ = ud2;
    const req: *DeviceRequest = @ptrCast(@alignCast(ud1.?));
    if (status == c.WGPURequestDeviceStatus_Success) req.device = device else printMessage("request device", message);
    req.done = true;
}

fn onMap(status: c.WGPUMapAsyncStatus, message: c.WGPUStringView, ud1: ?*anyopaque, ud2: ?*anyopaque) callconv(.c) void {
    _ = ud2;
    const req: *MapRequest = @ptrCast(@alignCast(ud1.?));
    req.ok = status == c.WGPUMapAsyncStatus_Success;
    if (!req.ok) printMessage("map buffer", message);
    req.done = true;
}

fn onUncapturedError(device: [*c]const c.WGPUDevice, err_type: c.WGPUErrorType, message: c.WGPUStringView, ud1: ?*anyopaque, ud2: ?*anyopaque) callconv(.c) void {
    _ = device;
    _ = ud1;
    _ = ud2;
    std.debug.print("wgpu uncaptured error (type {d}):\n", .{err_type});
    printMessage("error", message);
}

fn onLog(level: c.WGPULogLevel, message: c.WGPUStringView, ud: ?*anyopaque) callconv(.c) void {
    _ = ud;
    std.debug.print("[wgpu {d}] ", .{level});
    printMessage("log", message);
}

fn printMessage(context: []const u8, message: c.WGPUStringView) void {
    if (message.data != null and message.length > 0) {
        std.debug.print("{s}: {s}\n", .{ context, message.data[0..message.length] });
    }
}

// ── GPU context ──

const Gpu = struct {
    instance: c.WGPUInstance,
    adapter: c.WGPUAdapter,
    device: c.WGPUDevice,
    queue: c.WGPUQueue,

    fn init() !Gpu {
        if (getenv("SNAIL_WGPU_LOG") != null) {
            c.wgpuSetLogCallback(&onLog, null);
            c.wgpuSetLogLevel(c.WGPULogLevel_Info);
        }
        const instance = c.wgpuCreateInstance(null) orelse return error.InstanceFailed;
        errdefer c.wgpuInstanceRelease(instance);

        var adapter_req = AdapterRequest{};
        var adapter_options = std.mem.zeroInit(c.WGPURequestAdapterOptions, .{
            .powerPreference = c.WGPUPowerPreference_HighPerformance,
        });
        if (getenv("SNAIL_WGPU_BACKEND")) |backend| {
            if (std.mem.eql(u8, backend, "vulkan")) adapter_options.backendType = c.WGPUBackendType_Vulkan;
            if (std.mem.eql(u8, backend, "gl")) adapter_options.backendType = c.WGPUBackendType_OpenGL;
        }
        _ = c.wgpuInstanceRequestAdapter(instance, &adapter_options, .{
            .nextInChain = null,
            .mode = c.WGPUCallbackMode_AllowProcessEvents,
            .callback = &onAdapter,
            .userdata1 = &adapter_req,
            .userdata2 = null,
        });
        while (!adapter_req.done) c.wgpuInstanceProcessEvents(instance);
        const adapter = adapter_req.adapter orelse return error.NoAdapter;
        errdefer c.wgpuAdapterRelease(adapter);
        if (getenv("SNAIL_WGPU_LOG") != null) {
            var info = std.mem.zeroes(c.WGPUAdapterInfo);
            _ = c.wgpuAdapterGetInfo(adapter, &info);
            if (info.device.data != null) std.debug.print("adapter: {s} (backend {d})\n", .{ info.device.data[0..info.device.length], info.backendType });
        }

        var device_req = DeviceRequest{};
        var device_desc = std.mem.zeroInit(c.WGPUDeviceDescriptor, .{});
        device_desc.uncapturedErrorCallbackInfo = .{
            .nextInChain = null,
            .callback = &onUncapturedError,
            .userdata1 = null,
            .userdata2 = null,
        };
        _ = c.wgpuAdapterRequestDevice(adapter, &device_desc, .{
            .nextInChain = null,
            .mode = c.WGPUCallbackMode_AllowProcessEvents,
            .callback = &onDevice,
            .userdata1 = &device_req,
            .userdata2 = null,
        });
        while (!device_req.done) c.wgpuInstanceProcessEvents(instance);
        const device = device_req.device orelse return error.NoDevice;
        errdefer c.wgpuDeviceRelease(device);

        const queue = c.wgpuDeviceGetQueue(device) orelse return error.NoQueue;
        return .{ .instance = instance, .adapter = adapter, .device = device, .queue = queue };
    }

    fn deinit(self: *Gpu) void {
        c.wgpuQueueRelease(self.queue);
        c.wgpuDeviceRelease(self.device);
        c.wgpuAdapterRelease(self.adapter);
        c.wgpuInstanceRelease(self.instance);
    }
};

fn createShaderModule(device: c.WGPUDevice, source: [:0]const u8, label: []const u8) !c.WGPUShaderModule {
    var wgsl_source = c.WGPUShaderSourceWGSL{
        .chain = .{ .next = null, .sType = c.WGPUSType_ShaderSourceWGSL },
        .code = sv(source),
    };
    const desc = c.WGPUShaderModuleDescriptor{
        .nextInChain = @ptrCast(&wgsl_source.chain),
        .label = sv(label),
    };
    return c.wgpuDeviceCreateShaderModule(device, &desc) orelse error.ShaderModuleFailed;
}

// ── Bind group layouts / pipelines ──

const Layouts = struct {
    textures: c.WGPUBindGroupLayout,
    samplers: c.WGPUBindGroupLayout,
    uniforms: c.WGPUBindGroupLayout,
    pipeline: c.WGPUPipelineLayout,

    fn init(device: c.WGPUDevice) !Layouts {
        const both: c.WGPUShaderStage = c.WGPUShaderStage_Vertex | c.WGPUShaderStage_Fragment;

        // Group 0: the four atlas textures at their Vulkan binding numbers.
        // curve/layer-info are only ever textureLoad-ed (rgba16float /
        // rgba32float), so unfilterable-float keeps default limits happy.
        var tex_entries = [4]c.WGPUBindGroupLayoutEntry{
            textureEntry(0, both, c.WGPUTextureSampleType_UnfilterableFloat, c.WGPUTextureViewDimension_2DArray),
            textureEntry(1, both, c.WGPUTextureSampleType_Uint, c.WGPUTextureViewDimension_2DArray),
            textureEntry(2, both, c.WGPUTextureSampleType_UnfilterableFloat, c.WGPUTextureViewDimension_2D),
            textureEntry(3, both, c.WGPUTextureSampleType_Float, c.WGPUTextureViewDimension_2DArray),
        };
        const textures = c.wgpuDeviceCreateBindGroupLayout(device, &.{
            .nextInChain = null,
            .label = sv("snail-textures"),
            .entryCount = tex_entries.len,
            .entries = &tex_entries,
        }) orelse return error.LayoutFailed;

        // Group 1: the samplers naga split out of the combined image samplers.
        // Only the image-array sampler (3) filters; the rest are never used.
        var sampler_entries = [4]c.WGPUBindGroupLayoutEntry{
            samplerEntry(0, both, c.WGPUSamplerBindingType_NonFiltering),
            samplerEntry(1, both, c.WGPUSamplerBindingType_NonFiltering),
            samplerEntry(2, both, c.WGPUSamplerBindingType_NonFiltering),
            samplerEntry(3, both, c.WGPUSamplerBindingType_Filtering),
        };
        const samplers = c.wgpuDeviceCreateBindGroupLayout(device, &.{
            .nextInChain = null,
            .label = sv("snail-samplers"),
            .entryCount = sampler_entries.len,
            .entries = &sampler_entries,
        }) orelse return error.LayoutFailed;

        // Group 2: the push-constant block as a uniform buffer.
        var uniform_entries = [1]c.WGPUBindGroupLayoutEntry{
            std.mem.zeroInit(c.WGPUBindGroupLayoutEntry, .{
                .binding = 0,
                .visibility = both,
                .buffer = std.mem.zeroInit(c.WGPUBufferBindingLayout, .{
                    .type = c.WGPUBufferBindingType_Uniform,
                    .minBindingSize = @sizeOf(PushConstants),
                }),
            }),
        };
        const uniforms = c.wgpuDeviceCreateBindGroupLayout(device, &.{
            .nextInChain = null,
            .label = sv("snail-uniforms"),
            .entryCount = uniform_entries.len,
            .entries = &uniform_entries,
        }) orelse return error.LayoutFailed;

        var groups = [3]c.WGPUBindGroupLayout{ textures, samplers, uniforms };
        const pipeline = c.wgpuDeviceCreatePipelineLayout(device, &.{
            .nextInChain = null,
            .label = sv("snail-pipeline-layout"),
            .bindGroupLayoutCount = groups.len,
            .bindGroupLayouts = &groups,
        }) orelse return error.LayoutFailed;

        return .{ .textures = textures, .samplers = samplers, .uniforms = uniforms, .pipeline = pipeline };
    }

    fn deinit(self: *Layouts) void {
        c.wgpuPipelineLayoutRelease(self.pipeline);
        c.wgpuBindGroupLayoutRelease(self.uniforms);
        c.wgpuBindGroupLayoutRelease(self.samplers);
        c.wgpuBindGroupLayoutRelease(self.textures);
    }

    fn textureEntry(binding: u32, visibility: c.WGPUShaderStage, sample_type: c.WGPUTextureSampleType, dimension: c.WGPUTextureViewDimension) c.WGPUBindGroupLayoutEntry {
        return std.mem.zeroInit(c.WGPUBindGroupLayoutEntry, .{
            .binding = binding,
            .visibility = visibility,
            .texture = std.mem.zeroInit(c.WGPUTextureBindingLayout, .{
                .sampleType = sample_type,
                .viewDimension = dimension,
            }),
        });
    }

    fn samplerEntry(binding: u32, visibility: c.WGPUShaderStage, sampler_type: c.WGPUSamplerBindingType) c.WGPUBindGroupLayoutEntry {
        return std.mem.zeroInit(c.WGPUBindGroupLayoutEntry, .{
            .binding = binding,
            .visibility = visibility,
            .sampler = std.mem.zeroInit(c.WGPUSamplerBindingLayout, .{ .type = sampler_type }),
        });
    }
};

/// One instance-rate vertex buffer mirroring the Vulkan contract's nine
/// attributes at locations 0–8 (the generated WGSL preserves them).
fn vertexAttributes() [9]c.WGPUVertexAttribute {
    const Instance = snail.render.records.Instance;
    return .{
        .{ .format = c.WGPUVertexFormat_Float16x4, .offset = @offsetOf(Instance, "rect"), .shaderLocation = 0 },
        .{ .format = c.WGPUVertexFormat_Float32x4, .offset = @offsetOf(Instance, "xform"), .shaderLocation = 1 },
        .{ .format = c.WGPUVertexFormat_Float32x2, .offset = @offsetOf(Instance, "origin"), .shaderLocation = 2 },
        .{ .format = c.WGPUVertexFormat_Uint32x2, .offset = @offsetOf(Instance, "glyph"), .shaderLocation = 3 },
        .{ .format = c.WGPUVertexFormat_Float32x4, .offset = @offsetOf(Instance, "band"), .shaderLocation = 4 },
        .{ .format = c.WGPUVertexFormat_Unorm8x4, .offset = @offsetOf(Instance, "color"), .shaderLocation = 5 },
        .{ .format = c.WGPUVertexFormat_Unorm8x4, .offset = @offsetOf(Instance, "tint"), .shaderLocation = 6 },
        .{ .format = c.WGPUVertexFormat_Uint32x4, .offset = @offsetOf(Instance, "policy"), .shaderLocation = 7 },
        .{ .format = c.WGPUVertexFormat_Uint32x3, .offset = @offsetOf(Instance, "policy") + 16, .shaderLocation = 8 },
    };
}

const Pipelines = struct {
    regular: c.WGPURenderPipeline,
    autohint: c.WGPURenderPipeline,
    tt_hint: c.WGPURenderPipeline,
    path: c.WGPURenderPipeline,
    colr: c.WGPURenderPipeline,

    fn init(device: c.WGPUDevice, layout: c.WGPUPipelineLayout) !Pipelines {
        const text_vert = try createShaderModule(device, wgsl.source(.text, .vertex), "snail-text-vert");
        defer c.wgpuShaderModuleRelease(text_vert);
        // Stage A of the Slang cutover: the regular-text pipeline uses the
        // native-Slang generated WGSL (same @group/@binding contract; entry
        // points keep their Slang names). Other families keep the catalog.
        const native_text_vert = try createShaderModule(device, slang_gen.textWgsl(.vertex), "snail-text-native-vert");
        defer c.wgpuShaderModuleRelease(native_text_vert);
        const native_text_frag = try createShaderModule(device, slang_gen.textWgsl(.fragment), "snail-text-native-frag");
        defer c.wgpuShaderModuleRelease(native_text_frag);
        const autohint_vert = try createShaderModule(device, slang_gen.autohintWgsl(.vertex), "snail-autohint-native-vert");
        defer c.wgpuShaderModuleRelease(autohint_vert);
        const autohint_frag = try createShaderModule(device, slang_gen.autohintWgsl(.fragment), "snail-autohint-native-frag");
        defer c.wgpuShaderModuleRelease(autohint_frag);
        const tt_frag = try createShaderModule(device, slang_gen.ttHintedFragWgsl(), "snail-tt-native-frag");
        defer c.wgpuShaderModuleRelease(tt_frag);
        const native_path_frag = try createShaderModule(device, slang_gen.pathFragWgsl(), "snail-path-native-frag");
        defer c.wgpuShaderModuleRelease(native_path_frag);
        const native_colr_frag = try createShaderModule(device, slang_gen.colrFragWgsl(), "snail-colr-native-frag");
        defer c.wgpuShaderModuleRelease(native_colr_frag);

        return .{
            .regular = try createPipelineEntries(device, layout, native_text_vert, slang_gen.wgsl_vertex_entry, native_text_frag, slang_gen.wgsl_fragment_entry, "snail-text"),
            .autohint = try createPipelineEntries(device, layout, autohint_vert, slang_gen.wgsl_vertex_entry, autohint_frag, slang_gen.wgsl_fragment_entry, "snail-autohint"),
            .tt_hint = try createPipelineEntries(device, layout, native_text_vert, slang_gen.wgsl_vertex_entry, tt_frag, slang_gen.wgsl_fragment_entry, "snail-tt-hint"),
            .path = try createPipelineEntries(device, layout, native_text_vert, slang_gen.wgsl_vertex_entry, native_path_frag, slang_gen.wgsl_fragment_entry, "snail-path"),
            .colr = try createPipelineEntries(device, layout, native_text_vert, slang_gen.wgsl_vertex_entry, native_colr_frag, slang_gen.wgsl_fragment_entry, "snail-colr"),
        };
    }

    fn deinit(self: *Pipelines) void {
        c.wgpuRenderPipelineRelease(self.regular);
        c.wgpuRenderPipelineRelease(self.autohint);
        c.wgpuRenderPipelineRelease(self.tt_hint);
        c.wgpuRenderPipelineRelease(self.path);
        c.wgpuRenderPipelineRelease(self.colr);
    }

    fn forKind(self: Pipelines, kind: snail.render.records.ShapeKind) c.WGPURenderPipeline {
        return switch (kind) {
            .regular => self.regular,
            .autohint => self.autohint,
            .tt_hinted_text => self.tt_hint,
            .path => self.path,
            .colr => self.colr,
        };
    }

    fn createPipeline(
        device: c.WGPUDevice,
        layout: c.WGPUPipelineLayout,
        vert: c.WGPUShaderModule,
        frag: c.WGPUShaderModule,
        label: []const u8,
    ) !c.WGPURenderPipeline {
        return createPipelineEntries(device, layout, vert, "main", frag, "main", label);
    }

    fn createPipelineEntries(
        device: c.WGPUDevice,
        layout: c.WGPUPipelineLayout,
        vert: c.WGPUShaderModule,
        vert_entry: []const u8,
        frag: c.WGPUShaderModule,
        frag_entry: []const u8,
        label: []const u8,
    ) !c.WGPURenderPipeline {
        var attributes = vertexAttributes();
        const vertex_buffers = [1]c.WGPUVertexBufferLayout{.{
            .stepMode = c.WGPUVertexStepMode_Instance,
            .arrayStride = snail.render.records.BYTES_PER_INSTANCE,
            .attributeCount = attributes.len,
            .attributes = &attributes,
        }};
        // Premultiplied-over, matching the Vulkan contract's blendAttachment.
        const blend = c.WGPUBlendState{
            .color = .{ .operation = c.WGPUBlendOperation_Add, .srcFactor = c.WGPUBlendFactor_One, .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha },
            .alpha = .{ .operation = c.WGPUBlendOperation_Add, .srcFactor = c.WGPUBlendFactor_One, .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha },
        };
        const targets = [1]c.WGPUColorTargetState{.{
            .nextInChain = null,
            .format = c.WGPUTextureFormat_RGBA8UnormSrgb,
            .blend = &blend,
            .writeMask = c.WGPUColorWriteMask_All,
        }};
        const fragment = c.WGPUFragmentState{
            .nextInChain = null,
            .module = frag,
            .entryPoint = sv(frag_entry),
            .constantCount = 0,
            .constants = null,
            .targetCount = targets.len,
            .targets = &targets,
        };
        const desc = c.WGPURenderPipelineDescriptor{
            .nextInChain = null,
            .label = sv(label),
            .layout = layout,
            .vertex = .{
                .nextInChain = null,
                .module = vert,
                .entryPoint = sv(vert_entry),
                .constantCount = 0,
                .constants = null,
                .bufferCount = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = std.mem.zeroInit(c.WGPUPrimitiveState, .{
                .topology = c.WGPUPrimitiveTopology_TriangleList,
                .frontFace = c.WGPUFrontFace_CCW,
                .cullMode = c.WGPUCullMode_None,
            }),
            .depthStencil = null,
            .multisample = std.mem.zeroInit(c.WGPUMultisampleState, .{
                .count = 1,
                .mask = ~@as(u32, 0),
            }),
            .fragment = &fragment,
        };
        return c.wgpuDeviceCreateRenderPipeline(device, &desc) orelse error.PipelineFailed;
    }
};

// ── Atlas residency ──

/// The complete caller-owned GPU side of a Snail atlas: WebGPU textures fed
/// by the planner's regions through `queue.writeTexture`.
const GpuAtlas = struct {
    gpu: *const Gpu,
    pool: *snail.PagePool,
    curve_tex: c.WGPUTexture = null,
    band_tex: c.WGPUTexture = null,
    layer_tex: c.WGPUTexture = null,
    image_tex: c.WGPUTexture = null, // 1×1 placeholder: the scene packs no image paints
    uploads: snail.OwnedAtlasUploadPlanner,
    binding: ?snail.render.records.Binding = null,

    const options = snail.atlas_upload.Options{
        .max_bindings = 1,
        .layer_info_height = 256,
        .max_images = 0,
        .max_image_width = 0,
        .max_image_height = 0,
    };

    fn init(allocator: std.mem.Allocator, gpu: *const Gpu, pool: *snail.PagePool) !GpuAtlas {
        var self = GpuAtlas{
            .gpu = gpu,
            .pool = pool,
            .uploads = try snail.OwnedAtlasUploadPlanner.init(allocator, pool, options),
        };
        errdefer self.uploads.deinit();
        try self.createTextures();
        return self;
    }

    fn deinit(self: *GpuAtlas) void {
        c.wgpuTextureRelease(self.curve_tex);
        c.wgpuTextureRelease(self.band_tex);
        c.wgpuTextureRelease(self.layer_tex);
        c.wgpuTextureRelease(self.image_tex);
        self.uploads.deinit();
        self.* = undefined;
    }

    fn createTextures(self: *GpuAtlas) !void {
        const curve_height = self.pool.options.curve_words_per_page / (snail.atlas_upload.CURVE_TEX_WIDTH * 4);
        const band_height = self.pool.options.band_words_per_page / (snail.atlas_upload.BAND_TEX_WIDTH * 2);
        const layers = self.pool.options.max_layers;

        self.curve_tex = try createTexture(self.gpu.device, "snail-curves", c.WGPUTextureFormat_RGBA16Float, snail.atlas_upload.CURVE_TEX_WIDTH, @intCast(curve_height), @intCast(layers));
        self.band_tex = try createTexture(self.gpu.device, "snail-bands", c.WGPUTextureFormat_RG16Uint, snail.atlas_upload.BAND_TEX_WIDTH, @intCast(band_height), @intCast(layers));
        self.layer_tex = try createTexture(self.gpu.device, "snail-layer-info", c.WGPUTextureFormat_RGBA32Float, snail.atlas_upload.INFO_WIDTH, options.layer_info_height, 1);
        self.image_tex = try createTexture(self.gpu.device, "snail-images", c.WGPUTextureFormat_RGBA8UnormSrgb, 1, 1, 1);
    }

    fn createTexture(device: c.WGPUDevice, label: []const u8, format: c.WGPUTextureFormat, w: u32, h: u32, layers: u32) !c.WGPUTexture {
        const desc = std.mem.zeroInit(c.WGPUTextureDescriptor, .{
            .label = sv(label),
            .usage = c.WGPUTextureUsage_TextureBinding | c.WGPUTextureUsage_CopyDst,
            .dimension = c.WGPUTextureDimension_2D,
            .size = c.WGPUExtent3D{ .width = w, .height = h, .depthOrArrayLayers = layers },
            .format = format,
            .mipLevelCount = 1,
            .sampleCount = 1,
        });
        return c.wgpuDeviceCreateTexture(device, &desc) orelse error.TextureFailed;
    }

    fn arrayView(texture: c.WGPUTexture) !c.WGPUTextureView {
        const desc = std.mem.zeroInit(c.WGPUTextureViewDescriptor, .{
            .dimension = c.WGPUTextureViewDimension_2DArray,
            .mipLevelCount = 1,
            .arrayLayerCount = c.wgpuTextureGetDepthOrArrayLayers(texture),
            .aspect = c.WGPUTextureAspect_All,
        });
        return c.wgpuTextureCreateView(texture, &desc) orelse error.ViewFailed;
    }

    fn planeView(texture: c.WGPUTexture) !c.WGPUTextureView {
        const desc = std.mem.zeroInit(c.WGPUTextureViewDescriptor, .{
            .dimension = c.WGPUTextureViewDimension_2D,
            .mipLevelCount = 1,
            .arrayLayerCount = 1,
            .aspect = c.WGPUTextureAspect_All,
        });
        return c.wgpuTextureCreateView(texture, &desc) orelse error.ViewFailed;
    }

    /// Upload after every `Atlas.extend` — identical planner protocol to the
    /// GL example: keep the binding on `planDelta`, replan larger on growth.
    fn upload(self: *GpuAtlas, atlas: *const snail.Atlas) !void {
        const planned = if (self.binding) |old|
            self.uploads.planDelta(old, atlas) catch |err| switch (err) {
                error.NoLayerInfoRoomToGrow, error.NoImageRoomToGrow => blk: {
                    std.debug.assert(self.uploads.release(old));
                    break :blk try self.uploads.plan(atlas);
                },
                else => return err,
            }
        else
            try self.uploads.plan(atlas);

        for (planned.regions) |region| self.apply(region);
        self.binding = planned.binding;
    }

    fn apply(self: *GpuAtlas, region: snail.atlas_upload.Region) void {
        switch (region.target) {
            .curve => self.write(self.curve_tex, region, 8),
            .band => self.write(self.band_tex, region, 4),
            .layer_info => self.write(self.layer_tex, region, 16),
            .image => unreachable,
        }
    }

    fn write(self: *GpuAtlas, texture: c.WGPUTexture, region: snail.atlas_upload.Region, bytes_per_texel: u32) void {
        const dst = c.WGPUTexelCopyTextureInfo{
            .texture = texture,
            .mipLevel = 0,
            .origin = .{ .x = region.col_base, .y = region.row_base, .z = region.layer },
            .aspect = c.WGPUTextureAspect_All,
        };
        const layout = c.WGPUTexelCopyBufferLayout{
            .offset = 0,
            .bytesPerRow = region.width * bytes_per_texel,
            .rowsPerImage = region.height,
        };
        const extent = c.WGPUExtent3D{ .width = region.width, .height = region.height, .depthOrArrayLayers = 1 };
        c.wgpuQueueWriteTexture(self.gpu.queue, &dst, region.src.ptr, region.src.len, &layout, &extent);
    }
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var gpu = try Gpu.init();
    defer gpu.deinit();

    var font = try snail.Font.init(assets.dejavu_sans_mono);
    var emoji_font = try snail.Font.init(assets.twemoji_mozilla);
    var faces = try snail.Faces.build(allocator, &.{
        .{ .font = &font },
        .{ .font = &emoji_font, .fallback = true },
    });
    defer faces.deinit();
    const font_id = faces.fontIdForFace(0);

    var seed = try snail.shape(allocator, &faces, "Hello, ", .{});
    defer seed.deinit();
    var shaped = try snail.shape(allocator, &faces, text, .{});
    defer shaped.deinit();
    var emoji = try snail.shape(allocator, &faces, "\xF0\x9F\x8C\x8D", .{});
    defer emoji.deinit();

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 17,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var gpu_atlas = try GpuAtlas.init(allocator, &gpu, pool);
    defer gpu_atlas.deinit();

    // Round 1: seed a new atlas with the first part of the unhinted run.
    var atlas = snail.Atlas.init(allocator, pool);
    defer atlas.deinit();
    try snail.recordUnhintedRun(&atlas, allocator, &faces, &seed, .{});
    try gpu_atlas.upload(&atlas);

    // Round 2: extend it with the remaining unhinted glyphs (planDelta path).
    try snail.recordUnhintedRun(&atlas, allocator, &faces, &shaped, .{});
    try gpu_atlas.upload(&atlas);

    // Round 3: extend the same atlas with immutable autohint analysis.
    var analyzer = try snail.autohint.AutohintAnalyzer.init(allocator, assets.dejavu_sans_mono);
    defer analyzer.deinit();
    try snail.recordAutohintRun(&atlas, allocator, &analyzer, font_id, &shaped);
    try gpu_atlas.upload(&atlas);

    // Round 4: per-PPEM TT-hinted curves, filled and stroked paths, and one
    // composite COLR glyph — identical to the GL example.
    var tt_hint_vm = try snail.TtHintVm.init(allocator, &font);
    defer tt_hint_vm.deinit();
    var prepared = try tt_hint_vm.prepare(snail.TtHintPpem.uniform(ppem));
    defer prepared.deinit();
    try snail.recordTtHintRun(&atlas, allocator, &tt_hint_vm, &prepared, font_id, &shaped);
    const path_shapes = try extendWithPaths(allocator, &atlas);
    try snail.recordUnhintedRun(&atlas, allocator, &faces, &emoji, .{
        .colr_foreground = snail.color.srgbToLinearColor(.{ 0.18, 0.35, 0.70, 1.0 }),
    });
    const colr = try snail.placeRunAlloc(allocator, &emoji, null, .{
        .baseline = .{ .x = 775, .y = 145 },
        .em = 92,
        .color = .{ 1, 1, 1, 1 },
    });
    defer allocator.free(colr);
    std.debug.assert(colr.len == 1);
    const extras = [3]snail.Shape{
        path_shapes[0],
        path_shapes[1],
        colr[0],
    };
    try gpu_atlas.upload(&atlas);

    const autohint_policy = snail.autohint.AutohintPolicy{
        .x = .{ .@"align" = .grid, .stem_width = .{ .full = .{ .std_snap_ratio = 0.10 } }, .positioning = .relative },
        .y = .{ .@"align" = .blue_zones, .stem_width = .{ .full = .{ .std_snap_ratio = 0.10 } } },
    };
    const world_to_pixel = snail.Transform2D.identity;
    const unhinted = try snail.placeRunAlloc(allocator, &shaped, null, .{
        .baseline = .{ .x = 48, .y = 92 },
        .em = 34,
        .color = snail.color.srgbToLinearColor(.{ 0.10, 0.22, 0.48, 1.0 }),
        .mode = .unhinted,
    });
    defer allocator.free(unhinted);
    const autohinted = try snail.placeRunAlloc(allocator, &shaped, null, .{
        .baseline = .{ .x = 48, .y = 202 },
        .em = 34,
        .color = snail.color.srgbToLinearColor(.{ 0.18, 0.48, 0.30, 1.0 }),
        .mode = .{ .autohint = autohint_policy },
        .snap = .origins,
        .world_to_pixel = world_to_pixel,
    });
    defer allocator.free(autohinted);
    const tt_hinted = try snail.placeRunAlloc(allocator, &shaped, null, .{
        .baseline = .{ .x = 48, .y = 312 },
        .em = 34,
        .color = snail.color.srgbToLinearColor(.{ 0.54, 0.20, 0.20, 1.0 }),
        .mode = .{ .tt_hint = .{ .ppem_26_6 = ppem } },
        .snap = .origins,
        .world_to_pixel = world_to_pixel,
    });
    defer allocator.free(tt_hinted);

    const total_shapes = extras.len + unhinted.len + autohinted.len + tt_hinted.len;
    const instances = try allocator.alloc(snail.render.records.Instance, total_shapes);
    defer allocator.free(instances);
    const batches = try allocator.alloc(snail.render.records.DrawBatch, total_shapes);
    defer allocator.free(batches);
    var instance_len: usize = 0;
    var batch_len: usize = 0;
    const binding = gpu_atlas.binding.?;
    _ = try snail.emit.emit(instances, batches, &instance_len, &batch_len, binding, &atlas, &extras, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(instances, batches, &instance_len, &batch_len, binding, &atlas, unhinted, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(instances, batches, &instance_len, &batch_len, binding, &atlas, autohinted, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(instances, batches, &instance_len, &batch_len, binding, &atlas, tt_hinted, .identity, .{ 1, 1, 1, 1 });

    var seen = struct {
        regular: bool = false,
        autohint: bool = false,
        tt_hinted_text: bool = false,
        colr: bool = false,
        path_shapes: u32 = 0,
    }{};
    for (batches[0..batch_len]) |batch| switch (batch.kind) {
        .regular => seen.regular = true,
        .autohint => seen.autohint = true,
        .tt_hinted_text => seen.tt_hinted_text = true,
        .colr => seen.colr = true,
        .path => seen.path_shapes += batch.instance_count,
    };
    std.debug.assert(seen.regular and seen.autohint and seen.tt_hinted_text and seen.colr and seen.path_shapes == 2);

    // ── GPU resources ──

    var layouts = try Layouts.init(gpu.device);
    defer layouts.deinit();
    var pipelines = try Pipelines.init(gpu.device, layouts.pipeline);
    defer pipelines.deinit();

    const curve_view = try GpuAtlas.arrayView(gpu_atlas.curve_tex);
    defer c.wgpuTextureViewRelease(curve_view);
    const band_view = try GpuAtlas.arrayView(gpu_atlas.band_tex);
    defer c.wgpuTextureViewRelease(band_view);
    const layer_view = try GpuAtlas.planeView(gpu_atlas.layer_tex);
    defer c.wgpuTextureViewRelease(layer_view);
    const image_view = try GpuAtlas.arrayView(gpu_atlas.image_tex);
    defer c.wgpuTextureViewRelease(image_view);

    const nearest_desc = std.mem.zeroInit(c.WGPUSamplerDescriptor, .{
        .addressModeU = c.WGPUAddressMode_ClampToEdge,
        .addressModeV = c.WGPUAddressMode_ClampToEdge,
        .addressModeW = c.WGPUAddressMode_ClampToEdge,
        .magFilter = c.WGPUFilterMode_Nearest,
        .minFilter = c.WGPUFilterMode_Nearest,
        .mipmapFilter = c.WGPUMipmapFilterMode_Nearest,
        .lodMaxClamp = 32.0,
        .maxAnisotropy = 1,
    });
    const nearest_sampler = c.wgpuDeviceCreateSampler(gpu.device, &nearest_desc) orelse return error.SamplerFailed;
    defer c.wgpuSamplerRelease(nearest_sampler);
    var linear_desc = nearest_desc;
    linear_desc.magFilter = c.WGPUFilterMode_Linear;
    linear_desc.minFilter = c.WGPUFilterMode_Linear;
    const linear_sampler = c.wgpuDeviceCreateSampler(gpu.device, &linear_desc) orelse return error.SamplerFailed;
    defer c.wgpuSamplerRelease(linear_sampler);

    const uniform_buffer = c.wgpuDeviceCreateBuffer(gpu.device, &std.mem.zeroInit(c.WGPUBufferDescriptor, .{
        .label = sv("snail-push-constants"),
        .usage = c.WGPUBufferUsage_Uniform | c.WGPUBufferUsage_CopyDst,
        .size = @sizeOf(PushConstants),
    })) orelse return error.BufferFailed;
    defer c.wgpuBufferRelease(uniform_buffer);
    // Vulkan-style projection (y flipped relative to the GL example's
    // `ortho(0, w, h, 0)`): the WGSL catalog is generated from the Vulkan
    // shaders and naga keeps their clip-space convention, so scene y-down
    // maps through `bottom = 0, top = height`.
    const push_constants = PushConstants{
        .mvp = snail.Mat4.ortho(0, width, 0, height, -1, 1).data,
        .viewport = .{ width, height },
    };
    c.wgpuQueueWriteBuffer(gpu.queue, uniform_buffer, 0, &push_constants, @sizeOf(PushConstants));

    var texture_entries = [4]c.WGPUBindGroupEntry{
        std.mem.zeroInit(c.WGPUBindGroupEntry, .{ .binding = 0, .textureView = curve_view }),
        std.mem.zeroInit(c.WGPUBindGroupEntry, .{ .binding = 1, .textureView = band_view }),
        std.mem.zeroInit(c.WGPUBindGroupEntry, .{ .binding = 2, .textureView = layer_view }),
        std.mem.zeroInit(c.WGPUBindGroupEntry, .{ .binding = 3, .textureView = image_view }),
    };
    const texture_group = c.wgpuDeviceCreateBindGroup(gpu.device, &.{
        .nextInChain = null,
        .label = sv("snail-textures"),
        .layout = layouts.textures,
        .entryCount = texture_entries.len,
        .entries = &texture_entries,
    }) orelse return error.BindGroupFailed;
    defer c.wgpuBindGroupRelease(texture_group);

    var sampler_entries = [4]c.WGPUBindGroupEntry{
        std.mem.zeroInit(c.WGPUBindGroupEntry, .{ .binding = 0, .sampler = nearest_sampler }),
        std.mem.zeroInit(c.WGPUBindGroupEntry, .{ .binding = 1, .sampler = nearest_sampler }),
        std.mem.zeroInit(c.WGPUBindGroupEntry, .{ .binding = 2, .sampler = nearest_sampler }),
        std.mem.zeroInit(c.WGPUBindGroupEntry, .{ .binding = 3, .sampler = linear_sampler }),
    };
    const sampler_group = c.wgpuDeviceCreateBindGroup(gpu.device, &.{
        .nextInChain = null,
        .label = sv("snail-samplers"),
        .layout = layouts.samplers,
        .entryCount = sampler_entries.len,
        .entries = &sampler_entries,
    }) orelse return error.BindGroupFailed;
    defer c.wgpuBindGroupRelease(sampler_group);

    var uniform_entries = [1]c.WGPUBindGroupEntry{
        std.mem.zeroInit(c.WGPUBindGroupEntry, .{ .binding = 0, .buffer = uniform_buffer, .size = @sizeOf(PushConstants) }),
    };
    const uniform_group = c.wgpuDeviceCreateBindGroup(gpu.device, &.{
        .nextInChain = null,
        .label = sv("snail-uniforms"),
        .layout = layouts.uniforms,
        .entryCount = uniform_entries.len,
        .entries = &uniform_entries,
    }) orelse return error.BindGroupFailed;
    defer c.wgpuBindGroupRelease(uniform_group);

    // Geometry: the whole emit stream in one instance buffer plus the shared
    // six-index quad; batches select their run via firstInstance.
    const instance_bytes = std.mem.sliceAsBytes(instances[0..instance_len]);
    const instance_buffer = c.wgpuDeviceCreateBuffer(gpu.device, &std.mem.zeroInit(c.WGPUBufferDescriptor, .{
        .label = sv("snail-instances"),
        .usage = c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst,
        .size = instance_bytes.len,
    })) orelse return error.BufferFailed;
    defer c.wgpuBufferRelease(instance_buffer);
    c.wgpuQueueWriteBuffer(gpu.queue, instance_buffer, 0, instance_bytes.ptr, instance_bytes.len);

    const indices = [6]u32{ 1, 2, 0, 2, 3, 0 };
    const index_buffer = c.wgpuDeviceCreateBuffer(gpu.device, &std.mem.zeroInit(c.WGPUBufferDescriptor, .{
        .label = sv("snail-quad-indices"),
        .usage = c.WGPUBufferUsage_Index | c.WGPUBufferUsage_CopyDst,
        .size = @sizeOf(@TypeOf(indices)),
    })) orelse return error.BufferFailed;
    defer c.wgpuBufferRelease(index_buffer);
    c.wgpuQueueWriteBuffer(gpu.queue, index_buffer, 0, &indices, @sizeOf(@TypeOf(indices)));

    const target_tex = c.wgpuDeviceCreateTexture(gpu.device, &std.mem.zeroInit(c.WGPUTextureDescriptor, .{
        .label = sv("snail-target"),
        .usage = c.WGPUTextureUsage_RenderAttachment | c.WGPUTextureUsage_CopySrc,
        .dimension = c.WGPUTextureDimension_2D,
        .size = c.WGPUExtent3D{ .width = width, .height = height, .depthOrArrayLayers = 1 },
        .format = c.WGPUTextureFormat_RGBA8UnormSrgb,
        .mipLevelCount = 1,
        .sampleCount = 1,
    })) orelse return error.TextureFailed;
    defer c.wgpuTextureRelease(target_tex);
    const target_view = try GpuAtlas.planeView(target_tex);
    defer c.wgpuTextureViewRelease(target_view);

    // ── Encode + draw ──

    const encoder = c.wgpuDeviceCreateCommandEncoder(gpu.device, &std.mem.zeroInit(c.WGPUCommandEncoderDescriptor, .{})) orelse return error.EncoderFailed;
    defer c.wgpuCommandEncoderRelease(encoder);

    const color_attachments = [1]c.WGPURenderPassColorAttachment{.{
        .nextInChain = null,
        .view = target_view,
        .depthSlice = c.WGPU_DEPTH_SLICE_UNDEFINED,
        .resolveTarget = null,
        .loadOp = c.WGPULoadOp_Clear,
        .storeOp = c.WGPUStoreOp_Store,
        // Linear clear color: the sRGB attachment encodes on write, matching
        // the GL example's glClearColor under GL_FRAMEBUFFER_SRGB.
        .clearValue = .{ .r = 0.955, .g = 0.965, .b = 0.985, .a = 1.0 },
    }};
    const pass = c.wgpuCommandEncoderBeginRenderPass(encoder, &std.mem.zeroInit(c.WGPURenderPassDescriptor, .{
        .colorAttachmentCount = color_attachments.len,
        .colorAttachments = &color_attachments,
    })) orelse return error.RenderPassFailed;

    c.wgpuRenderPassEncoderSetBindGroup(pass, 0, texture_group, 0, null);
    c.wgpuRenderPassEncoderSetBindGroup(pass, 1, sampler_group, 0, null);
    c.wgpuRenderPassEncoderSetBindGroup(pass, 2, uniform_group, 0, null);
    c.wgpuRenderPassEncoderSetIndexBuffer(pass, index_buffer, c.WGPUIndexFormat_Uint32, 0, @sizeOf(@TypeOf(indices)));
    c.wgpuRenderPassEncoderSetVertexBuffer(pass, 0, instance_buffer, 0, instance_bytes.len);
    for (batches[0..batch_len]) |batch| {
        c.wgpuRenderPassEncoderSetPipeline(pass, pipelines.forKind(batch.kind));
        c.wgpuRenderPassEncoderDrawIndexed(pass, indices.len, batch.instance_count, 0, 0, batch.first_instance);
    }
    c.wgpuRenderPassEncoderEnd(pass);
    c.wgpuRenderPassEncoderRelease(pass);

    // ── Readback ──

    const bytes_per_row = width * 4; // 3840, already a multiple of 256
    comptime std.debug.assert(bytes_per_row % 256 == 0);
    const readback_size = bytes_per_row * height;
    const readback_buffer = c.wgpuDeviceCreateBuffer(gpu.device, &std.mem.zeroInit(c.WGPUBufferDescriptor, .{
        .label = sv("snail-readback"),
        .usage = c.WGPUBufferUsage_CopyDst | c.WGPUBufferUsage_MapRead,
        .size = readback_size,
    })) orelse return error.BufferFailed;
    defer c.wgpuBufferRelease(readback_buffer);

    const copy_src = c.WGPUTexelCopyTextureInfo{
        .texture = target_tex,
        .mipLevel = 0,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
        .aspect = c.WGPUTextureAspect_All,
    };
    const copy_dst = c.WGPUTexelCopyBufferInfo{
        .layout = .{ .offset = 0, .bytesPerRow = bytes_per_row, .rowsPerImage = height },
        .buffer = readback_buffer,
    };
    c.wgpuCommandEncoderCopyTextureToBuffer(encoder, &copy_src, &copy_dst, &.{ .width = width, .height = height, .depthOrArrayLayers = 1 });

    const command = c.wgpuCommandEncoderFinish(encoder, null) orelse return error.CommandFailed;
    defer c.wgpuCommandBufferRelease(command);
    c.wgpuQueueSubmit(gpu.queue, 1, &command);

    // `AllowSpontaneous` is load-bearing: with `AllowProcessEvents` the
    // blocking `wgpuDevicePoll(wait = true)` deadlocks — it waits for the map
    // operation whose completion callback would only be delivered by a
    // `wgpuInstanceProcessEvents` call that never gets to run.
    var map_req = MapRequest{};
    _ = c.wgpuBufferMapAsync(readback_buffer, c.WGPUMapMode_Read, 0, readback_size, .{
        .nextInChain = null,
        .mode = c.WGPUCallbackMode_AllowSpontaneous,
        .callback = &onMap,
        .userdata1 = &map_req,
        .userdata2 = null,
    });
    while (!map_req.done) {
        _ = c.wgpuDevicePoll(gpu.device, 1, null);
        c.wgpuInstanceProcessEvents(gpu.instance);
    }
    if (!map_req.ok) return error.MapFailed;

    const mapped: [*]const u8 = @ptrCast(c.wgpuBufferGetConstMappedRange(readback_buffer, 0, readback_size) orelse return error.MapRangeFailed);
    try writeTga(mapped[0..readback_size], "zig-out/minimal-wgpu.tga");
    c.wgpuBufferUnmap(readback_buffer);
    std.debug.print("wrote zig-out/minimal-wgpu.tga\n", .{});
}

fn extendWithPaths(allocator: std.mem.Allocator, atlas: *snail.Atlas) ![2]snail.Shape {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();

    // Filled path.
    var fill_path = snail.Path.init(allocator);
    defer fill_path.deinit();
    try fill_path.addRoundedRect(.{ .x = 530, .y = 205, .w = 145, .h = 105 }, 22);
    var prepared_fill = try fill_path.prepare(allocator);
    defer prepared_fill.deinit();
    var fill_curves = try prepared_fill.fillCurves(allocator, scratch.allocator());
    defer fill_curves.deinit();
    _ = scratch.reset(.retain_capacity);
    const fill_key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = 1 };

    // Stroked path.
    var stroke_path = snail.Path.init(allocator);
    defer stroke_path.deinit();
    try stroke_path.moveTo(.{ .x = 705, .y = 220 });
    try stroke_path.cubicTo(.{ .x = 760, .y = 330 }, .{ .x = 855, .y = 175 }, .{ .x = 920, .y = 295 });
    var prepared_stroke = try stroke_path.prepare(allocator);
    defer prepared_stroke.deinit();
    const stroke_style = snail.StrokeStyle{
        .paint = .{ .solid = snail.color.srgbToLinearColor(.{ 0.10, 0.48, 0.64, 1.0 }) },
        .width = 12,
        .cap = .round,
        .join = .round,
    };
    var stroke_curves = try prepared_stroke.strokeCurves(allocator, scratch.allocator(), stroke_style);
    defer stroke_curves.deinit();
    _ = scratch.reset(.retain_capacity);
    const stroke_key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_stroke, .a = 1 };

    try atlas.extendInPlace(allocator, &.{
        .{
            .key = fill_key,
            .curves = fill_curves,
            .paint = prepared_fill.paintForDesign(.{ .solid = snail.color.srgbToLinearColor(.{ 0.34, 0.25, 0.72, 0.92 }) }),
        },
        .{
            .key = stroke_key,
            .curves = stroke_curves,
            .paint = prepared_stroke.paintForDesign(stroke_style.paint),
        },
    });
    return .{
        .{ .key = fill_key, .local_transform = prepared_fill.placedBy(.identity) },
        .{ .key = stroke_key, .local_transform = prepared_stroke.placedBy(.identity) },
    };
}

/// Write the readback (row 0 = top) as a top-left-origin BGRA TGA, matching
/// the GL example's writer.
fn writeTga(pixels: []const u8, path: [:0]const u8) !void {
    _ = c.mkdir("zig-out", 0o755);
    const file = c.fopen(path.ptr, "wb") orelse return error.OpenOutputFailed;
    defer _ = c.fclose(file);
    var header = [_]u8{0} ** 18;
    header[2] = 2;
    header[12] = width & 0xff;
    header[13] = (width >> 8) & 0xff;
    header[14] = height & 0xff;
    header[15] = (height >> 8) & 0xff;
    header[16] = 32;
    header[17] = 8 | 0x20; // 8 alpha bits, top-left origin
    try fwrite(file, &header);
    var row: [width * 4]u8 = undefined;
    for (0..height) |y| {
        const source = pixels[y * width * 4 ..][0 .. width * 4];
        for (0..width) |x| {
            row[x * 4 + 0] = source[x * 4 + 2];
            row[x * 4 + 1] = source[x * 4 + 1];
            row[x * 4 + 2] = source[x * 4 + 0];
            row[x * 4 + 3] = source[x * 4 + 3];
        }
        try fwrite(file, &row);
    }
}

fn fwrite(file: *c.FILE, bytes: []const u8) !void {
    if (c.fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.WriteFailed;
}

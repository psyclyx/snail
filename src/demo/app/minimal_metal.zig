//! Minimal Snail + Metal example — the macOS analog of `minimal_wgpu.zig` /
//! `minimal_d3d11.zig`, rendering the identical scene with the generated
//! Metal MSL artifacts (`snail_shaders`, runtime-compiled with
//! `newLibraryWithSource:`).
//!
//! Linux cross-compiles this file (`zig build check-metal-demo`,
//! aarch64-macos semantic analysis + codegen). macOS CI additionally
//! runtime-compiles every generated MSL artifact, exercises the scene-used
//! pipelines on a real Metal GPU, and pixel-gates the result. See
//! src/snail/shader/slang/README-notes, "Metal stage", for coverage details.
//!
//! This file intentionally imports none of the demo renderer, cache, scene,
//! platform, or support modules — and none of the Apple SDK headers: Metal
//! is driven entirely through the Objective-C runtime (`objc_msgSend` +
//! `sel_registerName`, plus the `MTLCreateSystemDefaultDevice` C entry
//! point), so the file cross-compiles without an SDK. It owns the device
//! (headless; no CAMetalLayer/swapchain), the offscreen sRGB render target,
//! the four atlas textures per the binding contract, the upload loop,
//! per-family PSOs, draw submission, blit readback, and the screenshot
//! writer. Its one frame covers unhinted, autohinted, TT-hinted, and COLR
//! text plus filled and stroked paths.
//!
//! Binding contract (see `snail_shaders`): the 96-byte
//! push-constant block binds as `constant SnailPushConstants_natural*` at
//! [[buffer(0)]] (natural layout — byte-identical to the extern struct);
//! textures land on the Vulkan binding numbers as [[texture(0)]] curve,
//! [[texture(1)]] band, [[texture(2)]] layer-info, [[texture(3)]] image
//! array, [[sampler(0)]] image sampler. The instance stream arrives via
//! [[stage_in]] / [[attribute(0..6)]]; its MTLVertexDescriptor buffer index
//! is the host's choice and must not collide with the parameter block —
//! this demo uses buffer index 1. Entry points keep their Slang names
//! (`vertexMain`/`fragmentMain`). Metal clip space is y-up with z in [0,1]
//! (like D3D11/WebGPU) and the generated vertex flips y, so the mvp matches
//! `minimal_wgpu`/`minimal_d3d11` exactly: `ortho(0, w, 0, h)`. Metal
//! texture origin is top-left, so blit-readback rows arrive top-first like
//! both of those examples.

const std = @import("std");
const snail = @import("snail");
const assets = @import("assets");

// Only the C standard library (bundled with zig for macOS cross targets):
// the TGA writer mirrors minimal_wgpu's. No Apple framework headers.
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("sys/stat.h");
});

// Force full analysis + codegen even when built as a check-only static
// library on a non-macOS host (`zig build check-metal-demo`): semantic
// analysis is lazy and a library build would otherwise skip `main`.
comptime {
    _ = &main;
}

const width = 960;
const height = 420;
const text = "Hello, world!";
const ppem: u32 = 34 * 64;

const slang_gen = @import("snail_shaders");

/// The parameter block as a Metal `constant` buffer at [[buffer(0)]] —
/// the machine-derived layout from slangc reflection. The generated MSL
/// declares it with NATURAL (C) layout (`SnailPushConstants_natural`), so
/// this extern struct's bytes are the buffer contents verbatim.
const PushConstants = slang_gen.reflection.PushConstants;

// ── Objective-C runtime shim ──
//
// `objc_msgSend` is declared with an empty prototype and cast to the exact
// C function type per call site (the standard C convention for the
// runtime's trampoline). aarch64 has no `objc_msgSend_stret` split — one
// symbol serves every signature, including by-value struct arguments
// (MTLRegion/MTLClearColor below). No method used here RETURNS a struct,
// so this file stays off the struct-return ABI entirely.

const id = ?*anyopaque;
const SEL = ?*anyopaque;
const NSUInteger = usize;
const NSInteger = isize;

extern fn objc_msgSend() void;
extern fn sel_registerName(name: [*:0]const u8) SEL;
extern fn objc_getClass(name: [*:0]const u8) id;
extern fn objc_autoreleasePoolPush() ?*anyopaque;
extern fn objc_autoreleasePoolPop(pool: ?*anyopaque) void;
/// Metal.framework C entry point. NOTE (documented Apple gotcha): a
/// command-line tool must also link CoreGraphics or this returns nil —
/// build.zig links Metal + Foundation + CoreGraphics.
extern fn MTLCreateSystemDefaultDevice() id;

/// `[receiver selector: args...]` with an explicit return type. Argument
/// types are taken from the tuple as written — pass exact C types
/// (`@as(NSUInteger, ...)` etc.). The C function type is spelled out per
/// arity (up to the 9 arguments of the blit copy).
fn msg(comptime Ret: type, receiver: id, comptime sel_name: [:0]const u8, args: anytype) Ret {
    const a = @typeInfo(@TypeOf(args)).@"struct".fields;
    const F = switch (a.len) {
        0 => fn (id, SEL) callconv(.c) Ret,
        1 => fn (id, SEL, a[0].type) callconv(.c) Ret,
        2 => fn (id, SEL, a[0].type, a[1].type) callconv(.c) Ret,
        3 => fn (id, SEL, a[0].type, a[1].type, a[2].type) callconv(.c) Ret,
        4 => fn (id, SEL, a[0].type, a[1].type, a[2].type, a[3].type) callconv(.c) Ret,
        5 => fn (id, SEL, a[0].type, a[1].type, a[2].type, a[3].type, a[4].type) callconv(.c) Ret,
        6 => fn (id, SEL, a[0].type, a[1].type, a[2].type, a[3].type, a[4].type, a[5].type) callconv(.c) Ret,
        7 => fn (id, SEL, a[0].type, a[1].type, a[2].type, a[3].type, a[4].type, a[5].type, a[6].type) callconv(.c) Ret,
        8 => fn (id, SEL, a[0].type, a[1].type, a[2].type, a[3].type, a[4].type, a[5].type, a[6].type, a[7].type) callconv(.c) Ret,
        9 => fn (id, SEL, a[0].type, a[1].type, a[2].type, a[3].type, a[4].type, a[5].type, a[6].type, a[7].type, a[8].type) callconv(.c) Ret,
        else => @compileError("msg: unsupported arity"),
    };
    const f: *const F = @ptrCast(&objc_msgSend);
    return @call(.auto, f, .{ receiver, sel_registerName(sel_name.ptr) } ++ args);
}

fn class(comptime name: [:0]const u8) id {
    return objc_getClass(name.ptr);
}

fn release(obj: id) void {
    if (obj != null) msg(void, obj, "release", .{});
}

fn nsString(s: [:0]const u8) id {
    // Autoreleased; the demo runs inside one autorelease pool.
    return msg(id, class("NSString"), "stringWithUTF8String:", .{@as([*:0]const u8, s.ptr)});
}

fn nsErrorUtf8(err: id) [*:0]const u8 {
    if (err == null) return "(no NSError)";
    const desc = msg(id, err, "localizedDescription", .{});
    return msg([*:0]const u8, desc, "UTF8String", .{});
}

// ── Metal enum values (from the Metal.framework headers; the SDK is not
// available on the cross host, so the numeric values are pinned here —
// they are ABI-stable public constants) ──

const mtl = struct {
    // MTLPixelFormat
    const PixelFormatRGBA8Unorm_sRGB: NSUInteger = 71;
    const PixelFormatRG16Uint: NSUInteger = 63;
    const PixelFormatRGBA16Float: NSUInteger = 115;
    const PixelFormatRGBA32Float: NSUInteger = 125;
    // MTLVertexFormat
    const VertexFormatHalf4: NSUInteger = 27;
    const VertexFormatFloat2: NSUInteger = 29;
    const VertexFormatFloat4: NSUInteger = 31;
    const VertexFormatUInt2: NSUInteger = 37;
    const VertexFormatUInt4: NSUInteger = 39;
    // MTLVertexStepFunction
    const VertexStepFunctionPerInstance: NSUInteger = 2;
    // MTLTextureType
    const TextureType2D: NSUInteger = 2;
    const TextureType2DArray: NSUInteger = 3;
    // MTLTextureUsage (bitmask)
    const TextureUsageShaderRead: NSUInteger = 1;
    const TextureUsageRenderTarget: NSUInteger = 4;
    // MTLStorageMode
    const StorageModeShared: NSUInteger = 0;
    const StorageModePrivate: NSUInteger = 2;
    // MTLResourceOptions (storage/cache bits; 0 = shared + default cache)
    const ResourceStorageModeShared: NSUInteger = 0;
    // MTLLoadAction / MTLStoreAction
    const LoadActionClear: NSUInteger = 2;
    const StoreActionStore: NSUInteger = 1;
    // MTLPrimitiveType / MTLIndexType
    const PrimitiveTypeTriangle: NSUInteger = 3;
    const IndexTypeUInt32: NSUInteger = 1;
    // MTLBlendFactor / MTLBlendOperation
    const BlendFactorOne: NSUInteger = 1;
    const BlendFactorOneMinusSourceAlpha: NSUInteger = 5;
    const BlendOperationAdd: NSUInteger = 0;
    // MTLSamplerMinMagFilter / MTLSamplerAddressMode
    const SamplerMinMagFilterLinear: NSUInteger = 1;
    const SamplerAddressModeClampToEdge: NSUInteger = 0;
};

const MTLOrigin = extern struct { x: NSUInteger, y: NSUInteger, z: NSUInteger };
const MTLSize = extern struct { width: NSUInteger, height: NSUInteger, depth: NSUInteger };
const MTLRegion = extern struct { origin: MTLOrigin, size: MTLSize };
const MTLClearColor = extern struct { red: f64, green: f64, blue: f64, alpha: f64 };

/// MTLVertexDescriptor buffer index of the instance stream. Must not
/// collide with the parameter block at [[buffer(0)]]: [[stage_in]] data and
/// explicit buffer bindings share one vertex argument table.
const instance_buffer_index: NSUInteger = 1;

// ── Device ──

const Gpu = struct {
    device: id,
    queue: id,

    fn init() !Gpu {
        const device = MTLCreateSystemDefaultDevice();
        if (device == null) {
            std.debug.print("MTLCreateSystemDefaultDevice returned nil (CoreGraphics linked? headless session?)\n", .{});
            return error.NoMetalDevice;
        }
        const queue = msg(id, device, "newCommandQueue", .{});
        if (queue == null) return error.NoCommandQueue;
        return .{ .device = device, .queue = queue };
    }

    fn deinit(self: *Gpu) void {
        release(self.queue);
        release(self.device);
    }
};

// ── Shaders / pipelines ──

/// Runtime-compile one generated MSL artifact into a MTLLibrary. On
/// failure the NSError text is printed verbatim — paste it into the
/// handoff notes (README-notes, Metal stage) when reporting.
fn compileLibrary(device: id, source: [:0]const u8, label: []const u8) !id {
    const options = msg(id, msg(id, class("MTLCompileOptions"), "alloc", .{}), "init", .{});
    defer release(options);
    // Metal's shader compiler defaults to fast-math, which relaxes FP the
    // way Mesa's fma fusion did (1-LSB drift on every AA edge — observed
    // as ~2.9k gate pixels vs the ~680 cross-backend class on the first
    // CI run). No other backend compiles snail's shaders with fast-math;
    // disable it so Metal joins the same numeric class. Both spellings:
    // `fastMathEnabled` (BOOL, deprecated — can be a no-op shim on
    // macOS 15+) and `mathMode` (MTLMathModeSafe = 0, the replacement).
    // `respondsToSelector:` guards the newer setter on older frameworks.
    msg(void, options, "setFastMathEnabled:", .{@as(i8, 0)});
    if (msg(i8, options, "respondsToSelector:", .{sel_registerName("setMathMode:")}) != 0) {
        msg(void, options, "setMathMode:", .{@as(isize, 0)});
    }
    std.debug.print("metal compile options: fast-math disabled (mathMode safe where available)\n", .{});
    var err: id = null;
    const library = msg(id, device, "newLibraryWithSource:options:error:", .{ nsString(source), options, @as(*id, &err) });
    if (library == null) {
        std.debug.print("newLibraryWithSource({s}) failed:\n{s}\n", .{ label, nsErrorUtf8(err) });
        return error.ShaderCompileFailed;
    }
    return library;
}

/// The seven per-instance attributes mirroring the Vulkan contract's
/// locations 0–6 (the generated MSL names them [[attribute(0..6)]]).
/// One descriptor serves every vertex function — Metal ignores descriptor
/// attributes a function does not declare (text reads 0..6).
fn createVertexDescriptor() id {
    const Instance = snail.render.records.Instance;
    const desc = msg(id, class("MTLVertexDescriptor"), "vertexDescriptor", .{}); // autoreleased
    const attrs = msg(id, desc, "attributes", .{});
    const table = [7]struct { format: NSUInteger, offset: NSUInteger }{
        .{ .format = mtl.VertexFormatHalf4, .offset = @offsetOf(Instance, "rect") },
        .{ .format = mtl.VertexFormatFloat4, .offset = @offsetOf(Instance, "xform") },
        .{ .format = mtl.VertexFormatFloat2, .offset = @offsetOf(Instance, "origin") },
        .{ .format = mtl.VertexFormatUInt2, .offset = @offsetOf(Instance, "glyph") },
        .{ .format = mtl.VertexFormatUInt4, .offset = @offsetOf(Instance, "payload") },
        .{ .format = mtl.VertexFormatHalf4, .offset = @offsetOf(Instance, "color") },
        .{ .format = mtl.VertexFormatHalf4, .offset = @offsetOf(Instance, "tint") },
    };
    for (table, 0..) |entry, i| {
        const attr = msg(id, attrs, "objectAtIndexedSubscript:", .{@as(NSUInteger, i)});
        msg(void, attr, "setFormat:", .{entry.format});
        msg(void, attr, "setOffset:", .{entry.offset});
        msg(void, attr, "setBufferIndex:", .{instance_buffer_index});
    }
    const layout = msg(id, msg(id, desc, "layouts", .{}), "objectAtIndexedSubscript:", .{instance_buffer_index});
    msg(void, layout, "setStride:", .{@as(NSUInteger, snail.render.records.BYTES_PER_INSTANCE)});
    msg(void, layout, "setStepFunction:", .{mtl.VertexStepFunctionPerInstance});
    msg(void, layout, "setStepRate:", .{@as(NSUInteger, 1)});
    return desc;
}

const Pipelines = struct {
    regular: id = null,
    autohint: id = null,
    tt_hint: id = null,
    path: id = null,
    colr: id = null,

    fn init(device: id) !Pipelines {
        var self = Pipelines{};
        errdefer self.deinit();

        // Entry points keep their Slang names; fragment-only families pair
        // with the text vertex artifact. Each artifact is a self-contained
        // MSL module compiled into its own library.
        const text_vert_lib = try compileLibrary(device, slang_gen.textMsl(.vertex), "text.vert");
        defer release(text_vert_lib);
        const autohint_vert_lib = try compileLibrary(device, slang_gen.autohintMsl(.vertex), "autohint.vert");
        defer release(autohint_vert_lib);
        const text_frag_lib = try compileLibrary(device, slang_gen.textMsl(.fragment), "text.frag");
        defer release(text_frag_lib);
        const autohint_frag_lib = try compileLibrary(device, slang_gen.autohintMsl(.fragment), "autohint.frag");
        defer release(autohint_frag_lib);
        const tt_frag_lib = try compileLibrary(device, slang_gen.ttHintedFragMsl(), "tt_hinted_text.frag");
        defer release(tt_frag_lib);
        const path_frag_lib = try compileLibrary(device, slang_gen.pathFragMsl(), "path.frag");
        defer release(path_frag_lib);
        const colr_frag_lib = try compileLibrary(device, slang_gen.colrFragMsl(), "colr.frag");
        defer release(colr_frag_lib);

        const vdesc = createVertexDescriptor();
        self.regular = try createPipeline(device, text_vert_lib, text_frag_lib, vdesc, "snail-text");
        self.autohint = try createPipeline(device, autohint_vert_lib, autohint_frag_lib, vdesc, "snail-autohint");
        self.tt_hint = try createPipeline(device, text_vert_lib, tt_frag_lib, vdesc, "snail-tt-hint");
        self.path = try createPipeline(device, text_vert_lib, path_frag_lib, vdesc, "snail-path");
        self.colr = try createPipeline(device, text_vert_lib, colr_frag_lib, vdesc, "snail-colr");
        return self;
    }

    fn deinit(self: *Pipelines) void {
        release(self.regular);
        release(self.autohint);
        release(self.tt_hint);
        release(self.path);
        release(self.colr);
    }

    fn forKind(self: *const Pipelines, kind: snail.render.records.ShapeKind) id {
        return switch (kind) {
            .regular => self.regular,
            .autohint => self.autohint,
            .tt_hinted_text => self.tt_hint,
            .path => self.path,
            .colr => self.colr,
        };
    }

    fn createPipeline(device: id, vert_lib: id, frag_lib: id, vdesc: id, label: [:0]const u8) !id {
        const vfn = msg(id, vert_lib, "newFunctionWithName:", .{nsString(slang_gen.msl_vertex_entry)});
        if (vfn == null) return error.MissingVertexEntry;
        defer release(vfn);
        const ffn = msg(id, frag_lib, "newFunctionWithName:", .{nsString(slang_gen.msl_fragment_entry)});
        if (ffn == null) return error.MissingFragmentEntry;
        defer release(ffn);

        const desc = msg(id, msg(id, class("MTLRenderPipelineDescriptor"), "alloc", .{}), "init", .{});
        defer release(desc);
        msg(void, desc, "setLabel:", .{nsString(label)});
        msg(void, desc, "setVertexFunction:", .{vfn});
        msg(void, desc, "setFragmentFunction:", .{ffn});
        msg(void, desc, "setVertexDescriptor:", .{vdesc});

        // Premultiplied-over blend on the sRGB attachment, matching the
        // Vulkan contract's blendAttachment (and minimal_wgpu/d3d11).
        const attachment = msg(id, msg(id, desc, "colorAttachments", .{}), "objectAtIndexedSubscript:", .{@as(NSUInteger, 0)});
        msg(void, attachment, "setPixelFormat:", .{mtl.PixelFormatRGBA8Unorm_sRGB});
        msg(void, attachment, "setBlendingEnabled:", .{true});
        msg(void, attachment, "setRgbBlendOperation:", .{mtl.BlendOperationAdd});
        msg(void, attachment, "setAlphaBlendOperation:", .{mtl.BlendOperationAdd});
        msg(void, attachment, "setSourceRGBBlendFactor:", .{mtl.BlendFactorOne});
        msg(void, attachment, "setSourceAlphaBlendFactor:", .{mtl.BlendFactorOne});
        msg(void, attachment, "setDestinationRGBBlendFactor:", .{mtl.BlendFactorOneMinusSourceAlpha});
        msg(void, attachment, "setDestinationAlphaBlendFactor:", .{mtl.BlendFactorOneMinusSourceAlpha});

        var err: id = null;
        const pso = msg(id, device, "newRenderPipelineStateWithDescriptor:error:", .{ desc, @as(*id, &err) });
        if (pso == null) {
            std.debug.print("newRenderPipelineState({s}) failed:\n{s}\n", .{ label, nsErrorUtf8(err) });
            return error.PipelineFailed;
        }
        return pso;
    }
};

/// Compile-check every generated MSL fragment the scene does not draw: all
/// three LCD-subpixel families (plain-MRT flavor, see the generated module's
/// caveat) and the text_sample material module. This makes a
/// `run-minimal-metal` pass validate the complete catalog against Apple's
/// real Metal compiler.
fn validateRemainingArtifacts(device: id) !void {
    const subpixel = try compileLibrary(device, slang_gen.subpixelFragMsl(), "text_subpixel.frag");
    release(subpixel);
    const tt_subpixel = try compileLibrary(device, slang_gen.ttHintedSubpixelFragMsl(), "tt_hinted_text_subpixel.frag");
    release(tt_subpixel);
    const autohint_subpixel = try compileLibrary(device, slang_gen.autohintSubpixelFragMsl(), "autohint_subpixel.frag");
    release(autohint_subpixel);
    const sample = try compileLibrary(device, slang_gen.textSampleFragMsl(), "text_sample.frag");
    release(sample);
}

// ── Atlas residency ──

/// The complete caller-owned GPU side of a Snail atlas: Metal textures fed
/// by the planner's regions through `replaceRegion:` (CPU-writable shared
/// storage — no staging pass needed for this one-shot demo).
const GpuAtlas = struct {
    gpu: *const Gpu,
    pool: *snail.PagePool,
    curve_tex: id = null,
    band_tex: id = null,
    layer_tex: id = null,
    image_tex: id = null, // 1×1 placeholder: the scene packs no image paints
    uploads: snail.atlas_upload.OwnedPlanner,
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
            .uploads = try snail.atlas_upload.OwnedPlanner.init(allocator, pool, options),
        };
        errdefer self.uploads.deinit();
        try self.createTextures();
        return self;
    }

    fn deinit(self: *GpuAtlas) void {
        release(self.curve_tex);
        release(self.band_tex);
        release(self.layer_tex);
        release(self.image_tex);
        self.uploads.deinit();
        self.* = undefined;
    }

    fn createTextures(self: *GpuAtlas) !void {
        const device = self.gpu.device;
        const pool_config = self.pool.config();
        const curve_height = pool_config.curve_words_per_page / (snail.atlas_upload.CURVE_TEX_WIDTH * 4);
        const band_height = pool_config.band_words_per_page / (snail.atlas_upload.BAND_TEX_WIDTH * 2);
        const layers: NSUInteger = @intCast(pool_config.max_layers);

        self.curve_tex = try createTexture(device, mtl.TextureType2DArray, mtl.PixelFormatRGBA16Float, snail.atlas_upload.CURVE_TEX_WIDTH, @intCast(curve_height), layers);
        self.band_tex = try createTexture(device, mtl.TextureType2DArray, mtl.PixelFormatRG16Uint, snail.atlas_upload.BAND_TEX_WIDTH, @intCast(band_height), layers);
        // The layer-info texture is `texture2d` in the MSL (not an array).
        self.layer_tex = try createTexture(device, mtl.TextureType2D, mtl.PixelFormatRGBA32Float, snail.atlas_upload.INFO_WIDTH, options.layer_info_height, 1);
        // The image placeholder must still be a texture2d_array to match
        // [[texture(3)]]'s declared type.
        self.image_tex = try createTexture(device, mtl.TextureType2DArray, mtl.PixelFormatRGBA8Unorm_sRGB, 1, 1, 1);
    }

    fn createTexture(device: id, texture_type: NSUInteger, format: NSUInteger, w: NSUInteger, h: NSUInteger, layers: NSUInteger) !id {
        const desc = msg(id, msg(id, class("MTLTextureDescriptor"), "alloc", .{}), "init", .{});
        defer release(desc);
        msg(void, desc, "setTextureType:", .{texture_type});
        msg(void, desc, "setPixelFormat:", .{format});
        msg(void, desc, "setWidth:", .{w});
        msg(void, desc, "setHeight:", .{h});
        msg(void, desc, "setArrayLength:", .{layers});
        msg(void, desc, "setMipmapLevelCount:", .{@as(NSUInteger, 1)});
        msg(void, desc, "setUsage:", .{mtl.TextureUsageShaderRead});
        // Shared storage: `replaceRegion:` uploads directly from the CPU.
        // (Shared TEXTURES require unified memory — Apple silicon. On an
        // Intel Mac change this to Managed (1); render-target readback is
        // unaffected since it blits into a shared BUFFER.)
        msg(void, desc, "setStorageMode:", .{mtl.StorageModeShared});
        const tex = msg(id, device, "newTextureWithDescriptor:", .{desc});
        if (tex == null) return error.TextureFailed;
        return tex;
    }

    /// Upload after every `Atlas.extend` — identical planner protocol to the
    /// GL/WebGPU/D3D11 examples: keep the binding on `planDelta`, replan
    /// larger on growth.
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
            .curve => write(self.curve_tex, region, 8),
            .band => write(self.band_tex, region, 4),
            .layer_info => write(self.layer_tex, region, 16),
            .image => unreachable,
        }
    }

    fn write(tex: id, region: snail.atlas_upload.Region, bytes_per_texel: u32) void {
        const mtl_region = MTLRegion{
            .origin = .{ .x = region.col_base, .y = region.row_base, .z = 0 },
            .size = .{ .width = region.width, .height = region.height, .depth = 1 },
        };
        msg(void, tex, "replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:", .{
            mtl_region,
            @as(NSUInteger, 0),
            @as(NSUInteger, region.layer),
            @as(*const anyopaque, region.src.ptr),
            @as(NSUInteger, region.width * bytes_per_texel),
            @as(NSUInteger, 0),
        });
    }
};

pub fn main() !void {
    const pool_token = objc_autoreleasePoolPush();
    defer objc_autoreleasePoolPop(pool_token);

    const allocator = std.heap.c_allocator;
    var gpu = try Gpu.init();
    defer gpu.deinit();

    var font = try snail.Font.init(assets.dejavu_sans_mono);
    var emoji_font = try snail.Font.init(assets.twemoji_mozilla);
    var faces = try snail.Faces.build(allocator, &.{
        .{ .font = &font, .font_id = 0 },
        .{ .font = &emoji_font, .font_id = 1, .fallback = true },
    });
    defer faces.deinit();
    const font_id = faces.fontIdForFace(0).?;

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
    var atlas = try snail.Atlas.init(allocator, pool);
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

    const device = gpu.device;

    var pipelines = try Pipelines.init(device);
    defer pipelines.deinit();
    try validateRemainingArtifacts(device);

    // Render target: RGBA8 sRGB (encodes on write; shaders emit linear).
    // Private storage + blit to a shared buffer keeps the readback path
    // valid on every Mac (shared render-target textures are Apple-silicon
    // only).
    const target_desc = msg(id, msg(id, class("MTLTextureDescriptor"), "alloc", .{}), "init", .{});
    msg(void, target_desc, "setTextureType:", .{mtl.TextureType2D});
    msg(void, target_desc, "setPixelFormat:", .{mtl.PixelFormatRGBA8Unorm_sRGB});
    msg(void, target_desc, "setWidth:", .{@as(NSUInteger, width)});
    msg(void, target_desc, "setHeight:", .{@as(NSUInteger, height)});
    msg(void, target_desc, "setMipmapLevelCount:", .{@as(NSUInteger, 1)});
    msg(void, target_desc, "setUsage:", .{mtl.TextureUsageRenderTarget});
    msg(void, target_desc, "setStorageMode:", .{mtl.StorageModePrivate});
    const target_tex = msg(id, device, "newTextureWithDescriptor:", .{target_desc});
    release(target_desc);
    if (target_tex == null) return error.TextureFailed;
    defer release(target_tex);

    // s0-analog: the image-paint sampler (linear; the scene's placeholder
    // is never actually sampled but the slot must be bound).
    const sampler_desc = msg(id, msg(id, class("MTLSamplerDescriptor"), "alloc", .{}), "init", .{});
    msg(void, sampler_desc, "setMinFilter:", .{mtl.SamplerMinMagFilterLinear});
    msg(void, sampler_desc, "setMagFilter:", .{mtl.SamplerMinMagFilterLinear});
    msg(void, sampler_desc, "setSAddressMode:", .{mtl.SamplerAddressModeClampToEdge});
    msg(void, sampler_desc, "setTAddressMode:", .{mtl.SamplerAddressModeClampToEdge});
    const linear_sampler = msg(id, device, "newSamplerStateWithDescriptor:", .{sampler_desc});
    release(sampler_desc);
    if (linear_sampler == null) return error.SamplerFailed;
    defer release(linear_sampler);

    // [[buffer(0)]]: the push-constant block. Metal clip space is y-up
    // (the shader flips y), so the projection matches minimal_wgpu/d3d11:
    // `bottom = 0, top = height`.
    const push_constants = PushConstants{
        .mvp = snail.Mat4.ortho(0, width, 0, height, -1, 1).data,
        .viewport = .{ width, height },
        .subpixel_order = 0,
        .output_srgb = 0, // hardware-sRGB render target: emit linear
        .layer_base = 0,
        .coverage_exponent = 1.0,
        .dither_scale = 0.0,
        .mask_output = 0,
    };
    const pc_buffer = msg(id, device, "newBufferWithBytes:length:options:", .{
        @as(*const anyopaque, &push_constants),
        @as(NSUInteger, @sizeOf(PushConstants)),
        mtl.ResourceStorageModeShared,
    });
    if (pc_buffer == null) return error.BufferFailed;
    defer release(pc_buffer);

    // Geometry: the whole emit stream in one instance buffer plus the shared
    // six-index quad; batches select their run via baseInstance.
    const instance_bytes = std.mem.sliceAsBytes(instances[0..instance_len]);
    const instance_buffer = msg(id, device, "newBufferWithBytes:length:options:", .{
        @as(*const anyopaque, instance_bytes.ptr),
        @as(NSUInteger, instance_bytes.len),
        mtl.ResourceStorageModeShared,
    });
    if (instance_buffer == null) return error.BufferFailed;
    defer release(instance_buffer);

    const indices = [6]u32{ 1, 2, 0, 2, 3, 0 };
    const index_buffer = msg(id, device, "newBufferWithBytes:length:options:", .{
        @as(*const anyopaque, &indices),
        @as(NSUInteger, @sizeOf(@TypeOf(indices))),
        mtl.ResourceStorageModeShared,
    });
    if (index_buffer == null) return error.BufferFailed;
    defer release(index_buffer);

    const bytes_per_row: NSUInteger = width * 4;
    const readback_size: NSUInteger = bytes_per_row * height;
    const readback_buffer = msg(id, device, "newBufferWithLength:options:", .{
        readback_size,
        mtl.ResourceStorageModeShared,
    });
    if (readback_buffer == null) return error.BufferFailed;
    defer release(readback_buffer);

    // ── Encode + draw ──

    const command_buffer = msg(id, gpu.queue, "commandBuffer", .{}); // autoreleased
    if (command_buffer == null) return error.CommandBufferFailed;

    const pass_desc = msg(id, class("MTLRenderPassDescriptor"), "renderPassDescriptor", .{}); // autoreleased
    const color_attachment = msg(id, msg(id, pass_desc, "colorAttachments", .{}), "objectAtIndexedSubscript:", .{@as(NSUInteger, 0)});
    msg(void, color_attachment, "setTexture:", .{target_tex});
    msg(void, color_attachment, "setLoadAction:", .{mtl.LoadActionClear});
    msg(void, color_attachment, "setStoreAction:", .{mtl.StoreActionStore});
    // Linear clear color: the sRGB attachment encodes on write, matching
    // the GL example's glClearColor under GL_FRAMEBUFFER_SRGB.
    msg(void, color_attachment, "setClearColor:", .{MTLClearColor{ .red = 0.955, .green = 0.965, .blue = 0.985, .alpha = 1.0 }});

    const encoder = msg(id, command_buffer, "renderCommandEncoderWithDescriptor:", .{pass_desc});
    if (encoder == null) return error.RenderPassFailed;

    // Fixed function defaults already match the other examples: cull none,
    // no depth/stencil, full-target viewport.
    msg(void, encoder, "setVertexBuffer:offset:atIndex:", .{ pc_buffer, @as(NSUInteger, 0), @as(NSUInteger, 0) });
    msg(void, encoder, "setVertexBuffer:offset:atIndex:", .{ instance_buffer, @as(NSUInteger, 0), instance_buffer_index });
    msg(void, encoder, "setFragmentBuffer:offset:atIndex:", .{ pc_buffer, @as(NSUInteger, 0), @as(NSUInteger, 0) });
    const textures = [4]id{ gpu_atlas.curve_tex, gpu_atlas.band_tex, gpu_atlas.layer_tex, gpu_atlas.image_tex };
    for (textures, 0..) |tex, i| {
        // The autohint vertex reads [[texture(2)]]; binding the full set to
        // both stages (like d3d11's VSSetShaderResources) is harmless.
        msg(void, encoder, "setVertexTexture:atIndex:", .{ tex, @as(NSUInteger, i) });
        msg(void, encoder, "setFragmentTexture:atIndex:", .{ tex, @as(NSUInteger, i) });
    }
    msg(void, encoder, "setFragmentSamplerState:atIndex:", .{ linear_sampler, @as(NSUInteger, 0) });

    for (batches[0..batch_len]) |batch| {
        msg(void, encoder, "setRenderPipelineState:", .{pipelines.forKind(batch.kind)});
        msg(void, encoder, "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:", .{
            mtl.PrimitiveTypeTriangle,
            @as(NSUInteger, indices.len),
            mtl.IndexTypeUInt32,
            index_buffer,
            @as(NSUInteger, 0),
            @as(NSUInteger, batch.instance_count),
            @as(NSInteger, 0),
            @as(NSUInteger, batch.first_instance),
        });
    }
    msg(void, encoder, "endEncoding", .{});

    // ── Readback: blit the private render target into the shared buffer ──

    const blit = msg(id, command_buffer, "blitCommandEncoder", .{});
    if (blit == null) return error.BlitFailed;
    msg(void, blit, "copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:", .{
        target_tex,
        @as(NSUInteger, 0),
        @as(NSUInteger, 0),
        MTLOrigin{ .x = 0, .y = 0, .z = 0 },
        MTLSize{ .width = width, .height = height, .depth = 1 },
        readback_buffer,
        @as(NSUInteger, 0),
        bytes_per_row,
        readback_size,
    });
    msg(void, blit, "endEncoding", .{});

    msg(void, command_buffer, "commit", .{});
    msg(void, command_buffer, "waitUntilCompleted", .{});

    const contents = msg(?*anyopaque, readback_buffer, "contents", .{}) orelse return error.MapFailed;
    const pixels: [*]const u8 = @ptrCast(contents);
    try writeTga(pixels[0..readback_size], "zig-out/minimal-metal.tga");
    std.debug.print("wrote zig-out/minimal-metal.tga\n", .{});
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
            .paint = try prepared_fill.paintForDesign(.{ .solid = snail.color.srgbToLinearColor(.{ 0.34, 0.25, 0.72, 0.92 }) }),
        },
        .{
            .key = stroke_key,
            .curves = stroke_curves,
            .paint = try prepared_stroke.paintForDesign(stroke_style.paint),
        },
    });
    return .{
        .{ .key = fill_key, .local_transform = prepared_fill.placedBy(.identity) },
        .{ .key = stroke_key, .local_transform = prepared_stroke.placedBy(.identity) },
    };
}

/// Write the readback (row 0 = top; Metal's texture origin is top-left) as
/// a top-left-origin BGRA TGA, matching the GL/WebGPU/D3D11 examples'
/// writers.
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

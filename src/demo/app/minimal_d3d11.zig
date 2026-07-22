//! Minimal Snail + Direct3D 11 example — the Windows analog of
//! `minimal_wgpu.zig`, rendering the identical scene with the generated
//! D3D11 HLSL artifacts (`snail_shaders`, SM 5.0). Cross-compiled
//! to x86_64-windows-gnu and validated headless under Wine
//! (`zig build run-minimal-d3d11`).
//!
//! This file intentionally imports none of the demo renderer, cache, scene,
//! platform, or support modules. It owns the D3D11 device (no swapchain;
//! WARP fallback when hardware creation fails), the offscreen sRGB render
//! target, the four atlas textures per the binding contract, the upload
//! loop, per-family pipelines (runtime `D3DCompile` via d3dcompiler_47 —
//! Wine provides the real FXC-class compiler), draw submission, readback,
//! and the screenshot writer. Its one frame covers unhinted, autohinted,
//! TT-hinted, and COLR text plus filled and stroked paths.
//!
//! Binding contract (see `snail_shaders`): registers land on the
//! Vulkan binding numbers — b0 = the 96-byte push-constant block as a
//! constant buffer, t0 curve, t1 band, t2 layer-info, t3 image array,
//! s0 image sampler. Vertex-input semantics are `ATTRIB0..8` over the
//! instance stream; entry points keep their Slang names
//! (`vertexMain`/`fragmentMain`). D3D11 clip space is y-up like WebGPU's,
//! so the mvp matches `minimal_wgpu` (`ortho(0, w, 0, h)`; the shader
//! flips y) and the readback rows arrive top-first.

const std = @import("std");
const snail = @import("snail");
const assets = @import("assets");

const c = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "1");
    @cInclude("d3d11.h");
    @cInclude("d3dcompiler.h");
    @cInclude("stdio.h");
    @cInclude("direct.h");
});

const width = 960;
const height = 420;
const text = "Hello, world!";
const ppem: u32 = 34 * 64;

const slang_gen = @import("snail_shaders");

/// The parameter block as a D3D11 constant buffer — the machine-derived
/// layout from slangc reflection (the cbuffer packing matches the C
/// struct's offsets; the size is a legal multiple of 16).
const PushConstants = slang_gen.reflection.PushConstants;

fn check(hr: c.HRESULT, what: []const u8) !void {
    if (hr < 0) {
        std.debug.print("{s} failed: hr=0x{x:0>8}\n", .{ what, @as(u32, @bitCast(hr)) });
        return error.D3d11CallFailed;
    }
}

fn release(obj: anytype) void {
    if (obj) |o| _ = o.*.lpVtbl.*.Release.?(@ptrCast(o));
}

// ── Device ──

const Gpu = struct {
    device: *c.ID3D11Device,
    context: *c.ID3D11DeviceContext,

    fn init() !Gpu {
        var device: ?*c.ID3D11Device = null;
        var context: ?*c.ID3D11DeviceContext = null;
        var level: c.D3D_FEATURE_LEVEL = 0;
        const levels = [_]c.D3D_FEATURE_LEVEL{c.D3D_FEATURE_LEVEL_11_0};
        // Headless: no swapchain. Hardware first, WARP as the software
        // fallback (useful under Wine when the host GL/Vulkan path fails).
        var hr = c.D3D11CreateDevice(null, c.D3D_DRIVER_TYPE_HARDWARE, null, 0, &levels, levels.len, c.D3D11_SDK_VERSION, &device, &level, &context);
        if (hr < 0) {
            hr = c.D3D11CreateDevice(null, c.D3D_DRIVER_TYPE_WARP, null, 0, &levels, levels.len, c.D3D11_SDK_VERSION, &device, &level, &context);
        }
        try check(hr, "D3D11CreateDevice");
        return .{ .device = device.?, .context = context.? };
    }

    fn deinit(self: *Gpu) void {
        release(@as(?*c.ID3D11DeviceContext, self.context));
        release(@as(?*c.ID3D11Device, self.device));
    }
};

// ── Shaders / pipelines ──

/// Runtime-compile one HLSL artifact with d3dcompiler_47 (under Wine the
/// built-in FXC-class compiler) and return the bytecode blob.
fn compileHlsl(source: [:0]const u8, entry: [:0]const u8, target: [:0]const u8, label: []const u8) !*c.ID3DBlob {
    var blob: ?*c.ID3DBlob = null;
    var errors: ?*c.ID3DBlob = null;
    const hr = c.D3DCompile(source.ptr, source.len, null, null, null, entry.ptr, target.ptr, c.D3DCOMPILE_ENABLE_STRICTNESS, 0, &blob, &errors);
    if (errors) |e| {
        const ptr: [*]const u8 = @ptrCast(e.*.lpVtbl.*.GetBufferPointer.?(e).?);
        const len = e.*.lpVtbl.*.GetBufferSize.?(e);
        if (hr < 0) std.debug.print("D3DCompile({s}) messages:\n{s}\n", .{ label, ptr[0..len] });
        release(errors);
    }
    if (hr < 0) {
        std.debug.print("D3DCompile({s}) failed: hr=0x{x:0>8}\n", .{ label, @as(u32, @bitCast(hr)) });
        return error.ShaderCompileFailed;
    }
    return blob.?;
}

fn blobBytes(blob: *c.ID3DBlob) []const u8 {
    const ptr: [*]const u8 = @ptrCast(blob.*.lpVtbl.*.GetBufferPointer.?(blob).?);
    return ptr[0..blob.*.lpVtbl.*.GetBufferSize.?(blob)];
}

/// The nine per-instance input-layout elements mirroring the Vulkan
/// contract's attributes at locations 0–8; the generated HLSL names them
/// ATTRIB0..8. Layouts built from this table also serve vertex shaders
/// consuming a prefix of it (text reads ATTRIB0..6) — extra elements are
/// legal in D3D11.
fn inputElements() [9]c.D3D11_INPUT_ELEMENT_DESC {
    const Instance = snail.render.records.Instance;
    const step = c.D3D11_INPUT_PER_INSTANCE_DATA;
    return .{
        .{ .SemanticName = "ATTRIB", .SemanticIndex = 0, .Format = c.DXGI_FORMAT_R16G16B16A16_FLOAT, .InputSlot = 0, .AlignedByteOffset = @offsetOf(Instance, "rect"), .InputSlotClass = step, .InstanceDataStepRate = 1 },
        .{ .SemanticName = "ATTRIB", .SemanticIndex = 1, .Format = c.DXGI_FORMAT_R32G32B32A32_FLOAT, .InputSlot = 0, .AlignedByteOffset = @offsetOf(Instance, "xform"), .InputSlotClass = step, .InstanceDataStepRate = 1 },
        .{ .SemanticName = "ATTRIB", .SemanticIndex = 2, .Format = c.DXGI_FORMAT_R32G32_FLOAT, .InputSlot = 0, .AlignedByteOffset = @offsetOf(Instance, "origin"), .InputSlotClass = step, .InstanceDataStepRate = 1 },
        .{ .SemanticName = "ATTRIB", .SemanticIndex = 3, .Format = c.DXGI_FORMAT_R32G32_UINT, .InputSlot = 0, .AlignedByteOffset = @offsetOf(Instance, "glyph"), .InputSlotClass = step, .InstanceDataStepRate = 1 },
        .{ .SemanticName = "ATTRIB", .SemanticIndex = 4, .Format = c.DXGI_FORMAT_R32G32B32A32_FLOAT, .InputSlot = 0, .AlignedByteOffset = @offsetOf(Instance, "band"), .InputSlotClass = step, .InstanceDataStepRate = 1 },
        .{ .SemanticName = "ATTRIB", .SemanticIndex = 5, .Format = c.DXGI_FORMAT_R8G8B8A8_UNORM, .InputSlot = 0, .AlignedByteOffset = @offsetOf(Instance, "color"), .InputSlotClass = step, .InstanceDataStepRate = 1 },
        .{ .SemanticName = "ATTRIB", .SemanticIndex = 6, .Format = c.DXGI_FORMAT_R8G8B8A8_UNORM, .InputSlot = 0, .AlignedByteOffset = @offsetOf(Instance, "tint"), .InputSlotClass = step, .InstanceDataStepRate = 1 },
        .{ .SemanticName = "ATTRIB", .SemanticIndex = 7, .Format = c.DXGI_FORMAT_R32G32B32A32_UINT, .InputSlot = 0, .AlignedByteOffset = @offsetOf(Instance, "policy"), .InputSlotClass = step, .InstanceDataStepRate = 1 },
        .{ .SemanticName = "ATTRIB", .SemanticIndex = 8, .Format = c.DXGI_FORMAT_R32G32B32_UINT, .InputSlot = 0, .AlignedByteOffset = @offsetOf(Instance, "policy") + 16, .InputSlotClass = step, .InstanceDataStepRate = 1 },
    };
}

const Pipeline = struct {
    layout: *c.ID3D11InputLayout,
    vs: *c.ID3D11VertexShader,
    ps: *c.ID3D11PixelShader,
};

const Pipelines = struct {
    text_layout: ?*c.ID3D11InputLayout = null,
    autohint_layout: ?*c.ID3D11InputLayout = null,
    text_vs: ?*c.ID3D11VertexShader = null,
    autohint_vs: ?*c.ID3D11VertexShader = null,
    regular_ps: ?*c.ID3D11PixelShader = null,
    autohint_ps: ?*c.ID3D11PixelShader = null,
    tt_ps: ?*c.ID3D11PixelShader = null,
    path_ps: ?*c.ID3D11PixelShader = null,
    colr_ps: ?*c.ID3D11PixelShader = null,

    fn init(device: *c.ID3D11Device) !Pipelines {
        var self = Pipelines{};
        errdefer self.deinit();

        // Entry points keep their Slang names; fragment-only families pair
        // with the text vertex artifact.
        const text_vert_blob = try compileHlsl(slang_gen.textHlsl(.vertex), slang_gen.hlsl_vertex_entry, "vs_5_0", "text.vert");
        defer release(@as(?*c.ID3DBlob, text_vert_blob));
        const autohint_vert_blob = try compileHlsl(slang_gen.autohintHlsl(.vertex), slang_gen.hlsl_vertex_entry, "vs_5_0", "autohint.vert");
        defer release(@as(?*c.ID3DBlob, autohint_vert_blob));

        self.text_vs = try createVs(device, text_vert_blob);
        self.autohint_vs = try createVs(device, autohint_vert_blob);
        self.text_layout = try createLayout(device, text_vert_blob);
        self.autohint_layout = try createLayout(device, autohint_vert_blob);
        self.regular_ps = try createPs(device, slang_gen.textHlsl(.fragment), "text.frag");
        self.autohint_ps = try createPs(device, slang_gen.autohintHlsl(.fragment), "autohint.frag");
        self.tt_ps = try createPs(device, slang_gen.ttHintedFragHlsl(), "tt_hinted_text.frag");
        self.path_ps = try createPs(device, slang_gen.pathFragHlsl(), "path.frag");
        self.colr_ps = try createPs(device, slang_gen.colrFragHlsl(), "colr.frag");
        return self;
    }

    fn deinit(self: *Pipelines) void {
        release(self.text_layout);
        release(self.autohint_layout);
        release(self.text_vs);
        release(self.autohint_vs);
        release(self.regular_ps);
        release(self.autohint_ps);
        release(self.tt_ps);
        release(self.path_ps);
        release(self.colr_ps);
    }

    fn createVs(device: *c.ID3D11Device, blob: *c.ID3DBlob) !*c.ID3D11VertexShader {
        const bytes = blobBytes(blob);
        var vs: ?*c.ID3D11VertexShader = null;
        try check(device.*.lpVtbl.*.CreateVertexShader.?(device, bytes.ptr, bytes.len, null, &vs), "CreateVertexShader");
        return vs.?;
    }

    fn createPs(device: *c.ID3D11Device, source: [:0]const u8, label: []const u8) !*c.ID3D11PixelShader {
        const blob = try compileHlsl(source, slang_gen.hlsl_fragment_entry, "ps_5_0", label);
        defer release(@as(?*c.ID3DBlob, blob));
        const bytes = blobBytes(blob);
        var ps: ?*c.ID3D11PixelShader = null;
        try check(device.*.lpVtbl.*.CreatePixelShader.?(device, bytes.ptr, bytes.len, null, &ps), "CreatePixelShader");
        return ps.?;
    }

    fn createLayout(device: *c.ID3D11Device, vs_blob: *c.ID3DBlob) !*c.ID3D11InputLayout {
        var elements = inputElements();
        const bytes = blobBytes(vs_blob);
        var layout: ?*c.ID3D11InputLayout = null;
        try check(device.*.lpVtbl.*.CreateInputLayout.?(device, &elements, elements.len, bytes.ptr, bytes.len, &layout), "CreateInputLayout");
        return layout.?;
    }

    fn forKind(self: *const Pipelines, kind: snail.render.records.ShapeKind) Pipeline {
        return switch (kind) {
            .regular => .{ .layout = self.text_layout.?, .vs = self.text_vs.?, .ps = self.regular_ps.? },
            .autohint => .{ .layout = self.autohint_layout.?, .vs = self.autohint_vs.?, .ps = self.autohint_ps.? },
            .tt_hinted_text => .{ .layout = self.text_layout.?, .vs = self.text_vs.?, .ps = self.tt_ps.? },
            .path => .{ .layout = self.text_layout.?, .vs = self.text_vs.?, .ps = self.path_ps.? },
            .colr => .{ .layout = self.text_layout.?, .vs = self.text_vs.?, .ps = self.colr_ps.? },
        };
    }
};

/// Compile-check the two generated HLSL artifacts the scene does not draw
/// (LCD subpixel and the text_sample material module) so a
/// `run-minimal-d3d11` pass also validates them against the real
/// d3dcompiler_47.
fn validateRemainingArtifacts() !void {
    const subpixel = try compileHlsl(slang_gen.subpixelFragHlsl(), slang_gen.hlsl_fragment_entry, "ps_5_0", "text_subpixel.frag");
    release(@as(?*c.ID3DBlob, subpixel));
    const sample = try compileHlsl(slang_gen.textSampleFragHlsl(), slang_gen.hlsl_fragment_entry, "ps_5_0", "text_sample.frag");
    release(@as(?*c.ID3DBlob, sample));
}

// ── Atlas residency ──

/// The complete caller-owned GPU side of a Snail atlas: D3D11 textures fed
/// by the planner's regions through `UpdateSubresource`.
const GpuAtlas = struct {
    gpu: *const Gpu,
    pool: *snail.PagePool,
    curve_tex: ?*c.ID3D11Texture2D = null,
    band_tex: ?*c.ID3D11Texture2D = null,
    layer_tex: ?*c.ID3D11Texture2D = null,
    image_tex: ?*c.ID3D11Texture2D = null, // 1×1 placeholder: the scene packs no image paints
    curve_srv: ?*c.ID3D11ShaderResourceView = null,
    band_srv: ?*c.ID3D11ShaderResourceView = null,
    layer_srv: ?*c.ID3D11ShaderResourceView = null,
    image_srv: ?*c.ID3D11ShaderResourceView = null,
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
        release(self.curve_srv);
        release(self.band_srv);
        release(self.layer_srv);
        release(self.image_srv);
        release(self.curve_tex);
        release(self.band_tex);
        release(self.layer_tex);
        release(self.image_tex);
        self.uploads.deinit();
        self.* = undefined;
    }

    fn createTextures(self: *GpuAtlas) !void {
        const device = self.gpu.device;
        const curve_height = self.pool.options.curve_words_per_page / (snail.atlas_upload.CURVE_TEX_WIDTH * 4);
        const band_height = self.pool.options.band_words_per_page / (snail.atlas_upload.BAND_TEX_WIDTH * 2);
        const layers: u32 = @intCast(self.pool.options.max_layers);

        self.curve_tex = try createTexture(device, c.DXGI_FORMAT_R16G16B16A16_FLOAT, snail.atlas_upload.CURVE_TEX_WIDTH, @intCast(curve_height), layers);
        self.band_tex = try createTexture(device, c.DXGI_FORMAT_R16G16_UINT, snail.atlas_upload.BAND_TEX_WIDTH, @intCast(band_height), layers);
        self.layer_tex = try createTexture(device, c.DXGI_FORMAT_R32G32B32A32_FLOAT, snail.atlas_upload.INFO_WIDTH, options.layer_info_height, 1);
        self.image_tex = try createTexture(device, c.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB, 1, 1, 1);

        // Null-desc views inherit dimension/format from the resource; the
        // image placeholder needs an explicit Texture2DArray view (its one
        // slice would otherwise view as Texture2D, mismatching the HLSL
        // `Texture2DArray` at t3).
        self.curve_srv = try createSrv(device, self.curve_tex.?, null);
        self.band_srv = try createSrv(device, self.band_tex.?, null);
        self.layer_srv = try createSrv(device, self.layer_tex.?, null);
        var image_desc = std.mem.zeroes(c.D3D11_SHADER_RESOURCE_VIEW_DESC);
        image_desc.Format = c.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB;
        image_desc.ViewDimension = c.D3D11_SRV_DIMENSION_TEXTURE2DARRAY;
        image_desc.unnamed_0.Texture2DArray = .{ .MostDetailedMip = 0, .MipLevels = 1, .FirstArraySlice = 0, .ArraySize = 1 };
        self.image_srv = try createSrv(device, self.image_tex.?, &image_desc);
    }

    fn createTexture(device: *c.ID3D11Device, format: c.DXGI_FORMAT, w: u32, h: u32, layers: u32) !*c.ID3D11Texture2D {
        const desc = c.D3D11_TEXTURE2D_DESC{
            .Width = w,
            .Height = h,
            .MipLevels = 1,
            .ArraySize = layers,
            .Format = format,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Usage = c.D3D11_USAGE_DEFAULT,
            .BindFlags = c.D3D11_BIND_SHADER_RESOURCE,
            .CPUAccessFlags = 0,
            .MiscFlags = 0,
        };
        var tex: ?*c.ID3D11Texture2D = null;
        try check(device.*.lpVtbl.*.CreateTexture2D.?(device, &desc, null, &tex), "CreateTexture2D");
        return tex.?;
    }

    fn createSrv(device: *c.ID3D11Device, tex: *c.ID3D11Texture2D, desc: ?*const c.D3D11_SHADER_RESOURCE_VIEW_DESC) !*c.ID3D11ShaderResourceView {
        var srv: ?*c.ID3D11ShaderResourceView = null;
        try check(device.*.lpVtbl.*.CreateShaderResourceView.?(device, @ptrCast(tex), desc, &srv), "CreateShaderResourceView");
        return srv.?;
    }

    /// Upload after every `Atlas.extend` — identical planner protocol to the
    /// GL/WebGPU examples: keep the binding on `planDelta`, replan larger on
    /// growth.
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
            .curve => self.write(self.curve_tex.?, region, 8),
            .band => self.write(self.band_tex.?, region, 4),
            .layer_info => self.write(self.layer_tex.?, region, 16),
            .image => unreachable,
        }
    }

    fn write(self: *GpuAtlas, tex: *c.ID3D11Texture2D, region: snail.atlas_upload.Region, bytes_per_texel: u32) void {
        const ctx = self.gpu.context;
        const box = c.D3D11_BOX{
            .left = region.col_base,
            .top = region.row_base,
            .front = 0,
            .right = region.col_base + region.width,
            .bottom = region.row_base + region.height,
            .back = 1,
        };
        // Subresource index = mip 0 of array slice `layer` (1 mip level).
        ctx.*.lpVtbl.*.UpdateSubresource.?(ctx, @ptrCast(tex), region.layer, &box, region.src.ptr, region.width * bytes_per_texel, 0);
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

    const device = gpu.device;
    const ctx = gpu.context;

    var pipelines = try Pipelines.init(device);
    defer pipelines.deinit();
    try validateRemainingArtifacts();

    // Render target: RGBA8 sRGB (encodes on write; shaders emit linear).
    const target_desc = c.D3D11_TEXTURE2D_DESC{
        .Width = width,
        .Height = height,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = c.DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Usage = c.D3D11_USAGE_DEFAULT,
        .BindFlags = c.D3D11_BIND_RENDER_TARGET,
        .CPUAccessFlags = 0,
        .MiscFlags = 0,
    };
    var target_tex: ?*c.ID3D11Texture2D = null;
    try check(device.*.lpVtbl.*.CreateTexture2D.?(device, &target_desc, null, &target_tex), "create render target");
    defer release(target_tex);
    var rtv: ?*c.ID3D11RenderTargetView = null;
    try check(device.*.lpVtbl.*.CreateRenderTargetView.?(device, @ptrCast(target_tex), null, &rtv), "CreateRenderTargetView");
    defer release(rtv);

    // Fixed-function state: premultiplied-over blend (matching the Vulkan
    // contract's blendAttachment), no cull, no depth.
    var blend_desc = std.mem.zeroes(c.D3D11_BLEND_DESC);
    blend_desc.RenderTarget[0] = .{
        .BlendEnable = c.TRUE,
        .SrcBlend = c.D3D11_BLEND_ONE,
        .DestBlend = c.D3D11_BLEND_INV_SRC_ALPHA,
        .BlendOp = c.D3D11_BLEND_OP_ADD,
        .SrcBlendAlpha = c.D3D11_BLEND_ONE,
        .DestBlendAlpha = c.D3D11_BLEND_INV_SRC_ALPHA,
        .BlendOpAlpha = c.D3D11_BLEND_OP_ADD,
        .RenderTargetWriteMask = c.D3D11_COLOR_WRITE_ENABLE_ALL,
    };
    var blend_state: ?*c.ID3D11BlendState = null;
    try check(device.*.lpVtbl.*.CreateBlendState.?(device, &blend_desc, &blend_state), "CreateBlendState");
    defer release(blend_state);

    var raster_desc = std.mem.zeroes(c.D3D11_RASTERIZER_DESC);
    raster_desc.FillMode = c.D3D11_FILL_SOLID;
    raster_desc.CullMode = c.D3D11_CULL_NONE;
    raster_desc.DepthClipEnable = c.TRUE;
    var raster_state: ?*c.ID3D11RasterizerState = null;
    try check(device.*.lpVtbl.*.CreateRasterizerState.?(device, &raster_desc, &raster_state), "CreateRasterizerState");
    defer release(raster_state);

    var depth_desc = std.mem.zeroes(c.D3D11_DEPTH_STENCIL_DESC);
    depth_desc.DepthEnable = c.FALSE;
    var depth_state: ?*c.ID3D11DepthStencilState = null;
    try check(device.*.lpVtbl.*.CreateDepthStencilState.?(device, &depth_desc, &depth_state), "CreateDepthStencilState");
    defer release(depth_state);

    // s0: the image-paint sampler (linear; the scene's placeholder is never
    // actually sampled but the register must be bound).
    var sampler_desc = std.mem.zeroes(c.D3D11_SAMPLER_DESC);
    sampler_desc.Filter = c.D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    sampler_desc.AddressU = c.D3D11_TEXTURE_ADDRESS_CLAMP;
    sampler_desc.AddressV = c.D3D11_TEXTURE_ADDRESS_CLAMP;
    sampler_desc.AddressW = c.D3D11_TEXTURE_ADDRESS_CLAMP;
    sampler_desc.MaxLOD = 32.0;
    var linear_sampler: ?*c.ID3D11SamplerState = null;
    try check(device.*.lpVtbl.*.CreateSamplerState.?(device, &sampler_desc, &linear_sampler), "CreateSamplerState");
    defer release(linear_sampler);

    // b0: the push-constant block. D3D11 clip space is y-up like WebGPU's
    // (the shader flips y), so the projection matches minimal_wgpu:
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
    const cbuffer_desc = c.D3D11_BUFFER_DESC{
        .ByteWidth = @sizeOf(PushConstants),
        .Usage = c.D3D11_USAGE_IMMUTABLE,
        .BindFlags = c.D3D11_BIND_CONSTANT_BUFFER,
        .CPUAccessFlags = 0,
        .MiscFlags = 0,
        .StructureByteStride = 0,
    };
    const cbuffer_init = c.D3D11_SUBRESOURCE_DATA{ .pSysMem = &push_constants, .SysMemPitch = 0, .SysMemSlicePitch = 0 };
    var cbuffer: ?*c.ID3D11Buffer = null;
    try check(device.*.lpVtbl.*.CreateBuffer.?(device, &cbuffer_desc, &cbuffer_init, &cbuffer), "create constant buffer");
    defer release(cbuffer);

    // Geometry: the whole emit stream in one instance buffer plus the shared
    // six-index quad; batches select their run via StartInstanceLocation.
    const instance_bytes = std.mem.sliceAsBytes(instances[0..instance_len]);
    const instance_desc = c.D3D11_BUFFER_DESC{
        .ByteWidth = @intCast(instance_bytes.len),
        .Usage = c.D3D11_USAGE_IMMUTABLE,
        .BindFlags = c.D3D11_BIND_VERTEX_BUFFER,
        .CPUAccessFlags = 0,
        .MiscFlags = 0,
        .StructureByteStride = 0,
    };
    const instance_init = c.D3D11_SUBRESOURCE_DATA{ .pSysMem = instance_bytes.ptr, .SysMemPitch = 0, .SysMemSlicePitch = 0 };
    var instance_buffer: ?*c.ID3D11Buffer = null;
    try check(device.*.lpVtbl.*.CreateBuffer.?(device, &instance_desc, &instance_init, &instance_buffer), "create instance buffer");
    defer release(instance_buffer);

    const indices = [6]u32{ 1, 2, 0, 2, 3, 0 };
    const index_desc = c.D3D11_BUFFER_DESC{
        .ByteWidth = @sizeOf(@TypeOf(indices)),
        .Usage = c.D3D11_USAGE_IMMUTABLE,
        .BindFlags = c.D3D11_BIND_INDEX_BUFFER,
        .CPUAccessFlags = 0,
        .MiscFlags = 0,
        .StructureByteStride = 0,
    };
    const index_init = c.D3D11_SUBRESOURCE_DATA{ .pSysMem = &indices, .SysMemPitch = 0, .SysMemSlicePitch = 0 };
    var index_buffer: ?*c.ID3D11Buffer = null;
    try check(device.*.lpVtbl.*.CreateBuffer.?(device, &index_desc, &index_init, &index_buffer), "create index buffer");
    defer release(index_buffer);

    // ── Draw ──

    var rtvs = [1]?*c.ID3D11RenderTargetView{rtv};
    ctx.*.lpVtbl.*.OMSetRenderTargets.?(ctx, 1, &rtvs, null);
    const viewport = c.D3D11_VIEWPORT{ .TopLeftX = 0, .TopLeftY = 0, .Width = width, .Height = height, .MinDepth = 0, .MaxDepth = 1 };
    ctx.*.lpVtbl.*.RSSetViewports.?(ctx, 1, &viewport);
    ctx.*.lpVtbl.*.RSSetState.?(ctx, raster_state);
    ctx.*.lpVtbl.*.OMSetBlendState.?(ctx, blend_state, null, 0xffff_ffff);
    ctx.*.lpVtbl.*.OMSetDepthStencilState.?(ctx, depth_state, 0);

    // Linear clear color: the sRGB target encodes on write, matching the GL
    // example's glClearColor under GL_FRAMEBUFFER_SRGB.
    const clear = [4]f32{ 0.955, 0.965, 0.985, 1.0 };
    ctx.*.lpVtbl.*.ClearRenderTargetView.?(ctx, rtv, &clear);

    var srvs = [4]?*c.ID3D11ShaderResourceView{ gpu_atlas.curve_srv, gpu_atlas.band_srv, gpu_atlas.layer_srv, gpu_atlas.image_srv };
    ctx.*.lpVtbl.*.VSSetShaderResources.?(ctx, 0, srvs.len, &srvs);
    ctx.*.lpVtbl.*.PSSetShaderResources.?(ctx, 0, srvs.len, &srvs);
    var cbuffers = [1]?*c.ID3D11Buffer{cbuffer};
    ctx.*.lpVtbl.*.VSSetConstantBuffers.?(ctx, 0, 1, &cbuffers);
    ctx.*.lpVtbl.*.PSSetConstantBuffers.?(ctx, 0, 1, &cbuffers);
    var samplers = [1]?*c.ID3D11SamplerState{linear_sampler};
    ctx.*.lpVtbl.*.PSSetSamplers.?(ctx, 0, 1, &samplers);

    ctx.*.lpVtbl.*.IASetPrimitiveTopology.?(ctx, c.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ctx.*.lpVtbl.*.IASetIndexBuffer.?(ctx, index_buffer, c.DXGI_FORMAT_R32_UINT, 0);
    var vbs = [1]?*c.ID3D11Buffer{instance_buffer};
    var strides = [1]c.UINT{snail.render.records.BYTES_PER_INSTANCE};
    var offsets = [1]c.UINT{0};
    ctx.*.lpVtbl.*.IASetVertexBuffers.?(ctx, 0, 1, &vbs, &strides, &offsets);

    for (batches[0..batch_len]) |batch| {
        const pipeline = pipelines.forKind(batch.kind);
        ctx.*.lpVtbl.*.IASetInputLayout.?(ctx, pipeline.layout);
        ctx.*.lpVtbl.*.VSSetShader.?(ctx, pipeline.vs, null, 0);
        ctx.*.lpVtbl.*.PSSetShader.?(ctx, pipeline.ps, null, 0);
        ctx.*.lpVtbl.*.DrawIndexedInstanced.?(ctx, indices.len, batch.instance_count, 0, 0, batch.first_instance);
    }

    // ── Readback ──

    var staging_desc = target_desc;
    staging_desc.Usage = c.D3D11_USAGE_STAGING;
    staging_desc.BindFlags = 0;
    staging_desc.CPUAccessFlags = c.D3D11_CPU_ACCESS_READ;
    var staging_tex: ?*c.ID3D11Texture2D = null;
    try check(device.*.lpVtbl.*.CreateTexture2D.?(device, &staging_desc, null, &staging_tex), "create staging texture");
    defer release(staging_tex);
    ctx.*.lpVtbl.*.CopyResource.?(ctx, @ptrCast(staging_tex), @ptrCast(target_tex));

    var mapped = std.mem.zeroes(c.D3D11_MAPPED_SUBRESOURCE);
    try check(ctx.*.lpVtbl.*.Map.?(ctx, @ptrCast(staging_tex), 0, c.D3D11_MAP_READ, 0, &mapped), "map staging texture");
    const base: [*]const u8 = @ptrCast(mapped.pData.?);
    try writeTga(base, mapped.RowPitch, "zig-out/minimal-d3d11.tga");
    ctx.*.lpVtbl.*.Unmap.?(ctx, @ptrCast(staging_tex), 0);
    std.debug.print("wrote zig-out/minimal-d3d11.tga\n", .{});
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

/// Write the mapped readback (row 0 = top, `row_pitch` bytes apart) as a
/// top-left-origin BGRA TGA, matching the GL/WebGPU examples' writer.
fn writeTga(pixels: [*]const u8, row_pitch: u32, path: [:0]const u8) !void {
    _ = c._mkdir("zig-out");
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
        const source = pixels[y * row_pitch ..][0 .. width * 4];
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

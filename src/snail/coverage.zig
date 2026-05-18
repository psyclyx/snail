const std = @import("std");
const build_options = @import("build_options");
const backend_kind_mod = @import("backend_kind.zig");
const resource_key_mod = @import("resource_key.zig");
const prepared_mod = @import("resources/prepared.zig");
const scene_mod = @import("scene.zig");
const target_mod = @import("target.zig");
const text_mod = @import("text.zig");
const texture_layers = @import("render/format/texture_layers.zig");
const vec = @import("math/vec.zig");
const pipeline = if (build_options.enable_opengl) @import("render/backend/gl/state.zig") else struct {
    pub const TextCoverageProgram = struct {};
    pub const TextCoverageDrawState = struct {};
    pub const GlTextState = void;
    pub const PreparedResources = void;
    pub const text_vertex_interface = "";
    pub const text_coverage_fragment_interface = "";
    pub const text_coverage_fragment_body = "";
    pub const text_sample_interface = "";
    pub const text_sample_body = "";
};
const vulkan_pipeline = if (build_options.enable_vulkan) @import("render/backend/vulkan/pipeline.zig") else struct {
    pub const TextCoverageProgram = struct {};
    pub const PreparedResources = void;
    pub const VulkanPipeline = void;
};

const BackendKind = backend_kind_mod.BackendKind;
const Transform2D = vec.Transform2D;
const CoverageTransfer = target_mod.CoverageTransfer;
const FillRule = target_mod.FillRule;
const RenderDrawState = target_mod.DrawState;
const SubpixelOrder = target_mod.SubpixelOrder;
const TextBlob = text_mod.TextBlob;
const ResourceStamp = resource_key_mod.ResourceStamp;
const PreparedResources = prepared_mod.PreparedResources;
const Override = scene_mod.Override;
const TextDraw = scene_mod.TextDraw;
const TextResourceKeys = scene_mod.TextResourceKeys;
const TextBatch = text_mod.TextBatch;

const TEXT_WORDS_PER_GLYPH = text_mod.TEXT_WORDS_PER_GLYPH;

pub const GlProgram = if (build_options.enable_opengl) pipeline.TextCoverageProgram else struct {};
pub const VulkanProgram = if (build_options.enable_vulkan) vulkan_pipeline.TextCoverageProgram else struct {};

pub const Program = union(BackendKind) {
    gl: GlProgram,
    vulkan: VulkanProgram,
    cpu: void,
};

/// GLSL 330 pieces for material shaders that consume Snail text coverage.
///
/// Include `snail.coverage.Shader.gl.vertex_interface` in a vertex shader that draws
/// prepared text coverage geometry, and `snail.coverage.Shader.gl.fragment_interface`
/// plus `snail.coverage.Shader.gl.fragment_body` in the fragment shader. The fragment body exposes
/// `snail_text_coverage()`, `snail_text_color_srgb()`, and
/// `snail_text_color_linear()` for use as material inputs. Material shaders
/// that evaluate coverage without Snail's text varyings can instead include
/// `snail.coverage.Shader.gl.resource_interface` and `snail.coverage.Shader.gl.coverage_functions`.
/// Shaders that need random access to `TextCoverageRecords` can also include
/// `sample_interface` and `sample_functions`, upload `records.slice()` as a
/// `GL_R32UI` texture buffer, set `u_layer_base` to
/// `records.layerWindowBase()`, and call `snail_text_sample_premul_linear(scene_pos)`.
pub const Shader = struct {
    pub const gl = struct {
        pub const vertex_interface = pipeline.text_vertex_interface;
        pub const fragment_interface = pipeline.text_coverage_fragment_interface;
        pub const resource_interface =
            \\uniform sampler2DArray u_curve_tex;
            \\uniform usampler2DArray u_band_tex;
            \\uniform int u_fill_rule;
            \\uniform int u_layer_base;
            \\
            \\#define SNAIL_FILL_RULE u_fill_rule
            \\
        ;
        pub const coverage_functions = pipeline.text_coverage_fragment_body;
        pub const sample_interface = pipeline.text_sample_interface;
        pub const sample_functions = if (build_options.enable_opengl)
            std.fmt.comptimePrint(
                "#define SNAIL_TEXT_RECORD_WORDS_PER_GLYPH {d}\n",
                .{TEXT_WORDS_PER_GLYPH},
            ) ++ pipeline.text_sample_body
        else
            "";
        pub const fragment_body =
            coverage_functions ++
            "\n" ++
            \\float snail_text_coverage() {
            \\    int layer_byte = (v_glyph.w >> 8) & 0xFF;
            \\    if (layer_byte == SNAIL_SPECIAL_LAYER_SENTINEL) return 0.0;
            \\    int atlas_layer = u_layer_base + layer_byte;
            \\    vec2 rc = v_texcoord;
            \\    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
            \\    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
            \\    vec2 ppe = vec2(1.0 / max(length(dx), 1.0 / 65536.0), 1.0 / max(length(dy), 1.0 / 65536.0));
            \\    return evalGlyphCoverage(rc, ppe, v_glyph.xy,
            \\                             ivec2(v_glyph.w & 0xFF, v_glyph.z),
            \\                             v_banding, atlas_layer);
            \\}
            \\
            \\vec4 snail_text_color_srgb() {
            \\    return v_color;
            \\}
            \\
            \\vec4 snail_text_color_linear() {
            \\    return vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
            \\}
            \\
            ;
    };

    pub const vulkan = struct {
        pub const vertex_shader = @embedFile("render/backend/vulkan_glsl/snail.vert");
        pub const text_fragment_shader = @embedFile("render/backend/vulkan_glsl/snail_text.frag");
        pub const coverage_functions =
            @embedFile("render/backend/glsl/snail_render_abi.glsl") ++
            "\n" ++
            @embedFile("render/backend/glsl/snail_coverage_common.glsl") ++
            "\n" ++
            @embedFile("render/backend/glsl/snail_color_common.glsl") ++
            "\n" ++
            @embedFile("render/backend/glsl/snail_text_frag_body.glsl");
        pub const descriptor_set_index: u32 = 0;
        pub const curve_texture_binding: u32 = 0;
        pub const band_texture_binding: u32 = 1;
    };
};

pub const DrawState = struct {
    fill_rule: FillRule = .non_zero,
    subpixel_order: SubpixelOrder = .none,
    output_srgb: bool = false,
    coverage_transfer: CoverageTransfer = .identity,
    layer_base: u32 = 0,
};

pub fn drawStateFor(records: *const TextCoverageRecords, state: RenderDrawState) DrawState {
    return .{
        .fill_rule = state.raster.fill_rule,
        .subpixel_order = state.raster.subpixel_order,
        .output_srgb = state.surface.encoding.shaderEncodesSrgb(),
        .coverage_transfer = state.raster.coverage_transfer,
        .layer_base = records.layerWindowBase(),
    };
}

/// Resolve options used when preparing text coverage geometry for a custom
/// material shader.
pub const TextCoverageOptions = struct {
    resources: TextResourceKeys,
    transform: Transform2D = .identity,
};

/// Prepared glyph coverage records for use by a custom material shader.
///
/// Wraps caller-owned per-glyph draw data. Snail atlas textures come from
/// PreparedResources. Use `wordCapacityForBlob` to size `buffer`.
pub const TextCoverageRecords = struct {
    buffer: []u32,
    len: usize = 0,
    resources: ?TextResourceKeys = null,
    atlas_stamp: ResourceStamp = .{},
    paint_stamp: ResourceStamp = .{},
    layer_window_base: u32 = 0,

    pub fn wordCapacityForBlob(blob: *const TextBlob) usize {
        return blob.gpu_instance_budget * TEXT_WORDS_PER_GLYPH;
    }

    pub fn init(buffer: []u32) TextCoverageRecords {
        return .{ .buffer = buffer };
    }

    pub fn reset(self: *TextCoverageRecords) void {
        self.len = 0;
        self.resources = null;
        self.atlas_stamp = .{};
        self.paint_stamp = .{};
        self.layer_window_base = 0;
    }

    pub fn glyphCount(self: *const TextCoverageRecords) usize {
        return self.len / TEXT_WORDS_PER_GLYPH;
    }

    pub fn slice(self: *const TextCoverageRecords) []const u32 {
        return self.buffer[0..self.len];
    }

    pub fn layerWindowBase(self: *const TextCoverageRecords) u32 {
        return self.layer_window_base;
    }

    pub fn buildLocal(
        self: *TextCoverageRecords,
        prepared: *const PreparedResources,
        blob: *const TextBlob,
        options: TextCoverageOptions,
    ) !void {
        self.reset();
        var atlas_view = try prepared.textAtlasView(options.resources.atlas);
        if (blob.hasPaintRecords()) {
            const paint_key = options.resources.paint orelse return error.MissingPreparedResource;
            const paint_view = try prepared.textPaintView(paint_key);
            atlas_view.paint_info_row_base = paint_view.info_row_base;
        }

        var batch = TextBatch.init(self.buffer);
        const overrides = [_]Override{.{ .transform = options.transform }};
        const draw = TextDraw{ .blob = blob, .resources = options.resources, .instances = &overrides };
        const result = try batch.addDraw(atlas_view, draw, 0, 0);
        self.layer_window_base = result.layer_window_base;
        if (!result.completed) {
            self.len = batch.slice().len;
            return error.DrawListFull;
        }

        const stamp = try prepared.textStamp(options.resources.atlas);
        self.len = batch.slice().len;
        self.resources = options.resources;
        self.atlas_stamp = stamp;
        if (blob.hasPaintRecords()) {
            const paint_key = options.resources.paint orelse return error.MissingPreparedResource;
            self.paint_stamp = try prepared.textPaintStamp(paint_key);
        }
    }

    pub fn validFor(self: *const TextCoverageRecords, prepared: *const PreparedResources) bool {
        const resources = self.resources orelse return false;
        const stamp = prepared.textStamp(resources.atlas) catch return false;
        if (!self.atlas_stamp.eql(stamp)) return false;
        const atlas_view = prepared.textAtlasView(resources.atlas) catch return false;
        if (!self.layerWindowValidFor(atlas_view)) return false;
        if (resources.paint) |paint_key| {
            const paint_stamp = prepared.textPaintStamp(paint_key) catch return false;
            if (!self.paint_stamp.eql(paint_stamp)) return false;
        }
        return true;
    }

    fn layerWindowValidFor(self: *const TextCoverageRecords, atlas_view: anytype) bool {
        if (atlas_view.page_layers.len == 0) {
            return texture_layers.windowBase(atlas_view.layer_base) == self.layer_window_base;
        }
        for (atlas_view.page_layers) |layer| {
            if (texture_layers.windowBase(layer) == self.layer_window_base) return true;
        }
        return false;
    }
};

pub const GlBackend = if (build_options.enable_opengl) struct {
    gl: *pipeline.GlTextState,
    gl_resources: *const pipeline.PreparedResources,
    prepared: *const PreparedResources,

    fn glState(self: GlBackend) *pipeline.GlTextState {
        return self.gl;
    }

    pub fn bindProgram(self: GlBackend, program: GlProgram) !void {
        self.gl_resources.bindTextCoverageProgram(program);
    }

    pub fn bindDrawState(self: GlBackend, program: GlProgram, state: DrawState) !void {
        _ = self;
        pipeline.PreparedResources.bindTextCoverageDrawState(program, .{
            .fill_rule = state.fill_rule,
            .subpixel_order = state.subpixel_order,
            .output_srgb = state.output_srgb,
            .coverage_transfer = state.coverage_transfer,
            .layer_base = state.layer_base,
        });
    }

    pub fn drawCoverage(self: GlBackend, coverage: *const TextCoverageRecords) !void {
        std.debug.assert(coverage.validFor(self.prepared));
        try self.drawVertices(coverage.slice());
    }

    pub fn drawVertices(self: GlBackend, vertices: []const u32) !void {
        self.glState().drawPreparedText(self.gl_resources, vertices);
    }
} else struct {};

pub const VulkanBackend = if (build_options.enable_vulkan) struct {
    vk: *vulkan_pipeline.VulkanPipeline,
    vk_resources: *const vulkan_pipeline.PreparedResources,
    prepared: *const PreparedResources,
    cmd: vulkan_pipeline.vk.VkCommandBuffer,

    pub fn descriptorSetLayout(self: VulkanBackend) vulkan_pipeline.vk.VkDescriptorSetLayout {
        return self.vk.textCoverageDescriptorSetLayout();
    }

    pub fn pipelineLayout(self: VulkanBackend) vulkan_pipeline.vk.VkPipelineLayout {
        return self.vk.textCoveragePipelineLayout();
    }

    pub fn bindProgram(self: VulkanBackend, program: VulkanProgram) !void {
        self.vk.setCommandBuffer(self.cmd);
        defer self.vk.clearCommandBuffer();
        try self.vk.bindTextCoverageProgram(self.vk_resources, program);
    }

    pub fn bindDrawState(self: VulkanBackend, program: VulkanProgram, state: DrawState) !void {
        _ = self;
        _ = program;
        _ = state;
    }

    pub fn drawCoverage(self: VulkanBackend, coverage: *const TextCoverageRecords) !void {
        std.debug.assert(coverage.validFor(self.prepared));
        try self.drawVertices(coverage.slice());
    }

    pub fn drawVertices(self: VulkanBackend, vertices: []const u32) !void {
        self.vk.setCommandBuffer(self.cmd);
        defer self.vk.clearCommandBuffer();
        try self.vk.drawPreparedTextCoverage(vertices);
    }
} else struct {};

/// Backend hook for evaluating Snail text coverage inside caller-owned shaders.
pub const Backend = union(BackendKind) {
    gl: GlBackend,
    vulkan: VulkanBackend,
    cpu: void,

    pub fn bindProgram(self: Backend, program: Program) !void {
        switch (self) {
            .gl => |backend| if (comptime build_options.enable_opengl) try backend.bindProgram(program.gl),
            .vulkan => |backend| if (comptime build_options.enable_vulkan) {
                try backend.bindProgram(program.vulkan);
            },
            .cpu => {},
        }
    }

    pub fn bindDrawState(self: Backend, program: Program, state: DrawState) !void {
        switch (self) {
            .gl => |backend| if (comptime build_options.enable_opengl) try backend.bindDrawState(program.gl, state),
            .vulkan => |backend| if (comptime build_options.enable_vulkan) {
                try backend.bindDrawState(program.vulkan, state);
            },
            .cpu => {},
        }
    }

    pub fn drawCoverage(self: Backend, coverage: *const TextCoverageRecords) !void {
        switch (self) {
            .gl => |backend| if (comptime build_options.enable_opengl) try backend.drawCoverage(coverage),
            .vulkan => |backend| if (comptime build_options.enable_vulkan) try backend.drawCoverage(coverage),
            .cpu => {},
        }
    }

    pub fn drawVertices(self: Backend, vertices: []const u32) !void {
        switch (self) {
            .gl => |backend| if (comptime build_options.enable_opengl) try backend.drawVertices(vertices),
            .vulkan => |backend| if (comptime build_options.enable_vulkan) try backend.drawVertices(vertices),
            .cpu => {},
        }
    }
};

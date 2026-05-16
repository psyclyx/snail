const std = @import("std");
const build_options = @import("build_options");
const backend_kind_mod = @import("backend_kind.zig");
const lowlevel_mod = @import("lowlevel.zig");
const resource_key_mod = @import("resource_key.zig");
const resources_mod = @import("resources.zig");
const scene_mod = @import("scene.zig");
const text_mod = @import("text.zig");
const vec = @import("math/vec.zig");
const vertex_mod = @import("renderer/vertex.zig");
const pipeline = if (build_options.enable_opengl) @import("renderer/gl.zig") else struct {
    pub const TextCoverageBindings = struct {};
    pub const GlTextState = void;
    pub const PreparedResources = void;
    pub const text_vertex_interface = "";
    pub const text_coverage_fragment_interface = "";
    pub const text_coverage_fragment_body = "";
    pub const text_sample_interface = "";
    pub const text_sample_body = "";
};
const vulkan_pipeline = if (build_options.enable_vulkan) @import("renderer/vulkan.zig") else struct {
    pub const PreparedResources = void;
    pub const VulkanPipeline = void;
};

const BackendKind = backend_kind_mod.BackendKind;
const Transform2D = vec.Transform2D;
const TextAtlas = text_mod.TextAtlas;
const TextBlob = text_mod.TextBlob;
const ResourceStamp = resource_key_mod.ResourceStamp;
const PreparedResources = resources_mod.PreparedResources;
const Override = scene_mod.Override;
const TextDraw = scene_mod.TextDraw;
const TextBatch = lowlevel_mod.TextBatch;

const TEXT_WORDS_PER_GLYPH = vertex_mod.WORDS_PER_VERTEX * vertex_mod.VERTICES_PER_GLYPH;

pub const GlBindings = if (build_options.enable_opengl) pipeline.TextCoverageBindings else struct {};
pub const VulkanBindings = if (build_options.enable_vulkan) vulkan_pipeline.TextCoverageBindings else struct {};

pub const Bindings = union(BackendKind) {
    gl: GlBindings,
    vulkan: VulkanBindings,
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
/// `GL_R32UI` texture buffer, and call `snail_text_sample_premul_linear(scene_pos)`.
pub const Shader = struct {
    pub const gl = struct {
        pub const vertex_interface = pipeline.text_vertex_interface;
        pub const fragment_interface = pipeline.text_coverage_fragment_interface;
        pub const resource_interface =
            \\uniform sampler2DArray u_curve_tex;
            \\uniform usampler2DArray u_band_tex;
            \\uniform int u_fill_rule;
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
            \\    int atlas_layer = (v_glyph.w >> 8) & 0xFF;
            \\    if (atlas_layer == 0xFF) return 0.0;
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
        pub const vertex_shader = @embedFile("renderer/vulkan_glsl/snail.vert");
        pub const text_fragment_shader = @embedFile("renderer/vulkan_glsl/snail_text.frag");
        pub const coverage_functions =
            @embedFile("renderer/glsl/snail_coverage_common.glsl") ++
            "\n" ++
            @embedFile("renderer/glsl/snail_color_common.glsl") ++
            "\n" ++
            @embedFile("renderer/glsl/snail_text_frag_body.glsl");
        pub const descriptor_set_index: u32 = 0;
        pub const curve_texture_binding: u32 = 0;
        pub const band_texture_binding: u32 = 1;
    };
};

pub const GlProgram = struct {
    bindings: GlBindings = .{},
};

pub const VulkanProgram = if (build_options.enable_vulkan) struct {
    pipeline_layout: vulkan_pipeline.vk.VkPipelineLayout = null,
    descriptor_set_index: u32 = 0,
} else struct {};

pub const CpuProgram = struct {};

pub const Program = union(BackendKind) {
    gl: GlProgram,
    vulkan: VulkanProgram,
    cpu: CpuProgram,
};

/// Resolve options used when preparing text coverage geometry for a custom
/// material shader.
pub const TextCoverageOptions = struct {
    transform: Transform2D = .identity,
};

/// Prepared glyph coverage records for use by a custom material shader.
///
/// Wraps caller-owned per-glyph draw data. Snail atlas textures come from
/// PreparedResources. Use `wordCapacityForBlob` to size `buffer`.
pub const TextCoverageRecords = struct {
    buffer: []u32,
    len: usize = 0,
    atlas: ?*const TextAtlas = null,
    atlas_stamp: ResourceStamp = .{},
    paint_blob: ?*const TextBlob = null,
    paint_stamp: ResourceStamp = .{},

    pub fn wordCapacityForBlob(blob: *const TextBlob) usize {
        return blob.gpu_instance_budget * TEXT_WORDS_PER_GLYPH;
    }

    pub fn init(buffer: []u32) TextCoverageRecords {
        return .{ .buffer = buffer };
    }

    pub fn reset(self: *TextCoverageRecords) void {
        self.len = 0;
        self.atlas = null;
        self.atlas_stamp = .{};
        self.paint_blob = null;
        self.paint_stamp = .{};
    }

    pub fn glyphCount(self: *const TextCoverageRecords) usize {
        return self.len / TEXT_WORDS_PER_GLYPH;
    }

    pub fn slice(self: *const TextCoverageRecords) []const u32 {
        return self.buffer[0..self.len];
    }

    pub fn buildLocal(
        self: *TextCoverageRecords,
        prepared: *const PreparedResources,
        blob: *const TextBlob,
        options: TextCoverageOptions,
    ) !void {
        self.reset();
        var atlas_view = try prepared.textAtlasView(blob.atlas);
        if (blob.hasPaintRecords()) {
            const paint_view = try prepared.textPaintView(blob);
            atlas_view.paint_info_row_base = paint_view.info_row_base;
        }

        var batch = TextBatch.init(self.buffer);
        const overrides = [_]Override{.{ .transform = options.transform }};
        const draw = TextDraw{ .blob = blob, .instances = &overrides };
        const result = try batch.addDraw(atlas_view, draw, 0, 0);
        if (!result.completed) {
            self.len = batch.slice().len;
            return error.DrawListFull;
        }

        const stamp = try prepared.textStamp(blob.atlas);
        self.len = batch.slice().len;
        self.atlas = blob.atlas;
        self.atlas_stamp = stamp;
        if (blob.hasPaintRecords()) {
            self.paint_blob = blob;
            self.paint_stamp = try prepared.textPaintStamp(blob);
        }
    }

    pub fn validFor(self: *const TextCoverageRecords, prepared: *const PreparedResources) bool {
        const atlas = self.atlas orelse return false;
        const stamp = prepared.textStamp(atlas) catch return false;
        if (!self.atlas_stamp.eql(stamp)) return false;
        if (self.paint_blob) |blob| {
            const paint_stamp = prepared.textPaintStamp(blob) catch return false;
            if (!self.paint_stamp.eql(paint_stamp)) return false;
        }
        return true;
    }
};

pub const GlBackend = if (build_options.enable_opengl) struct {
    gl: *pipeline.GlTextState,
    gl_resources: *const pipeline.PreparedResources,
    prepared: *const PreparedResources,

    fn glState(self: GlBackend) *pipeline.GlTextState {
        return self.gl;
    }

    pub fn bindResources(self: GlBackend, bindings: GlBindings) void {
        self.gl_resources.bindTextCoverageResources(bindings);
    }

    pub fn drawCoverage(self: GlBackend, coverage: *const TextCoverageRecords) void {
        std.debug.assert(coverage.validFor(self.prepared));
        self.drawVertices(coverage.slice());
    }

    pub fn drawVertices(self: GlBackend, vertices: []const u32) void {
        self.glState().drawPreparedText(self.gl_resources, vertices);
    }
} else struct {};

pub const VulkanBackend = if (build_options.enable_vulkan) struct {
    vk: *vulkan_pipeline.VulkanPipeline,
    vk_resources: *const vulkan_pipeline.PreparedResources,
    prepared: *const PreparedResources,

    pub fn descriptorSetLayout(self: VulkanBackend) vulkan_pipeline.vk.VkDescriptorSetLayout {
        return self.vk.textCoverageDescriptorSetLayout();
    }

    pub fn pipelineLayout(self: VulkanBackend) vulkan_pipeline.vk.VkPipelineLayout {
        return self.vk.textCoveragePipelineLayout();
    }

    pub fn bindResources(self: VulkanBackend, bindings: VulkanBindings) void {
        self.vk.bindTextCoverageResources(self.vk_resources, bindings);
    }

    pub fn drawCoverage(self: VulkanBackend, coverage: *const TextCoverageRecords) void {
        std.debug.assert(coverage.validFor(self.prepared));
        self.drawVertices(coverage.slice());
    }

    pub fn drawVertices(self: VulkanBackend, vertices: []const u32) void {
        self.vk.drawPreparedTextCoverage(vertices);
    }
} else struct {};

/// Backend hook for evaluating Snail text coverage inside caller-owned shaders.
pub const Backend = union(BackendKind) {
    gl: GlBackend,
    vulkan: VulkanBackend,
    cpu: void,

    pub fn bindResources(self: Backend, bindings: Bindings) void {
        switch (self) {
            .gl => |backend| if (comptime build_options.enable_opengl) backend.bindResources(bindings.gl),
            .vulkan => |backend| if (comptime build_options.enable_vulkan) {
                backend.bindResources(bindings.vulkan);
            },
            .cpu => {},
        }
    }

    pub fn drawCoverage(self: Backend, coverage: *const TextCoverageRecords) void {
        switch (self) {
            .gl => |backend| if (comptime build_options.enable_opengl) backend.drawCoverage(coverage),
            .vulkan => |backend| if (comptime build_options.enable_vulkan) backend.drawCoverage(coverage),
            .cpu => {},
        }
    }

    pub fn drawVertices(self: Backend, vertices: []const u32) void {
        switch (self) {
            .gl => |backend| if (comptime build_options.enable_opengl) backend.drawVertices(vertices),
            .vulkan => |backend| if (comptime build_options.enable_vulkan) backend.drawVertices(vertices),
            .cpu => {},
        }
    }
};

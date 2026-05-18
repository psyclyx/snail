const common = @import("common.zig");
const snail = common.snail;
const build_options = common.build_options;
const vk = common.vk;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_RENDERER_FAILED = common.SNAIL_ERR_RENDERER_FAILED;
const SNAIL_ERR_INVALID_ARGUMENT = common.SNAIL_ERR_INVALID_ARGUMENT;
const SNAIL_ERR_DRAW_FAILED = common.SNAIL_ERR_DRAW_FAILED;
const SnailString = common.SnailString;
const SnailCoverageDrawState = common.SnailCoverageDrawState;
const SnailGlTextCoverageProgram = common.SnailGlTextCoverageProgram;
const SnailVulkanTextCoverageProgram = common.SnailVulkanTextCoverageProgram;
const wrapString = common.wrapString;
const toCoverageDrawState = common.toCoverageDrawState;
const toGlCoverageProgram = common.toGlCoverageProgram;
const toVulkanCoverageProgram = common.toVulkanCoverageProgram;
const CoverageBackendImpl = common.CoverageBackendImpl;

pub export fn snail_gl_coverage_shader_vertex_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.vertex_interface);
}

pub export fn snail_gl_coverage_shader_fragment_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.fragment_interface);
}

pub export fn snail_gl_coverage_shader_resource_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.resource_interface);
}

pub export fn snail_gl_coverage_shader_coverage_functions() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.coverage_functions);
}

pub export fn snail_gl_coverage_shader_sample_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.sample_interface);
}

pub export fn snail_gl_coverage_shader_sample_functions() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.sample_functions);
}

pub export fn snail_gl_coverage_shader_fragment_body() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.fragment_body);
}

pub export fn snail_gl_coverage_backend_bind_program(backend: *CoverageBackendImpl, program: SnailGlTextCoverageProgram) c_int {
    if (comptime !build_options.enable_opengl) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gl => |gl_backend| {
            gl_backend.bindProgram(toGlCoverageProgram(program) catch return SNAIL_ERR_INVALID_ARGUMENT) catch return SNAIL_ERR_DRAW_FAILED;
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

pub export fn snail_gl_coverage_backend_bind_draw_state(backend: *CoverageBackendImpl, program: SnailGlTextCoverageProgram, state: SnailCoverageDrawState) c_int {
    if (comptime !build_options.enable_opengl) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gl => |gl_backend| {
            gl_backend.bindDrawState(
                toGlCoverageProgram(program) catch return SNAIL_ERR_INVALID_ARGUMENT,
                toCoverageDrawState(state) catch return SNAIL_ERR_INVALID_ARGUMENT,
            ) catch return SNAIL_ERR_DRAW_FAILED;
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

pub export fn snail_vulkan_coverage_shader_vertex_shader() SnailString {
    if (comptime !build_options.enable_vulkan) return wrapString("");
    return wrapString(snail.coverage.Shader.vulkan.vertex_shader);
}

pub export fn snail_vulkan_coverage_shader_text_fragment_shader() SnailString {
    if (comptime !build_options.enable_vulkan) return wrapString("");
    return wrapString(snail.coverage.Shader.vulkan.text_fragment_shader);
}

pub export fn snail_vulkan_coverage_shader_coverage_functions() SnailString {
    if (comptime !build_options.enable_vulkan) return wrapString("");
    return wrapString(snail.coverage.Shader.vulkan.coverage_functions);
}

pub export fn snail_vulkan_coverage_shader_descriptor_set_index() u32 {
    if (comptime !build_options.enable_vulkan) return 0;
    return snail.coverage.Shader.vulkan.descriptor_set_index;
}

pub export fn snail_vulkan_coverage_shader_curve_texture_binding() u32 {
    if (comptime !build_options.enable_vulkan) return 0;
    return snail.coverage.Shader.vulkan.curve_texture_binding;
}

pub export fn snail_vulkan_coverage_shader_band_texture_binding() u32 {
    if (comptime !build_options.enable_vulkan) return 0;
    return snail.coverage.Shader.vulkan.band_texture_binding;
}

pub export fn snail_vulkan_coverage_backend_descriptor_set_layout(backend: *CoverageBackendImpl) vk.VkDescriptorSetLayout {
    if (comptime !build_options.enable_vulkan) return null;
    return switch (backend.inner) {
        .vulkan => |vk_backend| vk_backend.descriptorSetLayout(),
        else => null,
    };
}

pub export fn snail_vulkan_coverage_backend_pipeline_layout(backend: *CoverageBackendImpl) vk.VkPipelineLayout {
    if (comptime !build_options.enable_vulkan) return null;
    return switch (backend.inner) {
        .vulkan => |vk_backend| vk_backend.pipelineLayout(),
        else => null,
    };
}

pub export fn snail_vulkan_coverage_backend_bind_program(backend: *CoverageBackendImpl, program: SnailVulkanTextCoverageProgram) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .vulkan => |vk_backend| {
            vk_backend.bindProgram(toVulkanCoverageProgram(program)) catch return SNAIL_ERR_DRAW_FAILED;
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

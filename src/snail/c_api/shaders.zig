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
const SnailGl33TextCoverageProgram = common.SnailGl33TextCoverageProgram;
const SnailGl44TextCoverageProgram = common.SnailGl44TextCoverageProgram;
const SnailGles30TextCoverageProgram = common.SnailGles30TextCoverageProgram;
const SnailVulkanTextCoverageProgram = common.SnailVulkanTextCoverageProgram;
const wrapString = common.wrapString;
const toCoverageDrawState = common.toCoverageDrawState;
const toGl33CoverageProgram = common.toGl33CoverageProgram;
const toGl44CoverageProgram = common.toGl44CoverageProgram;
const toGles30CoverageProgram = common.toGles30CoverageProgram;
const toVulkanCoverageProgram = common.toVulkanCoverageProgram;
const CoverageBackendImpl = common.CoverageBackendImpl;

pub export fn snail_gl33_coverage_shader_vertex_interface() SnailString {
    if (comptime !build_options.enable_gl33) return wrapString("");
    return wrapString(snail.coverage.Shader.gl33.vertex_interface);
}

pub export fn snail_gl33_coverage_shader_fragment_interface() SnailString {
    if (comptime !build_options.enable_gl33) return wrapString("");
    return wrapString(snail.coverage.Shader.gl33.fragment_interface);
}

pub export fn snail_gl33_coverage_shader_resource_interface() SnailString {
    if (comptime !build_options.enable_gl33) return wrapString("");
    return wrapString(snail.coverage.Shader.gl33.resource_interface);
}

pub export fn snail_gl33_coverage_shader_coverage_functions() SnailString {
    if (comptime !build_options.enable_gl33) return wrapString("");
    return wrapString(snail.coverage.Shader.gl33.coverage_functions);
}

pub export fn snail_gl33_coverage_shader_sample_interface() SnailString {
    if (comptime !build_options.enable_gl33) return wrapString("");
    return wrapString(snail.coverage.Shader.gl33.sample_interface);
}

pub export fn snail_gl33_coverage_shader_sample_functions() SnailString {
    if (comptime !build_options.enable_gl33) return wrapString("");
    return wrapString(snail.coverage.Shader.gl33.sample_functions);
}

pub export fn snail_gl33_coverage_shader_fragment_body() SnailString {
    if (comptime !build_options.enable_gl33) return wrapString("");
    return wrapString(snail.coverage.Shader.gl33.fragment_body);
}

pub export fn snail_gl44_coverage_shader_vertex_interface() SnailString {
    if (comptime !build_options.enable_gl44) return wrapString("");
    return wrapString(snail.coverage.Shader.gl44.vertex_interface);
}

pub export fn snail_gl44_coverage_shader_fragment_interface() SnailString {
    if (comptime !build_options.enable_gl44) return wrapString("");
    return wrapString(snail.coverage.Shader.gl44.fragment_interface);
}

pub export fn snail_gl44_coverage_shader_resource_interface() SnailString {
    if (comptime !build_options.enable_gl44) return wrapString("");
    return wrapString(snail.coverage.Shader.gl44.resource_interface);
}

pub export fn snail_gl44_coverage_shader_coverage_functions() SnailString {
    if (comptime !build_options.enable_gl44) return wrapString("");
    return wrapString(snail.coverage.Shader.gl44.coverage_functions);
}

pub export fn snail_gl44_coverage_shader_sample_interface() SnailString {
    if (comptime !build_options.enable_gl44) return wrapString("");
    return wrapString(snail.coverage.Shader.gl44.sample_interface);
}

pub export fn snail_gl44_coverage_shader_sample_functions() SnailString {
    if (comptime !build_options.enable_gl44) return wrapString("");
    return wrapString(snail.coverage.Shader.gl44.sample_functions);
}

pub export fn snail_gl44_coverage_shader_fragment_body() SnailString {
    if (comptime !build_options.enable_gl44) return wrapString("");
    return wrapString(snail.coverage.Shader.gl44.fragment_body);
}

pub export fn snail_gl33_coverage_backend_bind_program(backend: *CoverageBackendImpl, program: SnailGl33TextCoverageProgram) c_int {
    if (comptime !build_options.enable_gl33) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gl33 => |gl_backend| {
            gl_backend.bindProgram(toGl33CoverageProgram(program) catch return SNAIL_ERR_INVALID_ARGUMENT) catch return SNAIL_ERR_DRAW_FAILED;
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

pub export fn snail_gl33_coverage_backend_bind_draw_state(backend: *CoverageBackendImpl, program: SnailGl33TextCoverageProgram, state: SnailCoverageDrawState) c_int {
    if (comptime !build_options.enable_gl33) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gl33 => |gl_backend| {
            gl_backend.bindDrawState(
                toGl33CoverageProgram(program) catch return SNAIL_ERR_INVALID_ARGUMENT,
                toCoverageDrawState(state) catch return SNAIL_ERR_INVALID_ARGUMENT,
            ) catch return SNAIL_ERR_DRAW_FAILED;
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

pub export fn snail_gl44_coverage_backend_bind_program(backend: *CoverageBackendImpl, program: SnailGl44TextCoverageProgram) c_int {
    if (comptime !build_options.enable_gl44) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gl44 => |gl_backend| {
            gl_backend.bindProgram(toGl44CoverageProgram(program) catch return SNAIL_ERR_INVALID_ARGUMENT) catch return SNAIL_ERR_DRAW_FAILED;
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

pub export fn snail_gl44_coverage_backend_bind_draw_state(backend: *CoverageBackendImpl, program: SnailGl44TextCoverageProgram, state: SnailCoverageDrawState) c_int {
    if (comptime !build_options.enable_gl44) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gl44 => |gl_backend| {
            gl_backend.bindDrawState(
                toGl44CoverageProgram(program) catch return SNAIL_ERR_INVALID_ARGUMENT,
                toCoverageDrawState(state) catch return SNAIL_ERR_INVALID_ARGUMENT,
            ) catch return SNAIL_ERR_DRAW_FAILED;
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

pub export fn snail_gles30_coverage_shader_vertex_interface() SnailString {
    if (comptime !build_options.enable_gles30) return wrapString("");
    return wrapString(snail.coverage.Shader.gles30.vertex_interface);
}

pub export fn snail_gles30_coverage_shader_fragment_interface() SnailString {
    if (comptime !build_options.enable_gles30) return wrapString("");
    return wrapString(snail.coverage.Shader.gles30.fragment_interface);
}

pub export fn snail_gles30_coverage_shader_resource_interface() SnailString {
    if (comptime !build_options.enable_gles30) return wrapString("");
    return wrapString(snail.coverage.Shader.gles30.resource_interface);
}

pub export fn snail_gles30_coverage_shader_coverage_functions() SnailString {
    if (comptime !build_options.enable_gles30) return wrapString("");
    return wrapString(snail.coverage.Shader.gles30.coverage_functions);
}

pub export fn snail_gles30_coverage_shader_sample_interface() SnailString {
    if (comptime !build_options.enable_gles30) return wrapString("");
    return wrapString(snail.coverage.Shader.gles30.sample_interface);
}

pub export fn snail_gles30_coverage_shader_sample_functions() SnailString {
    if (comptime !build_options.enable_gles30) return wrapString("");
    return wrapString(snail.coverage.Shader.gles30.sample_functions);
}

pub export fn snail_gles30_coverage_shader_fragment_body() SnailString {
    if (comptime !build_options.enable_gles30) return wrapString("");
    return wrapString(snail.coverage.Shader.gles30.fragment_body);
}

pub export fn snail_gles30_coverage_backend_bind_program(backend: *CoverageBackendImpl, program: SnailGles30TextCoverageProgram) c_int {
    if (comptime !build_options.enable_gles30) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gles30 => |gles30_backend| {
            gles30_backend.bindProgram(toGles30CoverageProgram(program) catch return SNAIL_ERR_INVALID_ARGUMENT) catch return SNAIL_ERR_DRAW_FAILED;
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

pub export fn snail_gles30_coverage_backend_bind_draw_state(backend: *CoverageBackendImpl, program: SnailGles30TextCoverageProgram, state: SnailCoverageDrawState) c_int {
    if (comptime !build_options.enable_gles30) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gles30 => |gles30_backend| {
            gles30_backend.bindDrawState(
                toGles30CoverageProgram(program) catch return SNAIL_ERR_INVALID_ARGUMENT,
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

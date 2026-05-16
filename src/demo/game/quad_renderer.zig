const std = @import("std");
const snail = @import("snail");
const gl = @import("../internal_gl.zig").gl;
const common = @import("common.zig");

const Vec3 = common.Vec3;
const MATERIAL_GRID: u32 = 72;

pub const RenderTarget = struct {
    fbo: gl.GLuint = 0,
    texture: gl.GLuint = 0,
    depth: gl.GLuint = 0,
    width: u32 = 0,
    height: u32 = 0,

    pub fn init(width: u32, height: u32, with_depth: bool) !RenderTarget {
        var target: RenderTarget = .{};
        try target.allocate(width, height, with_depth);
        return target;
    }

    fn allocate(self: *RenderTarget, width: u32, height: u32, with_depth: bool) !void {
        self.width = width;
        self.height = height;

        gl.glGenFramebuffers(1, &self.fbo);
        gl.glGenTextures(1, &self.texture);

        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, self.fbo);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture);
        gl.glTexImage2D(
            gl.GL_TEXTURE_2D,
            0,
            @intCast(common.GL_SRGB8_ALPHA8),
            @intCast(width),
            @intCast(height),
            0,
            gl.GL_RGBA,
            gl.GL_UNSIGNED_BYTE,
            null,
        );
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        gl.glFramebufferTexture2D(gl.GL_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.texture, 0);

        if (with_depth) {
            gl.glGenRenderbuffers(1, &self.depth);
            gl.glBindRenderbuffer(gl.GL_RENDERBUFFER, self.depth);
            gl.glRenderbufferStorage(gl.GL_RENDERBUFFER, gl.GL_DEPTH_COMPONENT24, @intCast(width), @intCast(height));
            gl.glFramebufferRenderbuffer(gl.GL_FRAMEBUFFER, gl.GL_DEPTH_ATTACHMENT, gl.GL_RENDERBUFFER, self.depth);
        }

        if (gl.glCheckFramebufferStatus(gl.GL_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) {
            return error.FramebufferIncomplete;
        }

        gl.glBindRenderbuffer(gl.GL_RENDERBUFFER, 0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
        gl.glBindFramebuffer(gl.GL_FRAMEBUFFER, 0);
    }

    pub fn resize(self: *RenderTarget, width: u32, height: u32, with_depth: bool) !void {
        self.deinit();
        try self.allocate(width, height, with_depth);
    }

    pub fn deinit(self: *RenderTarget) void {
        if (self.depth != 0) gl.glDeleteRenderbuffers(1, &self.depth);
        if (self.texture != 0) gl.glDeleteTextures(1, &self.texture);
        if (self.fbo != 0) gl.glDeleteFramebuffers(1, &self.fbo);
        self.* = .{};
    }
};

const MaterialProgram = struct {
    handle: gl.GLuint = 0,
    view_proj_loc: gl.GLint = -1,
    model_loc: gl.GLint = -1,
    base_color_loc: gl.GLint = -1,
    overlay_tex_loc: gl.GLint = -1,
    normal_tex_loc: gl.GLint = -1,
    camera_pos_loc: gl.GLint = -1,
    light_pos_loc: gl.GLint = -1,
    light_color_loc: gl.GLint = -1,
    uv_scale_loc: gl.GLint = -1,
    use_overlay_loc: gl.GLint = -1,
    use_normal_map_loc: gl.GLint = -1,
    normal_strength_loc: gl.GLint = -1,
    parallax_strength_loc: gl.GLint = -1,
    displacement_strength_loc: gl.GLint = -1,
    shadow_strength_loc: gl.GLint = -1,
    sign_style_loc: gl.GLint = -1,
    overlay_material_paint_loc: gl.GLint = -1,

    fn init() !MaterialProgram {
        const handle = try common.linkProgram(material_vertex_shader, material_fragment_shader);
        return .{
            .handle = handle,
            .view_proj_loc = gl.glGetUniformLocation(handle, "u_view_proj"),
            .model_loc = gl.glGetUniformLocation(handle, "u_model"),
            .base_color_loc = gl.glGetUniformLocation(handle, "u_base_color"),
            .overlay_tex_loc = gl.glGetUniformLocation(handle, "u_overlay_tex"),
            .normal_tex_loc = gl.glGetUniformLocation(handle, "u_normal_tex"),
            .camera_pos_loc = gl.glGetUniformLocation(handle, "u_camera_pos"),
            .light_pos_loc = gl.glGetUniformLocation(handle, "u_light_pos"),
            .light_color_loc = gl.glGetUniformLocation(handle, "u_light_color"),
            .uv_scale_loc = gl.glGetUniformLocation(handle, "u_uv_scale"),
            .use_overlay_loc = gl.glGetUniformLocation(handle, "u_use_overlay"),
            .use_normal_map_loc = gl.glGetUniformLocation(handle, "u_use_normal_map"),
            .normal_strength_loc = gl.glGetUniformLocation(handle, "u_normal_strength"),
            .parallax_strength_loc = gl.glGetUniformLocation(handle, "u_parallax_strength"),
            .displacement_strength_loc = gl.glGetUniformLocation(handle, "u_displacement_strength"),
            .shadow_strength_loc = gl.glGetUniformLocation(handle, "u_shadow_strength"),
            .sign_style_loc = gl.glGetUniformLocation(handle, "u_sign_style"),
            .overlay_material_paint_loc = gl.glGetUniformLocation(handle, "u_overlay_material_paint"),
        };
    }

    fn deinit(self: *MaterialProgram) void {
        if (self.handle != 0) gl.glDeleteProgram(self.handle);
        self.* = .{};
    }
};

const PremultTextureProgram = struct {
    handle: gl.GLuint = 0,
    view_proj_loc: gl.GLint = -1,
    model_loc: gl.GLint = -1,
    tex_loc: gl.GLint = -1,
    camera_pos_loc: gl.GLint = -1,
    light_pos_loc: gl.GLint = -1,
    light_color_loc: gl.GLint = -1,
    lighting_loc: gl.GLint = -1,

    fn init() !PremultTextureProgram {
        const handle = try common.linkProgram(material_vertex_shader, premult_texture_fragment_shader);
        return .{
            .handle = handle,
            .view_proj_loc = gl.glGetUniformLocation(handle, "u_view_proj"),
            .model_loc = gl.glGetUniformLocation(handle, "u_model"),
            .tex_loc = gl.glGetUniformLocation(handle, "u_tex"),
            .camera_pos_loc = gl.glGetUniformLocation(handle, "u_camera_pos"),
            .light_pos_loc = gl.glGetUniformLocation(handle, "u_light_pos"),
            .light_color_loc = gl.glGetUniformLocation(handle, "u_light_color"),
            .lighting_loc = gl.glGetUniformLocation(handle, "u_enable_lighting"),
        };
    }

    fn deinit(self: *PremultTextureProgram) void {
        if (self.handle != 0) gl.glDeleteProgram(self.handle);
        self.* = .{};
    }
};

pub const QuadRenderer = struct {
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    ebo: gl.GLuint = 0,
    material_vao: gl.GLuint = 0,
    material_vbo: gl.GLuint = 0,
    material_ebo: gl.GLuint = 0,
    material_index_count: gl.GLsizei = 0,
    material: MaterialProgram,
    premult: PremultTextureProgram,

    pub fn init() !QuadRenderer {
        var self: QuadRenderer = .{
            .material = try MaterialProgram.init(),
            .premult = try PremultTextureProgram.init(),
        };
        errdefer self.material.deinit();
        errdefer self.premult.deinit();

        const vertices = [_]f32{
            -0.5, -0.5, 0.0, 0.0, 0.0,
            0.5,  -0.5, 0.0, 1.0, 0.0,
            0.5,  0.5,  0.0, 1.0, 1.0,
            -0.5, 0.5,  0.0, 0.0, 1.0,
        };
        const indices = [_]u32{ 0, 1, 2, 0, 2, 3 };

        gl.glGenVertexArrays(1, &self.vao);
        gl.glGenBuffers(1, &self.vbo);
        gl.glGenBuffers(1, &self.ebo);

        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.GL_STATIC_DRAW);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.GL_STATIC_DRAW);

        const stride = 5 * @sizeOf(f32);
        gl.glEnableVertexAttribArray(0);
        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, @intCast(stride), @ptrFromInt(0));
        gl.glEnableVertexAttribArray(1);
        gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, @intCast(stride), @ptrFromInt(3 * @sizeOf(f32)));

        gl.glBindVertexArray(0);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, 0);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, 0);

        try self.initMaterialGrid();
        return self;
    }

    fn initMaterialGrid(self: *QuadRenderer) !void {
        const allocator = std.heap.smp_allocator;
        const side = MATERIAL_GRID + 1;
        const vertex_count: usize = side * side;
        const index_count: usize = MATERIAL_GRID * MATERIAL_GRID * 6;
        const vertices = try allocator.alloc(f32, vertex_count * 5);
        defer allocator.free(vertices);
        const indices = try allocator.alloc(u32, index_count);
        defer allocator.free(indices);

        var v: usize = 0;
        for (0..side) |y| {
            const fy = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(MATERIAL_GRID));
            for (0..side) |x| {
                const fx = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(MATERIAL_GRID));
                vertices[v + 0] = fx - 0.5;
                vertices[v + 1] = fy - 0.5;
                vertices[v + 2] = 0.0;
                vertices[v + 3] = fx;
                vertices[v + 4] = fy;
                v += 5;
            }
        }

        var i: usize = 0;
        for (0..MATERIAL_GRID) |y| {
            for (0..MATERIAL_GRID) |x| {
                const a: u32 = @intCast(y * side + x);
                const b = a + 1;
                const c = a + side;
                const d = c + 1;
                indices[i + 0] = a;
                indices[i + 1] = b;
                indices[i + 2] = d;
                indices[i + 3] = a;
                indices[i + 4] = d;
                indices[i + 5] = c;
                i += 6;
            }
        }

        gl.glGenVertexArrays(1, &self.material_vao);
        gl.glGenBuffers(1, &self.material_vbo);
        gl.glGenBuffers(1, &self.material_ebo);

        gl.glBindVertexArray(self.material_vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.material_vbo);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(vertices.len * @sizeOf(f32)), vertices.ptr, gl.GL_STATIC_DRAW);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.material_ebo);
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.len * @sizeOf(u32)), indices.ptr, gl.GL_STATIC_DRAW);

        const stride = 5 * @sizeOf(f32);
        gl.glEnableVertexAttribArray(0);
        gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, @intCast(stride), @ptrFromInt(0));
        gl.glEnableVertexAttribArray(1);
        gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, @intCast(stride), @ptrFromInt(3 * @sizeOf(f32)));

        self.material_index_count = @intCast(index_count);

        gl.glBindVertexArray(0);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, 0);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, 0);
    }

    pub fn deinit(self: *QuadRenderer) void {
        self.material.deinit();
        self.premult.deinit();
        if (self.material_ebo != 0) gl.glDeleteBuffers(1, &self.material_ebo);
        if (self.material_vbo != 0) gl.glDeleteBuffers(1, &self.material_vbo);
        if (self.material_vao != 0) gl.glDeleteVertexArrays(1, &self.material_vao);
        if (self.ebo != 0) gl.glDeleteBuffers(1, &self.ebo);
        if (self.vbo != 0) gl.glDeleteBuffers(1, &self.vbo);
        if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
        self.* = undefined;
    }

    pub fn drawMaterial(
        self: *const QuadRenderer,
        view_proj: snail.Mat4,
        model: snail.Mat4,
        base_color: [4]f32,
        overlay_texture: ?gl.GLuint,
        normal_map: ?gl.GLuint,
        uv_scale: [2]f32,
        normal_strength: f32,
        parallax_strength: f32,
        displacement_strength: f32,
        shadow_strength: f32,
        sign_style: bool,
        overlay_material_paint: bool,
        camera_pos: Vec3,
        light_pos: Vec3,
        light_color: [3]f32,
    ) void {
        gl.glUseProgram(self.material.handle);
        gl.glBindVertexArray(self.material_vao);
        gl.glUniformMatrix4fv(self.material.view_proj_loc, 1, gl.GL_FALSE, &view_proj.data[0]);
        gl.glUniformMatrix4fv(self.material.model_loc, 1, gl.GL_FALSE, &model.data[0]);
        gl.glUniform4f(self.material.base_color_loc, base_color[0], base_color[1], base_color[2], base_color[3]);
        gl.glUniform3f(self.material.camera_pos_loc, camera_pos.x, camera_pos.y, camera_pos.z);
        gl.glUniform3f(self.material.light_pos_loc, light_pos.x, light_pos.y, light_pos.z);
        gl.glUniform3f(self.material.light_color_loc, light_color[0], light_color[1], light_color[2]);
        gl.glUniform2f(self.material.uv_scale_loc, uv_scale[0], uv_scale[1]);
        gl.glUniform1f(self.material.normal_strength_loc, normal_strength);
        gl.glUniform1f(self.material.parallax_strength_loc, parallax_strength);
        gl.glUniform1f(self.material.displacement_strength_loc, displacement_strength);
        gl.glUniform1f(self.material.shadow_strength_loc, shadow_strength);
        gl.glUniform1i(self.material.sign_style_loc, if (sign_style) 1 else 0);
        gl.glUniform1i(self.material.overlay_material_paint_loc, if (overlay_material_paint) 1 else 0);
        gl.glUniform1i(self.material.use_overlay_loc, if (overlay_texture != null) 1 else 0);
        gl.glUniform1i(self.material.use_normal_map_loc, if (normal_map != null) 1 else 0);

        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, overlay_texture orelse 0);
        gl.glUniform1i(self.material.overlay_tex_loc, 0);

        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D, normal_map orelse 0);
        gl.glUniform1i(self.material.normal_tex_loc, 1);

        gl.glDrawElements(gl.GL_TRIANGLES, self.material_index_count, gl.GL_UNSIGNED_INT, null);
        gl.glBindVertexArray(0);
        gl.glUseProgram(0);
    }

    pub fn drawPremultTexture(
        self: *const QuadRenderer,
        view_proj: snail.Mat4,
        model: snail.Mat4,
        texture: gl.GLuint,
        camera_pos: Vec3,
        light_pos: Vec3,
        light_color: [3]f32,
        enable_lighting: bool,
    ) void {
        gl.glUseProgram(self.premult.handle);
        gl.glBindVertexArray(self.vao);
        gl.glUniformMatrix4fv(self.premult.view_proj_loc, 1, gl.GL_FALSE, &view_proj.data[0]);
        gl.glUniformMatrix4fv(self.premult.model_loc, 1, gl.GL_FALSE, &model.data[0]);
        gl.glUniform3f(self.premult.camera_pos_loc, camera_pos.x, camera_pos.y, camera_pos.z);
        gl.glUniform3f(self.premult.light_pos_loc, light_pos.x, light_pos.y, light_pos.z);
        gl.glUniform3f(self.premult.light_color_loc, light_color[0], light_color[1], light_color[2]);
        gl.glUniform1i(self.premult.lighting_loc, if (enable_lighting) 1 else 0);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
        gl.glUniform1i(self.premult.tex_loc, 0);
        gl.glDrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, null);
        gl.glBindVertexArray(0);
        gl.glUseProgram(0);
    }
};

const material_vertex_shader: [:0]const u8 =
    \\#version 330 core
    \\layout(location = 0) in vec3 a_pos;
    \\layout(location = 1) in vec2 a_uv;
    \\
    \\uniform mat4 u_view_proj;
    \\uniform mat4 u_model;
    \\uniform sampler2D u_normal_tex;
    \\uniform vec2 u_uv_scale;
    \\uniform float u_displacement_strength;
    \\uniform int u_use_normal_map;
    \\
    \\out vec2 v_uv;
    \\out vec3 v_world_pos;
    \\out vec3 v_world_normal;
    \\out vec3 v_world_tangent;
    \\out vec3 v_world_bitangent;
    \\
    \\void main() {
    \\    vec3 local_pos = a_pos;
    \\    if (u_use_normal_map != 0 && u_displacement_strength > 0.0) {
    \\        float h = texture(u_normal_tex, a_uv * u_uv_scale).a;
    \\        float height = clamp((h - 0.5) * 1.42 + 0.5, 0.0, 1.0);
    \\        local_pos.z += (height - 0.5) * u_displacement_strength;
    \\    }
    \\    vec4 world = u_model * vec4(local_pos, 1.0);
    \\    mat3 basis = mat3(u_model);
    \\    v_uv = a_uv;
    \\    v_world_pos = world.xyz;
    \\    v_world_tangent = normalize(basis * vec3(1.0, 0.0, 0.0));
    \\    v_world_bitangent = normalize(basis * vec3(0.0, 1.0, 0.0));
    \\    v_world_normal = normalize(basis * vec3(0.0, 0.0, 1.0));
    \\    gl_Position = u_view_proj * world;
    \\}
;

const material_fragment_shader: [:0]const u8 =
    \\#version 330 core
    \\
    \\in vec2 v_uv;
    \\in vec3 v_world_pos;
    \\in vec3 v_world_normal;
    \\in vec3 v_world_tangent;
    \\in vec3 v_world_bitangent;
    \\
    \\uniform vec4 u_base_color;
    \\uniform sampler2D u_overlay_tex;
    \\uniform sampler2D u_normal_tex;
    \\uniform vec3 u_camera_pos;
    \\uniform vec3 u_light_pos;
    \\uniform vec3 u_light_color;
    \\uniform vec2 u_uv_scale;
    \\uniform float u_normal_strength;
    \\uniform float u_parallax_strength;
    \\uniform float u_shadow_strength;
    \\uniform int u_use_overlay;
    \\uniform int u_use_normal_map;
    \\uniform int u_sign_style;
    \\uniform int u_overlay_material_paint;
    \\
    \\out vec4 out_color;
    \\
    \\float rectMask(vec2 uv, vec4 rect) {
    \\    vec2 aa = max(fwidth(uv) * 1.5, vec2(0.001));
    \\    vec2 lo = smoothstep(rect.xy, rect.xy + aa, uv);
    \\    vec2 hi = 1.0 - smoothstep(rect.zw - aa, rect.zw, uv);
    \\    return lo.x * lo.y * hi.x * hi.y;
    \\}
    \\
    \\float materialSelfShadow(vec2 uv, vec3 light_dir_ts, float height, float strength) {
    \\    if (strength <= 0.0) return 1.0;
    \\    float grazing = 1.0 - clamp(light_dir_ts.z, 0.0, 1.0);
    \\    vec2 dir = normalize(light_dir_ts.xy + vec2(0.0001, -0.0002));
    \\    float occlusion = 0.0;
    \\    for (int i = 1; i <= 5; i++) {
    \\        float fi = float(i);
    \\        float sample_h = texture(u_normal_tex, uv + dir * fi * 0.018).a;
    \\        sample_h = clamp((sample_h - 0.5) * 1.42 + 0.5, 0.0, 1.0);
    \\        float ridge = sample_h - height - fi * 0.020;
    \\        float reach = 1.0 - fi / 6.0;
    \\        occlusion += smoothstep(0.015, 0.090, ridge) * reach;
    \\    }
    \\    float shadow = 1.0 - min(occlusion * mix(0.10, 0.26, grazing), 0.38);
    \\    return mix(1.0, shadow, clamp(strength, 0.0, 1.0));
    \\}
    \\
    \\void main() {
    \\    vec3 tangent = normalize(v_world_tangent);
    \\    vec3 bitangent = normalize(v_world_bitangent);
    \\    vec3 base_normal = normalize(v_world_normal);
    \\    mat3 tbn = mat3(tangent, bitangent, base_normal);
    \\    vec3 view_dir = normalize(u_camera_pos - v_world_pos);
    \\    vec3 to_light = u_light_pos - v_world_pos;
    \\    float dist = length(to_light);
    \\    vec3 light_dir = to_light / max(dist, 1e-4);
    \\    vec3 normal = base_normal;
    \\    float material_shadow = 1.0;
    \\    float material_cavity = 1.0;
    \\    vec2 detail_uv = v_uv * u_uv_scale;
    \\    vec2 paint_uv = v_uv;
    \\    vec2 overlay_uv = v_uv;
    \\    vec4 detail_texel = vec4(0.5, 0.5, 1.0, 0.5);
    \\    vec3 detail = vec3(0.0, 0.0, 1.0);
    \\    float height = 0.5;
    \\    if (u_use_normal_map != 0) {
    \\        vec3 view_dir_ts = normalize(vec3(
    \\            dot(view_dir, tangent),
    \\            dot(view_dir, bitangent),
    \\            dot(view_dir, base_normal)
    \\        ));
    \\        vec4 height_probe = texture(u_normal_tex, detail_uv);
    \\        height = clamp((height_probe.a - 0.5) * 1.42 + 0.5, 0.0, 1.0);
    \\        if (u_parallax_strength > 0.0) {
    \\            float facing = clamp(view_dir_ts.z, 0.0, 1.0);
    \\            float parallax_fade = smoothstep(0.30, 0.70, facing);
    \\            vec2 parallax_uv = (view_dir_ts.xy / max(facing, 0.35)) * ((height - 0.5) * u_parallax_strength * parallax_fade);
    \\            detail_uv -= parallax_uv;
    \\            if (abs(u_uv_scale.x) > 1e-4 && abs(u_uv_scale.y) > 1e-4) {
    \\                if (u_overlay_material_paint != 0) {
    \\                    overlay_uv -= parallax_uv / u_uv_scale;
    \\                }
    \\            }
    \\        }
    \\        detail_texel = texture(u_normal_tex, detail_uv);
    \\        height = clamp((detail_texel.a - 0.5) * 1.42 + 0.5, 0.0, 1.0);
    \\        detail = detail_texel.xyz * 2.0 - 1.0;
    \\        detail.xy *= 1.10;
    \\        vec3 mapped = detail;
    \\        mapped.xy *= u_normal_strength;
    \\        normal = normalize(tbn * normalize(mapped));
    \\        vec3 light_dir_ts = normalize(vec3(
    \\            dot(light_dir, tangent),
    \\            dot(light_dir, bitangent),
    \\            dot(light_dir, base_normal)
    \\        ));
    \\        material_shadow = materialSelfShadow(detail_uv, light_dir_ts, height, u_shadow_strength);
    \\        float low_spots = 1.0 - smoothstep(0.22, 0.70, height);
    \\        material_cavity = mix(1.0, 1.0 - low_spots * 0.40, clamp(u_shadow_strength, 0.0, 1.0));
    \\    }
    \\
    \\    vec3 albedo = u_base_color.rgb;
    \\    if (u_use_normal_map != 0) {
    \\        float plaster = mix(0.76, 1.20, height);
    \\        plaster += detail.x * 0.05 + detail.y * 0.04;
    \\        albedo *= clamp(plaster, 0.72, 1.20);
    \\    }
    \\    if (u_sign_style != 0) {
    \\        float panel = rectMask(v_uv, vec4(0.035, 0.13, 0.965, 0.90));
    \\        float top_rule = rectMask(v_uv, vec4(0.058, 0.835, 0.942, 0.846));
    \\        float bottom_rule = rectMask(v_uv, vec4(0.058, 0.224, 0.942, 0.231));
    \\        float tab = rectMask(v_uv, vec4(0.062, 0.650, 0.230, 0.772));
    \\        float divider = rectMask(v_uv, vec4(0.275, 0.706, 0.882, 0.713));
    \\        float lamp = rectMask(v_uv, vec4(0.868, 0.692, 0.900, 0.780));
    \\        vec3 panel_color = mix(vec3(0.20, 0.24, 0.28), vec3(0.35, 0.39, 0.42), clamp(v_uv.y, 0.0, 1.0));
    \\        albedo = mix(albedo, panel_color, panel);
    \\        albedo = mix(albedo, vec3(0.88, 0.62, 0.26), top_rule);
    \\        albedo = mix(albedo, vec3(0.52, 0.60, 0.64), bottom_rule);
    \\        albedo = mix(albedo, vec3(0.76, 0.42, 0.12), tab);
    \\        albedo = mix(albedo, vec3(0.64, 0.70, 0.74), divider);
    \\        albedo = mix(albedo, vec3(0.86, 0.58, 0.24), lamp);
    \\    }
    \\    if (u_use_overlay != 0) {
    \\        vec4 overlay = texture(u_overlay_tex, overlay_uv);
    \\        if (overlay.a > 1.0 / 255.0) {
    \\            vec3 paint_color = overlay.rgb / max(overlay.a, 1e-4);
    \\            if (u_overlay_material_paint != 0) {
    \\                vec3 surface_tint = albedo / max(u_base_color.rgb, vec3(1e-4));
    \\                float rough_variation = clamp(0.68 + height * 0.46 + detail.x * 0.10 + detail.y * 0.08, 0.52, 1.24);
    \\                float porous_cover = clamp(0.83 + (height - 0.5) * 0.32, 0.68, 1.0);
    \\                vec3 painted = clamp(paint_color * surface_tint * rough_variation, 0.0, 1.0);
    \\                albedo = mix(albedo, painted, overlay.a * porous_cover);
    \\            } else {
    \\                float decal_variation = clamp(0.93 + height * 0.11 + detail.x * 0.015 + detail.y * 0.015, 0.88, 1.06);
    \\                albedo = mix(albedo, clamp(paint_color * decal_variation, 0.0, 1.0), overlay.a);
    \\            }
    \\        }
    \\    }
    \\
    \\    vec3 half_vec = normalize(light_dir + view_dir);
    \\
    \\    float diffuse = max(dot(normal, light_dir), 0.0);
    \\    float specular = pow(max(dot(normal, half_vec), 0.0), 28.0) * 0.10;
    \\    float attenuation = 1.0 / (1.0 + 0.10 * dist + 0.035 * dist * dist);
    \\    float hemi = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
    \\    vec3 ambient = mix(vec3(0.19, 0.21, 0.24), vec3(0.35, 0.34, 0.31), hemi);
    \\    vec3 fill_dir = normalize(vec3(0.45, 0.65, 0.35));
    \\    vec3 cool_fill = vec3(0.13, 0.17, 0.22) * max(dot(normal, fill_dir), 0.0);
    \\    vec3 back_dir = normalize(vec3(-0.25, 0.35, -0.90));
    \\    vec3 wall_bounce = vec3(0.10, 0.09, 0.075) * max(dot(normal, back_dir), 0.0);
    \\    vec3 indirect = (ambient + cool_fill + wall_bounce) * material_cavity;
    \\    vec3 direct = (diffuse * 1.10 * material_shadow + specular * mix(0.45, 1.0, material_shadow)) * attenuation * u_light_color;
    \\    out_color = vec4(albedo * (indirect + direct), 1.0);
    \\}
;

const premult_texture_fragment_shader: [:0]const u8 =
    \\#version 330 core
    \\in vec2 v_uv;
    \\in vec3 v_world_pos;
    \\in vec3 v_world_normal;
    \\
    \\uniform sampler2D u_tex;
    \\uniform vec3 u_camera_pos;
    \\uniform vec3 u_light_pos;
    \\uniform vec3 u_light_color;
    \\uniform int u_enable_lighting;
    \\
    \\out vec4 out_color;
    \\
    \\void main() {
    \\    vec4 texel = texture(u_tex, v_uv);
    \\    if (texel.a <= 1.0 / 255.0) discard;
    \\
    \\    vec3 rgb = texel.rgb;
    \\    if (u_enable_lighting != 0) {
    \\        vec3 normal = normalize(v_world_normal);
    \\        vec3 to_light = u_light_pos - v_world_pos;
    \\        float dist = length(to_light);
    \\        vec3 light_dir = to_light / max(dist, 1e-4);
    \\        vec3 view_dir = normalize(u_camera_pos - v_world_pos);
    \\        vec3 half_vec = normalize(light_dir + view_dir);
    \\        float diffuse = max(dot(normal, light_dir), 0.0);
    \\        float specular = pow(max(dot(normal, half_vec), 0.0), 28.0) * 0.09;
    \\        float attenuation = 1.0 / (1.0 + 0.10 * dist + 0.035 * dist * dist);
    \\        float hemi = clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
    \\        vec3 ambient = mix(vec3(0.19, 0.21, 0.24), vec3(0.35, 0.34, 0.31), hemi);
    \\        vec3 fill_dir = normalize(vec3(0.45, 0.65, 0.35));
    \\        vec3 cool_fill = vec3(0.13, 0.17, 0.22) * max(dot(normal, fill_dir), 0.0);
    \\        rgb *= ambient + cool_fill + (diffuse * 1.05 + specular) * attenuation * u_light_color;
    \\    }
    \\    out_color = vec4(rgb, texel.a);
    \\}
;

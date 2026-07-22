#version 300 es

precision highp float;
precision highp int;

struct VsOutput {
    vec4 position;
    vec2 uv;
};
struct VertexOutput {
    vec4 member;
    vec2 member_1;
};
int global = 0;

vec4 global_1 = vec4(0.0, 0.0, 0.0, 1.0);

vec2 entryPointParam_vertexMain_u002e_uv = vec2(0.0);

smooth out vec2 _vs2fs_location0;

void vertexMain() {
    float local = 0.0;
    float local_1 = 0.0;
    VsOutput o = VsOutput(vec4(0.0), vec2(0.0));
    int _e14 = global;
    if ((_e14 == 1)) {
        local = 3.0;
    } else {
        local = -1.0;
    }
    if ((_e14 == 2)) {
        local_1 = 3.0;
    } else {
        local_1 = -1.0;
    }
    float _e17 = local;
    float _e18 = local_1;
    vec2 _e19 = vec2(_e17, _e18);
    o.uv = ((_e19 * 0.5) + vec2(0.5));
    o.position = vec4(_e19, 0.0, 1.0);
    VsOutput _e26 = o;
    global_1 = _e26.position;
    entryPointParam_vertexMain_u002e_uv = _e26.uv;
    return;
}

void main() {
    uint param = uint(gl_VertexID);
    global = int(param);
    vertexMain();
    vec4 _e5 = global_1;
    vec2 _e6 = entryPointParam_vertexMain_u002e_uv;
    VertexOutput _tmp_return = VertexOutput(_e5, _e6);
    gl_Position = _tmp_return.member;
    _vs2fs_location0 = _tmp_return.member_1;
    return;
}


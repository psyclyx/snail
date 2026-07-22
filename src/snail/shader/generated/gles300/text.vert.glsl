#version 300 es

const vec2 _123[4] = vec2[](vec2(0.0), vec2(1.0, 0.0), vec2(1.0), vec2(0.0, 1.0));

layout(std140) uniform SnailPushConstants_std140
{
    layout(row_major) mat4 mvp;
    vec2 viewport;
    int subpixel_order;
    int output_srgb;
    int layer_base;
    float coverage_exponent;
    float dither_scale;
    int mask_output;
} pc;

layout(location = 0) in vec4 input_rect;
layout(location = 1) in vec4 input_xform;
layout(location = 2) in vec2 input_origin;
layout(location = 3) in uvec2 input_glyph;
layout(location = 4) in vec4 input_bnd;
layout(location = 5) in vec4 input_col;
layout(location = 6) in vec4 input_tint;
out vec4 snail_io0;
out vec2 snail_io1;
flat out vec4 snail_io2;
flat out ivec4 snail_io3;
out vec4 snail_io4;

highp mat4 spvWorkaroundRowMajor(highp mat4 wrap) { return wrap; }
mediump mat4 spvWorkaroundRowMajorMP(mediump mat4 wrap) { return wrap; }

void main()
{
    uint _17 = uint(gl_VertexID);
    vec2 _450 = mix(input_rect.xy, input_rect.zw, _123[_17]);
    vec2 _453 = (_123[_17] * 2.0) - vec2(1.0);
    float _461 = _450.x;
    float _464 = _450.y;
    vec2 _476 = vec2(((input_xform.x * _461) + (input_xform.y * _464)) + input_origin.x, ((input_xform.z * _461) + (input_xform.w * _464)) + input_origin.y);
    float _477 = _453.x;
    float _479 = _453.y;
    float _489 = 1.0 / ((input_xform.x * input_xform.w) - (input_xform.y * input_xform.z));
    ivec4 _694 = ivec4(int(input_glyph.x & 65535u), int(input_glyph.x >> 16u), int(input_glyph.y & 65535u), int(input_glyph.y >> 16u));
    vec4 _693 = input_bnd;
    float _599;
    if (input_col.x <= 0.040449999272823333740234375)
    {
        _599 = input_col.x * 0.077399380505084991455078125;
    }
    else
    {
        _599 = pow((input_col.x + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _611;
    if (input_col.y <= 0.040449999272823333740234375)
    {
        _611 = input_col.y * 0.077399380505084991455078125;
    }
    else
    {
        _611 = pow((input_col.y + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _623;
    if (input_col.z <= 0.040449999272823333740234375)
    {
        _623 = input_col.z * 0.077399380505084991455078125;
    }
    else
    {
        _623 = pow((input_col.z + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec4 _690 = vec4(vec3(_599, _611, _623), input_col.w);
    float _644;
    if (input_tint.x <= 0.040449999272823333740234375)
    {
        _644 = input_tint.x * 0.077399380505084991455078125;
    }
    else
    {
        _644 = pow((input_tint.x + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _656;
    if (input_tint.y <= 0.040449999272823333740234375)
    {
        _656 = input_tint.y * 0.077399380505084991455078125;
    }
    else
    {
        _656 = pow((input_tint.y + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    float _668;
    if (input_tint.z <= 0.040449999272823333740234375)
    {
        _668 = input_tint.z * 0.077399380505084991455078125;
    }
    else
    {
        _668 = pow((input_tint.z + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
    }
    vec4 _691 = vec4(vec3(_644, _656, _668), input_tint.w);
    vec2 _528 = normalize(vec2((input_xform.x * _477) + (input_xform.y * _479), (input_xform.z * _477) + (input_xform.w * _479)));
    float _532 = dot(spvWorkaroundRowMajor(pc.mvp)[3].xy, _476) + spvWorkaroundRowMajor(pc.mvp)[3].w;
    float _533 = dot(spvWorkaroundRowMajor(pc.mvp)[3].xy, _528);
    float _543 = ((_532 * dot(spvWorkaroundRowMajor(pc.mvp)[0].xy, _528)) - (_533 * (dot(spvWorkaroundRowMajor(pc.mvp)[0].xy, _476) + spvWorkaroundRowMajor(pc.mvp)[0].w))) * pc.viewport.x;
    float _553 = ((_532 * dot(spvWorkaroundRowMajor(pc.mvp)[1].xy, _528)) - (_533 * (dot(spvWorkaroundRowMajor(pc.mvp)[1].xy, _476) + spvWorkaroundRowMajor(pc.mvp)[1].w))) * pc.viewport.y;
    float _555 = _532 * _533;
    float _558 = (_543 * _543) + (_553 * _553);
    float _560 = _558 - (_555 * _555);
    vec2 _441;
    if (abs(_560) > 1.0000000133514319600180897396058e-10)
    {
        _441 = _528 * (((_532 * _532) * (_555 + sqrt(_558))) / _560);
    }
    else
    {
        _441 = (_528 * 2.0) / pc.viewport;
    }
    float _680;
    if (pc.subpixel_order == 0)
    {
        _680 = 1.0;
    }
    else
    {
        _680 = 2.3333332538604736328125;
    }
    vec2 _575 = _441 * (1.41421353816986083984375 * _680);
    gl_Position = vec4(_476 + _575, 0.0, 1.0) * spvWorkaroundRowMajor(pc.mvp);
    snail_io0 = _690;
    snail_io1 = vec2(_461 + dot(_575, vec2(input_xform.w * _489, (-input_xform.y) * _489)), _464 + dot(_575, vec2((-input_xform.z) * _489, input_xform.x * _489)));
    snail_io2 = _693;
    snail_io3 = _694;
    snail_io4 = _691;
}


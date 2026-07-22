#version 330

const vec2 _247[4] = vec2[](vec2(0.0), vec2(1.0, 0.0), vec2(1.0), vec2(0.0, 1.0));

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

uniform sampler2D SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler;

layout(location = 0) in vec4 input_rect;
layout(location = 1) in vec4 input_xform;
layout(location = 2) in vec2 input_origin;
layout(location = 3) in uvec2 input_glyph;
layout(location = 4) in vec4 input_bnd;
layout(location = 5) in vec4 input_col;
layout(location = 6) in vec4 input_tint;
layout(location = 7) in uvec4 input_policy0;
layout(location = 8) in uvec3 input_policy1;
out vec4 snail_io0;
out vec3 snail_io1;
flat out ivec2 snail_io2;
flat out uvec4 snail_io3;
flat out uvec3 snail_io4;
flat out vec4 snail_io5;
flat out vec4 snail_io6;
flat out vec4 snail_io7;
flat out vec4 snail_io8;
flat out vec4 snail_io9;
flat out vec4 snail_io10;
flat out vec4 snail_io11;
flat out vec4 snail_io12;
flat out uvec4 snail_io13;
flat out uvec4 snail_io14;

mat4 spvWorkaroundRowMajor(mat4 wrap) { return wrap; }

void main()
{
    bool _7130 = false;
    bool _5258 = false;
    uint _19 = uint(gl_VertexID);
    vec4 _9497 = input_rect;
    vec4 _9498 = input_xform;
    vec2 _9499 = input_origin;
    uvec2 _9500 = input_glyph;
    vec4 _9501 = input_bnd;
    vec4 _9502 = input_col;
    vec4 _9503 = input_tint;
    vec4 _9214;
    vec4 _9215;
    vec3 _9216;
    ivec2 _9217;
    uvec4 _9218;
    uvec3 _9219;
    uvec4 _9222;
    uvec4 _9223;
    vec4 _9611;
    vec4 _9612;
    vec4 _9613;
    vec4 _9614;
    vec4 _9636;
    vec4 _9637;
    vec4 _9638;
    vec4 _9639;
    do
    {
        vec2 _4077 = mix(_9497.xy, _9497.zw, _247[_19]);
        vec2 _4080 = (_247[_19] * 2.0) - vec2(1.0);
        float _4088 = _4077.x;
        float _4091 = _4077.y;
        vec2 _4103 = vec2(((_9498.x * _4088) + (_9498.y * _4091)) + _9499.x, ((_9498.z * _4088) + (_9498.w * _4091)) + _9499.y);
        float _4104 = _4080.x;
        float _4106 = _4080.y;
        float _4116 = 1.0 / ((_9498.x * _9498.w) - (_9498.y * _9498.z));
        float _4225;
        if (_9502.x <= 0.040449999272823333740234375)
        {
            _4225 = _9502.x * 0.077399380505084991455078125;
        }
        else
        {
            _4225 = pow((_9502.x + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
        }
        float _4237;
        if (_9502.y <= 0.040449999272823333740234375)
        {
            _4237 = _9502.y * 0.077399380505084991455078125;
        }
        else
        {
            _4237 = pow((_9502.y + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
        }
        float _4249;
        if (_9502.z <= 0.040449999272823333740234375)
        {
            _4249 = _9502.z * 0.077399380505084991455078125;
        }
        else
        {
            _4249 = pow((_9502.z + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
        }
        vec4 _9187 = vec4(vec3(_4225, _4237, _4249), _9502.w);
        float _4270;
        if (_9503.x <= 0.040449999272823333740234375)
        {
            _4270 = _9503.x * 0.077399380505084991455078125;
        }
        else
        {
            _4270 = pow((_9503.x + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
        }
        float _4282;
        if (_9503.y <= 0.040449999272823333740234375)
        {
            _4282 = _9503.y * 0.077399380505084991455078125;
        }
        else
        {
            _4282 = pow((_9503.y + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
        }
        float _4294;
        if (_9503.z <= 0.040449999272823333740234375)
        {
            _4294 = _9503.z * 0.077399380505084991455078125;
        }
        else
        {
            _4294 = pow((_9503.z + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
        }
        vec4 _9188 = vec4(vec3(_4270, _4282, _4294), _9503.w);
        vec2 _4155 = normalize(vec2((_9498.x * _4104) + (_9498.y * _4106), (_9498.z * _4104) + (_9498.w * _4106)));
        float _4159 = dot(spvWorkaroundRowMajor(pc.mvp)[3].xy, _4103) + spvWorkaroundRowMajor(pc.mvp)[3].w;
        float _4160 = dot(spvWorkaroundRowMajor(pc.mvp)[3].xy, _4155);
        float _4170 = ((_4159 * dot(spvWorkaroundRowMajor(pc.mvp)[0].xy, _4155)) - (_4160 * (dot(spvWorkaroundRowMajor(pc.mvp)[0].xy, _4103) + spvWorkaroundRowMajor(pc.mvp)[0].w))) * pc.viewport.x;
        float _4180 = ((_4159 * dot(spvWorkaroundRowMajor(pc.mvp)[1].xy, _4155)) - (_4160 * (dot(spvWorkaroundRowMajor(pc.mvp)[1].xy, _4103) + spvWorkaroundRowMajor(pc.mvp)[1].w))) * pc.viewport.y;
        float _4182 = _4159 * _4160;
        float _4185 = (_4170 * _4170) + (_4180 * _4180);
        float _4187 = _4185 - (_4182 * _4182);
        vec2 _4068;
        if (abs(_4187) > 1.0000000133514319600180897396058e-10)
        {
            _4068 = _4155 * (((_4159 * _4159) * (_4182 + sqrt(_4185))) / _4187);
        }
        else
        {
            _4068 = (_4155 * 2.0) / pc.viewport;
        }
        float _4306;
        if (pc.subpixel_order == 0)
        {
            _4306 = 1.0;
        }
        else
        {
            _4306 = 2.3333332538604736328125;
        }
        vec2 _4202 = _4068 * (1.41421353816986083984375 * _4306);
        vec4 _9275 = vec4(_4103 + _4202, 0.0, 1.0) * spvWorkaroundRowMajor(pc.mvp);
        vec4 _9276 = _9187 * _9188;
        vec3 _9277 = vec3(vec2(_4088 + dot(_4202, vec2(_9498.w * _4116, (-_9498.y) * _4116)), _4091 + dot(_4202, vec2((-_9498.z) * _4116, _9498.x * _4116))), _9501.w);
        ivec2 _9278 = ivec2(int(_9500.x & 65535u), int(_9500.x >> 16u));
        uvec4 _9279 = input_policy0;
        uvec3 _9280 = input_policy1;
        vec4 _9281[4];
        vec4 _9282[4];
        uvec4 _9283;
        uvec4 _9284;
        if (_19 != 0u)
        {
            int _3834 = 0;
            for (;;)
            {
                if (!(_3834 < 4))
                {
                    break;
                }
                _9281[_3834] = vec4(0.0);
                _9282[_3834] = vec4(0.0);
                _3834++;
                continue;
            }
            _9283 = uvec4(4294967295u);
            _9284 = uvec4(4294967295u);
            _9214 = _9275;
            _9215 = _9276;
            _9216 = _9277;
            _9217 = _9278;
            _9218 = _9279;
            _9219 = _9280;
            _9611 = _9281[0];
            _9612 = _9281[1];
            _9613 = _9281[2];
            _9614 = _9281[3];
            _9636 = _9282[0];
            _9637 = _9282[1];
            _9638 = _9282[2];
            _9639 = _9282[3];
            _9222 = uvec4(4294967295u);
            _9223 = uvec4(4294967295u);
            break;
        }
        vec2 _3835;
        bool _4316;
        do
        {
            _3835 = vec2(0.0);
            bool _4317;
            if (abs(spvWorkaroundRowMajor(pc.mvp)[3].x) > 1.0000000116860974230803549289703e-07)
            {
                _4317 = true;
            }
            else
            {
                _4317 = abs(spvWorkaroundRowMajor(pc.mvp)[3].y) > 1.0000000116860974230803549289703e-07;
            }
            if (_4317)
            {
                _4317 = true;
            }
            else
            {
                bool _4426;
                if (!isnan(spvWorkaroundRowMajor(pc.mvp)[3].w))
                {
                    _4426 = !isinf(spvWorkaroundRowMajor(pc.mvp)[3].w);
                }
                else
                {
                    _4426 = false;
                }
                _4317 = !_4426;
            }
            if (_4317)
            {
                _4317 = true;
            }
            else
            {
                _4317 = abs(spvWorkaroundRowMajor(pc.mvp)[3].w) < 1.0000000133514319600180897396058e-10;
            }
            if (_4317)
            {
                _4316 = false;
                break;
            }
            vec2 _4352 = vec2(_9498.xz);
            vec2 _4355 = vec2(_9498.yw);
            vec2 _4356 = pc.viewport * 0.5;
            vec2 _4365 = (_4356 * vec2(dot(spvWorkaroundRowMajor(pc.mvp)[0].xy, _4352), dot(spvWorkaroundRowMajor(pc.mvp)[1].xy, _4352))) / vec2(spvWorkaroundRowMajor(pc.mvp)[3].w);
            vec2 _4371 = (_4356 * vec2(dot(spvWorkaroundRowMajor(pc.mvp)[0].xy, _4355), dot(spvWorkaroundRowMajor(pc.mvp)[1].xy, _4355))) / vec2(spvWorkaroundRowMajor(pc.mvp)[3].w);
            float _4372 = _4365.x;
            float _4373 = _4371.y;
            float _4375 = _4371.x;
            float _4376 = _4365.y;
            float _4378 = (_4372 * _4373) - (_4375 * _4376);
            bool _4437;
            if (!isnan(_4378))
            {
                _4437 = !isinf(_4378);
            }
            else
            {
                _4437 = false;
            }
            if (!_4437)
            {
                _4317 = true;
            }
            else
            {
                _4317 = abs(_4378) < 1.0000000133514319600180897396058e-10;
            }
            if (_4317)
            {
                _4316 = false;
                break;
            }
            float _4392 = abs(_4378);
            vec2 _4400 = vec2(1.0) / vec2((abs(_4373) + abs(_4375)) / _4392, (abs(_4376) + abs(_4372)) / _4392);
            _3835 = _4400;
            float _4401 = _4400.x;
            bool _4448;
            if (!isnan(_4401))
            {
                _4448 = !isinf(_4401);
            }
            else
            {
                _4448 = false;
            }
            if (_4448)
            {
                bool _4459;
                if (!isnan(_3835.y))
                {
                    _4459 = !isinf(_3835.y);
                }
                else
                {
                    _4459 = false;
                }
                _4317 = _4459;
            }
            else
            {
                _4317 = false;
            }
            if (_4317)
            {
                _4317 = _3835.x > 0.0;
            }
            else
            {
                _4317 = false;
            }
            if (_4317)
            {
                _4317 = _3835.y > 0.0;
            }
            else
            {
                _4317 = false;
            }
            _4316 = _4317;
            break;
        } while(false);
        if (!_4316)
        {
            vec4 _3836[4] = _9281;
            int _4470 = 0;
            for (;;)
            {
                if (!(_4470 < 4))
                {
                    break;
                }
                _3836[_4470] = vec4(0.0);
                _4470++;
                continue;
            }
            uvec4 _9692 = uvec4(4294967295u);
            _9692.x = 4294967294u;
            _9281 = _3836;
            _9283 = _9692;
            vec4 _3838[4] = _9282;
            int _4492 = 0;
            for (;;)
            {
                if (!(_4492 < 4))
                {
                    break;
                }
                _3838[_4492] = vec4(0.0);
                _4492++;
                continue;
            }
            uvec4 _9694 = uvec4(4294967295u);
            _9694.x = 4294967294u;
            _9282 = _3838;
            _9284 = _9694;
            _9214 = _9275;
            _9215 = _9276;
            _9216 = _9277;
            _9217 = _9278;
            _9218 = _9279;
            _9219 = _9280;
            _9611 = _9281[0];
            _9612 = _9281[1];
            _9613 = _9281[2];
            _9614 = _9281[3];
            _9636 = _3838[0];
            _9637 = _3838[1];
            _9638 = _3838[2];
            _9639 = _3838[3];
            _9222 = _9283;
            _9223 = _9694;
            break;
        }
        int _3841 = 0;
        int _3842 = 0;
        int _4552 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
        int _4557 = ((_9278.y * _4552) + _9278.x) + 2;
        vec4 _4523 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_4557 - _4552 * (_4557 / _4552), _4557 / _4552), 0).xy, 0);
        float _4514;
        if (true)
        {
            _4514 = _4523.x;
        }
        else
        {
            if (false)
            {
                _4514 = _4523.y;
            }
            else
            {
                if (false)
                {
                    _4514 = _4523.z;
                }
                else
                {
                    _4514 = _4523.w;
                }
            }
        }
        int _4599 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
        int _4604 = ((_9278.y * _4599) + _9278.x) + 2;
        vec4 _4570 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_4604 - _4599 * (_4604 / _4599), _4604 / _4599), 0).xy, 0);
        float _4561;
        if (false)
        {
            _4561 = _4570.x;
        }
        else
        {
            if (true)
            {
                _4561 = _4570.y;
            }
            else
            {
                if (false)
                {
                    _4561 = _4570.z;
                }
                else
                {
                    _4561 = _4570.w;
                }
            }
        }
        bool _4609;
        int _9329;
        int _9330;
        int _9331;
        int _9332;
        int _9333;
        int _9334;
        int _9335;
        int _9336;
        float _9337;
        float _9338;
        float _9339;
        float _9340;
        float _9341;
        float _9342;
        float _9343;
        do
        {
            _9329 = 0;
            _9330 = 0;
            _9331 = 0;
            _9332 = 0;
            _9333 = 0;
            _9334 = 0;
            _9335 = 0;
            _9336 = 0;
            _9337 = 0.0;
            _9338 = 0.0;
            _9339 = 0.0;
            _9340 = 0.0;
            _9341 = 0.0;
            _9342 = 0.0;
            _9343 = 0.0;
            bool _4610;
            if ((input_policy0.x & 4286578688u) != 0u)
            {
                _4610 = true;
            }
            else
            {
                _4610 = (input_policy0.y & 4294967232u) != 0u;
            }
            if (_4610)
            {
                _4609 = false;
                break;
            }
            int _4628 = int(input_policy0.x & 3u);
            _9329 = _4628;
            _9330 = int((input_policy0.x >> 2u) & 3u);
            _9331 = int((input_policy0.x >> 4u) & 3u);
            _9332 = int((input_policy0.x >> 6u) & 3u);
            _9336 = int((input_policy0.x >> 8u) & 1u);
            _9337 = float((input_policy0.x >> 9u) & 127u);
            _9338 = float((input_policy0.x >> 16u) & 127u);
            _9333 = int(input_policy0.y & 3u);
            _9334 = int((input_policy0.y >> 2u) & 3u);
            _9335 = int((input_policy0.y >> 4u) & 3u);
            if (_4628 > 1)
            {
                _4610 = true;
            }
            else
            {
                _4610 = _9330 > 2;
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                _4610 = _9331 > 1;
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                _4610 = _9332 > 1;
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                _4610 = _9333 > 2;
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                _4610 = _9334 > 2;
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                _4610 = _9335 > 1;
            }
            if (_4610)
            {
                _4609 = false;
                break;
            }
            _9339 = uintBitsToFloat(input_policy0.z);
            _9340 = uintBitsToFloat(input_policy0.w);
            _9341 = uintBitsToFloat(input_policy1.x);
            _9342 = uintBitsToFloat(input_policy1.y);
            _9343 = uintBitsToFloat(input_policy1.z);
            if (_9330 != 0)
            {
                bool _4826;
                if (!isnan(_9339))
                {
                    _4826 = !isinf(_9339);
                }
                else
                {
                    _4826 = false;
                }
                if (!_4826)
                {
                    _4610 = true;
                }
                else
                {
                    _4610 = _9339 < 0.0;
                }
            }
            else
            {
                _4610 = false;
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                if (_9330 == 1)
                {
                    bool _4837;
                    if (!isnan(_9340))
                    {
                        _4837 = !isinf(_9340);
                    }
                    else
                    {
                        _4837 = false;
                    }
                    if (!_4837)
                    {
                        _4610 = true;
                    }
                    else
                    {
                        _4610 = _9340 < 0.0;
                    }
                }
                else
                {
                    _4610 = false;
                }
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                if (_9334 != 0)
                {
                    bool _4848;
                    if (!isnan(_9341))
                    {
                        _4848 = !isinf(_9341);
                    }
                    else
                    {
                        _4848 = false;
                    }
                    if (!_4848)
                    {
                        _4610 = true;
                    }
                    else
                    {
                        _4610 = _9341 < 0.0;
                    }
                }
                else
                {
                    _4610 = false;
                }
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                if (_9334 == 1)
                {
                    bool _4859;
                    if (!isnan(_9342))
                    {
                        _4859 = !isinf(_9342);
                    }
                    else
                    {
                        _4859 = false;
                    }
                    if (!_4859)
                    {
                        _4610 = true;
                    }
                    else
                    {
                        _4610 = _9342 < 0.0;
                    }
                }
                else
                {
                    _4610 = false;
                }
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                if (_9335 == 1)
                {
                    bool _4870;
                    if (!isnan(_9343))
                    {
                        _4870 = !isinf(_9343);
                    }
                    else
                    {
                        _4870 = false;
                    }
                    if (!_4870)
                    {
                        _4610 = true;
                    }
                    else
                    {
                        _4610 = _9343 < 0.0;
                    }
                }
                else
                {
                    _4610 = false;
                }
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                if (_9331 == 1)
                {
                    _4610 = _9329 == 0;
                }
                else
                {
                    _4610 = false;
                }
            }
            if (_4610)
            {
                _4610 = true;
            }
            else
            {
                if (_9335 == 1)
                {
                    _4610 = _9333 != 2;
                }
                else
                {
                    _4610 = false;
                }
            }
            if (_4610)
            {
                _4609 = false;
                break;
            }
            _4609 = true;
            break;
        } while(false);
        bool _3844;
        if (_4609)
        {
            bool _4881;
            if (!isnan(_4514))
            {
                _4881 = !isinf(_4514);
            }
            else
            {
                _4881 = false;
            }
            _3844 = _4881;
        }
        else
        {
            _3844 = false;
        }
        if (_3844)
        {
            _3844 = _4514 >= 0.0;
        }
        else
        {
            _3844 = false;
        }
        if (_3844)
        {
            bool _4892;
            if (!isnan(_4561))
            {
                _4892 = !isinf(_4561);
            }
            else
            {
                _4892 = false;
            }
            _3844 = _4892;
        }
        else
        {
            _3844 = false;
        }
        if (_3844)
        {
            _3844 = _4561 >= 0.0;
        }
        else
        {
            _3844 = false;
        }
        if (_3844)
        {
            int _4941 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
            int _4946 = ((_9278.y * _4941) + _9278.x) + 2;
            vec4 _4912 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_4946 - _4941 * (_4946 / _4941), _4946 / _4941), 0).xy, 0);
            float _4903;
            if (false)
            {
                _4903 = _4912.x;
            }
            else
            {
                if (false)
                {
                    _4903 = _4912.y;
                }
                else
                {
                    if (true)
                    {
                        _4903 = _4912.z;
                    }
                    else
                    {
                        _4903 = _4912.w;
                    }
                }
            }
            bool _4951;
            do
            {
                bool _4980;
                if (!isnan(_4903))
                {
                    _4980 = !isinf(_4903);
                }
                else
                {
                    _4980 = false;
                }
                bool _4952;
                if (!_4980)
                {
                    _4952 = true;
                }
                else
                {
                    _4952 = _4903 < 0.0;
                }
                if (_4952)
                {
                    _4952 = true;
                }
                else
                {
                    _4952 = _4903 > 16.0;
                }
                if (_4952)
                {
                    _4952 = true;
                }
                else
                {
                    _4952 = floor(_4903) != _4903;
                }
                if (_4952)
                {
                    _3841 = 0;
                    _4951 = false;
                    break;
                }
                _3841 = int(_4903);
                _4951 = true;
                break;
            } while(false);
            _3844 = _4951;
        }
        else
        {
            _3844 = false;
        }
        int _3975 = 2 * _3841;
        int _3976 = 12 + _3975;
        if (_3844)
        {
            int _5029 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
            int _5034 = ((_9278.y * _5029) + _9278.x) + (_3976 >> 2);
            vec4 _5000 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_5034 - _5029 * (_5034 / _5029), _5034 / _5029), 0).xy, 0);
            int _5002 = _3975 & 3;
            float _4991;
            if (_5002 == 0)
            {
                _4991 = _5000.x;
            }
            else
            {
                if (_5002 == 1)
                {
                    _4991 = _5000.y;
                }
                else
                {
                    if (_5002 == 2)
                    {
                        _4991 = _5000.z;
                    }
                    else
                    {
                        _4991 = _5000.w;
                    }
                }
            }
            bool _5039;
            do
            {
                bool _5068;
                if (!isnan(_4991))
                {
                    _5068 = !isinf(_4991);
                }
                else
                {
                    _5068 = false;
                }
                bool _5040;
                if (!_5068)
                {
                    _5040 = true;
                }
                else
                {
                    _5040 = _4991 < 0.0;
                }
                if (_5040)
                {
                    _5040 = true;
                }
                else
                {
                    _5040 = _4991 > 16.0;
                }
                if (_5040)
                {
                    _5040 = true;
                }
                else
                {
                    _5040 = floor(_4991) != _4991;
                }
                if (_5040)
                {
                    _3842 = 0;
                    _5039 = false;
                    break;
                }
                _3842 = int(_4991);
                _5039 = true;
                break;
            } while(false);
            _3844 = _5039;
        }
        else
        {
            _3844 = false;
        }
        int _3986 = (_3975 + 13) + (4 * _3842);
        if (_3844)
        {
            int _5117 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
            int _5122 = ((_9278.y * _5117) + _9278.x) + (_3986 >> 2);
            vec4 _5088 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_5122 - _5117 * (_5122 / _5117), _5122 / _5117), 0).xy, 0);
            int _5090 = _3986 & 3;
            float _5079;
            if (_5090 == 0)
            {
                _5079 = _5088.x;
            }
            else
            {
                if (_5090 == 1)
                {
                    _5079 = _5088.y;
                }
                else
                {
                    if (_5090 == 2)
                    {
                        _5079 = _5088.z;
                    }
                    else
                    {
                        _5079 = _5088.w;
                    }
                }
            }
            bool _5127;
            do
            {
                bool _5156;
                if (!isnan(_5079))
                {
                    _5156 = !isinf(_5079);
                }
                else
                {
                    _5156 = false;
                }
                bool _5128;
                if (!_5156)
                {
                    _5128 = true;
                }
                else
                {
                    _5128 = _5079 < 0.0;
                }
                if (_5128)
                {
                    _5128 = true;
                }
                else
                {
                    _5128 = _5079 > 16.0;
                }
                if (_5128)
                {
                    _5128 = true;
                }
                else
                {
                    _5128 = floor(_5079) != _5079;
                }
                if (_5128)
                {
                    _5127 = false;
                    break;
                }
                _5127 = true;
                break;
            } while(false);
            _3844 = _5127;
        }
        else
        {
            _3844 = false;
        }
        if (!_3844)
        {
            vec4 _3845[4] = _9281;
            int _5167 = 0;
            for (;;)
            {
                if (!(_5167 < 4))
                {
                    break;
                }
                _3845[_5167] = vec4(0.0);
                _5167++;
                continue;
            }
            uvec4 _9696 = uvec4(4294967295u);
            _9696.x = 4294967294u;
            _9281 = _3845;
            _9283 = _9696;
            vec4 _3847[4] = _9282;
            int _5189 = 0;
            for (;;)
            {
                if (!(_5189 < 4))
                {
                    break;
                }
                _3847[_5189] = vec4(0.0);
                _5189++;
                continue;
            }
            uvec4 _9698 = uvec4(4294967295u);
            _9698.x = 4294967294u;
            _9282 = _3847;
            _9284 = _9698;
            _9214 = _9275;
            _9215 = _9276;
            _9216 = _9277;
            _9217 = _9278;
            _9218 = _9279;
            _9219 = _9280;
            _9611 = _9281[0];
            _9612 = _9281[1];
            _9613 = _9281[2];
            _9614 = _9281[3];
            _9636 = _3847[0];
            _9637 = _3847[1];
            _9638 = _3847[2];
            _9639 = _3847[3];
            _9222 = _9283;
            _9223 = _9698;
            break;
        }
        int _3849 = 0;
        int _3850 = 0;
        int _5249 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
        int _5254 = ((_9278.y * _5249) + _9278.x) + 2;
        vec4 _5220 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_5254 - _5249 * (_5254 / _5249), _5254 / _5249), 0).xy, 0);
        float _5211;
        if (false)
        {
            _5211 = _5220.x;
        }
        else
        {
            if (false)
            {
                _5211 = _5220.y;
            }
            else
            {
                if (false)
                {
                    _5211 = _5220.z;
                }
                else
                {
                    _5211 = _5220.w;
                }
            }
        }
        int _9391 = _9329;
        int _9392 = _9330;
        int _9393 = _9331;
        int _9394 = _9332;
        int _9395 = _9333;
        int _9396 = _9334;
        int _9397 = _9335;
        int _9398 = _9336;
        float _9399 = _9337;
        float _9400 = _9338;
        float _9401 = _9339;
        float _9402 = _9340;
        float _9403 = _9341;
        float _9404 = _9342;
        float _9405 = _9343;
        _5258 = false;
        float _3852[16];
        int _3855[16];
        bool _5259;
        do
        {
            _3849 = 0;
            int _5260 = 0;
            float _3851[16];
            for (;;)
            {
                if (!(_5260 < 16))
                {
                    break;
                }
                _3851[_5260] = 0.0;
                _3852[_5260] = 0.0;
                _3855[_5260] = 0;
                _5260++;
                continue;
            }
            bool _6571;
            if (!isnan(_3835.x))
            {
                _6571 = !isinf(_3835.x);
            }
            else
            {
                _6571 = false;
            }
            bool _5261;
            if (!_6571)
            {
                _5261 = true;
            }
            else
            {
                _5261 = _3835.x <= 0.0;
            }
            if (_5261)
            {
                _5261 = true;
            }
            else
            {
                _5261 = _3841 < 0;
            }
            if (_5261)
            {
                _5261 = true;
            }
            else
            {
                _5261 = _3841 > 16;
            }
            if (_5261)
            {
                _5261 = true;
            }
            else
            {
                bool _6582;
                if (!isnan(_4514))
                {
                    _6582 = !isinf(_4514);
                }
                else
                {
                    _6582 = false;
                }
                _5261 = !_6582;
            }
            if (_5261)
            {
                _5261 = true;
            }
            else
            {
                _5261 = _4514 < 0.0;
            }
            if (_5261)
            {
                _5258 = true;
                _5259 = false;
                break;
            }
            if (true)
            {
                _5261 = _9391 == 0;
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                _5261 = _9392 == 0;
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                _5261 = _9393 == 0;
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                _5261 = _9394 == 0;
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                _5261 = true;
            }
            else
            {
                if (false)
                {
                    _5261 = _9395 == 0;
                }
                else
                {
                    _5261 = false;
                }
                if (_5261)
                {
                    _5261 = _9396 == 0;
                }
                else
                {
                    _5261 = false;
                }
                if (_5261)
                {
                    _5261 = _9397 == 0;
                }
                else
                {
                    _5261 = false;
                }
            }
            if (_5261)
            {
                _5258 = true;
                _5259 = true;
                break;
            }
            int _6631 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
            int _6636 = ((_9278.y * _6631) + _9278.x) + (_3976 >> 2);
            vec4 _6602 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_6636 - _6631 * (_6636 / _6631), _6636 / _6631), 0).xy, 0);
            int _6604 = _3975 & 3;
            float _6593;
            if (_6604 == 0)
            {
                _6593 = _6602.x;
            }
            else
            {
                if (_6604 == 1)
                {
                    _6593 = _6602.y;
                }
                else
                {
                    if (_6604 == 2)
                    {
                        _6593 = _6602.z;
                    }
                    else
                    {
                        _6593 = _6602.w;
                    }
                }
            }
            int _5412 = int(_6593);
            if (_5412 <= 0)
            {
                _5261 = true;
            }
            else
            {
                _5261 = _5412 > 16;
            }
            if (_5261)
            {
                _5258 = true;
                _5259 = _5412 == 0;
                break;
            }
            if (false)
            {
                _5261 = _9395 == 2;
            }
            else
            {
                _5261 = false;
            }
            bool _5262;
            if (true)
            {
                _5262 = _9394 == 1;
            }
            else
            {
                _5262 = false;
            }
            if (_5262)
            {
                bool _6640;
                if (!isnan(_5211))
                {
                    _6640 = !isinf(_5211);
                }
                else
                {
                    _6640 = false;
                }
                _5262 = !_6640;
            }
            else
            {
                _5262 = false;
            }
            if (_5262)
            {
                _5258 = true;
                _5259 = false;
                break;
            }
            _5260 = 0;
            float _5263[16];
            float _5264[16];
            int _5265[16];
            int _5266[16];
            bool _5267[16];
            bool _5268[16];
            int _5269[16];
            int _5270[16];
            bool _5272[16];
            int _5275;
            int _5276;
            bool _5277;
            bool _5278;
            bool _5279;
            bool _5280;
            bool _5281;
            bool _5282;
            bool _5283;
            uint _5284;
            float _6651;
            float _6698;
            float _6745;
            float _6792;
            bool _6839;
            bool _6850;
            for (;;)
            {
                if (!(_5260 < 16))
                {
                    break;
                }
                if (_5260 >= _5412)
                {
                    break;
                }
                int _5459 = (_3975 + 13) + (4 * _5260);
                int _6689 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _6694 = ((_9278.y * _6689) + _9278.x) + (_5459 >> 2);
                vec4 _6660 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_6694 - _6689 * (_6694 / _6689), _6694 / _6689), 0).xy, 0);
                int _6662 = _5459 & 3;
                if (_6662 == 0)
                {
                    _6651 = _6660.x;
                }
                else
                {
                    if (_6662 == 1)
                    {
                        _6651 = _6660.y;
                    }
                    else
                    {
                        if (_6662 == 2)
                        {
                            _6651 = _6660.z;
                        }
                        else
                        {
                            _6651 = _6660.w;
                        }
                    }
                }
                _5263[_5260] = _6651;
                int _6701 = _5459 + 1;
                int _6736 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _6741 = ((_9278.y * _6736) + _9278.x) + (_6701 >> 2);
                vec4 _6707 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_6741 - _6736 * (_6741 / _6736), _6741 / _6736), 0).xy, 0);
                int _6709 = _6701 & 3;
                if (_6709 == 0)
                {
                    _6698 = _6707.x;
                }
                else
                {
                    if (_6709 == 1)
                    {
                        _6698 = _6707.y;
                    }
                    else
                    {
                        if (_6709 == 2)
                        {
                            _6698 = _6707.z;
                        }
                        else
                        {
                            _6698 = _6707.w;
                        }
                    }
                }
                _5264[_5260] = _6698;
                int _6748 = _5459 + 2;
                int _6783 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _6788 = ((_9278.y * _6783) + _9278.x) + (_6748 >> 2);
                vec4 _6754 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_6788 - _6783 * (_6788 / _6783), _6788 / _6783), 0).xy, 0);
                int _6756 = _6748 & 3;
                if (_6756 == 0)
                {
                    _6745 = _6754.x;
                }
                else
                {
                    if (_6756 == 1)
                    {
                        _6745 = _6754.y;
                    }
                    else
                    {
                        if (_6756 == 2)
                        {
                            _6745 = _6754.z;
                        }
                        else
                        {
                            _6745 = _6754.w;
                        }
                    }
                }
                _5265[_5260] = int(floatBitsToUint(_6745) << 16u) >> 16;
                _5266[_5260] = floatBitsToInt(_6745) >> 16;
                int _6795 = _5459 + 3;
                int _6830 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _6835 = ((_9278.y * _6830) + _9278.x) + (_6795 >> 2);
                vec4 _6801 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_6835 - _6830 * (_6835 / _6830), _6835 / _6830), 0).xy, 0);
                int _6803 = _6795 & 3;
                if (_6803 == 0)
                {
                    _6792 = _6801.x;
                }
                else
                {
                    if (_6803 == 1)
                    {
                        _6792 = _6801.y;
                    }
                    else
                    {
                        if (_6803 == 2)
                        {
                            _6792 = _6801.z;
                        }
                        else
                        {
                            _6792 = _6801.w;
                        }
                    }
                }
                uint _5478 = floatBitsToUint(_6792);
                _5267[_5260] = (_5478 & 1u) != 0u;
                _5268[_5260] = (_5478 & 2u) != 0u;
                if ((_5478 & 4u) == 0u)
                {
                    _5258 = true;
                    _5259 = false;
                    break;
                }
                if ((_5478 & 8u) != 0u)
                {
                    _5275 = -1;
                }
                else
                {
                    _5275 = 1;
                }
                _5270[_5260] = _5275;
                if (_5261)
                {
                    _5284 = 10u;
                }
                else
                {
                    _5284 = 4u;
                }
                int _5507 = int((_5478 >> _5284) & 63u);
                if (_5507 >= 62)
                {
                    _5276 = -1;
                }
                else
                {
                    _5276 = _5507;
                }
                _5269[_5260] = _5276;
                if (_5507 >= 63)
                {
                    _5262 = _5267[_5260];
                }
                else
                {
                    _5262 = false;
                }
                if (_5262)
                {
                    _5277 = _5266[_5260] >= 0;
                }
                else
                {
                    _5277 = false;
                }
                if (_5277)
                {
                    _5258 = true;
                    _5259 = false;
                    break;
                }
                _5272[_5260] = false;
                if (!isnan(_5263[_5260]))
                {
                    _6839 = !isinf(_5263[_5260]);
                }
                else
                {
                    _6839 = false;
                }
                if (!_6839)
                {
                    _5278 = true;
                }
                else
                {
                    if (!isnan(_5264[_5260]))
                    {
                        _6850 = !isinf(_5264[_5260]);
                    }
                    else
                    {
                        _6850 = false;
                    }
                    _5278 = !_6850;
                }
                if (_5278)
                {
                    _5279 = true;
                }
                else
                {
                    _5279 = _5264[_5260] < 0.0;
                }
                if (_5279)
                {
                    _5280 = true;
                }
                else
                {
                    _5280 = _5265[_5260] < (-1);
                }
                if (_5280)
                {
                    _5281 = true;
                }
                else
                {
                    _5281 = _5265[_5260] >= _5412;
                }
                if (_5281)
                {
                    _5282 = true;
                }
                else
                {
                    _5282 = _5266[_5260] < (-1);
                }
                if (_5282)
                {
                    _5283 = true;
                }
                else
                {
                    _5283 = _5266[_5260] >= _3841;
                }
                if (_5283)
                {
                    _5258 = true;
                    _5259 = false;
                    break;
                }
                _5260++;
                continue;
            }
            if (_5258)
            {
                break;
            }
            _5260 = 0;
            float _6861;
            float _6908;
            bool _6955;
            bool _6966;
            for (;;)
            {
                if (!(_5260 < 16))
                {
                    break;
                }
                if (_5260 >= _3841)
                {
                    break;
                }
                int _5595 = 2 * _5260;
                int _6899 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _6904 = ((_9278.y * _6899) + _9278.x) + ((12 + _5595) >> 2);
                vec4 _6870 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_6904 - _6899 * (_6904 / _6899), _6904 / _6899), 0).xy, 0);
                int _6872 = _5595 & 3;
                if (_6872 == 0)
                {
                    _6861 = _6870.x;
                }
                else
                {
                    if (_6872 == 1)
                    {
                        _6861 = _6870.y;
                    }
                    else
                    {
                        if (_6872 == 2)
                        {
                            _6861 = _6870.z;
                        }
                        else
                        {
                            _6861 = _6870.w;
                        }
                    }
                }
                int _6911 = _5595 + 13;
                int _6946 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _6951 = ((_9278.y * _6946) + _9278.x) + (_6911 >> 2);
                vec4 _6917 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_6951 - _6946 * (_6951 / _6946), _6951 / _6946), 0).xy, 0);
                int _6919 = _6911 & 3;
                if (_6919 == 0)
                {
                    _6908 = _6917.x;
                }
                else
                {
                    if (_6919 == 1)
                    {
                        _6908 = _6917.y;
                    }
                    else
                    {
                        if (_6919 == 2)
                        {
                            _6908 = _6917.z;
                        }
                        else
                        {
                            _6908 = _6917.w;
                        }
                    }
                }
                if (!isnan(_6861))
                {
                    _6955 = !isinf(_6861);
                }
                else
                {
                    _6955 = false;
                }
                if (!_6955)
                {
                    _5262 = true;
                }
                else
                {
                    if (!isnan(_6908))
                    {
                        _6966 = !isinf(_6908);
                    }
                    else
                    {
                        _6966 = false;
                    }
                    _5262 = !_6966;
                }
                if (_5262)
                {
                    _5258 = true;
                    _5259 = false;
                    break;
                }
                _5260++;
                continue;
            }
            if (_5258)
            {
                break;
            }
            if (false)
            {
                _5262 = _9397 == 1;
            }
            else
            {
                _5262 = false;
            }
            float _5285;
            if (_5262)
            {
                _5285 = _9405;
            }
            else
            {
                _5285 = 0.0;
            }
            _5260 = 0;
            float _5271[16];
            float _6982;
            float _7029;
            for (;;)
            {
                if (!(_5260 < 16))
                {
                    break;
                }
                if (_5260 >= _5412)
                {
                    break;
                }
                if (_5265[_5260] >= 0)
                {
                    _5262 = _5263[_5265[_5260]] > _5263[_5260];
                }
                else
                {
                    _5262 = false;
                }
                if (_5261)
                {
                    _5277 = _5266[_5260] >= 0;
                }
                else
                {
                    _5277 = false;
                }
                if (!_5261)
                {
                    if (_5262)
                    {
                        _5275 = -1;
                    }
                    else
                    {
                        _5275 = 1;
                    }
                    _5270[_5260] = _5275;
                }
                if (_5277)
                {
                    int _5689 = 2 * _5266[_5260];
                    int _7020 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _7025 = ((_9278.y * _7020) + _9278.x) + ((12 + _5689) >> 2);
                    vec4 _6991 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7025 - _7020 * (_7025 / _7020), _7025 / _7020), 0).xy, 0);
                    int _6993 = _5689 & 3;
                    if (_6993 == 0)
                    {
                        _6982 = _6991.x;
                    }
                    else
                    {
                        if (_6993 == 1)
                        {
                            _6982 = _6991.y;
                        }
                        else
                        {
                            if (_6993 == 2)
                            {
                                _6982 = _6991.z;
                            }
                            else
                            {
                                _6982 = _6991.w;
                            }
                        }
                    }
                    int _7032 = (2 * _5266[_5260]) + 13;
                    int _7067 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _7072 = ((_9278.y * _7067) + _9278.x) + (_7032 >> 2);
                    vec4 _7038 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7072 - _7067 * (_7072 / _7067), _7072 / _7067), 0).xy, 0);
                    int _7040 = _7032 & 3;
                    if (_7040 == 0)
                    {
                        _7029 = _7038.x;
                    }
                    else
                    {
                        if (_7040 == 1)
                        {
                            _7029 = _7038.y;
                        }
                        else
                        {
                            if (_7040 == 2)
                            {
                                _7029 = _7038.z;
                            }
                            else
                            {
                                _7029 = _7038.w;
                            }
                        }
                    }
                    if (_5267[_5260])
                    {
                        _5278 = false;
                    }
                    else
                    {
                        _5278 = false;
                    }
                    if (_5278)
                    {
                        _5279 = _9397 == 0;
                    }
                    else
                    {
                        _5279 = false;
                    }
                    if (_5279)
                    {
                        _5271[_5260] = _5263[_5260];
                    }
                    else
                    {
                        _5271[_5260] = round(_6982 * _3835.x) / _3835.x;
                        if (_5267[_5260])
                        {
                            _5280 = abs((_7029 - _6982) * _3835.x) >= _5285;
                        }
                        else
                        {
                            _5280 = false;
                        }
                        if (_5280)
                        {
                            _5271[_5260] += (_7029 - _6982);
                        }
                    }
                }
                else
                {
                    _5271[_5260] = round(_5263[_5260] * _3835.x) / _3835.x;
                }
                _5260++;
                continue;
            }
            float _5742 = 1.0 / _3835.x;
            if (true)
            {
                _5275 = _9392;
            }
            else
            {
                _5275 = _9396;
            }
            if (true)
            {
                _5285 = _9401;
            }
            else
            {
                _5285 = _9403;
            }
            float _5286;
            if (true)
            {
                _5286 = _9402;
            }
            else
            {
                _5286 = _9404;
            }
            if (true)
            {
                _5261 = _9391 == 1;
            }
            else
            {
                _5261 = _9395 != 0;
            }
            if (true)
            {
                _5262 = _9393 == 1;
            }
            else
            {
                _5262 = false;
            }
            _5277 = false;
            float _5288 = 0.0;
            float _5289 = 0.0;
            float _5290 = 0.0;
            float _5291 = 0.0;
            float _5292 = 0.0;
            _5276 = 0;
            _5260 = 0;
            int _5287 = 0;
            int _5293;
            int _5294;
            float _5295;
            float _5296;
            float _5297;
            float _5298;
            float _5299;
            float _5300;
            bool _5301;
            bool _7081;
            float _7082;
            for (;;)
            {
                bool _5781_ladder_break = false;
                do
                {
                    if (!(_5260 < 16))
                    {
                        _5781_ladder_break = true;
                        break;
                    }
                    if (_5260 >= _5412)
                    {
                        _5781_ladder_break = true;
                        break;
                    }
                    if (_5265[_5260] < 0)
                    {
                        _5278 = true;
                    }
                    else
                    {
                        _5278 = _5265[_5260] <= _5260;
                    }
                    if (_5278)
                    {
                        _5280 = _5277;
                        break;
                    }
                    if (_4514 > 0.0)
                    {
                        _7081 = abs(_5264[_5260] - _4514) <= (_5285 * _4514);
                    }
                    else
                    {
                        _7081 = false;
                    }
                    if (_7081)
                    {
                        _7082 = _4514;
                    }
                    else
                    {
                        _7082 = _5264[_5260];
                    }
                    if (_5275 == 2)
                    {
                        _5279 = true;
                    }
                    else
                    {
                        if (_5275 == 1)
                        {
                            _5279 = (_7082 * _3835.x) < _5286;
                        }
                        else
                        {
                            _5279 = false;
                        }
                    }
                    if (_5279)
                    {
                        _5295 = max(round(_7082 * _3835.x), 1.0) * _5742;
                    }
                    else
                    {
                        _5295 = _5264[_5260];
                    }
                    if (_5262)
                    {
                        if (_5277)
                        {
                            _5271[_5260] = _5288 + (round((_5263[_5260] - _5289) * _3835.x) * _5742);
                            _5296 = _5290;
                            _5297 = _5291;
                            _5280 = _5277;
                        }
                        else
                        {
                            float _7102 = round(_5263[_5260] * _3835.x) / _3835.x;
                            _5271[_5260] = _7102;
                            _5296 = _7102;
                            _5297 = _5263[_5260];
                            _5280 = true;
                        }
                        _5271[_5265[_5260]] = _5271[_5260] + _5295;
                        float _5939 = _5297;
                        float _5944 = _5296;
                        _5296 = _5271[_5260];
                        _5297 = _5263[_5260];
                        _5298 = _5944;
                        _5299 = _5939;
                        _5300 = (_5944 + (round((_5263[_5260] - _5939) * _3835.x) * _5742)) + _5295;
                        _5293 = _5265[_5260];
                        _5294 = _5287 + 1;
                    }
                    else
                    {
                        if (true)
                        {
                            _5280 = _9391 != 0;
                        }
                        else
                        {
                            _5280 = _9395 != 0;
                        }
                        if (_5280)
                        {
                            _5281 = _5266[_5260] >= 0;
                        }
                        else
                        {
                            _5281 = false;
                        }
                        if (_5280)
                        {
                            _5282 = _5266[_5265[_5260]] >= 0;
                        }
                        else
                        {
                            _5282 = false;
                        }
                        if (!_5261)
                        {
                            _5271[_5260] = _5263[_5260];
                        }
                        if (_5282)
                        {
                            _5283 = !_5281;
                        }
                        else
                        {
                            _5283 = false;
                        }
                        if (_5283)
                        {
                            _5301 = _5261;
                        }
                        else
                        {
                            _5301 = false;
                        }
                        if (_5301)
                        {
                            _5271[_5260] = _5271[_5265[_5260]] - _5295;
                        }
                        else
                        {
                            _5271[_5265[_5260]] = _5271[_5260] + _5295;
                        }
                        _5280 = _5277;
                        _5296 = _5288;
                        _5297 = _5289;
                        _5298 = _5290;
                        _5299 = _5291;
                        _5300 = _5292;
                        _5293 = _5276;
                        _5294 = _5287;
                    }
                    _5272[_5260] = true;
                    _5272[_5265[_5260]] = true;
                    _5288 = _5296;
                    _5289 = _5297;
                    _5290 = _5298;
                    _5291 = _5299;
                    _5292 = _5300;
                    _5276 = _5293;
                    _5287 = _5294;
                    break;
                } while(false);
                if (_5781_ladder_break)
                {
                    break;
                }
                _5277 = _5280;
                _5260++;
                continue;
            }
            if (_5262)
            {
                _5261 = _5287 > 1;
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                float _5982 = _5292 - _5271[_5276];
                _5260 = 0;
                for (;;)
                {
                    if (!(_5260 < 16))
                    {
                        break;
                    }
                    if (_5260 >= _5412)
                    {
                        break;
                    }
                    if (_5272[_5260])
                    {
                        _5271[_5260] += _5982;
                    }
                    _5260++;
                    continue;
                }
            }
            if (_5275 == 1)
            {
                _5285 = _5286;
            }
            else
            {
                _5285 = 1.60000002384185791015625;
            }
            _5260 = 0;
            for (;;)
            {
                bool _6019_ladder_break = false;
                do
                {
                    if (!(_5260 < 16))
                    {
                        _6019_ladder_break = true;
                        break;
                    }
                    if (_5260 >= _5412)
                    {
                        _6019_ladder_break = true;
                        break;
                    }
                    if (true)
                    {
                        _5280 = _9391 != 0;
                    }
                    else
                    {
                        _5280 = _9395 != 0;
                    }
                    if (!_5280)
                    {
                        _5261 = true;
                    }
                    else
                    {
                        _5261 = _5266[_5260] < 0;
                    }
                    if (_5261)
                    {
                        _5262 = true;
                    }
                    else
                    {
                        _5262 = !_5267[_5260];
                    }
                    if (_5262)
                    {
                        _5277 = true;
                    }
                    else
                    {
                        _5277 = _5272[_5260];
                    }
                    if (_5277)
                    {
                        break;
                    }
                    bool _6068 = _5270[_5260] > 0;
                    if (_5269[_5260] >= 0)
                    {
                        if (_6068)
                        {
                            _5286 = _5263[_5260] - _5263[_5269[_5260]];
                        }
                        else
                        {
                            _5286 = _5263[_5269[_5260]] - _5263[_5260];
                        }
                        _5293 = _5269[_5260];
                        _5295 = _5286;
                    }
                    else
                    {
                        if (_5269[_5260] == (-2))
                        {
                            _5295 = 3.4028234663852885981170418348452e+38;
                            _5293 = _5269[_5260];
                            _5294 = 0;
                            for (;;)
                            {
                                bool _6079_ladder_break = false;
                                do
                                {
                                    if (!(_5294 < 16))
                                    {
                                        _6079_ladder_break = true;
                                        break;
                                    }
                                    if (_5294 >= _5412)
                                    {
                                        _6079_ladder_break = true;
                                        break;
                                    }
                                    if (_5294 == _5260)
                                    {
                                        _5278 = true;
                                    }
                                    else
                                    {
                                        _5278 = _5270[_5294] == _5270[_5260];
                                    }
                                    if (_5278)
                                    {
                                        break;
                                    }
                                    if (_6068)
                                    {
                                        _5296 = _5263[_5260] - _5263[_5294];
                                    }
                                    else
                                    {
                                        _5296 = _5263[_5294] - _5263[_5260];
                                    }
                                    if (_5296 <= 0.0)
                                    {
                                        _5279 = true;
                                    }
                                    else
                                    {
                                        _5279 = _5296 >= _5295;
                                    }
                                    if (_5279)
                                    {
                                        break;
                                    }
                                    _5295 = _5296;
                                    _5293 = _5294;
                                    break;
                                } while(false);
                                if (_6079_ladder_break)
                                {
                                    break;
                                }
                                _5294++;
                                continue;
                            }
                        }
                        else
                        {
                            _5293 = _5269[_5260];
                            _5295 = 3.4028234663852885981170418348452e+38;
                        }
                    }
                    if (_5293 < 0)
                    {
                        _5278 = true;
                    }
                    else
                    {
                        _5278 = _5272[_5293];
                    }
                    if (_5278)
                    {
                        _5279 = true;
                    }
                    else
                    {
                        _5279 = _5266[_5293] >= 0;
                    }
                    if (_5279)
                    {
                        _5281 = true;
                    }
                    else
                    {
                        _5281 = (_5295 * _3835.x) >= _5285;
                    }
                    if (_5281)
                    {
                        break;
                    }
                    if (_5268[_5293])
                    {
                        _5296 = _5295;
                    }
                    else
                    {
                        _5296 = max(round(_5295 * _3835.x), 1.0) * _5742;
                    }
                    if (_6068)
                    {
                        _5286 = _5271[_5260] - _5296;
                    }
                    else
                    {
                        _5286 = _5271[_5260] + _5296;
                    }
                    _5271[_5293] = _5286;
                    _5272[_5293] = true;
                    break;
                } while(false);
                if (_6019_ladder_break)
                {
                    break;
                }
                _5260++;
                continue;
            }
            _5260 = 0;
            bool _5273[16];
            bool _5274[16];
            for (;;)
            {
                bool _6223_ladder_break = false;
                do
                {
                    if (!(_5260 < 16))
                    {
                        _6223_ladder_break = true;
                        break;
                    }
                    if (_5260 >= _5412)
                    {
                        _6223_ladder_break = true;
                        break;
                    }
                    if (true)
                    {
                        _5280 = _9391 != 0;
                    }
                    else
                    {
                        _5280 = _9395 != 0;
                    }
                    if (!_5272[_5260])
                    {
                        if (_5280)
                        {
                            _5261 = _5266[_5260] >= 0;
                        }
                        else
                        {
                            _5261 = false;
                        }
                        _5261 = !_5261;
                    }
                    else
                    {
                        _5261 = false;
                    }
                    if (_5261)
                    {
                        break;
                    }
                    _3851[_3849] = _5263[_5260];
                    _3852[_3849] = _5271[_5260];
                    if (_5280)
                    {
                        _5262 = _5266[_5260] >= 0;
                    }
                    else
                    {
                        _5262 = false;
                    }
                    _5273[_3849] = _5262;
                    _5274[_3849] = _5268[_5260];
                    _3855[_3849] = _5260;
                    _3849++;
                    break;
                } while(false);
                if (_6223_ladder_break)
                {
                    break;
                }
                _5260++;
                continue;
            }
            if (true)
            {
                _5261 = _9394 == 1;
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                _5261 = _3849 > 0;
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                _5261 = _3849 < 16;
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                _5261 = _5211 < (_3851[0] - (0.25 / _3835.x));
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                _5260 = 15;
                for (;;)
                {
                    if (!(_5260 > 0))
                    {
                        break;
                    }
                    if (_5260 <= _3849)
                    {
                        int _6343 = _5260 - 1;
                        _3851[_5260] = _3851[_6343];
                        _3852[_5260] = _3852[_6343];
                        _5273[_5260] = _5273[_6343];
                        _5274[_5260] = _5274[_6343];
                        _3855[_5260] = _3855[_6343];
                    }
                    _5260--;
                    continue;
                }
                _3851[0] = _5211;
                _3852[0] = round(_5211 * _3835.x) / _3835.x;
                _5273[0] = false;
                _5274[0] = false;
                _3855[0] = 32;
                _3849++;
            }
            _5293 = 15;
            for (;;)
            {
                bool _6380_ladder_break = false;
                do
                {
                    if (!(_5293 > 0))
                    {
                        _6380_ladder_break = true;
                        break;
                    }
                    if (_5293 >= _3849)
                    {
                        _5261 = true;
                    }
                    else
                    {
                        _5261 = !_5273[_5293];
                    }
                    if (_5261)
                    {
                        break;
                    }
                    _5294 = 15;
                    for (;;)
                    {
                        bool _6401_ladder_break = false;
                        do
                        {
                            if (!(_5294 > 0))
                            {
                                _6401_ladder_break = true;
                                break;
                            }
                            if (_5294 > _5293)
                            {
                                break;
                            }
                            int _6413 = _5294 - 1;
                            if (_5273[_6413])
                            {
                                _6401_ladder_break = true;
                                break;
                            }
                            if (_5274[_6413])
                            {
                                _5285 = 9.9999999747524270787835121154785e-07;
                            }
                            else
                            {
                                _5285 = _5742;
                            }
                            _3852[_6413] = min(_3852[_6413], _3852[_5294] - _5285);
                            break;
                        } while(false);
                        if (_6401_ladder_break)
                        {
                            break;
                        }
                        _5294--;
                        continue;
                    }
                    break;
                } while(false);
                if (_6380_ladder_break)
                {
                    break;
                }
                _5293--;
                continue;
            }
            _5260 = 1;
            for (;;)
            {
                if (!(_5260 < 16))
                {
                    break;
                }
                if (_5260 >= _3849)
                {
                    break;
                }
                int _6460 = _5260 - 1;
                if (_3852[_5260] <= _3852[_6460])
                {
                    _3852[_5260] = _3852[_6460] + _5742;
                }
                _5260++;
                continue;
            }
            if (_9398 != 0)
            {
                _5261 = _3835.x > _9399;
            }
            else
            {
                _5261 = false;
            }
            if (_5261)
            {
                float _6489 = _9400 - _9399;
                if (_6489 <= 0.0)
                {
                    _5261 = true;
                }
                else
                {
                    _5261 = _3835.x >= _9400;
                }
                if (_5261)
                {
                    _5285 = 1.0;
                }
                else
                {
                    _5285 = (_3835.x - _9399) / _6489;
                }
                _5260 = 0;
                for (;;)
                {
                    if (!(_5260 < 16))
                    {
                        break;
                    }
                    if (_5260 >= _3849)
                    {
                        break;
                    }
                    _3852[_5260] += ((_3851[_5260] - _3852[_5260]) * _5285);
                    _5260++;
                    continue;
                }
            }
            _5260 = 0;
            bool _7108;
            bool _7119;
            for (;;)
            {
                if (!(_5260 < 16))
                {
                    break;
                }
                if (_5260 >= _3849)
                {
                    break;
                }
                if (!isnan(_3851[_5260]))
                {
                    _7108 = !isinf(_3851[_5260]);
                }
                else
                {
                    _7108 = false;
                }
                if (!_7108)
                {
                    _5261 = true;
                }
                else
                {
                    if (!isnan(_3852[_5260]))
                    {
                        _7119 = !isinf(_3852[_5260]);
                    }
                    else
                    {
                        _7119 = false;
                    }
                    _5261 = !_7119;
                }
                if (_5261)
                {
                    _3849 = 0;
                    _5258 = true;
                    _5259 = false;
                    break;
                }
                _5260++;
                continue;
            }
            if (_5258)
            {
                break;
            }
            _5258 = true;
            _5259 = true;
            break;
        } while(false);
        int _9421 = _9329;
        int _9422 = _9330;
        int _9423 = _9331;
        int _9424 = _9332;
        int _9425 = _9333;
        int _9426 = _9334;
        int _9427 = _9335;
        int _9428 = _9336;
        float _9429 = _9337;
        float _9430 = _9338;
        float _9431 = _9339;
        float _9432 = _9340;
        float _9433 = _9341;
        float _9434 = _9342;
        float _9435 = _9343;
        _7130 = false;
        float _3854[16];
        int _3856[16];
        bool _7131;
        do
        {
            _3850 = 0;
            int _7132 = 0;
            float _3853[16];
            for (;;)
            {
                if (!(_7132 < 16))
                {
                    break;
                }
                _3853[_7132] = 0.0;
                _3854[_7132] = 0.0;
                _3856[_7132] = 0;
                _7132++;
                continue;
            }
            bool _8443;
            if (!isnan(_3835.y))
            {
                _8443 = !isinf(_3835.y);
            }
            else
            {
                _8443 = false;
            }
            bool _7133;
            if (!_8443)
            {
                _7133 = true;
            }
            else
            {
                _7133 = _3835.y <= 0.0;
            }
            if (_7133)
            {
                _7133 = true;
            }
            else
            {
                _7133 = _3841 < 0;
            }
            if (_7133)
            {
                _7133 = true;
            }
            else
            {
                _7133 = _3841 > 16;
            }
            if (_7133)
            {
                _7133 = true;
            }
            else
            {
                bool _8454;
                if (!isnan(_4561))
                {
                    _8454 = !isinf(_4561);
                }
                else
                {
                    _8454 = false;
                }
                _7133 = !_8454;
            }
            if (_7133)
            {
                _7133 = true;
            }
            else
            {
                _7133 = _4561 < 0.0;
            }
            if (_7133)
            {
                _7130 = true;
                _7131 = false;
                break;
            }
            if (false)
            {
                _7133 = _9421 == 0;
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                _7133 = _9422 == 0;
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                _7133 = _9423 == 0;
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                _7133 = _9424 == 0;
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                _7133 = true;
            }
            else
            {
                if (true)
                {
                    _7133 = _9425 == 0;
                }
                else
                {
                    _7133 = false;
                }
                if (_7133)
                {
                    _7133 = _9426 == 0;
                }
                else
                {
                    _7133 = false;
                }
                if (_7133)
                {
                    _7133 = _9427 == 0;
                }
                else
                {
                    _7133 = false;
                }
            }
            if (_7133)
            {
                _7130 = true;
                _7131 = true;
                break;
            }
            int _8503 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
            int _8508 = ((_9278.y * _8503) + _9278.x) + (_3986 >> 2);
            vec4 _8474 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8508 - _8503 * (_8508 / _8503), _8508 / _8503), 0).xy, 0);
            int _8476 = _3986 & 3;
            float _8465;
            if (_8476 == 0)
            {
                _8465 = _8474.x;
            }
            else
            {
                if (_8476 == 1)
                {
                    _8465 = _8474.y;
                }
                else
                {
                    if (_8476 == 2)
                    {
                        _8465 = _8474.z;
                    }
                    else
                    {
                        _8465 = _8474.w;
                    }
                }
            }
            int _7284 = int(_8465);
            if (_7284 <= 0)
            {
                _7133 = true;
            }
            else
            {
                _7133 = _7284 > 16;
            }
            if (_7133)
            {
                _7130 = true;
                _7131 = _7284 == 0;
                break;
            }
            if (true)
            {
                _7133 = _9425 == 2;
            }
            else
            {
                _7133 = false;
            }
            bool _7134;
            if (false)
            {
                _7134 = _9424 == 1;
            }
            else
            {
                _7134 = false;
            }
            if (_7134)
            {
                bool _8512;
                if (!isnan(0.0))
                {
                    _8512 = !isinf(0.0);
                }
                else
                {
                    _8512 = false;
                }
                _7134 = !_8512;
            }
            else
            {
                _7134 = false;
            }
            if (_7134)
            {
                _7130 = true;
                _7131 = false;
                break;
            }
            _7132 = 0;
            float _7135[16];
            float _7136[16];
            int _7137[16];
            int _7138[16];
            bool _7139[16];
            bool _7140[16];
            int _7141[16];
            int _7142[16];
            bool _7144[16];
            int _7147;
            int _7148;
            bool _7149;
            bool _7150;
            bool _7151;
            bool _7152;
            bool _7153;
            bool _7154;
            bool _7155;
            uint _7156;
            float _8523;
            float _8570;
            float _8617;
            float _8664;
            bool _8711;
            bool _8722;
            for (;;)
            {
                if (!(_7132 < 16))
                {
                    break;
                }
                if (_7132 >= _7284)
                {
                    break;
                }
                int _7331 = (_3986 + 1) + (4 * _7132);
                int _8561 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _8566 = ((_9278.y * _8561) + _9278.x) + (_7331 >> 2);
                vec4 _8532 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8566 - _8561 * (_8566 / _8561), _8566 / _8561), 0).xy, 0);
                int _8534 = _7331 & 3;
                if (_8534 == 0)
                {
                    _8523 = _8532.x;
                }
                else
                {
                    if (_8534 == 1)
                    {
                        _8523 = _8532.y;
                    }
                    else
                    {
                        if (_8534 == 2)
                        {
                            _8523 = _8532.z;
                        }
                        else
                        {
                            _8523 = _8532.w;
                        }
                    }
                }
                _7135[_7132] = _8523;
                int _8573 = _7331 + 1;
                int _8608 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _8613 = ((_9278.y * _8608) + _9278.x) + (_8573 >> 2);
                vec4 _8579 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8613 - _8608 * (_8613 / _8608), _8613 / _8608), 0).xy, 0);
                int _8581 = _8573 & 3;
                if (_8581 == 0)
                {
                    _8570 = _8579.x;
                }
                else
                {
                    if (_8581 == 1)
                    {
                        _8570 = _8579.y;
                    }
                    else
                    {
                        if (_8581 == 2)
                        {
                            _8570 = _8579.z;
                        }
                        else
                        {
                            _8570 = _8579.w;
                        }
                    }
                }
                _7136[_7132] = _8570;
                int _8620 = _7331 + 2;
                int _8655 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _8660 = ((_9278.y * _8655) + _9278.x) + (_8620 >> 2);
                vec4 _8626 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8660 - _8655 * (_8660 / _8655), _8660 / _8655), 0).xy, 0);
                int _8628 = _8620 & 3;
                if (_8628 == 0)
                {
                    _8617 = _8626.x;
                }
                else
                {
                    if (_8628 == 1)
                    {
                        _8617 = _8626.y;
                    }
                    else
                    {
                        if (_8628 == 2)
                        {
                            _8617 = _8626.z;
                        }
                        else
                        {
                            _8617 = _8626.w;
                        }
                    }
                }
                _7137[_7132] = int(floatBitsToUint(_8617) << 16u) >> 16;
                _7138[_7132] = floatBitsToInt(_8617) >> 16;
                int _8667 = _7331 + 3;
                int _8702 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _8707 = ((_9278.y * _8702) + _9278.x) + (_8667 >> 2);
                vec4 _8673 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8707 - _8702 * (_8707 / _8702), _8707 / _8702), 0).xy, 0);
                int _8675 = _8667 & 3;
                if (_8675 == 0)
                {
                    _8664 = _8673.x;
                }
                else
                {
                    if (_8675 == 1)
                    {
                        _8664 = _8673.y;
                    }
                    else
                    {
                        if (_8675 == 2)
                        {
                            _8664 = _8673.z;
                        }
                        else
                        {
                            _8664 = _8673.w;
                        }
                    }
                }
                uint _7350 = floatBitsToUint(_8664);
                _7139[_7132] = (_7350 & 1u) != 0u;
                _7140[_7132] = (_7350 & 2u) != 0u;
                if ((_7350 & 4u) == 0u)
                {
                    _7130 = true;
                    _7131 = false;
                    break;
                }
                if ((_7350 & 8u) != 0u)
                {
                    _7147 = -1;
                }
                else
                {
                    _7147 = 1;
                }
                _7142[_7132] = _7147;
                if (_7133)
                {
                    _7156 = 10u;
                }
                else
                {
                    _7156 = 4u;
                }
                int _7379 = int((_7350 >> _7156) & 63u);
                if (_7379 >= 62)
                {
                    _7148 = -1;
                }
                else
                {
                    _7148 = _7379;
                }
                _7141[_7132] = _7148;
                if (_7379 >= 63)
                {
                    _7134 = _7139[_7132];
                }
                else
                {
                    _7134 = false;
                }
                if (_7134)
                {
                    _7149 = _7138[_7132] >= 0;
                }
                else
                {
                    _7149 = false;
                }
                if (_7149)
                {
                    _7130 = true;
                    _7131 = false;
                    break;
                }
                _7144[_7132] = false;
                if (!isnan(_7135[_7132]))
                {
                    _8711 = !isinf(_7135[_7132]);
                }
                else
                {
                    _8711 = false;
                }
                if (!_8711)
                {
                    _7150 = true;
                }
                else
                {
                    if (!isnan(_7136[_7132]))
                    {
                        _8722 = !isinf(_7136[_7132]);
                    }
                    else
                    {
                        _8722 = false;
                    }
                    _7150 = !_8722;
                }
                if (_7150)
                {
                    _7151 = true;
                }
                else
                {
                    _7151 = _7136[_7132] < 0.0;
                }
                if (_7151)
                {
                    _7152 = true;
                }
                else
                {
                    _7152 = _7137[_7132] < (-1);
                }
                if (_7152)
                {
                    _7153 = true;
                }
                else
                {
                    _7153 = _7137[_7132] >= _7284;
                }
                if (_7153)
                {
                    _7154 = true;
                }
                else
                {
                    _7154 = _7138[_7132] < (-1);
                }
                if (_7154)
                {
                    _7155 = true;
                }
                else
                {
                    _7155 = _7138[_7132] >= _3841;
                }
                if (_7155)
                {
                    _7130 = true;
                    _7131 = false;
                    break;
                }
                _7132++;
                continue;
            }
            if (_7130)
            {
                break;
            }
            _7132 = 0;
            float _8733;
            float _8780;
            bool _8827;
            bool _8838;
            for (;;)
            {
                if (!(_7132 < 16))
                {
                    break;
                }
                if (_7132 >= _3841)
                {
                    break;
                }
                int _7467 = 2 * _7132;
                int _8771 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _8776 = ((_9278.y * _8771) + _9278.x) + ((12 + _7467) >> 2);
                vec4 _8742 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8776 - _8771 * (_8776 / _8771), _8776 / _8771), 0).xy, 0);
                int _8744 = _7467 & 3;
                if (_8744 == 0)
                {
                    _8733 = _8742.x;
                }
                else
                {
                    if (_8744 == 1)
                    {
                        _8733 = _8742.y;
                    }
                    else
                    {
                        if (_8744 == 2)
                        {
                            _8733 = _8742.z;
                        }
                        else
                        {
                            _8733 = _8742.w;
                        }
                    }
                }
                int _8783 = _7467 + 13;
                int _8818 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _8823 = ((_9278.y * _8818) + _9278.x) + (_8783 >> 2);
                vec4 _8789 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8823 - _8818 * (_8823 / _8818), _8823 / _8818), 0).xy, 0);
                int _8791 = _8783 & 3;
                if (_8791 == 0)
                {
                    _8780 = _8789.x;
                }
                else
                {
                    if (_8791 == 1)
                    {
                        _8780 = _8789.y;
                    }
                    else
                    {
                        if (_8791 == 2)
                        {
                            _8780 = _8789.z;
                        }
                        else
                        {
                            _8780 = _8789.w;
                        }
                    }
                }
                if (!isnan(_8733))
                {
                    _8827 = !isinf(_8733);
                }
                else
                {
                    _8827 = false;
                }
                if (!_8827)
                {
                    _7134 = true;
                }
                else
                {
                    if (!isnan(_8780))
                    {
                        _8838 = !isinf(_8780);
                    }
                    else
                    {
                        _8838 = false;
                    }
                    _7134 = !_8838;
                }
                if (_7134)
                {
                    _7130 = true;
                    _7131 = false;
                    break;
                }
                _7132++;
                continue;
            }
            if (_7130)
            {
                break;
            }
            if (true)
            {
                _7134 = _9427 == 1;
            }
            else
            {
                _7134 = false;
            }
            float _7157;
            if (_7134)
            {
                _7157 = _9435;
            }
            else
            {
                _7157 = 0.0;
            }
            _7132 = 0;
            float _7143[16];
            float _8854;
            float _8901;
            for (;;)
            {
                if (!(_7132 < 16))
                {
                    break;
                }
                if (_7132 >= _7284)
                {
                    break;
                }
                if (_7137[_7132] >= 0)
                {
                    _7134 = _7135[_7137[_7132]] > _7135[_7132];
                }
                else
                {
                    _7134 = false;
                }
                if (_7133)
                {
                    _7149 = _7138[_7132] >= 0;
                }
                else
                {
                    _7149 = false;
                }
                if (!_7133)
                {
                    if (_7134)
                    {
                        _7147 = -1;
                    }
                    else
                    {
                        _7147 = 1;
                    }
                    _7142[_7132] = _7147;
                }
                if (_7149)
                {
                    int _7561 = 2 * _7138[_7132];
                    int _8892 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _8897 = ((_9278.y * _8892) + _9278.x) + ((12 + _7561) >> 2);
                    vec4 _8863 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8897 - _8892 * (_8897 / _8892), _8897 / _8892), 0).xy, 0);
                    int _8865 = _7561 & 3;
                    if (_8865 == 0)
                    {
                        _8854 = _8863.x;
                    }
                    else
                    {
                        if (_8865 == 1)
                        {
                            _8854 = _8863.y;
                        }
                        else
                        {
                            if (_8865 == 2)
                            {
                                _8854 = _8863.z;
                            }
                            else
                            {
                                _8854 = _8863.w;
                            }
                        }
                    }
                    int _8904 = (2 * _7138[_7132]) + 13;
                    int _8939 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _8944 = ((_9278.y * _8939) + _9278.x) + (_8904 >> 2);
                    vec4 _8910 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8944 - _8939 * (_8944 / _8939), _8944 / _8939), 0).xy, 0);
                    int _8912 = _8904 & 3;
                    if (_8912 == 0)
                    {
                        _8901 = _8910.x;
                    }
                    else
                    {
                        if (_8912 == 1)
                        {
                            _8901 = _8910.y;
                        }
                        else
                        {
                            if (_8912 == 2)
                            {
                                _8901 = _8910.z;
                            }
                            else
                            {
                                _8901 = _8910.w;
                            }
                        }
                    }
                    if (_7139[_7132])
                    {
                        _7150 = true;
                    }
                    else
                    {
                        _7150 = false;
                    }
                    if (_7150)
                    {
                        _7151 = _9427 == 0;
                    }
                    else
                    {
                        _7151 = false;
                    }
                    if (_7151)
                    {
                        _7143[_7132] = _7135[_7132];
                    }
                    else
                    {
                        _7143[_7132] = round(_8854 * _3835.y) / _3835.y;
                        if (_7139[_7132])
                        {
                            _7152 = abs((_8901 - _8854) * _3835.y) >= _7157;
                        }
                        else
                        {
                            _7152 = false;
                        }
                        if (_7152)
                        {
                            _7143[_7132] += (_8901 - _8854);
                        }
                    }
                }
                else
                {
                    _7143[_7132] = round(_7135[_7132] * _3835.y) / _3835.y;
                }
                _7132++;
                continue;
            }
            float _7614 = 1.0 / _3835.y;
            if (false)
            {
                _7147 = _9422;
            }
            else
            {
                _7147 = _9426;
            }
            if (false)
            {
                _7157 = _9431;
            }
            else
            {
                _7157 = _9433;
            }
            float _7158;
            if (false)
            {
                _7158 = _9432;
            }
            else
            {
                _7158 = _9434;
            }
            if (false)
            {
                _7133 = _9421 == 1;
            }
            else
            {
                _7133 = _9425 != 0;
            }
            if (false)
            {
                _7134 = _9423 == 1;
            }
            else
            {
                _7134 = false;
            }
            _7149 = false;
            float _7160 = 0.0;
            float _7161 = 0.0;
            float _7162 = 0.0;
            float _7163 = 0.0;
            float _7164 = 0.0;
            _7148 = 0;
            _7132 = 0;
            int _7159 = 0;
            int _7165;
            int _7166;
            float _7167;
            float _7168;
            float _7169;
            float _7170;
            float _7171;
            float _7172;
            bool _7173;
            bool _8953;
            float _8954;
            for (;;)
            {
                bool _7653_ladder_break = false;
                do
                {
                    if (!(_7132 < 16))
                    {
                        _7653_ladder_break = true;
                        break;
                    }
                    if (_7132 >= _7284)
                    {
                        _7653_ladder_break = true;
                        break;
                    }
                    if (_7137[_7132] < 0)
                    {
                        _7150 = true;
                    }
                    else
                    {
                        _7150 = _7137[_7132] <= _7132;
                    }
                    if (_7150)
                    {
                        _7152 = _7149;
                        break;
                    }
                    if (_4561 > 0.0)
                    {
                        _8953 = abs(_7136[_7132] - _4561) <= (_7157 * _4561);
                    }
                    else
                    {
                        _8953 = false;
                    }
                    if (_8953)
                    {
                        _8954 = _4561;
                    }
                    else
                    {
                        _8954 = _7136[_7132];
                    }
                    if (_7147 == 2)
                    {
                        _7151 = true;
                    }
                    else
                    {
                        if (_7147 == 1)
                        {
                            _7151 = (_8954 * _3835.y) < _7158;
                        }
                        else
                        {
                            _7151 = false;
                        }
                    }
                    if (_7151)
                    {
                        _7167 = max(round(_8954 * _3835.y), 1.0) * _7614;
                    }
                    else
                    {
                        _7167 = _7136[_7132];
                    }
                    if (_7134)
                    {
                        if (_7149)
                        {
                            _7143[_7132] = _7160 + (round((_7135[_7132] - _7161) * _3835.y) * _7614);
                            _7168 = _7162;
                            _7169 = _7163;
                            _7152 = _7149;
                        }
                        else
                        {
                            float _8974 = round(_7135[_7132] * _3835.y) / _3835.y;
                            _7143[_7132] = _8974;
                            _7168 = _8974;
                            _7169 = _7135[_7132];
                            _7152 = true;
                        }
                        _7143[_7137[_7132]] = _7143[_7132] + _7167;
                        float _7811 = _7169;
                        float _7816 = _7168;
                        _7168 = _7143[_7132];
                        _7169 = _7135[_7132];
                        _7170 = _7816;
                        _7171 = _7811;
                        _7172 = (_7816 + (round((_7135[_7132] - _7811) * _3835.y) * _7614)) + _7167;
                        _7165 = _7137[_7132];
                        _7166 = _7159 + 1;
                    }
                    else
                    {
                        if (false)
                        {
                            _7152 = _9421 != 0;
                        }
                        else
                        {
                            _7152 = _9425 != 0;
                        }
                        if (_7152)
                        {
                            _7153 = _7138[_7132] >= 0;
                        }
                        else
                        {
                            _7153 = false;
                        }
                        if (_7152)
                        {
                            _7154 = _7138[_7137[_7132]] >= 0;
                        }
                        else
                        {
                            _7154 = false;
                        }
                        if (!_7133)
                        {
                            _7143[_7132] = _7135[_7132];
                        }
                        if (_7154)
                        {
                            _7155 = !_7153;
                        }
                        else
                        {
                            _7155 = false;
                        }
                        if (_7155)
                        {
                            _7173 = _7133;
                        }
                        else
                        {
                            _7173 = false;
                        }
                        if (_7173)
                        {
                            _7143[_7132] = _7143[_7137[_7132]] - _7167;
                        }
                        else
                        {
                            _7143[_7137[_7132]] = _7143[_7132] + _7167;
                        }
                        _7152 = _7149;
                        _7168 = _7160;
                        _7169 = _7161;
                        _7170 = _7162;
                        _7171 = _7163;
                        _7172 = _7164;
                        _7165 = _7148;
                        _7166 = _7159;
                    }
                    _7144[_7132] = true;
                    _7144[_7137[_7132]] = true;
                    _7160 = _7168;
                    _7161 = _7169;
                    _7162 = _7170;
                    _7163 = _7171;
                    _7164 = _7172;
                    _7148 = _7165;
                    _7159 = _7166;
                    break;
                } while(false);
                if (_7653_ladder_break)
                {
                    break;
                }
                _7149 = _7152;
                _7132++;
                continue;
            }
            if (_7134)
            {
                _7133 = _7159 > 1;
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                float _7854 = _7164 - _7143[_7148];
                _7132 = 0;
                for (;;)
                {
                    if (!(_7132 < 16))
                    {
                        break;
                    }
                    if (_7132 >= _7284)
                    {
                        break;
                    }
                    if (_7144[_7132])
                    {
                        _7143[_7132] += _7854;
                    }
                    _7132++;
                    continue;
                }
            }
            if (_7147 == 1)
            {
                _7157 = _7158;
            }
            else
            {
                _7157 = 1.60000002384185791015625;
            }
            _7132 = 0;
            for (;;)
            {
                bool _7891_ladder_break = false;
                do
                {
                    if (!(_7132 < 16))
                    {
                        _7891_ladder_break = true;
                        break;
                    }
                    if (_7132 >= _7284)
                    {
                        _7891_ladder_break = true;
                        break;
                    }
                    if (false)
                    {
                        _7152 = _9421 != 0;
                    }
                    else
                    {
                        _7152 = _9425 != 0;
                    }
                    if (!_7152)
                    {
                        _7133 = true;
                    }
                    else
                    {
                        _7133 = _7138[_7132] < 0;
                    }
                    if (_7133)
                    {
                        _7134 = true;
                    }
                    else
                    {
                        _7134 = !_7139[_7132];
                    }
                    if (_7134)
                    {
                        _7149 = true;
                    }
                    else
                    {
                        _7149 = _7144[_7132];
                    }
                    if (_7149)
                    {
                        break;
                    }
                    bool _7940 = _7142[_7132] > 0;
                    if (_7141[_7132] >= 0)
                    {
                        if (_7940)
                        {
                            _7158 = _7135[_7132] - _7135[_7141[_7132]];
                        }
                        else
                        {
                            _7158 = _7135[_7141[_7132]] - _7135[_7132];
                        }
                        _7165 = _7141[_7132];
                        _7167 = _7158;
                    }
                    else
                    {
                        if (_7141[_7132] == (-2))
                        {
                            _7167 = 3.4028234663852885981170418348452e+38;
                            _7165 = _7141[_7132];
                            _7166 = 0;
                            for (;;)
                            {
                                bool _7951_ladder_break = false;
                                do
                                {
                                    if (!(_7166 < 16))
                                    {
                                        _7951_ladder_break = true;
                                        break;
                                    }
                                    if (_7166 >= _7284)
                                    {
                                        _7951_ladder_break = true;
                                        break;
                                    }
                                    if (_7166 == _7132)
                                    {
                                        _7150 = true;
                                    }
                                    else
                                    {
                                        _7150 = _7142[_7166] == _7142[_7132];
                                    }
                                    if (_7150)
                                    {
                                        break;
                                    }
                                    if (_7940)
                                    {
                                        _7168 = _7135[_7132] - _7135[_7166];
                                    }
                                    else
                                    {
                                        _7168 = _7135[_7166] - _7135[_7132];
                                    }
                                    if (_7168 <= 0.0)
                                    {
                                        _7151 = true;
                                    }
                                    else
                                    {
                                        _7151 = _7168 >= _7167;
                                    }
                                    if (_7151)
                                    {
                                        break;
                                    }
                                    _7167 = _7168;
                                    _7165 = _7166;
                                    break;
                                } while(false);
                                if (_7951_ladder_break)
                                {
                                    break;
                                }
                                _7166++;
                                continue;
                            }
                        }
                        else
                        {
                            _7165 = _7141[_7132];
                            _7167 = 3.4028234663852885981170418348452e+38;
                        }
                    }
                    if (_7165 < 0)
                    {
                        _7150 = true;
                    }
                    else
                    {
                        _7150 = _7144[_7165];
                    }
                    if (_7150)
                    {
                        _7151 = true;
                    }
                    else
                    {
                        _7151 = _7138[_7165] >= 0;
                    }
                    if (_7151)
                    {
                        _7153 = true;
                    }
                    else
                    {
                        _7153 = (_7167 * _3835.y) >= _7157;
                    }
                    if (_7153)
                    {
                        break;
                    }
                    if (_7140[_7165])
                    {
                        _7168 = _7167;
                    }
                    else
                    {
                        _7168 = max(round(_7167 * _3835.y), 1.0) * _7614;
                    }
                    if (_7940)
                    {
                        _7158 = _7143[_7132] - _7168;
                    }
                    else
                    {
                        _7158 = _7143[_7132] + _7168;
                    }
                    _7143[_7165] = _7158;
                    _7144[_7165] = true;
                    break;
                } while(false);
                if (_7891_ladder_break)
                {
                    break;
                }
                _7132++;
                continue;
            }
            _7132 = 0;
            bool _7145[16];
            bool _7146[16];
            for (;;)
            {
                bool _8095_ladder_break = false;
                do
                {
                    if (!(_7132 < 16))
                    {
                        _8095_ladder_break = true;
                        break;
                    }
                    if (_7132 >= _7284)
                    {
                        _8095_ladder_break = true;
                        break;
                    }
                    if (false)
                    {
                        _7152 = _9421 != 0;
                    }
                    else
                    {
                        _7152 = _9425 != 0;
                    }
                    if (!_7144[_7132])
                    {
                        if (_7152)
                        {
                            _7133 = _7138[_7132] >= 0;
                        }
                        else
                        {
                            _7133 = false;
                        }
                        _7133 = !_7133;
                    }
                    else
                    {
                        _7133 = false;
                    }
                    if (_7133)
                    {
                        break;
                    }
                    _3853[_3850] = _7135[_7132];
                    _3854[_3850] = _7143[_7132];
                    if (_7152)
                    {
                        _7134 = _7138[_7132] >= 0;
                    }
                    else
                    {
                        _7134 = false;
                    }
                    _7145[_3850] = _7134;
                    _7146[_3850] = _7140[_7132];
                    _3856[_3850] = _7132;
                    _3850++;
                    break;
                } while(false);
                if (_8095_ladder_break)
                {
                    break;
                }
                _7132++;
                continue;
            }
            if (false)
            {
                _7133 = _9424 == 1;
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                _7133 = _3850 > 0;
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                _7133 = _3850 < 16;
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                _7133 = 0.0 < (_3853[0] - (0.25 / _3835.y));
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                _7132 = 15;
                for (;;)
                {
                    if (!(_7132 > 0))
                    {
                        break;
                    }
                    if (_7132 <= _3850)
                    {
                        int _8215 = _7132 - 1;
                        _3853[_7132] = _3853[_8215];
                        _3854[_7132] = _3854[_8215];
                        _7145[_7132] = _7145[_8215];
                        _7146[_7132] = _7146[_8215];
                        _3856[_7132] = _3856[_8215];
                    }
                    _7132--;
                    continue;
                }
                _3853[0] = 0.0;
                _3854[0] = round(0.0) / _3835.y;
                _7145[0] = false;
                _7146[0] = false;
                _3856[0] = 32;
                _3850++;
            }
            _7165 = 15;
            for (;;)
            {
                bool _8252_ladder_break = false;
                do
                {
                    if (!(_7165 > 0))
                    {
                        _8252_ladder_break = true;
                        break;
                    }
                    if (_7165 >= _3850)
                    {
                        _7133 = true;
                    }
                    else
                    {
                        _7133 = !_7145[_7165];
                    }
                    if (_7133)
                    {
                        break;
                    }
                    _7166 = 15;
                    for (;;)
                    {
                        bool _8273_ladder_break = false;
                        do
                        {
                            if (!(_7166 > 0))
                            {
                                _8273_ladder_break = true;
                                break;
                            }
                            if (_7166 > _7165)
                            {
                                break;
                            }
                            int _8285 = _7166 - 1;
                            if (_7145[_8285])
                            {
                                _8273_ladder_break = true;
                                break;
                            }
                            if (_7146[_8285])
                            {
                                _7157 = 9.9999999747524270787835121154785e-07;
                            }
                            else
                            {
                                _7157 = _7614;
                            }
                            _3854[_8285] = min(_3854[_8285], _3854[_7166] - _7157);
                            break;
                        } while(false);
                        if (_8273_ladder_break)
                        {
                            break;
                        }
                        _7166--;
                        continue;
                    }
                    break;
                } while(false);
                if (_8252_ladder_break)
                {
                    break;
                }
                _7165--;
                continue;
            }
            _7132 = 1;
            for (;;)
            {
                if (!(_7132 < 16))
                {
                    break;
                }
                if (_7132 >= _3850)
                {
                    break;
                }
                int _8332 = _7132 - 1;
                if (_3854[_7132] <= _3854[_8332])
                {
                    _3854[_7132] = _3854[_8332] + _7614;
                }
                _7132++;
                continue;
            }
            if (_9428 != 0)
            {
                _7133 = _3835.y > _9429;
            }
            else
            {
                _7133 = false;
            }
            if (_7133)
            {
                float _8361 = _9430 - _9429;
                if (_8361 <= 0.0)
                {
                    _7133 = true;
                }
                else
                {
                    _7133 = _3835.y >= _9430;
                }
                if (_7133)
                {
                    _7157 = 1.0;
                }
                else
                {
                    _7157 = (_3835.y - _9429) / _8361;
                }
                _7132 = 0;
                for (;;)
                {
                    if (!(_7132 < 16))
                    {
                        break;
                    }
                    if (_7132 >= _3850)
                    {
                        break;
                    }
                    _3854[_7132] += ((_3853[_7132] - _3854[_7132]) * _7157);
                    _7132++;
                    continue;
                }
            }
            _7132 = 0;
            bool _8980;
            bool _8991;
            for (;;)
            {
                if (!(_7132 < 16))
                {
                    break;
                }
                if (_7132 >= _3850)
                {
                    break;
                }
                if (!isnan(_3853[_7132]))
                {
                    _8980 = !isinf(_3853[_7132]);
                }
                else
                {
                    _8980 = false;
                }
                if (!_8980)
                {
                    _7133 = true;
                }
                else
                {
                    if (!isnan(_3854[_7132]))
                    {
                        _8991 = !isinf(_3854[_7132]);
                    }
                    else
                    {
                        _8991 = false;
                    }
                    _7133 = !_8991;
                }
                if (_7133)
                {
                    _3850 = 0;
                    _7130 = true;
                    _7131 = false;
                    break;
                }
                _7132++;
                continue;
            }
            if (_7130)
            {
                break;
            }
            _7130 = true;
            _7131 = true;
            break;
        } while(false);
        if (_5259)
        {
            float _3859[16] = _3852;
            int _3860[16] = _3855;
            vec4 _3861[4] = _9281;
            uvec4 _3862 = _9283;
            do
            {
                int _9025 = 0;
                for (;;)
                {
                    if (!(_9025 < 4))
                    {
                        break;
                    }
                    _3861[_9025] = vec4(0.0);
                    _9025++;
                    continue;
                }
                _3862 = uvec4(4294967295u);
                if (_3849 > 16)
                {
                    _3862.x = (_3862.x & 4294967040u) | 254u;
                    break;
                }
                _9025 = 0;
                for (;;)
                {
                    if (!(_9025 < 16))
                    {
                        break;
                    }
                    if (_9025 >= _3849)
                    {
                        break;
                    }
                    int _9065 = _9025 >> 2;
                    int _9068 = _9025 & 3;
                    _3861[_9065][_9068] = _3859[_9025];
                    uint _9076 = uint(_9068 * 8);
                    _3862[_9065] = (_3862[_9065] & (~(255u << _9076))) | ((uint(_3860[_9025]) & 255u) << _9076);
                    _9025++;
                    continue;
                }
                break;
            } while(false);
            _9281 = _3861;
            _9283 = _3862;
        }
        else
        {
            vec4 _3863[4] = _9281;
            int _9002 = 0;
            for (;;)
            {
                if (!(_9002 < 4))
                {
                    break;
                }
                _3863[_9002] = vec4(0.0);
                _9002++;
                continue;
            }
            uvec4 _9700 = uvec4(4294967295u);
            _9700.x = 4294967294u;
            _9281 = _3863;
            _9283 = _9700;
        }
        if (_7131)
        {
            float _3865[16] = _3854;
            int _3866[16] = _3856;
            vec4 _3867[4] = _9282;
            uvec4 _3868 = _9284;
            do
            {
                int _9117 = 0;
                for (;;)
                {
                    if (!(_9117 < 4))
                    {
                        break;
                    }
                    _3867[_9117] = vec4(0.0);
                    _9117++;
                    continue;
                }
                _3868 = uvec4(4294967295u);
                if (_3850 > 16)
                {
                    _3868.x = (_3868.x & 4294967040u) | 254u;
                    break;
                }
                _9117 = 0;
                for (;;)
                {
                    if (!(_9117 < 16))
                    {
                        break;
                    }
                    if (_9117 >= _3850)
                    {
                        break;
                    }
                    int _9157 = _9117 >> 2;
                    int _9160 = _9117 & 3;
                    _3867[_9157][_9160] = _3865[_9117];
                    uint _9168 = uint(_9160 * 8);
                    _3868[_9157] = (_3868[_9157] & (~(255u << _9168))) | ((uint(_3866[_9117]) & 255u) << _9168);
                    _9117++;
                    continue;
                }
                break;
            } while(false);
            _9282 = _3867;
            _9284 = _3868;
        }
        else
        {
            vec4 _3869[4] = _9282;
            int _9094 = 0;
            for (;;)
            {
                if (!(_9094 < 4))
                {
                    break;
                }
                _3869[_9094] = vec4(0.0);
                _9094++;
                continue;
            }
            uvec4 _9702 = uvec4(4294967295u);
            _9702.x = 4294967294u;
            _9282 = _3869;
            _9284 = _9702;
        }
        _9214 = _9275;
        _9215 = _9276;
        _9216 = _9277;
        _9217 = _9278;
        _9218 = _9279;
        _9219 = _9280;
        _9611 = _9281[0];
        _9612 = _9281[1];
        _9613 = _9281[2];
        _9614 = _9281[3];
        _9636 = _9282[0];
        _9637 = _9282[1];
        _9638 = _9282[2];
        _9639 = _9282[3];
        _9222 = _9283;
        _9223 = _9284;
        break;
    } while(false);
    gl_Position = _9214;
    snail_io0 = _9215;
    snail_io1 = _9216;
    snail_io2 = _9217;
    snail_io3 = _9218;
    snail_io4 = _9219;
    snail_io5 = _9611;
    snail_io6 = _9612;
    snail_io7 = _9613;
    snail_io8 = _9614;
    snail_io9 = _9636;
    snail_io10 = _9637;
    snail_io11 = _9638;
    snail_io12 = _9639;
    snail_io13 = _9222;
    snail_io14 = _9223;
}


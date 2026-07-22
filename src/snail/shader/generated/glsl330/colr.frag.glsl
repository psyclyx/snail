#version 330

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
uniform usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_image_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_image_texu_image_sampler;

in vec4 snail_io4;
in vec2 snail_io1;
flat in vec4 snail_io2;
flat in ivec4 snail_io3;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

void main()
{
    vec4 _12862 = snail_io4;
    vec2 _12863 = snail_io1;
    vec4 _12864 = snail_io2;
    ivec4 _12865 = snail_io3;
    int _12870 = pc.layer_base;
    int _12871 = pc.output_srgb;
    float _12872 = pc.coverage_exponent;
    float _12873 = pc.dither_scale;
    int _12874 = pc.mask_output;
    vec4 _3237;
    do
    {
        vec2 _3383 = fwidth(_12863);
        vec2 _3248 = vec2(1.0) / max(_3383, vec2(1.52587890625e-05));
        if (((_12865.w >> 8) & 255) != 255)
        {
            discard;
        }
        if ((_12865.w & 255) != 0)
        {
            discard;
        }
        vec4 _3265 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(_12865.xy, 0).xy, 0);
        float _3267 = _3265.w;
        if (_3267 >= 0.0)
        {
            discard;
        }
        int _3277 = _12870 + int(_12864.w);
        vec4 _3238;
        if (int(0.5 - _3267) == 5)
        {
            int _3403 = int(_3265.x + 0.5);
            int _3406 = int(_3265.y + 0.5);
            vec4 _3384 = vec4(0.0);
            float _3385 = 0.0;
            float _3386 = 0.0;
            vec4 _12773 = vec4(0.0);
            float _12774 = 0.0;
            vec4 _12788 = vec4(0.0);
            float _12789 = 0.0;
            float _3387 = 0.0;
            int _3390 = 0;
            bool _3391;
            bool _3393;
            float _3394;
            float _3395;
            bool _3398;
            bool _3899;
            float _3900;
            uint _3901;
            vec2 _3902;
            float _3903;
            float _3904;
            float _3905;
            float _3906;
            float _3907;
            float _3908;
            float _3909;
            float _3910;
            float _3911;
            float _3912;
            float _3913;
            float _3914;
            int _3915;
            int _3916;
            int _3917;
            bool _3918;
            float _3919;
            float _4631;
            float _4679;
            float _4745;
            float _4754;
            float _4763;
            float _4791;
            float _4800;
            float _4809;
            float _4818;
            float _4819;
            float _4884;
            float _4897;
            float _4898;
            float _4963;
            float _4976;
            float _4985;
            bool _4995;
            float _4996;
            float _4997;
            float _4998;
            float _4999;
            float _5000;
            bool _5090;
            bool _5107;
            float _5141;
            float _5150;
            float _5159;
            bool _5181;
            float _5182;
            float _5183;
            float _5184;
            float _5185;
            float _5186;
            bool _5276;
            bool _5293;
            float _5308;
            float _5317;
            bool _5327;
            bool _5328;
            bool _5333;
            float _5334;
            bool _5335;
            bool _5651;
            float _5652;
            uint _5653;
            vec2 _5654;
            float _5655;
            float _5656;
            float _5657;
            float _5658;
            float _5659;
            float _5660;
            float _5661;
            float _5662;
            float _5663;
            float _5664;
            float _5665;
            float _5666;
            int _5667;
            int _5668;
            int _5669;
            bool _5670;
            float _5671;
            float _6383;
            float _6431;
            float _6497;
            float _6506;
            float _6515;
            float _6543;
            float _6552;
            float _6561;
            float _6570;
            float _6571;
            float _6636;
            float _6649;
            float _6650;
            float _6715;
            float _6728;
            float _6737;
            bool _6747;
            float _6748;
            float _6749;
            float _6750;
            float _6751;
            float _6752;
            bool _6842;
            bool _6859;
            float _6893;
            float _6902;
            float _6911;
            bool _6933;
            float _6934;
            float _6935;
            float _6936;
            float _6937;
            float _6938;
            bool _7028;
            bool _7045;
            float _7060;
            float _7069;
            bool _7079;
            bool _7080;
            bool _7085;
            float _7086;
            bool _7087;
            float _7187;
            float _7204;
            float _7221;
            float _7237;
            float _7252;
            float _7461;
            float _7462;
            float _7502;
            float _7503;
            float _7543;
            float _7544;
            float _7620;
            float _7621;
            float _7651;
            float _7652;
            vec4 _7682;
            vec4 _12611;
            float _12612;
            vec3 _12640;
            vec3 _12684;
            vec4 _12813;
            float _12814;
            vec4 _12822;
            float _12823;
            for (;;)
            {
                bool _3410_ladder_break = false;
                do
                {
                    if (!(_3390 < _3403))
                    {
                        _3410_ladder_break = true;
                        break;
                    }
                    int _3572 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _3577 = ((_12865.y * _3572) + _12865.x) + (1 + (_3390 * 6));
                    ivec2 _3580 = ivec2(_3577 - _3572 * (_3577 / _3572), _3577 / _3572);
                    vec4 _3423 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(_3580, 0).xy, 0);
                    int _3590 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _3595 = ((_3580.y * _3590) + _3580.x) + 1;
                    vec4 _3429 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_3595 - _3590 * (_3595 / _3590), _3595 / _3590), 0).xy, 0);
                    int _3432 = int(_3423.x);
                    int _3433 = _3432 & 32767;
                    int _3435 = int(_3423.y);
                    int _3438 = (_3432 >> 15) & 1;
                    int _3440 = floatBitsToInt(_3423.z);
                    int _3441 = _3440 & 65535;
                    int _3443 = (_3440 >> 16) & 65535;
                    float _3603 = _3429.y;
                    float _3641 = (_12863.y * _3603) + _3429.w;
                    float _3645 = max(abs(_3383.y * _3603) * 0.5, 9.9999997473787516355514526367188e-06);
                    int _3648 = clamp(int(_3641 - _3645), 0, _3441);
                    int _3652 = max(_3648, clamp(int(_3641 + _3645), 0, _3441));
                    float _3609 = _3429.x;
                    float _3663 = (_12863.x * _3609) + _3429.z;
                    float _3667 = max(abs(_3383.x * _3609) * 0.5, 9.9999997473787516355514526367188e-06);
                    int _3670 = clamp(int(_3663 - _3667), 0, _3443);
                    int _3674 = max(_3670, clamp(int(_3663 + _3667), 0, _3443));
                    float _3613 = _3248.x;
                    float _3682 = 0.0;
                    float _3683 = 0.0;
                    bool _3689 = _3648 != _3652;
                    int _3684 = _3648;
                    for (;;)
                    {
                        if (!(_3684 <= _3652))
                        {
                            break;
                        }
                        int _3766 = _3433 + _3684;
                        ivec2 _3768 = ivec2(_3766, _3435);
                        _3768.y = _3768.y + (_3766 >> 12);
                        _3768.x = _3768.x & 4095;
                        uvec4 _3705 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_3768, _3277, 0).xyz, 0);
                        int _3782 = _3433 + int(_3705.y);
                        ivec2 _3784 = ivec2(_3782, _3435);
                        _3784.y = _3784.y + (_3782 >> 12);
                        _3784.x = _3784.x & 4095;
                        int _3712 = int(_3705.x);
                        int _3685 = 0;
                        for (;;)
                        {
                            bool _3715_ladder_break = false;
                            do
                            {
                                if (!(_3685 < _3712))
                                {
                                    _3715_ladder_break = true;
                                    break;
                                }
                                int _3798 = _3784.x + _3685;
                                ivec2 _3800 = ivec2(_3798, _3784.y);
                                _3800.y = _3800.y + (_3798 >> 12);
                                _3800.x = _3800.x & 4095;
                                uvec4 _3727 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_3800, _3277, 0).xyz, 0);
                                if (_3689)
                                {
                                    if (_3684 != max(int(_3727.x >> 12u), _3648))
                                    {
                                        break;
                                    }
                                }
                                ivec2 _3822 = ivec2(int(_3727.x & 4095u), int(_3727.y & 16383u));
                                int _3827 = int(_3727.y >> 14u);
                                vec4 _3834 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3822, _3277, 0).xyz, 0);
                                int _3872 = _3822.x + 1;
                                ivec2 _3874 = ivec2(_3872, _3822.y);
                                _3874.y = _3874.y + (_3872 >> 12);
                                _3874.x = _3874.x & 4095;
                                vec4 _3840 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3874, _3277, 0).xyz, 0);
                                int _12679 = _3827;
                                vec2 _12680 = _3834.xy;
                                vec2 _12681 = _3834.zw;
                                vec2 _12682 = _3840.xy;
                                vec2 _12683 = _3840.zw;
                                if (_3827 == 1)
                                {
                                    int _3887 = _3822.x + 2;
                                    ivec2 _3889 = ivec2(_3887, _3822.y);
                                    _3889.y = _3889.y + (_3887 >> 12);
                                    _3889.x = _3889.x & 4095;
                                    _12684 = vec3(texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3889, _3277, 0).xyz, 0).wxy);
                                }
                                else
                                {
                                    _12684 = vec3(1.0);
                                }
                                int _12711 = _12679;
                                vec2 _12712 = _12680;
                                vec2 _12713 = _12681;
                                vec2 _12714 = _12682;
                                vec2 _12715 = _12683;
                                vec3 _12716 = _12684;
                                do
                                {
                                    if (true)
                                    {
                                        do
                                        {
                                            if (_12711 == 3)
                                            {
                                                _4679 = max(_12712.x, _12714.x);
                                                break;
                                            }
                                            if (_12711 == 2)
                                            {
                                                _4679 = max(max(_12712.x, _12713.x), max(_12714.x, _12715.x));
                                                break;
                                            }
                                            _4679 = max(max(_12712.x, _12713.x), _12714.x);
                                            break;
                                        } while(false);
                                        _3900 = _4679 - _12863.x;
                                    }
                                    else
                                    {
                                        do
                                        {
                                            if (_12711 == 3)
                                            {
                                                _4631 = max(_12712.y, _12714.y);
                                                break;
                                            }
                                            if (_12711 == 2)
                                            {
                                                _4631 = max(max(_12712.y, _12713.y), max(_12714.y, _12715.y));
                                                break;
                                            }
                                            _4631 = max(max(_12712.y, _12713.y), _12714.y);
                                            break;
                                        } while(false);
                                        _3900 = _4631 - _12863.y;
                                    }
                                    if ((_3900 * _3613) < (-0.5))
                                    {
                                        _3899 = false;
                                        break;
                                    }
                                    if (_12711 == 0)
                                    {
                                        float _3946 = _12712.x - _12863.x;
                                        float _3949 = _12712.y - _12863.y;
                                        float _3953 = _12713.x - _12863.x;
                                        float _3955 = _12713.y - _12863.y;
                                        float _3959 = _12714.x - _12863.x;
                                        float _3961 = _12714.y - _12863.y;
                                        if (true)
                                        {
                                            if (abs(_3949) <= 1.52587890625e-05)
                                            {
                                                _4791 = 0.0;
                                            }
                                            else
                                            {
                                                _4791 = _3949;
                                            }
                                            if (abs(_3955) <= 1.52587890625e-05)
                                            {
                                                _4800 = 0.0;
                                            }
                                            else
                                            {
                                                _4800 = _3955;
                                            }
                                            if (abs(_3961) <= 1.52587890625e-05)
                                            {
                                                _4809 = 0.0;
                                            }
                                            else
                                            {
                                                _4809 = _3961;
                                            }
                                            _3901 = (11892u >> (((floatBitsToUint(_4809) >> 29u) & 4u) | ((((floatBitsToUint(_4800) >> 30u) & 2u) | ((floatBitsToUint(_4791) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                                        }
                                        else
                                        {
                                            if (abs(_3946) <= 1.52587890625e-05)
                                            {
                                                _4745 = 0.0;
                                            }
                                            else
                                            {
                                                _4745 = _3946;
                                            }
                                            if (abs(_3953) <= 1.52587890625e-05)
                                            {
                                                _4754 = 0.0;
                                            }
                                            else
                                            {
                                                _4754 = _3953;
                                            }
                                            if (abs(_3959) <= 1.52587890625e-05)
                                            {
                                                _4763 = 0.0;
                                            }
                                            else
                                            {
                                                _4763 = _3959;
                                            }
                                            _3901 = (11892u >> (((floatBitsToUint(_4763) >> 29u) & 4u) | ((((floatBitsToUint(_4754) >> 30u) & 2u) | ((floatBitsToUint(_4745) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                                        }
                                        if (_3901 == 0u)
                                        {
                                            _3899 = true;
                                            break;
                                        }
                                        if (true)
                                        {
                                            float _4903 = (_3946 - (_3953 * 2.0)) + _3959;
                                            float _4906 = (_3949 - (_3955 * 2.0)) + _3961;
                                            float _4908 = _3949 - _3955;
                                            if (abs(_4906) < 1.52587890625e-05)
                                            {
                                                if (abs(_4908) < 1.52587890625e-05)
                                                {
                                                    _4897 = 0.0;
                                                }
                                                else
                                                {
                                                    _4897 = (_3949 * 0.5) / _4908;
                                                }
                                                _4898 = _4897;
                                            }
                                            else
                                            {
                                                float _4913 = _4906 * _3949;
                                                float _4914 = (_4908 * _4908) - _4913;
                                                if (_4914 <= (max(_4908 * _4908, abs(_4913)) * 3.0000001061125658452510833740234e-06))
                                                {
                                                    _4963 = 0.0;
                                                }
                                                else
                                                {
                                                    _4963 = sqrt(_4914);
                                                }
                                                if (_4908 >= 0.0)
                                                {
                                                    float _4928 = _4908 + _4963;
                                                    if (abs(_4928) < 1.52587890625e-05)
                                                    {
                                                        _4897 = 0.0;
                                                    }
                                                    else
                                                    {
                                                        _4897 = _3949 / _4928;
                                                    }
                                                    _4898 = _4928 / _4906;
                                                }
                                                else
                                                {
                                                    float _4918 = _4908 - _4963;
                                                    if (abs(_4918) < 1.52587890625e-05)
                                                    {
                                                        _4897 = 0.0;
                                                    }
                                                    else
                                                    {
                                                        _4897 = _3949 / _4918;
                                                    }
                                                    float _4926 = _4897;
                                                    _4897 = _4918 / _4906;
                                                    _4898 = _4926;
                                                }
                                            }
                                            float _4949 = (_3946 - _3953) * 2.0;
                                            _3902 = vec2(((((_4903 * _4897) - _4949) * _4897) + _3946) * _3613, ((((_4903 * _4898) - _4949) * _4898) + _3946) * _3613);
                                        }
                                        else
                                        {
                                            float _4824 = (_3946 - (_3953 * 2.0)) + _3959;
                                            float _4827 = (_3949 - (_3955 * 2.0)) + _3961;
                                            float _4828 = _3946 - _3953;
                                            if (abs(_4824) < 1.52587890625e-05)
                                            {
                                                if (abs(_4828) < 1.52587890625e-05)
                                                {
                                                    _4818 = 0.0;
                                                }
                                                else
                                                {
                                                    _4818 = (_3946 * 0.5) / _4828;
                                                }
                                                _4819 = _4818;
                                            }
                                            else
                                            {
                                                float _4834 = _4824 * _3946;
                                                float _4835 = (_4828 * _4828) - _4834;
                                                if (_4835 <= (max(_4828 * _4828, abs(_4834)) * 3.0000001061125658452510833740234e-06))
                                                {
                                                    _4884 = 0.0;
                                                }
                                                else
                                                {
                                                    _4884 = sqrt(_4835);
                                                }
                                                if (_4828 >= 0.0)
                                                {
                                                    float _4849 = _4828 + _4884;
                                                    if (abs(_4849) < 1.52587890625e-05)
                                                    {
                                                        _4818 = 0.0;
                                                    }
                                                    else
                                                    {
                                                        _4818 = _3946 / _4849;
                                                    }
                                                    _4819 = _4849 / _4824;
                                                }
                                                else
                                                {
                                                    float _4839 = _4828 - _4884;
                                                    if (abs(_4839) < 1.52587890625e-05)
                                                    {
                                                        _4818 = 0.0;
                                                    }
                                                    else
                                                    {
                                                        _4818 = _3946 / _4839;
                                                    }
                                                    float _4847 = _4818;
                                                    _4818 = _4839 / _4824;
                                                    _4819 = _4847;
                                                }
                                            }
                                            float _4870 = (_3949 - _3955) * 2.0;
                                            _3902 = vec2(((((_4827 * _4818) - _4870) * _4818) + _3949) * _3613, ((((_4827 * _4819) - _4870) * _4819) + _3949) * _3613);
                                        }
                                        if ((_3901 & 1u) != 0u)
                                        {
                                            if (true)
                                            {
                                                _3900 = 1.0;
                                            }
                                            else
                                            {
                                                _3900 = -1.0;
                                            }
                                            _3682 += (_3900 * clamp(_3902.x + 0.5, 0.0, 1.0));
                                            _3683 = max(_3683, clamp(1.0 - (abs(_3902.x) * 2.0), 0.0, 1.0));
                                        }
                                        if (_3901 > 1u)
                                        {
                                            if (true)
                                            {
                                                _3900 = -1.0;
                                            }
                                            else
                                            {
                                                _3900 = 1.0;
                                            }
                                            _3682 += (_3900 * clamp(_3902.y + 0.5, 0.0, 1.0));
                                            _3683 = max(_3683, clamp(1.0 - (abs(_3902.y) * 2.0), 0.0, 1.0));
                                        }
                                        _3899 = true;
                                        break;
                                    }
                                    if (_12711 == 3)
                                    {
                                        float _4026 = _12712.x - _12863.x;
                                        float _4029 = _12712.y - _12863.y;
                                        float _4033 = _12714.x - _12863.x;
                                        float _4035 = _12714.y - _12863.y;
                                        do
                                        {
                                            if (true)
                                            {
                                                _3903 = _4029;
                                            }
                                            else
                                            {
                                                _3903 = _4026;
                                            }
                                            if (true)
                                            {
                                                _3904 = _4035;
                                            }
                                            else
                                            {
                                                _3904 = _4033;
                                            }
                                            if (abs(_3903) <= 1.52587890625e-05)
                                            {
                                                _4976 = 0.0;
                                            }
                                            else
                                            {
                                                _4976 = _3903;
                                            }
                                            if (abs(_3904) <= 1.52587890625e-05)
                                            {
                                                _4985 = 0.0;
                                            }
                                            else
                                            {
                                                _4985 = _3904;
                                            }
                                            if ((_4976 < 0.0) == (_4985 < 0.0))
                                            {
                                                break;
                                            }
                                            float _4055 = _3904 - _3903;
                                            if (abs(_4055) < 1.0000000133514319600180897396058e-10)
                                            {
                                                break;
                                            }
                                            float _4063 = clamp((-_3903) / _4055, 0.0, 1.0);
                                            if (true)
                                            {
                                                _3905 = _4035 - _4029;
                                            }
                                            else
                                            {
                                                _3905 = _4026 - _4033;
                                            }
                                            if (abs(_3905) <= 9.9999997473787516355514526367188e-06)
                                            {
                                                break;
                                            }
                                            if (true)
                                            {
                                                _3900 = _4026 + ((_4033 - _4026) * _4063);
                                            }
                                            else
                                            {
                                                _3900 = _4029 + ((_4035 - _4029) * _4063);
                                            }
                                            float _4083 = _3900;
                                            float _4084 = _4083 * _3613;
                                            if (_3905 > 0.0)
                                            {
                                                _3900 = 1.0;
                                            }
                                            else
                                            {
                                                _3900 = -1.0;
                                            }
                                            _3682 += (_3900 * clamp(_4084 + 0.5, 0.0, 1.0));
                                            _3683 = max(_3683, clamp(1.0 - (abs(_4084) * 2.0), 0.0, 1.0));
                                            break;
                                        } while(false);
                                        _3899 = true;
                                        break;
                                    }
                                    if (_12711 == 1)
                                    {
                                        do
                                        {
                                            do
                                            {
                                                if (true)
                                                {
                                                    _4996 = _12863.y;
                                                }
                                                else
                                                {
                                                    _4996 = _12863.x;
                                                }
                                                if (_12711 == 2)
                                                {
                                                    if (true)
                                                    {
                                                        _4997 = _12712.y;
                                                    }
                                                    else
                                                    {
                                                        _4997 = _12712.x;
                                                    }
                                                    if (true)
                                                    {
                                                        _4998 = _12713.y;
                                                    }
                                                    else
                                                    {
                                                        _4998 = _12713.x;
                                                    }
                                                    if (true)
                                                    {
                                                        _4999 = _12714.y;
                                                    }
                                                    else
                                                    {
                                                        _4999 = _12714.x;
                                                    }
                                                    if (true)
                                                    {
                                                        _5000 = _12715.y;
                                                    }
                                                    else
                                                    {
                                                        _5000 = _12715.x;
                                                    }
                                                    if ((min(min(_4997, _4998), min(_4999, _5000)) - _4996) <= 1.52587890625e-05)
                                                    {
                                                        _5090 = (max(max(_4997, _4998), max(_4999, _5000)) - _4996) >= (-1.52587890625e-05);
                                                    }
                                                    else
                                                    {
                                                        _5090 = false;
                                                    }
                                                    _4995 = _5090;
                                                    break;
                                                }
                                                if (true)
                                                {
                                                    _4997 = _12712.y;
                                                }
                                                else
                                                {
                                                    _4997 = _12712.x;
                                                }
                                                if (true)
                                                {
                                                    _4998 = _12713.y;
                                                }
                                                else
                                                {
                                                    _4998 = _12713.x;
                                                }
                                                if (true)
                                                {
                                                    _4999 = _12714.y;
                                                }
                                                else
                                                {
                                                    _4999 = _12714.x;
                                                }
                                                if ((min(min(_4997, _4998), _4999) - _4996) <= 1.52587890625e-05)
                                                {
                                                    _5107 = (max(max(_4997, _4998), _4999) - _4996) >= (-1.52587890625e-05);
                                                }
                                                else
                                                {
                                                    _5107 = false;
                                                }
                                                _4995 = _5107;
                                                break;
                                            } while(false);
                                            if (!_4995)
                                            {
                                                break;
                                            }
                                            if (true)
                                            {
                                                _3903 = _12863.y;
                                            }
                                            else
                                            {
                                                _3903 = _12863.x;
                                            }
                                            if (true)
                                            {
                                                _3904 = _12863.x;
                                            }
                                            else
                                            {
                                                _3904 = _12863.y;
                                            }
                                            if (true)
                                            {
                                                _3905 = _12712.y;
                                            }
                                            else
                                            {
                                                _3905 = _12712.x;
                                            }
                                            if (true)
                                            {
                                                _3906 = _12713.y;
                                            }
                                            else
                                            {
                                                _3906 = _12713.x;
                                            }
                                            if (true)
                                            {
                                                _3907 = _12714.y;
                                            }
                                            else
                                            {
                                                _3907 = _12714.x;
                                            }
                                            if (true)
                                            {
                                                _3909 = _12712.x;
                                            }
                                            else
                                            {
                                                _3909 = _12712.y;
                                            }
                                            if (true)
                                            {
                                                _3910 = _12713.x;
                                            }
                                            else
                                            {
                                                _3910 = _12713.y;
                                            }
                                            if (true)
                                            {
                                                _3911 = _12714.x;
                                            }
                                            else
                                            {
                                                _3911 = _12714.y;
                                            }
                                            float _4182 = _12716.x * (_3905 - _3903);
                                            float _4187 = _12716.y * (_3906 - _3903);
                                            float _4192 = _12716.z * (_3907 - _3903);
                                            if (abs(_4182) <= 1.52587890625e-05)
                                            {
                                                _5141 = 0.0;
                                            }
                                            else
                                            {
                                                _5141 = _4182;
                                            }
                                            if (abs(_4187) <= 1.52587890625e-05)
                                            {
                                                _5150 = 0.0;
                                            }
                                            else
                                            {
                                                _5150 = _4187;
                                            }
                                            if (abs(_4192) <= 1.52587890625e-05)
                                            {
                                                _5159 = 0.0;
                                            }
                                            else
                                            {
                                                _5159 = _4192;
                                            }
                                            uint _5140 = (11892u >> (((floatBitsToUint(_5159) >> 29u) & 4u) | ((((floatBitsToUint(_5150) >> 30u) & 2u) | ((floatBitsToUint(_5141) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                                            if (_5140 == 0u)
                                            {
                                                break;
                                            }
                                            if (_5140 == 257u)
                                            {
                                                _3915 = 2;
                                            }
                                            else
                                            {
                                                _3915 = 1;
                                            }
                                            float _4203 = (_4182 - (2.0 * _4187)) + _4192;
                                            float _4204 = _4187 - _4182;
                                            float _4205 = 2.0 * _4204;
                                            if (abs(_4203) < 1.52587890625e-05)
                                            {
                                                if (abs(_4205) >= 1.52587890625e-05)
                                                {
                                                    _3916 = 1;
                                                    _3908 = (-_4182) / _4205;
                                                }
                                                else
                                                {
                                                    _3916 = 0;
                                                    _3908 = 0.0;
                                                }
                                                float _4229 = _3908;
                                                _3908 = 0.0;
                                                _3912 = _4229;
                                            }
                                            else
                                            {
                                                float _4214 = sqrt(max((_4205 * _4205) - ((4.0 * _4203) * _4182), 0.0));
                                                float _4215 = 0.5 / _4203;
                                                float _4216 = _4204 * (-2.0);
                                                _3916 = 2;
                                                _3908 = (_4216 + _4214) * _4215;
                                                _3912 = (_4216 - _4214) * _4215;
                                            }
                                            if (_3916 == 0)
                                            {
                                                break;
                                            }
                                            if (_3915 == 1)
                                            {
                                                if (_3916 == 2)
                                                {
                                                    _3918 = max(max(0.0, -_3908), _3908 - 1.0) < max(max(0.0, -_3912), _3912 - 1.0);
                                                }
                                                else
                                                {
                                                    _3918 = false;
                                                }
                                                if (_3918)
                                                {
                                                    _3913 = _3908;
                                                }
                                                else
                                                {
                                                    _3913 = _3912;
                                                }
                                                _3913 = clamp(_3913, 0.0, 1.0);
                                                _3917 = 1;
                                                _3914 = 0.0;
                                            }
                                            else
                                            {
                                                _3913 = clamp(_3912, 0.0, 1.0);
                                                _3917 = 2;
                                                _3914 = clamp(_3908, 0.0, 1.0);
                                            }
                                            float _4263 = _3905 * _12716.x;
                                            float _4270 = (_4263 - ((2.0 * _3906) * _12716.y)) + (_3907 * _12716.z);
                                            float _4274 = 2.0 * ((_3906 * _12716.y) - _4263);
                                            float _4276 = _3909 * _12716.x;
                                            float _4283 = (_4276 - ((2.0 * _3910) * _12716.y)) + (_3911 * _12716.z);
                                            float _4287 = 2.0 * ((_3910 * _12716.y) - _4276);
                                            float _4290 = (_12716.x - (2.0 * _12716.y)) + _12716.z;
                                            float _4292 = 2.0 * (_12716.y - _12716.x);
                                            float _4315;
                                            float _4319;
                                            do
                                            {
                                                float _4301 = max((((_4290 * _3913) + _4292) * _3913) + _12716.x, 1.52587890625e-05);
                                                _4315 = 2.0 * _4270;
                                                _4319 = 2.0 * _4290;
                                                float _4327 = ((((_4315 * _3913) + _4274) * _4301) - (((((_4270 * _3913) + _4274) * _3913) + _4263) * ((_4319 * _3913) + _4292))) / (_4301 * _4301);
                                                if (false)
                                                {
                                                    _3919 = -_4327;
                                                }
                                                else
                                                {
                                                    _3919 = _4327;
                                                }
                                                if (abs(_3919) <= 9.9999997473787516355514526367188e-06)
                                                {
                                                    break;
                                                }
                                                float _4340 = ((((((_4283 * _3913) + _4287) * _3913) + _4276) / _4301) - _3904) * _3613;
                                                if (_3919 > 0.0)
                                                {
                                                    _3900 = 1.0;
                                                }
                                                else
                                                {
                                                    _3900 = -1.0;
                                                }
                                                _3682 += (_3900 * clamp(_4340 + 0.5, 0.0, 1.0));
                                                _3683 = max(_3683, clamp(1.0 - (abs(_4340) * 2.0), 0.0, 1.0));
                                                break;
                                            } while(false);
                                            if (_3917 == 2)
                                            {
                                                do
                                                {
                                                    float _4370 = max((((_4290 * _3914) + _4292) * _3914) + _12716.x, 1.52587890625e-05);
                                                    float _4394 = ((((_4315 * _3914) + _4274) * _4370) - (((((_4270 * _3914) + _4274) * _3914) + _4263) * ((_4319 * _3914) + _4292))) / (_4370 * _4370);
                                                    if (false)
                                                    {
                                                        _3919 = -_4394;
                                                    }
                                                    else
                                                    {
                                                        _3919 = _4394;
                                                    }
                                                    if (abs(_3919) <= 9.9999997473787516355514526367188e-06)
                                                    {
                                                        break;
                                                    }
                                                    float _4406 = ((((((_4283 * _3914) + _4287) * _3914) + _4276) / _4370) - _3904) * _3613;
                                                    if (_3919 > 0.0)
                                                    {
                                                        _3900 = 1.0;
                                                    }
                                                    else
                                                    {
                                                        _3900 = -1.0;
                                                    }
                                                    _3682 += (_3900 * clamp(_4406 + 0.5, 0.0, 1.0));
                                                    _3683 = max(_3683, clamp(1.0 - (abs(_4406) * 2.0), 0.0, 1.0));
                                                    break;
                                                } while(false);
                                            }
                                            break;
                                        } while(false);
                                        _3899 = true;
                                        break;
                                    }
                                    do
                                    {
                                        do
                                        {
                                            if (true)
                                            {
                                                _5182 = _12863.y;
                                            }
                                            else
                                            {
                                                _5182 = _12863.x;
                                            }
                                            if (_12711 == 2)
                                            {
                                                if (true)
                                                {
                                                    _5183 = _12712.y;
                                                }
                                                else
                                                {
                                                    _5183 = _12712.x;
                                                }
                                                if (true)
                                                {
                                                    _5184 = _12713.y;
                                                }
                                                else
                                                {
                                                    _5184 = _12713.x;
                                                }
                                                if (true)
                                                {
                                                    _5185 = _12714.y;
                                                }
                                                else
                                                {
                                                    _5185 = _12714.x;
                                                }
                                                if (true)
                                                {
                                                    _5186 = _12715.y;
                                                }
                                                else
                                                {
                                                    _5186 = _12715.x;
                                                }
                                                if ((min(min(_5183, _5184), min(_5185, _5186)) - _5182) <= 1.52587890625e-05)
                                                {
                                                    _5276 = (max(max(_5183, _5184), max(_5185, _5186)) - _5182) >= (-1.52587890625e-05);
                                                }
                                                else
                                                {
                                                    _5276 = false;
                                                }
                                                _5181 = _5276;
                                                break;
                                            }
                                            if (true)
                                            {
                                                _5183 = _12712.y;
                                            }
                                            else
                                            {
                                                _5183 = _12712.x;
                                            }
                                            if (true)
                                            {
                                                _5184 = _12713.y;
                                            }
                                            else
                                            {
                                                _5184 = _12713.x;
                                            }
                                            if (true)
                                            {
                                                _5185 = _12714.y;
                                            }
                                            else
                                            {
                                                _5185 = _12714.x;
                                            }
                                            if ((min(min(_5183, _5184), _5185) - _5182) <= 1.52587890625e-05)
                                            {
                                                _5293 = (max(max(_5183, _5184), _5185) - _5182) >= (-1.52587890625e-05);
                                            }
                                            else
                                            {
                                                _5293 = false;
                                            }
                                            _5181 = _5293;
                                            break;
                                        } while(false);
                                        if (!_5181)
                                        {
                                            break;
                                        }
                                        if (true)
                                        {
                                            _3903 = _12863.y;
                                        }
                                        else
                                        {
                                            _3903 = _12863.x;
                                        }
                                        if (true)
                                        {
                                            _3904 = _12863.x;
                                        }
                                        else
                                        {
                                            _3904 = _12863.y;
                                        }
                                        if (true)
                                        {
                                            _3905 = _12712.y;
                                        }
                                        else
                                        {
                                            _3905 = _12712.x;
                                        }
                                        if (true)
                                        {
                                            _3906 = _12713.y;
                                        }
                                        else
                                        {
                                            _3906 = _12713.x;
                                        }
                                        if (true)
                                        {
                                            _3907 = _12714.y;
                                        }
                                        else
                                        {
                                            _3907 = _12714.x;
                                        }
                                        if (true)
                                        {
                                            _3908 = _12715.y;
                                        }
                                        else
                                        {
                                            _3908 = _12715.x;
                                        }
                                        if (true)
                                        {
                                            _3909 = _12712.x;
                                        }
                                        else
                                        {
                                            _3909 = _12712.y;
                                        }
                                        if (true)
                                        {
                                            _3910 = _12713.x;
                                        }
                                        else
                                        {
                                            _3910 = _12713.y;
                                        }
                                        if (true)
                                        {
                                            _3911 = _12714.x;
                                        }
                                        else
                                        {
                                            _3911 = _12714.y;
                                        }
                                        if (true)
                                        {
                                            _3912 = _12715.x;
                                        }
                                        else
                                        {
                                            _3912 = _12715.y;
                                        }
                                        float _4519 = 3.0 * _3906;
                                        float _4522 = 3.0 * _3907;
                                        float _4525 = ((_4519 - _3905) - _4522) + _3908;
                                        float _4531 = ((3.0 * _3905) - (6.0 * _3906)) + _4522;
                                        float _4534 = ((-3.0) * _3905) + _4519;
                                        float _4537 = _3905 - _3903;
                                        float _4540 = _3908 - _3903;
                                        if (abs(_4537) <= 1.52587890625e-05)
                                        {
                                            _5308 = 0.0;
                                        }
                                        else
                                        {
                                            _5308 = _4537;
                                        }
                                        if (abs(_4540) <= 1.52587890625e-05)
                                        {
                                            _5317 = 0.0;
                                        }
                                        else
                                        {
                                            _5317 = _4540;
                                        }
                                        if ((_5308 < 0.0) == (_5317 < 0.0))
                                        {
                                            break;
                                        }
                                        float _3920 = 0.0;
                                        if (abs(_4537) <= 1.52587890625e-05)
                                        {
                                            _3920 = 0.0;
                                        }
                                        else
                                        {
                                            if (abs(_4540) <= 1.52587890625e-05)
                                            {
                                                _3920 = 1.0;
                                            }
                                            else
                                            {
                                                do
                                                {
                                                    _3920 = 0.0;
                                                    if (_4537 < (-1.52587890625e-05))
                                                    {
                                                        _5328 = _4540 < (-1.52587890625e-05);
                                                    }
                                                    else
                                                    {
                                                        _5328 = false;
                                                    }
                                                    if (_5328)
                                                    {
                                                        _5328 = true;
                                                    }
                                                    else
                                                    {
                                                        if (_4537 > 1.52587890625e-05)
                                                        {
                                                            _5328 = _4540 > 1.52587890625e-05;
                                                        }
                                                        else
                                                        {
                                                            _5328 = false;
                                                        }
                                                    }
                                                    if (_5328)
                                                    {
                                                        _5327 = false;
                                                        break;
                                                    }
                                                    bool _5356 = _4540 >= _4537;
                                                    float _5329 = 0.5;
                                                    float _5330 = 0.0;
                                                    float _5331 = 1.0;
                                                    int _5332 = 0;
                                                    for (;;)
                                                    {
                                                        if (!(_5332 < 16))
                                                        {
                                                            break;
                                                        }
                                                        float _5373 = (((((_4525 * _5329) + _4531) * _5329) + _4534) * _5329) + _4537;
                                                        if (_5356)
                                                        {
                                                            _5328 = _5373 < 0.0;
                                                        }
                                                        else
                                                        {
                                                            _5328 = false;
                                                        }
                                                        if (_5328)
                                                        {
                                                            _5333 = true;
                                                        }
                                                        else
                                                        {
                                                            if (!_5356)
                                                            {
                                                                _5333 = _5373 > 0.0;
                                                            }
                                                            else
                                                            {
                                                                _5333 = false;
                                                            }
                                                        }
                                                        if (_5333)
                                                        {
                                                            _5330 = _5329;
                                                        }
                                                        else
                                                        {
                                                            _5331 = _5329;
                                                        }
                                                        float _5400 = ((((3.0 * _4525) * _5329) + (2.0 * _4531)) * _5329) + _4534;
                                                        float _5404 = (_5330 + _5331) * 0.5;
                                                        if (abs(_5400) >= 9.9999999747524270787835121154785e-07)
                                                        {
                                                            float _5411 = _5329 - (_5373 / _5400);
                                                            if (_5411 > _5330)
                                                            {
                                                                _5335 = _5411 < _5331;
                                                            }
                                                            else
                                                            {
                                                                _5335 = false;
                                                            }
                                                            if (_5335)
                                                            {
                                                                _5334 = _5411;
                                                            }
                                                            else
                                                            {
                                                                _5334 = _5404;
                                                            }
                                                        }
                                                        else
                                                        {
                                                            _5334 = _5404;
                                                        }
                                                        _5329 = _5334;
                                                        _5332++;
                                                        continue;
                                                    }
                                                    _3920 = _5329;
                                                    _5327 = true;
                                                    break;
                                                } while(false);
                                                if (!_5327)
                                                {
                                                    break;
                                                }
                                            }
                                        }
                                        float _4565 = 3.0 * _3910;
                                        float _4568 = 3.0 * _3911;
                                        if (_3920 == 1.0)
                                        {
                                            _3913 = _3912;
                                        }
                                        else
                                        {
                                            _3913 = ((((((((_4565 - _3909) - _4568) + _3912) * _3920) + (((3.0 * _3909) - (6.0 * _3910)) + _4568)) * _3920) + (((-3.0) * _3909) + _4565)) * _3920) + _3909;
                                        }
                                        if (true)
                                        {
                                            _3914 = _3908 - _3905;
                                        }
                                        else
                                        {
                                            _3914 = _3905 - _3908;
                                        }
                                        float _4609 = (_3913 - _3904) * _3613;
                                        if (_3914 > 0.0)
                                        {
                                            _3900 = 1.0;
                                        }
                                        else
                                        {
                                            _3900 = -1.0;
                                        }
                                        _3682 += (_3900 * clamp(_4609 + 0.5, 0.0, 1.0));
                                        _3683 = max(_3683, clamp(1.0 - (abs(_4609) * 2.0), 0.0, 1.0));
                                        break;
                                    } while(false);
                                    _3899 = true;
                                    break;
                                } while(false);
                                if (!_3899)
                                {
                                    _3715_ladder_break = true;
                                    break;
                                }
                                break;
                            } while(false);
                            if (_3715_ladder_break)
                            {
                                break;
                            }
                            _3685++;
                            continue;
                        }
                        _3684++;
                        continue;
                    }
                    vec2 _3760 = vec2(_3682, _3683);
                    float _3617 = _3248.y;
                    int _3618 = _3441 + 1;
                    float _5434 = 0.0;
                    float _5435 = 0.0;
                    bool _5441 = _3670 != _3674;
                    int _5436 = _3670;
                    for (;;)
                    {
                        if (!(_5436 <= _3674))
                        {
                            break;
                        }
                        int _5518 = _3433 + (_3618 + _5436);
                        ivec2 _5520 = ivec2(_5518, _3435);
                        _5520.y = _5520.y + (_5518 >> 12);
                        _5520.x = _5520.x & 4095;
                        uvec4 _5457 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5520, _3277, 0).xyz, 0);
                        int _5534 = _3433 + int(_5457.y);
                        ivec2 _5536 = ivec2(_5534, _3435);
                        _5536.y = _5536.y + (_5534 >> 12);
                        _5536.x = _5536.x & 4095;
                        int _5464 = int(_5457.x);
                        int _5437 = 0;
                        for (;;)
                        {
                            bool _5467_ladder_break = false;
                            do
                            {
                                if (!(_5437 < _5464))
                                {
                                    _5467_ladder_break = true;
                                    break;
                                }
                                int _5550 = _5536.x + _5437;
                                ivec2 _5552 = ivec2(_5550, _5536.y);
                                _5552.y = _5552.y + (_5550 >> 12);
                                _5552.x = _5552.x & 4095;
                                uvec4 _5479 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5552, _3277, 0).xyz, 0);
                                if (_5441)
                                {
                                    if (_5436 != max(int(_5479.x >> 12u), _3670))
                                    {
                                        break;
                                    }
                                }
                                ivec2 _5574 = ivec2(int(_5479.x & 4095u), int(_5479.y & 16383u));
                                int _5579 = int(_5479.y >> 14u);
                                vec4 _5586 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5574, _3277, 0).xyz, 0);
                                int _5624 = _5574.x + 1;
                                ivec2 _5626 = ivec2(_5624, _5574.y);
                                _5626.y = _5626.y + (_5624 >> 12);
                                _5626.x = _5626.x & 4095;
                                vec4 _5592 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5626, _3277, 0).xyz, 0);
                                int _12635 = _5579;
                                vec2 _12636 = _5586.xy;
                                vec2 _12637 = _5586.zw;
                                vec2 _12638 = _5592.xy;
                                vec2 _12639 = _5592.zw;
                                if (_5579 == 1)
                                {
                                    int _5639 = _5574.x + 2;
                                    ivec2 _5641 = ivec2(_5639, _5574.y);
                                    _5641.y = _5641.y + (_5639 >> 12);
                                    _5641.x = _5641.x & 4095;
                                    _12640 = vec3(texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5641, _3277, 0).xyz, 0).wxy);
                                }
                                else
                                {
                                    _12640 = vec3(1.0);
                                }
                                int _12667 = _12635;
                                vec2 _12668 = _12636;
                                vec2 _12669 = _12637;
                                vec2 _12670 = _12638;
                                vec2 _12671 = _12639;
                                vec3 _12672 = _12640;
                                do
                                {
                                    if (false)
                                    {
                                        do
                                        {
                                            if (_12667 == 3)
                                            {
                                                _6431 = max(_12668.x, _12670.x);
                                                break;
                                            }
                                            if (_12667 == 2)
                                            {
                                                _6431 = max(max(_12668.x, _12669.x), max(_12670.x, _12671.x));
                                                break;
                                            }
                                            _6431 = max(max(_12668.x, _12669.x), _12670.x);
                                            break;
                                        } while(false);
                                        _5652 = _6431 - _12863.x;
                                    }
                                    else
                                    {
                                        do
                                        {
                                            if (_12667 == 3)
                                            {
                                                _6383 = max(_12668.y, _12670.y);
                                                break;
                                            }
                                            if (_12667 == 2)
                                            {
                                                _6383 = max(max(_12668.y, _12669.y), max(_12670.y, _12671.y));
                                                break;
                                            }
                                            _6383 = max(max(_12668.y, _12669.y), _12670.y);
                                            break;
                                        } while(false);
                                        _5652 = _6383 - _12863.y;
                                    }
                                    if ((_5652 * _3617) < (-0.5))
                                    {
                                        _5651 = false;
                                        break;
                                    }
                                    if (_12667 == 0)
                                    {
                                        float _5698 = _12668.x - _12863.x;
                                        float _5701 = _12668.y - _12863.y;
                                        float _5705 = _12669.x - _12863.x;
                                        float _5707 = _12669.y - _12863.y;
                                        float _5711 = _12670.x - _12863.x;
                                        float _5713 = _12670.y - _12863.y;
                                        if (false)
                                        {
                                            if (abs(_5701) <= 1.52587890625e-05)
                                            {
                                                _6543 = 0.0;
                                            }
                                            else
                                            {
                                                _6543 = _5701;
                                            }
                                            if (abs(_5707) <= 1.52587890625e-05)
                                            {
                                                _6552 = 0.0;
                                            }
                                            else
                                            {
                                                _6552 = _5707;
                                            }
                                            if (abs(_5713) <= 1.52587890625e-05)
                                            {
                                                _6561 = 0.0;
                                            }
                                            else
                                            {
                                                _6561 = _5713;
                                            }
                                            _5653 = (11892u >> (((floatBitsToUint(_6561) >> 29u) & 4u) | ((((floatBitsToUint(_6552) >> 30u) & 2u) | ((floatBitsToUint(_6543) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                                        }
                                        else
                                        {
                                            if (abs(_5698) <= 1.52587890625e-05)
                                            {
                                                _6497 = 0.0;
                                            }
                                            else
                                            {
                                                _6497 = _5698;
                                            }
                                            if (abs(_5705) <= 1.52587890625e-05)
                                            {
                                                _6506 = 0.0;
                                            }
                                            else
                                            {
                                                _6506 = _5705;
                                            }
                                            if (abs(_5711) <= 1.52587890625e-05)
                                            {
                                                _6515 = 0.0;
                                            }
                                            else
                                            {
                                                _6515 = _5711;
                                            }
                                            _5653 = (11892u >> (((floatBitsToUint(_6515) >> 29u) & 4u) | ((((floatBitsToUint(_6506) >> 30u) & 2u) | ((floatBitsToUint(_6497) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                                        }
                                        if (_5653 == 0u)
                                        {
                                            _5651 = true;
                                            break;
                                        }
                                        if (false)
                                        {
                                            float _6655 = (_5698 - (_5705 * 2.0)) + _5711;
                                            float _6658 = (_5701 - (_5707 * 2.0)) + _5713;
                                            float _6660 = _5701 - _5707;
                                            if (abs(_6658) < 1.52587890625e-05)
                                            {
                                                if (abs(_6660) < 1.52587890625e-05)
                                                {
                                                    _6649 = 0.0;
                                                }
                                                else
                                                {
                                                    _6649 = (_5701 * 0.5) / _6660;
                                                }
                                                _6650 = _6649;
                                            }
                                            else
                                            {
                                                float _6665 = _6658 * _5701;
                                                float _6666 = (_6660 * _6660) - _6665;
                                                if (_6666 <= (max(_6660 * _6660, abs(_6665)) * 3.0000001061125658452510833740234e-06))
                                                {
                                                    _6715 = 0.0;
                                                }
                                                else
                                                {
                                                    _6715 = sqrt(_6666);
                                                }
                                                if (_6660 >= 0.0)
                                                {
                                                    float _6680 = _6660 + _6715;
                                                    if (abs(_6680) < 1.52587890625e-05)
                                                    {
                                                        _6649 = 0.0;
                                                    }
                                                    else
                                                    {
                                                        _6649 = _5701 / _6680;
                                                    }
                                                    _6650 = _6680 / _6658;
                                                }
                                                else
                                                {
                                                    float _6670 = _6660 - _6715;
                                                    if (abs(_6670) < 1.52587890625e-05)
                                                    {
                                                        _6649 = 0.0;
                                                    }
                                                    else
                                                    {
                                                        _6649 = _5701 / _6670;
                                                    }
                                                    float _6678 = _6649;
                                                    _6649 = _6670 / _6658;
                                                    _6650 = _6678;
                                                }
                                            }
                                            float _6701 = (_5698 - _5705) * 2.0;
                                            _5654 = vec2(((((_6655 * _6649) - _6701) * _6649) + _5698) * _3617, ((((_6655 * _6650) - _6701) * _6650) + _5698) * _3617);
                                        }
                                        else
                                        {
                                            float _6576 = (_5698 - (_5705 * 2.0)) + _5711;
                                            float _6579 = (_5701 - (_5707 * 2.0)) + _5713;
                                            float _6580 = _5698 - _5705;
                                            if (abs(_6576) < 1.52587890625e-05)
                                            {
                                                if (abs(_6580) < 1.52587890625e-05)
                                                {
                                                    _6570 = 0.0;
                                                }
                                                else
                                                {
                                                    _6570 = (_5698 * 0.5) / _6580;
                                                }
                                                _6571 = _6570;
                                            }
                                            else
                                            {
                                                float _6586 = _6576 * _5698;
                                                float _6587 = (_6580 * _6580) - _6586;
                                                if (_6587 <= (max(_6580 * _6580, abs(_6586)) * 3.0000001061125658452510833740234e-06))
                                                {
                                                    _6636 = 0.0;
                                                }
                                                else
                                                {
                                                    _6636 = sqrt(_6587);
                                                }
                                                if (_6580 >= 0.0)
                                                {
                                                    float _6601 = _6580 + _6636;
                                                    if (abs(_6601) < 1.52587890625e-05)
                                                    {
                                                        _6570 = 0.0;
                                                    }
                                                    else
                                                    {
                                                        _6570 = _5698 / _6601;
                                                    }
                                                    _6571 = _6601 / _6576;
                                                }
                                                else
                                                {
                                                    float _6591 = _6580 - _6636;
                                                    if (abs(_6591) < 1.52587890625e-05)
                                                    {
                                                        _6570 = 0.0;
                                                    }
                                                    else
                                                    {
                                                        _6570 = _5698 / _6591;
                                                    }
                                                    float _6599 = _6570;
                                                    _6570 = _6591 / _6576;
                                                    _6571 = _6599;
                                                }
                                            }
                                            float _6622 = (_5701 - _5707) * 2.0;
                                            _5654 = vec2(((((_6579 * _6570) - _6622) * _6570) + _5701) * _3617, ((((_6579 * _6571) - _6622) * _6571) + _5701) * _3617);
                                        }
                                        if ((_5653 & 1u) != 0u)
                                        {
                                            if (false)
                                            {
                                                _5652 = 1.0;
                                            }
                                            else
                                            {
                                                _5652 = -1.0;
                                            }
                                            _5434 += (_5652 * clamp(_5654.x + 0.5, 0.0, 1.0));
                                            _5435 = max(_5435, clamp(1.0 - (abs(_5654.x) * 2.0), 0.0, 1.0));
                                        }
                                        if (_5653 > 1u)
                                        {
                                            if (false)
                                            {
                                                _5652 = -1.0;
                                            }
                                            else
                                            {
                                                _5652 = 1.0;
                                            }
                                            _5434 += (_5652 * clamp(_5654.y + 0.5, 0.0, 1.0));
                                            _5435 = max(_5435, clamp(1.0 - (abs(_5654.y) * 2.0), 0.0, 1.0));
                                        }
                                        _5651 = true;
                                        break;
                                    }
                                    if (_12667 == 3)
                                    {
                                        float _5778 = _12668.x - _12863.x;
                                        float _5781 = _12668.y - _12863.y;
                                        float _5785 = _12670.x - _12863.x;
                                        float _5787 = _12670.y - _12863.y;
                                        do
                                        {
                                            if (false)
                                            {
                                                _5655 = _5781;
                                            }
                                            else
                                            {
                                                _5655 = _5778;
                                            }
                                            if (false)
                                            {
                                                _5656 = _5787;
                                            }
                                            else
                                            {
                                                _5656 = _5785;
                                            }
                                            if (abs(_5655) <= 1.52587890625e-05)
                                            {
                                                _6728 = 0.0;
                                            }
                                            else
                                            {
                                                _6728 = _5655;
                                            }
                                            if (abs(_5656) <= 1.52587890625e-05)
                                            {
                                                _6737 = 0.0;
                                            }
                                            else
                                            {
                                                _6737 = _5656;
                                            }
                                            if ((_6728 < 0.0) == (_6737 < 0.0))
                                            {
                                                break;
                                            }
                                            float _5807 = _5656 - _5655;
                                            if (abs(_5807) < 1.0000000133514319600180897396058e-10)
                                            {
                                                break;
                                            }
                                            float _5815 = clamp((-_5655) / _5807, 0.0, 1.0);
                                            if (false)
                                            {
                                                _5657 = _5787 - _5781;
                                            }
                                            else
                                            {
                                                _5657 = _5778 - _5785;
                                            }
                                            if (abs(_5657) <= 9.9999997473787516355514526367188e-06)
                                            {
                                                break;
                                            }
                                            if (false)
                                            {
                                                _5652 = _5778 + ((_5785 - _5778) * _5815);
                                            }
                                            else
                                            {
                                                _5652 = _5781 + ((_5787 - _5781) * _5815);
                                            }
                                            float _5835 = _5652;
                                            float _5836 = _5835 * _3617;
                                            if (_5657 > 0.0)
                                            {
                                                _5652 = 1.0;
                                            }
                                            else
                                            {
                                                _5652 = -1.0;
                                            }
                                            _5434 += (_5652 * clamp(_5836 + 0.5, 0.0, 1.0));
                                            _5435 = max(_5435, clamp(1.0 - (abs(_5836) * 2.0), 0.0, 1.0));
                                            break;
                                        } while(false);
                                        _5651 = true;
                                        break;
                                    }
                                    if (_12667 == 1)
                                    {
                                        do
                                        {
                                            do
                                            {
                                                if (false)
                                                {
                                                    _6748 = _12863.y;
                                                }
                                                else
                                                {
                                                    _6748 = _12863.x;
                                                }
                                                if (_12667 == 2)
                                                {
                                                    if (false)
                                                    {
                                                        _6749 = _12668.y;
                                                    }
                                                    else
                                                    {
                                                        _6749 = _12668.x;
                                                    }
                                                    if (false)
                                                    {
                                                        _6750 = _12669.y;
                                                    }
                                                    else
                                                    {
                                                        _6750 = _12669.x;
                                                    }
                                                    if (false)
                                                    {
                                                        _6751 = _12670.y;
                                                    }
                                                    else
                                                    {
                                                        _6751 = _12670.x;
                                                    }
                                                    if (false)
                                                    {
                                                        _6752 = _12671.y;
                                                    }
                                                    else
                                                    {
                                                        _6752 = _12671.x;
                                                    }
                                                    if ((min(min(_6749, _6750), min(_6751, _6752)) - _6748) <= 1.52587890625e-05)
                                                    {
                                                        _6842 = (max(max(_6749, _6750), max(_6751, _6752)) - _6748) >= (-1.52587890625e-05);
                                                    }
                                                    else
                                                    {
                                                        _6842 = false;
                                                    }
                                                    _6747 = _6842;
                                                    break;
                                                }
                                                if (false)
                                                {
                                                    _6749 = _12668.y;
                                                }
                                                else
                                                {
                                                    _6749 = _12668.x;
                                                }
                                                if (false)
                                                {
                                                    _6750 = _12669.y;
                                                }
                                                else
                                                {
                                                    _6750 = _12669.x;
                                                }
                                                if (false)
                                                {
                                                    _6751 = _12670.y;
                                                }
                                                else
                                                {
                                                    _6751 = _12670.x;
                                                }
                                                if ((min(min(_6749, _6750), _6751) - _6748) <= 1.52587890625e-05)
                                                {
                                                    _6859 = (max(max(_6749, _6750), _6751) - _6748) >= (-1.52587890625e-05);
                                                }
                                                else
                                                {
                                                    _6859 = false;
                                                }
                                                _6747 = _6859;
                                                break;
                                            } while(false);
                                            if (!_6747)
                                            {
                                                break;
                                            }
                                            if (false)
                                            {
                                                _5655 = _12863.y;
                                            }
                                            else
                                            {
                                                _5655 = _12863.x;
                                            }
                                            if (false)
                                            {
                                                _5656 = _12863.x;
                                            }
                                            else
                                            {
                                                _5656 = _12863.y;
                                            }
                                            if (false)
                                            {
                                                _5657 = _12668.y;
                                            }
                                            else
                                            {
                                                _5657 = _12668.x;
                                            }
                                            if (false)
                                            {
                                                _5658 = _12669.y;
                                            }
                                            else
                                            {
                                                _5658 = _12669.x;
                                            }
                                            if (false)
                                            {
                                                _5659 = _12670.y;
                                            }
                                            else
                                            {
                                                _5659 = _12670.x;
                                            }
                                            if (false)
                                            {
                                                _5661 = _12668.x;
                                            }
                                            else
                                            {
                                                _5661 = _12668.y;
                                            }
                                            if (false)
                                            {
                                                _5662 = _12669.x;
                                            }
                                            else
                                            {
                                                _5662 = _12669.y;
                                            }
                                            if (false)
                                            {
                                                _5663 = _12670.x;
                                            }
                                            else
                                            {
                                                _5663 = _12670.y;
                                            }
                                            float _5934 = _12672.x * (_5657 - _5655);
                                            float _5939 = _12672.y * (_5658 - _5655);
                                            float _5944 = _12672.z * (_5659 - _5655);
                                            if (abs(_5934) <= 1.52587890625e-05)
                                            {
                                                _6893 = 0.0;
                                            }
                                            else
                                            {
                                                _6893 = _5934;
                                            }
                                            if (abs(_5939) <= 1.52587890625e-05)
                                            {
                                                _6902 = 0.0;
                                            }
                                            else
                                            {
                                                _6902 = _5939;
                                            }
                                            if (abs(_5944) <= 1.52587890625e-05)
                                            {
                                                _6911 = 0.0;
                                            }
                                            else
                                            {
                                                _6911 = _5944;
                                            }
                                            uint _6892 = (11892u >> (((floatBitsToUint(_6911) >> 29u) & 4u) | ((((floatBitsToUint(_6902) >> 30u) & 2u) | ((floatBitsToUint(_6893) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                                            if (_6892 == 0u)
                                            {
                                                break;
                                            }
                                            if (_6892 == 257u)
                                            {
                                                _5667 = 2;
                                            }
                                            else
                                            {
                                                _5667 = 1;
                                            }
                                            float _5955 = (_5934 - (2.0 * _5939)) + _5944;
                                            float _5956 = _5939 - _5934;
                                            float _5957 = 2.0 * _5956;
                                            if (abs(_5955) < 1.52587890625e-05)
                                            {
                                                if (abs(_5957) >= 1.52587890625e-05)
                                                {
                                                    _5668 = 1;
                                                    _5660 = (-_5934) / _5957;
                                                }
                                                else
                                                {
                                                    _5668 = 0;
                                                    _5660 = 0.0;
                                                }
                                                float _5981 = _5660;
                                                _5660 = 0.0;
                                                _5664 = _5981;
                                            }
                                            else
                                            {
                                                float _5966 = sqrt(max((_5957 * _5957) - ((4.0 * _5955) * _5934), 0.0));
                                                float _5967 = 0.5 / _5955;
                                                float _5968 = _5956 * (-2.0);
                                                _5668 = 2;
                                                _5660 = (_5968 + _5966) * _5967;
                                                _5664 = (_5968 - _5966) * _5967;
                                            }
                                            if (_5668 == 0)
                                            {
                                                break;
                                            }
                                            if (_5667 == 1)
                                            {
                                                if (_5668 == 2)
                                                {
                                                    _5670 = max(max(0.0, -_5660), _5660 - 1.0) < max(max(0.0, -_5664), _5664 - 1.0);
                                                }
                                                else
                                                {
                                                    _5670 = false;
                                                }
                                                if (_5670)
                                                {
                                                    _5665 = _5660;
                                                }
                                                else
                                                {
                                                    _5665 = _5664;
                                                }
                                                _5665 = clamp(_5665, 0.0, 1.0);
                                                _5669 = 1;
                                                _5666 = 0.0;
                                            }
                                            else
                                            {
                                                _5665 = clamp(_5664, 0.0, 1.0);
                                                _5669 = 2;
                                                _5666 = clamp(_5660, 0.0, 1.0);
                                            }
                                            float _6015 = _5657 * _12672.x;
                                            float _6022 = (_6015 - ((2.0 * _5658) * _12672.y)) + (_5659 * _12672.z);
                                            float _6026 = 2.0 * ((_5658 * _12672.y) - _6015);
                                            float _6028 = _5661 * _12672.x;
                                            float _6035 = (_6028 - ((2.0 * _5662) * _12672.y)) + (_5663 * _12672.z);
                                            float _6039 = 2.0 * ((_5662 * _12672.y) - _6028);
                                            float _6042 = (_12672.x - (2.0 * _12672.y)) + _12672.z;
                                            float _6044 = 2.0 * (_12672.y - _12672.x);
                                            float _6067;
                                            float _6071;
                                            do
                                            {
                                                float _6053 = max((((_6042 * _5665) + _6044) * _5665) + _12672.x, 1.52587890625e-05);
                                                _6067 = 2.0 * _6022;
                                                _6071 = 2.0 * _6042;
                                                float _6079 = ((((_6067 * _5665) + _6026) * _6053) - (((((_6022 * _5665) + _6026) * _5665) + _6015) * ((_6071 * _5665) + _6044))) / (_6053 * _6053);
                                                if (true)
                                                {
                                                    _5671 = -_6079;
                                                }
                                                else
                                                {
                                                    _5671 = _6079;
                                                }
                                                if (abs(_5671) <= 9.9999997473787516355514526367188e-06)
                                                {
                                                    break;
                                                }
                                                float _6092 = ((((((_6035 * _5665) + _6039) * _5665) + _6028) / _6053) - _5656) * _3617;
                                                if (_5671 > 0.0)
                                                {
                                                    _5652 = 1.0;
                                                }
                                                else
                                                {
                                                    _5652 = -1.0;
                                                }
                                                _5434 += (_5652 * clamp(_6092 + 0.5, 0.0, 1.0));
                                                _5435 = max(_5435, clamp(1.0 - (abs(_6092) * 2.0), 0.0, 1.0));
                                                break;
                                            } while(false);
                                            if (_5669 == 2)
                                            {
                                                do
                                                {
                                                    float _6122 = max((((_6042 * _5666) + _6044) * _5666) + _12672.x, 1.52587890625e-05);
                                                    float _6146 = ((((_6067 * _5666) + _6026) * _6122) - (((((_6022 * _5666) + _6026) * _5666) + _6015) * ((_6071 * _5666) + _6044))) / (_6122 * _6122);
                                                    if (true)
                                                    {
                                                        _5671 = -_6146;
                                                    }
                                                    else
                                                    {
                                                        _5671 = _6146;
                                                    }
                                                    if (abs(_5671) <= 9.9999997473787516355514526367188e-06)
                                                    {
                                                        break;
                                                    }
                                                    float _6158 = ((((((_6035 * _5666) + _6039) * _5666) + _6028) / _6122) - _5656) * _3617;
                                                    if (_5671 > 0.0)
                                                    {
                                                        _5652 = 1.0;
                                                    }
                                                    else
                                                    {
                                                        _5652 = -1.0;
                                                    }
                                                    _5434 += (_5652 * clamp(_6158 + 0.5, 0.0, 1.0));
                                                    _5435 = max(_5435, clamp(1.0 - (abs(_6158) * 2.0), 0.0, 1.0));
                                                    break;
                                                } while(false);
                                            }
                                            break;
                                        } while(false);
                                        _5651 = true;
                                        break;
                                    }
                                    do
                                    {
                                        do
                                        {
                                            if (false)
                                            {
                                                _6934 = _12863.y;
                                            }
                                            else
                                            {
                                                _6934 = _12863.x;
                                            }
                                            if (_12667 == 2)
                                            {
                                                if (false)
                                                {
                                                    _6935 = _12668.y;
                                                }
                                                else
                                                {
                                                    _6935 = _12668.x;
                                                }
                                                if (false)
                                                {
                                                    _6936 = _12669.y;
                                                }
                                                else
                                                {
                                                    _6936 = _12669.x;
                                                }
                                                if (false)
                                                {
                                                    _6937 = _12670.y;
                                                }
                                                else
                                                {
                                                    _6937 = _12670.x;
                                                }
                                                if (false)
                                                {
                                                    _6938 = _12671.y;
                                                }
                                                else
                                                {
                                                    _6938 = _12671.x;
                                                }
                                                if ((min(min(_6935, _6936), min(_6937, _6938)) - _6934) <= 1.52587890625e-05)
                                                {
                                                    _7028 = (max(max(_6935, _6936), max(_6937, _6938)) - _6934) >= (-1.52587890625e-05);
                                                }
                                                else
                                                {
                                                    _7028 = false;
                                                }
                                                _6933 = _7028;
                                                break;
                                            }
                                            if (false)
                                            {
                                                _6935 = _12668.y;
                                            }
                                            else
                                            {
                                                _6935 = _12668.x;
                                            }
                                            if (false)
                                            {
                                                _6936 = _12669.y;
                                            }
                                            else
                                            {
                                                _6936 = _12669.x;
                                            }
                                            if (false)
                                            {
                                                _6937 = _12670.y;
                                            }
                                            else
                                            {
                                                _6937 = _12670.x;
                                            }
                                            if ((min(min(_6935, _6936), _6937) - _6934) <= 1.52587890625e-05)
                                            {
                                                _7045 = (max(max(_6935, _6936), _6937) - _6934) >= (-1.52587890625e-05);
                                            }
                                            else
                                            {
                                                _7045 = false;
                                            }
                                            _6933 = _7045;
                                            break;
                                        } while(false);
                                        if (!_6933)
                                        {
                                            break;
                                        }
                                        if (false)
                                        {
                                            _5655 = _12863.y;
                                        }
                                        else
                                        {
                                            _5655 = _12863.x;
                                        }
                                        if (false)
                                        {
                                            _5656 = _12863.x;
                                        }
                                        else
                                        {
                                            _5656 = _12863.y;
                                        }
                                        if (false)
                                        {
                                            _5657 = _12668.y;
                                        }
                                        else
                                        {
                                            _5657 = _12668.x;
                                        }
                                        if (false)
                                        {
                                            _5658 = _12669.y;
                                        }
                                        else
                                        {
                                            _5658 = _12669.x;
                                        }
                                        if (false)
                                        {
                                            _5659 = _12670.y;
                                        }
                                        else
                                        {
                                            _5659 = _12670.x;
                                        }
                                        if (false)
                                        {
                                            _5660 = _12671.y;
                                        }
                                        else
                                        {
                                            _5660 = _12671.x;
                                        }
                                        if (false)
                                        {
                                            _5661 = _12668.x;
                                        }
                                        else
                                        {
                                            _5661 = _12668.y;
                                        }
                                        if (false)
                                        {
                                            _5662 = _12669.x;
                                        }
                                        else
                                        {
                                            _5662 = _12669.y;
                                        }
                                        if (false)
                                        {
                                            _5663 = _12670.x;
                                        }
                                        else
                                        {
                                            _5663 = _12670.y;
                                        }
                                        if (false)
                                        {
                                            _5664 = _12671.x;
                                        }
                                        else
                                        {
                                            _5664 = _12671.y;
                                        }
                                        float _6271 = 3.0 * _5658;
                                        float _6274 = 3.0 * _5659;
                                        float _6277 = ((_6271 - _5657) - _6274) + _5660;
                                        float _6283 = ((3.0 * _5657) - (6.0 * _5658)) + _6274;
                                        float _6286 = ((-3.0) * _5657) + _6271;
                                        float _6289 = _5657 - _5655;
                                        float _6292 = _5660 - _5655;
                                        if (abs(_6289) <= 1.52587890625e-05)
                                        {
                                            _7060 = 0.0;
                                        }
                                        else
                                        {
                                            _7060 = _6289;
                                        }
                                        if (abs(_6292) <= 1.52587890625e-05)
                                        {
                                            _7069 = 0.0;
                                        }
                                        else
                                        {
                                            _7069 = _6292;
                                        }
                                        if ((_7060 < 0.0) == (_7069 < 0.0))
                                        {
                                            break;
                                        }
                                        float _5672 = 0.0;
                                        if (abs(_6289) <= 1.52587890625e-05)
                                        {
                                            _5672 = 0.0;
                                        }
                                        else
                                        {
                                            if (abs(_6292) <= 1.52587890625e-05)
                                            {
                                                _5672 = 1.0;
                                            }
                                            else
                                            {
                                                do
                                                {
                                                    _5672 = 0.0;
                                                    if (_6289 < (-1.52587890625e-05))
                                                    {
                                                        _7080 = _6292 < (-1.52587890625e-05);
                                                    }
                                                    else
                                                    {
                                                        _7080 = false;
                                                    }
                                                    if (_7080)
                                                    {
                                                        _7080 = true;
                                                    }
                                                    else
                                                    {
                                                        if (_6289 > 1.52587890625e-05)
                                                        {
                                                            _7080 = _6292 > 1.52587890625e-05;
                                                        }
                                                        else
                                                        {
                                                            _7080 = false;
                                                        }
                                                    }
                                                    if (_7080)
                                                    {
                                                        _7079 = false;
                                                        break;
                                                    }
                                                    bool _7108 = _6292 >= _6289;
                                                    float _7081 = 0.5;
                                                    float _7082 = 0.0;
                                                    float _7083 = 1.0;
                                                    int _7084 = 0;
                                                    for (;;)
                                                    {
                                                        if (!(_7084 < 16))
                                                        {
                                                            break;
                                                        }
                                                        float _7125 = (((((_6277 * _7081) + _6283) * _7081) + _6286) * _7081) + _6289;
                                                        if (_7108)
                                                        {
                                                            _7080 = _7125 < 0.0;
                                                        }
                                                        else
                                                        {
                                                            _7080 = false;
                                                        }
                                                        if (_7080)
                                                        {
                                                            _7085 = true;
                                                        }
                                                        else
                                                        {
                                                            if (!_7108)
                                                            {
                                                                _7085 = _7125 > 0.0;
                                                            }
                                                            else
                                                            {
                                                                _7085 = false;
                                                            }
                                                        }
                                                        if (_7085)
                                                        {
                                                            _7082 = _7081;
                                                        }
                                                        else
                                                        {
                                                            _7083 = _7081;
                                                        }
                                                        float _7152 = ((((3.0 * _6277) * _7081) + (2.0 * _6283)) * _7081) + _6286;
                                                        float _7156 = (_7082 + _7083) * 0.5;
                                                        if (abs(_7152) >= 9.9999999747524270787835121154785e-07)
                                                        {
                                                            float _7163 = _7081 - (_7125 / _7152);
                                                            if (_7163 > _7082)
                                                            {
                                                                _7087 = _7163 < _7083;
                                                            }
                                                            else
                                                            {
                                                                _7087 = false;
                                                            }
                                                            if (_7087)
                                                            {
                                                                _7086 = _7163;
                                                            }
                                                            else
                                                            {
                                                                _7086 = _7156;
                                                            }
                                                        }
                                                        else
                                                        {
                                                            _7086 = _7156;
                                                        }
                                                        _7081 = _7086;
                                                        _7084++;
                                                        continue;
                                                    }
                                                    _5672 = _7081;
                                                    _7079 = true;
                                                    break;
                                                } while(false);
                                                if (!_7079)
                                                {
                                                    break;
                                                }
                                            }
                                        }
                                        float _6317 = 3.0 * _5662;
                                        float _6320 = 3.0 * _5663;
                                        if (_5672 == 1.0)
                                        {
                                            _5665 = _5664;
                                        }
                                        else
                                        {
                                            _5665 = ((((((((_6317 - _5661) - _6320) + _5664) * _5672) + (((3.0 * _5661) - (6.0 * _5662)) + _6320)) * _5672) + (((-3.0) * _5661) + _6317)) * _5672) + _5661;
                                        }
                                        if (false)
                                        {
                                            _5666 = _5660 - _5657;
                                        }
                                        else
                                        {
                                            _5666 = _5657 - _5660;
                                        }
                                        float _6361 = (_5665 - _5656) * _3617;
                                        if (_5666 > 0.0)
                                        {
                                            _5652 = 1.0;
                                        }
                                        else
                                        {
                                            _5652 = -1.0;
                                        }
                                        _5434 += (_5652 * clamp(_6361 + 0.5, 0.0, 1.0));
                                        _5435 = max(_5435, clamp(1.0 - (abs(_6361) * 2.0), 0.0, 1.0));
                                        break;
                                    } while(false);
                                    _5651 = true;
                                    break;
                                } while(false);
                                if (!_5651)
                                {
                                    _5467_ladder_break = true;
                                    break;
                                }
                                break;
                            } while(false);
                            if (_5467_ladder_break)
                            {
                                break;
                            }
                            _5437++;
                            continue;
                        }
                        _5436++;
                        continue;
                    }
                    vec2 _5512 = vec2(_5434, _5435);
                    float _3622 = _3760.y;
                    float _3623 = _5512.y;
                    float _3625 = _3760.x;
                    float _3627 = _5512.x;
                    float _3631 = ((_3625 * _3622) + (_3627 * _3623)) / max(_3622 + _3623, 1.52587890625e-05);
                    do
                    {
                        if (_3438 == 1)
                        {
                            _7187 = 1.0 - abs((fract(_3631 * 0.5) * 2.0) - 1.0);
                            break;
                        }
                        _7187 = abs(_3631);
                        break;
                    } while(false);
                    do
                    {
                        if (_3438 == 1)
                        {
                            _7204 = 1.0 - abs((fract(_3625 * 0.5) * 2.0) - 1.0);
                            break;
                        }
                        _7204 = abs(_3625);
                        break;
                    } while(false);
                    do
                    {
                        if (_3438 == 1)
                        {
                            _7221 = 1.0 - abs((fract(_3627 * 0.5) * 2.0) - 1.0);
                            break;
                        }
                        _7221 = abs(_3627);
                        break;
                    } while(false);
                    float _7240 = clamp(max(_7187, min(_7204, _7221)), 0.0, 1.0);
                    float _7241 = max(_12872, 1.52587890625e-05);
                    if (abs(_7241 - 1.0) <= 9.9999999747524270787835121154785e-07)
                    {
                        _7237 = _7240;
                    }
                    else
                    {
                        _7237 = pow(_7240, _7241);
                    }
                    do
                    {
                        int _7259 = int(0.5 - _3423.w);
                        int _7391 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _7396 = ((_3580.y * _7391) + _3580.x) + 2;
                        vec4 _7264 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7396 - _7391 * (_7396 / _7391), _7396 / _7391), 0).xy, 0);
                        if (_7259 == 1)
                        {
                            _12611 = _7264;
                            _12612 = 0.0;
                            break;
                        }
                        int _7415 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _7420 = ((_3580.y * _7415) + _3580.x) + 3;
                        vec4 _7274 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7420 - _7415 * (_7420 / _7415), _7420 / _7415), 0).xy, 0);
                        int _7433 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _7438 = ((_3580.y * _7433) + _3580.x) + 4;
                        vec4 _7280 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7438 - _7433 * (_7438 / _7433), _7438 / _7433), 0).xy, 0);
                        if (_7259 == 2)
                        {
                            vec2 _7285 = _7264.xy;
                            vec2 _7286 = _7264.zw - _7285;
                            float _7287 = dot(_7286, _7286);
                            if (_7287 > 1.0000000133514319600180897396058e-10)
                            {
                                _7252 = dot(_12863 - _7285, _7286) / _7287;
                            }
                            else
                            {
                                _7252 = 0.0;
                            }
                            int _7451 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                            int _7456 = ((_3580.y * _7451) + _3580.x) + 5;
                            do
                            {
                                int _7467 = int(texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7456 - _7451 * (_7456 / _7451), _7456 / _7451), 0).xy, 0).x + 0.5);
                                if (_7467 == 1)
                                {
                                    _7461 = fract(_7252);
                                    break;
                                }
                                if (_7467 == 2)
                                {
                                    float _7477 = _7252 - (2.0 * floor(_7252 * 0.5));
                                    if (_7477 < 0.0)
                                    {
                                        _7462 = _7477 + 2.0;
                                    }
                                    else
                                    {
                                        _7462 = _7477;
                                    }
                                    _7461 = 1.0 - abs(_7462 - 1.0);
                                    break;
                                }
                                _7461 = clamp(_7252, 0.0, 1.0);
                                break;
                            } while(false);
                            _12611 = mix(_7274, _7280, vec4(_7461));
                            _12612 = 1.0;
                            break;
                        }
                        if (_7259 == 3)
                        {
                            float _7315 = length(_12863 - _7264.xy) / max(abs(_7264.z), 1.52587890625e-05);
                            do
                            {
                                int _7508 = int(_7264.w + 0.5);
                                if (_7508 == 1)
                                {
                                    _7502 = fract(_7315);
                                    break;
                                }
                                if (_7508 == 2)
                                {
                                    float _7518 = _7315 - (2.0 * floor(_7315 * 0.5));
                                    if (_7518 < 0.0)
                                    {
                                        _7503 = _7518 + 2.0;
                                    }
                                    else
                                    {
                                        _7503 = _7518;
                                    }
                                    _7502 = 1.0 - abs(_7503 - 1.0);
                                    break;
                                }
                                _7502 = clamp(_7315, 0.0, 1.0);
                                break;
                            } while(false);
                            _12611 = mix(_7274, _7280, vec4(_7502));
                            _12612 = 1.0;
                            break;
                        }
                        if (_7259 == 6)
                        {
                            vec2 _7324 = _12863 - _7264.xy;
                            float _7329 = atan(_7324.y, _7324.x) - _7264.z;
                            float _7330 = _7329 * 0.15915493667125701904296875;
                            do
                            {
                                int _7549 = int(_7264.w + 0.5);
                                if (_7549 == 1)
                                {
                                    _7543 = fract(_7330);
                                    break;
                                }
                                if (_7549 == 2)
                                {
                                    float _7559 = _7330 - (2.0 * floor(_7329 * 0.079577468335628509521484375));
                                    if (_7559 < 0.0)
                                    {
                                        _7544 = _7559 + 2.0;
                                    }
                                    else
                                    {
                                        _7544 = _7559;
                                    }
                                    _7543 = 1.0 - abs(_7544 - 1.0);
                                    break;
                                }
                                _7543 = clamp(_7330, 0.0, 1.0);
                                break;
                            } while(false);
                            _12611 = mix(_7274, _7280, vec4(_7543));
                            _12612 = 1.0;
                            break;
                        }
                        if (_7259 == 4)
                        {
                            int _7592 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                            int _7597 = ((_3580.y * _7592) + _3580.x) + 3;
                            vec4 _7342 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7597 - _7592 * (_7597 / _7592), _7597 / _7592), 0).xy, 0);
                            int _7610 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                            int _7615 = ((_3580.y * _7610) + _3580.x) + 5;
                            vec4 _7348 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7615 - _7610 * (_7615 / _7610), _7615 / _7610), 0).xy, 0);
                            vec3 _7350 = vec3(_12863, 1.0);
                            float _7355 = dot(_7350, vec3(_7264.xyz));
                            float _7360 = dot(_7350, vec3(_7342.xyz));
                            do
                            {
                                int _7626 = int(_7348.z + 0.5);
                                if (_7626 == 1)
                                {
                                    _7620 = fract(_7355);
                                    break;
                                }
                                if (_7626 == 2)
                                {
                                    float _7636 = _7355 - (2.0 * floor(_7355 * 0.5));
                                    if (_7636 < 0.0)
                                    {
                                        _7621 = _7636 + 2.0;
                                    }
                                    else
                                    {
                                        _7621 = _7636;
                                    }
                                    _7620 = 1.0 - abs(_7621 - 1.0);
                                    break;
                                }
                                _7620 = clamp(_7355, 0.0, 1.0);
                                break;
                            } while(false);
                            do
                            {
                                int _7657 = int(_7348.w + 0.5);
                                if (_7657 == 1)
                                {
                                    _7651 = fract(_7360);
                                    break;
                                }
                                if (_7657 == 2)
                                {
                                    float _7667 = _7360 - (2.0 * floor(_7360 * 0.5));
                                    if (_7667 < 0.0)
                                    {
                                        _7652 = _7667 + 2.0;
                                    }
                                    else
                                    {
                                        _7652 = _7667;
                                    }
                                    _7651 = 1.0 - abs(_7652 - 1.0);
                                    break;
                                }
                                _7651 = clamp(_7360, 0.0, 1.0);
                                break;
                            } while(false);
                            vec2 _7369 = vec2(_7620 * _7348.x, _7651 * _7348.y);
                            int _7372 = int(_7264.w + 0.5);
                            do
                            {
                                if (int(_7342.w + 0.5) == 1)
                                {
                                    uvec3 _7692 = uvec3(textureSize(SPIRV_Cross_Combinedu_image_texSPIRV_Cross_DummySampler, 0));
                                    ivec2 _7700 = ivec2(int(_7692.x), int(_7692.y));
                                    _7682 = texelFetch(SPIRV_Cross_Combinedu_image_texSPIRV_Cross_DummySampler, ivec4(clamp(ivec2(_7369 * vec2(_7700)), ivec2(0), _7700 - ivec2(1)), _7372, 0).xyz, 0);
                                    break;
                                }
                                _7682 = texture(SPIRV_Cross_Combinedu_image_texu_image_sampler, vec3(_7369, float(_7372)));
                                break;
                            } while(false);
                            _12611 = _7682;
                            _12612 = 0.0;
                            break;
                        }
                        _12611 = vec4(1.0, 0.0, 1.0, 1.0);
                        _12612 = 0.0;
                        break;
                    } while(false);
                    float _12804 = _12612;
                    vec4 _12803 = _12611 * _12862;
                    if (_3406 == 1)
                    {
                        _3391 = _3403 >= 2;
                    }
                    else
                    {
                        _3391 = false;
                    }
                    if (_3391)
                    {
                        _3393 = _3390 < 2;
                    }
                    else
                    {
                        _3393 = false;
                    }
                    if (_3393)
                    {
                        if (_3390 == 0)
                        {
                            _3394 = _7237;
                            _3395 = _3386;
                            _12813 = _12803;
                            _12814 = _12804;
                            _12822 = _12788;
                            _12823 = _12789;
                        }
                        else
                        {
                            _3394 = _3385;
                            _3395 = _7237;
                            _12813 = _12773;
                            _12814 = _12774;
                            _12822 = _12803;
                            _12823 = _12804;
                        }
                        _12773 = _12813;
                        _12774 = _12814;
                        _12788 = _12822;
                        _12789 = _12823;
                        break;
                    }
                    if (_12804 > 0.5)
                    {
                        _3398 = _7237 > 9.9999999747524270787835121154785e-07;
                    }
                    else
                    {
                        _3398 = false;
                    }
                    if (_3398)
                    {
                        _3394 = 1.0;
                    }
                    else
                    {
                        _3394 = _3387;
                    }
                    float _7736 = _12803.w * _7237;
                    vec4 _7739 = vec4(_12803.xyz * _7736, _7736);
                    float _3498 = _3394;
                    _3384 = _7739 + (_3384 * (1.0 - _7739.w));
                    _3394 = _3385;
                    _3395 = _3386;
                    _3387 = _3498;
                    break;
                } while(false);
                if (_3410_ladder_break)
                {
                    break;
                }
                _3385 = _3394;
                _3386 = _3395;
                _3390++;
                continue;
            }
            if (_3406 == 1)
            {
                _3391 = _3403 >= 2;
            }
            else
            {
                _3391 = false;
            }
            if (_3391)
            {
                float _3516 = min(_3385, _3386);
                float _3519 = max(_3385 - _3516, 0.0);
                if (_12774 > 0.5)
                {
                    _3391 = _3519 > 9.9999999747524270787835121154785e-07;
                }
                else
                {
                    _3391 = false;
                }
                if (_3391)
                {
                    _3387 = 1.0;
                }
                if (_12789 > 0.5)
                {
                    _3391 = _3516 > 9.9999999747524270787835121154785e-07;
                }
                else
                {
                    _3391 = false;
                }
                if (_3391)
                {
                    _3387 = 1.0;
                }
                float _7743 = _12773.w * _3519;
                float _7750 = _12788.w * _3516;
                _3384 += ((vec4(_12773.xyz * _7743, _7743) + vec4(_12788.xyz * _7750, _7750)) * (1.0 - _3384.w));
            }
            if (_3384.w < 0.0039215688593685626983642578125)
            {
                discard;
            }
            if (_3387 > 0.5)
            {
                vec4 _7761;
                do
                {
                    bool _7762;
                    if (_3384.w <= 0.0)
                    {
                        _7762 = true;
                    }
                    else
                    {
                        _7762 = _12873 <= 0.0;
                    }
                    if (_7762)
                    {
                        _7761 = _3384;
                        break;
                    }
                    float _7798 = max(_3384.x, 0.0);
                    float _7807;
                    if (_7798 <= 0.003130800090730190277099609375)
                    {
                        _7807 = _7798 * 12.9200000762939453125;
                    }
                    else
                    {
                        _7807 = (1.05499994754791259765625 * pow(_7798, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                    }
                    float _7801 = max(_3384.y, 0.0);
                    float _7819;
                    if (_7801 <= 0.003130800090730190277099609375)
                    {
                        _7819 = _7801 * 12.9200000762939453125;
                    }
                    else
                    {
                        _7819 = (1.05499994754791259765625 * pow(_7801, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                    }
                    float _7804 = max(_3384.z, 0.0);
                    float _7831;
                    if (_7804 <= 0.003130800090730190277099609375)
                    {
                        _7831 = _7804 * 12.9200000762939453125;
                    }
                    else
                    {
                        _7831 = (1.05499994754791259765625 * pow(_7804, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                    }
                    vec3 _7784 = clamp(vec3(_7807, _7819, _7831) + vec3((fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) - 0.5) * (clamp(_3384.w, 0.0, 1.0) * _12873)), vec3(0.0), vec3(1.0));
                    float _7845 = _7784.x;
                    float _7852;
                    if (_7845 <= 0.040449999272823333740234375)
                    {
                        _7852 = _7845 * 0.077399380505084991455078125;
                    }
                    else
                    {
                        _7852 = pow((_7845 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
                    }
                    float _7847 = _7784.y;
                    float _7864;
                    if (_7847 <= 0.040449999272823333740234375)
                    {
                        _7864 = _7847 * 0.077399380505084991455078125;
                    }
                    else
                    {
                        _7864 = pow((_7847 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
                    }
                    float _7849 = _7784.z;
                    float _7876;
                    if (_7849 <= 0.040449999272823333740234375)
                    {
                        _7876 = _7849 * 0.077399380505084991455078125;
                    }
                    else
                    {
                        _7876 = pow((_7849 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
                    }
                    _7761 = vec4(vec3(_7852, _7864, _7876), _3384.w);
                    break;
                } while(false);
                _3238 = _7761;
            }
            else
            {
                _3238 = _3384;
            }
            if (_12874 != 0)
            {
                _3238 = vec4(_3238.w);
            }
            else
            {
                if (_12871 != 0)
                {
                    vec4 _7889;
                    do
                    {
                        if (_3238.w <= 0.0)
                        {
                            _7889 = vec4(0.0);
                            break;
                        }
                        vec3 _7899 = _3238.xyz * (1.0 / _3238.w);
                        float _7908 = max(_7899.x, 0.0);
                        float _7917;
                        if (_7908 <= 0.003130800090730190277099609375)
                        {
                            _7917 = _7908 * 12.9200000762939453125;
                        }
                        else
                        {
                            _7917 = (1.05499994754791259765625 * pow(_7908, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                        }
                        float _7911 = max(_7899.y, 0.0);
                        float _7929;
                        if (_7911 <= 0.003130800090730190277099609375)
                        {
                            _7929 = _7911 * 12.9200000762939453125;
                        }
                        else
                        {
                            _7929 = (1.05499994754791259765625 * pow(_7911, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                        }
                        float _7914 = max(_7899.z, 0.0);
                        float _7941;
                        if (_7914 <= 0.003130800090730190277099609375)
                        {
                            _7941 = _7914 * 12.9200000762939453125;
                        }
                        else
                        {
                            _7941 = (1.05499994754791259765625 * pow(_7914, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                        }
                        _7889 = vec4(vec3(_7917, _7929, _7941) * _3238.w, _3238.w);
                        break;
                    } while(false);
                    _3238 = _7889;
                }
            }
            _3237 = _3238;
            break;
        }
        int _7962 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
        int _7967 = ((_12865.y * _7962) + _12865.x) + 1;
        vec4 _3323 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7967 - _7962 * (_7967 / _7962), _7967 / _7962), 0).xy, 0);
        int _3326 = int(_3265.x);
        int _3327 = _3326 & 32767;
        int _3329 = int(_3265.y);
        int _3332 = (_3326 >> 15) & 1;
        int _3334 = floatBitsToInt(_3265.z);
        int _3335 = _3334 & 65535;
        int _3337 = (_3334 >> 16) & 65535;
        float _7975 = _3323.y;
        float _8013 = (_12863.y * _7975) + _3323.w;
        float _8017 = max(abs(_3383.y * _7975) * 0.5, 9.9999997473787516355514526367188e-06);
        int _8020 = clamp(int(_8013 - _8017), 0, _3335);
        int _8024 = max(_8020, clamp(int(_8013 + _8017), 0, _3335));
        float _7981 = _3323.x;
        float _8035 = (_12863.x * _7981) + _3323.z;
        float _8039 = max(abs(_3383.x * _7981) * 0.5, 9.9999997473787516355514526367188e-06);
        int _8042 = clamp(int(_8035 - _8039), 0, _3337);
        int _8046 = max(_8042, clamp(int(_8035 + _8039), 0, _3337));
        float _7985 = _3248.x;
        float _8054 = 0.0;
        float _8055 = 0.0;
        bool _8061 = _8020 != _8024;
        int _8056 = _8020;
        bool _8271;
        float _8272;
        uint _8273;
        vec2 _8274;
        float _8275;
        float _8276;
        float _8277;
        float _8278;
        float _8279;
        float _8280;
        float _8281;
        float _8282;
        float _8283;
        float _8284;
        float _8285;
        float _8286;
        int _8287;
        int _8288;
        int _8289;
        bool _8290;
        float _8291;
        float _9003;
        float _9051;
        float _9117;
        float _9126;
        float _9135;
        float _9163;
        float _9172;
        float _9181;
        float _9190;
        float _9191;
        float _9256;
        float _9269;
        float _9270;
        float _9335;
        float _9348;
        float _9357;
        bool _9367;
        float _9368;
        float _9369;
        float _9370;
        float _9371;
        float _9372;
        bool _9462;
        bool _9479;
        float _9513;
        float _9522;
        float _9531;
        bool _9553;
        float _9554;
        float _9555;
        float _9556;
        float _9557;
        float _9558;
        bool _9648;
        bool _9665;
        float _9680;
        float _9689;
        bool _9699;
        bool _9700;
        bool _9705;
        float _9706;
        bool _9707;
        vec3 _12450;
        for (;;)
        {
            if (!(_8056 <= _8024))
            {
                break;
            }
            int _8138 = _3327 + _8056;
            ivec2 _8140 = ivec2(_8138, _3329);
            _8140.y = _8140.y + (_8138 >> 12);
            _8140.x = _8140.x & 4095;
            uvec4 _8077 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_8140, _3277, 0).xyz, 0);
            int _8154 = _3327 + int(_8077.y);
            ivec2 _8156 = ivec2(_8154, _3329);
            _8156.y = _8156.y + (_8154 >> 12);
            _8156.x = _8156.x & 4095;
            int _8084 = int(_8077.x);
            int _8057 = 0;
            for (;;)
            {
                bool _8087_ladder_break = false;
                do
                {
                    if (!(_8057 < _8084))
                    {
                        _8087_ladder_break = true;
                        break;
                    }
                    int _8170 = _8156.x + _8057;
                    ivec2 _8172 = ivec2(_8170, _8156.y);
                    _8172.y = _8172.y + (_8170 >> 12);
                    _8172.x = _8172.x & 4095;
                    uvec4 _8099 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_8172, _3277, 0).xyz, 0);
                    if (_8061)
                    {
                        if (_8056 != max(int(_8099.x >> 12u), _8020))
                        {
                            break;
                        }
                    }
                    ivec2 _8194 = ivec2(int(_8099.x & 4095u), int(_8099.y & 16383u));
                    int _8199 = int(_8099.y >> 14u);
                    vec4 _8206 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_8194, _3277, 0).xyz, 0);
                    int _8244 = _8194.x + 1;
                    ivec2 _8246 = ivec2(_8244, _8194.y);
                    _8246.y = _8246.y + (_8244 >> 12);
                    _8246.x = _8246.x & 4095;
                    vec4 _8212 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_8246, _3277, 0).xyz, 0);
                    int _12445 = _8199;
                    vec2 _12446 = _8206.xy;
                    vec2 _12447 = _8206.zw;
                    vec2 _12448 = _8212.xy;
                    vec2 _12449 = _8212.zw;
                    if (_8199 == 1)
                    {
                        int _8259 = _8194.x + 2;
                        ivec2 _8261 = ivec2(_8259, _8194.y);
                        _8261.y = _8261.y + (_8259 >> 12);
                        _8261.x = _8261.x & 4095;
                        _12450 = vec3(texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_8261, _3277, 0).xyz, 0).wxy);
                    }
                    else
                    {
                        _12450 = vec3(1.0);
                    }
                    int _12477 = _12445;
                    vec2 _12478 = _12446;
                    vec2 _12479 = _12447;
                    vec2 _12480 = _12448;
                    vec2 _12481 = _12449;
                    vec3 _12482 = _12450;
                    do
                    {
                        if (true)
                        {
                            do
                            {
                                if (_12477 == 3)
                                {
                                    _9051 = max(_12478.x, _12480.x);
                                    break;
                                }
                                if (_12477 == 2)
                                {
                                    _9051 = max(max(_12478.x, _12479.x), max(_12480.x, _12481.x));
                                    break;
                                }
                                _9051 = max(max(_12478.x, _12479.x), _12480.x);
                                break;
                            } while(false);
                            _8272 = _9051 - _12863.x;
                        }
                        else
                        {
                            do
                            {
                                if (_12477 == 3)
                                {
                                    _9003 = max(_12478.y, _12480.y);
                                    break;
                                }
                                if (_12477 == 2)
                                {
                                    _9003 = max(max(_12478.y, _12479.y), max(_12480.y, _12481.y));
                                    break;
                                }
                                _9003 = max(max(_12478.y, _12479.y), _12480.y);
                                break;
                            } while(false);
                            _8272 = _9003 - _12863.y;
                        }
                        if ((_8272 * _7985) < (-0.5))
                        {
                            _8271 = false;
                            break;
                        }
                        if (_12477 == 0)
                        {
                            float _8318 = _12478.x - _12863.x;
                            float _8321 = _12478.y - _12863.y;
                            float _8325 = _12479.x - _12863.x;
                            float _8327 = _12479.y - _12863.y;
                            float _8331 = _12480.x - _12863.x;
                            float _8333 = _12480.y - _12863.y;
                            if (true)
                            {
                                if (abs(_8321) <= 1.52587890625e-05)
                                {
                                    _9163 = 0.0;
                                }
                                else
                                {
                                    _9163 = _8321;
                                }
                                if (abs(_8327) <= 1.52587890625e-05)
                                {
                                    _9172 = 0.0;
                                }
                                else
                                {
                                    _9172 = _8327;
                                }
                                if (abs(_8333) <= 1.52587890625e-05)
                                {
                                    _9181 = 0.0;
                                }
                                else
                                {
                                    _9181 = _8333;
                                }
                                _8273 = (11892u >> (((floatBitsToUint(_9181) >> 29u) & 4u) | ((((floatBitsToUint(_9172) >> 30u) & 2u) | ((floatBitsToUint(_9163) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            }
                            else
                            {
                                if (abs(_8318) <= 1.52587890625e-05)
                                {
                                    _9117 = 0.0;
                                }
                                else
                                {
                                    _9117 = _8318;
                                }
                                if (abs(_8325) <= 1.52587890625e-05)
                                {
                                    _9126 = 0.0;
                                }
                                else
                                {
                                    _9126 = _8325;
                                }
                                if (abs(_8331) <= 1.52587890625e-05)
                                {
                                    _9135 = 0.0;
                                }
                                else
                                {
                                    _9135 = _8331;
                                }
                                _8273 = (11892u >> (((floatBitsToUint(_9135) >> 29u) & 4u) | ((((floatBitsToUint(_9126) >> 30u) & 2u) | ((floatBitsToUint(_9117) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            }
                            if (_8273 == 0u)
                            {
                                _8271 = true;
                                break;
                            }
                            if (true)
                            {
                                float _9275 = (_8318 - (_8325 * 2.0)) + _8331;
                                float _9278 = (_8321 - (_8327 * 2.0)) + _8333;
                                float _9280 = _8321 - _8327;
                                if (abs(_9278) < 1.52587890625e-05)
                                {
                                    if (abs(_9280) < 1.52587890625e-05)
                                    {
                                        _9269 = 0.0;
                                    }
                                    else
                                    {
                                        _9269 = (_8321 * 0.5) / _9280;
                                    }
                                    _9270 = _9269;
                                }
                                else
                                {
                                    float _9285 = _9278 * _8321;
                                    float _9286 = (_9280 * _9280) - _9285;
                                    if (_9286 <= (max(_9280 * _9280, abs(_9285)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _9335 = 0.0;
                                    }
                                    else
                                    {
                                        _9335 = sqrt(_9286);
                                    }
                                    if (_9280 >= 0.0)
                                    {
                                        float _9300 = _9280 + _9335;
                                        if (abs(_9300) < 1.52587890625e-05)
                                        {
                                            _9269 = 0.0;
                                        }
                                        else
                                        {
                                            _9269 = _8321 / _9300;
                                        }
                                        _9270 = _9300 / _9278;
                                    }
                                    else
                                    {
                                        float _9290 = _9280 - _9335;
                                        if (abs(_9290) < 1.52587890625e-05)
                                        {
                                            _9269 = 0.0;
                                        }
                                        else
                                        {
                                            _9269 = _8321 / _9290;
                                        }
                                        float _9298 = _9269;
                                        _9269 = _9290 / _9278;
                                        _9270 = _9298;
                                    }
                                }
                                float _9321 = (_8318 - _8325) * 2.0;
                                _8274 = vec2(((((_9275 * _9269) - _9321) * _9269) + _8318) * _7985, ((((_9275 * _9270) - _9321) * _9270) + _8318) * _7985);
                            }
                            else
                            {
                                float _9196 = (_8318 - (_8325 * 2.0)) + _8331;
                                float _9199 = (_8321 - (_8327 * 2.0)) + _8333;
                                float _9200 = _8318 - _8325;
                                if (abs(_9196) < 1.52587890625e-05)
                                {
                                    if (abs(_9200) < 1.52587890625e-05)
                                    {
                                        _9190 = 0.0;
                                    }
                                    else
                                    {
                                        _9190 = (_8318 * 0.5) / _9200;
                                    }
                                    _9191 = _9190;
                                }
                                else
                                {
                                    float _9206 = _9196 * _8318;
                                    float _9207 = (_9200 * _9200) - _9206;
                                    if (_9207 <= (max(_9200 * _9200, abs(_9206)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _9256 = 0.0;
                                    }
                                    else
                                    {
                                        _9256 = sqrt(_9207);
                                    }
                                    if (_9200 >= 0.0)
                                    {
                                        float _9221 = _9200 + _9256;
                                        if (abs(_9221) < 1.52587890625e-05)
                                        {
                                            _9190 = 0.0;
                                        }
                                        else
                                        {
                                            _9190 = _8318 / _9221;
                                        }
                                        _9191 = _9221 / _9196;
                                    }
                                    else
                                    {
                                        float _9211 = _9200 - _9256;
                                        if (abs(_9211) < 1.52587890625e-05)
                                        {
                                            _9190 = 0.0;
                                        }
                                        else
                                        {
                                            _9190 = _8318 / _9211;
                                        }
                                        float _9219 = _9190;
                                        _9190 = _9211 / _9196;
                                        _9191 = _9219;
                                    }
                                }
                                float _9242 = (_8321 - _8327) * 2.0;
                                _8274 = vec2(((((_9199 * _9190) - _9242) * _9190) + _8321) * _7985, ((((_9199 * _9191) - _9242) * _9191) + _8321) * _7985);
                            }
                            if ((_8273 & 1u) != 0u)
                            {
                                if (true)
                                {
                                    _8272 = 1.0;
                                }
                                else
                                {
                                    _8272 = -1.0;
                                }
                                _8054 += (_8272 * clamp(_8274.x + 0.5, 0.0, 1.0));
                                _8055 = max(_8055, clamp(1.0 - (abs(_8274.x) * 2.0), 0.0, 1.0));
                            }
                            if (_8273 > 1u)
                            {
                                if (true)
                                {
                                    _8272 = -1.0;
                                }
                                else
                                {
                                    _8272 = 1.0;
                                }
                                _8054 += (_8272 * clamp(_8274.y + 0.5, 0.0, 1.0));
                                _8055 = max(_8055, clamp(1.0 - (abs(_8274.y) * 2.0), 0.0, 1.0));
                            }
                            _8271 = true;
                            break;
                        }
                        if (_12477 == 3)
                        {
                            float _8398 = _12478.x - _12863.x;
                            float _8401 = _12478.y - _12863.y;
                            float _8405 = _12480.x - _12863.x;
                            float _8407 = _12480.y - _12863.y;
                            do
                            {
                                if (true)
                                {
                                    _8275 = _8401;
                                }
                                else
                                {
                                    _8275 = _8398;
                                }
                                if (true)
                                {
                                    _8276 = _8407;
                                }
                                else
                                {
                                    _8276 = _8405;
                                }
                                if (abs(_8275) <= 1.52587890625e-05)
                                {
                                    _9348 = 0.0;
                                }
                                else
                                {
                                    _9348 = _8275;
                                }
                                if (abs(_8276) <= 1.52587890625e-05)
                                {
                                    _9357 = 0.0;
                                }
                                else
                                {
                                    _9357 = _8276;
                                }
                                if ((_9348 < 0.0) == (_9357 < 0.0))
                                {
                                    break;
                                }
                                float _8427 = _8276 - _8275;
                                if (abs(_8427) < 1.0000000133514319600180897396058e-10)
                                {
                                    break;
                                }
                                float _8435 = clamp((-_8275) / _8427, 0.0, 1.0);
                                if (true)
                                {
                                    _8277 = _8407 - _8401;
                                }
                                else
                                {
                                    _8277 = _8398 - _8405;
                                }
                                if (abs(_8277) <= 9.9999997473787516355514526367188e-06)
                                {
                                    break;
                                }
                                if (true)
                                {
                                    _8272 = _8398 + ((_8405 - _8398) * _8435);
                                }
                                else
                                {
                                    _8272 = _8401 + ((_8407 - _8401) * _8435);
                                }
                                float _8455 = _8272;
                                float _8456 = _8455 * _7985;
                                if (_8277 > 0.0)
                                {
                                    _8272 = 1.0;
                                }
                                else
                                {
                                    _8272 = -1.0;
                                }
                                _8054 += (_8272 * clamp(_8456 + 0.5, 0.0, 1.0));
                                _8055 = max(_8055, clamp(1.0 - (abs(_8456) * 2.0), 0.0, 1.0));
                                break;
                            } while(false);
                            _8271 = true;
                            break;
                        }
                        if (_12477 == 1)
                        {
                            do
                            {
                                do
                                {
                                    if (true)
                                    {
                                        _9368 = _12863.y;
                                    }
                                    else
                                    {
                                        _9368 = _12863.x;
                                    }
                                    if (_12477 == 2)
                                    {
                                        if (true)
                                        {
                                            _9369 = _12478.y;
                                        }
                                        else
                                        {
                                            _9369 = _12478.x;
                                        }
                                        if (true)
                                        {
                                            _9370 = _12479.y;
                                        }
                                        else
                                        {
                                            _9370 = _12479.x;
                                        }
                                        if (true)
                                        {
                                            _9371 = _12480.y;
                                        }
                                        else
                                        {
                                            _9371 = _12480.x;
                                        }
                                        if (true)
                                        {
                                            _9372 = _12481.y;
                                        }
                                        else
                                        {
                                            _9372 = _12481.x;
                                        }
                                        if ((min(min(_9369, _9370), min(_9371, _9372)) - _9368) <= 1.52587890625e-05)
                                        {
                                            _9462 = (max(max(_9369, _9370), max(_9371, _9372)) - _9368) >= (-1.52587890625e-05);
                                        }
                                        else
                                        {
                                            _9462 = false;
                                        }
                                        _9367 = _9462;
                                        break;
                                    }
                                    if (true)
                                    {
                                        _9369 = _12478.y;
                                    }
                                    else
                                    {
                                        _9369 = _12478.x;
                                    }
                                    if (true)
                                    {
                                        _9370 = _12479.y;
                                    }
                                    else
                                    {
                                        _9370 = _12479.x;
                                    }
                                    if (true)
                                    {
                                        _9371 = _12480.y;
                                    }
                                    else
                                    {
                                        _9371 = _12480.x;
                                    }
                                    if ((min(min(_9369, _9370), _9371) - _9368) <= 1.52587890625e-05)
                                    {
                                        _9479 = (max(max(_9369, _9370), _9371) - _9368) >= (-1.52587890625e-05);
                                    }
                                    else
                                    {
                                        _9479 = false;
                                    }
                                    _9367 = _9479;
                                    break;
                                } while(false);
                                if (!_9367)
                                {
                                    break;
                                }
                                if (true)
                                {
                                    _8275 = _12863.y;
                                }
                                else
                                {
                                    _8275 = _12863.x;
                                }
                                if (true)
                                {
                                    _8276 = _12863.x;
                                }
                                else
                                {
                                    _8276 = _12863.y;
                                }
                                if (true)
                                {
                                    _8277 = _12478.y;
                                }
                                else
                                {
                                    _8277 = _12478.x;
                                }
                                if (true)
                                {
                                    _8278 = _12479.y;
                                }
                                else
                                {
                                    _8278 = _12479.x;
                                }
                                if (true)
                                {
                                    _8279 = _12480.y;
                                }
                                else
                                {
                                    _8279 = _12480.x;
                                }
                                if (true)
                                {
                                    _8281 = _12478.x;
                                }
                                else
                                {
                                    _8281 = _12478.y;
                                }
                                if (true)
                                {
                                    _8282 = _12479.x;
                                }
                                else
                                {
                                    _8282 = _12479.y;
                                }
                                if (true)
                                {
                                    _8283 = _12480.x;
                                }
                                else
                                {
                                    _8283 = _12480.y;
                                }
                                float _8554 = _12482.x * (_8277 - _8275);
                                float _8559 = _12482.y * (_8278 - _8275);
                                float _8564 = _12482.z * (_8279 - _8275);
                                if (abs(_8554) <= 1.52587890625e-05)
                                {
                                    _9513 = 0.0;
                                }
                                else
                                {
                                    _9513 = _8554;
                                }
                                if (abs(_8559) <= 1.52587890625e-05)
                                {
                                    _9522 = 0.0;
                                }
                                else
                                {
                                    _9522 = _8559;
                                }
                                if (abs(_8564) <= 1.52587890625e-05)
                                {
                                    _9531 = 0.0;
                                }
                                else
                                {
                                    _9531 = _8564;
                                }
                                uint _9512 = (11892u >> (((floatBitsToUint(_9531) >> 29u) & 4u) | ((((floatBitsToUint(_9522) >> 30u) & 2u) | ((floatBitsToUint(_9513) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                                if (_9512 == 0u)
                                {
                                    break;
                                }
                                if (_9512 == 257u)
                                {
                                    _8287 = 2;
                                }
                                else
                                {
                                    _8287 = 1;
                                }
                                float _8575 = (_8554 - (2.0 * _8559)) + _8564;
                                float _8576 = _8559 - _8554;
                                float _8577 = 2.0 * _8576;
                                if (abs(_8575) < 1.52587890625e-05)
                                {
                                    if (abs(_8577) >= 1.52587890625e-05)
                                    {
                                        _8288 = 1;
                                        _8280 = (-_8554) / _8577;
                                    }
                                    else
                                    {
                                        _8288 = 0;
                                        _8280 = 0.0;
                                    }
                                    float _8601 = _8280;
                                    _8280 = 0.0;
                                    _8284 = _8601;
                                }
                                else
                                {
                                    float _8586 = sqrt(max((_8577 * _8577) - ((4.0 * _8575) * _8554), 0.0));
                                    float _8587 = 0.5 / _8575;
                                    float _8588 = _8576 * (-2.0);
                                    _8288 = 2;
                                    _8280 = (_8588 + _8586) * _8587;
                                    _8284 = (_8588 - _8586) * _8587;
                                }
                                if (_8288 == 0)
                                {
                                    break;
                                }
                                if (_8287 == 1)
                                {
                                    if (_8288 == 2)
                                    {
                                        _8290 = max(max(0.0, -_8280), _8280 - 1.0) < max(max(0.0, -_8284), _8284 - 1.0);
                                    }
                                    else
                                    {
                                        _8290 = false;
                                    }
                                    if (_8290)
                                    {
                                        _8285 = _8280;
                                    }
                                    else
                                    {
                                        _8285 = _8284;
                                    }
                                    _8285 = clamp(_8285, 0.0, 1.0);
                                    _8289 = 1;
                                    _8286 = 0.0;
                                }
                                else
                                {
                                    _8285 = clamp(_8284, 0.0, 1.0);
                                    _8289 = 2;
                                    _8286 = clamp(_8280, 0.0, 1.0);
                                }
                                float _8635 = _8277 * _12482.x;
                                float _8642 = (_8635 - ((2.0 * _8278) * _12482.y)) + (_8279 * _12482.z);
                                float _8646 = 2.0 * ((_8278 * _12482.y) - _8635);
                                float _8648 = _8281 * _12482.x;
                                float _8655 = (_8648 - ((2.0 * _8282) * _12482.y)) + (_8283 * _12482.z);
                                float _8659 = 2.0 * ((_8282 * _12482.y) - _8648);
                                float _8662 = (_12482.x - (2.0 * _12482.y)) + _12482.z;
                                float _8664 = 2.0 * (_12482.y - _12482.x);
                                float _8687;
                                float _8691;
                                do
                                {
                                    float _8673 = max((((_8662 * _8285) + _8664) * _8285) + _12482.x, 1.52587890625e-05);
                                    _8687 = 2.0 * _8642;
                                    _8691 = 2.0 * _8662;
                                    float _8699 = ((((_8687 * _8285) + _8646) * _8673) - (((((_8642 * _8285) + _8646) * _8285) + _8635) * ((_8691 * _8285) + _8664))) / (_8673 * _8673);
                                    if (false)
                                    {
                                        _8291 = -_8699;
                                    }
                                    else
                                    {
                                        _8291 = _8699;
                                    }
                                    if (abs(_8291) <= 9.9999997473787516355514526367188e-06)
                                    {
                                        break;
                                    }
                                    float _8712 = ((((((_8655 * _8285) + _8659) * _8285) + _8648) / _8673) - _8276) * _7985;
                                    if (_8291 > 0.0)
                                    {
                                        _8272 = 1.0;
                                    }
                                    else
                                    {
                                        _8272 = -1.0;
                                    }
                                    _8054 += (_8272 * clamp(_8712 + 0.5, 0.0, 1.0));
                                    _8055 = max(_8055, clamp(1.0 - (abs(_8712) * 2.0), 0.0, 1.0));
                                    break;
                                } while(false);
                                if (_8289 == 2)
                                {
                                    do
                                    {
                                        float _8742 = max((((_8662 * _8286) + _8664) * _8286) + _12482.x, 1.52587890625e-05);
                                        float _8766 = ((((_8687 * _8286) + _8646) * _8742) - (((((_8642 * _8286) + _8646) * _8286) + _8635) * ((_8691 * _8286) + _8664))) / (_8742 * _8742);
                                        if (false)
                                        {
                                            _8291 = -_8766;
                                        }
                                        else
                                        {
                                            _8291 = _8766;
                                        }
                                        if (abs(_8291) <= 9.9999997473787516355514526367188e-06)
                                        {
                                            break;
                                        }
                                        float _8778 = ((((((_8655 * _8286) + _8659) * _8286) + _8648) / _8742) - _8276) * _7985;
                                        if (_8291 > 0.0)
                                        {
                                            _8272 = 1.0;
                                        }
                                        else
                                        {
                                            _8272 = -1.0;
                                        }
                                        _8054 += (_8272 * clamp(_8778 + 0.5, 0.0, 1.0));
                                        _8055 = max(_8055, clamp(1.0 - (abs(_8778) * 2.0), 0.0, 1.0));
                                        break;
                                    } while(false);
                                }
                                break;
                            } while(false);
                            _8271 = true;
                            break;
                        }
                        do
                        {
                            do
                            {
                                if (true)
                                {
                                    _9554 = _12863.y;
                                }
                                else
                                {
                                    _9554 = _12863.x;
                                }
                                if (_12477 == 2)
                                {
                                    if (true)
                                    {
                                        _9555 = _12478.y;
                                    }
                                    else
                                    {
                                        _9555 = _12478.x;
                                    }
                                    if (true)
                                    {
                                        _9556 = _12479.y;
                                    }
                                    else
                                    {
                                        _9556 = _12479.x;
                                    }
                                    if (true)
                                    {
                                        _9557 = _12480.y;
                                    }
                                    else
                                    {
                                        _9557 = _12480.x;
                                    }
                                    if (true)
                                    {
                                        _9558 = _12481.y;
                                    }
                                    else
                                    {
                                        _9558 = _12481.x;
                                    }
                                    if ((min(min(_9555, _9556), min(_9557, _9558)) - _9554) <= 1.52587890625e-05)
                                    {
                                        _9648 = (max(max(_9555, _9556), max(_9557, _9558)) - _9554) >= (-1.52587890625e-05);
                                    }
                                    else
                                    {
                                        _9648 = false;
                                    }
                                    _9553 = _9648;
                                    break;
                                }
                                if (true)
                                {
                                    _9555 = _12478.y;
                                }
                                else
                                {
                                    _9555 = _12478.x;
                                }
                                if (true)
                                {
                                    _9556 = _12479.y;
                                }
                                else
                                {
                                    _9556 = _12479.x;
                                }
                                if (true)
                                {
                                    _9557 = _12480.y;
                                }
                                else
                                {
                                    _9557 = _12480.x;
                                }
                                if ((min(min(_9555, _9556), _9557) - _9554) <= 1.52587890625e-05)
                                {
                                    _9665 = (max(max(_9555, _9556), _9557) - _9554) >= (-1.52587890625e-05);
                                }
                                else
                                {
                                    _9665 = false;
                                }
                                _9553 = _9665;
                                break;
                            } while(false);
                            if (!_9553)
                            {
                                break;
                            }
                            if (true)
                            {
                                _8275 = _12863.y;
                            }
                            else
                            {
                                _8275 = _12863.x;
                            }
                            if (true)
                            {
                                _8276 = _12863.x;
                            }
                            else
                            {
                                _8276 = _12863.y;
                            }
                            if (true)
                            {
                                _8277 = _12478.y;
                            }
                            else
                            {
                                _8277 = _12478.x;
                            }
                            if (true)
                            {
                                _8278 = _12479.y;
                            }
                            else
                            {
                                _8278 = _12479.x;
                            }
                            if (true)
                            {
                                _8279 = _12480.y;
                            }
                            else
                            {
                                _8279 = _12480.x;
                            }
                            if (true)
                            {
                                _8280 = _12481.y;
                            }
                            else
                            {
                                _8280 = _12481.x;
                            }
                            if (true)
                            {
                                _8281 = _12478.x;
                            }
                            else
                            {
                                _8281 = _12478.y;
                            }
                            if (true)
                            {
                                _8282 = _12479.x;
                            }
                            else
                            {
                                _8282 = _12479.y;
                            }
                            if (true)
                            {
                                _8283 = _12480.x;
                            }
                            else
                            {
                                _8283 = _12480.y;
                            }
                            if (true)
                            {
                                _8284 = _12481.x;
                            }
                            else
                            {
                                _8284 = _12481.y;
                            }
                            float _8891 = 3.0 * _8278;
                            float _8894 = 3.0 * _8279;
                            float _8897 = ((_8891 - _8277) - _8894) + _8280;
                            float _8903 = ((3.0 * _8277) - (6.0 * _8278)) + _8894;
                            float _8906 = ((-3.0) * _8277) + _8891;
                            float _8909 = _8277 - _8275;
                            float _8912 = _8280 - _8275;
                            if (abs(_8909) <= 1.52587890625e-05)
                            {
                                _9680 = 0.0;
                            }
                            else
                            {
                                _9680 = _8909;
                            }
                            if (abs(_8912) <= 1.52587890625e-05)
                            {
                                _9689 = 0.0;
                            }
                            else
                            {
                                _9689 = _8912;
                            }
                            if ((_9680 < 0.0) == (_9689 < 0.0))
                            {
                                break;
                            }
                            float _8292 = 0.0;
                            if (abs(_8909) <= 1.52587890625e-05)
                            {
                                _8292 = 0.0;
                            }
                            else
                            {
                                if (abs(_8912) <= 1.52587890625e-05)
                                {
                                    _8292 = 1.0;
                                }
                                else
                                {
                                    do
                                    {
                                        _8292 = 0.0;
                                        if (_8909 < (-1.52587890625e-05))
                                        {
                                            _9700 = _8912 < (-1.52587890625e-05);
                                        }
                                        else
                                        {
                                            _9700 = false;
                                        }
                                        if (_9700)
                                        {
                                            _9700 = true;
                                        }
                                        else
                                        {
                                            if (_8909 > 1.52587890625e-05)
                                            {
                                                _9700 = _8912 > 1.52587890625e-05;
                                            }
                                            else
                                            {
                                                _9700 = false;
                                            }
                                        }
                                        if (_9700)
                                        {
                                            _9699 = false;
                                            break;
                                        }
                                        bool _9728 = _8912 >= _8909;
                                        float _9701 = 0.5;
                                        float _9702 = 0.0;
                                        float _9703 = 1.0;
                                        int _9704 = 0;
                                        for (;;)
                                        {
                                            if (!(_9704 < 16))
                                            {
                                                break;
                                            }
                                            float _9745 = (((((_8897 * _9701) + _8903) * _9701) + _8906) * _9701) + _8909;
                                            if (_9728)
                                            {
                                                _9700 = _9745 < 0.0;
                                            }
                                            else
                                            {
                                                _9700 = false;
                                            }
                                            if (_9700)
                                            {
                                                _9705 = true;
                                            }
                                            else
                                            {
                                                if (!_9728)
                                                {
                                                    _9705 = _9745 > 0.0;
                                                }
                                                else
                                                {
                                                    _9705 = false;
                                                }
                                            }
                                            if (_9705)
                                            {
                                                _9702 = _9701;
                                            }
                                            else
                                            {
                                                _9703 = _9701;
                                            }
                                            float _9772 = ((((3.0 * _8897) * _9701) + (2.0 * _8903)) * _9701) + _8906;
                                            float _9776 = (_9702 + _9703) * 0.5;
                                            if (abs(_9772) >= 9.9999999747524270787835121154785e-07)
                                            {
                                                float _9783 = _9701 - (_9745 / _9772);
                                                if (_9783 > _9702)
                                                {
                                                    _9707 = _9783 < _9703;
                                                }
                                                else
                                                {
                                                    _9707 = false;
                                                }
                                                if (_9707)
                                                {
                                                    _9706 = _9783;
                                                }
                                                else
                                                {
                                                    _9706 = _9776;
                                                }
                                            }
                                            else
                                            {
                                                _9706 = _9776;
                                            }
                                            _9701 = _9706;
                                            _9704++;
                                            continue;
                                        }
                                        _8292 = _9701;
                                        _9699 = true;
                                        break;
                                    } while(false);
                                    if (!_9699)
                                    {
                                        break;
                                    }
                                }
                            }
                            float _8937 = 3.0 * _8282;
                            float _8940 = 3.0 * _8283;
                            if (_8292 == 1.0)
                            {
                                _8285 = _8284;
                            }
                            else
                            {
                                _8285 = ((((((((_8937 - _8281) - _8940) + _8284) * _8292) + (((3.0 * _8281) - (6.0 * _8282)) + _8940)) * _8292) + (((-3.0) * _8281) + _8937)) * _8292) + _8281;
                            }
                            if (true)
                            {
                                _8286 = _8280 - _8277;
                            }
                            else
                            {
                                _8286 = _8277 - _8280;
                            }
                            float _8981 = (_8285 - _8276) * _7985;
                            if (_8286 > 0.0)
                            {
                                _8272 = 1.0;
                            }
                            else
                            {
                                _8272 = -1.0;
                            }
                            _8054 += (_8272 * clamp(_8981 + 0.5, 0.0, 1.0));
                            _8055 = max(_8055, clamp(1.0 - (abs(_8981) * 2.0), 0.0, 1.0));
                            break;
                        } while(false);
                        _8271 = true;
                        break;
                    } while(false);
                    if (!_8271)
                    {
                        _8087_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_8087_ladder_break)
                {
                    break;
                }
                _8057++;
                continue;
            }
            _8056++;
            continue;
        }
        vec2 _8132 = vec2(_8054, _8055);
        float _7989 = _3248.y;
        int _7990 = _3335 + 1;
        float _9806 = 0.0;
        float _9807 = 0.0;
        bool _9813 = _8042 != _8046;
        int _9808 = _8042;
        bool _10023;
        float _10024;
        uint _10025;
        vec2 _10026;
        float _10027;
        float _10028;
        float _10029;
        float _10030;
        float _10031;
        float _10032;
        float _10033;
        float _10034;
        float _10035;
        float _10036;
        float _10037;
        float _10038;
        int _10039;
        int _10040;
        int _10041;
        bool _10042;
        float _10043;
        float _10755;
        float _10803;
        float _10869;
        float _10878;
        float _10887;
        float _10915;
        float _10924;
        float _10933;
        float _10942;
        float _10943;
        float _11008;
        float _11021;
        float _11022;
        float _11087;
        float _11100;
        float _11109;
        bool _11119;
        float _11120;
        float _11121;
        float _11122;
        float _11123;
        float _11124;
        bool _11214;
        bool _11231;
        float _11265;
        float _11274;
        float _11283;
        bool _11305;
        float _11306;
        float _11307;
        float _11308;
        float _11309;
        float _11310;
        bool _11400;
        bool _11417;
        float _11432;
        float _11441;
        bool _11451;
        bool _11452;
        bool _11457;
        float _11458;
        bool _11459;
        vec3 _12406;
        for (;;)
        {
            if (!(_9808 <= _8046))
            {
                break;
            }
            int _9890 = _3327 + (_7990 + _9808);
            ivec2 _9892 = ivec2(_9890, _3329);
            _9892.y = _9892.y + (_9890 >> 12);
            _9892.x = _9892.x & 4095;
            uvec4 _9829 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9892, _3277, 0).xyz, 0);
            int _9906 = _3327 + int(_9829.y);
            ivec2 _9908 = ivec2(_9906, _3329);
            _9908.y = _9908.y + (_9906 >> 12);
            _9908.x = _9908.x & 4095;
            int _9836 = int(_9829.x);
            int _9809 = 0;
            for (;;)
            {
                bool _9839_ladder_break = false;
                do
                {
                    if (!(_9809 < _9836))
                    {
                        _9839_ladder_break = true;
                        break;
                    }
                    int _9922 = _9908.x + _9809;
                    ivec2 _9924 = ivec2(_9922, _9908.y);
                    _9924.y = _9924.y + (_9922 >> 12);
                    _9924.x = _9924.x & 4095;
                    uvec4 _9851 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9924, _3277, 0).xyz, 0);
                    if (_9813)
                    {
                        if (_9808 != max(int(_9851.x >> 12u), _8042))
                        {
                            break;
                        }
                    }
                    ivec2 _9946 = ivec2(int(_9851.x & 4095u), int(_9851.y & 16383u));
                    int _9951 = int(_9851.y >> 14u);
                    vec4 _9958 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9946, _3277, 0).xyz, 0);
                    int _9996 = _9946.x + 1;
                    ivec2 _9998 = ivec2(_9996, _9946.y);
                    _9998.y = _9998.y + (_9996 >> 12);
                    _9998.x = _9998.x & 4095;
                    vec4 _9964 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9998, _3277, 0).xyz, 0);
                    int _12401 = _9951;
                    vec2 _12402 = _9958.xy;
                    vec2 _12403 = _9958.zw;
                    vec2 _12404 = _9964.xy;
                    vec2 _12405 = _9964.zw;
                    if (_9951 == 1)
                    {
                        int _10011 = _9946.x + 2;
                        ivec2 _10013 = ivec2(_10011, _9946.y);
                        _10013.y = _10013.y + (_10011 >> 12);
                        _10013.x = _10013.x & 4095;
                        _12406 = vec3(texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_10013, _3277, 0).xyz, 0).wxy);
                    }
                    else
                    {
                        _12406 = vec3(1.0);
                    }
                    int _12433 = _12401;
                    vec2 _12434 = _12402;
                    vec2 _12435 = _12403;
                    vec2 _12436 = _12404;
                    vec2 _12437 = _12405;
                    vec3 _12438 = _12406;
                    do
                    {
                        if (false)
                        {
                            do
                            {
                                if (_12433 == 3)
                                {
                                    _10803 = max(_12434.x, _12436.x);
                                    break;
                                }
                                if (_12433 == 2)
                                {
                                    _10803 = max(max(_12434.x, _12435.x), max(_12436.x, _12437.x));
                                    break;
                                }
                                _10803 = max(max(_12434.x, _12435.x), _12436.x);
                                break;
                            } while(false);
                            _10024 = _10803 - _12863.x;
                        }
                        else
                        {
                            do
                            {
                                if (_12433 == 3)
                                {
                                    _10755 = max(_12434.y, _12436.y);
                                    break;
                                }
                                if (_12433 == 2)
                                {
                                    _10755 = max(max(_12434.y, _12435.y), max(_12436.y, _12437.y));
                                    break;
                                }
                                _10755 = max(max(_12434.y, _12435.y), _12436.y);
                                break;
                            } while(false);
                            _10024 = _10755 - _12863.y;
                        }
                        if ((_10024 * _7989) < (-0.5))
                        {
                            _10023 = false;
                            break;
                        }
                        if (_12433 == 0)
                        {
                            float _10070 = _12434.x - _12863.x;
                            float _10073 = _12434.y - _12863.y;
                            float _10077 = _12435.x - _12863.x;
                            float _10079 = _12435.y - _12863.y;
                            float _10083 = _12436.x - _12863.x;
                            float _10085 = _12436.y - _12863.y;
                            if (false)
                            {
                                if (abs(_10073) <= 1.52587890625e-05)
                                {
                                    _10915 = 0.0;
                                }
                                else
                                {
                                    _10915 = _10073;
                                }
                                if (abs(_10079) <= 1.52587890625e-05)
                                {
                                    _10924 = 0.0;
                                }
                                else
                                {
                                    _10924 = _10079;
                                }
                                if (abs(_10085) <= 1.52587890625e-05)
                                {
                                    _10933 = 0.0;
                                }
                                else
                                {
                                    _10933 = _10085;
                                }
                                _10025 = (11892u >> (((floatBitsToUint(_10933) >> 29u) & 4u) | ((((floatBitsToUint(_10924) >> 30u) & 2u) | ((floatBitsToUint(_10915) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            }
                            else
                            {
                                if (abs(_10070) <= 1.52587890625e-05)
                                {
                                    _10869 = 0.0;
                                }
                                else
                                {
                                    _10869 = _10070;
                                }
                                if (abs(_10077) <= 1.52587890625e-05)
                                {
                                    _10878 = 0.0;
                                }
                                else
                                {
                                    _10878 = _10077;
                                }
                                if (abs(_10083) <= 1.52587890625e-05)
                                {
                                    _10887 = 0.0;
                                }
                                else
                                {
                                    _10887 = _10083;
                                }
                                _10025 = (11892u >> (((floatBitsToUint(_10887) >> 29u) & 4u) | ((((floatBitsToUint(_10878) >> 30u) & 2u) | ((floatBitsToUint(_10869) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            }
                            if (_10025 == 0u)
                            {
                                _10023 = true;
                                break;
                            }
                            if (false)
                            {
                                float _11027 = (_10070 - (_10077 * 2.0)) + _10083;
                                float _11030 = (_10073 - (_10079 * 2.0)) + _10085;
                                float _11032 = _10073 - _10079;
                                if (abs(_11030) < 1.52587890625e-05)
                                {
                                    if (abs(_11032) < 1.52587890625e-05)
                                    {
                                        _11021 = 0.0;
                                    }
                                    else
                                    {
                                        _11021 = (_10073 * 0.5) / _11032;
                                    }
                                    _11022 = _11021;
                                }
                                else
                                {
                                    float _11037 = _11030 * _10073;
                                    float _11038 = (_11032 * _11032) - _11037;
                                    if (_11038 <= (max(_11032 * _11032, abs(_11037)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _11087 = 0.0;
                                    }
                                    else
                                    {
                                        _11087 = sqrt(_11038);
                                    }
                                    if (_11032 >= 0.0)
                                    {
                                        float _11052 = _11032 + _11087;
                                        if (abs(_11052) < 1.52587890625e-05)
                                        {
                                            _11021 = 0.0;
                                        }
                                        else
                                        {
                                            _11021 = _10073 / _11052;
                                        }
                                        _11022 = _11052 / _11030;
                                    }
                                    else
                                    {
                                        float _11042 = _11032 - _11087;
                                        if (abs(_11042) < 1.52587890625e-05)
                                        {
                                            _11021 = 0.0;
                                        }
                                        else
                                        {
                                            _11021 = _10073 / _11042;
                                        }
                                        float _11050 = _11021;
                                        _11021 = _11042 / _11030;
                                        _11022 = _11050;
                                    }
                                }
                                float _11073 = (_10070 - _10077) * 2.0;
                                _10026 = vec2(((((_11027 * _11021) - _11073) * _11021) + _10070) * _7989, ((((_11027 * _11022) - _11073) * _11022) + _10070) * _7989);
                            }
                            else
                            {
                                float _10948 = (_10070 - (_10077 * 2.0)) + _10083;
                                float _10951 = (_10073 - (_10079 * 2.0)) + _10085;
                                float _10952 = _10070 - _10077;
                                if (abs(_10948) < 1.52587890625e-05)
                                {
                                    if (abs(_10952) < 1.52587890625e-05)
                                    {
                                        _10942 = 0.0;
                                    }
                                    else
                                    {
                                        _10942 = (_10070 * 0.5) / _10952;
                                    }
                                    _10943 = _10942;
                                }
                                else
                                {
                                    float _10958 = _10948 * _10070;
                                    float _10959 = (_10952 * _10952) - _10958;
                                    if (_10959 <= (max(_10952 * _10952, abs(_10958)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _11008 = 0.0;
                                    }
                                    else
                                    {
                                        _11008 = sqrt(_10959);
                                    }
                                    if (_10952 >= 0.0)
                                    {
                                        float _10973 = _10952 + _11008;
                                        if (abs(_10973) < 1.52587890625e-05)
                                        {
                                            _10942 = 0.0;
                                        }
                                        else
                                        {
                                            _10942 = _10070 / _10973;
                                        }
                                        _10943 = _10973 / _10948;
                                    }
                                    else
                                    {
                                        float _10963 = _10952 - _11008;
                                        if (abs(_10963) < 1.52587890625e-05)
                                        {
                                            _10942 = 0.0;
                                        }
                                        else
                                        {
                                            _10942 = _10070 / _10963;
                                        }
                                        float _10971 = _10942;
                                        _10942 = _10963 / _10948;
                                        _10943 = _10971;
                                    }
                                }
                                float _10994 = (_10073 - _10079) * 2.0;
                                _10026 = vec2(((((_10951 * _10942) - _10994) * _10942) + _10073) * _7989, ((((_10951 * _10943) - _10994) * _10943) + _10073) * _7989);
                            }
                            if ((_10025 & 1u) != 0u)
                            {
                                if (false)
                                {
                                    _10024 = 1.0;
                                }
                                else
                                {
                                    _10024 = -1.0;
                                }
                                _9806 += (_10024 * clamp(_10026.x + 0.5, 0.0, 1.0));
                                _9807 = max(_9807, clamp(1.0 - (abs(_10026.x) * 2.0), 0.0, 1.0));
                            }
                            if (_10025 > 1u)
                            {
                                if (false)
                                {
                                    _10024 = -1.0;
                                }
                                else
                                {
                                    _10024 = 1.0;
                                }
                                _9806 += (_10024 * clamp(_10026.y + 0.5, 0.0, 1.0));
                                _9807 = max(_9807, clamp(1.0 - (abs(_10026.y) * 2.0), 0.0, 1.0));
                            }
                            _10023 = true;
                            break;
                        }
                        if (_12433 == 3)
                        {
                            float _10150 = _12434.x - _12863.x;
                            float _10153 = _12434.y - _12863.y;
                            float _10157 = _12436.x - _12863.x;
                            float _10159 = _12436.y - _12863.y;
                            do
                            {
                                if (false)
                                {
                                    _10027 = _10153;
                                }
                                else
                                {
                                    _10027 = _10150;
                                }
                                if (false)
                                {
                                    _10028 = _10159;
                                }
                                else
                                {
                                    _10028 = _10157;
                                }
                                if (abs(_10027) <= 1.52587890625e-05)
                                {
                                    _11100 = 0.0;
                                }
                                else
                                {
                                    _11100 = _10027;
                                }
                                if (abs(_10028) <= 1.52587890625e-05)
                                {
                                    _11109 = 0.0;
                                }
                                else
                                {
                                    _11109 = _10028;
                                }
                                if ((_11100 < 0.0) == (_11109 < 0.0))
                                {
                                    break;
                                }
                                float _10179 = _10028 - _10027;
                                if (abs(_10179) < 1.0000000133514319600180897396058e-10)
                                {
                                    break;
                                }
                                float _10187 = clamp((-_10027) / _10179, 0.0, 1.0);
                                if (false)
                                {
                                    _10029 = _10159 - _10153;
                                }
                                else
                                {
                                    _10029 = _10150 - _10157;
                                }
                                if (abs(_10029) <= 9.9999997473787516355514526367188e-06)
                                {
                                    break;
                                }
                                if (false)
                                {
                                    _10024 = _10150 + ((_10157 - _10150) * _10187);
                                }
                                else
                                {
                                    _10024 = _10153 + ((_10159 - _10153) * _10187);
                                }
                                float _10207 = _10024;
                                float _10208 = _10207 * _7989;
                                if (_10029 > 0.0)
                                {
                                    _10024 = 1.0;
                                }
                                else
                                {
                                    _10024 = -1.0;
                                }
                                _9806 += (_10024 * clamp(_10208 + 0.5, 0.0, 1.0));
                                _9807 = max(_9807, clamp(1.0 - (abs(_10208) * 2.0), 0.0, 1.0));
                                break;
                            } while(false);
                            _10023 = true;
                            break;
                        }
                        if (_12433 == 1)
                        {
                            do
                            {
                                do
                                {
                                    if (false)
                                    {
                                        _11120 = _12863.y;
                                    }
                                    else
                                    {
                                        _11120 = _12863.x;
                                    }
                                    if (_12433 == 2)
                                    {
                                        if (false)
                                        {
                                            _11121 = _12434.y;
                                        }
                                        else
                                        {
                                            _11121 = _12434.x;
                                        }
                                        if (false)
                                        {
                                            _11122 = _12435.y;
                                        }
                                        else
                                        {
                                            _11122 = _12435.x;
                                        }
                                        if (false)
                                        {
                                            _11123 = _12436.y;
                                        }
                                        else
                                        {
                                            _11123 = _12436.x;
                                        }
                                        if (false)
                                        {
                                            _11124 = _12437.y;
                                        }
                                        else
                                        {
                                            _11124 = _12437.x;
                                        }
                                        if ((min(min(_11121, _11122), min(_11123, _11124)) - _11120) <= 1.52587890625e-05)
                                        {
                                            _11214 = (max(max(_11121, _11122), max(_11123, _11124)) - _11120) >= (-1.52587890625e-05);
                                        }
                                        else
                                        {
                                            _11214 = false;
                                        }
                                        _11119 = _11214;
                                        break;
                                    }
                                    if (false)
                                    {
                                        _11121 = _12434.y;
                                    }
                                    else
                                    {
                                        _11121 = _12434.x;
                                    }
                                    if (false)
                                    {
                                        _11122 = _12435.y;
                                    }
                                    else
                                    {
                                        _11122 = _12435.x;
                                    }
                                    if (false)
                                    {
                                        _11123 = _12436.y;
                                    }
                                    else
                                    {
                                        _11123 = _12436.x;
                                    }
                                    if ((min(min(_11121, _11122), _11123) - _11120) <= 1.52587890625e-05)
                                    {
                                        _11231 = (max(max(_11121, _11122), _11123) - _11120) >= (-1.52587890625e-05);
                                    }
                                    else
                                    {
                                        _11231 = false;
                                    }
                                    _11119 = _11231;
                                    break;
                                } while(false);
                                if (!_11119)
                                {
                                    break;
                                }
                                if (false)
                                {
                                    _10027 = _12863.y;
                                }
                                else
                                {
                                    _10027 = _12863.x;
                                }
                                if (false)
                                {
                                    _10028 = _12863.x;
                                }
                                else
                                {
                                    _10028 = _12863.y;
                                }
                                if (false)
                                {
                                    _10029 = _12434.y;
                                }
                                else
                                {
                                    _10029 = _12434.x;
                                }
                                if (false)
                                {
                                    _10030 = _12435.y;
                                }
                                else
                                {
                                    _10030 = _12435.x;
                                }
                                if (false)
                                {
                                    _10031 = _12436.y;
                                }
                                else
                                {
                                    _10031 = _12436.x;
                                }
                                if (false)
                                {
                                    _10033 = _12434.x;
                                }
                                else
                                {
                                    _10033 = _12434.y;
                                }
                                if (false)
                                {
                                    _10034 = _12435.x;
                                }
                                else
                                {
                                    _10034 = _12435.y;
                                }
                                if (false)
                                {
                                    _10035 = _12436.x;
                                }
                                else
                                {
                                    _10035 = _12436.y;
                                }
                                float _10306 = _12438.x * (_10029 - _10027);
                                float _10311 = _12438.y * (_10030 - _10027);
                                float _10316 = _12438.z * (_10031 - _10027);
                                if (abs(_10306) <= 1.52587890625e-05)
                                {
                                    _11265 = 0.0;
                                }
                                else
                                {
                                    _11265 = _10306;
                                }
                                if (abs(_10311) <= 1.52587890625e-05)
                                {
                                    _11274 = 0.0;
                                }
                                else
                                {
                                    _11274 = _10311;
                                }
                                if (abs(_10316) <= 1.52587890625e-05)
                                {
                                    _11283 = 0.0;
                                }
                                else
                                {
                                    _11283 = _10316;
                                }
                                uint _11264 = (11892u >> (((floatBitsToUint(_11283) >> 29u) & 4u) | ((((floatBitsToUint(_11274) >> 30u) & 2u) | ((floatBitsToUint(_11265) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                                if (_11264 == 0u)
                                {
                                    break;
                                }
                                if (_11264 == 257u)
                                {
                                    _10039 = 2;
                                }
                                else
                                {
                                    _10039 = 1;
                                }
                                float _10327 = (_10306 - (2.0 * _10311)) + _10316;
                                float _10328 = _10311 - _10306;
                                float _10329 = 2.0 * _10328;
                                if (abs(_10327) < 1.52587890625e-05)
                                {
                                    if (abs(_10329) >= 1.52587890625e-05)
                                    {
                                        _10040 = 1;
                                        _10032 = (-_10306) / _10329;
                                    }
                                    else
                                    {
                                        _10040 = 0;
                                        _10032 = 0.0;
                                    }
                                    float _10353 = _10032;
                                    _10032 = 0.0;
                                    _10036 = _10353;
                                }
                                else
                                {
                                    float _10338 = sqrt(max((_10329 * _10329) - ((4.0 * _10327) * _10306), 0.0));
                                    float _10339 = 0.5 / _10327;
                                    float _10340 = _10328 * (-2.0);
                                    _10040 = 2;
                                    _10032 = (_10340 + _10338) * _10339;
                                    _10036 = (_10340 - _10338) * _10339;
                                }
                                if (_10040 == 0)
                                {
                                    break;
                                }
                                if (_10039 == 1)
                                {
                                    if (_10040 == 2)
                                    {
                                        _10042 = max(max(0.0, -_10032), _10032 - 1.0) < max(max(0.0, -_10036), _10036 - 1.0);
                                    }
                                    else
                                    {
                                        _10042 = false;
                                    }
                                    if (_10042)
                                    {
                                        _10037 = _10032;
                                    }
                                    else
                                    {
                                        _10037 = _10036;
                                    }
                                    _10037 = clamp(_10037, 0.0, 1.0);
                                    _10041 = 1;
                                    _10038 = 0.0;
                                }
                                else
                                {
                                    _10037 = clamp(_10036, 0.0, 1.0);
                                    _10041 = 2;
                                    _10038 = clamp(_10032, 0.0, 1.0);
                                }
                                float _10387 = _10029 * _12438.x;
                                float _10394 = (_10387 - ((2.0 * _10030) * _12438.y)) + (_10031 * _12438.z);
                                float _10398 = 2.0 * ((_10030 * _12438.y) - _10387);
                                float _10400 = _10033 * _12438.x;
                                float _10407 = (_10400 - ((2.0 * _10034) * _12438.y)) + (_10035 * _12438.z);
                                float _10411 = 2.0 * ((_10034 * _12438.y) - _10400);
                                float _10414 = (_12438.x - (2.0 * _12438.y)) + _12438.z;
                                float _10416 = 2.0 * (_12438.y - _12438.x);
                                float _10439;
                                float _10443;
                                do
                                {
                                    float _10425 = max((((_10414 * _10037) + _10416) * _10037) + _12438.x, 1.52587890625e-05);
                                    _10439 = 2.0 * _10394;
                                    _10443 = 2.0 * _10414;
                                    float _10451 = ((((_10439 * _10037) + _10398) * _10425) - (((((_10394 * _10037) + _10398) * _10037) + _10387) * ((_10443 * _10037) + _10416))) / (_10425 * _10425);
                                    if (true)
                                    {
                                        _10043 = -_10451;
                                    }
                                    else
                                    {
                                        _10043 = _10451;
                                    }
                                    if (abs(_10043) <= 9.9999997473787516355514526367188e-06)
                                    {
                                        break;
                                    }
                                    float _10464 = ((((((_10407 * _10037) + _10411) * _10037) + _10400) / _10425) - _10028) * _7989;
                                    if (_10043 > 0.0)
                                    {
                                        _10024 = 1.0;
                                    }
                                    else
                                    {
                                        _10024 = -1.0;
                                    }
                                    _9806 += (_10024 * clamp(_10464 + 0.5, 0.0, 1.0));
                                    _9807 = max(_9807, clamp(1.0 - (abs(_10464) * 2.0), 0.0, 1.0));
                                    break;
                                } while(false);
                                if (_10041 == 2)
                                {
                                    do
                                    {
                                        float _10494 = max((((_10414 * _10038) + _10416) * _10038) + _12438.x, 1.52587890625e-05);
                                        float _10518 = ((((_10439 * _10038) + _10398) * _10494) - (((((_10394 * _10038) + _10398) * _10038) + _10387) * ((_10443 * _10038) + _10416))) / (_10494 * _10494);
                                        if (true)
                                        {
                                            _10043 = -_10518;
                                        }
                                        else
                                        {
                                            _10043 = _10518;
                                        }
                                        if (abs(_10043) <= 9.9999997473787516355514526367188e-06)
                                        {
                                            break;
                                        }
                                        float _10530 = ((((((_10407 * _10038) + _10411) * _10038) + _10400) / _10494) - _10028) * _7989;
                                        if (_10043 > 0.0)
                                        {
                                            _10024 = 1.0;
                                        }
                                        else
                                        {
                                            _10024 = -1.0;
                                        }
                                        _9806 += (_10024 * clamp(_10530 + 0.5, 0.0, 1.0));
                                        _9807 = max(_9807, clamp(1.0 - (abs(_10530) * 2.0), 0.0, 1.0));
                                        break;
                                    } while(false);
                                }
                                break;
                            } while(false);
                            _10023 = true;
                            break;
                        }
                        do
                        {
                            do
                            {
                                if (false)
                                {
                                    _11306 = _12863.y;
                                }
                                else
                                {
                                    _11306 = _12863.x;
                                }
                                if (_12433 == 2)
                                {
                                    if (false)
                                    {
                                        _11307 = _12434.y;
                                    }
                                    else
                                    {
                                        _11307 = _12434.x;
                                    }
                                    if (false)
                                    {
                                        _11308 = _12435.y;
                                    }
                                    else
                                    {
                                        _11308 = _12435.x;
                                    }
                                    if (false)
                                    {
                                        _11309 = _12436.y;
                                    }
                                    else
                                    {
                                        _11309 = _12436.x;
                                    }
                                    if (false)
                                    {
                                        _11310 = _12437.y;
                                    }
                                    else
                                    {
                                        _11310 = _12437.x;
                                    }
                                    if ((min(min(_11307, _11308), min(_11309, _11310)) - _11306) <= 1.52587890625e-05)
                                    {
                                        _11400 = (max(max(_11307, _11308), max(_11309, _11310)) - _11306) >= (-1.52587890625e-05);
                                    }
                                    else
                                    {
                                        _11400 = false;
                                    }
                                    _11305 = _11400;
                                    break;
                                }
                                if (false)
                                {
                                    _11307 = _12434.y;
                                }
                                else
                                {
                                    _11307 = _12434.x;
                                }
                                if (false)
                                {
                                    _11308 = _12435.y;
                                }
                                else
                                {
                                    _11308 = _12435.x;
                                }
                                if (false)
                                {
                                    _11309 = _12436.y;
                                }
                                else
                                {
                                    _11309 = _12436.x;
                                }
                                if ((min(min(_11307, _11308), _11309) - _11306) <= 1.52587890625e-05)
                                {
                                    _11417 = (max(max(_11307, _11308), _11309) - _11306) >= (-1.52587890625e-05);
                                }
                                else
                                {
                                    _11417 = false;
                                }
                                _11305 = _11417;
                                break;
                            } while(false);
                            if (!_11305)
                            {
                                break;
                            }
                            if (false)
                            {
                                _10027 = _12863.y;
                            }
                            else
                            {
                                _10027 = _12863.x;
                            }
                            if (false)
                            {
                                _10028 = _12863.x;
                            }
                            else
                            {
                                _10028 = _12863.y;
                            }
                            if (false)
                            {
                                _10029 = _12434.y;
                            }
                            else
                            {
                                _10029 = _12434.x;
                            }
                            if (false)
                            {
                                _10030 = _12435.y;
                            }
                            else
                            {
                                _10030 = _12435.x;
                            }
                            if (false)
                            {
                                _10031 = _12436.y;
                            }
                            else
                            {
                                _10031 = _12436.x;
                            }
                            if (false)
                            {
                                _10032 = _12437.y;
                            }
                            else
                            {
                                _10032 = _12437.x;
                            }
                            if (false)
                            {
                                _10033 = _12434.x;
                            }
                            else
                            {
                                _10033 = _12434.y;
                            }
                            if (false)
                            {
                                _10034 = _12435.x;
                            }
                            else
                            {
                                _10034 = _12435.y;
                            }
                            if (false)
                            {
                                _10035 = _12436.x;
                            }
                            else
                            {
                                _10035 = _12436.y;
                            }
                            if (false)
                            {
                                _10036 = _12437.x;
                            }
                            else
                            {
                                _10036 = _12437.y;
                            }
                            float _10643 = 3.0 * _10030;
                            float _10646 = 3.0 * _10031;
                            float _10649 = ((_10643 - _10029) - _10646) + _10032;
                            float _10655 = ((3.0 * _10029) - (6.0 * _10030)) + _10646;
                            float _10658 = ((-3.0) * _10029) + _10643;
                            float _10661 = _10029 - _10027;
                            float _10664 = _10032 - _10027;
                            if (abs(_10661) <= 1.52587890625e-05)
                            {
                                _11432 = 0.0;
                            }
                            else
                            {
                                _11432 = _10661;
                            }
                            if (abs(_10664) <= 1.52587890625e-05)
                            {
                                _11441 = 0.0;
                            }
                            else
                            {
                                _11441 = _10664;
                            }
                            if ((_11432 < 0.0) == (_11441 < 0.0))
                            {
                                break;
                            }
                            float _10044 = 0.0;
                            if (abs(_10661) <= 1.52587890625e-05)
                            {
                                _10044 = 0.0;
                            }
                            else
                            {
                                if (abs(_10664) <= 1.52587890625e-05)
                                {
                                    _10044 = 1.0;
                                }
                                else
                                {
                                    do
                                    {
                                        _10044 = 0.0;
                                        if (_10661 < (-1.52587890625e-05))
                                        {
                                            _11452 = _10664 < (-1.52587890625e-05);
                                        }
                                        else
                                        {
                                            _11452 = false;
                                        }
                                        if (_11452)
                                        {
                                            _11452 = true;
                                        }
                                        else
                                        {
                                            if (_10661 > 1.52587890625e-05)
                                            {
                                                _11452 = _10664 > 1.52587890625e-05;
                                            }
                                            else
                                            {
                                                _11452 = false;
                                            }
                                        }
                                        if (_11452)
                                        {
                                            _11451 = false;
                                            break;
                                        }
                                        bool _11480 = _10664 >= _10661;
                                        float _11453 = 0.5;
                                        float _11454 = 0.0;
                                        float _11455 = 1.0;
                                        int _11456 = 0;
                                        for (;;)
                                        {
                                            if (!(_11456 < 16))
                                            {
                                                break;
                                            }
                                            float _11497 = (((((_10649 * _11453) + _10655) * _11453) + _10658) * _11453) + _10661;
                                            if (_11480)
                                            {
                                                _11452 = _11497 < 0.0;
                                            }
                                            else
                                            {
                                                _11452 = false;
                                            }
                                            if (_11452)
                                            {
                                                _11457 = true;
                                            }
                                            else
                                            {
                                                if (!_11480)
                                                {
                                                    _11457 = _11497 > 0.0;
                                                }
                                                else
                                                {
                                                    _11457 = false;
                                                }
                                            }
                                            if (_11457)
                                            {
                                                _11454 = _11453;
                                            }
                                            else
                                            {
                                                _11455 = _11453;
                                            }
                                            float _11524 = ((((3.0 * _10649) * _11453) + (2.0 * _10655)) * _11453) + _10658;
                                            float _11528 = (_11454 + _11455) * 0.5;
                                            if (abs(_11524) >= 9.9999999747524270787835121154785e-07)
                                            {
                                                float _11535 = _11453 - (_11497 / _11524);
                                                if (_11535 > _11454)
                                                {
                                                    _11459 = _11535 < _11455;
                                                }
                                                else
                                                {
                                                    _11459 = false;
                                                }
                                                if (_11459)
                                                {
                                                    _11458 = _11535;
                                                }
                                                else
                                                {
                                                    _11458 = _11528;
                                                }
                                            }
                                            else
                                            {
                                                _11458 = _11528;
                                            }
                                            _11453 = _11458;
                                            _11456++;
                                            continue;
                                        }
                                        _10044 = _11453;
                                        _11451 = true;
                                        break;
                                    } while(false);
                                    if (!_11451)
                                    {
                                        break;
                                    }
                                }
                            }
                            float _10689 = 3.0 * _10034;
                            float _10692 = 3.0 * _10035;
                            if (_10044 == 1.0)
                            {
                                _10037 = _10036;
                            }
                            else
                            {
                                _10037 = ((((((((_10689 - _10033) - _10692) + _10036) * _10044) + (((3.0 * _10033) - (6.0 * _10034)) + _10692)) * _10044) + (((-3.0) * _10033) + _10689)) * _10044) + _10033;
                            }
                            if (false)
                            {
                                _10038 = _10032 - _10029;
                            }
                            else
                            {
                                _10038 = _10029 - _10032;
                            }
                            float _10733 = (_10037 - _10028) * _7989;
                            if (_10038 > 0.0)
                            {
                                _10024 = 1.0;
                            }
                            else
                            {
                                _10024 = -1.0;
                            }
                            _9806 += (_10024 * clamp(_10733 + 0.5, 0.0, 1.0));
                            _9807 = max(_9807, clamp(1.0 - (abs(_10733) * 2.0), 0.0, 1.0));
                            break;
                        } while(false);
                        _10023 = true;
                        break;
                    } while(false);
                    if (!_10023)
                    {
                        _9839_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_9839_ladder_break)
                {
                    break;
                }
                _9809++;
                continue;
            }
            _9808++;
            continue;
        }
        vec2 _9884 = vec2(_9806, _9807);
        float _7994 = _8132.y;
        float _7995 = _9884.y;
        float _7997 = _8132.x;
        float _7999 = _9884.x;
        float _8003 = ((_7997 * _7994) + (_7999 * _7995)) / max(_7994 + _7995, 1.52587890625e-05);
        float _11559;
        do
        {
            if (_3332 == 1)
            {
                _11559 = 1.0 - abs((fract(_8003 * 0.5) * 2.0) - 1.0);
                break;
            }
            _11559 = abs(_8003);
            break;
        } while(false);
        float _11576;
        do
        {
            if (_3332 == 1)
            {
                _11576 = 1.0 - abs((fract(_7997 * 0.5) * 2.0) - 1.0);
                break;
            }
            _11576 = abs(_7997);
            break;
        } while(false);
        float _11593;
        do
        {
            if (_3332 == 1)
            {
                _11593 = 1.0 - abs((fract(_7999 * 0.5) * 2.0) - 1.0);
                break;
            }
            _11593 = abs(_7999);
            break;
        } while(false);
        float _11612 = clamp(max(_11559, min(_11576, _11593)), 0.0, 1.0);
        float _11613 = max(_12872, 1.52587890625e-05);
        float _11609;
        if (abs(_11613 - 1.0) <= 9.9999999747524270787835121154785e-07)
        {
            _11609 = _11612;
        }
        else
        {
            _11609 = pow(_11612, _11613);
        }
        if (_11609 < 0.0039215688593685626983642578125)
        {
            discard;
        }
        vec4 _12377;
        float _12378;
        do
        {
            int _11631 = int(0.5 - _3265.w);
            int _11763 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
            int _11768 = ((_12865.y * _11763) + _12865.x) + 2;
            vec4 _11636 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11768 - _11763 * (_11768 / _11763), _11768 / _11763), 0).xy, 0);
            if (_11631 == 1)
            {
                _12377 = _11636;
                _12378 = 0.0;
                break;
            }
            int _11787 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
            int _11792 = ((_12865.y * _11787) + _12865.x) + 3;
            vec4 _11646 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11792 - _11787 * (_11792 / _11787), _11792 / _11787), 0).xy, 0);
            int _11805 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
            int _11810 = ((_12865.y * _11805) + _12865.x) + 4;
            vec4 _11652 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11810 - _11805 * (_11810 / _11805), _11810 / _11805), 0).xy, 0);
            if (_11631 == 2)
            {
                vec2 _11657 = _11636.xy;
                vec2 _11658 = _11636.zw - _11657;
                float _11659 = dot(_11658, _11658);
                float _11624;
                if (_11659 > 1.0000000133514319600180897396058e-10)
                {
                    _11624 = dot(_12863 - _11657, _11658) / _11659;
                }
                else
                {
                    _11624 = 0.0;
                }
                int _11823 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _11828 = ((_12865.y * _11823) + _12865.x) + 5;
                float _11833;
                do
                {
                    int _11839 = int(texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11828 - _11823 * (_11828 / _11823), _11828 / _11823), 0).xy, 0).x + 0.5);
                    if (_11839 == 1)
                    {
                        _11833 = fract(_11624);
                        break;
                    }
                    if (_11839 == 2)
                    {
                        float _11849 = _11624 - (2.0 * floor(_11624 * 0.5));
                        float _11834;
                        if (_11849 < 0.0)
                        {
                            _11834 = _11849 + 2.0;
                        }
                        else
                        {
                            _11834 = _11849;
                        }
                        _11833 = 1.0 - abs(_11834 - 1.0);
                        break;
                    }
                    _11833 = clamp(_11624, 0.0, 1.0);
                    break;
                } while(false);
                _12377 = mix(_11646, _11652, vec4(_11833));
                _12378 = 1.0;
                break;
            }
            if (_11631 == 3)
            {
                float _11687 = length(_12863 - _11636.xy) / max(abs(_11636.z), 1.52587890625e-05);
                float _11874;
                do
                {
                    int _11880 = int(_11636.w + 0.5);
                    if (_11880 == 1)
                    {
                        _11874 = fract(_11687);
                        break;
                    }
                    if (_11880 == 2)
                    {
                        float _11890 = _11687 - (2.0 * floor(_11687 * 0.5));
                        float _11875;
                        if (_11890 < 0.0)
                        {
                            _11875 = _11890 + 2.0;
                        }
                        else
                        {
                            _11875 = _11890;
                        }
                        _11874 = 1.0 - abs(_11875 - 1.0);
                        break;
                    }
                    _11874 = clamp(_11687, 0.0, 1.0);
                    break;
                } while(false);
                _12377 = mix(_11646, _11652, vec4(_11874));
                _12378 = 1.0;
                break;
            }
            if (_11631 == 6)
            {
                vec2 _11696 = _12863 - _11636.xy;
                float _11701 = atan(_11696.y, _11696.x) - _11636.z;
                float _11702 = _11701 * 0.15915493667125701904296875;
                float _11915;
                do
                {
                    int _11921 = int(_11636.w + 0.5);
                    if (_11921 == 1)
                    {
                        _11915 = fract(_11702);
                        break;
                    }
                    if (_11921 == 2)
                    {
                        float _11931 = _11702 - (2.0 * floor(_11701 * 0.079577468335628509521484375));
                        float _11916;
                        if (_11931 < 0.0)
                        {
                            _11916 = _11931 + 2.0;
                        }
                        else
                        {
                            _11916 = _11931;
                        }
                        _11915 = 1.0 - abs(_11916 - 1.0);
                        break;
                    }
                    _11915 = clamp(_11702, 0.0, 1.0);
                    break;
                } while(false);
                _12377 = mix(_11646, _11652, vec4(_11915));
                _12378 = 1.0;
                break;
            }
            if (_11631 == 4)
            {
                int _11964 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _11969 = ((_12865.y * _11964) + _12865.x) + 3;
                vec4 _11714 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11969 - _11964 * (_11969 / _11964), _11969 / _11964), 0).xy, 0);
                int _11982 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _11987 = ((_12865.y * _11982) + _12865.x) + 5;
                vec4 _11720 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11987 - _11982 * (_11987 / _11982), _11987 / _11982), 0).xy, 0);
                vec3 _11722 = vec3(_12863, 1.0);
                float _11727 = dot(_11722, vec3(_11636.xyz));
                float _11732 = dot(_11722, vec3(_11714.xyz));
                float _11992;
                do
                {
                    int _11998 = int(_11720.z + 0.5);
                    if (_11998 == 1)
                    {
                        _11992 = fract(_11727);
                        break;
                    }
                    if (_11998 == 2)
                    {
                        float _12008 = _11727 - (2.0 * floor(_11727 * 0.5));
                        float _11993;
                        if (_12008 < 0.0)
                        {
                            _11993 = _12008 + 2.0;
                        }
                        else
                        {
                            _11993 = _12008;
                        }
                        _11992 = 1.0 - abs(_11993 - 1.0);
                        break;
                    }
                    _11992 = clamp(_11727, 0.0, 1.0);
                    break;
                } while(false);
                float _12023;
                do
                {
                    int _12029 = int(_11720.w + 0.5);
                    if (_12029 == 1)
                    {
                        _12023 = fract(_11732);
                        break;
                    }
                    if (_12029 == 2)
                    {
                        float _12039 = _11732 - (2.0 * floor(_11732 * 0.5));
                        float _12024;
                        if (_12039 < 0.0)
                        {
                            _12024 = _12039 + 2.0;
                        }
                        else
                        {
                            _12024 = _12039;
                        }
                        _12023 = 1.0 - abs(_12024 - 1.0);
                        break;
                    }
                    _12023 = clamp(_11732, 0.0, 1.0);
                    break;
                } while(false);
                vec2 _11741 = vec2(_11992 * _11720.x, _12023 * _11720.y);
                int _11744 = int(_11636.w + 0.5);
                vec4 _12054;
                do
                {
                    if (int(_11714.w + 0.5) == 1)
                    {
                        uvec3 _12064 = uvec3(textureSize(SPIRV_Cross_Combinedu_image_texSPIRV_Cross_DummySampler, 0));
                        ivec2 _12072 = ivec2(int(_12064.x), int(_12064.y));
                        _12054 = texelFetch(SPIRV_Cross_Combinedu_image_texSPIRV_Cross_DummySampler, ivec4(clamp(ivec2(_11741 * vec2(_12072)), ivec2(0), _12072 - ivec2(1)), _11744, 0).xyz, 0);
                        break;
                    }
                    _12054 = texture(SPIRV_Cross_Combinedu_image_texu_image_sampler, vec3(_11741, float(_11744)));
                    break;
                } while(false);
                _12377 = _12054;
                _12378 = 0.0;
                break;
            }
            _12377 = vec4(1.0, 0.0, 1.0, 1.0);
            _12378 = 0.0;
            break;
        } while(false);
        vec4 _3350 = _12377 * _12862;
        float _12108 = _3350.w * _11609;
        vec4 _12111 = vec4(_3350.xyz * _12108, _12108);
        if (_12378 > 0.5)
        {
            vec4 _12113;
            do
            {
                float _12118 = _12111.w;
                bool _12114;
                if (_12118 <= 0.0)
                {
                    _12114 = true;
                }
                else
                {
                    _12114 = _12873 <= 0.0;
                }
                if (_12114)
                {
                    _12113 = _12111;
                    break;
                }
                float _12150 = max(_12111.x, 0.0);
                float _12159;
                if (_12150 <= 0.003130800090730190277099609375)
                {
                    _12159 = _12150 * 12.9200000762939453125;
                }
                else
                {
                    _12159 = (1.05499994754791259765625 * pow(_12150, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                float _12153 = max(_12111.y, 0.0);
                float _12171;
                if (_12153 <= 0.003130800090730190277099609375)
                {
                    _12171 = _12153 * 12.9200000762939453125;
                }
                else
                {
                    _12171 = (1.05499994754791259765625 * pow(_12153, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                float _12156 = max(_12111.z, 0.0);
                float _12183;
                if (_12156 <= 0.003130800090730190277099609375)
                {
                    _12183 = _12156 * 12.9200000762939453125;
                }
                else
                {
                    _12183 = (1.05499994754791259765625 * pow(_12156, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                vec3 _12136 = clamp(vec3(_12159, _12171, _12183) + vec3((fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) - 0.5) * (clamp(_12118, 0.0, 1.0) * _12873)), vec3(0.0), vec3(1.0));
                float _12197 = _12136.x;
                float _12204;
                if (_12197 <= 0.040449999272823333740234375)
                {
                    _12204 = _12197 * 0.077399380505084991455078125;
                }
                else
                {
                    _12204 = pow((_12197 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
                }
                float _12199 = _12136.y;
                float _12216;
                if (_12199 <= 0.040449999272823333740234375)
                {
                    _12216 = _12199 * 0.077399380505084991455078125;
                }
                else
                {
                    _12216 = pow((_12199 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
                }
                float _12201 = _12136.z;
                float _12228;
                if (_12201 <= 0.040449999272823333740234375)
                {
                    _12228 = _12201 * 0.077399380505084991455078125;
                }
                else
                {
                    _12228 = pow((_12201 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
                }
                _12113 = vec4(vec3(_12204, _12216, _12228), _12118);
                break;
            } while(false);
            _3238 = _12113;
        }
        else
        {
            _3238 = _12111;
        }
        if (_12874 != 0)
        {
            _3238 = vec4(_3238.w);
        }
        else
        {
            if (_12871 != 0)
            {
                vec4 _12241;
                do
                {
                    if (_3238.w <= 0.0)
                    {
                        _12241 = vec4(0.0);
                        break;
                    }
                    vec3 _12251 = _3238.xyz * (1.0 / _3238.w);
                    float _12260 = max(_12251.x, 0.0);
                    float _12269;
                    if (_12260 <= 0.003130800090730190277099609375)
                    {
                        _12269 = _12260 * 12.9200000762939453125;
                    }
                    else
                    {
                        _12269 = (1.05499994754791259765625 * pow(_12260, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                    }
                    float _12263 = max(_12251.y, 0.0);
                    float _12281;
                    if (_12263 <= 0.003130800090730190277099609375)
                    {
                        _12281 = _12263 * 12.9200000762939453125;
                    }
                    else
                    {
                        _12281 = (1.05499994754791259765625 * pow(_12263, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                    }
                    float _12266 = max(_12251.z, 0.0);
                    float _12293;
                    if (_12266 <= 0.003130800090730190277099609375)
                    {
                        _12293 = _12266 * 12.9200000762939453125;
                    }
                    else
                    {
                        _12293 = (1.05499994754791259765625 * pow(_12266, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                    }
                    _12241 = vec4(vec3(_12269, _12281, _12293) * _3238.w, _3238.w);
                    break;
                } while(false);
                _3238 = _12241;
            }
        }
        _3237 = _3238;
        break;
    } while(false);
    vec4 _3240 = _3237;
    entryPointParam_fragmentMain = _3240;
}


#version 330

layout(std140) uniform GameMaterialParams_std140
{
    layout(row_major) mat4 view_proj;
    layout(row_major) mat4 model;
    vec4 base_color;
    vec4 light_dir;
    vec2 scene_size;
    int glyph_count;
    int output_srgb;
    float relief;
    float roughness;
} pc;

uniform usamplerBuffer u_snail_text_records;
uniform usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in vec2 snail_io0;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

void main()
{
    vec2 scene_pos = vec2(snail_io0.x * pc.scene_size.x, (1.0 - snail_io0.y) * pc.scene_size.y);
    vec2 _1628 = dFdx(scene_pos);
    vec2 _1631 = dFdy(scene_pos);
    vec2 _1638 = max((abs(_1628) + abs(_1631)) * 1.25, vec2(1.52587890625e-05));
    vec4 _1706 = vec4(0.0);
    int _1707 = 0;
    bool _1708;
    bool _1709;
    bool _1710;
    float _1928;
    float _1929;
    float _1972;
    float _1973;
    float _2023;
    float _2024;
    float _2067;
    float _2068;
    int _2377;
    bool _2378;
    bool _2670;
    float _2776;
    float _2785;
    float _2794;
    float _2803;
    float _2804;
    float _2873;
    bool _2957;
    float _3063;
    float _3072;
    float _3081;
    float _3090;
    float _3091;
    float _3160;
    float _3174;
    float _3191;
    float _3208;
    float _3224;
    float _3246;
    float _3258;
    float _3270;
    float _3291;
    float _3303;
    float _3315;
    for (;;)
    {
        bool _1715_ladder_break = false;
        do
        {
            if (!(_1707 < pc.glyph_count))
            {
                _1715_ladder_break = true;
                break;
            }
            uvec4 _1901 = texelFetch(u_snail_text_records, _1707 * 23);
            uint _1902 = _1901.x;
            uvec4 _1913 = texelFetch(u_snail_text_records, (_1707 * 23) + 1);
            uint _1914 = _1913.x;
            uint _1922 = _1902 & 65535u;
            do
            {
                uint _1935 = (_1922 >> 10u) & 31u;
                uint _1936 = _1902 & 1023u;
                if ((_1922 >> 15u) == 0u)
                {
                    _1929 = 1.0;
                }
                else
                {
                    _1929 = -1.0;
                }
                if (_1935 == 0u)
                {
                    if (_1936 == 0u)
                    {
                        _1928 = 0.0;
                        break;
                    }
                    _1928 = (_1929 * 6.103515625e-05) * (float(_1936) * 0.0009765625);
                    break;
                }
                if (_1935 == 31u)
                {
                    _1928 = _1929 * 65504.0;
                    break;
                }
                _1928 = (_1929 * exp2(float(_1935) - 15.0)) * (1.0 + (float(_1936) * 0.0009765625));
                break;
            } while(false);
            uint _1924 = _1902 >> 16u;
            do
            {
                uint _1979 = (_1924 >> 10u) & 31u;
                uint _1980 = _1924 & 1023u;
                if ((_1924 >> 15u) == 0u)
                {
                    _1973 = 1.0;
                }
                else
                {
                    _1973 = -1.0;
                }
                if (_1979 == 0u)
                {
                    if (_1980 == 0u)
                    {
                        _1972 = 0.0;
                        break;
                    }
                    _1972 = (_1973 * 6.103515625e-05) * (float(_1980) * 0.0009765625);
                    break;
                }
                if (_1979 == 31u)
                {
                    _1972 = _1973 * 65504.0;
                    break;
                }
                _1972 = (_1973 * exp2(float(_1979) - 15.0)) * (1.0 + (float(_1980) * 0.0009765625));
                break;
            } while(false);
            uint _2017 = _1914 & 65535u;
            do
            {
                uint _2030 = (_2017 >> 10u) & 31u;
                uint _2031 = _1914 & 1023u;
                if ((_2017 >> 15u) == 0u)
                {
                    _2024 = 1.0;
                }
                else
                {
                    _2024 = -1.0;
                }
                if (_2030 == 0u)
                {
                    if (_2031 == 0u)
                    {
                        _2023 = 0.0;
                        break;
                    }
                    _2023 = (_2024 * 6.103515625e-05) * (float(_2031) * 0.0009765625);
                    break;
                }
                if (_2030 == 31u)
                {
                    _2023 = _2024 * 65504.0;
                    break;
                }
                _2023 = (_2024 * exp2(float(_2030) - 15.0)) * (1.0 + (float(_2031) * 0.0009765625));
                break;
            } while(false);
            uint _2019 = _1914 >> 16u;
            do
            {
                uint _2074 = (_2019 >> 10u) & 31u;
                uint _2075 = _2019 & 1023u;
                if ((_2019 >> 15u) == 0u)
                {
                    _2068 = 1.0;
                }
                else
                {
                    _2068 = -1.0;
                }
                if (_2074 == 0u)
                {
                    if (_2075 == 0u)
                    {
                        _2067 = 0.0;
                        break;
                    }
                    _2067 = (_2068 * 6.103515625e-05) * (float(_2075) * 0.0009765625);
                    break;
                }
                if (_2074 == 31u)
                {
                    _2067 = _2068 * 65504.0;
                    break;
                }
                _2067 = (_2068 * exp2(float(_2074) - 15.0)) * (1.0 + (float(_2075) * 0.0009765625));
                break;
            } while(false);
            vec4 _1919 = vec4(vec2(_1928, _1972), vec2(_2023, _2067));
            vec4 _1862 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 2).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 3).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 4).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 5).x));
            uvec2 _1872 = uvec2(texelFetch(u_snail_text_records, (_1707 * 23) + 8).x, texelFetch(u_snail_text_records, (_1707 * 23) + 9).x);
            vec4 _1882 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 10).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 11).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 12).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 13).x));
            uvec4 _2264 = texelFetch(u_snail_text_records, (_1707 * 23) + 14);
            uint _2265 = _2264.x;
            vec4 _2281 = vec4(float(_2265 & 255u), float((_2265 >> 8u) & 255u), float((_2265 >> 16u) & 255u), float((_2265 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            uvec4 _2292 = texelFetch(u_snail_text_records, (_1707 * 23) + 15);
            uint _2293 = _2292.x;
            vec4 _2309 = vec4(float(_2293 & 255u), float((_2293 >> 8u) & 255u), float((_2293 >> 16u) & 255u), float((_2293 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_1862.x * _1862.w) - (_1862.y * _1862.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            float _2312 = _1862.x;
            float _2313 = _1862.w;
            float _2315 = _1862.y;
            float _2316 = _1862.z;
            float _2318 = (_2312 * _2313) - (_2315 * _2316);
            vec2 _2319 = scene_pos - vec2(uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 6).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1707 * 23) + 7).x));
            float _2320 = _2319.x;
            float _2322 = _2319.y;
            vec2 _2331 = vec2(((_2313 * _2320) - (_2315 * _2322)) / _2318, (((-_2316) * _2320) + (_2312 * _2322)) / _2318);
            float _2334 = _1862.x;
            float _2335 = _1862.w;
            float _2337 = _1862.y;
            float _2338 = _1862.z;
            float _2340 = (_2334 * _2335) - (_2337 * _2338);
            float _2341 = _1628.x;
            float _2343 = _1628.y;
            float _2355 = _1862.x;
            float _2356 = _1862.w;
            float _2358 = _1862.y;
            float _2359 = _1862.z;
            float _2361 = (_2355 * _2356) - (_2358 * _2359);
            float _2362 = _1631.x;
            float _2364 = _1631.y;
            vec2 _1741 = abs(vec2(((_2335 * _2341) - (_2337 * _2343)) / _2340, (((-_2338) * _2341) + (_2334 * _2343)) / _2340)) + abs(vec2(((_2356 * _2362) - (_2358 * _2364)) / _2361, (((-_2359) * _2362) + (_2355 * _2364)) / _2361));
            vec2 _1743 = max(_1741 * 2.0, vec2(0.001000000047497451305389404296875));
            float _1747 = _1743.x;
            if (_2331.x < (_1919.x - _1747))
            {
                _1708 = true;
            }
            else
            {
                _1708 = _2331.x > (_1919.z + _1747);
            }
            if (_1708)
            {
                _1709 = true;
            }
            else
            {
                _1709 = _2331.y < (_1919.y - _1743.y);
            }
            if (_1709)
            {
                _1710 = true;
            }
            else
            {
                _1710 = _2331.y > (_1919.w + _1743.y);
            }
            if (_1710)
            {
                break;
            }
            uint _1778 = _1872.x;
            uint _1779 = _1872.y;
            int _1782 = int((_1779 >> 24u) & 255u);
            if (_1782 == 255)
            {
                break;
            }
            int _1788 = int(_1778 & 65535u);
            int _1790 = int(_1778 >> 16u);
            int _1794 = int((_1779 >> 16u) & 255u);
            int _1796 = int(_1779 & 65535u);
            float _1800 = 1.0 / max(_1741.x, 1.52587890625e-05);
            float _1803 = 1.0 / max(_1741.y, 1.52587890625e-05);
            float _2385 = _1882.y;
            float _2558 = (_2331.y * _2385) + _1882.w;
            float _2562 = max(abs(_1741.y * _2385) * 0.5, 9.9999997473787516355514526367188e-06);
            int _2565 = clamp(int(_2558 - _2562), 0, _1796);
            int _2569 = max(_2565, clamp(int(_2558 + _2562), 0, _1796));
            float _2391 = _1882.x;
            float _2580 = (_2331.x * _2391) + _1882.z;
            float _2584 = max(abs(_1741.x * _2391) * 0.5, 9.9999997473787516355514526367188e-06);
            int _2587 = clamp(int(_2580 - _2584), 0, _1794);
            int _2591 = max(_2587, clamp(int(_2580 + _2584), 0, _1794));
            float _2374 = 0.0;
            float _2375 = 0.0;
            bool _2397 = _2565 != _2569;
            int _2376 = _2565;
            for (;;)
            {
                if (!(_2376 <= _2569))
                {
                    break;
                }
                int _2604 = _1788 + _2376;
                ivec2 _2606 = ivec2(_2604, _1790);
                _2606.y = _2606.y + (_2604 >> 12);
                _2606.x = _2606.x & 4095;
                uvec4 _2412 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2606, _1782, 0).xyz, 0);
                int _2620 = _1788 + int(_2412.y);
                ivec2 _2622 = ivec2(_2620, _1790);
                _2622.y = _2622.y + (_2620 >> 12);
                _2622.x = _2622.x & 4095;
                int _2419 = int(_2412.x);
                _2377 = 0;
                for (;;)
                {
                    bool _2422_ladder_break = false;
                    do
                    {
                        if (!(_2377 < _2419))
                        {
                            _2422_ladder_break = true;
                            break;
                        }
                        int _2636 = _2622.x + _2377;
                        ivec2 _2638 = ivec2(_2636, _2622.y);
                        _2638.y = _2638.y + (_2636 >> 12);
                        _2638.x = _2638.x & 4095;
                        uvec4 _2434 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2638, _1782, 0).xyz, 0);
                        if (_2397)
                        {
                            _2378 = !(_2376 == max(int(_2434.x >> 12u), _2565));
                        }
                        else
                        {
                            _2378 = false;
                        }
                        if (_2378)
                        {
                            break;
                        }
                        ivec2 _2668 = ivec2(int(_2434.x & 4095u), int(_2434.y & 16383u));
                        do
                        {
                            vec4 _2677 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2668, _1782, 0).xyz, 0);
                            int _2746 = _2668.x + 1;
                            ivec2 _2748 = ivec2(_2746, _2668.y);
                            _2748.y = _2748.y + (_2746 >> 12);
                            _2748.x = _2748.x & 4095;
                            vec4 _2689 = vec4(_2677.xy, _2677.zw) - vec4(_2331, _2331);
                            vec2 _2691 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2748, _1782, 0).xyz, 0).xy - _2331;
                            if ((max(max(_2689.x, _2689.z), _2691.x) * _1800) < (-0.5))
                            {
                                _2670 = false;
                                break;
                            }
                            float _2702 = _2689.y;
                            float _2703 = _2689.w;
                            float _2704 = _2691.y;
                            if (abs(_2702) <= 1.52587890625e-05)
                            {
                                _2776 = 0.0;
                            }
                            else
                            {
                                _2776 = _2702;
                            }
                            if (abs(_2703) <= 1.52587890625e-05)
                            {
                                _2785 = 0.0;
                            }
                            else
                            {
                                _2785 = _2703;
                            }
                            if (abs(_2704) <= 1.52587890625e-05)
                            {
                                _2794 = 0.0;
                            }
                            else
                            {
                                _2794 = _2704;
                            }
                            uint _2775 = (11892u >> (((floatBitsToUint(_2794) >> 29u) & 4u) | ((((floatBitsToUint(_2785) >> 30u) & 2u) | ((floatBitsToUint(_2776) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_2775 != 0u)
                            {
                                vec2 _2807 = _2689.xy;
                                vec2 _2808 = _2689.zw;
                                vec2 _2811 = (_2807 - (_2808 * 2.0)) + _2691;
                                vec2 _2812 = _2807 - _2808;
                                float _2813 = _2811.y;
                                if (abs(_2813) < 1.52587890625e-05)
                                {
                                    float _2845 = _2812.y;
                                    if (abs(_2845) < 1.52587890625e-05)
                                    {
                                        _2803 = 0.0;
                                    }
                                    else
                                    {
                                        _2803 = (_2689.y * 0.5) / _2845;
                                    }
                                    _2804 = _2803;
                                }
                                else
                                {
                                    float _2817 = _2812.y;
                                    float _2819 = _2689.y;
                                    float _2820 = _2813 * _2819;
                                    float _2821 = (_2817 * _2817) - _2820;
                                    if (_2821 <= (max(_2817 * _2817, abs(_2820)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _2873 = 0.0;
                                    }
                                    else
                                    {
                                        _2873 = sqrt(_2821);
                                    }
                                    if (_2817 >= 0.0)
                                    {
                                        float _2835 = _2817 + _2873;
                                        if (abs(_2835) < 1.52587890625e-05)
                                        {
                                            _2803 = 0.0;
                                        }
                                        else
                                        {
                                            _2803 = _2819 / _2835;
                                        }
                                        _2804 = _2835 / _2813;
                                    }
                                    else
                                    {
                                        float _2825 = _2817 - _2873;
                                        if (abs(_2825) < 1.52587890625e-05)
                                        {
                                            _2803 = 0.0;
                                        }
                                        else
                                        {
                                            _2803 = _2819 / _2825;
                                        }
                                        float _2833 = _2803;
                                        _2803 = _2825 / _2813;
                                        _2804 = _2833;
                                    }
                                }
                                float _2856 = _2811.x;
                                float _2860 = _2812.x * 2.0;
                                float _2864 = _2689.x;
                                vec2 _2709 = vec2((((_2856 * _2803) - _2860) * _2803) + _2864, (((_2856 * _2804) - _2860) * _2804) + _2864) * _1800;
                                if ((_2775 & 1u) != 0u)
                                {
                                    float _2713 = _2709.x;
                                    _2374 += clamp(_2713 + 0.5, 0.0, 1.0);
                                    _2375 = max(_2375, clamp(1.0 - (abs(_2713) * 2.0), 0.0, 1.0));
                                }
                                if (_2775 > 1u)
                                {
                                    float _2727 = _2709.y;
                                    _2374 -= clamp(_2727 + 0.5, 0.0, 1.0);
                                    _2375 = max(_2375, clamp(1.0 - (abs(_2727) * 2.0), 0.0, 1.0));
                                }
                            }
                            _2670 = true;
                            break;
                        } while(false);
                        if (!_2670)
                        {
                            _2422_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_2422_ladder_break)
                    {
                        break;
                    }
                    _2377++;
                    continue;
                }
                _2376++;
                continue;
            }
            float _2379 = 0.0;
            float _2380 = 0.0;
            bool _2466 = _2587 != _2591;
            _2376 = _2587;
            for (;;)
            {
                if (!(_2376 <= _2591))
                {
                    break;
                }
                int _2891 = _1788 + ((_1796 + 1) + _2376);
                ivec2 _2893 = ivec2(_2891, _1790);
                _2893.y = _2893.y + (_2891 >> 12);
                _2893.x = _2893.x & 4095;
                uvec4 _2483 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2893, _1782, 0).xyz, 0);
                int _2907 = _1788 + int(_2483.y);
                ivec2 _2909 = ivec2(_2907, _1790);
                _2909.y = _2909.y + (_2907 >> 12);
                _2909.x = _2909.x & 4095;
                int _2490 = int(_2483.x);
                _2377 = 0;
                for (;;)
                {
                    bool _2493_ladder_break = false;
                    do
                    {
                        if (!(_2377 < _2490))
                        {
                            _2493_ladder_break = true;
                            break;
                        }
                        int _2923 = _2909.x + _2377;
                        ivec2 _2925 = ivec2(_2923, _2909.y);
                        _2925.y = _2925.y + (_2923 >> 12);
                        _2925.x = _2925.x & 4095;
                        uvec4 _2505 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2925, _1782, 0).xyz, 0);
                        if (_2466)
                        {
                            _2378 = !(_2376 == max(int(_2505.x >> 12u), _2587));
                        }
                        else
                        {
                            _2378 = false;
                        }
                        if (_2378)
                        {
                            break;
                        }
                        ivec2 _2955 = ivec2(int(_2505.x & 4095u), int(_2505.y & 16383u));
                        do
                        {
                            vec4 _2964 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2955, _1782, 0).xyz, 0);
                            int _3033 = _2955.x + 1;
                            ivec2 _3035 = ivec2(_3033, _2955.y);
                            _3035.y = _3035.y + (_3033 >> 12);
                            _3035.x = _3035.x & 4095;
                            vec4 _2976 = vec4(_2964.xy, _2964.zw) - vec4(_2331, _2331);
                            vec2 _2978 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3035, _1782, 0).xyz, 0).xy - _2331;
                            if ((max(max(_2976.y, _2976.w), _2978.y) * _1803) < (-0.5))
                            {
                                _2957 = false;
                                break;
                            }
                            float _2989 = _2976.x;
                            float _2990 = _2976.z;
                            float _2991 = _2978.x;
                            if (abs(_2989) <= 1.52587890625e-05)
                            {
                                _3063 = 0.0;
                            }
                            else
                            {
                                _3063 = _2989;
                            }
                            if (abs(_2990) <= 1.52587890625e-05)
                            {
                                _3072 = 0.0;
                            }
                            else
                            {
                                _3072 = _2990;
                            }
                            if (abs(_2991) <= 1.52587890625e-05)
                            {
                                _3081 = 0.0;
                            }
                            else
                            {
                                _3081 = _2991;
                            }
                            uint _3062 = (11892u >> (((floatBitsToUint(_3081) >> 29u) & 4u) | ((((floatBitsToUint(_3072) >> 30u) & 2u) | ((floatBitsToUint(_3063) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_3062 != 0u)
                            {
                                vec2 _3094 = _2976.xy;
                                vec2 _3095 = _2976.zw;
                                vec2 _3098 = (_3094 - (_3095 * 2.0)) + _2978;
                                vec2 _3099 = _3094 - _3095;
                                float _3100 = _3098.x;
                                if (abs(_3100) < 1.52587890625e-05)
                                {
                                    float _3132 = _3099.x;
                                    if (abs(_3132) < 1.52587890625e-05)
                                    {
                                        _3090 = 0.0;
                                    }
                                    else
                                    {
                                        _3090 = (_2976.x * 0.5) / _3132;
                                    }
                                    _3091 = _3090;
                                }
                                else
                                {
                                    float _3104 = _3099.x;
                                    float _3106 = _2976.x;
                                    float _3107 = _3100 * _3106;
                                    float _3108 = (_3104 * _3104) - _3107;
                                    if (_3108 <= (max(_3104 * _3104, abs(_3107)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _3160 = 0.0;
                                    }
                                    else
                                    {
                                        _3160 = sqrt(_3108);
                                    }
                                    if (_3104 >= 0.0)
                                    {
                                        float _3122 = _3104 + _3160;
                                        if (abs(_3122) < 1.52587890625e-05)
                                        {
                                            _3090 = 0.0;
                                        }
                                        else
                                        {
                                            _3090 = _3106 / _3122;
                                        }
                                        _3091 = _3122 / _3100;
                                    }
                                    else
                                    {
                                        float _3112 = _3104 - _3160;
                                        if (abs(_3112) < 1.52587890625e-05)
                                        {
                                            _3090 = 0.0;
                                        }
                                        else
                                        {
                                            _3090 = _3106 / _3112;
                                        }
                                        float _3120 = _3090;
                                        _3090 = _3112 / _3100;
                                        _3091 = _3120;
                                    }
                                }
                                float _3143 = _3098.y;
                                float _3147 = _3099.y * 2.0;
                                float _3151 = _2976.y;
                                vec2 _2996 = vec2((((_3143 * _3090) - _3147) * _3090) + _3151, (((_3143 * _3091) - _3147) * _3091) + _3151) * _1803;
                                if ((_3062 & 1u) != 0u)
                                {
                                    float _3000 = _2996.x;
                                    _2379 -= clamp(_3000 + 0.5, 0.0, 1.0);
                                    _2380 = max(_2380, clamp(1.0 - (abs(_3000) * 2.0), 0.0, 1.0));
                                }
                                if (_3062 > 1u)
                                {
                                    float _3014 = _2996.y;
                                    _2379 += clamp(_3014 + 0.5, 0.0, 1.0);
                                    _2380 = max(_2380, clamp(1.0 - (abs(_3014) * 2.0), 0.0, 1.0));
                                }
                            }
                            _2957 = true;
                            break;
                        } while(false);
                        if (!_2957)
                        {
                            _2493_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_2493_ladder_break)
                    {
                        break;
                    }
                    _2377++;
                    continue;
                }
                _2376++;
                continue;
            }
            float _2546 = ((_2374 * _2375) + (_2379 * _2380)) / max(_2375 + _2380, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _3174 = 1.0 - abs((fract(_2546 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _3174 = abs(_2546);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _3191 = 1.0 - abs((fract(_2374 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _3191 = abs(_2374);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _3208 = 1.0 - abs((fract(_2379 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _3208 = abs(_2379);
                break;
            } while(false);
            float _3227 = clamp(max(_3174, min(_3191, _3208)), 0.0, 1.0);
            if (abs(0.0) <= 9.9999999747524270787835121154785e-07)
            {
                _3224 = _3227;
            }
            else
            {
                _3224 = pow(_3227, 1.0);
            }
            float _1813 = clamp((_3224 * _2281.w) * _2309.w, 0.0, 1.0);
            if (_1813 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            float _3239 = _2281.x;
            if (_3239 <= 0.040449999272823333740234375)
            {
                _3246 = _3239 * 0.077399380505084991455078125;
            }
            else
            {
                _3246 = pow((_3239 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _3241 = _2281.y;
            if (_3241 <= 0.040449999272823333740234375)
            {
                _3258 = _3241 * 0.077399380505084991455078125;
            }
            else
            {
                _3258 = pow((_3241 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _3243 = _2281.z;
            if (_3243 <= 0.040449999272823333740234375)
            {
                _3270 = _3243 * 0.077399380505084991455078125;
            }
            else
            {
                _3270 = pow((_3243 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _3284 = _2309.x;
            if (_3284 <= 0.040449999272823333740234375)
            {
                _3291 = _3284 * 0.077399380505084991455078125;
            }
            else
            {
                _3291 = pow((_3284 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _3286 = _2309.y;
            if (_3286 <= 0.040449999272823333740234375)
            {
                _3303 = _3286 * 0.077399380505084991455078125;
            }
            else
            {
                _3303 = pow((_3286 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _3288 = _2309.z;
            if (_3288 <= 0.040449999272823333740234375)
            {
                _3315 = _3288 * 0.077399380505084991455078125;
            }
            else
            {
                _3315 = pow((_3288 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            vec4 _1823 = _1706;
            float _1825 = 1.0 - _1813;
            vec3 _1827 = ((vec3(_3246, _3258, _3270) * vec3(_3291, _3303, _3315)) * _1813) + (_1823.xyz * _1825);
            vec4 _10331 = _1823;
            _10331.x = _1827.x;
            _10331.y = _1827.y;
            _10331.z = _1827.z;
            _10331.w = _1813 + (_10331.w * _1825);
            _1706 = _10331;
            break;
        } while(false);
        if (_1715_ladder_break)
        {
            break;
        }
        _1707++;
        continue;
    }
    vec2 _1642 = vec2(_1638.x, 0.0);
    vec2 _1643 = scene_pos + _1642;
    vec4 _3332 = vec4(0.0);
    int _3333 = 0;
    bool _3334;
    bool _3335;
    bool _3336;
    float _3553;
    float _3554;
    float _3597;
    float _3598;
    float _3648;
    float _3649;
    float _3692;
    float _3693;
    int _4002;
    bool _4003;
    bool _4295;
    float _4401;
    float _4410;
    float _4419;
    float _4428;
    float _4429;
    float _4498;
    bool _4582;
    float _4688;
    float _4697;
    float _4706;
    float _4715;
    float _4716;
    float _4785;
    float _4799;
    float _4816;
    float _4833;
    float _4849;
    float _4871;
    float _4883;
    float _4895;
    float _4916;
    float _4928;
    float _4940;
    for (;;)
    {
        bool _3341_ladder_break = false;
        do
        {
            if (!(_3333 < pc.glyph_count))
            {
                _3341_ladder_break = true;
                break;
            }
            uvec4 _3526 = texelFetch(u_snail_text_records, _3333 * 23);
            uint _3527 = _3526.x;
            uvec4 _3538 = texelFetch(u_snail_text_records, (_3333 * 23) + 1);
            uint _3539 = _3538.x;
            uint _3547 = _3527 & 65535u;
            do
            {
                uint _3560 = (_3547 >> 10u) & 31u;
                uint _3561 = _3527 & 1023u;
                if ((_3547 >> 15u) == 0u)
                {
                    _3554 = 1.0;
                }
                else
                {
                    _3554 = -1.0;
                }
                if (_3560 == 0u)
                {
                    if (_3561 == 0u)
                    {
                        _3553 = 0.0;
                        break;
                    }
                    _3553 = (_3554 * 6.103515625e-05) * (float(_3561) * 0.0009765625);
                    break;
                }
                if (_3560 == 31u)
                {
                    _3553 = _3554 * 65504.0;
                    break;
                }
                _3553 = (_3554 * exp2(float(_3560) - 15.0)) * (1.0 + (float(_3561) * 0.0009765625));
                break;
            } while(false);
            uint _3549 = _3527 >> 16u;
            do
            {
                uint _3604 = (_3549 >> 10u) & 31u;
                uint _3605 = _3549 & 1023u;
                if ((_3549 >> 15u) == 0u)
                {
                    _3598 = 1.0;
                }
                else
                {
                    _3598 = -1.0;
                }
                if (_3604 == 0u)
                {
                    if (_3605 == 0u)
                    {
                        _3597 = 0.0;
                        break;
                    }
                    _3597 = (_3598 * 6.103515625e-05) * (float(_3605) * 0.0009765625);
                    break;
                }
                if (_3604 == 31u)
                {
                    _3597 = _3598 * 65504.0;
                    break;
                }
                _3597 = (_3598 * exp2(float(_3604) - 15.0)) * (1.0 + (float(_3605) * 0.0009765625));
                break;
            } while(false);
            uint _3642 = _3539 & 65535u;
            do
            {
                uint _3655 = (_3642 >> 10u) & 31u;
                uint _3656 = _3539 & 1023u;
                if ((_3642 >> 15u) == 0u)
                {
                    _3649 = 1.0;
                }
                else
                {
                    _3649 = -1.0;
                }
                if (_3655 == 0u)
                {
                    if (_3656 == 0u)
                    {
                        _3648 = 0.0;
                        break;
                    }
                    _3648 = (_3649 * 6.103515625e-05) * (float(_3656) * 0.0009765625);
                    break;
                }
                if (_3655 == 31u)
                {
                    _3648 = _3649 * 65504.0;
                    break;
                }
                _3648 = (_3649 * exp2(float(_3655) - 15.0)) * (1.0 + (float(_3656) * 0.0009765625));
                break;
            } while(false);
            uint _3644 = _3539 >> 16u;
            do
            {
                uint _3699 = (_3644 >> 10u) & 31u;
                uint _3700 = _3644 & 1023u;
                if ((_3644 >> 15u) == 0u)
                {
                    _3693 = 1.0;
                }
                else
                {
                    _3693 = -1.0;
                }
                if (_3699 == 0u)
                {
                    if (_3700 == 0u)
                    {
                        _3692 = 0.0;
                        break;
                    }
                    _3692 = (_3693 * 6.103515625e-05) * (float(_3700) * 0.0009765625);
                    break;
                }
                if (_3699 == 31u)
                {
                    _3692 = _3693 * 65504.0;
                    break;
                }
                _3692 = (_3693 * exp2(float(_3699) - 15.0)) * (1.0 + (float(_3700) * 0.0009765625));
                break;
            } while(false);
            vec4 _3544 = vec4(vec2(_3553, _3597), vec2(_3648, _3692));
            vec4 _3488 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 2).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 3).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 4).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 5).x));
            uvec2 _3498 = uvec2(texelFetch(u_snail_text_records, (_3333 * 23) + 8).x, texelFetch(u_snail_text_records, (_3333 * 23) + 9).x);
            vec4 _3508 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 10).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 11).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 12).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 13).x));
            uvec4 _3889 = texelFetch(u_snail_text_records, (_3333 * 23) + 14);
            uint _3890 = _3889.x;
            vec4 _3906 = vec4(float(_3890 & 255u), float((_3890 >> 8u) & 255u), float((_3890 >> 16u) & 255u), float((_3890 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            uvec4 _3917 = texelFetch(u_snail_text_records, (_3333 * 23) + 15);
            uint _3918 = _3917.x;
            vec4 _3934 = vec4(float(_3918 & 255u), float((_3918 >> 8u) & 255u), float((_3918 >> 16u) & 255u), float((_3918 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_3488.x * _3488.w) - (_3488.y * _3488.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            float _3937 = _3488.x;
            float _3938 = _3488.w;
            float _3940 = _3488.y;
            float _3941 = _3488.z;
            float _3943 = (_3937 * _3938) - (_3940 * _3941);
            vec2 _3944 = _1643 - vec2(uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 6).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_3333 * 23) + 7).x));
            float _3945 = _3944.x;
            float _3947 = _3944.y;
            vec2 _3956 = vec2(((_3938 * _3945) - (_3940 * _3947)) / _3943, (((-_3941) * _3945) + (_3937 * _3947)) / _3943);
            float _3959 = _3488.x;
            float _3960 = _3488.w;
            float _3962 = _3488.y;
            float _3963 = _3488.z;
            float _3965 = (_3959 * _3960) - (_3962 * _3963);
            float _3966 = _1628.x;
            float _3968 = _1628.y;
            float _3980 = _3488.x;
            float _3981 = _3488.w;
            float _3983 = _3488.y;
            float _3984 = _3488.z;
            float _3986 = (_3980 * _3981) - (_3983 * _3984);
            float _3987 = _1631.x;
            float _3989 = _1631.y;
            vec2 _3367 = abs(vec2(((_3960 * _3966) - (_3962 * _3968)) / _3965, (((-_3963) * _3966) + (_3959 * _3968)) / _3965)) + abs(vec2(((_3981 * _3987) - (_3983 * _3989)) / _3986, (((-_3984) * _3987) + (_3980 * _3989)) / _3986));
            vec2 _3369 = max(_3367 * 2.0, vec2(0.001000000047497451305389404296875));
            float _3370 = _3956.x;
            float _3373 = _3369.x;
            if (_3370 < (_3544.x - _3373))
            {
                _3334 = true;
            }
            else
            {
                _3334 = _3370 > (_3544.z + _3373);
            }
            if (_3334)
            {
                _3335 = true;
            }
            else
            {
                _3335 = _3956.y < (_3544.y - _3369.y);
            }
            if (_3335)
            {
                _3336 = true;
            }
            else
            {
                _3336 = _3956.y > (_3544.w + _3369.y);
            }
            if (_3336)
            {
                break;
            }
            uint _3404 = _3498.x;
            uint _3405 = _3498.y;
            int _3408 = int((_3405 >> 24u) & 255u);
            if (_3408 == 255)
            {
                break;
            }
            int _3414 = int(_3404 & 65535u);
            int _3416 = int(_3404 >> 16u);
            int _3420 = int((_3405 >> 16u) & 255u);
            int _3422 = int(_3405 & 65535u);
            float _3426 = 1.0 / max(_3367.x, 1.52587890625e-05);
            float _3429 = 1.0 / max(_3367.y, 1.52587890625e-05);
            float _4010 = _3508.y;
            float _4183 = (_3956.y * _4010) + _3508.w;
            float _4187 = max(abs(_3367.y * _4010) * 0.5, 9.9999997473787516355514526367188e-06);
            int _4190 = clamp(int(_4183 - _4187), 0, _3422);
            int _4194 = max(_4190, clamp(int(_4183 + _4187), 0, _3422));
            float _4016 = _3508.x;
            float _4205 = (_3956.x * _4016) + _3508.z;
            float _4209 = max(abs(_3367.x * _4016) * 0.5, 9.9999997473787516355514526367188e-06);
            int _4212 = clamp(int(_4205 - _4209), 0, _3420);
            int _4216 = max(_4212, clamp(int(_4205 + _4209), 0, _3420));
            float _3999 = 0.0;
            float _4000 = 0.0;
            bool _4022 = _4190 != _4194;
            int _4001 = _4190;
            for (;;)
            {
                if (!(_4001 <= _4194))
                {
                    break;
                }
                int _4229 = _3414 + _4001;
                ivec2 _4231 = ivec2(_4229, _3416);
                _4231.y = _4231.y + (_4229 >> 12);
                _4231.x = _4231.x & 4095;
                uvec4 _4037 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4231, _3408, 0).xyz, 0);
                int _4245 = _3414 + int(_4037.y);
                ivec2 _4247 = ivec2(_4245, _3416);
                _4247.y = _4247.y + (_4245 >> 12);
                _4247.x = _4247.x & 4095;
                int _4044 = int(_4037.x);
                _4002 = 0;
                for (;;)
                {
                    bool _4047_ladder_break = false;
                    do
                    {
                        if (!(_4002 < _4044))
                        {
                            _4047_ladder_break = true;
                            break;
                        }
                        int _4261 = _4247.x + _4002;
                        ivec2 _4263 = ivec2(_4261, _4247.y);
                        _4263.y = _4263.y + (_4261 >> 12);
                        _4263.x = _4263.x & 4095;
                        uvec4 _4059 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4263, _3408, 0).xyz, 0);
                        if (_4022)
                        {
                            _4003 = !(_4001 == max(int(_4059.x >> 12u), _4190));
                        }
                        else
                        {
                            _4003 = false;
                        }
                        if (_4003)
                        {
                            break;
                        }
                        ivec2 _4293 = ivec2(int(_4059.x & 4095u), int(_4059.y & 16383u));
                        do
                        {
                            vec4 _4302 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4293, _3408, 0).xyz, 0);
                            int _4371 = _4293.x + 1;
                            ivec2 _4373 = ivec2(_4371, _4293.y);
                            _4373.y = _4373.y + (_4371 >> 12);
                            _4373.x = _4373.x & 4095;
                            vec4 _4314 = vec4(_4302.xy, _4302.zw) - vec4(_3956, _3956);
                            vec2 _4316 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4373, _3408, 0).xyz, 0).xy - _3956;
                            if ((max(max(_4314.x, _4314.z), _4316.x) * _3426) < (-0.5))
                            {
                                _4295 = false;
                                break;
                            }
                            float _4327 = _4314.y;
                            float _4328 = _4314.w;
                            float _4329 = _4316.y;
                            if (abs(_4327) <= 1.52587890625e-05)
                            {
                                _4401 = 0.0;
                            }
                            else
                            {
                                _4401 = _4327;
                            }
                            if (abs(_4328) <= 1.52587890625e-05)
                            {
                                _4410 = 0.0;
                            }
                            else
                            {
                                _4410 = _4328;
                            }
                            if (abs(_4329) <= 1.52587890625e-05)
                            {
                                _4419 = 0.0;
                            }
                            else
                            {
                                _4419 = _4329;
                            }
                            uint _4400 = (11892u >> (((floatBitsToUint(_4419) >> 29u) & 4u) | ((((floatBitsToUint(_4410) >> 30u) & 2u) | ((floatBitsToUint(_4401) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_4400 != 0u)
                            {
                                vec2 _4432 = _4314.xy;
                                vec2 _4433 = _4314.zw;
                                vec2 _4436 = (_4432 - (_4433 * 2.0)) + _4316;
                                vec2 _4437 = _4432 - _4433;
                                float _4438 = _4436.y;
                                if (abs(_4438) < 1.52587890625e-05)
                                {
                                    float _4470 = _4437.y;
                                    if (abs(_4470) < 1.52587890625e-05)
                                    {
                                        _4428 = 0.0;
                                    }
                                    else
                                    {
                                        _4428 = (_4314.y * 0.5) / _4470;
                                    }
                                    _4429 = _4428;
                                }
                                else
                                {
                                    float _4442 = _4437.y;
                                    float _4444 = _4314.y;
                                    float _4445 = _4438 * _4444;
                                    float _4446 = (_4442 * _4442) - _4445;
                                    if (_4446 <= (max(_4442 * _4442, abs(_4445)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _4498 = 0.0;
                                    }
                                    else
                                    {
                                        _4498 = sqrt(_4446);
                                    }
                                    if (_4442 >= 0.0)
                                    {
                                        float _4460 = _4442 + _4498;
                                        if (abs(_4460) < 1.52587890625e-05)
                                        {
                                            _4428 = 0.0;
                                        }
                                        else
                                        {
                                            _4428 = _4444 / _4460;
                                        }
                                        _4429 = _4460 / _4438;
                                    }
                                    else
                                    {
                                        float _4450 = _4442 - _4498;
                                        if (abs(_4450) < 1.52587890625e-05)
                                        {
                                            _4428 = 0.0;
                                        }
                                        else
                                        {
                                            _4428 = _4444 / _4450;
                                        }
                                        float _4458 = _4428;
                                        _4428 = _4450 / _4438;
                                        _4429 = _4458;
                                    }
                                }
                                float _4481 = _4436.x;
                                float _4485 = _4437.x * 2.0;
                                float _4489 = _4314.x;
                                vec2 _4334 = vec2((((_4481 * _4428) - _4485) * _4428) + _4489, (((_4481 * _4429) - _4485) * _4429) + _4489) * _3426;
                                if ((_4400 & 1u) != 0u)
                                {
                                    _3999 += clamp(_4334.x + 0.5, 0.0, 1.0);
                                    _4000 = max(_4000, clamp(1.0 - (abs(_4334.x) * 2.0), 0.0, 1.0));
                                }
                                if (_4400 > 1u)
                                {
                                    _3999 -= clamp(_4334.y + 0.5, 0.0, 1.0);
                                    _4000 = max(_4000, clamp(1.0 - (abs(_4334.y) * 2.0), 0.0, 1.0));
                                }
                            }
                            _4295 = true;
                            break;
                        } while(false);
                        if (!_4295)
                        {
                            _4047_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_4047_ladder_break)
                    {
                        break;
                    }
                    _4002++;
                    continue;
                }
                _4001++;
                continue;
            }
            float _4004 = 0.0;
            float _4005 = 0.0;
            bool _4091 = _4212 != _4216;
            _4001 = _4212;
            for (;;)
            {
                if (!(_4001 <= _4216))
                {
                    break;
                }
                int _4516 = _3414 + ((_3422 + 1) + _4001);
                ivec2 _4518 = ivec2(_4516, _3416);
                _4518.y = _4518.y + (_4516 >> 12);
                _4518.x = _4518.x & 4095;
                uvec4 _4108 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4518, _3408, 0).xyz, 0);
                int _4532 = _3414 + int(_4108.y);
                ivec2 _4534 = ivec2(_4532, _3416);
                _4534.y = _4534.y + (_4532 >> 12);
                _4534.x = _4534.x & 4095;
                int _4115 = int(_4108.x);
                _4002 = 0;
                for (;;)
                {
                    bool _4118_ladder_break = false;
                    do
                    {
                        if (!(_4002 < _4115))
                        {
                            _4118_ladder_break = true;
                            break;
                        }
                        int _4548 = _4534.x + _4002;
                        ivec2 _4550 = ivec2(_4548, _4534.y);
                        _4550.y = _4550.y + (_4548 >> 12);
                        _4550.x = _4550.x & 4095;
                        uvec4 _4130 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4550, _3408, 0).xyz, 0);
                        if (_4091)
                        {
                            _4003 = !(_4001 == max(int(_4130.x >> 12u), _4212));
                        }
                        else
                        {
                            _4003 = false;
                        }
                        if (_4003)
                        {
                            break;
                        }
                        ivec2 _4580 = ivec2(int(_4130.x & 4095u), int(_4130.y & 16383u));
                        do
                        {
                            vec4 _4589 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4580, _3408, 0).xyz, 0);
                            int _4658 = _4580.x + 1;
                            ivec2 _4660 = ivec2(_4658, _4580.y);
                            _4660.y = _4660.y + (_4658 >> 12);
                            _4660.x = _4660.x & 4095;
                            vec4 _4601 = vec4(_4589.xy, _4589.zw) - vec4(_3956, _3956);
                            vec2 _4603 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4660, _3408, 0).xyz, 0).xy - _3956;
                            if ((max(max(_4601.y, _4601.w), _4603.y) * _3429) < (-0.5))
                            {
                                _4582 = false;
                                break;
                            }
                            float _4614 = _4601.x;
                            float _4615 = _4601.z;
                            float _4616 = _4603.x;
                            if (abs(_4614) <= 1.52587890625e-05)
                            {
                                _4688 = 0.0;
                            }
                            else
                            {
                                _4688 = _4614;
                            }
                            if (abs(_4615) <= 1.52587890625e-05)
                            {
                                _4697 = 0.0;
                            }
                            else
                            {
                                _4697 = _4615;
                            }
                            if (abs(_4616) <= 1.52587890625e-05)
                            {
                                _4706 = 0.0;
                            }
                            else
                            {
                                _4706 = _4616;
                            }
                            uint _4687 = (11892u >> (((floatBitsToUint(_4706) >> 29u) & 4u) | ((((floatBitsToUint(_4697) >> 30u) & 2u) | ((floatBitsToUint(_4688) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_4687 != 0u)
                            {
                                vec2 _4719 = _4601.xy;
                                vec2 _4720 = _4601.zw;
                                vec2 _4723 = (_4719 - (_4720 * 2.0)) + _4603;
                                vec2 _4724 = _4719 - _4720;
                                float _4725 = _4723.x;
                                if (abs(_4725) < 1.52587890625e-05)
                                {
                                    float _4757 = _4724.x;
                                    if (abs(_4757) < 1.52587890625e-05)
                                    {
                                        _4715 = 0.0;
                                    }
                                    else
                                    {
                                        _4715 = (_4601.x * 0.5) / _4757;
                                    }
                                    _4716 = _4715;
                                }
                                else
                                {
                                    float _4729 = _4724.x;
                                    float _4731 = _4601.x;
                                    float _4732 = _4725 * _4731;
                                    float _4733 = (_4729 * _4729) - _4732;
                                    if (_4733 <= (max(_4729 * _4729, abs(_4732)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _4785 = 0.0;
                                    }
                                    else
                                    {
                                        _4785 = sqrt(_4733);
                                    }
                                    if (_4729 >= 0.0)
                                    {
                                        float _4747 = _4729 + _4785;
                                        if (abs(_4747) < 1.52587890625e-05)
                                        {
                                            _4715 = 0.0;
                                        }
                                        else
                                        {
                                            _4715 = _4731 / _4747;
                                        }
                                        _4716 = _4747 / _4725;
                                    }
                                    else
                                    {
                                        float _4737 = _4729 - _4785;
                                        if (abs(_4737) < 1.52587890625e-05)
                                        {
                                            _4715 = 0.0;
                                        }
                                        else
                                        {
                                            _4715 = _4731 / _4737;
                                        }
                                        float _4745 = _4715;
                                        _4715 = _4737 / _4725;
                                        _4716 = _4745;
                                    }
                                }
                                float _4768 = _4723.y;
                                float _4772 = _4724.y * 2.0;
                                float _4776 = _4601.y;
                                vec2 _4621 = vec2((((_4768 * _4715) - _4772) * _4715) + _4776, (((_4768 * _4716) - _4772) * _4716) + _4776) * _3429;
                                if ((_4687 & 1u) != 0u)
                                {
                                    _4004 -= clamp(_4621.x + 0.5, 0.0, 1.0);
                                    _4005 = max(_4005, clamp(1.0 - (abs(_4621.x) * 2.0), 0.0, 1.0));
                                }
                                if (_4687 > 1u)
                                {
                                    _4004 += clamp(_4621.y + 0.5, 0.0, 1.0);
                                    _4005 = max(_4005, clamp(1.0 - (abs(_4621.y) * 2.0), 0.0, 1.0));
                                }
                            }
                            _4582 = true;
                            break;
                        } while(false);
                        if (!_4582)
                        {
                            _4118_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_4118_ladder_break)
                    {
                        break;
                    }
                    _4002++;
                    continue;
                }
                _4001++;
                continue;
            }
            float _4171 = ((_3999 * _4000) + (_4004 * _4005)) / max(_4000 + _4005, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _4799 = 1.0 - abs((fract(_4171 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _4799 = abs(_4171);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _4816 = 1.0 - abs((fract(_3999 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _4816 = abs(_3999);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _4833 = 1.0 - abs((fract(_4004 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _4833 = abs(_4004);
                break;
            } while(false);
            float _4852 = clamp(max(_4799, min(_4816, _4833)), 0.0, 1.0);
            if (abs(0.0) <= 9.9999999747524270787835121154785e-07)
            {
                _4849 = _4852;
            }
            else
            {
                _4849 = pow(_4852, 1.0);
            }
            float _3439 = clamp((_4849 * _3906.w) * _3934.w, 0.0, 1.0);
            if (_3439 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            float _4864 = _3906.x;
            if (_4864 <= 0.040449999272823333740234375)
            {
                _4871 = _4864 * 0.077399380505084991455078125;
            }
            else
            {
                _4871 = pow((_4864 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _4866 = _3906.y;
            if (_4866 <= 0.040449999272823333740234375)
            {
                _4883 = _4866 * 0.077399380505084991455078125;
            }
            else
            {
                _4883 = pow((_4866 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _4868 = _3906.z;
            if (_4868 <= 0.040449999272823333740234375)
            {
                _4895 = _4868 * 0.077399380505084991455078125;
            }
            else
            {
                _4895 = pow((_4868 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _4909 = _3934.x;
            if (_4909 <= 0.040449999272823333740234375)
            {
                _4916 = _4909 * 0.077399380505084991455078125;
            }
            else
            {
                _4916 = pow((_4909 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _4911 = _3934.y;
            if (_4911 <= 0.040449999272823333740234375)
            {
                _4928 = _4911 * 0.077399380505084991455078125;
            }
            else
            {
                _4928 = pow((_4911 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _4913 = _3934.z;
            if (_4913 <= 0.040449999272823333740234375)
            {
                _4940 = _4913 * 0.077399380505084991455078125;
            }
            else
            {
                _4940 = pow((_4913 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            vec4 _3449 = _3332;
            float _3451 = 1.0 - _3439;
            vec3 _3453 = ((vec3(_4871, _4883, _4895) * vec3(_4916, _4928, _4940)) * _3439) + (_3449.xyz * _3451);
            vec4 _10387 = _3449;
            _10387.x = _3453.x;
            _10387.y = _3453.y;
            _10387.z = _3453.z;
            _10387.w = _3439 + (_10387.w * _3451);
            _3332 = _10387;
            break;
        } while(false);
        if (_3341_ladder_break)
        {
            break;
        }
        _3333++;
        continue;
    }
    vec2 _1646 = scene_pos - _1642;
    vec4 _4957 = vec4(0.0);
    int _4958 = 0;
    bool _4959;
    bool _4960;
    bool _4961;
    float _5178;
    float _5179;
    float _5222;
    float _5223;
    float _5273;
    float _5274;
    float _5317;
    float _5318;
    int _5627;
    bool _5628;
    bool _5920;
    float _6026;
    float _6035;
    float _6044;
    float _6053;
    float _6054;
    float _6123;
    bool _6207;
    float _6313;
    float _6322;
    float _6331;
    float _6340;
    float _6341;
    float _6410;
    float _6424;
    float _6441;
    float _6458;
    float _6474;
    float _6496;
    float _6508;
    float _6520;
    float _6541;
    float _6553;
    float _6565;
    for (;;)
    {
        bool _4966_ladder_break = false;
        do
        {
            if (!(_4958 < pc.glyph_count))
            {
                _4966_ladder_break = true;
                break;
            }
            uvec4 _5151 = texelFetch(u_snail_text_records, _4958 * 23);
            uint _5152 = _5151.x;
            uvec4 _5163 = texelFetch(u_snail_text_records, (_4958 * 23) + 1);
            uint _5164 = _5163.x;
            uint _5172 = _5152 & 65535u;
            do
            {
                uint _5185 = (_5172 >> 10u) & 31u;
                uint _5186 = _5152 & 1023u;
                if ((_5172 >> 15u) == 0u)
                {
                    _5179 = 1.0;
                }
                else
                {
                    _5179 = -1.0;
                }
                if (_5185 == 0u)
                {
                    if (_5186 == 0u)
                    {
                        _5178 = 0.0;
                        break;
                    }
                    _5178 = (_5179 * 6.103515625e-05) * (float(_5186) * 0.0009765625);
                    break;
                }
                if (_5185 == 31u)
                {
                    _5178 = _5179 * 65504.0;
                    break;
                }
                _5178 = (_5179 * exp2(float(_5185) - 15.0)) * (1.0 + (float(_5186) * 0.0009765625));
                break;
            } while(false);
            uint _5174 = _5152 >> 16u;
            do
            {
                uint _5229 = (_5174 >> 10u) & 31u;
                uint _5230 = _5174 & 1023u;
                if ((_5174 >> 15u) == 0u)
                {
                    _5223 = 1.0;
                }
                else
                {
                    _5223 = -1.0;
                }
                if (_5229 == 0u)
                {
                    if (_5230 == 0u)
                    {
                        _5222 = 0.0;
                        break;
                    }
                    _5222 = (_5223 * 6.103515625e-05) * (float(_5230) * 0.0009765625);
                    break;
                }
                if (_5229 == 31u)
                {
                    _5222 = _5223 * 65504.0;
                    break;
                }
                _5222 = (_5223 * exp2(float(_5229) - 15.0)) * (1.0 + (float(_5230) * 0.0009765625));
                break;
            } while(false);
            uint _5267 = _5164 & 65535u;
            do
            {
                uint _5280 = (_5267 >> 10u) & 31u;
                uint _5281 = _5164 & 1023u;
                if ((_5267 >> 15u) == 0u)
                {
                    _5274 = 1.0;
                }
                else
                {
                    _5274 = -1.0;
                }
                if (_5280 == 0u)
                {
                    if (_5281 == 0u)
                    {
                        _5273 = 0.0;
                        break;
                    }
                    _5273 = (_5274 * 6.103515625e-05) * (float(_5281) * 0.0009765625);
                    break;
                }
                if (_5280 == 31u)
                {
                    _5273 = _5274 * 65504.0;
                    break;
                }
                _5273 = (_5274 * exp2(float(_5280) - 15.0)) * (1.0 + (float(_5281) * 0.0009765625));
                break;
            } while(false);
            uint _5269 = _5164 >> 16u;
            do
            {
                uint _5324 = (_5269 >> 10u) & 31u;
                uint _5325 = _5269 & 1023u;
                if ((_5269 >> 15u) == 0u)
                {
                    _5318 = 1.0;
                }
                else
                {
                    _5318 = -1.0;
                }
                if (_5324 == 0u)
                {
                    if (_5325 == 0u)
                    {
                        _5317 = 0.0;
                        break;
                    }
                    _5317 = (_5318 * 6.103515625e-05) * (float(_5325) * 0.0009765625);
                    break;
                }
                if (_5324 == 31u)
                {
                    _5317 = _5318 * 65504.0;
                    break;
                }
                _5317 = (_5318 * exp2(float(_5324) - 15.0)) * (1.0 + (float(_5325) * 0.0009765625));
                break;
            } while(false);
            vec4 _5169 = vec4(vec2(_5178, _5222), vec2(_5273, _5317));
            vec4 _5113 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 2).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 3).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 4).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 5).x));
            uvec2 _5123 = uvec2(texelFetch(u_snail_text_records, (_4958 * 23) + 8).x, texelFetch(u_snail_text_records, (_4958 * 23) + 9).x);
            vec4 _5133 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 10).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 11).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 12).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 13).x));
            uvec4 _5514 = texelFetch(u_snail_text_records, (_4958 * 23) + 14);
            uint _5515 = _5514.x;
            vec4 _5531 = vec4(float(_5515 & 255u), float((_5515 >> 8u) & 255u), float((_5515 >> 16u) & 255u), float((_5515 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            uvec4 _5542 = texelFetch(u_snail_text_records, (_4958 * 23) + 15);
            uint _5543 = _5542.x;
            vec4 _5559 = vec4(float(_5543 & 255u), float((_5543 >> 8u) & 255u), float((_5543 >> 16u) & 255u), float((_5543 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_5113.x * _5113.w) - (_5113.y * _5113.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            float _5562 = _5113.x;
            float _5563 = _5113.w;
            float _5565 = _5113.y;
            float _5566 = _5113.z;
            float _5568 = (_5562 * _5563) - (_5565 * _5566);
            vec2 _5569 = _1646 - vec2(uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 6).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_4958 * 23) + 7).x));
            float _5570 = _5569.x;
            float _5572 = _5569.y;
            vec2 _5581 = vec2(((_5563 * _5570) - (_5565 * _5572)) / _5568, (((-_5566) * _5570) + (_5562 * _5572)) / _5568);
            float _5584 = _5113.x;
            float _5585 = _5113.w;
            float _5587 = _5113.y;
            float _5588 = _5113.z;
            float _5590 = (_5584 * _5585) - (_5587 * _5588);
            float _5591 = _1628.x;
            float _5593 = _1628.y;
            float _5605 = _5113.x;
            float _5606 = _5113.w;
            float _5608 = _5113.y;
            float _5609 = _5113.z;
            float _5611 = (_5605 * _5606) - (_5608 * _5609);
            float _5612 = _1631.x;
            float _5614 = _1631.y;
            vec2 _4992 = abs(vec2(((_5585 * _5591) - (_5587 * _5593)) / _5590, (((-_5588) * _5591) + (_5584 * _5593)) / _5590)) + abs(vec2(((_5606 * _5612) - (_5608 * _5614)) / _5611, (((-_5609) * _5612) + (_5605 * _5614)) / _5611));
            vec2 _4994 = max(_4992 * 2.0, vec2(0.001000000047497451305389404296875));
            float _4995 = _5581.x;
            float _4998 = _4994.x;
            if (_4995 < (_5169.x - _4998))
            {
                _4959 = true;
            }
            else
            {
                _4959 = _4995 > (_5169.z + _4998);
            }
            if (_4959)
            {
                _4960 = true;
            }
            else
            {
                _4960 = _5581.y < (_5169.y - _4994.y);
            }
            if (_4960)
            {
                _4961 = true;
            }
            else
            {
                _4961 = _5581.y > (_5169.w + _4994.y);
            }
            if (_4961)
            {
                break;
            }
            uint _5029 = _5123.x;
            uint _5030 = _5123.y;
            int _5033 = int((_5030 >> 24u) & 255u);
            if (_5033 == 255)
            {
                break;
            }
            int _5039 = int(_5029 & 65535u);
            int _5041 = int(_5029 >> 16u);
            int _5045 = int((_5030 >> 16u) & 255u);
            int _5047 = int(_5030 & 65535u);
            float _5051 = 1.0 / max(_4992.x, 1.52587890625e-05);
            float _5054 = 1.0 / max(_4992.y, 1.52587890625e-05);
            float _5635 = _5133.y;
            float _5808 = (_5581.y * _5635) + _5133.w;
            float _5812 = max(abs(_4992.y * _5635) * 0.5, 9.9999997473787516355514526367188e-06);
            int _5815 = clamp(int(_5808 - _5812), 0, _5047);
            int _5819 = max(_5815, clamp(int(_5808 + _5812), 0, _5047));
            float _5641 = _5133.x;
            float _5830 = (_5581.x * _5641) + _5133.z;
            float _5834 = max(abs(_4992.x * _5641) * 0.5, 9.9999997473787516355514526367188e-06);
            int _5837 = clamp(int(_5830 - _5834), 0, _5045);
            int _5841 = max(_5837, clamp(int(_5830 + _5834), 0, _5045));
            float _5624 = 0.0;
            float _5625 = 0.0;
            bool _5647 = _5815 != _5819;
            int _5626 = _5815;
            for (;;)
            {
                if (!(_5626 <= _5819))
                {
                    break;
                }
                int _5854 = _5039 + _5626;
                ivec2 _5856 = ivec2(_5854, _5041);
                _5856.y = _5856.y + (_5854 >> 12);
                _5856.x = _5856.x & 4095;
                uvec4 _5662 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5856, _5033, 0).xyz, 0);
                int _5870 = _5039 + int(_5662.y);
                ivec2 _5872 = ivec2(_5870, _5041);
                _5872.y = _5872.y + (_5870 >> 12);
                _5872.x = _5872.x & 4095;
                int _5669 = int(_5662.x);
                _5627 = 0;
                for (;;)
                {
                    bool _5672_ladder_break = false;
                    do
                    {
                        if (!(_5627 < _5669))
                        {
                            _5672_ladder_break = true;
                            break;
                        }
                        int _5886 = _5872.x + _5627;
                        ivec2 _5888 = ivec2(_5886, _5872.y);
                        _5888.y = _5888.y + (_5886 >> 12);
                        _5888.x = _5888.x & 4095;
                        uvec4 _5684 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5888, _5033, 0).xyz, 0);
                        if (_5647)
                        {
                            _5628 = !(_5626 == max(int(_5684.x >> 12u), _5815));
                        }
                        else
                        {
                            _5628 = false;
                        }
                        if (_5628)
                        {
                            break;
                        }
                        ivec2 _5918 = ivec2(int(_5684.x & 4095u), int(_5684.y & 16383u));
                        do
                        {
                            vec4 _5927 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5918, _5033, 0).xyz, 0);
                            int _5996 = _5918.x + 1;
                            ivec2 _5998 = ivec2(_5996, _5918.y);
                            _5998.y = _5998.y + (_5996 >> 12);
                            _5998.x = _5998.x & 4095;
                            vec4 _5939 = vec4(_5927.xy, _5927.zw) - vec4(_5581, _5581);
                            vec2 _5941 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5998, _5033, 0).xyz, 0).xy - _5581;
                            if ((max(max(_5939.x, _5939.z), _5941.x) * _5051) < (-0.5))
                            {
                                _5920 = false;
                                break;
                            }
                            float _5952 = _5939.y;
                            float _5953 = _5939.w;
                            float _5954 = _5941.y;
                            if (abs(_5952) <= 1.52587890625e-05)
                            {
                                _6026 = 0.0;
                            }
                            else
                            {
                                _6026 = _5952;
                            }
                            if (abs(_5953) <= 1.52587890625e-05)
                            {
                                _6035 = 0.0;
                            }
                            else
                            {
                                _6035 = _5953;
                            }
                            if (abs(_5954) <= 1.52587890625e-05)
                            {
                                _6044 = 0.0;
                            }
                            else
                            {
                                _6044 = _5954;
                            }
                            uint _6025 = (11892u >> (((floatBitsToUint(_6044) >> 29u) & 4u) | ((((floatBitsToUint(_6035) >> 30u) & 2u) | ((floatBitsToUint(_6026) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_6025 != 0u)
                            {
                                vec2 _6057 = _5939.xy;
                                vec2 _6058 = _5939.zw;
                                vec2 _6061 = (_6057 - (_6058 * 2.0)) + _5941;
                                vec2 _6062 = _6057 - _6058;
                                float _6063 = _6061.y;
                                if (abs(_6063) < 1.52587890625e-05)
                                {
                                    float _6095 = _6062.y;
                                    if (abs(_6095) < 1.52587890625e-05)
                                    {
                                        _6053 = 0.0;
                                    }
                                    else
                                    {
                                        _6053 = (_5939.y * 0.5) / _6095;
                                    }
                                    _6054 = _6053;
                                }
                                else
                                {
                                    float _6067 = _6062.y;
                                    float _6069 = _5939.y;
                                    float _6070 = _6063 * _6069;
                                    float _6071 = (_6067 * _6067) - _6070;
                                    if (_6071 <= (max(_6067 * _6067, abs(_6070)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _6123 = 0.0;
                                    }
                                    else
                                    {
                                        _6123 = sqrt(_6071);
                                    }
                                    if (_6067 >= 0.0)
                                    {
                                        float _6085 = _6067 + _6123;
                                        if (abs(_6085) < 1.52587890625e-05)
                                        {
                                            _6053 = 0.0;
                                        }
                                        else
                                        {
                                            _6053 = _6069 / _6085;
                                        }
                                        _6054 = _6085 / _6063;
                                    }
                                    else
                                    {
                                        float _6075 = _6067 - _6123;
                                        if (abs(_6075) < 1.52587890625e-05)
                                        {
                                            _6053 = 0.0;
                                        }
                                        else
                                        {
                                            _6053 = _6069 / _6075;
                                        }
                                        float _6083 = _6053;
                                        _6053 = _6075 / _6063;
                                        _6054 = _6083;
                                    }
                                }
                                float _6106 = _6061.x;
                                float _6110 = _6062.x * 2.0;
                                float _6114 = _5939.x;
                                vec2 _5959 = vec2((((_6106 * _6053) - _6110) * _6053) + _6114, (((_6106 * _6054) - _6110) * _6054) + _6114) * _5051;
                                if ((_6025 & 1u) != 0u)
                                {
                                    _5624 += clamp(_5959.x + 0.5, 0.0, 1.0);
                                    _5625 = max(_5625, clamp(1.0 - (abs(_5959.x) * 2.0), 0.0, 1.0));
                                }
                                if (_6025 > 1u)
                                {
                                    _5624 -= clamp(_5959.y + 0.5, 0.0, 1.0);
                                    _5625 = max(_5625, clamp(1.0 - (abs(_5959.y) * 2.0), 0.0, 1.0));
                                }
                            }
                            _5920 = true;
                            break;
                        } while(false);
                        if (!_5920)
                        {
                            _5672_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_5672_ladder_break)
                    {
                        break;
                    }
                    _5627++;
                    continue;
                }
                _5626++;
                continue;
            }
            float _5629 = 0.0;
            float _5630 = 0.0;
            bool _5716 = _5837 != _5841;
            _5626 = _5837;
            for (;;)
            {
                if (!(_5626 <= _5841))
                {
                    break;
                }
                int _6141 = _5039 + ((_5047 + 1) + _5626);
                ivec2 _6143 = ivec2(_6141, _5041);
                _6143.y = _6143.y + (_6141 >> 12);
                _6143.x = _6143.x & 4095;
                uvec4 _5733 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_6143, _5033, 0).xyz, 0);
                int _6157 = _5039 + int(_5733.y);
                ivec2 _6159 = ivec2(_6157, _5041);
                _6159.y = _6159.y + (_6157 >> 12);
                _6159.x = _6159.x & 4095;
                int _5740 = int(_5733.x);
                _5627 = 0;
                for (;;)
                {
                    bool _5743_ladder_break = false;
                    do
                    {
                        if (!(_5627 < _5740))
                        {
                            _5743_ladder_break = true;
                            break;
                        }
                        int _6173 = _6159.x + _5627;
                        ivec2 _6175 = ivec2(_6173, _6159.y);
                        _6175.y = _6175.y + (_6173 >> 12);
                        _6175.x = _6175.x & 4095;
                        uvec4 _5755 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_6175, _5033, 0).xyz, 0);
                        if (_5716)
                        {
                            _5628 = !(_5626 == max(int(_5755.x >> 12u), _5837));
                        }
                        else
                        {
                            _5628 = false;
                        }
                        if (_5628)
                        {
                            break;
                        }
                        ivec2 _6205 = ivec2(int(_5755.x & 4095u), int(_5755.y & 16383u));
                        do
                        {
                            vec4 _6214 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6205, _5033, 0).xyz, 0);
                            int _6283 = _6205.x + 1;
                            ivec2 _6285 = ivec2(_6283, _6205.y);
                            _6285.y = _6285.y + (_6283 >> 12);
                            _6285.x = _6285.x & 4095;
                            vec4 _6226 = vec4(_6214.xy, _6214.zw) - vec4(_5581, _5581);
                            vec2 _6228 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6285, _5033, 0).xyz, 0).xy - _5581;
                            if ((max(max(_6226.y, _6226.w), _6228.y) * _5054) < (-0.5))
                            {
                                _6207 = false;
                                break;
                            }
                            float _6239 = _6226.x;
                            float _6240 = _6226.z;
                            float _6241 = _6228.x;
                            if (abs(_6239) <= 1.52587890625e-05)
                            {
                                _6313 = 0.0;
                            }
                            else
                            {
                                _6313 = _6239;
                            }
                            if (abs(_6240) <= 1.52587890625e-05)
                            {
                                _6322 = 0.0;
                            }
                            else
                            {
                                _6322 = _6240;
                            }
                            if (abs(_6241) <= 1.52587890625e-05)
                            {
                                _6331 = 0.0;
                            }
                            else
                            {
                                _6331 = _6241;
                            }
                            uint _6312 = (11892u >> (((floatBitsToUint(_6331) >> 29u) & 4u) | ((((floatBitsToUint(_6322) >> 30u) & 2u) | ((floatBitsToUint(_6313) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_6312 != 0u)
                            {
                                vec2 _6344 = _6226.xy;
                                vec2 _6345 = _6226.zw;
                                vec2 _6348 = (_6344 - (_6345 * 2.0)) + _6228;
                                vec2 _6349 = _6344 - _6345;
                                float _6350 = _6348.x;
                                if (abs(_6350) < 1.52587890625e-05)
                                {
                                    float _6382 = _6349.x;
                                    if (abs(_6382) < 1.52587890625e-05)
                                    {
                                        _6340 = 0.0;
                                    }
                                    else
                                    {
                                        _6340 = (_6226.x * 0.5) / _6382;
                                    }
                                    _6341 = _6340;
                                }
                                else
                                {
                                    float _6354 = _6349.x;
                                    float _6356 = _6226.x;
                                    float _6357 = _6350 * _6356;
                                    float _6358 = (_6354 * _6354) - _6357;
                                    if (_6358 <= (max(_6354 * _6354, abs(_6357)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _6410 = 0.0;
                                    }
                                    else
                                    {
                                        _6410 = sqrt(_6358);
                                    }
                                    if (_6354 >= 0.0)
                                    {
                                        float _6372 = _6354 + _6410;
                                        if (abs(_6372) < 1.52587890625e-05)
                                        {
                                            _6340 = 0.0;
                                        }
                                        else
                                        {
                                            _6340 = _6356 / _6372;
                                        }
                                        _6341 = _6372 / _6350;
                                    }
                                    else
                                    {
                                        float _6362 = _6354 - _6410;
                                        if (abs(_6362) < 1.52587890625e-05)
                                        {
                                            _6340 = 0.0;
                                        }
                                        else
                                        {
                                            _6340 = _6356 / _6362;
                                        }
                                        float _6370 = _6340;
                                        _6340 = _6362 / _6350;
                                        _6341 = _6370;
                                    }
                                }
                                float _6393 = _6348.y;
                                float _6397 = _6349.y * 2.0;
                                float _6401 = _6226.y;
                                vec2 _6246 = vec2((((_6393 * _6340) - _6397) * _6340) + _6401, (((_6393 * _6341) - _6397) * _6341) + _6401) * _5054;
                                if ((_6312 & 1u) != 0u)
                                {
                                    _5629 -= clamp(_6246.x + 0.5, 0.0, 1.0);
                                    _5630 = max(_5630, clamp(1.0 - (abs(_6246.x) * 2.0), 0.0, 1.0));
                                }
                                if (_6312 > 1u)
                                {
                                    _5629 += clamp(_6246.y + 0.5, 0.0, 1.0);
                                    _5630 = max(_5630, clamp(1.0 - (abs(_6246.y) * 2.0), 0.0, 1.0));
                                }
                            }
                            _6207 = true;
                            break;
                        } while(false);
                        if (!_6207)
                        {
                            _5743_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_5743_ladder_break)
                    {
                        break;
                    }
                    _5627++;
                    continue;
                }
                _5626++;
                continue;
            }
            float _5796 = ((_5624 * _5625) + (_5629 * _5630)) / max(_5625 + _5630, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _6424 = 1.0 - abs((fract(_5796 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _6424 = abs(_5796);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _6441 = 1.0 - abs((fract(_5624 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _6441 = abs(_5624);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _6458 = 1.0 - abs((fract(_5629 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _6458 = abs(_5629);
                break;
            } while(false);
            float _6477 = clamp(max(_6424, min(_6441, _6458)), 0.0, 1.0);
            if (abs(0.0) <= 9.9999999747524270787835121154785e-07)
            {
                _6474 = _6477;
            }
            else
            {
                _6474 = pow(_6477, 1.0);
            }
            float _5064 = clamp((_6474 * _5531.w) * _5559.w, 0.0, 1.0);
            if (_5064 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            float _6489 = _5531.x;
            if (_6489 <= 0.040449999272823333740234375)
            {
                _6496 = _6489 * 0.077399380505084991455078125;
            }
            else
            {
                _6496 = pow((_6489 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _6491 = _5531.y;
            if (_6491 <= 0.040449999272823333740234375)
            {
                _6508 = _6491 * 0.077399380505084991455078125;
            }
            else
            {
                _6508 = pow((_6491 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _6493 = _5531.z;
            if (_6493 <= 0.040449999272823333740234375)
            {
                _6520 = _6493 * 0.077399380505084991455078125;
            }
            else
            {
                _6520 = pow((_6493 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _6534 = _5559.x;
            if (_6534 <= 0.040449999272823333740234375)
            {
                _6541 = _6534 * 0.077399380505084991455078125;
            }
            else
            {
                _6541 = pow((_6534 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _6536 = _5559.y;
            if (_6536 <= 0.040449999272823333740234375)
            {
                _6553 = _6536 * 0.077399380505084991455078125;
            }
            else
            {
                _6553 = pow((_6536 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _6538 = _5559.z;
            if (_6538 <= 0.040449999272823333740234375)
            {
                _6565 = _6538 * 0.077399380505084991455078125;
            }
            else
            {
                _6565 = pow((_6538 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            vec4 _5074 = _4957;
            float _5076 = 1.0 - _5064;
            vec3 _5078 = ((vec3(_6496, _6508, _6520) * vec3(_6541, _6553, _6565)) * _5064) + (_5074.xyz * _5076);
            vec4 _10443 = _5074;
            _10443.x = _5078.x;
            _10443.y = _5078.y;
            _10443.z = _5078.z;
            _10443.w = _5064 + (_10443.w * _5076);
            _4957 = _10443;
            break;
        } while(false);
        if (_4966_ladder_break)
        {
            break;
        }
        _4958++;
        continue;
    }
    vec2 _1650 = vec2(0.0, _1638.y);
    vec2 _1651 = scene_pos + _1650;
    vec4 _6582 = vec4(0.0);
    int _6583 = 0;
    bool _6584;
    bool _6585;
    bool _6586;
    float _6803;
    float _6804;
    float _6847;
    float _6848;
    float _6898;
    float _6899;
    float _6942;
    float _6943;
    int _7252;
    bool _7253;
    bool _7545;
    float _7651;
    float _7660;
    float _7669;
    float _7678;
    float _7679;
    float _7748;
    bool _7832;
    float _7938;
    float _7947;
    float _7956;
    float _7965;
    float _7966;
    float _8035;
    float _8049;
    float _8066;
    float _8083;
    float _8099;
    float _8121;
    float _8133;
    float _8145;
    float _8166;
    float _8178;
    float _8190;
    for (;;)
    {
        bool _6591_ladder_break = false;
        do
        {
            if (!(_6583 < pc.glyph_count))
            {
                _6591_ladder_break = true;
                break;
            }
            uvec4 _6776 = texelFetch(u_snail_text_records, _6583 * 23);
            uint _6777 = _6776.x;
            uvec4 _6788 = texelFetch(u_snail_text_records, (_6583 * 23) + 1);
            uint _6789 = _6788.x;
            uint _6797 = _6777 & 65535u;
            do
            {
                uint _6810 = (_6797 >> 10u) & 31u;
                uint _6811 = _6777 & 1023u;
                if ((_6797 >> 15u) == 0u)
                {
                    _6804 = 1.0;
                }
                else
                {
                    _6804 = -1.0;
                }
                if (_6810 == 0u)
                {
                    if (_6811 == 0u)
                    {
                        _6803 = 0.0;
                        break;
                    }
                    _6803 = (_6804 * 6.103515625e-05) * (float(_6811) * 0.0009765625);
                    break;
                }
                if (_6810 == 31u)
                {
                    _6803 = _6804 * 65504.0;
                    break;
                }
                _6803 = (_6804 * exp2(float(_6810) - 15.0)) * (1.0 + (float(_6811) * 0.0009765625));
                break;
            } while(false);
            uint _6799 = _6777 >> 16u;
            do
            {
                uint _6854 = (_6799 >> 10u) & 31u;
                uint _6855 = _6799 & 1023u;
                if ((_6799 >> 15u) == 0u)
                {
                    _6848 = 1.0;
                }
                else
                {
                    _6848 = -1.0;
                }
                if (_6854 == 0u)
                {
                    if (_6855 == 0u)
                    {
                        _6847 = 0.0;
                        break;
                    }
                    _6847 = (_6848 * 6.103515625e-05) * (float(_6855) * 0.0009765625);
                    break;
                }
                if (_6854 == 31u)
                {
                    _6847 = _6848 * 65504.0;
                    break;
                }
                _6847 = (_6848 * exp2(float(_6854) - 15.0)) * (1.0 + (float(_6855) * 0.0009765625));
                break;
            } while(false);
            uint _6892 = _6789 & 65535u;
            do
            {
                uint _6905 = (_6892 >> 10u) & 31u;
                uint _6906 = _6789 & 1023u;
                if ((_6892 >> 15u) == 0u)
                {
                    _6899 = 1.0;
                }
                else
                {
                    _6899 = -1.0;
                }
                if (_6905 == 0u)
                {
                    if (_6906 == 0u)
                    {
                        _6898 = 0.0;
                        break;
                    }
                    _6898 = (_6899 * 6.103515625e-05) * (float(_6906) * 0.0009765625);
                    break;
                }
                if (_6905 == 31u)
                {
                    _6898 = _6899 * 65504.0;
                    break;
                }
                _6898 = (_6899 * exp2(float(_6905) - 15.0)) * (1.0 + (float(_6906) * 0.0009765625));
                break;
            } while(false);
            uint _6894 = _6789 >> 16u;
            do
            {
                uint _6949 = (_6894 >> 10u) & 31u;
                uint _6950 = _6894 & 1023u;
                if ((_6894 >> 15u) == 0u)
                {
                    _6943 = 1.0;
                }
                else
                {
                    _6943 = -1.0;
                }
                if (_6949 == 0u)
                {
                    if (_6950 == 0u)
                    {
                        _6942 = 0.0;
                        break;
                    }
                    _6942 = (_6943 * 6.103515625e-05) * (float(_6950) * 0.0009765625);
                    break;
                }
                if (_6949 == 31u)
                {
                    _6942 = _6943 * 65504.0;
                    break;
                }
                _6942 = (_6943 * exp2(float(_6949) - 15.0)) * (1.0 + (float(_6950) * 0.0009765625));
                break;
            } while(false);
            vec4 _6794 = vec4(vec2(_6803, _6847), vec2(_6898, _6942));
            vec4 _6738 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 2).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 3).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 4).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 5).x));
            uvec2 _6748 = uvec2(texelFetch(u_snail_text_records, (_6583 * 23) + 8).x, texelFetch(u_snail_text_records, (_6583 * 23) + 9).x);
            vec4 _6758 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 10).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 11).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 12).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 13).x));
            uvec4 _7139 = texelFetch(u_snail_text_records, (_6583 * 23) + 14);
            uint _7140 = _7139.x;
            vec4 _7156 = vec4(float(_7140 & 255u), float((_7140 >> 8u) & 255u), float((_7140 >> 16u) & 255u), float((_7140 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            uvec4 _7167 = texelFetch(u_snail_text_records, (_6583 * 23) + 15);
            uint _7168 = _7167.x;
            vec4 _7184 = vec4(float(_7168 & 255u), float((_7168 >> 8u) & 255u), float((_7168 >> 16u) & 255u), float((_7168 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_6738.x * _6738.w) - (_6738.y * _6738.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            float _7187 = _6738.x;
            float _7188 = _6738.w;
            float _7190 = _6738.y;
            float _7191 = _6738.z;
            float _7193 = (_7187 * _7188) - (_7190 * _7191);
            vec2 _7194 = _1651 - vec2(uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 6).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_6583 * 23) + 7).x));
            float _7195 = _7194.x;
            float _7197 = _7194.y;
            vec2 _7206 = vec2(((_7188 * _7195) - (_7190 * _7197)) / _7193, (((-_7191) * _7195) + (_7187 * _7197)) / _7193);
            float _7209 = _6738.x;
            float _7210 = _6738.w;
            float _7212 = _6738.y;
            float _7213 = _6738.z;
            float _7215 = (_7209 * _7210) - (_7212 * _7213);
            float _7216 = _1628.x;
            float _7218 = _1628.y;
            float _7230 = _6738.x;
            float _7231 = _6738.w;
            float _7233 = _6738.y;
            float _7234 = _6738.z;
            float _7236 = (_7230 * _7231) - (_7233 * _7234);
            float _7237 = _1631.x;
            float _7239 = _1631.y;
            vec2 _6617 = abs(vec2(((_7210 * _7216) - (_7212 * _7218)) / _7215, (((-_7213) * _7216) + (_7209 * _7218)) / _7215)) + abs(vec2(((_7231 * _7237) - (_7233 * _7239)) / _7236, (((-_7234) * _7237) + (_7230 * _7239)) / _7236));
            vec2 _6619 = max(_6617 * 2.0, vec2(0.001000000047497451305389404296875));
            float _6620 = _7206.x;
            float _6623 = _6619.x;
            if (_6620 < (_6794.x - _6623))
            {
                _6584 = true;
            }
            else
            {
                _6584 = _6620 > (_6794.z + _6623);
            }
            if (_6584)
            {
                _6585 = true;
            }
            else
            {
                _6585 = _7206.y < (_6794.y - _6619.y);
            }
            if (_6585)
            {
                _6586 = true;
            }
            else
            {
                _6586 = _7206.y > (_6794.w + _6619.y);
            }
            if (_6586)
            {
                break;
            }
            uint _6654 = _6748.x;
            uint _6655 = _6748.y;
            int _6658 = int((_6655 >> 24u) & 255u);
            if (_6658 == 255)
            {
                break;
            }
            int _6664 = int(_6654 & 65535u);
            int _6666 = int(_6654 >> 16u);
            int _6670 = int((_6655 >> 16u) & 255u);
            int _6672 = int(_6655 & 65535u);
            float _6676 = 1.0 / max(_6617.x, 1.52587890625e-05);
            float _6679 = 1.0 / max(_6617.y, 1.52587890625e-05);
            float _7260 = _6758.y;
            float _7433 = (_7206.y * _7260) + _6758.w;
            float _7437 = max(abs(_6617.y * _7260) * 0.5, 9.9999997473787516355514526367188e-06);
            int _7440 = clamp(int(_7433 - _7437), 0, _6672);
            int _7444 = max(_7440, clamp(int(_7433 + _7437), 0, _6672));
            float _7266 = _6758.x;
            float _7455 = (_7206.x * _7266) + _6758.z;
            float _7459 = max(abs(_6617.x * _7266) * 0.5, 9.9999997473787516355514526367188e-06);
            int _7462 = clamp(int(_7455 - _7459), 0, _6670);
            int _7466 = max(_7462, clamp(int(_7455 + _7459), 0, _6670));
            float _7249 = 0.0;
            float _7250 = 0.0;
            bool _7272 = _7440 != _7444;
            int _7251 = _7440;
            for (;;)
            {
                if (!(_7251 <= _7444))
                {
                    break;
                }
                int _7479 = _6664 + _7251;
                ivec2 _7481 = ivec2(_7479, _6666);
                _7481.y = _7481.y + (_7479 >> 12);
                _7481.x = _7481.x & 4095;
                uvec4 _7287 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7481, _6658, 0).xyz, 0);
                int _7495 = _6664 + int(_7287.y);
                ivec2 _7497 = ivec2(_7495, _6666);
                _7497.y = _7497.y + (_7495 >> 12);
                _7497.x = _7497.x & 4095;
                int _7294 = int(_7287.x);
                _7252 = 0;
                for (;;)
                {
                    bool _7297_ladder_break = false;
                    do
                    {
                        if (!(_7252 < _7294))
                        {
                            _7297_ladder_break = true;
                            break;
                        }
                        int _7511 = _7497.x + _7252;
                        ivec2 _7513 = ivec2(_7511, _7497.y);
                        _7513.y = _7513.y + (_7511 >> 12);
                        _7513.x = _7513.x & 4095;
                        uvec4 _7309 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7513, _6658, 0).xyz, 0);
                        if (_7272)
                        {
                            _7253 = !(_7251 == max(int(_7309.x >> 12u), _7440));
                        }
                        else
                        {
                            _7253 = false;
                        }
                        if (_7253)
                        {
                            break;
                        }
                        ivec2 _7543 = ivec2(int(_7309.x & 4095u), int(_7309.y & 16383u));
                        do
                        {
                            vec4 _7552 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7543, _6658, 0).xyz, 0);
                            int _7621 = _7543.x + 1;
                            ivec2 _7623 = ivec2(_7621, _7543.y);
                            _7623.y = _7623.y + (_7621 >> 12);
                            _7623.x = _7623.x & 4095;
                            vec4 _7564 = vec4(_7552.xy, _7552.zw) - vec4(_7206, _7206);
                            vec2 _7566 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7623, _6658, 0).xyz, 0).xy - _7206;
                            if ((max(max(_7564.x, _7564.z), _7566.x) * _6676) < (-0.5))
                            {
                                _7545 = false;
                                break;
                            }
                            float _7577 = _7564.y;
                            float _7578 = _7564.w;
                            float _7579 = _7566.y;
                            if (abs(_7577) <= 1.52587890625e-05)
                            {
                                _7651 = 0.0;
                            }
                            else
                            {
                                _7651 = _7577;
                            }
                            if (abs(_7578) <= 1.52587890625e-05)
                            {
                                _7660 = 0.0;
                            }
                            else
                            {
                                _7660 = _7578;
                            }
                            if (abs(_7579) <= 1.52587890625e-05)
                            {
                                _7669 = 0.0;
                            }
                            else
                            {
                                _7669 = _7579;
                            }
                            uint _7650 = (11892u >> (((floatBitsToUint(_7669) >> 29u) & 4u) | ((((floatBitsToUint(_7660) >> 30u) & 2u) | ((floatBitsToUint(_7651) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_7650 != 0u)
                            {
                                vec2 _7682 = _7564.xy;
                                vec2 _7683 = _7564.zw;
                                vec2 _7686 = (_7682 - (_7683 * 2.0)) + _7566;
                                vec2 _7687 = _7682 - _7683;
                                float _7688 = _7686.y;
                                if (abs(_7688) < 1.52587890625e-05)
                                {
                                    float _7720 = _7687.y;
                                    if (abs(_7720) < 1.52587890625e-05)
                                    {
                                        _7678 = 0.0;
                                    }
                                    else
                                    {
                                        _7678 = (_7564.y * 0.5) / _7720;
                                    }
                                    _7679 = _7678;
                                }
                                else
                                {
                                    float _7692 = _7687.y;
                                    float _7694 = _7564.y;
                                    float _7695 = _7688 * _7694;
                                    float _7696 = (_7692 * _7692) - _7695;
                                    if (_7696 <= (max(_7692 * _7692, abs(_7695)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _7748 = 0.0;
                                    }
                                    else
                                    {
                                        _7748 = sqrt(_7696);
                                    }
                                    if (_7692 >= 0.0)
                                    {
                                        float _7710 = _7692 + _7748;
                                        if (abs(_7710) < 1.52587890625e-05)
                                        {
                                            _7678 = 0.0;
                                        }
                                        else
                                        {
                                            _7678 = _7694 / _7710;
                                        }
                                        _7679 = _7710 / _7688;
                                    }
                                    else
                                    {
                                        float _7700 = _7692 - _7748;
                                        if (abs(_7700) < 1.52587890625e-05)
                                        {
                                            _7678 = 0.0;
                                        }
                                        else
                                        {
                                            _7678 = _7694 / _7700;
                                        }
                                        float _7708 = _7678;
                                        _7678 = _7700 / _7688;
                                        _7679 = _7708;
                                    }
                                }
                                float _7731 = _7686.x;
                                float _7735 = _7687.x * 2.0;
                                float _7739 = _7564.x;
                                vec2 _7584 = vec2((((_7731 * _7678) - _7735) * _7678) + _7739, (((_7731 * _7679) - _7735) * _7679) + _7739) * _6676;
                                if ((_7650 & 1u) != 0u)
                                {
                                    _7249 += clamp(_7584.x + 0.5, 0.0, 1.0);
                                    _7250 = max(_7250, clamp(1.0 - (abs(_7584.x) * 2.0), 0.0, 1.0));
                                }
                                if (_7650 > 1u)
                                {
                                    _7249 -= clamp(_7584.y + 0.5, 0.0, 1.0);
                                    _7250 = max(_7250, clamp(1.0 - (abs(_7584.y) * 2.0), 0.0, 1.0));
                                }
                            }
                            _7545 = true;
                            break;
                        } while(false);
                        if (!_7545)
                        {
                            _7297_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_7297_ladder_break)
                    {
                        break;
                    }
                    _7252++;
                    continue;
                }
                _7251++;
                continue;
            }
            float _7254 = 0.0;
            float _7255 = 0.0;
            bool _7341 = _7462 != _7466;
            _7251 = _7462;
            for (;;)
            {
                if (!(_7251 <= _7466))
                {
                    break;
                }
                int _7766 = _6664 + ((_6672 + 1) + _7251);
                ivec2 _7768 = ivec2(_7766, _6666);
                _7768.y = _7768.y + (_7766 >> 12);
                _7768.x = _7768.x & 4095;
                uvec4 _7358 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7768, _6658, 0).xyz, 0);
                int _7782 = _6664 + int(_7358.y);
                ivec2 _7784 = ivec2(_7782, _6666);
                _7784.y = _7784.y + (_7782 >> 12);
                _7784.x = _7784.x & 4095;
                int _7365 = int(_7358.x);
                _7252 = 0;
                for (;;)
                {
                    bool _7368_ladder_break = false;
                    do
                    {
                        if (!(_7252 < _7365))
                        {
                            _7368_ladder_break = true;
                            break;
                        }
                        int _7798 = _7784.x + _7252;
                        ivec2 _7800 = ivec2(_7798, _7784.y);
                        _7800.y = _7800.y + (_7798 >> 12);
                        _7800.x = _7800.x & 4095;
                        uvec4 _7380 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7800, _6658, 0).xyz, 0);
                        if (_7341)
                        {
                            _7253 = !(_7251 == max(int(_7380.x >> 12u), _7462));
                        }
                        else
                        {
                            _7253 = false;
                        }
                        if (_7253)
                        {
                            break;
                        }
                        ivec2 _7830 = ivec2(int(_7380.x & 4095u), int(_7380.y & 16383u));
                        do
                        {
                            vec4 _7839 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7830, _6658, 0).xyz, 0);
                            int _7908 = _7830.x + 1;
                            ivec2 _7910 = ivec2(_7908, _7830.y);
                            _7910.y = _7910.y + (_7908 >> 12);
                            _7910.x = _7910.x & 4095;
                            vec4 _7851 = vec4(_7839.xy, _7839.zw) - vec4(_7206, _7206);
                            vec2 _7853 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7910, _6658, 0).xyz, 0).xy - _7206;
                            if ((max(max(_7851.y, _7851.w), _7853.y) * _6679) < (-0.5))
                            {
                                _7832 = false;
                                break;
                            }
                            float _7864 = _7851.x;
                            float _7865 = _7851.z;
                            float _7866 = _7853.x;
                            if (abs(_7864) <= 1.52587890625e-05)
                            {
                                _7938 = 0.0;
                            }
                            else
                            {
                                _7938 = _7864;
                            }
                            if (abs(_7865) <= 1.52587890625e-05)
                            {
                                _7947 = 0.0;
                            }
                            else
                            {
                                _7947 = _7865;
                            }
                            if (abs(_7866) <= 1.52587890625e-05)
                            {
                                _7956 = 0.0;
                            }
                            else
                            {
                                _7956 = _7866;
                            }
                            uint _7937 = (11892u >> (((floatBitsToUint(_7956) >> 29u) & 4u) | ((((floatBitsToUint(_7947) >> 30u) & 2u) | ((floatBitsToUint(_7938) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_7937 != 0u)
                            {
                                vec2 _7969 = _7851.xy;
                                vec2 _7970 = _7851.zw;
                                vec2 _7973 = (_7969 - (_7970 * 2.0)) + _7853;
                                vec2 _7974 = _7969 - _7970;
                                float _7975 = _7973.x;
                                if (abs(_7975) < 1.52587890625e-05)
                                {
                                    float _8007 = _7974.x;
                                    if (abs(_8007) < 1.52587890625e-05)
                                    {
                                        _7965 = 0.0;
                                    }
                                    else
                                    {
                                        _7965 = (_7851.x * 0.5) / _8007;
                                    }
                                    _7966 = _7965;
                                }
                                else
                                {
                                    float _7979 = _7974.x;
                                    float _7981 = _7851.x;
                                    float _7982 = _7975 * _7981;
                                    float _7983 = (_7979 * _7979) - _7982;
                                    if (_7983 <= (max(_7979 * _7979, abs(_7982)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _8035 = 0.0;
                                    }
                                    else
                                    {
                                        _8035 = sqrt(_7983);
                                    }
                                    if (_7979 >= 0.0)
                                    {
                                        float _7997 = _7979 + _8035;
                                        if (abs(_7997) < 1.52587890625e-05)
                                        {
                                            _7965 = 0.0;
                                        }
                                        else
                                        {
                                            _7965 = _7981 / _7997;
                                        }
                                        _7966 = _7997 / _7975;
                                    }
                                    else
                                    {
                                        float _7987 = _7979 - _8035;
                                        if (abs(_7987) < 1.52587890625e-05)
                                        {
                                            _7965 = 0.0;
                                        }
                                        else
                                        {
                                            _7965 = _7981 / _7987;
                                        }
                                        float _7995 = _7965;
                                        _7965 = _7987 / _7975;
                                        _7966 = _7995;
                                    }
                                }
                                float _8018 = _7973.y;
                                float _8022 = _7974.y * 2.0;
                                float _8026 = _7851.y;
                                vec2 _7871 = vec2((((_8018 * _7965) - _8022) * _7965) + _8026, (((_8018 * _7966) - _8022) * _7966) + _8026) * _6679;
                                if ((_7937 & 1u) != 0u)
                                {
                                    _7254 -= clamp(_7871.x + 0.5, 0.0, 1.0);
                                    _7255 = max(_7255, clamp(1.0 - (abs(_7871.x) * 2.0), 0.0, 1.0));
                                }
                                if (_7937 > 1u)
                                {
                                    _7254 += clamp(_7871.y + 0.5, 0.0, 1.0);
                                    _7255 = max(_7255, clamp(1.0 - (abs(_7871.y) * 2.0), 0.0, 1.0));
                                }
                            }
                            _7832 = true;
                            break;
                        } while(false);
                        if (!_7832)
                        {
                            _7368_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_7368_ladder_break)
                    {
                        break;
                    }
                    _7252++;
                    continue;
                }
                _7251++;
                continue;
            }
            float _7421 = ((_7249 * _7250) + (_7254 * _7255)) / max(_7250 + _7255, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _8049 = 1.0 - abs((fract(_7421 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _8049 = abs(_7421);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _8066 = 1.0 - abs((fract(_7249 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _8066 = abs(_7249);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _8083 = 1.0 - abs((fract(_7254 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _8083 = abs(_7254);
                break;
            } while(false);
            float _8102 = clamp(max(_8049, min(_8066, _8083)), 0.0, 1.0);
            if (abs(0.0) <= 9.9999999747524270787835121154785e-07)
            {
                _8099 = _8102;
            }
            else
            {
                _8099 = pow(_8102, 1.0);
            }
            float _6689 = clamp((_8099 * _7156.w) * _7184.w, 0.0, 1.0);
            if (_6689 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            float _8114 = _7156.x;
            if (_8114 <= 0.040449999272823333740234375)
            {
                _8121 = _8114 * 0.077399380505084991455078125;
            }
            else
            {
                _8121 = pow((_8114 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _8116 = _7156.y;
            if (_8116 <= 0.040449999272823333740234375)
            {
                _8133 = _8116 * 0.077399380505084991455078125;
            }
            else
            {
                _8133 = pow((_8116 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _8118 = _7156.z;
            if (_8118 <= 0.040449999272823333740234375)
            {
                _8145 = _8118 * 0.077399380505084991455078125;
            }
            else
            {
                _8145 = pow((_8118 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _8159 = _7184.x;
            if (_8159 <= 0.040449999272823333740234375)
            {
                _8166 = _8159 * 0.077399380505084991455078125;
            }
            else
            {
                _8166 = pow((_8159 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _8161 = _7184.y;
            if (_8161 <= 0.040449999272823333740234375)
            {
                _8178 = _8161 * 0.077399380505084991455078125;
            }
            else
            {
                _8178 = pow((_8161 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _8163 = _7184.z;
            if (_8163 <= 0.040449999272823333740234375)
            {
                _8190 = _8163 * 0.077399380505084991455078125;
            }
            else
            {
                _8190 = pow((_8163 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            vec4 _6699 = _6582;
            float _6701 = 1.0 - _6689;
            vec3 _6703 = ((vec3(_8121, _8133, _8145) * vec3(_8166, _8178, _8190)) * _6689) + (_6699.xyz * _6701);
            vec4 _10499 = _6699;
            _10499.x = _6703.x;
            _10499.y = _6703.y;
            _10499.z = _6703.z;
            _10499.w = _6689 + (_10499.w * _6701);
            _6582 = _10499;
            break;
        } while(false);
        if (_6591_ladder_break)
        {
            break;
        }
        _6583++;
        continue;
    }
    vec2 _1654 = scene_pos - _1650;
    vec4 _8207 = vec4(0.0);
    int _8208 = 0;
    bool _8209;
    bool _8210;
    bool _8211;
    float _8428;
    float _8429;
    float _8472;
    float _8473;
    float _8523;
    float _8524;
    float _8567;
    float _8568;
    int _8877;
    bool _8878;
    bool _9170;
    float _9276;
    float _9285;
    float _9294;
    float _9303;
    float _9304;
    float _9373;
    bool _9457;
    float _9563;
    float _9572;
    float _9581;
    float _9590;
    float _9591;
    float _9660;
    float _9674;
    float _9691;
    float _9708;
    float _9724;
    float _9746;
    float _9758;
    float _9770;
    float _9791;
    float _9803;
    float _9815;
    for (;;)
    {
        bool _8216_ladder_break = false;
        do
        {
            if (!(_8208 < pc.glyph_count))
            {
                _8216_ladder_break = true;
                break;
            }
            uvec4 _8401 = texelFetch(u_snail_text_records, _8208 * 23);
            uint _8402 = _8401.x;
            uvec4 _8413 = texelFetch(u_snail_text_records, (_8208 * 23) + 1);
            uint _8414 = _8413.x;
            uint _8422 = _8402 & 65535u;
            do
            {
                uint _8435 = (_8422 >> 10u) & 31u;
                uint _8436 = _8402 & 1023u;
                if ((_8422 >> 15u) == 0u)
                {
                    _8429 = 1.0;
                }
                else
                {
                    _8429 = -1.0;
                }
                if (_8435 == 0u)
                {
                    if (_8436 == 0u)
                    {
                        _8428 = 0.0;
                        break;
                    }
                    _8428 = (_8429 * 6.103515625e-05) * (float(_8436) * 0.0009765625);
                    break;
                }
                if (_8435 == 31u)
                {
                    _8428 = _8429 * 65504.0;
                    break;
                }
                _8428 = (_8429 * exp2(float(_8435) - 15.0)) * (1.0 + (float(_8436) * 0.0009765625));
                break;
            } while(false);
            uint _8424 = _8402 >> 16u;
            do
            {
                uint _8479 = (_8424 >> 10u) & 31u;
                uint _8480 = _8424 & 1023u;
                if ((_8424 >> 15u) == 0u)
                {
                    _8473 = 1.0;
                }
                else
                {
                    _8473 = -1.0;
                }
                if (_8479 == 0u)
                {
                    if (_8480 == 0u)
                    {
                        _8472 = 0.0;
                        break;
                    }
                    _8472 = (_8473 * 6.103515625e-05) * (float(_8480) * 0.0009765625);
                    break;
                }
                if (_8479 == 31u)
                {
                    _8472 = _8473 * 65504.0;
                    break;
                }
                _8472 = (_8473 * exp2(float(_8479) - 15.0)) * (1.0 + (float(_8480) * 0.0009765625));
                break;
            } while(false);
            uint _8517 = _8414 & 65535u;
            do
            {
                uint _8530 = (_8517 >> 10u) & 31u;
                uint _8531 = _8414 & 1023u;
                if ((_8517 >> 15u) == 0u)
                {
                    _8524 = 1.0;
                }
                else
                {
                    _8524 = -1.0;
                }
                if (_8530 == 0u)
                {
                    if (_8531 == 0u)
                    {
                        _8523 = 0.0;
                        break;
                    }
                    _8523 = (_8524 * 6.103515625e-05) * (float(_8531) * 0.0009765625);
                    break;
                }
                if (_8530 == 31u)
                {
                    _8523 = _8524 * 65504.0;
                    break;
                }
                _8523 = (_8524 * exp2(float(_8530) - 15.0)) * (1.0 + (float(_8531) * 0.0009765625));
                break;
            } while(false);
            uint _8519 = _8414 >> 16u;
            do
            {
                uint _8574 = (_8519 >> 10u) & 31u;
                uint _8575 = _8519 & 1023u;
                if ((_8519 >> 15u) == 0u)
                {
                    _8568 = 1.0;
                }
                else
                {
                    _8568 = -1.0;
                }
                if (_8574 == 0u)
                {
                    if (_8575 == 0u)
                    {
                        _8567 = 0.0;
                        break;
                    }
                    _8567 = (_8568 * 6.103515625e-05) * (float(_8575) * 0.0009765625);
                    break;
                }
                if (_8574 == 31u)
                {
                    _8567 = _8568 * 65504.0;
                    break;
                }
                _8567 = (_8568 * exp2(float(_8574) - 15.0)) * (1.0 + (float(_8575) * 0.0009765625));
                break;
            } while(false);
            vec4 _8419 = vec4(vec2(_8428, _8472), vec2(_8523, _8567));
            vec4 _8363 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 2).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 3).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 4).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 5).x));
            uvec2 _8373 = uvec2(texelFetch(u_snail_text_records, (_8208 * 23) + 8).x, texelFetch(u_snail_text_records, (_8208 * 23) + 9).x);
            vec4 _8383 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 10).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 11).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 12).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 13).x));
            uvec4 _8764 = texelFetch(u_snail_text_records, (_8208 * 23) + 14);
            uint _8765 = _8764.x;
            vec4 _8781 = vec4(float(_8765 & 255u), float((_8765 >> 8u) & 255u), float((_8765 >> 16u) & 255u), float((_8765 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            uvec4 _8792 = texelFetch(u_snail_text_records, (_8208 * 23) + 15);
            uint _8793 = _8792.x;
            vec4 _8809 = vec4(float(_8793 & 255u), float((_8793 >> 8u) & 255u), float((_8793 >> 16u) & 255u), float((_8793 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_8363.x * _8363.w) - (_8363.y * _8363.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            float _8812 = _8363.x;
            float _8813 = _8363.w;
            float _8815 = _8363.y;
            float _8816 = _8363.z;
            float _8818 = (_8812 * _8813) - (_8815 * _8816);
            vec2 _8819 = _1654 - vec2(uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 6).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_8208 * 23) + 7).x));
            float _8820 = _8819.x;
            float _8822 = _8819.y;
            vec2 _8831 = vec2(((_8813 * _8820) - (_8815 * _8822)) / _8818, (((-_8816) * _8820) + (_8812 * _8822)) / _8818);
            float _8834 = _8363.x;
            float _8835 = _8363.w;
            float _8837 = _8363.y;
            float _8838 = _8363.z;
            float _8840 = (_8834 * _8835) - (_8837 * _8838);
            float _8841 = _1628.x;
            float _8843 = _1628.y;
            float _8855 = _8363.x;
            float _8856 = _8363.w;
            float _8858 = _8363.y;
            float _8859 = _8363.z;
            float _8861 = (_8855 * _8856) - (_8858 * _8859);
            float _8862 = _1631.x;
            float _8864 = _1631.y;
            vec2 _8242 = abs(vec2(((_8835 * _8841) - (_8837 * _8843)) / _8840, (((-_8838) * _8841) + (_8834 * _8843)) / _8840)) + abs(vec2(((_8856 * _8862) - (_8858 * _8864)) / _8861, (((-_8859) * _8862) + (_8855 * _8864)) / _8861));
            vec2 _8244 = max(_8242 * 2.0, vec2(0.001000000047497451305389404296875));
            float _8245 = _8831.x;
            float _8248 = _8244.x;
            if (_8245 < (_8419.x - _8248))
            {
                _8209 = true;
            }
            else
            {
                _8209 = _8245 > (_8419.z + _8248);
            }
            if (_8209)
            {
                _8210 = true;
            }
            else
            {
                _8210 = _8831.y < (_8419.y - _8244.y);
            }
            if (_8210)
            {
                _8211 = true;
            }
            else
            {
                _8211 = _8831.y > (_8419.w + _8244.y);
            }
            if (_8211)
            {
                break;
            }
            uint _8279 = _8373.x;
            uint _8280 = _8373.y;
            int _8283 = int((_8280 >> 24u) & 255u);
            if (_8283 == 255)
            {
                break;
            }
            int _8289 = int(_8279 & 65535u);
            int _8291 = int(_8279 >> 16u);
            int _8295 = int((_8280 >> 16u) & 255u);
            int _8297 = int(_8280 & 65535u);
            float _8301 = 1.0 / max(_8242.x, 1.52587890625e-05);
            float _8304 = 1.0 / max(_8242.y, 1.52587890625e-05);
            float _8885 = _8383.y;
            float _9058 = (_8831.y * _8885) + _8383.w;
            float _9062 = max(abs(_8242.y * _8885) * 0.5, 9.9999997473787516355514526367188e-06);
            int _9065 = clamp(int(_9058 - _9062), 0, _8297);
            int _9069 = max(_9065, clamp(int(_9058 + _9062), 0, _8297));
            float _8891 = _8383.x;
            float _9080 = (_8831.x * _8891) + _8383.z;
            float _9084 = max(abs(_8242.x * _8891) * 0.5, 9.9999997473787516355514526367188e-06);
            int _9087 = clamp(int(_9080 - _9084), 0, _8295);
            int _9091 = max(_9087, clamp(int(_9080 + _9084), 0, _8295));
            float _8874 = 0.0;
            float _8875 = 0.0;
            bool _8897 = _9065 != _9069;
            int _8876 = _9065;
            for (;;)
            {
                if (!(_8876 <= _9069))
                {
                    break;
                }
                int _9104 = _8289 + _8876;
                ivec2 _9106 = ivec2(_9104, _8291);
                _9106.y = _9106.y + (_9104 >> 12);
                _9106.x = _9106.x & 4095;
                uvec4 _8912 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9106, _8283, 0).xyz, 0);
                int _9120 = _8289 + int(_8912.y);
                ivec2 _9122 = ivec2(_9120, _8291);
                _9122.y = _9122.y + (_9120 >> 12);
                _9122.x = _9122.x & 4095;
                int _8919 = int(_8912.x);
                _8877 = 0;
                for (;;)
                {
                    bool _8922_ladder_break = false;
                    do
                    {
                        if (!(_8877 < _8919))
                        {
                            _8922_ladder_break = true;
                            break;
                        }
                        int _9136 = _9122.x + _8877;
                        ivec2 _9138 = ivec2(_9136, _9122.y);
                        _9138.y = _9138.y + (_9136 >> 12);
                        _9138.x = _9138.x & 4095;
                        uvec4 _8934 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9138, _8283, 0).xyz, 0);
                        if (_8897)
                        {
                            _8878 = !(_8876 == max(int(_8934.x >> 12u), _9065));
                        }
                        else
                        {
                            _8878 = false;
                        }
                        if (_8878)
                        {
                            break;
                        }
                        ivec2 _9168 = ivec2(int(_8934.x & 4095u), int(_8934.y & 16383u));
                        do
                        {
                            vec4 _9177 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9168, _8283, 0).xyz, 0);
                            int _9246 = _9168.x + 1;
                            ivec2 _9248 = ivec2(_9246, _9168.y);
                            _9248.y = _9248.y + (_9246 >> 12);
                            _9248.x = _9248.x & 4095;
                            vec4 _9189 = vec4(_9177.xy, _9177.zw) - vec4(_8831, _8831);
                            vec2 _9191 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9248, _8283, 0).xyz, 0).xy - _8831;
                            if ((max(max(_9189.x, _9189.z), _9191.x) * _8301) < (-0.5))
                            {
                                _9170 = false;
                                break;
                            }
                            float _9202 = _9189.y;
                            float _9203 = _9189.w;
                            float _9204 = _9191.y;
                            if (abs(_9202) <= 1.52587890625e-05)
                            {
                                _9276 = 0.0;
                            }
                            else
                            {
                                _9276 = _9202;
                            }
                            if (abs(_9203) <= 1.52587890625e-05)
                            {
                                _9285 = 0.0;
                            }
                            else
                            {
                                _9285 = _9203;
                            }
                            if (abs(_9204) <= 1.52587890625e-05)
                            {
                                _9294 = 0.0;
                            }
                            else
                            {
                                _9294 = _9204;
                            }
                            uint _9275 = (11892u >> (((floatBitsToUint(_9294) >> 29u) & 4u) | ((((floatBitsToUint(_9285) >> 30u) & 2u) | ((floatBitsToUint(_9276) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_9275 != 0u)
                            {
                                vec2 _9307 = _9189.xy;
                                vec2 _9308 = _9189.zw;
                                vec2 _9311 = (_9307 - (_9308 * 2.0)) + _9191;
                                vec2 _9312 = _9307 - _9308;
                                float _9313 = _9311.y;
                                if (abs(_9313) < 1.52587890625e-05)
                                {
                                    float _9345 = _9312.y;
                                    if (abs(_9345) < 1.52587890625e-05)
                                    {
                                        _9303 = 0.0;
                                    }
                                    else
                                    {
                                        _9303 = (_9189.y * 0.5) / _9345;
                                    }
                                    _9304 = _9303;
                                }
                                else
                                {
                                    float _9317 = _9312.y;
                                    float _9319 = _9189.y;
                                    float _9320 = _9313 * _9319;
                                    float _9321 = (_9317 * _9317) - _9320;
                                    if (_9321 <= (max(_9317 * _9317, abs(_9320)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _9373 = 0.0;
                                    }
                                    else
                                    {
                                        _9373 = sqrt(_9321);
                                    }
                                    if (_9317 >= 0.0)
                                    {
                                        float _9335 = _9317 + _9373;
                                        if (abs(_9335) < 1.52587890625e-05)
                                        {
                                            _9303 = 0.0;
                                        }
                                        else
                                        {
                                            _9303 = _9319 / _9335;
                                        }
                                        _9304 = _9335 / _9313;
                                    }
                                    else
                                    {
                                        float _9325 = _9317 - _9373;
                                        if (abs(_9325) < 1.52587890625e-05)
                                        {
                                            _9303 = 0.0;
                                        }
                                        else
                                        {
                                            _9303 = _9319 / _9325;
                                        }
                                        float _9333 = _9303;
                                        _9303 = _9325 / _9313;
                                        _9304 = _9333;
                                    }
                                }
                                float _9356 = _9311.x;
                                float _9360 = _9312.x * 2.0;
                                float _9364 = _9189.x;
                                vec2 _9209 = vec2((((_9356 * _9303) - _9360) * _9303) + _9364, (((_9356 * _9304) - _9360) * _9304) + _9364) * _8301;
                                if ((_9275 & 1u) != 0u)
                                {
                                    _8874 += clamp(_9209.x + 0.5, 0.0, 1.0);
                                    _8875 = max(_8875, clamp(1.0 - (abs(_9209.x) * 2.0), 0.0, 1.0));
                                }
                                if (_9275 > 1u)
                                {
                                    _8874 -= clamp(_9209.y + 0.5, 0.0, 1.0);
                                    _8875 = max(_8875, clamp(1.0 - (abs(_9209.y) * 2.0), 0.0, 1.0));
                                }
                            }
                            _9170 = true;
                            break;
                        } while(false);
                        if (!_9170)
                        {
                            _8922_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_8922_ladder_break)
                    {
                        break;
                    }
                    _8877++;
                    continue;
                }
                _8876++;
                continue;
            }
            float _8879 = 0.0;
            float _8880 = 0.0;
            bool _8966 = _9087 != _9091;
            _8876 = _9087;
            for (;;)
            {
                if (!(_8876 <= _9091))
                {
                    break;
                }
                int _9391 = _8289 + ((_8297 + 1) + _8876);
                ivec2 _9393 = ivec2(_9391, _8291);
                _9393.y = _9393.y + (_9391 >> 12);
                _9393.x = _9393.x & 4095;
                uvec4 _8983 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9393, _8283, 0).xyz, 0);
                int _9407 = _8289 + int(_8983.y);
                ivec2 _9409 = ivec2(_9407, _8291);
                _9409.y = _9409.y + (_9407 >> 12);
                _9409.x = _9409.x & 4095;
                int _8990 = int(_8983.x);
                _8877 = 0;
                for (;;)
                {
                    bool _8993_ladder_break = false;
                    do
                    {
                        if (!(_8877 < _8990))
                        {
                            _8993_ladder_break = true;
                            break;
                        }
                        int _9423 = _9409.x + _8877;
                        ivec2 _9425 = ivec2(_9423, _9409.y);
                        _9425.y = _9425.y + (_9423 >> 12);
                        _9425.x = _9425.x & 4095;
                        uvec4 _9005 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9425, _8283, 0).xyz, 0);
                        if (_8966)
                        {
                            _8878 = !(_8876 == max(int(_9005.x >> 12u), _9087));
                        }
                        else
                        {
                            _8878 = false;
                        }
                        if (_8878)
                        {
                            break;
                        }
                        ivec2 _9455 = ivec2(int(_9005.x & 4095u), int(_9005.y & 16383u));
                        do
                        {
                            vec4 _9464 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9455, _8283, 0).xyz, 0);
                            int _9533 = _9455.x + 1;
                            ivec2 _9535 = ivec2(_9533, _9455.y);
                            _9535.y = _9535.y + (_9533 >> 12);
                            _9535.x = _9535.x & 4095;
                            vec4 _9476 = vec4(_9464.xy, _9464.zw) - vec4(_8831, _8831);
                            vec2 _9478 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9535, _8283, 0).xyz, 0).xy - _8831;
                            if ((max(max(_9476.y, _9476.w), _9478.y) * _8304) < (-0.5))
                            {
                                _9457 = false;
                                break;
                            }
                            float _9489 = _9476.x;
                            float _9490 = _9476.z;
                            float _9491 = _9478.x;
                            if (abs(_9489) <= 1.52587890625e-05)
                            {
                                _9563 = 0.0;
                            }
                            else
                            {
                                _9563 = _9489;
                            }
                            if (abs(_9490) <= 1.52587890625e-05)
                            {
                                _9572 = 0.0;
                            }
                            else
                            {
                                _9572 = _9490;
                            }
                            if (abs(_9491) <= 1.52587890625e-05)
                            {
                                _9581 = 0.0;
                            }
                            else
                            {
                                _9581 = _9491;
                            }
                            uint _9562 = (11892u >> (((floatBitsToUint(_9581) >> 29u) & 4u) | ((((floatBitsToUint(_9572) >> 30u) & 2u) | ((floatBitsToUint(_9563) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_9562 != 0u)
                            {
                                vec2 _9594 = _9476.xy;
                                vec2 _9595 = _9476.zw;
                                vec2 _9598 = (_9594 - (_9595 * 2.0)) + _9478;
                                vec2 _9599 = _9594 - _9595;
                                float _9600 = _9598.x;
                                if (abs(_9600) < 1.52587890625e-05)
                                {
                                    float _9632 = _9599.x;
                                    if (abs(_9632) < 1.52587890625e-05)
                                    {
                                        _9590 = 0.0;
                                    }
                                    else
                                    {
                                        _9590 = (_9476.x * 0.5) / _9632;
                                    }
                                    _9591 = _9590;
                                }
                                else
                                {
                                    float _9604 = _9599.x;
                                    float _9606 = _9476.x;
                                    float _9607 = _9600 * _9606;
                                    float _9608 = (_9604 * _9604) - _9607;
                                    if (_9608 <= (max(_9604 * _9604, abs(_9607)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _9660 = 0.0;
                                    }
                                    else
                                    {
                                        _9660 = sqrt(_9608);
                                    }
                                    if (_9604 >= 0.0)
                                    {
                                        float _9622 = _9604 + _9660;
                                        if (abs(_9622) < 1.52587890625e-05)
                                        {
                                            _9590 = 0.0;
                                        }
                                        else
                                        {
                                            _9590 = _9606 / _9622;
                                        }
                                        _9591 = _9622 / _9600;
                                    }
                                    else
                                    {
                                        float _9612 = _9604 - _9660;
                                        if (abs(_9612) < 1.52587890625e-05)
                                        {
                                            _9590 = 0.0;
                                        }
                                        else
                                        {
                                            _9590 = _9606 / _9612;
                                        }
                                        float _9620 = _9590;
                                        _9590 = _9612 / _9600;
                                        _9591 = _9620;
                                    }
                                }
                                float _9643 = _9598.y;
                                float _9647 = _9599.y * 2.0;
                                float _9651 = _9476.y;
                                vec2 _9496 = vec2((((_9643 * _9590) - _9647) * _9590) + _9651, (((_9643 * _9591) - _9647) * _9591) + _9651) * _8304;
                                if ((_9562 & 1u) != 0u)
                                {
                                    _8879 -= clamp(_9496.x + 0.5, 0.0, 1.0);
                                    _8880 = max(_8880, clamp(1.0 - (abs(_9496.x) * 2.0), 0.0, 1.0));
                                }
                                if (_9562 > 1u)
                                {
                                    _8879 += clamp(_9496.y + 0.5, 0.0, 1.0);
                                    _8880 = max(_8880, clamp(1.0 - (abs(_9496.y) * 2.0), 0.0, 1.0));
                                }
                            }
                            _9457 = true;
                            break;
                        } while(false);
                        if (!_9457)
                        {
                            _8993_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_8993_ladder_break)
                    {
                        break;
                    }
                    _8877++;
                    continue;
                }
                _8876++;
                continue;
            }
            float _9046 = ((_8874 * _8875) + (_8879 * _8880)) / max(_8875 + _8880, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _9674 = 1.0 - abs((fract(_9046 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _9674 = abs(_9046);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _9691 = 1.0 - abs((fract(_8874 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _9691 = abs(_8874);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _9708 = 1.0 - abs((fract(_8879 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _9708 = abs(_8879);
                break;
            } while(false);
            float _9727 = clamp(max(_9674, min(_9691, _9708)), 0.0, 1.0);
            if (abs(0.0) <= 9.9999999747524270787835121154785e-07)
            {
                _9724 = _9727;
            }
            else
            {
                _9724 = pow(_9727, 1.0);
            }
            float _8314 = clamp((_9724 * _8781.w) * _8809.w, 0.0, 1.0);
            if (_8314 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            float _9739 = _8781.x;
            if (_9739 <= 0.040449999272823333740234375)
            {
                _9746 = _9739 * 0.077399380505084991455078125;
            }
            else
            {
                _9746 = pow((_9739 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _9741 = _8781.y;
            if (_9741 <= 0.040449999272823333740234375)
            {
                _9758 = _9741 * 0.077399380505084991455078125;
            }
            else
            {
                _9758 = pow((_9741 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _9743 = _8781.z;
            if (_9743 <= 0.040449999272823333740234375)
            {
                _9770 = _9743 * 0.077399380505084991455078125;
            }
            else
            {
                _9770 = pow((_9743 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _9784 = _8809.x;
            if (_9784 <= 0.040449999272823333740234375)
            {
                _9791 = _9784 * 0.077399380505084991455078125;
            }
            else
            {
                _9791 = pow((_9784 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _9786 = _8809.y;
            if (_9786 <= 0.040449999272823333740234375)
            {
                _9803 = _9786 * 0.077399380505084991455078125;
            }
            else
            {
                _9803 = pow((_9786 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _9788 = _8809.z;
            if (_9788 <= 0.040449999272823333740234375)
            {
                _9815 = _9788 * 0.077399380505084991455078125;
            }
            else
            {
                _9815 = pow((_9788 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            vec4 _8324 = _8207;
            float _8326 = 1.0 - _8314;
            vec3 _8328 = ((vec3(_9746, _9758, _9770) * vec3(_9791, _9803, _9815)) * _8314) + (_8324.xyz * _8326);
            vec4 _10555 = _8324;
            _10555.x = _8328.x;
            _10555.y = _8328.y;
            _10555.z = _8328.z;
            _10555.w = _8314 + (_10555.w * _8326);
            _8207 = _10555;
            break;
        } while(false);
        if (_8216_ladder_break)
        {
            break;
        }
        _8208++;
        continue;
    }
    vec2 _9829 = snail_io0 * 6.283185482025146484375;
    float _9847 = (((0.5 * sin(dot(_9829, vec2(1.7000000476837158203125, 0.60000002384185791015625)))) + (0.2700000107288360595703125 * sin(dot(_9829, vec2(3.900000095367431640625, -2.7000000476837158203125)) + 1.2999999523162841796875))) + (0.1500000059604644775390625 * cos(dot(_9829, vec2(7.099999904632568359375, 5.30000019073486328125)) + 0.4000000059604644775390625))) + (0.07999999821186065673828125 * sin(dot(_9829, vec2(13.69999980926513671875, -9.1000003814697265625)) + 2.099999904632568359375));
    vec2 _9850 = (snail_io0 + vec2(0.0009765625, 0.0)) * 6.283185482025146484375;
    vec2 _9871 = (snail_io0 + vec2(0.0, 0.0009765625)) * 6.283185482025146484375;
    vec3 _1675 = normalize(vec3(-((vec2(((((0.5 * sin(dot(_9850, vec2(1.7000000476837158203125, 0.60000002384185791015625)))) + (0.2700000107288360595703125 * sin(dot(_9850, vec2(3.900000095367431640625, -2.7000000476837158203125)) + 1.2999999523162841796875))) + (0.1500000059604644775390625 * cos(dot(_9850, vec2(7.099999904632568359375, 5.30000019073486328125)) + 0.4000000059604644775390625))) + (0.07999999821186065673828125 * sin(dot(_9850, vec2(13.69999980926513671875, -9.1000003814697265625)) + 2.099999904632568359375))) - _9847, ((((0.5 * sin(dot(_9871, vec2(1.7000000476837158203125, 0.60000002384185791015625)))) + (0.2700000107288360595703125 * sin(dot(_9871, vec2(3.900000095367431640625, -2.7000000476837158203125)) + 1.2999999523162841796875))) + (0.1500000059604644775390625 * cos(dot(_9871, vec2(7.099999904632568359375, 5.30000019073486328125)) + 0.4000000059604644775390625))) + (0.07999999821186065673828125 * sin(dot(_9871, vec2(13.69999980926513671875, -9.1000003814697265625)) + 2.099999904632568359375))) - _9847) * (pc.roughness * 1024.0)) + (vec2(_3332.w - _4957.w, _6582.w - _8207.w) * (0.5 * pc.relief))), 1.0));
    vec3 _1676 = normalize(pc.light_dir.xyz);
    float _1684 = clamp(_1706.w, 0.0, 1.0);
    vec3 _1700 = ((mix(pc.base_color.xyz, vec3(0.23999999463558197021484375, 0.300000011920928955078125, 0.4000000059604644775390625), vec3(_1684)) * (0.20000000298023223876953125 + ((0.7799999713897705078125 + (0.2199999988079071044921875 * _1684)) * max(dot(_1675, _1676), 0.0)))) * (0.939999997615814208984375 + (0.0599999986588954925537109375 * _9847))) + ((vec3(0.800000011920928955078125, 0.87999999523162841796875, 1.0) * pow(max(dot(_1675, normalize(_1676 + vec3(0.0, 0.0, 1.0))), 0.0), 40.0)) * (0.119999997317790985107421875 + (0.2800000011920928955078125 * _1684)));
    vec3 outc;
    if (pc.output_srgb == 1)
    {
        vec3 _9892 = clamp(_1700, vec3(0.0), vec3(1.0));
        outc = mix((pow(_9892, vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), _9892 * 12.9200000762939453125, step(_9892, vec3(0.003130800090730190277099609375)));
    }
    else
    {
        outc = _1700;
    }
    entryPointParam_fragmentMain = vec4(outc, 1.0);
}


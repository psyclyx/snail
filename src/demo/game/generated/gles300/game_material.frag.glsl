#version 300 es
precision highp float;
precision highp int;

layout(std140) uniform GameMaterialParams_std140
{
    layout(row_major) highp mat4 view_proj;
    layout(row_major) highp mat4 model;
    highp vec4 base_color;
    highp vec4 light_dir;
    highp vec2 scene_size;
    int glyph_count;
    int output_srgb;
    highp float relief;
    highp float roughness;
} pc;

uniform highp usampler2D SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler;
uniform highp usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform highp sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in highp vec2 snail_io0;
layout(location = 0) out highp vec4 entryPointParam_fragmentMain;

void main()
{
    highp vec2 scene_pos = vec2(snail_io0.x * pc.scene_size.x, (1.0 - snail_io0.y) * pc.scene_size.y);
    highp vec2 _1630 = dFdx(scene_pos);
    highp vec2 _1633 = dFdy(scene_pos);
    highp vec2 _1640 = max((abs(_1630) + abs(_1633)) * 1.25, vec2(1.52587890625e-05));
    highp vec4 _1708 = vec4(0.0);
    int _1709 = 0;
    bool _1710;
    bool _1711;
    bool _1712;
    highp float _1932;
    highp float _1933;
    highp float _1976;
    highp float _1977;
    highp float _2027;
    highp float _2028;
    highp float _2071;
    highp float _2072;
    int _2395;
    bool _2396;
    bool _2688;
    highp float _2794;
    highp float _2803;
    highp float _2812;
    highp float _2821;
    highp float _2822;
    highp float _2891;
    bool _2975;
    highp float _3081;
    highp float _3090;
    highp float _3099;
    highp float _3108;
    highp float _3109;
    highp float _3178;
    highp float _3192;
    highp float _3209;
    highp float _3226;
    highp float _3242;
    highp float _3264;
    highp float _3276;
    highp float _3288;
    highp float _3309;
    highp float _3321;
    highp float _3333;
    for (;;)
    {
        bool _1717_ladder_break = false;
        do
        {
            if (!(_1709 < pc.glyph_count))
            {
                _1717_ladder_break = true;
                break;
            }
            int _1895 = _1709 * 23;
            uvec4 _1904 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1895 - 1024 * (_1895 / 1024), _1895 / 1024), 0);
            uint _1905 = _1904.x;
            int _1909 = (_1709 * 23) + 1;
            uvec4 _1917 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1909 - 1024 * (_1909 / 1024), _1909 / 1024), 0);
            uint _1918 = _1917.x;
            uint _1926 = _1905 & 65535u;
            do
            {
                uint _1939 = (_1926 >> 10u) & 31u;
                uint _1940 = _1905 & 1023u;
                if ((_1926 >> 15u) == 0u)
                {
                    _1933 = 1.0;
                }
                else
                {
                    _1933 = -1.0;
                }
                if (_1939 == 0u)
                {
                    if (_1940 == 0u)
                    {
                        _1932 = 0.0;
                        break;
                    }
                    _1932 = (_1933 * 6.103515625e-05) * (float(_1940) * 0.0009765625);
                    break;
                }
                if (_1939 == 31u)
                {
                    _1932 = _1933 * 65504.0;
                    break;
                }
                _1932 = (_1933 * exp2(float(_1939) - 15.0)) * (1.0 + (float(_1940) * 0.0009765625));
                break;
            } while(false);
            uint _1928 = _1905 >> 16u;
            do
            {
                uint _1983 = (_1928 >> 10u) & 31u;
                uint _1984 = _1928 & 1023u;
                if ((_1928 >> 15u) == 0u)
                {
                    _1977 = 1.0;
                }
                else
                {
                    _1977 = -1.0;
                }
                if (_1983 == 0u)
                {
                    if (_1984 == 0u)
                    {
                        _1976 = 0.0;
                        break;
                    }
                    _1976 = (_1977 * 6.103515625e-05) * (float(_1984) * 0.0009765625);
                    break;
                }
                if (_1983 == 31u)
                {
                    _1976 = _1977 * 65504.0;
                    break;
                }
                _1976 = (_1977 * exp2(float(_1983) - 15.0)) * (1.0 + (float(_1984) * 0.0009765625));
                break;
            } while(false);
            uint _2021 = _1918 & 65535u;
            do
            {
                uint _2034 = (_2021 >> 10u) & 31u;
                uint _2035 = _1918 & 1023u;
                if ((_2021 >> 15u) == 0u)
                {
                    _2028 = 1.0;
                }
                else
                {
                    _2028 = -1.0;
                }
                if (_2034 == 0u)
                {
                    if (_2035 == 0u)
                    {
                        _2027 = 0.0;
                        break;
                    }
                    _2027 = (_2028 * 6.103515625e-05) * (float(_2035) * 0.0009765625);
                    break;
                }
                if (_2034 == 31u)
                {
                    _2027 = _2028 * 65504.0;
                    break;
                }
                _2027 = (_2028 * exp2(float(_2034) - 15.0)) * (1.0 + (float(_2035) * 0.0009765625));
                break;
            } while(false);
            uint _2023 = _1918 >> 16u;
            do
            {
                uint _2078 = (_2023 >> 10u) & 31u;
                uint _2079 = _2023 & 1023u;
                if ((_2023 >> 15u) == 0u)
                {
                    _2072 = 1.0;
                }
                else
                {
                    _2072 = -1.0;
                }
                if (_2078 == 0u)
                {
                    if (_2079 == 0u)
                    {
                        _2071 = 0.0;
                        break;
                    }
                    _2071 = (_2072 * 6.103515625e-05) * (float(_2079) * 0.0009765625);
                    break;
                }
                if (_2078 == 31u)
                {
                    _2071 = _2072 * 65504.0;
                    break;
                }
                _2071 = (_2072 * exp2(float(_2078) - 15.0)) * (1.0 + (float(_2079) * 0.0009765625));
                break;
            } while(false);
            highp vec4 _1923 = vec4(vec2(_1932, _1976), vec2(_2027, _2071));
            int _2117 = (_1709 * 23) + 2;
            int _2130 = (_1709 * 23) + 3;
            int _2143 = (_1709 * 23) + 4;
            int _2156 = (_1709 * 23) + 5;
            highp vec4 _1864 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2117 - 1024 * (_2117 / 1024), _2117 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2130 - 1024 * (_2130 / 1024), _2130 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2143 - 1024 * (_2143 / 1024), _2143 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2156 - 1024 * (_2156 / 1024), _2156 / 1024), 0).x));
            int _2169 = (_1709 * 23) + 6;
            int _2182 = (_1709 * 23) + 7;
            int _2195 = (_1709 * 23) + 8;
            int _2208 = (_1709 * 23) + 9;
            uvec2 _1874 = uvec2(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2195 - 1024 * (_2195 / 1024), _2195 / 1024), 0).x, texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2208 - 1024 * (_2208 / 1024), _2208 / 1024), 0).x);
            int _2221 = (_1709 * 23) + 10;
            int _2234 = (_1709 * 23) + 11;
            int _2247 = (_1709 * 23) + 12;
            int _2260 = (_1709 * 23) + 13;
            highp vec4 _1884 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2221 - 1024 * (_2221 / 1024), _2221 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2234 - 1024 * (_2234 / 1024), _2234 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2247 - 1024 * (_2247 / 1024), _2247 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2260 - 1024 * (_2260 / 1024), _2260 / 1024), 0).x));
            int _2273 = (_1709 * 23) + 14;
            uvec4 _2281 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2273 - 1024 * (_2273 / 1024), _2273 / 1024), 0);
            uint _2282 = _2281.x;
            highp vec4 _2298 = vec4(float(_2282 & 255u), float((_2282 >> 8u) & 255u), float((_2282 >> 16u) & 255u), float((_2282 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            int _2302 = (_1709 * 23) + 15;
            uvec4 _2310 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2302 - 1024 * (_2302 / 1024), _2302 / 1024), 0);
            uint _2311 = _2310.x;
            highp vec4 _2327 = vec4(float(_2311 & 255u), float((_2311 >> 8u) & 255u), float((_2311 >> 16u) & 255u), float((_2311 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_1864.x * _1864.w) - (_1864.y * _1864.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            highp float _2330 = _1864.x;
            highp float _2331 = _1864.w;
            highp float _2333 = _1864.y;
            highp float _2334 = _1864.z;
            highp float _2336 = (_2330 * _2331) - (_2333 * _2334);
            highp vec2 _2337 = scene_pos - vec2(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2169 - 1024 * (_2169 / 1024), _2169 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2182 - 1024 * (_2182 / 1024), _2182 / 1024), 0).x));
            highp float _2338 = _2337.x;
            highp float _2340 = _2337.y;
            highp vec2 _2349 = vec2(((_2331 * _2338) - (_2333 * _2340)) / _2336, (((-_2334) * _2338) + (_2330 * _2340)) / _2336);
            highp float _2352 = _1864.x;
            highp float _2353 = _1864.w;
            highp float _2355 = _1864.y;
            highp float _2356 = _1864.z;
            highp float _2358 = (_2352 * _2353) - (_2355 * _2356);
            highp float _2359 = _1630.x;
            highp float _2361 = _1630.y;
            highp float _2373 = _1864.x;
            highp float _2374 = _1864.w;
            highp float _2376 = _1864.y;
            highp float _2377 = _1864.z;
            highp float _2379 = (_2373 * _2374) - (_2376 * _2377);
            highp float _2380 = _1633.x;
            highp float _2382 = _1633.y;
            highp vec2 _1743 = abs(vec2(((_2353 * _2359) - (_2355 * _2361)) / _2358, (((-_2356) * _2359) + (_2352 * _2361)) / _2358)) + abs(vec2(((_2374 * _2380) - (_2376 * _2382)) / _2379, (((-_2377) * _2380) + (_2373 * _2382)) / _2379));
            highp vec2 _1745 = max(_1743 * 2.0, vec2(0.001000000047497451305389404296875));
            highp float _1746 = _2349.x;
            highp float _1749 = _1745.x;
            if (_1746 < (_1923.x - _1749))
            {
                _1710 = true;
            }
            else
            {
                _1710 = _1746 > (_1923.z + _1749);
            }
            if (_1710)
            {
                _1711 = true;
            }
            else
            {
                _1711 = _2349.y < (_1923.y - _1745.y);
            }
            if (_1711)
            {
                _1712 = true;
            }
            else
            {
                _1712 = _2349.y > (_1923.w + _1745.y);
            }
            if (_1712)
            {
                break;
            }
            uint _1780 = _1874.x;
            uint _1781 = _1874.y;
            int _1784 = int((_1781 >> 24u) & 255u);
            if (_1784 == 255)
            {
                break;
            }
            int _1790 = int(_1780 & 65535u);
            int _1792 = int(_1780 >> 16u);
            int _1796 = int((_1781 >> 16u) & 255u);
            int _1798 = int(_1781 & 65535u);
            highp float _1802 = 1.0 / max(_1743.x, 1.52587890625e-05);
            highp float _1805 = 1.0 / max(_1743.y, 1.52587890625e-05);
            highp float _2403 = _1884.y;
            highp float _2576 = (_2349.y * _2403) + _1884.w;
            highp float _2580 = max(abs(_1743.y * _2403) * 0.5, 9.9999997473787516355514526367188e-06);
            int _2583 = clamp(int(_2576 - _2580), 0, _1798);
            int _2587 = max(_2583, clamp(int(_2576 + _2580), 0, _1798));
            highp float _2409 = _1884.x;
            highp float _2598 = (_2349.x * _2409) + _1884.z;
            highp float _2602 = max(abs(_1743.x * _2409) * 0.5, 9.9999997473787516355514526367188e-06);
            int _2605 = clamp(int(_2598 - _2602), 0, _1796);
            int _2609 = max(_2605, clamp(int(_2598 + _2602), 0, _1796));
            highp float _2392 = 0.0;
            highp float _2393 = 0.0;
            bool _2415 = _2583 != _2587;
            int _2394 = _2583;
            for (;;)
            {
                if (!(_2394 <= _2587))
                {
                    break;
                }
                int _2622 = _1790 + _2394;
                ivec2 _2624 = ivec2(_2622, _1792);
                _2624.y = _2624.y + (_2622 >> 12);
                _2624.x = _2624.x & 4095;
                uvec4 _2430 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2624, _1784, 0).xyz, 0);
                int _2638 = _1790 + int(_2430.y);
                ivec2 _2640 = ivec2(_2638, _1792);
                _2640.y = _2640.y + (_2638 >> 12);
                _2640.x = _2640.x & 4095;
                int _2437 = int(_2430.x);
                _2395 = 0;
                for (;;)
                {
                    bool _2440_ladder_break = false;
                    do
                    {
                        if (!(_2395 < _2437))
                        {
                            _2440_ladder_break = true;
                            break;
                        }
                        int _2654 = _2640.x + _2395;
                        ivec2 _2656 = ivec2(_2654, _2640.y);
                        _2656.y = _2656.y + (_2654 >> 12);
                        _2656.x = _2656.x & 4095;
                        uvec4 _2452 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2656, _1784, 0).xyz, 0);
                        if (_2415)
                        {
                            _2396 = !(_2394 == max(int(_2452.x >> 12u), _2583));
                        }
                        else
                        {
                            _2396 = false;
                        }
                        if (_2396)
                        {
                            break;
                        }
                        ivec2 _2686 = ivec2(int(_2452.x & 4095u), int(_2452.y & 16383u));
                        do
                        {
                            highp vec4 _2695 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2686, _1784, 0).xyz, 0);
                            int _2764 = _2686.x + 1;
                            ivec2 _2766 = ivec2(_2764, _2686.y);
                            _2766.y = _2766.y + (_2764 >> 12);
                            _2766.x = _2766.x & 4095;
                            highp vec4 _2707 = vec4(_2695.xy, _2695.zw) - vec4(_2349, _2349);
                            highp vec2 _2709 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2766, _1784, 0).xyz, 0).xy - _2349;
                            if ((max(max(_2707.x, _2707.z), _2709.x) * _1802) < (-0.5))
                            {
                                _2688 = false;
                                break;
                            }
                            if (abs(_2707.y) <= 1.52587890625e-05)
                            {
                                _2794 = 0.0;
                            }
                            else
                            {
                                _2794 = _2707.y;
                            }
                            if (abs(_2707.w) <= 1.52587890625e-05)
                            {
                                _2803 = 0.0;
                            }
                            else
                            {
                                _2803 = _2707.w;
                            }
                            if (abs(_2709.y) <= 1.52587890625e-05)
                            {
                                _2812 = 0.0;
                            }
                            else
                            {
                                _2812 = _2709.y;
                            }
                            uint _2793 = (11892u >> (((floatBitsToUint(_2812) >> 29u) & 4u) | ((((floatBitsToUint(_2803) >> 30u) & 2u) | ((floatBitsToUint(_2794) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_2793 != 0u)
                            {
                                highp vec2 _2829 = (_2707.xy - (_2707.zw * 2.0)) + _2709;
                                highp vec2 _2830 = _2707.xy - _2707.zw;
                                highp float _2831 = _2829.y;
                                if (abs(_2831) < 1.52587890625e-05)
                                {
                                    highp float _2863 = _2830.y;
                                    if (abs(_2863) < 1.52587890625e-05)
                                    {
                                        _2821 = 0.0;
                                    }
                                    else
                                    {
                                        _2821 = (_2707.y * 0.5) / _2863;
                                    }
                                    _2822 = _2821;
                                }
                                else
                                {
                                    highp float _2835 = _2830.y;
                                    highp float _2838 = _2831 * _2707.y;
                                    highp float _2839 = (_2835 * _2835) - _2838;
                                    if (_2839 <= (max(_2835 * _2835, abs(_2838)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _2891 = 0.0;
                                    }
                                    else
                                    {
                                        _2891 = sqrt(_2839);
                                    }
                                    if (_2835 >= 0.0)
                                    {
                                        highp float _2853 = _2835 + _2891;
                                        if (abs(_2853) < 1.52587890625e-05)
                                        {
                                            _2821 = 0.0;
                                        }
                                        else
                                        {
                                            _2821 = _2707.y / _2853;
                                        }
                                        _2822 = _2853 / _2831;
                                    }
                                    else
                                    {
                                        highp float _2843 = _2835 - _2891;
                                        if (abs(_2843) < 1.52587890625e-05)
                                        {
                                            _2821 = 0.0;
                                        }
                                        else
                                        {
                                            _2821 = _2707.y / _2843;
                                        }
                                        highp float _2851 = _2821;
                                        _2821 = _2843 / _2831;
                                        _2822 = _2851;
                                    }
                                }
                                highp float _2874 = _2829.x;
                                highp float _2878 = _2830.x * 2.0;
                                highp vec2 _2727 = vec2((((_2874 * _2821) - _2878) * _2821) + _2707.x, (((_2874 * _2822) - _2878) * _2822) + _2707.x) * _1802;
                                if ((_2793 & 1u) != 0u)
                                {
                                    highp float _2731 = _2727.x;
                                    _2392 += clamp(_2731 + 0.5, 0.0, 1.0);
                                    _2393 = max(_2393, clamp(1.0 - (abs(_2731) * 2.0), 0.0, 1.0));
                                }
                                if (_2793 > 1u)
                                {
                                    highp float _2745 = _2727.y;
                                    _2392 -= clamp(_2745 + 0.5, 0.0, 1.0);
                                    _2393 = max(_2393, clamp(1.0 - (abs(_2745) * 2.0), 0.0, 1.0));
                                }
                            }
                            _2688 = true;
                            break;
                        } while(false);
                        if (!_2688)
                        {
                            _2440_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_2440_ladder_break)
                    {
                        break;
                    }
                    _2395++;
                    continue;
                }
                _2394++;
                continue;
            }
            highp float _2397 = 0.0;
            highp float _2398 = 0.0;
            bool _2484 = _2605 != _2609;
            _2394 = _2605;
            for (;;)
            {
                if (!(_2394 <= _2609))
                {
                    break;
                }
                int _2909 = _1790 + ((_1798 + 1) + _2394);
                ivec2 _2911 = ivec2(_2909, _1792);
                _2911.y = _2911.y + (_2909 >> 12);
                _2911.x = _2911.x & 4095;
                uvec4 _2501 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2911, _1784, 0).xyz, 0);
                int _2925 = _1790 + int(_2501.y);
                ivec2 _2927 = ivec2(_2925, _1792);
                _2927.y = _2927.y + (_2925 >> 12);
                _2927.x = _2927.x & 4095;
                int _2508 = int(_2501.x);
                _2395 = 0;
                for (;;)
                {
                    bool _2511_ladder_break = false;
                    do
                    {
                        if (!(_2395 < _2508))
                        {
                            _2511_ladder_break = true;
                            break;
                        }
                        int _2941 = _2927.x + _2395;
                        ivec2 _2943 = ivec2(_2941, _2927.y);
                        _2943.y = _2943.y + (_2941 >> 12);
                        _2943.x = _2943.x & 4095;
                        uvec4 _2523 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2943, _1784, 0).xyz, 0);
                        if (_2484)
                        {
                            _2396 = !(_2394 == max(int(_2523.x >> 12u), _2605));
                        }
                        else
                        {
                            _2396 = false;
                        }
                        if (_2396)
                        {
                            break;
                        }
                        ivec2 _2973 = ivec2(int(_2523.x & 4095u), int(_2523.y & 16383u));
                        do
                        {
                            highp vec4 _2982 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2973, _1784, 0).xyz, 0);
                            int _3051 = _2973.x + 1;
                            ivec2 _3053 = ivec2(_3051, _2973.y);
                            _3053.y = _3053.y + (_3051 >> 12);
                            _3053.x = _3053.x & 4095;
                            highp vec4 _2994 = vec4(_2982.xy, _2982.zw) - vec4(_2349, _2349);
                            highp vec2 _2996 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3053, _1784, 0).xyz, 0).xy - _2349;
                            if ((max(max(_2994.y, _2994.w), _2996.y) * _1805) < (-0.5))
                            {
                                _2975 = false;
                                break;
                            }
                            if (abs(_2994.x) <= 1.52587890625e-05)
                            {
                                _3081 = 0.0;
                            }
                            else
                            {
                                _3081 = _2994.x;
                            }
                            if (abs(_2994.z) <= 1.52587890625e-05)
                            {
                                _3090 = 0.0;
                            }
                            else
                            {
                                _3090 = _2994.z;
                            }
                            if (abs(_2996.x) <= 1.52587890625e-05)
                            {
                                _3099 = 0.0;
                            }
                            else
                            {
                                _3099 = _2996.x;
                            }
                            uint _3080 = (11892u >> (((floatBitsToUint(_3099) >> 29u) & 4u) | ((((floatBitsToUint(_3090) >> 30u) & 2u) | ((floatBitsToUint(_3081) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_3080 != 0u)
                            {
                                highp vec2 _3116 = (_2994.xy - (_2994.zw * 2.0)) + _2996;
                                highp vec2 _3117 = _2994.xy - _2994.zw;
                                highp float _3118 = _3116.x;
                                if (abs(_3118) < 1.52587890625e-05)
                                {
                                    highp float _3150 = _3117.x;
                                    if (abs(_3150) < 1.52587890625e-05)
                                    {
                                        _3108 = 0.0;
                                    }
                                    else
                                    {
                                        _3108 = (_2994.x * 0.5) / _3150;
                                    }
                                    _3109 = _3108;
                                }
                                else
                                {
                                    highp float _3122 = _3117.x;
                                    highp float _3125 = _3118 * _2994.x;
                                    highp float _3126 = (_3122 * _3122) - _3125;
                                    if (_3126 <= (max(_3122 * _3122, abs(_3125)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _3178 = 0.0;
                                    }
                                    else
                                    {
                                        _3178 = sqrt(_3126);
                                    }
                                    if (_3122 >= 0.0)
                                    {
                                        highp float _3140 = _3122 + _3178;
                                        if (abs(_3140) < 1.52587890625e-05)
                                        {
                                            _3108 = 0.0;
                                        }
                                        else
                                        {
                                            _3108 = _2994.x / _3140;
                                        }
                                        _3109 = _3140 / _3118;
                                    }
                                    else
                                    {
                                        highp float _3130 = _3122 - _3178;
                                        if (abs(_3130) < 1.52587890625e-05)
                                        {
                                            _3108 = 0.0;
                                        }
                                        else
                                        {
                                            _3108 = _2994.x / _3130;
                                        }
                                        highp float _3138 = _3108;
                                        _3108 = _3130 / _3118;
                                        _3109 = _3138;
                                    }
                                }
                                highp float _3161 = _3116.y;
                                highp float _3165 = _3117.y * 2.0;
                                highp vec2 _3014 = vec2((((_3161 * _3108) - _3165) * _3108) + _2994.y, (((_3161 * _3109) - _3165) * _3109) + _2994.y) * _1805;
                                if ((_3080 & 1u) != 0u)
                                {
                                    highp float _3018 = _3014.x;
                                    _2397 -= clamp(_3018 + 0.5, 0.0, 1.0);
                                    _2398 = max(_2398, clamp(1.0 - (abs(_3018) * 2.0), 0.0, 1.0));
                                }
                                if (_3080 > 1u)
                                {
                                    highp float _3032 = _3014.y;
                                    _2397 += clamp(_3032 + 0.5, 0.0, 1.0);
                                    _2398 = max(_2398, clamp(1.0 - (abs(_3032) * 2.0), 0.0, 1.0));
                                }
                            }
                            _2975 = true;
                            break;
                        } while(false);
                        if (!_2975)
                        {
                            _2511_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_2511_ladder_break)
                    {
                        break;
                    }
                    _2395++;
                    continue;
                }
                _2394++;
                continue;
            }
            highp float _2564 = ((_2392 * _2393) + (_2397 * _2398)) / max(_2393 + _2398, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _3192 = 1.0 - abs((fract(_2564 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _3192 = abs(_2564);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _3209 = 1.0 - abs((fract(_2392 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _3209 = abs(_2392);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _3226 = 1.0 - abs((fract(_2397 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _3226 = abs(_2397);
                break;
            } while(false);
            highp float _3245 = clamp(max(_3192, min(_3209, _3226)), 0.0, 1.0);
            highp float _3248 = abs(0.0);
            if (_3248 <= 9.9999999747524270787835121154785e-07)
            {
                _3242 = _3245;
            }
            else
            {
                _3242 = pow(_3245, 1.0);
            }
            highp float _1815 = clamp((_3242 * _2298.w) * _2327.w, 0.0, 1.0);
            if (_1815 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            highp float _3257 = _2298.x;
            if (_3257 <= 0.040449999272823333740234375)
            {
                _3264 = _3257 * 0.077399380505084991455078125;
            }
            else
            {
                _3264 = pow((_3257 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _3259 = _2298.y;
            if (_3259 <= 0.040449999272823333740234375)
            {
                _3276 = _3259 * 0.077399380505084991455078125;
            }
            else
            {
                _3276 = pow((_3259 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _3261 = _2298.z;
            if (_3261 <= 0.040449999272823333740234375)
            {
                _3288 = _3261 * 0.077399380505084991455078125;
            }
            else
            {
                _3288 = pow((_3261 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _3302 = _2327.x;
            if (_3302 <= 0.040449999272823333740234375)
            {
                _3309 = _3302 * 0.077399380505084991455078125;
            }
            else
            {
                _3309 = pow((_3302 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _3304 = _2327.y;
            if (_3304 <= 0.040449999272823333740234375)
            {
                _3321 = _3304 * 0.077399380505084991455078125;
            }
            else
            {
                _3321 = pow((_3304 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _3306 = _2327.z;
            if (_3306 <= 0.040449999272823333740234375)
            {
                _3333 = _3306 * 0.077399380505084991455078125;
            }
            else
            {
                _3333 = pow((_3306 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp vec4 _1825 = _1708;
            highp float _1827 = 1.0 - _1815;
            highp vec3 _1829 = ((vec3(_3264, _3276, _3288) * vec3(_3309, _3321, _3333)) * _1815) + (_1825.xyz * _1827);
            highp vec4 _10413 = _1825;
            _10413.x = _1829.x;
            _10413.y = _1829.y;
            _10413.z = _1829.z;
            _10413.w = _1815 + (_10413.w * _1827);
            _1708 = _10413;
            break;
        } while(false);
        if (_1717_ladder_break)
        {
            break;
        }
        _1709++;
        continue;
    }
    highp vec2 _1644 = vec2(_1640.x, 0.0);
    highp vec2 _1645 = scene_pos + _1644;
    highp vec4 _3350 = vec4(0.0);
    int _3351 = 0;
    bool _3352;
    bool _3353;
    bool _3354;
    highp float _3573;
    highp float _3574;
    highp float _3617;
    highp float _3618;
    highp float _3668;
    highp float _3669;
    highp float _3712;
    highp float _3713;
    int _4036;
    bool _4037;
    bool _4329;
    highp float _4435;
    highp float _4444;
    highp float _4453;
    highp float _4462;
    highp float _4463;
    highp float _4532;
    bool _4616;
    highp float _4722;
    highp float _4731;
    highp float _4740;
    highp float _4749;
    highp float _4750;
    highp float _4819;
    highp float _4833;
    highp float _4850;
    highp float _4867;
    highp float _4883;
    highp float _4905;
    highp float _4917;
    highp float _4929;
    highp float _4950;
    highp float _4962;
    highp float _4974;
    for (;;)
    {
        bool _3359_ladder_break = false;
        do
        {
            if (!(_3351 < pc.glyph_count))
            {
                _3359_ladder_break = true;
                break;
            }
            int _3536 = _3351 * 23;
            uvec4 _3545 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3536 - 1024 * (_3536 / 1024), _3536 / 1024), 0);
            uint _3546 = _3545.x;
            int _3550 = (_3351 * 23) + 1;
            uvec4 _3558 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3550 - 1024 * (_3550 / 1024), _3550 / 1024), 0);
            uint _3559 = _3558.x;
            uint _3567 = _3546 & 65535u;
            do
            {
                uint _3580 = (_3567 >> 10u) & 31u;
                uint _3581 = _3546 & 1023u;
                if ((_3567 >> 15u) == 0u)
                {
                    _3574 = 1.0;
                }
                else
                {
                    _3574 = -1.0;
                }
                if (_3580 == 0u)
                {
                    if (_3581 == 0u)
                    {
                        _3573 = 0.0;
                        break;
                    }
                    _3573 = (_3574 * 6.103515625e-05) * (float(_3581) * 0.0009765625);
                    break;
                }
                if (_3580 == 31u)
                {
                    _3573 = _3574 * 65504.0;
                    break;
                }
                _3573 = (_3574 * exp2(float(_3580) - 15.0)) * (1.0 + (float(_3581) * 0.0009765625));
                break;
            } while(false);
            uint _3569 = _3546 >> 16u;
            do
            {
                uint _3624 = (_3569 >> 10u) & 31u;
                uint _3625 = _3569 & 1023u;
                if ((_3569 >> 15u) == 0u)
                {
                    _3618 = 1.0;
                }
                else
                {
                    _3618 = -1.0;
                }
                if (_3624 == 0u)
                {
                    if (_3625 == 0u)
                    {
                        _3617 = 0.0;
                        break;
                    }
                    _3617 = (_3618 * 6.103515625e-05) * (float(_3625) * 0.0009765625);
                    break;
                }
                if (_3624 == 31u)
                {
                    _3617 = _3618 * 65504.0;
                    break;
                }
                _3617 = (_3618 * exp2(float(_3624) - 15.0)) * (1.0 + (float(_3625) * 0.0009765625));
                break;
            } while(false);
            uint _3662 = _3559 & 65535u;
            do
            {
                uint _3675 = (_3662 >> 10u) & 31u;
                uint _3676 = _3559 & 1023u;
                if ((_3662 >> 15u) == 0u)
                {
                    _3669 = 1.0;
                }
                else
                {
                    _3669 = -1.0;
                }
                if (_3675 == 0u)
                {
                    if (_3676 == 0u)
                    {
                        _3668 = 0.0;
                        break;
                    }
                    _3668 = (_3669 * 6.103515625e-05) * (float(_3676) * 0.0009765625);
                    break;
                }
                if (_3675 == 31u)
                {
                    _3668 = _3669 * 65504.0;
                    break;
                }
                _3668 = (_3669 * exp2(float(_3675) - 15.0)) * (1.0 + (float(_3676) * 0.0009765625));
                break;
            } while(false);
            uint _3664 = _3559 >> 16u;
            do
            {
                uint _3719 = (_3664 >> 10u) & 31u;
                uint _3720 = _3664 & 1023u;
                if ((_3664 >> 15u) == 0u)
                {
                    _3713 = 1.0;
                }
                else
                {
                    _3713 = -1.0;
                }
                if (_3719 == 0u)
                {
                    if (_3720 == 0u)
                    {
                        _3712 = 0.0;
                        break;
                    }
                    _3712 = (_3713 * 6.103515625e-05) * (float(_3720) * 0.0009765625);
                    break;
                }
                if (_3719 == 31u)
                {
                    _3712 = _3713 * 65504.0;
                    break;
                }
                _3712 = (_3713 * exp2(float(_3719) - 15.0)) * (1.0 + (float(_3720) * 0.0009765625));
                break;
            } while(false);
            highp vec4 _3564 = vec4(vec2(_3573, _3617), vec2(_3668, _3712));
            int _3758 = (_3351 * 23) + 2;
            int _3771 = (_3351 * 23) + 3;
            int _3784 = (_3351 * 23) + 4;
            int _3797 = (_3351 * 23) + 5;
            highp vec4 _3506 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3758 - 1024 * (_3758 / 1024), _3758 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3771 - 1024 * (_3771 / 1024), _3771 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3784 - 1024 * (_3784 / 1024), _3784 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3797 - 1024 * (_3797 / 1024), _3797 / 1024), 0).x));
            int _3810 = (_3351 * 23) + 6;
            int _3823 = (_3351 * 23) + 7;
            int _3836 = (_3351 * 23) + 8;
            int _3849 = (_3351 * 23) + 9;
            uvec2 _3516 = uvec2(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3836 - 1024 * (_3836 / 1024), _3836 / 1024), 0).x, texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3849 - 1024 * (_3849 / 1024), _3849 / 1024), 0).x);
            int _3862 = (_3351 * 23) + 10;
            int _3875 = (_3351 * 23) + 11;
            int _3888 = (_3351 * 23) + 12;
            int _3901 = (_3351 * 23) + 13;
            highp vec4 _3526 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3862 - 1024 * (_3862 / 1024), _3862 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3875 - 1024 * (_3875 / 1024), _3875 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3888 - 1024 * (_3888 / 1024), _3888 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3901 - 1024 * (_3901 / 1024), _3901 / 1024), 0).x));
            int _3914 = (_3351 * 23) + 14;
            uvec4 _3922 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3914 - 1024 * (_3914 / 1024), _3914 / 1024), 0);
            uint _3923 = _3922.x;
            highp vec4 _3939 = vec4(float(_3923 & 255u), float((_3923 >> 8u) & 255u), float((_3923 >> 16u) & 255u), float((_3923 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            int _3943 = (_3351 * 23) + 15;
            uvec4 _3951 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3943 - 1024 * (_3943 / 1024), _3943 / 1024), 0);
            uint _3952 = _3951.x;
            highp vec4 _3968 = vec4(float(_3952 & 255u), float((_3952 >> 8u) & 255u), float((_3952 >> 16u) & 255u), float((_3952 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_3506.x * _3506.w) - (_3506.y * _3506.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            highp float _3971 = _3506.x;
            highp float _3972 = _3506.w;
            highp float _3974 = _3506.y;
            highp float _3975 = _3506.z;
            highp float _3977 = (_3971 * _3972) - (_3974 * _3975);
            highp vec2 _3978 = _1645 - vec2(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3810 - 1024 * (_3810 / 1024), _3810 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_3823 - 1024 * (_3823 / 1024), _3823 / 1024), 0).x));
            highp float _3979 = _3978.x;
            highp float _3981 = _3978.y;
            highp vec2 _3990 = vec2(((_3972 * _3979) - (_3974 * _3981)) / _3977, (((-_3975) * _3979) + (_3971 * _3981)) / _3977);
            highp float _3993 = _3506.x;
            highp float _3994 = _3506.w;
            highp float _3996 = _3506.y;
            highp float _3997 = _3506.z;
            highp float _3999 = (_3993 * _3994) - (_3996 * _3997);
            highp float _4000 = _1630.x;
            highp float _4002 = _1630.y;
            highp float _4014 = _3506.x;
            highp float _4015 = _3506.w;
            highp float _4017 = _3506.y;
            highp float _4018 = _3506.z;
            highp float _4020 = (_4014 * _4015) - (_4017 * _4018);
            highp float _4021 = _1633.x;
            highp float _4023 = _1633.y;
            highp vec2 _3385 = abs(vec2(((_3994 * _4000) - (_3996 * _4002)) / _3999, (((-_3997) * _4000) + (_3993 * _4002)) / _3999)) + abs(vec2(((_4015 * _4021) - (_4017 * _4023)) / _4020, (((-_4018) * _4021) + (_4014 * _4023)) / _4020));
            highp vec2 _3387 = max(_3385 * 2.0, vec2(0.001000000047497451305389404296875));
            highp float _3388 = _3990.x;
            highp float _3391 = _3387.x;
            if (_3388 < (_3564.x - _3391))
            {
                _3352 = true;
            }
            else
            {
                _3352 = _3388 > (_3564.z + _3391);
            }
            if (_3352)
            {
                _3353 = true;
            }
            else
            {
                _3353 = _3990.y < (_3564.y - _3387.y);
            }
            if (_3353)
            {
                _3354 = true;
            }
            else
            {
                _3354 = _3990.y > (_3564.w + _3387.y);
            }
            if (_3354)
            {
                break;
            }
            uint _3422 = _3516.x;
            uint _3423 = _3516.y;
            int _3426 = int((_3423 >> 24u) & 255u);
            if (_3426 == 255)
            {
                break;
            }
            int _3432 = int(_3422 & 65535u);
            int _3434 = int(_3422 >> 16u);
            int _3438 = int((_3423 >> 16u) & 255u);
            int _3440 = int(_3423 & 65535u);
            highp float _3444 = 1.0 / max(_3385.x, 1.52587890625e-05);
            highp float _3447 = 1.0 / max(_3385.y, 1.52587890625e-05);
            highp float _4044 = _3526.y;
            highp float _4217 = (_3990.y * _4044) + _3526.w;
            highp float _4221 = max(abs(_3385.y * _4044) * 0.5, 9.9999997473787516355514526367188e-06);
            int _4224 = clamp(int(_4217 - _4221), 0, _3440);
            int _4228 = max(_4224, clamp(int(_4217 + _4221), 0, _3440));
            highp float _4050 = _3526.x;
            highp float _4239 = (_3990.x * _4050) + _3526.z;
            highp float _4243 = max(abs(_3385.x * _4050) * 0.5, 9.9999997473787516355514526367188e-06);
            int _4246 = clamp(int(_4239 - _4243), 0, _3438);
            int _4250 = max(_4246, clamp(int(_4239 + _4243), 0, _3438));
            highp float _4033 = 0.0;
            highp float _4034 = 0.0;
            bool _4056 = _4224 != _4228;
            int _4035 = _4224;
            for (;;)
            {
                if (!(_4035 <= _4228))
                {
                    break;
                }
                int _4263 = _3432 + _4035;
                ivec2 _4265 = ivec2(_4263, _3434);
                _4265.y = _4265.y + (_4263 >> 12);
                _4265.x = _4265.x & 4095;
                uvec4 _4071 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4265, _3426, 0).xyz, 0);
                int _4279 = _3432 + int(_4071.y);
                ivec2 _4281 = ivec2(_4279, _3434);
                _4281.y = _4281.y + (_4279 >> 12);
                _4281.x = _4281.x & 4095;
                int _4078 = int(_4071.x);
                _4036 = 0;
                for (;;)
                {
                    bool _4081_ladder_break = false;
                    do
                    {
                        if (!(_4036 < _4078))
                        {
                            _4081_ladder_break = true;
                            break;
                        }
                        int _4295 = _4281.x + _4036;
                        ivec2 _4297 = ivec2(_4295, _4281.y);
                        _4297.y = _4297.y + (_4295 >> 12);
                        _4297.x = _4297.x & 4095;
                        uvec4 _4093 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4297, _3426, 0).xyz, 0);
                        if (_4056)
                        {
                            _4037 = !(_4035 == max(int(_4093.x >> 12u), _4224));
                        }
                        else
                        {
                            _4037 = false;
                        }
                        if (_4037)
                        {
                            break;
                        }
                        ivec2 _4327 = ivec2(int(_4093.x & 4095u), int(_4093.y & 16383u));
                        do
                        {
                            highp vec4 _4336 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4327, _3426, 0).xyz, 0);
                            int _4405 = _4327.x + 1;
                            ivec2 _4407 = ivec2(_4405, _4327.y);
                            _4407.y = _4407.y + (_4405 >> 12);
                            _4407.x = _4407.x & 4095;
                            highp vec4 _4348 = vec4(_4336.xy, _4336.zw) - vec4(_3990, _3990);
                            highp vec2 _4350 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4407, _3426, 0).xyz, 0).xy - _3990;
                            if ((max(max(_4348.x, _4348.z), _4350.x) * _3444) < (-0.5))
                            {
                                _4329 = false;
                                break;
                            }
                            if (abs(_4348.y) <= 1.52587890625e-05)
                            {
                                _4435 = 0.0;
                            }
                            else
                            {
                                _4435 = _4348.y;
                            }
                            if (abs(_4348.w) <= 1.52587890625e-05)
                            {
                                _4444 = 0.0;
                            }
                            else
                            {
                                _4444 = _4348.w;
                            }
                            if (abs(_4350.y) <= 1.52587890625e-05)
                            {
                                _4453 = 0.0;
                            }
                            else
                            {
                                _4453 = _4350.y;
                            }
                            uint _4434 = (11892u >> (((floatBitsToUint(_4453) >> 29u) & 4u) | ((((floatBitsToUint(_4444) >> 30u) & 2u) | ((floatBitsToUint(_4435) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_4434 != 0u)
                            {
                                highp vec2 _4470 = (_4348.xy - (_4348.zw * 2.0)) + _4350;
                                highp vec2 _4471 = _4348.xy - _4348.zw;
                                highp float _4472 = _4470.y;
                                if (abs(_4472) < 1.52587890625e-05)
                                {
                                    highp float _4504 = _4471.y;
                                    if (abs(_4504) < 1.52587890625e-05)
                                    {
                                        _4462 = 0.0;
                                    }
                                    else
                                    {
                                        _4462 = (_4348.y * 0.5) / _4504;
                                    }
                                    _4463 = _4462;
                                }
                                else
                                {
                                    highp float _4476 = _4471.y;
                                    highp float _4479 = _4472 * _4348.y;
                                    highp float _4480 = (_4476 * _4476) - _4479;
                                    if (_4480 <= (max(_4476 * _4476, abs(_4479)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _4532 = 0.0;
                                    }
                                    else
                                    {
                                        _4532 = sqrt(_4480);
                                    }
                                    if (_4476 >= 0.0)
                                    {
                                        highp float _4494 = _4476 + _4532;
                                        if (abs(_4494) < 1.52587890625e-05)
                                        {
                                            _4462 = 0.0;
                                        }
                                        else
                                        {
                                            _4462 = _4348.y / _4494;
                                        }
                                        _4463 = _4494 / _4472;
                                    }
                                    else
                                    {
                                        highp float _4484 = _4476 - _4532;
                                        if (abs(_4484) < 1.52587890625e-05)
                                        {
                                            _4462 = 0.0;
                                        }
                                        else
                                        {
                                            _4462 = _4348.y / _4484;
                                        }
                                        highp float _4492 = _4462;
                                        _4462 = _4484 / _4472;
                                        _4463 = _4492;
                                    }
                                }
                                highp float _4515 = _4470.x;
                                highp float _4519 = _4471.x * 2.0;
                                highp vec2 _4368 = vec2((((_4515 * _4462) - _4519) * _4462) + _4348.x, (((_4515 * _4463) - _4519) * _4463) + _4348.x) * _3444;
                                if ((_4434 & 1u) != 0u)
                                {
                                    highp float _4372 = _4368.x;
                                    _4033 += clamp(_4372 + 0.5, 0.0, 1.0);
                                    _4034 = max(_4034, clamp(1.0 - (abs(_4372) * 2.0), 0.0, 1.0));
                                }
                                if (_4434 > 1u)
                                {
                                    highp float _4386 = _4368.y;
                                    _4033 -= clamp(_4386 + 0.5, 0.0, 1.0);
                                    _4034 = max(_4034, clamp(1.0 - (abs(_4386) * 2.0), 0.0, 1.0));
                                }
                            }
                            _4329 = true;
                            break;
                        } while(false);
                        if (!_4329)
                        {
                            _4081_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_4081_ladder_break)
                    {
                        break;
                    }
                    _4036++;
                    continue;
                }
                _4035++;
                continue;
            }
            highp float _4038 = 0.0;
            highp float _4039 = 0.0;
            bool _4125 = _4246 != _4250;
            _4035 = _4246;
            for (;;)
            {
                if (!(_4035 <= _4250))
                {
                    break;
                }
                int _4550 = _3432 + ((_3440 + 1) + _4035);
                ivec2 _4552 = ivec2(_4550, _3434);
                _4552.y = _4552.y + (_4550 >> 12);
                _4552.x = _4552.x & 4095;
                uvec4 _4142 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4552, _3426, 0).xyz, 0);
                int _4566 = _3432 + int(_4142.y);
                ivec2 _4568 = ivec2(_4566, _3434);
                _4568.y = _4568.y + (_4566 >> 12);
                _4568.x = _4568.x & 4095;
                int _4149 = int(_4142.x);
                _4036 = 0;
                for (;;)
                {
                    bool _4152_ladder_break = false;
                    do
                    {
                        if (!(_4036 < _4149))
                        {
                            _4152_ladder_break = true;
                            break;
                        }
                        int _4582 = _4568.x + _4036;
                        ivec2 _4584 = ivec2(_4582, _4568.y);
                        _4584.y = _4584.y + (_4582 >> 12);
                        _4584.x = _4584.x & 4095;
                        uvec4 _4164 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4584, _3426, 0).xyz, 0);
                        if (_4125)
                        {
                            _4037 = !(_4035 == max(int(_4164.x >> 12u), _4246));
                        }
                        else
                        {
                            _4037 = false;
                        }
                        if (_4037)
                        {
                            break;
                        }
                        ivec2 _4614 = ivec2(int(_4164.x & 4095u), int(_4164.y & 16383u));
                        do
                        {
                            highp vec4 _4623 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4614, _3426, 0).xyz, 0);
                            int _4692 = _4614.x + 1;
                            ivec2 _4694 = ivec2(_4692, _4614.y);
                            _4694.y = _4694.y + (_4692 >> 12);
                            _4694.x = _4694.x & 4095;
                            highp vec4 _4635 = vec4(_4623.xy, _4623.zw) - vec4(_3990, _3990);
                            highp vec2 _4637 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4694, _3426, 0).xyz, 0).xy - _3990;
                            if ((max(max(_4635.y, _4635.w), _4637.y) * _3447) < (-0.5))
                            {
                                _4616 = false;
                                break;
                            }
                            if (abs(_4635.x) <= 1.52587890625e-05)
                            {
                                _4722 = 0.0;
                            }
                            else
                            {
                                _4722 = _4635.x;
                            }
                            if (abs(_4635.z) <= 1.52587890625e-05)
                            {
                                _4731 = 0.0;
                            }
                            else
                            {
                                _4731 = _4635.z;
                            }
                            if (abs(_4637.x) <= 1.52587890625e-05)
                            {
                                _4740 = 0.0;
                            }
                            else
                            {
                                _4740 = _4637.x;
                            }
                            uint _4721 = (11892u >> (((floatBitsToUint(_4740) >> 29u) & 4u) | ((((floatBitsToUint(_4731) >> 30u) & 2u) | ((floatBitsToUint(_4722) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_4721 != 0u)
                            {
                                highp vec2 _4757 = (_4635.xy - (_4635.zw * 2.0)) + _4637;
                                highp vec2 _4758 = _4635.xy - _4635.zw;
                                highp float _4759 = _4757.x;
                                if (abs(_4759) < 1.52587890625e-05)
                                {
                                    highp float _4791 = _4758.x;
                                    if (abs(_4791) < 1.52587890625e-05)
                                    {
                                        _4749 = 0.0;
                                    }
                                    else
                                    {
                                        _4749 = (_4635.x * 0.5) / _4791;
                                    }
                                    _4750 = _4749;
                                }
                                else
                                {
                                    highp float _4763 = _4758.x;
                                    highp float _4766 = _4759 * _4635.x;
                                    highp float _4767 = (_4763 * _4763) - _4766;
                                    if (_4767 <= (max(_4763 * _4763, abs(_4766)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _4819 = 0.0;
                                    }
                                    else
                                    {
                                        _4819 = sqrt(_4767);
                                    }
                                    if (_4763 >= 0.0)
                                    {
                                        highp float _4781 = _4763 + _4819;
                                        if (abs(_4781) < 1.52587890625e-05)
                                        {
                                            _4749 = 0.0;
                                        }
                                        else
                                        {
                                            _4749 = _4635.x / _4781;
                                        }
                                        _4750 = _4781 / _4759;
                                    }
                                    else
                                    {
                                        highp float _4771 = _4763 - _4819;
                                        if (abs(_4771) < 1.52587890625e-05)
                                        {
                                            _4749 = 0.0;
                                        }
                                        else
                                        {
                                            _4749 = _4635.x / _4771;
                                        }
                                        highp float _4779 = _4749;
                                        _4749 = _4771 / _4759;
                                        _4750 = _4779;
                                    }
                                }
                                highp float _4802 = _4757.y;
                                highp float _4806 = _4758.y * 2.0;
                                highp vec2 _4655 = vec2((((_4802 * _4749) - _4806) * _4749) + _4635.y, (((_4802 * _4750) - _4806) * _4750) + _4635.y) * _3447;
                                if ((_4721 & 1u) != 0u)
                                {
                                    highp float _4659 = _4655.x;
                                    _4038 -= clamp(_4659 + 0.5, 0.0, 1.0);
                                    _4039 = max(_4039, clamp(1.0 - (abs(_4659) * 2.0), 0.0, 1.0));
                                }
                                if (_4721 > 1u)
                                {
                                    highp float _4673 = _4655.y;
                                    _4038 += clamp(_4673 + 0.5, 0.0, 1.0);
                                    _4039 = max(_4039, clamp(1.0 - (abs(_4673) * 2.0), 0.0, 1.0));
                                }
                            }
                            _4616 = true;
                            break;
                        } while(false);
                        if (!_4616)
                        {
                            _4152_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_4152_ladder_break)
                    {
                        break;
                    }
                    _4036++;
                    continue;
                }
                _4035++;
                continue;
            }
            highp float _4205 = ((_4033 * _4034) + (_4038 * _4039)) / max(_4034 + _4039, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _4833 = 1.0 - abs((fract(_4205 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _4833 = abs(_4205);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _4850 = 1.0 - abs((fract(_4033 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _4850 = abs(_4033);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _4867 = 1.0 - abs((fract(_4038 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _4867 = abs(_4038);
                break;
            } while(false);
            highp float _4886 = clamp(max(_4833, min(_4850, _4867)), 0.0, 1.0);
            highp float _4889 = abs(0.0);
            if (_4889 <= 9.9999999747524270787835121154785e-07)
            {
                _4883 = _4886;
            }
            else
            {
                _4883 = pow(_4886, 1.0);
            }
            highp float _3457 = clamp((_4883 * _3939.w) * _3968.w, 0.0, 1.0);
            if (_3457 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            highp float _4898 = _3939.x;
            if (_4898 <= 0.040449999272823333740234375)
            {
                _4905 = _4898 * 0.077399380505084991455078125;
            }
            else
            {
                _4905 = pow((_4898 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _4900 = _3939.y;
            if (_4900 <= 0.040449999272823333740234375)
            {
                _4917 = _4900 * 0.077399380505084991455078125;
            }
            else
            {
                _4917 = pow((_4900 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _4902 = _3939.z;
            if (_4902 <= 0.040449999272823333740234375)
            {
                _4929 = _4902 * 0.077399380505084991455078125;
            }
            else
            {
                _4929 = pow((_4902 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _4943 = _3968.x;
            if (_4943 <= 0.040449999272823333740234375)
            {
                _4950 = _4943 * 0.077399380505084991455078125;
            }
            else
            {
                _4950 = pow((_4943 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _4945 = _3968.y;
            if (_4945 <= 0.040449999272823333740234375)
            {
                _4962 = _4945 * 0.077399380505084991455078125;
            }
            else
            {
                _4962 = pow((_4945 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _4947 = _3968.z;
            if (_4947 <= 0.040449999272823333740234375)
            {
                _4974 = _4947 * 0.077399380505084991455078125;
            }
            else
            {
                _4974 = pow((_4947 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp vec4 _3467 = _3350;
            highp float _3469 = 1.0 - _3457;
            highp vec3 _3471 = ((vec3(_4905, _4917, _4929) * vec3(_4950, _4962, _4974)) * _3457) + (_3467.xyz * _3469);
            highp vec4 _10469 = _3467;
            _10469.x = _3471.x;
            _10469.y = _3471.y;
            _10469.z = _3471.z;
            _10469.w = _3457 + (_10469.w * _3469);
            _3350 = _10469;
            break;
        } while(false);
        if (_3359_ladder_break)
        {
            break;
        }
        _3351++;
        continue;
    }
    highp vec2 _1648 = scene_pos - _1644;
    highp vec4 _4991 = vec4(0.0);
    int _4992 = 0;
    bool _4993;
    bool _4994;
    bool _4995;
    highp float _5214;
    highp float _5215;
    highp float _5258;
    highp float _5259;
    highp float _5309;
    highp float _5310;
    highp float _5353;
    highp float _5354;
    int _5677;
    bool _5678;
    bool _5970;
    highp float _6076;
    highp float _6085;
    highp float _6094;
    highp float _6103;
    highp float _6104;
    highp float _6173;
    bool _6257;
    highp float _6363;
    highp float _6372;
    highp float _6381;
    highp float _6390;
    highp float _6391;
    highp float _6460;
    highp float _6474;
    highp float _6491;
    highp float _6508;
    highp float _6524;
    highp float _6546;
    highp float _6558;
    highp float _6570;
    highp float _6591;
    highp float _6603;
    highp float _6615;
    for (;;)
    {
        bool _5000_ladder_break = false;
        do
        {
            if (!(_4992 < pc.glyph_count))
            {
                _5000_ladder_break = true;
                break;
            }
            int _5177 = _4992 * 23;
            uvec4 _5186 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5177 - 1024 * (_5177 / 1024), _5177 / 1024), 0);
            uint _5187 = _5186.x;
            int _5191 = (_4992 * 23) + 1;
            uvec4 _5199 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5191 - 1024 * (_5191 / 1024), _5191 / 1024), 0);
            uint _5200 = _5199.x;
            uint _5208 = _5187 & 65535u;
            do
            {
                uint _5221 = (_5208 >> 10u) & 31u;
                uint _5222 = _5187 & 1023u;
                if ((_5208 >> 15u) == 0u)
                {
                    _5215 = 1.0;
                }
                else
                {
                    _5215 = -1.0;
                }
                if (_5221 == 0u)
                {
                    if (_5222 == 0u)
                    {
                        _5214 = 0.0;
                        break;
                    }
                    _5214 = (_5215 * 6.103515625e-05) * (float(_5222) * 0.0009765625);
                    break;
                }
                if (_5221 == 31u)
                {
                    _5214 = _5215 * 65504.0;
                    break;
                }
                _5214 = (_5215 * exp2(float(_5221) - 15.0)) * (1.0 + (float(_5222) * 0.0009765625));
                break;
            } while(false);
            uint _5210 = _5187 >> 16u;
            do
            {
                uint _5265 = (_5210 >> 10u) & 31u;
                uint _5266 = _5210 & 1023u;
                if ((_5210 >> 15u) == 0u)
                {
                    _5259 = 1.0;
                }
                else
                {
                    _5259 = -1.0;
                }
                if (_5265 == 0u)
                {
                    if (_5266 == 0u)
                    {
                        _5258 = 0.0;
                        break;
                    }
                    _5258 = (_5259 * 6.103515625e-05) * (float(_5266) * 0.0009765625);
                    break;
                }
                if (_5265 == 31u)
                {
                    _5258 = _5259 * 65504.0;
                    break;
                }
                _5258 = (_5259 * exp2(float(_5265) - 15.0)) * (1.0 + (float(_5266) * 0.0009765625));
                break;
            } while(false);
            uint _5303 = _5200 & 65535u;
            do
            {
                uint _5316 = (_5303 >> 10u) & 31u;
                uint _5317 = _5200 & 1023u;
                if ((_5303 >> 15u) == 0u)
                {
                    _5310 = 1.0;
                }
                else
                {
                    _5310 = -1.0;
                }
                if (_5316 == 0u)
                {
                    if (_5317 == 0u)
                    {
                        _5309 = 0.0;
                        break;
                    }
                    _5309 = (_5310 * 6.103515625e-05) * (float(_5317) * 0.0009765625);
                    break;
                }
                if (_5316 == 31u)
                {
                    _5309 = _5310 * 65504.0;
                    break;
                }
                _5309 = (_5310 * exp2(float(_5316) - 15.0)) * (1.0 + (float(_5317) * 0.0009765625));
                break;
            } while(false);
            uint _5305 = _5200 >> 16u;
            do
            {
                uint _5360 = (_5305 >> 10u) & 31u;
                uint _5361 = _5305 & 1023u;
                if ((_5305 >> 15u) == 0u)
                {
                    _5354 = 1.0;
                }
                else
                {
                    _5354 = -1.0;
                }
                if (_5360 == 0u)
                {
                    if (_5361 == 0u)
                    {
                        _5353 = 0.0;
                        break;
                    }
                    _5353 = (_5354 * 6.103515625e-05) * (float(_5361) * 0.0009765625);
                    break;
                }
                if (_5360 == 31u)
                {
                    _5353 = _5354 * 65504.0;
                    break;
                }
                _5353 = (_5354 * exp2(float(_5360) - 15.0)) * (1.0 + (float(_5361) * 0.0009765625));
                break;
            } while(false);
            highp vec4 _5205 = vec4(vec2(_5214, _5258), vec2(_5309, _5353));
            int _5399 = (_4992 * 23) + 2;
            int _5412 = (_4992 * 23) + 3;
            int _5425 = (_4992 * 23) + 4;
            int _5438 = (_4992 * 23) + 5;
            highp vec4 _5147 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5399 - 1024 * (_5399 / 1024), _5399 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5412 - 1024 * (_5412 / 1024), _5412 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5425 - 1024 * (_5425 / 1024), _5425 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5438 - 1024 * (_5438 / 1024), _5438 / 1024), 0).x));
            int _5451 = (_4992 * 23) + 6;
            int _5464 = (_4992 * 23) + 7;
            int _5477 = (_4992 * 23) + 8;
            int _5490 = (_4992 * 23) + 9;
            uvec2 _5157 = uvec2(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5477 - 1024 * (_5477 / 1024), _5477 / 1024), 0).x, texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5490 - 1024 * (_5490 / 1024), _5490 / 1024), 0).x);
            int _5503 = (_4992 * 23) + 10;
            int _5516 = (_4992 * 23) + 11;
            int _5529 = (_4992 * 23) + 12;
            int _5542 = (_4992 * 23) + 13;
            highp vec4 _5167 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5503 - 1024 * (_5503 / 1024), _5503 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5516 - 1024 * (_5516 / 1024), _5516 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5529 - 1024 * (_5529 / 1024), _5529 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5542 - 1024 * (_5542 / 1024), _5542 / 1024), 0).x));
            int _5555 = (_4992 * 23) + 14;
            uvec4 _5563 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5555 - 1024 * (_5555 / 1024), _5555 / 1024), 0);
            uint _5564 = _5563.x;
            highp vec4 _5580 = vec4(float(_5564 & 255u), float((_5564 >> 8u) & 255u), float((_5564 >> 16u) & 255u), float((_5564 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            int _5584 = (_4992 * 23) + 15;
            uvec4 _5592 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5584 - 1024 * (_5584 / 1024), _5584 / 1024), 0);
            uint _5593 = _5592.x;
            highp vec4 _5609 = vec4(float(_5593 & 255u), float((_5593 >> 8u) & 255u), float((_5593 >> 16u) & 255u), float((_5593 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_5147.x * _5147.w) - (_5147.y * _5147.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            highp float _5612 = _5147.x;
            highp float _5613 = _5147.w;
            highp float _5615 = _5147.y;
            highp float _5616 = _5147.z;
            highp float _5618 = (_5612 * _5613) - (_5615 * _5616);
            highp vec2 _5619 = _1648 - vec2(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5451 - 1024 * (_5451 / 1024), _5451 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_5464 - 1024 * (_5464 / 1024), _5464 / 1024), 0).x));
            highp float _5620 = _5619.x;
            highp float _5622 = _5619.y;
            highp vec2 _5631 = vec2(((_5613 * _5620) - (_5615 * _5622)) / _5618, (((-_5616) * _5620) + (_5612 * _5622)) / _5618);
            highp float _5634 = _5147.x;
            highp float _5635 = _5147.w;
            highp float _5637 = _5147.y;
            highp float _5638 = _5147.z;
            highp float _5640 = (_5634 * _5635) - (_5637 * _5638);
            highp float _5641 = _1630.x;
            highp float _5643 = _1630.y;
            highp float _5655 = _5147.x;
            highp float _5656 = _5147.w;
            highp float _5658 = _5147.y;
            highp float _5659 = _5147.z;
            highp float _5661 = (_5655 * _5656) - (_5658 * _5659);
            highp float _5662 = _1633.x;
            highp float _5664 = _1633.y;
            highp vec2 _5026 = abs(vec2(((_5635 * _5641) - (_5637 * _5643)) / _5640, (((-_5638) * _5641) + (_5634 * _5643)) / _5640)) + abs(vec2(((_5656 * _5662) - (_5658 * _5664)) / _5661, (((-_5659) * _5662) + (_5655 * _5664)) / _5661));
            highp vec2 _5028 = max(_5026 * 2.0, vec2(0.001000000047497451305389404296875));
            highp float _5029 = _5631.x;
            highp float _5032 = _5028.x;
            if (_5029 < (_5205.x - _5032))
            {
                _4993 = true;
            }
            else
            {
                _4993 = _5029 > (_5205.z + _5032);
            }
            if (_4993)
            {
                _4994 = true;
            }
            else
            {
                _4994 = _5631.y < (_5205.y - _5028.y);
            }
            if (_4994)
            {
                _4995 = true;
            }
            else
            {
                _4995 = _5631.y > (_5205.w + _5028.y);
            }
            if (_4995)
            {
                break;
            }
            uint _5063 = _5157.x;
            uint _5064 = _5157.y;
            int _5067 = int((_5064 >> 24u) & 255u);
            if (_5067 == 255)
            {
                break;
            }
            int _5073 = int(_5063 & 65535u);
            int _5075 = int(_5063 >> 16u);
            int _5079 = int((_5064 >> 16u) & 255u);
            int _5081 = int(_5064 & 65535u);
            highp float _5085 = 1.0 / max(_5026.x, 1.52587890625e-05);
            highp float _5088 = 1.0 / max(_5026.y, 1.52587890625e-05);
            highp float _5685 = _5167.y;
            highp float _5858 = (_5631.y * _5685) + _5167.w;
            highp float _5862 = max(abs(_5026.y * _5685) * 0.5, 9.9999997473787516355514526367188e-06);
            int _5865 = clamp(int(_5858 - _5862), 0, _5081);
            int _5869 = max(_5865, clamp(int(_5858 + _5862), 0, _5081));
            highp float _5691 = _5167.x;
            highp float _5880 = (_5631.x * _5691) + _5167.z;
            highp float _5884 = max(abs(_5026.x * _5691) * 0.5, 9.9999997473787516355514526367188e-06);
            int _5887 = clamp(int(_5880 - _5884), 0, _5079);
            int _5891 = max(_5887, clamp(int(_5880 + _5884), 0, _5079));
            highp float _5674 = 0.0;
            highp float _5675 = 0.0;
            bool _5697 = _5865 != _5869;
            int _5676 = _5865;
            for (;;)
            {
                if (!(_5676 <= _5869))
                {
                    break;
                }
                int _5904 = _5073 + _5676;
                ivec2 _5906 = ivec2(_5904, _5075);
                _5906.y = _5906.y + (_5904 >> 12);
                _5906.x = _5906.x & 4095;
                uvec4 _5712 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5906, _5067, 0).xyz, 0);
                int _5920 = _5073 + int(_5712.y);
                ivec2 _5922 = ivec2(_5920, _5075);
                _5922.y = _5922.y + (_5920 >> 12);
                _5922.x = _5922.x & 4095;
                int _5719 = int(_5712.x);
                _5677 = 0;
                for (;;)
                {
                    bool _5722_ladder_break = false;
                    do
                    {
                        if (!(_5677 < _5719))
                        {
                            _5722_ladder_break = true;
                            break;
                        }
                        int _5936 = _5922.x + _5677;
                        ivec2 _5938 = ivec2(_5936, _5922.y);
                        _5938.y = _5938.y + (_5936 >> 12);
                        _5938.x = _5938.x & 4095;
                        uvec4 _5734 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5938, _5067, 0).xyz, 0);
                        if (_5697)
                        {
                            _5678 = !(_5676 == max(int(_5734.x >> 12u), _5865));
                        }
                        else
                        {
                            _5678 = false;
                        }
                        if (_5678)
                        {
                            break;
                        }
                        ivec2 _5968 = ivec2(int(_5734.x & 4095u), int(_5734.y & 16383u));
                        do
                        {
                            highp vec4 _5977 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5968, _5067, 0).xyz, 0);
                            int _6046 = _5968.x + 1;
                            ivec2 _6048 = ivec2(_6046, _5968.y);
                            _6048.y = _6048.y + (_6046 >> 12);
                            _6048.x = _6048.x & 4095;
                            highp vec4 _5989 = vec4(_5977.xy, _5977.zw) - vec4(_5631, _5631);
                            highp vec2 _5991 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6048, _5067, 0).xyz, 0).xy - _5631;
                            if ((max(max(_5989.x, _5989.z), _5991.x) * _5085) < (-0.5))
                            {
                                _5970 = false;
                                break;
                            }
                            if (abs(_5989.y) <= 1.52587890625e-05)
                            {
                                _6076 = 0.0;
                            }
                            else
                            {
                                _6076 = _5989.y;
                            }
                            if (abs(_5989.w) <= 1.52587890625e-05)
                            {
                                _6085 = 0.0;
                            }
                            else
                            {
                                _6085 = _5989.w;
                            }
                            if (abs(_5991.y) <= 1.52587890625e-05)
                            {
                                _6094 = 0.0;
                            }
                            else
                            {
                                _6094 = _5991.y;
                            }
                            uint _6075 = (11892u >> (((floatBitsToUint(_6094) >> 29u) & 4u) | ((((floatBitsToUint(_6085) >> 30u) & 2u) | ((floatBitsToUint(_6076) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_6075 != 0u)
                            {
                                highp vec2 _6111 = (_5989.xy - (_5989.zw * 2.0)) + _5991;
                                highp vec2 _6112 = _5989.xy - _5989.zw;
                                highp float _6113 = _6111.y;
                                if (abs(_6113) < 1.52587890625e-05)
                                {
                                    highp float _6145 = _6112.y;
                                    if (abs(_6145) < 1.52587890625e-05)
                                    {
                                        _6103 = 0.0;
                                    }
                                    else
                                    {
                                        _6103 = (_5989.y * 0.5) / _6145;
                                    }
                                    _6104 = _6103;
                                }
                                else
                                {
                                    highp float _6117 = _6112.y;
                                    highp float _6120 = _6113 * _5989.y;
                                    highp float _6121 = (_6117 * _6117) - _6120;
                                    if (_6121 <= (max(_6117 * _6117, abs(_6120)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _6173 = 0.0;
                                    }
                                    else
                                    {
                                        _6173 = sqrt(_6121);
                                    }
                                    if (_6117 >= 0.0)
                                    {
                                        highp float _6135 = _6117 + _6173;
                                        if (abs(_6135) < 1.52587890625e-05)
                                        {
                                            _6103 = 0.0;
                                        }
                                        else
                                        {
                                            _6103 = _5989.y / _6135;
                                        }
                                        _6104 = _6135 / _6113;
                                    }
                                    else
                                    {
                                        highp float _6125 = _6117 - _6173;
                                        if (abs(_6125) < 1.52587890625e-05)
                                        {
                                            _6103 = 0.0;
                                        }
                                        else
                                        {
                                            _6103 = _5989.y / _6125;
                                        }
                                        highp float _6133 = _6103;
                                        _6103 = _6125 / _6113;
                                        _6104 = _6133;
                                    }
                                }
                                highp float _6156 = _6111.x;
                                highp float _6160 = _6112.x * 2.0;
                                highp vec2 _6009 = vec2((((_6156 * _6103) - _6160) * _6103) + _5989.x, (((_6156 * _6104) - _6160) * _6104) + _5989.x) * _5085;
                                if ((_6075 & 1u) != 0u)
                                {
                                    highp float _6013 = _6009.x;
                                    _5674 += clamp(_6013 + 0.5, 0.0, 1.0);
                                    _5675 = max(_5675, clamp(1.0 - (abs(_6013) * 2.0), 0.0, 1.0));
                                }
                                if (_6075 > 1u)
                                {
                                    highp float _6027 = _6009.y;
                                    _5674 -= clamp(_6027 + 0.5, 0.0, 1.0);
                                    _5675 = max(_5675, clamp(1.0 - (abs(_6027) * 2.0), 0.0, 1.0));
                                }
                            }
                            _5970 = true;
                            break;
                        } while(false);
                        if (!_5970)
                        {
                            _5722_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_5722_ladder_break)
                    {
                        break;
                    }
                    _5677++;
                    continue;
                }
                _5676++;
                continue;
            }
            highp float _5679 = 0.0;
            highp float _5680 = 0.0;
            bool _5766 = _5887 != _5891;
            _5676 = _5887;
            for (;;)
            {
                if (!(_5676 <= _5891))
                {
                    break;
                }
                int _6191 = _5073 + ((_5081 + 1) + _5676);
                ivec2 _6193 = ivec2(_6191, _5075);
                _6193.y = _6193.y + (_6191 >> 12);
                _6193.x = _6193.x & 4095;
                uvec4 _5783 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_6193, _5067, 0).xyz, 0);
                int _6207 = _5073 + int(_5783.y);
                ivec2 _6209 = ivec2(_6207, _5075);
                _6209.y = _6209.y + (_6207 >> 12);
                _6209.x = _6209.x & 4095;
                int _5790 = int(_5783.x);
                _5677 = 0;
                for (;;)
                {
                    bool _5793_ladder_break = false;
                    do
                    {
                        if (!(_5677 < _5790))
                        {
                            _5793_ladder_break = true;
                            break;
                        }
                        int _6223 = _6209.x + _5677;
                        ivec2 _6225 = ivec2(_6223, _6209.y);
                        _6225.y = _6225.y + (_6223 >> 12);
                        _6225.x = _6225.x & 4095;
                        uvec4 _5805 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_6225, _5067, 0).xyz, 0);
                        if (_5766)
                        {
                            _5678 = !(_5676 == max(int(_5805.x >> 12u), _5887));
                        }
                        else
                        {
                            _5678 = false;
                        }
                        if (_5678)
                        {
                            break;
                        }
                        ivec2 _6255 = ivec2(int(_5805.x & 4095u), int(_5805.y & 16383u));
                        do
                        {
                            highp vec4 _6264 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6255, _5067, 0).xyz, 0);
                            int _6333 = _6255.x + 1;
                            ivec2 _6335 = ivec2(_6333, _6255.y);
                            _6335.y = _6335.y + (_6333 >> 12);
                            _6335.x = _6335.x & 4095;
                            highp vec4 _6276 = vec4(_6264.xy, _6264.zw) - vec4(_5631, _5631);
                            highp vec2 _6278 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6335, _5067, 0).xyz, 0).xy - _5631;
                            if ((max(max(_6276.y, _6276.w), _6278.y) * _5088) < (-0.5))
                            {
                                _6257 = false;
                                break;
                            }
                            if (abs(_6276.x) <= 1.52587890625e-05)
                            {
                                _6363 = 0.0;
                            }
                            else
                            {
                                _6363 = _6276.x;
                            }
                            if (abs(_6276.z) <= 1.52587890625e-05)
                            {
                                _6372 = 0.0;
                            }
                            else
                            {
                                _6372 = _6276.z;
                            }
                            if (abs(_6278.x) <= 1.52587890625e-05)
                            {
                                _6381 = 0.0;
                            }
                            else
                            {
                                _6381 = _6278.x;
                            }
                            uint _6362 = (11892u >> (((floatBitsToUint(_6381) >> 29u) & 4u) | ((((floatBitsToUint(_6372) >> 30u) & 2u) | ((floatBitsToUint(_6363) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_6362 != 0u)
                            {
                                highp vec2 _6398 = (_6276.xy - (_6276.zw * 2.0)) + _6278;
                                highp vec2 _6399 = _6276.xy - _6276.zw;
                                highp float _6400 = _6398.x;
                                if (abs(_6400) < 1.52587890625e-05)
                                {
                                    highp float _6432 = _6399.x;
                                    if (abs(_6432) < 1.52587890625e-05)
                                    {
                                        _6390 = 0.0;
                                    }
                                    else
                                    {
                                        _6390 = (_6276.x * 0.5) / _6432;
                                    }
                                    _6391 = _6390;
                                }
                                else
                                {
                                    highp float _6404 = _6399.x;
                                    highp float _6407 = _6400 * _6276.x;
                                    highp float _6408 = (_6404 * _6404) - _6407;
                                    if (_6408 <= (max(_6404 * _6404, abs(_6407)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _6460 = 0.0;
                                    }
                                    else
                                    {
                                        _6460 = sqrt(_6408);
                                    }
                                    if (_6404 >= 0.0)
                                    {
                                        highp float _6422 = _6404 + _6460;
                                        if (abs(_6422) < 1.52587890625e-05)
                                        {
                                            _6390 = 0.0;
                                        }
                                        else
                                        {
                                            _6390 = _6276.x / _6422;
                                        }
                                        _6391 = _6422 / _6400;
                                    }
                                    else
                                    {
                                        highp float _6412 = _6404 - _6460;
                                        if (abs(_6412) < 1.52587890625e-05)
                                        {
                                            _6390 = 0.0;
                                        }
                                        else
                                        {
                                            _6390 = _6276.x / _6412;
                                        }
                                        highp float _6420 = _6390;
                                        _6390 = _6412 / _6400;
                                        _6391 = _6420;
                                    }
                                }
                                highp float _6443 = _6398.y;
                                highp float _6447 = _6399.y * 2.0;
                                highp vec2 _6296 = vec2((((_6443 * _6390) - _6447) * _6390) + _6276.y, (((_6443 * _6391) - _6447) * _6391) + _6276.y) * _5088;
                                if ((_6362 & 1u) != 0u)
                                {
                                    highp float _6300 = _6296.x;
                                    _5679 -= clamp(_6300 + 0.5, 0.0, 1.0);
                                    _5680 = max(_5680, clamp(1.0 - (abs(_6300) * 2.0), 0.0, 1.0));
                                }
                                if (_6362 > 1u)
                                {
                                    highp float _6314 = _6296.y;
                                    _5679 += clamp(_6314 + 0.5, 0.0, 1.0);
                                    _5680 = max(_5680, clamp(1.0 - (abs(_6314) * 2.0), 0.0, 1.0));
                                }
                            }
                            _6257 = true;
                            break;
                        } while(false);
                        if (!_6257)
                        {
                            _5793_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_5793_ladder_break)
                    {
                        break;
                    }
                    _5677++;
                    continue;
                }
                _5676++;
                continue;
            }
            highp float _5846 = ((_5674 * _5675) + (_5679 * _5680)) / max(_5675 + _5680, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _6474 = 1.0 - abs((fract(_5846 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _6474 = abs(_5846);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _6491 = 1.0 - abs((fract(_5674 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _6491 = abs(_5674);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _6508 = 1.0 - abs((fract(_5679 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _6508 = abs(_5679);
                break;
            } while(false);
            highp float _6527 = clamp(max(_6474, min(_6491, _6508)), 0.0, 1.0);
            highp float _6530 = abs(0.0);
            if (_6530 <= 9.9999999747524270787835121154785e-07)
            {
                _6524 = _6527;
            }
            else
            {
                _6524 = pow(_6527, 1.0);
            }
            highp float _5098 = clamp((_6524 * _5580.w) * _5609.w, 0.0, 1.0);
            if (_5098 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            highp float _6539 = _5580.x;
            if (_6539 <= 0.040449999272823333740234375)
            {
                _6546 = _6539 * 0.077399380505084991455078125;
            }
            else
            {
                _6546 = pow((_6539 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _6541 = _5580.y;
            if (_6541 <= 0.040449999272823333740234375)
            {
                _6558 = _6541 * 0.077399380505084991455078125;
            }
            else
            {
                _6558 = pow((_6541 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _6543 = _5580.z;
            if (_6543 <= 0.040449999272823333740234375)
            {
                _6570 = _6543 * 0.077399380505084991455078125;
            }
            else
            {
                _6570 = pow((_6543 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _6584 = _5609.x;
            if (_6584 <= 0.040449999272823333740234375)
            {
                _6591 = _6584 * 0.077399380505084991455078125;
            }
            else
            {
                _6591 = pow((_6584 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _6586 = _5609.y;
            if (_6586 <= 0.040449999272823333740234375)
            {
                _6603 = _6586 * 0.077399380505084991455078125;
            }
            else
            {
                _6603 = pow((_6586 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _6588 = _5609.z;
            if (_6588 <= 0.040449999272823333740234375)
            {
                _6615 = _6588 * 0.077399380505084991455078125;
            }
            else
            {
                _6615 = pow((_6588 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp vec4 _5108 = _4991;
            highp float _5110 = 1.0 - _5098;
            highp vec3 _5112 = ((vec3(_6546, _6558, _6570) * vec3(_6591, _6603, _6615)) * _5098) + (_5108.xyz * _5110);
            highp vec4 _10525 = _5108;
            _10525.x = _5112.x;
            _10525.y = _5112.y;
            _10525.z = _5112.z;
            _10525.w = _5098 + (_10525.w * _5110);
            _4991 = _10525;
            break;
        } while(false);
        if (_5000_ladder_break)
        {
            break;
        }
        _4992++;
        continue;
    }
    highp vec2 _1652 = vec2(0.0, _1640.y);
    highp vec2 _1653 = scene_pos + _1652;
    highp vec4 _6632 = vec4(0.0);
    int _6633 = 0;
    bool _6634;
    bool _6635;
    bool _6636;
    highp float _6855;
    highp float _6856;
    highp float _6899;
    highp float _6900;
    highp float _6950;
    highp float _6951;
    highp float _6994;
    highp float _6995;
    int _7318;
    bool _7319;
    bool _7611;
    highp float _7717;
    highp float _7726;
    highp float _7735;
    highp float _7744;
    highp float _7745;
    highp float _7814;
    bool _7898;
    highp float _8004;
    highp float _8013;
    highp float _8022;
    highp float _8031;
    highp float _8032;
    highp float _8101;
    highp float _8115;
    highp float _8132;
    highp float _8149;
    highp float _8165;
    highp float _8187;
    highp float _8199;
    highp float _8211;
    highp float _8232;
    highp float _8244;
    highp float _8256;
    for (;;)
    {
        bool _6641_ladder_break = false;
        do
        {
            if (!(_6633 < pc.glyph_count))
            {
                _6641_ladder_break = true;
                break;
            }
            int _6818 = _6633 * 23;
            uvec4 _6827 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_6818 - 1024 * (_6818 / 1024), _6818 / 1024), 0);
            uint _6828 = _6827.x;
            int _6832 = (_6633 * 23) + 1;
            uvec4 _6840 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_6832 - 1024 * (_6832 / 1024), _6832 / 1024), 0);
            uint _6841 = _6840.x;
            uint _6849 = _6828 & 65535u;
            do
            {
                uint _6862 = (_6849 >> 10u) & 31u;
                uint _6863 = _6828 & 1023u;
                if ((_6849 >> 15u) == 0u)
                {
                    _6856 = 1.0;
                }
                else
                {
                    _6856 = -1.0;
                }
                if (_6862 == 0u)
                {
                    if (_6863 == 0u)
                    {
                        _6855 = 0.0;
                        break;
                    }
                    _6855 = (_6856 * 6.103515625e-05) * (float(_6863) * 0.0009765625);
                    break;
                }
                if (_6862 == 31u)
                {
                    _6855 = _6856 * 65504.0;
                    break;
                }
                _6855 = (_6856 * exp2(float(_6862) - 15.0)) * (1.0 + (float(_6863) * 0.0009765625));
                break;
            } while(false);
            uint _6851 = _6828 >> 16u;
            do
            {
                uint _6906 = (_6851 >> 10u) & 31u;
                uint _6907 = _6851 & 1023u;
                if ((_6851 >> 15u) == 0u)
                {
                    _6900 = 1.0;
                }
                else
                {
                    _6900 = -1.0;
                }
                if (_6906 == 0u)
                {
                    if (_6907 == 0u)
                    {
                        _6899 = 0.0;
                        break;
                    }
                    _6899 = (_6900 * 6.103515625e-05) * (float(_6907) * 0.0009765625);
                    break;
                }
                if (_6906 == 31u)
                {
                    _6899 = _6900 * 65504.0;
                    break;
                }
                _6899 = (_6900 * exp2(float(_6906) - 15.0)) * (1.0 + (float(_6907) * 0.0009765625));
                break;
            } while(false);
            uint _6944 = _6841 & 65535u;
            do
            {
                uint _6957 = (_6944 >> 10u) & 31u;
                uint _6958 = _6841 & 1023u;
                if ((_6944 >> 15u) == 0u)
                {
                    _6951 = 1.0;
                }
                else
                {
                    _6951 = -1.0;
                }
                if (_6957 == 0u)
                {
                    if (_6958 == 0u)
                    {
                        _6950 = 0.0;
                        break;
                    }
                    _6950 = (_6951 * 6.103515625e-05) * (float(_6958) * 0.0009765625);
                    break;
                }
                if (_6957 == 31u)
                {
                    _6950 = _6951 * 65504.0;
                    break;
                }
                _6950 = (_6951 * exp2(float(_6957) - 15.0)) * (1.0 + (float(_6958) * 0.0009765625));
                break;
            } while(false);
            uint _6946 = _6841 >> 16u;
            do
            {
                uint _7001 = (_6946 >> 10u) & 31u;
                uint _7002 = _6946 & 1023u;
                if ((_6946 >> 15u) == 0u)
                {
                    _6995 = 1.0;
                }
                else
                {
                    _6995 = -1.0;
                }
                if (_7001 == 0u)
                {
                    if (_7002 == 0u)
                    {
                        _6994 = 0.0;
                        break;
                    }
                    _6994 = (_6995 * 6.103515625e-05) * (float(_7002) * 0.0009765625);
                    break;
                }
                if (_7001 == 31u)
                {
                    _6994 = _6995 * 65504.0;
                    break;
                }
                _6994 = (_6995 * exp2(float(_7001) - 15.0)) * (1.0 + (float(_7002) * 0.0009765625));
                break;
            } while(false);
            highp vec4 _6846 = vec4(vec2(_6855, _6899), vec2(_6950, _6994));
            int _7040 = (_6633 * 23) + 2;
            int _7053 = (_6633 * 23) + 3;
            int _7066 = (_6633 * 23) + 4;
            int _7079 = (_6633 * 23) + 5;
            highp vec4 _6788 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7040 - 1024 * (_7040 / 1024), _7040 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7053 - 1024 * (_7053 / 1024), _7053 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7066 - 1024 * (_7066 / 1024), _7066 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7079 - 1024 * (_7079 / 1024), _7079 / 1024), 0).x));
            int _7092 = (_6633 * 23) + 6;
            int _7105 = (_6633 * 23) + 7;
            int _7118 = (_6633 * 23) + 8;
            int _7131 = (_6633 * 23) + 9;
            uvec2 _6798 = uvec2(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7118 - 1024 * (_7118 / 1024), _7118 / 1024), 0).x, texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7131 - 1024 * (_7131 / 1024), _7131 / 1024), 0).x);
            int _7144 = (_6633 * 23) + 10;
            int _7157 = (_6633 * 23) + 11;
            int _7170 = (_6633 * 23) + 12;
            int _7183 = (_6633 * 23) + 13;
            highp vec4 _6808 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7144 - 1024 * (_7144 / 1024), _7144 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7157 - 1024 * (_7157 / 1024), _7157 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7170 - 1024 * (_7170 / 1024), _7170 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7183 - 1024 * (_7183 / 1024), _7183 / 1024), 0).x));
            int _7196 = (_6633 * 23) + 14;
            uvec4 _7204 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7196 - 1024 * (_7196 / 1024), _7196 / 1024), 0);
            uint _7205 = _7204.x;
            highp vec4 _7221 = vec4(float(_7205 & 255u), float((_7205 >> 8u) & 255u), float((_7205 >> 16u) & 255u), float((_7205 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            int _7225 = (_6633 * 23) + 15;
            uvec4 _7233 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7225 - 1024 * (_7225 / 1024), _7225 / 1024), 0);
            uint _7234 = _7233.x;
            highp vec4 _7250 = vec4(float(_7234 & 255u), float((_7234 >> 8u) & 255u), float((_7234 >> 16u) & 255u), float((_7234 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_6788.x * _6788.w) - (_6788.y * _6788.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            highp float _7253 = _6788.x;
            highp float _7254 = _6788.w;
            highp float _7256 = _6788.y;
            highp float _7257 = _6788.z;
            highp float _7259 = (_7253 * _7254) - (_7256 * _7257);
            highp vec2 _7260 = _1653 - vec2(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7092 - 1024 * (_7092 / 1024), _7092 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_7105 - 1024 * (_7105 / 1024), _7105 / 1024), 0).x));
            highp float _7261 = _7260.x;
            highp float _7263 = _7260.y;
            highp vec2 _7272 = vec2(((_7254 * _7261) - (_7256 * _7263)) / _7259, (((-_7257) * _7261) + (_7253 * _7263)) / _7259);
            highp float _7275 = _6788.x;
            highp float _7276 = _6788.w;
            highp float _7278 = _6788.y;
            highp float _7279 = _6788.z;
            highp float _7281 = (_7275 * _7276) - (_7278 * _7279);
            highp float _7282 = _1630.x;
            highp float _7284 = _1630.y;
            highp float _7296 = _6788.x;
            highp float _7297 = _6788.w;
            highp float _7299 = _6788.y;
            highp float _7300 = _6788.z;
            highp float _7302 = (_7296 * _7297) - (_7299 * _7300);
            highp float _7303 = _1633.x;
            highp float _7305 = _1633.y;
            highp vec2 _6667 = abs(vec2(((_7276 * _7282) - (_7278 * _7284)) / _7281, (((-_7279) * _7282) + (_7275 * _7284)) / _7281)) + abs(vec2(((_7297 * _7303) - (_7299 * _7305)) / _7302, (((-_7300) * _7303) + (_7296 * _7305)) / _7302));
            highp vec2 _6669 = max(_6667 * 2.0, vec2(0.001000000047497451305389404296875));
            highp float _6670 = _7272.x;
            highp float _6673 = _6669.x;
            if (_6670 < (_6846.x - _6673))
            {
                _6634 = true;
            }
            else
            {
                _6634 = _6670 > (_6846.z + _6673);
            }
            if (_6634)
            {
                _6635 = true;
            }
            else
            {
                _6635 = _7272.y < (_6846.y - _6669.y);
            }
            if (_6635)
            {
                _6636 = true;
            }
            else
            {
                _6636 = _7272.y > (_6846.w + _6669.y);
            }
            if (_6636)
            {
                break;
            }
            uint _6704 = _6798.x;
            uint _6705 = _6798.y;
            int _6708 = int((_6705 >> 24u) & 255u);
            if (_6708 == 255)
            {
                break;
            }
            int _6714 = int(_6704 & 65535u);
            int _6716 = int(_6704 >> 16u);
            int _6720 = int((_6705 >> 16u) & 255u);
            int _6722 = int(_6705 & 65535u);
            highp float _6726 = 1.0 / max(_6667.x, 1.52587890625e-05);
            highp float _6729 = 1.0 / max(_6667.y, 1.52587890625e-05);
            highp float _7326 = _6808.y;
            highp float _7499 = (_7272.y * _7326) + _6808.w;
            highp float _7503 = max(abs(_6667.y * _7326) * 0.5, 9.9999997473787516355514526367188e-06);
            int _7506 = clamp(int(_7499 - _7503), 0, _6722);
            int _7510 = max(_7506, clamp(int(_7499 + _7503), 0, _6722));
            highp float _7332 = _6808.x;
            highp float _7521 = (_7272.x * _7332) + _6808.z;
            highp float _7525 = max(abs(_6667.x * _7332) * 0.5, 9.9999997473787516355514526367188e-06);
            int _7528 = clamp(int(_7521 - _7525), 0, _6720);
            int _7532 = max(_7528, clamp(int(_7521 + _7525), 0, _6720));
            highp float _7315 = 0.0;
            highp float _7316 = 0.0;
            bool _7338 = _7506 != _7510;
            int _7317 = _7506;
            for (;;)
            {
                if (!(_7317 <= _7510))
                {
                    break;
                }
                int _7545 = _6714 + _7317;
                ivec2 _7547 = ivec2(_7545, _6716);
                _7547.y = _7547.y + (_7545 >> 12);
                _7547.x = _7547.x & 4095;
                uvec4 _7353 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7547, _6708, 0).xyz, 0);
                int _7561 = _6714 + int(_7353.y);
                ivec2 _7563 = ivec2(_7561, _6716);
                _7563.y = _7563.y + (_7561 >> 12);
                _7563.x = _7563.x & 4095;
                int _7360 = int(_7353.x);
                _7318 = 0;
                for (;;)
                {
                    bool _7363_ladder_break = false;
                    do
                    {
                        if (!(_7318 < _7360))
                        {
                            _7363_ladder_break = true;
                            break;
                        }
                        int _7577 = _7563.x + _7318;
                        ivec2 _7579 = ivec2(_7577, _7563.y);
                        _7579.y = _7579.y + (_7577 >> 12);
                        _7579.x = _7579.x & 4095;
                        uvec4 _7375 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7579, _6708, 0).xyz, 0);
                        if (_7338)
                        {
                            _7319 = !(_7317 == max(int(_7375.x >> 12u), _7506));
                        }
                        else
                        {
                            _7319 = false;
                        }
                        if (_7319)
                        {
                            break;
                        }
                        ivec2 _7609 = ivec2(int(_7375.x & 4095u), int(_7375.y & 16383u));
                        do
                        {
                            highp vec4 _7618 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7609, _6708, 0).xyz, 0);
                            int _7687 = _7609.x + 1;
                            ivec2 _7689 = ivec2(_7687, _7609.y);
                            _7689.y = _7689.y + (_7687 >> 12);
                            _7689.x = _7689.x & 4095;
                            highp vec4 _7630 = vec4(_7618.xy, _7618.zw) - vec4(_7272, _7272);
                            highp vec2 _7632 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7689, _6708, 0).xyz, 0).xy - _7272;
                            if ((max(max(_7630.x, _7630.z), _7632.x) * _6726) < (-0.5))
                            {
                                _7611 = false;
                                break;
                            }
                            if (abs(_7630.y) <= 1.52587890625e-05)
                            {
                                _7717 = 0.0;
                            }
                            else
                            {
                                _7717 = _7630.y;
                            }
                            if (abs(_7630.w) <= 1.52587890625e-05)
                            {
                                _7726 = 0.0;
                            }
                            else
                            {
                                _7726 = _7630.w;
                            }
                            if (abs(_7632.y) <= 1.52587890625e-05)
                            {
                                _7735 = 0.0;
                            }
                            else
                            {
                                _7735 = _7632.y;
                            }
                            uint _7716 = (11892u >> (((floatBitsToUint(_7735) >> 29u) & 4u) | ((((floatBitsToUint(_7726) >> 30u) & 2u) | ((floatBitsToUint(_7717) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_7716 != 0u)
                            {
                                highp vec2 _7752 = (_7630.xy - (_7630.zw * 2.0)) + _7632;
                                highp vec2 _7753 = _7630.xy - _7630.zw;
                                highp float _7754 = _7752.y;
                                if (abs(_7754) < 1.52587890625e-05)
                                {
                                    highp float _7786 = _7753.y;
                                    if (abs(_7786) < 1.52587890625e-05)
                                    {
                                        _7744 = 0.0;
                                    }
                                    else
                                    {
                                        _7744 = (_7630.y * 0.5) / _7786;
                                    }
                                    _7745 = _7744;
                                }
                                else
                                {
                                    highp float _7758 = _7753.y;
                                    highp float _7761 = _7754 * _7630.y;
                                    highp float _7762 = (_7758 * _7758) - _7761;
                                    if (_7762 <= (max(_7758 * _7758, abs(_7761)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _7814 = 0.0;
                                    }
                                    else
                                    {
                                        _7814 = sqrt(_7762);
                                    }
                                    if (_7758 >= 0.0)
                                    {
                                        highp float _7776 = _7758 + _7814;
                                        if (abs(_7776) < 1.52587890625e-05)
                                        {
                                            _7744 = 0.0;
                                        }
                                        else
                                        {
                                            _7744 = _7630.y / _7776;
                                        }
                                        _7745 = _7776 / _7754;
                                    }
                                    else
                                    {
                                        highp float _7766 = _7758 - _7814;
                                        if (abs(_7766) < 1.52587890625e-05)
                                        {
                                            _7744 = 0.0;
                                        }
                                        else
                                        {
                                            _7744 = _7630.y / _7766;
                                        }
                                        highp float _7774 = _7744;
                                        _7744 = _7766 / _7754;
                                        _7745 = _7774;
                                    }
                                }
                                highp float _7797 = _7752.x;
                                highp float _7801 = _7753.x * 2.0;
                                highp vec2 _7650 = vec2((((_7797 * _7744) - _7801) * _7744) + _7630.x, (((_7797 * _7745) - _7801) * _7745) + _7630.x) * _6726;
                                if ((_7716 & 1u) != 0u)
                                {
                                    highp float _7654 = _7650.x;
                                    _7315 += clamp(_7654 + 0.5, 0.0, 1.0);
                                    _7316 = max(_7316, clamp(1.0 - (abs(_7654) * 2.0), 0.0, 1.0));
                                }
                                if (_7716 > 1u)
                                {
                                    highp float _7668 = _7650.y;
                                    _7315 -= clamp(_7668 + 0.5, 0.0, 1.0);
                                    _7316 = max(_7316, clamp(1.0 - (abs(_7668) * 2.0), 0.0, 1.0));
                                }
                            }
                            _7611 = true;
                            break;
                        } while(false);
                        if (!_7611)
                        {
                            _7363_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_7363_ladder_break)
                    {
                        break;
                    }
                    _7318++;
                    continue;
                }
                _7317++;
                continue;
            }
            highp float _7320 = 0.0;
            highp float _7321 = 0.0;
            bool _7407 = _7528 != _7532;
            _7317 = _7528;
            for (;;)
            {
                if (!(_7317 <= _7532))
                {
                    break;
                }
                int _7832 = _6714 + ((_6722 + 1) + _7317);
                ivec2 _7834 = ivec2(_7832, _6716);
                _7834.y = _7834.y + (_7832 >> 12);
                _7834.x = _7834.x & 4095;
                uvec4 _7424 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7834, _6708, 0).xyz, 0);
                int _7848 = _6714 + int(_7424.y);
                ivec2 _7850 = ivec2(_7848, _6716);
                _7850.y = _7850.y + (_7848 >> 12);
                _7850.x = _7850.x & 4095;
                int _7431 = int(_7424.x);
                _7318 = 0;
                for (;;)
                {
                    bool _7434_ladder_break = false;
                    do
                    {
                        if (!(_7318 < _7431))
                        {
                            _7434_ladder_break = true;
                            break;
                        }
                        int _7864 = _7850.x + _7318;
                        ivec2 _7866 = ivec2(_7864, _7850.y);
                        _7866.y = _7866.y + (_7864 >> 12);
                        _7866.x = _7866.x & 4095;
                        uvec4 _7446 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7866, _6708, 0).xyz, 0);
                        if (_7407)
                        {
                            _7319 = !(_7317 == max(int(_7446.x >> 12u), _7528));
                        }
                        else
                        {
                            _7319 = false;
                        }
                        if (_7319)
                        {
                            break;
                        }
                        ivec2 _7896 = ivec2(int(_7446.x & 4095u), int(_7446.y & 16383u));
                        do
                        {
                            highp vec4 _7905 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7896, _6708, 0).xyz, 0);
                            int _7974 = _7896.x + 1;
                            ivec2 _7976 = ivec2(_7974, _7896.y);
                            _7976.y = _7976.y + (_7974 >> 12);
                            _7976.x = _7976.x & 4095;
                            highp vec4 _7917 = vec4(_7905.xy, _7905.zw) - vec4(_7272, _7272);
                            highp vec2 _7919 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7976, _6708, 0).xyz, 0).xy - _7272;
                            if ((max(max(_7917.y, _7917.w), _7919.y) * _6729) < (-0.5))
                            {
                                _7898 = false;
                                break;
                            }
                            if (abs(_7917.x) <= 1.52587890625e-05)
                            {
                                _8004 = 0.0;
                            }
                            else
                            {
                                _8004 = _7917.x;
                            }
                            if (abs(_7917.z) <= 1.52587890625e-05)
                            {
                                _8013 = 0.0;
                            }
                            else
                            {
                                _8013 = _7917.z;
                            }
                            if (abs(_7919.x) <= 1.52587890625e-05)
                            {
                                _8022 = 0.0;
                            }
                            else
                            {
                                _8022 = _7919.x;
                            }
                            uint _8003 = (11892u >> (((floatBitsToUint(_8022) >> 29u) & 4u) | ((((floatBitsToUint(_8013) >> 30u) & 2u) | ((floatBitsToUint(_8004) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_8003 != 0u)
                            {
                                highp vec2 _8039 = (_7917.xy - (_7917.zw * 2.0)) + _7919;
                                highp vec2 _8040 = _7917.xy - _7917.zw;
                                highp float _8041 = _8039.x;
                                if (abs(_8041) < 1.52587890625e-05)
                                {
                                    highp float _8073 = _8040.x;
                                    if (abs(_8073) < 1.52587890625e-05)
                                    {
                                        _8031 = 0.0;
                                    }
                                    else
                                    {
                                        _8031 = (_7917.x * 0.5) / _8073;
                                    }
                                    _8032 = _8031;
                                }
                                else
                                {
                                    highp float _8045 = _8040.x;
                                    highp float _8048 = _8041 * _7917.x;
                                    highp float _8049 = (_8045 * _8045) - _8048;
                                    if (_8049 <= (max(_8045 * _8045, abs(_8048)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _8101 = 0.0;
                                    }
                                    else
                                    {
                                        _8101 = sqrt(_8049);
                                    }
                                    if (_8045 >= 0.0)
                                    {
                                        highp float _8063 = _8045 + _8101;
                                        if (abs(_8063) < 1.52587890625e-05)
                                        {
                                            _8031 = 0.0;
                                        }
                                        else
                                        {
                                            _8031 = _7917.x / _8063;
                                        }
                                        _8032 = _8063 / _8041;
                                    }
                                    else
                                    {
                                        highp float _8053 = _8045 - _8101;
                                        if (abs(_8053) < 1.52587890625e-05)
                                        {
                                            _8031 = 0.0;
                                        }
                                        else
                                        {
                                            _8031 = _7917.x / _8053;
                                        }
                                        highp float _8061 = _8031;
                                        _8031 = _8053 / _8041;
                                        _8032 = _8061;
                                    }
                                }
                                highp float _8084 = _8039.y;
                                highp float _8088 = _8040.y * 2.0;
                                highp vec2 _7937 = vec2((((_8084 * _8031) - _8088) * _8031) + _7917.y, (((_8084 * _8032) - _8088) * _8032) + _7917.y) * _6729;
                                if ((_8003 & 1u) != 0u)
                                {
                                    highp float _7941 = _7937.x;
                                    _7320 -= clamp(_7941 + 0.5, 0.0, 1.0);
                                    _7321 = max(_7321, clamp(1.0 - (abs(_7941) * 2.0), 0.0, 1.0));
                                }
                                if (_8003 > 1u)
                                {
                                    highp float _7955 = _7937.y;
                                    _7320 += clamp(_7955 + 0.5, 0.0, 1.0);
                                    _7321 = max(_7321, clamp(1.0 - (abs(_7955) * 2.0), 0.0, 1.0));
                                }
                            }
                            _7898 = true;
                            break;
                        } while(false);
                        if (!_7898)
                        {
                            _7434_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_7434_ladder_break)
                    {
                        break;
                    }
                    _7318++;
                    continue;
                }
                _7317++;
                continue;
            }
            highp float _7487 = ((_7315 * _7316) + (_7320 * _7321)) / max(_7316 + _7321, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _8115 = 1.0 - abs((fract(_7487 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _8115 = abs(_7487);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _8132 = 1.0 - abs((fract(_7315 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _8132 = abs(_7315);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _8149 = 1.0 - abs((fract(_7320 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _8149 = abs(_7320);
                break;
            } while(false);
            highp float _8168 = clamp(max(_8115, min(_8132, _8149)), 0.0, 1.0);
            highp float _8171 = abs(0.0);
            if (_8171 <= 9.9999999747524270787835121154785e-07)
            {
                _8165 = _8168;
            }
            else
            {
                _8165 = pow(_8168, 1.0);
            }
            highp float _6739 = clamp((_8165 * _7221.w) * _7250.w, 0.0, 1.0);
            if (_6739 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            highp float _8180 = _7221.x;
            if (_8180 <= 0.040449999272823333740234375)
            {
                _8187 = _8180 * 0.077399380505084991455078125;
            }
            else
            {
                _8187 = pow((_8180 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _8182 = _7221.y;
            if (_8182 <= 0.040449999272823333740234375)
            {
                _8199 = _8182 * 0.077399380505084991455078125;
            }
            else
            {
                _8199 = pow((_8182 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _8184 = _7221.z;
            if (_8184 <= 0.040449999272823333740234375)
            {
                _8211 = _8184 * 0.077399380505084991455078125;
            }
            else
            {
                _8211 = pow((_8184 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _8225 = _7250.x;
            if (_8225 <= 0.040449999272823333740234375)
            {
                _8232 = _8225 * 0.077399380505084991455078125;
            }
            else
            {
                _8232 = pow((_8225 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _8227 = _7250.y;
            if (_8227 <= 0.040449999272823333740234375)
            {
                _8244 = _8227 * 0.077399380505084991455078125;
            }
            else
            {
                _8244 = pow((_8227 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _8229 = _7250.z;
            if (_8229 <= 0.040449999272823333740234375)
            {
                _8256 = _8229 * 0.077399380505084991455078125;
            }
            else
            {
                _8256 = pow((_8229 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp vec4 _6749 = _6632;
            highp float _6751 = 1.0 - _6739;
            highp vec3 _6753 = ((vec3(_8187, _8199, _8211) * vec3(_8232, _8244, _8256)) * _6739) + (_6749.xyz * _6751);
            highp vec4 _10581 = _6749;
            _10581.x = _6753.x;
            _10581.y = _6753.y;
            _10581.z = _6753.z;
            _10581.w = _6739 + (_10581.w * _6751);
            _6632 = _10581;
            break;
        } while(false);
        if (_6641_ladder_break)
        {
            break;
        }
        _6633++;
        continue;
    }
    highp vec2 _1656 = scene_pos - _1652;
    highp vec4 _8273 = vec4(0.0);
    int _8274 = 0;
    bool _8275;
    bool _8276;
    bool _8277;
    highp float _8496;
    highp float _8497;
    highp float _8540;
    highp float _8541;
    highp float _8591;
    highp float _8592;
    highp float _8635;
    highp float _8636;
    int _8959;
    bool _8960;
    bool _9252;
    highp float _9358;
    highp float _9367;
    highp float _9376;
    highp float _9385;
    highp float _9386;
    highp float _9455;
    bool _9539;
    highp float _9645;
    highp float _9654;
    highp float _9663;
    highp float _9672;
    highp float _9673;
    highp float _9742;
    highp float _9756;
    highp float _9773;
    highp float _9790;
    highp float _9806;
    highp float _9828;
    highp float _9840;
    highp float _9852;
    highp float _9873;
    highp float _9885;
    highp float _9897;
    for (;;)
    {
        bool _8282_ladder_break = false;
        do
        {
            if (!(_8274 < pc.glyph_count))
            {
                _8282_ladder_break = true;
                break;
            }
            int _8459 = _8274 * 23;
            uvec4 _8468 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8459 - 1024 * (_8459 / 1024), _8459 / 1024), 0);
            uint _8469 = _8468.x;
            int _8473 = (_8274 * 23) + 1;
            uvec4 _8481 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8473 - 1024 * (_8473 / 1024), _8473 / 1024), 0);
            uint _8482 = _8481.x;
            uint _8490 = _8469 & 65535u;
            do
            {
                uint _8503 = (_8490 >> 10u) & 31u;
                uint _8504 = _8469 & 1023u;
                if ((_8490 >> 15u) == 0u)
                {
                    _8497 = 1.0;
                }
                else
                {
                    _8497 = -1.0;
                }
                if (_8503 == 0u)
                {
                    if (_8504 == 0u)
                    {
                        _8496 = 0.0;
                        break;
                    }
                    _8496 = (_8497 * 6.103515625e-05) * (float(_8504) * 0.0009765625);
                    break;
                }
                if (_8503 == 31u)
                {
                    _8496 = _8497 * 65504.0;
                    break;
                }
                _8496 = (_8497 * exp2(float(_8503) - 15.0)) * (1.0 + (float(_8504) * 0.0009765625));
                break;
            } while(false);
            uint _8492 = _8469 >> 16u;
            do
            {
                uint _8547 = (_8492 >> 10u) & 31u;
                uint _8548 = _8492 & 1023u;
                if ((_8492 >> 15u) == 0u)
                {
                    _8541 = 1.0;
                }
                else
                {
                    _8541 = -1.0;
                }
                if (_8547 == 0u)
                {
                    if (_8548 == 0u)
                    {
                        _8540 = 0.0;
                        break;
                    }
                    _8540 = (_8541 * 6.103515625e-05) * (float(_8548) * 0.0009765625);
                    break;
                }
                if (_8547 == 31u)
                {
                    _8540 = _8541 * 65504.0;
                    break;
                }
                _8540 = (_8541 * exp2(float(_8547) - 15.0)) * (1.0 + (float(_8548) * 0.0009765625));
                break;
            } while(false);
            uint _8585 = _8482 & 65535u;
            do
            {
                uint _8598 = (_8585 >> 10u) & 31u;
                uint _8599 = _8482 & 1023u;
                if ((_8585 >> 15u) == 0u)
                {
                    _8592 = 1.0;
                }
                else
                {
                    _8592 = -1.0;
                }
                if (_8598 == 0u)
                {
                    if (_8599 == 0u)
                    {
                        _8591 = 0.0;
                        break;
                    }
                    _8591 = (_8592 * 6.103515625e-05) * (float(_8599) * 0.0009765625);
                    break;
                }
                if (_8598 == 31u)
                {
                    _8591 = _8592 * 65504.0;
                    break;
                }
                _8591 = (_8592 * exp2(float(_8598) - 15.0)) * (1.0 + (float(_8599) * 0.0009765625));
                break;
            } while(false);
            uint _8587 = _8482 >> 16u;
            do
            {
                uint _8642 = (_8587 >> 10u) & 31u;
                uint _8643 = _8587 & 1023u;
                if ((_8587 >> 15u) == 0u)
                {
                    _8636 = 1.0;
                }
                else
                {
                    _8636 = -1.0;
                }
                if (_8642 == 0u)
                {
                    if (_8643 == 0u)
                    {
                        _8635 = 0.0;
                        break;
                    }
                    _8635 = (_8636 * 6.103515625e-05) * (float(_8643) * 0.0009765625);
                    break;
                }
                if (_8642 == 31u)
                {
                    _8635 = _8636 * 65504.0;
                    break;
                }
                _8635 = (_8636 * exp2(float(_8642) - 15.0)) * (1.0 + (float(_8643) * 0.0009765625));
                break;
            } while(false);
            highp vec4 _8487 = vec4(vec2(_8496, _8540), vec2(_8591, _8635));
            int _8681 = (_8274 * 23) + 2;
            int _8694 = (_8274 * 23) + 3;
            int _8707 = (_8274 * 23) + 4;
            int _8720 = (_8274 * 23) + 5;
            highp vec4 _8429 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8681 - 1024 * (_8681 / 1024), _8681 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8694 - 1024 * (_8694 / 1024), _8694 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8707 - 1024 * (_8707 / 1024), _8707 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8720 - 1024 * (_8720 / 1024), _8720 / 1024), 0).x));
            int _8733 = (_8274 * 23) + 6;
            int _8746 = (_8274 * 23) + 7;
            int _8759 = (_8274 * 23) + 8;
            int _8772 = (_8274 * 23) + 9;
            uvec2 _8439 = uvec2(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8759 - 1024 * (_8759 / 1024), _8759 / 1024), 0).x, texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8772 - 1024 * (_8772 / 1024), _8772 / 1024), 0).x);
            int _8785 = (_8274 * 23) + 10;
            int _8798 = (_8274 * 23) + 11;
            int _8811 = (_8274 * 23) + 12;
            int _8824 = (_8274 * 23) + 13;
            highp vec4 _8449 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8785 - 1024 * (_8785 / 1024), _8785 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8798 - 1024 * (_8798 / 1024), _8798 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8811 - 1024 * (_8811 / 1024), _8811 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8824 - 1024 * (_8824 / 1024), _8824 / 1024), 0).x));
            int _8837 = (_8274 * 23) + 14;
            uvec4 _8845 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8837 - 1024 * (_8837 / 1024), _8837 / 1024), 0);
            uint _8846 = _8845.x;
            highp vec4 _8862 = vec4(float(_8846 & 255u), float((_8846 >> 8u) & 255u), float((_8846 >> 16u) & 255u), float((_8846 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            int _8866 = (_8274 * 23) + 15;
            uvec4 _8874 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8866 - 1024 * (_8866 / 1024), _8866 / 1024), 0);
            uint _8875 = _8874.x;
            highp vec4 _8891 = vec4(float(_8875 & 255u), float((_8875 >> 8u) & 255u), float((_8875 >> 16u) & 255u), float((_8875 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_8429.x * _8429.w) - (_8429.y * _8429.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            highp float _8894 = _8429.x;
            highp float _8895 = _8429.w;
            highp float _8897 = _8429.y;
            highp float _8898 = _8429.z;
            highp float _8900 = (_8894 * _8895) - (_8897 * _8898);
            highp vec2 _8901 = _1656 - vec2(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8733 - 1024 * (_8733 / 1024), _8733 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_8746 - 1024 * (_8746 / 1024), _8746 / 1024), 0).x));
            highp float _8902 = _8901.x;
            highp float _8904 = _8901.y;
            highp vec2 _8913 = vec2(((_8895 * _8902) - (_8897 * _8904)) / _8900, (((-_8898) * _8902) + (_8894 * _8904)) / _8900);
            highp float _8916 = _8429.x;
            highp float _8917 = _8429.w;
            highp float _8919 = _8429.y;
            highp float _8920 = _8429.z;
            highp float _8922 = (_8916 * _8917) - (_8919 * _8920);
            highp float _8923 = _1630.x;
            highp float _8925 = _1630.y;
            highp float _8937 = _8429.x;
            highp float _8938 = _8429.w;
            highp float _8940 = _8429.y;
            highp float _8941 = _8429.z;
            highp float _8943 = (_8937 * _8938) - (_8940 * _8941);
            highp float _8944 = _1633.x;
            highp float _8946 = _1633.y;
            highp vec2 _8308 = abs(vec2(((_8917 * _8923) - (_8919 * _8925)) / _8922, (((-_8920) * _8923) + (_8916 * _8925)) / _8922)) + abs(vec2(((_8938 * _8944) - (_8940 * _8946)) / _8943, (((-_8941) * _8944) + (_8937 * _8946)) / _8943));
            highp vec2 _8310 = max(_8308 * 2.0, vec2(0.001000000047497451305389404296875));
            highp float _8311 = _8913.x;
            highp float _8314 = _8310.x;
            if (_8311 < (_8487.x - _8314))
            {
                _8275 = true;
            }
            else
            {
                _8275 = _8311 > (_8487.z + _8314);
            }
            if (_8275)
            {
                _8276 = true;
            }
            else
            {
                _8276 = _8913.y < (_8487.y - _8310.y);
            }
            if (_8276)
            {
                _8277 = true;
            }
            else
            {
                _8277 = _8913.y > (_8487.w + _8310.y);
            }
            if (_8277)
            {
                break;
            }
            uint _8345 = _8439.x;
            uint _8346 = _8439.y;
            int _8349 = int((_8346 >> 24u) & 255u);
            if (_8349 == 255)
            {
                break;
            }
            int _8355 = int(_8345 & 65535u);
            int _8357 = int(_8345 >> 16u);
            int _8361 = int((_8346 >> 16u) & 255u);
            int _8363 = int(_8346 & 65535u);
            highp float _8367 = 1.0 / max(_8308.x, 1.52587890625e-05);
            highp float _8370 = 1.0 / max(_8308.y, 1.52587890625e-05);
            highp float _8967 = _8449.y;
            highp float _9140 = (_8913.y * _8967) + _8449.w;
            highp float _9144 = max(abs(_8308.y * _8967) * 0.5, 9.9999997473787516355514526367188e-06);
            int _9147 = clamp(int(_9140 - _9144), 0, _8363);
            int _9151 = max(_9147, clamp(int(_9140 + _9144), 0, _8363));
            highp float _8973 = _8449.x;
            highp float _9162 = (_8913.x * _8973) + _8449.z;
            highp float _9166 = max(abs(_8308.x * _8973) * 0.5, 9.9999997473787516355514526367188e-06);
            int _9169 = clamp(int(_9162 - _9166), 0, _8361);
            int _9173 = max(_9169, clamp(int(_9162 + _9166), 0, _8361));
            highp float _8956 = 0.0;
            highp float _8957 = 0.0;
            bool _8979 = _9147 != _9151;
            int _8958 = _9147;
            for (;;)
            {
                if (!(_8958 <= _9151))
                {
                    break;
                }
                int _9186 = _8355 + _8958;
                ivec2 _9188 = ivec2(_9186, _8357);
                _9188.y = _9188.y + (_9186 >> 12);
                _9188.x = _9188.x & 4095;
                uvec4 _8994 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9188, _8349, 0).xyz, 0);
                int _9202 = _8355 + int(_8994.y);
                ivec2 _9204 = ivec2(_9202, _8357);
                _9204.y = _9204.y + (_9202 >> 12);
                _9204.x = _9204.x & 4095;
                int _9001 = int(_8994.x);
                _8959 = 0;
                for (;;)
                {
                    bool _9004_ladder_break = false;
                    do
                    {
                        if (!(_8959 < _9001))
                        {
                            _9004_ladder_break = true;
                            break;
                        }
                        int _9218 = _9204.x + _8959;
                        ivec2 _9220 = ivec2(_9218, _9204.y);
                        _9220.y = _9220.y + (_9218 >> 12);
                        _9220.x = _9220.x & 4095;
                        uvec4 _9016 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9220, _8349, 0).xyz, 0);
                        if (_8979)
                        {
                            _8960 = !(_8958 == max(int(_9016.x >> 12u), _9147));
                        }
                        else
                        {
                            _8960 = false;
                        }
                        if (_8960)
                        {
                            break;
                        }
                        ivec2 _9250 = ivec2(int(_9016.x & 4095u), int(_9016.y & 16383u));
                        do
                        {
                            highp vec4 _9259 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9250, _8349, 0).xyz, 0);
                            int _9328 = _9250.x + 1;
                            ivec2 _9330 = ivec2(_9328, _9250.y);
                            _9330.y = _9330.y + (_9328 >> 12);
                            _9330.x = _9330.x & 4095;
                            highp vec4 _9271 = vec4(_9259.xy, _9259.zw) - vec4(_8913, _8913);
                            highp vec2 _9273 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9330, _8349, 0).xyz, 0).xy - _8913;
                            if ((max(max(_9271.x, _9271.z), _9273.x) * _8367) < (-0.5))
                            {
                                _9252 = false;
                                break;
                            }
                            if (abs(_9271.y) <= 1.52587890625e-05)
                            {
                                _9358 = 0.0;
                            }
                            else
                            {
                                _9358 = _9271.y;
                            }
                            if (abs(_9271.w) <= 1.52587890625e-05)
                            {
                                _9367 = 0.0;
                            }
                            else
                            {
                                _9367 = _9271.w;
                            }
                            if (abs(_9273.y) <= 1.52587890625e-05)
                            {
                                _9376 = 0.0;
                            }
                            else
                            {
                                _9376 = _9273.y;
                            }
                            uint _9357 = (11892u >> (((floatBitsToUint(_9376) >> 29u) & 4u) | ((((floatBitsToUint(_9367) >> 30u) & 2u) | ((floatBitsToUint(_9358) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_9357 != 0u)
                            {
                                highp vec2 _9393 = (_9271.xy - (_9271.zw * 2.0)) + _9273;
                                highp vec2 _9394 = _9271.xy - _9271.zw;
                                highp float _9395 = _9393.y;
                                if (abs(_9395) < 1.52587890625e-05)
                                {
                                    highp float _9427 = _9394.y;
                                    if (abs(_9427) < 1.52587890625e-05)
                                    {
                                        _9385 = 0.0;
                                    }
                                    else
                                    {
                                        _9385 = (_9271.y * 0.5) / _9427;
                                    }
                                    _9386 = _9385;
                                }
                                else
                                {
                                    highp float _9399 = _9394.y;
                                    highp float _9402 = _9395 * _9271.y;
                                    highp float _9403 = (_9399 * _9399) - _9402;
                                    if (_9403 <= (max(_9399 * _9399, abs(_9402)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _9455 = 0.0;
                                    }
                                    else
                                    {
                                        _9455 = sqrt(_9403);
                                    }
                                    if (_9399 >= 0.0)
                                    {
                                        highp float _9417 = _9399 + _9455;
                                        if (abs(_9417) < 1.52587890625e-05)
                                        {
                                            _9385 = 0.0;
                                        }
                                        else
                                        {
                                            _9385 = _9271.y / _9417;
                                        }
                                        _9386 = _9417 / _9395;
                                    }
                                    else
                                    {
                                        highp float _9407 = _9399 - _9455;
                                        if (abs(_9407) < 1.52587890625e-05)
                                        {
                                            _9385 = 0.0;
                                        }
                                        else
                                        {
                                            _9385 = _9271.y / _9407;
                                        }
                                        highp float _9415 = _9385;
                                        _9385 = _9407 / _9395;
                                        _9386 = _9415;
                                    }
                                }
                                highp float _9438 = _9393.x;
                                highp float _9442 = _9394.x * 2.0;
                                highp vec2 _9291 = vec2((((_9438 * _9385) - _9442) * _9385) + _9271.x, (((_9438 * _9386) - _9442) * _9386) + _9271.x) * _8367;
                                if ((_9357 & 1u) != 0u)
                                {
                                    highp float _9295 = _9291.x;
                                    _8956 += clamp(_9295 + 0.5, 0.0, 1.0);
                                    _8957 = max(_8957, clamp(1.0 - (abs(_9295) * 2.0), 0.0, 1.0));
                                }
                                if (_9357 > 1u)
                                {
                                    highp float _9309 = _9291.y;
                                    _8956 -= clamp(_9309 + 0.5, 0.0, 1.0);
                                    _8957 = max(_8957, clamp(1.0 - (abs(_9309) * 2.0), 0.0, 1.0));
                                }
                            }
                            _9252 = true;
                            break;
                        } while(false);
                        if (!_9252)
                        {
                            _9004_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_9004_ladder_break)
                    {
                        break;
                    }
                    _8959++;
                    continue;
                }
                _8958++;
                continue;
            }
            highp float _8961 = 0.0;
            highp float _8962 = 0.0;
            bool _9048 = _9169 != _9173;
            _8958 = _9169;
            for (;;)
            {
                if (!(_8958 <= _9173))
                {
                    break;
                }
                int _9473 = _8355 + ((_8363 + 1) + _8958);
                ivec2 _9475 = ivec2(_9473, _8357);
                _9475.y = _9475.y + (_9473 >> 12);
                _9475.x = _9475.x & 4095;
                uvec4 _9065 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9475, _8349, 0).xyz, 0);
                int _9489 = _8355 + int(_9065.y);
                ivec2 _9491 = ivec2(_9489, _8357);
                _9491.y = _9491.y + (_9489 >> 12);
                _9491.x = _9491.x & 4095;
                int _9072 = int(_9065.x);
                _8959 = 0;
                for (;;)
                {
                    bool _9075_ladder_break = false;
                    do
                    {
                        if (!(_8959 < _9072))
                        {
                            _9075_ladder_break = true;
                            break;
                        }
                        int _9505 = _9491.x + _8959;
                        ivec2 _9507 = ivec2(_9505, _9491.y);
                        _9507.y = _9507.y + (_9505 >> 12);
                        _9507.x = _9507.x & 4095;
                        uvec4 _9087 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_9507, _8349, 0).xyz, 0);
                        if (_9048)
                        {
                            _8960 = !(_8958 == max(int(_9087.x >> 12u), _9169));
                        }
                        else
                        {
                            _8960 = false;
                        }
                        if (_8960)
                        {
                            break;
                        }
                        ivec2 _9537 = ivec2(int(_9087.x & 4095u), int(_9087.y & 16383u));
                        do
                        {
                            highp vec4 _9546 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9537, _8349, 0).xyz, 0);
                            int _9615 = _9537.x + 1;
                            ivec2 _9617 = ivec2(_9615, _9537.y);
                            _9617.y = _9617.y + (_9615 >> 12);
                            _9617.x = _9617.x & 4095;
                            highp vec4 _9558 = vec4(_9546.xy, _9546.zw) - vec4(_8913, _8913);
                            highp vec2 _9560 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_9617, _8349, 0).xyz, 0).xy - _8913;
                            if ((max(max(_9558.y, _9558.w), _9560.y) * _8370) < (-0.5))
                            {
                                _9539 = false;
                                break;
                            }
                            if (abs(_9558.x) <= 1.52587890625e-05)
                            {
                                _9645 = 0.0;
                            }
                            else
                            {
                                _9645 = _9558.x;
                            }
                            if (abs(_9558.z) <= 1.52587890625e-05)
                            {
                                _9654 = 0.0;
                            }
                            else
                            {
                                _9654 = _9558.z;
                            }
                            if (abs(_9560.x) <= 1.52587890625e-05)
                            {
                                _9663 = 0.0;
                            }
                            else
                            {
                                _9663 = _9560.x;
                            }
                            uint _9644 = (11892u >> (((floatBitsToUint(_9663) >> 29u) & 4u) | ((((floatBitsToUint(_9654) >> 30u) & 2u) | ((floatBitsToUint(_9645) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_9644 != 0u)
                            {
                                highp vec2 _9680 = (_9558.xy - (_9558.zw * 2.0)) + _9560;
                                highp vec2 _9681 = _9558.xy - _9558.zw;
                                highp float _9682 = _9680.x;
                                if (abs(_9682) < 1.52587890625e-05)
                                {
                                    highp float _9714 = _9681.x;
                                    if (abs(_9714) < 1.52587890625e-05)
                                    {
                                        _9672 = 0.0;
                                    }
                                    else
                                    {
                                        _9672 = (_9558.x * 0.5) / _9714;
                                    }
                                    _9673 = _9672;
                                }
                                else
                                {
                                    highp float _9686 = _9681.x;
                                    highp float _9689 = _9682 * _9558.x;
                                    highp float _9690 = (_9686 * _9686) - _9689;
                                    if (_9690 <= (max(_9686 * _9686, abs(_9689)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _9742 = 0.0;
                                    }
                                    else
                                    {
                                        _9742 = sqrt(_9690);
                                    }
                                    if (_9686 >= 0.0)
                                    {
                                        highp float _9704 = _9686 + _9742;
                                        if (abs(_9704) < 1.52587890625e-05)
                                        {
                                            _9672 = 0.0;
                                        }
                                        else
                                        {
                                            _9672 = _9558.x / _9704;
                                        }
                                        _9673 = _9704 / _9682;
                                    }
                                    else
                                    {
                                        highp float _9694 = _9686 - _9742;
                                        if (abs(_9694) < 1.52587890625e-05)
                                        {
                                            _9672 = 0.0;
                                        }
                                        else
                                        {
                                            _9672 = _9558.x / _9694;
                                        }
                                        highp float _9702 = _9672;
                                        _9672 = _9694 / _9682;
                                        _9673 = _9702;
                                    }
                                }
                                highp float _9725 = _9680.y;
                                highp float _9729 = _9681.y * 2.0;
                                highp vec2 _9578 = vec2((((_9725 * _9672) - _9729) * _9672) + _9558.y, (((_9725 * _9673) - _9729) * _9673) + _9558.y) * _8370;
                                if ((_9644 & 1u) != 0u)
                                {
                                    highp float _9582 = _9578.x;
                                    _8961 -= clamp(_9582 + 0.5, 0.0, 1.0);
                                    _8962 = max(_8962, clamp(1.0 - (abs(_9582) * 2.0), 0.0, 1.0));
                                }
                                if (_9644 > 1u)
                                {
                                    highp float _9596 = _9578.y;
                                    _8961 += clamp(_9596 + 0.5, 0.0, 1.0);
                                    _8962 = max(_8962, clamp(1.0 - (abs(_9596) * 2.0), 0.0, 1.0));
                                }
                            }
                            _9539 = true;
                            break;
                        } while(false);
                        if (!_9539)
                        {
                            _9075_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_9075_ladder_break)
                    {
                        break;
                    }
                    _8959++;
                    continue;
                }
                _8958++;
                continue;
            }
            highp float _9128 = ((_8956 * _8957) + (_8961 * _8962)) / max(_8957 + _8962, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _9756 = 1.0 - abs((fract(_9128 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _9756 = abs(_9128);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _9773 = 1.0 - abs((fract(_8956 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _9773 = abs(_8956);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _9790 = 1.0 - abs((fract(_8961 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _9790 = abs(_8961);
                break;
            } while(false);
            highp float _9809 = clamp(max(_9756, min(_9773, _9790)), 0.0, 1.0);
            highp float _9812 = abs(0.0);
            if (_9812 <= 9.9999999747524270787835121154785e-07)
            {
                _9806 = _9809;
            }
            else
            {
                _9806 = pow(_9809, 1.0);
            }
            highp float _8380 = clamp((_9806 * _8862.w) * _8891.w, 0.0, 1.0);
            if (_8380 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            highp float _9821 = _8862.x;
            if (_9821 <= 0.040449999272823333740234375)
            {
                _9828 = _9821 * 0.077399380505084991455078125;
            }
            else
            {
                _9828 = pow((_9821 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _9823 = _8862.y;
            if (_9823 <= 0.040449999272823333740234375)
            {
                _9840 = _9823 * 0.077399380505084991455078125;
            }
            else
            {
                _9840 = pow((_9823 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _9825 = _8862.z;
            if (_9825 <= 0.040449999272823333740234375)
            {
                _9852 = _9825 * 0.077399380505084991455078125;
            }
            else
            {
                _9852 = pow((_9825 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _9866 = _8891.x;
            if (_9866 <= 0.040449999272823333740234375)
            {
                _9873 = _9866 * 0.077399380505084991455078125;
            }
            else
            {
                _9873 = pow((_9866 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _9868 = _8891.y;
            if (_9868 <= 0.040449999272823333740234375)
            {
                _9885 = _9868 * 0.077399380505084991455078125;
            }
            else
            {
                _9885 = pow((_9868 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _9870 = _8891.z;
            if (_9870 <= 0.040449999272823333740234375)
            {
                _9897 = _9870 * 0.077399380505084991455078125;
            }
            else
            {
                _9897 = pow((_9870 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp vec4 _8390 = _8273;
            highp float _8392 = 1.0 - _8380;
            highp vec3 _8394 = ((vec3(_9828, _9840, _9852) * vec3(_9873, _9885, _9897)) * _8380) + (_8390.xyz * _8392);
            highp vec4 _10637 = _8390;
            _10637.x = _8394.x;
            _10637.y = _8394.y;
            _10637.z = _8394.z;
            _10637.w = _8380 + (_10637.w * _8392);
            _8273 = _10637;
            break;
        } while(false);
        if (_8282_ladder_break)
        {
            break;
        }
        _8274++;
        continue;
    }
    highp vec2 _9911 = snail_io0 * 6.283185482025146484375;
    highp float _9929 = (((0.5 * sin(dot(_9911, vec2(1.7000000476837158203125, 0.60000002384185791015625)))) + (0.2700000107288360595703125 * sin(dot(_9911, vec2(3.900000095367431640625, -2.7000000476837158203125)) + 1.2999999523162841796875))) + (0.1500000059604644775390625 * cos(dot(_9911, vec2(7.099999904632568359375, 5.30000019073486328125)) + 0.4000000059604644775390625))) + (0.07999999821186065673828125 * sin(dot(_9911, vec2(13.69999980926513671875, -9.1000003814697265625)) + 2.099999904632568359375));
    highp vec2 _9932 = (snail_io0 + vec2(0.0009765625, 0.0)) * 6.283185482025146484375;
    highp vec2 _9953 = (snail_io0 + vec2(0.0, 0.0009765625)) * 6.283185482025146484375;
    highp vec3 _1677 = normalize(vec3(-((vec2(((((0.5 * sin(dot(_9932, vec2(1.7000000476837158203125, 0.60000002384185791015625)))) + (0.2700000107288360595703125 * sin(dot(_9932, vec2(3.900000095367431640625, -2.7000000476837158203125)) + 1.2999999523162841796875))) + (0.1500000059604644775390625 * cos(dot(_9932, vec2(7.099999904632568359375, 5.30000019073486328125)) + 0.4000000059604644775390625))) + (0.07999999821186065673828125 * sin(dot(_9932, vec2(13.69999980926513671875, -9.1000003814697265625)) + 2.099999904632568359375))) - _9929, ((((0.5 * sin(dot(_9953, vec2(1.7000000476837158203125, 0.60000002384185791015625)))) + (0.2700000107288360595703125 * sin(dot(_9953, vec2(3.900000095367431640625, -2.7000000476837158203125)) + 1.2999999523162841796875))) + (0.1500000059604644775390625 * cos(dot(_9953, vec2(7.099999904632568359375, 5.30000019073486328125)) + 0.4000000059604644775390625))) + (0.07999999821186065673828125 * sin(dot(_9953, vec2(13.69999980926513671875, -9.1000003814697265625)) + 2.099999904632568359375))) - _9929) * (pc.roughness * 1024.0)) + (vec2(_3350.w - _4991.w, _6632.w - _8273.w) * (0.5 * pc.relief))), 1.0));
    highp vec3 _1678 = normalize(pc.light_dir.xyz);
    highp float _1686 = clamp(_1708.w, 0.0, 1.0);
    highp vec3 _1702 = ((mix(pc.base_color.xyz, vec3(0.23999999463558197021484375, 0.300000011920928955078125, 0.4000000059604644775390625), vec3(_1686)) * (0.20000000298023223876953125 + ((0.7799999713897705078125 + (0.2199999988079071044921875 * _1686)) * max(dot(_1677, _1678), 0.0)))) * (0.939999997615814208984375 + (0.0599999986588954925537109375 * _9929))) + ((vec3(0.800000011920928955078125, 0.87999999523162841796875, 1.0) * pow(max(dot(_1677, normalize(_1678 + vec3(0.0, 0.0, 1.0))), 0.0), 40.0)) * (0.119999997317790985107421875 + (0.2800000011920928955078125 * _1686)));
    highp vec3 outc;
    if (pc.output_srgb == 1)
    {
        highp vec3 _9974 = clamp(_1702, vec3(0.0), vec3(1.0));
        outc = mix((pow(_9974, vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), _9974 * 12.9200000762939453125, step(_9974, vec3(0.003130800090730190277099609375)));
    }
    else
    {
        outc = _1702;
    }
    entryPointParam_fragmentMain = vec4(outc, 1.0);
}


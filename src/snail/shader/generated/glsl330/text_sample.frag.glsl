#version 330

layout(std140) uniform SnailTextSampleParams_std140
{
    int glyph_count;
    int words_per_glyph;
    int layer_base;
    float coverage_exponent;
} pc;

uniform usamplerBuffer u_snail_text_records;
uniform usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in vec2 snail_io0;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

void main()
{
    vec2 _1439 = dFdx(snail_io0);
    vec2 _1442 = dFdy(snail_io0);
    vec4 _1443 = vec4(0.0);
    int _1444 = 0;
    bool _1445;
    bool _1446;
    bool _1447;
    float _1665;
    float _1666;
    float _1709;
    float _1710;
    float _1760;
    float _1761;
    float _1804;
    float _1805;
    int _2114;
    bool _2115;
    bool _2407;
    float _2513;
    float _2522;
    float _2531;
    float _2540;
    float _2541;
    float _2610;
    bool _2694;
    float _2800;
    float _2809;
    float _2818;
    float _2827;
    float _2828;
    float _2897;
    float _2911;
    float _2928;
    float _2945;
    float _2961;
    float _2984;
    float _2996;
    float _3008;
    float _3029;
    float _3041;
    float _3053;
    for (;;)
    {
        bool _1452_ladder_break = false;
        do
        {
            if (!(_1444 < pc.glyph_count))
            {
                _1452_ladder_break = true;
                break;
            }
            uvec4 _1638 = texelFetch(u_snail_text_records, _1444 * pc.words_per_glyph);
            uint _1639 = _1638.x;
            uvec4 _1650 = texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 1);
            uint _1651 = _1650.x;
            uint _1659 = _1639 & 65535u;
            do
            {
                uint _1672 = (_1659 >> 10u) & 31u;
                uint _1673 = _1639 & 1023u;
                if ((_1659 >> 15u) == 0u)
                {
                    _1666 = 1.0;
                }
                else
                {
                    _1666 = -1.0;
                }
                if (_1672 == 0u)
                {
                    if (_1673 == 0u)
                    {
                        _1665 = 0.0;
                        break;
                    }
                    _1665 = (_1666 * 6.103515625e-05) * (float(_1673) * 0.0009765625);
                    break;
                }
                if (_1672 == 31u)
                {
                    _1665 = _1666 * 65504.0;
                    break;
                }
                _1665 = (_1666 * exp2(float(_1672) - 15.0)) * (1.0 + (float(_1673) * 0.0009765625));
                break;
            } while(false);
            uint _1661 = _1639 >> 16u;
            do
            {
                uint _1716 = (_1661 >> 10u) & 31u;
                uint _1717 = _1661 & 1023u;
                if ((_1661 >> 15u) == 0u)
                {
                    _1710 = 1.0;
                }
                else
                {
                    _1710 = -1.0;
                }
                if (_1716 == 0u)
                {
                    if (_1717 == 0u)
                    {
                        _1709 = 0.0;
                        break;
                    }
                    _1709 = (_1710 * 6.103515625e-05) * (float(_1717) * 0.0009765625);
                    break;
                }
                if (_1716 == 31u)
                {
                    _1709 = _1710 * 65504.0;
                    break;
                }
                _1709 = (_1710 * exp2(float(_1716) - 15.0)) * (1.0 + (float(_1717) * 0.0009765625));
                break;
            } while(false);
            uint _1754 = _1651 & 65535u;
            do
            {
                uint _1767 = (_1754 >> 10u) & 31u;
                uint _1768 = _1651 & 1023u;
                if ((_1754 >> 15u) == 0u)
                {
                    _1761 = 1.0;
                }
                else
                {
                    _1761 = -1.0;
                }
                if (_1767 == 0u)
                {
                    if (_1768 == 0u)
                    {
                        _1760 = 0.0;
                        break;
                    }
                    _1760 = (_1761 * 6.103515625e-05) * (float(_1768) * 0.0009765625);
                    break;
                }
                if (_1767 == 31u)
                {
                    _1760 = _1761 * 65504.0;
                    break;
                }
                _1760 = (_1761 * exp2(float(_1767) - 15.0)) * (1.0 + (float(_1768) * 0.0009765625));
                break;
            } while(false);
            uint _1756 = _1651 >> 16u;
            do
            {
                uint _1811 = (_1756 >> 10u) & 31u;
                uint _1812 = _1756 & 1023u;
                if ((_1756 >> 15u) == 0u)
                {
                    _1805 = 1.0;
                }
                else
                {
                    _1805 = -1.0;
                }
                if (_1811 == 0u)
                {
                    if (_1812 == 0u)
                    {
                        _1804 = 0.0;
                        break;
                    }
                    _1804 = (_1805 * 6.103515625e-05) * (float(_1812) * 0.0009765625);
                    break;
                }
                if (_1811 == 31u)
                {
                    _1804 = _1805 * 65504.0;
                    break;
                }
                _1804 = (_1805 * exp2(float(_1811) - 15.0)) * (1.0 + (float(_1812) * 0.0009765625));
                break;
            } while(false);
            vec4 _1656 = vec4(vec2(_1665, _1709), vec2(_1760, _1804));
            vec4 _1599 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 2).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 3).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 4).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 5).x));
            uvec2 _1609 = uvec2(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 8).x, texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 9).x);
            vec4 _1619 = vec4(uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 10).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 11).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 12).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 13).x));
            uvec4 _2001 = texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 14);
            uint _2002 = _2001.x;
            vec4 _2018 = vec4(float(_2002 & 255u), float((_2002 >> 8u) & 255u), float((_2002 >> 16u) & 255u), float((_2002 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            uvec4 _2029 = texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 15);
            uint _2030 = _2029.x;
            vec4 _2046 = vec4(float(_2030 & 255u), float((_2030 >> 8u) & 255u), float((_2030 >> 16u) & 255u), float((_2030 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_1599.x * _1599.w) - (_1599.y * _1599.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            float _2049 = _1599.x;
            float _2050 = _1599.w;
            float _2052 = _1599.y;
            float _2053 = _1599.z;
            float _2055 = (_2049 * _2050) - (_2052 * _2053);
            vec2 _2056 = snail_io0 - vec2(uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 6).x), uintBitsToFloat(texelFetch(u_snail_text_records, (_1444 * pc.words_per_glyph) + 7).x));
            float _2057 = _2056.x;
            float _2059 = _2056.y;
            vec2 _2068 = vec2(((_2050 * _2057) - (_2052 * _2059)) / _2055, (((-_2053) * _2057) + (_2049 * _2059)) / _2055);
            float _2071 = _1599.x;
            float _2072 = _1599.w;
            float _2074 = _1599.y;
            float _2075 = _1599.z;
            float _2077 = (_2071 * _2072) - (_2074 * _2075);
            float _2078 = _1439.x;
            float _2080 = _1439.y;
            float _2092 = _1599.x;
            float _2093 = _1599.w;
            float _2095 = _1599.y;
            float _2096 = _1599.z;
            float _2098 = (_2092 * _2093) - (_2095 * _2096);
            float _2099 = _1442.x;
            float _2101 = _1442.y;
            vec2 _1478 = abs(vec2(((_2072 * _2078) - (_2074 * _2080)) / _2077, (((-_2075) * _2078) + (_2071 * _2080)) / _2077)) + abs(vec2(((_2093 * _2099) - (_2095 * _2101)) / _2098, (((-_2096) * _2099) + (_2092 * _2101)) / _2098));
            vec2 _1480 = max(_1478 * 2.0, vec2(0.001000000047497451305389404296875));
            float _1481 = _2068.x;
            float _1484 = _1480.x;
            if (_1481 < (_1656.x - _1484))
            {
                _1445 = true;
            }
            else
            {
                _1445 = _1481 > (_1656.z + _1484);
            }
            if (_1445)
            {
                _1446 = true;
            }
            else
            {
                _1446 = _2068.y < (_1656.y - _1480.y);
            }
            if (_1446)
            {
                _1447 = true;
            }
            else
            {
                _1447 = _2068.y > (_1656.w + _1480.y);
            }
            if (_1447)
            {
                break;
            }
            uint _1515 = _1609.x;
            uint _1516 = _1609.y;
            int _1519 = int((_1516 >> 24u) & 255u);
            if (_1519 == 255)
            {
                break;
            }
            int _1523 = pc.layer_base + _1519;
            int _1525 = int(_1515 & 65535u);
            int _1527 = int(_1515 >> 16u);
            int _1531 = int((_1516 >> 16u) & 255u);
            int _1533 = int(_1516 & 65535u);
            float _1537 = 1.0 / max(_1478.x, 1.52587890625e-05);
            float _1540 = 1.0 / max(_1478.y, 1.52587890625e-05);
            float _2122 = _1619.y;
            float _2295 = (_2068.y * _2122) + _1619.w;
            float _2299 = max(abs(_1478.y * _2122) * 0.5, 9.9999997473787516355514526367188e-06);
            int _2302 = clamp(int(_2295 - _2299), 0, _1533);
            int _2306 = max(_2302, clamp(int(_2295 + _2299), 0, _1533));
            float _2128 = _1619.x;
            float _2317 = (_2068.x * _2128) + _1619.z;
            float _2321 = max(abs(_1478.x * _2128) * 0.5, 9.9999997473787516355514526367188e-06);
            int _2324 = clamp(int(_2317 - _2321), 0, _1531);
            int _2328 = max(_2324, clamp(int(_2317 + _2321), 0, _1531));
            float _2111 = 0.0;
            float _2112 = 0.0;
            bool _2134 = _2302 != _2306;
            int _2113 = _2302;
            for (;;)
            {
                if (!(_2113 <= _2306))
                {
                    break;
                }
                int _2341 = _1525 + _2113;
                ivec2 _2343 = ivec2(_2341, _1527);
                _2343.y = _2343.y + (_2341 >> 12);
                _2343.x = _2343.x & 4095;
                uvec4 _2149 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2343, _1523, 0).xyz, 0);
                int _2357 = _1525 + int(_2149.y);
                ivec2 _2359 = ivec2(_2357, _1527);
                _2359.y = _2359.y + (_2357 >> 12);
                _2359.x = _2359.x & 4095;
                int _2156 = int(_2149.x);
                _2114 = 0;
                for (;;)
                {
                    bool _2159_ladder_break = false;
                    do
                    {
                        if (!(_2114 < _2156))
                        {
                            _2159_ladder_break = true;
                            break;
                        }
                        int _2373 = _2359.x + _2114;
                        ivec2 _2375 = ivec2(_2373, _2359.y);
                        _2375.y = _2375.y + (_2373 >> 12);
                        _2375.x = _2375.x & 4095;
                        uvec4 _2171 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2375, _1523, 0).xyz, 0);
                        if (_2134)
                        {
                            _2115 = !(_2113 == max(int(_2171.x >> 12u), _2302));
                        }
                        else
                        {
                            _2115 = false;
                        }
                        if (_2115)
                        {
                            break;
                        }
                        ivec2 _2405 = ivec2(int(_2171.x & 4095u), int(_2171.y & 16383u));
                        do
                        {
                            vec4 _2414 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2405, _1523, 0).xyz, 0);
                            int _2483 = _2405.x + 1;
                            ivec2 _2485 = ivec2(_2483, _2405.y);
                            _2485.y = _2485.y + (_2483 >> 12);
                            _2485.x = _2485.x & 4095;
                            vec4 _2426 = vec4(_2414.xy, _2414.zw) - vec4(_2068, _2068);
                            vec2 _2428 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2485, _1523, 0).xyz, 0).xy - _2068;
                            if ((max(max(_2426.x, _2426.z), _2428.x) * _1537) < (-0.5))
                            {
                                _2407 = false;
                                break;
                            }
                            if (abs(_2426.y) <= 1.52587890625e-05)
                            {
                                _2513 = 0.0;
                            }
                            else
                            {
                                _2513 = _2426.y;
                            }
                            if (abs(_2426.w) <= 1.52587890625e-05)
                            {
                                _2522 = 0.0;
                            }
                            else
                            {
                                _2522 = _2426.w;
                            }
                            if (abs(_2428.y) <= 1.52587890625e-05)
                            {
                                _2531 = 0.0;
                            }
                            else
                            {
                                _2531 = _2428.y;
                            }
                            uint _2512 = (11892u >> (((floatBitsToUint(_2531) >> 29u) & 4u) | ((((floatBitsToUint(_2522) >> 30u) & 2u) | ((floatBitsToUint(_2513) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_2512 != 0u)
                            {
                                vec2 _2548 = (_2426.xy - (_2426.zw * 2.0)) + _2428;
                                vec2 _2549 = _2426.xy - _2426.zw;
                                float _2550 = _2548.y;
                                if (abs(_2550) < 1.52587890625e-05)
                                {
                                    float _2582 = _2549.y;
                                    if (abs(_2582) < 1.52587890625e-05)
                                    {
                                        _2540 = 0.0;
                                    }
                                    else
                                    {
                                        _2540 = (_2426.y * 0.5) / _2582;
                                    }
                                    _2541 = _2540;
                                }
                                else
                                {
                                    float _2554 = _2549.y;
                                    float _2557 = _2550 * _2426.y;
                                    float _2558 = (_2554 * _2554) - _2557;
                                    if (_2558 <= (max(_2554 * _2554, abs(_2557)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _2610 = 0.0;
                                    }
                                    else
                                    {
                                        _2610 = sqrt(_2558);
                                    }
                                    if (_2554 >= 0.0)
                                    {
                                        float _2572 = _2554 + _2610;
                                        if (abs(_2572) < 1.52587890625e-05)
                                        {
                                            _2540 = 0.0;
                                        }
                                        else
                                        {
                                            _2540 = _2426.y / _2572;
                                        }
                                        _2541 = _2572 / _2550;
                                    }
                                    else
                                    {
                                        float _2562 = _2554 - _2610;
                                        if (abs(_2562) < 1.52587890625e-05)
                                        {
                                            _2540 = 0.0;
                                        }
                                        else
                                        {
                                            _2540 = _2426.y / _2562;
                                        }
                                        float _2570 = _2540;
                                        _2540 = _2562 / _2550;
                                        _2541 = _2570;
                                    }
                                }
                                float _2593 = _2548.x;
                                float _2597 = _2549.x * 2.0;
                                vec2 _2446 = vec2((((_2593 * _2540) - _2597) * _2540) + _2426.x, (((_2593 * _2541) - _2597) * _2541) + _2426.x) * _1537;
                                if ((_2512 & 1u) != 0u)
                                {
                                    float _2450 = _2446.x;
                                    _2111 += clamp(_2450 + 0.5, 0.0, 1.0);
                                    _2112 = max(_2112, clamp(1.0 - (abs(_2450) * 2.0), 0.0, 1.0));
                                }
                                if (_2512 > 1u)
                                {
                                    float _2464 = _2446.y;
                                    _2111 -= clamp(_2464 + 0.5, 0.0, 1.0);
                                    _2112 = max(_2112, clamp(1.0 - (abs(_2464) * 2.0), 0.0, 1.0));
                                }
                            }
                            _2407 = true;
                            break;
                        } while(false);
                        if (!_2407)
                        {
                            _2159_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_2159_ladder_break)
                    {
                        break;
                    }
                    _2114++;
                    continue;
                }
                _2113++;
                continue;
            }
            float _2116 = 0.0;
            float _2117 = 0.0;
            bool _2203 = _2324 != _2328;
            _2113 = _2324;
            for (;;)
            {
                if (!(_2113 <= _2328))
                {
                    break;
                }
                int _2628 = _1525 + ((_1533 + 1) + _2113);
                ivec2 _2630 = ivec2(_2628, _1527);
                _2630.y = _2630.y + (_2628 >> 12);
                _2630.x = _2630.x & 4095;
                uvec4 _2220 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2630, _1523, 0).xyz, 0);
                int _2644 = _1525 + int(_2220.y);
                ivec2 _2646 = ivec2(_2644, _1527);
                _2646.y = _2646.y + (_2644 >> 12);
                _2646.x = _2646.x & 4095;
                int _2227 = int(_2220.x);
                _2114 = 0;
                for (;;)
                {
                    bool _2230_ladder_break = false;
                    do
                    {
                        if (!(_2114 < _2227))
                        {
                            _2230_ladder_break = true;
                            break;
                        }
                        int _2660 = _2646.x + _2114;
                        ivec2 _2662 = ivec2(_2660, _2646.y);
                        _2662.y = _2662.y + (_2660 >> 12);
                        _2662.x = _2662.x & 4095;
                        uvec4 _2242 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2662, _1523, 0).xyz, 0);
                        if (_2203)
                        {
                            _2115 = !(_2113 == max(int(_2242.x >> 12u), _2324));
                        }
                        else
                        {
                            _2115 = false;
                        }
                        if (_2115)
                        {
                            break;
                        }
                        ivec2 _2692 = ivec2(int(_2242.x & 4095u), int(_2242.y & 16383u));
                        do
                        {
                            vec4 _2701 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2692, _1523, 0).xyz, 0);
                            int _2770 = _2692.x + 1;
                            ivec2 _2772 = ivec2(_2770, _2692.y);
                            _2772.y = _2772.y + (_2770 >> 12);
                            _2772.x = _2772.x & 4095;
                            vec4 _2713 = vec4(_2701.xy, _2701.zw) - vec4(_2068, _2068);
                            vec2 _2715 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2772, _1523, 0).xyz, 0).xy - _2068;
                            if ((max(max(_2713.y, _2713.w), _2715.y) * _1540) < (-0.5))
                            {
                                _2694 = false;
                                break;
                            }
                            if (abs(_2713.x) <= 1.52587890625e-05)
                            {
                                _2800 = 0.0;
                            }
                            else
                            {
                                _2800 = _2713.x;
                            }
                            if (abs(_2713.z) <= 1.52587890625e-05)
                            {
                                _2809 = 0.0;
                            }
                            else
                            {
                                _2809 = _2713.z;
                            }
                            if (abs(_2715.x) <= 1.52587890625e-05)
                            {
                                _2818 = 0.0;
                            }
                            else
                            {
                                _2818 = _2715.x;
                            }
                            uint _2799 = (11892u >> (((floatBitsToUint(_2818) >> 29u) & 4u) | ((((floatBitsToUint(_2809) >> 30u) & 2u) | ((floatBitsToUint(_2800) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_2799 != 0u)
                            {
                                vec2 _2835 = (_2713.xy - (_2713.zw * 2.0)) + _2715;
                                vec2 _2836 = _2713.xy - _2713.zw;
                                float _2837 = _2835.x;
                                if (abs(_2837) < 1.52587890625e-05)
                                {
                                    float _2869 = _2836.x;
                                    if (abs(_2869) < 1.52587890625e-05)
                                    {
                                        _2827 = 0.0;
                                    }
                                    else
                                    {
                                        _2827 = (_2713.x * 0.5) / _2869;
                                    }
                                    _2828 = _2827;
                                }
                                else
                                {
                                    float _2841 = _2836.x;
                                    float _2844 = _2837 * _2713.x;
                                    float _2845 = (_2841 * _2841) - _2844;
                                    if (_2845 <= (max(_2841 * _2841, abs(_2844)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _2897 = 0.0;
                                    }
                                    else
                                    {
                                        _2897 = sqrt(_2845);
                                    }
                                    if (_2841 >= 0.0)
                                    {
                                        float _2859 = _2841 + _2897;
                                        if (abs(_2859) < 1.52587890625e-05)
                                        {
                                            _2827 = 0.0;
                                        }
                                        else
                                        {
                                            _2827 = _2713.x / _2859;
                                        }
                                        _2828 = _2859 / _2837;
                                    }
                                    else
                                    {
                                        float _2849 = _2841 - _2897;
                                        if (abs(_2849) < 1.52587890625e-05)
                                        {
                                            _2827 = 0.0;
                                        }
                                        else
                                        {
                                            _2827 = _2713.x / _2849;
                                        }
                                        float _2857 = _2827;
                                        _2827 = _2849 / _2837;
                                        _2828 = _2857;
                                    }
                                }
                                float _2880 = _2835.y;
                                float _2884 = _2836.y * 2.0;
                                vec2 _2733 = vec2((((_2880 * _2827) - _2884) * _2827) + _2713.y, (((_2880 * _2828) - _2884) * _2828) + _2713.y) * _1540;
                                if ((_2799 & 1u) != 0u)
                                {
                                    float _2737 = _2733.x;
                                    _2116 -= clamp(_2737 + 0.5, 0.0, 1.0);
                                    _2117 = max(_2117, clamp(1.0 - (abs(_2737) * 2.0), 0.0, 1.0));
                                }
                                if (_2799 > 1u)
                                {
                                    float _2751 = _2733.y;
                                    _2116 += clamp(_2751 + 0.5, 0.0, 1.0);
                                    _2117 = max(_2117, clamp(1.0 - (abs(_2751) * 2.0), 0.0, 1.0));
                                }
                            }
                            _2694 = true;
                            break;
                        } while(false);
                        if (!_2694)
                        {
                            _2230_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_2230_ladder_break)
                    {
                        break;
                    }
                    _2114++;
                    continue;
                }
                _2113++;
                continue;
            }
            float _2283 = ((_2111 * _2112) + (_2116 * _2117)) / max(_2112 + _2117, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _2911 = 1.0 - abs((fract(_2283 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _2911 = abs(_2283);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _2928 = 1.0 - abs((fract(_2111 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _2928 = abs(_2111);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _2945 = 1.0 - abs((fract(_2116 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _2945 = abs(_2116);
                break;
            } while(false);
            float _2964 = clamp(max(_2911, min(_2928, _2945)), 0.0, 1.0);
            float _2965 = max(pc.coverage_exponent, 1.52587890625e-05);
            if (abs(_2965 - 1.0) <= 9.9999999747524270787835121154785e-07)
            {
                _2961 = _2964;
            }
            else
            {
                _2961 = pow(_2964, _2965);
            }
            float _1550 = clamp((_2961 * _2018.w) * _2046.w, 0.0, 1.0);
            if (_1550 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            float _2977 = _2018.x;
            if (_2977 <= 0.040449999272823333740234375)
            {
                _2984 = _2977 * 0.077399380505084991455078125;
            }
            else
            {
                _2984 = pow((_2977 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _2979 = _2018.y;
            if (_2979 <= 0.040449999272823333740234375)
            {
                _2996 = _2979 * 0.077399380505084991455078125;
            }
            else
            {
                _2996 = pow((_2979 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _2981 = _2018.z;
            if (_2981 <= 0.040449999272823333740234375)
            {
                _3008 = _2981 * 0.077399380505084991455078125;
            }
            else
            {
                _3008 = pow((_2981 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _3022 = _2046.x;
            if (_3022 <= 0.040449999272823333740234375)
            {
                _3029 = _3022 * 0.077399380505084991455078125;
            }
            else
            {
                _3029 = pow((_3022 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _3024 = _2046.y;
            if (_3024 <= 0.040449999272823333740234375)
            {
                _3041 = _3024 * 0.077399380505084991455078125;
            }
            else
            {
                _3041 = pow((_3024 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            float _3026 = _2046.z;
            if (_3026 <= 0.040449999272823333740234375)
            {
                _3053 = _3026 * 0.077399380505084991455078125;
            }
            else
            {
                _3053 = pow((_3026 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            vec4 _1560 = _1443;
            float _1562 = 1.0 - _1550;
            vec3 _1564 = ((vec3(_2984, _2996, _3008) * vec3(_3029, _3041, _3053)) * _1550) + (_1560.xyz * _1562);
            vec4 _3196 = _1560;
            _3196.x = _1564.x;
            _3196.y = _1564.y;
            _3196.z = _1564.z;
            _3196.w = _1550 + (_3196.w * _1562);
            _1443 = _3196;
            break;
        } while(false);
        if (_1452_ladder_break)
        {
            break;
        }
        _1444++;
        continue;
    }
    entryPointParam_fragmentMain = _1443;
}


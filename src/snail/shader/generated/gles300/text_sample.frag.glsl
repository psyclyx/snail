#version 300 es
precision highp float;
precision highp int;

layout(std140) uniform SnailTextSampleParams_std140
{
    int glyph_count;
    int words_per_glyph;
    int layer_base;
    highp float coverage_exponent;
} pc;

uniform highp usampler2D SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler;
uniform highp usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform highp sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in highp vec2 snail_io0;
layout(location = 0) out highp vec4 entryPointParam_fragmentMain;

void main()
{
    highp vec2 _1441 = dFdx(snail_io0);
    highp vec2 _1444 = dFdy(snail_io0);
    highp vec4 _1445 = vec4(0.0);
    int _1446 = 0;
    bool _1447;
    bool _1448;
    bool _1449;
    highp float _1669;
    highp float _1670;
    highp float _1713;
    highp float _1714;
    highp float _1764;
    highp float _1765;
    highp float _1808;
    highp float _1809;
    int _2132;
    bool _2133;
    bool _2425;
    highp float _2531;
    highp float _2540;
    highp float _2549;
    highp float _2558;
    highp float _2559;
    highp float _2628;
    bool _2712;
    highp float _2818;
    highp float _2827;
    highp float _2836;
    highp float _2845;
    highp float _2846;
    highp float _2915;
    highp float _2929;
    highp float _2946;
    highp float _2963;
    highp float _2979;
    highp float _3002;
    highp float _3014;
    highp float _3026;
    highp float _3047;
    highp float _3059;
    highp float _3071;
    for (;;)
    {
        bool _1454_ladder_break = false;
        do
        {
            if (!(_1446 < pc.glyph_count))
            {
                _1454_ladder_break = true;
                break;
            }
            int _1632 = _1446 * pc.words_per_glyph;
            uvec4 _1641 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1632 - 1024 * (_1632 / 1024), _1632 / 1024), 0);
            uint _1642 = _1641.x;
            int _1646 = (_1446 * pc.words_per_glyph) + 1;
            uvec4 _1654 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1646 - 1024 * (_1646 / 1024), _1646 / 1024), 0);
            uint _1655 = _1654.x;
            uint _1663 = _1642 & 65535u;
            do
            {
                uint _1676 = (_1663 >> 10u) & 31u;
                uint _1677 = _1642 & 1023u;
                if ((_1663 >> 15u) == 0u)
                {
                    _1670 = 1.0;
                }
                else
                {
                    _1670 = -1.0;
                }
                if (_1676 == 0u)
                {
                    if (_1677 == 0u)
                    {
                        _1669 = 0.0;
                        break;
                    }
                    _1669 = (_1670 * 6.103515625e-05) * (float(_1677) * 0.0009765625);
                    break;
                }
                if (_1676 == 31u)
                {
                    _1669 = _1670 * 65504.0;
                    break;
                }
                _1669 = (_1670 * exp2(float(_1676) - 15.0)) * (1.0 + (float(_1677) * 0.0009765625));
                break;
            } while(false);
            uint _1665 = _1642 >> 16u;
            do
            {
                uint _1720 = (_1665 >> 10u) & 31u;
                uint _1721 = _1665 & 1023u;
                if ((_1665 >> 15u) == 0u)
                {
                    _1714 = 1.0;
                }
                else
                {
                    _1714 = -1.0;
                }
                if (_1720 == 0u)
                {
                    if (_1721 == 0u)
                    {
                        _1713 = 0.0;
                        break;
                    }
                    _1713 = (_1714 * 6.103515625e-05) * (float(_1721) * 0.0009765625);
                    break;
                }
                if (_1720 == 31u)
                {
                    _1713 = _1714 * 65504.0;
                    break;
                }
                _1713 = (_1714 * exp2(float(_1720) - 15.0)) * (1.0 + (float(_1721) * 0.0009765625));
                break;
            } while(false);
            uint _1758 = _1655 & 65535u;
            do
            {
                uint _1771 = (_1758 >> 10u) & 31u;
                uint _1772 = _1655 & 1023u;
                if ((_1758 >> 15u) == 0u)
                {
                    _1765 = 1.0;
                }
                else
                {
                    _1765 = -1.0;
                }
                if (_1771 == 0u)
                {
                    if (_1772 == 0u)
                    {
                        _1764 = 0.0;
                        break;
                    }
                    _1764 = (_1765 * 6.103515625e-05) * (float(_1772) * 0.0009765625);
                    break;
                }
                if (_1771 == 31u)
                {
                    _1764 = _1765 * 65504.0;
                    break;
                }
                _1764 = (_1765 * exp2(float(_1771) - 15.0)) * (1.0 + (float(_1772) * 0.0009765625));
                break;
            } while(false);
            uint _1760 = _1655 >> 16u;
            do
            {
                uint _1815 = (_1760 >> 10u) & 31u;
                uint _1816 = _1760 & 1023u;
                if ((_1760 >> 15u) == 0u)
                {
                    _1809 = 1.0;
                }
                else
                {
                    _1809 = -1.0;
                }
                if (_1815 == 0u)
                {
                    if (_1816 == 0u)
                    {
                        _1808 = 0.0;
                        break;
                    }
                    _1808 = (_1809 * 6.103515625e-05) * (float(_1816) * 0.0009765625);
                    break;
                }
                if (_1815 == 31u)
                {
                    _1808 = _1809 * 65504.0;
                    break;
                }
                _1808 = (_1809 * exp2(float(_1815) - 15.0)) * (1.0 + (float(_1816) * 0.0009765625));
                break;
            } while(false);
            highp vec4 _1660 = vec4(vec2(_1669, _1713), vec2(_1764, _1808));
            int _1854 = (_1446 * pc.words_per_glyph) + 2;
            int _1867 = (_1446 * pc.words_per_glyph) + 3;
            int _1880 = (_1446 * pc.words_per_glyph) + 4;
            int _1893 = (_1446 * pc.words_per_glyph) + 5;
            highp vec4 _1601 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1854 - 1024 * (_1854 / 1024), _1854 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1867 - 1024 * (_1867 / 1024), _1867 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1880 - 1024 * (_1880 / 1024), _1880 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1893 - 1024 * (_1893 / 1024), _1893 / 1024), 0).x));
            int _1906 = (_1446 * pc.words_per_glyph) + 6;
            int _1919 = (_1446 * pc.words_per_glyph) + 7;
            int _1932 = (_1446 * pc.words_per_glyph) + 8;
            int _1945 = (_1446 * pc.words_per_glyph) + 9;
            uvec2 _1611 = uvec2(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1932 - 1024 * (_1932 / 1024), _1932 / 1024), 0).x, texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1945 - 1024 * (_1945 / 1024), _1945 / 1024), 0).x);
            int _1958 = (_1446 * pc.words_per_glyph) + 10;
            int _1971 = (_1446 * pc.words_per_glyph) + 11;
            int _1984 = (_1446 * pc.words_per_glyph) + 12;
            int _1997 = (_1446 * pc.words_per_glyph) + 13;
            highp vec4 _1621 = vec4(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1958 - 1024 * (_1958 / 1024), _1958 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1971 - 1024 * (_1971 / 1024), _1971 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1984 - 1024 * (_1984 / 1024), _1984 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1997 - 1024 * (_1997 / 1024), _1997 / 1024), 0).x));
            int _2010 = (_1446 * pc.words_per_glyph) + 14;
            uvec4 _2018 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2010 - 1024 * (_2010 / 1024), _2010 / 1024), 0);
            uint _2019 = _2018.x;
            highp vec4 _2035 = vec4(float(_2019 & 255u), float((_2019 >> 8u) & 255u), float((_2019 >> 16u) & 255u), float((_2019 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            int _2039 = (_1446 * pc.words_per_glyph) + 15;
            uvec4 _2047 = texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_2039 - 1024 * (_2039 / 1024), _2039 / 1024), 0);
            uint _2048 = _2047.x;
            highp vec4 _2064 = vec4(float(_2048 & 255u), float((_2048 >> 8u) & 255u), float((_2048 >> 16u) & 255u), float((_2048 >> 24u) & 255u)) * vec4(0.0039215688593685626983642578125);
            if (abs((_1601.x * _1601.w) - (_1601.y * _1601.z)) < 1.0000000133514319600180897396058e-10)
            {
                break;
            }
            highp float _2067 = _1601.x;
            highp float _2068 = _1601.w;
            highp float _2070 = _1601.y;
            highp float _2071 = _1601.z;
            highp float _2073 = (_2067 * _2068) - (_2070 * _2071);
            highp vec2 _2074 = snail_io0 - vec2(uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1906 - 1024 * (_1906 / 1024), _1906 / 1024), 0).x), uintBitsToFloat(texelFetch(SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler, ivec2(_1919 - 1024 * (_1919 / 1024), _1919 / 1024), 0).x));
            highp float _2075 = _2074.x;
            highp float _2077 = _2074.y;
            highp vec2 _2086 = vec2(((_2068 * _2075) - (_2070 * _2077)) / _2073, (((-_2071) * _2075) + (_2067 * _2077)) / _2073);
            highp float _2089 = _1601.x;
            highp float _2090 = _1601.w;
            highp float _2092 = _1601.y;
            highp float _2093 = _1601.z;
            highp float _2095 = (_2089 * _2090) - (_2092 * _2093);
            highp float _2096 = _1441.x;
            highp float _2098 = _1441.y;
            highp float _2110 = _1601.x;
            highp float _2111 = _1601.w;
            highp float _2113 = _1601.y;
            highp float _2114 = _1601.z;
            highp float _2116 = (_2110 * _2111) - (_2113 * _2114);
            highp float _2117 = _1444.x;
            highp float _2119 = _1444.y;
            highp vec2 _1480 = abs(vec2(((_2090 * _2096) - (_2092 * _2098)) / _2095, (((-_2093) * _2096) + (_2089 * _2098)) / _2095)) + abs(vec2(((_2111 * _2117) - (_2113 * _2119)) / _2116, (((-_2114) * _2117) + (_2110 * _2119)) / _2116));
            highp vec2 _1482 = max(_1480 * 2.0, vec2(0.001000000047497451305389404296875));
            highp float _1483 = _2086.x;
            highp float _1486 = _1482.x;
            if (_1483 < (_1660.x - _1486))
            {
                _1447 = true;
            }
            else
            {
                _1447 = _1483 > (_1660.z + _1486);
            }
            if (_1447)
            {
                _1448 = true;
            }
            else
            {
                _1448 = _2086.y < (_1660.y - _1482.y);
            }
            if (_1448)
            {
                _1449 = true;
            }
            else
            {
                _1449 = _2086.y > (_1660.w + _1482.y);
            }
            if (_1449)
            {
                break;
            }
            uint _1517 = _1611.x;
            uint _1518 = _1611.y;
            int _1521 = int((_1518 >> 24u) & 255u);
            if (_1521 == 255)
            {
                break;
            }
            int _1525 = pc.layer_base + _1521;
            int _1527 = int(_1517 & 65535u);
            int _1529 = int(_1517 >> 16u);
            int _1533 = int((_1518 >> 16u) & 255u);
            int _1535 = int(_1518 & 65535u);
            highp float _1539 = 1.0 / max(_1480.x, 1.52587890625e-05);
            highp float _1542 = 1.0 / max(_1480.y, 1.52587890625e-05);
            highp float _2140 = _1621.y;
            highp float _2313 = (_2086.y * _2140) + _1621.w;
            highp float _2317 = max(abs(_1480.y * _2140) * 0.5, 9.9999997473787516355514526367188e-06);
            int _2320 = clamp(int(_2313 - _2317), 0, _1535);
            int _2324 = max(_2320, clamp(int(_2313 + _2317), 0, _1535));
            highp float _2146 = _1621.x;
            highp float _2335 = (_2086.x * _2146) + _1621.z;
            highp float _2339 = max(abs(_1480.x * _2146) * 0.5, 9.9999997473787516355514526367188e-06);
            int _2342 = clamp(int(_2335 - _2339), 0, _1533);
            int _2346 = max(_2342, clamp(int(_2335 + _2339), 0, _1533));
            highp float _2129 = 0.0;
            highp float _2130 = 0.0;
            bool _2152 = _2320 != _2324;
            int _2131 = _2320;
            for (;;)
            {
                if (!(_2131 <= _2324))
                {
                    break;
                }
                int _2359 = _1527 + _2131;
                ivec2 _2361 = ivec2(_2359, _1529);
                _2361.y = _2361.y + (_2359 >> 12);
                _2361.x = _2361.x & 4095;
                uvec4 _2167 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2361, _1525, 0).xyz, 0);
                int _2375 = _1527 + int(_2167.y);
                ivec2 _2377 = ivec2(_2375, _1529);
                _2377.y = _2377.y + (_2375 >> 12);
                _2377.x = _2377.x & 4095;
                int _2174 = int(_2167.x);
                _2132 = 0;
                for (;;)
                {
                    bool _2177_ladder_break = false;
                    do
                    {
                        if (!(_2132 < _2174))
                        {
                            _2177_ladder_break = true;
                            break;
                        }
                        int _2391 = _2377.x + _2132;
                        ivec2 _2393 = ivec2(_2391, _2377.y);
                        _2393.y = _2393.y + (_2391 >> 12);
                        _2393.x = _2393.x & 4095;
                        uvec4 _2189 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2393, _1525, 0).xyz, 0);
                        if (_2152)
                        {
                            _2133 = !(_2131 == max(int(_2189.x >> 12u), _2320));
                        }
                        else
                        {
                            _2133 = false;
                        }
                        if (_2133)
                        {
                            break;
                        }
                        ivec2 _2423 = ivec2(int(_2189.x & 4095u), int(_2189.y & 16383u));
                        do
                        {
                            highp vec4 _2432 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2423, _1525, 0).xyz, 0);
                            int _2501 = _2423.x + 1;
                            ivec2 _2503 = ivec2(_2501, _2423.y);
                            _2503.y = _2503.y + (_2501 >> 12);
                            _2503.x = _2503.x & 4095;
                            highp vec4 _2444 = vec4(_2432.xy, _2432.zw) - vec4(_2086, _2086);
                            highp vec2 _2446 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2503, _1525, 0).xyz, 0).xy - _2086;
                            if ((max(max(_2444.x, _2444.z), _2446.x) * _1539) < (-0.5))
                            {
                                _2425 = false;
                                break;
                            }
                            highp float _2457 = _2444.y;
                            highp float _2458 = _2444.w;
                            highp float _2459 = _2446.y;
                            if (abs(_2457) <= 1.52587890625e-05)
                            {
                                _2531 = 0.0;
                            }
                            else
                            {
                                _2531 = _2457;
                            }
                            if (abs(_2458) <= 1.52587890625e-05)
                            {
                                _2540 = 0.0;
                            }
                            else
                            {
                                _2540 = _2458;
                            }
                            if (abs(_2459) <= 1.52587890625e-05)
                            {
                                _2549 = 0.0;
                            }
                            else
                            {
                                _2549 = _2459;
                            }
                            uint _2530 = (11892u >> (((floatBitsToUint(_2549) >> 29u) & 4u) | ((((floatBitsToUint(_2540) >> 30u) & 2u) | ((floatBitsToUint(_2531) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_2530 != 0u)
                            {
                                highp vec2 _2562 = _2444.xy;
                                highp vec2 _2563 = _2444.zw;
                                highp vec2 _2566 = (_2562 - (_2563 * 2.0)) + _2446;
                                highp vec2 _2567 = _2562 - _2563;
                                highp float _2568 = _2566.y;
                                if (abs(_2568) < 1.52587890625e-05)
                                {
                                    highp float _2600 = _2567.y;
                                    if (abs(_2600) < 1.52587890625e-05)
                                    {
                                        _2558 = 0.0;
                                    }
                                    else
                                    {
                                        _2558 = (_2444.y * 0.5) / _2600;
                                    }
                                    _2559 = _2558;
                                }
                                else
                                {
                                    highp float _2572 = _2567.y;
                                    highp float _2574 = _2444.y;
                                    highp float _2575 = _2568 * _2574;
                                    highp float _2576 = (_2572 * _2572) - _2575;
                                    if (_2576 <= (max(_2572 * _2572, abs(_2575)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _2628 = 0.0;
                                    }
                                    else
                                    {
                                        _2628 = sqrt(_2576);
                                    }
                                    if (_2572 >= 0.0)
                                    {
                                        highp float _2590 = _2572 + _2628;
                                        if (abs(_2590) < 1.52587890625e-05)
                                        {
                                            _2558 = 0.0;
                                        }
                                        else
                                        {
                                            _2558 = _2574 / _2590;
                                        }
                                        _2559 = _2590 / _2568;
                                    }
                                    else
                                    {
                                        highp float _2580 = _2572 - _2628;
                                        if (abs(_2580) < 1.52587890625e-05)
                                        {
                                            _2558 = 0.0;
                                        }
                                        else
                                        {
                                            _2558 = _2574 / _2580;
                                        }
                                        highp float _2588 = _2558;
                                        _2558 = _2580 / _2568;
                                        _2559 = _2588;
                                    }
                                }
                                highp float _2611 = _2566.x;
                                highp float _2615 = _2567.x * 2.0;
                                highp float _2619 = _2444.x;
                                highp vec2 _2464 = vec2((((_2611 * _2558) - _2615) * _2558) + _2619, (((_2611 * _2559) - _2615) * _2559) + _2619) * _1539;
                                if ((_2530 & 1u) != 0u)
                                {
                                    highp float _2468 = _2464.x;
                                    _2129 += clamp(_2468 + 0.5, 0.0, 1.0);
                                    _2130 = max(_2130, clamp(1.0 - (abs(_2468) * 2.0), 0.0, 1.0));
                                }
                                if (_2530 > 1u)
                                {
                                    highp float _2482 = _2464.y;
                                    _2129 -= clamp(_2482 + 0.5, 0.0, 1.0);
                                    _2130 = max(_2130, clamp(1.0 - (abs(_2482) * 2.0), 0.0, 1.0));
                                }
                            }
                            _2425 = true;
                            break;
                        } while(false);
                        if (!_2425)
                        {
                            _2177_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_2177_ladder_break)
                    {
                        break;
                    }
                    _2132++;
                    continue;
                }
                _2131++;
                continue;
            }
            highp float _2134 = 0.0;
            highp float _2135 = 0.0;
            bool _2221 = _2342 != _2346;
            _2131 = _2342;
            for (;;)
            {
                if (!(_2131 <= _2346))
                {
                    break;
                }
                int _2646 = _1527 + ((_1535 + 1) + _2131);
                ivec2 _2648 = ivec2(_2646, _1529);
                _2648.y = _2648.y + (_2646 >> 12);
                _2648.x = _2648.x & 4095;
                uvec4 _2238 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2648, _1525, 0).xyz, 0);
                int _2662 = _1527 + int(_2238.y);
                ivec2 _2664 = ivec2(_2662, _1529);
                _2664.y = _2664.y + (_2662 >> 12);
                _2664.x = _2664.x & 4095;
                int _2245 = int(_2238.x);
                _2132 = 0;
                for (;;)
                {
                    bool _2248_ladder_break = false;
                    do
                    {
                        if (!(_2132 < _2245))
                        {
                            _2248_ladder_break = true;
                            break;
                        }
                        int _2678 = _2664.x + _2132;
                        ivec2 _2680 = ivec2(_2678, _2664.y);
                        _2680.y = _2680.y + (_2678 >> 12);
                        _2680.x = _2680.x & 4095;
                        uvec4 _2260 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2680, _1525, 0).xyz, 0);
                        if (_2221)
                        {
                            _2133 = !(_2131 == max(int(_2260.x >> 12u), _2342));
                        }
                        else
                        {
                            _2133 = false;
                        }
                        if (_2133)
                        {
                            break;
                        }
                        ivec2 _2710 = ivec2(int(_2260.x & 4095u), int(_2260.y & 16383u));
                        do
                        {
                            highp vec4 _2719 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2710, _1525, 0).xyz, 0);
                            int _2788 = _2710.x + 1;
                            ivec2 _2790 = ivec2(_2788, _2710.y);
                            _2790.y = _2790.y + (_2788 >> 12);
                            _2790.x = _2790.x & 4095;
                            highp vec4 _2731 = vec4(_2719.xy, _2719.zw) - vec4(_2086, _2086);
                            highp vec2 _2733 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2790, _1525, 0).xyz, 0).xy - _2086;
                            if ((max(max(_2731.y, _2731.w), _2733.y) * _1542) < (-0.5))
                            {
                                _2712 = false;
                                break;
                            }
                            highp float _2744 = _2731.x;
                            highp float _2745 = _2731.z;
                            highp float _2746 = _2733.x;
                            if (abs(_2744) <= 1.52587890625e-05)
                            {
                                _2818 = 0.0;
                            }
                            else
                            {
                                _2818 = _2744;
                            }
                            if (abs(_2745) <= 1.52587890625e-05)
                            {
                                _2827 = 0.0;
                            }
                            else
                            {
                                _2827 = _2745;
                            }
                            if (abs(_2746) <= 1.52587890625e-05)
                            {
                                _2836 = 0.0;
                            }
                            else
                            {
                                _2836 = _2746;
                            }
                            uint _2817 = (11892u >> (((floatBitsToUint(_2836) >> 29u) & 4u) | ((((floatBitsToUint(_2827) >> 30u) & 2u) | ((floatBitsToUint(_2818) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                            if (_2817 != 0u)
                            {
                                highp vec2 _2849 = _2731.xy;
                                highp vec2 _2850 = _2731.zw;
                                highp vec2 _2853 = (_2849 - (_2850 * 2.0)) + _2733;
                                highp vec2 _2854 = _2849 - _2850;
                                highp float _2855 = _2853.x;
                                if (abs(_2855) < 1.52587890625e-05)
                                {
                                    highp float _2887 = _2854.x;
                                    if (abs(_2887) < 1.52587890625e-05)
                                    {
                                        _2845 = 0.0;
                                    }
                                    else
                                    {
                                        _2845 = (_2731.x * 0.5) / _2887;
                                    }
                                    _2846 = _2845;
                                }
                                else
                                {
                                    highp float _2859 = _2854.x;
                                    highp float _2861 = _2731.x;
                                    highp float _2862 = _2855 * _2861;
                                    highp float _2863 = (_2859 * _2859) - _2862;
                                    if (_2863 <= (max(_2859 * _2859, abs(_2862)) * 3.0000001061125658452510833740234e-06))
                                    {
                                        _2915 = 0.0;
                                    }
                                    else
                                    {
                                        _2915 = sqrt(_2863);
                                    }
                                    if (_2859 >= 0.0)
                                    {
                                        highp float _2877 = _2859 + _2915;
                                        if (abs(_2877) < 1.52587890625e-05)
                                        {
                                            _2845 = 0.0;
                                        }
                                        else
                                        {
                                            _2845 = _2861 / _2877;
                                        }
                                        _2846 = _2877 / _2855;
                                    }
                                    else
                                    {
                                        highp float _2867 = _2859 - _2915;
                                        if (abs(_2867) < 1.52587890625e-05)
                                        {
                                            _2845 = 0.0;
                                        }
                                        else
                                        {
                                            _2845 = _2861 / _2867;
                                        }
                                        highp float _2875 = _2845;
                                        _2845 = _2867 / _2855;
                                        _2846 = _2875;
                                    }
                                }
                                highp float _2898 = _2853.y;
                                highp float _2902 = _2854.y * 2.0;
                                highp float _2906 = _2731.y;
                                highp vec2 _2751 = vec2((((_2898 * _2845) - _2902) * _2845) + _2906, (((_2898 * _2846) - _2902) * _2846) + _2906) * _1542;
                                if ((_2817 & 1u) != 0u)
                                {
                                    highp float _2755 = _2751.x;
                                    _2134 -= clamp(_2755 + 0.5, 0.0, 1.0);
                                    _2135 = max(_2135, clamp(1.0 - (abs(_2755) * 2.0), 0.0, 1.0));
                                }
                                if (_2817 > 1u)
                                {
                                    highp float _2769 = _2751.y;
                                    _2134 += clamp(_2769 + 0.5, 0.0, 1.0);
                                    _2135 = max(_2135, clamp(1.0 - (abs(_2769) * 2.0), 0.0, 1.0));
                                }
                            }
                            _2712 = true;
                            break;
                        } while(false);
                        if (!_2712)
                        {
                            _2248_ladder_break = true;
                            break;
                        }
                        break;
                    } while(false);
                    if (_2248_ladder_break)
                    {
                        break;
                    }
                    _2132++;
                    continue;
                }
                _2131++;
                continue;
            }
            highp float _2301 = ((_2129 * _2130) + (_2134 * _2135)) / max(_2130 + _2135, 1.52587890625e-05);
            do
            {
                if (false)
                {
                    _2929 = 1.0 - abs((fract(_2301 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _2929 = abs(_2301);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _2946 = 1.0 - abs((fract(_2129 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _2946 = abs(_2129);
                break;
            } while(false);
            do
            {
                if (false)
                {
                    _2963 = 1.0 - abs((fract(_2134 * 0.5) * 2.0) - 1.0);
                    break;
                }
                _2963 = abs(_2134);
                break;
            } while(false);
            highp float _2982 = clamp(max(_2929, min(_2946, _2963)), 0.0, 1.0);
            highp float _2983 = max(pc.coverage_exponent, 1.52587890625e-05);
            if (abs(_2983 - 1.0) <= 9.9999999747524270787835121154785e-07)
            {
                _2979 = _2982;
            }
            else
            {
                _2979 = pow(_2982, _2983);
            }
            highp float _1552 = clamp((_2979 * _2035.w) * _2064.w, 0.0, 1.0);
            if (_1552 <= 0.0039215688593685626983642578125)
            {
                break;
            }
            highp float _2995 = _2035.x;
            if (_2995 <= 0.040449999272823333740234375)
            {
                _3002 = _2995 * 0.077399380505084991455078125;
            }
            else
            {
                _3002 = pow((_2995 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _2997 = _2035.y;
            if (_2997 <= 0.040449999272823333740234375)
            {
                _3014 = _2997 * 0.077399380505084991455078125;
            }
            else
            {
                _3014 = pow((_2997 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _2999 = _2035.z;
            if (_2999 <= 0.040449999272823333740234375)
            {
                _3026 = _2999 * 0.077399380505084991455078125;
            }
            else
            {
                _3026 = pow((_2999 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _3040 = _2064.x;
            if (_3040 <= 0.040449999272823333740234375)
            {
                _3047 = _3040 * 0.077399380505084991455078125;
            }
            else
            {
                _3047 = pow((_3040 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _3042 = _2064.y;
            if (_3042 <= 0.040449999272823333740234375)
            {
                _3059 = _3042 * 0.077399380505084991455078125;
            }
            else
            {
                _3059 = pow((_3042 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp float _3044 = _2064.z;
            if (_3044 <= 0.040449999272823333740234375)
            {
                _3071 = _3044 * 0.077399380505084991455078125;
            }
            else
            {
                _3071 = pow((_3044 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
            }
            highp vec4 _1562 = _1445;
            highp float _1564 = 1.0 - _1552;
            highp vec3 _1566 = ((vec3(_3002, _3014, _3026) * vec3(_3047, _3059, _3071)) * _1552) + (_1562.xyz * _1564);
            highp vec4 _3214 = _1562;
            _3214.x = _1566.x;
            _3214.y = _1566.y;
            _3214.z = _1566.z;
            _3214.w = _1552 + (_3214.w * _1564);
            _1445 = _3214;
            break;
        } while(false);
        if (_1454_ladder_break)
        {
            break;
        }
        _1446++;
        continue;
    }
    entryPointParam_fragmentMain = _1445;
}


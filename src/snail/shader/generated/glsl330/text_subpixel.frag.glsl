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

uniform usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in vec4 snail_io0;
in vec4 snail_io4;
in vec2 snail_io1;
flat in vec4 snail_io2;
flat in ivec4 snail_io3;
layout(location = 0) out vec4 entryPointParam_fragmentMain_color;
layout(location = 0, index = 1) out vec4 entryPointParam_fragmentMain_blend;

void main()
{
    vec4 _7925 = snail_io0;
    vec4 _7926 = snail_io4;
    vec2 _7927 = snail_io1;
    vec4 _7928 = snail_io2;
    ivec4 _7929 = snail_io3;
    vec4 _7873;
    vec4 _7874;
    bool _7875;
    do
    {
        vec4 _7889 = vec4(0.0);
        vec4 _7890 = vec4(0.0);
        bool _7891 = false;
        int _1321 = (_7929.w >> 8) & 255;
        if (_1321 == 255)
        {
            _7891 = true;
            _7873 = _7889;
            _7874 = _7890;
            _7875 = true;
            break;
        }
        int _1326 = pc.layer_base + _1321;
        int _1329 = _7929.w & 255;
        vec2 _1418 = dFdx(_7927);
        vec2 _1421 = dFdy(_7927);
        vec2 _1376;
        if (pc.subpixel_order <= 2)
        {
            _1376 = _1418;
        }
        else
        {
            _1376 = _1421;
        }
        vec2 _1387 = _1376 * 0.3333333432674407958984375;
        vec2 _1425 = abs(_1418);
        vec2 _1426 = abs(_1421);
        vec2 _1422;
        if (pc.subpixel_order <= 2)
        {
            _1422 = (_1425 * 0.3333333432674407958984375) + _1426;
        }
        else
        {
            _1422 = _1425 + (_1426 * 0.3333333432674407958984375);
        }
        vec2 _1389 = _1387 * 3.0;
        vec2 _1390 = _7927 - _1389;
        vec2 _1391 = _1387 * 2.0;
        vec2 _1392 = _7927 - _1391;
        vec2 _1393 = _7927 - _1387;
        vec2 _1394 = _7927 + _1387;
        vec2 _1395 = _7927 + _1391;
        vec2 _1396 = _7927 + _1389;
        float _1440 = 1.0 / max(_1422.x, 1.52587890625e-05);
        float _1443 = 1.0 / max(_1422.y, 1.52587890625e-05);
        float _1630 = (_1390.y * _7928.y) + _7928.w;
        float _1634 = max(abs(_1422.y * _7928.y) * 0.5, 9.9999997473787516355514526367188e-06);
        int _1637 = clamp(int(_1630 - _1634), 0, _7929.z);
        int _1641 = max(_1637, clamp(int(_1630 + _1634), 0, _7929.z));
        float _1652 = (_1390.x * _7928.x) + _7928.z;
        float _1656 = max(abs(_1422.x * _7928.x) * 0.5, 9.9999997473787516355514526367188e-06);
        int _1659 = clamp(int(_1652 - _1656), 0, _1329);
        int _1663 = max(_1659, clamp(int(_1652 + _1656), 0, _1329));
        float _1446 = 0.0;
        float _1447 = 0.0;
        bool _1469 = _1637 != _1641;
        int _1448 = _1637;
        int _1449;
        bool _1450;
        bool _1742;
        float _1849;
        float _1858;
        float _1867;
        float _1876;
        float _1877;
        float _1946;
        for (;;)
        {
            if (!(_1448 <= _1641))
            {
                break;
            }
            int _1676 = _7929.x + _1448;
            ivec2 _1678 = ivec2(_1676, _7929.y);
            _1678.y = _1678.y + (_1676 >> 12);
            _1678.x = _1678.x & 4095;
            uvec4 _1484 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1678, _1326, 0).xyz, 0);
            int _1692 = _7929.x + int(_1484.y);
            ivec2 _1694 = ivec2(_1692, _7929.y);
            _1694.y = _1694.y + (_1692 >> 12);
            _1694.x = _1694.x & 4095;
            int _1491 = int(_1484.x);
            _1449 = 0;
            for (;;)
            {
                bool _1494_ladder_break = false;
                do
                {
                    if (!(_1449 < _1491))
                    {
                        _1494_ladder_break = true;
                        break;
                    }
                    int _1708 = _1694.x + _1449;
                    ivec2 _1710 = ivec2(_1708, _1694.y);
                    _1710.y = _1710.y + (_1708 >> 12);
                    _1710.x = _1710.x & 4095;
                    uvec4 _1506 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1710, _1326, 0).xyz, 0);
                    if (_1469)
                    {
                        _1450 = !(_1448 == max(int(_1506.x >> 12u), _1637));
                    }
                    else
                    {
                        _1450 = false;
                    }
                    if (_1450)
                    {
                        break;
                    }
                    ivec2 _1740 = ivec2(int(_1506.x & 4095u), int(_1506.y & 16383u));
                    do
                    {
                        vec4 _1749 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1740, _1326, 0).xyz, 0);
                        int _1818 = _1740.x + 1;
                        ivec2 _1820 = ivec2(_1818, _1740.y);
                        _1820.y = _1820.y + (_1818 >> 12);
                        _1820.x = _1820.x & 4095;
                        vec4 _1761 = vec4(_1749.xy, _1749.zw) - vec4(_1390, _1390);
                        vec2 _1763 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1820, _1326, 0).xyz, 0).xy - _1390;
                        if ((max(max(_1761.x, _1761.z), _1763.x) * _1440) < (-0.5))
                        {
                            _1742 = false;
                            break;
                        }
                        float _1774 = _1761.y;
                        float _1775 = _1761.w;
                        float _1776 = _1763.y;
                        if (abs(_1774) <= 1.52587890625e-05)
                        {
                            _1849 = 0.0;
                        }
                        else
                        {
                            _1849 = _1774;
                        }
                        if (abs(_1775) <= 1.52587890625e-05)
                        {
                            _1858 = 0.0;
                        }
                        else
                        {
                            _1858 = _1775;
                        }
                        if (abs(_1776) <= 1.52587890625e-05)
                        {
                            _1867 = 0.0;
                        }
                        else
                        {
                            _1867 = _1776;
                        }
                        uint _1848 = (11892u >> (((floatBitsToUint(_1867) >> 29u) & 4u) | ((((floatBitsToUint(_1858) >> 30u) & 2u) | ((floatBitsToUint(_1849) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_1848 != 0u)
                        {
                            vec2 _1880 = _1761.xy;
                            vec2 _1881 = _1761.zw;
                            vec2 _1884 = (_1880 - (_1881 * 2.0)) + _1763;
                            vec2 _1885 = _1880 - _1881;
                            float _1886 = _1884.y;
                            if (abs(_1886) < 1.52587890625e-05)
                            {
                                float _1918 = _1885.y;
                                if (abs(_1918) < 1.52587890625e-05)
                                {
                                    _1876 = 0.0;
                                }
                                else
                                {
                                    _1876 = (_1761.y * 0.5) / _1918;
                                }
                                _1877 = _1876;
                            }
                            else
                            {
                                float _1890 = _1885.y;
                                float _1892 = _1761.y;
                                float _1893 = _1886 * _1892;
                                float _1894 = (_1890 * _1890) - _1893;
                                if (_1894 <= (max(_1890 * _1890, abs(_1893)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _1946 = 0.0;
                                }
                                else
                                {
                                    _1946 = sqrt(_1894);
                                }
                                if (_1890 >= 0.0)
                                {
                                    float _1908 = _1890 + _1946;
                                    if (abs(_1908) < 1.52587890625e-05)
                                    {
                                        _1876 = 0.0;
                                    }
                                    else
                                    {
                                        _1876 = _1892 / _1908;
                                    }
                                    _1877 = _1908 / _1886;
                                }
                                else
                                {
                                    float _1898 = _1890 - _1946;
                                    if (abs(_1898) < 1.52587890625e-05)
                                    {
                                        _1876 = 0.0;
                                    }
                                    else
                                    {
                                        _1876 = _1892 / _1898;
                                    }
                                    float _1906 = _1876;
                                    _1876 = _1898 / _1886;
                                    _1877 = _1906;
                                }
                            }
                            float _1929 = _1884.x;
                            float _1933 = _1885.x * 2.0;
                            float _1937 = _1761.x;
                            vec2 _1781 = vec2((((_1929 * _1876) - _1933) * _1876) + _1937, (((_1929 * _1877) - _1933) * _1877) + _1937) * _1440;
                            if ((_1848 & 1u) != 0u)
                            {
                                float _1785 = _1781.x;
                                _1446 += clamp(_1785 + 0.5, 0.0, 1.0);
                                _1447 = max(_1447, clamp(1.0 - (abs(_1785) * 2.0), 0.0, 1.0));
                            }
                            if (_1848 > 1u)
                            {
                                float _1799 = _1781.y;
                                _1446 -= clamp(_1799 + 0.5, 0.0, 1.0);
                                _1447 = max(_1447, clamp(1.0 - (abs(_1799) * 2.0), 0.0, 1.0));
                            }
                        }
                        _1742 = true;
                        break;
                    } while(false);
                    if (!_1742)
                    {
                        _1494_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_1494_ladder_break)
                {
                    break;
                }
                _1449++;
                continue;
            }
            _1448++;
            continue;
        }
        float _1451 = 0.0;
        float _1452 = 0.0;
        bool _1538 = _1659 != _1663;
        _1448 = _1659;
        bool _2030;
        float _2136;
        float _2145;
        float _2154;
        float _2163;
        float _2164;
        float _2233;
        for (;;)
        {
            if (!(_1448 <= _1663))
            {
                break;
            }
            int _1964 = _7929.x + ((_7929.z + 1) + _1448);
            ivec2 _1966 = ivec2(_1964, _7929.y);
            _1966.y = _1966.y + (_1964 >> 12);
            _1966.x = _1966.x & 4095;
            uvec4 _1555 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1966, _1326, 0).xyz, 0);
            int _1980 = _7929.x + int(_1555.y);
            ivec2 _1982 = ivec2(_1980, _7929.y);
            _1982.y = _1982.y + (_1980 >> 12);
            _1982.x = _1982.x & 4095;
            int _1562 = int(_1555.x);
            _1449 = 0;
            for (;;)
            {
                bool _1565_ladder_break = false;
                do
                {
                    if (!(_1449 < _1562))
                    {
                        _1565_ladder_break = true;
                        break;
                    }
                    int _1996 = _1982.x + _1449;
                    ivec2 _1998 = ivec2(_1996, _1982.y);
                    _1998.y = _1998.y + (_1996 >> 12);
                    _1998.x = _1998.x & 4095;
                    uvec4 _1577 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1998, _1326, 0).xyz, 0);
                    if (_1538)
                    {
                        _1450 = !(_1448 == max(int(_1577.x >> 12u), _1659));
                    }
                    else
                    {
                        _1450 = false;
                    }
                    if (_1450)
                    {
                        break;
                    }
                    ivec2 _2028 = ivec2(int(_1577.x & 4095u), int(_1577.y & 16383u));
                    do
                    {
                        vec4 _2037 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2028, _1326, 0).xyz, 0);
                        int _2106 = _2028.x + 1;
                        ivec2 _2108 = ivec2(_2106, _2028.y);
                        _2108.y = _2108.y + (_2106 >> 12);
                        _2108.x = _2108.x & 4095;
                        vec4 _2049 = vec4(_2037.xy, _2037.zw) - vec4(_1390, _1390);
                        vec2 _2051 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2108, _1326, 0).xyz, 0).xy - _1390;
                        if ((max(max(_2049.y, _2049.w), _2051.y) * _1443) < (-0.5))
                        {
                            _2030 = false;
                            break;
                        }
                        float _2062 = _2049.x;
                        float _2063 = _2049.z;
                        float _2064 = _2051.x;
                        if (abs(_2062) <= 1.52587890625e-05)
                        {
                            _2136 = 0.0;
                        }
                        else
                        {
                            _2136 = _2062;
                        }
                        if (abs(_2063) <= 1.52587890625e-05)
                        {
                            _2145 = 0.0;
                        }
                        else
                        {
                            _2145 = _2063;
                        }
                        if (abs(_2064) <= 1.52587890625e-05)
                        {
                            _2154 = 0.0;
                        }
                        else
                        {
                            _2154 = _2064;
                        }
                        uint _2135 = (11892u >> (((floatBitsToUint(_2154) >> 29u) & 4u) | ((((floatBitsToUint(_2145) >> 30u) & 2u) | ((floatBitsToUint(_2136) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_2135 != 0u)
                        {
                            vec2 _2167 = _2049.xy;
                            vec2 _2168 = _2049.zw;
                            vec2 _2171 = (_2167 - (_2168 * 2.0)) + _2051;
                            vec2 _2172 = _2167 - _2168;
                            float _2173 = _2171.x;
                            if (abs(_2173) < 1.52587890625e-05)
                            {
                                float _2205 = _2172.x;
                                if (abs(_2205) < 1.52587890625e-05)
                                {
                                    _2163 = 0.0;
                                }
                                else
                                {
                                    _2163 = (_2049.x * 0.5) / _2205;
                                }
                                _2164 = _2163;
                            }
                            else
                            {
                                float _2177 = _2172.x;
                                float _2179 = _2049.x;
                                float _2180 = _2173 * _2179;
                                float _2181 = (_2177 * _2177) - _2180;
                                if (_2181 <= (max(_2177 * _2177, abs(_2180)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _2233 = 0.0;
                                }
                                else
                                {
                                    _2233 = sqrt(_2181);
                                }
                                if (_2177 >= 0.0)
                                {
                                    float _2195 = _2177 + _2233;
                                    if (abs(_2195) < 1.52587890625e-05)
                                    {
                                        _2163 = 0.0;
                                    }
                                    else
                                    {
                                        _2163 = _2179 / _2195;
                                    }
                                    _2164 = _2195 / _2173;
                                }
                                else
                                {
                                    float _2185 = _2177 - _2233;
                                    if (abs(_2185) < 1.52587890625e-05)
                                    {
                                        _2163 = 0.0;
                                    }
                                    else
                                    {
                                        _2163 = _2179 / _2185;
                                    }
                                    float _2193 = _2163;
                                    _2163 = _2185 / _2173;
                                    _2164 = _2193;
                                }
                            }
                            float _2216 = _2171.y;
                            float _2220 = _2172.y * 2.0;
                            float _2224 = _2049.y;
                            vec2 _2069 = vec2((((_2216 * _2163) - _2220) * _2163) + _2224, (((_2216 * _2164) - _2220) * _2164) + _2224) * _1443;
                            if ((_2135 & 1u) != 0u)
                            {
                                float _2073 = _2069.x;
                                _1451 -= clamp(_2073 + 0.5, 0.0, 1.0);
                                _1452 = max(_1452, clamp(1.0 - (abs(_2073) * 2.0), 0.0, 1.0));
                            }
                            if (_2135 > 1u)
                            {
                                float _2087 = _2069.y;
                                _1451 += clamp(_2087 + 0.5, 0.0, 1.0);
                                _1452 = max(_1452, clamp(1.0 - (abs(_2087) * 2.0), 0.0, 1.0));
                            }
                        }
                        _2030 = true;
                        break;
                    } while(false);
                    if (!_2030)
                    {
                        _1565_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_1565_ladder_break)
                {
                    break;
                }
                _1449++;
                continue;
            }
            _1448++;
            continue;
        }
        float _1618 = ((_1446 * _1447) + (_1451 * _1452)) / max(_1447 + _1452, 1.52587890625e-05);
        float _2247;
        do
        {
            if (false)
            {
                _2247 = 1.0 - abs((fract(_1618 * 0.5) * 2.0) - 1.0);
                break;
            }
            _2247 = abs(_1618);
            break;
        } while(false);
        float _2264;
        do
        {
            if (false)
            {
                _2264 = 1.0 - abs((fract(_1446 * 0.5) * 2.0) - 1.0);
                break;
            }
            _2264 = abs(_1446);
            break;
        } while(false);
        float _2281;
        do
        {
            if (false)
            {
                _2281 = 1.0 - abs((fract(_1451 * 0.5) * 2.0) - 1.0);
                break;
            }
            _2281 = abs(_1451);
            break;
        } while(false);
        float _2301 = 1.0 / max(_1422.x, 1.52587890625e-05);
        float _2304 = 1.0 / max(_1422.y, 1.52587890625e-05);
        float _2491 = (_1392.y * _7928.y) + _7928.w;
        float _2495 = max(abs(_1422.y * _7928.y) * 0.5, 9.9999997473787516355514526367188e-06);
        int _2498 = clamp(int(_2491 - _2495), 0, _7929.z);
        int _2502 = max(_2498, clamp(int(_2491 + _2495), 0, _7929.z));
        float _2513 = (_1392.x * _7928.x) + _7928.z;
        float _2517 = max(abs(_1422.x * _7928.x) * 0.5, 9.9999997473787516355514526367188e-06);
        int _2520 = clamp(int(_2513 - _2517), 0, _1329);
        int _2524 = max(_2520, clamp(int(_2513 + _2517), 0, _1329));
        float _2307 = 0.0;
        float _2308 = 0.0;
        bool _2330 = _2498 != _2502;
        int _2309 = _2498;
        int _2310;
        bool _2311;
        bool _2603;
        float _2709;
        float _2718;
        float _2727;
        float _2736;
        float _2737;
        float _2806;
        for (;;)
        {
            if (!(_2309 <= _2502))
            {
                break;
            }
            int _2537 = _7929.x + _2309;
            ivec2 _2539 = ivec2(_2537, _7929.y);
            _2539.y = _2539.y + (_2537 >> 12);
            _2539.x = _2539.x & 4095;
            uvec4 _2345 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2539, _1326, 0).xyz, 0);
            int _2553 = _7929.x + int(_2345.y);
            ivec2 _2555 = ivec2(_2553, _7929.y);
            _2555.y = _2555.y + (_2553 >> 12);
            _2555.x = _2555.x & 4095;
            int _2352 = int(_2345.x);
            _2310 = 0;
            for (;;)
            {
                bool _2355_ladder_break = false;
                do
                {
                    if (!(_2310 < _2352))
                    {
                        _2355_ladder_break = true;
                        break;
                    }
                    int _2569 = _2555.x + _2310;
                    ivec2 _2571 = ivec2(_2569, _2555.y);
                    _2571.y = _2571.y + (_2569 >> 12);
                    _2571.x = _2571.x & 4095;
                    uvec4 _2367 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2571, _1326, 0).xyz, 0);
                    if (_2330)
                    {
                        _2311 = !(_2309 == max(int(_2367.x >> 12u), _2498));
                    }
                    else
                    {
                        _2311 = false;
                    }
                    if (_2311)
                    {
                        break;
                    }
                    ivec2 _2601 = ivec2(int(_2367.x & 4095u), int(_2367.y & 16383u));
                    do
                    {
                        vec4 _2610 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2601, _1326, 0).xyz, 0);
                        int _2679 = _2601.x + 1;
                        ivec2 _2681 = ivec2(_2679, _2601.y);
                        _2681.y = _2681.y + (_2679 >> 12);
                        _2681.x = _2681.x & 4095;
                        vec4 _2622 = vec4(_2610.xy, _2610.zw) - vec4(_1392, _1392);
                        vec2 _2624 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2681, _1326, 0).xyz, 0).xy - _1392;
                        if ((max(max(_2622.x, _2622.z), _2624.x) * _2301) < (-0.5))
                        {
                            _2603 = false;
                            break;
                        }
                        float _2635 = _2622.y;
                        float _2636 = _2622.w;
                        float _2637 = _2624.y;
                        if (abs(_2635) <= 1.52587890625e-05)
                        {
                            _2709 = 0.0;
                        }
                        else
                        {
                            _2709 = _2635;
                        }
                        if (abs(_2636) <= 1.52587890625e-05)
                        {
                            _2718 = 0.0;
                        }
                        else
                        {
                            _2718 = _2636;
                        }
                        if (abs(_2637) <= 1.52587890625e-05)
                        {
                            _2727 = 0.0;
                        }
                        else
                        {
                            _2727 = _2637;
                        }
                        uint _2708 = (11892u >> (((floatBitsToUint(_2727) >> 29u) & 4u) | ((((floatBitsToUint(_2718) >> 30u) & 2u) | ((floatBitsToUint(_2709) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_2708 != 0u)
                        {
                            vec2 _2740 = _2622.xy;
                            vec2 _2741 = _2622.zw;
                            vec2 _2744 = (_2740 - (_2741 * 2.0)) + _2624;
                            vec2 _2745 = _2740 - _2741;
                            float _2746 = _2744.y;
                            if (abs(_2746) < 1.52587890625e-05)
                            {
                                float _2778 = _2745.y;
                                if (abs(_2778) < 1.52587890625e-05)
                                {
                                    _2736 = 0.0;
                                }
                                else
                                {
                                    _2736 = (_2622.y * 0.5) / _2778;
                                }
                                _2737 = _2736;
                            }
                            else
                            {
                                float _2750 = _2745.y;
                                float _2752 = _2622.y;
                                float _2753 = _2746 * _2752;
                                float _2754 = (_2750 * _2750) - _2753;
                                if (_2754 <= (max(_2750 * _2750, abs(_2753)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _2806 = 0.0;
                                }
                                else
                                {
                                    _2806 = sqrt(_2754);
                                }
                                if (_2750 >= 0.0)
                                {
                                    float _2768 = _2750 + _2806;
                                    if (abs(_2768) < 1.52587890625e-05)
                                    {
                                        _2736 = 0.0;
                                    }
                                    else
                                    {
                                        _2736 = _2752 / _2768;
                                    }
                                    _2737 = _2768 / _2746;
                                }
                                else
                                {
                                    float _2758 = _2750 - _2806;
                                    if (abs(_2758) < 1.52587890625e-05)
                                    {
                                        _2736 = 0.0;
                                    }
                                    else
                                    {
                                        _2736 = _2752 / _2758;
                                    }
                                    float _2766 = _2736;
                                    _2736 = _2758 / _2746;
                                    _2737 = _2766;
                                }
                            }
                            float _2789 = _2744.x;
                            float _2793 = _2745.x * 2.0;
                            float _2797 = _2622.x;
                            vec2 _2642 = vec2((((_2789 * _2736) - _2793) * _2736) + _2797, (((_2789 * _2737) - _2793) * _2737) + _2797) * _2301;
                            if ((_2708 & 1u) != 0u)
                            {
                                float _2646 = _2642.x;
                                _2307 += clamp(_2646 + 0.5, 0.0, 1.0);
                                _2308 = max(_2308, clamp(1.0 - (abs(_2646) * 2.0), 0.0, 1.0));
                            }
                            if (_2708 > 1u)
                            {
                                float _2660 = _2642.y;
                                _2307 -= clamp(_2660 + 0.5, 0.0, 1.0);
                                _2308 = max(_2308, clamp(1.0 - (abs(_2660) * 2.0), 0.0, 1.0));
                            }
                        }
                        _2603 = true;
                        break;
                    } while(false);
                    if (!_2603)
                    {
                        _2355_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_2355_ladder_break)
                {
                    break;
                }
                _2310++;
                continue;
            }
            _2309++;
            continue;
        }
        float _2312 = 0.0;
        float _2313 = 0.0;
        bool _2399 = _2520 != _2524;
        _2309 = _2520;
        bool _2890;
        float _2996;
        float _3005;
        float _3014;
        float _3023;
        float _3024;
        float _3093;
        for (;;)
        {
            if (!(_2309 <= _2524))
            {
                break;
            }
            int _2824 = _7929.x + ((_7929.z + 1) + _2309);
            ivec2 _2826 = ivec2(_2824, _7929.y);
            _2826.y = _2826.y + (_2824 >> 12);
            _2826.x = _2826.x & 4095;
            uvec4 _2416 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2826, _1326, 0).xyz, 0);
            int _2840 = _7929.x + int(_2416.y);
            ivec2 _2842 = ivec2(_2840, _7929.y);
            _2842.y = _2842.y + (_2840 >> 12);
            _2842.x = _2842.x & 4095;
            int _2423 = int(_2416.x);
            _2310 = 0;
            for (;;)
            {
                bool _2426_ladder_break = false;
                do
                {
                    if (!(_2310 < _2423))
                    {
                        _2426_ladder_break = true;
                        break;
                    }
                    int _2856 = _2842.x + _2310;
                    ivec2 _2858 = ivec2(_2856, _2842.y);
                    _2858.y = _2858.y + (_2856 >> 12);
                    _2858.x = _2858.x & 4095;
                    uvec4 _2438 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_2858, _1326, 0).xyz, 0);
                    if (_2399)
                    {
                        _2311 = !(_2309 == max(int(_2438.x >> 12u), _2520));
                    }
                    else
                    {
                        _2311 = false;
                    }
                    if (_2311)
                    {
                        break;
                    }
                    ivec2 _2888 = ivec2(int(_2438.x & 4095u), int(_2438.y & 16383u));
                    do
                    {
                        vec4 _2897 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2888, _1326, 0).xyz, 0);
                        int _2966 = _2888.x + 1;
                        ivec2 _2968 = ivec2(_2966, _2888.y);
                        _2968.y = _2968.y + (_2966 >> 12);
                        _2968.x = _2968.x & 4095;
                        vec4 _2909 = vec4(_2897.xy, _2897.zw) - vec4(_1392, _1392);
                        vec2 _2911 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_2968, _1326, 0).xyz, 0).xy - _1392;
                        if ((max(max(_2909.y, _2909.w), _2911.y) * _2304) < (-0.5))
                        {
                            _2890 = false;
                            break;
                        }
                        float _2922 = _2909.x;
                        float _2923 = _2909.z;
                        float _2924 = _2911.x;
                        if (abs(_2922) <= 1.52587890625e-05)
                        {
                            _2996 = 0.0;
                        }
                        else
                        {
                            _2996 = _2922;
                        }
                        if (abs(_2923) <= 1.52587890625e-05)
                        {
                            _3005 = 0.0;
                        }
                        else
                        {
                            _3005 = _2923;
                        }
                        if (abs(_2924) <= 1.52587890625e-05)
                        {
                            _3014 = 0.0;
                        }
                        else
                        {
                            _3014 = _2924;
                        }
                        uint _2995 = (11892u >> (((floatBitsToUint(_3014) >> 29u) & 4u) | ((((floatBitsToUint(_3005) >> 30u) & 2u) | ((floatBitsToUint(_2996) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_2995 != 0u)
                        {
                            vec2 _3027 = _2909.xy;
                            vec2 _3028 = _2909.zw;
                            vec2 _3031 = (_3027 - (_3028 * 2.0)) + _2911;
                            vec2 _3032 = _3027 - _3028;
                            float _3033 = _3031.x;
                            if (abs(_3033) < 1.52587890625e-05)
                            {
                                float _3065 = _3032.x;
                                if (abs(_3065) < 1.52587890625e-05)
                                {
                                    _3023 = 0.0;
                                }
                                else
                                {
                                    _3023 = (_2909.x * 0.5) / _3065;
                                }
                                _3024 = _3023;
                            }
                            else
                            {
                                float _3037 = _3032.x;
                                float _3039 = _2909.x;
                                float _3040 = _3033 * _3039;
                                float _3041 = (_3037 * _3037) - _3040;
                                if (_3041 <= (max(_3037 * _3037, abs(_3040)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _3093 = 0.0;
                                }
                                else
                                {
                                    _3093 = sqrt(_3041);
                                }
                                if (_3037 >= 0.0)
                                {
                                    float _3055 = _3037 + _3093;
                                    if (abs(_3055) < 1.52587890625e-05)
                                    {
                                        _3023 = 0.0;
                                    }
                                    else
                                    {
                                        _3023 = _3039 / _3055;
                                    }
                                    _3024 = _3055 / _3033;
                                }
                                else
                                {
                                    float _3045 = _3037 - _3093;
                                    if (abs(_3045) < 1.52587890625e-05)
                                    {
                                        _3023 = 0.0;
                                    }
                                    else
                                    {
                                        _3023 = _3039 / _3045;
                                    }
                                    float _3053 = _3023;
                                    _3023 = _3045 / _3033;
                                    _3024 = _3053;
                                }
                            }
                            float _3076 = _3031.y;
                            float _3080 = _3032.y * 2.0;
                            float _3084 = _2909.y;
                            vec2 _2929 = vec2((((_3076 * _3023) - _3080) * _3023) + _3084, (((_3076 * _3024) - _3080) * _3024) + _3084) * _2304;
                            if ((_2995 & 1u) != 0u)
                            {
                                float _2933 = _2929.x;
                                _2312 -= clamp(_2933 + 0.5, 0.0, 1.0);
                                _2313 = max(_2313, clamp(1.0 - (abs(_2933) * 2.0), 0.0, 1.0));
                            }
                            if (_2995 > 1u)
                            {
                                float _2947 = _2929.y;
                                _2312 += clamp(_2947 + 0.5, 0.0, 1.0);
                                _2313 = max(_2313, clamp(1.0 - (abs(_2947) * 2.0), 0.0, 1.0));
                            }
                        }
                        _2890 = true;
                        break;
                    } while(false);
                    if (!_2890)
                    {
                        _2426_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_2426_ladder_break)
                {
                    break;
                }
                _2310++;
                continue;
            }
            _2309++;
            continue;
        }
        float _2479 = ((_2307 * _2308) + (_2312 * _2313)) / max(_2308 + _2313, 1.52587890625e-05);
        float _3107;
        do
        {
            if (false)
            {
                _3107 = 1.0 - abs((fract(_2479 * 0.5) * 2.0) - 1.0);
                break;
            }
            _3107 = abs(_2479);
            break;
        } while(false);
        float _3124;
        do
        {
            if (false)
            {
                _3124 = 1.0 - abs((fract(_2307 * 0.5) * 2.0) - 1.0);
                break;
            }
            _3124 = abs(_2307);
            break;
        } while(false);
        float _3141;
        do
        {
            if (false)
            {
                _3141 = 1.0 - abs((fract(_2312 * 0.5) * 2.0) - 1.0);
                break;
            }
            _3141 = abs(_2312);
            break;
        } while(false);
        float _2487 = clamp(max(_3107, min(_3124, _3141)), 0.0, 1.0);
        float _3161 = 1.0 / max(_1422.x, 1.52587890625e-05);
        float _3164 = 1.0 / max(_1422.y, 1.52587890625e-05);
        float _3351 = (_1393.y * _7928.y) + _7928.w;
        float _3355 = max(abs(_1422.y * _7928.y) * 0.5, 9.9999997473787516355514526367188e-06);
        int _3358 = clamp(int(_3351 - _3355), 0, _7929.z);
        int _3362 = max(_3358, clamp(int(_3351 + _3355), 0, _7929.z));
        float _3373 = (_1393.x * _7928.x) + _7928.z;
        float _3377 = max(abs(_1422.x * _7928.x) * 0.5, 9.9999997473787516355514526367188e-06);
        int _3380 = clamp(int(_3373 - _3377), 0, _1329);
        int _3384 = max(_3380, clamp(int(_3373 + _3377), 0, _1329));
        float _3167 = 0.0;
        float _3168 = 0.0;
        bool _3190 = _3358 != _3362;
        int _3169 = _3358;
        int _3170;
        bool _3171;
        bool _3463;
        float _3569;
        float _3578;
        float _3587;
        float _3596;
        float _3597;
        float _3666;
        for (;;)
        {
            if (!(_3169 <= _3362))
            {
                break;
            }
            int _3397 = _7929.x + _3169;
            ivec2 _3399 = ivec2(_3397, _7929.y);
            _3399.y = _3399.y + (_3397 >> 12);
            _3399.x = _3399.x & 4095;
            uvec4 _3205 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_3399, _1326, 0).xyz, 0);
            int _3413 = _7929.x + int(_3205.y);
            ivec2 _3415 = ivec2(_3413, _7929.y);
            _3415.y = _3415.y + (_3413 >> 12);
            _3415.x = _3415.x & 4095;
            int _3212 = int(_3205.x);
            _3170 = 0;
            for (;;)
            {
                bool _3215_ladder_break = false;
                do
                {
                    if (!(_3170 < _3212))
                    {
                        _3215_ladder_break = true;
                        break;
                    }
                    int _3429 = _3415.x + _3170;
                    ivec2 _3431 = ivec2(_3429, _3415.y);
                    _3431.y = _3431.y + (_3429 >> 12);
                    _3431.x = _3431.x & 4095;
                    uvec4 _3227 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_3431, _1326, 0).xyz, 0);
                    if (_3190)
                    {
                        _3171 = !(_3169 == max(int(_3227.x >> 12u), _3358));
                    }
                    else
                    {
                        _3171 = false;
                    }
                    if (_3171)
                    {
                        break;
                    }
                    ivec2 _3461 = ivec2(int(_3227.x & 4095u), int(_3227.y & 16383u));
                    do
                    {
                        vec4 _3470 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3461, _1326, 0).xyz, 0);
                        int _3539 = _3461.x + 1;
                        ivec2 _3541 = ivec2(_3539, _3461.y);
                        _3541.y = _3541.y + (_3539 >> 12);
                        _3541.x = _3541.x & 4095;
                        vec4 _3482 = vec4(_3470.xy, _3470.zw) - vec4(_1393, _1393);
                        vec2 _3484 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3541, _1326, 0).xyz, 0).xy - _1393;
                        if ((max(max(_3482.x, _3482.z), _3484.x) * _3161) < (-0.5))
                        {
                            _3463 = false;
                            break;
                        }
                        float _3495 = _3482.y;
                        float _3496 = _3482.w;
                        float _3497 = _3484.y;
                        if (abs(_3495) <= 1.52587890625e-05)
                        {
                            _3569 = 0.0;
                        }
                        else
                        {
                            _3569 = _3495;
                        }
                        if (abs(_3496) <= 1.52587890625e-05)
                        {
                            _3578 = 0.0;
                        }
                        else
                        {
                            _3578 = _3496;
                        }
                        if (abs(_3497) <= 1.52587890625e-05)
                        {
                            _3587 = 0.0;
                        }
                        else
                        {
                            _3587 = _3497;
                        }
                        uint _3568 = (11892u >> (((floatBitsToUint(_3587) >> 29u) & 4u) | ((((floatBitsToUint(_3578) >> 30u) & 2u) | ((floatBitsToUint(_3569) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_3568 != 0u)
                        {
                            vec2 _3600 = _3482.xy;
                            vec2 _3601 = _3482.zw;
                            vec2 _3604 = (_3600 - (_3601 * 2.0)) + _3484;
                            vec2 _3605 = _3600 - _3601;
                            float _3606 = _3604.y;
                            if (abs(_3606) < 1.52587890625e-05)
                            {
                                float _3638 = _3605.y;
                                if (abs(_3638) < 1.52587890625e-05)
                                {
                                    _3596 = 0.0;
                                }
                                else
                                {
                                    _3596 = (_3482.y * 0.5) / _3638;
                                }
                                _3597 = _3596;
                            }
                            else
                            {
                                float _3610 = _3605.y;
                                float _3612 = _3482.y;
                                float _3613 = _3606 * _3612;
                                float _3614 = (_3610 * _3610) - _3613;
                                if (_3614 <= (max(_3610 * _3610, abs(_3613)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _3666 = 0.0;
                                }
                                else
                                {
                                    _3666 = sqrt(_3614);
                                }
                                if (_3610 >= 0.0)
                                {
                                    float _3628 = _3610 + _3666;
                                    if (abs(_3628) < 1.52587890625e-05)
                                    {
                                        _3596 = 0.0;
                                    }
                                    else
                                    {
                                        _3596 = _3612 / _3628;
                                    }
                                    _3597 = _3628 / _3606;
                                }
                                else
                                {
                                    float _3618 = _3610 - _3666;
                                    if (abs(_3618) < 1.52587890625e-05)
                                    {
                                        _3596 = 0.0;
                                    }
                                    else
                                    {
                                        _3596 = _3612 / _3618;
                                    }
                                    float _3626 = _3596;
                                    _3596 = _3618 / _3606;
                                    _3597 = _3626;
                                }
                            }
                            float _3649 = _3604.x;
                            float _3653 = _3605.x * 2.0;
                            float _3657 = _3482.x;
                            vec2 _3502 = vec2((((_3649 * _3596) - _3653) * _3596) + _3657, (((_3649 * _3597) - _3653) * _3597) + _3657) * _3161;
                            if ((_3568 & 1u) != 0u)
                            {
                                float _3506 = _3502.x;
                                _3167 += clamp(_3506 + 0.5, 0.0, 1.0);
                                _3168 = max(_3168, clamp(1.0 - (abs(_3506) * 2.0), 0.0, 1.0));
                            }
                            if (_3568 > 1u)
                            {
                                float _3520 = _3502.y;
                                _3167 -= clamp(_3520 + 0.5, 0.0, 1.0);
                                _3168 = max(_3168, clamp(1.0 - (abs(_3520) * 2.0), 0.0, 1.0));
                            }
                        }
                        _3463 = true;
                        break;
                    } while(false);
                    if (!_3463)
                    {
                        _3215_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_3215_ladder_break)
                {
                    break;
                }
                _3170++;
                continue;
            }
            _3169++;
            continue;
        }
        float _3172 = 0.0;
        float _3173 = 0.0;
        bool _3259 = _3380 != _3384;
        _3169 = _3380;
        bool _3750;
        float _3856;
        float _3865;
        float _3874;
        float _3883;
        float _3884;
        float _3953;
        for (;;)
        {
            if (!(_3169 <= _3384))
            {
                break;
            }
            int _3684 = _7929.x + ((_7929.z + 1) + _3169);
            ivec2 _3686 = ivec2(_3684, _7929.y);
            _3686.y = _3686.y + (_3684 >> 12);
            _3686.x = _3686.x & 4095;
            uvec4 _3276 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_3686, _1326, 0).xyz, 0);
            int _3700 = _7929.x + int(_3276.y);
            ivec2 _3702 = ivec2(_3700, _7929.y);
            _3702.y = _3702.y + (_3700 >> 12);
            _3702.x = _3702.x & 4095;
            int _3283 = int(_3276.x);
            _3170 = 0;
            for (;;)
            {
                bool _3286_ladder_break = false;
                do
                {
                    if (!(_3170 < _3283))
                    {
                        _3286_ladder_break = true;
                        break;
                    }
                    int _3716 = _3702.x + _3170;
                    ivec2 _3718 = ivec2(_3716, _3702.y);
                    _3718.y = _3718.y + (_3716 >> 12);
                    _3718.x = _3718.x & 4095;
                    uvec4 _3298 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_3718, _1326, 0).xyz, 0);
                    if (_3259)
                    {
                        _3171 = !(_3169 == max(int(_3298.x >> 12u), _3380));
                    }
                    else
                    {
                        _3171 = false;
                    }
                    if (_3171)
                    {
                        break;
                    }
                    ivec2 _3748 = ivec2(int(_3298.x & 4095u), int(_3298.y & 16383u));
                    do
                    {
                        vec4 _3757 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3748, _1326, 0).xyz, 0);
                        int _3826 = _3748.x + 1;
                        ivec2 _3828 = ivec2(_3826, _3748.y);
                        _3828.y = _3828.y + (_3826 >> 12);
                        _3828.x = _3828.x & 4095;
                        vec4 _3769 = vec4(_3757.xy, _3757.zw) - vec4(_1393, _1393);
                        vec2 _3771 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_3828, _1326, 0).xyz, 0).xy - _1393;
                        if ((max(max(_3769.y, _3769.w), _3771.y) * _3164) < (-0.5))
                        {
                            _3750 = false;
                            break;
                        }
                        float _3782 = _3769.x;
                        float _3783 = _3769.z;
                        float _3784 = _3771.x;
                        if (abs(_3782) <= 1.52587890625e-05)
                        {
                            _3856 = 0.0;
                        }
                        else
                        {
                            _3856 = _3782;
                        }
                        if (abs(_3783) <= 1.52587890625e-05)
                        {
                            _3865 = 0.0;
                        }
                        else
                        {
                            _3865 = _3783;
                        }
                        if (abs(_3784) <= 1.52587890625e-05)
                        {
                            _3874 = 0.0;
                        }
                        else
                        {
                            _3874 = _3784;
                        }
                        uint _3855 = (11892u >> (((floatBitsToUint(_3874) >> 29u) & 4u) | ((((floatBitsToUint(_3865) >> 30u) & 2u) | ((floatBitsToUint(_3856) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_3855 != 0u)
                        {
                            vec2 _3887 = _3769.xy;
                            vec2 _3888 = _3769.zw;
                            vec2 _3891 = (_3887 - (_3888 * 2.0)) + _3771;
                            vec2 _3892 = _3887 - _3888;
                            float _3893 = _3891.x;
                            if (abs(_3893) < 1.52587890625e-05)
                            {
                                float _3925 = _3892.x;
                                if (abs(_3925) < 1.52587890625e-05)
                                {
                                    _3883 = 0.0;
                                }
                                else
                                {
                                    _3883 = (_3769.x * 0.5) / _3925;
                                }
                                _3884 = _3883;
                            }
                            else
                            {
                                float _3897 = _3892.x;
                                float _3899 = _3769.x;
                                float _3900 = _3893 * _3899;
                                float _3901 = (_3897 * _3897) - _3900;
                                if (_3901 <= (max(_3897 * _3897, abs(_3900)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _3953 = 0.0;
                                }
                                else
                                {
                                    _3953 = sqrt(_3901);
                                }
                                if (_3897 >= 0.0)
                                {
                                    float _3915 = _3897 + _3953;
                                    if (abs(_3915) < 1.52587890625e-05)
                                    {
                                        _3883 = 0.0;
                                    }
                                    else
                                    {
                                        _3883 = _3899 / _3915;
                                    }
                                    _3884 = _3915 / _3893;
                                }
                                else
                                {
                                    float _3905 = _3897 - _3953;
                                    if (abs(_3905) < 1.52587890625e-05)
                                    {
                                        _3883 = 0.0;
                                    }
                                    else
                                    {
                                        _3883 = _3899 / _3905;
                                    }
                                    float _3913 = _3883;
                                    _3883 = _3905 / _3893;
                                    _3884 = _3913;
                                }
                            }
                            float _3936 = _3891.y;
                            float _3940 = _3892.y * 2.0;
                            float _3944 = _3769.y;
                            vec2 _3789 = vec2((((_3936 * _3883) - _3940) * _3883) + _3944, (((_3936 * _3884) - _3940) * _3884) + _3944) * _3164;
                            if ((_3855 & 1u) != 0u)
                            {
                                float _3793 = _3789.x;
                                _3172 -= clamp(_3793 + 0.5, 0.0, 1.0);
                                _3173 = max(_3173, clamp(1.0 - (abs(_3793) * 2.0), 0.0, 1.0));
                            }
                            if (_3855 > 1u)
                            {
                                float _3807 = _3789.y;
                                _3172 += clamp(_3807 + 0.5, 0.0, 1.0);
                                _3173 = max(_3173, clamp(1.0 - (abs(_3807) * 2.0), 0.0, 1.0));
                            }
                        }
                        _3750 = true;
                        break;
                    } while(false);
                    if (!_3750)
                    {
                        _3286_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_3286_ladder_break)
                {
                    break;
                }
                _3170++;
                continue;
            }
            _3169++;
            continue;
        }
        float _3339 = ((_3167 * _3168) + (_3172 * _3173)) / max(_3168 + _3173, 1.52587890625e-05);
        float _3967;
        do
        {
            if (false)
            {
                _3967 = 1.0 - abs((fract(_3339 * 0.5) * 2.0) - 1.0);
                break;
            }
            _3967 = abs(_3339);
            break;
        } while(false);
        float _3984;
        do
        {
            if (false)
            {
                _3984 = 1.0 - abs((fract(_3167 * 0.5) * 2.0) - 1.0);
                break;
            }
            _3984 = abs(_3167);
            break;
        } while(false);
        float _4001;
        do
        {
            if (false)
            {
                _4001 = 1.0 - abs((fract(_3172 * 0.5) * 2.0) - 1.0);
                break;
            }
            _4001 = abs(_3172);
            break;
        } while(false);
        float _3347 = clamp(max(_3967, min(_3984, _4001)), 0.0, 1.0);
        float _4021 = 1.0 / max(_1422.x, 1.52587890625e-05);
        float _4024 = 1.0 / max(_1422.y, 1.52587890625e-05);
        float _4211 = (_7927.y * _7928.y) + _7928.w;
        float _4215 = max(abs(_1422.y * _7928.y) * 0.5, 9.9999997473787516355514526367188e-06);
        int _4218 = clamp(int(_4211 - _4215), 0, _7929.z);
        int _4222 = max(_4218, clamp(int(_4211 + _4215), 0, _7929.z));
        float _4233 = (_7927.x * _7928.x) + _7928.z;
        float _4237 = max(abs(_1422.x * _7928.x) * 0.5, 9.9999997473787516355514526367188e-06);
        int _4240 = clamp(int(_4233 - _4237), 0, _1329);
        int _4244 = max(_4240, clamp(int(_4233 + _4237), 0, _1329));
        float _4027 = 0.0;
        float _4028 = 0.0;
        bool _4050 = _4218 != _4222;
        int _4029 = _4218;
        int _4030;
        bool _4031;
        bool _4323;
        float _4429;
        float _4438;
        float _4447;
        float _4456;
        float _4457;
        float _4526;
        for (;;)
        {
            if (!(_4029 <= _4222))
            {
                break;
            }
            int _4257 = _7929.x + _4029;
            ivec2 _4259 = ivec2(_4257, _7929.y);
            _4259.y = _4259.y + (_4257 >> 12);
            _4259.x = _4259.x & 4095;
            uvec4 _4065 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4259, _1326, 0).xyz, 0);
            int _4273 = _7929.x + int(_4065.y);
            ivec2 _4275 = ivec2(_4273, _7929.y);
            _4275.y = _4275.y + (_4273 >> 12);
            _4275.x = _4275.x & 4095;
            int _4072 = int(_4065.x);
            _4030 = 0;
            for (;;)
            {
                bool _4075_ladder_break = false;
                do
                {
                    if (!(_4030 < _4072))
                    {
                        _4075_ladder_break = true;
                        break;
                    }
                    int _4289 = _4275.x + _4030;
                    ivec2 _4291 = ivec2(_4289, _4275.y);
                    _4291.y = _4291.y + (_4289 >> 12);
                    _4291.x = _4291.x & 4095;
                    uvec4 _4087 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4291, _1326, 0).xyz, 0);
                    if (_4050)
                    {
                        _4031 = !(_4029 == max(int(_4087.x >> 12u), _4218));
                    }
                    else
                    {
                        _4031 = false;
                    }
                    if (_4031)
                    {
                        break;
                    }
                    ivec2 _4321 = ivec2(int(_4087.x & 4095u), int(_4087.y & 16383u));
                    do
                    {
                        vec4 _4330 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4321, _1326, 0).xyz, 0);
                        int _4399 = _4321.x + 1;
                        ivec2 _4401 = ivec2(_4399, _4321.y);
                        _4401.y = _4401.y + (_4399 >> 12);
                        _4401.x = _4401.x & 4095;
                        vec4 _4342 = vec4(_4330.xy, _4330.zw) - vec4(_7927, _7927);
                        vec2 _4344 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4401, _1326, 0).xyz, 0).xy - _7927;
                        if ((max(max(_4342.x, _4342.z), _4344.x) * _4021) < (-0.5))
                        {
                            _4323 = false;
                            break;
                        }
                        float _4355 = _4342.y;
                        float _4356 = _4342.w;
                        float _4357 = _4344.y;
                        if (abs(_4355) <= 1.52587890625e-05)
                        {
                            _4429 = 0.0;
                        }
                        else
                        {
                            _4429 = _4355;
                        }
                        if (abs(_4356) <= 1.52587890625e-05)
                        {
                            _4438 = 0.0;
                        }
                        else
                        {
                            _4438 = _4356;
                        }
                        if (abs(_4357) <= 1.52587890625e-05)
                        {
                            _4447 = 0.0;
                        }
                        else
                        {
                            _4447 = _4357;
                        }
                        uint _4428 = (11892u >> (((floatBitsToUint(_4447) >> 29u) & 4u) | ((((floatBitsToUint(_4438) >> 30u) & 2u) | ((floatBitsToUint(_4429) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_4428 != 0u)
                        {
                            vec2 _4460 = _4342.xy;
                            vec2 _4461 = _4342.zw;
                            vec2 _4464 = (_4460 - (_4461 * 2.0)) + _4344;
                            vec2 _4465 = _4460 - _4461;
                            float _4466 = _4464.y;
                            if (abs(_4466) < 1.52587890625e-05)
                            {
                                float _4498 = _4465.y;
                                if (abs(_4498) < 1.52587890625e-05)
                                {
                                    _4456 = 0.0;
                                }
                                else
                                {
                                    _4456 = (_4342.y * 0.5) / _4498;
                                }
                                _4457 = _4456;
                            }
                            else
                            {
                                float _4470 = _4465.y;
                                float _4472 = _4342.y;
                                float _4473 = _4466 * _4472;
                                float _4474 = (_4470 * _4470) - _4473;
                                if (_4474 <= (max(_4470 * _4470, abs(_4473)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _4526 = 0.0;
                                }
                                else
                                {
                                    _4526 = sqrt(_4474);
                                }
                                if (_4470 >= 0.0)
                                {
                                    float _4488 = _4470 + _4526;
                                    if (abs(_4488) < 1.52587890625e-05)
                                    {
                                        _4456 = 0.0;
                                    }
                                    else
                                    {
                                        _4456 = _4472 / _4488;
                                    }
                                    _4457 = _4488 / _4466;
                                }
                                else
                                {
                                    float _4478 = _4470 - _4526;
                                    if (abs(_4478) < 1.52587890625e-05)
                                    {
                                        _4456 = 0.0;
                                    }
                                    else
                                    {
                                        _4456 = _4472 / _4478;
                                    }
                                    float _4486 = _4456;
                                    _4456 = _4478 / _4466;
                                    _4457 = _4486;
                                }
                            }
                            float _4509 = _4464.x;
                            float _4513 = _4465.x * 2.0;
                            float _4517 = _4342.x;
                            vec2 _4362 = vec2((((_4509 * _4456) - _4513) * _4456) + _4517, (((_4509 * _4457) - _4513) * _4457) + _4517) * _4021;
                            if ((_4428 & 1u) != 0u)
                            {
                                float _4366 = _4362.x;
                                _4027 += clamp(_4366 + 0.5, 0.0, 1.0);
                                _4028 = max(_4028, clamp(1.0 - (abs(_4366) * 2.0), 0.0, 1.0));
                            }
                            if (_4428 > 1u)
                            {
                                float _4380 = _4362.y;
                                _4027 -= clamp(_4380 + 0.5, 0.0, 1.0);
                                _4028 = max(_4028, clamp(1.0 - (abs(_4380) * 2.0), 0.0, 1.0));
                            }
                        }
                        _4323 = true;
                        break;
                    } while(false);
                    if (!_4323)
                    {
                        _4075_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_4075_ladder_break)
                {
                    break;
                }
                _4030++;
                continue;
            }
            _4029++;
            continue;
        }
        float _4032 = 0.0;
        float _4033 = 0.0;
        bool _4119 = _4240 != _4244;
        _4029 = _4240;
        bool _4610;
        float _4716;
        float _4725;
        float _4734;
        float _4743;
        float _4744;
        float _4813;
        for (;;)
        {
            if (!(_4029 <= _4244))
            {
                break;
            }
            int _4544 = _7929.x + ((_7929.z + 1) + _4029);
            ivec2 _4546 = ivec2(_4544, _7929.y);
            _4546.y = _4546.y + (_4544 >> 12);
            _4546.x = _4546.x & 4095;
            uvec4 _4136 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4546, _1326, 0).xyz, 0);
            int _4560 = _7929.x + int(_4136.y);
            ivec2 _4562 = ivec2(_4560, _7929.y);
            _4562.y = _4562.y + (_4560 >> 12);
            _4562.x = _4562.x & 4095;
            int _4143 = int(_4136.x);
            _4030 = 0;
            for (;;)
            {
                bool _4146_ladder_break = false;
                do
                {
                    if (!(_4030 < _4143))
                    {
                        _4146_ladder_break = true;
                        break;
                    }
                    int _4576 = _4562.x + _4030;
                    ivec2 _4578 = ivec2(_4576, _4562.y);
                    _4578.y = _4578.y + (_4576 >> 12);
                    _4578.x = _4578.x & 4095;
                    uvec4 _4158 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_4578, _1326, 0).xyz, 0);
                    if (_4119)
                    {
                        _4031 = !(_4029 == max(int(_4158.x >> 12u), _4240));
                    }
                    else
                    {
                        _4031 = false;
                    }
                    if (_4031)
                    {
                        break;
                    }
                    ivec2 _4608 = ivec2(int(_4158.x & 4095u), int(_4158.y & 16383u));
                    do
                    {
                        vec4 _4617 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4608, _1326, 0).xyz, 0);
                        int _4686 = _4608.x + 1;
                        ivec2 _4688 = ivec2(_4686, _4608.y);
                        _4688.y = _4688.y + (_4686 >> 12);
                        _4688.x = _4688.x & 4095;
                        vec4 _4629 = vec4(_4617.xy, _4617.zw) - vec4(_7927, _7927);
                        vec2 _4631 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_4688, _1326, 0).xyz, 0).xy - _7927;
                        if ((max(max(_4629.y, _4629.w), _4631.y) * _4024) < (-0.5))
                        {
                            _4610 = false;
                            break;
                        }
                        float _4642 = _4629.x;
                        float _4643 = _4629.z;
                        float _4644 = _4631.x;
                        if (abs(_4642) <= 1.52587890625e-05)
                        {
                            _4716 = 0.0;
                        }
                        else
                        {
                            _4716 = _4642;
                        }
                        if (abs(_4643) <= 1.52587890625e-05)
                        {
                            _4725 = 0.0;
                        }
                        else
                        {
                            _4725 = _4643;
                        }
                        if (abs(_4644) <= 1.52587890625e-05)
                        {
                            _4734 = 0.0;
                        }
                        else
                        {
                            _4734 = _4644;
                        }
                        uint _4715 = (11892u >> (((floatBitsToUint(_4734) >> 29u) & 4u) | ((((floatBitsToUint(_4725) >> 30u) & 2u) | ((floatBitsToUint(_4716) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_4715 != 0u)
                        {
                            vec2 _4747 = _4629.xy;
                            vec2 _4748 = _4629.zw;
                            vec2 _4751 = (_4747 - (_4748 * 2.0)) + _4631;
                            vec2 _4752 = _4747 - _4748;
                            float _4753 = _4751.x;
                            if (abs(_4753) < 1.52587890625e-05)
                            {
                                float _4785 = _4752.x;
                                if (abs(_4785) < 1.52587890625e-05)
                                {
                                    _4743 = 0.0;
                                }
                                else
                                {
                                    _4743 = (_4629.x * 0.5) / _4785;
                                }
                                _4744 = _4743;
                            }
                            else
                            {
                                float _4757 = _4752.x;
                                float _4759 = _4629.x;
                                float _4760 = _4753 * _4759;
                                float _4761 = (_4757 * _4757) - _4760;
                                if (_4761 <= (max(_4757 * _4757, abs(_4760)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _4813 = 0.0;
                                }
                                else
                                {
                                    _4813 = sqrt(_4761);
                                }
                                if (_4757 >= 0.0)
                                {
                                    float _4775 = _4757 + _4813;
                                    if (abs(_4775) < 1.52587890625e-05)
                                    {
                                        _4743 = 0.0;
                                    }
                                    else
                                    {
                                        _4743 = _4759 / _4775;
                                    }
                                    _4744 = _4775 / _4753;
                                }
                                else
                                {
                                    float _4765 = _4757 - _4813;
                                    if (abs(_4765) < 1.52587890625e-05)
                                    {
                                        _4743 = 0.0;
                                    }
                                    else
                                    {
                                        _4743 = _4759 / _4765;
                                    }
                                    float _4773 = _4743;
                                    _4743 = _4765 / _4753;
                                    _4744 = _4773;
                                }
                            }
                            float _4796 = _4751.y;
                            float _4800 = _4752.y * 2.0;
                            float _4804 = _4629.y;
                            vec2 _4649 = vec2((((_4796 * _4743) - _4800) * _4743) + _4804, (((_4796 * _4744) - _4800) * _4744) + _4804) * _4024;
                            if ((_4715 & 1u) != 0u)
                            {
                                float _4653 = _4649.x;
                                _4032 -= clamp(_4653 + 0.5, 0.0, 1.0);
                                _4033 = max(_4033, clamp(1.0 - (abs(_4653) * 2.0), 0.0, 1.0));
                            }
                            if (_4715 > 1u)
                            {
                                float _4667 = _4649.y;
                                _4032 += clamp(_4667 + 0.5, 0.0, 1.0);
                                _4033 = max(_4033, clamp(1.0 - (abs(_4667) * 2.0), 0.0, 1.0));
                            }
                        }
                        _4610 = true;
                        break;
                    } while(false);
                    if (!_4610)
                    {
                        _4146_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_4146_ladder_break)
                {
                    break;
                }
                _4030++;
                continue;
            }
            _4029++;
            continue;
        }
        float _4199 = ((_4027 * _4028) + (_4032 * _4033)) / max(_4028 + _4033, 1.52587890625e-05);
        float _4827;
        do
        {
            if (false)
            {
                _4827 = 1.0 - abs((fract(_4199 * 0.5) * 2.0) - 1.0);
                break;
            }
            _4827 = abs(_4199);
            break;
        } while(false);
        float _4844;
        do
        {
            if (false)
            {
                _4844 = 1.0 - abs((fract(_4027 * 0.5) * 2.0) - 1.0);
                break;
            }
            _4844 = abs(_4027);
            break;
        } while(false);
        float _4861;
        do
        {
            if (false)
            {
                _4861 = 1.0 - abs((fract(_4032 * 0.5) * 2.0) - 1.0);
                break;
            }
            _4861 = abs(_4032);
            break;
        } while(false);
        float _4207 = clamp(max(_4827, min(_4844, _4861)), 0.0, 1.0);
        float _4881 = 1.0 / max(_1422.x, 1.52587890625e-05);
        float _4884 = 1.0 / max(_1422.y, 1.52587890625e-05);
        float _5071 = (_1394.y * _7928.y) + _7928.w;
        float _5075 = max(abs(_1422.y * _7928.y) * 0.5, 9.9999997473787516355514526367188e-06);
        int _5078 = clamp(int(_5071 - _5075), 0, _7929.z);
        int _5082 = max(_5078, clamp(int(_5071 + _5075), 0, _7929.z));
        float _5093 = (_1394.x * _7928.x) + _7928.z;
        float _5097 = max(abs(_1422.x * _7928.x) * 0.5, 9.9999997473787516355514526367188e-06);
        int _5100 = clamp(int(_5093 - _5097), 0, _1329);
        int _5104 = max(_5100, clamp(int(_5093 + _5097), 0, _1329));
        float _4887 = 0.0;
        float _4888 = 0.0;
        bool _4910 = _5078 != _5082;
        int _4889 = _5078;
        int _4890;
        bool _4891;
        bool _5183;
        float _5289;
        float _5298;
        float _5307;
        float _5316;
        float _5317;
        float _5386;
        for (;;)
        {
            if (!(_4889 <= _5082))
            {
                break;
            }
            int _5117 = _7929.x + _4889;
            ivec2 _5119 = ivec2(_5117, _7929.y);
            _5119.y = _5119.y + (_5117 >> 12);
            _5119.x = _5119.x & 4095;
            uvec4 _4925 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5119, _1326, 0).xyz, 0);
            int _5133 = _7929.x + int(_4925.y);
            ivec2 _5135 = ivec2(_5133, _7929.y);
            _5135.y = _5135.y + (_5133 >> 12);
            _5135.x = _5135.x & 4095;
            int _4932 = int(_4925.x);
            _4890 = 0;
            for (;;)
            {
                bool _4935_ladder_break = false;
                do
                {
                    if (!(_4890 < _4932))
                    {
                        _4935_ladder_break = true;
                        break;
                    }
                    int _5149 = _5135.x + _4890;
                    ivec2 _5151 = ivec2(_5149, _5135.y);
                    _5151.y = _5151.y + (_5149 >> 12);
                    _5151.x = _5151.x & 4095;
                    uvec4 _4947 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5151, _1326, 0).xyz, 0);
                    if (_4910)
                    {
                        _4891 = !(_4889 == max(int(_4947.x >> 12u), _5078));
                    }
                    else
                    {
                        _4891 = false;
                    }
                    if (_4891)
                    {
                        break;
                    }
                    ivec2 _5181 = ivec2(int(_4947.x & 4095u), int(_4947.y & 16383u));
                    do
                    {
                        vec4 _5190 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5181, _1326, 0).xyz, 0);
                        int _5259 = _5181.x + 1;
                        ivec2 _5261 = ivec2(_5259, _5181.y);
                        _5261.y = _5261.y + (_5259 >> 12);
                        _5261.x = _5261.x & 4095;
                        vec4 _5202 = vec4(_5190.xy, _5190.zw) - vec4(_1394, _1394);
                        vec2 _5204 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5261, _1326, 0).xyz, 0).xy - _1394;
                        if ((max(max(_5202.x, _5202.z), _5204.x) * _4881) < (-0.5))
                        {
                            _5183 = false;
                            break;
                        }
                        float _5215 = _5202.y;
                        float _5216 = _5202.w;
                        float _5217 = _5204.y;
                        if (abs(_5215) <= 1.52587890625e-05)
                        {
                            _5289 = 0.0;
                        }
                        else
                        {
                            _5289 = _5215;
                        }
                        if (abs(_5216) <= 1.52587890625e-05)
                        {
                            _5298 = 0.0;
                        }
                        else
                        {
                            _5298 = _5216;
                        }
                        if (abs(_5217) <= 1.52587890625e-05)
                        {
                            _5307 = 0.0;
                        }
                        else
                        {
                            _5307 = _5217;
                        }
                        uint _5288 = (11892u >> (((floatBitsToUint(_5307) >> 29u) & 4u) | ((((floatBitsToUint(_5298) >> 30u) & 2u) | ((floatBitsToUint(_5289) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_5288 != 0u)
                        {
                            vec2 _5320 = _5202.xy;
                            vec2 _5321 = _5202.zw;
                            vec2 _5324 = (_5320 - (_5321 * 2.0)) + _5204;
                            vec2 _5325 = _5320 - _5321;
                            float _5326 = _5324.y;
                            if (abs(_5326) < 1.52587890625e-05)
                            {
                                float _5358 = _5325.y;
                                if (abs(_5358) < 1.52587890625e-05)
                                {
                                    _5316 = 0.0;
                                }
                                else
                                {
                                    _5316 = (_5202.y * 0.5) / _5358;
                                }
                                _5317 = _5316;
                            }
                            else
                            {
                                float _5330 = _5325.y;
                                float _5332 = _5202.y;
                                float _5333 = _5326 * _5332;
                                float _5334 = (_5330 * _5330) - _5333;
                                if (_5334 <= (max(_5330 * _5330, abs(_5333)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _5386 = 0.0;
                                }
                                else
                                {
                                    _5386 = sqrt(_5334);
                                }
                                if (_5330 >= 0.0)
                                {
                                    float _5348 = _5330 + _5386;
                                    if (abs(_5348) < 1.52587890625e-05)
                                    {
                                        _5316 = 0.0;
                                    }
                                    else
                                    {
                                        _5316 = _5332 / _5348;
                                    }
                                    _5317 = _5348 / _5326;
                                }
                                else
                                {
                                    float _5338 = _5330 - _5386;
                                    if (abs(_5338) < 1.52587890625e-05)
                                    {
                                        _5316 = 0.0;
                                    }
                                    else
                                    {
                                        _5316 = _5332 / _5338;
                                    }
                                    float _5346 = _5316;
                                    _5316 = _5338 / _5326;
                                    _5317 = _5346;
                                }
                            }
                            float _5369 = _5324.x;
                            float _5373 = _5325.x * 2.0;
                            float _5377 = _5202.x;
                            vec2 _5222 = vec2((((_5369 * _5316) - _5373) * _5316) + _5377, (((_5369 * _5317) - _5373) * _5317) + _5377) * _4881;
                            if ((_5288 & 1u) != 0u)
                            {
                                float _5226 = _5222.x;
                                _4887 += clamp(_5226 + 0.5, 0.0, 1.0);
                                _4888 = max(_4888, clamp(1.0 - (abs(_5226) * 2.0), 0.0, 1.0));
                            }
                            if (_5288 > 1u)
                            {
                                float _5240 = _5222.y;
                                _4887 -= clamp(_5240 + 0.5, 0.0, 1.0);
                                _4888 = max(_4888, clamp(1.0 - (abs(_5240) * 2.0), 0.0, 1.0));
                            }
                        }
                        _5183 = true;
                        break;
                    } while(false);
                    if (!_5183)
                    {
                        _4935_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_4935_ladder_break)
                {
                    break;
                }
                _4890++;
                continue;
            }
            _4889++;
            continue;
        }
        float _4892 = 0.0;
        float _4893 = 0.0;
        bool _4979 = _5100 != _5104;
        _4889 = _5100;
        bool _5470;
        float _5576;
        float _5585;
        float _5594;
        float _5603;
        float _5604;
        float _5673;
        for (;;)
        {
            if (!(_4889 <= _5104))
            {
                break;
            }
            int _5404 = _7929.x + ((_7929.z + 1) + _4889);
            ivec2 _5406 = ivec2(_5404, _7929.y);
            _5406.y = _5406.y + (_5404 >> 12);
            _5406.x = _5406.x & 4095;
            uvec4 _4996 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5406, _1326, 0).xyz, 0);
            int _5420 = _7929.x + int(_4996.y);
            ivec2 _5422 = ivec2(_5420, _7929.y);
            _5422.y = _5422.y + (_5420 >> 12);
            _5422.x = _5422.x & 4095;
            int _5003 = int(_4996.x);
            _4890 = 0;
            for (;;)
            {
                bool _5006_ladder_break = false;
                do
                {
                    if (!(_4890 < _5003))
                    {
                        _5006_ladder_break = true;
                        break;
                    }
                    int _5436 = _5422.x + _4890;
                    ivec2 _5438 = ivec2(_5436, _5422.y);
                    _5438.y = _5438.y + (_5436 >> 12);
                    _5438.x = _5438.x & 4095;
                    uvec4 _5018 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5438, _1326, 0).xyz, 0);
                    if (_4979)
                    {
                        _4891 = !(_4889 == max(int(_5018.x >> 12u), _5100));
                    }
                    else
                    {
                        _4891 = false;
                    }
                    if (_4891)
                    {
                        break;
                    }
                    ivec2 _5468 = ivec2(int(_5018.x & 4095u), int(_5018.y & 16383u));
                    do
                    {
                        vec4 _5477 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5468, _1326, 0).xyz, 0);
                        int _5546 = _5468.x + 1;
                        ivec2 _5548 = ivec2(_5546, _5468.y);
                        _5548.y = _5548.y + (_5546 >> 12);
                        _5548.x = _5548.x & 4095;
                        vec4 _5489 = vec4(_5477.xy, _5477.zw) - vec4(_1394, _1394);
                        vec2 _5491 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_5548, _1326, 0).xyz, 0).xy - _1394;
                        if ((max(max(_5489.y, _5489.w), _5491.y) * _4884) < (-0.5))
                        {
                            _5470 = false;
                            break;
                        }
                        float _5502 = _5489.x;
                        float _5503 = _5489.z;
                        float _5504 = _5491.x;
                        if (abs(_5502) <= 1.52587890625e-05)
                        {
                            _5576 = 0.0;
                        }
                        else
                        {
                            _5576 = _5502;
                        }
                        if (abs(_5503) <= 1.52587890625e-05)
                        {
                            _5585 = 0.0;
                        }
                        else
                        {
                            _5585 = _5503;
                        }
                        if (abs(_5504) <= 1.52587890625e-05)
                        {
                            _5594 = 0.0;
                        }
                        else
                        {
                            _5594 = _5504;
                        }
                        uint _5575 = (11892u >> (((floatBitsToUint(_5594) >> 29u) & 4u) | ((((floatBitsToUint(_5585) >> 30u) & 2u) | ((floatBitsToUint(_5576) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_5575 != 0u)
                        {
                            vec2 _5607 = _5489.xy;
                            vec2 _5608 = _5489.zw;
                            vec2 _5611 = (_5607 - (_5608 * 2.0)) + _5491;
                            vec2 _5612 = _5607 - _5608;
                            float _5613 = _5611.x;
                            if (abs(_5613) < 1.52587890625e-05)
                            {
                                float _5645 = _5612.x;
                                if (abs(_5645) < 1.52587890625e-05)
                                {
                                    _5603 = 0.0;
                                }
                                else
                                {
                                    _5603 = (_5489.x * 0.5) / _5645;
                                }
                                _5604 = _5603;
                            }
                            else
                            {
                                float _5617 = _5612.x;
                                float _5619 = _5489.x;
                                float _5620 = _5613 * _5619;
                                float _5621 = (_5617 * _5617) - _5620;
                                if (_5621 <= (max(_5617 * _5617, abs(_5620)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _5673 = 0.0;
                                }
                                else
                                {
                                    _5673 = sqrt(_5621);
                                }
                                if (_5617 >= 0.0)
                                {
                                    float _5635 = _5617 + _5673;
                                    if (abs(_5635) < 1.52587890625e-05)
                                    {
                                        _5603 = 0.0;
                                    }
                                    else
                                    {
                                        _5603 = _5619 / _5635;
                                    }
                                    _5604 = _5635 / _5613;
                                }
                                else
                                {
                                    float _5625 = _5617 - _5673;
                                    if (abs(_5625) < 1.52587890625e-05)
                                    {
                                        _5603 = 0.0;
                                    }
                                    else
                                    {
                                        _5603 = _5619 / _5625;
                                    }
                                    float _5633 = _5603;
                                    _5603 = _5625 / _5613;
                                    _5604 = _5633;
                                }
                            }
                            float _5656 = _5611.y;
                            float _5660 = _5612.y * 2.0;
                            float _5664 = _5489.y;
                            vec2 _5509 = vec2((((_5656 * _5603) - _5660) * _5603) + _5664, (((_5656 * _5604) - _5660) * _5604) + _5664) * _4884;
                            if ((_5575 & 1u) != 0u)
                            {
                                float _5513 = _5509.x;
                                _4892 -= clamp(_5513 + 0.5, 0.0, 1.0);
                                _4893 = max(_4893, clamp(1.0 - (abs(_5513) * 2.0), 0.0, 1.0));
                            }
                            if (_5575 > 1u)
                            {
                                float _5527 = _5509.y;
                                _4892 += clamp(_5527 + 0.5, 0.0, 1.0);
                                _4893 = max(_4893, clamp(1.0 - (abs(_5527) * 2.0), 0.0, 1.0));
                            }
                        }
                        _5470 = true;
                        break;
                    } while(false);
                    if (!_5470)
                    {
                        _5006_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_5006_ladder_break)
                {
                    break;
                }
                _4890++;
                continue;
            }
            _4889++;
            continue;
        }
        float _5059 = ((_4887 * _4888) + (_4892 * _4893)) / max(_4888 + _4893, 1.52587890625e-05);
        float _5687;
        do
        {
            if (false)
            {
                _5687 = 1.0 - abs((fract(_5059 * 0.5) * 2.0) - 1.0);
                break;
            }
            _5687 = abs(_5059);
            break;
        } while(false);
        float _5704;
        do
        {
            if (false)
            {
                _5704 = 1.0 - abs((fract(_4887 * 0.5) * 2.0) - 1.0);
                break;
            }
            _5704 = abs(_4887);
            break;
        } while(false);
        float _5721;
        do
        {
            if (false)
            {
                _5721 = 1.0 - abs((fract(_4892 * 0.5) * 2.0) - 1.0);
                break;
            }
            _5721 = abs(_4892);
            break;
        } while(false);
        float _5067 = clamp(max(_5687, min(_5704, _5721)), 0.0, 1.0);
        float _5741 = 1.0 / max(_1422.x, 1.52587890625e-05);
        float _5744 = 1.0 / max(_1422.y, 1.52587890625e-05);
        float _5931 = (_1395.y * _7928.y) + _7928.w;
        float _5935 = max(abs(_1422.y * _7928.y) * 0.5, 9.9999997473787516355514526367188e-06);
        int _5938 = clamp(int(_5931 - _5935), 0, _7929.z);
        int _5942 = max(_5938, clamp(int(_5931 + _5935), 0, _7929.z));
        float _5953 = (_1395.x * _7928.x) + _7928.z;
        float _5957 = max(abs(_1422.x * _7928.x) * 0.5, 9.9999997473787516355514526367188e-06);
        int _5960 = clamp(int(_5953 - _5957), 0, _1329);
        int _5964 = max(_5960, clamp(int(_5953 + _5957), 0, _1329));
        float _5747 = 0.0;
        float _5748 = 0.0;
        bool _5770 = _5938 != _5942;
        int _5749 = _5938;
        int _5750;
        bool _5751;
        bool _6043;
        float _6149;
        float _6158;
        float _6167;
        float _6176;
        float _6177;
        float _6246;
        for (;;)
        {
            if (!(_5749 <= _5942))
            {
                break;
            }
            int _5977 = _7929.x + _5749;
            ivec2 _5979 = ivec2(_5977, _7929.y);
            _5979.y = _5979.y + (_5977 >> 12);
            _5979.x = _5979.x & 4095;
            uvec4 _5785 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_5979, _1326, 0).xyz, 0);
            int _5993 = _7929.x + int(_5785.y);
            ivec2 _5995 = ivec2(_5993, _7929.y);
            _5995.y = _5995.y + (_5993 >> 12);
            _5995.x = _5995.x & 4095;
            int _5792 = int(_5785.x);
            _5750 = 0;
            for (;;)
            {
                bool _5795_ladder_break = false;
                do
                {
                    if (!(_5750 < _5792))
                    {
                        _5795_ladder_break = true;
                        break;
                    }
                    int _6009 = _5995.x + _5750;
                    ivec2 _6011 = ivec2(_6009, _5995.y);
                    _6011.y = _6011.y + (_6009 >> 12);
                    _6011.x = _6011.x & 4095;
                    uvec4 _5807 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_6011, _1326, 0).xyz, 0);
                    if (_5770)
                    {
                        _5751 = !(_5749 == max(int(_5807.x >> 12u), _5938));
                    }
                    else
                    {
                        _5751 = false;
                    }
                    if (_5751)
                    {
                        break;
                    }
                    ivec2 _6041 = ivec2(int(_5807.x & 4095u), int(_5807.y & 16383u));
                    do
                    {
                        vec4 _6050 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6041, _1326, 0).xyz, 0);
                        int _6119 = _6041.x + 1;
                        ivec2 _6121 = ivec2(_6119, _6041.y);
                        _6121.y = _6121.y + (_6119 >> 12);
                        _6121.x = _6121.x & 4095;
                        vec4 _6062 = vec4(_6050.xy, _6050.zw) - vec4(_1395, _1395);
                        vec2 _6064 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6121, _1326, 0).xyz, 0).xy - _1395;
                        if ((max(max(_6062.x, _6062.z), _6064.x) * _5741) < (-0.5))
                        {
                            _6043 = false;
                            break;
                        }
                        float _6075 = _6062.y;
                        float _6076 = _6062.w;
                        float _6077 = _6064.y;
                        if (abs(_6075) <= 1.52587890625e-05)
                        {
                            _6149 = 0.0;
                        }
                        else
                        {
                            _6149 = _6075;
                        }
                        if (abs(_6076) <= 1.52587890625e-05)
                        {
                            _6158 = 0.0;
                        }
                        else
                        {
                            _6158 = _6076;
                        }
                        if (abs(_6077) <= 1.52587890625e-05)
                        {
                            _6167 = 0.0;
                        }
                        else
                        {
                            _6167 = _6077;
                        }
                        uint _6148 = (11892u >> (((floatBitsToUint(_6167) >> 29u) & 4u) | ((((floatBitsToUint(_6158) >> 30u) & 2u) | ((floatBitsToUint(_6149) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_6148 != 0u)
                        {
                            vec2 _6180 = _6062.xy;
                            vec2 _6181 = _6062.zw;
                            vec2 _6184 = (_6180 - (_6181 * 2.0)) + _6064;
                            vec2 _6185 = _6180 - _6181;
                            float _6186 = _6184.y;
                            if (abs(_6186) < 1.52587890625e-05)
                            {
                                float _6218 = _6185.y;
                                if (abs(_6218) < 1.52587890625e-05)
                                {
                                    _6176 = 0.0;
                                }
                                else
                                {
                                    _6176 = (_6062.y * 0.5) / _6218;
                                }
                                _6177 = _6176;
                            }
                            else
                            {
                                float _6190 = _6185.y;
                                float _6192 = _6062.y;
                                float _6193 = _6186 * _6192;
                                float _6194 = (_6190 * _6190) - _6193;
                                if (_6194 <= (max(_6190 * _6190, abs(_6193)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _6246 = 0.0;
                                }
                                else
                                {
                                    _6246 = sqrt(_6194);
                                }
                                if (_6190 >= 0.0)
                                {
                                    float _6208 = _6190 + _6246;
                                    if (abs(_6208) < 1.52587890625e-05)
                                    {
                                        _6176 = 0.0;
                                    }
                                    else
                                    {
                                        _6176 = _6192 / _6208;
                                    }
                                    _6177 = _6208 / _6186;
                                }
                                else
                                {
                                    float _6198 = _6190 - _6246;
                                    if (abs(_6198) < 1.52587890625e-05)
                                    {
                                        _6176 = 0.0;
                                    }
                                    else
                                    {
                                        _6176 = _6192 / _6198;
                                    }
                                    float _6206 = _6176;
                                    _6176 = _6198 / _6186;
                                    _6177 = _6206;
                                }
                            }
                            float _6229 = _6184.x;
                            float _6233 = _6185.x * 2.0;
                            float _6237 = _6062.x;
                            vec2 _6082 = vec2((((_6229 * _6176) - _6233) * _6176) + _6237, (((_6229 * _6177) - _6233) * _6177) + _6237) * _5741;
                            if ((_6148 & 1u) != 0u)
                            {
                                float _6086 = _6082.x;
                                _5747 += clamp(_6086 + 0.5, 0.0, 1.0);
                                _5748 = max(_5748, clamp(1.0 - (abs(_6086) * 2.0), 0.0, 1.0));
                            }
                            if (_6148 > 1u)
                            {
                                float _6100 = _6082.y;
                                _5747 -= clamp(_6100 + 0.5, 0.0, 1.0);
                                _5748 = max(_5748, clamp(1.0 - (abs(_6100) * 2.0), 0.0, 1.0));
                            }
                        }
                        _6043 = true;
                        break;
                    } while(false);
                    if (!_6043)
                    {
                        _5795_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_5795_ladder_break)
                {
                    break;
                }
                _5750++;
                continue;
            }
            _5749++;
            continue;
        }
        float _5752 = 0.0;
        float _5753 = 0.0;
        bool _5839 = _5960 != _5964;
        _5749 = _5960;
        bool _6330;
        float _6436;
        float _6445;
        float _6454;
        float _6463;
        float _6464;
        float _6533;
        for (;;)
        {
            if (!(_5749 <= _5964))
            {
                break;
            }
            int _6264 = _7929.x + ((_7929.z + 1) + _5749);
            ivec2 _6266 = ivec2(_6264, _7929.y);
            _6266.y = _6266.y + (_6264 >> 12);
            _6266.x = _6266.x & 4095;
            uvec4 _5856 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_6266, _1326, 0).xyz, 0);
            int _6280 = _7929.x + int(_5856.y);
            ivec2 _6282 = ivec2(_6280, _7929.y);
            _6282.y = _6282.y + (_6280 >> 12);
            _6282.x = _6282.x & 4095;
            int _5863 = int(_5856.x);
            _5750 = 0;
            for (;;)
            {
                bool _5866_ladder_break = false;
                do
                {
                    if (!(_5750 < _5863))
                    {
                        _5866_ladder_break = true;
                        break;
                    }
                    int _6296 = _6282.x + _5750;
                    ivec2 _6298 = ivec2(_6296, _6282.y);
                    _6298.y = _6298.y + (_6296 >> 12);
                    _6298.x = _6298.x & 4095;
                    uvec4 _5878 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_6298, _1326, 0).xyz, 0);
                    if (_5839)
                    {
                        _5751 = !(_5749 == max(int(_5878.x >> 12u), _5960));
                    }
                    else
                    {
                        _5751 = false;
                    }
                    if (_5751)
                    {
                        break;
                    }
                    ivec2 _6328 = ivec2(int(_5878.x & 4095u), int(_5878.y & 16383u));
                    do
                    {
                        vec4 _6337 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6328, _1326, 0).xyz, 0);
                        int _6406 = _6328.x + 1;
                        ivec2 _6408 = ivec2(_6406, _6328.y);
                        _6408.y = _6408.y + (_6406 >> 12);
                        _6408.x = _6408.x & 4095;
                        vec4 _6349 = vec4(_6337.xy, _6337.zw) - vec4(_1395, _1395);
                        vec2 _6351 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6408, _1326, 0).xyz, 0).xy - _1395;
                        if ((max(max(_6349.y, _6349.w), _6351.y) * _5744) < (-0.5))
                        {
                            _6330 = false;
                            break;
                        }
                        float _6362 = _6349.x;
                        float _6363 = _6349.z;
                        float _6364 = _6351.x;
                        if (abs(_6362) <= 1.52587890625e-05)
                        {
                            _6436 = 0.0;
                        }
                        else
                        {
                            _6436 = _6362;
                        }
                        if (abs(_6363) <= 1.52587890625e-05)
                        {
                            _6445 = 0.0;
                        }
                        else
                        {
                            _6445 = _6363;
                        }
                        if (abs(_6364) <= 1.52587890625e-05)
                        {
                            _6454 = 0.0;
                        }
                        else
                        {
                            _6454 = _6364;
                        }
                        uint _6435 = (11892u >> (((floatBitsToUint(_6454) >> 29u) & 4u) | ((((floatBitsToUint(_6445) >> 30u) & 2u) | ((floatBitsToUint(_6436) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_6435 != 0u)
                        {
                            vec2 _6467 = _6349.xy;
                            vec2 _6468 = _6349.zw;
                            vec2 _6471 = (_6467 - (_6468 * 2.0)) + _6351;
                            vec2 _6472 = _6467 - _6468;
                            float _6473 = _6471.x;
                            if (abs(_6473) < 1.52587890625e-05)
                            {
                                float _6505 = _6472.x;
                                if (abs(_6505) < 1.52587890625e-05)
                                {
                                    _6463 = 0.0;
                                }
                                else
                                {
                                    _6463 = (_6349.x * 0.5) / _6505;
                                }
                                _6464 = _6463;
                            }
                            else
                            {
                                float _6477 = _6472.x;
                                float _6479 = _6349.x;
                                float _6480 = _6473 * _6479;
                                float _6481 = (_6477 * _6477) - _6480;
                                if (_6481 <= (max(_6477 * _6477, abs(_6480)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _6533 = 0.0;
                                }
                                else
                                {
                                    _6533 = sqrt(_6481);
                                }
                                if (_6477 >= 0.0)
                                {
                                    float _6495 = _6477 + _6533;
                                    if (abs(_6495) < 1.52587890625e-05)
                                    {
                                        _6463 = 0.0;
                                    }
                                    else
                                    {
                                        _6463 = _6479 / _6495;
                                    }
                                    _6464 = _6495 / _6473;
                                }
                                else
                                {
                                    float _6485 = _6477 - _6533;
                                    if (abs(_6485) < 1.52587890625e-05)
                                    {
                                        _6463 = 0.0;
                                    }
                                    else
                                    {
                                        _6463 = _6479 / _6485;
                                    }
                                    float _6493 = _6463;
                                    _6463 = _6485 / _6473;
                                    _6464 = _6493;
                                }
                            }
                            float _6516 = _6471.y;
                            float _6520 = _6472.y * 2.0;
                            float _6524 = _6349.y;
                            vec2 _6369 = vec2((((_6516 * _6463) - _6520) * _6463) + _6524, (((_6516 * _6464) - _6520) * _6464) + _6524) * _5744;
                            if ((_6435 & 1u) != 0u)
                            {
                                float _6373 = _6369.x;
                                _5752 -= clamp(_6373 + 0.5, 0.0, 1.0);
                                _5753 = max(_5753, clamp(1.0 - (abs(_6373) * 2.0), 0.0, 1.0));
                            }
                            if (_6435 > 1u)
                            {
                                float _6387 = _6369.y;
                                _5752 += clamp(_6387 + 0.5, 0.0, 1.0);
                                _5753 = max(_5753, clamp(1.0 - (abs(_6387) * 2.0), 0.0, 1.0));
                            }
                        }
                        _6330 = true;
                        break;
                    } while(false);
                    if (!_6330)
                    {
                        _5866_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_5866_ladder_break)
                {
                    break;
                }
                _5750++;
                continue;
            }
            _5749++;
            continue;
        }
        float _5919 = ((_5747 * _5748) + (_5752 * _5753)) / max(_5748 + _5753, 1.52587890625e-05);
        float _6547;
        do
        {
            if (false)
            {
                _6547 = 1.0 - abs((fract(_5919 * 0.5) * 2.0) - 1.0);
                break;
            }
            _6547 = abs(_5919);
            break;
        } while(false);
        float _6564;
        do
        {
            if (false)
            {
                _6564 = 1.0 - abs((fract(_5747 * 0.5) * 2.0) - 1.0);
                break;
            }
            _6564 = abs(_5747);
            break;
        } while(false);
        float _6581;
        do
        {
            if (false)
            {
                _6581 = 1.0 - abs((fract(_5752 * 0.5) * 2.0) - 1.0);
                break;
            }
            _6581 = abs(_5752);
            break;
        } while(false);
        float _5927 = clamp(max(_6547, min(_6564, _6581)), 0.0, 1.0);
        float _6601 = 1.0 / max(_1422.x, 1.52587890625e-05);
        float _6604 = 1.0 / max(_1422.y, 1.52587890625e-05);
        float _6791 = (_1396.y * _7928.y) + _7928.w;
        float _6795 = max(abs(_1422.y * _7928.y) * 0.5, 9.9999997473787516355514526367188e-06);
        int _6798 = clamp(int(_6791 - _6795), 0, _7929.z);
        int _6802 = max(_6798, clamp(int(_6791 + _6795), 0, _7929.z));
        float _6813 = (_1396.x * _7928.x) + _7928.z;
        float _6817 = max(abs(_1422.x * _7928.x) * 0.5, 9.9999997473787516355514526367188e-06);
        int _6820 = clamp(int(_6813 - _6817), 0, _1329);
        int _6824 = max(_6820, clamp(int(_6813 + _6817), 0, _1329));
        float _6607 = 0.0;
        float _6608 = 0.0;
        bool _6630 = _6798 != _6802;
        int _6609 = _6798;
        int _6610;
        bool _6611;
        bool _6903;
        float _7009;
        float _7018;
        float _7027;
        float _7036;
        float _7037;
        float _7106;
        for (;;)
        {
            if (!(_6609 <= _6802))
            {
                break;
            }
            int _6837 = _7929.x + _6609;
            ivec2 _6839 = ivec2(_6837, _7929.y);
            _6839.y = _6839.y + (_6837 >> 12);
            _6839.x = _6839.x & 4095;
            uvec4 _6645 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_6839, _1326, 0).xyz, 0);
            int _6853 = _7929.x + int(_6645.y);
            ivec2 _6855 = ivec2(_6853, _7929.y);
            _6855.y = _6855.y + (_6853 >> 12);
            _6855.x = _6855.x & 4095;
            int _6652 = int(_6645.x);
            _6610 = 0;
            for (;;)
            {
                bool _6655_ladder_break = false;
                do
                {
                    if (!(_6610 < _6652))
                    {
                        _6655_ladder_break = true;
                        break;
                    }
                    int _6869 = _6855.x + _6610;
                    ivec2 _6871 = ivec2(_6869, _6855.y);
                    _6871.y = _6871.y + (_6869 >> 12);
                    _6871.x = _6871.x & 4095;
                    uvec4 _6667 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_6871, _1326, 0).xyz, 0);
                    if (_6630)
                    {
                        _6611 = !(_6609 == max(int(_6667.x >> 12u), _6798));
                    }
                    else
                    {
                        _6611 = false;
                    }
                    if (_6611)
                    {
                        break;
                    }
                    ivec2 _6901 = ivec2(int(_6667.x & 4095u), int(_6667.y & 16383u));
                    do
                    {
                        vec4 _6910 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6901, _1326, 0).xyz, 0);
                        int _6979 = _6901.x + 1;
                        ivec2 _6981 = ivec2(_6979, _6901.y);
                        _6981.y = _6981.y + (_6979 >> 12);
                        _6981.x = _6981.x & 4095;
                        vec4 _6922 = vec4(_6910.xy, _6910.zw) - vec4(_1396, _1396);
                        vec2 _6924 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_6981, _1326, 0).xyz, 0).xy - _1396;
                        if ((max(max(_6922.x, _6922.z), _6924.x) * _6601) < (-0.5))
                        {
                            _6903 = false;
                            break;
                        }
                        float _6935 = _6922.y;
                        float _6936 = _6922.w;
                        float _6937 = _6924.y;
                        if (abs(_6935) <= 1.52587890625e-05)
                        {
                            _7009 = 0.0;
                        }
                        else
                        {
                            _7009 = _6935;
                        }
                        if (abs(_6936) <= 1.52587890625e-05)
                        {
                            _7018 = 0.0;
                        }
                        else
                        {
                            _7018 = _6936;
                        }
                        if (abs(_6937) <= 1.52587890625e-05)
                        {
                            _7027 = 0.0;
                        }
                        else
                        {
                            _7027 = _6937;
                        }
                        uint _7008 = (11892u >> (((floatBitsToUint(_7027) >> 29u) & 4u) | ((((floatBitsToUint(_7018) >> 30u) & 2u) | ((floatBitsToUint(_7009) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_7008 != 0u)
                        {
                            vec2 _7040 = _6922.xy;
                            vec2 _7041 = _6922.zw;
                            vec2 _7044 = (_7040 - (_7041 * 2.0)) + _6924;
                            vec2 _7045 = _7040 - _7041;
                            float _7046 = _7044.y;
                            if (abs(_7046) < 1.52587890625e-05)
                            {
                                float _7078 = _7045.y;
                                if (abs(_7078) < 1.52587890625e-05)
                                {
                                    _7036 = 0.0;
                                }
                                else
                                {
                                    _7036 = (_6922.y * 0.5) / _7078;
                                }
                                _7037 = _7036;
                            }
                            else
                            {
                                float _7050 = _7045.y;
                                float _7052 = _6922.y;
                                float _7053 = _7046 * _7052;
                                float _7054 = (_7050 * _7050) - _7053;
                                if (_7054 <= (max(_7050 * _7050, abs(_7053)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _7106 = 0.0;
                                }
                                else
                                {
                                    _7106 = sqrt(_7054);
                                }
                                if (_7050 >= 0.0)
                                {
                                    float _7068 = _7050 + _7106;
                                    if (abs(_7068) < 1.52587890625e-05)
                                    {
                                        _7036 = 0.0;
                                    }
                                    else
                                    {
                                        _7036 = _7052 / _7068;
                                    }
                                    _7037 = _7068 / _7046;
                                }
                                else
                                {
                                    float _7058 = _7050 - _7106;
                                    if (abs(_7058) < 1.52587890625e-05)
                                    {
                                        _7036 = 0.0;
                                    }
                                    else
                                    {
                                        _7036 = _7052 / _7058;
                                    }
                                    float _7066 = _7036;
                                    _7036 = _7058 / _7046;
                                    _7037 = _7066;
                                }
                            }
                            float _7089 = _7044.x;
                            float _7093 = _7045.x * 2.0;
                            float _7097 = _6922.x;
                            vec2 _6942 = vec2((((_7089 * _7036) - _7093) * _7036) + _7097, (((_7089 * _7037) - _7093) * _7037) + _7097) * _6601;
                            if ((_7008 & 1u) != 0u)
                            {
                                float _6946 = _6942.x;
                                _6607 += clamp(_6946 + 0.5, 0.0, 1.0);
                                _6608 = max(_6608, clamp(1.0 - (abs(_6946) * 2.0), 0.0, 1.0));
                            }
                            if (_7008 > 1u)
                            {
                                float _6960 = _6942.y;
                                _6607 -= clamp(_6960 + 0.5, 0.0, 1.0);
                                _6608 = max(_6608, clamp(1.0 - (abs(_6960) * 2.0), 0.0, 1.0));
                            }
                        }
                        _6903 = true;
                        break;
                    } while(false);
                    if (!_6903)
                    {
                        _6655_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_6655_ladder_break)
                {
                    break;
                }
                _6610++;
                continue;
            }
            _6609++;
            continue;
        }
        float _6612 = 0.0;
        float _6613 = 0.0;
        bool _6699 = _6820 != _6824;
        _6609 = _6820;
        bool _7190;
        float _7296;
        float _7305;
        float _7314;
        float _7323;
        float _7324;
        float _7393;
        for (;;)
        {
            if (!(_6609 <= _6824))
            {
                break;
            }
            int _7124 = _7929.x + ((_7929.z + 1) + _6609);
            ivec2 _7126 = ivec2(_7124, _7929.y);
            _7126.y = _7126.y + (_7124 >> 12);
            _7126.x = _7126.x & 4095;
            uvec4 _6716 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7126, _1326, 0).xyz, 0);
            int _7140 = _7929.x + int(_6716.y);
            ivec2 _7142 = ivec2(_7140, _7929.y);
            _7142.y = _7142.y + (_7140 >> 12);
            _7142.x = _7142.x & 4095;
            int _6723 = int(_6716.x);
            _6610 = 0;
            for (;;)
            {
                bool _6726_ladder_break = false;
                do
                {
                    if (!(_6610 < _6723))
                    {
                        _6726_ladder_break = true;
                        break;
                    }
                    int _7156 = _7142.x + _6610;
                    ivec2 _7158 = ivec2(_7156, _7142.y);
                    _7158.y = _7158.y + (_7156 >> 12);
                    _7158.x = _7158.x & 4095;
                    uvec4 _6738 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_7158, _1326, 0).xyz, 0);
                    if (_6699)
                    {
                        _6611 = !(_6609 == max(int(_6738.x >> 12u), _6820));
                    }
                    else
                    {
                        _6611 = false;
                    }
                    if (_6611)
                    {
                        break;
                    }
                    ivec2 _7188 = ivec2(int(_6738.x & 4095u), int(_6738.y & 16383u));
                    do
                    {
                        vec4 _7197 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7188, _1326, 0).xyz, 0);
                        int _7266 = _7188.x + 1;
                        ivec2 _7268 = ivec2(_7266, _7188.y);
                        _7268.y = _7268.y + (_7266 >> 12);
                        _7268.x = _7268.x & 4095;
                        vec4 _7209 = vec4(_7197.xy, _7197.zw) - vec4(_1396, _1396);
                        vec2 _7211 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_7268, _1326, 0).xyz, 0).xy - _1396;
                        if ((max(max(_7209.y, _7209.w), _7211.y) * _6604) < (-0.5))
                        {
                            _7190 = false;
                            break;
                        }
                        float _7222 = _7209.x;
                        float _7223 = _7209.z;
                        float _7224 = _7211.x;
                        if (abs(_7222) <= 1.52587890625e-05)
                        {
                            _7296 = 0.0;
                        }
                        else
                        {
                            _7296 = _7222;
                        }
                        if (abs(_7223) <= 1.52587890625e-05)
                        {
                            _7305 = 0.0;
                        }
                        else
                        {
                            _7305 = _7223;
                        }
                        if (abs(_7224) <= 1.52587890625e-05)
                        {
                            _7314 = 0.0;
                        }
                        else
                        {
                            _7314 = _7224;
                        }
                        uint _7295 = (11892u >> (((floatBitsToUint(_7314) >> 29u) & 4u) | ((((floatBitsToUint(_7305) >> 30u) & 2u) | ((floatBitsToUint(_7296) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                        if (_7295 != 0u)
                        {
                            vec2 _7327 = _7209.xy;
                            vec2 _7328 = _7209.zw;
                            vec2 _7331 = (_7327 - (_7328 * 2.0)) + _7211;
                            vec2 _7332 = _7327 - _7328;
                            float _7333 = _7331.x;
                            if (abs(_7333) < 1.52587890625e-05)
                            {
                                float _7365 = _7332.x;
                                if (abs(_7365) < 1.52587890625e-05)
                                {
                                    _7323 = 0.0;
                                }
                                else
                                {
                                    _7323 = (_7209.x * 0.5) / _7365;
                                }
                                _7324 = _7323;
                            }
                            else
                            {
                                float _7337 = _7332.x;
                                float _7339 = _7209.x;
                                float _7340 = _7333 * _7339;
                                float _7341 = (_7337 * _7337) - _7340;
                                if (_7341 <= (max(_7337 * _7337, abs(_7340)) * 3.0000001061125658452510833740234e-06))
                                {
                                    _7393 = 0.0;
                                }
                                else
                                {
                                    _7393 = sqrt(_7341);
                                }
                                if (_7337 >= 0.0)
                                {
                                    float _7355 = _7337 + _7393;
                                    if (abs(_7355) < 1.52587890625e-05)
                                    {
                                        _7323 = 0.0;
                                    }
                                    else
                                    {
                                        _7323 = _7339 / _7355;
                                    }
                                    _7324 = _7355 / _7333;
                                }
                                else
                                {
                                    float _7345 = _7337 - _7393;
                                    if (abs(_7345) < 1.52587890625e-05)
                                    {
                                        _7323 = 0.0;
                                    }
                                    else
                                    {
                                        _7323 = _7339 / _7345;
                                    }
                                    float _7353 = _7323;
                                    _7323 = _7345 / _7333;
                                    _7324 = _7353;
                                }
                            }
                            float _7376 = _7331.y;
                            float _7380 = _7332.y * 2.0;
                            float _7384 = _7209.y;
                            vec2 _7229 = vec2((((_7376 * _7323) - _7380) * _7323) + _7384, (((_7376 * _7324) - _7380) * _7324) + _7384) * _6604;
                            if ((_7295 & 1u) != 0u)
                            {
                                float _7233 = _7229.x;
                                _6612 -= clamp(_7233 + 0.5, 0.0, 1.0);
                                _6613 = max(_6613, clamp(1.0 - (abs(_7233) * 2.0), 0.0, 1.0));
                            }
                            if (_7295 > 1u)
                            {
                                float _7247 = _7229.y;
                                _6612 += clamp(_7247 + 0.5, 0.0, 1.0);
                                _6613 = max(_6613, clamp(1.0 - (abs(_7247) * 2.0), 0.0, 1.0));
                            }
                        }
                        _7190 = true;
                        break;
                    } while(false);
                    if (!_7190)
                    {
                        _6726_ladder_break = true;
                        break;
                    }
                    break;
                } while(false);
                if (_6726_ladder_break)
                {
                    break;
                }
                _6610++;
                continue;
            }
            _6609++;
            continue;
        }
        float _6779 = ((_6607 * _6608) + (_6612 * _6613)) / max(_6608 + _6613, 1.52587890625e-05);
        float _7407;
        do
        {
            if (false)
            {
                _7407 = 1.0 - abs((fract(_6779 * 0.5) * 2.0) - 1.0);
                break;
            }
            _7407 = abs(_6779);
            break;
        } while(false);
        float _7424;
        do
        {
            if (false)
            {
                _7424 = 1.0 - abs((fract(_6607 * 0.5) * 2.0) - 1.0);
                break;
            }
            _7424 = abs(_6607);
            break;
        } while(false);
        float _7441;
        do
        {
            if (false)
            {
                _7441 = 1.0 - abs((fract(_6612 * 0.5) * 2.0) - 1.0);
                break;
            }
            _7441 = abs(_6612);
            break;
        } while(false);
        bool _1377;
        if (pc.subpixel_order == 2)
        {
            _1377 = true;
        }
        else
        {
            _1377 = pc.subpixel_order == 4;
        }
        float _7465 = 0.30078125 * _4207;
        float _7468 = ((((0.03125 * clamp(max(_2247, min(_2264, _2281)), 0.0, 1.0)) + (0.30078125 * _2487)) + (0.3359375 * _3347)) + _7465) + (0.03125 * _5067);
        float _7477 = ((((0.03125 * _2487) + (0.30078125 * _3347)) + (0.3359375 * _4207)) + (0.30078125 * _5067)) + (0.03125 * _5927);
        float _7485 = ((((0.03125 * _3347) + _7465) + (0.3359375 * _5067)) + (0.30078125 * _5927)) + (0.03125 * clamp(max(_7407, min(_7424, _7441)), 0.0, 1.0));
        vec3 _7457;
        if (_1377)
        {
            _7457 = vec3(_7485, _7477, _7468);
        }
        else
        {
            _7457 = vec3(_7468, _7477, _7485);
        }
        vec3 _7492 = clamp(_7457, vec3(0.0), vec3(1.0));
        vec4 _7500 = vec4(_7492, clamp(((_7492.x + _7492.y) + _7492.z) * 0.3333333432674407958984375, 0.0, 1.0));
        float _7513 = clamp(_7500.x, 0.0, 1.0);
        float _7514 = max(pc.coverage_exponent, 1.52587890625e-05);
        float _7510;
        if (abs(_7514 - 1.0) <= 9.9999999747524270787835121154785e-07)
        {
            _7510 = _7513;
        }
        else
        {
            _7510 = pow(_7513, _7514);
        }
        float _7526 = clamp(_7500.y, 0.0, 1.0);
        float _7527 = max(pc.coverage_exponent, 1.52587890625e-05);
        float _7523;
        if (abs(_7527 - 1.0) <= 9.9999999747524270787835121154785e-07)
        {
            _7523 = _7526;
        }
        else
        {
            _7523 = pow(_7526, _7527);
        }
        float _7539 = clamp(_7500.z, 0.0, 1.0);
        float _7540 = max(pc.coverage_exponent, 1.52587890625e-05);
        float _7536;
        if (abs(_7540 - 1.0) <= 9.9999999747524270787835121154785e-07)
        {
            _7536 = _7539;
        }
        else
        {
            _7536 = pow(_7539, _7540);
        }
        float _7552 = clamp(_7500.w, 0.0, 1.0);
        float _7553 = max(pc.coverage_exponent, 1.52587890625e-05);
        float _7549;
        if (abs(_7553 - 1.0) <= 9.9999999747524270787835121154785e-07)
        {
            _7549 = _7552;
        }
        else
        {
            _7549 = pow(_7552, _7553);
        }
        vec4 _1415 = vec4(vec3(_7510, _7523, _7536), _7549);
        vec3 _1336 = _1415.xyz;
        if (max(max(_1415.x, _1415.y), _1415.z) < 0.0039215688593685626983642578125)
        {
            _7891 = true;
            _7873 = _7889;
            _7874 = _7890;
            _7875 = true;
            break;
        }
        vec4 _1350 = _7925 * _7926;
        vec4 _1310;
        if (pc.output_srgb != 0)
        {
            float _1355 = max(_1350.x, 0.0);
            float _7562;
            if (_1355 <= 0.003130800090730190277099609375)
            {
                _7562 = _1355 * 12.9200000762939453125;
            }
            else
            {
                _7562 = (1.05499994754791259765625 * pow(_1355, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
            }
            float _1358 = max(_1350.y, 0.0);
            float _7574;
            if (_1358 <= 0.003130800090730190277099609375)
            {
                _7574 = _1358 * 12.9200000762939453125;
            }
            else
            {
                _7574 = (1.05499994754791259765625 * pow(_1358, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
            }
            float _1361 = max(_1350.z, 0.0);
            float _7586;
            if (_1361 <= 0.003130800090730190277099609375)
            {
                _7586 = _1361 * 12.9200000762939453125;
            }
            else
            {
                _7586 = (1.05499994754791259765625 * pow(_1361, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
            }
            _1310 = vec4(_7562, _7574, _7586, _1350.w);
        }
        else
        {
            _1310 = _1350;
        }
        vec4 _7606 = vec4(_1310.xyz * (vec3(_1310.w) * _1336), _1310.w * _1415.w);
        _7889 = _7606;
        vec4 _1372 = vec4(vec3(_1350.w) * _1336, 0.0);
        _7890 = _1372;
        _7873 = _7606;
        _7874 = _1372;
        _7875 = _7891;
        break;
    } while(false);
    if (_7875)
    {
        discard;
    }
    entryPointParam_fragmentMain_color = _7873;
    entryPointParam_fragmentMain_blend = _7874;
}


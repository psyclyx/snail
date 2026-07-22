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

in vec4 snail_io0;
in vec4 snail_io4;
in vec2 snail_io1;
flat in vec4 snail_io2;
flat in ivec4 snail_io3;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

void main()
{
    vec4 _2251 = snail_io0;
    vec4 _2252 = snail_io4;
    vec2 _2253 = snail_io1;
    vec4 _2254 = snail_io2;
    if (((snail_io3.w >> 8) & 255) != 255)
    {
        discard;
    }
    if ((snail_io3.w & 255) != 2)
    {
        discard;
    }
    vec2 _1247 = fwidth(_2253);
    float _1189 = 1.0 / max(_1247.x, 1.52587890625e-05);
    float _1192 = 1.0 / max(_1247.y, 1.52587890625e-05);
    vec4 _1198 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(snail_io3.xy, 0).xy, 0);
    int _1257 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
    int _1262 = ((snail_io3.y * _1257) + snail_io3.x) + 1;
    vec4 _1204 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_1262 - _1257 * (_1262 / _1257), _1262 / _1257), 0).xy, 0);
    int _1207 = floatBitsToInt(_1198.z);
    int _1208 = _1207 & 65535;
    int _1210 = (_1207 >> 16) & 65535;
    int _1215 = pc.layer_base + int(_2254.w);
    int _1217 = int(_1198.x);
    int _1219 = int(_1198.y);
    float _1277 = _1204.y;
    float _1450 = (_2253.y * _1277) + _1204.w;
    float _1454 = max(abs(_1247.y * _1277) * 0.5, 9.9999997473787516355514526367188e-06);
    int _1457 = clamp(int(_1450 - _1454), 0, _1208);
    int _1461 = max(_1457, clamp(int(_1450 + _1454), 0, _1208));
    float _1283 = _1204.x;
    float _1472 = (_2253.x * _1283) + _1204.z;
    float _1476 = max(abs(_1247.x * _1283) * 0.5, 9.9999997473787516355514526367188e-06);
    int _1479 = clamp(int(_1472 - _1476), 0, _1210);
    int _1483 = max(_1479, clamp(int(_1472 + _1476), 0, _1210));
    float _1266 = 0.0;
    float _1267 = 0.0;
    bool _1289 = _1457 != _1461;
    int _1268 = _1457;
    int _1269;
    bool _1270;
    bool _1562;
    float _1668;
    float _1677;
    float _1686;
    float _1695;
    float _1696;
    float _1765;
    for (;;)
    {
        if (!(_1268 <= _1461))
        {
            break;
        }
        int _1496 = _1217 + _1268;
        ivec2 _1498 = ivec2(_1496, _1219);
        _1498.y = _1498.y + (_1496 >> 12);
        _1498.x = _1498.x & 4095;
        uvec4 _1304 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1498, _1215, 0).xyz, 0);
        int _1512 = _1217 + int(_1304.y);
        ivec2 _1514 = ivec2(_1512, _1219);
        _1514.y = _1514.y + (_1512 >> 12);
        _1514.x = _1514.x & 4095;
        int _1311 = int(_1304.x);
        _1269 = 0;
        for (;;)
        {
            bool _1314_ladder_break = false;
            do
            {
                if (!(_1269 < _1311))
                {
                    _1314_ladder_break = true;
                    break;
                }
                int _1528 = _1514.x + _1269;
                ivec2 _1530 = ivec2(_1528, _1514.y);
                _1530.y = _1530.y + (_1528 >> 12);
                _1530.x = _1530.x & 4095;
                uvec4 _1326 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1530, _1215, 0).xyz, 0);
                if (_1289)
                {
                    _1270 = !(_1268 == max(int(_1326.x >> 12u), _1457));
                }
                else
                {
                    _1270 = false;
                }
                if (_1270)
                {
                    break;
                }
                ivec2 _1560 = ivec2(int(_1326.x & 4095u), int(_1326.y & 16383u));
                do
                {
                    vec4 _1569 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1560, _1215, 0).xyz, 0);
                    int _1638 = _1560.x + 1;
                    ivec2 _1640 = ivec2(_1638, _1560.y);
                    _1640.y = _1640.y + (_1638 >> 12);
                    _1640.x = _1640.x & 4095;
                    vec4 _1581 = vec4(_1569.xy, _1569.zw) - vec4(_2253, _2253);
                    vec2 _1583 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1640, _1215, 0).xyz, 0).xy - _2253;
                    if ((max(max(_1581.x, _1581.z), _1583.x) * _1189) < (-0.5))
                    {
                        _1562 = false;
                        break;
                    }
                    float _1594 = _1581.y;
                    float _1595 = _1581.w;
                    float _1596 = _1583.y;
                    if (abs(_1594) <= 1.52587890625e-05)
                    {
                        _1668 = 0.0;
                    }
                    else
                    {
                        _1668 = _1594;
                    }
                    if (abs(_1595) <= 1.52587890625e-05)
                    {
                        _1677 = 0.0;
                    }
                    else
                    {
                        _1677 = _1595;
                    }
                    if (abs(_1596) <= 1.52587890625e-05)
                    {
                        _1686 = 0.0;
                    }
                    else
                    {
                        _1686 = _1596;
                    }
                    uint _1667 = (11892u >> (((floatBitsToUint(_1686) >> 29u) & 4u) | ((((floatBitsToUint(_1677) >> 30u) & 2u) | ((floatBitsToUint(_1668) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                    if (_1667 != 0u)
                    {
                        vec2 _1699 = _1581.xy;
                        vec2 _1700 = _1581.zw;
                        vec2 _1703 = (_1699 - (_1700 * 2.0)) + _1583;
                        vec2 _1704 = _1699 - _1700;
                        float _1705 = _1703.y;
                        if (abs(_1705) < 1.52587890625e-05)
                        {
                            float _1737 = _1704.y;
                            if (abs(_1737) < 1.52587890625e-05)
                            {
                                _1695 = 0.0;
                            }
                            else
                            {
                                _1695 = (_1581.y * 0.5) / _1737;
                            }
                            _1696 = _1695;
                        }
                        else
                        {
                            float _1709 = _1704.y;
                            float _1711 = _1581.y;
                            float _1712 = _1705 * _1711;
                            float _1713 = (_1709 * _1709) - _1712;
                            if (_1713 <= (max(_1709 * _1709, abs(_1712)) * 3.0000001061125658452510833740234e-06))
                            {
                                _1765 = 0.0;
                            }
                            else
                            {
                                _1765 = sqrt(_1713);
                            }
                            if (_1709 >= 0.0)
                            {
                                float _1727 = _1709 + _1765;
                                if (abs(_1727) < 1.52587890625e-05)
                                {
                                    _1695 = 0.0;
                                }
                                else
                                {
                                    _1695 = _1711 / _1727;
                                }
                                _1696 = _1727 / _1705;
                            }
                            else
                            {
                                float _1717 = _1709 - _1765;
                                if (abs(_1717) < 1.52587890625e-05)
                                {
                                    _1695 = 0.0;
                                }
                                else
                                {
                                    _1695 = _1711 / _1717;
                                }
                                float _1725 = _1695;
                                _1695 = _1717 / _1705;
                                _1696 = _1725;
                            }
                        }
                        float _1748 = _1703.x;
                        float _1752 = _1704.x * 2.0;
                        float _1756 = _1581.x;
                        vec2 _1601 = vec2((((_1748 * _1695) - _1752) * _1695) + _1756, (((_1748 * _1696) - _1752) * _1696) + _1756) * _1189;
                        if ((_1667 & 1u) != 0u)
                        {
                            float _1605 = _1601.x;
                            _1266 += clamp(_1605 + 0.5, 0.0, 1.0);
                            _1267 = max(_1267, clamp(1.0 - (abs(_1605) * 2.0), 0.0, 1.0));
                        }
                        if (_1667 > 1u)
                        {
                            float _1619 = _1601.y;
                            _1266 -= clamp(_1619 + 0.5, 0.0, 1.0);
                            _1267 = max(_1267, clamp(1.0 - (abs(_1619) * 2.0), 0.0, 1.0));
                        }
                    }
                    _1562 = true;
                    break;
                } while(false);
                if (!_1562)
                {
                    _1314_ladder_break = true;
                    break;
                }
                break;
            } while(false);
            if (_1314_ladder_break)
            {
                break;
            }
            _1269++;
            continue;
        }
        _1268++;
        continue;
    }
    float _1271 = 0.0;
    float _1272 = 0.0;
    bool _1358 = _1479 != _1483;
    _1268 = _1479;
    bool _1849;
    float _1955;
    float _1964;
    float _1973;
    float _1982;
    float _1983;
    float _2052;
    for (;;)
    {
        if (!(_1268 <= _1483))
        {
            break;
        }
        int _1783 = _1217 + ((_1208 + 1) + _1268);
        ivec2 _1785 = ivec2(_1783, _1219);
        _1785.y = _1785.y + (_1783 >> 12);
        _1785.x = _1785.x & 4095;
        uvec4 _1375 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1785, _1215, 0).xyz, 0);
        int _1799 = _1217 + int(_1375.y);
        ivec2 _1801 = ivec2(_1799, _1219);
        _1801.y = _1801.y + (_1799 >> 12);
        _1801.x = _1801.x & 4095;
        int _1382 = int(_1375.x);
        _1269 = 0;
        for (;;)
        {
            bool _1385_ladder_break = false;
            do
            {
                if (!(_1269 < _1382))
                {
                    _1385_ladder_break = true;
                    break;
                }
                int _1815 = _1801.x + _1269;
                ivec2 _1817 = ivec2(_1815, _1801.y);
                _1817.y = _1817.y + (_1815 >> 12);
                _1817.x = _1817.x & 4095;
                uvec4 _1397 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1817, _1215, 0).xyz, 0);
                if (_1358)
                {
                    _1270 = !(_1268 == max(int(_1397.x >> 12u), _1479));
                }
                else
                {
                    _1270 = false;
                }
                if (_1270)
                {
                    break;
                }
                ivec2 _1847 = ivec2(int(_1397.x & 4095u), int(_1397.y & 16383u));
                do
                {
                    vec4 _1856 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1847, _1215, 0).xyz, 0);
                    int _1925 = _1847.x + 1;
                    ivec2 _1927 = ivec2(_1925, _1847.y);
                    _1927.y = _1927.y + (_1925 >> 12);
                    _1927.x = _1927.x & 4095;
                    vec4 _1868 = vec4(_1856.xy, _1856.zw) - vec4(_2253, _2253);
                    vec2 _1870 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1927, _1215, 0).xyz, 0).xy - _2253;
                    if ((max(max(_1868.y, _1868.w), _1870.y) * _1192) < (-0.5))
                    {
                        _1849 = false;
                        break;
                    }
                    float _1881 = _1868.x;
                    float _1882 = _1868.z;
                    float _1883 = _1870.x;
                    if (abs(_1881) <= 1.52587890625e-05)
                    {
                        _1955 = 0.0;
                    }
                    else
                    {
                        _1955 = _1881;
                    }
                    if (abs(_1882) <= 1.52587890625e-05)
                    {
                        _1964 = 0.0;
                    }
                    else
                    {
                        _1964 = _1882;
                    }
                    if (abs(_1883) <= 1.52587890625e-05)
                    {
                        _1973 = 0.0;
                    }
                    else
                    {
                        _1973 = _1883;
                    }
                    uint _1954 = (11892u >> (((floatBitsToUint(_1973) >> 29u) & 4u) | ((((floatBitsToUint(_1964) >> 30u) & 2u) | ((floatBitsToUint(_1955) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                    if (_1954 != 0u)
                    {
                        vec2 _1986 = _1868.xy;
                        vec2 _1987 = _1868.zw;
                        vec2 _1990 = (_1986 - (_1987 * 2.0)) + _1870;
                        vec2 _1991 = _1986 - _1987;
                        float _1992 = _1990.x;
                        if (abs(_1992) < 1.52587890625e-05)
                        {
                            float _2024 = _1991.x;
                            if (abs(_2024) < 1.52587890625e-05)
                            {
                                _1982 = 0.0;
                            }
                            else
                            {
                                _1982 = (_1868.x * 0.5) / _2024;
                            }
                            _1983 = _1982;
                        }
                        else
                        {
                            float _1996 = _1991.x;
                            float _1998 = _1868.x;
                            float _1999 = _1992 * _1998;
                            float _2000 = (_1996 * _1996) - _1999;
                            if (_2000 <= (max(_1996 * _1996, abs(_1999)) * 3.0000001061125658452510833740234e-06))
                            {
                                _2052 = 0.0;
                            }
                            else
                            {
                                _2052 = sqrt(_2000);
                            }
                            if (_1996 >= 0.0)
                            {
                                float _2014 = _1996 + _2052;
                                if (abs(_2014) < 1.52587890625e-05)
                                {
                                    _1982 = 0.0;
                                }
                                else
                                {
                                    _1982 = _1998 / _2014;
                                }
                                _1983 = _2014 / _1992;
                            }
                            else
                            {
                                float _2004 = _1996 - _2052;
                                if (abs(_2004) < 1.52587890625e-05)
                                {
                                    _1982 = 0.0;
                                }
                                else
                                {
                                    _1982 = _1998 / _2004;
                                }
                                float _2012 = _1982;
                                _1982 = _2004 / _1992;
                                _1983 = _2012;
                            }
                        }
                        float _2035 = _1990.y;
                        float _2039 = _1991.y * 2.0;
                        float _2043 = _1868.y;
                        vec2 _1888 = vec2((((_2035 * _1982) - _2039) * _1982) + _2043, (((_2035 * _1983) - _2039) * _1983) + _2043) * _1192;
                        if ((_1954 & 1u) != 0u)
                        {
                            float _1892 = _1888.x;
                            _1271 -= clamp(_1892 + 0.5, 0.0, 1.0);
                            _1272 = max(_1272, clamp(1.0 - (abs(_1892) * 2.0), 0.0, 1.0));
                        }
                        if (_1954 > 1u)
                        {
                            float _1906 = _1888.y;
                            _1271 += clamp(_1906 + 0.5, 0.0, 1.0);
                            _1272 = max(_1272, clamp(1.0 - (abs(_1906) * 2.0), 0.0, 1.0));
                        }
                    }
                    _1849 = true;
                    break;
                } while(false);
                if (!_1849)
                {
                    _1385_ladder_break = true;
                    break;
                }
                break;
            } while(false);
            if (_1385_ladder_break)
            {
                break;
            }
            _1269++;
            continue;
        }
        _1268++;
        continue;
    }
    float _1438 = ((_1266 * _1267) + (_1271 * _1272)) / max(_1267 + _1272, 1.52587890625e-05);
    float _2066;
    do
    {
        if (false)
        {
            _2066 = 1.0 - abs((fract(_1438 * 0.5) * 2.0) - 1.0);
            break;
        }
        _2066 = abs(_1438);
        break;
    } while(false);
    float _2083;
    do
    {
        if (false)
        {
            _2083 = 1.0 - abs((fract(_1266 * 0.5) * 2.0) - 1.0);
            break;
        }
        _2083 = abs(_1266);
        break;
    } while(false);
    float _2100;
    do
    {
        if (false)
        {
            _2100 = 1.0 - abs((fract(_1271 * 0.5) * 2.0) - 1.0);
            break;
        }
        _2100 = abs(_1271);
        break;
    } while(false);
    float _2119 = clamp(max(_2066, min(_2083, _2100)), 0.0, 1.0);
    float _2120 = max(pc.coverage_exponent, 1.52587890625e-05);
    float _2116;
    if (abs(_2120 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _2116 = _2119;
    }
    else
    {
        _2116 = pow(_2119, _2120);
    }
    if (_2116 < 0.0039215688593685626983642578125)
    {
        discard;
    }
    vec4 _1230 = _2251 * _2252;
    float _2132 = _1230.w * _2116;
    vec4 _2135 = vec4(_1230.xyz * _2132, _2132);
    vec4 _1169;
    if (pc.mask_output != 0)
    {
        _1169 = vec4(_2135.w);
    }
    else
    {
        if (pc.output_srgb != 0)
        {
            vec4 _2137;
            do
            {
                float _2141 = _2135.w;
                if (_2141 <= 0.0)
                {
                    _2137 = vec4(0.0);
                    break;
                }
                vec3 _2147 = _2135.xyz * (1.0 / _2141);
                float _2157 = max(_2147.x, 0.0);
                float _2166;
                if (_2157 <= 0.003130800090730190277099609375)
                {
                    _2166 = _2157 * 12.9200000762939453125;
                }
                else
                {
                    _2166 = (1.05499994754791259765625 * pow(_2157, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                float _2160 = max(_2147.y, 0.0);
                float _2178;
                if (_2160 <= 0.003130800090730190277099609375)
                {
                    _2178 = _2160 * 12.9200000762939453125;
                }
                else
                {
                    _2178 = (1.05499994754791259765625 * pow(_2160, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                float _2163 = max(_2147.z, 0.0);
                float _2190;
                if (_2163 <= 0.003130800090730190277099609375)
                {
                    _2190 = _2163 * 12.9200000762939453125;
                }
                else
                {
                    _2190 = (1.05499994754791259765625 * pow(_2163, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                _2137 = vec4(vec3(_2166, _2178, _2190) * _2141, _2141);
                break;
            } while(false);
            _1169 = _2137;
        }
        else
        {
            _1169 = _2135;
        }
    }
    vec4 _1170 = _1169;
    entryPointParam_fragmentMain = _1170;
}


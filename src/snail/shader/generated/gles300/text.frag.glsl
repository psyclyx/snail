#version 300 es
precision highp float;
precision highp int;

layout(std140) uniform SnailPushConstants_std140
{
    layout(row_major) highp mat4 mvp;
    highp vec2 viewport;
    int subpixel_order;
    int output_srgb;
    int layer_base;
    highp float coverage_exponent;
    highp float dither_scale;
    int mask_output;
} pc;

uniform highp usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform highp sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in highp vec4 snail_io0;
in highp vec4 snail_io4;
in highp vec2 snail_io1;
flat in highp vec4 snail_io2;
flat in ivec4 snail_io3;
layout(location = 0) out highp vec4 entryPointParam_fragmentMain;

void main()
{
    highp vec4 _2154 = snail_io0;
    highp vec4 _2155 = snail_io4;
    highp vec2 _2156 = snail_io1;
    highp vec4 _2157 = snail_io2;
    int _1121 = (snail_io3.w >> 8) & 255;
    if (_1121 == 255)
    {
        discard;
    }
    int _1125 = pc.layer_base + _1121;
    highp vec2 _1167 = fwidth(_2156);
    highp float _1131 = 1.0 / max(_1167.x, 1.52587890625e-05);
    highp float _1134 = 1.0 / max(_1167.y, 1.52587890625e-05);
    int _1137 = snail_io3.w & 255;
    highp float _1352 = (_2156.y * _2157.y) + _2157.w;
    highp float _1356 = max(abs(_1167.y * _2157.y) * 0.5, 9.9999997473787516355514526367188e-06);
    int _1359 = clamp(int(_1352 - _1356), 0, snail_io3.z);
    int _1363 = max(_1359, clamp(int(_1352 + _1356), 0, snail_io3.z));
    highp float _1374 = (_2156.x * _2157.x) + _2157.z;
    highp float _1378 = max(abs(_1167.x * _2157.x) * 0.5, 9.9999997473787516355514526367188e-06);
    int _1381 = clamp(int(_1374 - _1378), 0, _1137);
    int _1385 = max(_1381, clamp(int(_1374 + _1378), 0, _1137));
    highp float _1168 = 0.0;
    highp float _1169 = 0.0;
    bool _1191 = _1359 != _1363;
    int _1170 = _1359;
    int _1171;
    bool _1172;
    bool _1464;
    highp float _1571;
    highp float _1580;
    highp float _1589;
    highp float _1598;
    highp float _1599;
    highp float _1668;
    for (;;)
    {
        if (!(_1170 <= _1363))
        {
            break;
        }
        int _1398 = snail_io3.x + _1170;
        ivec2 _1400 = ivec2(_1398, snail_io3.y);
        _1400.y = _1400.y + (_1398 >> 12);
        _1400.x = _1400.x & 4095;
        uvec4 _1206 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1400, _1125, 0).xyz, 0);
        int _1414 = snail_io3.x + int(_1206.y);
        ivec2 _1416 = ivec2(_1414, snail_io3.y);
        _1416.y = _1416.y + (_1414 >> 12);
        _1416.x = _1416.x & 4095;
        int _1213 = int(_1206.x);
        _1171 = 0;
        for (;;)
        {
            bool _1216_ladder_break = false;
            do
            {
                if (!(_1171 < _1213))
                {
                    _1216_ladder_break = true;
                    break;
                }
                int _1430 = _1416.x + _1171;
                ivec2 _1432 = ivec2(_1430, _1416.y);
                _1432.y = _1432.y + (_1430 >> 12);
                _1432.x = _1432.x & 4095;
                uvec4 _1228 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1432, _1125, 0).xyz, 0);
                if (_1191)
                {
                    _1172 = !(_1170 == max(int(_1228.x >> 12u), _1359));
                }
                else
                {
                    _1172 = false;
                }
                if (_1172)
                {
                    break;
                }
                ivec2 _1462 = ivec2(int(_1228.x & 4095u), int(_1228.y & 16383u));
                do
                {
                    highp vec4 _1471 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1462, _1125, 0).xyz, 0);
                    int _1540 = _1462.x + 1;
                    ivec2 _1542 = ivec2(_1540, _1462.y);
                    _1542.y = _1542.y + (_1540 >> 12);
                    _1542.x = _1542.x & 4095;
                    highp vec4 _1483 = vec4(_1471.xy, _1471.zw) - vec4(_2156, _2156);
                    highp vec2 _1485 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1542, _1125, 0).xyz, 0).xy - _2156;
                    if ((max(max(_1483.x, _1483.z), _1485.x) * _1131) < (-0.5))
                    {
                        _1464 = false;
                        break;
                    }
                    highp float _1496 = _1483.y;
                    highp float _1497 = _1483.w;
                    highp float _1498 = _1485.y;
                    if (abs(_1496) <= 1.52587890625e-05)
                    {
                        _1571 = 0.0;
                    }
                    else
                    {
                        _1571 = _1496;
                    }
                    if (abs(_1497) <= 1.52587890625e-05)
                    {
                        _1580 = 0.0;
                    }
                    else
                    {
                        _1580 = _1497;
                    }
                    if (abs(_1498) <= 1.52587890625e-05)
                    {
                        _1589 = 0.0;
                    }
                    else
                    {
                        _1589 = _1498;
                    }
                    uint _1570 = (11892u >> (((floatBitsToUint(_1589) >> 29u) & 4u) | ((((floatBitsToUint(_1580) >> 30u) & 2u) | ((floatBitsToUint(_1571) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                    if (_1570 != 0u)
                    {
                        highp vec2 _1602 = _1483.xy;
                        highp vec2 _1603 = _1483.zw;
                        highp vec2 _1606 = (_1602 - (_1603 * 2.0)) + _1485;
                        highp vec2 _1607 = _1602 - _1603;
                        highp float _1608 = _1606.y;
                        if (abs(_1608) < 1.52587890625e-05)
                        {
                            highp float _1640 = _1607.y;
                            if (abs(_1640) < 1.52587890625e-05)
                            {
                                _1598 = 0.0;
                            }
                            else
                            {
                                _1598 = (_1483.y * 0.5) / _1640;
                            }
                            _1599 = _1598;
                        }
                        else
                        {
                            highp float _1612 = _1607.y;
                            highp float _1614 = _1483.y;
                            highp float _1615 = _1608 * _1614;
                            highp float _1616 = (_1612 * _1612) - _1615;
                            if (_1616 <= (max(_1612 * _1612, abs(_1615)) * 3.0000001061125658452510833740234e-06))
                            {
                                _1668 = 0.0;
                            }
                            else
                            {
                                _1668 = sqrt(_1616);
                            }
                            if (_1612 >= 0.0)
                            {
                                highp float _1630 = _1612 + _1668;
                                if (abs(_1630) < 1.52587890625e-05)
                                {
                                    _1598 = 0.0;
                                }
                                else
                                {
                                    _1598 = _1614 / _1630;
                                }
                                _1599 = _1630 / _1608;
                            }
                            else
                            {
                                highp float _1620 = _1612 - _1668;
                                if (abs(_1620) < 1.52587890625e-05)
                                {
                                    _1598 = 0.0;
                                }
                                else
                                {
                                    _1598 = _1614 / _1620;
                                }
                                highp float _1628 = _1598;
                                _1598 = _1620 / _1608;
                                _1599 = _1628;
                            }
                        }
                        highp float _1651 = _1606.x;
                        highp float _1655 = _1607.x * 2.0;
                        highp float _1659 = _1483.x;
                        highp vec2 _1503 = vec2((((_1651 * _1598) - _1655) * _1598) + _1659, (((_1651 * _1599) - _1655) * _1599) + _1659) * _1131;
                        if ((_1570 & 1u) != 0u)
                        {
                            highp float _1507 = _1503.x;
                            _1168 += clamp(_1507 + 0.5, 0.0, 1.0);
                            _1169 = max(_1169, clamp(1.0 - (abs(_1507) * 2.0), 0.0, 1.0));
                        }
                        if (_1570 > 1u)
                        {
                            highp float _1521 = _1503.y;
                            _1168 -= clamp(_1521 + 0.5, 0.0, 1.0);
                            _1169 = max(_1169, clamp(1.0 - (abs(_1521) * 2.0), 0.0, 1.0));
                        }
                    }
                    _1464 = true;
                    break;
                } while(false);
                if (!_1464)
                {
                    _1216_ladder_break = true;
                    break;
                }
                break;
            } while(false);
            if (_1216_ladder_break)
            {
                break;
            }
            _1171++;
            continue;
        }
        _1170++;
        continue;
    }
    highp float _1173 = 0.0;
    highp float _1174 = 0.0;
    bool _1260 = _1381 != _1385;
    _1170 = _1381;
    bool _1752;
    highp float _1858;
    highp float _1867;
    highp float _1876;
    highp float _1885;
    highp float _1886;
    highp float _1955;
    for (;;)
    {
        if (!(_1170 <= _1385))
        {
            break;
        }
        int _1686 = snail_io3.x + ((snail_io3.z + 1) + _1170);
        ivec2 _1688 = ivec2(_1686, snail_io3.y);
        _1688.y = _1688.y + (_1686 >> 12);
        _1688.x = _1688.x & 4095;
        uvec4 _1277 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1688, _1125, 0).xyz, 0);
        int _1702 = snail_io3.x + int(_1277.y);
        ivec2 _1704 = ivec2(_1702, snail_io3.y);
        _1704.y = _1704.y + (_1702 >> 12);
        _1704.x = _1704.x & 4095;
        int _1284 = int(_1277.x);
        _1171 = 0;
        for (;;)
        {
            bool _1287_ladder_break = false;
            do
            {
                if (!(_1171 < _1284))
                {
                    _1287_ladder_break = true;
                    break;
                }
                int _1718 = _1704.x + _1171;
                ivec2 _1720 = ivec2(_1718, _1704.y);
                _1720.y = _1720.y + (_1718 >> 12);
                _1720.x = _1720.x & 4095;
                uvec4 _1299 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_1720, _1125, 0).xyz, 0);
                if (_1260)
                {
                    _1172 = !(_1170 == max(int(_1299.x >> 12u), _1381));
                }
                else
                {
                    _1172 = false;
                }
                if (_1172)
                {
                    break;
                }
                ivec2 _1750 = ivec2(int(_1299.x & 4095u), int(_1299.y & 16383u));
                do
                {
                    highp vec4 _1759 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1750, _1125, 0).xyz, 0);
                    int _1828 = _1750.x + 1;
                    ivec2 _1830 = ivec2(_1828, _1750.y);
                    _1830.y = _1830.y + (_1828 >> 12);
                    _1830.x = _1830.x & 4095;
                    highp vec4 _1771 = vec4(_1759.xy, _1759.zw) - vec4(_2156, _2156);
                    highp vec2 _1773 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_1830, _1125, 0).xyz, 0).xy - _2156;
                    if ((max(max(_1771.y, _1771.w), _1773.y) * _1134) < (-0.5))
                    {
                        _1752 = false;
                        break;
                    }
                    highp float _1784 = _1771.x;
                    highp float _1785 = _1771.z;
                    highp float _1786 = _1773.x;
                    if (abs(_1784) <= 1.52587890625e-05)
                    {
                        _1858 = 0.0;
                    }
                    else
                    {
                        _1858 = _1784;
                    }
                    if (abs(_1785) <= 1.52587890625e-05)
                    {
                        _1867 = 0.0;
                    }
                    else
                    {
                        _1867 = _1785;
                    }
                    if (abs(_1786) <= 1.52587890625e-05)
                    {
                        _1876 = 0.0;
                    }
                    else
                    {
                        _1876 = _1786;
                    }
                    uint _1857 = (11892u >> (((floatBitsToUint(_1876) >> 29u) & 4u) | ((((floatBitsToUint(_1867) >> 30u) & 2u) | ((floatBitsToUint(_1858) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                    if (_1857 != 0u)
                    {
                        highp vec2 _1889 = _1771.xy;
                        highp vec2 _1890 = _1771.zw;
                        highp vec2 _1893 = (_1889 - (_1890 * 2.0)) + _1773;
                        highp vec2 _1894 = _1889 - _1890;
                        highp float _1895 = _1893.x;
                        if (abs(_1895) < 1.52587890625e-05)
                        {
                            highp float _1927 = _1894.x;
                            if (abs(_1927) < 1.52587890625e-05)
                            {
                                _1885 = 0.0;
                            }
                            else
                            {
                                _1885 = (_1771.x * 0.5) / _1927;
                            }
                            _1886 = _1885;
                        }
                        else
                        {
                            highp float _1899 = _1894.x;
                            highp float _1901 = _1771.x;
                            highp float _1902 = _1895 * _1901;
                            highp float _1903 = (_1899 * _1899) - _1902;
                            if (_1903 <= (max(_1899 * _1899, abs(_1902)) * 3.0000001061125658452510833740234e-06))
                            {
                                _1955 = 0.0;
                            }
                            else
                            {
                                _1955 = sqrt(_1903);
                            }
                            if (_1899 >= 0.0)
                            {
                                highp float _1917 = _1899 + _1955;
                                if (abs(_1917) < 1.52587890625e-05)
                                {
                                    _1885 = 0.0;
                                }
                                else
                                {
                                    _1885 = _1901 / _1917;
                                }
                                _1886 = _1917 / _1895;
                            }
                            else
                            {
                                highp float _1907 = _1899 - _1955;
                                if (abs(_1907) < 1.52587890625e-05)
                                {
                                    _1885 = 0.0;
                                }
                                else
                                {
                                    _1885 = _1901 / _1907;
                                }
                                highp float _1915 = _1885;
                                _1885 = _1907 / _1895;
                                _1886 = _1915;
                            }
                        }
                        highp float _1938 = _1893.y;
                        highp float _1942 = _1894.y * 2.0;
                        highp float _1946 = _1771.y;
                        highp vec2 _1791 = vec2((((_1938 * _1885) - _1942) * _1885) + _1946, (((_1938 * _1886) - _1942) * _1886) + _1946) * _1134;
                        if ((_1857 & 1u) != 0u)
                        {
                            highp float _1795 = _1791.x;
                            _1173 -= clamp(_1795 + 0.5, 0.0, 1.0);
                            _1174 = max(_1174, clamp(1.0 - (abs(_1795) * 2.0), 0.0, 1.0));
                        }
                        if (_1857 > 1u)
                        {
                            highp float _1809 = _1791.y;
                            _1173 += clamp(_1809 + 0.5, 0.0, 1.0);
                            _1174 = max(_1174, clamp(1.0 - (abs(_1809) * 2.0), 0.0, 1.0));
                        }
                    }
                    _1752 = true;
                    break;
                } while(false);
                if (!_1752)
                {
                    _1287_ladder_break = true;
                    break;
                }
                break;
            } while(false);
            if (_1287_ladder_break)
            {
                break;
            }
            _1171++;
            continue;
        }
        _1170++;
        continue;
    }
    highp float _1340 = ((_1168 * _1169) + (_1173 * _1174)) / max(_1169 + _1174, 1.52587890625e-05);
    highp float _1969;
    do
    {
        if (false)
        {
            _1969 = 1.0 - abs((fract(_1340 * 0.5) * 2.0) - 1.0);
            break;
        }
        _1969 = abs(_1340);
        break;
    } while(false);
    highp float _1986;
    do
    {
        if (false)
        {
            _1986 = 1.0 - abs((fract(_1168 * 0.5) * 2.0) - 1.0);
            break;
        }
        _1986 = abs(_1168);
        break;
    } while(false);
    highp float _2003;
    do
    {
        if (false)
        {
            _2003 = 1.0 - abs((fract(_1173 * 0.5) * 2.0) - 1.0);
            break;
        }
        _2003 = abs(_1173);
        break;
    } while(false);
    highp float _2022 = clamp(max(_1969, min(_1986, _2003)), 0.0, 1.0);
    highp float _2023 = max(pc.coverage_exponent, 1.52587890625e-05);
    highp float _2019;
    if (abs(_2023 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _2019 = _2022;
    }
    else
    {
        _2019 = pow(_2022, _2023);
    }
    if (_2019 < 0.0039215688593685626983642578125)
    {
        discard;
    }
    highp vec4 _1150 = _2154 * _2155;
    highp float _2035 = _1150.w * _2019;
    highp vec4 _2038 = vec4(_1150.xyz * _2035, _2035);
    highp vec4 _1114;
    if (pc.mask_output != 0)
    {
        _1114 = vec4(_2038.w);
    }
    else
    {
        if (pc.output_srgb != 0)
        {
            highp vec4 _2040;
            do
            {
                highp float _2044 = _2038.w;
                if (_2044 <= 0.0)
                {
                    _2040 = vec4(0.0);
                    break;
                }
                highp vec3 _2050 = _2038.xyz * (1.0 / _2044);
                highp float _2060 = max(_2050.x, 0.0);
                highp float _2069;
                if (_2060 <= 0.003130800090730190277099609375)
                {
                    _2069 = _2060 * 12.9200000762939453125;
                }
                else
                {
                    _2069 = (1.05499994754791259765625 * pow(_2060, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                highp float _2063 = max(_2050.y, 0.0);
                highp float _2081;
                if (_2063 <= 0.003130800090730190277099609375)
                {
                    _2081 = _2063 * 12.9200000762939453125;
                }
                else
                {
                    _2081 = (1.05499994754791259765625 * pow(_2063, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                highp float _2066 = max(_2050.z, 0.0);
                highp float _2093;
                if (_2066 <= 0.003130800090730190277099609375)
                {
                    _2093 = _2066 * 12.9200000762939453125;
                }
                else
                {
                    _2093 = (1.05499994754791259765625 * pow(_2066, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                _2040 = vec4(vec3(_2069, _2081, _2093) * _2044, _2044);
                break;
            } while(false);
            _1114 = _2040;
        }
        else
        {
            _1114 = _2038;
        }
    }
    highp vec4 _1115 = _1114;
    entryPointParam_fragmentMain = _1115;
}


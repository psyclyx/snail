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

uniform highp sampler2D SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler;
uniform highp usampler2DArray SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler;
uniform highp sampler2DArray SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler;

in highp vec4 snail_io0;
in highp vec3 snail_io1;
flat in ivec2 snail_io2;
flat in uvec4 snail_io3;
flat in uvec3 snail_io4;
flat in highp vec4 snail_io5;
flat in highp vec4 snail_io6;
flat in highp vec4 snail_io7;
flat in highp vec4 snail_io8;
flat in highp vec4 snail_io9;
flat in highp vec4 snail_io10;
flat in highp vec4 snail_io11;
flat in highp vec4 snail_io12;
flat in uvec4 snail_io13;
flat in uvec4 snail_io14;
layout(location = 0) out highp vec4 entryPointParam_fragmentMain;

void main()
{
    bool _8147 = false;
    bool _5778 = false;
    highp vec4 _12471 = snail_io0;
    uvec4 _12474 = snail_io3;
    uvec3 _12475 = snail_io4;
    highp vec4 _12507 = snail_io5;
    highp vec4 _12508 = snail_io6;
    highp vec4 _12509 = snail_io7;
    highp vec4 _12510 = snail_io8;
    highp vec4 _12520 = snail_io9;
    highp vec4 _12521 = snail_io10;
    highp vec4 _12522 = snail_io11;
    highp vec4 _12523 = snail_io12;
    uvec4 _12478 = snail_io13;
    uvec4 _12479 = snail_io14;
    highp vec4 _4737 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(snail_io2, 0).xy, 0);
    int _4952 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
    int _4957 = ((snail_io2.y * _4952) + snail_io2.x) + 1;
    highp vec4 _4743 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_4957 - _4952 * (_4957 / _4952), _4957 / _4952), 0).xy, 0);
    int _4747 = int(_4737.x + 0.5);
    int _4750 = int(_4737.y + 0.5);
    int _4753 = floatBitsToInt(_4737.z);
    int _4754 = _4753 & 65535;
    int _4756 = (_4753 >> 16) & 65535;
    int _4761 = pc.layer_base + int(snail_io1.z);
    highp vec2 _4703 = snail_io1.xy;
    highp vec2 _4963 = fwidth(snail_io1.xy);
    highp float _4764 = _4963.x;
    highp float _4765 = 1.0 / _4764;
    highp float _4766 = _4963.y;
    highp float _4767 = 1.0 / _4766;
    int _4704 = 0;
    int _4705 = 0;
    int _5002 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
    int _5007 = ((snail_io2.y * _5002) + snail_io2.x) + 2;
    highp vec4 _4973 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_5007 - _5002 * (_5007 / _5002), _5007 / _5002), 0).xy, 0);
    highp float _4964;
    if (false)
    {
        _4964 = _4973.x;
    }
    else
    {
        if (false)
        {
            _4964 = _4973.y;
        }
        else
        {
            if (true)
            {
                _4964 = _4973.z;
            }
            else
            {
                _4964 = _4973.w;
            }
        }
    }
    bool _5012;
    do
    {
        bool _5041;
        if (!isnan(_4964))
        {
            _5041 = !isinf(_4964);
        }
        else
        {
            _5041 = false;
        }
        bool _5013;
        if (!_5041)
        {
            _5013 = true;
        }
        else
        {
            _5013 = _4964 < 0.0;
        }
        if (_5013)
        {
            _5013 = true;
        }
        else
        {
            _5013 = _4964 > 32.0;
        }
        if (_5013)
        {
            _5013 = true;
        }
        else
        {
            _5013 = floor(_4964) != _4964;
        }
        if (_5013)
        {
            _4704 = 0;
            _5012 = false;
            break;
        }
        _4704 = int(_4964);
        _5012 = true;
        break;
    } while(false);
    int _4771 = 2 * _4704;
    int _4772 = 12 + _4771;
    bool _4707;
    if (_5012)
    {
        int _5090 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
        int _5095 = ((snail_io2.y * _5090) + snail_io2.x) + (_4772 >> 2);
        highp vec4 _5061 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_5095 - _5090 * (_5095 / _5090), _5095 / _5090), 0).xy, 0);
        int _5063 = _4771 & 3;
        highp float _5052;
        if (_5063 == 0)
        {
            _5052 = _5061.x;
        }
        else
        {
            if (_5063 == 1)
            {
                _5052 = _5061.y;
            }
            else
            {
                if (_5063 == 2)
                {
                    _5052 = _5061.z;
                }
                else
                {
                    _5052 = _5061.w;
                }
            }
        }
        bool _5100;
        do
        {
            bool _5129;
            if (!isnan(_5052))
            {
                _5129 = !isinf(_5052);
            }
            else
            {
                _5129 = false;
            }
            bool _5101;
            if (!_5129)
            {
                _5101 = true;
            }
            else
            {
                _5101 = _5052 < 0.0;
            }
            if (_5101)
            {
                _5101 = true;
            }
            else
            {
                _5101 = _5052 > 32.0;
            }
            if (_5101)
            {
                _5101 = true;
            }
            else
            {
                _5101 = floor(_5052) != _5052;
            }
            if (_5101)
            {
                _4705 = 0;
                _5100 = false;
                break;
            }
            _4705 = int(_5052);
            _5100 = true;
            break;
        } while(false);
        _4707 = _5100;
    }
    else
    {
        _4707 = false;
    }
    int _4781 = (_4771 + 13) + (4 * _4705);
    if (_4707)
    {
        int _5178 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
        int _5183 = ((snail_io2.y * _5178) + snail_io2.x) + (_4781 >> 2);
        highp vec4 _5149 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_5183 - _5178 * (_5183 / _5178), _5183 / _5178), 0).xy, 0);
        int _5151 = _4781 & 3;
        highp float _5140;
        if (_5151 == 0)
        {
            _5140 = _5149.x;
        }
        else
        {
            if (_5151 == 1)
            {
                _5140 = _5149.y;
            }
            else
            {
                if (_5151 == 2)
                {
                    _5140 = _5149.z;
                }
                else
                {
                    _5140 = _5149.w;
                }
            }
        }
        bool _5188;
        do
        {
            bool _5217;
            if (!isnan(_5140))
            {
                _5217 = !isinf(_5140);
            }
            else
            {
                _5217 = false;
            }
            bool _5189;
            if (!_5217)
            {
                _5189 = true;
            }
            else
            {
                _5189 = _5140 < 0.0;
            }
            if (_5189)
            {
                _5189 = true;
            }
            else
            {
                _5189 = _5140 > 32.0;
            }
            if (_5189)
            {
                _5189 = true;
            }
            else
            {
                _5189 = floor(_5140) != _5140;
            }
            if (_5189)
            {
                _5188 = false;
                break;
            }
            _5188 = true;
            break;
        } while(false);
        _4707 = _5188;
    }
    else
    {
        _4707 = false;
    }
    int _4709;
    if (_4707)
    {
        int _5229;
        do
        {
            if ((_12478.x & 255u) == 254u)
            {
                _5229 = -1;
                break;
            }
            int _5230 = 0;
            int _5231 = 0;
            for (;;)
            {
                if (!(_5230 < 16))
                {
                    break;
                }
                uvec4 _5274 = _12478;
                if (((_5274[_5230 >> 2] >> uint((_5230 & 3) * 8)) & 255u) == 255u)
                {
                    break;
                }
                _5230++;
                _5231++;
                continue;
            }
            _5229 = _5231;
            break;
        } while(false);
        _4709 = _5229;
    }
    else
    {
        _4709 = 0;
    }
    int _4708 = _4709;
    if (_4707)
    {
        int _5286;
        do
        {
            if ((_12479.x & 255u) == 254u)
            {
                _5286 = -1;
                break;
            }
            int _5287 = 0;
            int _5288 = 0;
            for (;;)
            {
                if (!(_5287 < 16))
                {
                    break;
                }
                uvec4 _5331 = _12479;
                if (((_5331[_5287 >> 2] >> uint((_5287 & 3) * 8)) & 255u) == 255u)
                {
                    break;
                }
                _5287++;
                _5288++;
                continue;
            }
            _5286 = _5288;
            break;
        } while(false);
        _4709 = _5286;
    }
    else
    {
        _4709 = 0;
    }
    int _4710 = _4709;
    highp float _4711 = 1.0;
    highp float _4712 = 1.0;
    int _4804 = _4708;
    bool _4805 = _4804 < 0;
    bool _4807 = _4709 < 0;
    if (_4707)
    {
        if (_4805)
        {
            _4707 = true;
        }
        else
        {
            _4707 = _4807;
        }
    }
    else
    {
        _4707 = false;
    }
    if (_4707)
    {
        int _5380 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
        int _5385 = ((snail_io2.y * _5380) + snail_io2.x) + 2;
        highp vec4 _5351 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_5385 - _5380 * (_5385 / _5380), _5385 / _5380), 0).xy, 0);
        highp float _5342;
        if (true)
        {
            _5342 = _5351.x;
        }
        else
        {
            if (false)
            {
                _5342 = _5351.y;
            }
            else
            {
                if (false)
                {
                    _5342 = _5351.z;
                }
                else
                {
                    _5342 = _5351.w;
                }
            }
        }
        int _5427 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
        int _5432 = ((snail_io2.y * _5427) + snail_io2.x) + 2;
        highp vec4 _5398 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_5432 - _5427 * (_5432 / _5427), _5432 / _5427), 0).xy, 0);
        highp float _5389;
        if (false)
        {
            _5389 = _5398.x;
        }
        else
        {
            if (true)
            {
                _5389 = _5398.y;
            }
            else
            {
                if (false)
                {
                    _5389 = _5398.z;
                }
                else
                {
                    _5389 = _5398.w;
                }
            }
        }
        bool _5437;
        int _12330;
        int _12331;
        int _12332;
        int _12333;
        int _12334;
        int _12335;
        int _12336;
        int _12337;
        highp float _12338;
        highp float _12339;
        highp float _12340;
        highp float _12341;
        highp float _12342;
        highp float _12343;
        highp float _12344;
        do
        {
            _12330 = 0;
            _12331 = 0;
            _12332 = 0;
            _12333 = 0;
            _12334 = 0;
            _12335 = 0;
            _12336 = 0;
            _12337 = 0;
            _12338 = 0.0;
            _12339 = 0.0;
            _12340 = 0.0;
            _12341 = 0.0;
            _12342 = 0.0;
            _12343 = 0.0;
            _12344 = 0.0;
            bool _5438;
            if ((_12474.x & 4286578688u) != 0u)
            {
                _5438 = true;
            }
            else
            {
                _5438 = (_12474.y & 4294967232u) != 0u;
            }
            if (_5438)
            {
                _5437 = false;
                break;
            }
            int _5456 = int(_12474.x & 3u);
            _12330 = _5456;
            _12331 = int((_12474.x >> 2u) & 3u);
            _12332 = int((_12474.x >> 4u) & 3u);
            _12333 = int((_12474.x >> 6u) & 3u);
            _12337 = int((_12474.x >> 8u) & 1u);
            _12338 = float((_12474.x >> 9u) & 127u);
            _12339 = float((_12474.x >> 16u) & 127u);
            _12334 = int(_12474.y & 3u);
            _12335 = int((_12474.y >> 2u) & 3u);
            _12336 = int((_12474.y >> 4u) & 3u);
            if (_5456 > 1)
            {
                _5438 = true;
            }
            else
            {
                _5438 = _12331 > 2;
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                _5438 = _12332 > 1;
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                _5438 = _12333 > 1;
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                _5438 = _12334 > 2;
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                _5438 = _12335 > 2;
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                _5438 = _12336 > 1;
            }
            if (_5438)
            {
                _5437 = false;
                break;
            }
            _12340 = uintBitsToFloat(_12474.z);
            _12341 = uintBitsToFloat(_12474.w);
            _12342 = uintBitsToFloat(_12475.x);
            _12343 = uintBitsToFloat(_12475.y);
            _12344 = uintBitsToFloat(_12475.z);
            if (_12331 != 0)
            {
                bool _5654;
                if (!isnan(_12340))
                {
                    _5654 = !isinf(_12340);
                }
                else
                {
                    _5654 = false;
                }
                if (!_5654)
                {
                    _5438 = true;
                }
                else
                {
                    _5438 = _12340 < 0.0;
                }
            }
            else
            {
                _5438 = false;
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                if (_12331 == 1)
                {
                    bool _5665;
                    if (!isnan(_12341))
                    {
                        _5665 = !isinf(_12341);
                    }
                    else
                    {
                        _5665 = false;
                    }
                    if (!_5665)
                    {
                        _5438 = true;
                    }
                    else
                    {
                        _5438 = _12341 < 0.0;
                    }
                }
                else
                {
                    _5438 = false;
                }
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                if (_12335 != 0)
                {
                    bool _5676;
                    if (!isnan(_12342))
                    {
                        _5676 = !isinf(_12342);
                    }
                    else
                    {
                        _5676 = false;
                    }
                    if (!_5676)
                    {
                        _5438 = true;
                    }
                    else
                    {
                        _5438 = _12342 < 0.0;
                    }
                }
                else
                {
                    _5438 = false;
                }
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                if (_12335 == 1)
                {
                    bool _5687;
                    if (!isnan(_12343))
                    {
                        _5687 = !isinf(_12343);
                    }
                    else
                    {
                        _5687 = false;
                    }
                    if (!_5687)
                    {
                        _5438 = true;
                    }
                    else
                    {
                        _5438 = _12343 < 0.0;
                    }
                }
                else
                {
                    _5438 = false;
                }
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                if (_12336 == 1)
                {
                    bool _5698;
                    if (!isnan(_12344))
                    {
                        _5698 = !isinf(_12344);
                    }
                    else
                    {
                        _5698 = false;
                    }
                    if (!_5698)
                    {
                        _5438 = true;
                    }
                    else
                    {
                        _5438 = _12344 < 0.0;
                    }
                }
                else
                {
                    _5438 = false;
                }
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                if (_12332 == 1)
                {
                    _5438 = _12330 == 0;
                }
                else
                {
                    _5438 = false;
                }
            }
            if (_5438)
            {
                _5438 = true;
            }
            else
            {
                if (_12336 == 1)
                {
                    _5438 = _12334 != 2;
                }
                else
                {
                    _5438 = false;
                }
            }
            if (_5438)
            {
                _5437 = false;
                break;
            }
            _5437 = true;
            break;
        } while(false);
        if (_5437)
        {
            bool _5709;
            if (!isnan(_5342))
            {
                _5709 = !isinf(_5342);
            }
            else
            {
                _5709 = false;
            }
            _4707 = _5709;
        }
        else
        {
            _4707 = false;
        }
        if (_4707)
        {
            _4707 = _5342 >= 0.0;
        }
        else
        {
            _4707 = false;
        }
        if (_4707)
        {
            bool _5720;
            if (!isnan(_5389))
            {
                _5720 = !isinf(_5389);
            }
            else
            {
                _5720 = false;
            }
            _4707 = _5720;
        }
        else
        {
            _4707 = false;
        }
        if (_4707)
        {
            _4707 = _5389 >= 0.0;
        }
        else
        {
            _4707 = false;
        }
        bool _4714;
        if (_4707)
        {
            _4714 = _4805;
        }
        else
        {
            _4714 = false;
        }
        if (_4714)
        {
            int _5769 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
            int _5774 = ((snail_io2.y * _5769) + snail_io2.x) + 2;
            highp vec4 _5740 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_5774 - _5769 * (_5774 / _5769), _5774 / _5769), 0).xy, 0);
            highp float _5731;
            if (false)
            {
                _5731 = _5740.x;
            }
            else
            {
                if (false)
                {
                    _5731 = _5740.y;
                }
                else
                {
                    if (false)
                    {
                        _5731 = _5740.z;
                    }
                    else
                    {
                        _5731 = _5740.w;
                    }
                }
            }
            int _12392 = _12330;
            int _12393 = _12331;
            int _12394 = _12332;
            int _12395 = _12333;
            int _12396 = _12334;
            int _12397 = _12335;
            int _12398 = _12336;
            int _12399 = _12337;
            highp float _12400 = _12338;
            highp float _12401 = _12339;
            highp float _12402 = _12340;
            highp float _12403 = _12341;
            highp float _12404 = _12342;
            highp float _12405 = _12343;
            highp float _12406 = _12344;
            _5778 = false;
            highp float _4715[32];
            highp float _4716[32];
            bool _5779;
            do
            {
                _4708 = 0;
                int _5780 = 0;
                for (;;)
                {
                    if (!(_5780 < 32))
                    {
                        break;
                    }
                    _4715[_5780] = 0.0;
                    _4716[_5780] = 0.0;
                    _5780++;
                    continue;
                }
                bool _7295;
                if (!isnan(_4765))
                {
                    _7295 = !isinf(_4765);
                }
                else
                {
                    _7295 = false;
                }
                bool _5781;
                if (!_7295)
                {
                    _5781 = true;
                }
                else
                {
                    _5781 = _4765 <= 0.0;
                }
                if (_5781)
                {
                    _5781 = true;
                }
                else
                {
                    _5781 = _4704 < 0;
                }
                if (_5781)
                {
                    _5781 = true;
                }
                else
                {
                    _5781 = _4704 > 32;
                }
                if (_5781)
                {
                    _5781 = true;
                }
                else
                {
                    bool _7306;
                    if (!isnan(_5342))
                    {
                        _7306 = !isinf(_5342);
                    }
                    else
                    {
                        _7306 = false;
                    }
                    _5781 = !_7306;
                }
                if (_5781)
                {
                    _5781 = true;
                }
                else
                {
                    _5781 = _5342 < 0.0;
                }
                if (_5781)
                {
                    _5778 = true;
                    _5779 = false;
                    break;
                }
                if (true)
                {
                    _5781 = _12392 == 0;
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    _5781 = _12393 == 0;
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    _5781 = _12394 == 0;
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    _5781 = _12395 == 0;
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    _5781 = true;
                }
                else
                {
                    if (false)
                    {
                        _5781 = _12396 == 0;
                    }
                    else
                    {
                        _5781 = false;
                    }
                    if (_5781)
                    {
                        _5781 = _12397 == 0;
                    }
                    else
                    {
                        _5781 = false;
                    }
                    if (_5781)
                    {
                        _5781 = _12398 == 0;
                    }
                    else
                    {
                        _5781 = false;
                    }
                }
                if (_5781)
                {
                    _5778 = true;
                    _5779 = true;
                    break;
                }
                int _7355 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _7360 = ((snail_io2.y * _7355) + snail_io2.x) + (_4772 >> 2);
                highp vec4 _7326 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7360 - _7355 * (_7360 / _7355), _7360 / _7355), 0).xy, 0);
                int _7328 = _4771 & 3;
                highp float _7317;
                if (_7328 == 0)
                {
                    _7317 = _7326.x;
                }
                else
                {
                    if (_7328 == 1)
                    {
                        _7317 = _7326.y;
                    }
                    else
                    {
                        if (_7328 == 2)
                        {
                            _7317 = _7326.z;
                        }
                        else
                        {
                            _7317 = _7326.w;
                        }
                    }
                }
                int _5936 = int(_7317);
                if (_5936 <= 0)
                {
                    _5781 = true;
                }
                else
                {
                    _5781 = _5936 > 32;
                }
                if (_5781)
                {
                    _5778 = true;
                    _5779 = _5936 == 0;
                    break;
                }
                if (false)
                {
                    _5781 = _12396 == 2;
                }
                else
                {
                    _5781 = false;
                }
                bool _5782;
                if (true)
                {
                    _5782 = _12395 == 1;
                }
                else
                {
                    _5782 = false;
                }
                if (_5782)
                {
                    bool _7364;
                    if (!isnan(_5731))
                    {
                        _7364 = !isinf(_5731);
                    }
                    else
                    {
                        _7364 = false;
                    }
                    _5782 = !_7364;
                }
                else
                {
                    _5782 = false;
                }
                if (_5782)
                {
                    _5778 = true;
                    _5779 = false;
                    break;
                }
                _5780 = 0;
                highp float _5783[32];
                highp float _5784[32];
                int _5785[32];
                int _5786[32];
                bool _5787[32];
                bool _5788[32];
                bool _5790[32];
                bool _5791[32];
                int _5792[32];
                int _5793[32];
                bool _5796[32];
                bool _5799;
                bool _5800;
                bool _5801;
                bool _5802;
                bool _5803;
                highp float _7375;
                highp float _7422;
                highp float _7469;
                highp float _7516;
                bool _7563;
                bool _7574;
                for (;;)
                {
                    if (!(_5780 < 32))
                    {
                        break;
                    }
                    if (_5780 >= _5936)
                    {
                        break;
                    }
                    int _5983 = (_4771 + 13) + (4 * _5780);
                    int _7413 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _7418 = ((snail_io2.y * _7413) + snail_io2.x) + (_5983 >> 2);
                    highp vec4 _7384 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7418 - _7413 * (_7418 / _7413), _7418 / _7413), 0).xy, 0);
                    int _7386 = _5983 & 3;
                    if (_7386 == 0)
                    {
                        _7375 = _7384.x;
                    }
                    else
                    {
                        if (_7386 == 1)
                        {
                            _7375 = _7384.y;
                        }
                        else
                        {
                            if (_7386 == 2)
                            {
                                _7375 = _7384.z;
                            }
                            else
                            {
                                _7375 = _7384.w;
                            }
                        }
                    }
                    _5783[_5780] = _7375;
                    int _7425 = _5983 + 1;
                    int _7460 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _7465 = ((snail_io2.y * _7460) + snail_io2.x) + (_7425 >> 2);
                    highp vec4 _7431 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7465 - _7460 * (_7465 / _7460), _7465 / _7460), 0).xy, 0);
                    int _7433 = _7425 & 3;
                    if (_7433 == 0)
                    {
                        _7422 = _7431.x;
                    }
                    else
                    {
                        if (_7433 == 1)
                        {
                            _7422 = _7431.y;
                        }
                        else
                        {
                            if (_7433 == 2)
                            {
                                _7422 = _7431.z;
                            }
                            else
                            {
                                _7422 = _7431.w;
                            }
                        }
                    }
                    _5784[_5780] = _7422;
                    int _7472 = _5983 + 2;
                    int _7507 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _7512 = ((snail_io2.y * _7507) + snail_io2.x) + (_7472 >> 2);
                    highp vec4 _7478 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7512 - _7507 * (_7512 / _7507), _7512 / _7507), 0).xy, 0);
                    int _7480 = _7472 & 3;
                    if (_7480 == 0)
                    {
                        _7469 = _7478.x;
                    }
                    else
                    {
                        if (_7480 == 1)
                        {
                            _7469 = _7478.y;
                        }
                        else
                        {
                            if (_7480 == 2)
                            {
                                _7469 = _7478.z;
                            }
                            else
                            {
                                _7469 = _7478.w;
                            }
                        }
                    }
                    _5785[_5780] = int(floatBitsToUint(_7469) << 16u) >> 16;
                    _5786[_5780] = floatBitsToInt(_7469) >> 16;
                    int _7519 = _5983 + 3;
                    int _7554 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _7559 = ((snail_io2.y * _7554) + snail_io2.x) + (_7519 >> 2);
                    highp vec4 _7525 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7559 - _7554 * (_7559 / _7554), _7559 / _7554), 0).xy, 0);
                    int _7527 = _7519 & 3;
                    if (_7527 == 0)
                    {
                        _7516 = _7525.x;
                    }
                    else
                    {
                        if (_7527 == 1)
                        {
                            _7516 = _7525.y;
                        }
                        else
                        {
                            if (_7527 == 2)
                            {
                                _7516 = _7525.z;
                            }
                            else
                            {
                                _7516 = _7525.w;
                            }
                        }
                    }
                    uint _6002 = floatBitsToUint(_7516);
                    _5787[_5780] = (_6002 & 1u) != 0u;
                    _5788[_5780] = (_6002 & 2u) != 0u;
                    _5790[_5780] = (_6002 & 4u) != 0u;
                    _5791[_5780] = (_6002 & 8u) != 0u;
                    _5792[_5780] = int((_6002 >> 4u) & 63u);
                    _5793[_5780] = int((_6002 >> 10u) & 63u);
                    _5796[_5780] = false;
                    if (!isnan(_5783[_5780]))
                    {
                        _7563 = !isinf(_5783[_5780]);
                    }
                    else
                    {
                        _7563 = false;
                    }
                    if (!_7563)
                    {
                        _5782 = true;
                    }
                    else
                    {
                        if (!isnan(_5784[_5780]))
                        {
                            _7574 = !isinf(_5784[_5780]);
                        }
                        else
                        {
                            _7574 = false;
                        }
                        _5782 = !_7574;
                    }
                    if (_5782)
                    {
                        _5799 = true;
                    }
                    else
                    {
                        _5799 = _5784[_5780] < 0.0;
                    }
                    if (_5799)
                    {
                        _5800 = true;
                    }
                    else
                    {
                        _5800 = _5785[_5780] < (-1);
                    }
                    if (_5800)
                    {
                        _5801 = true;
                    }
                    else
                    {
                        _5801 = _5785[_5780] >= _5936;
                    }
                    if (_5801)
                    {
                        _5802 = true;
                    }
                    else
                    {
                        _5802 = _5786[_5780] < (-1);
                    }
                    if (_5802)
                    {
                        _5803 = true;
                    }
                    else
                    {
                        _5803 = _5786[_5780] >= _4704;
                    }
                    if (_5803)
                    {
                        _5778 = true;
                        _5779 = false;
                        break;
                    }
                    _5780++;
                    continue;
                }
                if (_5778)
                {
                    break;
                }
                _5780 = 0;
                highp float _7585;
                highp float _7632;
                bool _7679;
                bool _7690;
                for (;;)
                {
                    if (!(_5780 < 32))
                    {
                        break;
                    }
                    if (_5780 >= _4704)
                    {
                        break;
                    }
                    int _6095 = 2 * _5780;
                    int _7623 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _7628 = ((snail_io2.y * _7623) + snail_io2.x) + ((12 + _6095) >> 2);
                    highp vec4 _7594 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7628 - _7623 * (_7628 / _7623), _7628 / _7623), 0).xy, 0);
                    int _7596 = _6095 & 3;
                    if (_7596 == 0)
                    {
                        _7585 = _7594.x;
                    }
                    else
                    {
                        if (_7596 == 1)
                        {
                            _7585 = _7594.y;
                        }
                        else
                        {
                            if (_7596 == 2)
                            {
                                _7585 = _7594.z;
                            }
                            else
                            {
                                _7585 = _7594.w;
                            }
                        }
                    }
                    int _7635 = _6095 + 13;
                    int _7670 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _7675 = ((snail_io2.y * _7670) + snail_io2.x) + (_7635 >> 2);
                    highp vec4 _7641 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7675 - _7670 * (_7675 / _7670), _7675 / _7670), 0).xy, 0);
                    int _7643 = _7635 & 3;
                    if (_7643 == 0)
                    {
                        _7632 = _7641.x;
                    }
                    else
                    {
                        if (_7643 == 1)
                        {
                            _7632 = _7641.y;
                        }
                        else
                        {
                            if (_7643 == 2)
                            {
                                _7632 = _7641.z;
                            }
                            else
                            {
                                _7632 = _7641.w;
                            }
                        }
                    }
                    if (!isnan(_7585))
                    {
                        _7679 = !isinf(_7585);
                    }
                    else
                    {
                        _7679 = false;
                    }
                    if (!_7679)
                    {
                        _5782 = true;
                    }
                    else
                    {
                        if (!isnan(_7632))
                        {
                            _7690 = !isinf(_7632);
                        }
                        else
                        {
                            _7690 = false;
                        }
                        _5782 = !_7690;
                    }
                    if (_5782)
                    {
                        _5778 = true;
                        _5779 = false;
                        break;
                    }
                    _5780++;
                    continue;
                }
                if (_5778)
                {
                    break;
                }
                _5780 = 0;
                bool _7701;
                bool _7712;
                for (;;)
                {
                    if (!(_5780 < 32))
                    {
                        break;
                    }
                    if (_5780 >= _5936)
                    {
                        break;
                    }
                    if (_5785[_5780] >= 0)
                    {
                        if (_5785[_5780] >= _5936)
                        {
                            _5782 = true;
                        }
                        else
                        {
                            _5782 = _5785[_5780] == _5780;
                        }
                        if (_5782)
                        {
                            _5799 = true;
                        }
                        else
                        {
                            _5799 = _5785[_5785[_5780]] != _5780;
                        }
                        if (_5799)
                        {
                            _5800 = true;
                        }
                        else
                        {
                            if (!isnan(_5783[_5785[_5780]]))
                            {
                                _7701 = !isinf(_5783[_5785[_5780]]);
                            }
                            else
                            {
                                _7701 = false;
                            }
                            _5800 = !_7701;
                        }
                        if (_5800)
                        {
                            _5801 = true;
                        }
                        else
                        {
                            _5801 = _5783[_5785[_5780]] == _5783[_5780];
                        }
                        if (_5801)
                        {
                            _5802 = true;
                        }
                        else
                        {
                            if (!isnan(_5784[_5785[_5780]]))
                            {
                                _7712 = !isinf(_5784[_5785[_5780]]);
                            }
                            else
                            {
                                _7712 = false;
                            }
                            _5802 = !_7712;
                        }
                        if (_5802)
                        {
                            _5803 = true;
                        }
                        else
                        {
                            _5803 = _5784[_5785[_5780]] != _5784[_5780];
                        }
                        if (_5803)
                        {
                            _5778 = true;
                            _5779 = false;
                            break;
                        }
                    }
                    _5780++;
                    continue;
                }
                if (_5778)
                {
                    break;
                }
                if (false)
                {
                    _5782 = _12398 == 1;
                }
                else
                {
                    _5782 = false;
                }
                highp float _5804;
                if (_5782)
                {
                    _5804 = _12406;
                }
                else
                {
                    _5804 = 0.0;
                }
                _5780 = 0;
                int _5789[32];
                int _5794[32];
                highp float _5795[32];
                int _5805;
                int _5806;
                int _5807;
                int _5808;
                bool _5809;
                bool _5810;
                bool _5811;
                highp float _5812;
                bool _5813;
                highp float _7723;
                highp float _7770;
                highp float _7817;
                highp float _7864;
                highp float _7916;
                highp float _7963;
                for (;;)
                {
                    if (!(_5780 < 32))
                    {
                        break;
                    }
                    if (_5780 >= _5936)
                    {
                        break;
                    }
                    if (_5785[_5780] >= 0)
                    {
                        _5782 = _5783[_5785[_5780]] > _5783[_5780];
                    }
                    else
                    {
                        _5782 = false;
                    }
                    if (_5781)
                    {
                        _5799 = _5786[_5780] >= 0;
                    }
                    else
                    {
                        _5799 = false;
                    }
                    if (_5799)
                    {
                        int _7726 = (2 * _5786[_5780]) + 13;
                        int _7761 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _7766 = ((snail_io2.y * _7761) + snail_io2.x) + (_7726 >> 2);
                        highp vec4 _7732 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7766 - _7761 * (_7766 / _7761), _7766 / _7761), 0).xy, 0);
                        int _7734 = _7726 & 3;
                        if (_7734 == 0)
                        {
                            _7723 = _7732.x;
                        }
                        else
                        {
                            if (_7734 == 1)
                            {
                                _7723 = _7732.y;
                            }
                            else
                            {
                                if (_7734 == 2)
                                {
                                    _7723 = _7732.z;
                                }
                                else
                                {
                                    _7723 = _7732.w;
                                }
                            }
                        }
                        int _6256 = 2 * _5786[_5780];
                        int _7808 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _7813 = ((snail_io2.y * _7808) + snail_io2.x) + ((12 + _6256) >> 2);
                        highp vec4 _7779 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7813 - _7808 * (_7813 / _7808), _7813 / _7808), 0).xy, 0);
                        int _7781 = _6256 & 3;
                        if (_7781 == 0)
                        {
                            _7770 = _7779.x;
                        }
                        else
                        {
                            if (_7781 == 1)
                            {
                                _7770 = _7779.y;
                            }
                            else
                            {
                                if (_7781 == 2)
                                {
                                    _7770 = _7779.z;
                                }
                                else
                                {
                                    _7770 = _7779.w;
                                }
                            }
                        }
                        _5800 = _7723 < _7770;
                    }
                    else
                    {
                        _5800 = false;
                    }
                    if (!_5790[_5780])
                    {
                        _5801 = _5785[_5780] < 0;
                    }
                    else
                    {
                        _5801 = false;
                    }
                    if (_5801)
                    {
                        _5802 = !_5799;
                    }
                    else
                    {
                        _5802 = false;
                    }
                    if (_5802)
                    {
                        _5803 = _5781;
                    }
                    else
                    {
                        _5803 = false;
                    }
                    if (_5803)
                    {
                        _5812 = 3.4028234663852885981170418348452e+38;
                        _5805 = 1;
                        _5806 = 0;
                        for (;;)
                        {
                            bool _6285_ladder_break = false;
                            do
                            {
                                if (!(_5806 < 32))
                                {
                                    _6285_ladder_break = true;
                                    break;
                                }
                                if (_5806 >= _5936)
                                {
                                    _6285_ladder_break = true;
                                    break;
                                }
                                if (_5786[_5806] < 0)
                                {
                                    break;
                                }
                                highp float _6308 = abs(_5783[_5806] - _5783[_5780]);
                                if (_6308 >= _5812)
                                {
                                    break;
                                }
                                int _7820 = (2 * _5786[_5806]) + 13;
                                int _7855 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                                int _7860 = ((snail_io2.y * _7855) + snail_io2.x) + (_7820 >> 2);
                                highp vec4 _7826 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7860 - _7855 * (_7860 / _7855), _7860 / _7855), 0).xy, 0);
                                int _7828 = _7820 & 3;
                                if (_7828 == 0)
                                {
                                    _7817 = _7826.x;
                                }
                                else
                                {
                                    if (_7828 == 1)
                                    {
                                        _7817 = _7826.y;
                                    }
                                    else
                                    {
                                        if (_7828 == 2)
                                        {
                                            _7817 = _7826.z;
                                        }
                                        else
                                        {
                                            _7817 = _7826.w;
                                        }
                                    }
                                }
                                int _6318 = 2 * _5786[_5806];
                                int _7902 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                                int _7907 = ((snail_io2.y * _7902) + snail_io2.x) + ((12 + _6318) >> 2);
                                highp vec4 _7873 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7907 - _7902 * (_7907 / _7902), _7907 / _7902), 0).xy, 0);
                                int _7875 = _6318 & 3;
                                if (_7875 == 0)
                                {
                                    _7864 = _7873.x;
                                }
                                else
                                {
                                    if (_7875 == 1)
                                    {
                                        _7864 = _7873.y;
                                    }
                                    else
                                    {
                                        if (_7875 == 2)
                                        {
                                            _7864 = _7873.z;
                                        }
                                        else
                                        {
                                            _7864 = _7873.w;
                                        }
                                    }
                                }
                                if (_7817 < _7864)
                                {
                                    _5807 = 1;
                                }
                                else
                                {
                                    _5807 = -1;
                                }
                                _5812 = _6308;
                                _5805 = _5807;
                                break;
                            } while(false);
                            if (_6285_ladder_break)
                            {
                                break;
                            }
                            _5806++;
                            continue;
                        }
                    }
                    else
                    {
                        _5805 = 1;
                    }
                    if (_5790[_5780])
                    {
                        if (_5781)
                        {
                            _5809 = _5791[_5780];
                        }
                        else
                        {
                            _5809 = false;
                        }
                        if (_5809)
                        {
                            _5810 = true;
                        }
                        else
                        {
                            if (!_5781)
                            {
                                _5810 = _5782;
                            }
                            else
                            {
                                _5810 = false;
                            }
                        }
                        if (_5810)
                        {
                            _5806 = -1;
                        }
                        else
                        {
                            _5806 = 1;
                        }
                    }
                    else
                    {
                        if (_5782)
                        {
                            _5809 = true;
                        }
                        else
                        {
                            _5809 = _5800;
                        }
                        if (_5809)
                        {
                            _5806 = -1;
                        }
                        else
                        {
                            _5806 = _5805;
                        }
                    }
                    _5794[_5780] = _5806;
                    if (_5781)
                    {
                        _5807 = _5793[_5780];
                    }
                    else
                    {
                        _5807 = _5792[_5780];
                    }
                    if (!_5790[_5780])
                    {
                        _5809 = true;
                    }
                    else
                    {
                        _5809 = _5807 == 63;
                    }
                    if (_5809)
                    {
                        _5808 = -2;
                    }
                    else
                    {
                        if (_5807 == 62)
                        {
                            _5808 = -1;
                        }
                        else
                        {
                            _5808 = _5807;
                        }
                    }
                    _5789[_5780] = _5808;
                    if (_5799)
                    {
                        int _6413 = 2 * _5786[_5780];
                        int _7954 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _7959 = ((snail_io2.y * _7954) + snail_io2.x) + ((12 + _6413) >> 2);
                        highp vec4 _7925 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_7959 - _7954 * (_7959 / _7954), _7959 / _7954), 0).xy, 0);
                        int _7927 = _6413 & 3;
                        if (_7927 == 0)
                        {
                            _7916 = _7925.x;
                        }
                        else
                        {
                            if (_7927 == 1)
                            {
                                _7916 = _7925.y;
                            }
                            else
                            {
                                if (_7927 == 2)
                                {
                                    _7916 = _7925.z;
                                }
                                else
                                {
                                    _7916 = _7925.w;
                                }
                            }
                        }
                        int _7966 = (2 * _5786[_5780]) + 13;
                        int _8001 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _8006 = ((snail_io2.y * _8001) + snail_io2.x) + (_7966 >> 2);
                        highp vec4 _7972 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_8006 - _8001 * (_8006 / _8001), _8006 / _8001), 0).xy, 0);
                        int _7974 = _7966 & 3;
                        if (_7974 == 0)
                        {
                            _7963 = _7972.x;
                        }
                        else
                        {
                            if (_7974 == 1)
                            {
                                _7963 = _7972.y;
                            }
                            else
                            {
                                if (_7974 == 2)
                                {
                                    _7963 = _7972.z;
                                }
                                else
                                {
                                    _7963 = _7972.w;
                                }
                            }
                        }
                        if (_5787[_5780])
                        {
                            _5810 = false;
                        }
                        else
                        {
                            _5810 = false;
                        }
                        if (_5810)
                        {
                            _5811 = _12398 == 0;
                        }
                        else
                        {
                            _5811 = false;
                        }
                        if (_5811)
                        {
                            _5795[_5780] = _5783[_5780];
                        }
                        else
                        {
                            _5795[_5780] = round(_7916 * _4765) / _4765;
                            if (_5787[_5780])
                            {
                                _5813 = abs((_7963 - _7916) * _4765) >= _5804;
                            }
                            else
                            {
                                _5813 = false;
                            }
                            if (_5813)
                            {
                                _5795[_5780] += (_7963 - _7916);
                            }
                        }
                    }
                    else
                    {
                        _5795[_5780] = round(_5783[_5780] * _4765) / _4765;
                    }
                    _5780++;
                    continue;
                }
                if (true)
                {
                    _5805 = _12393;
                }
                else
                {
                    _5805 = _12397;
                }
                if (true)
                {
                    _5804 = _12402;
                }
                else
                {
                    _5804 = _12404;
                }
                if (true)
                {
                    _5812 = _12403;
                }
                else
                {
                    _5812 = _12405;
                }
                if (true)
                {
                    _5781 = _12392 == 1;
                }
                else
                {
                    _5781 = _12396 != 0;
                }
                if (true)
                {
                    _5782 = _12394 == 1;
                }
                else
                {
                    _5782 = false;
                }
                _5799 = false;
                highp float _5814 = 0.0;
                highp float _5815 = 0.0;
                highp float _5816 = 0.0;
                highp float _5817 = 0.0;
                highp float _5818 = 0.0;
                _5806 = 0;
                _5780 = 0;
                _5807 = 0;
                int _5819;
                highp float _5820;
                highp float _5821;
                highp float _5822;
                highp float _5823;
                highp float _5824;
                highp float _5825;
                bool _8015;
                highp float _8016;
                for (;;)
                {
                    bool _6505_ladder_break = false;
                    do
                    {
                        if (!(_5780 < 32))
                        {
                            _6505_ladder_break = true;
                            break;
                        }
                        if (_5780 >= _5936)
                        {
                            _6505_ladder_break = true;
                            break;
                        }
                        if (_5785[_5780] < 0)
                        {
                            _5800 = true;
                        }
                        else
                        {
                            _5800 = _5785[_5780] <= _5780;
                        }
                        if (_5800)
                        {
                            _5802 = _5799;
                            break;
                        }
                        if (_5342 > 0.0)
                        {
                            _8015 = abs(_5784[_5780] - _5342) <= (_5804 * _5342);
                        }
                        else
                        {
                            _8015 = false;
                        }
                        if (_8015)
                        {
                            _8016 = _5342;
                        }
                        else
                        {
                            _8016 = _5784[_5780];
                        }
                        if (_5805 == 2)
                        {
                            _5801 = true;
                        }
                        else
                        {
                            if (_5805 == 1)
                            {
                                _5801 = (_8016 * _4765) < _5812;
                            }
                            else
                            {
                                _5801 = false;
                            }
                        }
                        if (_5801)
                        {
                            _5820 = max(round(_8016 * _4765), 1.0) * _4764;
                        }
                        else
                        {
                            _5820 = _5784[_5780];
                        }
                        if (_5782)
                        {
                            if (_5799)
                            {
                                _5795[_5780] = _5814 + (round((_5783[_5780] - _5815) * _4765) * _4764);
                                _5821 = _5816;
                                _5822 = _5817;
                                _5802 = _5799;
                            }
                            else
                            {
                                highp float _8036 = round(_5783[_5780] * _4765) / _4765;
                                _5795[_5780] = _8036;
                                _5821 = _8036;
                                _5822 = _5783[_5780];
                                _5802 = true;
                            }
                            _5795[_5785[_5780]] = _5795[_5780] + _5820;
                            highp float _6663 = _5822;
                            highp float _6668 = _5821;
                            _5821 = _5795[_5780];
                            _5822 = _5783[_5780];
                            _5823 = _6668;
                            _5824 = _6663;
                            _5825 = (_6668 + (round((_5783[_5780] - _6663) * _4765) * _4764)) + _5820;
                            _5808 = _5785[_5780];
                            _5819 = _5807 + 1;
                        }
                        else
                        {
                            if (true)
                            {
                                _5802 = _12392 != 0;
                            }
                            else
                            {
                                _5802 = _12396 != 0;
                            }
                            if (_5802)
                            {
                                _5803 = _5786[_5780] >= 0;
                            }
                            else
                            {
                                _5803 = false;
                            }
                            if (_5802)
                            {
                                _5809 = _5786[_5785[_5780]] >= 0;
                            }
                            else
                            {
                                _5809 = false;
                            }
                            if (!_5781)
                            {
                                _5795[_5780] = _5783[_5780];
                            }
                            if (_5809)
                            {
                                _5810 = !_5803;
                            }
                            else
                            {
                                _5810 = false;
                            }
                            if (_5810)
                            {
                                _5811 = _5781;
                            }
                            else
                            {
                                _5811 = false;
                            }
                            if (_5811)
                            {
                                _5795[_5780] = _5795[_5785[_5780]] - _5820;
                            }
                            else
                            {
                                _5795[_5785[_5780]] = _5795[_5780] + _5820;
                            }
                            _5802 = _5799;
                            _5821 = _5814;
                            _5822 = _5815;
                            _5823 = _5816;
                            _5824 = _5817;
                            _5825 = _5818;
                            _5808 = _5806;
                            _5819 = _5807;
                        }
                        _5796[_5780] = true;
                        _5796[_5785[_5780]] = true;
                        _5814 = _5821;
                        _5815 = _5822;
                        _5816 = _5823;
                        _5817 = _5824;
                        _5818 = _5825;
                        _5806 = _5808;
                        _5807 = _5819;
                        break;
                    } while(false);
                    if (_6505_ladder_break)
                    {
                        break;
                    }
                    _5799 = _5802;
                    _5780++;
                    continue;
                }
                if (_5782)
                {
                    _5781 = _5807 > 1;
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    highp float _6706 = _5818 - _5795[_5806];
                    _5780 = 0;
                    for (;;)
                    {
                        if (!(_5780 < 32))
                        {
                            break;
                        }
                        if (_5780 >= _5936)
                        {
                            break;
                        }
                        if (_5796[_5780])
                        {
                            _5795[_5780] += _6706;
                        }
                        _5780++;
                        continue;
                    }
                }
                if (_5805 == 1)
                {
                    _5804 = _5812;
                }
                else
                {
                    _5804 = 1.60000002384185791015625;
                }
                _5780 = 0;
                for (;;)
                {
                    bool _6743_ladder_break = false;
                    do
                    {
                        if (!(_5780 < 32))
                        {
                            _6743_ladder_break = true;
                            break;
                        }
                        if (_5780 >= _5936)
                        {
                            _6743_ladder_break = true;
                            break;
                        }
                        if (true)
                        {
                            _5802 = _12392 != 0;
                        }
                        else
                        {
                            _5802 = _12396 != 0;
                        }
                        if (!_5802)
                        {
                            _5781 = true;
                        }
                        else
                        {
                            _5781 = _5786[_5780] < 0;
                        }
                        if (_5781)
                        {
                            _5782 = true;
                        }
                        else
                        {
                            _5782 = !_5787[_5780];
                        }
                        if (_5782)
                        {
                            _5799 = true;
                        }
                        else
                        {
                            _5799 = _5796[_5780];
                        }
                        if (_5799)
                        {
                            break;
                        }
                        bool _6792 = _5794[_5780] > 0;
                        if (_5789[_5780] >= 0)
                        {
                            if (_6792)
                            {
                                _5812 = _5783[_5780] - _5783[_5789[_5780]];
                            }
                            else
                            {
                                _5812 = _5783[_5789[_5780]] - _5783[_5780];
                            }
                            _5808 = _5789[_5780];
                            _5820 = _5812;
                        }
                        else
                        {
                            if (_5789[_5780] == (-2))
                            {
                                _5820 = 3.4028234663852885981170418348452e+38;
                                _5808 = _5789[_5780];
                                _5819 = 0;
                                for (;;)
                                {
                                    bool _6803_ladder_break = false;
                                    do
                                    {
                                        if (!(_5819 < 32))
                                        {
                                            _6803_ladder_break = true;
                                            break;
                                        }
                                        if (_5819 >= _5936)
                                        {
                                            _6803_ladder_break = true;
                                            break;
                                        }
                                        if (_5819 == _5780)
                                        {
                                            _5800 = true;
                                        }
                                        else
                                        {
                                            _5800 = _5794[_5819] == _5794[_5780];
                                        }
                                        if (_5800)
                                        {
                                            break;
                                        }
                                        if (_6792)
                                        {
                                            _5821 = _5783[_5780] - _5783[_5819];
                                        }
                                        else
                                        {
                                            _5821 = _5783[_5819] - _5783[_5780];
                                        }
                                        if (_5821 <= 0.0)
                                        {
                                            _5801 = true;
                                        }
                                        else
                                        {
                                            _5801 = _5821 >= _5820;
                                        }
                                        if (_5801)
                                        {
                                            break;
                                        }
                                        _5820 = _5821;
                                        _5808 = _5819;
                                        break;
                                    } while(false);
                                    if (_6803_ladder_break)
                                    {
                                        break;
                                    }
                                    _5819++;
                                    continue;
                                }
                            }
                            else
                            {
                                _5808 = _5789[_5780];
                                _5820 = 3.4028234663852885981170418348452e+38;
                            }
                        }
                        if (_5808 < 0)
                        {
                            _5800 = true;
                        }
                        else
                        {
                            _5800 = _5796[_5808];
                        }
                        if (_5800)
                        {
                            _5801 = true;
                        }
                        else
                        {
                            _5801 = _5786[_5808] >= 0;
                        }
                        if (_5801)
                        {
                            _5803 = true;
                        }
                        else
                        {
                            _5803 = (_5820 * _4765) >= _5804;
                        }
                        if (_5803)
                        {
                            break;
                        }
                        if (_5788[_5808])
                        {
                            _5821 = _5820;
                        }
                        else
                        {
                            _5821 = max(round(_5820 * _4765), 1.0) * _4764;
                        }
                        if (_6792)
                        {
                            _5812 = _5795[_5780] - _5821;
                        }
                        else
                        {
                            _5812 = _5795[_5780] + _5821;
                        }
                        _5795[_5808] = _5812;
                        _5796[_5808] = true;
                        break;
                    } while(false);
                    if (_6743_ladder_break)
                    {
                        break;
                    }
                    _5780++;
                    continue;
                }
                _5780 = 0;
                bool _5797[32];
                bool _5798[32];
                for (;;)
                {
                    bool _6947_ladder_break = false;
                    do
                    {
                        if (!(_5780 < 32))
                        {
                            _6947_ladder_break = true;
                            break;
                        }
                        if (_5780 >= _5936)
                        {
                            _6947_ladder_break = true;
                            break;
                        }
                        if (true)
                        {
                            _5802 = _12392 != 0;
                        }
                        else
                        {
                            _5802 = _12396 != 0;
                        }
                        if (!_5796[_5780])
                        {
                            if (_5802)
                            {
                                _5781 = _5786[_5780] >= 0;
                            }
                            else
                            {
                                _5781 = false;
                            }
                            _5781 = !_5781;
                        }
                        else
                        {
                            _5781 = false;
                        }
                        if (_5781)
                        {
                            break;
                        }
                        _4715[_4708] = _5783[_5780];
                        _4716[_4708] = _5795[_5780];
                        if (_5802)
                        {
                            _5782 = _5786[_5780] >= 0;
                        }
                        else
                        {
                            _5782 = false;
                        }
                        _5797[_4708] = _5782;
                        _5798[_4708] = _5788[_5780];
                        _4708++;
                        break;
                    } while(false);
                    if (_6947_ladder_break)
                    {
                        break;
                    }
                    _5780++;
                    continue;
                }
                if (true)
                {
                    _5781 = _12395 == 1;
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    _5781 = _4708 > 0;
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    _5781 = _4708 < 32;
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    _5781 = _5731 < (_4715[0] - (0.25 * _4764));
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    _5780 = 31;
                    for (;;)
                    {
                        if (!(_5780 > 0))
                        {
                            break;
                        }
                        if (_5780 <= _4708)
                        {
                            int _7067 = _5780 - 1;
                            _4715[_5780] = _4715[_7067];
                            _4716[_5780] = _4716[_7067];
                            _5797[_5780] = _5797[_7067];
                            _5798[_5780] = _5798[_7067];
                        }
                        _5780--;
                        continue;
                    }
                    _4715[0] = _5731;
                    _4716[0] = round(_5731 * _4765) / _4765;
                    _5797[0] = false;
                    _5798[0] = false;
                    _4708++;
                }
                _5808 = 31;
                for (;;)
                {
                    bool _7104_ladder_break = false;
                    do
                    {
                        if (!(_5808 > 0))
                        {
                            _7104_ladder_break = true;
                            break;
                        }
                        if (_5808 >= _4708)
                        {
                            _5781 = true;
                        }
                        else
                        {
                            _5781 = !_5797[_5808];
                        }
                        if (_5781)
                        {
                            break;
                        }
                        _5819 = 31;
                        for (;;)
                        {
                            bool _7125_ladder_break = false;
                            do
                            {
                                if (!(_5819 > 0))
                                {
                                    _7125_ladder_break = true;
                                    break;
                                }
                                if (_5819 > _5808)
                                {
                                    break;
                                }
                                int _7137 = _5819 - 1;
                                if (_5797[_7137])
                                {
                                    _7125_ladder_break = true;
                                    break;
                                }
                                if (_5798[_7137])
                                {
                                    _5804 = 9.9999999747524270787835121154785e-07;
                                }
                                else
                                {
                                    _5804 = _4764;
                                }
                                _4716[_7137] = min(_4716[_7137], _4716[_5819] - _5804);
                                break;
                            } while(false);
                            if (_7125_ladder_break)
                            {
                                break;
                            }
                            _5819--;
                            continue;
                        }
                        break;
                    } while(false);
                    if (_7104_ladder_break)
                    {
                        break;
                    }
                    _5808--;
                    continue;
                }
                _5780 = 1;
                for (;;)
                {
                    if (!(_5780 < 32))
                    {
                        break;
                    }
                    if (_5780 >= _4708)
                    {
                        break;
                    }
                    int _7184 = _5780 - 1;
                    if (_4716[_5780] <= _4716[_7184])
                    {
                        _4716[_5780] = _4716[_7184] + _4764;
                    }
                    _5780++;
                    continue;
                }
                if (_12399 != 0)
                {
                    _5781 = _4765 > _12400;
                }
                else
                {
                    _5781 = false;
                }
                if (_5781)
                {
                    highp float _7213 = _12401 - _12400;
                    if (_7213 <= 0.0)
                    {
                        _5781 = true;
                    }
                    else
                    {
                        _5781 = _4765 >= _12401;
                    }
                    if (_5781)
                    {
                        _5804 = 1.0;
                    }
                    else
                    {
                        _5804 = (_4765 - _12400) / _7213;
                    }
                    _5780 = 0;
                    for (;;)
                    {
                        if (!(_5780 < 32))
                        {
                            break;
                        }
                        if (_5780 >= _4708)
                        {
                            break;
                        }
                        _4716[_5780] += ((_4715[_5780] - _4716[_5780]) * _5804);
                        _5780++;
                        continue;
                    }
                }
                _5780 = 0;
                bool _8042;
                bool _8053;
                for (;;)
                {
                    if (!(_5780 < 32))
                    {
                        break;
                    }
                    if (_5780 >= _4708)
                    {
                        break;
                    }
                    if (!isnan(_4715[_5780]))
                    {
                        _8042 = !isinf(_4715[_5780]);
                    }
                    else
                    {
                        _8042 = false;
                    }
                    if (!_8042)
                    {
                        _5781 = true;
                    }
                    else
                    {
                        if (!isnan(_4716[_5780]))
                        {
                            _8053 = !isinf(_4716[_5780]);
                        }
                        else
                        {
                            _8053 = false;
                        }
                        _5781 = !_8053;
                    }
                    if (_5781)
                    {
                        _4708 = 0;
                        _5778 = true;
                        _5779 = false;
                        break;
                    }
                    _5780++;
                    continue;
                }
                if (_5778)
                {
                    break;
                }
                _5778 = true;
                _5779 = true;
                break;
            } while(false);
            if (!_5779)
            {
                _4708 = 0;
            }
            highp float _4719[32] = _4715;
            highp float _4720[32] = _4716;
            highp float _8065;
            do
            {
                _4711 = 1.0;
                if (_4708 == 0)
                {
                    _8065 = _4703.x;
                    break;
                }
                if (_4703.x <= _4720[0])
                {
                    _8065 = (_4719[0] + _4703.x) - _4720[0];
                    break;
                }
                int _8085 = _4708 - 1;
                if (_4703.x >= _4720[_8085])
                {
                    _8065 = (_4719[_8085] + _4703.x) - _4720[_8085];
                    break;
                }
                int _8066 = 0;
                int _8067;
                bool _8068;
                for (;;)
                {
                    if (!(_8066 < 31))
                    {
                        _8067 = 0;
                        break;
                    }
                    int _8104 = _8066 + 1;
                    if (_8104 >= _4708)
                    {
                        _8068 = true;
                    }
                    else
                    {
                        _8068 = _4720[_8104] >= _4703.x;
                    }
                    if (_8068)
                    {
                        _8067 = _8066;
                        break;
                    }
                    _8066 = _8104;
                    continue;
                }
                int _8121 = _8067 + 1;
                highp float _8127 = _4720[_8121] - _4720[_8067];
                highp float _8069;
                if (abs(_8127) > 9.9999999747524270787835121154785e-07)
                {
                    _8069 = (_4719[_8121] - _4719[_8067]) / _8127;
                }
                else
                {
                    _8069 = 1.0;
                }
                _4711 = _8069;
                _8065 = _4719[_8067] + ((_4703.x - _4720[_8067]) * _8069);
                break;
            } while(false);
            highp vec2 _12537 = _4703;
            _12537.x = _8065;
            _4703 = _12537;
        }
        if (_4707)
        {
            _4707 = _4807;
        }
        else
        {
            _4707 = false;
        }
        if (_4707)
        {
            int _12422 = _12330;
            int _12423 = _12331;
            int _12424 = _12332;
            int _12425 = _12333;
            int _12426 = _12334;
            int _12427 = _12335;
            int _12428 = _12336;
            int _12429 = _12337;
            highp float _12430 = _12338;
            highp float _12431 = _12339;
            highp float _12432 = _12340;
            highp float _12433 = _12341;
            highp float _12434 = _12342;
            highp float _12435 = _12343;
            highp float _12436 = _12344;
            _8147 = false;
            highp float _4721[32];
            highp float _4722[32];
            bool _8148;
            do
            {
                _4710 = 0;
                int _8149 = 0;
                for (;;)
                {
                    if (!(_8149 < 32))
                    {
                        break;
                    }
                    _4721[_8149] = 0.0;
                    _4722[_8149] = 0.0;
                    _8149++;
                    continue;
                }
                bool _9664;
                if (!isnan(_4767))
                {
                    _9664 = !isinf(_4767);
                }
                else
                {
                    _9664 = false;
                }
                bool _8150;
                if (!_9664)
                {
                    _8150 = true;
                }
                else
                {
                    _8150 = _4767 <= 0.0;
                }
                if (_8150)
                {
                    _8150 = true;
                }
                else
                {
                    _8150 = _4704 < 0;
                }
                if (_8150)
                {
                    _8150 = true;
                }
                else
                {
                    _8150 = _4704 > 32;
                }
                if (_8150)
                {
                    _8150 = true;
                }
                else
                {
                    bool _9675;
                    if (!isnan(_5389))
                    {
                        _9675 = !isinf(_5389);
                    }
                    else
                    {
                        _9675 = false;
                    }
                    _8150 = !_9675;
                }
                if (_8150)
                {
                    _8150 = true;
                }
                else
                {
                    _8150 = _5389 < 0.0;
                }
                if (_8150)
                {
                    _8147 = true;
                    _8148 = false;
                    break;
                }
                if (false)
                {
                    _8150 = _12422 == 0;
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    _8150 = _12423 == 0;
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    _8150 = _12424 == 0;
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    _8150 = _12425 == 0;
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    _8150 = true;
                }
                else
                {
                    if (true)
                    {
                        _8150 = _12426 == 0;
                    }
                    else
                    {
                        _8150 = false;
                    }
                    if (_8150)
                    {
                        _8150 = _12427 == 0;
                    }
                    else
                    {
                        _8150 = false;
                    }
                    if (_8150)
                    {
                        _8150 = _12428 == 0;
                    }
                    else
                    {
                        _8150 = false;
                    }
                }
                if (_8150)
                {
                    _8147 = true;
                    _8148 = true;
                    break;
                }
                int _9724 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _9729 = ((snail_io2.y * _9724) + snail_io2.x) + (_4781 >> 2);
                highp vec4 _9695 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_9729 - _9724 * (_9729 / _9724), _9729 / _9724), 0).xy, 0);
                int _9697 = _4781 & 3;
                highp float _9686;
                if (_9697 == 0)
                {
                    _9686 = _9695.x;
                }
                else
                {
                    if (_9697 == 1)
                    {
                        _9686 = _9695.y;
                    }
                    else
                    {
                        if (_9697 == 2)
                        {
                            _9686 = _9695.z;
                        }
                        else
                        {
                            _9686 = _9695.w;
                        }
                    }
                }
                int _8305 = int(_9686);
                if (_8305 <= 0)
                {
                    _8150 = true;
                }
                else
                {
                    _8150 = _8305 > 32;
                }
                if (_8150)
                {
                    _8147 = true;
                    _8148 = _8305 == 0;
                    break;
                }
                if (true)
                {
                    _8150 = _12426 == 2;
                }
                else
                {
                    _8150 = false;
                }
                bool _8151;
                if (false)
                {
                    _8151 = _12425 == 1;
                }
                else
                {
                    _8151 = false;
                }
                if (_8151)
                {
                    bool _9733;
                    if (!isnan(0.0))
                    {
                        _9733 = !isinf(0.0);
                    }
                    else
                    {
                        _9733 = false;
                    }
                    _8151 = !_9733;
                }
                else
                {
                    _8151 = false;
                }
                if (_8151)
                {
                    _8147 = true;
                    _8148 = false;
                    break;
                }
                _8149 = 0;
                highp float _8152[32];
                highp float _8153[32];
                int _8154[32];
                int _8155[32];
                bool _8156[32];
                bool _8157[32];
                bool _8159[32];
                bool _8160[32];
                int _8161[32];
                int _8162[32];
                bool _8165[32];
                bool _8168;
                bool _8169;
                bool _8170;
                bool _8171;
                bool _8172;
                highp float _9744;
                highp float _9791;
                highp float _9838;
                highp float _9885;
                bool _9932;
                bool _9943;
                for (;;)
                {
                    if (!(_8149 < 32))
                    {
                        break;
                    }
                    if (_8149 >= _8305)
                    {
                        break;
                    }
                    int _8352 = (_4781 + 1) + (4 * _8149);
                    int _9782 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _9787 = ((snail_io2.y * _9782) + snail_io2.x) + (_8352 >> 2);
                    highp vec4 _9753 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_9787 - _9782 * (_9787 / _9782), _9787 / _9782), 0).xy, 0);
                    int _9755 = _8352 & 3;
                    if (_9755 == 0)
                    {
                        _9744 = _9753.x;
                    }
                    else
                    {
                        if (_9755 == 1)
                        {
                            _9744 = _9753.y;
                        }
                        else
                        {
                            if (_9755 == 2)
                            {
                                _9744 = _9753.z;
                            }
                            else
                            {
                                _9744 = _9753.w;
                            }
                        }
                    }
                    _8152[_8149] = _9744;
                    int _9794 = _8352 + 1;
                    int _9829 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _9834 = ((snail_io2.y * _9829) + snail_io2.x) + (_9794 >> 2);
                    highp vec4 _9800 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_9834 - _9829 * (_9834 / _9829), _9834 / _9829), 0).xy, 0);
                    int _9802 = _9794 & 3;
                    if (_9802 == 0)
                    {
                        _9791 = _9800.x;
                    }
                    else
                    {
                        if (_9802 == 1)
                        {
                            _9791 = _9800.y;
                        }
                        else
                        {
                            if (_9802 == 2)
                            {
                                _9791 = _9800.z;
                            }
                            else
                            {
                                _9791 = _9800.w;
                            }
                        }
                    }
                    _8153[_8149] = _9791;
                    int _9841 = _8352 + 2;
                    int _9876 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _9881 = ((snail_io2.y * _9876) + snail_io2.x) + (_9841 >> 2);
                    highp vec4 _9847 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_9881 - _9876 * (_9881 / _9876), _9881 / _9876), 0).xy, 0);
                    int _9849 = _9841 & 3;
                    if (_9849 == 0)
                    {
                        _9838 = _9847.x;
                    }
                    else
                    {
                        if (_9849 == 1)
                        {
                            _9838 = _9847.y;
                        }
                        else
                        {
                            if (_9849 == 2)
                            {
                                _9838 = _9847.z;
                            }
                            else
                            {
                                _9838 = _9847.w;
                            }
                        }
                    }
                    _8154[_8149] = int(floatBitsToUint(_9838) << 16u) >> 16;
                    _8155[_8149] = floatBitsToInt(_9838) >> 16;
                    int _9888 = _8352 + 3;
                    int _9923 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _9928 = ((snail_io2.y * _9923) + snail_io2.x) + (_9888 >> 2);
                    highp vec4 _9894 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_9928 - _9923 * (_9928 / _9923), _9928 / _9923), 0).xy, 0);
                    int _9896 = _9888 & 3;
                    if (_9896 == 0)
                    {
                        _9885 = _9894.x;
                    }
                    else
                    {
                        if (_9896 == 1)
                        {
                            _9885 = _9894.y;
                        }
                        else
                        {
                            if (_9896 == 2)
                            {
                                _9885 = _9894.z;
                            }
                            else
                            {
                                _9885 = _9894.w;
                            }
                        }
                    }
                    uint _8371 = floatBitsToUint(_9885);
                    _8156[_8149] = (_8371 & 1u) != 0u;
                    _8157[_8149] = (_8371 & 2u) != 0u;
                    _8159[_8149] = (_8371 & 4u) != 0u;
                    _8160[_8149] = (_8371 & 8u) != 0u;
                    _8161[_8149] = int((_8371 >> 4u) & 63u);
                    _8162[_8149] = int((_8371 >> 10u) & 63u);
                    _8165[_8149] = false;
                    if (!isnan(_8152[_8149]))
                    {
                        _9932 = !isinf(_8152[_8149]);
                    }
                    else
                    {
                        _9932 = false;
                    }
                    if (!_9932)
                    {
                        _8151 = true;
                    }
                    else
                    {
                        if (!isnan(_8153[_8149]))
                        {
                            _9943 = !isinf(_8153[_8149]);
                        }
                        else
                        {
                            _9943 = false;
                        }
                        _8151 = !_9943;
                    }
                    if (_8151)
                    {
                        _8168 = true;
                    }
                    else
                    {
                        _8168 = _8153[_8149] < 0.0;
                    }
                    if (_8168)
                    {
                        _8169 = true;
                    }
                    else
                    {
                        _8169 = _8154[_8149] < (-1);
                    }
                    if (_8169)
                    {
                        _8170 = true;
                    }
                    else
                    {
                        _8170 = _8154[_8149] >= _8305;
                    }
                    if (_8170)
                    {
                        _8171 = true;
                    }
                    else
                    {
                        _8171 = _8155[_8149] < (-1);
                    }
                    if (_8171)
                    {
                        _8172 = true;
                    }
                    else
                    {
                        _8172 = _8155[_8149] >= _4704;
                    }
                    if (_8172)
                    {
                        _8147 = true;
                        _8148 = false;
                        break;
                    }
                    _8149++;
                    continue;
                }
                if (_8147)
                {
                    break;
                }
                _8149 = 0;
                highp float _9954;
                highp float _10001;
                bool _10048;
                bool _10059;
                for (;;)
                {
                    if (!(_8149 < 32))
                    {
                        break;
                    }
                    if (_8149 >= _4704)
                    {
                        break;
                    }
                    int _8464 = 2 * _8149;
                    int _9992 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _9997 = ((snail_io2.y * _9992) + snail_io2.x) + ((12 + _8464) >> 2);
                    highp vec4 _9963 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_9997 - _9992 * (_9997 / _9992), _9997 / _9992), 0).xy, 0);
                    int _9965 = _8464 & 3;
                    if (_9965 == 0)
                    {
                        _9954 = _9963.x;
                    }
                    else
                    {
                        if (_9965 == 1)
                        {
                            _9954 = _9963.y;
                        }
                        else
                        {
                            if (_9965 == 2)
                            {
                                _9954 = _9963.z;
                            }
                            else
                            {
                                _9954 = _9963.w;
                            }
                        }
                    }
                    int _10004 = _8464 + 13;
                    int _10039 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                    int _10044 = ((snail_io2.y * _10039) + snail_io2.x) + (_10004 >> 2);
                    highp vec4 _10010 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10044 - _10039 * (_10044 / _10039), _10044 / _10039), 0).xy, 0);
                    int _10012 = _10004 & 3;
                    if (_10012 == 0)
                    {
                        _10001 = _10010.x;
                    }
                    else
                    {
                        if (_10012 == 1)
                        {
                            _10001 = _10010.y;
                        }
                        else
                        {
                            if (_10012 == 2)
                            {
                                _10001 = _10010.z;
                            }
                            else
                            {
                                _10001 = _10010.w;
                            }
                        }
                    }
                    if (!isnan(_9954))
                    {
                        _10048 = !isinf(_9954);
                    }
                    else
                    {
                        _10048 = false;
                    }
                    if (!_10048)
                    {
                        _8151 = true;
                    }
                    else
                    {
                        if (!isnan(_10001))
                        {
                            _10059 = !isinf(_10001);
                        }
                        else
                        {
                            _10059 = false;
                        }
                        _8151 = !_10059;
                    }
                    if (_8151)
                    {
                        _8147 = true;
                        _8148 = false;
                        break;
                    }
                    _8149++;
                    continue;
                }
                if (_8147)
                {
                    break;
                }
                _8149 = 0;
                bool _10070;
                bool _10081;
                for (;;)
                {
                    if (!(_8149 < 32))
                    {
                        break;
                    }
                    if (_8149 >= _8305)
                    {
                        break;
                    }
                    if (_8154[_8149] >= 0)
                    {
                        if (_8154[_8149] >= _8305)
                        {
                            _8151 = true;
                        }
                        else
                        {
                            _8151 = _8154[_8149] == _8149;
                        }
                        if (_8151)
                        {
                            _8168 = true;
                        }
                        else
                        {
                            _8168 = _8154[_8154[_8149]] != _8149;
                        }
                        if (_8168)
                        {
                            _8169 = true;
                        }
                        else
                        {
                            if (!isnan(_8152[_8154[_8149]]))
                            {
                                _10070 = !isinf(_8152[_8154[_8149]]);
                            }
                            else
                            {
                                _10070 = false;
                            }
                            _8169 = !_10070;
                        }
                        if (_8169)
                        {
                            _8170 = true;
                        }
                        else
                        {
                            _8170 = _8152[_8154[_8149]] == _8152[_8149];
                        }
                        if (_8170)
                        {
                            _8171 = true;
                        }
                        else
                        {
                            if (!isnan(_8153[_8154[_8149]]))
                            {
                                _10081 = !isinf(_8153[_8154[_8149]]);
                            }
                            else
                            {
                                _10081 = false;
                            }
                            _8171 = !_10081;
                        }
                        if (_8171)
                        {
                            _8172 = true;
                        }
                        else
                        {
                            _8172 = _8153[_8154[_8149]] != _8153[_8149];
                        }
                        if (_8172)
                        {
                            _8147 = true;
                            _8148 = false;
                            break;
                        }
                    }
                    _8149++;
                    continue;
                }
                if (_8147)
                {
                    break;
                }
                if (true)
                {
                    _8151 = _12428 == 1;
                }
                else
                {
                    _8151 = false;
                }
                highp float _8173;
                if (_8151)
                {
                    _8173 = _12436;
                }
                else
                {
                    _8173 = 0.0;
                }
                _8149 = 0;
                int _8158[32];
                int _8163[32];
                highp float _8164[32];
                int _8174;
                int _8175;
                int _8176;
                int _8177;
                bool _8178;
                bool _8179;
                bool _8180;
                highp float _8181;
                bool _8182;
                highp float _10092;
                highp float _10139;
                highp float _10186;
                highp float _10233;
                highp float _10285;
                highp float _10332;
                for (;;)
                {
                    if (!(_8149 < 32))
                    {
                        break;
                    }
                    if (_8149 >= _8305)
                    {
                        break;
                    }
                    if (_8154[_8149] >= 0)
                    {
                        _8151 = _8152[_8154[_8149]] > _8152[_8149];
                    }
                    else
                    {
                        _8151 = false;
                    }
                    if (_8150)
                    {
                        _8168 = _8155[_8149] >= 0;
                    }
                    else
                    {
                        _8168 = false;
                    }
                    if (_8168)
                    {
                        int _10095 = (2 * _8155[_8149]) + 13;
                        int _10130 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _10135 = ((snail_io2.y * _10130) + snail_io2.x) + (_10095 >> 2);
                        highp vec4 _10101 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10135 - _10130 * (_10135 / _10130), _10135 / _10130), 0).xy, 0);
                        int _10103 = _10095 & 3;
                        if (_10103 == 0)
                        {
                            _10092 = _10101.x;
                        }
                        else
                        {
                            if (_10103 == 1)
                            {
                                _10092 = _10101.y;
                            }
                            else
                            {
                                if (_10103 == 2)
                                {
                                    _10092 = _10101.z;
                                }
                                else
                                {
                                    _10092 = _10101.w;
                                }
                            }
                        }
                        int _8625 = 2 * _8155[_8149];
                        int _10177 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _10182 = ((snail_io2.y * _10177) + snail_io2.x) + ((12 + _8625) >> 2);
                        highp vec4 _10148 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10182 - _10177 * (_10182 / _10177), _10182 / _10177), 0).xy, 0);
                        int _10150 = _8625 & 3;
                        if (_10150 == 0)
                        {
                            _10139 = _10148.x;
                        }
                        else
                        {
                            if (_10150 == 1)
                            {
                                _10139 = _10148.y;
                            }
                            else
                            {
                                if (_10150 == 2)
                                {
                                    _10139 = _10148.z;
                                }
                                else
                                {
                                    _10139 = _10148.w;
                                }
                            }
                        }
                        _8169 = _10092 < _10139;
                    }
                    else
                    {
                        _8169 = false;
                    }
                    if (!_8159[_8149])
                    {
                        _8170 = _8154[_8149] < 0;
                    }
                    else
                    {
                        _8170 = false;
                    }
                    if (_8170)
                    {
                        _8171 = !_8168;
                    }
                    else
                    {
                        _8171 = false;
                    }
                    if (_8171)
                    {
                        _8172 = _8150;
                    }
                    else
                    {
                        _8172 = false;
                    }
                    if (_8172)
                    {
                        _8181 = 3.4028234663852885981170418348452e+38;
                        _8174 = 1;
                        _8175 = 0;
                        for (;;)
                        {
                            bool _8654_ladder_break = false;
                            do
                            {
                                if (!(_8175 < 32))
                                {
                                    _8654_ladder_break = true;
                                    break;
                                }
                                if (_8175 >= _8305)
                                {
                                    _8654_ladder_break = true;
                                    break;
                                }
                                if (_8155[_8175] < 0)
                                {
                                    break;
                                }
                                highp float _8677 = abs(_8152[_8175] - _8152[_8149]);
                                if (_8677 >= _8181)
                                {
                                    break;
                                }
                                int _10189 = (2 * _8155[_8175]) + 13;
                                int _10224 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                                int _10229 = ((snail_io2.y * _10224) + snail_io2.x) + (_10189 >> 2);
                                highp vec4 _10195 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10229 - _10224 * (_10229 / _10224), _10229 / _10224), 0).xy, 0);
                                int _10197 = _10189 & 3;
                                if (_10197 == 0)
                                {
                                    _10186 = _10195.x;
                                }
                                else
                                {
                                    if (_10197 == 1)
                                    {
                                        _10186 = _10195.y;
                                    }
                                    else
                                    {
                                        if (_10197 == 2)
                                        {
                                            _10186 = _10195.z;
                                        }
                                        else
                                        {
                                            _10186 = _10195.w;
                                        }
                                    }
                                }
                                int _8687 = 2 * _8155[_8175];
                                int _10271 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                                int _10276 = ((snail_io2.y * _10271) + snail_io2.x) + ((12 + _8687) >> 2);
                                highp vec4 _10242 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10276 - _10271 * (_10276 / _10271), _10276 / _10271), 0).xy, 0);
                                int _10244 = _8687 & 3;
                                if (_10244 == 0)
                                {
                                    _10233 = _10242.x;
                                }
                                else
                                {
                                    if (_10244 == 1)
                                    {
                                        _10233 = _10242.y;
                                    }
                                    else
                                    {
                                        if (_10244 == 2)
                                        {
                                            _10233 = _10242.z;
                                        }
                                        else
                                        {
                                            _10233 = _10242.w;
                                        }
                                    }
                                }
                                if (_10186 < _10233)
                                {
                                    _8176 = 1;
                                }
                                else
                                {
                                    _8176 = -1;
                                }
                                _8181 = _8677;
                                _8174 = _8176;
                                break;
                            } while(false);
                            if (_8654_ladder_break)
                            {
                                break;
                            }
                            _8175++;
                            continue;
                        }
                    }
                    else
                    {
                        _8174 = 1;
                    }
                    if (_8159[_8149])
                    {
                        if (_8150)
                        {
                            _8178 = _8160[_8149];
                        }
                        else
                        {
                            _8178 = false;
                        }
                        if (_8178)
                        {
                            _8179 = true;
                        }
                        else
                        {
                            if (!_8150)
                            {
                                _8179 = _8151;
                            }
                            else
                            {
                                _8179 = false;
                            }
                        }
                        if (_8179)
                        {
                            _8175 = -1;
                        }
                        else
                        {
                            _8175 = 1;
                        }
                    }
                    else
                    {
                        if (_8151)
                        {
                            _8178 = true;
                        }
                        else
                        {
                            _8178 = _8169;
                        }
                        if (_8178)
                        {
                            _8175 = -1;
                        }
                        else
                        {
                            _8175 = _8174;
                        }
                    }
                    _8163[_8149] = _8175;
                    if (_8150)
                    {
                        _8176 = _8162[_8149];
                    }
                    else
                    {
                        _8176 = _8161[_8149];
                    }
                    if (!_8159[_8149])
                    {
                        _8178 = true;
                    }
                    else
                    {
                        _8178 = _8176 == 63;
                    }
                    if (_8178)
                    {
                        _8177 = -2;
                    }
                    else
                    {
                        if (_8176 == 62)
                        {
                            _8177 = -1;
                        }
                        else
                        {
                            _8177 = _8176;
                        }
                    }
                    _8158[_8149] = _8177;
                    if (_8168)
                    {
                        int _8782 = 2 * _8155[_8149];
                        int _10323 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _10328 = ((snail_io2.y * _10323) + snail_io2.x) + ((12 + _8782) >> 2);
                        highp vec4 _10294 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10328 - _10323 * (_10328 / _10323), _10328 / _10323), 0).xy, 0);
                        int _10296 = _8782 & 3;
                        if (_10296 == 0)
                        {
                            _10285 = _10294.x;
                        }
                        else
                        {
                            if (_10296 == 1)
                            {
                                _10285 = _10294.y;
                            }
                            else
                            {
                                if (_10296 == 2)
                                {
                                    _10285 = _10294.z;
                                }
                                else
                                {
                                    _10285 = _10294.w;
                                }
                            }
                        }
                        int _10335 = (2 * _8155[_8149]) + 13;
                        int _10370 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                        int _10375 = ((snail_io2.y * _10370) + snail_io2.x) + (_10335 >> 2);
                        highp vec4 _10341 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10375 - _10370 * (_10375 / _10370), _10375 / _10370), 0).xy, 0);
                        int _10343 = _10335 & 3;
                        if (_10343 == 0)
                        {
                            _10332 = _10341.x;
                        }
                        else
                        {
                            if (_10343 == 1)
                            {
                                _10332 = _10341.y;
                            }
                            else
                            {
                                if (_10343 == 2)
                                {
                                    _10332 = _10341.z;
                                }
                                else
                                {
                                    _10332 = _10341.w;
                                }
                            }
                        }
                        if (_8156[_8149])
                        {
                            _8179 = true;
                        }
                        else
                        {
                            _8179 = false;
                        }
                        if (_8179)
                        {
                            _8180 = _12428 == 0;
                        }
                        else
                        {
                            _8180 = false;
                        }
                        if (_8180)
                        {
                            _8164[_8149] = _8152[_8149];
                        }
                        else
                        {
                            _8164[_8149] = round(_10285 * _4767) / _4767;
                            if (_8156[_8149])
                            {
                                _8182 = abs((_10332 - _10285) * _4767) >= _8173;
                            }
                            else
                            {
                                _8182 = false;
                            }
                            if (_8182)
                            {
                                _8164[_8149] += (_10332 - _10285);
                            }
                        }
                    }
                    else
                    {
                        _8164[_8149] = round(_8152[_8149] * _4767) / _4767;
                    }
                    _8149++;
                    continue;
                }
                if (false)
                {
                    _8174 = _12423;
                }
                else
                {
                    _8174 = _12427;
                }
                if (false)
                {
                    _8173 = _12432;
                }
                else
                {
                    _8173 = _12434;
                }
                if (false)
                {
                    _8181 = _12433;
                }
                else
                {
                    _8181 = _12435;
                }
                if (false)
                {
                    _8150 = _12422 == 1;
                }
                else
                {
                    _8150 = _12426 != 0;
                }
                if (false)
                {
                    _8151 = _12424 == 1;
                }
                else
                {
                    _8151 = false;
                }
                _8168 = false;
                highp float _8183 = 0.0;
                highp float _8184 = 0.0;
                highp float _8185 = 0.0;
                highp float _8186 = 0.0;
                highp float _8187 = 0.0;
                _8175 = 0;
                _8149 = 0;
                _8176 = 0;
                int _8188;
                highp float _8189;
                highp float _8190;
                highp float _8191;
                highp float _8192;
                highp float _8193;
                highp float _8194;
                bool _10384;
                highp float _10385;
                for (;;)
                {
                    bool _8874_ladder_break = false;
                    do
                    {
                        if (!(_8149 < 32))
                        {
                            _8874_ladder_break = true;
                            break;
                        }
                        if (_8149 >= _8305)
                        {
                            _8874_ladder_break = true;
                            break;
                        }
                        if (_8154[_8149] < 0)
                        {
                            _8169 = true;
                        }
                        else
                        {
                            _8169 = _8154[_8149] <= _8149;
                        }
                        if (_8169)
                        {
                            _8171 = _8168;
                            break;
                        }
                        if (_5389 > 0.0)
                        {
                            _10384 = abs(_8153[_8149] - _5389) <= (_8173 * _5389);
                        }
                        else
                        {
                            _10384 = false;
                        }
                        if (_10384)
                        {
                            _10385 = _5389;
                        }
                        else
                        {
                            _10385 = _8153[_8149];
                        }
                        if (_8174 == 2)
                        {
                            _8170 = true;
                        }
                        else
                        {
                            if (_8174 == 1)
                            {
                                _8170 = (_10385 * _4767) < _8181;
                            }
                            else
                            {
                                _8170 = false;
                            }
                        }
                        if (_8170)
                        {
                            _8189 = max(round(_10385 * _4767), 1.0) * _4766;
                        }
                        else
                        {
                            _8189 = _8153[_8149];
                        }
                        if (_8151)
                        {
                            if (_8168)
                            {
                                _8164[_8149] = _8183 + (round((_8152[_8149] - _8184) * _4767) * _4766);
                                _8190 = _8185;
                                _8191 = _8186;
                                _8171 = _8168;
                            }
                            else
                            {
                                highp float _10405 = round(_8152[_8149] * _4767) / _4767;
                                _8164[_8149] = _10405;
                                _8190 = _10405;
                                _8191 = _8152[_8149];
                                _8171 = true;
                            }
                            _8164[_8154[_8149]] = _8164[_8149] + _8189;
                            highp float _9032 = _8191;
                            highp float _9037 = _8190;
                            _8190 = _8164[_8149];
                            _8191 = _8152[_8149];
                            _8192 = _9037;
                            _8193 = _9032;
                            _8194 = (_9037 + (round((_8152[_8149] - _9032) * _4767) * _4766)) + _8189;
                            _8177 = _8154[_8149];
                            _8188 = _8176 + 1;
                        }
                        else
                        {
                            if (false)
                            {
                                _8171 = _12422 != 0;
                            }
                            else
                            {
                                _8171 = _12426 != 0;
                            }
                            if (_8171)
                            {
                                _8172 = _8155[_8149] >= 0;
                            }
                            else
                            {
                                _8172 = false;
                            }
                            if (_8171)
                            {
                                _8178 = _8155[_8154[_8149]] >= 0;
                            }
                            else
                            {
                                _8178 = false;
                            }
                            if (!_8150)
                            {
                                _8164[_8149] = _8152[_8149];
                            }
                            if (_8178)
                            {
                                _8179 = !_8172;
                            }
                            else
                            {
                                _8179 = false;
                            }
                            if (_8179)
                            {
                                _8180 = _8150;
                            }
                            else
                            {
                                _8180 = false;
                            }
                            if (_8180)
                            {
                                _8164[_8149] = _8164[_8154[_8149]] - _8189;
                            }
                            else
                            {
                                _8164[_8154[_8149]] = _8164[_8149] + _8189;
                            }
                            _8171 = _8168;
                            _8190 = _8183;
                            _8191 = _8184;
                            _8192 = _8185;
                            _8193 = _8186;
                            _8194 = _8187;
                            _8177 = _8175;
                            _8188 = _8176;
                        }
                        _8165[_8149] = true;
                        _8165[_8154[_8149]] = true;
                        _8183 = _8190;
                        _8184 = _8191;
                        _8185 = _8192;
                        _8186 = _8193;
                        _8187 = _8194;
                        _8175 = _8177;
                        _8176 = _8188;
                        break;
                    } while(false);
                    if (_8874_ladder_break)
                    {
                        break;
                    }
                    _8168 = _8171;
                    _8149++;
                    continue;
                }
                if (_8151)
                {
                    _8150 = _8176 > 1;
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    highp float _9075 = _8187 - _8164[_8175];
                    _8149 = 0;
                    for (;;)
                    {
                        if (!(_8149 < 32))
                        {
                            break;
                        }
                        if (_8149 >= _8305)
                        {
                            break;
                        }
                        if (_8165[_8149])
                        {
                            _8164[_8149] += _9075;
                        }
                        _8149++;
                        continue;
                    }
                }
                if (_8174 == 1)
                {
                    _8173 = _8181;
                }
                else
                {
                    _8173 = 1.60000002384185791015625;
                }
                _8149 = 0;
                for (;;)
                {
                    bool _9112_ladder_break = false;
                    do
                    {
                        if (!(_8149 < 32))
                        {
                            _9112_ladder_break = true;
                            break;
                        }
                        if (_8149 >= _8305)
                        {
                            _9112_ladder_break = true;
                            break;
                        }
                        if (false)
                        {
                            _8171 = _12422 != 0;
                        }
                        else
                        {
                            _8171 = _12426 != 0;
                        }
                        if (!_8171)
                        {
                            _8150 = true;
                        }
                        else
                        {
                            _8150 = _8155[_8149] < 0;
                        }
                        if (_8150)
                        {
                            _8151 = true;
                        }
                        else
                        {
                            _8151 = !_8156[_8149];
                        }
                        if (_8151)
                        {
                            _8168 = true;
                        }
                        else
                        {
                            _8168 = _8165[_8149];
                        }
                        if (_8168)
                        {
                            break;
                        }
                        bool _9161 = _8163[_8149] > 0;
                        if (_8158[_8149] >= 0)
                        {
                            if (_9161)
                            {
                                _8181 = _8152[_8149] - _8152[_8158[_8149]];
                            }
                            else
                            {
                                _8181 = _8152[_8158[_8149]] - _8152[_8149];
                            }
                            _8177 = _8158[_8149];
                            _8189 = _8181;
                        }
                        else
                        {
                            if (_8158[_8149] == (-2))
                            {
                                _8189 = 3.4028234663852885981170418348452e+38;
                                _8177 = _8158[_8149];
                                _8188 = 0;
                                for (;;)
                                {
                                    bool _9172_ladder_break = false;
                                    do
                                    {
                                        if (!(_8188 < 32))
                                        {
                                            _9172_ladder_break = true;
                                            break;
                                        }
                                        if (_8188 >= _8305)
                                        {
                                            _9172_ladder_break = true;
                                            break;
                                        }
                                        if (_8188 == _8149)
                                        {
                                            _8169 = true;
                                        }
                                        else
                                        {
                                            _8169 = _8163[_8188] == _8163[_8149];
                                        }
                                        if (_8169)
                                        {
                                            break;
                                        }
                                        if (_9161)
                                        {
                                            _8190 = _8152[_8149] - _8152[_8188];
                                        }
                                        else
                                        {
                                            _8190 = _8152[_8188] - _8152[_8149];
                                        }
                                        if (_8190 <= 0.0)
                                        {
                                            _8170 = true;
                                        }
                                        else
                                        {
                                            _8170 = _8190 >= _8189;
                                        }
                                        if (_8170)
                                        {
                                            break;
                                        }
                                        _8189 = _8190;
                                        _8177 = _8188;
                                        break;
                                    } while(false);
                                    if (_9172_ladder_break)
                                    {
                                        break;
                                    }
                                    _8188++;
                                    continue;
                                }
                            }
                            else
                            {
                                _8177 = _8158[_8149];
                                _8189 = 3.4028234663852885981170418348452e+38;
                            }
                        }
                        if (_8177 < 0)
                        {
                            _8169 = true;
                        }
                        else
                        {
                            _8169 = _8165[_8177];
                        }
                        if (_8169)
                        {
                            _8170 = true;
                        }
                        else
                        {
                            _8170 = _8155[_8177] >= 0;
                        }
                        if (_8170)
                        {
                            _8172 = true;
                        }
                        else
                        {
                            _8172 = (_8189 * _4767) >= _8173;
                        }
                        if (_8172)
                        {
                            break;
                        }
                        if (_8157[_8177])
                        {
                            _8190 = _8189;
                        }
                        else
                        {
                            _8190 = max(round(_8189 * _4767), 1.0) * _4766;
                        }
                        if (_9161)
                        {
                            _8181 = _8164[_8149] - _8190;
                        }
                        else
                        {
                            _8181 = _8164[_8149] + _8190;
                        }
                        _8164[_8177] = _8181;
                        _8165[_8177] = true;
                        break;
                    } while(false);
                    if (_9112_ladder_break)
                    {
                        break;
                    }
                    _8149++;
                    continue;
                }
                _8149 = 0;
                bool _8166[32];
                bool _8167[32];
                for (;;)
                {
                    bool _9316_ladder_break = false;
                    do
                    {
                        if (!(_8149 < 32))
                        {
                            _9316_ladder_break = true;
                            break;
                        }
                        if (_8149 >= _8305)
                        {
                            _9316_ladder_break = true;
                            break;
                        }
                        if (false)
                        {
                            _8171 = _12422 != 0;
                        }
                        else
                        {
                            _8171 = _12426 != 0;
                        }
                        if (!_8165[_8149])
                        {
                            if (_8171)
                            {
                                _8150 = _8155[_8149] >= 0;
                            }
                            else
                            {
                                _8150 = false;
                            }
                            _8150 = !_8150;
                        }
                        else
                        {
                            _8150 = false;
                        }
                        if (_8150)
                        {
                            break;
                        }
                        _4721[_4710] = _8152[_8149];
                        _4722[_4710] = _8164[_8149];
                        if (_8171)
                        {
                            _8151 = _8155[_8149] >= 0;
                        }
                        else
                        {
                            _8151 = false;
                        }
                        _8166[_4710] = _8151;
                        _8167[_4710] = _8157[_8149];
                        _4710++;
                        break;
                    } while(false);
                    if (_9316_ladder_break)
                    {
                        break;
                    }
                    _8149++;
                    continue;
                }
                if (false)
                {
                    _8150 = _12425 == 1;
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    _8150 = _4710 > 0;
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    _8150 = _4710 < 32;
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    _8150 = 0.0 < (_4721[0] - (0.25 * _4766));
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    _8149 = 31;
                    for (;;)
                    {
                        if (!(_8149 > 0))
                        {
                            break;
                        }
                        if (_8149 <= _4710)
                        {
                            int _9436 = _8149 - 1;
                            _4721[_8149] = _4721[_9436];
                            _4722[_8149] = _4722[_9436];
                            _8166[_8149] = _8166[_9436];
                            _8167[_8149] = _8167[_9436];
                        }
                        _8149--;
                        continue;
                    }
                    _4721[0] = 0.0;
                    highp float _10409 = round(0.0);
                    _4722[0] = _10409 / _4767;
                    _8166[0] = false;
                    _8167[0] = false;
                    _4710++;
                }
                _8177 = 31;
                for (;;)
                {
                    bool _9473_ladder_break = false;
                    do
                    {
                        if (!(_8177 > 0))
                        {
                            _9473_ladder_break = true;
                            break;
                        }
                        if (_8177 >= _4710)
                        {
                            _8150 = true;
                        }
                        else
                        {
                            _8150 = !_8166[_8177];
                        }
                        if (_8150)
                        {
                            break;
                        }
                        _8188 = 31;
                        for (;;)
                        {
                            bool _9494_ladder_break = false;
                            do
                            {
                                if (!(_8188 > 0))
                                {
                                    _9494_ladder_break = true;
                                    break;
                                }
                                if (_8188 > _8177)
                                {
                                    break;
                                }
                                int _9506 = _8188 - 1;
                                if (_8166[_9506])
                                {
                                    _9494_ladder_break = true;
                                    break;
                                }
                                if (_8167[_9506])
                                {
                                    _8173 = 9.9999999747524270787835121154785e-07;
                                }
                                else
                                {
                                    _8173 = _4766;
                                }
                                _4722[_9506] = min(_4722[_9506], _4722[_8188] - _8173);
                                break;
                            } while(false);
                            if (_9494_ladder_break)
                            {
                                break;
                            }
                            _8188--;
                            continue;
                        }
                        break;
                    } while(false);
                    if (_9473_ladder_break)
                    {
                        break;
                    }
                    _8177--;
                    continue;
                }
                _8149 = 1;
                for (;;)
                {
                    if (!(_8149 < 32))
                    {
                        break;
                    }
                    if (_8149 >= _4710)
                    {
                        break;
                    }
                    int _9553 = _8149 - 1;
                    if (_4722[_8149] <= _4722[_9553])
                    {
                        _4722[_8149] = _4722[_9553] + _4766;
                    }
                    _8149++;
                    continue;
                }
                if (_12429 != 0)
                {
                    _8150 = _4767 > _12430;
                }
                else
                {
                    _8150 = false;
                }
                if (_8150)
                {
                    highp float _9582 = _12431 - _12430;
                    if (_9582 <= 0.0)
                    {
                        _8150 = true;
                    }
                    else
                    {
                        _8150 = _4767 >= _12431;
                    }
                    if (_8150)
                    {
                        _8173 = 1.0;
                    }
                    else
                    {
                        _8173 = (_4767 - _12430) / _9582;
                    }
                    _8149 = 0;
                    for (;;)
                    {
                        if (!(_8149 < 32))
                        {
                            break;
                        }
                        if (_8149 >= _4710)
                        {
                            break;
                        }
                        _4722[_8149] += ((_4721[_8149] - _4722[_8149]) * _8173);
                        _8149++;
                        continue;
                    }
                }
                _8149 = 0;
                bool _10411;
                bool _10422;
                for (;;)
                {
                    if (!(_8149 < 32))
                    {
                        break;
                    }
                    if (_8149 >= _4710)
                    {
                        break;
                    }
                    if (!isnan(_4721[_8149]))
                    {
                        _10411 = !isinf(_4721[_8149]);
                    }
                    else
                    {
                        _10411 = false;
                    }
                    if (!_10411)
                    {
                        _8150 = true;
                    }
                    else
                    {
                        if (!isnan(_4722[_8149]))
                        {
                            _10422 = !isinf(_4722[_8149]);
                        }
                        else
                        {
                            _10422 = false;
                        }
                        _8150 = !_10422;
                    }
                    if (_8150)
                    {
                        _4710 = 0;
                        _8147 = true;
                        _8148 = false;
                        break;
                    }
                    _8149++;
                    continue;
                }
                if (_8147)
                {
                    break;
                }
                _8147 = true;
                _8148 = true;
                break;
            } while(false);
            if (!_8148)
            {
                _4710 = 0;
            }
            highp float _4725[32] = _4721;
            highp float _4726[32] = _4722;
            highp float _10434;
            do
            {
                _4712 = 1.0;
                if (_4710 == 0)
                {
                    _10434 = _4703.y;
                    break;
                }
                if (_4703.y <= _4726[0])
                {
                    _10434 = (_4725[0] + _4703.y) - _4726[0];
                    break;
                }
                int _10454 = _4710 - 1;
                if (_4703.y >= _4726[_10454])
                {
                    _10434 = (_4725[_10454] + _4703.y) - _4726[_10454];
                    break;
                }
                int _10435 = 0;
                int _10436;
                bool _10437;
                for (;;)
                {
                    if (!(_10435 < 31))
                    {
                        _10436 = 0;
                        break;
                    }
                    int _10473 = _10435 + 1;
                    if (_10473 >= _4710)
                    {
                        _10437 = true;
                    }
                    else
                    {
                        _10437 = _4726[_10473] >= _4703.y;
                    }
                    if (_10437)
                    {
                        _10436 = _10435;
                        break;
                    }
                    _10435 = _10473;
                    continue;
                }
                int _10490 = _10436 + 1;
                highp float _10496 = _4726[_10490] - _4726[_10436];
                highp float _10438;
                if (abs(_10496) > 9.9999999747524270787835121154785e-07)
                {
                    _10438 = (_4725[_10490] - _4725[_10436]) / _10496;
                }
                else
                {
                    _10438 = 1.0;
                }
                _4712 = _10438;
                _10434 = _4725[_10436] + ((_4703.y - _4726[_10436]) * _10438);
                break;
            } while(false);
            highp vec2 _12539 = _4703;
            _12539.y = _10434;
            _4703 = _12539;
        }
    }
    if (!_4805)
    {
        int _10554 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
        int _10559 = ((snail_io2.y * _10554) + snail_io2.x) + 2;
        highp vec4 _10525 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10559 - _10554 * (_10559 / _10554), _10559 / _10554), 0).xy, 0);
        highp float _10516;
        if (false)
        {
            _10516 = _10525.x;
        }
        else
        {
            if (false)
            {
                _10516 = _10525.y;
            }
            else
            {
                if (false)
                {
                    _10516 = _10525.z;
                }
                else
                {
                    _10516 = _10525.w;
                }
            }
        }
        highp vec4 _4727[4] = vec4[](_12507, _12508, _12509, _12510);
        highp float _10564;
        do
        {
            _4711 = 1.0;
            if (_4708 == 0)
            {
                _10564 = _4703.x;
                break;
            }
            uint _10668 = _12478.x & 255u;
            highp float _10644;
            if (_10668 == 32u)
            {
                _10644 = _10516;
            }
            else
            {
                int _10653 = (_4771 + 13) + (4 * int(_10668));
                int _10707 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _10712 = ((snail_io2.y * _10707) + snail_io2.x) + (_10653 >> 2);
                highp vec4 _10678 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10712 - _10707 * (_10712 / _10707), _10712 / _10707), 0).xy, 0);
                int _10680 = _10653 & 3;
                highp float _10669;
                if (_10680 == 0)
                {
                    _10669 = _10678.x;
                }
                else
                {
                    if (_10680 == 1)
                    {
                        _10669 = _10678.y;
                    }
                    else
                    {
                        if (_10680 == 2)
                        {
                            _10669 = _10678.z;
                        }
                        else
                        {
                            _10669 = _10678.w;
                        }
                    }
                }
                _10644 = _10669;
            }
            if (_4703.x <= _4727[0].x)
            {
                _10564 = (_10644 + _4703.x) - _4727[0].x;
                break;
            }
            int _10582 = _4708 - 1;
            int _10718 = _10582 >> 2;
            int _10719 = _10582 & 3;
            uvec4 _10737 = _12478;
            uint _10747 = (_10737[_10582 >> 2] >> uint((_10582 & 3) * 8)) & 255u;
            highp float _10723;
            if (_10747 == 32u)
            {
                _10723 = _10516;
            }
            else
            {
                int _10732 = (_4771 + 13) + (4 * int(_10747));
                int _10786 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _10791 = ((snail_io2.y * _10786) + snail_io2.x) + (_10732 >> 2);
                highp vec4 _10757 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10791 - _10786 * (_10791 / _10786), _10791 / _10786), 0).xy, 0);
                int _10759 = _10732 & 3;
                highp float _10748;
                if (_10759 == 0)
                {
                    _10748 = _10757.x;
                }
                else
                {
                    if (_10759 == 1)
                    {
                        _10748 = _10757.y;
                    }
                    else
                    {
                        if (_10759 == 2)
                        {
                            _10748 = _10757.z;
                        }
                        else
                        {
                            _10748 = _10757.w;
                        }
                    }
                }
                _10723 = _10748;
            }
            if (_4703.x >= _4727[_10718][_10719])
            {
                _10564 = (_10723 + _4703.x) - _4727[_10718][_10719];
                break;
            }
            int _10565 = 0;
            int _10566;
            bool _10567;
            for (;;)
            {
                if (!(_10565 < 15))
                {
                    _10566 = 0;
                    break;
                }
                int _10599 = _10565 + 1;
                if (_10599 >= _4708)
                {
                    _10567 = true;
                }
                else
                {
                    _10567 = _4727[_10599 >> 2][_10599 & 3] >= _4703.x;
                }
                if (_10567)
                {
                    _10566 = _10565;
                    break;
                }
                _10565 = _10599;
                continue;
            }
            int _10804 = _10566 >> 2;
            int _10805 = _10566 & 3;
            int _10617 = _10566 + 1;
            uvec4 _10830 = _12478;
            uint _10840 = (_10830[_10566 >> 2] >> uint((_10566 & 3) * 8)) & 255u;
            highp float _10816;
            if (_10840 == 32u)
            {
                _10816 = _10516;
            }
            else
            {
                int _10825 = (_4771 + 13) + (4 * int(_10840));
                int _10879 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _10884 = ((snail_io2.y * _10879) + snail_io2.x) + (_10825 >> 2);
                highp vec4 _10850 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10884 - _10879 * (_10884 / _10879), _10884 / _10879), 0).xy, 0);
                int _10852 = _10825 & 3;
                highp float _10841;
                if (_10852 == 0)
                {
                    _10841 = _10850.x;
                }
                else
                {
                    if (_10852 == 1)
                    {
                        _10841 = _10850.y;
                    }
                    else
                    {
                        if (_10852 == 2)
                        {
                            _10841 = _10850.z;
                        }
                        else
                        {
                            _10841 = _10850.w;
                        }
                    }
                }
                _10816 = _10841;
            }
            uvec4 _10902 = _12478;
            uint _10912 = (_10902[_10617 >> 2] >> uint((_10617 & 3) * 8)) & 255u;
            highp float _10888;
            if (_10912 == 32u)
            {
                _10888 = _10516;
            }
            else
            {
                int _10897 = (_4771 + 13) + (4 * int(_10912));
                int _10951 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _10956 = ((snail_io2.y * _10951) + snail_io2.x) + (_10897 >> 2);
                highp vec4 _10922 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_10956 - _10951 * (_10956 / _10951), _10956 / _10951), 0).xy, 0);
                int _10924 = _10897 & 3;
                highp float _10913;
                if (_10924 == 0)
                {
                    _10913 = _10922.x;
                }
                else
                {
                    if (_10924 == 1)
                    {
                        _10913 = _10922.y;
                    }
                    else
                    {
                        if (_10924 == 2)
                        {
                            _10913 = _10922.z;
                        }
                        else
                        {
                            _10913 = _10922.w;
                        }
                    }
                }
                _10888 = _10913;
            }
            highp float _10622 = _4727[_10617 >> 2][_10617 & 3] - _4727[_10804][_10805];
            highp float _10568;
            if (abs(_10622) > 9.9999999747524270787835121154785e-07)
            {
                _10568 = (_10888 - _10816) / _10622;
            }
            else
            {
                _10568 = 1.0;
            }
            _4711 = _10568;
            _10564 = _10816 + ((_4703.x - _4727[_10804][_10805]) * _10568);
            break;
        } while(false);
        highp vec2 _12542 = _4703;
        _12542.x = _10564;
        _4703 = _12542;
    }
    if (!_4807)
    {
        highp vec4 _4728[4] = vec4[](_12520, _12521, _12522, _12523);
        highp float _10961;
        do
        {
            _4712 = 1.0;
            if (_4710 == 0)
            {
                _10961 = _4703.y;
                break;
            }
            uint _11065 = _12479.x & 255u;
            highp float _11041;
            if (_11065 == 32u)
            {
                _11041 = 0.0;
            }
            else
            {
                int _11050 = (_4781 + 1) + (4 * int(_11065));
                int _11104 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _11109 = ((snail_io2.y * _11104) + snail_io2.x) + (_11050 >> 2);
                highp vec4 _11075 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11109 - _11104 * (_11109 / _11104), _11109 / _11104), 0).xy, 0);
                int _11077 = _11050 & 3;
                highp float _11066;
                if (_11077 == 0)
                {
                    _11066 = _11075.x;
                }
                else
                {
                    if (_11077 == 1)
                    {
                        _11066 = _11075.y;
                    }
                    else
                    {
                        if (_11077 == 2)
                        {
                            _11066 = _11075.z;
                        }
                        else
                        {
                            _11066 = _11075.w;
                        }
                    }
                }
                _11041 = _11066;
            }
            if (_4703.y <= _4728[0].x)
            {
                _10961 = (_11041 + _4703.y) - _4728[0].x;
                break;
            }
            int _10979 = _4710 - 1;
            int _11115 = _10979 >> 2;
            int _11116 = _10979 & 3;
            uvec4 _11134 = _12479;
            uint _11144 = (_11134[_10979 >> 2] >> uint((_10979 & 3) * 8)) & 255u;
            highp float _11120;
            if (_11144 == 32u)
            {
                _11120 = 0.0;
            }
            else
            {
                int _11129 = (_4781 + 1) + (4 * int(_11144));
                int _11183 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _11188 = ((snail_io2.y * _11183) + snail_io2.x) + (_11129 >> 2);
                highp vec4 _11154 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11188 - _11183 * (_11188 / _11183), _11188 / _11183), 0).xy, 0);
                int _11156 = _11129 & 3;
                highp float _11145;
                if (_11156 == 0)
                {
                    _11145 = _11154.x;
                }
                else
                {
                    if (_11156 == 1)
                    {
                        _11145 = _11154.y;
                    }
                    else
                    {
                        if (_11156 == 2)
                        {
                            _11145 = _11154.z;
                        }
                        else
                        {
                            _11145 = _11154.w;
                        }
                    }
                }
                _11120 = _11145;
            }
            if (_4703.y >= _4728[_11115][_11116])
            {
                _10961 = (_11120 + _4703.y) - _4728[_11115][_11116];
                break;
            }
            int _10962 = 0;
            int _10963;
            bool _10964;
            for (;;)
            {
                if (!(_10962 < 15))
                {
                    _10963 = 0;
                    break;
                }
                int _10996 = _10962 + 1;
                if (_10996 >= _4710)
                {
                    _10964 = true;
                }
                else
                {
                    _10964 = _4728[_10996 >> 2][_10996 & 3] >= _4703.y;
                }
                if (_10964)
                {
                    _10963 = _10962;
                    break;
                }
                _10962 = _10996;
                continue;
            }
            int _11201 = _10963 >> 2;
            int _11202 = _10963 & 3;
            int _11014 = _10963 + 1;
            uvec4 _11227 = _12479;
            uint _11237 = (_11227[_10963 >> 2] >> uint((_10963 & 3) * 8)) & 255u;
            highp float _11213;
            if (_11237 == 32u)
            {
                _11213 = 0.0;
            }
            else
            {
                int _11222 = (_4781 + 1) + (4 * int(_11237));
                int _11276 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _11281 = ((snail_io2.y * _11276) + snail_io2.x) + (_11222 >> 2);
                highp vec4 _11247 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11281 - _11276 * (_11281 / _11276), _11281 / _11276), 0).xy, 0);
                int _11249 = _11222 & 3;
                highp float _11238;
                if (_11249 == 0)
                {
                    _11238 = _11247.x;
                }
                else
                {
                    if (_11249 == 1)
                    {
                        _11238 = _11247.y;
                    }
                    else
                    {
                        if (_11249 == 2)
                        {
                            _11238 = _11247.z;
                        }
                        else
                        {
                            _11238 = _11247.w;
                        }
                    }
                }
                _11213 = _11238;
            }
            uvec4 _11299 = _12479;
            uint _11309 = (_11299[_11014 >> 2] >> uint((_11014 & 3) * 8)) & 255u;
            highp float _11285;
            if (_11309 == 32u)
            {
                _11285 = 0.0;
            }
            else
            {
                int _11294 = (_4781 + 1) + (4 * int(_11309));
                int _11348 = int(uvec2(textureSize(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, 0)).x);
                int _11353 = ((snail_io2.y * _11348) + snail_io2.x) + (_11294 >> 2);
                highp vec4 _11319 = texelFetch(SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler, ivec3(ivec2(_11353 - _11348 * (_11353 / _11348), _11353 / _11348), 0).xy, 0);
                int _11321 = _11294 & 3;
                highp float _11310;
                if (_11321 == 0)
                {
                    _11310 = _11319.x;
                }
                else
                {
                    if (_11321 == 1)
                    {
                        _11310 = _11319.y;
                    }
                    else
                    {
                        if (_11321 == 2)
                        {
                            _11310 = _11319.z;
                        }
                        else
                        {
                            _11310 = _11319.w;
                        }
                    }
                }
                _11285 = _11310;
            }
            highp float _11019 = _4728[_11014 >> 2][_11014 & 3] - _4728[_11201][_11202];
            highp float _10965;
            if (abs(_11019) > 9.9999999747524270787835121154785e-07)
            {
                _10965 = (_11285 - _11213) / _11019;
            }
            else
            {
                _10965 = 1.0;
            }
            _4712 = _10965;
            _10961 = _11213 + ((_4703.y - _4728[_11201][_11202]) * _10965);
            break;
        } while(false);
        highp vec2 _12545 = _4703;
        _12545.y = _10961;
        _4703 = _12545;
    }
    highp vec2 _4913 = _4963 * vec2(_4711, _4712);
    highp float _4916 = 1.0 / max(_4913.x, 1.52587890625e-05);
    highp float _4919 = 1.0 / max(_4913.y, 1.52587890625e-05);
    highp float _11368 = _4743.y;
    highp float _11541 = (_4703.y * _11368) + _4743.w;
    highp float _11545 = max(abs(_4913.y * _11368) * 0.5, 9.9999997473787516355514526367188e-06);
    int _11548 = clamp(int(_11541 - _11545), 0, _4754);
    int _11552 = max(_11548, clamp(int(_11541 + _11545), 0, _4754));
    highp float _11374 = _4743.x;
    highp float _11563 = (_4703.x * _11374) + _4743.z;
    highp float _11567 = max(abs(_4913.x * _11374) * 0.5, 9.9999997473787516355514526367188e-06);
    int _11570 = clamp(int(_11563 - _11567), 0, _4756);
    int _11574 = max(_11570, clamp(int(_11563 + _11567), 0, _4756));
    highp float _11357 = 0.0;
    highp float _11358 = 0.0;
    bool _11380 = _11548 != _11552;
    int _11359 = _11548;
    int _11360;
    bool _11361;
    bool _11653;
    highp float _11759;
    highp float _11768;
    highp float _11777;
    highp float _11786;
    highp float _11787;
    highp float _11856;
    for (;;)
    {
        if (!(_11359 <= _11552))
        {
            break;
        }
        int _11587 = _4747 + _11359;
        ivec2 _11589 = ivec2(_11587, _4750);
        _11589.y = _11589.y + (_11587 >> 12);
        _11589.x = _11589.x & 4095;
        uvec4 _11395 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_11589, _4761, 0).xyz, 0);
        int _11603 = _4747 + int(_11395.y);
        ivec2 _11605 = ivec2(_11603, _4750);
        _11605.y = _11605.y + (_11603 >> 12);
        _11605.x = _11605.x & 4095;
        int _11402 = int(_11395.x);
        _11360 = 0;
        for (;;)
        {
            bool _11405_ladder_break = false;
            do
            {
                if (!(_11360 < _11402))
                {
                    _11405_ladder_break = true;
                    break;
                }
                int _11619 = _11605.x + _11360;
                ivec2 _11621 = ivec2(_11619, _11605.y);
                _11621.y = _11621.y + (_11619 >> 12);
                _11621.x = _11621.x & 4095;
                uvec4 _11417 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_11621, _4761, 0).xyz, 0);
                if (_11380)
                {
                    _11361 = !(_11359 == max(int(_11417.x >> 12u), _11548));
                }
                else
                {
                    _11361 = false;
                }
                if (_11361)
                {
                    break;
                }
                ivec2 _11651 = ivec2(int(_11417.x & 4095u), int(_11417.y & 16383u));
                do
                {
                    highp vec4 _11660 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_11651, _4761, 0).xyz, 0);
                    int _11729 = _11651.x + 1;
                    ivec2 _11731 = ivec2(_11729, _11651.y);
                    _11731.y = _11731.y + (_11729 >> 12);
                    _11731.x = _11731.x & 4095;
                    highp vec4 _11672 = vec4(_11660.xy, _11660.zw) - vec4(_4703, _4703);
                    highp vec2 _11674 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_11731, _4761, 0).xyz, 0).xy - _4703;
                    if ((max(max(_11672.x, _11672.z), _11674.x) * _4916) < (-0.5))
                    {
                        _11653 = false;
                        break;
                    }
                    highp float _11685 = _11672.y;
                    highp float _11686 = _11672.w;
                    highp float _11687 = _11674.y;
                    if (abs(_11685) <= 1.52587890625e-05)
                    {
                        _11759 = 0.0;
                    }
                    else
                    {
                        _11759 = _11685;
                    }
                    if (abs(_11686) <= 1.52587890625e-05)
                    {
                        _11768 = 0.0;
                    }
                    else
                    {
                        _11768 = _11686;
                    }
                    if (abs(_11687) <= 1.52587890625e-05)
                    {
                        _11777 = 0.0;
                    }
                    else
                    {
                        _11777 = _11687;
                    }
                    uint _11758 = (11892u >> (((floatBitsToUint(_11777) >> 29u) & 4u) | ((((floatBitsToUint(_11768) >> 30u) & 2u) | ((floatBitsToUint(_11759) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                    if (_11758 != 0u)
                    {
                        highp vec2 _11790 = _11672.xy;
                        highp vec2 _11791 = _11672.zw;
                        highp vec2 _11794 = (_11790 - (_11791 * 2.0)) + _11674;
                        highp vec2 _11795 = _11790 - _11791;
                        highp float _11796 = _11794.y;
                        if (abs(_11796) < 1.52587890625e-05)
                        {
                            highp float _11828 = _11795.y;
                            if (abs(_11828) < 1.52587890625e-05)
                            {
                                _11786 = 0.0;
                            }
                            else
                            {
                                _11786 = (_11672.y * 0.5) / _11828;
                            }
                            _11787 = _11786;
                        }
                        else
                        {
                            highp float _11800 = _11795.y;
                            highp float _11802 = _11672.y;
                            highp float _11803 = _11796 * _11802;
                            highp float _11804 = (_11800 * _11800) - _11803;
                            if (_11804 <= (max(_11800 * _11800, abs(_11803)) * 3.0000001061125658452510833740234e-06))
                            {
                                _11856 = 0.0;
                            }
                            else
                            {
                                _11856 = sqrt(_11804);
                            }
                            if (_11800 >= 0.0)
                            {
                                highp float _11818 = _11800 + _11856;
                                if (abs(_11818) < 1.52587890625e-05)
                                {
                                    _11786 = 0.0;
                                }
                                else
                                {
                                    _11786 = _11802 / _11818;
                                }
                                _11787 = _11818 / _11796;
                            }
                            else
                            {
                                highp float _11808 = _11800 - _11856;
                                if (abs(_11808) < 1.52587890625e-05)
                                {
                                    _11786 = 0.0;
                                }
                                else
                                {
                                    _11786 = _11802 / _11808;
                                }
                                highp float _11816 = _11786;
                                _11786 = _11808 / _11796;
                                _11787 = _11816;
                            }
                        }
                        highp float _11839 = _11794.x;
                        highp float _11843 = _11795.x * 2.0;
                        highp float _11847 = _11672.x;
                        highp vec2 _11692 = vec2((((_11839 * _11786) - _11843) * _11786) + _11847, (((_11839 * _11787) - _11843) * _11787) + _11847) * _4916;
                        if ((_11758 & 1u) != 0u)
                        {
                            highp float _11696 = _11692.x;
                            _11357 += clamp(_11696 + 0.5, 0.0, 1.0);
                            _11358 = max(_11358, clamp(1.0 - (abs(_11696) * 2.0), 0.0, 1.0));
                        }
                        if (_11758 > 1u)
                        {
                            highp float _11710 = _11692.y;
                            _11357 -= clamp(_11710 + 0.5, 0.0, 1.0);
                            _11358 = max(_11358, clamp(1.0 - (abs(_11710) * 2.0), 0.0, 1.0));
                        }
                    }
                    _11653 = true;
                    break;
                } while(false);
                if (!_11653)
                {
                    _11405_ladder_break = true;
                    break;
                }
                break;
            } while(false);
            if (_11405_ladder_break)
            {
                break;
            }
            _11360++;
            continue;
        }
        _11359++;
        continue;
    }
    highp float _11362 = 0.0;
    highp float _11363 = 0.0;
    bool _11449 = _11570 != _11574;
    _11359 = _11570;
    bool _11940;
    highp float _12046;
    highp float _12055;
    highp float _12064;
    highp float _12073;
    highp float _12074;
    highp float _12143;
    for (;;)
    {
        if (!(_11359 <= _11574))
        {
            break;
        }
        int _11874 = _4747 + ((_4754 + 1) + _11359);
        ivec2 _11876 = ivec2(_11874, _4750);
        _11876.y = _11876.y + (_11874 >> 12);
        _11876.x = _11876.x & 4095;
        uvec4 _11466 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_11876, _4761, 0).xyz, 0);
        int _11890 = _4747 + int(_11466.y);
        ivec2 _11892 = ivec2(_11890, _4750);
        _11892.y = _11892.y + (_11890 >> 12);
        _11892.x = _11892.x & 4095;
        int _11473 = int(_11466.x);
        _11360 = 0;
        for (;;)
        {
            bool _11476_ladder_break = false;
            do
            {
                if (!(_11360 < _11473))
                {
                    _11476_ladder_break = true;
                    break;
                }
                int _11906 = _11892.x + _11360;
                ivec2 _11908 = ivec2(_11906, _11892.y);
                _11908.y = _11908.y + (_11906 >> 12);
                _11908.x = _11908.x & 4095;
                uvec4 _11488 = texelFetch(SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler, ivec4(_11908, _4761, 0).xyz, 0);
                if (_11449)
                {
                    _11361 = !(_11359 == max(int(_11488.x >> 12u), _11570));
                }
                else
                {
                    _11361 = false;
                }
                if (_11361)
                {
                    break;
                }
                ivec2 _11938 = ivec2(int(_11488.x & 4095u), int(_11488.y & 16383u));
                do
                {
                    highp vec4 _11947 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_11938, _4761, 0).xyz, 0);
                    int _12016 = _11938.x + 1;
                    ivec2 _12018 = ivec2(_12016, _11938.y);
                    _12018.y = _12018.y + (_12016 >> 12);
                    _12018.x = _12018.x & 4095;
                    highp vec4 _11959 = vec4(_11947.xy, _11947.zw) - vec4(_4703, _4703);
                    highp vec2 _11961 = texelFetch(SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler, ivec4(_12018, _4761, 0).xyz, 0).xy - _4703;
                    if ((max(max(_11959.y, _11959.w), _11961.y) * _4919) < (-0.5))
                    {
                        _11940 = false;
                        break;
                    }
                    highp float _11972 = _11959.x;
                    highp float _11973 = _11959.z;
                    highp float _11974 = _11961.x;
                    if (abs(_11972) <= 1.52587890625e-05)
                    {
                        _12046 = 0.0;
                    }
                    else
                    {
                        _12046 = _11972;
                    }
                    if (abs(_11973) <= 1.52587890625e-05)
                    {
                        _12055 = 0.0;
                    }
                    else
                    {
                        _12055 = _11973;
                    }
                    if (abs(_11974) <= 1.52587890625e-05)
                    {
                        _12064 = 0.0;
                    }
                    else
                    {
                        _12064 = _11974;
                    }
                    uint _12045 = (11892u >> (((floatBitsToUint(_12064) >> 29u) & 4u) | ((((floatBitsToUint(_12055) >> 30u) & 2u) | ((floatBitsToUint(_12046) >> 31u) & 4294967293u)) & 4294967291u))) & 257u;
                    if (_12045 != 0u)
                    {
                        highp vec2 _12077 = _11959.xy;
                        highp vec2 _12078 = _11959.zw;
                        highp vec2 _12081 = (_12077 - (_12078 * 2.0)) + _11961;
                        highp vec2 _12082 = _12077 - _12078;
                        highp float _12083 = _12081.x;
                        if (abs(_12083) < 1.52587890625e-05)
                        {
                            highp float _12115 = _12082.x;
                            if (abs(_12115) < 1.52587890625e-05)
                            {
                                _12073 = 0.0;
                            }
                            else
                            {
                                _12073 = (_11959.x * 0.5) / _12115;
                            }
                            _12074 = _12073;
                        }
                        else
                        {
                            highp float _12087 = _12082.x;
                            highp float _12089 = _11959.x;
                            highp float _12090 = _12083 * _12089;
                            highp float _12091 = (_12087 * _12087) - _12090;
                            if (_12091 <= (max(_12087 * _12087, abs(_12090)) * 3.0000001061125658452510833740234e-06))
                            {
                                _12143 = 0.0;
                            }
                            else
                            {
                                _12143 = sqrt(_12091);
                            }
                            if (_12087 >= 0.0)
                            {
                                highp float _12105 = _12087 + _12143;
                                if (abs(_12105) < 1.52587890625e-05)
                                {
                                    _12073 = 0.0;
                                }
                                else
                                {
                                    _12073 = _12089 / _12105;
                                }
                                _12074 = _12105 / _12083;
                            }
                            else
                            {
                                highp float _12095 = _12087 - _12143;
                                if (abs(_12095) < 1.52587890625e-05)
                                {
                                    _12073 = 0.0;
                                }
                                else
                                {
                                    _12073 = _12089 / _12095;
                                }
                                highp float _12103 = _12073;
                                _12073 = _12095 / _12083;
                                _12074 = _12103;
                            }
                        }
                        highp float _12126 = _12081.y;
                        highp float _12130 = _12082.y * 2.0;
                        highp float _12134 = _11959.y;
                        highp vec2 _11979 = vec2((((_12126 * _12073) - _12130) * _12073) + _12134, (((_12126 * _12074) - _12130) * _12074) + _12134) * _4919;
                        if ((_12045 & 1u) != 0u)
                        {
                            highp float _11983 = _11979.x;
                            _11362 -= clamp(_11983 + 0.5, 0.0, 1.0);
                            _11363 = max(_11363, clamp(1.0 - (abs(_11983) * 2.0), 0.0, 1.0));
                        }
                        if (_12045 > 1u)
                        {
                            highp float _11997 = _11979.y;
                            _11362 += clamp(_11997 + 0.5, 0.0, 1.0);
                            _11363 = max(_11363, clamp(1.0 - (abs(_11997) * 2.0), 0.0, 1.0));
                        }
                    }
                    _11940 = true;
                    break;
                } while(false);
                if (!_11940)
                {
                    _11476_ladder_break = true;
                    break;
                }
                break;
            } while(false);
            if (_11476_ladder_break)
            {
                break;
            }
            _11360++;
            continue;
        }
        _11359++;
        continue;
    }
    highp float _11529 = ((_11357 * _11358) + (_11362 * _11363)) / max(_11358 + _11363, 1.52587890625e-05);
    highp float _12157;
    do
    {
        if (false)
        {
            _12157 = 1.0 - abs((fract(_11529 * 0.5) * 2.0) - 1.0);
            break;
        }
        _12157 = abs(_11529);
        break;
    } while(false);
    highp float _12174;
    do
    {
        if (false)
        {
            _12174 = 1.0 - abs((fract(_11357 * 0.5) * 2.0) - 1.0);
            break;
        }
        _12174 = abs(_11357);
        break;
    } while(false);
    highp float _12191;
    do
    {
        if (false)
        {
            _12191 = 1.0 - abs((fract(_11362 * 0.5) * 2.0) - 1.0);
            break;
        }
        _12191 = abs(_11362);
        break;
    } while(false);
    highp float _12210 = clamp(max(_12157, min(_12174, _12191)), 0.0, 1.0);
    highp float _12211 = max(pc.coverage_exponent, 1.52587890625e-05);
    highp float _12207;
    if (abs(_12211 - 1.0) <= 9.9999999747524270787835121154785e-07)
    {
        _12207 = _12210;
    }
    else
    {
        _12207 = pow(_12210, _12211);
    }
    if (_12207 < 0.0039215688593685626983642578125)
    {
        discard;
    }
    highp float _12223 = _12471.w * _12207;
    highp vec4 _12226 = vec4(_12471.xyz * _12223, _12223);
    highp vec4 _4729;
    if (pc.mask_output != 0)
    {
        _4729 = vec4(_12226.w);
    }
    else
    {
        if (pc.output_srgb != 0)
        {
            highp vec4 _12228;
            do
            {
                highp float _12232 = _12226.w;
                if (_12232 <= 0.0)
                {
                    _12228 = vec4(0.0);
                    break;
                }
                highp vec3 _12238 = _12226.xyz * (1.0 / _12232);
                highp float _12247 = max(_12238.x, 0.0);
                highp float _12256;
                if (_12247 <= 0.003130800090730190277099609375)
                {
                    _12256 = _12247 * 12.9200000762939453125;
                }
                else
                {
                    _12256 = (1.05499994754791259765625 * pow(_12247, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                highp float _12250 = max(_12238.y, 0.0);
                highp float _12268;
                if (_12250 <= 0.003130800090730190277099609375)
                {
                    _12268 = _12250 * 12.9200000762939453125;
                }
                else
                {
                    _12268 = (1.05499994754791259765625 * pow(_12250, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                highp float _12253 = max(_12238.z, 0.0);
                highp float _12280;
                if (_12253 <= 0.003130800090730190277099609375)
                {
                    _12280 = _12253 * 12.9200000762939453125;
                }
                else
                {
                    _12280 = (1.05499994754791259765625 * pow(_12253, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
                }
                _12228 = vec4(vec3(_12256, _12268, _12280) * _12232, _12232);
                break;
            } while(false);
            _4729 = _12228;
        }
        else
        {
            _4729 = _12226;
        }
    }
    highp vec4 _4730 = _4729;
    entryPointParam_fragmentMain = _4730;
}


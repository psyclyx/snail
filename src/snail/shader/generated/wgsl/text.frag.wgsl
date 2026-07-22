struct _MatrixStorage_float4x4_ColMajorstd140_0
{
    @align(16) data_0 : array<vec4<f32>, i32(4)>,
};

struct SnailPushConstants_std140_0
{
    @align(16) mvp_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) viewport_0 : vec2<f32>,
    @align(8) subpixel_order_0 : i32,
    @align(4) output_srgb_0 : i32,
    @align(16) layer_base_0 : i32,
    @align(4) coverage_exponent_0 : f32,
    @align(8) dither_scale_0 : f32,
    @align(4) mask_output_0 : i32,
};

@binding(0) @group(2) var<uniform> pc_0 : SnailPushConstants_std140_0;
@binding(0) @group(0) var u_curve_tex_0 : texture_2d_array<f32>;

@binding(1) @group(0) var u_band_tex_0 : texture_2d_array<u32>;

struct CoverageBandSpan_0
{
     first_0 : i32,
     last_0 : i32,
};

fn CoverageBandSpan_x24init_0( first_1 : i32,  last_1 : i32) -> CoverageBandSpan_0
{
    var _S1 : CoverageBandSpan_0;
    _S1.first_0 = first_1;
    _S1.last_0 = last_1;
    return _S1;
}

fn computeCoverageBandSpan_0( coord_0 : f32,  eppAxis_0 : f32,  bandScale_0 : f32,  bandOffset_0 : f32,  bandMax_0 : i32) -> CoverageBandSpan_0
{
    var center_0 : f32 = coord_0 * bandScale_0 + bandOffset_0;
    var _S2 : f32 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    var first_2 : i32 = clamp(i32(center_0 - _S2), i32(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(i32(center_0 + _S2), i32(0), bandMax_0)));
}

fn calcBandLoc_0( glyphLoc_0 : vec2<i32>,  offset_0 : u32) -> vec2<i32>
{
    var _S3 : i32 = glyphLoc_0.x + i32(offset_0);
    var loc_0 : vec2<i32> = vec2<i32>(_S3, glyphLoc_0.y);
    loc_0[i32(1)] = loc_0[i32(1)] + ((_S3 >> (u32(12))));
    loc_0[i32(0)] = ((loc_0[i32(0)]) & (i32(4095)));
    return loc_0;
}

fn decodeBandCurveFirstMemberCommon_0( ref_0 : vec2<u32>) -> i32
{
    return i32(((ref_0.x) >> (u32(12))));
}

fn isCoverageBandSpanOwner_0( ref_1 : vec2<u32>,  band_0 : i32,  spanFirst_0 : i32) -> bool
{
    return band_0 == (max(decodeBandCurveFirstMemberCommon_0(ref_1), spanFirst_0));
}

fn decodeBandCurveLocCommon_0( ref_2 : vec2<u32>) -> vec2<i32>
{
    return vec2<i32>(i32(((ref_2.x) & (u32(4095)))), i32(((ref_2.y) & (u32(16383)))));
}

fn decodeBandCurveLoc_0( ref_3 : vec2<u32>) -> vec2<i32>
{
    return decodeBandCurveLocCommon_0(ref_3);
}

fn offsetCurveLoc_0( base_0 : vec2<i32>,  offset_1 : i32) -> vec2<i32>
{
    var _S4 : i32 = base_0.x + offset_1;
    var loc_1 : vec2<i32> = vec2<i32>(_S4, base_0.y);
    loc_1[i32(1)] = loc_1[i32(1)] + ((_S4 >> (u32(12))));
    loc_1[i32(0)] = ((loc_1[i32(0)]) & (i32(4095)));
    return loc_1;
}

fn rootCodeCoord_0( v_0 : f32) -> f32
{
    var _S5 : f32;
    if((abs(v_0)) <= 0.0000152587890625f)
    {
        _S5 = 0.0f;
    }
    else
    {
        _S5 = v_0;
    }
    return _S5;
}

fn calcRootCode_0( y1_0 : f32,  y2_0 : f32,  y3_0 : f32) -> u32
{
    return (((u32(11892) >> ((((((((bitcast<u32>((rootCodeCoord_0(y3_0)))) >> (u32(29)))) & (u32(4)))) | ((((((((((bitcast<u32>((rootCodeCoord_0(y2_0)))) >> (u32(30)))) & (u32(2)))) | ((((((bitcast<u32>((rootCodeCoord_0(y1_0)))) >> (u32(31)))) & (u32(4294967293))))))) & (u32(4294967291)))))))))) & (u32(257)));
}

fn snapNearTangentSqrt_0( disc_0 : f32,  b_0 : f32,  ac_0 : f32) -> f32
{
    var _S6 : f32;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S6 = 0.0f;
    }
    else
    {
        _S6 = sqrt(disc_0);
    }
    return _S6;
}

fn solveHorizPoly_0( p12_0 : vec4<f32>,  p3_0 : vec2<f32>) -> vec2<f32>
{
    var _S7 : vec2<f32> = p12_0.xy;
    var _S8 : vec2<f32> = p12_0.zw;
    var a_0 : vec2<f32> = _S7 - _S8 * vec2<f32>(2.0f) + p3_0;
    var b_1 : vec2<f32> = _S7 - _S8;
    var _S9 : f32 = a_0.y;
    var t1_0 : f32;
    var t2_0 : f32;
    if((abs(_S9)) < 0.0000152587890625f)
    {
        var _S10 : f32 = b_1.y;
        if((abs(_S10)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p12_0.y * 0.5f / _S10;
        }
        t2_0 = t1_0;
    }
    else
    {
        var _S11 : f32 = b_1.y;
        var _S12 : f32 = p12_0.y;
        var _S13 : f32 = _S9 * _S12;
        var sq_0 : f32 = snapNearTangentSqrt_0(_S11 * _S11 - _S13, _S11, _S13);
        if(_S11 >= 0.0f)
        {
            var q_0 : f32 = _S11 + sq_0;
            var _S14 : f32 = q_0 / _S9;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S12 / q_0;
            }
            t2_0 = _S14;
        }
        else
        {
            var q_1 : f32 = _S11 - sq_0;
            var _S15 : f32 = q_1 / _S9;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S12 / q_1;
            }
            var _S16 : f32 = t1_0;
            t1_0 = _S15;
            t2_0 = _S16;
        }
    }
    var _S17 : f32 = a_0.x;
    var _S18 : f32 = b_1.x * 2.0f;
    var _S19 : f32 = p12_0.x;
    return vec2<f32>((_S17 * t1_0 - _S18) * t1_0 + _S19, (_S17 * t2_0 - _S18) * t2_0 + _S19);
}

fn accumulateHorizContribution_0( xcov_0 : ptr<function, f32>,  xwgt_0 : ptr<function, f32>,  rc_0 : vec2<f32>,  ppe_0 : vec2<f32>,  cLoc_0 : vec2<i32>,  texLayer_0 : i32,  curve_tex_0 : texture_2d_array<f32>) -> bool
{
    var _S20 : vec4<i32> = vec4<i32>(cLoc_0, texLayer_0, i32(0));
    var tex0_0 : vec4<f32> = (textureLoad((curve_tex_0), ((_S20)).xy, i32(((_S20)).z), ((_S20)).w));
    var _S21 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(cLoc_0, i32(1)), texLayer_0, i32(0));
    var p12_1 : vec4<f32> = vec4<f32>(tex0_0.xy, tex0_0.zw) - vec4<f32>(rc_0, rc_0);
    var p3_1 : vec2<f32> = (textureLoad((curve_tex_0), ((_S21)).xy, i32(((_S21)).z), ((_S21)).w)).xy - rc_0;
    var _S22 : f32 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S22) < -0.5f)
    {
        return false;
    }
    var code_0 : u32 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != u32(0))
    {
        var r_0 : vec2<f32> = solveHorizPoly_0(p12_1, p3_1) * vec2<f32>(_S22);
        if(((code_0 & (u32(1)))) != u32(0))
        {
            var _S23 : f32 = r_0.x;
            (*xcov_0) = (*xcov_0) + clamp(_S23 + 0.5f, 0.0f, 1.0f);
            (*xwgt_0) = max((*xwgt_0), clamp(1.0f - abs(_S23) * 2.0f, 0.0f, 1.0f));
        }
        if(code_0 > u32(1))
        {
            var _S24 : f32 = r_0.y;
            (*xcov_0) = (*xcov_0) - clamp(_S24 + 0.5f, 0.0f, 1.0f);
            (*xwgt_0) = max((*xwgt_0), clamp(1.0f - abs(_S24) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

fn solveVertPoly_0( p12_2 : vec4<f32>,  p3_2 : vec2<f32>) -> vec2<f32>
{
    var _S25 : vec2<f32> = p12_2.xy;
    var _S26 : vec2<f32> = p12_2.zw;
    var a_1 : vec2<f32> = _S25 - _S26 * vec2<f32>(2.0f) + p3_2;
    var b_2 : vec2<f32> = _S25 - _S26;
    var _S27 : f32 = a_1.x;
    var t1_1 : f32;
    var t2_1 : f32;
    if((abs(_S27)) < 0.0000152587890625f)
    {
        var _S28 : f32 = b_2.x;
        if((abs(_S28)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p12_2.x * 0.5f / _S28;
        }
        t2_1 = t1_1;
    }
    else
    {
        var _S29 : f32 = b_2.x;
        var _S30 : f32 = p12_2.x;
        var _S31 : f32 = _S27 * _S30;
        var sq_1 : f32 = snapNearTangentSqrt_0(_S29 * _S29 - _S31, _S29, _S31);
        if(_S29 >= 0.0f)
        {
            var q_2 : f32 = _S29 + sq_1;
            var _S32 : f32 = q_2 / _S27;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S30 / q_2;
            }
            t2_1 = _S32;
        }
        else
        {
            var q_3 : f32 = _S29 - sq_1;
            var _S33 : f32 = q_3 / _S27;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S30 / q_3;
            }
            var _S34 : f32 = t1_1;
            t1_1 = _S33;
            t2_1 = _S34;
        }
    }
    var _S35 : f32 = a_1.y;
    var _S36 : f32 = b_2.y * 2.0f;
    var _S37 : f32 = p12_2.y;
    return vec2<f32>((_S35 * t1_1 - _S36) * t1_1 + _S37, (_S35 * t2_1 - _S36) * t2_1 + _S37);
}

fn accumulateVertContribution_0( ycov_0 : ptr<function, f32>,  ywgt_0 : ptr<function, f32>,  rc_1 : vec2<f32>,  ppe_1 : vec2<f32>,  cLoc_1 : vec2<i32>,  texLayer_1 : i32,  curve_tex_1 : texture_2d_array<f32>) -> bool
{
    var _S38 : vec4<i32> = vec4<i32>(cLoc_1, texLayer_1, i32(0));
    var tex0_1 : vec4<f32> = (textureLoad((curve_tex_1), ((_S38)).xy, i32(((_S38)).z), ((_S38)).w));
    var _S39 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(cLoc_1, i32(1)), texLayer_1, i32(0));
    var p12_3 : vec4<f32> = vec4<f32>(tex0_1.xy, tex0_1.zw) - vec4<f32>(rc_1, rc_1);
    var p3_3 : vec2<f32> = (textureLoad((curve_tex_1), ((_S39)).xy, i32(((_S39)).z), ((_S39)).w)).xy - rc_1;
    var _S40 : f32 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S40) < -0.5f)
    {
        return false;
    }
    var code_1 : u32 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != u32(0))
    {
        var r_1 : vec2<f32> = solveVertPoly_0(p12_3, p3_3) * vec2<f32>(_S40);
        if(((code_1 & (u32(1)))) != u32(0))
        {
            var _S41 : f32 = r_1.x;
            (*ycov_0) = (*ycov_0) - clamp(_S41 + 0.5f, 0.0f, 1.0f);
            (*ywgt_0) = max((*ywgt_0), clamp(1.0f - abs(_S41) * 2.0f, 0.0f, 1.0f));
        }
        if(code_1 > u32(1))
        {
            var _S42 : f32 = r_1.y;
            (*ycov_0) = (*ycov_0) + clamp(_S42 + 0.5f, 0.0f, 1.0f);
            (*ywgt_0) = max((*ywgt_0), clamp(1.0f - abs(_S42) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

fn applyFillRule_0( winding_0 : f32,  fill_rule_mode_0 : i32) -> f32
{
    if(fill_rule_mode_0 == i32(1))
    {
        return 1.0f - abs(fract(winding_0 * 0.5f) * 2.0f - 1.0f);
    }
    return abs(winding_0);
}

fn applyCoverageTransfer_0( cov_0 : f32,  coverage_exponent_1 : f32) -> f32
{
    var clamped_0 : f32 = clamp(cov_0, 0.0f, 1.0f);
    var _S43 : f32 = max(coverage_exponent_1, 0.0000152587890625f);
    var _S44 : f32;
    if((abs(_S43 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S44 = clamped_0;
    }
    else
    {
        _S44 = pow(clamped_0, _S43);
    }
    return _S44;
}

fn evalGlyphCoverage_0( rc_2 : vec2<f32>,  epp_0 : vec2<f32>,  ppe_2 : vec2<f32>,  gLoc_0 : vec2<i32>,  bandMax_1 : vec2<i32>,  banding_0 : vec4<f32>,  texLayer_2 : i32,  curve_tex_2 : texture_2d_array<f32>,  band_tex_0 : texture_2d_array<u32>,  coverage_exponent_2 : f32) -> f32
{
    var _S45 : bool;
    var i_0 : i32;
    var _S46 : i32 = bandMax_1.y;
    var hSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S46);
    var vSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    var xcov_1 : f32 = 0.0f;
    var xwgt_1 : f32 = 0.0f;
    var _S47 : bool = (hSpan_0.first_0) != (hSpan_0.last_0);
    var band_1 : i32 = hSpan_0.first_0;
    for(;;)
    {
        if(band_1 <= (hSpan_0.last_0))
        {
        }
        else
        {
            break;
        }
        var _S48 : vec4<i32> = vec4<i32>(calcBandLoc_0(gLoc_0, u32(band_1)), texLayer_2, i32(0));
        var hbd_0 : vec2<u32> = (textureLoad((band_tex_0), ((_S48)).xy, i32(((_S48)).z), ((_S48)).w).xy).xy;
        var _S49 : vec2<i32> = calcBandLoc_0(gLoc_0, hbd_0.y);
        var _S50 : i32 = i32(hbd_0.x);
        i_0 = i32(0);
        for(;;)
        {
            if(i_0 < _S50)
            {
            }
            else
            {
                break;
            }
            var _S51 : vec4<i32> = vec4<i32>(calcBandLoc_0(_S49, u32(i_0)), texLayer_2, i32(0));
            var ref_4 : vec2<u32> = (textureLoad((band_tex_0), ((_S51)).xy, i32(((_S51)).z), ((_S51)).w).xy).xy;
            if(_S47)
            {
                _S45 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S45 = false;
            }
            if(_S45)
            {
                i_0 = i_0 + i32(1);
                continue;
            }
            var _S52 : bool = accumulateHorizContribution_0(&(xcov_1), &(xwgt_1), rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), texLayer_2, curve_tex_2);
            if(!_S52)
            {
                break;
            }
            i_0 = i_0 + i32(1);
        }
        band_1 = band_1 + i32(1);
    }
    var ycov_1 : f32 = 0.0f;
    var ywgt_1 : f32 = 0.0f;
    var _S53 : bool = (vSpan_0.first_0) != (vSpan_0.last_0);
    band_1 = vSpan_0.first_0;
    for(;;)
    {
        if(band_1 <= (vSpan_0.last_0))
        {
        }
        else
        {
            break;
        }
        var _S54 : vec4<i32> = vec4<i32>(calcBandLoc_0(gLoc_0, u32(_S46 + i32(1) + band_1)), texLayer_2, i32(0));
        var vbd_0 : vec2<u32> = (textureLoad((band_tex_0), ((_S54)).xy, i32(((_S54)).z), ((_S54)).w).xy).xy;
        var _S55 : vec2<i32> = calcBandLoc_0(gLoc_0, vbd_0.y);
        var _S56 : i32 = i32(vbd_0.x);
        i_0 = i32(0);
        for(;;)
        {
            if(i_0 < _S56)
            {
            }
            else
            {
                break;
            }
            var _S57 : vec4<i32> = vec4<i32>(calcBandLoc_0(_S55, u32(i_0)), texLayer_2, i32(0));
            var ref_5 : vec2<u32> = (textureLoad((band_tex_0), ((_S57)).xy, i32(((_S57)).z), ((_S57)).w).xy).xy;
            if(_S53)
            {
                _S45 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S45 = false;
            }
            if(_S45)
            {
                i_0 = i_0 + i32(1);
                continue;
            }
            var _S58 : bool = accumulateVertContribution_0(&(ycov_1), &(ywgt_1), rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), texLayer_2, curve_tex_2);
            if(!_S58)
            {
                break;
            }
            i_0 = i_0 + i32(1);
        }
        band_1 = band_1 + i32(1);
    }
    return applyCoverageTransfer_0(max(applyFillRule_0((xcov_1 * xwgt_1 + ycov_1 * ywgt_1) / max(xwgt_1 + ywgt_1, 0.0000152587890625f), i32(0)), min(applyFillRule_0(xcov_1, i32(0)), applyFillRule_0(ycov_1, i32(0)))), coverage_exponent_2);
}

fn premultiplyColor_0( color_0 : vec4<f32>,  cov_1 : f32) -> vec4<f32>
{
    var alpha_0 : f32 = color_0.w * cov_1;
    return vec4<f32>(color_0.xyz * vec3<f32>(alpha_0), alpha_0);
}

fn srgbEncode_0( c_0 : f32) -> f32
{
    var _S59 : f32;
    if(c_0 <= 0.00313080009073019f)
    {
        _S59 = c_0 * 12.92000007629394531f;
    }
    else
    {
        _S59 = 1.0549999475479126f * pow(c_0, 0.4166666567325592f) - 0.05499999970197678f;
    }
    return _S59;
}

fn linearToSrgb_0( color_1 : vec3<f32>) -> vec3<f32>
{
    return vec3<f32>(srgbEncode_0(max(color_1.x, 0.0f)), srgbEncode_0(max(color_1.y, 0.0f)), srgbEncode_0(max(color_1.z, 0.0f)));
}

fn srgbEncodePremultiplied_0( premul_0 : vec4<f32>) -> vec4<f32>
{
    var _S60 : f32 = premul_0.w;
    if(_S60 <= 0.0f)
    {
        return vec4<f32>(0.0f);
    }
    return vec4<f32>(linearToSrgb_0(premul_0.xyz * vec3<f32>((1.0f / _S60))) * vec3<f32>(_S60), _S60);
}

struct TextVaryings_0
{
     color_2 : vec4<f32>,
     tint_0 : vec4<f32>,
     texcoord_0 : vec2<f32>,
     banding_1 : vec4<f32>,
     glyph_0 : vec4<i32>,
};

fn snailTextFragment_0( v_1 : TextVaryings_0,  curve_tex_3 : texture_2d_array<f32>,  band_tex_1 : texture_2d_array<u32>,  layer_base_1 : i32,  output_srgb_1 : i32,  coverage_exponent_3 : f32,  mask_output_1 : i32) -> vec4<f32>
{
    var _S61 : i32 = v_1.glyph_0.w;
    var layer_byte_0 : i32 = (((_S61 >> (u32(8)))) & (i32(255)));
    if(layer_byte_0 == i32(255))
    {
        discard;
    }
    var epp_1 : vec2<f32> = (fwidth((v_1.texcoord_0)));
    var cov_2 : f32 = evalGlyphCoverage_0(v_1.texcoord_0, epp_1, vec2<f32>(1.0f / max(epp_1.x, 0.0000152587890625f), 1.0f / max(epp_1.y, 0.0000152587890625f)), v_1.glyph_0.xy, vec2<i32>((_S61 & (i32(255))), v_1.glyph_0.z), v_1.banding_1, layer_base_1 + layer_byte_0, curve_tex_3, band_tex_1, coverage_exponent_3);
    if(cov_2 < 0.00392156885936856f)
    {
        discard;
    }
    var premul_1 : vec4<f32> = premultiplyColor_0(v_1.color_2 * v_1.tint_0, cov_2);
    var _S62 : vec4<f32>;
    if(mask_output_1 != i32(0))
    {
        _S62 = vec4<f32>(premul_1.w);
    }
    else
    {
        if(output_srgb_1 != i32(0))
        {
            _S62 = srgbEncodePremultiplied_0(premul_1);
        }
        else
        {
            _S62 = premul_1;
        }
    }
    return _S62;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) color_3 : vec4<f32>,
    @location(1) texcoord_1 : vec2<f32>,
    @interpolate(flat) @location(2) banding_2 : vec4<f32>,
    @interpolate(flat) @location(3) glyph_1 : vec4<i32>,
    @location(4) tint_1 : vec4<f32>,
};

@fragment
fn fragmentMain( _S63 : pixelInput_0, @builtin(position) position_0 : vec4<f32>) -> pixelOutput_0
{
    var v_2 : TextVaryings_0;
    v_2.color_2 = _S63.color_3;
    v_2.tint_0 = _S63.tint_1;
    v_2.texcoord_0 = _S63.texcoord_1;
    v_2.banding_1 = _S63.banding_2;
    v_2.glyph_0 = _S63.glyph_1;
    var _S64 : vec4<f32> = snailTextFragment_0(v_2, u_curve_tex_0, u_band_tex_0, pc_0.layer_base_0, pc_0.output_srgb_0, pc_0.coverage_exponent_0, pc_0.mask_output_0);
    var _S65 : pixelOutput_0 = pixelOutput_0( _S64 );
    return _S65;
}


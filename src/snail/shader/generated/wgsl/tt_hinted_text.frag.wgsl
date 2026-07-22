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

@binding(2) @group(0) var u_layer_tex_0 : texture_2d<f32>;

fn offsetTtHintedInfoLoc_0( layer_tex_0 : texture_2d<f32>,  base_0 : vec2<i32>,  offset_0 : i32) -> vec2<i32>
{
    var uw_0 : u32;
    var uh_0 : u32;
    {var dim = textureDimensions((layer_tex_0));((uw_0)) = dim.x;((uh_0)) = dim.y;};
    var width_0 : i32 = i32(uw_0);
    var texel_0 : i32 = base_0.y * width_0 + base_0.x + offset_0;
    var _S1 : i32 = texel_0 % width_0;
    var _S2 : i32 = texel_0 / width_0;
    return vec2<i32>(_S1, _S2);
}

struct CoverageBandSpan_0
{
     first_0 : i32,
     last_0 : i32,
};

fn CoverageBandSpan_x24init_0( first_1 : i32,  last_1 : i32) -> CoverageBandSpan_0
{
    var _S3 : CoverageBandSpan_0;
    _S3.first_0 = first_1;
    _S3.last_0 = last_1;
    return _S3;
}

fn computeCoverageBandSpan_0( coord_0 : f32,  eppAxis_0 : f32,  bandScale_0 : f32,  bandOffset_0 : f32,  bandMax_0 : i32) -> CoverageBandSpan_0
{
    var center_0 : f32 = coord_0 * bandScale_0 + bandOffset_0;
    var _S4 : f32 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    var first_2 : i32 = clamp(i32(center_0 - _S4), i32(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(i32(center_0 + _S4), i32(0), bandMax_0)));
}

fn calcBandLoc_0( glyphLoc_0 : vec2<i32>,  offset_1 : u32) -> vec2<i32>
{
    var _S5 : i32 = glyphLoc_0.x + i32(offset_1);
    var loc_0 : vec2<i32> = vec2<i32>(_S5, glyphLoc_0.y);
    loc_0[i32(1)] = loc_0[i32(1)] + ((_S5 >> (u32(12))));
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

fn offsetCurveLoc_0( base_1 : vec2<i32>,  offset_2 : i32) -> vec2<i32>
{
    var _S6 : i32 = base_1.x + offset_2;
    var loc_1 : vec2<i32> = vec2<i32>(_S6, base_1.y);
    loc_1[i32(1)] = loc_1[i32(1)] + ((_S6 >> (u32(12))));
    loc_1[i32(0)] = ((loc_1[i32(0)]) & (i32(4095)));
    return loc_1;
}

fn rootCodeCoord_0( v_0 : f32) -> f32
{
    var _S7 : f32;
    if((abs(v_0)) <= 0.0000152587890625f)
    {
        _S7 = 0.0f;
    }
    else
    {
        _S7 = v_0;
    }
    return _S7;
}

fn calcRootCode_0( y1_0 : f32,  y2_0 : f32,  y3_0 : f32) -> u32
{
    return (((u32(11892) >> ((((((((bitcast<u32>((rootCodeCoord_0(y3_0)))) >> (u32(29)))) & (u32(4)))) | ((((((((((bitcast<u32>((rootCodeCoord_0(y2_0)))) >> (u32(30)))) & (u32(2)))) | ((((((bitcast<u32>((rootCodeCoord_0(y1_0)))) >> (u32(31)))) & (u32(4294967293))))))) & (u32(4294967291)))))))))) & (u32(257)));
}

fn snapNearTangentSqrt_0( disc_0 : f32,  b_0 : f32,  ac_0 : f32) -> f32
{
    var _S8 : f32;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S8 = 0.0f;
    }
    else
    {
        _S8 = sqrt(disc_0);
    }
    return _S8;
}

fn solveHorizPoly_0( p12_0 : vec4<f32>,  p3_0 : vec2<f32>) -> vec2<f32>
{
    var _S9 : vec2<f32> = p12_0.xy;
    var _S10 : vec2<f32> = p12_0.zw;
    var a_0 : vec2<f32> = _S9 - _S10 * vec2<f32>(2.0f) + p3_0;
    var b_1 : vec2<f32> = _S9 - _S10;
    var _S11 : f32 = a_0.y;
    var t1_0 : f32;
    var t2_0 : f32;
    if((abs(_S11)) < 0.0000152587890625f)
    {
        var _S12 : f32 = b_1.y;
        if((abs(_S12)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p12_0.y * 0.5f / _S12;
        }
        t2_0 = t1_0;
    }
    else
    {
        var _S13 : f32 = b_1.y;
        var _S14 : f32 = p12_0.y;
        var _S15 : f32 = _S11 * _S14;
        var sq_0 : f32 = snapNearTangentSqrt_0(_S13 * _S13 - _S15, _S13, _S15);
        if(_S13 >= 0.0f)
        {
            var q_0 : f32 = _S13 + sq_0;
            var _S16 : f32 = q_0 / _S11;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S14 / q_0;
            }
            t2_0 = _S16;
        }
        else
        {
            var q_1 : f32 = _S13 - sq_0;
            var _S17 : f32 = q_1 / _S11;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S14 / q_1;
            }
            var _S18 : f32 = t1_0;
            t1_0 = _S17;
            t2_0 = _S18;
        }
    }
    var _S19 : f32 = a_0.x;
    var _S20 : f32 = b_1.x * 2.0f;
    var _S21 : f32 = p12_0.x;
    return vec2<f32>((_S19 * t1_0 - _S20) * t1_0 + _S21, (_S19 * t2_0 - _S20) * t2_0 + _S21);
}

fn accumulateHorizContribution_0( xcov_0 : ptr<function, f32>,  xwgt_0 : ptr<function, f32>,  rc_0 : vec2<f32>,  ppe_0 : vec2<f32>,  cLoc_0 : vec2<i32>,  texLayer_0 : i32,  curve_tex_0 : texture_2d_array<f32>) -> bool
{
    var _S22 : vec4<i32> = vec4<i32>(cLoc_0, texLayer_0, i32(0));
    var tex0_0 : vec4<f32> = (textureLoad((curve_tex_0), ((_S22)).xy, i32(((_S22)).z), ((_S22)).w));
    var _S23 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(cLoc_0, i32(1)), texLayer_0, i32(0));
    var p12_1 : vec4<f32> = vec4<f32>(tex0_0.xy, tex0_0.zw) - vec4<f32>(rc_0, rc_0);
    var p3_1 : vec2<f32> = (textureLoad((curve_tex_0), ((_S23)).xy, i32(((_S23)).z), ((_S23)).w)).xy - rc_0;
    var _S24 : f32 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S24) < -0.5f)
    {
        return false;
    }
    var code_0 : u32 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != u32(0))
    {
        var r_0 : vec2<f32> = solveHorizPoly_0(p12_1, p3_1) * vec2<f32>(_S24);
        if(((code_0 & (u32(1)))) != u32(0))
        {
            var _S25 : f32 = r_0.x;
            (*xcov_0) = (*xcov_0) + clamp(_S25 + 0.5f, 0.0f, 1.0f);
            (*xwgt_0) = max((*xwgt_0), clamp(1.0f - abs(_S25) * 2.0f, 0.0f, 1.0f));
        }
        if(code_0 > u32(1))
        {
            var _S26 : f32 = r_0.y;
            (*xcov_0) = (*xcov_0) - clamp(_S26 + 0.5f, 0.0f, 1.0f);
            (*xwgt_0) = max((*xwgt_0), clamp(1.0f - abs(_S26) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

fn solveVertPoly_0( p12_2 : vec4<f32>,  p3_2 : vec2<f32>) -> vec2<f32>
{
    var _S27 : vec2<f32> = p12_2.xy;
    var _S28 : vec2<f32> = p12_2.zw;
    var a_1 : vec2<f32> = _S27 - _S28 * vec2<f32>(2.0f) + p3_2;
    var b_2 : vec2<f32> = _S27 - _S28;
    var _S29 : f32 = a_1.x;
    var t1_1 : f32;
    var t2_1 : f32;
    if((abs(_S29)) < 0.0000152587890625f)
    {
        var _S30 : f32 = b_2.x;
        if((abs(_S30)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p12_2.x * 0.5f / _S30;
        }
        t2_1 = t1_1;
    }
    else
    {
        var _S31 : f32 = b_2.x;
        var _S32 : f32 = p12_2.x;
        var _S33 : f32 = _S29 * _S32;
        var sq_1 : f32 = snapNearTangentSqrt_0(_S31 * _S31 - _S33, _S31, _S33);
        if(_S31 >= 0.0f)
        {
            var q_2 : f32 = _S31 + sq_1;
            var _S34 : f32 = q_2 / _S29;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S32 / q_2;
            }
            t2_1 = _S34;
        }
        else
        {
            var q_3 : f32 = _S31 - sq_1;
            var _S35 : f32 = q_3 / _S29;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S32 / q_3;
            }
            var _S36 : f32 = t1_1;
            t1_1 = _S35;
            t2_1 = _S36;
        }
    }
    var _S37 : f32 = a_1.y;
    var _S38 : f32 = b_2.y * 2.0f;
    var _S39 : f32 = p12_2.y;
    return vec2<f32>((_S37 * t1_1 - _S38) * t1_1 + _S39, (_S37 * t2_1 - _S38) * t2_1 + _S39);
}

fn accumulateVertContribution_0( ycov_0 : ptr<function, f32>,  ywgt_0 : ptr<function, f32>,  rc_1 : vec2<f32>,  ppe_1 : vec2<f32>,  cLoc_1 : vec2<i32>,  texLayer_1 : i32,  curve_tex_1 : texture_2d_array<f32>) -> bool
{
    var _S40 : vec4<i32> = vec4<i32>(cLoc_1, texLayer_1, i32(0));
    var tex0_1 : vec4<f32> = (textureLoad((curve_tex_1), ((_S40)).xy, i32(((_S40)).z), ((_S40)).w));
    var _S41 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(cLoc_1, i32(1)), texLayer_1, i32(0));
    var p12_3 : vec4<f32> = vec4<f32>(tex0_1.xy, tex0_1.zw) - vec4<f32>(rc_1, rc_1);
    var p3_3 : vec2<f32> = (textureLoad((curve_tex_1), ((_S41)).xy, i32(((_S41)).z), ((_S41)).w)).xy - rc_1;
    var _S42 : f32 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S42) < -0.5f)
    {
        return false;
    }
    var code_1 : u32 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != u32(0))
    {
        var r_1 : vec2<f32> = solveVertPoly_0(p12_3, p3_3) * vec2<f32>(_S42);
        if(((code_1 & (u32(1)))) != u32(0))
        {
            var _S43 : f32 = r_1.x;
            (*ycov_0) = (*ycov_0) - clamp(_S43 + 0.5f, 0.0f, 1.0f);
            (*ywgt_0) = max((*ywgt_0), clamp(1.0f - abs(_S43) * 2.0f, 0.0f, 1.0f));
        }
        if(code_1 > u32(1))
        {
            var _S44 : f32 = r_1.y;
            (*ycov_0) = (*ycov_0) + clamp(_S44 + 0.5f, 0.0f, 1.0f);
            (*ywgt_0) = max((*ywgt_0), clamp(1.0f - abs(_S44) * 2.0f, 0.0f, 1.0f));
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
    var _S45 : f32 = max(coverage_exponent_1, 0.0000152587890625f);
    var _S46 : f32;
    if((abs(_S45 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S46 = clamped_0;
    }
    else
    {
        _S46 = pow(clamped_0, _S45);
    }
    return _S46;
}

fn evalGlyphCoverage_0( rc_2 : vec2<f32>,  epp_0 : vec2<f32>,  ppe_2 : vec2<f32>,  gLoc_0 : vec2<i32>,  bandMax_1 : vec2<i32>,  banding_0 : vec4<f32>,  texLayer_2 : i32,  curve_tex_2 : texture_2d_array<f32>,  band_tex_0 : texture_2d_array<u32>,  coverage_exponent_2 : f32) -> f32
{
    var _S47 : bool;
    var i_0 : i32;
    var _S48 : i32 = bandMax_1.y;
    var hSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_0.y, banding_0.w, _S48);
    var vSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    var xcov_1 : f32 = 0.0f;
    var xwgt_1 : f32 = 0.0f;
    var _S49 : bool = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        var _S50 : vec4<i32> = vec4<i32>(calcBandLoc_0(gLoc_0, u32(band_1)), texLayer_2, i32(0));
        var hbd_0 : vec2<u32> = (textureLoad((band_tex_0), ((_S50)).xy, i32(((_S50)).z), ((_S50)).w).xy).xy;
        var _S51 : vec2<i32> = calcBandLoc_0(gLoc_0, hbd_0.y);
        var _S52 : i32 = i32(hbd_0.x);
        i_0 = i32(0);
        for(;;)
        {
            if(i_0 < _S52)
            {
            }
            else
            {
                break;
            }
            var _S53 : vec4<i32> = vec4<i32>(calcBandLoc_0(_S51, u32(i_0)), texLayer_2, i32(0));
            var ref_4 : vec2<u32> = (textureLoad((band_tex_0), ((_S53)).xy, i32(((_S53)).z), ((_S53)).w).xy).xy;
            if(_S49)
            {
                _S47 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S47 = false;
            }
            if(_S47)
            {
                i_0 = i_0 + i32(1);
                continue;
            }
            var _S54 : bool = accumulateHorizContribution_0(&(xcov_1), &(xwgt_1), rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), texLayer_2, curve_tex_2);
            if(!_S54)
            {
                break;
            }
            i_0 = i_0 + i32(1);
        }
        band_1 = band_1 + i32(1);
    }
    var ycov_1 : f32 = 0.0f;
    var ywgt_1 : f32 = 0.0f;
    var _S55 : bool = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        var _S56 : vec4<i32> = vec4<i32>(calcBandLoc_0(gLoc_0, u32(_S48 + i32(1) + band_1)), texLayer_2, i32(0));
        var vbd_0 : vec2<u32> = (textureLoad((band_tex_0), ((_S56)).xy, i32(((_S56)).z), ((_S56)).w).xy).xy;
        var _S57 : vec2<i32> = calcBandLoc_0(gLoc_0, vbd_0.y);
        var _S58 : i32 = i32(vbd_0.x);
        i_0 = i32(0);
        for(;;)
        {
            if(i_0 < _S58)
            {
            }
            else
            {
                break;
            }
            var _S59 : vec4<i32> = vec4<i32>(calcBandLoc_0(_S57, u32(i_0)), texLayer_2, i32(0));
            var ref_5 : vec2<u32> = (textureLoad((band_tex_0), ((_S59)).xy, i32(((_S59)).z), ((_S59)).w).xy).xy;
            if(_S55)
            {
                _S47 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S47 = false;
            }
            if(_S47)
            {
                i_0 = i_0 + i32(1);
                continue;
            }
            var _S60 : bool = accumulateVertContribution_0(&(ycov_1), &(ywgt_1), rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), texLayer_2, curve_tex_2);
            if(!_S60)
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
    var _S61 : f32;
    if(c_0 <= 0.00313080009073019f)
    {
        _S61 = c_0 * 12.92000007629394531f;
    }
    else
    {
        _S61 = 1.0549999475479126f * pow(c_0, 0.4166666567325592f) - 0.05499999970197678f;
    }
    return _S61;
}

fn linearToSrgb_0( color_1 : vec3<f32>) -> vec3<f32>
{
    return vec3<f32>(srgbEncode_0(max(color_1.x, 0.0f)), srgbEncode_0(max(color_1.y, 0.0f)), srgbEncode_0(max(color_1.z, 0.0f)));
}

fn srgbEncodePremultiplied_0( premul_0 : vec4<f32>) -> vec4<f32>
{
    var _S62 : f32 = premul_0.w;
    if(_S62 <= 0.0f)
    {
        return vec4<f32>(0.0f);
    }
    return vec4<f32>(linearToSrgb_0(premul_0.xyz * vec3<f32>((1.0f / _S62))) * vec3<f32>(_S62), _S62);
}

struct TtHintedVaryings_0
{
     color_2 : vec4<f32>,
     tint_0 : vec4<f32>,
     texcoord_0 : vec2<f32>,
     banding_1 : vec4<f32>,
     glyph_0 : vec4<i32>,
};

fn snailTtHintedTextFragment_0( v_1 : TtHintedVaryings_0,  curve_tex_3 : texture_2d_array<f32>,  band_tex_1 : texture_2d_array<u32>,  layer_tex_1 : texture_2d<f32>,  layer_base_1 : i32,  output_srgb_1 : i32,  coverage_exponent_3 : f32,  mask_output_1 : i32) -> vec4<f32>
{
    var _S63 : i32 = v_1.glyph_0.w;
    if(((((_S63 >> (u32(8)))) & (i32(255)))) != i32(255))
    {
        discard;
    }
    if(((_S63 & (i32(255)))) != i32(2))
    {
        discard;
    }
    var epp_1 : vec2<f32> = (fwidth((v_1.texcoord_0)));
    var ppe_3 : vec2<f32> = vec2<f32>(1.0f / max(epp_1.x, 0.0000152587890625f), 1.0f / max(epp_1.y, 0.0000152587890625f));
    var info_base_0 : vec2<i32> = v_1.glyph_0.xy;
    var _S64 : vec3<i32> = vec3<i32>(info_base_0, i32(0));
    var header_0 : vec4<f32> = (textureLoad((layer_tex_1), ((_S64)).xy, ((_S64)).z));
    var _S65 : vec2<i32> = offsetTtHintedInfoLoc_0(layer_tex_1, info_base_0, i32(1));
    var _S66 : vec3<i32> = vec3<i32>(_S65, i32(0));
    var packed_counts_0 : i32 = (bitcast<i32>((header_0.z)));
    var cov_2 : f32 = evalGlyphCoverage_0(v_1.texcoord_0, epp_1, ppe_3, vec2<i32>(i32(header_0.x), i32(header_0.y)), vec2<i32>((((packed_counts_0 >> (u32(16)))) & (i32(65535))), (packed_counts_0 & (i32(65535)))), (textureLoad((layer_tex_1), ((_S66)).xy, ((_S66)).z)), layer_base_1 + i32(v_1.banding_1.w), curve_tex_3, band_tex_1, coverage_exponent_3);
    if(cov_2 < 0.00392156885936856f)
    {
        discard;
    }
    var premul_1 : vec4<f32> = premultiplyColor_0(v_1.color_2 * v_1.tint_0, cov_2);
    var _S67 : vec4<f32>;
    if(mask_output_1 != i32(0))
    {
        _S67 = vec4<f32>(premul_1.w);
    }
    else
    {
        if(output_srgb_1 != i32(0))
        {
            _S67 = srgbEncodePremultiplied_0(premul_1);
        }
        else
        {
            _S67 = premul_1;
        }
    }
    return _S67;
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
fn fragmentMain( _S68 : pixelInput_0, @builtin(position) position_0 : vec4<f32>) -> pixelOutput_0
{
    var v_2 : TtHintedVaryings_0;
    v_2.color_2 = _S68.color_3;
    v_2.tint_0 = _S68.tint_1;
    v_2.texcoord_0 = _S68.texcoord_1;
    v_2.banding_1 = _S68.banding_2;
    v_2.glyph_0 = _S68.glyph_1;
    var _S69 : vec4<f32> = snailTtHintedTextFragment_0(v_2, u_curve_tex_0, u_band_tex_0, u_layer_tex_0, pc_0.layer_base_0, pc_0.output_srgb_0, pc_0.coverage_exponent_0, pc_0.mask_output_0);
    var _S70 : pixelOutput_0 = pixelOutput_0( _S69 );
    return _S70;
}


struct SnailTextSampleParams_std140_0
{
    @align(16) glyph_count_0 : i32,
    @align(4) words_per_glyph_0 : i32,
    @align(8) layer_base_0 : i32,
    @align(4) coverage_exponent_0 : f32,
};

@binding(0) @group(2) var<uniform> pc_0 : SnailTextSampleParams_std140_0;
@binding(0) @group(0) var u_curve_tex_0 : texture_2d_array<f32>;

@binding(1) @group(0) var u_band_tex_0 : texture_2d_array<u32>;

@binding(4) @group(0) var<storage, read> u_snail_text_records_0 : array<u32>;

fn Records_word_0( linear_index_0 : i32) -> u32
{
    return u_snail_text_records_0[linear_index_0];
}

fn snailTextSampleWord_0( words_per_glyph_1 : i32,  glyph_index_0 : i32,  word_offset_0 : i32) -> u32
{
    return Records_word_0(glyph_index_0 * words_per_glyph_1 + word_offset_0);
}

fn snailDecodeFloat16_0( bits_0 : u32) -> f32
{
    var exponent_0 : u32 = (((bits_0 >> (u32(10)))) & (u32(31)));
    var fraction_0 : u32 = (bits_0 & (u32(1023)));
    var sign_0 : f32;
    if(((bits_0 >> (u32(15)))) == u32(0))
    {
        sign_0 = 1.0f;
    }
    else
    {
        sign_0 = -1.0f;
    }
    if(exponent_0 == u32(0))
    {
        if(fraction_0 == u32(0))
        {
            return sign_0 * 0.0f;
        }
        return sign_0 * exp2(-14.0f) * (f32(fraction_0) / 1024.0f);
    }
    if(exponent_0 == u32(31))
    {
        return sign_0 * 65504.0f;
    }
    return sign_0 * exp2(f32(exponent_0) - 15.0f) * (1.0f + f32(fraction_0) / 1024.0f);
}

fn snailUnpackHalf2_0( word_0 : u32) -> vec2<f32>
{
    return vec2<f32>(snailDecodeFloat16_0((word_0 & (u32(65535)))), snailDecodeFloat16_0((word_0 >> (u32(16)))));
}

fn snailUnpackHalf4_0( lo_0 : u32,  hi_0 : u32) -> vec4<f32>
{
    return vec4<f32>(snailUnpackHalf2_0(lo_0), snailUnpackHalf2_0(hi_0));
}

fn snailUnpackUnorm4x8_0( word_1 : u32) -> vec4<f32>
{
    return vec4<f32>(f32((word_1 & (u32(255)))), f32((((word_1 >> (u32(8)))) & (u32(255)))), f32((((word_1 >> (u32(16)))) & (u32(255)))), f32((((word_1 >> (u32(24)))) & (u32(255))))) / vec4<f32>(255.0f);
}

struct SnailTextSampleRecord_0
{
     rect_0 : vec4<f32>,
     xform_0 : vec4<f32>,
     origin_0 : vec2<f32>,
     glyph_0 : vec2<u32>,
     banding_0 : vec4<f32>,
     color_0 : vec4<f32>,
     tint_0 : vec4<f32>,
};

fn snailTextSampleRecord_0( words_per_glyph_2 : i32,  glyph_index_1 : i32) -> SnailTextSampleRecord_0
{
    var record_0 : SnailTextSampleRecord_0;
    record_0.rect_0 = snailUnpackHalf4_0(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(0)), snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(1)));
    record_0.xform_0 = vec4<f32>((bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(2))))), (bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(3))))), (bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(4))))), (bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(5))))));
    record_0.origin_0 = vec2<f32>((bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(6))))), (bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(7))))));
    record_0.glyph_0 = vec2<u32>(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(8)), snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(9)));
    record_0.banding_0 = vec4<f32>((bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(10))))), (bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(11))))), (bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(12))))), (bitcast<f32>((snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(13))))));
    record_0.color_0 = snailUnpackUnorm4x8_0(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(14)));
    record_0.tint_0 = snailUnpackUnorm4x8_0(snailTextSampleWord_0(words_per_glyph_2, glyph_index_1, i32(15)));
    return record_0;
}

fn snailTextSampleLocalCoord_0( scene_pos_0 : vec2<f32>,  xform_1 : vec4<f32>,  origin_1 : vec2<f32>) -> vec2<f32>
{
    var _S1 : f32 = xform_1.x;
    var _S2 : f32 = xform_1.w;
    var _S3 : f32 = xform_1.y;
    var _S4 : f32 = xform_1.z;
    var det_0 : f32 = _S1 * _S2 - _S3 * _S4;
    var delta_0 : vec2<f32> = scene_pos_0 - origin_1;
    var _S5 : f32 = delta_0.x;
    var _S6 : f32 = delta_0.y;
    return vec2<f32>((_S2 * _S5 - _S3 * _S6) / det_0, (- _S4 * _S5 + _S1 * _S6) / det_0);
}

fn snailTextSampleLocalVector_0( scene_vector_0 : vec2<f32>,  xform_2 : vec4<f32>) -> vec2<f32>
{
    var _S7 : f32 = xform_2.x;
    var _S8 : f32 = xform_2.w;
    var _S9 : f32 = xform_2.y;
    var _S10 : f32 = xform_2.z;
    var det_1 : f32 = _S7 * _S8 - _S9 * _S10;
    var _S11 : f32 = scene_vector_0.x;
    var _S12 : f32 = scene_vector_0.y;
    return vec2<f32>((_S8 * _S11 - _S9 * _S12) / det_1, (- _S10 * _S11 + _S7 * _S12) / det_1);
}

struct CoverageBandSpan_0
{
     first_0 : i32,
     last_0 : i32,
};

fn CoverageBandSpan_x24init_0( first_1 : i32,  last_1 : i32) -> CoverageBandSpan_0
{
    var _S13 : CoverageBandSpan_0;
    _S13.first_0 = first_1;
    _S13.last_0 = last_1;
    return _S13;
}

fn computeCoverageBandSpan_0( coord_0 : f32,  eppAxis_0 : f32,  bandScale_0 : f32,  bandOffset_0 : f32,  bandMax_0 : i32) -> CoverageBandSpan_0
{
    var center_0 : f32 = coord_0 * bandScale_0 + bandOffset_0;
    var _S14 : f32 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    var first_2 : i32 = clamp(i32(center_0 - _S14), i32(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(i32(center_0 + _S14), i32(0), bandMax_0)));
}

fn calcBandLoc_0( glyphLoc_0 : vec2<i32>,  offset_0 : u32) -> vec2<i32>
{
    var _S15 : i32 = glyphLoc_0.x + i32(offset_0);
    var loc_0 : vec2<i32> = vec2<i32>(_S15, glyphLoc_0.y);
    loc_0[i32(1)] = loc_0[i32(1)] + ((_S15 >> (u32(12))));
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
    var _S16 : i32 = base_0.x + offset_1;
    var loc_1 : vec2<i32> = vec2<i32>(_S16, base_0.y);
    loc_1[i32(1)] = loc_1[i32(1)] + ((_S16 >> (u32(12))));
    loc_1[i32(0)] = ((loc_1[i32(0)]) & (i32(4095)));
    return loc_1;
}

fn rootCodeCoord_0( v_0 : f32) -> f32
{
    var _S17 : f32;
    if((abs(v_0)) <= 0.0000152587890625f)
    {
        _S17 = 0.0f;
    }
    else
    {
        _S17 = v_0;
    }
    return _S17;
}

fn calcRootCode_0( y1_0 : f32,  y2_0 : f32,  y3_0 : f32) -> u32
{
    return (((u32(11892) >> ((((((((bitcast<u32>((rootCodeCoord_0(y3_0)))) >> (u32(29)))) & (u32(4)))) | ((((((((((bitcast<u32>((rootCodeCoord_0(y2_0)))) >> (u32(30)))) & (u32(2)))) | ((((((bitcast<u32>((rootCodeCoord_0(y1_0)))) >> (u32(31)))) & (u32(4294967293))))))) & (u32(4294967291)))))))))) & (u32(257)));
}

fn snapNearTangentSqrt_0( disc_0 : f32,  b_0 : f32,  ac_0 : f32) -> f32
{
    var _S18 : f32;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S18 = 0.0f;
    }
    else
    {
        _S18 = sqrt(disc_0);
    }
    return _S18;
}

fn solveHorizPoly_0( p12_0 : vec4<f32>,  p3_0 : vec2<f32>) -> vec2<f32>
{
    var _S19 : vec2<f32> = p12_0.xy;
    var _S20 : vec2<f32> = p12_0.zw;
    var a_0 : vec2<f32> = _S19 - _S20 * vec2<f32>(2.0f) + p3_0;
    var b_1 : vec2<f32> = _S19 - _S20;
    var _S21 : f32 = a_0.y;
    var t1_0 : f32;
    var t2_0 : f32;
    if((abs(_S21)) < 0.0000152587890625f)
    {
        var _S22 : f32 = b_1.y;
        if((abs(_S22)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p12_0.y * 0.5f / _S22;
        }
        t2_0 = t1_0;
    }
    else
    {
        var _S23 : f32 = b_1.y;
        var _S24 : f32 = p12_0.y;
        var _S25 : f32 = _S21 * _S24;
        var sq_0 : f32 = snapNearTangentSqrt_0(_S23 * _S23 - _S25, _S23, _S25);
        if(_S23 >= 0.0f)
        {
            var q_0 : f32 = _S23 + sq_0;
            var _S26 : f32 = q_0 / _S21;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S24 / q_0;
            }
            t2_0 = _S26;
        }
        else
        {
            var q_1 : f32 = _S23 - sq_0;
            var _S27 : f32 = q_1 / _S21;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = _S24 / q_1;
            }
            var _S28 : f32 = t1_0;
            t1_0 = _S27;
            t2_0 = _S28;
        }
    }
    var _S29 : f32 = a_0.x;
    var _S30 : f32 = b_1.x * 2.0f;
    var _S31 : f32 = p12_0.x;
    return vec2<f32>((_S29 * t1_0 - _S30) * t1_0 + _S31, (_S29 * t2_0 - _S30) * t2_0 + _S31);
}

fn accumulateHorizContribution_0( xcov_0 : ptr<function, f32>,  xwgt_0 : ptr<function, f32>,  rc_0 : vec2<f32>,  ppe_0 : vec2<f32>,  cLoc_0 : vec2<i32>,  texLayer_0 : i32,  curve_tex_0 : texture_2d_array<f32>) -> bool
{
    var _S32 : vec4<i32> = vec4<i32>(cLoc_0, texLayer_0, i32(0));
    var tex0_0 : vec4<f32> = (textureLoad((curve_tex_0), ((_S32)).xy, i32(((_S32)).z), ((_S32)).w));
    var _S33 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(cLoc_0, i32(1)), texLayer_0, i32(0));
    var p12_1 : vec4<f32> = vec4<f32>(tex0_0.xy, tex0_0.zw) - vec4<f32>(rc_0, rc_0);
    var p3_1 : vec2<f32> = (textureLoad((curve_tex_0), ((_S33)).xy, i32(((_S33)).z), ((_S33)).w)).xy - rc_0;
    var _S34 : f32 = ppe_0.x;
    if((max(max(p12_1.x, p12_1.z), p3_1.x) * _S34) < -0.5f)
    {
        return false;
    }
    var code_0 : u32 = calcRootCode_0(p12_1.y, p12_1.w, p3_1.y);
    if(code_0 != u32(0))
    {
        var r_0 : vec2<f32> = solveHorizPoly_0(p12_1, p3_1) * vec2<f32>(_S34);
        if(((code_0 & (u32(1)))) != u32(0))
        {
            var _S35 : f32 = r_0.x;
            (*xcov_0) = (*xcov_0) + clamp(_S35 + 0.5f, 0.0f, 1.0f);
            (*xwgt_0) = max((*xwgt_0), clamp(1.0f - abs(_S35) * 2.0f, 0.0f, 1.0f));
        }
        if(code_0 > u32(1))
        {
            var _S36 : f32 = r_0.y;
            (*xcov_0) = (*xcov_0) - clamp(_S36 + 0.5f, 0.0f, 1.0f);
            (*xwgt_0) = max((*xwgt_0), clamp(1.0f - abs(_S36) * 2.0f, 0.0f, 1.0f));
        }
    }
    return true;
}

fn solveVertPoly_0( p12_2 : vec4<f32>,  p3_2 : vec2<f32>) -> vec2<f32>
{
    var _S37 : vec2<f32> = p12_2.xy;
    var _S38 : vec2<f32> = p12_2.zw;
    var a_1 : vec2<f32> = _S37 - _S38 * vec2<f32>(2.0f) + p3_2;
    var b_2 : vec2<f32> = _S37 - _S38;
    var _S39 : f32 = a_1.x;
    var t1_1 : f32;
    var t2_1 : f32;
    if((abs(_S39)) < 0.0000152587890625f)
    {
        var _S40 : f32 = b_2.x;
        if((abs(_S40)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p12_2.x * 0.5f / _S40;
        }
        t2_1 = t1_1;
    }
    else
    {
        var _S41 : f32 = b_2.x;
        var _S42 : f32 = p12_2.x;
        var _S43 : f32 = _S39 * _S42;
        var sq_1 : f32 = snapNearTangentSqrt_0(_S41 * _S41 - _S43, _S41, _S43);
        if(_S41 >= 0.0f)
        {
            var q_2 : f32 = _S41 + sq_1;
            var _S44 : f32 = q_2 / _S39;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S42 / q_2;
            }
            t2_1 = _S44;
        }
        else
        {
            var q_3 : f32 = _S41 - sq_1;
            var _S45 : f32 = q_3 / _S39;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = _S42 / q_3;
            }
            var _S46 : f32 = t1_1;
            t1_1 = _S45;
            t2_1 = _S46;
        }
    }
    var _S47 : f32 = a_1.y;
    var _S48 : f32 = b_2.y * 2.0f;
    var _S49 : f32 = p12_2.y;
    return vec2<f32>((_S47 * t1_1 - _S48) * t1_1 + _S49, (_S47 * t2_1 - _S48) * t2_1 + _S49);
}

fn accumulateVertContribution_0( ycov_0 : ptr<function, f32>,  ywgt_0 : ptr<function, f32>,  rc_1 : vec2<f32>,  ppe_1 : vec2<f32>,  cLoc_1 : vec2<i32>,  texLayer_1 : i32,  curve_tex_1 : texture_2d_array<f32>) -> bool
{
    var _S50 : vec4<i32> = vec4<i32>(cLoc_1, texLayer_1, i32(0));
    var tex0_1 : vec4<f32> = (textureLoad((curve_tex_1), ((_S50)).xy, i32(((_S50)).z), ((_S50)).w));
    var _S51 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(cLoc_1, i32(1)), texLayer_1, i32(0));
    var p12_3 : vec4<f32> = vec4<f32>(tex0_1.xy, tex0_1.zw) - vec4<f32>(rc_1, rc_1);
    var p3_3 : vec2<f32> = (textureLoad((curve_tex_1), ((_S51)).xy, i32(((_S51)).z), ((_S51)).w)).xy - rc_1;
    var _S52 : f32 = ppe_1.y;
    if((max(max(p12_3.y, p12_3.w), p3_3.y) * _S52) < -0.5f)
    {
        return false;
    }
    var code_1 : u32 = calcRootCode_0(p12_3.x, p12_3.z, p3_3.x);
    if(code_1 != u32(0))
    {
        var r_1 : vec2<f32> = solveVertPoly_0(p12_3, p3_3) * vec2<f32>(_S52);
        if(((code_1 & (u32(1)))) != u32(0))
        {
            var _S53 : f32 = r_1.x;
            (*ycov_0) = (*ycov_0) - clamp(_S53 + 0.5f, 0.0f, 1.0f);
            (*ywgt_0) = max((*ywgt_0), clamp(1.0f - abs(_S53) * 2.0f, 0.0f, 1.0f));
        }
        if(code_1 > u32(1))
        {
            var _S54 : f32 = r_1.y;
            (*ycov_0) = (*ycov_0) + clamp(_S54 + 0.5f, 0.0f, 1.0f);
            (*ywgt_0) = max((*ywgt_0), clamp(1.0f - abs(_S54) * 2.0f, 0.0f, 1.0f));
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
    var _S55 : f32 = max(coverage_exponent_1, 0.0000152587890625f);
    var _S56 : f32;
    if((abs(_S55 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S56 = clamped_0;
    }
    else
    {
        _S56 = pow(clamped_0, _S55);
    }
    return _S56;
}

fn evalGlyphCoverage_0( rc_2 : vec2<f32>,  epp_0 : vec2<f32>,  ppe_2 : vec2<f32>,  gLoc_0 : vec2<i32>,  bandMax_1 : vec2<i32>,  banding_1 : vec4<f32>,  texLayer_2 : i32,  curve_tex_2 : texture_2d_array<f32>,  band_tex_0 : texture_2d_array<u32>,  coverage_exponent_2 : f32) -> f32
{
    var _S57 : bool;
    var i_0 : i32;
    var _S58 : i32 = bandMax_1.y;
    var hSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_2.y, epp_0.y, banding_1.y, banding_1.w, _S58);
    var vSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_2.x, epp_0.x, banding_1.x, banding_1.z, bandMax_1.x);
    var xcov_1 : f32 = 0.0f;
    var xwgt_1 : f32 = 0.0f;
    var _S59 : bool = (hSpan_0.first_0) != (hSpan_0.last_0);
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
        var _S60 : vec4<i32> = vec4<i32>(calcBandLoc_0(gLoc_0, u32(band_1)), texLayer_2, i32(0));
        var hbd_0 : vec2<u32> = (textureLoad((band_tex_0), ((_S60)).xy, i32(((_S60)).z), ((_S60)).w).xy).xy;
        var _S61 : vec2<i32> = calcBandLoc_0(gLoc_0, hbd_0.y);
        var _S62 : i32 = i32(hbd_0.x);
        i_0 = i32(0);
        for(;;)
        {
            if(i_0 < _S62)
            {
            }
            else
            {
                break;
            }
            var _S63 : vec4<i32> = vec4<i32>(calcBandLoc_0(_S61, u32(i_0)), texLayer_2, i32(0));
            var ref_4 : vec2<u32> = (textureLoad((band_tex_0), ((_S63)).xy, i32(((_S63)).z), ((_S63)).w).xy).xy;
            if(_S59)
            {
                _S57 = !isCoverageBandSpanOwner_0(ref_4, band_1, hSpan_0.first_0);
            }
            else
            {
                _S57 = false;
            }
            if(_S57)
            {
                i_0 = i_0 + i32(1);
                continue;
            }
            var _S64 : bool = accumulateHorizContribution_0(&(xcov_1), &(xwgt_1), rc_2, ppe_2, decodeBandCurveLoc_0(ref_4), texLayer_2, curve_tex_2);
            if(!_S64)
            {
                break;
            }
            i_0 = i_0 + i32(1);
        }
        band_1 = band_1 + i32(1);
    }
    var ycov_1 : f32 = 0.0f;
    var ywgt_1 : f32 = 0.0f;
    var _S65 : bool = (vSpan_0.first_0) != (vSpan_0.last_0);
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
        var _S66 : vec4<i32> = vec4<i32>(calcBandLoc_0(gLoc_0, u32(_S58 + i32(1) + band_1)), texLayer_2, i32(0));
        var vbd_0 : vec2<u32> = (textureLoad((band_tex_0), ((_S66)).xy, i32(((_S66)).z), ((_S66)).w).xy).xy;
        var _S67 : vec2<i32> = calcBandLoc_0(gLoc_0, vbd_0.y);
        var _S68 : i32 = i32(vbd_0.x);
        i_0 = i32(0);
        for(;;)
        {
            if(i_0 < _S68)
            {
            }
            else
            {
                break;
            }
            var _S69 : vec4<i32> = vec4<i32>(calcBandLoc_0(_S67, u32(i_0)), texLayer_2, i32(0));
            var ref_5 : vec2<u32> = (textureLoad((band_tex_0), ((_S69)).xy, i32(((_S69)).z), ((_S69)).w).xy).xy;
            if(_S65)
            {
                _S57 = !isCoverageBandSpanOwner_0(ref_5, band_1, vSpan_0.first_0);
            }
            else
            {
                _S57 = false;
            }
            if(_S57)
            {
                i_0 = i_0 + i32(1);
                continue;
            }
            var _S70 : bool = accumulateVertContribution_0(&(ycov_1), &(ywgt_1), rc_2, ppe_2, decodeBandCurveLoc_0(ref_5), texLayer_2, curve_tex_2);
            if(!_S70)
            {
                break;
            }
            i_0 = i_0 + i32(1);
        }
        band_1 = band_1 + i32(1);
    }
    return applyCoverageTransfer_0(max(applyFillRule_0((xcov_1 * xwgt_1 + ycov_1 * ywgt_1) / max(xwgt_1 + ywgt_1, 0.0000152587890625f), i32(0)), min(applyFillRule_0(xcov_1, i32(0)), applyFillRule_0(ycov_1, i32(0)))), coverage_exponent_2);
}

fn srgbDecode_0( c_0 : f32) -> f32
{
    var _S71 : f32;
    if(c_0 <= 0.04044999927282333f)
    {
        _S71 = c_0 / 12.92000007629394531f;
    }
    else
    {
        _S71 = pow((c_0 + 0.05499999970197678f) / 1.0549999475479126f, 2.40000009536743164f);
    }
    return _S71;
}

fn srgbToLinear_0( color_1 : vec3<f32>) -> vec3<f32>
{
    return vec3<f32>(srgbDecode_0(color_1.x), srgbDecode_0(color_1.y), srgbDecode_0(color_1.z));
}

fn snailTextSamplePremulLinearWithFootprint_0( words_per_glyph_3 : i32,  glyph_count_1 : i32,  layer_base_1 : i32,  coverage_exponent_3 : f32,  curve_tex_3 : texture_2d_array<f32>,  band_tex_1 : texture_2d_array<u32>,  scene_pos_1 : vec2<f32>,  scene_dx_0 : vec2<f32>,  scene_dy_0 : vec2<f32>) -> vec4<f32>
{
    var paint_0 : vec4<f32> = vec4<f32>(0.0f);
    var i_1 : i32 = i32(0);
    for(;;)
    {
        if(i_1 < glyph_count_1)
        {
        }
        else
        {
            break;
        }
        var _S72 : SnailTextSampleRecord_0 = snailTextSampleRecord_0(words_per_glyph_3, i_1);
        if((abs(_S72.xform_0.x * _S72.xform_0.w - _S72.xform_0.y * _S72.xform_0.z)) < 1.00000001335143196e-10f)
        {
            i_1 = i_1 + i32(1);
            continue;
        }
        var rc_3 : vec2<f32> = snailTextSampleLocalCoord_0(scene_pos_1, _S72.xform_0, _S72.origin_0);
        var epp_1 : vec2<f32> = abs(snailTextSampleLocalVector_0(scene_dx_0, _S72.xform_0)) + abs(snailTextSampleLocalVector_0(scene_dy_0, _S72.xform_0));
        var em_aa_0 : vec2<f32> = max(epp_1 * vec2<f32>(2.0f), vec2<f32>(0.00100000004749745f));
        var _S73 : f32 = rc_3.x;
        var _S74 : f32 = em_aa_0.x;
        var _S75 : bool;
        if(_S73 < (_S72.rect_0.x - _S74))
        {
            _S75 = true;
        }
        else
        {
            _S75 = _S73 > (_S72.rect_0.z + _S74);
        }
        var _S76 : bool;
        if(_S75)
        {
            _S76 = true;
        }
        else
        {
            _S76 = (rc_3.y) < (_S72.rect_0.y - em_aa_0.y);
        }
        var _S77 : bool;
        if(_S76)
        {
            _S77 = true;
        }
        else
        {
            _S77 = (rc_3.y) > (_S72.rect_0.w + em_aa_0.y);
        }
        if(_S77)
        {
            i_1 = i_1 + i32(1);
            continue;
        }
        var gz_0 : u32 = _S72.glyph_0.x;
        var gw_0 : u32 = _S72.glyph_0.y;
        var layer_byte_0 : i32 = i32((((gw_0 >> (u32(24)))) & (u32(255))));
        if(layer_byte_0 == i32(255))
        {
            i_1 = i_1 + i32(1);
            continue;
        }
        var alpha_0 : f32 = clamp(evalGlyphCoverage_0(rc_3, epp_1, vec2<f32>(1.0f / max(epp_1.x, 0.0000152587890625f), 1.0f / max(epp_1.y, 0.0000152587890625f)), vec2<i32>(i32((gz_0 & (u32(65535)))), i32((gz_0 >> (u32(16))))), vec2<i32>(i32((((gw_0 >> (u32(16)))) & (u32(255)))), i32((gw_0 & (u32(65535))))), _S72.banding_0, layer_base_1 + layer_byte_0, curve_tex_3, band_tex_1, coverage_exponent_3) * _S72.color_0.w * _S72.tint_0.w, 0.0f, 1.0f);
        if(alpha_0 <= 0.00392156885936856f)
        {
            i_1 = i_1 + i32(1);
            continue;
        }
        var _S78 : f32 = 1.0f - alpha_0;
        var _S79 : vec3<f32> = srgbToLinear_0(_S72.color_0.xyz) * srgbToLinear_0(_S72.tint_0.xyz) * vec3<f32>(alpha_0) + paint_0.xyz * vec3<f32>(_S78);
        paint_0.x = _S79.x;
        paint_0.y = _S79.y;
        paint_0.z = _S79.z;
        paint_0[i32(3)] = alpha_0 + paint_0.w * _S78;
        i_1 = i_1 + i32(1);
    }
    return paint_0;
}

fn snailTextSamplePremulLinear_0( words_per_glyph_4 : i32,  glyph_count_2 : i32,  layer_base_2 : i32,  coverage_exponent_4 : f32,  curve_tex_4 : texture_2d_array<f32>,  band_tex_2 : texture_2d_array<u32>,  scene_pos_2 : vec2<f32>) -> vec4<f32>
{
    return snailTextSamplePremulLinearWithFootprint_0(words_per_glyph_4, glyph_count_2, layer_base_2, coverage_exponent_4, curve_tex_4, band_tex_2, scene_pos_2, dpdx(scene_pos_2), dpdy(scene_pos_2));
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) scene_pos_3 : vec2<f32>,
};

@fragment
fn fragmentMain( _S80 : pixelInput_0, @builtin(position) position_0 : vec4<f32>) -> pixelOutput_0
{
    var _S81 : pixelOutput_0 = pixelOutput_0( snailTextSamplePremulLinear_0(pc_0.words_per_glyph_0, pc_0.glyph_count_0, pc_0.layer_base_0, pc_0.coverage_exponent_0, u_curve_tex_0, u_band_tex_0, _S80.scene_pos_3) );
    return _S81;
}


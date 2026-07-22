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

@binding(3) @group(0) var u_image_tex_0 : texture_2d_array<f32>;

@binding(3) @group(1) var u_image_sampler_0 : sampler;

struct PathPaintSample_0
{
     color_0 : vec4<f32>,
     gradient_0 : f32,
};

fn PathPaintSample_x24init_0( color_1 : vec4<f32>,  gradient_1 : f32) -> PathPaintSample_0
{
    var _S1 : PathPaintSample_0;
    _S1.color_0 = color_1;
    _S1.gradient_0 = gradient_1;
    return _S1;
}

fn offsetLayerLoc_0( layer_tex_0 : texture_2d<f32>,  base_0 : vec2<i32>,  offset_0 : i32) -> vec2<i32>
{
    var uw_0 : u32;
    var uh_0 : u32;
    {var dim = textureDimensions((layer_tex_0));((uw_0)) = dim.x;((uh_0)) = dim.y;};
    var width_0 : i32 = i32(uw_0);
    var texel_0 : i32 = base_0.y * width_0 + base_0.x + offset_0;
    var _S2 : i32 = texel_0 % width_0;
    var _S3 : i32 = texel_0 / width_0;
    return vec2<i32>(_S2, _S3);
}

struct CoverageBandSpan_0
{
     first_0 : i32,
     last_0 : i32,
};

fn CoverageBandSpan_x24init_0( first_1 : i32,  last_1 : i32) -> CoverageBandSpan_0
{
    var _S4 : CoverageBandSpan_0;
    _S4.first_0 = first_1;
    _S4.last_0 = last_1;
    return _S4;
}

fn computeCoverageBandSpan_0( coord_0 : f32,  eppAxis_0 : f32,  bandScale_0 : f32,  bandOffset_0 : f32,  bandMax_0 : i32) -> CoverageBandSpan_0
{
    var center_0 : f32 = coord_0 * bandScale_0 + bandOffset_0;
    var _S5 : f32 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    var first_2 : i32 = clamp(i32(center_0 - _S5), i32(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(i32(center_0 + _S5), i32(0), bandMax_0)));
}

fn calcBandLoc_0( glyphLoc_0 : vec2<i32>,  offset_1 : u32) -> vec2<i32>
{
    var _S6 : i32 = glyphLoc_0.x + i32(offset_1);
    var loc_0 : vec2<i32> = vec2<i32>(_S6, glyphLoc_0.y);
    loc_0[i32(1)] = loc_0[i32(1)] + ((_S6 >> (u32(12))));
    loc_0[i32(0)] = ((loc_0[i32(0)]) & (i32(4095)));
    return loc_0;
}

fn decodeBandCurveFirstMemberCommon_0( ref_0 : vec2<u32>) -> i32
{
    return i32(((ref_0.x) >> (u32(12))));
}

fn decodeBandCurveLocCommon_0( ref_1 : vec2<u32>) -> vec2<i32>
{
    return vec2<i32>(i32(((ref_1.x) & (u32(4095)))), i32(((ref_1.y) & (u32(16383)))));
}

fn decodeBandCurveKindCommon_0( ref_2 : vec2<u32>) -> i32
{
    return i32(((ref_2.y) >> (u32(14))));
}

fn offsetCurveLoc_0( base_1 : vec2<i32>,  offset_2 : i32) -> vec2<i32>
{
    var _S7 : i32 = base_1.x + offset_2;
    var loc_1 : vec2<i32> = vec2<i32>(_S7, base_1.y);
    loc_1[i32(1)] = loc_1[i32(1)] + ((_S7 >> (u32(12))));
    loc_1[i32(0)] = ((loc_1[i32(0)]) & (i32(4095)));
    return loc_1;
}

struct SegmentData_0
{
     kind_0 : i32,
     p0_0 : vec2<f32>,
     p1_0 : vec2<f32>,
     p2_0 : vec2<f32>,
     p3_0 : vec2<f32>,
     weights_0 : vec3<f32>,
};

fn fetchSegment_0( curve_tex_0 : texture_2d_array<f32>,  loc_2 : vec2<i32>,  layer_0 : i32,  kind_1 : i32) -> SegmentData_0
{
    var _S8 : vec4<i32> = vec4<i32>(loc_2, layer_0, i32(0));
    var tex0_0 : vec4<f32> = (textureLoad((curve_tex_0), ((_S8)).xy, i32(((_S8)).z), ((_S8)).w));
    var _S9 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(loc_2, i32(1)), layer_0, i32(0));
    var tex1_0 : vec4<f32> = (textureLoad((curve_tex_0), ((_S9)).xy, i32(((_S9)).z), ((_S9)).w));
    var seg_0 : SegmentData_0;
    seg_0.kind_0 = kind_1;
    seg_0.p0_0 = tex0_0.xy;
    seg_0.p1_0 = tex0_0.zw;
    seg_0.p2_0 = tex1_0.xy;
    seg_0.p3_0 = tex1_0.zw;
    if(kind_1 == i32(1))
    {
        var _S10 : vec4<i32> = vec4<i32>(offsetCurveLoc_0(loc_2, i32(2)), layer_0, i32(0));
        var tex2_0 : vec4<f32> = (textureLoad((curve_tex_0), ((_S10)).xy, i32(((_S10)).z), ((_S10)).w));
        seg_0.weights_0 = vec3<f32>(tex2_0.w, tex2_0.x, tex2_0.y);
    }
    else
    {
        seg_0.weights_0 = vec3<f32>(1.0f);
    }
    return seg_0;
}

fn segmentMaxX_0( seg_1 : SegmentData_0) -> f32
{
    if((seg_1.kind_0) == i32(3))
    {
        return max(seg_1.p0_0.x, seg_1.p2_0.x);
    }
    if((seg_1.kind_0) == i32(2))
    {
        return max(max(seg_1.p0_0.x, seg_1.p1_0.x), max(seg_1.p2_0.x, seg_1.p3_0.x));
    }
    return max(max(seg_1.p0_0.x, seg_1.p1_0.x), seg_1.p2_0.x);
}

fn segmentMaxY_0( seg_2 : SegmentData_0) -> f32
{
    if((seg_2.kind_0) == i32(3))
    {
        return max(seg_2.p0_0.y, seg_2.p2_0.y);
    }
    if((seg_2.kind_0) == i32(2))
    {
        return max(max(seg_2.p0_0.y, seg_2.p1_0.y), max(seg_2.p2_0.y, seg_2.p3_0.y));
    }
    return max(max(seg_2.p0_0.y, seg_2.p1_0.y), seg_2.p2_0.y);
}

fn rootCodeCoord_0( v_0 : f32) -> f32
{
    var _S11 : f32;
    if((abs(v_0)) <= 0.0000152587890625f)
    {
        _S11 = 0.0f;
    }
    else
    {
        _S11 = v_0;
    }
    return _S11;
}

fn calcRootCode_0( y1_0 : f32,  y2_0 : f32,  y3_0 : f32) -> u32
{
    return (((u32(11892) >> ((((((((bitcast<u32>((rootCodeCoord_0(y3_0)))) >> (u32(29)))) & (u32(4)))) | ((((((((((bitcast<u32>((rootCodeCoord_0(y2_0)))) >> (u32(30)))) & (u32(2)))) | ((((((bitcast<u32>((rootCodeCoord_0(y1_0)))) >> (u32(31)))) & (u32(4294967293))))))) & (u32(4294967291)))))))))) & (u32(257)));
}

fn snapNearTangentSqrt_0( disc_0 : f32,  b_0 : f32,  ac_0 : f32) -> f32
{
    var _S12 : f32;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S12 = 0.0f;
    }
    else
    {
        _S12 = sqrt(disc_0);
    }
    return _S12;
}

fn solveQuadraticHorizDistances_0( p0x_0 : f32,  p0y_0 : f32,  p1x_0 : f32,  p1y_0 : f32,  p2x_0 : f32,  p2y_0 : f32,  ppeX_0 : f32) -> vec2<f32>
{
    var ax_0 : f32 = p0x_0 - p1x_0 * 2.0f + p2x_0;
    var ay_0 : f32 = p0y_0 - p1y_0 * 2.0f + p2y_0;
    var bx_0 : f32 = p0x_0 - p1x_0;
    var by_0 : f32 = p0y_0 - p1y_0;
    var t1_0 : f32;
    var t2_0 : f32;
    if((abs(ay_0)) < 0.0000152587890625f)
    {
        if((abs(by_0)) < 0.0000152587890625f)
        {
            t1_0 = 0.0f;
        }
        else
        {
            t1_0 = p0y_0 * 0.5f / by_0;
        }
        t2_0 = t1_0;
    }
    else
    {
        var _S13 : f32 = ay_0 * p0y_0;
        var sq_0 : f32 = snapNearTangentSqrt_0(by_0 * by_0 - _S13, by_0, _S13);
        if(by_0 >= 0.0f)
        {
            var q_0 : f32 = by_0 + sq_0;
            var _S14 : f32 = q_0 / ay_0;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = p0y_0 / q_0;
            }
            t2_0 = _S14;
        }
        else
        {
            var q_1 : f32 = by_0 - sq_0;
            var _S15 : f32 = q_1 / ay_0;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = p0y_0 / q_1;
            }
            var _S16 : f32 = t1_0;
            t1_0 = _S15;
            t2_0 = _S16;
        }
    }
    var _S17 : f32 = bx_0 * 2.0f;
    return vec2<f32>(((ax_0 * t1_0 - _S17) * t1_0 + p0x_0) * ppeX_0, ((ax_0 * t2_0 - _S17) * t2_0 + p0x_0) * ppeX_0);
}

fn solveQuadraticVertDistances_0( p0x_1 : f32,  p0y_1 : f32,  p1x_1 : f32,  p1y_1 : f32,  p2x_1 : f32,  p2y_1 : f32,  ppeY_0 : f32) -> vec2<f32>
{
    var ax_1 : f32 = p0x_1 - p1x_1 * 2.0f + p2x_1;
    var ay_1 : f32 = p0y_1 - p1y_1 * 2.0f + p2y_1;
    var bx_1 : f32 = p0x_1 - p1x_1;
    var by_1 : f32 = p0y_1 - p1y_1;
    var t1_1 : f32;
    var t2_1 : f32;
    if((abs(ax_1)) < 0.0000152587890625f)
    {
        if((abs(bx_1)) < 0.0000152587890625f)
        {
            t1_1 = 0.0f;
        }
        else
        {
            t1_1 = p0x_1 * 0.5f / bx_1;
        }
        t2_1 = t1_1;
    }
    else
    {
        var _S18 : f32 = ax_1 * p0x_1;
        var sq_1 : f32 = snapNearTangentSqrt_0(bx_1 * bx_1 - _S18, bx_1, _S18);
        if(bx_1 >= 0.0f)
        {
            var q_2 : f32 = bx_1 + sq_1;
            var _S19 : f32 = q_2 / ax_1;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = p0x_1 / q_2;
            }
            t2_1 = _S19;
        }
        else
        {
            var q_3 : f32 = bx_1 - sq_1;
            var _S20 : f32 = q_3 / ax_1;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = p0x_1 / q_3;
            }
            var _S21 : f32 = t1_1;
            t1_1 = _S20;
            t2_1 = _S21;
        }
    }
    var _S22 : f32 = by_1 * 2.0f;
    return vec2<f32>(((ay_1 * t1_1 - _S22) * t1_1 + p0y_1) * ppeY_0, ((ay_1 * t2_1 - _S22) * t2_1 + p0y_1) * ppeY_0);
}

fn appendCoverageContribution_0( cov_0 : ptr<function, f32>,  wgt_0 : ptr<function, f32>,  distance_0 : f32,  sign_0 : f32)
{
    (*cov_0) = (*cov_0) + sign_0 * clamp(distance_0 + 0.5f, 0.0f, 1.0f);
    (*wgt_0) = max((*wgt_0), clamp(1.0f - abs(distance_0) * 2.0f, 0.0f, 1.0f));
    return;
}

fn appendCoverageContribution_1( cov_1 : ptr<function, f32>,  wgt_1 : ptr<function, f32>,  distance_1 : f32,  sign_1 : f32)
{
    (*cov_1) = (*cov_1) + sign_1 * clamp(distance_1 + 0.5f, 0.0f, 1.0f);
    (*wgt_1) = max((*wgt_1), clamp(1.0f - abs(distance_1) * 2.0f, 0.0f, 1.0f));
    return;
}

fn accumulateLineCoverage_0( cov_2 : ptr<function, f32>,  wgt_2 : ptr<function, f32>,  p0x_2 : f32,  p0y_2 : f32,  p2x_2 : f32,  p2y_2 : f32,  ppe_0 : f32,  horizontal_0 : bool)
{
    var rootAxis0_0 : f32;
    if(horizontal_0)
    {
        rootAxis0_0 = p0y_2;
    }
    else
    {
        rootAxis0_0 = p0x_2;
    }
    var rootAxis2_0 : f32;
    if(horizontal_0)
    {
        rootAxis2_0 = p2y_2;
    }
    else
    {
        rootAxis2_0 = p2x_2;
    }
    if(((rootCodeCoord_0(rootAxis0_0)) < 0.0f) == ((rootCodeCoord_0(rootAxis2_0)) < 0.0f))
    {
        return;
    }
    var denom_0 : f32 = rootAxis2_0 - rootAxis0_0;
    if((abs(denom_0)) < 1.00000001335143196e-10f)
    {
        return;
    }
    var t_0 : f32 = clamp(- rootAxis0_0 / denom_0, 0.0f, 1.0f);
    var derivativeAxis_0 : f32;
    if(horizontal_0)
    {
        derivativeAxis_0 = p2y_2 - p0y_2;
    }
    else
    {
        derivativeAxis_0 = p0x_2 - p2x_2;
    }
    if((abs(derivativeAxis_0)) <= 0.00000999999974738f)
    {
        return;
    }
    if(horizontal_0)
    {
        rootAxis0_0 = p0x_2 + (p2x_2 - p0x_2) * t_0;
    }
    else
    {
        rootAxis0_0 = p0y_2 + (p2y_2 - p0y_2) * t_0;
    }
    var distance_2 : f32 = rootAxis0_0 * ppe_0;
    if(derivativeAxis_0 > 0.0f)
    {
        rootAxis0_0 = 1.0f;
    }
    else
    {
        rootAxis0_0 = -1.0f;
    }
    appendCoverageContribution_1(&((*cov_2)), &((*wgt_2)), distance_2, rootAxis0_0);
    return;
}

fn rootHullCanCross4_0( p0_1 : f32,  p1_1 : f32,  p2_1 : f32,  p3_1 : f32,  sampleRoot_0 : f32) -> bool
{
    var _S23 : f32 = max(max(p0_1, p1_1), max(p2_1, p3_1));
    var _S24 : bool;
    if((min(min(p0_1, p1_1), min(p2_1, p3_1)) - sampleRoot_0) <= 0.0000152587890625f)
    {
        _S24 = (_S23 - sampleRoot_0) >= -0.0000152587890625f;
    }
    else
    {
        _S24 = false;
    }
    return _S24;
}

fn rootHullCanCross3_0( p0_2 : f32,  p1_2 : f32,  p2_2 : f32,  sampleRoot_1 : f32) -> bool
{
    var _S25 : f32 = max(max(p0_2, p1_2), p2_2);
    var _S26 : bool;
    if((min(min(p0_2, p1_2), p2_2) - sampleRoot_1) <= 0.0000152587890625f)
    {
        _S26 = (_S25 - sampleRoot_1) >= -0.0000152587890625f;
    }
    else
    {
        _S26 = false;
    }
    return _S26;
}

fn segmentRootHullCanCross_0( seg_3 : SegmentData_0,  sampleRc_0 : vec2<f32>,  horizontal_1 : bool) -> bool
{
    var sampleRoot_2 : f32;
    if(horizontal_1)
    {
        sampleRoot_2 = sampleRc_0.y;
    }
    else
    {
        sampleRoot_2 = sampleRc_0.x;
    }
    var _S27 : f32;
    var _S28 : f32;
    var _S29 : f32;
    if((seg_3.kind_0) == i32(2))
    {
        if(horizontal_1)
        {
            _S27 = seg_3.p0_0.y;
        }
        else
        {
            _S27 = seg_3.p0_0.x;
        }
        if(horizontal_1)
        {
            _S28 = seg_3.p1_0.y;
        }
        else
        {
            _S28 = seg_3.p1_0.x;
        }
        if(horizontal_1)
        {
            _S29 = seg_3.p2_0.y;
        }
        else
        {
            _S29 = seg_3.p2_0.x;
        }
        var _S30 : f32;
        if(horizontal_1)
        {
            _S30 = seg_3.p3_0.y;
        }
        else
        {
            _S30 = seg_3.p3_0.x;
        }
        return rootHullCanCross4_0(_S27, _S28, _S29, _S30, sampleRoot_2);
    }
    if(horizontal_1)
    {
        _S27 = seg_3.p0_0.y;
    }
    else
    {
        _S27 = seg_3.p0_0.x;
    }
    if(horizontal_1)
    {
        _S28 = seg_3.p1_0.y;
    }
    else
    {
        _S28 = seg_3.p1_0.x;
    }
    if(horizontal_1)
    {
        _S29 = seg_3.p2_0.y;
    }
    else
    {
        _S29 = seg_3.p2_0.x;
    }
    return rootHullCanCross3_0(_S27, _S28, _S29, sampleRoot_2);
}

fn distToUnitInterval_0( t_1 : f32) -> f32
{
    return max(max(0.0f, - t_1), t_1 - 1.0f);
}

fn segmentEndRootDelta_0( seg_4 : SegmentData_0,  sampleRc_1 : vec2<f32>,  horizontal_2 : bool) -> f32
{
    var _S31 : f32;
    if((seg_4.kind_0) == i32(2))
    {
        if(horizontal_2)
        {
            _S31 = seg_4.p3_0.y - sampleRc_1.y;
        }
        else
        {
            _S31 = seg_4.p3_0.x - sampleRc_1.x;
        }
        return _S31;
    }
    if(horizontal_2)
    {
        _S31 = seg_4.p2_0.y - sampleRc_1.y;
    }
    else
    {
        _S31 = seg_4.p2_0.x - sampleRc_1.x;
    }
    return _S31;
}

fn accumulateConicRoot_0( cov_3 : ptr<function, f32>,  wgt_3 : ptr<function, f32>,  t_2 : f32,  endRootDelta_0 : f32,  sampleAlong_0 : f32,  ppe_1 : f32,  horizontal_3 : bool,  rootA_0 : f32,  rootB_0 : f32,  rootC_0 : f32,  alongA_0 : f32,  alongB_0 : f32,  alongC_0 : f32,  denA_0 : f32,  denB_0 : f32,  denC_0 : f32)
{
    var _S32 : f32 = max((denA_0 * t_2 + denB_0) * t_2 + denC_0, 0.0000152587890625f);
    var along_0 : f32 = ((alongA_0 * t_2 + alongB_0) * t_2 + alongC_0) / _S32;
    var derivAxis_0 : f32 = ((2.0f * rootA_0 * t_2 + rootB_0) * _S32 - ((rootA_0 * t_2 + rootB_0) * t_2 + rootC_0) * (2.0f * denA_0 * t_2 + denB_0)) / (_S32 * _S32);
    var derivAxis_1 : f32;
    if(!horizontal_3)
    {
        derivAxis_1 = - derivAxis_0;
    }
    else
    {
        derivAxis_1 = derivAxis_0;
    }
    if((abs(derivAxis_1)) <= 0.00000999999974738f)
    {
        return;
    }
    var dist_0 : f32 = (along_0 - sampleAlong_0) * ppe_1;
    if(derivAxis_1 > 0.0f)
    {
        derivAxis_1 = 1.0f;
    }
    else
    {
        derivAxis_1 = -1.0f;
    }
    appendCoverageContribution_1(&((*cov_3)), &((*wgt_3)), dist_0, derivAxis_1);
    return;
}

fn accumulateConicCoverage_0( cov_4 : ptr<function, f32>,  wgt_4 : ptr<function, f32>,  seg_5 : SegmentData_0,  sampleRc_2 : vec2<f32>,  ppe_2 : f32,  horizontal_4 : bool)
{
    if(!segmentRootHullCanCross_0(seg_5, sampleRc_2, horizontal_4))
    {
        return;
    }
    var sampleRoot_3 : f32;
    if(horizontal_4)
    {
        sampleRoot_3 = sampleRc_2.y;
    }
    else
    {
        sampleRoot_3 = sampleRc_2.x;
    }
    var sampleAlong_1 : f32;
    if(horizontal_4)
    {
        sampleAlong_1 = sampleRc_2.x;
    }
    else
    {
        sampleAlong_1 = sampleRc_2.y;
    }
    var p0Root_0 : f32;
    if(horizontal_4)
    {
        p0Root_0 = seg_5.p0_0.y;
    }
    else
    {
        p0Root_0 = seg_5.p0_0.x;
    }
    var p1Root_0 : f32;
    if(horizontal_4)
    {
        p1Root_0 = seg_5.p1_0.y;
    }
    else
    {
        p1Root_0 = seg_5.p1_0.x;
    }
    var p2Root_0 : f32;
    if(horizontal_4)
    {
        p2Root_0 = seg_5.p2_0.y;
    }
    else
    {
        p2Root_0 = seg_5.p2_0.x;
    }
    var p0Along_0 : f32;
    if(horizontal_4)
    {
        p0Along_0 = seg_5.p0_0.x;
    }
    else
    {
        p0Along_0 = seg_5.p0_0.y;
    }
    var p1Along_0 : f32;
    if(horizontal_4)
    {
        p1Along_0 = seg_5.p1_0.x;
    }
    else
    {
        p1Along_0 = seg_5.p1_0.y;
    }
    var p2Along_0 : f32;
    if(horizontal_4)
    {
        p2Along_0 = seg_5.p2_0.x;
    }
    else
    {
        p2Along_0 = seg_5.p2_0.y;
    }
    var _S33 : f32 = seg_5.weights_0.x;
    var c0_0 : f32 = _S33 * (p0Root_0 - sampleRoot_3);
    var _S34 : f32 = seg_5.weights_0.y;
    var c1_0 : f32 = _S34 * (p1Root_0 - sampleRoot_3);
    var _S35 : f32 = seg_5.weights_0.z;
    var c2_0 : f32 = _S35 * (p2Root_0 - sampleRoot_3);
    var code_0 : u32 = calcRootCode_0(c0_0, c1_0, c2_0);
    if(code_0 == u32(0))
    {
        return;
    }
    var want_0 : i32;
    if(code_0 == u32(257))
    {
        want_0 = i32(2);
    }
    else
    {
        want_0 = i32(1);
    }
    var quadA_0 : f32 = c0_0 - 2.0f * c1_0 + c2_0;
    var quadB_0 : f32 = 2.0f * (c1_0 - c0_0);
    var cand1_0 : f32;
    var cand0_0 : f32;
    var ncand_0 : i32;
    if((abs(quadA_0)) < 0.0000152587890625f)
    {
        if((abs(quadB_0)) >= 0.0000152587890625f)
        {
            var _S36 : f32 = - c0_0 / quadB_0;
            ncand_0 = i32(1);
            cand1_0 = _S36;
        }
        else
        {
            ncand_0 = i32(0);
            cand1_0 = 0.0f;
        }
        var _S37 : f32 = cand1_0;
        cand1_0 = 0.0f;
        cand0_0 = _S37;
    }
    else
    {
        var sqrtDisc_0 : f32 = sqrt(max(quadB_0 * quadB_0 - 4.0f * quadA_0 * c0_0, 0.0f));
        var inv2a_0 : f32 = 0.5f / quadA_0;
        var _S38 : f32 = - quadB_0;
        var _S39 : f32 = (_S38 - sqrtDisc_0) * inv2a_0;
        var _S40 : f32 = (_S38 + sqrtDisc_0) * inv2a_0;
        ncand_0 = i32(2);
        cand1_0 = _S40;
        cand0_0 = _S39;
    }
    if(ncand_0 == i32(0))
    {
        return;
    }
    var root0_0 : f32;
    var root1_0 : f32;
    var rootCount_0 : i32;
    if(want_0 == i32(1))
    {
        var _S41 : bool;
        if(ncand_0 == i32(2))
        {
            _S41 = (distToUnitInterval_0(cand1_0)) < (distToUnitInterval_0(cand0_0));
        }
        else
        {
            _S41 = false;
        }
        if(_S41)
        {
            root0_0 = cand1_0;
        }
        else
        {
            root0_0 = cand0_0;
        }
        root0_0 = clamp(root0_0, 0.0f, 1.0f);
        rootCount_0 = i32(1);
        root1_0 = 0.0f;
    }
    else
    {
        var _S42 : f32 = clamp(cand1_0, 0.0f, 1.0f);
        root0_0 = clamp(cand0_0, 0.0f, 1.0f);
        rootCount_0 = i32(2);
        root1_0 = _S42;
    }
    var _S43 : f32 = p0Root_0 * _S33;
    var rootA_1 : f32 = _S43 - 2.0f * p1Root_0 * _S34 + p2Root_0 * _S35;
    var rootB_1 : f32 = 2.0f * (p1Root_0 * _S34 - _S43);
    var _S44 : f32 = p0Along_0 * _S33;
    var alongA_1 : f32 = _S44 - 2.0f * p1Along_0 * _S34 + p2Along_0 * _S35;
    var alongB_1 : f32 = 2.0f * (p1Along_0 * _S34 - _S44);
    var denA_1 : f32 = _S33 - 2.0f * _S34 + _S35;
    var denB_1 : f32 = 2.0f * (_S34 - _S33);
    var endRootDelta_1 : f32 = segmentEndRootDelta_0(seg_5, sampleRc_2, horizontal_4);
    accumulateConicRoot_0(&((*cov_4)), &((*wgt_4)), root0_0, endRootDelta_1, sampleAlong_1, ppe_2, horizontal_4, rootA_1, rootB_1, _S43, alongA_1, alongB_1, _S44, denA_1, denB_1, _S33);
    if(rootCount_0 == i32(2))
    {
        accumulateConicRoot_0(&((*cov_4)), &((*wgt_4)), root1_0, endRootDelta_1, sampleAlong_1, ppe_2, horizontal_4, rootA_1, rootB_1, _S43, alongA_1, alongB_1, _S44, denA_1, denB_1, _S33);
    }
    return;
}

fn solveMonotonicCubicRoot_0( a_0 : f32,  b_1 : f32,  cVal_0 : f32,  d_0 : f32,  endDelta_0 : f32,  tOut_0 : ptr<function, f32>) -> bool
{
    (*tOut_0) = 0.0f;
    var _S45 : bool;
    if(d_0 < -0.0000152587890625f)
    {
        _S45 = endDelta_0 < -0.0000152587890625f;
    }
    else
    {
        _S45 = false;
    }
    if(_S45)
    {
        _S45 = true;
    }
    else
    {
        if(d_0 > 0.0000152587890625f)
        {
            _S45 = endDelta_0 > 0.0000152587890625f;
        }
        else
        {
            _S45 = false;
        }
    }
    if(_S45)
    {
        return false;
    }
    var _S46 : bool = endDelta_0 >= d_0;
    var t_3 : f32 = 0.5f;
    var lo_0 : f32 = 0.0f;
    var hi_0 : f32 = 1.0f;
    var i_0 : i32 = i32(0);
    for(;;)
    {
        if(i_0 < i32(16))
        {
        }
        else
        {
            break;
        }
        var f_0 : f32 = ((a_0 * t_3 + b_1) * t_3 + cVal_0) * t_3 + d_0;
        if(_S46)
        {
            _S45 = f_0 < 0.0f;
        }
        else
        {
            _S45 = false;
        }
        var _S47 : bool;
        if(_S45)
        {
            _S47 = true;
        }
        else
        {
            if(!_S46)
            {
                _S47 = f_0 > 0.0f;
            }
            else
            {
                _S47 = false;
            }
        }
        if(_S47)
        {
            lo_0 = t_3;
        }
        else
        {
            hi_0 = t_3;
        }
        var deriv_0 : f32 = (3.0f * a_0 * t_3 + 2.0f * b_1) * t_3 + cVal_0;
        var _S48 : f32 = (lo_0 + hi_0) * 0.5f;
        var next_0 : f32;
        if((abs(deriv_0)) >= 9.99999997475242708e-07f)
        {
            var newton_0 : f32 = t_3 - f_0 / deriv_0;
            var _S49 : bool;
            if(newton_0 > lo_0)
            {
                _S49 = newton_0 < hi_0;
            }
            else
            {
                _S49 = false;
            }
            if(_S49)
            {
                next_0 = newton_0;
            }
            else
            {
                next_0 = _S48;
            }
        }
        else
        {
            next_0 = _S48;
        }
        var _S50 : i32 = i_0 + i32(1);
        t_3 = next_0;
        i_0 = _S50;
    }
    (*tOut_0) = t_3;
    return true;
}

fn accumulateCubicCoverage_0( cov_5 : ptr<function, f32>,  wgt_5 : ptr<function, f32>,  seg_6 : SegmentData_0,  sampleRc_3 : vec2<f32>,  ppe_3 : f32,  horizontal_5 : bool)
{
    if(!segmentRootHullCanCross_0(seg_6, sampleRc_3, horizontal_5))
    {
        return;
    }
    var sampleRoot_4 : f32;
    if(horizontal_5)
    {
        sampleRoot_4 = sampleRc_3.y;
    }
    else
    {
        sampleRoot_4 = sampleRc_3.x;
    }
    var sampleAlong_2 : f32;
    if(horizontal_5)
    {
        sampleAlong_2 = sampleRc_3.x;
    }
    else
    {
        sampleAlong_2 = sampleRc_3.y;
    }
    var p0Root_1 : f32;
    if(horizontal_5)
    {
        p0Root_1 = seg_6.p0_0.y;
    }
    else
    {
        p0Root_1 = seg_6.p0_0.x;
    }
    var p1Root_1 : f32;
    if(horizontal_5)
    {
        p1Root_1 = seg_6.p1_0.y;
    }
    else
    {
        p1Root_1 = seg_6.p1_0.x;
    }
    var p2Root_1 : f32;
    if(horizontal_5)
    {
        p2Root_1 = seg_6.p2_0.y;
    }
    else
    {
        p2Root_1 = seg_6.p2_0.x;
    }
    var p3Root_0 : f32;
    if(horizontal_5)
    {
        p3Root_0 = seg_6.p3_0.y;
    }
    else
    {
        p3Root_0 = seg_6.p3_0.x;
    }
    var p0Along_1 : f32;
    if(horizontal_5)
    {
        p0Along_1 = seg_6.p0_0.x;
    }
    else
    {
        p0Along_1 = seg_6.p0_0.y;
    }
    var p1Along_1 : f32;
    if(horizontal_5)
    {
        p1Along_1 = seg_6.p1_0.x;
    }
    else
    {
        p1Along_1 = seg_6.p1_0.y;
    }
    var p2Along_1 : f32;
    if(horizontal_5)
    {
        p2Along_1 = seg_6.p2_0.x;
    }
    else
    {
        p2Along_1 = seg_6.p2_0.y;
    }
    var p3Along_0 : f32;
    if(horizontal_5)
    {
        p3Along_0 = seg_6.p3_0.x;
    }
    else
    {
        p3Along_0 = seg_6.p3_0.y;
    }
    var _S51 : f32 = 3.0f * p1Root_1;
    var _S52 : f32 = 3.0f * p2Root_1;
    var rootA_2 : f32 = - p0Root_1 + _S51 - _S52 + p3Root_0;
    var rootB_2 : f32 = 3.0f * p0Root_1 - 6.0f * p1Root_1 + _S52;
    var rootC_1 : f32 = -3.0f * p0Root_1 + _S51;
    var startDelta_0 : f32 = p0Root_1 - sampleRoot_4;
    var endDelta_1 : f32 = p3Root_0 - sampleRoot_4;
    if(((rootCodeCoord_0(startDelta_0)) < 0.0f) == ((rootCodeCoord_0(endDelta_1)) < 0.0f))
    {
        return;
    }
    var t_4 : f32 = 0.0f;
    if((abs(startDelta_0)) <= 0.0000152587890625f)
    {
        t_4 = 0.0f;
    }
    else
    {
        if((abs(endDelta_1)) <= 0.0000152587890625f)
        {
            t_4 = 1.0f;
        }
        else
        {
            var _S53 : bool = solveMonotonicCubicRoot_0(rootA_2, rootB_2, rootC_1, startDelta_0, endDelta_1, &(t_4));
            if(!_S53)
            {
                return;
            }
        }
    }
    var _S54 : f32 = 3.0f * p1Along_1;
    var _S55 : f32 = 3.0f * p2Along_1;
    var alongA_2 : f32 = - p0Along_1 + _S54 - _S55 + p3Along_0;
    var alongB_2 : f32 = 3.0f * p0Along_1 - 6.0f * p1Along_1 + _S55;
    var alongC_1 : f32 = -3.0f * p0Along_1 + _S54;
    var along_1 : f32;
    if(t_4 == 1.0f)
    {
        along_1 = p3Along_0;
    }
    else
    {
        along_1 = ((alongA_2 * t_4 + alongB_2) * t_4 + alongC_1) * t_4 + p0Along_1;
    }
    var derivAxis_2 : f32;
    if(horizontal_5)
    {
        derivAxis_2 = p3Root_0 - p0Root_1;
    }
    else
    {
        derivAxis_2 = p0Root_1 - p3Root_0;
    }
    var dist_1 : f32 = (along_1 - sampleAlong_2) * ppe_3;
    if(derivAxis_2 > 0.0f)
    {
        sampleRoot_4 = 1.0f;
    }
    else
    {
        sampleRoot_4 = -1.0f;
    }
    appendCoverageContribution_0(&((*cov_5)), &((*wgt_5)), dist_1, sampleRoot_4);
    return;
}

fn accumulateAxisCoverageSegment_0( cov_6 : ptr<function, f32>,  wgt_6 : ptr<function, f32>,  sampleRc_4 : vec2<f32>,  ppe_4 : f32,  seg_7 : SegmentData_0,  horizontal_6 : bool) -> bool
{
    var maxCoord_0 : f32;
    if(horizontal_6)
    {
        maxCoord_0 = segmentMaxX_0(seg_7) - sampleRc_4.x;
    }
    else
    {
        maxCoord_0 = segmentMaxY_0(seg_7) - sampleRc_4.y;
    }
    if((maxCoord_0 * ppe_4) < -0.5f)
    {
        return false;
    }
    if((seg_7.kind_0) == i32(0))
    {
        var _S56 : f32 = sampleRc_4.x;
        var p0x_3 : f32 = seg_7.p0_0.x - _S56;
        var _S57 : f32 = sampleRc_4.y;
        var p0y_3 : f32 = seg_7.p0_0.y - _S57;
        var p1x_2 : f32 = seg_7.p1_0.x - _S56;
        var p1y_2 : f32 = seg_7.p1_0.y - _S57;
        var p2x_3 : f32 = seg_7.p2_0.x - _S56;
        var p2y_3 : f32 = seg_7.p2_0.y - _S57;
        var code_1 : u32;
        if(horizontal_6)
        {
            code_1 = calcRootCode_0(p0y_3, p1y_2, p2y_3);
        }
        else
        {
            code_1 = calcRootCode_0(p0x_3, p1x_2, p2x_3);
        }
        if(code_1 == u32(0))
        {
            return true;
        }
        var roots_0 : vec2<f32>;
        if(horizontal_6)
        {
            roots_0 = solveQuadraticHorizDistances_0(p0x_3, p0y_3, p1x_2, p1y_2, p2x_3, p2y_3, ppe_4);
        }
        else
        {
            roots_0 = solveQuadraticVertDistances_0(p0x_3, p0y_3, p1x_2, p1y_2, p2x_3, p2y_3, ppe_4);
        }
        if(((code_1 & (u32(1)))) != u32(0))
        {
            var _S58 : f32 = roots_0.x;
            if(horizontal_6)
            {
                maxCoord_0 = 1.0f;
            }
            else
            {
                maxCoord_0 = -1.0f;
            }
            appendCoverageContribution_1(&((*cov_6)), &((*wgt_6)), _S58, maxCoord_0);
        }
        if(code_1 > u32(1))
        {
            var _S59 : f32 = roots_0.y;
            if(horizontal_6)
            {
                maxCoord_0 = -1.0f;
            }
            else
            {
                maxCoord_0 = 1.0f;
            }
            appendCoverageContribution_1(&((*cov_6)), &((*wgt_6)), _S59, maxCoord_0);
        }
        return true;
    }
    if((seg_7.kind_0) == i32(3))
    {
        var _S60 : f32 = sampleRc_4.x;
        var _S61 : f32 = sampleRc_4.y;
        accumulateLineCoverage_0(&((*cov_6)), &((*wgt_6)), seg_7.p0_0.x - _S60, seg_7.p0_0.y - _S61, seg_7.p2_0.x - _S60, seg_7.p2_0.y - _S61, ppe_4, horizontal_6);
        return true;
    }
    if((seg_7.kind_0) == i32(1))
    {
        accumulateConicCoverage_0(&((*cov_6)), &((*wgt_6)), seg_7, sampleRc_4, ppe_4, horizontal_6);
        return true;
    }
    accumulateCubicCoverage_0(&((*cov_6)), &((*wgt_6)), seg_7, sampleRc_4, ppe_4, horizontal_6);
    return true;
}

fn evalAxisCoverageBands_0( curve_tex_1 : texture_2d_array<f32>,  band_tex_0 : texture_2d_array<u32>,  sampleRc_5 : vec2<f32>,  ppe_5 : f32,  gLoc_0 : vec2<i32>,  headerBase_0 : i32,  firstBand_0 : i32,  lastBand_0 : i32,  layer_1 : i32,  horizontal_7 : bool) -> vec2<f32>
{
    var cov_7 : f32 = 0.0f;
    var wgt_7 : f32 = 0.0f;
    var _S62 : bool = firstBand_0 != lastBand_0;
    var band_0 : i32 = firstBand_0;
    for(;;)
    {
        if(band_0 <= lastBand_0)
        {
        }
        else
        {
            break;
        }
        var _S63 : vec4<i32> = vec4<i32>(calcBandLoc_0(gLoc_0, u32(headerBase_0 + band_0)), layer_1, i32(0));
        var bd_0 : vec2<u32> = (textureLoad((band_tex_0), ((_S63)).xy, i32(((_S63)).z), ((_S63)).w).xy).xy;
        var _S64 : vec2<i32> = calcBandLoc_0(gLoc_0, bd_0.y);
        var _S65 : i32 = i32(bd_0.x);
        var i_1 : i32 = i32(0);
        for(;;)
        {
            if(i_1 < _S65)
            {
            }
            else
            {
                break;
            }
            var _S66 : vec4<i32> = vec4<i32>(calcBandLoc_0(_S64, u32(i_1)), layer_1, i32(0));
            var ref_3 : vec2<u32> = (textureLoad((band_tex_0), ((_S66)).xy, i32(((_S66)).z), ((_S66)).w).xy).xy;
            if(_S62)
            {
                if(band_0 != (max(decodeBandCurveFirstMemberCommon_0(ref_3), firstBand_0)))
                {
                    i_1 = i_1 + i32(1);
                    continue;
                }
            }
            var _S67 : bool = accumulateAxisCoverageSegment_0(&(cov_7), &(wgt_7), sampleRc_5, ppe_5, fetchSegment_0(curve_tex_1, decodeBandCurveLocCommon_0(ref_3), layer_1, decodeBandCurveKindCommon_0(ref_3)), horizontal_7);
            if(!_S67)
            {
                break;
            }
            i_1 = i_1 + i32(1);
        }
        band_0 = band_0 + i32(1);
    }
    return vec2<f32>(cov_7, wgt_7);
}

fn applyFillRule_0( winding_0 : f32,  fill_rule_mode_0 : i32) -> f32
{
    if(fill_rule_mode_0 == i32(1))
    {
        return 1.0f - abs(fract(winding_0 * 0.5f) * 2.0f - 1.0f);
    }
    return abs(winding_0);
}

fn applyCoverageTransfer_0( cov_8 : f32,  coverage_exponent_1 : f32) -> f32
{
    var clamped_0 : f32 = clamp(cov_8, 0.0f, 1.0f);
    var _S68 : f32 = max(coverage_exponent_1, 0.0000152587890625f);
    var _S69 : f32;
    if((abs(_S68 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S69 = clamped_0;
    }
    else
    {
        _S69 = pow(clamped_0, _S68);
    }
    return _S69;
}

fn evalPathGlyphCoverage_0( curve_tex_2 : texture_2d_array<f32>,  band_tex_1 : texture_2d_array<u32>,  rc_0 : vec2<f32>,  epp_0 : vec2<f32>,  ppe_6 : vec2<f32>,  gLoc_1 : vec2<i32>,  bandMax_1 : vec2<i32>,  banding_0 : vec4<f32>,  texLayer_0 : i32,  fill_rule_0 : i32,  coverage_exponent_2 : f32) -> f32
{
    var _S70 : i32 = bandMax_1.y;
    var hSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_0.y, epp_0.y, banding_0.y, banding_0.w, _S70);
    var vSpan_0 : CoverageBandSpan_0 = computeCoverageBandSpan_0(rc_0.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    var horiz_0 : vec2<f32> = evalAxisCoverageBands_0(curve_tex_2, band_tex_1, rc_0, ppe_6.x, gLoc_1, i32(0), hSpan_0.first_0, hSpan_0.last_0, texLayer_0, true);
    var vert_0 : vec2<f32> = evalAxisCoverageBands_0(curve_tex_2, band_tex_1, rc_0, ppe_6.y, gLoc_1, _S70 + i32(1), vSpan_0.first_0, vSpan_0.last_0, texLayer_0, false);
    var _S71 : f32 = horiz_0.y;
    var _S72 : f32 = vert_0.y;
    var _S73 : f32 = horiz_0.x;
    var _S74 : f32 = vert_0.x;
    return applyCoverageTransfer_0(max(applyFillRule_0((_S73 * _S71 + _S74 * _S72) / max(_S71 + _S72, 0.0000152587890625f), fill_rule_0), min(applyFillRule_0(_S73, fill_rule_0), applyFillRule_0(_S74, fill_rule_0))), coverage_exponent_2);
}

fn wrapPaintT_0( t_5 : f32,  extendMode_0 : f32) -> f32
{
    var mode_0 : i32 = i32(extendMode_0 + 0.5f);
    if(mode_0 == i32(1))
    {
        return fract(t_5);
    }
    if(mode_0 == i32(2))
    {
        var reflected_0 : f32 = t_5 - 2.0f * floor(t_5 / 2.0f);
        var reflected_1 : f32;
        if(reflected_0 < 0.0f)
        {
            reflected_1 = reflected_0 + 2.0f;
        }
        else
        {
            reflected_1 = reflected_0;
        }
        return 1.0f - abs(reflected_1 - 1.0f);
    }
    return clamp(t_5, 0.0f, 1.0f);
}

fn mixGradient_0( c0_1 : vec4<f32>,  c1_1 : vec4<f32>,  t_6 : f32) -> vec4<f32>
{
    return mix(c0_1, c1_1, vec4<f32>(t_6));
}

fn sampleImagePaintTex_0( image_tex_0 : texture_2d_array<f32>,  image_sampler_0 : sampler,  uv_0 : vec2<f32>,  layer_2 : i32,  filterMode_0 : i32) -> vec4<f32>
{
    if(filterMode_0 == i32(1))
    {
        var uw_1 : u32;
        var uh_1 : u32;
        var ue_0 : u32;
        {var dim = textureDimensions((image_tex_0));((uw_1)) = dim.x;((uh_1)) = dim.y;((ue_0)) = textureNumLayers((image_tex_0));};
        var size_0 : vec2<i32> = vec2<i32>(i32(uw_1), i32(uh_1));
        var _S75 : vec4<i32> = vec4<i32>(clamp(vec2<i32>(uv_0 * vec2<f32>(size_0)), vec2<i32>(i32(0)), size_0 - vec2<i32>(i32(1))), layer_2, i32(0));
        return (textureLoad((image_tex_0), ((_S75)).xy, i32(((_S75)).z), ((_S75)).w));
    }
    var _S76 : vec3<f32> = vec3<f32>(uv_0, f32(layer_2));
    return (textureSample((image_tex_0), (image_sampler_0), ((_S76)).xy, i32(((_S76)).z)));
}

fn samplePathPaint_0( layer_tex_1 : texture_2d<f32>,  image_tex_1 : texture_2d_array<f32>,  image_sampler_1 : sampler,  rc_1 : vec2<f32>,  infoBase_0 : vec2<i32>,  info_0 : vec4<f32>) -> PathPaintSample_0
{
    var paintKind_0 : i32 = i32(- info_0.w + 0.5f);
    var _S77 : vec2<i32> = offsetLayerLoc_0(layer_tex_1, infoBase_0, i32(2));
    var _S78 : vec3<i32> = vec3<i32>(_S77, i32(0));
    var data0_0 : vec4<f32> = (textureLoad((layer_tex_1), ((_S78)).xy, ((_S78)).z));
    if(paintKind_0 == i32(1))
    {
        return PathPaintSample_x24init_0(data0_0, 0.0f);
    }
    var _S79 : vec2<i32> = offsetLayerLoc_0(layer_tex_1, infoBase_0, i32(3));
    var _S80 : vec3<i32> = vec3<i32>(_S79, i32(0));
    var color0_0 : vec4<f32> = (textureLoad((layer_tex_1), ((_S80)).xy, ((_S80)).z));
    var _S81 : vec2<i32> = offsetLayerLoc_0(layer_tex_1, infoBase_0, i32(4));
    var _S82 : vec3<i32> = vec3<i32>(_S81, i32(0));
    var color1_0 : vec4<f32> = (textureLoad((layer_tex_1), ((_S82)).xy, ((_S82)).z));
    if(paintKind_0 == i32(2))
    {
        var _S83 : vec2<f32> = data0_0.xy;
        var delta_0 : vec2<f32> = data0_0.zw - _S83;
        var lenSq_0 : f32 = dot(delta_0, delta_0);
        var t_7 : f32;
        if(lenSq_0 > 1.00000001335143196e-10f)
        {
            t_7 = dot(rc_1 - _S83, delta_0) / lenSq_0;
        }
        else
        {
            t_7 = 0.0f;
        }
        var _S84 : vec2<i32> = offsetLayerLoc_0(layer_tex_1, infoBase_0, i32(5));
        var _S85 : vec3<i32> = vec3<i32>(_S84, i32(0));
        return PathPaintSample_x24init_0(mixGradient_0(color0_0, color1_0, wrapPaintT_0(t_7, (textureLoad((layer_tex_1), ((_S85)).xy, ((_S85)).z)).x)), 1.0f);
    }
    if(paintKind_0 == i32(3))
    {
        return PathPaintSample_x24init_0(mixGradient_0(color0_0, color1_0, wrapPaintT_0(length(rc_1 - data0_0.xy) / max(abs(data0_0.z), 0.0000152587890625f), data0_0.w)), 1.0f);
    }
    if(paintKind_0 == i32(6))
    {
        var d_1 : vec2<f32> = rc_1 - data0_0.xy;
        return PathPaintSample_x24init_0(mixGradient_0(color0_0, color1_0, wrapPaintT_0((atan2(d_1.y, d_1.x) - data0_0.z) * 0.15915493667125702f, data0_0.w)), 1.0f);
    }
    if(paintKind_0 == i32(4))
    {
        var _S86 : vec2<i32> = offsetLayerLoc_0(layer_tex_1, infoBase_0, i32(3));
        var _S87 : vec3<i32> = vec3<i32>(_S86, i32(0));
        var data1_0 : vec4<f32> = (textureLoad((layer_tex_1), ((_S87)).xy, ((_S87)).z));
        var _S88 : vec2<i32> = offsetLayerLoc_0(layer_tex_1, infoBase_0, i32(5));
        var _S89 : vec3<i32> = vec3<i32>(_S88, i32(0));
        var extra_0 : vec4<f32> = (textureLoad((layer_tex_1), ((_S89)).xy, ((_S89)).z));
        var _S90 : vec3<f32> = vec3<f32>(rc_1, 1.0f);
        return PathPaintSample_x24init_0(sampleImagePaintTex_0(image_tex_1, image_sampler_1, vec2<f32>(wrapPaintT_0(dot(_S90, vec3<f32>(data0_0.x, data0_0.y, data0_0.z)), extra_0.z) * extra_0.x, wrapPaintT_0(dot(_S90, vec3<f32>(data1_0.x, data1_0.y, data1_0.z)), extra_0.w) * extra_0.y), i32(data0_0.w + 0.5f), i32(data1_0.w + 0.5f)), 0.0f);
    }
    return PathPaintSample_x24init_0(vec4<f32>(1.0f, 0.0f, 1.0f, 1.0f), 0.0f);
}

fn premultiplyColor_0( color_2 : vec4<f32>,  cov_9 : f32) -> vec4<f32>
{
    var alpha_0 : f32 = color_2.w * cov_9;
    return vec4<f32>(color_2.xyz * vec3<f32>(alpha_0), alpha_0);
}

struct PathCompositeSample_0
{
     color_3 : vec4<f32>,
     gradient_2 : f32,
};

fn PathCompositeSample_x24init_0( color_4 : vec4<f32>,  gradient_3 : f32) -> PathCompositeSample_0
{
    var _S91 : PathCompositeSample_0;
    _S91.color_3 = color_4;
    _S91.gradient_2 = gradient_3;
    return _S91;
}

fn compositePathGroup_0( curve_tex_3 : texture_2d_array<f32>,  band_tex_2 : texture_2d_array<u32>,  layer_tex_2 : texture_2d<f32>,  image_tex_2 : texture_2d_array<f32>,  image_sampler_2 : sampler,  rc_2 : vec2<f32>,  epp_1 : vec2<f32>,  ppe_7 : vec2<f32>,  infoBase_1 : vec2<i32>,  header_0 : vec4<f32>,  texLayer_1 : i32,  tint_0 : vec4<f32>,  coverage_exponent_3 : f32) -> PathCompositeSample_0
{
    var _S92 : bool;
    var layer_count_0 : i32 = i32(header_0.x + 0.5f);
    var composite_mode_0 : i32 = i32(header_0.y + 0.5f);
    var _S93 : vec4<f32> = vec4<f32>(0.0f);
    var _S94 : PathPaintSample_0 = PathPaintSample_x24init_0(_S93, 0.0f);
    var result_0 : vec4<f32> = _S93;
    var fill_cov_0 : f32 = 0.0f;
    var stroke_cov_0 : f32 = 0.0f;
    var fill_paint_0 : PathPaintSample_0 = _S94;
    var stroke_paint_0 : PathPaintSample_0 = _S94;
    var has_gradient_0 : f32 = 0.0f;
    var l_0 : i32 = i32(0);
    for(;;)
    {
        if(l_0 < layer_count_0)
        {
        }
        else
        {
            break;
        }
        var loc_3 : vec2<i32> = offsetLayerLoc_0(layer_tex_2, infoBase_1, i32(1) + l_0 * i32(6));
        var _S95 : vec3<i32> = vec3<i32>(loc_3, i32(0));
        var info_1 : vec4<f32> = (textureLoad((layer_tex_2), ((_S95)).xy, ((_S95)).z));
        var _S96 : vec2<i32> = offsetLayerLoc_0(layer_tex_2, loc_3, i32(1));
        var _S97 : vec3<i32> = vec3<i32>(_S96, i32(0));
        var packed_gx_0 : i32 = i32(info_1.x);
        var _S98 : i32 = (bitcast<i32>((info_1.z)));
        var cov_10 : f32 = evalPathGlyphCoverage_0(curve_tex_3, band_tex_2, rc_2, epp_1, ppe_7, vec2<i32>((packed_gx_0 & (i32(32767))), i32(info_1.y)), vec2<i32>((((_S98 >> (u32(16)))) & (i32(65535))), (_S98 & (i32(65535)))), (textureLoad((layer_tex_2), ((_S97)).xy, ((_S97)).z)), texLayer_1, (((packed_gx_0 >> (u32(15)))) & (i32(1))), coverage_exponent_3);
        var _S99 : PathPaintSample_0 = samplePathPaint_0(layer_tex_2, image_tex_2, image_sampler_2, rc_2, loc_3, info_1);
        var paint_0 : PathPaintSample_0 = _S99;
        paint_0.color_0 = paint_0.color_0 * tint_0;
        if(composite_mode_0 == i32(1))
        {
            _S92 = layer_count_0 >= i32(2);
        }
        else
        {
            _S92 = false;
        }
        var _S100 : bool;
        if(_S92)
        {
            _S100 = l_0 < i32(2);
        }
        else
        {
            _S100 = false;
        }
        var fill_cov_1 : f32;
        if(_S100)
        {
            var stroke_cov_1 : f32;
            var fill_paint_1 : PathPaintSample_0;
            var stroke_paint_1 : PathPaintSample_0;
            if(l_0 == i32(0))
            {
                fill_cov_1 = cov_10;
                stroke_cov_1 = stroke_cov_0;
                fill_paint_1 = paint_0;
                stroke_paint_1 = stroke_paint_0;
            }
            else
            {
                fill_cov_1 = fill_cov_0;
                stroke_cov_1 = cov_10;
                fill_paint_1 = fill_paint_0;
                stroke_paint_1 = paint_0;
            }
            fill_cov_0 = fill_cov_1;
            stroke_cov_0 = stroke_cov_1;
            fill_paint_0 = fill_paint_1;
            stroke_paint_0 = stroke_paint_1;
            l_0 = l_0 + i32(1);
            continue;
        }
        var _S101 : bool;
        if((paint_0.gradient_0) > 0.5f)
        {
            _S101 = cov_10 > 9.99999997475242708e-07f;
        }
        else
        {
            _S101 = false;
        }
        if(_S101)
        {
            fill_cov_1 = 1.0f;
        }
        else
        {
            fill_cov_1 = has_gradient_0;
        }
        var premul_0 : vec4<f32> = premultiplyColor_0(paint_0.color_0, cov_10);
        result_0 = premul_0 + result_0 * vec4<f32>((1.0f - premul_0.w));
        has_gradient_0 = fill_cov_1;
        l_0 = l_0 + i32(1);
    }
    if(composite_mode_0 == i32(1))
    {
        _S92 = layer_count_0 >= i32(2);
    }
    else
    {
        _S92 = false;
    }
    if(_S92)
    {
        var _S102 : f32 = min(fill_cov_0, stroke_cov_0);
        var _S103 : f32 = max(fill_cov_0 - _S102, 0.0f);
        if((fill_paint_0.gradient_0) > 0.5f)
        {
            _S92 = _S103 > 9.99999997475242708e-07f;
        }
        else
        {
            _S92 = false;
        }
        if(_S92)
        {
            has_gradient_0 = 1.0f;
        }
        if((stroke_paint_0.gradient_0) > 0.5f)
        {
            _S92 = _S102 > 9.99999997475242708e-07f;
        }
        else
        {
            _S92 = false;
        }
        if(_S92)
        {
            has_gradient_0 = 1.0f;
        }
        result_0 = result_0 + (premultiplyColor_0(fill_paint_0.color_0, _S103) + premultiplyColor_0(stroke_paint_0.color_0, _S102)) * vec4<f32>((1.0f - result_0.w));
    }
    return PathCompositeSample_x24init_0(result_0, has_gradient_0);
}

fn interleavedGradientNoise_0( pixel_0 : vec2<f32>) -> f32
{
    return fract(52.98291778564453125f * fract(dot(pixel_0, vec2<f32>(0.06711056083440781f, 0.00583714991807938f))));
}

fn srgbEncode_0( c_0 : f32) -> f32
{
    var _S104 : f32;
    if(c_0 <= 0.00313080009073019f)
    {
        _S104 = c_0 * 12.92000007629394531f;
    }
    else
    {
        _S104 = 1.0549999475479126f * pow(c_0, 0.4166666567325592f) - 0.05499999970197678f;
    }
    return _S104;
}

fn linearToSrgb_0( color_5 : vec3<f32>) -> vec3<f32>
{
    return vec3<f32>(srgbEncode_0(max(color_5.x, 0.0f)), srgbEncode_0(max(color_5.y, 0.0f)), srgbEncode_0(max(color_5.z, 0.0f)));
}

fn srgbDecode_0( c_1 : f32) -> f32
{
    var _S105 : f32;
    if(c_1 <= 0.04044999927282333f)
    {
        _S105 = c_1 / 12.92000007629394531f;
    }
    else
    {
        _S105 = pow((c_1 + 0.05499999970197678f) / 1.0549999475479126f, 2.40000009536743164f);
    }
    return _S105;
}

fn srgbToLinear_0( color_6 : vec3<f32>) -> vec3<f32>
{
    return vec3<f32>(srgbDecode_0(color_6.x), srgbDecode_0(color_6.y), srgbDecode_0(color_6.z));
}

fn ditherPremultipliedColor_0( color_7 : vec4<f32>,  frag_coord_0 : vec2<f32>,  dither_scale_1 : f32) -> vec4<f32>
{
    var _S106 : f32 = color_7.w;
    var _S107 : bool;
    if(_S106 <= 0.0f)
    {
        _S107 = true;
    }
    else
    {
        _S107 = dither_scale_1 <= 0.0f;
    }
    if(_S107)
    {
        return color_7;
    }
    return vec4<f32>(srgbToLinear_0(clamp(linearToSrgb_0(color_7.xyz) + vec3<f32>(((interleavedGradientNoise_0(frag_coord_0) - 0.5f) * (clamp(_S106, 0.0f, 1.0f) * dither_scale_1))), vec3<f32>(0.0f), vec3<f32>(1.0f))), _S106);
}

fn srgbEncodePremultiplied_0( premul_1 : vec4<f32>) -> vec4<f32>
{
    var _S108 : f32 = premul_1.w;
    if(_S108 <= 0.0f)
    {
        return vec4<f32>(0.0f);
    }
    return vec4<f32>(linearToSrgb_0(premul_1.xyz * vec3<f32>((1.0f / _S108))) * vec3<f32>(_S108), _S108);
}

struct PaintedVaryings_0
{
     tint_1 : vec4<f32>,
     texcoord_0 : vec2<f32>,
     banding_1 : vec4<f32>,
     glyph_0 : vec4<i32>,
};

struct PaintedParams_0
{
     layer_base_1 : i32,
     output_srgb_1 : i32,
     coverage_exponent_4 : f32,
     dither_scale_2 : f32,
     mask_output_1 : i32,
};

fn snailPaintedFragment_0( expected_special_kind_0 : i32,  v_1 : PaintedVaryings_0,  frag_coord_1 : vec2<f32>,  curve_tex_4 : texture_2d_array<f32>,  band_tex_3 : texture_2d_array<u32>,  layer_tex_3 : texture_2d<f32>,  image_tex_3 : texture_2d_array<f32>,  image_sampler_3 : sampler,  p_0 : PaintedParams_0) -> vec4<f32>
{
    var epp_2 : vec2<f32> = (fwidth((v_1.texcoord_0)));
    var ppe_8 : vec2<f32> = vec2<f32>(1.0f) / max(epp_2, vec2<f32>(0.0000152587890625f));
    var _S109 : i32 = v_1.glyph_0.w;
    var special_kind_0 : i32 = (_S109 & (i32(255)));
    if(((((_S109 >> (u32(8)))) & (i32(255)))) != i32(255))
    {
        discard;
    }
    if(special_kind_0 != expected_special_kind_0)
    {
        discard;
    }
    var infoBase_2 : vec2<i32> = v_1.glyph_0.xy;
    var _S110 : vec3<i32> = vec3<i32>(infoBase_2, i32(0));
    var firstInfo_0 : vec4<f32> = (textureLoad((layer_tex_3), ((_S110)).xy, ((_S110)).z));
    var _S111 : f32 = firstInfo_0.w;
    if(_S111 >= 0.0f)
    {
        discard;
    }
    var texLayer_2 : i32 = p_0.layer_base_1 + i32(v_1.banding_1.w);
    var emit_0 : vec4<f32>;
    if(i32(- _S111 + 0.5f) == i32(5))
    {
        var result_1 : PathCompositeSample_0 = compositePathGroup_0(curve_tex_4, band_tex_3, layer_tex_3, image_tex_3, image_sampler_3, v_1.texcoord_0, epp_2, ppe_8, infoBase_2, firstInfo_0, texLayer_2, v_1.tint_1, p_0.coverage_exponent_4);
        if((result_1.color_3.w) < 0.00392156885936856f)
        {
            discard;
        }
        if((result_1.gradient_2) > 0.5f)
        {
            emit_0 = ditherPremultipliedColor_0(result_1.color_3, frag_coord_1, p_0.dither_scale_2);
        }
        else
        {
            emit_0 = result_1.color_3;
        }
        if((p_0.mask_output_1) != i32(0))
        {
            emit_0 = vec4<f32>(emit_0.w);
        }
        else
        {
            if((p_0.output_srgb_1) != i32(0))
            {
                emit_0 = srgbEncodePremultiplied_0(emit_0);
            }
        }
        return emit_0;
    }
    var _S112 : vec2<i32> = offsetLayerLoc_0(layer_tex_3, infoBase_2, i32(1));
    var _S113 : vec3<i32> = vec3<i32>(_S112, i32(0));
    var packed_gx_1 : i32 = i32(firstInfo_0.x);
    var _S114 : i32 = (bitcast<i32>((firstInfo_0.z)));
    var cov_11 : f32 = evalPathGlyphCoverage_0(curve_tex_4, band_tex_3, v_1.texcoord_0, epp_2, ppe_8, vec2<i32>((packed_gx_1 & (i32(32767))), i32(firstInfo_0.y)), vec2<i32>((((_S114 >> (u32(16)))) & (i32(65535))), (_S114 & (i32(65535)))), (textureLoad((layer_tex_3), ((_S113)).xy, ((_S113)).z)), texLayer_2, (((packed_gx_1 >> (u32(15)))) & (i32(1))), p_0.coverage_exponent_4);
    if(cov_11 < 0.00392156885936856f)
    {
        discard;
    }
    var _S115 : PathPaintSample_0 = samplePathPaint_0(layer_tex_3, image_tex_3, image_sampler_3, v_1.texcoord_0, infoBase_2, firstInfo_0);
    var paint_1 : PathPaintSample_0 = _S115;
    var _S116 : vec4<f32> = paint_1.color_0 * v_1.tint_1;
    paint_1.color_0 = _S116;
    var result_2 : vec4<f32> = premultiplyColor_0(_S116, cov_11);
    if((paint_1.gradient_0) > 0.5f)
    {
        emit_0 = ditherPremultipliedColor_0(result_2, frag_coord_1, p_0.dither_scale_2);
    }
    else
    {
        emit_0 = result_2;
    }
    if((p_0.mask_output_1) != i32(0))
    {
        emit_0 = vec4<f32>(emit_0.w);
    }
    else
    {
        if((p_0.output_srgb_1) != i32(0))
        {
            emit_0 = srgbEncodePremultiplied_0(emit_0);
        }
    }
    return emit_0;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) color_8 : vec4<f32>,
    @location(1) texcoord_1 : vec2<f32>,
    @interpolate(flat) @location(2) banding_2 : vec4<f32>,
    @interpolate(flat) @location(3) glyph_1 : vec4<i32>,
    @location(4) tint_2 : vec4<f32>,
};

@fragment
fn fragmentMain( _S117 : pixelInput_0, @builtin(position) position_0 : vec4<f32>) -> pixelOutput_0
{
    var v_2 : PaintedVaryings_0;
    v_2.tint_1 = _S117.tint_2;
    v_2.texcoord_0 = _S117.texcoord_1;
    v_2.banding_1 = _S117.banding_2;
    v_2.glyph_0 = _S117.glyph_1;
    var p_1 : PaintedParams_0;
    p_1.layer_base_1 = pc_0.layer_base_0;
    p_1.output_srgb_1 = pc_0.output_srgb_0;
    p_1.coverage_exponent_4 = pc_0.coverage_exponent_0;
    p_1.dither_scale_2 = pc_0.dither_scale_0;
    p_1.mask_output_1 = pc_0.mask_output_0;
    var _S118 : vec4<f32> = snailPaintedFragment_0(i32(1), v_2, position_0.xy, u_curve_tex_0, u_band_tex_0, u_layer_tex_0, u_image_tex_0, u_image_sampler_0, p_1);
    var _S119 : pixelOutput_0 = pixelOutput_0( _S118 );
    return _S119;
}


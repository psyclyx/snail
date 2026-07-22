#pragma pack_matrix(column_major)
#ifdef SLANG_HLSL_ENABLE_NVAPI
#include "nvHLSLExtns.h"
#endif

#ifndef __DXC_VERSION_MAJOR
// warning X3557: loop doesn't seem to do anything, forcing loop to unroll
#pragma warning(disable : 3557)
#endif

struct SnailPushConstants_0
{
    float4x4 mvp_0;
    float2 viewport_0;
    int subpixel_order_0;
    int output_srgb_0;
    int layer_base_0;
    float coverage_exponent_0;
    float dither_scale_0;
    int mask_output_0;
};

cbuffer pc_0 : register(b0)
{
    SnailPushConstants_0 pc_0;
}
Texture2DArray<float4 > u_curve_tex_0 : register(t0);

Texture2DArray<uint2 > u_band_tex_0 : register(t1);

Texture2D<float4 > u_layer_tex_0 : register(t2);

Texture2DArray<float4 > u_image_tex_0 : register(t3);

SamplerState u_image_sampler_0 : register(s0);

struct PathPaintSample_0
{
    float4 color_0;
    float gradient_0;
};

PathPaintSample_0 PathPaintSample_x24init_0(float4 color_1, float gradient_1)
{
    PathPaintSample_0 _S1;
    _S1.color_0 = color_1;
    _S1.gradient_0 = gradient_1;
    return _S1;
}

int2 offsetLayerLoc_0(Texture2D<float4 > layer_tex_0, int2 base_0, int offset_0)
{
    uint uw_0;
    uint uh_0;
    layer_tex_0.GetDimensions(uw_0, uh_0);
    int width_0 = int(uw_0);
    int texel_0 = base_0.y * width_0 + base_0.x + offset_0;
    int _S2 = texel_0 % width_0;
    int _S3 = texel_0 / width_0;
    return int2(_S2, _S3);
}

struct CoverageBandSpan_0
{
    int first_0;
    int last_0;
};

CoverageBandSpan_0 CoverageBandSpan_x24init_0(int first_1, int last_1)
{
    CoverageBandSpan_0 _S4;
    _S4.first_0 = first_1;
    _S4.last_0 = last_1;
    return _S4;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S5 = max(abs(eppAxis_0 * bandScale_0) * 0.5f, 0.00000999999974738f);
    int first_2 = clamp(int(center_0 - _S5), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S5), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_1)
{
    int _S6 = glyphLoc_0.x + int(offset_1);
    int2 loc_0 = int2(_S6, glyphLoc_0.y);
    loc_0[int(1)] = loc_0[int(1)] + (_S6 >> int(12));
    loc_0[int(0)] = (loc_0[int(0)]) & int(4095);
    return loc_0;
}

int decodeBandCurveFirstMemberCommon_0(uint2 ref_0)
{
    return int((ref_0.x) >> 12U);
}

int2 decodeBandCurveLocCommon_0(uint2 ref_1)
{
    return int2(int((ref_1.x) & 4095U), int((ref_1.y) & 16383U));
}

int decodeBandCurveKindCommon_0(uint2 ref_2)
{
    return int((ref_2.y) >> 14U);
}

int2 offsetCurveLoc_0(int2 base_1, int offset_2)
{
    int _S7 = base_1.x + offset_2;
    int2 loc_1 = int2(_S7, base_1.y);
    loc_1[int(1)] = loc_1[int(1)] + (_S7 >> int(12));
    loc_1[int(0)] = (loc_1[int(0)]) & int(4095);
    return loc_1;
}

struct SegmentData_0
{
    int kind_0;
    float2 p0_0;
    float2 p1_0;
    float2 p2_0;
    float2 p3_0;
    float3 weights_0;
};

SegmentData_0 fetchSegment_0(Texture2DArray<float4 > curve_tex_0, int2 loc_2, int layer_0, int kind_1)
{
    float4 tex0_0 = curve_tex_0.Load(int4(loc_2, layer_0, int(0)));
    float4 tex1_0 = curve_tex_0.Load(int4(offsetCurveLoc_0(loc_2, int(1)), layer_0, int(0)));
    SegmentData_0 seg_0;
    seg_0.kind_0 = kind_1;
    seg_0.p0_0 = tex0_0.xy;
    seg_0.p1_0 = tex0_0.zw;
    seg_0.p2_0 = tex1_0.xy;
    seg_0.p3_0 = tex1_0.zw;
    if(kind_1 == int(1))
    {
        float4 tex2_0 = curve_tex_0.Load(int4(offsetCurveLoc_0(loc_2, int(2)), layer_0, int(0)));
        seg_0.weights_0 = float3(tex2_0.w, tex2_0.x, tex2_0.y);
    }
    else
    {
        seg_0.weights_0 = (float3)1.0f;
    }
    return seg_0;
}

float segmentMaxX_0(SegmentData_0 seg_1)
{
    if((seg_1.kind_0) == int(3))
    {
        return max(seg_1.p0_0.x, seg_1.p2_0.x);
    }
    if((seg_1.kind_0) == int(2))
    {
        return max(max(seg_1.p0_0.x, seg_1.p1_0.x), max(seg_1.p2_0.x, seg_1.p3_0.x));
    }
    return max(max(seg_1.p0_0.x, seg_1.p1_0.x), seg_1.p2_0.x);
}

float segmentMaxY_0(SegmentData_0 seg_2)
{
    if((seg_2.kind_0) == int(3))
    {
        return max(seg_2.p0_0.y, seg_2.p2_0.y);
    }
    if((seg_2.kind_0) == int(2))
    {
        return max(max(seg_2.p0_0.y, seg_2.p1_0.y), max(seg_2.p2_0.y, seg_2.p3_0.y));
    }
    return max(max(seg_2.p0_0.y, seg_2.p1_0.y), seg_2.p2_0.y);
}

float rootCodeCoord_0(float v_0)
{
    float _S8;
    if((abs(v_0)) <= 0.0000152587890625f)
    {
        _S8 = 0.0f;
    }
    else
    {
        _S8 = v_0;
    }
    return _S8;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((asuint(rootCodeCoord_0(y3_0))) >> 29U) & 4U) | (((((asuint(rootCodeCoord_0(y2_0))) >> 30U) & 2U) | (((asuint(rootCodeCoord_0(y1_0))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S9;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06f))
    {
        _S9 = 0.0f;
    }
    else
    {
        _S9 = sqrt(disc_0);
    }
    return _S9;
}

float2 solveQuadraticHorizDistances_0(float p0x_0, float p0y_0, float p1x_0, float p1y_0, float p2x_0, float p2y_0, float ppeX_0)
{
    float ax_0 = p0x_0 - p1x_0 * 2.0f + p2x_0;
    float ay_0 = p0y_0 - p1y_0 * 2.0f + p2y_0;
    float bx_0 = p0x_0 - p1x_0;
    float by_0 = p0y_0 - p1y_0;
    float t1_0;
    float t2_0;
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
        float _S10 = ay_0 * p0y_0;
        float sq_0 = snapNearTangentSqrt_0(by_0 * by_0 - _S10, by_0, _S10);
        if(by_0 >= 0.0f)
        {
            float q_0 = by_0 + sq_0;
            float _S11 = q_0 / ay_0;
            if((abs(q_0)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = p0y_0 / q_0;
            }
            t2_0 = _S11;
        }
        else
        {
            float q_1 = by_0 - sq_0;
            float _S12 = q_1 / ay_0;
            if((abs(q_1)) < 0.0000152587890625f)
            {
                t1_0 = 0.0f;
            }
            else
            {
                t1_0 = p0y_0 / q_1;
            }
            float _S13 = t1_0;
            t1_0 = _S12;
            t2_0 = _S13;
        }
    }
    float _S14 = bx_0 * 2.0f;
    return float2(((ax_0 * t1_0 - _S14) * t1_0 + p0x_0) * ppeX_0, ((ax_0 * t2_0 - _S14) * t2_0 + p0x_0) * ppeX_0);
}

float2 solveQuadraticVertDistances_0(float p0x_1, float p0y_1, float p1x_1, float p1y_1, float p2x_1, float p2y_1, float ppeY_0)
{
    float ax_1 = p0x_1 - p1x_1 * 2.0f + p2x_1;
    float ay_1 = p0y_1 - p1y_1 * 2.0f + p2y_1;
    float bx_1 = p0x_1 - p1x_1;
    float by_1 = p0y_1 - p1y_1;
    float t1_1;
    float t2_1;
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
        float _S15 = ax_1 * p0x_1;
        float sq_1 = snapNearTangentSqrt_0(bx_1 * bx_1 - _S15, bx_1, _S15);
        if(bx_1 >= 0.0f)
        {
            float q_2 = bx_1 + sq_1;
            float _S16 = q_2 / ax_1;
            if((abs(q_2)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = p0x_1 / q_2;
            }
            t2_1 = _S16;
        }
        else
        {
            float q_3 = bx_1 - sq_1;
            float _S17 = q_3 / ax_1;
            if((abs(q_3)) < 0.0000152587890625f)
            {
                t1_1 = 0.0f;
            }
            else
            {
                t1_1 = p0x_1 / q_3;
            }
            float _S18 = t1_1;
            t1_1 = _S17;
            t2_1 = _S18;
        }
    }
    float _S19 = by_1 * 2.0f;
    return float2(((ay_1 * t1_1 - _S19) * t1_1 + p0y_1) * ppeY_0, ((ay_1 * t2_1 - _S19) * t2_1 + p0y_1) * ppeY_0);
}

void appendCoverageContribution_0(inout float cov_0, inout float wgt_0, float distance_0, float sign_0)
{
    cov_0 = cov_0 + sign_0 * clamp(distance_0 + 0.5f, 0.0f, 1.0f);
    wgt_0 = max(wgt_0, clamp(1.0f - abs(distance_0) * 2.0f, 0.0f, 1.0f));
    return;
}

void accumulateLineCoverage_0(inout float cov_1, inout float wgt_1, float p0x_2, float p0y_2, float p2x_2, float p2y_2, float ppe_0, bool horizontal_0)
{
    float rootAxis0_0;
    if(horizontal_0)
    {
        rootAxis0_0 = p0y_2;
    }
    else
    {
        rootAxis0_0 = p0x_2;
    }
    float rootAxis2_0;
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
    float denom_0 = rootAxis2_0 - rootAxis0_0;
    if((abs(denom_0)) < 1.00000001335143196e-10f)
    {
        return;
    }
    float t_0 = clamp(- rootAxis0_0 / denom_0, 0.0f, 1.0f);
    float derivativeAxis_0;
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
    float distance_1 = rootAxis0_0 * ppe_0;
    if(derivativeAxis_0 > 0.0f)
    {
        rootAxis0_0 = 1.0f;
    }
    else
    {
        rootAxis0_0 = -1.0f;
    }
    appendCoverageContribution_0(cov_1, wgt_1, distance_1, rootAxis0_0);
    return;
}

bool rootHullCanCross4_0(float p0_1, float p1_1, float p2_1, float p3_1, float sampleRoot_0)
{
    float _S20 = max(max(p0_1, p1_1), max(p2_1, p3_1));
    bool _S21;
    if((min(min(p0_1, p1_1), min(p2_1, p3_1)) - sampleRoot_0) <= 0.0000152587890625f)
    {
        _S21 = (_S20 - sampleRoot_0) >= -0.0000152587890625f;
    }
    else
    {
        _S21 = false;
    }
    return _S21;
}

bool rootHullCanCross3_0(float p0_2, float p1_2, float p2_2, float sampleRoot_1)
{
    float _S22 = max(max(p0_2, p1_2), p2_2);
    bool _S23;
    if((min(min(p0_2, p1_2), p2_2) - sampleRoot_1) <= 0.0000152587890625f)
    {
        _S23 = (_S22 - sampleRoot_1) >= -0.0000152587890625f;
    }
    else
    {
        _S23 = false;
    }
    return _S23;
}

bool segmentRootHullCanCross_0(SegmentData_0 seg_3, float2 sampleRc_0, bool horizontal_1)
{
    float sampleRoot_2;
    if(horizontal_1)
    {
        sampleRoot_2 = sampleRc_0.y;
    }
    else
    {
        sampleRoot_2 = sampleRc_0.x;
    }
    float _S24;
    float _S25;
    float _S26;
    if((seg_3.kind_0) == int(2))
    {
        if(horizontal_1)
        {
            _S24 = seg_3.p0_0.y;
        }
        else
        {
            _S24 = seg_3.p0_0.x;
        }
        if(horizontal_1)
        {
            _S25 = seg_3.p1_0.y;
        }
        else
        {
            _S25 = seg_3.p1_0.x;
        }
        if(horizontal_1)
        {
            _S26 = seg_3.p2_0.y;
        }
        else
        {
            _S26 = seg_3.p2_0.x;
        }
        float _S27;
        if(horizontal_1)
        {
            _S27 = seg_3.p3_0.y;
        }
        else
        {
            _S27 = seg_3.p3_0.x;
        }
        return rootHullCanCross4_0(_S24, _S25, _S26, _S27, sampleRoot_2);
    }
    if(horizontal_1)
    {
        _S24 = seg_3.p0_0.y;
    }
    else
    {
        _S24 = seg_3.p0_0.x;
    }
    if(horizontal_1)
    {
        _S25 = seg_3.p1_0.y;
    }
    else
    {
        _S25 = seg_3.p1_0.x;
    }
    if(horizontal_1)
    {
        _S26 = seg_3.p2_0.y;
    }
    else
    {
        _S26 = seg_3.p2_0.x;
    }
    return rootHullCanCross3_0(_S24, _S25, _S26, sampleRoot_2);
}

float distToUnitInterval_0(float t_1)
{
    return max(max(0.0f, - t_1), t_1 - 1.0f);
}

float segmentEndRootDelta_0(SegmentData_0 seg_4, float2 sampleRc_1, bool horizontal_2)
{
    float _S28;
    if((seg_4.kind_0) == int(2))
    {
        if(horizontal_2)
        {
            _S28 = seg_4.p3_0.y - sampleRc_1.y;
        }
        else
        {
            _S28 = seg_4.p3_0.x - sampleRc_1.x;
        }
        return _S28;
    }
    if(horizontal_2)
    {
        _S28 = seg_4.p2_0.y - sampleRc_1.y;
    }
    else
    {
        _S28 = seg_4.p2_0.x - sampleRc_1.x;
    }
    return _S28;
}

void accumulateConicRoot_0(inout float cov_2, inout float wgt_2, float t_2, float endRootDelta_0, float sampleAlong_0, float ppe_1, bool horizontal_3, float rootA_0, float rootB_0, float rootC_0, float alongA_0, float alongB_0, float alongC_0, float denA_0, float denB_0, float denC_0)
{
    float _S29 = max((denA_0 * t_2 + denB_0) * t_2 + denC_0, 0.0000152587890625f);
    float along_0 = ((alongA_0 * t_2 + alongB_0) * t_2 + alongC_0) / _S29;
    float derivAxis_0 = ((2.0f * rootA_0 * t_2 + rootB_0) * _S29 - ((rootA_0 * t_2 + rootB_0) * t_2 + rootC_0) * (2.0f * denA_0 * t_2 + denB_0)) / (_S29 * _S29);
    float derivAxis_1;
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
    float dist_0 = (along_0 - sampleAlong_0) * ppe_1;
    if(derivAxis_1 > 0.0f)
    {
        derivAxis_1 = 1.0f;
    }
    else
    {
        derivAxis_1 = -1.0f;
    }
    appendCoverageContribution_0(cov_2, wgt_2, dist_0, derivAxis_1);
    return;
}

void accumulateConicCoverage_0(inout float cov_3, inout float wgt_3, SegmentData_0 seg_5, float2 sampleRc_2, float ppe_2, bool horizontal_4)
{
    if(!segmentRootHullCanCross_0(seg_5, sampleRc_2, horizontal_4))
    {
        return;
    }
    float sampleRoot_3;
    if(horizontal_4)
    {
        sampleRoot_3 = sampleRc_2.y;
    }
    else
    {
        sampleRoot_3 = sampleRc_2.x;
    }
    float sampleAlong_1;
    if(horizontal_4)
    {
        sampleAlong_1 = sampleRc_2.x;
    }
    else
    {
        sampleAlong_1 = sampleRc_2.y;
    }
    float p0Root_0;
    if(horizontal_4)
    {
        p0Root_0 = seg_5.p0_0.y;
    }
    else
    {
        p0Root_0 = seg_5.p0_0.x;
    }
    float p1Root_0;
    if(horizontal_4)
    {
        p1Root_0 = seg_5.p1_0.y;
    }
    else
    {
        p1Root_0 = seg_5.p1_0.x;
    }
    float p2Root_0;
    if(horizontal_4)
    {
        p2Root_0 = seg_5.p2_0.y;
    }
    else
    {
        p2Root_0 = seg_5.p2_0.x;
    }
    float p0Along_0;
    if(horizontal_4)
    {
        p0Along_0 = seg_5.p0_0.x;
    }
    else
    {
        p0Along_0 = seg_5.p0_0.y;
    }
    float p1Along_0;
    if(horizontal_4)
    {
        p1Along_0 = seg_5.p1_0.x;
    }
    else
    {
        p1Along_0 = seg_5.p1_0.y;
    }
    float p2Along_0;
    if(horizontal_4)
    {
        p2Along_0 = seg_5.p2_0.x;
    }
    else
    {
        p2Along_0 = seg_5.p2_0.y;
    }
    float _S30 = seg_5.weights_0.x;
    float c0_0 = _S30 * (p0Root_0 - sampleRoot_3);
    float _S31 = seg_5.weights_0.y;
    float c1_0 = _S31 * (p1Root_0 - sampleRoot_3);
    float _S32 = seg_5.weights_0.z;
    float c2_0 = _S32 * (p2Root_0 - sampleRoot_3);
    uint code_0 = calcRootCode_0(c0_0, c1_0, c2_0);
    if(code_0 == 0U)
    {
        return;
    }
    int want_0;
    if(code_0 == 257U)
    {
        want_0 = int(2);
    }
    else
    {
        want_0 = int(1);
    }
    float quadA_0 = c0_0 - 2.0f * c1_0 + c2_0;
    float quadB_0 = 2.0f * (c1_0 - c0_0);
    float cand1_0;
    float cand0_0;
    int ncand_0;
    if((abs(quadA_0)) < 0.0000152587890625f)
    {
        if((abs(quadB_0)) >= 0.0000152587890625f)
        {
            float _S33 = - c0_0 / quadB_0;
            ncand_0 = int(1);
            cand1_0 = _S33;
        }
        else
        {
            ncand_0 = int(0);
            cand1_0 = 0.0f;
        }
        float _S34 = cand1_0;
        cand1_0 = 0.0f;
        cand0_0 = _S34;
    }
    else
    {
        float sqrtDisc_0 = sqrt(max(quadB_0 * quadB_0 - 4.0f * quadA_0 * c0_0, 0.0f));
        float inv2a_0 = 0.5f / quadA_0;
        float _S35 = - quadB_0;
        float _S36 = (_S35 - sqrtDisc_0) * inv2a_0;
        float _S37 = (_S35 + sqrtDisc_0) * inv2a_0;
        ncand_0 = int(2);
        cand1_0 = _S37;
        cand0_0 = _S36;
    }
    if(ncand_0 == int(0))
    {
        return;
    }
    float root0_0;
    float root1_0;
    int rootCount_0;
    if(want_0 == int(1))
    {
        bool _S38;
        if(ncand_0 == int(2))
        {
            _S38 = (distToUnitInterval_0(cand1_0)) < (distToUnitInterval_0(cand0_0));
        }
        else
        {
            _S38 = false;
        }
        if(_S38)
        {
            root0_0 = cand1_0;
        }
        else
        {
            root0_0 = cand0_0;
        }
        root0_0 = clamp(root0_0, 0.0f, 1.0f);
        rootCount_0 = int(1);
        root1_0 = 0.0f;
    }
    else
    {
        float _S39 = clamp(cand1_0, 0.0f, 1.0f);
        root0_0 = clamp(cand0_0, 0.0f, 1.0f);
        rootCount_0 = int(2);
        root1_0 = _S39;
    }
    float _S40 = p0Root_0 * _S30;
    float rootA_1 = _S40 - 2.0f * p1Root_0 * _S31 + p2Root_0 * _S32;
    float rootB_1 = 2.0f * (p1Root_0 * _S31 - _S40);
    float _S41 = p0Along_0 * _S30;
    float alongA_1 = _S41 - 2.0f * p1Along_0 * _S31 + p2Along_0 * _S32;
    float alongB_1 = 2.0f * (p1Along_0 * _S31 - _S41);
    float denA_1 = _S30 - 2.0f * _S31 + _S32;
    float denB_1 = 2.0f * (_S31 - _S30);
    float endRootDelta_1 = segmentEndRootDelta_0(seg_5, sampleRc_2, horizontal_4);
    accumulateConicRoot_0(cov_3, wgt_3, root0_0, endRootDelta_1, sampleAlong_1, ppe_2, horizontal_4, rootA_1, rootB_1, _S40, alongA_1, alongB_1, _S41, denA_1, denB_1, _S30);
    if(rootCount_0 == int(2))
    {
        accumulateConicRoot_0(cov_3, wgt_3, root1_0, endRootDelta_1, sampleAlong_1, ppe_2, horizontal_4, rootA_1, rootB_1, _S40, alongA_1, alongB_1, _S41, denA_1, denB_1, _S30);
    }
    return;
}

bool solveMonotonicCubicRoot_0(float a_0, float b_1, float cVal_0, float d_0, float endDelta_0, out float tOut_0)
{
    tOut_0 = 0.0f;
    bool _S42;
    if(d_0 < -0.0000152587890625f)
    {
        _S42 = endDelta_0 < -0.0000152587890625f;
    }
    else
    {
        _S42 = false;
    }
    if(_S42)
    {
        _S42 = true;
    }
    else
    {
        if(d_0 > 0.0000152587890625f)
        {
            _S42 = endDelta_0 > 0.0000152587890625f;
        }
        else
        {
            _S42 = false;
        }
    }
    if(_S42)
    {
        return false;
    }
    bool _S43 = endDelta_0 >= d_0;
    float t_3 = 0.5f;
    float lo_0 = 0.0f;
    float hi_0 = 1.0f;
    int i_0 = int(0);
    for(;;)
    {
        if(i_0 < int(16))
        {
        }
        else
        {
            break;
        }
        float f_0 = ((a_0 * t_3 + b_1) * t_3 + cVal_0) * t_3 + d_0;
        if(_S43)
        {
            _S42 = f_0 < 0.0f;
        }
        else
        {
            _S42 = false;
        }
        bool _S44;
        if(_S42)
        {
            _S44 = true;
        }
        else
        {
            if(!_S43)
            {
                _S44 = f_0 > 0.0f;
            }
            else
            {
                _S44 = false;
            }
        }
        if(_S44)
        {
            lo_0 = t_3;
        }
        else
        {
            hi_0 = t_3;
        }
        float deriv_0 = (3.0f * a_0 * t_3 + 2.0f * b_1) * t_3 + cVal_0;
        float _S45 = (lo_0 + hi_0) * 0.5f;
        float next_0;
        if((abs(deriv_0)) >= 9.99999997475242708e-07f)
        {
            float newton_0 = t_3 - f_0 / deriv_0;
            bool _S46;
            if(newton_0 > lo_0)
            {
                _S46 = newton_0 < hi_0;
            }
            else
            {
                _S46 = false;
            }
            if(_S46)
            {
                next_0 = newton_0;
            }
            else
            {
                next_0 = _S45;
            }
        }
        else
        {
            next_0 = _S45;
        }
        int _S47 = i_0 + int(1);
        t_3 = next_0;
        i_0 = _S47;
    }
    tOut_0 = t_3;
    return true;
}

void accumulateCubicCoverage_0(inout float cov_4, inout float wgt_4, SegmentData_0 seg_6, float2 sampleRc_3, float ppe_3, bool horizontal_5)
{
    if(!segmentRootHullCanCross_0(seg_6, sampleRc_3, horizontal_5))
    {
        return;
    }
    float sampleRoot_4;
    if(horizontal_5)
    {
        sampleRoot_4 = sampleRc_3.y;
    }
    else
    {
        sampleRoot_4 = sampleRc_3.x;
    }
    float sampleAlong_2;
    if(horizontal_5)
    {
        sampleAlong_2 = sampleRc_3.x;
    }
    else
    {
        sampleAlong_2 = sampleRc_3.y;
    }
    float p0Root_1;
    if(horizontal_5)
    {
        p0Root_1 = seg_6.p0_0.y;
    }
    else
    {
        p0Root_1 = seg_6.p0_0.x;
    }
    float p1Root_1;
    if(horizontal_5)
    {
        p1Root_1 = seg_6.p1_0.y;
    }
    else
    {
        p1Root_1 = seg_6.p1_0.x;
    }
    float p2Root_1;
    if(horizontal_5)
    {
        p2Root_1 = seg_6.p2_0.y;
    }
    else
    {
        p2Root_1 = seg_6.p2_0.x;
    }
    float p3Root_0;
    if(horizontal_5)
    {
        p3Root_0 = seg_6.p3_0.y;
    }
    else
    {
        p3Root_0 = seg_6.p3_0.x;
    }
    float p0Along_1;
    if(horizontal_5)
    {
        p0Along_1 = seg_6.p0_0.x;
    }
    else
    {
        p0Along_1 = seg_6.p0_0.y;
    }
    float p1Along_1;
    if(horizontal_5)
    {
        p1Along_1 = seg_6.p1_0.x;
    }
    else
    {
        p1Along_1 = seg_6.p1_0.y;
    }
    float p2Along_1;
    if(horizontal_5)
    {
        p2Along_1 = seg_6.p2_0.x;
    }
    else
    {
        p2Along_1 = seg_6.p2_0.y;
    }
    float p3Along_0;
    if(horizontal_5)
    {
        p3Along_0 = seg_6.p3_0.x;
    }
    else
    {
        p3Along_0 = seg_6.p3_0.y;
    }
    float _S48 = 3.0f * p1Root_1;
    float _S49 = 3.0f * p2Root_1;
    float rootA_2 = - p0Root_1 + _S48 - _S49 + p3Root_0;
    float rootB_2 = 3.0f * p0Root_1 - 6.0f * p1Root_1 + _S49;
    float rootC_1 = -3.0f * p0Root_1 + _S48;
    float startDelta_0 = p0Root_1 - sampleRoot_4;
    float endDelta_1 = p3Root_0 - sampleRoot_4;
    if(((rootCodeCoord_0(startDelta_0)) < 0.0f) == ((rootCodeCoord_0(endDelta_1)) < 0.0f))
    {
        return;
    }
    float t_4 = 0.0f;
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
            bool _S50 = solveMonotonicCubicRoot_0(rootA_2, rootB_2, rootC_1, startDelta_0, endDelta_1, t_4);
            if(!_S50)
            {
                return;
            }
        }
    }
    float _S51 = 3.0f * p1Along_1;
    float _S52 = 3.0f * p2Along_1;
    float alongA_2 = - p0Along_1 + _S51 - _S52 + p3Along_0;
    float alongB_2 = 3.0f * p0Along_1 - 6.0f * p1Along_1 + _S52;
    float alongC_1 = -3.0f * p0Along_1 + _S51;
    float along_1;
    if(t_4 == 1.0f)
    {
        along_1 = p3Along_0;
    }
    else
    {
        along_1 = ((alongA_2 * t_4 + alongB_2) * t_4 + alongC_1) * t_4 + p0Along_1;
    }
    float derivAxis_2;
    if(horizontal_5)
    {
        derivAxis_2 = p3Root_0 - p0Root_1;
    }
    else
    {
        derivAxis_2 = p0Root_1 - p3Root_0;
    }
    float dist_1 = (along_1 - sampleAlong_2) * ppe_3;
    if(derivAxis_2 > 0.0f)
    {
        sampleRoot_4 = 1.0f;
    }
    else
    {
        sampleRoot_4 = -1.0f;
    }
    appendCoverageContribution_0(cov_4, wgt_4, dist_1, sampleRoot_4);
    return;
}

bool accumulateAxisCoverageSegment_0(inout float cov_5, inout float wgt_5, float2 sampleRc_4, float ppe_4, SegmentData_0 seg_7, bool horizontal_6)
{
    float maxCoord_0;
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
    if((seg_7.kind_0) == int(0))
    {
        float _S53 = sampleRc_4.x;
        float p0x_3 = seg_7.p0_0.x - _S53;
        float _S54 = sampleRc_4.y;
        float p0y_3 = seg_7.p0_0.y - _S54;
        float p1x_2 = seg_7.p1_0.x - _S53;
        float p1y_2 = seg_7.p1_0.y - _S54;
        float p2x_3 = seg_7.p2_0.x - _S53;
        float p2y_3 = seg_7.p2_0.y - _S54;
        uint code_1;
        if(horizontal_6)
        {
            code_1 = calcRootCode_0(p0y_3, p1y_2, p2y_3);
        }
        else
        {
            code_1 = calcRootCode_0(p0x_3, p1x_2, p2x_3);
        }
        if(code_1 == 0U)
        {
            return true;
        }
        float2 roots_0;
        if(horizontal_6)
        {
            roots_0 = solveQuadraticHorizDistances_0(p0x_3, p0y_3, p1x_2, p1y_2, p2x_3, p2y_3, ppe_4);
        }
        else
        {
            roots_0 = solveQuadraticVertDistances_0(p0x_3, p0y_3, p1x_2, p1y_2, p2x_3, p2y_3, ppe_4);
        }
        if((code_1 & 1U) != 0U)
        {
            float _S55 = roots_0.x;
            if(horizontal_6)
            {
                maxCoord_0 = 1.0f;
            }
            else
            {
                maxCoord_0 = -1.0f;
            }
            appendCoverageContribution_0(cov_5, wgt_5, _S55, maxCoord_0);
        }
        if(code_1 > 1U)
        {
            float _S56 = roots_0.y;
            if(horizontal_6)
            {
                maxCoord_0 = -1.0f;
            }
            else
            {
                maxCoord_0 = 1.0f;
            }
            appendCoverageContribution_0(cov_5, wgt_5, _S56, maxCoord_0);
        }
        return true;
    }
    if((seg_7.kind_0) == int(3))
    {
        float _S57 = sampleRc_4.x;
        float _S58 = sampleRc_4.y;
        accumulateLineCoverage_0(cov_5, wgt_5, seg_7.p0_0.x - _S57, seg_7.p0_0.y - _S58, seg_7.p2_0.x - _S57, seg_7.p2_0.y - _S58, ppe_4, horizontal_6);
        return true;
    }
    if((seg_7.kind_0) == int(1))
    {
        accumulateConicCoverage_0(cov_5, wgt_5, seg_7, sampleRc_4, ppe_4, horizontal_6);
        return true;
    }
    accumulateCubicCoverage_0(cov_5, wgt_5, seg_7, sampleRc_4, ppe_4, horizontal_6);
    return true;
}

float2 evalAxisCoverageBands_0(Texture2DArray<float4 > curve_tex_1, Texture2DArray<uint2 > band_tex_0, float2 sampleRc_5, float ppe_5, int2 gLoc_0, int headerBase_0, int firstBand_0, int lastBand_0, int layer_1, bool horizontal_7)
{
    float cov_6 = 0.0f;
    float wgt_6 = 0.0f;
    bool _S59 = firstBand_0 != lastBand_0;
    int band_0 = firstBand_0;
    for(;;)
    {
        if(band_0 <= lastBand_0)
        {
        }
        else
        {
            break;
        }
        uint2 bd_0 = band_tex_0.Load(int4(calcBandLoc_0(gLoc_0, uint(headerBase_0 + band_0)), layer_1, int(0))).xy;
        int2 _S60 = calcBandLoc_0(gLoc_0, bd_0.y);
        int _S61 = int(bd_0.x);
        int i_1 = int(0);
        for(;;)
        {
            if(i_1 < _S61)
            {
            }
            else
            {
                break;
            }
            uint2 ref_3 = band_tex_0.Load(int4(calcBandLoc_0(_S60, uint(i_1)), layer_1, int(0))).xy;
            if(_S59)
            {
                if(band_0 != (max(decodeBandCurveFirstMemberCommon_0(ref_3), firstBand_0)))
                {
                    i_1 = i_1 + int(1);
                    continue;
                }
            }
            bool _S62 = accumulateAxisCoverageSegment_0(cov_6, wgt_6, sampleRc_5, ppe_5, fetchSegment_0(curve_tex_1, decodeBandCurveLocCommon_0(ref_3), layer_1, decodeBandCurveKindCommon_0(ref_3)), horizontal_7);
            if(!_S62)
            {
                break;
            }
            i_1 = i_1 + int(1);
        }
        band_0 = band_0 + int(1);
    }
    return float2(cov_6, wgt_6);
}

float applyFillRule_0(float winding_0, int fill_rule_mode_0)
{
    if(fill_rule_mode_0 == int(1))
    {
        return 1.0f - abs(frac(winding_0 * 0.5f) * 2.0f - 1.0f);
    }
    return abs(winding_0);
}

float applyCoverageTransfer_0(float cov_7, float coverage_exponent_1)
{
    float clamped_0 = clamp(cov_7, 0.0f, 1.0f);
    float _S63 = max(coverage_exponent_1, 0.0000152587890625f);
    float _S64;
    if((abs(_S63 - 1.0f)) <= 9.99999997475242708e-07f)
    {
        _S64 = clamped_0;
    }
    else
    {
        _S64 = pow(clamped_0, _S63);
    }
    return _S64;
}

float evalPathGlyphCoverage_0(Texture2DArray<float4 > curve_tex_2, Texture2DArray<uint2 > band_tex_1, float2 rc_0, float2 epp_0, float2 ppe_6, int2 gLoc_1, int2 bandMax_1, float4 banding_0, int texLayer_0, int fill_rule_0, float coverage_exponent_2)
{
    int _S65 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_0.y, epp_0.y, banding_0.y, banding_0.w, _S65);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_0.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    float2 horiz_0 = evalAxisCoverageBands_0(curve_tex_2, band_tex_1, rc_0, ppe_6.x, gLoc_1, int(0), hSpan_0.first_0, hSpan_0.last_0, texLayer_0, true);
    float2 vert_0 = evalAxisCoverageBands_0(curve_tex_2, band_tex_1, rc_0, ppe_6.y, gLoc_1, _S65 + int(1), vSpan_0.first_0, vSpan_0.last_0, texLayer_0, false);
    float _S66 = horiz_0.y;
    float _S67 = vert_0.y;
    float _S68 = horiz_0.x;
    float _S69 = vert_0.x;
    return applyCoverageTransfer_0(max(applyFillRule_0((_S68 * _S66 + _S69 * _S67) / max(_S66 + _S67, 0.0000152587890625f), fill_rule_0), min(applyFillRule_0(_S68, fill_rule_0), applyFillRule_0(_S69, fill_rule_0))), coverage_exponent_2);
}

float wrapPaintT_0(float t_5, float extendMode_0)
{
    int mode_0 = int(extendMode_0 + 0.5f);
    if(mode_0 == int(1))
    {
        return frac(t_5);
    }
    if(mode_0 == int(2))
    {
        float reflected_0 = t_5 - 2.0f * floor(t_5 / 2.0f);
        float reflected_1;
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

float4 mixGradient_0(float4 c0_1, float4 c1_1, float t_6)
{
    return lerp(c0_1, c1_1, (float4)t_6);
}

float4 sampleImagePaintTex_0(Texture2DArray<float4 > image_tex_0, SamplerState image_sampler_0, float2 uv_0, int layer_2, int filterMode_0)
{
    if(filterMode_0 == int(1))
    {
        uint uw_1;
        uint uh_1;
        uint ue_0;
        image_tex_0.GetDimensions(uw_1, uh_1, ue_0);
        int2 size_0 = int2(int(uw_1), int(uh_1));
        return image_tex_0.Load(int4(clamp(int2(uv_0 * float2(size_0)), (int2)int(0), size_0 - (int2)int(1)), layer_2, int(0)));
    }
    return image_tex_0.Sample(image_sampler_0, float3(uv_0, float(layer_2)));
}

PathPaintSample_0 samplePathPaint_0(Texture2D<float4 > layer_tex_1, Texture2DArray<float4 > image_tex_1, SamplerState image_sampler_1, float2 rc_1, int2 infoBase_0, float4 info_0)
{
    int paintKind_0 = int(- info_0.w + 0.5f);
    int2 _S70 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(2));
    float4 data0_0 = layer_tex_1.Load(int3(_S70, int(0)));
    if(paintKind_0 == int(1))
    {
        return PathPaintSample_x24init_0(data0_0, 0.0f);
    }
    int2 _S71 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(3));
    float4 color0_0 = layer_tex_1.Load(int3(_S71, int(0)));
    int2 _S72 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(4));
    float4 color1_0 = layer_tex_1.Load(int3(_S72, int(0)));
    if(paintKind_0 == int(2))
    {
        float2 _S73 = data0_0.xy;
        float2 delta_0 = data0_0.zw - _S73;
        float lenSq_0 = dot(delta_0, delta_0);
        float t_7;
        if(lenSq_0 > 1.00000001335143196e-10f)
        {
            t_7 = dot(rc_1 - _S73, delta_0) / lenSq_0;
        }
        else
        {
            t_7 = 0.0f;
        }
        int2 _S74 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(5));
        return PathPaintSample_x24init_0(mixGradient_0(color0_0, color1_0, wrapPaintT_0(t_7, layer_tex_1.Load(int3(_S74, int(0))).x)), 1.0f);
    }
    if(paintKind_0 == int(3))
    {
        return PathPaintSample_x24init_0(mixGradient_0(color0_0, color1_0, wrapPaintT_0(length(rc_1 - data0_0.xy) / max(abs(data0_0.z), 0.0000152587890625f), data0_0.w)), 1.0f);
    }
    if(paintKind_0 == int(6))
    {
        float2 d_1 = rc_1 - data0_0.xy;
        return PathPaintSample_x24init_0(mixGradient_0(color0_0, color1_0, wrapPaintT_0((atan2(d_1.y, d_1.x) - data0_0.z) * 0.15915493667125702f, data0_0.w)), 1.0f);
    }
    if(paintKind_0 == int(4))
    {
        int2 _S75 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(3));
        float4 data1_0 = layer_tex_1.Load(int3(_S75, int(0)));
        int2 _S76 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(5));
        float4 extra_0 = layer_tex_1.Load(int3(_S76, int(0)));
        float3 _S77 = float3(rc_1, 1.0f);
        return PathPaintSample_x24init_0(sampleImagePaintTex_0(image_tex_1, image_sampler_1, float2(wrapPaintT_0(dot(_S77, float3(data0_0.x, data0_0.y, data0_0.z)), extra_0.z) * extra_0.x, wrapPaintT_0(dot(_S77, float3(data1_0.x, data1_0.y, data1_0.z)), extra_0.w) * extra_0.y), int(data0_0.w + 0.5f), int(data1_0.w + 0.5f)), 0.0f);
    }
    return PathPaintSample_x24init_0(float4(1.0f, 0.0f, 1.0f, 1.0f), 0.0f);
}

float4 premultiplyColor_0(float4 color_2, float cov_8)
{
    float alpha_0 = color_2.w * cov_8;
    return float4(color_2.xyz * alpha_0, alpha_0);
}

struct PathCompositeSample_0
{
    float4 color_3;
    float gradient_2;
};

PathCompositeSample_0 PathCompositeSample_x24init_0(float4 color_4, float gradient_3)
{
    PathCompositeSample_0 _S78;
    _S78.color_3 = color_4;
    _S78.gradient_2 = gradient_3;
    return _S78;
}

PathCompositeSample_0 compositePathGroup_0(Texture2DArray<float4 > curve_tex_3, Texture2DArray<uint2 > band_tex_2, Texture2D<float4 > layer_tex_2, Texture2DArray<float4 > image_tex_2, SamplerState image_sampler_2, float2 rc_2, float2 epp_1, float2 ppe_7, int2 infoBase_1, float4 header_0, int texLayer_1, float4 tint_0, float coverage_exponent_3)
{
    bool _S79;
    int layer_count_0 = int(header_0.x + 0.5f);
    int composite_mode_0 = int(header_0.y + 0.5f);
    float4 _S80 = (float4)0.0f;
    PathPaintSample_0 _S81 = PathPaintSample_x24init_0(_S80, 0.0f);
    float4 result_0 = _S80;
    float fill_cov_0 = 0.0f;
    float stroke_cov_0 = 0.0f;
    PathPaintSample_0 fill_paint_0 = _S81;
    PathPaintSample_0 stroke_paint_0 = _S81;
    float has_gradient_0 = 0.0f;
    int l_0 = int(0);
    for(;;)
    {
        if(l_0 < layer_count_0)
        {
        }
        else
        {
            break;
        }
        int2 loc_3 = offsetLayerLoc_0(layer_tex_2, infoBase_1, int(1) + l_0 * int(6));
        float4 info_1 = layer_tex_2.Load(int3(loc_3, int(0)));
        int2 _S82 = offsetLayerLoc_0(layer_tex_2, loc_3, int(1));
        int packed_gx_0 = int(info_1.x);
        int _S83 = asint(info_1.z);
        float cov_9 = evalPathGlyphCoverage_0(curve_tex_3, band_tex_2, rc_2, epp_1, ppe_7, int2(packed_gx_0 & int(32767), int(info_1.y)), int2((_S83 >> int(16)) & int(65535), _S83 & int(65535)), layer_tex_2.Load(int3(_S82, int(0))), texLayer_1, (packed_gx_0 >> int(15)) & int(1), coverage_exponent_3);
        PathPaintSample_0 _S84 = samplePathPaint_0(layer_tex_2, image_tex_2, image_sampler_2, rc_2, loc_3, info_1);
        PathPaintSample_0 paint_0 = _S84;
        paint_0.color_0 = paint_0.color_0 * tint_0;
        if(composite_mode_0 == int(1))
        {
            _S79 = layer_count_0 >= int(2);
        }
        else
        {
            _S79 = false;
        }
        bool _S85;
        if(_S79)
        {
            _S85 = l_0 < int(2);
        }
        else
        {
            _S85 = false;
        }
        float fill_cov_1;
        if(_S85)
        {
            float stroke_cov_1;
            PathPaintSample_0 fill_paint_1;
            PathPaintSample_0 stroke_paint_1;
            if(l_0 == int(0))
            {
                fill_cov_1 = cov_9;
                stroke_cov_1 = stroke_cov_0;
                fill_paint_1 = paint_0;
                stroke_paint_1 = stroke_paint_0;
            }
            else
            {
                fill_cov_1 = fill_cov_0;
                stroke_cov_1 = cov_9;
                fill_paint_1 = fill_paint_0;
                stroke_paint_1 = paint_0;
            }
            fill_cov_0 = fill_cov_1;
            stroke_cov_0 = stroke_cov_1;
            fill_paint_0 = fill_paint_1;
            stroke_paint_0 = stroke_paint_1;
            l_0 = l_0 + int(1);
            continue;
        }
        bool _S86;
        if((paint_0.gradient_0) > 0.5f)
        {
            _S86 = cov_9 > 9.99999997475242708e-07f;
        }
        else
        {
            _S86 = false;
        }
        if(_S86)
        {
            fill_cov_1 = 1.0f;
        }
        else
        {
            fill_cov_1 = has_gradient_0;
        }
        float4 premul_0 = premultiplyColor_0(paint_0.color_0, cov_9);
        result_0 = premul_0 + result_0 * (1.0f - premul_0.w);
        has_gradient_0 = fill_cov_1;
        l_0 = l_0 + int(1);
    }
    if(composite_mode_0 == int(1))
    {
        _S79 = layer_count_0 >= int(2);
    }
    else
    {
        _S79 = false;
    }
    if(_S79)
    {
        float _S87 = min(fill_cov_0, stroke_cov_0);
        float _S88 = max(fill_cov_0 - _S87, 0.0f);
        if((fill_paint_0.gradient_0) > 0.5f)
        {
            _S79 = _S88 > 9.99999997475242708e-07f;
        }
        else
        {
            _S79 = false;
        }
        if(_S79)
        {
            has_gradient_0 = 1.0f;
        }
        if((stroke_paint_0.gradient_0) > 0.5f)
        {
            _S79 = _S87 > 9.99999997475242708e-07f;
        }
        else
        {
            _S79 = false;
        }
        if(_S79)
        {
            has_gradient_0 = 1.0f;
        }
        result_0 = result_0 + (premultiplyColor_0(fill_paint_0.color_0, _S88) + premultiplyColor_0(stroke_paint_0.color_0, _S87)) * (1.0f - result_0.w);
    }
    return PathCompositeSample_x24init_0(result_0, has_gradient_0);
}

float interleavedGradientNoise_0(float2 pixel_0)
{
    return frac(52.98291778564453125f * frac(dot(pixel_0, float2(0.06711056083440781f, 0.00583714991807938f))));
}

float srgbEncode_0(float c_0)
{
    float _S89;
    if(c_0 <= 0.00313080009073019f)
    {
        _S89 = c_0 * 12.92000007629394531f;
    }
    else
    {
        _S89 = 1.0549999475479126f * pow(c_0, 0.4166666567325592f) - 0.05499999970197678f;
    }
    return _S89;
}

float3 linearToSrgb_0(float3 color_5)
{
    return float3(srgbEncode_0(max(color_5.x, 0.0f)), srgbEncode_0(max(color_5.y, 0.0f)), srgbEncode_0(max(color_5.z, 0.0f)));
}

float srgbDecode_0(float c_1)
{
    float _S90;
    if(c_1 <= 0.04044999927282333f)
    {
        _S90 = c_1 / 12.92000007629394531f;
    }
    else
    {
        _S90 = pow((c_1 + 0.05499999970197678f) / 1.0549999475479126f, 2.40000009536743164f);
    }
    return _S90;
}

float3 srgbToLinear_0(float3 color_6)
{
    return float3(srgbDecode_0(color_6.x), srgbDecode_0(color_6.y), srgbDecode_0(color_6.z));
}

float4 ditherPremultipliedColor_0(float4 color_7, float2 frag_coord_0, float dither_scale_1)
{
    float _S91 = color_7.w;
    bool _S92;
    if(_S91 <= 0.0f)
    {
        _S92 = true;
    }
    else
    {
        _S92 = dither_scale_1 <= 0.0f;
    }
    if(_S92)
    {
        return color_7;
    }
    return float4(srgbToLinear_0(clamp(linearToSrgb_0(color_7.xyz) + (float3)((interleavedGradientNoise_0(frag_coord_0) - 0.5f) * (clamp(_S91, 0.0f, 1.0f) * dither_scale_1)), (float3)0.0f, (float3)1.0f)), _S91);
}

float4 srgbEncodePremultiplied_0(float4 premul_1)
{
    float _S93 = premul_1.w;
    if(_S93 <= 0.0f)
    {
        return (float4)0.0f;
    }
    return float4(linearToSrgb_0(premul_1.xyz * (1.0f / _S93)) * _S93, _S93);
}

struct PaintedVaryings_0
{
    float4 tint_1;
    float2 texcoord_0;
    float4 banding_1;
    int4 glyph_0;
};

struct PaintedParams_0
{
    int layer_base_1;
    int output_srgb_1;
    float coverage_exponent_4;
    float dither_scale_2;
    int mask_output_1;
};

float4 snailPaintedFragment_0(int expected_special_kind_0, PaintedVaryings_0 v_1, float2 frag_coord_1, Texture2DArray<float4 > curve_tex_4, Texture2DArray<uint2 > band_tex_3, Texture2D<float4 > layer_tex_3, Texture2DArray<float4 > image_tex_3, SamplerState image_sampler_3, PaintedParams_0 p_0)
{
    float2 epp_2 = (fwidth((v_1.texcoord_0)));
    float2 ppe_8 = 1.0f / max(epp_2, (float2)0.0000152587890625f);
    int _S94 = v_1.glyph_0.w;
    int special_kind_0 = _S94 & int(255);
    if(((_S94 >> int(8)) & int(255)) != int(255))
    {
        discard;
    }
    if(special_kind_0 != expected_special_kind_0)
    {
        discard;
    }
    int2 infoBase_2 = v_1.glyph_0.xy;
    float4 firstInfo_0 = layer_tex_3.Load(int3(infoBase_2, int(0)));
    float _S95 = firstInfo_0.w;
    if(_S95 >= 0.0f)
    {
        discard;
    }
    int texLayer_2 = p_0.layer_base_1 + int(v_1.banding_1.w);
    float4 emit_0;
    if(int(- _S95 + 0.5f) == int(5))
    {
        PathCompositeSample_0 result_1 = compositePathGroup_0(curve_tex_4, band_tex_3, layer_tex_3, image_tex_3, image_sampler_3, v_1.texcoord_0, epp_2, ppe_8, infoBase_2, firstInfo_0, texLayer_2, v_1.tint_1, p_0.coverage_exponent_4);
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
        if((p_0.mask_output_1) != int(0))
        {
            emit_0 = (float4)emit_0.w;
        }
        else
        {
            if((p_0.output_srgb_1) != int(0))
            {
                emit_0 = srgbEncodePremultiplied_0(emit_0);
            }
        }
        return emit_0;
    }
    int2 _S96 = offsetLayerLoc_0(layer_tex_3, infoBase_2, int(1));
    int packed_gx_1 = int(firstInfo_0.x);
    int _S97 = asint(firstInfo_0.z);
    float cov_10 = evalPathGlyphCoverage_0(curve_tex_4, band_tex_3, v_1.texcoord_0, epp_2, ppe_8, int2(packed_gx_1 & int(32767), int(firstInfo_0.y)), int2((_S97 >> int(16)) & int(65535), _S97 & int(65535)), layer_tex_3.Load(int3(_S96, int(0))), texLayer_2, (packed_gx_1 >> int(15)) & int(1), p_0.coverage_exponent_4);
    if(cov_10 < 0.00392156885936856f)
    {
        discard;
    }
    PathPaintSample_0 _S98 = samplePathPaint_0(layer_tex_3, image_tex_3, image_sampler_3, v_1.texcoord_0, infoBase_2, firstInfo_0);
    PathPaintSample_0 paint_1 = _S98;
    float4 _S99 = paint_1.color_0 * v_1.tint_1;
    paint_1.color_0 = _S99;
    float4 result_2 = premultiplyColor_0(_S99, cov_10);
    if((paint_1.gradient_0) > 0.5f)
    {
        emit_0 = ditherPremultipliedColor_0(result_2, frag_coord_1, p_0.dither_scale_2);
    }
    else
    {
        emit_0 = result_2;
    }
    if((p_0.mask_output_1) != int(0))
    {
        emit_0 = (float4)emit_0.w;
    }
    else
    {
        if((p_0.output_srgb_1) != int(0))
        {
            emit_0 = srgbEncodePremultiplied_0(emit_0);
        }
    }
    return emit_0;
}

struct VsOutput_0
{
    float4 position_0 : SV_Position;
    float4 color_8 : TEXCOORD0;
    float2 texcoord_1 : TEXCOORD1;
    nointerpolation float4 banding_2 : TEXCOORD2;
    nointerpolation int4 glyph_1 : TEXCOORD3;
    float4 tint_2 : TEXCOORD4;
};

float4 fragmentMain(VsOutput_0 input_0) : SV_TARGET
{
    PaintedVaryings_0 v_2;
    v_2.tint_1 = input_0.tint_2;
    v_2.texcoord_0 = input_0.texcoord_1;
    v_2.banding_1 = input_0.banding_2;
    v_2.glyph_0 = input_0.glyph_1;
    PaintedParams_0 p_1;
    p_1.layer_base_1 = pc_0.layer_base_0;
    p_1.output_srgb_1 = pc_0.output_srgb_0;
    p_1.coverage_exponent_4 = pc_0.coverage_exponent_0;
    p_1.dither_scale_2 = pc_0.dither_scale_0;
    p_1.mask_output_1 = pc_0.mask_output_0;
    float4 _S100 = snailPaintedFragment_0(int(0), v_2, input_0.position_0.xy, u_curve_tex_0, u_band_tex_0, u_layer_tex_0, u_image_tex_0, u_image_sampler_0, p_1);
    return _S100;
}


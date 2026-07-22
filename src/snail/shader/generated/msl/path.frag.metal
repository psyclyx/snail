#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;
float2 fwidth_0(float2 x_0)
{
    ;
}

struct PathPaintSample_0
{
    float4 color_0;
    float gradient_0;
};

PathPaintSample_0 PathPaintSample_x24init_0(float4 color_1, float gradient_1)
{
    thread PathPaintSample_0 _S1;
    (&_S1)->color_0 = color_1;
    (&_S1)->gradient_0 = gradient_1;
    return _S1;
}

int2 offsetLayerLoc_0(texture2d<float, access::sample> layer_tex_0, int2 base_0, int offset_0)
{
    thread uint uw_0;
    thread uint uh_0;
    (*((&uw_0)) = (layer_tex_0).get_width(0)),(*((&uh_0)) = (layer_tex_0).get_height(0));
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
    thread CoverageBandSpan_0 _S4;
    (&_S4)->first_0 = first_1;
    (&_S4)->last_0 = last_1;
    return _S4;
}

CoverageBandSpan_0 computeCoverageBandSpan_0(float coord_0, float eppAxis_0, float bandScale_0, float bandOffset_0, int bandMax_0)
{
    float center_0 = coord_0 * bandScale_0 + bandOffset_0;
    float _S5 = max(abs(eppAxis_0 * bandScale_0) * 0.5, 0.00000999999974738);
    int first_2 = clamp(int(center_0 - _S5), int(0), bandMax_0);
    return CoverageBandSpan_x24init_0(first_2, max(first_2, clamp(int(center_0 + _S5), int(0), bandMax_0)));
}

int2 calcBandLoc_0(int2 glyphLoc_0, uint offset_1)
{
    int _S6 = glyphLoc_0.x + int(offset_1);
    thread int2 loc_0 = int2(_S6, glyphLoc_0.y);
    loc_0.y = loc_0.y + (_S6 >> 12U);
    loc_0.x = (loc_0.x) & int(4095);
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
    thread int2 loc_1 = int2(_S7, base_1.y);
    loc_1.y = loc_1.y + (_S7 >> 12U);
    loc_1.x = (loc_1.x) & int(4095);
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

SegmentData_0 fetchSegment_0(texture2d_array<float, access::sample> curve_tex_0, int2 loc_2, int layer_0, int kind_1)
{
    int4 _S8 = int4(loc_2, layer_0, int(0));
    float4 tex0_0 = ((curve_tex_0).read(vec<uint,2>(((_S8)).xy), uint(((_S8)).z), uint(((_S8)).w)));
    int4 _S9 = int4(offsetCurveLoc_0(loc_2, int(1)), layer_0, int(0));
    float4 tex1_0 = ((curve_tex_0).read(vec<uint,2>(((_S9)).xy), uint(((_S9)).z), uint(((_S9)).w)));
    thread SegmentData_0 seg_0;
    (&seg_0)->kind_0 = kind_1;
    (&seg_0)->p0_0 = tex0_0.xy;
    (&seg_0)->p1_0 = tex0_0.zw;
    (&seg_0)->p2_0 = tex1_0.xy;
    (&seg_0)->p3_0 = tex1_0.zw;
    if(kind_1 == int(1))
    {
        int4 _S10 = int4(offsetCurveLoc_0(loc_2, int(2)), layer_0, int(0));
        float4 tex2_0 = ((curve_tex_0).read(vec<uint,2>(((_S10)).xy), uint(((_S10)).z), uint(((_S10)).w)));
        (&seg_0)->weights_0 = float3(tex2_0.w, tex2_0.x, tex2_0.y);
    }
    else
    {
        (&seg_0)->weights_0 = float3(1.0) ;
    }
    return seg_0;
}

float segmentMaxX_0(const SegmentData_0 thread* seg_1)
{
    int _S11 = seg_1->kind_0;
    if((seg_1->kind_0) == int(3))
    {
        return max(seg_1->p0_0.x, seg_1->p2_0.x);
    }
    if(_S11 == int(2))
    {
        return max(max(seg_1->p0_0.x, seg_1->p1_0.x), max(seg_1->p2_0.x, seg_1->p3_0.x));
    }
    return max(max(seg_1->p0_0.x, seg_1->p1_0.x), seg_1->p2_0.x);
}

float segmentMaxY_0(const SegmentData_0 thread* seg_2)
{
    int _S12 = seg_2->kind_0;
    if((seg_2->kind_0) == int(3))
    {
        return max(seg_2->p0_0.y, seg_2->p2_0.y);
    }
    if(_S12 == int(2))
    {
        return max(max(seg_2->p0_0.y, seg_2->p1_0.y), max(seg_2->p2_0.y, seg_2->p3_0.y));
    }
    return max(max(seg_2->p0_0.y, seg_2->p1_0.y), seg_2->p2_0.y);
}

float rootCodeCoord_0(float v_0)
{
    float _S13;
    if((abs(v_0)) <= 0.0000152587890625)
    {
        _S13 = 0.0;
    }
    else
    {
        _S13 = v_0;
    }
    return _S13;
}

uint calcRootCode_0(float y1_0, float y2_0, float y3_0)
{
    return (11892U >> ((((as_type<uint>((rootCodeCoord_0(y3_0)))) >> 29U) & 4U) | (((((as_type<uint>((rootCodeCoord_0(y2_0)))) >> 30U) & 2U) | (((as_type<uint>((rootCodeCoord_0(y1_0)))) >> 31U) & 4294967293U)) & 4294967291U))) & 257U;
}

float snapNearTangentSqrt_0(float disc_0, float b_0, float ac_0)
{
    float _S14;
    if(disc_0 <= (max(b_0 * b_0, abs(ac_0)) * 3.00000010611256585e-06))
    {
        _S14 = 0.0;
    }
    else
    {
        _S14 = sqrt(disc_0);
    }
    return _S14;
}

float2 solveQuadraticHorizDistances_0(float p0x_0, float p0y_0, float p1x_0, float p1y_0, float p2x_0, float p2y_0, float ppeX_0)
{
    float ax_0 = p0x_0 - p1x_0 * 2.0 + p2x_0;
    float ay_0 = p0y_0 - p1y_0 * 2.0 + p2y_0;
    float bx_0 = p0x_0 - p1x_0;
    float by_0 = p0y_0 - p1y_0;
    float t1_0;
    float t2_0;
    if((abs(ay_0)) < 0.0000152587890625)
    {
        if((abs(by_0)) < 0.0000152587890625)
        {
            t1_0 = 0.0;
        }
        else
        {
            t1_0 = p0y_0 * 0.5 / by_0;
        }
        t2_0 = t1_0;
    }
    else
    {
        float _S15 = ay_0 * p0y_0;
        float sq_0 = snapNearTangentSqrt_0(by_0 * by_0 - _S15, by_0, _S15);
        if(by_0 >= 0.0)
        {
            float q_0 = by_0 + sq_0;
            float _S16 = q_0 / ay_0;
            if((abs(q_0)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
            }
            else
            {
                t1_0 = p0y_0 / q_0;
            }
            t2_0 = _S16;
        }
        else
        {
            float q_1 = by_0 - sq_0;
            float _S17 = q_1 / ay_0;
            if((abs(q_1)) < 0.0000152587890625)
            {
                t1_0 = 0.0;
            }
            else
            {
                t1_0 = p0y_0 / q_1;
            }
            float _S18 = t1_0;
            t1_0 = _S17;
            t2_0 = _S18;
        }
    }
    float _S19 = bx_0 * 2.0;
    return float2(((ax_0 * t1_0 - _S19) * t1_0 + p0x_0) * ppeX_0, ((ax_0 * t2_0 - _S19) * t2_0 + p0x_0) * ppeX_0);
}

float2 solveQuadraticVertDistances_0(float p0x_1, float p0y_1, float p1x_1, float p1y_1, float p2x_1, float p2y_1, float ppeY_0)
{
    float ax_1 = p0x_1 - p1x_1 * 2.0 + p2x_1;
    float ay_1 = p0y_1 - p1y_1 * 2.0 + p2y_1;
    float bx_1 = p0x_1 - p1x_1;
    float by_1 = p0y_1 - p1y_1;
    float t1_1;
    float t2_1;
    if((abs(ax_1)) < 0.0000152587890625)
    {
        if((abs(bx_1)) < 0.0000152587890625)
        {
            t1_1 = 0.0;
        }
        else
        {
            t1_1 = p0x_1 * 0.5 / bx_1;
        }
        t2_1 = t1_1;
    }
    else
    {
        float _S20 = ax_1 * p0x_1;
        float sq_1 = snapNearTangentSqrt_0(bx_1 * bx_1 - _S20, bx_1, _S20);
        if(bx_1 >= 0.0)
        {
            float q_2 = bx_1 + sq_1;
            float _S21 = q_2 / ax_1;
            if((abs(q_2)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = p0x_1 / q_2;
            }
            t2_1 = _S21;
        }
        else
        {
            float q_3 = bx_1 - sq_1;
            float _S22 = q_3 / ax_1;
            if((abs(q_3)) < 0.0000152587890625)
            {
                t1_1 = 0.0;
            }
            else
            {
                t1_1 = p0x_1 / q_3;
            }
            float _S23 = t1_1;
            t1_1 = _S22;
            t2_1 = _S23;
        }
    }
    float _S24 = by_1 * 2.0;
    return float2(((ay_1 * t1_1 - _S24) * t1_1 + p0y_1) * ppeY_0, ((ay_1 * t2_1 - _S24) * t2_1 + p0y_1) * ppeY_0);
}

void appendCoverageContribution_0(float thread* cov_0, float thread* wgt_0, float distance_0, float sign_0)
{
    *cov_0 = *cov_0 + sign_0 * clamp(distance_0 + 0.5, 0.0, 1.0);
    *wgt_0 = max(*wgt_0, clamp(1.0 - abs(distance_0) * 2.0, 0.0, 1.0));
    return;
}

void appendCoverageContribution_1(float thread* cov_1, float thread* wgt_1, float distance_1, float sign_1)
{
    *cov_1 = *cov_1 + sign_1 * clamp(distance_1 + 0.5, 0.0, 1.0);
    *wgt_1 = max(*wgt_1, clamp(1.0 - abs(distance_1) * 2.0, 0.0, 1.0));
    return;
}

void accumulateLineCoverage_0(float thread* cov_2, float thread* wgt_2, float p0x_2, float p0y_2, float p2x_2, float p2y_2, float ppe_0, bool horizontal_0)
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
    if(((rootCodeCoord_0(rootAxis0_0)) < 0.0) == ((rootCodeCoord_0(rootAxis2_0)) < 0.0))
    {
        return;
    }
    float denom_0 = rootAxis2_0 - rootAxis0_0;
    if((abs(denom_0)) < 1.00000001335143196e-10)
    {
        return;
    }
    float t_0 = clamp(- rootAxis0_0 / denom_0, 0.0, 1.0);
    float derivativeAxis_0;
    if(horizontal_0)
    {
        derivativeAxis_0 = p2y_2 - p0y_2;
    }
    else
    {
        derivativeAxis_0 = p0x_2 - p2x_2;
    }
    if((abs(derivativeAxis_0)) <= 0.00000999999974738)
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
    float distance_2 = rootAxis0_0 * ppe_0;
    if(derivativeAxis_0 > 0.0)
    {
        rootAxis0_0 = 1.0;
    }
    else
    {
        rootAxis0_0 = -1.0;
    }
    appendCoverageContribution_1(cov_2, wgt_2, distance_2, rootAxis0_0);
    return;
}

bool rootHullCanCross4_0(float p0_1, float p1_1, float p2_1, float p3_1, float sampleRoot_0)
{
    float _S25 = max(max(p0_1, p1_1), max(p2_1, p3_1));
    bool _S26;
    if((min(min(p0_1, p1_1), min(p2_1, p3_1)) - sampleRoot_0) <= 0.0000152587890625)
    {
        _S26 = (_S25 - sampleRoot_0) >= -0.0000152587890625;
    }
    else
    {
        _S26 = false;
    }
    return _S26;
}

bool rootHullCanCross3_0(float p0_2, float p1_2, float p2_2, float sampleRoot_1)
{
    float _S27 = max(max(p0_2, p1_2), p2_2);
    bool _S28;
    if((min(min(p0_2, p1_2), p2_2) - sampleRoot_1) <= 0.0000152587890625)
    {
        _S28 = (_S27 - sampleRoot_1) >= -0.0000152587890625;
    }
    else
    {
        _S28 = false;
    }
    return _S28;
}

bool segmentRootHullCanCross_0(const SegmentData_0 thread* seg_3, float2 sampleRc_0, bool horizontal_1)
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
    float _S29;
    float _S30;
    float _S31;
    if((seg_3->kind_0) == int(2))
    {
        if(horizontal_1)
        {
            _S29 = seg_3->p0_0.y;
        }
        else
        {
            _S29 = seg_3->p0_0.x;
        }
        if(horizontal_1)
        {
            _S30 = seg_3->p1_0.y;
        }
        else
        {
            _S30 = seg_3->p1_0.x;
        }
        if(horizontal_1)
        {
            _S31 = seg_3->p2_0.y;
        }
        else
        {
            _S31 = seg_3->p2_0.x;
        }
        float _S32;
        if(horizontal_1)
        {
            _S32 = seg_3->p3_0.y;
        }
        else
        {
            _S32 = seg_3->p3_0.x;
        }
        return rootHullCanCross4_0(_S29, _S30, _S31, _S32, sampleRoot_2);
    }
    if(horizontal_1)
    {
        _S29 = seg_3->p0_0.y;
    }
    else
    {
        _S29 = seg_3->p0_0.x;
    }
    if(horizontal_1)
    {
        _S30 = seg_3->p1_0.y;
    }
    else
    {
        _S30 = seg_3->p1_0.x;
    }
    if(horizontal_1)
    {
        _S31 = seg_3->p2_0.y;
    }
    else
    {
        _S31 = seg_3->p2_0.x;
    }
    return rootHullCanCross3_0(_S29, _S30, _S31, sampleRoot_2);
}

float distToUnitInterval_0(float t_1)
{
    return max(max(0.0, - t_1), t_1 - 1.0);
}

float segmentEndRootDelta_0(const SegmentData_0 thread* seg_4, float2 sampleRc_1, bool horizontal_2)
{
    float _S33;
    if((seg_4->kind_0) == int(2))
    {
        if(horizontal_2)
        {
            _S33 = seg_4->p3_0.y - sampleRc_1.y;
        }
        else
        {
            _S33 = seg_4->p3_0.x - sampleRc_1.x;
        }
        return _S33;
    }
    if(horizontal_2)
    {
        _S33 = seg_4->p2_0.y - sampleRc_1.y;
    }
    else
    {
        _S33 = seg_4->p2_0.x - sampleRc_1.x;
    }
    return _S33;
}

void accumulateConicRoot_0(float thread* cov_3, float thread* wgt_3, float t_2, float endRootDelta_0, float sampleAlong_0, float ppe_1, bool horizontal_3, float rootA_0, float rootB_0, float rootC_0, float alongA_0, float alongB_0, float alongC_0, float denA_0, float denB_0, float denC_0)
{
    float _S34 = max((denA_0 * t_2 + denB_0) * t_2 + denC_0, 0.0000152587890625);
    float along_0 = ((alongA_0 * t_2 + alongB_0) * t_2 + alongC_0) / _S34;
    float derivAxis_0 = ((2.0 * rootA_0 * t_2 + rootB_0) * _S34 - ((rootA_0 * t_2 + rootB_0) * t_2 + rootC_0) * (2.0 * denA_0 * t_2 + denB_0)) / (_S34 * _S34);
    float derivAxis_1;
    if(!horizontal_3)
    {
        derivAxis_1 = - derivAxis_0;
    }
    else
    {
        derivAxis_1 = derivAxis_0;
    }
    if((abs(derivAxis_1)) <= 0.00000999999974738)
    {
        return;
    }
    float dist_0 = (along_0 - sampleAlong_0) * ppe_1;
    if(derivAxis_1 > 0.0)
    {
        derivAxis_1 = 1.0;
    }
    else
    {
        derivAxis_1 = -1.0;
    }
    appendCoverageContribution_1(cov_3, wgt_3, dist_0, derivAxis_1);
    return;
}

void accumulateConicCoverage_0(float thread* cov_4, float thread* wgt_4, const SegmentData_0 thread* seg_5, float2 sampleRc_2, float ppe_2, bool horizontal_4)
{
    bool _S35 = segmentRootHullCanCross_0(seg_5, sampleRc_2, horizontal_4);
    if(!_S35)
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
        p0Root_0 = seg_5->p0_0.y;
    }
    else
    {
        p0Root_0 = seg_5->p0_0.x;
    }
    float p1Root_0;
    if(horizontal_4)
    {
        p1Root_0 = seg_5->p1_0.y;
    }
    else
    {
        p1Root_0 = seg_5->p1_0.x;
    }
    float p2Root_0;
    if(horizontal_4)
    {
        p2Root_0 = seg_5->p2_0.y;
    }
    else
    {
        p2Root_0 = seg_5->p2_0.x;
    }
    float p0Along_0;
    if(horizontal_4)
    {
        p0Along_0 = seg_5->p0_0.x;
    }
    else
    {
        p0Along_0 = seg_5->p0_0.y;
    }
    float p1Along_0;
    if(horizontal_4)
    {
        p1Along_0 = seg_5->p1_0.x;
    }
    else
    {
        p1Along_0 = seg_5->p1_0.y;
    }
    float p2Along_0;
    if(horizontal_4)
    {
        p2Along_0 = seg_5->p2_0.x;
    }
    else
    {
        p2Along_0 = seg_5->p2_0.y;
    }
    float _S36 = seg_5->weights_0.x;
    float c0_0 = _S36 * (p0Root_0 - sampleRoot_3);
    float _S37 = seg_5->weights_0.y;
    float c1_0 = _S37 * (p1Root_0 - sampleRoot_3);
    float _S38 = seg_5->weights_0.z;
    float c2_0 = _S38 * (p2Root_0 - sampleRoot_3);
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
    float quadA_0 = c0_0 - 2.0 * c1_0 + c2_0;
    float quadB_0 = 2.0 * (c1_0 - c0_0);
    float cand1_0;
    float cand0_0;
    int ncand_0;
    if((abs(quadA_0)) < 0.0000152587890625)
    {
        if((abs(quadB_0)) >= 0.0000152587890625)
        {
            float _S39 = - c0_0 / quadB_0;
            ncand_0 = int(1);
            cand1_0 = _S39;
        }
        else
        {
            ncand_0 = int(0);
            cand1_0 = 0.0;
        }
        float _S40 = cand1_0;
        cand1_0 = 0.0;
        cand0_0 = _S40;
    }
    else
    {
        float sqrtDisc_0 = sqrt(max(quadB_0 * quadB_0 - 4.0 * quadA_0 * c0_0, 0.0));
        float inv2a_0 = 0.5 / quadA_0;
        float _S41 = - quadB_0;
        float _S42 = (_S41 - sqrtDisc_0) * inv2a_0;
        float _S43 = (_S41 + sqrtDisc_0) * inv2a_0;
        ncand_0 = int(2);
        cand1_0 = _S43;
        cand0_0 = _S42;
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
        bool _S44;
        if(ncand_0 == int(2))
        {
            _S44 = (distToUnitInterval_0(cand1_0)) < (distToUnitInterval_0(cand0_0));
        }
        else
        {
            _S44 = false;
        }
        if(_S44)
        {
            root0_0 = cand1_0;
        }
        else
        {
            root0_0 = cand0_0;
        }
        root0_0 = clamp(root0_0, 0.0, 1.0);
        rootCount_0 = int(1);
        root1_0 = 0.0;
    }
    else
    {
        float _S45 = clamp(cand1_0, 0.0, 1.0);
        root0_0 = clamp(cand0_0, 0.0, 1.0);
        rootCount_0 = int(2);
        root1_0 = _S45;
    }
    float _S46 = p0Root_0 * _S36;
    float rootA_1 = _S46 - 2.0 * p1Root_0 * _S37 + p2Root_0 * _S38;
    float rootB_1 = 2.0 * (p1Root_0 * _S37 - _S46);
    float _S47 = p0Along_0 * _S36;
    float alongA_1 = _S47 - 2.0 * p1Along_0 * _S37 + p2Along_0 * _S38;
    float alongB_1 = 2.0 * (p1Along_0 * _S37 - _S47);
    float denA_1 = _S36 - 2.0 * _S37 + _S38;
    float denB_1 = 2.0 * (_S37 - _S36);
    float _S48 = segmentEndRootDelta_0(seg_5, sampleRc_2, horizontal_4);
    accumulateConicRoot_0(cov_4, wgt_4, root0_0, _S48, sampleAlong_1, ppe_2, horizontal_4, rootA_1, rootB_1, _S46, alongA_1, alongB_1, _S47, denA_1, denB_1, _S36);
    if(rootCount_0 == int(2))
    {
        accumulateConicRoot_0(cov_4, wgt_4, root1_0, _S48, sampleAlong_1, ppe_2, horizontal_4, rootA_1, rootB_1, _S46, alongA_1, alongB_1, _S47, denA_1, denB_1, _S36);
    }
    return;
}

bool solveMonotonicCubicRoot_0(float a_0, float b_1, float cVal_0, float d_0, float endDelta_0, float thread* tOut_0)
{
    *tOut_0 = 0.0;
    bool _S49;
    if(d_0 < -0.0000152587890625)
    {
        _S49 = endDelta_0 < -0.0000152587890625;
    }
    else
    {
        _S49 = false;
    }
    if(_S49)
    {
        _S49 = true;
    }
    else
    {
        if(d_0 > 0.0000152587890625)
        {
            _S49 = endDelta_0 > 0.0000152587890625;
        }
        else
        {
            _S49 = false;
        }
    }
    if(_S49)
    {
        return false;
    }
    bool _S50 = endDelta_0 >= d_0;
    float t_3 = 0.5;
    float lo_0 = 0.0;
    float hi_0 = 1.0;
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
        if(_S50)
        {
            _S49 = f_0 < 0.0;
        }
        else
        {
            _S49 = false;
        }
        bool _S51;
        if(_S49)
        {
            _S51 = true;
        }
        else
        {
            if(!_S50)
            {
                _S51 = f_0 > 0.0;
            }
            else
            {
                _S51 = false;
            }
        }
        if(_S51)
        {
            lo_0 = t_3;
        }
        else
        {
            hi_0 = t_3;
        }
        float deriv_0 = (3.0 * a_0 * t_3 + 2.0 * b_1) * t_3 + cVal_0;
        float _S52 = (lo_0 + hi_0) * 0.5;
        float next_0;
        if((abs(deriv_0)) >= 9.99999997475242708e-07)
        {
            float newton_0 = t_3 - f_0 / deriv_0;
            bool _S53;
            if(newton_0 > lo_0)
            {
                _S53 = newton_0 < hi_0;
            }
            else
            {
                _S53 = false;
            }
            if(_S53)
            {
                next_0 = newton_0;
            }
            else
            {
                next_0 = _S52;
            }
        }
        else
        {
            next_0 = _S52;
        }
        int _S54 = i_0 + int(1);
        t_3 = next_0;
        i_0 = _S54;
    }
    *tOut_0 = t_3;
    return true;
}

void accumulateCubicCoverage_0(float thread* cov_5, float thread* wgt_5, const SegmentData_0 thread* seg_6, float2 sampleRc_3, float ppe_3, bool horizontal_5)
{
    bool _S55 = segmentRootHullCanCross_0(seg_6, sampleRc_3, horizontal_5);
    if(!_S55)
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
        p0Root_1 = seg_6->p0_0.y;
    }
    else
    {
        p0Root_1 = seg_6->p0_0.x;
    }
    float p1Root_1;
    if(horizontal_5)
    {
        p1Root_1 = seg_6->p1_0.y;
    }
    else
    {
        p1Root_1 = seg_6->p1_0.x;
    }
    float p2Root_1;
    if(horizontal_5)
    {
        p2Root_1 = seg_6->p2_0.y;
    }
    else
    {
        p2Root_1 = seg_6->p2_0.x;
    }
    float p3Root_0;
    if(horizontal_5)
    {
        p3Root_0 = seg_6->p3_0.y;
    }
    else
    {
        p3Root_0 = seg_6->p3_0.x;
    }
    float p0Along_1;
    if(horizontal_5)
    {
        p0Along_1 = seg_6->p0_0.x;
    }
    else
    {
        p0Along_1 = seg_6->p0_0.y;
    }
    float p1Along_1;
    if(horizontal_5)
    {
        p1Along_1 = seg_6->p1_0.x;
    }
    else
    {
        p1Along_1 = seg_6->p1_0.y;
    }
    float p2Along_1;
    if(horizontal_5)
    {
        p2Along_1 = seg_6->p2_0.x;
    }
    else
    {
        p2Along_1 = seg_6->p2_0.y;
    }
    float p3Along_0;
    if(horizontal_5)
    {
        p3Along_0 = seg_6->p3_0.x;
    }
    else
    {
        p3Along_0 = seg_6->p3_0.y;
    }
    float _S56 = 3.0 * p1Root_1;
    float _S57 = 3.0 * p2Root_1;
    float rootA_2 = - p0Root_1 + _S56 - _S57 + p3Root_0;
    float rootB_2 = 3.0 * p0Root_1 - 6.0 * p1Root_1 + _S57;
    float rootC_1 = -3.0 * p0Root_1 + _S56;
    float startDelta_0 = p0Root_1 - sampleRoot_4;
    float endDelta_1 = p3Root_0 - sampleRoot_4;
    if(((rootCodeCoord_0(startDelta_0)) < 0.0) == ((rootCodeCoord_0(endDelta_1)) < 0.0))
    {
        return;
    }
    thread float t_4 = 0.0;
    if((abs(startDelta_0)) <= 0.0000152587890625)
    {
        t_4 = 0.0;
    }
    else
    {
        if((abs(endDelta_1)) <= 0.0000152587890625)
        {
            t_4 = 1.0;
        }
        else
        {
            bool _S58 = solveMonotonicCubicRoot_0(rootA_2, rootB_2, rootC_1, startDelta_0, endDelta_1, &t_4);
            if(!_S58)
            {
                return;
            }
        }
    }
    float _S59 = 3.0 * p1Along_1;
    float _S60 = 3.0 * p2Along_1;
    float alongA_2 = - p0Along_1 + _S59 - _S60 + p3Along_0;
    float alongB_2 = 3.0 * p0Along_1 - 6.0 * p1Along_1 + _S60;
    float alongC_1 = -3.0 * p0Along_1 + _S59;
    float along_1;
    if(t_4 == 1.0)
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
    if(derivAxis_2 > 0.0)
    {
        sampleRoot_4 = 1.0;
    }
    else
    {
        sampleRoot_4 = -1.0;
    }
    appendCoverageContribution_0(cov_5, wgt_5, dist_1, sampleRoot_4);
    return;
}

bool accumulateAxisCoverageSegment_0(float thread* cov_6, float thread* wgt_6, float2 sampleRc_4, float ppe_4, const SegmentData_0 thread* seg_7, bool horizontal_6)
{
    float maxCoord_0;
    if(horizontal_6)
    {
        float _S61 = segmentMaxX_0(seg_7);
        maxCoord_0 = _S61 - sampleRc_4.x;
    }
    else
    {
        float _S62 = segmentMaxY_0(seg_7);
        maxCoord_0 = _S62 - sampleRc_4.y;
    }
    if((maxCoord_0 * ppe_4) < -0.5)
    {
        return false;
    }
    int _S63 = seg_7->kind_0;
    if((seg_7->kind_0) == int(0))
    {
        float _S64 = sampleRc_4.x;
        float p0x_3 = seg_7->p0_0.x - _S64;
        float _S65 = sampleRc_4.y;
        float p0y_3 = seg_7->p0_0.y - _S65;
        float p1x_2 = seg_7->p1_0.x - _S64;
        float p1y_2 = seg_7->p1_0.y - _S65;
        float p2x_3 = seg_7->p2_0.x - _S64;
        float p2y_3 = seg_7->p2_0.y - _S65;
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
            float _S66 = roots_0.x;
            if(horizontal_6)
            {
                maxCoord_0 = 1.0;
            }
            else
            {
                maxCoord_0 = -1.0;
            }
            appendCoverageContribution_0(cov_6, wgt_6, _S66, maxCoord_0);
        }
        if(code_1 > 1U)
        {
            float _S67 = roots_0.y;
            if(horizontal_6)
            {
                maxCoord_0 = -1.0;
            }
            else
            {
                maxCoord_0 = 1.0;
            }
            appendCoverageContribution_0(cov_6, wgt_6, _S67, maxCoord_0);
        }
        return true;
    }
    if(_S63 == int(3))
    {
        float _S68 = sampleRc_4.x;
        float _S69 = sampleRc_4.y;
        accumulateLineCoverage_0(cov_6, wgt_6, seg_7->p0_0.x - _S68, seg_7->p0_0.y - _S69, seg_7->p2_0.x - _S68, seg_7->p2_0.y - _S69, ppe_4, horizontal_6);
        return true;
    }
    if(_S63 == int(1))
    {
        accumulateConicCoverage_0(cov_6, wgt_6, seg_7, sampleRc_4, ppe_4, horizontal_6);
        return true;
    }
    accumulateCubicCoverage_0(cov_6, wgt_6, seg_7, sampleRc_4, ppe_4, horizontal_6);
    return true;
}

float2 evalAxisCoverageBands_0(texture2d_array<float, access::sample> curve_tex_1, texture2d_array<uint, access::sample> band_tex_0, float2 sampleRc_5, float ppe_5, int2 gLoc_0, int headerBase_0, int firstBand_0, int lastBand_0, int layer_1, bool horizontal_7)
{
    thread float cov_7 = 0.0;
    thread float wgt_7 = 0.0;
    bool _S70 = firstBand_0 != lastBand_0;
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
        int4 _S71 = int4(calcBandLoc_0(gLoc_0, uint(headerBase_0 + band_0)), layer_1, int(0));
        uint2 bd_0 = ((band_tex_0).read(vec<uint,2>(((_S71)).xy), uint(((_S71)).z), uint(((_S71)).w)).xy).xy;
        int2 _S72 = calcBandLoc_0(gLoc_0, bd_0.y);
        int _S73 = int(bd_0.x);
        int i_1 = int(0);
        for(;;)
        {
            if(i_1 < _S73)
            {
            }
            else
            {
                break;
            }
            int4 _S74 = int4(calcBandLoc_0(_S72, uint(i_1)), layer_1, int(0));
            uint2 ref_3 = ((band_tex_0).read(vec<uint,2>(((_S74)).xy), uint(((_S74)).z), uint(((_S74)).w)).xy).xy;
            if(_S70)
            {
                if(band_0 != (max(decodeBandCurveFirstMemberCommon_0(ref_3), firstBand_0)))
                {
                    i_1 = i_1 + int(1);
                    continue;
                }
            }
            thread SegmentData_0 _S75 = fetchSegment_0(curve_tex_1, decodeBandCurveLocCommon_0(ref_3), layer_1, decodeBandCurveKindCommon_0(ref_3));
            bool _S76 = accumulateAxisCoverageSegment_0(&cov_7, &wgt_7, sampleRc_5, ppe_5, &_S75, horizontal_7);
            if(!_S76)
            {
                break;
            }
            i_1 = i_1 + int(1);
        }
        band_0 = band_0 + int(1);
    }
    return float2(cov_7, wgt_7);
}

float applyFillRule_0(float winding_0, int fill_rule_mode_0)
{
    if(fill_rule_mode_0 == int(1))
    {
        return 1.0 - abs(fract(winding_0 * 0.5) * 2.0 - 1.0);
    }
    return abs(winding_0);
}

float applyCoverageTransfer_0(float cov_8, float coverage_exponent_0)
{
    float clamped_0 = clamp(cov_8, 0.0, 1.0);
    float _S77 = max(coverage_exponent_0, 0.0000152587890625);
    float _S78;
    if((abs(_S77 - 1.0)) <= 9.99999997475242708e-07)
    {
        _S78 = clamped_0;
    }
    else
    {
        _S78 = pow(clamped_0, _S77);
    }
    return _S78;
}

float evalPathGlyphCoverage_0(texture2d_array<float, access::sample> curve_tex_2, texture2d_array<uint, access::sample> band_tex_1, float2 rc_0, float2 epp_0, float2 ppe_6, int2 gLoc_1, int2 bandMax_1, float4 banding_0, int texLayer_0, int fill_rule_0, float coverage_exponent_1)
{
    int _S79 = bandMax_1.y;
    CoverageBandSpan_0 hSpan_0 = computeCoverageBandSpan_0(rc_0.y, epp_0.y, banding_0.y, banding_0.w, _S79);
    CoverageBandSpan_0 vSpan_0 = computeCoverageBandSpan_0(rc_0.x, epp_0.x, banding_0.x, banding_0.z, bandMax_1.x);
    float2 horiz_0 = evalAxisCoverageBands_0(curve_tex_2, band_tex_1, rc_0, ppe_6.x, gLoc_1, int(0), hSpan_0.first_0, hSpan_0.last_0, texLayer_0, true);
    float2 vert_0 = evalAxisCoverageBands_0(curve_tex_2, band_tex_1, rc_0, ppe_6.y, gLoc_1, _S79 + int(1), vSpan_0.first_0, vSpan_0.last_0, texLayer_0, false);
    float _S80 = horiz_0.y;
    float _S81 = vert_0.y;
    float _S82 = horiz_0.x;
    float _S83 = vert_0.x;
    return applyCoverageTransfer_0(max(applyFillRule_0((_S82 * _S80 + _S83 * _S81) / max(_S80 + _S81, 0.0000152587890625), fill_rule_0), min(applyFillRule_0(_S82, fill_rule_0), applyFillRule_0(_S83, fill_rule_0))), coverage_exponent_1);
}

float wrapPaintT_0(float t_5, float extendMode_0)
{
    int mode_0 = int(extendMode_0 + 0.5);
    if(mode_0 == int(1))
    {
        return fract(t_5);
    }
    if(mode_0 == int(2))
    {
        float reflected_0 = t_5 - 2.0 * floor(t_5 / 2.0);
        float reflected_1;
        if(reflected_0 < 0.0)
        {
            reflected_1 = reflected_0 + 2.0;
        }
        else
        {
            reflected_1 = reflected_0;
        }
        return 1.0 - abs(reflected_1 - 1.0);
    }
    return clamp(t_5, 0.0, 1.0);
}

float4 mixGradient_0(float4 c0_1, float4 c1_1, float t_6)
{
    return mix(c0_1, c1_1, float4(t_6) );
}

float4 sampleImagePaintTex_0(texture2d_array<float, access::sample> image_tex_0, sampler image_sampler_0, float2 uv_0, int layer_2, int filterMode_0)
{
    if(filterMode_0 == int(1))
    {
        thread uint uw_1;
        thread uint uh_1;
        thread uint ue_0;
        (*((&uw_1)) = (image_tex_0).get_width(0)),(*((&uh_1)) = (image_tex_0).get_height(0)),(*((&ue_0)) = (image_tex_0).get_array_size());
        int2 size_0 = int2(int(uw_1), int(uh_1));
        int4 _S84 = int4(clamp(int2(uv_0 * float2(size_0)), int2(int(0)) , size_0 - int2(int(1)) ), layer_2, int(0));
        return ((image_tex_0).read(vec<uint,2>(((_S84)).xy), uint(((_S84)).z), uint(((_S84)).w)));
    }
    float3 _S85 = float3(uv_0, float(layer_2));
    return ((image_tex_0).sample((image_sampler_0), ((_S85)).xy, uint(((_S85)).z)));
}

PathPaintSample_0 samplePathPaint_0(texture2d<float, access::sample> layer_tex_1, texture2d_array<float, access::sample> image_tex_1, sampler image_sampler_1, float2 rc_1, int2 infoBase_0, float4 info_0)
{
    int paintKind_0 = int(- info_0.w + 0.5);
    int2 _S86 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(2));
    int3 _S87 = int3(_S86, int(0));
    float4 data0_0 = ((layer_tex_1).read(vec<uint,2>(((_S87)).xy), uint(((_S87)).z)));
    if(paintKind_0 == int(1))
    {
        return PathPaintSample_x24init_0(data0_0, 0.0);
    }
    int2 _S88 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(3));
    int3 _S89 = int3(_S88, int(0));
    float4 color0_0 = ((layer_tex_1).read(vec<uint,2>(((_S89)).xy), uint(((_S89)).z)));
    int2 _S90 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(4));
    int3 _S91 = int3(_S90, int(0));
    float4 color1_0 = ((layer_tex_1).read(vec<uint,2>(((_S91)).xy), uint(((_S91)).z)));
    if(paintKind_0 == int(2))
    {
        float2 _S92 = data0_0.xy;
        float2 delta_0 = data0_0.zw - _S92;
        float lenSq_0 = dot(delta_0, delta_0);
        float t_7;
        if(lenSq_0 > 1.00000001335143196e-10)
        {
            t_7 = dot(rc_1 - _S92, delta_0) / lenSq_0;
        }
        else
        {
            t_7 = 0.0;
        }
        int2 _S93 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(5));
        int3 _S94 = int3(_S93, int(0));
        return PathPaintSample_x24init_0(mixGradient_0(color0_0, color1_0, wrapPaintT_0(t_7, ((layer_tex_1).read(vec<uint,2>(((_S94)).xy), uint(((_S94)).z))).x)), 1.0);
    }
    if(paintKind_0 == int(3))
    {
        return PathPaintSample_x24init_0(mixGradient_0(color0_0, color1_0, wrapPaintT_0(length(rc_1 - data0_0.xy) / max(abs(data0_0.z), 0.0000152587890625), data0_0.w)), 1.0);
    }
    if(paintKind_0 == int(6))
    {
        float2 d_1 = rc_1 - data0_0.xy;
        return PathPaintSample_x24init_0(mixGradient_0(color0_0, color1_0, wrapPaintT_0((atan2(d_1.y, d_1.x) - data0_0.z) * 0.15915493667125702, data0_0.w)), 1.0);
    }
    if(paintKind_0 == int(4))
    {
        int2 _S95 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(3));
        int3 _S96 = int3(_S95, int(0));
        float4 data1_0 = ((layer_tex_1).read(vec<uint,2>(((_S96)).xy), uint(((_S96)).z)));
        int2 _S97 = offsetLayerLoc_0(layer_tex_1, infoBase_0, int(5));
        int3 _S98 = int3(_S97, int(0));
        float4 extra_0 = ((layer_tex_1).read(vec<uint,2>(((_S98)).xy), uint(((_S98)).z)));
        float3 _S99 = float3(rc_1, 1.0);
        return PathPaintSample_x24init_0(sampleImagePaintTex_0(image_tex_1, image_sampler_1, float2(wrapPaintT_0(dot(_S99, float3(data0_0.x, data0_0.y, data0_0.z)), extra_0.z) * extra_0.x, wrapPaintT_0(dot(_S99, float3(data1_0.x, data1_0.y, data1_0.z)), extra_0.w) * extra_0.y), int(data0_0.w + 0.5), int(data1_0.w + 0.5)), 0.0);
    }
    return PathPaintSample_x24init_0(float4(1.0, 0.0, 1.0, 1.0), 0.0);
}

float4 premultiplyColor_0(float4 color_2, float cov_9)
{
    float alpha_0 = color_2.w * cov_9;
    return float4(color_2.xyz * float3(alpha_0) , alpha_0);
}

struct PathCompositeSample_0
{
    float4 color_3;
    float gradient_2;
};

PathCompositeSample_0 PathCompositeSample_x24init_0(float4 color_4, float gradient_3)
{
    thread PathCompositeSample_0 _S100;
    (&_S100)->color_3 = color_4;
    (&_S100)->gradient_2 = gradient_3;
    return _S100;
}

PathCompositeSample_0 compositePathGroup_0(texture2d_array<float, access::sample> curve_tex_3, texture2d_array<uint, access::sample> band_tex_2, texture2d<float, access::sample> layer_tex_2, texture2d_array<float, access::sample> image_tex_2, sampler image_sampler_2, float2 rc_2, float2 epp_1, float2 ppe_7, int2 infoBase_1, float4 header_0, int texLayer_1, float4 tint_0, float coverage_exponent_2)
{
    bool _S101;
    int layer_count_0 = int(header_0.x + 0.5);
    int composite_mode_0 = int(header_0.y + 0.5);
    float4 _S102 = float4(0.0) ;
    PathPaintSample_0 _S103 = PathPaintSample_x24init_0(_S102, 0.0);
    float4 result_0 = _S102;
    float fill_cov_0 = 0.0;
    float stroke_cov_0 = 0.0;
    PathPaintSample_0 fill_paint_0 = _S103;
    PathPaintSample_0 stroke_paint_0 = _S103;
    float has_gradient_0 = 0.0;
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
        int3 _S104 = int3(loc_3, int(0));
        float4 info_1 = ((layer_tex_2).read(vec<uint,2>(((_S104)).xy), uint(((_S104)).z)));
        int2 _S105 = offsetLayerLoc_0(layer_tex_2, loc_3, int(1));
        int3 _S106 = int3(_S105, int(0));
        int packed_gx_0 = int(info_1.x);
        int _S107 = (as_type<int>((info_1.z)));
        float cov_10 = evalPathGlyphCoverage_0(curve_tex_3, band_tex_2, rc_2, epp_1, ppe_7, int2(packed_gx_0 & int(32767), int(info_1.y)), int2((_S107 >> 16U) & int(65535), _S107 & int(65535)), ((layer_tex_2).read(vec<uint,2>(((_S106)).xy), uint(((_S106)).z))), texLayer_1, (packed_gx_0 >> 15U) & int(1), coverage_exponent_2);
        PathPaintSample_0 _S108 = samplePathPaint_0(layer_tex_2, image_tex_2, image_sampler_2, rc_2, loc_3, info_1);
        thread PathPaintSample_0 paint_0 = _S108;
        (&paint_0)->color_0 = (&paint_0)->color_0 * tint_0;
        if(composite_mode_0 == int(1))
        {
            _S101 = layer_count_0 >= int(2);
        }
        else
        {
            _S101 = false;
        }
        bool _S109;
        if(_S101)
        {
            _S109 = l_0 < int(2);
        }
        else
        {
            _S109 = false;
        }
        float fill_cov_1;
        if(_S109)
        {
            float stroke_cov_1;
            PathPaintSample_0 fill_paint_1;
            PathPaintSample_0 stroke_paint_1;
            if(l_0 == int(0))
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
            l_0 = l_0 + int(1);
            continue;
        }
        bool _S110;
        if(((&paint_0)->gradient_0) > 0.5)
        {
            _S110 = cov_10 > 9.99999997475242708e-07;
        }
        else
        {
            _S110 = false;
        }
        if(_S110)
        {
            fill_cov_1 = 1.0;
        }
        else
        {
            fill_cov_1 = has_gradient_0;
        }
        float4 premul_0 = premultiplyColor_0((&paint_0)->color_0, cov_10);
        result_0 = premul_0 + result_0 * float4((1.0 - premul_0.w)) ;
        has_gradient_0 = fill_cov_1;
        l_0 = l_0 + int(1);
    }
    if(composite_mode_0 == int(1))
    {
        _S101 = layer_count_0 >= int(2);
    }
    else
    {
        _S101 = false;
    }
    if(_S101)
    {
        float _S111 = min(fill_cov_0, stroke_cov_0);
        float _S112 = max(fill_cov_0 - _S111, 0.0);
        if((fill_paint_0.gradient_0) > 0.5)
        {
            _S101 = _S112 > 9.99999997475242708e-07;
        }
        else
        {
            _S101 = false;
        }
        if(_S101)
        {
            has_gradient_0 = 1.0;
        }
        if((stroke_paint_0.gradient_0) > 0.5)
        {
            _S101 = _S111 > 9.99999997475242708e-07;
        }
        else
        {
            _S101 = false;
        }
        if(_S101)
        {
            has_gradient_0 = 1.0;
        }
        result_0 = result_0 + (premultiplyColor_0(fill_paint_0.color_0, _S112) + premultiplyColor_0(stroke_paint_0.color_0, _S111)) * float4((1.0 - result_0.w)) ;
    }
    return PathCompositeSample_x24init_0(result_0, has_gradient_0);
}

float interleavedGradientNoise_0(float2 pixel_0)
{
    return fract(52.98291778564453125 * fract(dot(pixel_0, float2(0.06711056083440781, 0.00583714991807938))));
}

float srgbEncode_0(float c_0)
{
    float _S113;
    if(c_0 <= 0.00313080009073019)
    {
        _S113 = c_0 * 12.92000007629394531;
    }
    else
    {
        _S113 = 1.0549999475479126 * pow(c_0, 0.4166666567325592) - 0.05499999970197678;
    }
    return _S113;
}

float3 linearToSrgb_0(float3 color_5)
{
    return float3(srgbEncode_0(max(color_5.x, 0.0)), srgbEncode_0(max(color_5.y, 0.0)), srgbEncode_0(max(color_5.z, 0.0)));
}

float srgbDecode_0(float c_1)
{
    float _S114;
    if(c_1 <= 0.04044999927282333)
    {
        _S114 = c_1 / 12.92000007629394531;
    }
    else
    {
        _S114 = pow((c_1 + 0.05499999970197678) / 1.0549999475479126, 2.40000009536743164);
    }
    return _S114;
}

float3 srgbToLinear_0(float3 color_6)
{
    return float3(srgbDecode_0(color_6.x), srgbDecode_0(color_6.y), srgbDecode_0(color_6.z));
}

float4 ditherPremultipliedColor_0(float4 color_7, float2 frag_coord_0, float dither_scale_0)
{
    float _S115 = color_7.w;
    bool _S116;
    if(_S115 <= 0.0)
    {
        _S116 = true;
    }
    else
    {
        _S116 = dither_scale_0 <= 0.0;
    }
    if(_S116)
    {
        return color_7;
    }
    return float4(srgbToLinear_0(clamp(linearToSrgb_0(color_7.xyz) + float3(((interleavedGradientNoise_0(frag_coord_0) - 0.5) * (clamp(_S115, 0.0, 1.0) * dither_scale_0))) , float3(0.0) , float3(1.0) )), _S115);
}

float4 srgbEncodePremultiplied_0(float4 premul_1)
{
    float _S117 = premul_1.w;
    if(_S117 <= 0.0)
    {
        return float4(0.0) ;
    }
    return float4(linearToSrgb_0(premul_1.xyz * float3((1.0 / _S117)) ) * float3(_S117) , _S117);
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
    int layer_base_0;
    int output_srgb_0;
    float coverage_exponent_3;
    float dither_scale_1;
    int mask_output_0;
};

float4 snailPaintedFragment_0(int expected_special_kind_0, const PaintedVaryings_0 thread* v_1, float2 frag_coord_1, texture2d_array<float, access::sample> curve_tex_4, texture2d_array<uint, access::sample> band_tex_3, texture2d<float, access::sample> layer_tex_3, texture2d_array<float, access::sample> image_tex_3, sampler image_sampler_3, const PaintedParams_0 thread* p_0)
{
    float2 _S118 = v_1->texcoord_0;
    float2 epp_2 = fwidth_0(v_1->texcoord_0);
    float2 ppe_8 = float2(1.0)  / max(epp_2, float2(0.0000152587890625) );
    int4 _S119 = v_1->glyph_0;
    int _S120 = v_1->glyph_0.w;
    int special_kind_0 = _S120 & int(255);
    if(((_S120 >> 8U) & int(255)) != int(255))
    {
        discard_fragment();
    }
    if(special_kind_0 != expected_special_kind_0)
    {
        discard_fragment();
    }
    int2 infoBase_2 = _S119.xy;
    int3 _S121 = int3(infoBase_2, int(0));
    float4 firstInfo_0 = ((layer_tex_3).read(vec<uint,2>(((_S121)).xy), uint(((_S121)).z)));
    float _S122 = firstInfo_0.w;
    if(_S122 >= 0.0)
    {
        discard_fragment();
    }
    int texLayer_2 = p_0->layer_base_0 + int(v_1->banding_1.w);
    float4 emit_0;
    if(int(- _S122 + 0.5) == int(5))
    {
        PathCompositeSample_0 result_1 = compositePathGroup_0(curve_tex_4, band_tex_3, layer_tex_3, image_tex_3, image_sampler_3, _S118, epp_2, ppe_8, infoBase_2, firstInfo_0, texLayer_2, v_1->tint_1, p_0->coverage_exponent_3);
        if((result_1.color_3.w) < 0.00392156885936856)
        {
            discard_fragment();
        }
        if((result_1.gradient_2) > 0.5)
        {
            emit_0 = ditherPremultipliedColor_0(result_1.color_3, frag_coord_1, p_0->dither_scale_1);
        }
        else
        {
            emit_0 = result_1.color_3;
        }
        if((p_0->mask_output_0) != int(0))
        {
            emit_0 = float4(emit_0.w) ;
        }
        else
        {
            if((p_0->output_srgb_0) != int(0))
            {
                emit_0 = srgbEncodePremultiplied_0(emit_0);
            }
        }
        return emit_0;
    }
    int2 _S123 = offsetLayerLoc_0(layer_tex_3, infoBase_2, int(1));
    int3 _S124 = int3(_S123, int(0));
    int packed_gx_1 = int(firstInfo_0.x);
    int _S125 = (as_type<int>((firstInfo_0.z)));
    float cov_11 = evalPathGlyphCoverage_0(curve_tex_4, band_tex_3, _S118, epp_2, ppe_8, int2(packed_gx_1 & int(32767), int(firstInfo_0.y)), int2((_S125 >> 16U) & int(65535), _S125 & int(65535)), ((layer_tex_3).read(vec<uint,2>(((_S124)).xy), uint(((_S124)).z))), texLayer_2, (packed_gx_1 >> 15U) & int(1), p_0->coverage_exponent_3);
    if(cov_11 < 0.00392156885936856)
    {
        discard_fragment();
    }
    PathPaintSample_0 _S126 = samplePathPaint_0(layer_tex_3, image_tex_3, image_sampler_3, _S118, infoBase_2, firstInfo_0);
    thread PathPaintSample_0 paint_1 = _S126;
    float4 _S127 = (&paint_1)->color_0 * v_1->tint_1;
    (&paint_1)->color_0 = _S127;
    float4 result_2 = premultiplyColor_0(_S127, cov_11);
    if(((&paint_1)->gradient_0) > 0.5)
    {
        emit_0 = ditherPremultipliedColor_0(result_2, frag_coord_1, p_0->dither_scale_1);
    }
    else
    {
        emit_0 = result_2;
    }
    if((p_0->mask_output_0) != int(0))
    {
        emit_0 = float4(emit_0.w) ;
    }
    else
    {
        if((p_0->output_srgb_0) != int(0))
        {
            emit_0 = srgbEncodePremultiplied_0(emit_0);
        }
    }
    return emit_0;
}

struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};

struct pixelInput_0
{
    float4 color_8 [[user(TEXCOORD)]];
    float2 texcoord_1 [[user(TEXCOORD_1)]];
    [[flat]] float4 banding_2 [[user(TEXCOORD_2)]];
    [[flat]] int4 glyph_1 [[user(TEXCOORD_3)]];
    float4 tint_2 [[user(TEXCOORD_4)]];
};

struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};

struct SnailPushConstants_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 mvp_0;
    float2 viewport_0;
    int subpixel_order_0;
    int output_srgb_1;
    int layer_base_1;
    float coverage_exponent_4;
    float dither_scale_2;
    int mask_output_1;
};

struct KernelContext_0
{
    SnailPushConstants_natural_0 constant* pc_0;
    texture2d_array<float, access::sample> u_curve_tex_0;
    texture2d_array<uint, access::sample> u_band_tex_0;
    texture2d<float, access::sample> u_layer_tex_0;
    texture2d_array<float, access::sample> u_image_tex_0;
    sampler u_image_sampler_0;
};

[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S128 [[stage_in]], float4 position_0 [[position]], SnailPushConstants_natural_0 constant* pc_1 [[buffer(0)]], texture2d_array<float, access::sample> u_curve_tex_1 [[texture(0)]], texture2d_array<uint, access::sample> u_band_tex_1 [[texture(1)]], texture2d<float, access::sample> u_layer_tex_1 [[texture(2)]], texture2d_array<float, access::sample> u_image_tex_1 [[texture(3)]], sampler u_image_sampler_1 [[sampler(0)]])
{
    thread KernelContext_0 kernelContext_0;
    (&kernelContext_0)->pc_0 = pc_1;
    (&kernelContext_0)->u_curve_tex_0 = u_curve_tex_1;
    (&kernelContext_0)->u_band_tex_0 = u_band_tex_1;
    (&kernelContext_0)->u_layer_tex_0 = u_layer_tex_1;
    (&kernelContext_0)->u_image_tex_0 = u_image_tex_1;
    (&kernelContext_0)->u_image_sampler_0 = u_image_sampler_1;
    thread PaintedVaryings_0 v_2;
    (&v_2)->tint_1 = _S128.tint_2;
    (&v_2)->texcoord_0 = _S128.texcoord_1;
    (&v_2)->banding_1 = _S128.banding_2;
    (&v_2)->glyph_0 = _S128.glyph_1;
    thread PaintedParams_0 p_1;
    (&p_1)->layer_base_0 = pc_1->layer_base_1;
    (&p_1)->output_srgb_0 = pc_1->output_srgb_1;
    (&p_1)->coverage_exponent_3 = pc_1->coverage_exponent_4;
    (&p_1)->dither_scale_1 = pc_1->dither_scale_2;
    (&p_1)->mask_output_0 = pc_1->mask_output_1;
    float2 _S129 = position_0.xy;
    thread PaintedVaryings_0 _S130 = v_2;
    thread PaintedParams_0 _S131 = p_1;
    float4 _S132 = snailPaintedFragment_0(int(1), &_S130, _S129, u_curve_tex_1, u_band_tex_1, u_layer_tex_1, u_image_tex_1, u_image_sampler_1, &_S131);
    pixelOutput_0 _S133 = { _S132 };
    return _S133;
}


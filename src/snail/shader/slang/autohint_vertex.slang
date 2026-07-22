// Native-Slang port of snail_autohint_vert_body.glsl — the vertex half of
// the autohint family: fit immutable autohint semantics once at the quad's
// shared provoking vertex. The GLSL fragment is the behavioral spec: every
// epsilon, literal, and operation order is preserved.
module autohint_vertex;

import color_common;
import vertex;
import autohint_warp;

public static const int SNAIL_AH_VERTEX_KNOTS = 16;
static const uint SNAIL_AH_SOURCE_UNUSED = 255u;
static const uint SNAIL_AH_SOURCE_FALLBACK = 254u;

public struct AutohintVertexResult {
    public float4 position;
    public float4 paint;
    public float3 texcoord_layer;
    public int2 info;
    public uint4 policy;
    public float4 x_targets[4];
    public float4 y_targets[4];
    public uint4 x_sources;
    public uint4 y_sources;
};

bool snailAhAffineScale(float4x4 mvp, float2 viewport, float4 xform, out float2 scale) {
    scale = float2(0.0, 0.0);
    // GLSL gathered rows element-wise (m0 = vec4(M[0].x, M[1].x, ...));
    // Slang's row indexing gives the same logical rows directly.
    float4 m0 = mvp[0];
    float4 m1 = mvp[1];
    float4 m3 = mvp[3];
    if (abs(m3.x) > 1e-7 || abs(m3.y) > 1e-7 || !snailAhFinite(m3.w) || abs(m3.w) < 1e-10) return false;

    float2 localX = float2(xform.x, xform.z);
    float2 localY = float2(xform.y, xform.w);
    float2 screenX = 0.5 * viewport * float2(dot(m0.xy, localX), dot(m1.xy, localX)) / m3.w;
    float2 screenY = 0.5 * viewport * float2(dot(m0.xy, localY), dot(m1.xy, localY)) / m3.w;
    float det = screenX.x * screenY.y - screenY.x * screenX.y;
    if (!snailAhFinite(det) || abs(det) < 1e-10) return false;
    float2 epp = float2(
        (abs(screenY.y) + abs(screenY.x)) / abs(det),
        (abs(screenX.y) + abs(screenX.x)) / abs(det)
    );
    scale = 1.0 / epp;
    return snailAhFinite(scale.x) && snailAhFinite(scale.y) && scale.x > 0.0 && scale.y > 0.0;
}

void snailAhPackAxis(
    int count,
    float targets[SNAIL_AH_VERTEX_KNOTS],
    int sources[SNAIL_AH_VERTEX_KNOTS],
    out float4 packedTargets[4],
    out uint4 packedSources
) {
    for (int i = 0; i < 4; ++i) packedTargets[i] = float4(0.0);
    packedSources = uint4(0xffffffffu);
    if (count > SNAIL_AH_VERTEX_KNOTS) {
        packedSources.x = (packedSources.x & 0xffffff00u) | SNAIL_AH_SOURCE_FALLBACK;
        return;
    }
#if defined(SNAIL_TARGET_D3D11)
    // Same packing, slang-side unrolled: vkd3d-shader (Wine's
    // d3dcompiler_47 and its wined3d HLSL front end) has no dynamic
    // vector-component STORES (E5017 "Non-constant vector addressing on
    // store"; Wine 11.0's bundled copy crashes outright). [ForceUnroll]
    // makes every subscript a compile-time constant; the `break` becomes
    // an `if` guard (identical semantics — the loop is pure writes).
    [ForceUnroll]
    for (int i = 0; i < SNAIL_AH_VERTEX_KNOTS; ++i) {
        if (i < count) {
            packedTargets[i >> 2][i & 3] = targets[i];
            int word = i >> 2;
            int shift = (i & 3) * 8;
            packedSources[word] = (packedSources[word] & ~(255u << uint(shift))) |
                ((uint(sources[i]) & 255u) << uint(shift));
        }
    }
#else
    for (int i = 0; i < SNAIL_AH_VERTEX_KNOTS; ++i) {
        if (i >= count) break;
        packedTargets[i >> 2][i & 3] = targets[i];
        int word = i >> 2;
        int shift = (i & 3) * 8;
        packedSources[word] = (packedSources[word] & ~(255u << uint(shift))) |
            ((uint(sources[i]) & 255u) << uint(shift));
    }
#endif
}

void snailAhMarkFallback(out float4 packedTargets[4], out uint4 packedSources) {
    for (int i = 0; i < 4; ++i) packedTargets[i] = float4(0.0);
    packedSources = uint4(0xffffffffu);
    packedSources.x = (packedSources.x & 0xffffff00u) | SNAIL_AH_SOURCE_FALLBACK;
}

public AutohintVertexResult snailAutohintVertex(
    TextVertexIn input,
    uint vertex_index,
    float4x4 mvp,
    float2 viewport,
    int subpixel_order,
    uint4 packed_policy,
    Texture2D<float4> layer_tex)
{
    TextVertexResult base = snailTextVertex(input, vertex_index, mvp, viewport, subpixel_order);

    AutohintVertexResult r;
    r.position = base.position;
    // v_paint = decoded color * decoded tint (constant across the quad).
    r.paint = base.color * base.tint;
    r.texcoord_layer = float3(base.texcoord, float((input.glyph.y >> 18u) & 0xffu));
    uint gz = input.glyph.x;
    r.info = int2(int(gz & 0xFFFFu), int(gz >> 16u));
    r.policy = packed_policy;

    // The reference GL index order makes vertex 0 the last (provoking) vertex
    // of both triangles; Vulkan's default convention uses the same vertex as
    // the first. Only that shared vertex needs to execute the flat fit.
    if (vertex_index != 0u) {
        for (int i = 0; i < 4; ++i) {
            r.x_targets[i] = float4(0.0);
            r.y_targets[i] = float4(0.0);
        }
        r.x_sources = uint4(0xffffffffu);
        r.y_sources = uint4(0xffffffffu);
        return r;
    }
    int2 info_base = r.info;

    float2 scale;
    if (!snailAhAffineScale(mvp, viewport, input.xform, scale)) {
        snailAhMarkFallback(r.x_targets, r.x_sources);
        snailAhMarkFallback(r.y_targets, r.y_sources);
        return r;
    }

    SnailAutohintPolicy decoded_policy;
    int blueCount = 0;
    int featureXCount = 0;
    int featureYCount = 0;
    float stdX = snailWarpF(layer_tex, info_base, 0, 8);
    float stdY = snailWarpF(layer_tex, info_base, 0, 9);
    bool valid = snailDecodeAutohintPolicy(packed_policy, decoded_policy) &&
        snailAhFinite(stdX) && stdX >= 0.0 && snailAhFinite(stdY) && stdY >= 0.0 &&
        snailAhCount(SNAIL_AH_VERTEX_KNOTS, snailWarpF(layer_tex, info_base, 0, 10), blueCount);
    int xRun = 12 + 2 * blueCount;
    valid = valid && snailAhCount(SNAIL_AH_VERTEX_KNOTS, snailWarpF(layer_tex, info_base, xRun, 0), featureXCount);
    int yRun = xRun + 1 + 4 * featureXCount;
    valid = valid && snailAhCount(SNAIL_AH_VERTEX_KNOTS, snailWarpF(layer_tex, info_base, yRun, 0), featureYCount);
    if (!valid) {
        snailAhMarkFallback(r.x_targets, r.x_sources);
        snailAhMarkFallback(r.y_targets, r.y_sources);
        return r;
    }

    int xCount = 0;
    int yCount = 0;
    float xBase[SNAIL_AH_VERTEX_KNOTS];
    float xTarget[SNAIL_AH_VERTEX_KNOTS];
    float yBase[SNAIL_AH_VERTEX_KNOTS];
    float yTarget[SNAIL_AH_VERTEX_KNOTS];
    int xSource[SNAIL_AH_VERTEX_KNOTS];
    int ySource[SNAIL_AH_VERTEX_KNOTS];
    bool xValid = snailFitAutohintAxis<SNAIL_AH_VERTEX_KNOTS, true>(layer_tex, info_base,
        0, xRun, blueCount, stdX, snailWarpF(layer_tex, info_base, 0, 11),
        scale.x, decoded_policy, xCount, xBase, xTarget, xSource);
    bool yValid = snailFitAutohintAxis<SNAIL_AH_VERTEX_KNOTS, true>(layer_tex, info_base,
        1, yRun, blueCount, stdY, 0.0,
        scale.y, decoded_policy, yCount, yBase, yTarget, ySource);
    if (xValid) snailAhPackAxis(xCount, xTarget, xSource, r.x_targets, r.x_sources);
    else snailAhMarkFallback(r.x_targets, r.x_sources);
    if (yValid) snailAhPackAxis(yCount, yTarget, ySource, r.y_targets, r.y_sources);
    else snailAhMarkFallback(r.y_targets, r.y_sources);
    return r;
}

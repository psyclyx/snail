// Vertex half of the autohint family: fit immutable autohint semantics once
// at the quad's shared provoking vertex. This module is canonical.
module autohint_vertex;

import resource_types;

import color_common;
import vertex;
import autohint_warp;

public struct AutohintVertexResult {
    public float4 position;
    public float4 paint;
    public float3 texcoord_layer;
    public int2 info;
    public uint4 policy;
    public float4 x_targets[4];
    public float4 y_targets[4];
    // Per axis: see snailAhPackFit.
    public uint4 x_knots;
    public uint4 y_knots;
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
// Per-axis knot descriptor: (mask, left-knot target bits, record run offset,
// left edge bits). The run and left edge let the fragment stage look up knot
// bases without re-parsing the record header.
void snailAhPackFit(SnailAhAxisFit fit, int run, float left, out float4 targets[4], out uint4 knots) {
    targets = fit.targets;
    knots = uint4(fit.mask, asuint(fit.leftTarget), uint(run), asuint(left));
}

void snailAhPackIdentity(out float4 targets[4], out uint4 knots) {
    for (int i = 0; i < 4; ++i) targets[i] = float4(0.0);
    knots = uint4(0u);
}

public AutohintVertexResult snailAutohintVertex(
    TextVertexIn input,
    uint vertex_index,
    float4x4 mvp,
    float2 viewport,
    int subpixel_order,
    uint4 packed_policy,
    SnailFloatTexture2D layer_tex)
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
    snailAhPackIdentity(r.x_targets, r.x_knots);
    snailAhPackIdentity(r.y_targets, r.y_knots);

    // The reference GL index order makes vertex 0 the last (provoking) vertex
    // of both triangles; Vulkan's default convention uses the same vertex as
    // the first. Only that shared vertex needs to execute the flat fit.
    if (vertex_index != 0u) return r;
    int2 info_base = r.info;

    // Grid-fitting needs a constant pixels-per-em across the glyph; a
    // non-affine (perspective) placement renders unhinted.
    float2 scale;
    if (!snailAhAffineScale(mvp, viewport, input.xform, scale)) return r;

    SnailAutohintPolicy decoded_policy;
    int blueCount = 0;
    int featureXCount = 0;
    int featureYCount = 0;
    float stdX = snailWarpF(layer_tex, info_base, 0, 8);
    float stdY = snailWarpF(layer_tex, info_base, 0, 9);
    bool valid = snailDecodeAutohintPolicy(packed_policy, decoded_policy) &&
        snailAhFinite(stdX) && stdX >= 0.0 && snailAhFinite(stdY) && stdY >= 0.0 &&
        snailAhCount(SNAIL_AH_RECORD_FEATURES, snailWarpF(layer_tex, info_base, 0, 10), blueCount);
    int xRun = 12 + 2 * blueCount;
    valid = valid && snailAhCount(SNAIL_AH_RECORD_FEATURES, snailWarpF(layer_tex, info_base, xRun, 0), featureXCount);
    int yRun = xRun + 1 + 4 * featureXCount;
    valid = valid && snailAhCount(SNAIL_AH_RECORD_FEATURES, snailWarpF(layer_tex, info_base, yRun, 0), featureYCount);
    if (!valid) return r;

    float left = snailWarpF(layer_tex, info_base, 0, 11);
    SnailAhAxisFit xFit = snailFitAutohintAxis(layer_tex, info_base,
        0, xRun, blueCount, stdX, left, scale.x, decoded_policy);
    SnailAhAxisFit yFit = snailFitAutohintAxis(layer_tex, info_base,
        1, yRun, blueCount, stdY, 0.0,
        scale.y, decoded_policy);
    snailAhPackFit(xFit, xRun, left, r.x_targets, r.x_knots);
    snailAhPackFit(yFit, yRun, 0.0, r.y_targets, r.y_knots);
    return r;
}

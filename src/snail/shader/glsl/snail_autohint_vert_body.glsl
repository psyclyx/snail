// Fit immutable autohint semantics once at the quad's shared provoking vertex.
// The fragment stage consumes at most 16 exact targets per axis and falls back
// to the full fitter when an external font exceeds that bound or projection is
// perspective.

const int SNAIL_AH_VERTEX_KNOTS = 16;
const uint SNAIL_AH_SOURCE_UNUSED = 255u;
const uint SNAIL_AH_SOURCE_FALLBACK = 254u;

ivec2 snailAhVertexInfoBase;

ivec2 snailAhLayerLoc(ivec2 base, int offset) {
    int width = textureSize(u_layer_tex, 0).x;
    int texel = base.y * width + base.x + offset;
    return ivec2(texel % width, texel / width);
}

float snailWarpF(int block, int i) {
    int f = block + i;
    vec4 t = texelFetch(u_layer_tex, snailAhLayerLoc(snailAhVertexInfoBase, f >> 2), 0);
    int c = f & 3;
    return (c == 0) ? t.x : ((c == 1) ? t.y : ((c == 2) ? t.z : t.w));
}

bool snailAhAffineScale(out vec2 scale) {
    vec4 m0 = vec4(SNAIL_MVP[0].x, SNAIL_MVP[1].x, SNAIL_MVP[2].x, SNAIL_MVP[3].x);
    vec4 m1 = vec4(SNAIL_MVP[0].y, SNAIL_MVP[1].y, SNAIL_MVP[2].y, SNAIL_MVP[3].y);
    vec4 m3 = vec4(SNAIL_MVP[0].w, SNAIL_MVP[1].w, SNAIL_MVP[2].w, SNAIL_MVP[3].w);
    if (abs(m3.x) > 1e-7 || abs(m3.y) > 1e-7 || !snailAhFinite(m3.w) || abs(m3.w) < 1e-10) return false;

    vec2 localX = vec2(a_xform.x, a_xform.z);
    vec2 localY = vec2(a_xform.y, a_xform.w);
    vec2 screenX = 0.5 * SNAIL_VIEWPORT * vec2(dot(m0.xy, localX), dot(m1.xy, localX)) / m3.w;
    vec2 screenY = 0.5 * SNAIL_VIEWPORT * vec2(dot(m0.xy, localY), dot(m1.xy, localY)) / m3.w;
    float det = screenX.x * screenY.y - screenY.x * screenX.y;
    if (!snailAhFinite(det) || abs(det) < 1e-10) return false;
    vec2 epp = vec2(
        (abs(screenY.y) + abs(screenY.x)) / abs(det),
        (abs(screenX.y) + abs(screenX.x)) / abs(det)
    );
    scale = 1.0 / epp;
    return snailAhFinite(scale.x) && snailAhFinite(scale.y) && scale.x > 0.0 && scale.y > 0.0;
}

void snailAhPackAxis(
    int count,
    float targets[SNAIL_AH_MAX_KNOTS],
    int sources[SNAIL_AH_MAX_KNOTS],
    out vec4 packedTargets[4],
    out uvec4 packedSources
) {
    for (int i = 0; i < 4; ++i) packedTargets[i] = vec4(0.0);
    packedSources = uvec4(0xffffffffu);
    if (count > SNAIL_AH_VERTEX_KNOTS) {
        packedSources.x = (packedSources.x & 0xffffff00u) | SNAIL_AH_SOURCE_FALLBACK;
        return;
    }
    for (int i = 0; i < SNAIL_AH_VERTEX_KNOTS; ++i) {
        if (i >= count) break;
        packedTargets[i >> 2][i & 3] = targets[i];
        int word = i >> 2;
        int shift = (i & 3) * 8;
        packedSources[word] = (packedSources[word] & ~(255u << uint(shift))) |
            ((uint(sources[i]) & 255u) << uint(shift));
    }
}

void snailAhMarkFallback(out vec4 packedTargets[4], out uvec4 packedSources) {
    for (int i = 0; i < 4; ++i) packedTargets[i] = vec4(0.0);
    packedSources = uvec4(0xffffffffu);
    packedSources.x = (packedSources.x & 0xffffff00u) | SNAIL_AH_SOURCE_FALLBACK;
}

void snailAutohintVertex() {
    snailVertex();
    // The reference GL index order makes vertex 0 the last (provoking) vertex
    // of both triangles; Vulkan's default convention uses the same vertex as
    // the first. Only that shared vertex needs to execute the flat fit.
    if (SNAIL_VERTEX_INDEX != 0) {
        for (int i = 0; i < 4; ++i) {
            v_ah_x_targets[i] = vec4(0.0);
            v_ah_y_targets[i] = vec4(0.0);
        }
        v_ah_x_sources = uvec4(0xffffffffu);
        v_ah_y_sources = uvec4(0xffffffffu);
        return;
    }
    snailAhVertexInfoBase = v_info;

    #ifdef SNAIL_AH_FORCE_FRAGMENT
    snailAhMarkFallback(v_ah_x_targets, v_ah_x_sources);
    snailAhMarkFallback(v_ah_y_targets, v_ah_y_sources);
    return;
    #endif

    vec2 scale;
    if (!snailAhAffineScale(scale)) {
        snailAhMarkFallback(v_ah_x_targets, v_ah_x_sources);
        snailAhMarkFallback(v_ah_y_targets, v_ah_y_sources);
        return;
    }

    SnailAutohintPolicy policy;
    int blueCount = 0;
    int featureXCount = 0;
    int featureYCount = 0;
    float stdX = snailWarpF(0, 8);
    float stdY = snailWarpF(0, 9);
    bool valid = snailDecodeAutohintPolicy(a_policy0, a_policy1, policy) &&
        snailAhFinite(stdX) && stdX >= 0.0 && snailAhFinite(stdY) && stdY >= 0.0 &&
        snailAhCount(snailWarpF(0, 10), blueCount);
    int xRun = 12 + 2 * blueCount;
    valid = valid && snailAhCount(snailWarpF(xRun, 0), featureXCount);
    int yRun = xRun + 1 + 4 * featureXCount;
    valid = valid && snailAhCount(snailWarpF(yRun, 0), featureYCount);
    if (!valid) {
        snailAhMarkFallback(v_ah_x_targets, v_ah_x_sources);
        snailAhMarkFallback(v_ah_y_targets, v_ah_y_sources);
        return;
    }

    int xCount = 0;
    int yCount = 0;
    float xBase[SNAIL_AH_MAX_KNOTS];
    float xTarget[SNAIL_AH_MAX_KNOTS];
    float yBase[SNAIL_AH_MAX_KNOTS];
    float yTarget[SNAIL_AH_MAX_KNOTS];
    int xSource[SNAIL_AH_MAX_KNOTS];
    int ySource[SNAIL_AH_MAX_KNOTS];
    bool xValid = snailFitAutohintAxis(0, xRun, blueCount, stdX, snailWarpF(0, 11),
        scale.x, policy, xCount, xBase, xTarget, xSource);
    bool yValid = snailFitAutohintAxis(1, yRun, blueCount, stdY, 0.0,
        scale.y, policy, yCount, yBase, yTarget, ySource);
    if (xValid) snailAhPackAxis(xCount, xTarget, xSource, v_ah_x_targets, v_ah_x_sources);
    else snailAhMarkFallback(v_ah_x_targets, v_ah_x_sources);
    if (yValid) snailAhPackAxis(yCount, yTarget, ySource, v_ah_y_targets, v_ah_y_sources);
    else snailAhMarkFallback(v_ah_y_targets, v_ah_y_sources);
}

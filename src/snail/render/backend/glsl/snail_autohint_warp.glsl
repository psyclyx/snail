// Auto-light coordinate warp — the shader-side of resolution-independent
// hinting. Mirrors `font/autohint/warp.zig` `inverseWarpPacked` exactly (the
// Zig parity test "packed inverse warp matches the reference" pins them
// together). The renderer warps the SAMPLE coordinate back into base-outline
// space, then runs the normal coverage evaluator against the shared, unhinted
// base glyph — no per-ppem baked curves.
//
// Per-axis knots live as a flat float run: [count, base0,target0, base1,...].
// The including shader supplies two accessors that fetch from wherever it
// stored the run (layer slab / SSBO):
//
//   float snailWarpF(int block, int i);   // float at run `block`, index `i`
//
// `block` is the run's start index; index 0 is `count`, then pairs follow.

// Prototype — the host shader's main defines the body (it knows the buffer).
float snailWarpF(int block, int i);

// Inverse warp along one axis. Returns the base-space coordinate; writes the
// local d(base)/d(hinted) slope used to rescale the AA footprint.
float snailInverseWarpAxis(int block, float hinted, out float invSlope) {
    invSlope = 1.0;
    int count = int(snailWarpF(block, 0));
    if (count == 0) return hinted;

    float firstBase = snailWarpF(block, 1);
    float firstTarget = snailWarpF(block, 2);
    if (hinted <= firstTarget) return firstBase + (hinted - firstTarget);

    float lastBase = snailWarpF(block, 1 + 2 * (count - 1));
    float lastTarget = snailWarpF(block, 2 + 2 * (count - 1));
    if (hinted >= lastTarget) return lastBase + (hinted - lastTarget);

    int i = 0;
    while (i + 1 < count && snailWarpF(block, 2 + 2 * (i + 1)) < hinted) i++;
    float loBase = snailWarpF(block, 1 + 2 * i);
    float loTarget = snailWarpF(block, 2 + 2 * i);
    float hiBase = snailWarpF(block, 1 + 2 * (i + 1));
    float hiTarget = snailWarpF(block, 2 + 2 * (i + 1));
    float dt = hiTarget - loTarget;
    float db = hiBase - loBase;
    invSlope = (abs(dt) > 1e-6) ? db / dt : 1.0;
    return loBase + (hinted - loTarget) * invSlope;
}

// Warp a full sample coordinate and rescale the per-axis AA footprint `epp`
// (em-per-pixel) into base space: epp_base = epp_screen * d(base)/d(hinted).
// `xBlock`/`yBlock` are the two axes' knot-run starts.
vec2 snailWarpSample(int xBlock, int yBlock, vec2 rc, inout vec2 epp) {
    float sx, sy;
    float bx = snailInverseWarpAxis(xBlock, rc.x, sx);
    float by = snailInverseWarpAxis(yBlock, rc.y, sy);
    epp = vec2(epp.x * sx, epp.y * sy);
    return vec2(bx, by);
}

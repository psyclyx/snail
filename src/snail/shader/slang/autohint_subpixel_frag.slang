// LCD-subpixel fragment body for autohinted text. There is no GLSL spec
// for this path: the Slang source is authoritative, and the CPU raster
// backend (snail-raster renderTransformedAutohintGlyph with subpixel) is
// the parity reference.
//
// Warp semantics: the inverse warp is resolved ONCE at the pixel center
// and linearized — the 7-tap sample offsets and the AA footprint are the
// display-space derivatives of the unwarped varying scaled by the
// per-axis warp slope. This is the same local linearization the
// grayscale fragment applies to its footprint (epp *= slope); samples
// whose ±1-pixel neighborhood crosses a warp knot see the center
// segment's slope.
module autohint_subpixel_frag;

import resource_types;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import autohint_warp;
import autohint_frag;
import subpixel_body;

public SubpixelResult snailAutohintSubpixelFragment(
    AutohintVaryings v,
    SnailFloatTexture2DArray curve_tex,
    SnailUint2Texture2DArray band_tex,
    SnailFloatTexture2D layer_tex,
    int layer_base,
    int subpixel_order,
    int output_srgb,
    float coverage_exponent)
{
    // Derivatives of the UNWARPED coordinate, taken before any divergent
    // control flow.
    float2 unwarped = v.texcoord_layer.xy;
    float2 display_dx = ddx(unwarped);
    float2 display_dy = ddy(unwarped);

    SnailAutohintWarped w = snailAutohintWarpSample(v, layer_tex, layer_base);
    float4 cov_alpha = snailEvalGlyphCoverageSubpixelDerivs(
        w.rc, display_dx * w.slope, display_dy * w.slope,
        w.gLoc, w.bandMax, w.band, w.texLayer,
        subpixel_order, coverage_exponent, curve_tex, band_tex);
    // v.paint is the product of linear-light f16 color and tint.
    return snailPackSubpixelResult(v.paint, cov_alpha, output_srgb);
}

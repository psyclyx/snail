void snailAutohintSubpixelFragment() {
#ifdef SNAIL_DUAL_SOURCE
    frag_blend = vec4(0.0);
#endif
    // Capture derivatives before the fitter's data-dependent control flow.
    vec2 unwarped = v_texcoord_layer.xy;
    vec2 display_dx = dFdx(unwarped);
    vec2 display_dy = dFdy(unwarped);
    SnailAutohintWarped w = snailAutohintWarpSample();
    vec4 cov_alpha = evalGlyphCoverageSubpixelDerivs(
        w.rc, display_dx * w.slope, display_dy * w.slope,
        w.gLoc, w.bandMax, w.band, w.texLayer
    );
    vec3 cov = cov_alpha.rgb;
    if (max(max(cov.r, cov.g), cov.b) < 1.0 / 255.0) discard;
    emitSubpixelColor(v_paint, cov, cov_alpha.a);
}

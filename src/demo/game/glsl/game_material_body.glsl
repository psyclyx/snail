// Shared material-shading body for the game demo's custom shader, used by both
// the GL assembly (gl_material.zig) and the Vulkan shader (game_material.frag).
// It turns snail glyph coverage into text *carved into a rough, lit surface*:
// a procedural normal gives the surface its roughness, the coverage gradient
// embosses the glyphs, and a fixed tangent-space light catches both. This is
// the nontrivial "text reacts to light on a real surface" effect — not text
// slapped flat onto a quad.
//
// Requires `snail_text_sample_premul_linear_with_footprint` to be declared.

// Differentiable, material-space roughness. A small set of incommensurate
// waves reads as a hammered surface without the lattice seams hash/value noise
// can expose differently after GL and SPIR-V compilation.
float snailGameHeight(vec2 uv) {
    const float tau = 6.28318530718;
    vec2 p = uv * tau;
    return 0.50 * sin(dot(p, vec2(1.7, 0.6))) +
           0.27 * sin(dot(p, vec2(3.9, -2.7)) + 1.3) +
           0.15 * cos(dot(p, vec2(7.1, 5.3)) + 0.4) +
           0.08 * sin(dot(p, vec2(13.7, -9.1)) + 2.1);
}

/// `uv`        quad UV in [0,1]²
/// `scene_pos` position in snail's text authoring frame (for coverage sampling)
/// `scene_dx/dy` scene-space derivatives computed by the fragment entry point
/// `light_dir` fixed tangent-space light direction
/// `base`      surface base color (linear)
/// `relief`    text emboss strength
/// `roughness` surface bump strength
/// returns premultiplied-linear-ish opaque surface color.
vec3 snailGameMaterial(vec2 uv, vec2 scene_pos, vec2 scene_dx, vec2 scene_dy, vec3 light_dir, vec4 base, float relief, float roughness) {
    // Coverage is the text height field. Sample about 1.25 screen pixels to
    // either side so the bevel stays the same apparent width under perspective
    // instead of stretching with the authoring frame.
    vec2 scene_pixel = abs(scene_dx) + abs(scene_dy);
    vec2 bevel_step = max(scene_pixel * 1.25, vec2(1.0 / 65536.0));
    float c   = snail_text_sample_premul_linear_with_footprint(scene_pos, scene_dx, scene_dy).a;
    float cxp = snail_text_sample_premul_linear_with_footprint(scene_pos + vec2(bevel_step.x, 0.0), scene_dx, scene_dy).a;
    float cxn = snail_text_sample_premul_linear_with_footprint(scene_pos - vec2(bevel_step.x, 0.0), scene_dx, scene_dy).a;
    float cyp = snail_text_sample_premul_linear_with_footprint(scene_pos + vec2(0.0, bevel_step.y), scene_dx, scene_dy).a;
    float cyn = snail_text_sample_premul_linear_with_footprint(scene_pos - vec2(0.0, bevel_step.y), scene_dx, scene_dy).a;

    // A low-frequency, surface-anchored height field. Differentiate it with a
    // small material-space step; the old large step turned the normal into
    // unrelated blotches rather than a coherent rough surface.
    float e = 1.0 / 1024.0;
    float h0 = snailGameHeight(uv);
    float hx = snailGameHeight(uv + vec2(e, 0.0));
    float hy = snailGameHeight(uv + vec2(0.0, e));
    vec2 rough_grad = vec2(hx - h0, hy - h0) * (roughness / e);

    // Text emboss: the strokes stand proud; their sloped sides tilt the normal.
    vec2 relief_grad = vec2(cxp - cxn, cyp - cyn) * (0.5 * relief);

    vec3 n = normalize(vec3(-(rough_grad + relief_grad), 1.0));
    vec3 L = normalize(light_dir);
    float diff = max(dot(n, L), 0.0);
    vec3 view = vec3(0.0, 0.0, 1.0);
    vec3 half_v = normalize(L + view);
    float spec = pow(max(dot(n, half_v), 0.0), 40.0);

    // One carved material: dark stone, with the strokes as a slightly brighter,
    // more reflective inlay. Crucially the inlay shares the *same* relief-lit
    // normal `n`, so the letters' shading comes from their bevels catching the
    // fixed light — one side bright, the other in shadow — not from a flat fill.
    float ink = clamp(c, 0.0, 1.0);
    float ao = 0.94 + 0.06 * h0;
    vec3 albedo = mix(base.rgb, vec3(0.24, 0.30, 0.40), ink);
    vec3 lit = albedo * (0.20 + (0.78 + 0.22 * ink) * diff) * ao
             + vec3(0.80, 0.88, 1.0) * spec * (0.12 + 0.28 * ink);
    return lit;
}

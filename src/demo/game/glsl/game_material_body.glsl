// Shared material-shading body for the game demo's custom shader, used by both
// the GL assembly (gl_material.zig) and the Vulkan shader (game_material.frag).
// It turns snail glyph coverage into text *carved into a rough, lit surface*:
// a procedural normal gives the surface its roughness, the coverage gradient
// embosses the glyphs, and a (moving) tangent-space light catches both. This is
// the nontrivial "text reacts to light on a real surface" effect — not text
// slapped flat onto a quad.
//
// Requires `snail_text_sample_premul_linear(vec2)` to be declared already.

float snailGameHash(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float snailGameNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = snailGameHash(i);
    float b = snailGameHash(i + vec2(1.0, 0.0));
    float c = snailGameHash(i + vec2(0.0, 1.0));
    float d = snailGameHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal roughness height at surface coordinate `q`.
float snailGameHeight(vec2 q) {
    return 0.62 * snailGameNoise(q) + 0.30 * snailGameNoise(q * 2.7) + 0.12 * snailGameNoise(q * 6.3);
}

/// `uv`        quad UV in [0,1]²
/// `scene_pos` position in snail's text authoring frame (for coverage sampling)
/// `texel`     small scene-space step used to finite-difference the coverage
/// `light_dir` tangent-space light direction (animate on the CPU)
/// `base`      surface base color (linear)
/// `relief`    text emboss strength
/// `roughness` surface bump strength
/// returns premultiplied-linear-ish opaque surface color.
vec3 snailGameMaterial(vec2 uv, vec2 scene_pos, vec2 texel, vec3 light_dir, vec4 base, float relief, float roughness) {
    // Text coverage at the fragment + two neighbors (relief gradient).
    float c  = snail_text_sample_premul_linear(scene_pos).a;
    float cx = snail_text_sample_premul_linear(scene_pos + vec2(texel.x, 0.0)).a;
    float cy = snail_text_sample_premul_linear(scene_pos + vec2(0.0, texel.y)).a;

    // Procedural rough-surface normal from the height-field gradient. A low base
    // frequency + fractal octaves gives a stone-like surface rather than static.
    vec2 q = uv * 13.0;
    float e = 0.6;
    float h0 = snailGameHeight(q);
    float hx = snailGameHeight(q + vec2(e, 0.0));
    float hy = snailGameHeight(q + vec2(0.0, e));
    vec2 rough_grad = vec2(hx - h0, hy - h0) * roughness;

    // Text relief: glyphs stand proud of the surface — tilt the normal at the
    // coverage edges so the light rakes across the lettering.
    vec2 relief_grad = vec2(cx - c, cy - c) * relief;

    vec3 n = normalize(vec3(-(rough_grad + relief_grad), 1.0));
    vec3 L = normalize(light_dir);
    float diff = max(dot(n, L), 0.0);
    vec3 view = vec3(0.0, 0.0, 1.0);
    vec3 half_v = normalize(L + view);
    float spec = pow(max(dot(n, half_v), 0.0), 26.0);

    // Baked occlusion in the surface crevices; the base surface is lit + speckled.
    float ao = 0.8 + 0.2 * h0;
    vec3 surface = base.rgb * (0.16 + 1.0 * diff) * ao + vec3(0.9, 0.95, 1.0) * spec * 0.35;

    // The lettering is a brighter inlaid material that catches the light harder.
    vec3 ink = vec3(0.78, 0.86, 1.0) * (0.22 + 1.25 * diff) + vec3(1.0) * spec * 0.9;

    return mix(surface, ink, clamp(c, 0.0, 1.0));
}

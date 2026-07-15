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
    // Coverage as a height field. A *centered* difference over a wide `texel`
    // gives each stroke visible sloped sides (a single forward diff over 1px is
    // an invisibly thin rim) — the raking light then reveals the strokes as
    // relief, so they read as carved into the surface rather than painted flat.
    float c   = snail_text_sample_premul_linear(scene_pos).a;
    float cxp = snail_text_sample_premul_linear(scene_pos + vec2(texel.x, 0.0)).a;
    float cxn = snail_text_sample_premul_linear(scene_pos - vec2(texel.x, 0.0)).a;
    float cyp = snail_text_sample_premul_linear(scene_pos + vec2(0.0, texel.y)).a;
    float cyn = snail_text_sample_premul_linear(scene_pos - vec2(0.0, texel.y)).a;

    // Procedural rough-surface height gradient: fractal octaves for a stone feel.
    vec2 q = uv * 13.0;
    float e = 0.6;
    float h0 = snailGameHeight(q);
    float hx = snailGameHeight(q + vec2(e, 0.0));
    float hy = snailGameHeight(q + vec2(0.0, e));
    vec2 rough_grad = vec2(hx - h0, hy - h0) * roughness;

    // Text emboss: the strokes stand proud; their sloped sides tilt the normal.
    vec2 relief_grad = vec2(cxp - cxn, cyp - cyn) * (0.5 * relief);

    vec3 n = normalize(vec3(-(rough_grad + relief_grad), 1.0));
    vec3 L = normalize(light_dir);
    float diff = max(dot(n, L), 0.0);
    vec3 view = vec3(0.0, 0.0, 1.0);
    vec3 half_v = normalize(L + view);
    float spec = pow(max(dot(n, half_v), 0.0), 32.0);

    // One carved material: dark stone, with the strokes as a slightly brighter,
    // more reflective inlay. Crucially the inlay shares the *same* relief-lit
    // normal `n`, so the letters' shading comes from their bevels catching the
    // moving light — one side bright, the other in shadow — not from a flat fill.
    float ink = clamp(c, 0.0, 1.0);
    float ao = 0.85 + 0.15 * h0;
    vec3 albedo = mix(base.rgb, vec3(0.34, 0.40, 0.52), ink);
    vec3 lit = albedo * (0.13 + (0.85 + 0.45 * ink) * diff) * ao
             + vec3(0.85, 0.92, 1.0) * spec * (0.35 + 0.9 * ink);
    return lit;
}

// Shared renderer parameter ABI. Entry modules own target-specific bindings;
// this module owns the byte layout consumed by every built-in family.
module render_params;

public struct SnailPushConstants {
    public float4x4 mvp;
    public float2 viewport;
    public int subpixel_order;
    public int output_srgb;
    public int page_base;
    public float coverage_exponent;
    public float dither_scale;
    public int mask_output;
    public int2 atlas_page_texels;
};

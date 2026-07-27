// Portable binary16 decoding using only uint32/float32 operations. This keeps
// baseline GL 3.3 and GLES 3.0 free of native 16-bit feature requirements.
module binary16;

public float snailDecodeFloat16Exact(uint bits)
{
    bits &= 0xffffu;
    uint sign = (bits & 0x8000u) << 16u;
    uint exponent = (bits >> 10u) & 31u;
    uint fraction = bits & 1023u;
    if (exponent == 0u) {
        if (fraction == 0u) return asfloat(sign);
        float magnitude = float(fraction) * 5.960464477539063e-8;
        return sign == 0u ? magnitude : -magnitude;
    }
    if (exponent == 31u)
        return asfloat(sign | 0x7f800000u | (fraction << 13u));
    return asfloat(sign | ((exponent + 112u) << 23u) | (fraction << 13u));
}

// Instance colors deliberately use a finite decoder: corrupt infinities and
// NaNs saturate to binary16's largest finite magnitude before paint math.
public float snailDecodeFloat16Finite(uint bits)
{
    bits &= 0xffffu;
    uint exponent = (bits >> 10u) & 31u;
    if (exponent == 31u)
        return (bits & 0x8000u) == 0u ? 65504.0 : -65504.0;
    return snailDecodeFloat16Exact(bits);
}

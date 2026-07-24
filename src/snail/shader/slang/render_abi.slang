// Shared shader data-ABI constants. This module is the canonical shader-side
// definition; Zig tests keep these values byte-identical to the CPU ABI.
module render_abi;

public static const int SNAIL_RENDER_ABI_VERSION = 2;

public static const uint SNAIL_SPECIAL_GLYPH_MARKER = 0x80000000u;
public static const int SNAIL_SPECIAL_KIND_COLR = 0;
public static const int SNAIL_SPECIAL_KIND_PATH = 1;
public static const int SNAIL_SPECIAL_KIND_TT_HINTED_TEXT = 2;
public static const int SNAIL_SPECIAL_KIND_AUTOHINT = 3;

public static const int SNAIL_PAINT_KIND_SOLID = 1;
public static const int SNAIL_PAINT_KIND_LINEAR_GRADIENT = 2;
public static const int SNAIL_PAINT_KIND_RADIAL_GRADIENT = 3;
public static const int SNAIL_PAINT_KIND_IMAGE = 4;
public static const int SNAIL_PAINT_KIND_COMPOSITE_GROUP = 5;
public static const int SNAIL_PAINT_KIND_CONIC_GRADIENT = 6;

public static const int SNAIL_PAINT_TEXELS_PER_RECORD = 6;
public static const int SNAIL_PATH_COMPOSITE_MODE_FILL_STROKE_INSIDE = 1;

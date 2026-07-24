// Classified quadratic path fragment entry.
module path_quadratic;

import painted_family_common;
import path_family;

[shader("fragment")]
float4 fragmentMain(PaintedFragmentInput input) : SV_Target {
    return pathFragment<false, false>(input);
}

// Classified conic path fragment entry.
module path_conic;

import painted_family_common;
import path_family;

[shader("fragment")]
float4 fragmentMain(PaintedFragmentInput input) : SV_Target {
    return pathFragment<true, false>(input);
}

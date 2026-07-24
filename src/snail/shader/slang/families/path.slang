// Compatibility general-path entry. Cubics are lowered during preparation,
// so this is the conic-capable evaluator.
module path;

import painted_family_common;
import path_family;

[shader("fragment")]
float4 fragmentMain(PaintedFragmentInput input) : SV_Target {
    return pathFragment<true>(input);
}

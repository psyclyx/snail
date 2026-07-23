// COLR composites use the same immutable paint-record layout as paths; only
// the semantic instance kind (and therefore caller-selected program) differs.
void snailColrFragment() {
    snailPaintedFragment(SNAIL_SPECIAL_KIND_COLR);
}

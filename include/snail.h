/* snail — GPU font rendering via direct Bézier curve evaluation (Slug algorithm).
 *
 * Thread safety:
 *   - Font: immutable after init, safe for concurrent reads.
 *   - Atlas snapshots: immutable after init/extend/compact, safe for concurrent reads.
 *   - Batch (snail_batch_*): operates on caller-owned buffers. Multiple batches
 *     reading the same Atlas/Font from different threads is safe.
 *   - Renderer (snail_renderer_*): must be called from the GL thread only.
 *
 * Atlas handle stability:
 *   - Extending an atlas returns a new snapshot that preserves existing glyph
 *     handles and page-local positions.
 *   - Compacting returns a new snapshot and may change handles/page placement.
 *
 * Memory:
 *   - Pass NULL for allocator to use libc malloc/free.
 *   - Pass a SnailAllocator to use custom allocation.
 *
 * MIT License. */

#ifndef SNAIL_H
#define SNAIL_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Error codes ── */

#define SNAIL_OK             0
#define SNAIL_ERR_INVALID_FONT  -1
#define SNAIL_ERR_OUT_OF_MEMORY -2
#define SNAIL_ERR_GL_FAILED     -3

/* ── Allocator ── */

typedef void *(*SnailAllocFn)(void *ctx, size_t size, size_t alignment);
typedef void  (*SnailFreeFn)(void *ctx, void *ptr, size_t size);

typedef struct {
    SnailAllocFn alloc_fn;
    SnailFreeFn  free_fn;
    void        *ctx;
} SnailAllocator;

/* ── Opaque types ── */

typedef struct SnailFont  SnailFont;
typedef struct SnailAtlas SnailAtlas;

typedef struct {
    float min_x, min_y, max_x, max_y;
} SnailBBox;

typedef struct {
    uint16_t advance_width;
    int16_t lsb;
    SnailBBox bbox;
} SnailGlyphMetrics;

typedef struct {
    int16_t ascent;
    int16_t descent;
    int16_t line_gap;
} SnailLineMetrics;

/* ── Font (thread-safe after init) ── */

int      snail_font_init(const uint8_t *data, size_t len, SnailFont **out);
void     snail_font_deinit(SnailFont *font);
uint16_t snail_font_units_per_em(const SnailFont *font);
uint16_t snail_font_glyph_index(const SnailFont *font, uint32_t codepoint);
int16_t  snail_font_get_kerning(const SnailFont *font, uint16_t left, uint16_t right);
int      snail_font_line_metrics(const SnailFont *font, SnailLineMetrics *out);
/* Read direct glyph metrics from font tables without building an atlas. */
int      snail_font_glyph_metrics(const SnailFont *font, uint16_t glyph_id, SnailGlyphMetrics *out);
int      snail_font_advance_width(const SnailFont *font, uint16_t glyph_id, int16_t *out);
int      snail_font_bbox(const SnailFont *font, uint16_t glyph_id, SnailBBox *out);

/* ── Atlas snapshots (thread-safe after creation) ── */

int  snail_atlas_init(const SnailAllocator *allocator, /* NULL for libc */
                      const SnailFont *font,
                      const uint32_t *codepoints, size_t num_codepoints,
                      SnailAtlas **out);
/* Return a new atlas snapshot extended with any missing codepoints.
 * Existing handles remain valid in the returned snapshot. If no new glyphs are
 * needed, *out is set to NULL and SNAIL_OK is returned. */
int  snail_atlas_extend_codepoints(const SnailAtlas *atlas,
                                   const uint32_t *codepoints, size_t num_codepoints,
                                   SnailAtlas **out);
/* Return a new atlas snapshot extended with any missing glyph IDs.
 * Existing handles remain valid in the returned snapshot. If no new glyphs are
 * needed, *out is set to NULL and SNAIL_OK is returned. */
int  snail_atlas_extend_glyph_ids(const SnailAtlas *atlas,
                                  const uint16_t *glyph_ids, size_t num_glyph_ids,
                                  SnailAtlas **out);
/* Return a compacted atlas snapshot. Compaction may change glyph handles. */
int  snail_atlas_compact(const SnailAtlas *atlas, SnailAtlas **out);
/* Legacy compatibility helper: mutate an atlas handle in place by replacing it
 * with an extended snapshot. Not thread-safe with concurrent readers. */
int  snail_atlas_add_codepoints(SnailAtlas *atlas,
                                const uint32_t *codepoints, size_t num_codepoints,
                                bool *added);
void snail_atlas_deinit(SnailAtlas *atlas);

/* ── Renderer (GL thread only) ── */

int  snail_renderer_init(void);
void snail_renderer_deinit(void);
void snail_renderer_upload_atlas(const SnailAtlas *atlas);

#define SNAIL_SUBPIXEL_NONE 0
#define SNAIL_SUBPIXEL_RGB  1
#define SNAIL_SUBPIXEL_BGR  2
#define SNAIL_SUBPIXEL_VRGB 3
#define SNAIL_SUBPIXEL_VBGR 4
/* Ordered LCD subpixel AA: see SNAIL_SUBPIXEL_* constants above. */
void snail_renderer_set_subpixel_order(int order);
/* LCD policy: safe = axis-aligned text with safe per-channel blending when
 * supported, otherwise opaque-backdrop resolve or grayscale fallback;
 * legacy_unsafe = previous behavior with known compositing artifacts. */
#define SNAIL_SUBPIXEL_MODE_SAFE 0
#define SNAIL_SUBPIXEL_MODE_LEGACY_UNSAFE 1
void snail_renderer_set_subpixel_mode(int mode);
/* Opaque linear RGBA backdrop used by safe LCD fallback mode. Pass NULL to clear. */
void snail_renderer_set_subpixel_backdrop(const float *rgba_or_null);
/* Legacy convenience wrapper: true = RGB, false = off. */
void snail_renderer_set_subpixel(bool enabled);

/* Fill rule: 0 = non-zero winding (TrueType default), 1 = even-odd */
#define SNAIL_FILL_NONZERO 0
#define SNAIL_FILL_EVENODD 1
void snail_renderer_set_fill_rule(int rule);

/* mvp: 16 floats, column-major 4x4 matrix */
void snail_renderer_draw(const float *vertices, size_t num_floats,
                         const float *mvp,
                         float viewport_w, float viewport_h);

/* ── Batch (any thread, caller-owned buffer) ── */

/* Lay out and append glyph vertices for a UTF-8 string.
 * buf + *buf_len: write position. buf_capacity: total buffer size in floats.
 * color: 4 floats (RGBA). Returns advance width in pixels. */
float snail_batch_add_string(float *buf, size_t buf_capacity, size_t *buf_len,
                             const SnailAtlas *atlas, const SnailFont *font,
                             const char *text, size_t text_len,
                             float x, float y, float font_size,
                             const float *color);

/* Append pre-shaped glyphs (e.g. from HarfBuzz). Positions are pixel offsets
 * from (x, y). Returns number of glyphs added. */
size_t snail_batch_add_shaped(float *buf, size_t buf_capacity, size_t *buf_len,
                              const SnailAtlas *atlas,
                              const uint16_t *glyph_ids,
                              const float *x_offsets, const float *y_offsets,
                              size_t num_glyphs,
                              float x, float y, float font_size,
                              const float *color);

/* Lay out and append glyph vertices with word wrapping.
 * Returns total height used in pixels. */
float snail_batch_add_string_wrapped(float *buf, size_t buf_capacity, size_t *buf_len,
                                     const SnailAtlas *atlas, const SnailFont *font,
                                     const char *text, size_t text_len,
                                     float x, float y, float font_size,
                                     float max_width, float line_height,
                                     const float *color);

/* ── HarfBuzz (compile-time optional: -Dharfbuzz=true) ── */

/* Returns true if HarfBuzz support was compiled in. */
bool snail_harfbuzz_available(void);

/* Return a new atlas snapshot extended with any glyphs discovered by shaping
 * the given text. Existing handles remain valid in the returned snapshot.
 * If no new glyphs are needed, *out is set to NULL and SNAIL_OK is returned.
 * No-op if HarfBuzz not compiled in. */
int  snail_atlas_extend_glyphs_for_text(const SnailAtlas *atlas,
                                        const char *text, size_t text_len,
                                        SnailAtlas **out);
/* Legacy compatibility helper: mutate an atlas handle in place by replacing it
 * with an extended snapshot. Not thread-safe with concurrent readers. */
int  snail_atlas_add_glyphs_for_text(SnailAtlas *atlas,
                                     const char *text, size_t text_len,
                                     bool *added);

/* ── Constants ── */

size_t snail_floats_per_glyph(void);

#ifdef __cplusplus
}
#endif

#endif /* SNAIL_H */

/* snail — GPU font rendering via direct Bézier curve evaluation (Slug algorithm).
 *
 * Thread safety:
 *   - Font: immutable after init, safe for concurrent reads.
 *   - Atlas: immutable after init, safe for concurrent reads.
 *   - Batch (snail_batch_*): operates on caller-owned buffers. Multiple batches
 *     reading the same Atlas/Font from different threads is safe.
 *   - Renderer (snail_renderer_*): must be called from the GL thread only.
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

/* ── Font (thread-safe after init) ── */

int      snail_font_init(const uint8_t *data, size_t len, SnailFont **out);
void     snail_font_deinit(SnailFont *font);
uint16_t snail_font_units_per_em(const SnailFont *font);
uint16_t snail_font_glyph_index(const SnailFont *font, uint32_t codepoint);
int16_t  snail_font_get_kerning(const SnailFont *font, uint16_t left, uint16_t right);

/* ── Atlas (thread-safe after init) ── */

int  snail_atlas_init(const SnailAllocator *allocator, /* NULL for libc */
                      const SnailFont *font,
                      const uint32_t *codepoints, size_t num_codepoints,
                      SnailAtlas **out);
void snail_atlas_deinit(SnailAtlas *atlas);

/* ── Renderer (GL thread only) ── */

int  snail_renderer_init(void);
void snail_renderer_deinit(void);
void snail_renderer_upload_atlas(const SnailAtlas *atlas);
void snail_renderer_set_subpixel(bool enabled);

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

/* ── Constants ── */

size_t snail_floats_per_glyph(void);

#ifdef __cplusplus
}
#endif

#endif /* SNAIL_H */

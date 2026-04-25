/* snail — GPU font rendering via direct Bézier curve evaluation (Slug algorithm).
 *
 * Thread safety:
 *   - Font: immutable after init, safe for concurrent reads.
 *   - Atlas snapshots: immutable after init/extend/compact, safe for concurrent reads.
 *   - TextBatch (snail_batch_*): operates on caller-owned buffers. Multiple batches
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

typedef struct SnailFont              SnailFont;
typedef struct SnailAtlas             SnailAtlas;
typedef struct SnailShapedRun         SnailShapedRun;
typedef struct SnailImage             SnailImage;
typedef struct SnailPath              SnailPath;
typedef struct SnailPathPictureBuilder SnailPathPictureBuilder;
typedef struct SnailPathPicture       SnailPathPicture;

/* ── Value types ── */

typedef struct { float min_x, min_y, max_x, max_y; } SnailBBox;
typedef struct { float x, y, w, h; } SnailRect;
typedef struct { float xx, xy, tx, yx, yy, ty; } SnailTransform2D;

typedef struct {
    uint16_t advance_width;
    int16_t lsb;
    SnailBBox bbox;
} SnailGlyphMetrics;

typedef struct {
    int16_t ascent, descent, line_gap;
} SnailLineMetrics;

typedef struct {
    uint16_t glyph_id;
    float x_offset, y_offset;
    float x_advance, y_advance;
    uint32_t source_start, source_end;
} SnailGlyphPlacement;

/* ── Paint / style types ── */

#define SNAIL_PAINT_SOLID   0
#define SNAIL_PAINT_LINEAR  1
#define SNAIL_PAINT_RADIAL  2

#define SNAIL_EXTEND_CLAMP   0
#define SNAIL_EXTEND_REPEAT  1
#define SNAIL_EXTEND_REFLECT 2

typedef struct {
    float start_x, start_y, end_x, end_y;
    float start_color[4], end_color[4];
    int extend;
} SnailLinearGradient;

typedef struct {
    float center_x, center_y, radius;
    float inner_color[4], outer_color[4];
    int extend;
} SnailRadialGradient;

/* FillStyle: set paint_kind = -1 to use color only.
 * Set paint_kind to SNAIL_PAINT_SOLID/LINEAR/RADIAL and fill the
 * corresponding paint_solid/paint_linear/paint_radial field. */
typedef struct {
    float color[4];
    int paint_kind;
    float paint_solid[4];
    SnailLinearGradient paint_linear;
    SnailRadialGradient paint_radial;
} SnailFillStyle;

#define SNAIL_CAP_BUTT   0
#define SNAIL_CAP_SQUARE 1
#define SNAIL_CAP_ROUND  2

#define SNAIL_JOIN_MITER 0
#define SNAIL_JOIN_BEVEL 1
#define SNAIL_JOIN_ROUND 2

#define SNAIL_STROKE_CENTER 0
#define SNAIL_STROKE_INSIDE 1

typedef struct {
    float color[4];
    int paint_kind;
    float paint_solid[4];
    SnailLinearGradient paint_linear;
    SnailRadialGradient paint_radial;
    float width;
    int cap, join;
    float miter_limit;
    int placement;
} SnailStrokeStyle;

typedef struct { float u0, v0, u1, v1; } SnailSpriteUvRect;
typedef struct { float x, y; } SnailSpriteAnchor;

/* ── Identity transform helper ── */
#define SNAIL_TRANSFORM2D_IDENTITY ((SnailTransform2D){1,0,0, 0,1,0})

/* ── Font (thread-safe after init) ── */

int      snail_font_init(const uint8_t *data, size_t len, SnailFont **out);
void     snail_font_deinit(SnailFont *font);
uint16_t snail_font_units_per_em(const SnailFont *font);
uint16_t snail_font_glyph_index(const SnailFont *font, uint32_t codepoint);
int16_t  snail_font_get_kerning(const SnailFont *font, uint16_t left, uint16_t right);
int      snail_font_glyph_metrics(const SnailFont *font, uint16_t glyph_id, SnailGlyphMetrics *out);
int      snail_font_line_metrics(const SnailFont *font, SnailLineMetrics *out);
int      snail_font_advance_width(const SnailFont *font, uint16_t glyph_id, int16_t *out);
int      snail_font_bbox(const SnailFont *font, uint16_t glyph_id, SnailBBox *out);

/* ── Atlas snapshots (thread-safe after creation) ── */

int    snail_atlas_init(const SnailAllocator *alloc, const SnailFont *font,
                        const uint32_t *codepoints, size_t num, SnailAtlas **out);
int    snail_atlas_init_ascii(const SnailAllocator *alloc, const SnailFont *font,
                              SnailAtlas **out);
int    snail_atlas_extend_codepoints(const SnailAtlas *atlas,
                                     const uint32_t *codepoints, size_t num,
                                     SnailAtlas **out);
int    snail_atlas_extend_glyph_ids(const SnailAtlas *atlas,
                                    const uint16_t *ids, size_t num,
                                    SnailAtlas **out);
int    snail_atlas_extend_text(const SnailAtlas *atlas,
                               const char *text, size_t len,
                               SnailAtlas **out);
int    snail_atlas_extend_run(const SnailAtlas *atlas,
                              const SnailShapedRun *run,
                              SnailAtlas **out);
int    snail_atlas_compact(const SnailAtlas *atlas, SnailAtlas **out);
/* Legacy in-place extend (not thread-safe with concurrent readers). */
int    snail_atlas_add_codepoints(SnailAtlas *atlas,
                                  const uint32_t *codepoints, size_t num,
                                  bool *added);
void   snail_atlas_deinit(SnailAtlas *atlas);
size_t snail_atlas_page_count(const SnailAtlas *atlas);
size_t snail_atlas_texture_byte_len(const SnailAtlas *atlas);

/* ── Shaping ── */

/* Shape UTF-8 text into positioned glyph placements.
 * Uses the built-in limited shaper (GSUB ligatures + GPOS/kern kerning).
 * Caller must free the result with snail_shaped_run_deinit(). */
int    snail_atlas_shape_utf8(const SnailAtlas *atlas, const SnailFont *font,
                              const char *text, size_t text_len,
                              float font_size,
                              SnailShapedRun **out);
size_t snail_shaped_run_glyph_count(const SnailShapedRun *run);
/* Copy a single glyph placement by index. Returns false if out of bounds. */
bool   snail_shaped_run_glyph(const SnailShapedRun *run, size_t index,
                              SnailGlyphPlacement *out);
/* Copy all glyph placements into a caller-owned buffer. Returns count copied. */
size_t snail_shaped_run_copy_glyphs(const SnailShapedRun *run,
                                    SnailGlyphPlacement *out, size_t capacity);
float  snail_shaped_run_advance_x(const SnailShapedRun *run);
float  snail_shaped_run_advance_y(const SnailShapedRun *run);
void   snail_shaped_run_deinit(SnailShapedRun *run);

/* Write glyph IDs from `run` that are missing from `atlas` into `out`.
 * Returns the number of unique missing IDs written. */
size_t snail_atlas_collect_missing_glyph_ids(const SnailAtlas *atlas,
                                             const SnailShapedRun *run,
                                             uint16_t *out, size_t capacity);

/* ── Image ── */

int    snail_image_init_rgba8(const SnailAllocator *alloc,
                              uint32_t width, uint32_t height,
                              const uint8_t *pixels,
                              SnailImage **out);
void   snail_image_deinit(SnailImage *image);
uint32_t snail_image_width(const SnailImage *image);
uint32_t snail_image_height(const SnailImage *image);

/* ── Renderer (GL thread only) ── */

int  snail_renderer_init(void);
void snail_renderer_deinit(void);
void snail_renderer_upload_atlas(const SnailAtlas *atlas);
void snail_renderer_upload_image(SnailImage *image);
void snail_renderer_upload_path_picture(SnailPathPicture *picture);
void snail_renderer_begin_frame(void);

#define SNAIL_SUBPIXEL_NONE 0
#define SNAIL_SUBPIXEL_RGB  1
#define SNAIL_SUBPIXEL_BGR  2
#define SNAIL_SUBPIXEL_VRGB 3
#define SNAIL_SUBPIXEL_VBGR 4
void snail_renderer_set_subpixel_order(int order);
int  snail_renderer_subpixel_order(void);

#define SNAIL_SUBPIXEL_MODE_SAFE 0
#define SNAIL_SUBPIXEL_MODE_LEGACY_UNSAFE 1
void snail_renderer_set_subpixel_mode(int mode);
int  snail_renderer_subpixel_mode(void);

void snail_renderer_set_subpixel_backdrop(const float *rgba_or_null);
void snail_renderer_set_subpixel(bool enabled);

#define SNAIL_FILL_NONZERO 0
#define SNAIL_FILL_EVENODD 1
void snail_renderer_set_fill_rule(int rule);
int  snail_renderer_fill_rule(void);

const char *snail_renderer_backend_name(void);

/* mvp: 16 floats, column-major 4x4 matrix */
void snail_renderer_draw_text(const float *vertices, size_t num_floats,
                              const float *mvp,
                              float viewport_w, float viewport_h);
void snail_renderer_draw_paths(const float *vertices, size_t num_floats,
                               const float *mvp,
                               float viewport_w, float viewport_h);
void snail_renderer_draw_sprites(const float *vertices, size_t num_floats,
                                 const float *mvp,
                                 float viewport_w, float viewport_h);

/* ── TextBatch (any thread, caller-owned buffer) ── */

float  snail_batch_add_text(float *buf, size_t buf_capacity, size_t *buf_len,
                            const SnailAtlas *atlas, const SnailFont *font,
                            const char *text, size_t text_len,
                            float x, float y, float font_size,
                            const float *color);
size_t snail_batch_add_run(float *buf, size_t buf_capacity, size_t *buf_len,
                           const SnailAtlas *atlas,
                           const SnailShapedRun *run,
                           float x, float y, float font_size,
                           const float *color);
size_t snail_batch_glyph_count(size_t buf_len);

/* ── SpriteBatch (any thread, caller-owned buffer) ── */

bool snail_sprite_batch_add_sprite(float *buf, size_t buf_capacity, size_t *buf_len,
                                   const SnailImage *image,
                                   float pos_x, float pos_y,
                                   float size_x, float size_y,
                                   const float *tint);
bool snail_sprite_batch_add_sprite_rect(float *buf, size_t buf_capacity, size_t *buf_len,
                                        const SnailImage *image,
                                        SnailRect rect, const float *tint,
                                        SnailSpriteUvRect uv, int filter);
bool snail_sprite_batch_add_sprite_transformed(float *buf, size_t buf_capacity, size_t *buf_len,
                                               const SnailImage *image,
                                               float size_x, float size_y,
                                               const float *tint,
                                               SnailSpriteUvRect uv, int filter,
                                               SnailSpriteAnchor anchor,
                                               SnailTransform2D transform);

/* ── Path (any thread) ── */

int  snail_path_init(const SnailAllocator *alloc, SnailPath **out);
void snail_path_deinit(SnailPath *path);
void snail_path_reset(SnailPath *path);
bool snail_path_is_empty(const SnailPath *path);
bool snail_path_bounds(const SnailPath *path, SnailBBox *out);
int  snail_path_move_to(SnailPath *path, float x, float y);
int  snail_path_line_to(SnailPath *path, float x, float y);
int  snail_path_quad_to(SnailPath *path, float cx, float cy, float x, float y);
int  snail_path_cubic_to(SnailPath *path, float c1x, float c1y,
                         float c2x, float c2y, float x, float y);
int  snail_path_close(SnailPath *path);
int  snail_path_add_rect(SnailPath *path, SnailRect rect);
int  snail_path_add_rounded_rect(SnailPath *path, SnailRect rect, float radius);
int  snail_path_add_ellipse(SnailPath *path, SnailRect rect);

/* ── PathPictureBuilder (any thread) ── */

int  snail_path_picture_builder_init(const SnailAllocator *alloc,
                                     SnailPathPictureBuilder **out);
void snail_path_picture_builder_deinit(SnailPathPictureBuilder *builder);
/* fill and/or stroke may be NULL to skip that side. */
int  snail_path_picture_builder_add_path(SnailPathPictureBuilder *builder,
                                         const SnailPath *path,
                                         const SnailFillStyle *fill,
                                         const SnailStrokeStyle *stroke,
                                         SnailTransform2D transform);
int  snail_path_picture_builder_add_filled_path(SnailPathPictureBuilder *builder,
                                                const SnailPath *path,
                                                SnailFillStyle fill,
                                                SnailTransform2D transform);
int  snail_path_picture_builder_add_stroked_path(SnailPathPictureBuilder *builder,
                                                 const SnailPath *path,
                                                 SnailStrokeStyle stroke,
                                                 SnailTransform2D transform);
int  snail_path_picture_builder_add_rect(SnailPathPictureBuilder *builder,
                                         SnailRect rect,
                                         const SnailFillStyle *fill,
                                         const SnailStrokeStyle *stroke,
                                         SnailTransform2D transform);
int  snail_path_picture_builder_add_rounded_rect(SnailPathPictureBuilder *builder,
                                                 SnailRect rect,
                                                 const SnailFillStyle *fill,
                                                 const SnailStrokeStyle *stroke,
                                                 float corner_radius,
                                                 SnailTransform2D transform);
int  snail_path_picture_builder_add_ellipse(SnailPathPictureBuilder *builder,
                                            SnailRect rect,
                                            const SnailFillStyle *fill,
                                            const SnailStrokeStyle *stroke,
                                            SnailTransform2D transform);
int  snail_path_picture_builder_freeze(const SnailPathPictureBuilder *builder,
                                       const SnailAllocator *alloc,
                                       SnailPathPicture **out);

/* ── PathPicture (thread-safe after creation) ── */

void   snail_path_picture_deinit(SnailPathPicture *picture);
size_t snail_path_picture_shape_count(const SnailPathPicture *picture);

/* ── PathBatch (any thread, caller-owned buffer) ── */

size_t snail_path_batch_add_picture(float *buf, size_t buf_capacity, size_t *buf_len,
                                    const SnailPathPicture *picture);
size_t snail_path_batch_add_picture_transformed(float *buf, size_t buf_capacity,
                                                size_t *buf_len,
                                                const SnailPathPicture *picture,
                                                SnailTransform2D transform);

/* ── HarfBuzz (compile-time optional: -Dharfbuzz=true) ── */

bool snail_harfbuzz_available(void);
int  snail_atlas_extend_glyphs_for_text(const SnailAtlas *atlas,
                                        const char *text, size_t text_len,
                                        SnailAtlas **out);
/* Legacy in-place extend (not thread-safe). */
int  snail_atlas_add_glyphs_for_text(SnailAtlas *atlas,
                                     const char *text, size_t text_len,
                                     bool *added);

/* ── Constants ── */

size_t snail_text_floats_per_glyph(void);
size_t snail_text_floats_per_vertex(void);
size_t snail_text_vertices_per_glyph(void);
size_t snail_path_floats_per_shape(void);
size_t snail_sprite_floats_per_sprite(void);
size_t snail_floats_per_glyph(void); /* alias for snail_text_floats_per_glyph */

#ifdef __cplusplus
}
#endif

#endif /* SNAIL_H */

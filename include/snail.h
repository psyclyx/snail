/* snail - GPU font rendering via direct Bezier curve evaluation.
 *
 * C API model:
 *   - CPU values are owned handles: TextAtlas, ShapedText, TextBlob, Image,
 *     PathPicture, Scene, ResourceSet, PreparedResources, PreparedScene.
 *   - Resource upload is explicit: build a ResourceSet, upload it with a
 *     Renderer, then draw a PreparedScene.
 *   - Pass NULL for SnailAllocator to use libc malloc/free.
 *
 * MIT License. */

#ifndef SNAIL_H
#define SNAIL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "snail_generated.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Allocator */

typedef void *(*SnailAllocFn)(void *ctx, size_t size, size_t alignment);
typedef void (*SnailFreeFn)(void *ctx, void *ptr, size_t size);

typedef struct {
    SnailAllocFn alloc_fn;
    SnailFreeFn free_fn;
    void *ctx;
} SnailAllocator;

/* Value types */

typedef struct {
    float min_x, min_y, max_x, max_y;
} SnailBBox;

typedef struct {
    float x, y, w, h;
} SnailRect;

typedef struct {
    float data[16];
} SnailMat4;

typedef struct {
    float xx, xy, tx;
    float yx, yy, ty;
} SnailTransform2D;

#define SNAIL_TRANSFORM2D_IDENTITY ((SnailTransform2D){1, 0, 0, 0, 1, 0})

typedef struct {
    SnailTransform2D transform;
    float tint[4];
} SnailOverride;

#define SNAIL_OVERRIDE_IDENTITY ((SnailOverride){SNAIL_TRANSFORM2D_IDENTITY, {1, 1, 1, 1}})

typedef struct {
    size_t start;
    size_t count;
} SnailRange;

#define SNAIL_RANGE_ALL ((SnailRange){0, SIZE_MAX})

typedef struct {
    size_t shape_count;
} SnailShapeMark;

#define SNAIL_RESOURCE_CAPACITY_GROWABLE 0
#define SNAIL_RESOURCE_CAPACITY_EXACT 1

typedef struct {
    size_t curve_bytes_used;
    size_t curve_bytes_allocated;
    size_t band_bytes_used;
    size_t band_bytes_allocated;
    size_t layer_info_bytes_used;
    size_t layer_info_bytes_allocated;
    size_t image_bytes_used;
    size_t image_bytes_allocated;
} SnailResourceFootprint;

size_t snail_resource_footprint_used_bytes(SnailResourceFootprint footprint);
size_t snail_resource_footprint_allocated_bytes(SnailResourceFootprint footprint);

typedef struct {
    uint16_t advance_width;
    int16_t lsb;
    SnailBBox bbox;
} SnailGlyphMetrics;

typedef struct {
    int16_t ascent, descent, line_gap;
} SnailLineMetrics;

typedef struct {
    float cell_width, line_height;
} SnailCellMetrics;

typedef struct {
    float embolden;
    float skew_x;
} SnailSyntheticStyle;

typedef struct {
    const uint8_t *data;
    size_t len;
    int weight;
    bool italic;
    bool fallback;
    SnailSyntheticStyle synthetic;
} SnailFaceSpec;

typedef struct {
    int weight;
    bool italic;
} SnailFontStyle;

typedef struct {
    uint16_t face_index;
    uint16_t glyph_id;
    float x_offset, y_offset;
    float x_advance, y_advance;
    uint32_t source_start, source_end;
} SnailShapedGlyph;

typedef struct {
    float baseline_x, baseline_y;
    float em;
} SnailTextPlacement;

typedef struct {
    float pixel_width;
    float pixel_height;
    int subpixel_order;
    int fill_rule;
    bool is_final_composite;
    bool opaque_backdrop;
    bool will_resample;
    /* Explicit color encoding for this target.
     * framebuffer_encoding describes how the current framebuffer/attachment
     * interprets fragment outputs. Use SNAIL_COLOR_ENCODING_SRGB for GL/Vulkan
     * sRGB formats and SNAIL_COLOR_ENCODING_LINEAR for linear UNORM/float
     * targets and CPU byte buffers.
     *
     * pixel_encoding describes the encoding expected in the final stored
     * pixels. For normal sRGB displays, both fields are
     * SNAIL_COLOR_ENCODING_SRGB. For CPU byte buffers, framebuffer_encoding is
     * SNAIL_COLOR_ENCODING_LINEAR and pixel_encoding selects linear or sRGB
     * bytes. */
    int framebuffer_encoding;
    int pixel_encoding;
    /* Exponent applied to analytic coverage after edge evaluation.
     * 1.0 is identity; values below 1.0 strengthen antialiased edges and
     * values above 1.0 lighten them. */
    float coverage_exponent;
} SnailResolveTarget;

typedef struct {
    SnailMat4 mvp;
    SnailResolveTarget target;
} SnailDrawOptions;

typedef uint64_t SnailResourceKey;

/* Enums */

#define SNAIL_FONT_WEIGHT_THIN 1
#define SNAIL_FONT_WEIGHT_EXTRA_LIGHT 2
#define SNAIL_FONT_WEIGHT_LIGHT 3
#define SNAIL_FONT_WEIGHT_REGULAR 4
#define SNAIL_FONT_WEIGHT_MEDIUM 5
#define SNAIL_FONT_WEIGHT_SEMI_BOLD 6
#define SNAIL_FONT_WEIGHT_BOLD 7
#define SNAIL_FONT_WEIGHT_EXTRA_BOLD 8
#define SNAIL_FONT_WEIGHT_BLACK 9

#define SNAIL_PAINT_SOLID 0
#define SNAIL_PAINT_LINEAR 1
#define SNAIL_PAINT_RADIAL 2
#define SNAIL_PAINT_IMAGE 3

#define SNAIL_COLOR_ENCODING_LINEAR 0
#define SNAIL_COLOR_ENCODING_SRGB 1

#define SNAIL_EXTEND_CLAMP 0
#define SNAIL_EXTEND_REPEAT 1
#define SNAIL_EXTEND_REFLECT 2

#define SNAIL_IMAGE_FILTER_LINEAR 0
#define SNAIL_IMAGE_FILTER_NEAREST 1

#define SNAIL_CAP_BUTT 0
#define SNAIL_CAP_SQUARE 1
#define SNAIL_CAP_ROUND 2

#define SNAIL_JOIN_MITER 0
#define SNAIL_JOIN_BEVEL 1
#define SNAIL_JOIN_ROUND 2

#define SNAIL_STROKE_CENTER 0
#define SNAIL_STROKE_INSIDE 1

#define SNAIL_FILL_NONZERO 0
#define SNAIL_FILL_EVENODD 1

#define SNAIL_SUBPIXEL_NONE 0
#define SNAIL_SUBPIXEL_RGB 1
#define SNAIL_SUBPIXEL_BGR 2
#define SNAIL_SUBPIXEL_VRGB 3
#define SNAIL_SUBPIXEL_VBGR 4

/* Paint / style types */

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

typedef struct {
    const SnailImage *image;
    SnailTransform2D uv_transform;
    float tint[4];
    int extend_x, extend_y;
    int filter;
} SnailImagePaint;

typedef struct {
    int kind;
    float paint_solid[4];
    SnailLinearGradient paint_linear;
    SnailRadialGradient paint_radial;
    SnailImagePaint paint_image;
} SnailPaint;

typedef struct {
    SnailTextPlacement placement;
    SnailPaint fill;
} SnailTextAppendOptions;

typedef struct {
    SnailPaint paint;
} SnailFillStyle;

typedef struct {
    SnailPaint paint;
    float width;
    int cap, join;
    float miter_limit;
    int placement;
} SnailStrokeStyle;

/* Font metrics helper */

int snail_font_init(const uint8_t *data, size_t len, SnailFont **out);
void snail_font_deinit(SnailFont *font);
uint16_t snail_font_units_per_em(const SnailFont *font);
uint16_t snail_font_glyph_index(const SnailFont *font, uint32_t codepoint);
int16_t snail_font_get_kerning(const SnailFont *font, uint16_t left, uint16_t right);
int snail_font_glyph_metrics(const SnailFont *font, uint16_t glyph_id, SnailGlyphMetrics *out);
int snail_font_line_metrics(const SnailFont *font, SnailLineMetrics *out);
int snail_font_advance_width(const SnailFont *font, uint16_t glyph_id, int16_t *out);
int snail_font_bbox(const SnailFont *font, uint16_t glyph_id, SnailBBox *out);

/* Text atlas, shaping, and text blobs */

int snail_text_atlas_init(const SnailAllocator *alloc,
                          const SnailFaceSpec *specs,
                          size_t spec_count,
                          SnailTextAtlas **out);
void snail_text_atlas_deinit(SnailTextAtlas *atlas);
size_t snail_text_atlas_page_count(const SnailTextAtlas *atlas);
void snail_text_atlas_upload_footprint(const SnailTextAtlas *atlas,
                                       SnailResourceFootprint *out);
size_t snail_text_atlas_texture_byte_len(const SnailTextAtlas *atlas);
int snail_text_atlas_units_per_em(const SnailTextAtlas *atlas, uint16_t *out);
int snail_text_atlas_line_metrics(const SnailTextAtlas *atlas, SnailLineMetrics *out);
size_t snail_text_atlas_face_count(const SnailTextAtlas *atlas);
int snail_text_atlas_primary_face_index(const SnailTextAtlas *atlas, uint16_t *out);
int snail_text_atlas_face_units_per_em(const SnailTextAtlas *atlas,
                                       size_t face_index,
                                       uint16_t *out);
int snail_text_atlas_face_line_metrics(const SnailTextAtlas *atlas,
                                       size_t face_index,
                                       SnailLineMetrics *out);
int snail_text_atlas_glyph_index(const SnailTextAtlas *atlas,
                                 size_t face_index,
                                 uint32_t codepoint,
                                 uint16_t *out);
int snail_text_atlas_advance_width(const SnailTextAtlas *atlas,
                                   size_t face_index,
                                   uint16_t glyph_id,
                                   int16_t *out);
int snail_text_atlas_cell_metrics(const SnailTextAtlas *atlas,
                                  SnailFontStyle style,
                                  float em,
                                  SnailCellMetrics *out);
int snail_text_atlas_shape_utf8(const SnailTextAtlas *atlas,
                                SnailFontStyle style,
                                const char *text,
                                size_t text_len,
                                SnailShapedText **out);
int snail_text_atlas_ensure_text(const SnailTextAtlas *atlas,
                                 SnailFontStyle style,
                                 const char *text,
                                 size_t text_len,
                                 SnailTextAtlas **out);
int snail_text_atlas_ensure_shaped(const SnailTextAtlas *atlas,
                                   const SnailShapedText *shaped,
                                   SnailTextAtlas **out);
int snail_text_atlas_ensure_glyphs(const SnailTextAtlas *atlas,
                                   size_t face_index,
                                   const uint16_t *glyph_ids,
                                   size_t glyph_count,
                                   SnailTextAtlas **out);

void snail_shaped_text_deinit(SnailShapedText *shaped);
size_t snail_shaped_text_glyph_count(const SnailShapedText *shaped);
float snail_shaped_text_advance_x(const SnailShapedText *shaped);
float snail_shaped_text_advance_y(const SnailShapedText *shaped);
bool snail_shaped_text_glyph(const SnailShapedText *shaped, size_t index, SnailShapedGlyph *out);
size_t snail_shaped_text_copy_glyphs(const SnailShapedText *shaped,
                                     SnailShapedGlyph *out,
                                     size_t capacity);

int snail_text_blob_init_from_shaped(const SnailAllocator *alloc,
                                     const SnailTextAtlas *atlas,
                                     const SnailShapedText *shaped,
                                     SnailTextAppendOptions options,
                                     SnailTextBlob **out);
int snail_text_blob_init_text(const SnailAllocator *alloc,
                              const SnailTextAtlas *atlas,
                              SnailFontStyle style,
                              const char *text,
                              size_t text_len,
                              SnailTextAppendOptions options,
                              SnailTextBlob **out);
void snail_text_blob_deinit(SnailTextBlob *blob);
size_t snail_text_blob_glyph_count(const SnailTextBlob *blob);
int snail_text_blob_rebind(SnailTextBlob *blob, const SnailTextAtlas *atlas);

/* Images */

int snail_image_init_srgba8(const SnailAllocator *alloc,
                            uint32_t width,
                            uint32_t height,
                            const uint8_t *pixels,
                            SnailImage **out);
void snail_image_deinit(SnailImage *image);
uint32_t snail_image_width(const SnailImage *image);
uint32_t snail_image_height(const SnailImage *image);
void snail_image_upload_footprint(const SnailImage *image,
                                  SnailResourceFootprint *out);

/* Paths and path pictures */

int snail_path_init(const SnailAllocator *alloc, SnailPath **out);
void snail_path_deinit(SnailPath *path);
void snail_path_reset(SnailPath *path);
bool snail_path_is_empty(const SnailPath *path);
bool snail_path_bounds(const SnailPath *path, SnailBBox *out);
int snail_path_move_to(SnailPath *path, float x, float y);
int snail_path_line_to(SnailPath *path, float x, float y);
int snail_path_quad_to(SnailPath *path, float cx, float cy, float x, float y);
int snail_path_cubic_to(SnailPath *path, float c1x, float c1y,
                        float c2x, float c2y, float x, float y);
int snail_path_close(SnailPath *path);
int snail_path_add_rect(SnailPath *path, SnailRect rect);
int snail_path_add_rounded_rect(SnailPath *path, SnailRect rect, float radius);
int snail_path_add_ellipse(SnailPath *path, SnailRect rect);

int snail_path_picture_builder_init(const SnailAllocator *alloc, SnailPathPictureBuilder **out);
void snail_path_picture_builder_deinit(SnailPathPictureBuilder *builder);
size_t snail_path_picture_builder_shape_count(const SnailPathPictureBuilder *builder);
SnailShapeMark snail_path_picture_builder_mark(const SnailPathPictureBuilder *builder);
int snail_path_picture_builder_range_from(const SnailPathPictureBuilder *builder,
                                          SnailShapeMark mark,
                                          SnailRange *out);
int snail_path_picture_builder_range_between(const SnailPathPictureBuilder *builder,
                                             SnailShapeMark start,
                                             SnailShapeMark end,
                                             SnailRange *out);
int snail_path_picture_builder_add_path(SnailPathPictureBuilder *builder,
                                        const SnailPath *path,
                                        const SnailFillStyle *fill,
                                        const SnailStrokeStyle *stroke,
                                        SnailTransform2D transform);
int snail_path_picture_builder_add_filled_path(SnailPathPictureBuilder *builder,
                                               const SnailPath *path,
                                               SnailFillStyle fill,
                                               SnailTransform2D transform);
int snail_path_picture_builder_add_stroked_path(SnailPathPictureBuilder *builder,
                                                const SnailPath *path,
                                                SnailStrokeStyle stroke,
                                                SnailTransform2D transform);
int snail_path_picture_builder_add_rect(SnailPathPictureBuilder *builder,
                                        SnailRect rect,
                                        const SnailFillStyle *fill,
                                        const SnailStrokeStyle *stroke,
                                        SnailTransform2D transform);
int snail_path_picture_builder_add_rounded_rect(SnailPathPictureBuilder *builder,
                                                SnailRect rect,
                                                const SnailFillStyle *fill,
                                                const SnailStrokeStyle *stroke,
                                                float corner_radius,
                                                SnailTransform2D transform);
int snail_path_picture_builder_add_ellipse(SnailPathPictureBuilder *builder,
                                           SnailRect rect,
                                           const SnailFillStyle *fill,
                                           const SnailStrokeStyle *stroke,
                                           SnailTransform2D transform);
int snail_path_picture_builder_freeze(const SnailPathPictureBuilder *builder,
                                      const SnailAllocator *alloc,
                                      const SnailAllocator *scratch_alloc,
                                      SnailPathPicture **out);
void snail_path_picture_deinit(SnailPathPicture *picture);
size_t snail_path_picture_shape_count(const SnailPathPicture *picture);
void snail_path_picture_upload_footprint(const SnailPathPicture *picture,
                                         SnailResourceFootprint *out);

/* Scene and resources */

/*
 * Transformed/override submission helpers need their per-call override to
 * outlive the caller's stack, so the scene keeps it in an internal arena.
 * That arena grows monotonically until `snail_scene_reset` releases its
 * capacity for reuse — long-running streams of additions without a reset will
 * grow memory unboundedly. Call `snail_scene_reset` between frames or before
 * rebuilding a scene from scratch.
 */
int snail_scene_init(const SnailAllocator *alloc, SnailScene **out);
void snail_scene_deinit(SnailScene *scene);
void snail_scene_reset(SnailScene *scene);
size_t snail_scene_command_count(const SnailScene *scene);
int snail_scene_add_text(SnailScene *scene, const SnailTextBlob *blob);
int snail_scene_add_text_transformed(SnailScene *scene,
                                     const SnailTextBlob *blob,
                                     SnailTransform2D transform);
int snail_scene_add_text_override(SnailScene *scene,
                                  const SnailTextBlob *blob,
                                  SnailOverride override_value);
int snail_scene_add_path_picture(SnailScene *scene, const SnailPathPicture *picture);
int snail_scene_add_path_picture_range(SnailScene *scene,
                                       const SnailPathPicture *picture,
                                       SnailRange range);
int snail_scene_add_path_picture_transformed(SnailScene *scene,
                                             const SnailPathPicture *picture,
                                             SnailTransform2D transform);
int snail_scene_add_path_picture_range_transformed(SnailScene *scene,
                                                   const SnailPathPicture *picture,
                                                   SnailRange range,
                                                   SnailTransform2D transform);
int snail_scene_add_path_picture_override(SnailScene *scene,
                                          const SnailPathPicture *picture,
                                          SnailOverride override_value);
int snail_scene_add_path_picture_range_override(SnailScene *scene,
                                                const SnailPathPicture *picture,
                                                SnailRange range,
                                                SnailOverride override_value);

int snail_resource_set_init(const SnailAllocator *alloc, size_t capacity, SnailResourceSet **out);
void snail_resource_set_deinit(SnailResourceSet *set);
void snail_resource_set_reset(SnailResourceSet *set);
size_t snail_resource_set_count(const SnailResourceSet *set);
size_t snail_resource_set_capacity(const SnailResourceSet *set);
int snail_resource_set_put_text_atlas(SnailResourceSet *set,
                                      SnailResourceKey key,
                                      const SnailTextAtlas *atlas);
int snail_resource_set_put_text_atlas_options(SnailResourceSet *set,
                                              SnailResourceKey key,
                                              const SnailTextAtlas *atlas,
                                              int atlas_capacity);
int snail_resource_set_put_path_picture(SnailResourceSet *set,
                                        SnailResourceKey key,
                                        const SnailPathPicture *picture);
int snail_resource_set_put_path_picture_options(SnailResourceSet *set,
                                                SnailResourceKey key,
                                                const SnailPathPicture *picture,
                                                int atlas_capacity);
int snail_resource_set_put_image(SnailResourceSet *set,
                                 SnailResourceKey key,
                                 const SnailImage *image);
int snail_resource_set_estimate_upload_footprint(const SnailResourceSet *set,
                                                 SnailResourceFootprint *out);
int snail_resource_set_add_scene(SnailResourceSet *set, const SnailScene *scene);

void snail_prepared_resources_deinit(SnailPreparedResources *prepared);
int snail_prepared_scene_init(const SnailAllocator *alloc,
                              const SnailPreparedResources *prepared,
                              const SnailScene *scene,
                              SnailDrawOptions options,
                              SnailPreparedScene **out);
void snail_prepared_scene_deinit(SnailPreparedScene *scene);
size_t snail_prepared_scene_word_count(const SnailPreparedScene *scene);
size_t snail_prepared_scene_segment_count(const SnailPreparedScene *scene);

/* Renderer
 *
 * Construct renderers through backend headers such as snail_cpu.h,
 * snail_gl.h, and snail_vulkan.h, then use this erased renderer handle for
 * shared operations.
 */

void snail_renderer_deinit(SnailRenderer *renderer);
void snail_renderer_begin_frame(SnailRenderer *renderer);
int snail_renderer_set_subpixel_order(SnailRenderer *renderer, int order);
int snail_renderer_subpixel_order(const SnailRenderer *renderer);
int snail_renderer_set_fill_rule(SnailRenderer *renderer, int rule);
int snail_renderer_fill_rule(const SnailRenderer *renderer);
const char *snail_renderer_backend_name(const SnailRenderer *renderer);
int snail_renderer_upload_resources_blocking(SnailRenderer *renderer,
                                             const SnailAllocator *alloc,
                                             const SnailResourceSet *set,
                                             SnailPreparedResources **out);
int snail_renderer_draw_prepared(SnailRenderer *renderer,
                                 const SnailPreparedResources *prepared,
                                 const SnailPreparedScene *scene,
                                 SnailDrawOptions options);

/* Features and constants */

bool snail_harfbuzz_available(void);
size_t snail_text_words_per_glyph(void);
size_t snail_text_words_per_vertex(void);
size_t snail_text_vertices_per_glyph(void);
size_t snail_path_words_per_shape(void);
size_t snail_path_words_per_vertex(void);
size_t snail_path_vertices_per_shape(void);
SnailMat4 snail_mat4_identity(void);

#ifdef __cplusplus
}
#endif

#endif /* SNAIL_H */

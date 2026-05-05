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

#ifdef __cplusplus
extern "C" {
#endif

/* Error codes */

#define SNAIL_OK 0
#define SNAIL_ERR_INVALID_FONT -1
#define SNAIL_ERR_OUT_OF_MEMORY -2
#define SNAIL_ERR_RENDERER_FAILED -3
#define SNAIL_ERR_INVALID_ARGUMENT -4
#define SNAIL_ERR_DRAW_FAILED -5

/* Allocator */

typedef void *(*SnailAllocFn)(void *ctx, size_t size, size_t alignment);
typedef void (*SnailFreeFn)(void *ctx, void *ptr, size_t size);

typedef struct {
    SnailAllocFn alloc_fn;
    SnailFreeFn free_fn;
    void *ctx;
} SnailAllocator;

/* Opaque handles */

typedef struct SnailFont SnailFont;
typedef struct SnailTextAtlas SnailTextAtlas;
typedef struct SnailShapedText SnailShapedText;
typedef struct SnailTextBlob SnailTextBlob;
typedef struct SnailImage SnailImage;
typedef struct SnailPath SnailPath;
typedef struct SnailPathPictureBuilder SnailPathPictureBuilder;
typedef struct SnailPathPicture SnailPathPicture;
typedef struct SnailScene SnailScene;
typedef struct SnailResourceSet SnailResourceSet;
typedef struct SnailPreparedResources SnailPreparedResources;
typedef struct SnailPreparedScene SnailPreparedScene;
typedef struct SnailRenderer SnailRenderer;

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
    uint16_t advance_width;
    int16_t lsb;
    SnailBBox bbox;
} SnailGlyphMetrics;

typedef struct {
    int16_t ascent, descent, line_gap;
} SnailLineMetrics;

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
    float x, y, size;
    float color[4];
} SnailTextBlobOptions;

typedef struct {
    int hinting;
} SnailTextResolveOptions;

typedef struct {
    float pixel_width;
    float pixel_height;
    int subpixel_order;
    int fill_rule;
    bool is_final_composite;
    bool opaque_backdrop;
    bool will_resample;
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

#define SNAIL_TEXT_HINT_NONE 0
#define SNAIL_TEXT_HINT_PHASE 1
#define SNAIL_TEXT_HINT_METRICS 2
#define SNAIL_TEXT_HINT_OUTLINE 3

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
    float color[4];
    int paint_kind; /* -1 uses color; otherwise SNAIL_PAINT_* */
    float paint_solid[4];
    SnailLinearGradient paint_linear;
    SnailRadialGradient paint_radial;
    SnailImagePaint paint_image;
} SnailFillStyle;

typedef struct {
    float color[4];
    int paint_kind;
    float paint_solid[4];
    SnailLinearGradient paint_linear;
    SnailRadialGradient paint_radial;
    SnailImagePaint paint_image;
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
size_t snail_text_atlas_texture_byte_len(const SnailTextAtlas *atlas);
int snail_text_atlas_units_per_em(const SnailTextAtlas *atlas, uint16_t *out);
int snail_text_atlas_line_metrics(const SnailTextAtlas *atlas, SnailLineMetrics *out);
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
                                     SnailTextBlobOptions options,
                                     SnailTextBlob **out);
int snail_text_blob_init_text(const SnailAllocator *alloc,
                              const SnailTextAtlas *atlas,
                              SnailFontStyle style,
                              const char *text,
                              size_t text_len,
                              SnailTextBlobOptions options,
                              SnailTextBlob **out);
void snail_text_blob_deinit(SnailTextBlob *blob);
size_t snail_text_blob_glyph_count(const SnailTextBlob *blob);

/* Images */

int snail_image_init_srgba8(const SnailAllocator *alloc,
                            uint32_t width,
                            uint32_t height,
                            const uint8_t *pixels,
                            SnailImage **out);
void snail_image_deinit(SnailImage *image);
uint32_t snail_image_width(const SnailImage *image);
uint32_t snail_image_height(const SnailImage *image);

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
                                      SnailPathPicture **out);
void snail_path_picture_deinit(SnailPathPicture *picture);
size_t snail_path_picture_shape_count(const SnailPathPicture *picture);

/* Scene and resources */

/*
 * `snail_scene_add_text_options` and
 * `snail_scene_add_path_picture_transformed` need to outlive the caller's
 * stack, so the scene keeps a per-call override in an internal arena. That
 * arena grows monotonically until `snail_scene_reset` releases its capacity
 * for reuse — long-running streams of additions without a reset will grow
 * memory unboundedly. Call `snail_scene_reset` between frames or before
 * rebuilding a scene from scratch.
 */
int snail_scene_init(const SnailAllocator *alloc, SnailScene **out);
void snail_scene_deinit(SnailScene *scene);
void snail_scene_reset(SnailScene *scene);
size_t snail_scene_command_count(const SnailScene *scene);
int snail_scene_add_text(SnailScene *scene, const SnailTextBlob *blob);
int snail_scene_add_text_options(SnailScene *scene,
                                 const SnailTextBlob *blob,
                                 SnailTransform2D transform,
                                 SnailTextResolveOptions resolve);
int snail_scene_add_path_picture(SnailScene *scene, const SnailPathPicture *picture);
int snail_scene_add_path_picture_transformed(SnailScene *scene,
                                             const SnailPathPicture *picture,
                                             SnailTransform2D transform);

int snail_resource_set_init(const SnailAllocator *alloc, size_t capacity, SnailResourceSet **out);
void snail_resource_set_deinit(SnailResourceSet *set);
void snail_resource_set_reset(SnailResourceSet *set);
size_t snail_resource_set_count(const SnailResourceSet *set);
size_t snail_resource_set_capacity(const SnailResourceSet *set);
int snail_resource_set_put_text_atlas(SnailResourceSet *set,
                                      SnailResourceKey key,
                                      const SnailTextAtlas *atlas);
int snail_resource_set_put_path_picture(SnailResourceSet *set,
                                        SnailResourceKey key,
                                        const SnailPathPicture *picture);
int snail_resource_set_put_image(SnailResourceSet *set,
                                 SnailResourceKey key,
                                 const SnailImage *image);
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

/* Renderer */

int snail_renderer_init(SnailRenderer **out);
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

/* Generated from src/snail/c_api/manifest.zig by tools/gen_c_api.zig. */
#ifndef SNAIL_GENERATED_H
#define SNAIL_GENERATED_H

/* Error codes */
#define SNAIL_OK 0
#define SNAIL_ERR_INVALID_FONT -1
#define SNAIL_ERR_OUT_OF_MEMORY -2
#define SNAIL_ERR_RENDERER_FAILED -3
#define SNAIL_ERR_INVALID_ARGUMENT -4
#define SNAIL_ERR_DRAW_FAILED -5

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

#endif /* SNAIL_GENERATED_H */

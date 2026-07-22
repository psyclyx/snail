const std = @import("std");
const snail = @import("snail");
const raster = @import("snail-raster");

test "core and external renderers need only the intentional public api" {
    comptime {
        if (@hasDecl(snail, "core")) @compileError("snail.core must not be public");
        if (@hasDecl(snail, "files")) @compileError("snail.files must not be public");
        if (@hasDecl(snail.render, "cache")) @compileError("cache policy belongs to renderer implementations");
        if (@hasDecl(snail.render, "range_allocator")) @compileError("cache allocation belongs to renderer implementations");
        if (@hasDecl(snail.render, "paint_records")) @compileError("paint encoding is not a renderer contract");
        if (@hasDecl(snail.render, "upload")) @compileError("upload patching is owned by atlas_upload.Planner");
        if (@hasDecl(snail.render, "subpixel")) @compileError("pipeline selection belongs to renderer implementations");
        if (@hasDecl(snail, "DrawState")) @compileError("draw state belongs to renderer implementations");
        if (@hasDecl(snail, "TargetSurface")) @compileError("target policy belongs to renderer implementations");
        if (@hasDecl(snail, "SubpixelOrder")) @compileError("subpixel policy belongs to renderer implementations");
        if (@hasDecl(snail, "Instance")) @compileError("renderer ABI belongs under snail.render.records");
        if (@hasDecl(snail, "WORDS_PER_INSTANCE")) @compileError("renderer ABI belongs under snail.render.records");
        if (@hasDecl(snail, "DrawBatch")) @compileError("draw records belong under snail.render.records");
        if (@hasDecl(snail, "Binding")) @compileError("draw records belong under snail.render.records");
        if (@hasDecl(snail, "RecordKey")) @compileError("record-key names belong under snail.record_key");
        if (@hasDecl(snail, "ns")) @compileError("record-key names belong under snail.record_key");
        if (@hasDecl(snail, "tt")) @compileError("TrueType implementation internals must not be public");
        if (@hasDecl(snail.font, "tt")) @compileError("TrueType implementation internals must not be public through font");
        if (@hasDecl(snail, "AtlasPage")) @compileError("raw mutable atlas pages must not be public");
        if (@hasDecl(snail, "AtlasUploadPlanner")) @compileError("upload planner types belong under snail.atlas_upload");
        if (@hasDecl(snail, "OwnedAtlasUploadPlanner")) @compileError("upload planner types belong under snail.atlas_upload");
        if (@hasDecl(snail.autohint, "analysis")) @compileError("autohint analysis implementation must not be public");
        if (@hasDecl(snail.autohint, "warp")) @compileError("runtime warp implementation must not be public");
        if (@hasDecl(snail.autohint, "blue")) @compileError("blue-zone implementation must not be public");
        if (@hasDecl(snail.autohint, "producer")) @compileError("producer implementation namespace must not be public");
        if (@hasDecl(snail.Faces, "face")) @compileError("Faces must not expose HarfBuzz-owning FaceState values");
        if (@hasField(snail.Faces, "font_count")) @compileError("the sparse font-id space has no meaningful dense count");
        if (@hasField(snail.Faces, "faces") or @hasField(snail.Faces, "chains") or
            @hasField(snail.Faces, "face_to_font_id") or @hasField(snail.Faces, "missing_glyph_replacement"))
        {
            @compileError("Faces ownership and fallback storage must remain type-erased");
        }
        if (@hasDecl(snail.PagePool, "acquire")) @compileError("raw page acquisition must remain internal");
        if (@hasDecl(snail.PagePool, "release")) @compileError("raw page recycling must remain internal");
        if (@hasDecl(snail.atlas_upload, "Atlas") or @hasDecl(snail.atlas_upload, "PagePool") or
            @hasDecl(snail.atlas_upload, "Binding"))
        {
            @compileError("atlas_upload must not duplicate root and render-record type names");
        }

        const AtlasPagePointer = @typeInfo(@FieldType(snail.Atlas, "pages")).pointer.child;
        const AtlasPageType = @typeInfo(AtlasPagePointer).pointer.child;
        switch (@typeInfo(AtlasPageType)) {
            .@"opaque" => {},
            else => @compileError("Atlas.pages must expose only opaque page handles"),
        }
        if (@hasDecl(raster.Renderer, "drawBatch")) @compileError("prepared-resource drawing is package-private; use raster.draw");

        _ = snail.TextDirection;
        _ = snail.ConicGradient;
        _ = snail.autohint.AutohintAnalyzer;
        _ = snail.autohint.AutohintPolicy;
        _ = snail.autohint.FeatureEdge;
        _ = snail.autohint.GlyphFeatures;
        _ = snail.autohint.FontFeatures;
        _ = snail.autohint.max_features_per_axis;
        _ = snail.Faces.fontForFace;
        _ = snail.PagePool.config;
        _ = snail.render.records.abi_version;
        _ = snail.render.records.BYTES_PER_INSTANCE;
        _ = snail.render.records.DrawRecords;
        _ = snail.render.records.DrawBatch;
        _ = snail.render.records.ShapeKind;
        _ = snail.render.records.unpackBandCounts;
        _ = snail.render.geometry.autohint.DecodedRecord;
        _ = snail.render.geometry.autohint.DecodeError;
        _ = snail.render.geometry.autohint.decode;
        if (@hasDecl(snail.render.geometry.autohint, "readBandEntry") or
            @hasDecl(snail.render.geometry.autohint, "fontFeatures") or
            @hasDecl(snail.render.geometry.autohint, "xFeatures") or
            @hasDecl(snail.render.geometry.autohint, "yFeatures"))
        {
            @compileError("raw autohint field decoders must not bypass record validation");
        }
        _ = snail.atlas_upload.Planner;
        _ = snail.atlas_upload.OwnedPlanner;
        _ = snail.atlas_upload.Region;
        _ = snail.shader.glsl.source(.coverage_common);
        _ = snail.shader.glsl.fileName(.coverage_common);
        _ = snail.shader.glsl.dependencies.regular_text;
        if (@hasDecl(snail.shader, "generated")) @compileError("the generated catalog moved to the snail-shaders module");
        if (@hasDecl(snail.shader.glsl, "ATLAS_SET")) @compileError("descriptor layouts belong to callers");
        if (@hasDecl(snail.shader.glsl, "RECORDS_SET")) @compileError("descriptor layouts belong to callers");
        if (@hasDecl(snail.shader, "wgsl")) @compileError("the generated per-target catalog replaced shader.wgsl");
        if (@hasDecl(snail.shader, "slang_generated")) @compileError("the generated catalog is the snail-shaders module");

        _ = raster.Renderer;
        _ = raster.DeviceAtlas;
        _ = raster.DeviceAtlasOptions;
        _ = raster.UploadError;
        _ = raster.ResizeError;
        _ = raster.ThreadPool;
        _ = raster.DrawRecords;
        _ = raster.draw;
        _ = raster.DrawState;
        _ = raster.TargetSurface;
        _ = raster.SubpixelOrder;
    }

    var pool = try snail.PagePool.init(std.testing.allocator, .{
        .max_layers = 1,
        .curve_words_per_page = 64,
        .band_words_per_page = 32,
    });
    defer pool.deinit();

    const options = snail.atlas_upload.Options{
        .max_bindings = 1,
        .layer_info_height = 1,
        .max_images = 0,
        .max_image_width = 0,
        .max_image_height = 0,
    };
    const sizes = try snail.atlas_upload.sizes(pool, options);
    try std.testing.expectEqual(@as(usize, 1), sizes.bindings);
    try std.testing.expect(sizes.regions > 0);

    try std.testing.expectEqual(
        @as(?snail.render.records.BandCounts, null),
        snail.render.records.unpackBandCounts(0x0000ffff),
    );
    try std.testing.expectError(
        error.BufferTooSmall,
        snail.render.geometry.autohint.decode(&.{}, std.math.maxInt(usize)),
    );
}

const std = @import("std");
const snail = @import("snail");
const raster = @import("snail-raster");
const generated = @import("snail_shaders");

test "external renderers need only the public snail api" {
    comptime {
        if (@hasDecl(snail, "core")) @compileError("snail.core must not be public");
        if (@hasDecl(snail, "files")) @compileError("snail.files must not be public");
        if (@hasDecl(snail.render, "cache")) @compileError("cache policy belongs to renderer implementations");
        if (@hasDecl(snail.render, "range_allocator")) @compileError("cache allocation belongs to renderer implementations");
        if (@hasDecl(snail.render, "paint_records")) @compileError("paint encoding is not a renderer contract");
        if (@hasDecl(snail.render, "upload")) @compileError("upload patching is owned by AtlasUploadPlanner");
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

        _ = snail.TextDirection;
        _ = snail.ConicGradient;
        _ = snail.render.records.abi_version;
        _ = snail.render.records.BYTES_PER_INSTANCE;
        _ = snail.render.records.DrawRecords;
        _ = snail.render.records.DrawBatch;
        _ = snail.render.records.ShapeKind;
        _ = snail.OwnedAtlasUploadPlanner;
        _ = snail.shader.glsl.source(.coverage_common);
        _ = snail.shader.glsl.fileName(.coverage_common);
        _ = snail.shader.glsl.dependencies.regular_text;
        // The generated per-target catalog is the separate `snail-shaders`
        // module (build-time artifacts; needs the Slang toolchain) — the
        // `snail` module itself must stay toolchain-free.
        if (@hasDecl(snail.shader, "generated")) @compileError("the generated catalog moved to the snail-shaders module");
        _ = generated.textSpv(.fragment);
        _ = generated.textWgsl(.fragment);
        _ = generated.textSampleFragGlsl330();
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
}

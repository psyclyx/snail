const std = @import("std");
const snail = @import("snail");
const raster = @import("snail-raster");

test "external renderers need only the public snail api" {
    comptime {
        if (@hasDecl(snail, "core")) @compileError("snail.core must not be public");
        if (@hasDecl(snail, "files")) @compileError("snail.files must not be public");
        if (@hasDecl(snail.render, "cache")) @compileError("cache policy belongs to renderer implementations");
        if (@hasDecl(snail.render, "range_allocator")) @compileError("cache allocation belongs to renderer implementations");
        if (@hasDecl(snail.render, "paint_records")) @compileError("paint encoding is not a renderer contract");
        if (@hasDecl(snail.render, "upload")) @compileError("upload patching is owned by AtlasUploadPlanner");
        if (@hasDecl(snail.render, "subpixel")) @compileError("pipeline selection belongs to renderer implementations");

        _ = snail.render.records.abi_version;
        _ = snail.render.records.WORDS_PER_INSTANCE;
        _ = snail.render.atlas.CURVE_TEX_WIDTH;
        _ = snail.render.atlas.BAND_TEX_WIDTH;
        _ = snail.render.atlas.INFO_WIDTH;
        _ = snail.render.records.DrawRecords;
        _ = snail.render.records.ShapeKind;
        _ = snail.shader.glsl.shader_library.coverage_functions;
        _ = snail.shader.glsl.embeddable.GlShaderSources.fragment_body;
        _ = snail.shader.vulkan.embeddable.records_interface_include;

        _ = raster.Renderer;
        _ = raster.BackendCache;
        _ = raster.CacheOptions;
        _ = raster.UploadError;
        _ = raster.ResizeError;
        _ = raster.ThreadPool;
        _ = raster.DrawRecords;
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
    const sizes = snail.atlas_upload.sizes(pool, options);
    try std.testing.expectEqual(@as(usize, 1), sizes.bindings);
    try std.testing.expect(sizes.regions > 0);
}

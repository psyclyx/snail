const std = @import("std");
const snail = @import("snail");
const raster = @import("snail-raster");

test "external renderers need only the public snail api" {
    comptime {
        if (@hasDecl(snail, "core")) @compileError("snail.core must not be public");
        if (@hasDecl(snail, "files")) @compileError("snail.files must not be public");

        _ = snail.render.abi.version;
        _ = snail.render.vertex.WORDS_PER_INSTANCE;
        _ = snail.render.curve_texture.TEX_WIDTH;
        _ = snail.render.band_texture.TEX_WIDTH;
        _ = snail.render.paint_records.info_width;
        _ = snail.render.draw_records.DrawRecords;
        _ = snail.render.subpixel.TextRenderMode;
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

const common = @import("common.zig");
const std = common.std;
const snail = common.snail;
const createHandle = common.createHandle;
const createHandleSharingAllocator = common.createHandleSharingAllocator;
const allocatorForHandle = common.allocatorForHandle;
const mapError = common.mapError;
const SnailAllocator = common.SnailAllocator;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_INVALID_FONT = common.SNAIL_ERR_INVALID_FONT;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SNAIL_ERR_INVALID_ARGUMENT = common.SNAIL_ERR_INVALID_ARGUMENT;
const SnailLineMetrics = common.SnailLineMetrics;
const SnailScriptTransform = common.SnailScriptTransform;
const SnailCellMetrics = common.SnailCellMetrics;
const SnailRect = common.SnailRect;
const SnailRange = common.SnailRange;
const SnailFaceSpec = common.SnailFaceSpec;
const SnailFontStyle = common.SnailFontStyle;
const SnailShapedGlyph = common.SnailShapedGlyph;
const SnailTextAppendOptions = common.SnailTextAppendOptions;
const SnailTextAppendResult = common.SnailTextAppendResult;
const SnailTextPlacement = common.SnailTextPlacement;
const SnailResourceKey = common.SnailResourceKey;
const SnailTrueTypeHintPpem = common.SnailTrueTypeHintPpem;
const SnailTrueTypeHintRunStats = common.SnailTrueTypeHintRunStats;
const SnailResourceFootprint = common.SnailResourceFootprint;
const wrapScriptTransform = common.wrapScriptTransform;
const toSnailRect = common.toSnailRect;
const fromResourceFootprint = common.fromResourceFootprint;
const fromTextAppendResult = common.fromTextAppendResult;
const toSyntheticStyle = common.toSyntheticStyle;
const toFontWeight = common.toFontWeight;
const toFontStyle = common.toFontStyle;
const toDecoration = common.toDecoration;
const toRange = common.toRange;
const toTextPlacement = common.toTextPlacement;
const toTrueTypeHintPpem = common.toTrueTypeHintPpem;
const fromTrueTypeHintRunStats = common.fromTrueTypeHintRunStats;
const toPaint = common.toPaint;
const TextAtlasImpl = common.TextAtlasImpl;
const ShapedTextImpl = common.ShapedTextImpl;
const TextBlobImpl = common.TextBlobImpl;
const TrueTypeHintContextImpl = common.TrueTypeHintContextImpl;
const TrueTypePreparedHintRunImpl = common.TrueTypePreparedHintRunImpl;
const destroyHandle = common.destroyHandle;

// TextAtlas and shaping

pub export fn snail_text_atlas_init(
    alloc_ptr: ?*const SnailAllocator,
    specs: [*]const SnailFaceSpec,
    spec_count: usize,
    out: *?*TextAtlasImpl,
) c_int {
    if (spec_count == 0) return SNAIL_ERR_INVALID_ARGUMENT;
    const impl = createHandle(TextAtlasImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const zig_specs = allocator.alloc(snail.FaceSpec, spec_count) catch {
        destroyHandle(impl);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };

    for (specs[0..spec_count], 0..) |spec, i| {
        const weight = toFontWeight(spec.weight) catch {
            allocator.free(zig_specs);
            destroyHandle(impl);
            return SNAIL_ERR_INVALID_ARGUMENT;
        };
        zig_specs[i] = .{
            .data = spec.data[0..spec.len],
            .weight = weight,
            .italic = spec.italic,
            .fallback = spec.fallback,
            .synthetic = toSyntheticStyle(spec.synthetic),
        };
    }

    const atlas = snail.TextAtlas.init(allocator, zig_specs) catch |err| {
        allocator.free(zig_specs);
        destroyHandle(impl);
        return mapError(err);
    };
    allocator.free(zig_specs);
    impl.inner = atlas;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_text_atlas_deinit(atlas: ?*TextAtlasImpl) void {
    if (atlas) |a| {
        a.inner.deinit();
        destroyHandle(a);
    }
}

pub export fn snail_text_atlas_page_count(atlas: *const TextAtlasImpl) usize {
    return atlas.inner.pageCount();
}

pub export fn snail_text_atlas_upload_footprint(atlas: *const TextAtlasImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(atlas.inner.uploadFootprint());
}

pub export fn snail_text_atlas_texture_byte_len(atlas: *const TextAtlasImpl) usize {
    var total: usize = 0;
    for (atlas.inner.pageSlice()) |page| total += page.textureBytes();
    if (atlas.inner.layer_info_data) |data| total += data.len * @sizeOf(f32);
    return total;
}

pub export fn snail_text_atlas_units_per_em(atlas: *const TextAtlasImpl, out: *u16) c_int {
    out.* = atlas.inner.unitsPerEm() catch return SNAIL_ERR_INVALID_FONT;
    return SNAIL_OK;
}

pub export fn snail_text_atlas_line_metrics(atlas: *const TextAtlasImpl, out: *SnailLineMetrics) c_int {
    const m = atlas.inner.lineMetrics() catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

pub export fn snail_text_atlas_face_count(atlas: *const TextAtlasImpl) usize {
    return atlas.inner.faceCount();
}

pub export fn snail_text_atlas_primary_face_index(atlas: *const TextAtlasImpl, out: *u16) c_int {
    out.* = atlas.inner.primaryFaceIndex() catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_atlas_face_units_per_em(atlas: *const TextAtlasImpl, face_index: usize, out: *u16) c_int {
    out.* = atlas.inner.faceUnitsPerEm(face_index) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_atlas_face_line_metrics(atlas: *const TextAtlasImpl, face_index: usize, out: *SnailLineMetrics) c_int {
    const m = atlas.inner.faceLineMetrics(face_index) catch |err| return mapError(err);
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

pub export fn snail_text_atlas_glyph_index(atlas: *const TextAtlasImpl, face_index: usize, codepoint: u32, out: *u16) c_int {
    const cp = std.math.cast(u21, codepoint) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    out.* = (atlas.inner.glyphIndex(face_index, cp) catch |err| return mapError(err)) orelse 0;
    return SNAIL_OK;
}

pub export fn snail_text_atlas_advance_width(atlas: *const TextAtlasImpl, face_index: usize, glyph_id: u16, out: *i16) c_int {
    out.* = atlas.inner.advanceWidth(face_index, glyph_id) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_atlas_cell_metrics(atlas: *const TextAtlasImpl, style: SnailFontStyle, em: f32, out: *SnailCellMetrics) c_int {
    const metrics = atlas.inner.cellMetrics(.{
        .style = toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT,
        .em = em,
    }) catch |err| return mapError(err);
    out.* = .{ .cell_width = metrics.cell_width, .line_height = metrics.line_height };
    return SNAIL_OK;
}

pub export fn snail_text_atlas_measure_text(
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    font_size: f32,
    out: *f32,
) c_int {
    out.* = atlas.inner.measureText(toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT, text[0..text_len], font_size) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_atlas_decoration_rect(
    atlas: *const TextAtlasImpl,
    decoration: c_int,
    x: f32,
    y: f32,
    advance: f32,
    font_size: f32,
    out: *SnailRect,
) c_int {
    out.* = toSnailRect(atlas.inner.decorationRect(toDecoration(decoration) catch return SNAIL_ERR_INVALID_ARGUMENT, x, y, advance, font_size) catch |err| return mapError(err));
    return SNAIL_OK;
}

pub export fn snail_text_atlas_superscript_transform(atlas: *const TextAtlasImpl, x: f32, y: f32, font_size: f32, out: *SnailScriptTransform) c_int {
    out.* = wrapScriptTransform(atlas.inner.superscriptTransform(x, y, font_size) catch |err| return mapError(err));
    return SNAIL_OK;
}

pub export fn snail_text_atlas_subscript_transform(atlas: *const TextAtlasImpl, x: f32, y: f32, font_size: f32, out: *SnailScriptTransform) c_int {
    out.* = wrapScriptTransform(atlas.inner.subscriptTransform(x, y, font_size) catch |err| return mapError(err));
    return SNAIL_OK;
}

pub export fn snail_text_atlas_shape_utf8(
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    out: *?*ShapedTextImpl,
) c_int {
    const impl = createHandle(ShapedTextImpl, &atlas.handle_allocator.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const shaped = atlas.inner.shapeText(allocator, toFontStyle(style) catch {
        destroyHandle(impl);
        return SNAIL_ERR_INVALID_ARGUMENT;
    }, text[0..text_len]) catch |err| {
        destroyHandle(impl);
        return mapError(err);
    };
    impl.inner = shaped;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_text_atlas_ensure_text(
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    out: *?*TextAtlasImpl,
) c_int {
    const next = atlas.inner.ensureText(toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT, text[0..text_len]) catch |err| return mapError(err);
    if (next) |new_atlas| {
        const impl = createHandleSharingAllocator(TextAtlasImpl, atlas.handle_allocator) catch {
            var doomed = new_atlas;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.inner = new_atlas;
        out.* = impl;
    } else {
        out.* = null;
    }
    return SNAIL_OK;
}

pub export fn snail_text_atlas_ensure_shaped(atlas: *const TextAtlasImpl, shaped: *const ShapedTextImpl, out: *?*TextAtlasImpl) c_int {
    const next = atlas.inner.ensureShaped(&shaped.inner) catch |err| return mapError(err);
    if (next) |new_atlas| {
        const impl = createHandleSharingAllocator(TextAtlasImpl, atlas.handle_allocator) catch {
            var doomed = new_atlas;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.inner = new_atlas;
        out.* = impl;
    } else {
        out.* = null;
    }
    return SNAIL_OK;
}

pub export fn snail_text_atlas_ensure_glyphs(
    atlas: *const TextAtlasImpl,
    face_index: usize,
    glyph_ids: ?[*]const u16,
    glyph_count: usize,
    out: *?*TextAtlasImpl,
) c_int {
    if (glyph_count > 0 and glyph_ids == null) return SNAIL_ERR_INVALID_ARGUMENT;
    const gids = if (glyph_count == 0) &.{} else glyph_ids.?[0..glyph_count];
    const next = atlas.inner.ensureGlyphs(face_index, gids) catch |err| return mapError(err);
    if (next) |new_atlas| {
        const impl = createHandleSharingAllocator(TextAtlasImpl, atlas.handle_allocator) catch {
            var doomed = new_atlas;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.inner = new_atlas;
        out.* = impl;
    } else {
        out.* = null;
    }
    return SNAIL_OK;
}

pub export fn snail_shaped_text_deinit(shaped: ?*ShapedTextImpl) void {
    if (shaped) |s| {
        s.inner.deinit();
        destroyHandle(s);
    }
}

pub export fn snail_shaped_text_glyph_count(shaped: *const ShapedTextImpl) usize {
    return shaped.inner.glyphs.len;
}

pub export fn snail_shaped_text_advance_x(shaped: *const ShapedTextImpl) f32 {
    return shaped.inner.advance_x;
}

pub export fn snail_shaped_text_advance_y(shaped: *const ShapedTextImpl) f32 {
    return shaped.inner.advance_y;
}

pub export fn snail_shaped_text_glyph(shaped: *const ShapedTextImpl, index: usize, out: *SnailShapedGlyph) bool {
    if (index >= shaped.inner.glyphs.len) return false;
    const g = shaped.inner.glyphs[index];
    out.* = .{
        .face_index = g.face_index,
        .glyph_id = g.glyph_id,
        .x_offset = g.x_offset,
        .y_offset = g.y_offset,
        .x_advance = g.x_advance,
        .y_advance = g.y_advance,
        .source_start = g.source_start,
        .source_end = g.source_end,
    };
    return true;
}

pub export fn snail_shaped_text_copy_glyphs(shaped: *const ShapedTextImpl, out: [*]SnailShapedGlyph, capacity: usize) usize {
    const count = @min(shaped.inner.glyphs.len, capacity);
    for (shaped.inner.glyphs[0..count], 0..) |g, i| {
        out[i] = .{
            .face_index = g.face_index,
            .glyph_id = g.glyph_id,
            .x_offset = g.x_offset,
            .y_offset = g.y_offset,
            .x_advance = g.x_advance,
            .y_advance = g.y_advance,
            .source_start = g.source_start,
            .source_end = g.source_end,
        };
    }
    return count;
}

// ── TextBlobBundle / BlobInProgress ──
//
// The bundle is the value-driven blob constructor. It owns the lifetime
// of every TextBlob it produces — caller must keep the bundle alive for
// as long as any of its blobs are in use. `reset` invalidates every
// outstanding `SnailTextBlob` borrowed from the bundle; the handle's
// captured generation no longer matches and access returns
// `SNAIL_ERR_INVALID_HANDLE`.

pub export fn snail_text_blob_bundle_init(
    alloc_ptr: ?*const SnailAllocator,
    atlas: *const TextAtlasImpl,
    out: *?*common.TextBlobBundleImpl,
) c_int {
    const impl = createHandle(common.TextBlobBundleImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    impl.inner = snail.TextBlobBundle.init(allocator, &atlas.inner);
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_text_blob_bundle_deinit(bundle: ?*common.TextBlobBundleImpl) void {
    if (bundle) |b| {
        b.inner.deinit();
        destroyHandle(b);
    }
}

pub export fn snail_text_blob_bundle_reset(bundle: *common.TextBlobBundleImpl) void {
    bundle.inner.reset();
}

pub export fn snail_text_blob_bundle_freeze(bundle: *common.TextBlobBundleImpl) void {
    bundle.inner.freeze();
}

pub export fn snail_text_blob_bundle_unfreeze(bundle: *common.TextBlobBundleImpl) void {
    bundle.inner.unfreeze();
}

pub export fn snail_text_blob_bundle_is_frozen(bundle: *const common.TextBlobBundleImpl) bool {
    return bundle.inner.isFrozen();
}

pub export fn snail_text_blob_bundle_blob_count(bundle: *const common.TextBlobBundleImpl) usize {
    return bundle.inner.blobCount();
}

pub export fn snail_text_blob_bundle_generation(bundle: *const common.TextBlobBundleImpl) u32 {
    return bundle.inner.currentGeneration();
}

pub export fn snail_text_blob_bundle_rebind_atlas(
    bundle: *common.TextBlobBundleImpl,
    atlas: *const TextAtlasImpl,
) c_int {
    bundle.inner.rebindAtlas(&atlas.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_blob_bundle_start_blob(
    bundle: *common.TextBlobBundleImpl,
    out: *?*common.BlobInProgressImpl,
) c_int {
    const bip = bundle.inner.startBlob() catch |err| return mapError(err);
    const impl = createHandleSharingAllocator(common.BlobInProgressImpl, bundle.handle_allocator) catch {
        bip.abort();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.bundle = bundle;
    impl.generation = bundle.inner.currentGeneration();
    out.* = impl;
    return SNAIL_OK;
}

fn bipValid(bip: *common.BlobInProgressImpl) bool {
    return bip.generation == bip.bundle.inner.currentGeneration();
}

pub export fn snail_blob_in_progress_append_shaped(
    bip: *common.BlobInProgressImpl,
    shaped: *const ShapedTextImpl,
    glyphs: SnailRange,
    options: SnailTextAppendOptions,
    out_result: ?*SnailTextAppendResult,
) c_int {
    if (!bipValid(bip)) return SNAIL_ERR_INVALID_ARGUMENT;
    const paint = toPaint(options.fill) catch return SNAIL_ERR_INVALID_ARGUMENT;
    const range = toRange(glyphs).resolve(shaped.inner.glyphs.len);
    const handle = snail.BlobInProgress{ .bundle = &bip.bundle.inner };
    const result = handle.append(.{
        .source = .{ .shaped = shaped.inner.glyphs[range.start..range.end] },
        .placement = toTextPlacement(options.placement),
        .fill = paint,
    }) catch |err| return mapError(err);
    if (out_result) |out| out.* = fromTextAppendResult(result);
    return SNAIL_OK;
}

pub export fn snail_blob_in_progress_append_prepared_hint_run(
    bip: *common.BlobInProgressImpl,
    run: *const TrueTypePreparedHintRunImpl,
    placement: SnailTextPlacement,
    color: ?[*]const f32,
    out_result: ?*SnailTextAppendResult,
) c_int {
    if (!bipValid(bip)) return SNAIL_ERR_INVALID_ARGUMENT;
    const c = color4(color) catch return SNAIL_ERR_INVALID_ARGUMENT;
    const handle = snail.BlobInProgress{ .bundle = &bip.bundle.inner };
    const result = handle.append(.{
        .source = .{ .hinted = run.inner.glyphs },
        .placement = toTextPlacement(placement),
        .fill = .{ .solid = c },
    }) catch |err| return mapError(err);
    if (out_result) |out| out.* = fromTextAppendResult(result);
    return SNAIL_OK;
}

pub export fn snail_blob_in_progress_glyph_count(bip: *const common.BlobInProgressImpl) usize {
    if (bip.generation != bip.bundle.inner.currentGeneration()) return 0;
    const handle = snail.BlobInProgress{ .bundle = @constCast(&bip.bundle.inner) };
    return handle.glyphCount();
}

pub export fn snail_blob_in_progress_finish(
    bip: *common.BlobInProgressImpl,
    key: SnailResourceKey,
    out: *?*TextBlobImpl,
) c_int {
    if (!bipValid(bip)) {
        destroyHandle(bip);
        return SNAIL_ERR_INVALID_ARGUMENT;
    }
    const handle = snail.BlobInProgress{ .bundle = &bip.bundle.inner };
    const blob_ptr = handle.finish(snail.ResourceKey.fromOpaque(key)) catch |err| {
        destroyHandle(bip);
        return mapError(err);
    };
    const impl = createHandleSharingAllocator(TextBlobImpl, bip.handle_allocator) catch {
        destroyHandle(bip);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.inner = blob_ptr.*;
    impl.owned_bundle = null;
    impl.borrowed_from = bip.bundle;
    impl.borrowed_generation = bip.bundle.inner.currentGeneration();
    out.* = impl;
    destroyHandle(bip);
    return SNAIL_OK;
}

pub export fn snail_blob_in_progress_abort(bip: *common.BlobInProgressImpl) void {
    if (bipValid(bip)) {
        const handle = snail.BlobInProgress{ .bundle = &bip.bundle.inner };
        handle.abort();
    }
    destroyHandle(bip);
}

// TrueType hinting

pub export fn snail_true_type_hint_ppem_uniform(ppem_26_6: u32) SnailTrueTypeHintPpem {
    return .{ .x_26_6 = ppem_26_6, .y_26_6 = ppem_26_6 };
}

pub export fn snail_true_type_hint_context_init(
    alloc_ptr: ?*const SnailAllocator,
    atlas: *const TextAtlasImpl,
    out: *?*TrueTypeHintContextImpl,
) c_int {
    const impl = createHandle(TrueTypeHintContextImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    impl.inner = snail.TrueTypeHintContext.init(allocator, &atlas.inner);
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_true_type_hint_context_deinit(context: ?*TrueTypeHintContextImpl) void {
    if (context) |c| {
        c.inner.deinit();
        destroyHandle(c);
    }
}

pub export fn snail_true_type_hint_context_rebind_atlas(context: *TrueTypeHintContextImpl, atlas: *const TextAtlasImpl) void {
    context.inner.rebindAtlas(&atlas.inner);
}

pub export fn snail_true_type_hint_context_prepare_size(
    context: *TrueTypeHintContextImpl,
    face_index: usize,
    ppem: SnailTrueTypeHintPpem,
) c_int {
    if (face_index >= context.inner.atlas.faceCount()) return SNAIL_ERR_INVALID_ARGUMENT;
    const face = std.math.cast(snail.FaceIndex, face_index) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    context.inner.prepareSize(face, toTrueTypeHintPpem(ppem)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_true_type_hint_context_prepare_run(
    context: *TrueTypeHintContextImpl,
    alloc_ptr: ?*const SnailAllocator,
    shaped: *const ShapedTextImpl,
    ppem: SnailTrueTypeHintPpem,
    out: *?*TrueTypePreparedHintRunImpl,
) c_int {
    const impl = createHandle(TrueTypePreparedHintRunImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const run = context.inner.prepareRun(allocator, .{
        .shaped = &shaped.inner,
        .ppem = toTrueTypeHintPpem(ppem),
    }) catch |err| {
        destroyHandle(impl);
        return mapError(err);
    };
    impl.inner = run;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_true_type_prepared_hint_run_deinit(run: ?*TrueTypePreparedHintRunImpl) void {
    if (run) |r| {
        r.inner.deinit();
        destroyHandle(r);
    }
}

pub export fn snail_true_type_prepared_hint_run_stats(run: *const TrueTypePreparedHintRunImpl, out: *SnailTrueTypeHintRunStats) void {
    out.* = fromTrueTypeHintRunStats(run.inner.stats);
}

/// Internal helper: build a TextBlob into a freshly-allocated bundle
/// owned by the returned TextBlobImpl. Used by all standalone
/// init_* paths so callers that don't manage their own bundle can still
/// get a TextBlob handle.
fn initStandaloneBlob(
    alloc_ptr: ?*const SnailAllocator,
    atlas: *const snail.TextAtlas,
    appends: []const snail.TextAppend,
    out: *?*TextBlobImpl,
) c_int {
    const impl = createHandle(TextBlobImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const owned_bundle = allocator.create(snail.TextBlobBundle) catch {
        destroyHandle(impl);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    owned_bundle.* = snail.TextBlobBundle.init(allocator, atlas);
    const blob_ptr = owned_bundle.buildBlob(snail.ResourceKey.named("standalone_blob"), appends, null) catch |err| {
        owned_bundle.deinit();
        allocator.destroy(owned_bundle);
        destroyHandle(impl);
        return mapError(err);
    };
    impl.inner = blob_ptr.*;
    impl.owned_bundle = owned_bundle;
    impl.borrowed_from = null;
    impl.borrowed_generation = 0;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_text_blob_init_from_prepared_hint_run(
    alloc_ptr: ?*const SnailAllocator,
    run: *const TrueTypePreparedHintRunImpl,
    placement: SnailTextPlacement,
    color: ?[*]const f32,
    out: *?*TextBlobImpl,
) c_int {
    const c = color4(color) catch return SNAIL_ERR_INVALID_ARGUMENT;
    const appends = [_]snail.TextAppend{.{
        .source = .{ .hinted = run.inner.glyphs },
        .placement = toTextPlacement(placement),
        .fill = .{ .solid = c },
    }};
    return initStandaloneBlob(alloc_ptr, run.inner.atlas, &appends, out);
}

pub export fn snail_text_blob_init_from_shaped(
    alloc_ptr: ?*const SnailAllocator,
    atlas: *const TextAtlasImpl,
    shaped: *const ShapedTextImpl,
    options: SnailTextAppendOptions,
    out: *?*TextBlobImpl,
) c_int {
    const paint = toPaint(options.fill) catch return SNAIL_ERR_INVALID_ARGUMENT;
    const appends = [_]snail.TextAppend{.{
        .source = .{ .shaped = shaped.inner.glyphs },
        .placement = toTextPlacement(options.placement),
        .fill = paint,
    }};
    return initStandaloneBlob(alloc_ptr, &atlas.inner, &appends, out);
}

pub export fn snail_text_blob_init_text(
    alloc_ptr: ?*const SnailAllocator,
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    options: SnailTextAppendOptions,
    out: *?*TextBlobImpl,
) c_int {
    const impl = createHandle(TextBlobImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const font_style = toFontStyle(style) catch {
        destroyHandle(impl);
        return SNAIL_ERR_INVALID_ARGUMENT;
    };
    const paint = toPaint(options.fill) catch {
        destroyHandle(impl);
        return SNAIL_ERR_INVALID_ARGUMENT;
    };
    var shaped = atlas.inner.shapeText(allocator, font_style, text[0..text_len]) catch |err| {
        destroyHandle(impl);
        return mapError(err);
    };
    defer shaped.deinit();
    const owned_bundle = allocator.create(snail.TextBlobBundle) catch {
        destroyHandle(impl);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    owned_bundle.* = snail.TextBlobBundle.init(allocator, &atlas.inner);
    const blob_ptr = owned_bundle.buildBlob(snail.ResourceKey.named("standalone_text"), &.{.{
        .source = .{ .shaped = shaped.glyphs },
        .placement = toTextPlacement(options.placement),
        .fill = paint,
    }}, null) catch |err| {
        owned_bundle.deinit();
        allocator.destroy(owned_bundle);
        destroyHandle(impl);
        return mapError(err);
    };
    impl.inner = blob_ptr.*;
    impl.owned_bundle = owned_bundle;
    impl.borrowed_from = null;
    impl.borrowed_generation = 0;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_text_blob_deinit(blob: ?*TextBlobImpl) void {
    if (blob) |b| {
        if (b.owned_bundle) |bundle| {
            bundle.deinit();
            b.handle_allocator.allocator().destroy(bundle);
        }
        // Bundle-borrowed blobs need no cleanup: the source bundle owns
        // the blob storage and reclaims it on its own reset/deinit.
        destroyHandle(b);
    }
}

pub export fn snail_text_blob_glyph_count(blob: *const TextBlobImpl) usize {
    return blob.inner.glyphCount();
}

pub export fn snail_text_blob_rebound(
    alloc_ptr: ?*const SnailAllocator,
    blob: *const TextBlobImpl,
    atlas: *const TextAtlasImpl,
    out: *?*TextBlobImpl,
) c_int {
    const impl = createHandle(TextBlobImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const owned_bundle = allocator.create(snail.TextBlobBundle) catch {
        destroyHandle(impl);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    owned_bundle.* = snail.TextBlobBundle.init(allocator, &atlas.inner);
    const rebound_ptr = owned_bundle.rebound(snail.ResourceKey.named("standalone_rebound"), &blob.inner, &atlas.inner) catch |err| {
        owned_bundle.deinit();
        allocator.destroy(owned_bundle);
        destroyHandle(impl);
        return mapError(err);
    };
    impl.inner = rebound_ptr.*;
    impl.owned_bundle = owned_bundle;
    impl.borrowed_from = null;
    impl.borrowed_generation = 0;
    out.* = impl;
    return SNAIL_OK;
}

fn color4(color: ?[*]const f32) ![4]f32 {
    const p = color orelse return error.InvalidArgument;
    return .{ p[0], p[1], p[2], p[3] };
}

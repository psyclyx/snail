# Embedding snail

This document collects the detailed host contracts behind the shorter
integration overview in the [README](README.md). The core flow is:

**shape → plan/prepare → apply → upload → emit → draw**

snail owns the CPU-side font, path, atlas, upload-planning, and draw-record
logic. A GPU host owns its textures, pipelines, uploads, command buffers, and
draw calls. `snail-raster` is the optional CPU backend.

## Software renderer

`snail-raster` uses the same `Atlas`, `Binding`, instances, and batches as a
GPU backend:

```zig
const raster = @import("snail-raster");

var device = try raster.DeviceAtlas.init(alloc, pool, .{});
defer device.deinit();
var bindings: [1]snail.render.records.Binding = undefined;
try device.upload(alloc, &.{&atlas}, &bindings);

var raster_ni: usize = 0;
var raster_nb: usize = 0;
_ = try snail.emit.emit(instances, batches, &raster_ni, &raster_nb,
    bindings[0], &atlas, shapes, world_xform, .{ 1, 1, 1, 1 });
const raster_records: raster.DrawRecords = .{
    .instances = instances[0..raster_ni],
    .batches = batches[0..raster_nb],
};

var renderer = try raster.Renderer.init(
    pixels, width, height, stride, .rgba8_unorm,
);
try raster.draw(&renderer, .{
    .mvp = mvp,
    .surface = .{
        .pixel_width = width,
        .pixel_height = height,
        .encoding = .srgb,
        .format = .rgba8_unorm,
    },
}, raster_records, &.{&device}, null);
```

`Renderer.init` and `reinitBuffer` validate the caller-owned byte length and
stride. Every draw also validates the declared surface size and
`PixelFormat`; the stride must be at least
`width * format.bytesPerPixel()`.

`DeviceAtlas.upload` requires one output binding per input atlas. If a
multi-atlas call fails, none of the bindings planned by that call remain
live, although successfully prepared shared-page data may stay cached.
`snail-raster` supports affine scene-to-pixel transforms. A perspective MVP
returns `error.NonAffineMvp`.

## Prepared artifacts and disk caches

The `snail.prepared` namespace separates expensive producer output from both
runtime atlas identity and presentation. Its archives contain only reusable
geometry, autohint models and glyph facts, TT-hinted geometry, and TT
advances. Paint, layers, scene shapes, atlas page positions, VM state, and GPU
objects are deliberately not archived.

`prepared.Archive.fromBytes(bytes)` takes the bytes representing an archive,
not a filename, stream, or file handle. Snail performs no filesystem I/O. The
host may read the file, memory-map it, embed it, receive it over a transport,
or stream it into a retained buffer before calling `fromBytes`. The byte
address must be 8-byte aligned. An `Archive` and every `RecordView` returned
from it borrow that buffer, so the bytes must remain alive and unchanged
until all of those views are finished.

`fromBytes` validates the magic, exact format version, endian tag, alignment,
sorted index, tags, and every table range without allocating or decoding
records. `find` is a binary search and returns slices directly into the
archive. Artifact semantics are checked lazily by `RecordView.validate` and
again before atlas mutation. Treat `VersionMismatch`, a structurally damaged
archive, or a record which fails semantic validation as a cache miss;
compatibility is intentionally exact.

The application supplies a stable `prepared.FontKey` for each precise font
instance. It must identify font bytes, face index, and variation coordinates.
This is separate from the runtime `font_id` used by shaping and atlas record
keys. Applications should not manufacture artifact keys: constructors such
as `unhintedKey`, `autohintGlyphKey`, and `ttGlyphKey` mix the font key with
the producer version and every output-affecting option, including the
bit-exact cubic tolerance.

`ArchiveBuilder` owns copies of added values, sorts by key, and emits
canonical bytes. Adding the same key and content is idempotent; adding the
same key with different content returns `ConflictingDuplicate`.
`finishInto` writes into caller-owned aligned storage, while `finishAlloc`
returns an `OwnedArchive`. Immutable archives can be sharded: search a small
new archive before an older base archive, then merge them under
caller-controlled cache policy instead of rewriting a large file after every
preparation batch.

Both fresh and archived geometry feed the same borrowed atlas input without a
codec or copy:

```zig
const fresh_entry = snail.AtlasEntry{ .geometry = .{
    .key = runtime_key,
    .curves = owned_curves.view(),
} };
const cached_entry = snail.AtlasEntry{ .geometry = .{
    .key = runtime_key,
    .curves = archive.find(artifact_key).?.value.geometry.atlasView(),
} };
// Each view only needs to outlive the Atlas.from/extend call.
```

Preparation is caller-scheduled. `planRuns` only discovers cacheable work and
atlas assembly dependencies; it does not extract outlines or create threads.
The `sources` slice is also an explicit selection set: glyphs whose
`font_id` is absent are skipped rather than rejected. This lets a host prepare
autohint or TT-hinted records only for a primary face while keeping fallback
faces on the unhinted path. `planTtAdvances` and `TtAdvanceSource` use the
same selected-source convention.

Each request operation has one preparation owner:

| `PrepareRequest.operation` | Thread-confined owner | Result |
|---|---|---|
| `.outline` | `OutlineContext.prepare` | ppem-independent geometry |
| `.autohint_model` / `.autohint_glyph` | `AutohintContext.prepare` | reusable font model / glyph facts |
| `.tt_glyph` | `TtHintContext.prepare` with a matching `TtHintSize` | ppem-specific geometry and advance from one VM execution |
| `.tt_advance` | `TtHintContext.prepare` with a matching `TtHintSize` | page-free hinted advance |

Construct `AutohintContext` per selected font and options. When an
`.autohint_model` dependency is a cache hit, `initWithModel` avoids deriving
that model again. Construct `TtHintContext` per selected TrueType font and
reuse a `prepareSize` result for requests with the same `TtHintPpem`.

A typical cache-hit/miss flow looks like this:

```zig
// Font borrows font_bytes and variation storage. The plan copies FontSource
// descriptors, but those borrowed Font inputs must outlive its jobs.
var font = try snail.Font.init(font_bytes);
const sources = [_]snail.FontSource{.{
    .font_id = 0,
    .font = &font,
    .cache_key = app.fontInstanceKey(font_bytes, 0, variations),
}};

// The caller chose mmap here. Reading into an aligned retained allocation is
// equally valid.
var mapped = try app.mapFile("font.snail-prepared");
defer mapped.unmap();
const disk_cache = snail.prepared.Archive.fromBytes(mapped.bytes()) catch null;

var plan = try snail.planRuns(
    &atlas,
    alloc,
    &sources,
    &.{&shaped},
    .{ .autohint = .{} },
);
defer plan.deinit();

const requests = plan.requests();
const results = try alloc.alloc(?snail.prepared.RecordView, requests.len);
defer alloc.free(results);
@memset(results, null);

// Owned misses may be produced on arbitrary jobs. Each worker uses its own
// thread-confined OutlineContext, AutohintContext, or TtHintContext.
const owned = try alloc.alloc(?snail.prepared.OwnedRecord, requests.len);
defer {
    for (owned) |*record| if (record.*) |*value| value.deinit();
    alloc.free(owned);
}
@memset(owned, null);

for (requests, 0..) |request, request_index| {
    if (disk_cache) |archive| {
        if (archive.find(request.key)) |hit| {
            if (hit.validate()) |_| {
                results[request_index] = hit;
                continue;
            } else |_| {
                // A semantically damaged cache record is an ordinary miss.
            }
        }
    }

    // `dependencies(request_index)` names earlier result slots which must
    // complete first. The host maps request.operation to the matching
    // per-thread context's prepare method.
    try jobs.submitAfter(plan.dependencies(request_index), .{
        .request = request,
        .result_index = request_index,
        .owned_results = owned,
        .result_views = results,
    });
}
try jobs.wait();

// Preflights every key, kind, dependency, and value before mutation. The
// atlas copies accepted data and retains no result views.
try plan.applyInPlace(alloc, &atlas, results);

// Persist misses if desired. Filesystem replacement and shard merging remain
// caller policy.
var builder = snail.prepared.ArchiveBuilder.init(alloc);
defer builder.deinit();
for (owned) |*record| if (record.*) |*value| try builder.add(value.view());
var new_shard = try builder.finishAlloc(alloc);
defer new_shard.deinit();
try app.atomicWrite("font.snail-prepared.next", new_shard.bytes());
```

Plans remain usable while unrelated atlas growth proceeds. They remember
records and advances which were already present during planning and require
those prerequisites at apply time. Applying after a filtered compaction or
replacement which removed one returns `error.IncompatibleAtlas`; replan
against that replacement rather than silently producing an incomplete run.

The job helpers above are application pseudocode; Snail deliberately does not
provide a thread pool or generic cache/filesystem vtable. `OutlineContext`,
`AutohintContext`, and `TtHintContext` are thread-confined. Their returned
owning records may move between threads, subject to the allocator's own
threading contract. TT `TtHintSize` and interpreter state are runtime
acceleration data and are not archive artifacts.

`Font` remains an immutable borrowed description; it does not acquire mutable
HarfBuzz state for preparation. `Faces` owns shaping state, while each
`OutlineContext` owns any per-worker CFF/CFF2 or variable-font outline backend
it needs. A cache hit therefore requires neither shaping nor outline
extraction.

## Capacity and eviction

`PagePool` is the resident page budget. Atlas updates are idempotent: an
existing record key is skipped. When a new record cannot acquire a page,
applying the update returns `error.OutOfLayers`; eviction policy belongs to
the host.

`Atlas.compactInto(allocator, scratch, target_pool, filter)` creates a new,
fully repacked snapshot in a caller-chosen pool. A `RecordFilter` chooses the
records that survive; `null` keeps everything and performs pure
defragmentation. Autohint dependencies are closed automatically, paint and
analysis records are retained, and TT advance-only records pass through the
same filter.

Using a distinct target pool decouples compaction from free space in the
source pool. The old atlas remains drawable while the caller plans and
records uploads for the replacement. Once the new upload graph is accepted,
publish the new atlas and binding together. After the last GPU use of the old
binding completes, release that binding and deinitialize the old atlas and
pool. This double-buffered migration is asynchronous: Snail never waits for a
queue or fence.

`Atlas.compact(allocator, scratch, filter)` is the persistent same-pool
convenience wrapper. Because source and result coexist, it still requires
enough free pages for the result. Snail does not offer an in-place destructive
variant: it cannot prove that the source atlas's CPU views and GPU binding are
no longer in use.

`PagePool.config()` returns the immutable capacity configuration. Atlas page
handles are opaque; renderer integrations receive immutable
`atlas_upload.Region` copies.
[`dev/support/working_set.zig`](dev/support/working_set.zig) is a demo-only
working-set example.

`max_pages` is the logical page count (up to 65,536), and page CPU storage
is allocated lazily. `pages_total` and `*_bytes_total` report logical
capacity; `pages_allocated` and `*_bytes_allocated` report actual retained
CPU storage. Font line/quadratic segments take two `RGBA16F` texels instead
of the general path format's four. Raising `curve_words_per_page` is
therefore an independent, shader-compatible way to make pages taller.

Placement uses a bounded two-dimensional best-fit scan over the most recent
`Atlas.Packing.recent_page_limit` pages (12 by default), balancing curve and
band leftovers. The work is capped at 64 candidates regardless of atlas
size; set the limit to one for tail-only behavior. Use
`Atlas.fromWithPacking` or its extension counterparts to override it. This
is deliberately not a size-class allocator: insertion cost stays bounded
when glyph sizes vary heavily.

Direct vector producers assemble one tagged `AtlasUpdate`: `.geometry`
entries place curve data, `.autohint` entries alias an existing or
same-update base, and `.tt_advances` carries page-free metrics. `extend` and
`extendInPlace` preflights the whole update and publishes it logically
atomically. A late allocator or concurrent-capacity failure can consume
unreachable append-only page padding, but never exposes a partial atlas. Font
preparation normally uses `PreparePlan.apply` or `applyInPlace`, which builds
that update only after every external result has validated. Do not put
one-entry `extendInPlace` calls in a loop.

## Upload planning and bindings

`atlas_upload.OwnedPlanner.plan` returns a `PendingUpload`: a provisional
binding plus complete upload regions. On a direct append-only child snapshot,
`planDelta(previous_binding, atlas)` returns a transaction containing only
changed curve/band regions and newly appended side data.

```zig
const binding = upload: {
    var pending = try planner.plan(&atlas);
    errdefer planner.abort(&pending) catch {};

    for (pending.regions()) |region| {
        // Copy into retained staging or record it into a command graph. All
        // borrowed source bytes must be accepted before commit.
        try gpu.accept(region);
    }

    // pending.binding() may be used while recording this same command graph.
    // commit publishes planner state; it does not submit or wait for GPU work.
    break :upload try planner.commit(&pending);
};

// Draw with binding...
// After the final GPU use completes:
_ = planner.release(binding);
```

Only one transaction may be pending on a planner. `abort` restores binding
reservations and page watermarks, so a later attempt re-emits bytes which
were not accepted. `commit` consumes the `PendingUpload`; call `regions()` and
`binding()` first. Host copies or commands already issued before an abort are
the host's responsibility, but remain unpublished to Snail.

Layer-info rows and image layers are fixed reservations made by the original
`plan`. If later side data outgrows that reservation, release the binding and
make a fresh plan. `planDelta` accepts only the exact snapshot or its direct
append-only child. A skipped descendant, branch, or unrelated snapshot returns
`error.IncompatibleSnapshot`; allocate a fresh binding with `plan`.

If accepting any region or recording its command fails before commit, call
`abort`. If committed work later fails to reach or remain on the device—for
example, submission failure or device loss—call `planner.invalidateUploads()`
before retrying
`planDelta(binding, &atlas)`, or release the binding before a fresh `plan`.
This clears the planner's page and side-data watermarks so bytes that never
reached the device are emitted again.

A `Binding` is meaningful only to the planner or `DeviceAtlas` that issued
it. Its identity includes the `PagePool`, the issuer's `source_id`, a 64-bit
slot generation, the layer-info row, and the image-layer offset. Do not
synthesize bindings or compare only part of one in a device cache.

Upload `Region` payloads borrow one of three owners:

- planner scratch for layer-info data;
- live atlas page memory for curve and band data;
- caller-owned `Image` texels.

Accept all regions before committing the transaction, and keep the referenced
atlas and images alive and unchanged until their borrowed bytes have been
copied into host-owned staging. The resulting `Binding` is independent of
those CPU byte borrows and remains live until `release`, normally after the
final GPU draw fence which uses it.

## Color

Paint, tint, placement, and emitted instance colors are linear-light
`[4]f32` values with straight (non-premultiplied) alpha. snail does not
automatically convert them. Gradients interpolate and tints multiply in
linear light; coverage produces premultiplied linear color. CPAL colors are
specified by OpenType as sRGB and are converted to linear during extraction.

`LinearResolve.Backdrop.clear` is the deliberate exception: it accepts an
sRGB straight-alpha color, matching an application-authored clear color.

Use `snail.color.srgbToLinearColor` for sRGB-authored paint and tint values.
Blend shader output with `ONE, ONE_MINUS_SRC_ALPHA`. `TargetEncoding`
selects the output path: a linear attachment receives linear values; an sRGB
attachment encodes in hardware; and
`.srgb_pixels_on_linear_attachment` asks the shader to encode before writing.
That last single-pass compatibility mode blends in storage space.

For linear-correct overlapping translucency, blend into a linear
intermediate and encode once afterward with the generated linear-resolve
stages or another final pass. Encoding each layer before blending makes
overlaps too dark.

## Coordinates

Font geometry is stored y-up. `RunPlacement.y_axis` and
`CellRunPlacement.y_axis` orient it into either a y-down scene (the default)
or a y-up scene. Coverage is orientation-independent.

`mvpToScenePixel` maps an affine MVP into framebuffer pixels with a top-left
origin. That framebuffer convention is separate from the scene's y-axis.
It returns `null` for perspective or degenerate transforms.

## Images

`Image` copies and stores tightly packed raw texel bytes; the core does not
parse an image-file format or reinterpret the texel layout. The sampling
contract is that a backend produces linear color with straight alpha:

- upload sRGB bytes to an sRGB texture format, or
- upload pre-linearized values to a UNORM or floating-point format.

`atlas_upload.Options.image_bytes_per_texel` declares the host array format
(four by default). Every image in a plan must match it and fit
`max_image_width × max_image_height`. `snail-raster` accepts four-byte sRGBA
texels and decodes RGB to linear for each sample.

## GPU resources and shaders

The classic atlas resource layout uses:

- an `RGBA16F` curve texture array;
- an `RG16UI` band texture array;
- an `RGBA32F` layer-info texture;
- an optional host-formatted image texture array.

These are the atlas resources, not the complete GPU footprint. A host also
provides the 72-byte-per-instance stream, the shared parameter block,
pipelines, samplers where required, and ordinary command-buffer state.

Curve/band pages are logical, not limited to one texture array. Each
`DrawBatch` contains an aligned `page_base`; its `atlasBank()` selects a
256-layer resource bank, while the packed instance retains the bank-local
layer. Curve/band upload `Region`s expose the matching `atlasBank()` and
`bankLayer()`. A banked-array backend selects the bank and sends zero as the
shader `page_base`; a backend with one sufficiently deep resource binds it
directly and sends `DrawBatch.page_base`.

Backends may instead use `snail.atlas_upload.FlatLayout`. It maps every
logical page into two flat typed buffers while retaining `RGBA16F` curve and
`RG16UI` band texels. Allocate `curveByteSize()` and `bandByteSize()`, apply
each curve/band upload using the byte offset returned by
`FlatLayout.translate`, and pass
`.{ flat.curve_page_texels, flat.band_page_texels }` in
`atlas_page_texels`. Pages use fixed strides, so the shader computes the
address directly; there is no page-table fetch. Use the `flatFrag*` accessor
for the batch's `FlatFamily` and pass `DrawBatch.page_base` unchanged.

On desktop OpenGL 3.3 the flat variants are ordinary `samplerBuffer` and
`usamplerBuffer` shaders: create texture-buffer objects with `GL_RGBA16F`
and `GL_RG16UI`, respectively. No SSBO or newer GL extension is required.
Validate both total texel counts against `GL_MAX_TEXTURE_BUFFER_SIZE`.
The desktop reference cache uses this path and binds each backing buffer once
per upload while coalescing adjacent dirty regions. GLES 3.0 has no core
texture buffers and therefore retains 256-layer array storage.

For Vulkan, the compact path is two buffers with
`VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT`, viewed as
`VK_FORMAT_R16G16B16A16_SFLOAT` and `VK_FORMAT_R16G16_UINT`, and exposed at
bindings 0 and 1 as `VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER`. Check
`maxTexelBufferElements`, image dimension/layer limits, and the required
format features. Vulkan SSBOs are also available, but formatted uniform texel
buffers are the natural fit here: they preserve compact half/u16 storage and
perform typed conversion in the texture path without shader-side unpacking.

There are two Vulkan integration levels:

1. For complete engine control, consume `atlas_upload.Region` and
   `FlatLayout` directly. The engine owns every buffer, allocation, mapping,
   copy command, barrier, submission, and completion primitive.
2. The code under
   [`dev/demo/render/vulkan`](dev/demo/render/vulkan) is a caller-side
   reference encoder. Create its resident `VulkanDeviceAtlas`, begin your own
   graphics-capable command buffer, construct an `UploadRecorder` over that
   command buffer, and call `upload` or `uploadDelta`. The call only records
   work. End and submit the command buffer yourself; after your fence or
   timeline value signals, call `UploadRecorder.releaseCompleted` to retire
   staging. Do not abandon a successfully recorded upload while continuing
   to use that cache, because its next transition assumes the recorded work
   remains ordered.

The reference encoder intentionally requires a graphics-capable queue: its
release barriers target vertex and fragment shader reads. It does not claim
dedicated-transfer-queue support. An engine using a transfer-only queue
should take the first integration level and record the appropriate
queue-family release/acquire pair in its own upload graph. The blocking
`uploadAndWait` helpers are demo caller conveniences, not library behavior.

WebGPU has no texel-buffer resource, so its flat WGSL variant uses compact
32-bit storage words and decodes the same half/u16 records. D3D11 and Metal
flat variants use their native typed-buffer representation.

The native Slang modules under
[`src/snail/shader/slang`](src/snail/shader/slang) are the authored source
of truth. Generated `snail-shaders` modules provide complete stages and
binding-name contracts for:

- Vulkan SPIR-V;
- WGSL;
- GLSL 330 and GLES 300;
- D3D11 HLSL;
- Metal MSL.

Artifacts are generated in the Zig cache only for an imported shader module.
`snail` and `snail-raster` alone do not require `slangc`. Per-target scopes
are `snail-shaders-gl`, `snail-shaders-glsl330`,
`snail-shaders-wgsl`, `snail-shaders-hlsl`, and `snail-shaders-msl`;
`snail-shaders` is the aggregate scope. Consumer scopes run `slangc` but not
the repository's additional `naga` validation step.

An engine that compiles snail's shaders itself does not need any generated
stage module. The push-constant layout and descriptor slots are committed at
`src/snail/shader/reflection.zig` and exposed by the `snail-shaders-reflection`
scope, which embeds no artifacts and therefore requires no shader toolchain.
Take the `snail_slang` source, compile it to your target with your own
pipeline, and read the binding contract from that reflection. `zig build
check-reflection` re-derives the reflection from `slangc` and diffs it against
the committed copy, so it cannot drift from the shaders.

For custom materials, caller-authored Slang can `import text_sample` and
sample glyph coverage inside its own fragment shader. The worked example is
[`dev/demo/game/slang/game_material.slang`](dev/demo/game/slang/game_material.slang).
Its caller-owned record plane demonstrates the complete flat-addressing
payload: `N × 18` packed instance words, then `N` per-glyph
`DrawBatch.page_base` words, then the curve and band page strides. This keeps
batch placement and atlas layout out of global shader state.

## Render ABI

The render ABI is versioned. Each packed instance is 72 bytes (18 32-bit
words): an outward-rounded f16 local bounding box, affine transform and
origin, glyph words, four payload words, and linear-f16 color/tint. Its layer
byte is local to a 256-page bank; `DrawBatch.page_base` supplies the high
logical-page bits. Backends validate packed records before consuming them.

The public byte-layout and decoding contracts live in `snail.render` (pure
Zig, no toolchain). The shader binding contract — push constants and
descriptor slots — is committed at `src/snail/shader/reflection.zig` and
surfaced by every `snail-shaders*` scope; the canonical shader-side layout
lives under `src/snail/shader/slang`.

## Ownership, failure, and threading

Allocating constructors and operations either accept an allocator or use
the allocator retained by their owning value. `Font` borrows its source
bytes and, for selected variable instances, its variation slice. `Faces`
borrows stable `Font` pointers. A `PagePool` must outlive every atlas, upload
planner, and device cache created from it.

`Atlas` is a persistent value: `extend` returns a snapshot which shares
retained, reference-counted page storage with its parent; `compact` or
`compactInto` returns a freshly packed root while preserving the source.
Lookups return records by value, avoiding an entry-versus-eviction lifetime
hazard.

Construction and validation errors are typed. Atlas insertion, draw
emission, device resize, and renderer buffer replacement preflight or stage
their work so published state is unchanged on failure. Paths, paints,
transforms, colors, packed records, and upload data are validated at their
public boundaries.

The core `snail` module does not create threads. Separate atlas handles,
including children of the same persistent snapshot, may be extended and
destroyed on different threads. Do not mutate or destroy the same handle
concurrently, and use distinct allocators or a thread-safe allocator.

`Faces`, `OutlineContext`, `AutohintContext`, `TtHintContext`, planners, and
other mutable working values are thread-confined unless their documentation
says otherwise. Construct one `Faces` per shaping thread and one preparation
context per worker. Prepared owning records may cross threads subject to
their allocator's threading contract. `snail-raster` provides an optional,
caller-driven `ThreadPool`.

The same boundary applies to GPU work: `snail` never creates a Vulkan, GL,
D3D, Metal, or WebGPU object; allocates device or staging memory; records a
command; submits a queue; or owns synchronization. `atlas_upload` returns
layouts and borrowed byte regions. Generated shaders define the other side
of that data contract. Code under `dev/demo/render` is integration guidance,
not library runtime or an ownership transfer.

//! Caller-scheduled preparation of shaped runs.
//!
//! Planning is cheap and never extracts outlines. A plan is a flat array of
//! independently cacheable requests plus a private set of atlas assembly
//! recipes. Callers satisfy requests from `prepared.Archive` or on arbitrary
//! worker threads, then apply all results in one logically atomic atlas update.

const std = @import("std");
const atlas_mod = @import("../atlas.zig");
const font_mod = @import("../font.zig");
const hint_vm_mod = @import("../font/tt_hint_vm.zig");
const autohint_mod = @import("../font/autohint/producer.zig");
const text_mod = @import("../text.zig");
const prepared = @import("../prepared.zig");
const record_key = @import("record_key.zig");
const cubic_to_quadratic = @import("../math/cubic_to_quadratic.zig");

const Allocator = std.mem.Allocator;
const Atlas = atlas_mod.Atlas;
const Font = font_mod.Font;
const RecordKey = record_key.RecordKey;

/// Stable preparation identity is deliberately separate from shaping's
/// `Faces` and the atlas's runtime `font_id`. A plan copies this descriptor,
/// but the `Font`, its bytes, and its variation slice remain caller-owned and
/// must outlive every job using the plan.
pub const FontSource = struct {
    font_id: u32,
    font: *const Font,
    cache_key: prepared.FontKey,
};

pub const ColrHandling = enum {
    composite,
    layers,
    outline_only,
};

pub const UnhintedRunOptions = struct {
    colr: ColrHandling = .composite,
    colr_foreground: [4]f32 = .{ 1, 1, 1, 1 },
    geometry: prepared.GeometryOptions = .{
        .cubic_tolerance = cubic_to_quadratic.default_tolerance,
    },
};

pub const AutohintRunOptions = struct {
    geometry: prepared.GeometryOptions = .{
        .cubic_tolerance = cubic_to_quadratic.default_tolerance,
    },
    autohint: prepared.AutohintOptions = .{},
};

pub const PrepareMode = union(enum) {
    unhinted: UnhintedRunOptions,
    autohint: AutohintRunOptions,
    tt_hint: hint_vm_mod.TtHintPpem,
};

pub const PrepareRequest = struct {
    key: prepared.Key,
    operation: Operation,

    pub const Operation = union(enum) {
        outline: Outline,
        autohint_model: AutohintModel,
        autohint_glyph: AutohintGlyph,
        tt_glyph: TtGlyph,
        tt_advance: TtAdvance,
    };

    pub const Outline = struct {
        source: *const FontSource,
        glyph_id: u16,
        options: prepared.GeometryOptions,
    };

    pub const AutohintModel = struct {
        source: *const FontSource,
        options: prepared.AutohintOptions,
    };

    pub const AutohintGlyph = struct {
        source: *const FontSource,
        glyph_id: u16,
        options: prepared.AutohintOptions,
    };

    pub const TtGlyph = struct {
        source: *const FontSource,
        glyph_id: u16,
        ppem: hint_vm_mod.TtHintPpem,
    };

    pub const TtAdvance = struct {
        source: *const FontSource,
        glyph_id: u16,
        ppem: hint_vm_mod.TtHintPpem,
    };
};

const GeometryRecipe = struct {
    destination: RecordKey,
    request: u32,
};

const CompositeLayerRecipe = struct {
    request: u32,
    paint: atlas_mod.Paint,
};

const CompositeRecipe = struct {
    destination: RecordKey,
    fallback_request: u32,
    first_layer: u32,
    layer_count: u16,
};

const AutohintRecipe = struct {
    destination: RecordKey,
    base: RecordKey,
    model_request: u32,
    glyph_request: u32,
};

const TtGlyphRecipe = struct {
    destination: RecordKey,
    advance_destination: RecordKey,
    request: u32,
    insert_geometry: bool,
    insert_advance: bool,
};

const TtAdvanceRecipe = struct {
    destination: RecordKey,
    request: u32,
};

const Recipe = union(enum) {
    geometry: GeometryRecipe,
    composite: CompositeRecipe,
    autohint: AutohintRecipe,
    tt_glyph: TtGlyphRecipe,
    tt_advance: TtAdvanceRecipe,
};

pub const PreparePlan = struct {
    allocator: Allocator,
    request_storage: []PrepareRequest,
    dependency_offsets: []u32,
    dependency_storage: []u32,
    recipes: []Recipe,
    composite_layers: []CompositeLayerRecipe,
    source_storage: []FontSource,
    required_records: []RecordKey,
    required_advances: []RecordKey,

    pub fn requests(self: *const PreparePlan) []const PrepareRequest {
        return self.request_storage;
    }

    /// Request indices which must complete before `request_index` may run.
    /// Most requests are independent. An autohint glyph depends only on its
    /// font model; its unhinted base is an atlas assembly dependency.
    pub fn dependencies(self: *const PreparePlan, request_index: usize) []const u32 {
        const start = self.dependency_offsets[request_index];
        const end = self.dependency_offsets[request_index + 1];
        return self.dependency_storage[start..end];
    }

    /// Build a persistent atlas snapshot without retaining result views.
    pub fn apply(
        self: *const PreparePlan,
        allocator: Allocator,
        atlas: *const Atlas,
        results: []const ?prepared.RecordView,
    ) !Atlas {
        var update = try self.buildUpdate(allocator, atlas, results);
        defer update.deinit();
        return atlas.extend(allocator, update.view());
    }

    /// Atomically replace `atlas` with its prepared extension.
    pub fn applyInPlace(
        self: *const PreparePlan,
        allocator: Allocator,
        atlas: *Atlas,
        results: []const ?prepared.RecordView,
    ) !void {
        var update = try self.buildUpdate(allocator, atlas, results);
        defer update.deinit();
        try atlas.extendInPlace(allocator, update.view());
    }

    pub fn deinit(self: *PreparePlan) void {
        self.allocator.free(self.request_storage);
        self.allocator.free(self.dependency_offsets);
        self.allocator.free(self.dependency_storage);
        self.allocator.free(self.recipes);
        self.allocator.free(self.composite_layers);
        self.allocator.free(self.source_storage);
        self.allocator.free(self.required_records);
        self.allocator.free(self.required_advances);
        self.* = undefined;
    }

    const BuiltUpdate = struct {
        arena: std.heap.ArenaAllocator,
        entries: std.ArrayList(atlas_mod.AtlasEntry) = .empty,
        advances: std.ArrayList(atlas_mod.TtAdvanceEntry) = .empty,

        fn view(self: *const BuiltUpdate) atlas_mod.AtlasUpdate {
            return .{
                .entries = self.entries.items,
                .tt_advances = self.advances.items,
            };
        }

        fn deinit(self: *BuiltUpdate) void {
            self.arena.deinit();
        }
    };

    fn buildUpdate(
        self: *const PreparePlan,
        allocator: Allocator,
        atlas: *const Atlas,
        results: []const ?prepared.RecordView,
    ) !BuiltUpdate {
        if (results.len != self.request_storage.len) return error.ResultCountMismatch;
        for (self.required_records) |key| {
            if (!atlas.contains(key)) return error.IncompatibleAtlas;
        }
        for (self.required_advances) |key| {
            if (atlas.lookupTtAdvance(key) == null) return error.IncompatibleAtlas;
        }

        // Preflight every external result before allocating atlas pages.
        for (self.request_storage, results) |request, maybe_result| {
            const result = maybe_result orelse return error.MissingResult;
            if (!result.key.eql(request.key)) return error.MismatchedResultKey;
            try result.validate();
            if (!valueMatchesOperation(result.value, request.operation)) {
                return error.MismatchedResultKind;
            }
        }

        var built = BuiltUpdate{ .arena = std.heap.ArenaAllocator.init(allocator) };
        errdefer built.deinit();
        const temp = built.arena.allocator();

        // Geometry first, so autohint aliases can reference bases from the
        // same atomic AtlasUpdate.
        for (self.recipes) |recipe| switch (recipe) {
            .autohint => {},
            else => try self.appendRecipe(&built, atlas, results, recipe, temp),
        };
        for (self.recipes) |recipe| switch (recipe) {
            .autohint => try self.appendRecipe(&built, atlas, results, recipe, temp),
            else => {},
        };
        return built;
    }

    fn appendRecipe(
        self: *const PreparePlan,
        built: *BuiltUpdate,
        atlas: *const Atlas,
        results: []const ?prepared.RecordView,
        recipe: Recipe,
        allocator: Allocator,
    ) !void {
        switch (recipe) {
            .geometry => |r| {
                if (atlas.contains(r.destination)) return;
                const geometry = results[r.request].?.value.geometry;
                try built.entries.append(allocator, .{ .geometry = .{
                    .key = r.destination,
                    .curves = geometry.atlasView(),
                } });
            },
            .composite => |r| {
                if (atlas.contains(r.destination)) return;
                const layer_recipes =
                    self.composite_layers[r.first_layer..][0..r.layer_count];
                const layers = try allocator.alloc(atlas_mod.Layer, layer_recipes.len);
                var visible: usize = 0;
                for (layer_recipes) |layer| {
                    const geometry = results[layer.request].?.value.geometry;
                    if (geometry.curve_count == 0) continue;
                    layers[visible] = .{
                        .curves = geometry.atlasView(),
                        .paint = layer.paint,
                    };
                    visible += 1;
                }
                if (visible == 0) {
                    const fallback = results[r.fallback_request].?.value.geometry;
                    try built.entries.append(allocator, .{ .geometry = .{
                        .key = r.destination,
                        .curves = fallback.atlasView(),
                    } });
                } else {
                    try built.entries.append(allocator, .{ .geometry = .{
                        .key = r.destination,
                        .curves = layers[0].curves,
                        .paint = layers[0].paint,
                        .extra_layers = layers[1..visible],
                    } });
                }
            },
            .autohint => |r| {
                if (atlas.contains(r.destination)) return;
                const model = results[r.model_request].?.value.autohint_model;
                const glyph = results[r.glyph_request].?.value.autohint_glyph;
                try built.entries.append(allocator, .{ .autohint = .{
                    .key = r.destination,
                    .base_key = r.base,
                    .analysis = .{
                        .font = .{
                            .blues = model.blues,
                            .std_x = model.std_x,
                            .std_y = model.std_y,
                        },
                        .glyph = .{
                            .x = glyph.x,
                            .y = glyph.y,
                            .left = glyph.left,
                        },
                    },
                } });
            },
            .tt_glyph => |r| {
                const value = results[r.request].?.value.tt_glyph;
                if (r.insert_geometry and !atlas.contains(r.destination)) {
                    try built.entries.append(allocator, .{ .geometry = .{
                        .key = r.destination,
                        .curves = value.geometry.atlasView(),
                    } });
                }
                if (r.insert_advance and atlas.lookupTtAdvance(r.advance_destination) == null) {
                    try built.advances.append(allocator, .{
                        .key = r.advance_destination,
                        .advance_26_6 = value.advance_x_26_6,
                    });
                }
            },
            .tt_advance => |r| {
                if (atlas.lookupTtAdvance(r.destination) != null) return;
                try built.advances.append(allocator, .{
                    .key = r.destination,
                    .advance_26_6 = results[r.request].?.value.tt_advance,
                });
            },
        }
    }
};

fn valueMatchesOperation(
    value: prepared.ValueView,
    operation: PrepareRequest.Operation,
) bool {
    return switch (operation) {
        .outline => switch (value) {
            .geometry => true,
            else => false,
        },
        .autohint_model => switch (value) {
            .autohint_model => true,
            else => false,
        },
        .autohint_glyph => switch (value) {
            .autohint_glyph => true,
            else => false,
        },
        .tt_glyph => switch (value) {
            .tt_glyph => true,
            else => false,
        },
        .tt_advance => switch (value) {
            .tt_advance => true,
            else => false,
        },
    };
}

const KeyContext = struct {
    pub fn hash(_: KeyContext, key: prepared.Key) u64 {
        return std.hash.Wyhash.hash(0, key.asBytes());
    }

    pub fn eql(_: KeyContext, a: prepared.Key, b: prepared.Key) bool {
        return a.eql(b);
    }
};

const PlanBuilder = struct {
    allocator: Allocator,
    atlas: *const Atlas,
    sources: []const FontSource,
    requests: std.ArrayList(PrepareRequest) = .empty,
    dependency_offsets: std.ArrayList(u32) = .empty,
    dependencies: std.ArrayList(u32) = .empty,
    recipes: std.ArrayList(Recipe) = .empty,
    composite_layers: std.ArrayList(CompositeLayerRecipe) = .empty,
    request_by_key: std.HashMapUnmanaged(prepared.Key, u32, KeyContext, 80) = .empty,
    destinations: std.AutoHashMapUnmanaged(RecordKey, void) = .empty,
    advance_destinations: std.AutoHashMapUnmanaged(RecordKey, void) = .empty,
    required_records: std.ArrayList(RecordKey) = .empty,
    required_advances: std.ArrayList(RecordKey) = .empty,
    required_record_set: std.AutoHashMapUnmanaged(RecordKey, void) = .empty,
    required_advance_set: std.AutoHashMapUnmanaged(RecordKey, void) = .empty,

    fn init(allocator: Allocator, atlas: *const Atlas, sources: []const FontSource) !PlanBuilder {
        var self = PlanBuilder{
            .allocator = allocator,
            .atlas = atlas,
            .sources = sources,
        };
        errdefer self.deinit();
        try self.validateSources();
        try self.dependency_offsets.append(allocator, 0);
        return self;
    }

    fn deinit(self: *PlanBuilder) void {
        self.requests.deinit(self.allocator);
        self.dependency_offsets.deinit(self.allocator);
        self.dependencies.deinit(self.allocator);
        self.recipes.deinit(self.allocator);
        self.composite_layers.deinit(self.allocator);
        self.request_by_key.deinit(self.allocator);
        self.destinations.deinit(self.allocator);
        self.advance_destinations.deinit(self.allocator);
        self.required_records.deinit(self.allocator);
        self.required_advances.deinit(self.allocator);
        self.required_record_set.deinit(self.allocator);
        self.required_advance_set.deinit(self.allocator);
    }

    fn validateSources(self: *const PlanBuilder) !void {
        for (self.sources, 0..) |source, i| {
            for (self.sources[0..i]) |previous| {
                if (source.font_id == previous.font_id) return error.DuplicateFontId;
            }
        }
    }

    fn sourceFor(self: *const PlanBuilder, font_id: u32) ?*const FontSource {
        for (self.sources) |*source| {
            if (source.font_id == font_id) return source;
        }
        return null;
    }

    fn addRequest(
        self: *PlanBuilder,
        request: PrepareRequest,
        dependencies: []const u32,
    ) !u32 {
        const gop = try self.request_by_key.getOrPut(self.allocator, request.key);
        if (gop.found_existing) return gop.value_ptr.*;
        const index = std.math.cast(u32, self.requests.items.len) orelse
            return error.TooManyRequests;
        gop.value_ptr.* = index;
        try self.requests.append(self.allocator, request);
        try self.dependencies.appendSlice(self.allocator, dependencies);
        try self.dependency_offsets.append(
            self.allocator,
            std.math.cast(u32, self.dependencies.items.len) orelse
                return error.TooManyRequests,
        );
        return index;
    }

    fn shouldPlanDestination(self: *PlanBuilder, key: RecordKey) !bool {
        if (self.atlas.contains(key)) {
            const gop = try self.required_record_set.getOrPut(self.allocator, key);
            if (!gop.found_existing) {
                try self.required_records.append(self.allocator, key);
            }
            return false;
        }
        const gop = try self.destinations.getOrPut(self.allocator, key);
        return !gop.found_existing;
    }

    fn shouldPlanAdvance(self: *PlanBuilder, key: RecordKey) !bool {
        if (self.atlas.lookupTtAdvance(key) != null) {
            const gop = try self.required_advance_set.getOrPut(self.allocator, key);
            if (!gop.found_existing) {
                try self.required_advances.append(self.allocator, key);
            }
            return false;
        }
        const gop = try self.advance_destinations.getOrPut(self.allocator, key);
        return !gop.found_existing;
    }

    fn outlineRequest(
        self: *PlanBuilder,
        source: *const FontSource,
        glyph_id: u16,
        options: prepared.GeometryOptions,
    ) !u32 {
        return self.addRequest(.{
            .key = try prepared.unhintedKey(source.cache_key, glyph_id, options),
            .operation = .{ .outline = .{
                .source = source,
                .glyph_id = glyph_id,
                .options = options,
            } },
        }, &.{});
    }

    fn planUnhintedGlyph(
        self: *PlanBuilder,
        source: *const FontSource,
        glyph_id: u16,
        options: UnhintedRunOptions,
    ) !void {
        if (options.colr == .layers) {
            var layer_iter = source.font.colrLayers(glyph_id);
            if (layer_iter.count() > 0) {
                while (layer_iter.next()) |layer| {
                    const destination =
                        record_key.unhintedGlyph(source.font_id, layer.glyph_id);
                    if (!try self.shouldPlanDestination(destination)) continue;
                    try self.recipes.append(self.allocator, .{ .geometry = .{
                        .destination = destination,
                        .request = try self.outlineRequest(
                            source,
                            layer.glyph_id,
                            options.geometry,
                        ),
                    } });
                }
                return;
            }
        }

        const destination = record_key.unhintedGlyph(source.font_id, glyph_id);
        if (!try self.shouldPlanDestination(destination)) return;

        var layer_iter = source.font.colrLayers(glyph_id);
        const layer_count = layer_iter.count();
        if (options.colr != .composite or layer_count == 0) {
            try self.recipes.append(self.allocator, .{ .geometry = .{
                .destination = destination,
                .request = try self.outlineRequest(source, glyph_id, options.geometry),
            } });
            return;
        }

        const first_layer = std.math.cast(u32, self.composite_layers.items.len) orelse
            return error.TooManyRequests;
        while (layer_iter.next()) |layer| {
            try self.composite_layers.append(self.allocator, .{
                .request = try self.outlineRequest(source, layer.glyph_id, options.geometry),
                .paint = .{ .solid = paletteColor(layer.color, options.colr_foreground) },
            });
        }
        try self.recipes.append(self.allocator, .{ .composite = .{
            .destination = destination,
            .fallback_request = try self.outlineRequest(source, glyph_id, options.geometry),
            .first_layer = first_layer,
            .layer_count = layer_count,
        } });
    }

    fn planAutohintGlyph(
        self: *PlanBuilder,
        source: *const FontSource,
        glyph_id: u16,
        options: AutohintRunOptions,
    ) !void {
        try self.planUnhintedGlyph(source, glyph_id, .{
            .colr = .outline_only,
            .geometry = options.geometry,
        });

        const destination = record_key.autohintGlyph(source.font_id, glyph_id);
        if (!try self.shouldPlanDestination(destination)) return;

        const model_request = try self.addRequest(.{
            .key = try prepared.autohintModelKey(source.cache_key, options.autohint),
            .operation = .{ .autohint_model = .{
                .source = source,
                .options = options.autohint,
            } },
        }, &.{});
        const glyph_request = try self.addRequest(.{
            .key = try prepared.autohintGlyphKey(
                source.cache_key,
                glyph_id,
                options.autohint,
            ),
            .operation = .{ .autohint_glyph = .{
                .source = source,
                .glyph_id = glyph_id,
                .options = options.autohint,
            } },
        }, &.{model_request});
        try self.recipes.append(self.allocator, .{ .autohint = .{
            .destination = destination,
            .base = record_key.unhintedGlyph(source.font_id, glyph_id),
            .model_request = model_request,
            .glyph_request = glyph_request,
        } });
    }

    fn planTtGlyph(
        self: *PlanBuilder,
        source: *const FontSource,
        glyph_id: u16,
        ppem: hint_vm_mod.TtHintPpem,
    ) !void {
        if (ppem.x_26_6 != ppem.y_26_6) return error.AnisotropicPpem;
        const packed_ppem = try ppem.packed26Dot6();
        const geometry_destination =
            record_key.ttHintedGlyph(source.font_id, glyph_id, ppem.x_26_6);
        const advance_destination =
            record_key.ttAdvance(source.font_id, glyph_id, packed_ppem);
        const insert_geometry = try self.shouldPlanDestination(geometry_destination);
        const insert_advance = try self.shouldPlanAdvance(advance_destination);
        if (!insert_geometry and !insert_advance) return;

        if (!insert_geometry) {
            const request = try self.addRequest(.{
                .key = try prepared.ttAdvanceKey(source.cache_key, glyph_id, ppem),
                .operation = .{ .tt_advance = .{
                    .source = source,
                    .glyph_id = glyph_id,
                    .ppem = ppem,
                } },
            }, &.{});
            try self.recipes.append(self.allocator, .{ .tt_advance = .{
                .destination = advance_destination,
                .request = request,
            } });
            return;
        }

        const request = try self.addRequest(.{
            .key = try prepared.ttGlyphKey(source.cache_key, glyph_id, ppem),
            .operation = .{ .tt_glyph = .{
                .source = source,
                .glyph_id = glyph_id,
                .ppem = ppem,
            } },
        }, &.{});
        try self.recipes.append(self.allocator, .{ .tt_glyph = .{
            .destination = geometry_destination,
            .advance_destination = advance_destination,
            .request = request,
            .insert_geometry = true,
            .insert_advance = insert_advance,
        } });
    }

    fn finish(self: *PlanBuilder) !PreparePlan {
        const request_storage = try self.requests.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(request_storage);
        const source_storage = try self.allocator.dupe(FontSource, self.sources);
        errdefer self.allocator.free(source_storage);
        for (request_storage) |*request| switch (request.operation) {
            inline else => |*operation| {
                for (source_storage) |*source| {
                    if (source.font_id == operation.source.font_id) {
                        operation.source = source;
                        break;
                    }
                }
            },
        };
        const dependency_offsets =
            try self.dependency_offsets.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(dependency_offsets);
        const dependency_storage =
            try self.dependencies.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(dependency_storage);
        const recipes = try self.recipes.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(recipes);
        const composite_layers =
            try self.composite_layers.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(composite_layers);
        const required_records =
            try self.required_records.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(required_records);
        const required_advances =
            try self.required_advances.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(required_advances);
        const result = PreparePlan{
            .allocator = self.allocator,
            .request_storage = request_storage,
            .dependency_offsets = dependency_offsets,
            .dependency_storage = dependency_storage,
            .recipes = recipes,
            .composite_layers = composite_layers,
            .source_storage = source_storage,
            .required_records = required_records,
            .required_advances = required_advances,
        };
        self.request_by_key.deinit(self.allocator);
        self.destinations.deinit(self.allocator);
        self.advance_destinations.deinit(self.allocator);
        self.required_record_set.deinit(self.allocator);
        self.required_advance_set.deinit(self.allocator);
        return result;
    }
};

fn paletteColor(color: [4]f32, foreground: [4]f32) [4]f32 {
    return if (color[0] < 0) foreground else color;
}

/// Plan all missing work for several independently shaped runs. `sources` is
/// also the selection set: glyphs whose runtime `font_id` is absent are
/// intentionally skipped. This lets a primary TrueType face be hinted while
/// fallback emoji or script faces retain their separately prepared unhinted
/// records.
pub fn planRuns(
    atlas: *const Atlas,
    allocator: Allocator,
    sources: []const FontSource,
    shaped_runs: []const *const text_mod.ShapedText,
    mode: PrepareMode,
) !PreparePlan {
    var builder = try PlanBuilder.init(allocator, atlas, sources);
    errdefer builder.deinit();
    for (shaped_runs) |shaped| {
        for (shaped.glyphs) |glyph| {
            const source = builder.sourceFor(glyph.font_id) orelse continue;
            switch (mode) {
                .unhinted => |options| try builder.planUnhintedGlyph(source, glyph.glyph_id, options),
                .autohint => |options| try builder.planAutohintGlyph(source, glyph.glyph_id, options),
                .tt_hint => |ppem| try builder.planTtGlyph(source, glyph.glyph_id, ppem),
            }
        }
    }
    return builder.finish();
}

/// Plan page-free TT advances for an asynchronous shape/prepare/reshape flow.
/// Like `planRuns`, the source slice selects participating font IDs. Unlike
/// rendered TT geometry, advances support independent x/y PPEM.
pub fn planTtAdvances(
    atlas: *const Atlas,
    allocator: Allocator,
    sources: []const FontSource,
    shaped_runs: []const *const text_mod.ShapedText,
    ppem: hint_vm_mod.TtHintPpem,
) !PreparePlan {
    try ppem.validate();
    var builder = try PlanBuilder.init(allocator, atlas, sources);
    errdefer builder.deinit();
    const packed_ppem = try ppem.packed26Dot6();
    for (shaped_runs) |shaped| {
        for (shaped.glyphs) |glyph| {
            const source = builder.sourceFor(glyph.font_id) orelse continue;
            const destination = record_key.ttAdvance(source.font_id, glyph.glyph_id, packed_ppem);
            if (!try builder.shouldPlanAdvance(destination)) continue;
            const request = try builder.addRequest(.{
                .key = try prepared.ttAdvanceKey(source.cache_key, glyph.glyph_id, ppem),
                .operation = .{ .tt_advance = .{
                    .source = source,
                    .glyph_id = glyph.glyph_id,
                    .ppem = ppem,
                } },
            }, &.{});
            try builder.recipes.append(allocator, .{ .tt_advance = .{
                .destination = destination,
                .request = request,
            } });
        }
    }
    return builder.finish();
}

/// Thread-confined outline extraction state. Returned owned records may move
/// freely between threads after the call completes.
pub const OutlineContext = struct {
    allocator: Allocator,
    scratch: std.heap.ArenaAllocator,
    instances: std.AutoHashMapUnmanaged(*const Font, Font.Instance) = .empty,

    pub fn init(allocator: Allocator, scratch_parent: Allocator) OutlineContext {
        return .{
            .allocator = allocator,
            .scratch = std.heap.ArenaAllocator.init(scratch_parent),
        };
    }

    pub fn prepare(
        self: *OutlineContext,
        request: PrepareRequest,
    ) !prepared.OwnedRecord {
        const operation = switch (request.operation) {
            .outline => |operation| operation,
            else => return error.WrongContext,
        };
        const instance = try self.instanceFor(operation.source.font);
        defer _ = self.scratch.reset(.retain_capacity);
        const curves = try operation.source.font.extractCurvesWithTolerance(
            instance,
            self.allocator,
            self.scratch.allocator(),
            operation.glyph_id,
            operation.options.cubic_tolerance,
        );
        return prepared.OwnedRecord.init(
            request.key,
            prepared.OwnedValue.fromGeometry(
                prepared.Geometry.fromGlyphCurves(curves),
            ),
        );
    }

    pub fn deinit(self: *OutlineContext) void {
        var iterator = self.instances.valueIterator();
        while (iterator.next()) |instance| instance.deinit();
        self.instances.deinit(self.allocator);
        self.scratch.deinit();
        self.* = undefined;
    }

    fn instanceFor(self: *OutlineContext, font: *const Font) !?*Font.Instance {
        if (!font.requiresInstance()) return null;
        const gop = try self.instances.getOrPut(self.allocator, font);
        if (!gop.found_existing) gop.value_ptr.* = try font.createInstance();
        return gop.value_ptr;
    }
};

/// Thread-confined, per-font autohint context.
pub const AutohintContext = struct {
    allocator: Allocator,
    source: *const FontSource,
    options: prepared.AutohintOptions,
    analyzer: autohint_mod.AutohintAnalyzer,
    scratch: std.heap.ArenaAllocator,

    pub fn init(
        allocator: Allocator,
        scratch_parent: Allocator,
        source: *const FontSource,
        options: prepared.AutohintOptions,
    ) !AutohintContext {
        try options.validate();
        return .{
            .allocator = allocator,
            .source = source,
            .options = options,
            .analyzer = try autohint_mod.AutohintAnalyzer.initFontWithOptions(
                allocator,
                source.font,
                .{
                    .params = options.params,
                    .blue_tolerance_em = options.blue_tolerance_em,
                },
            ),
            .scratch = std.heap.ArenaAllocator.init(scratch_parent),
        };
    }

    /// Cache-hit constructor used after the plan's `autohint_model`
    /// dependency resolves. It skips blue-zone and standard-width derivation.
    pub fn initWithModel(
        allocator: Allocator,
        scratch_parent: Allocator,
        source: *const FontSource,
        options: prepared.AutohintOptions,
        model: prepared.AutohintModelView,
    ) !AutohintContext {
        try options.validate();
        try model.validate();
        return .{
            .allocator = allocator,
            .source = source,
            .options = options,
            .analyzer = try autohint_mod.AutohintAnalyzer.initFontWithModel(
                allocator,
                source.font,
                .{
                    .params = options.params,
                    .blue_tolerance_em = options.blue_tolerance_em,
                },
                .{
                    .blues = model.blues,
                    .std_x = model.std_x,
                    .std_y = model.std_y,
                },
            ),
            .scratch = std.heap.ArenaAllocator.init(scratch_parent),
        };
    }

    pub fn prepare(
        self: *AutohintContext,
        request: PrepareRequest,
    ) !prepared.OwnedRecord {
        return switch (request.operation) {
            .autohint_model => |operation| blk: {
                try self.check(operation.source, operation.options);
                const model = self.analyzer.fontFeatures();
                break :blk prepared.OwnedRecord.init(
                    request.key,
                    try prepared.OwnedValue.cloneAutohintModel(
                        self.allocator,
                        .{
                            .blues = model.blues,
                            .std_x = model.std_x,
                            .std_y = model.std_y,
                        },
                    ),
                );
            },
            .autohint_glyph => |operation| blk: {
                try self.check(operation.source, operation.options);
                defer _ = self.scratch.reset(.retain_capacity);
                const x = try self.scratch.allocator().alloc(
                    autohint_mod.FeatureEdge,
                    autohint_mod.max_features_per_axis,
                );
                const y = try self.scratch.allocator().alloc(
                    autohint_mod.FeatureEdge,
                    autohint_mod.max_features_per_axis,
                );
                const glyph = try self.analyzer.analyzeGlyph(
                    self.scratch.allocator(),
                    operation.glyph_id,
                    x,
                    y,
                );
                const value = try prepared.OwnedValue.cloneAutohintGlyph(
                    self.allocator,
                    .{ .x = glyph.x, .y = glyph.y, .left = glyph.left },
                );
                break :blk prepared.OwnedRecord.init(request.key, value);
            },
            else => error.WrongContext,
        };
    }

    pub fn deinit(self: *AutohintContext) void {
        self.scratch.deinit();
        self.analyzer.deinit();
        self.* = undefined;
    }

    fn check(
        self: *const AutohintContext,
        source: *const FontSource,
        options: prepared.AutohintOptions,
    ) !void {
        if (source.font != self.source.font or
            !std.mem.eql(u8, &source.cache_key, &self.source.cache_key))
        {
            return error.WrongFontSource;
        }
        if (!std.meta.eql(options, self.options)) return error.WrongAutohintOptions;
    }
};

pub const TtHintSize = struct {
    ppem: hint_vm_mod.TtHintPpem,
    prepared_ppem: hint_vm_mod.TtHintVm.PreparedPpem,
    font: *const Font,
    cache_key: prepared.FontKey,

    pub fn deinit(self: *TtHintSize) void {
        self.prepared_ppem.deinit();
        self.* = undefined;
    }
};

/// Thread-confined, per-font TrueType hinting context.
pub const TtHintContext = struct {
    allocator: Allocator,
    source: *const FontSource,
    vm: hint_vm_mod.TtHintVm,
    scratch: std.heap.ArenaAllocator,

    pub fn init(
        allocator: Allocator,
        scratch_parent: Allocator,
        source: *const FontSource,
    ) !TtHintContext {
        return .{
            .allocator = allocator,
            .source = source,
            .vm = try hint_vm_mod.TtHintVm.init(allocator, source.font),
            .scratch = std.heap.ArenaAllocator.init(scratch_parent),
        };
    }

    pub fn prepareSize(
        self: *TtHintContext,
        ppem: hint_vm_mod.TtHintPpem,
    ) !TtHintSize {
        return .{
            .ppem = ppem,
            .prepared_ppem = try self.vm.prepare(ppem),
            .font = self.source.font,
            .cache_key = self.source.cache_key,
        };
    }

    pub fn prepare(
        self: *TtHintContext,
        size: *const TtHintSize,
        request: PrepareRequest,
    ) !prepared.OwnedRecord {
        return switch (request.operation) {
            .tt_glyph => |operation| blk: {
                try self.check(operation.source, size, operation.ppem);
                defer _ = self.scratch.reset(.retain_capacity);
                const hinted = try self.vm.hintGlyphWithAdvance(
                    self.allocator,
                    self.scratch.allocator(),
                    &size.prepared_ppem,
                    operation.glyph_id,
                );
                break :blk prepared.OwnedRecord.init(
                    request.key,
                    prepared.OwnedValue.fromTtGlyph(
                        prepared.Geometry.fromGlyphCurves(hinted.curves),
                        hinted.advance_x_26_6,
                    ),
                );
            },
            .tt_advance => |operation| blk: {
                try self.check(operation.source, size, operation.ppem);
                break :blk prepared.OwnedRecord.init(
                    request.key,
                    prepared.OwnedValue.fromTtAdvance(
                        try self.vm.hintedAdvance(
                            &size.prepared_ppem,
                            operation.glyph_id,
                        ),
                    ),
                );
            },
            else => error.WrongContext,
        };
    }

    pub fn deinit(self: *TtHintContext) void {
        self.scratch.deinit();
        self.vm.deinit();
        self.* = undefined;
    }

    fn check(
        self: *const TtHintContext,
        source: *const FontSource,
        size: *const TtHintSize,
        ppem: hint_vm_mod.TtHintPpem,
    ) !void {
        if (source.font != self.source.font or
            !std.mem.eql(u8, &source.cache_key, &self.source.cache_key))
        {
            return error.WrongFontSource;
        }
        if (size.font != self.source.font or
            !std.mem.eql(u8, &size.cache_key, &self.source.cache_key))
        {
            return error.WrongHintSizeSource;
        }
        if (size.ppem.x_26_6 != ppem.x_26_6 or
            size.ppem.y_26_6 != ppem.y_26_6)
        {
            return error.WrongPpem;
        }
    }
};

/// Cache-only advance provider. Misses deliberately fall back to native font
/// advances; callers use `planTtAdvances` and reshape to fill them.
pub const TtAdvanceSource = struct {
    atlas: *const Atlas,
    sources: []const FontSource,
    archives: []const prepared.Archive = &.{},

    pub fn advanceProvider(self: *TtAdvanceSource) text_mod.AdvanceProvider {
        return .{
            .context = @ptrCast(self),
            .covers = covers,
            .get_advance = getAdvance,
        };
    }

    fn covers(context: *anyopaque, font_id: u32) bool {
        const self: *TtAdvanceSource = @ptrCast(@alignCast(context));
        return self.sourceFor(font_id) != null;
    }

    fn sourceFor(self: *const TtAdvanceSource, font_id: u32) ?*const FontSource {
        for (self.sources) |*source| {
            if (source.font_id == font_id) return source;
        }
        return null;
    }

    fn getAdvance(
        context: *anyopaque,
        font_id: u32,
        glyph_id: u16,
        ppem: hint_vm_mod.TtHintPpem,
    ) ?i32 {
        const self: *TtAdvanceSource = @ptrCast(@alignCast(context));
        const source = self.sourceFor(font_id) orelse return null;
        const packed_ppem = ppem.packed26Dot6() catch return null;
        if (self.atlas.lookupTtAdvance(
            record_key.ttAdvance(font_id, glyph_id, packed_ppem),
        )) |advance| return advance;

        const advance_key = prepared.ttAdvanceKey(
            source.cache_key,
            glyph_id,
            ppem,
        ) catch return null;
        var i = self.archives.len;
        while (i > 0) {
            i -= 1;
            if (self.archives[i].find(advance_key)) |record| switch (record.value) {
                .tt_advance => |advance| return advance,
                else => {},
            };
        }

        if (ppem.x_26_6 == ppem.y_26_6) {
            const glyph_key = prepared.ttGlyphKey(
                source.cache_key,
                glyph_id,
                ppem,
            ) catch return null;
            i = self.archives.len;
            while (i > 0) {
                i -= 1;
                if (self.archives[i].find(glyph_key)) |record| switch (record.value) {
                    .tt_glyph => |glyph| return glyph.advance_x_26_6,
                    else => {},
                };
            }
        }
        return null;
    }
};

const testing = std.testing;

test "plan never extracts COLR composites and results may arrive out of order" {
    var regular = try Font.init(@import("assets").noto_sans_regular);
    var emoji = try Font.init(@import("assets").twemoji_mozilla);
    var faces = try @import("../text/faces.zig").Faces.build(testing.allocator, &.{
        .{ .font = &regular, .font_id = 0 },
        .{ .font = &emoji, .font_id = 1, .fallback = true },
    });
    defer faces.deinit();
    var shaped = try @import("../text/faces.zig").shape(
        testing.allocator,
        &faces,
        "AA\xf0\x9f\x8c\x8d",
        .{},
    );
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 8,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    const sources = [_]FontSource{
        .{ .font_id = 0, .font = &regular, .cache_key = .{0} ** 16 },
        .{ .font_id = 1, .font = &emoji, .cache_key = .{1} ** 16 },
    };
    var plan = try planRuns(
        &atlas,
        testing.allocator,
        &sources,
        &.{&shaped},
        .{ .unhinted = .{} },
    );
    defer plan.deinit();
    try testing.expect(plan.requests().len > 1);

    var owned = try testing.allocator.alloc(?prepared.OwnedRecord, plan.requests().len);
    defer testing.allocator.free(owned);
    @memset(owned, null);
    var views = try testing.allocator.alloc(?prepared.RecordView, plan.requests().len);
    defer testing.allocator.free(views);
    @memset(views, null);
    var context = OutlineContext.init(testing.allocator, testing.allocator);
    defer context.deinit();

    var i = plan.requests().len;
    while (i > 0) {
        i -= 1;
        owned[i] = try context.prepare(plan.requests()[i]);
        views[i] = owned[i].?.view();
    }
    defer for (owned) |*record| if (record.*) |*value| value.deinit();

    // Applying views from an mmap-shaped archive is identical to applying
    // fresh owned results.
    var archive_builder = prepared.ArchiveBuilder.init(testing.allocator);
    defer archive_builder.deinit();
    for (views) |record| try archive_builder.add(record.?);
    var archive_owner = try archive_builder.finishAlloc(testing.allocator);
    defer archive_owner.deinit();
    const archive = archive_owner.view();
    for (plan.requests(), 0..) |request, result_index| {
        views[result_index] = archive.find(request.key).?;
    }

    try plan.applyInPlace(testing.allocator, &atlas, views);
    for (shaped.glyphs) |glyph| {
        try testing.expect(atlas.contains(
            record_key.unhintedGlyph(glyph.font_id, glyph.glyph_id),
        ));
    }
}

test "apply rejects swapped cache records before mutating the atlas" {
    var font = try Font.init(@import("assets").noto_sans_regular);
    var faces = try @import("../text/faces.zig").Faces.build(
        testing.allocator,
        &.{.{ .font = &font, .font_id = 7 }},
    );
    defer faces.deinit();
    var shaped = try @import("../text/faces.zig").shape(
        testing.allocator,
        &faces,
        "ab",
        .{},
    );
    defer shaped.deinit();
    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 15,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    const sources = [_]FontSource{.{
        .font_id = 7,
        .font = &font,
        .cache_key = .{7} ** 16,
    }};
    var plan = try planRuns(
        &atlas,
        testing.allocator,
        &sources,
        &.{&shaped},
        .{ .unhinted = .{} },
    );
    defer plan.deinit();
    try testing.expect(plan.requests().len >= 2);

    var context = OutlineContext.init(testing.allocator, testing.allocator);
    defer context.deinit();
    var first = try context.prepare(plan.requests()[0]);
    defer first.deinit();
    var second = try context.prepare(plan.requests()[1]);
    defer second.deinit();
    var results = [_]?prepared.RecordView{ second.view(), first.view() };
    try testing.expectError(
        error.MismatchedResultKey,
        plan.applyInPlace(testing.allocator, &atlas, &results),
    );
    try testing.expectEqual(@as(u32, 0), atlas.recordCount());
}

test "apply rejects an atlas missing records present during planning" {
    var font = try Font.init(@import("assets").noto_sans_regular);
    var faces = try @import("../text/faces.zig").Faces.build(
        testing.allocator,
        &.{.{ .font = &font, .font_id = 7 }},
    );
    defer faces.deinit();
    var shaped = try @import("../text/faces.zig").shape(
        testing.allocator,
        &faces,
        "A",
        .{},
    );
    defer shaped.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 15,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    const glyph_id = shaped.glyphs[0].glyph_id;
    var curves = try font.extractCurves(
        testing.allocator,
        testing.allocator,
        glyph_id,
    );
    defer curves.deinit();
    var planning_atlas = try Atlas.from(testing.allocator, pool, .{
        .entries = &.{.{ .geometry = .{
            .key = record_key.unhintedGlyph(7, glyph_id),
            .curves = curves.view(),
        } }},
    });
    defer planning_atlas.deinit();

    const sources = [_]FontSource{.{
        .font_id = 7,
        .font = &font,
        .cache_key = .{7} ** 16,
    }};
    var plan = try planRuns(
        &planning_atlas,
        testing.allocator,
        &sources,
        &.{&shaped},
        .{ .unhinted = .{} },
    );
    defer plan.deinit();
    try testing.expectEqual(@as(usize, 0), plan.requests().len);

    var replacement = try Atlas.init(testing.allocator, pool);
    defer replacement.deinit();
    try testing.expectError(
        error.IncompatibleAtlas,
        plan.applyInPlace(testing.allocator, &replacement, &.{}),
    );
}

test "source slices select fonts and are copied into asynchronous plans" {
    var regular = try Font.init(@import("assets").noto_sans_regular);
    var emoji = try Font.init(@import("assets").twemoji_mozilla);
    var faces = try @import("../text/faces.zig").Faces.build(testing.allocator, &.{
        .{ .font = &regular, .font_id = 0 },
        .{ .font = &emoji, .font_id = 1, .fallback = true },
    });
    defer faces.deinit();
    var shaped = try @import("../text/faces.zig").shape(
        testing.allocator,
        &faces,
        "A\xf0\x9f\x8c\x8d",
        .{},
    );
    defer shaped.deinit();
    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 2,
        .curve_words_per_page = 1 << 14,
        .band_words_per_page = 1 << 12,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
    defer atlas.deinit();

    const selected = [_]FontSource{.{
        .font_id = 0,
        .font = &regular,
        .cache_key = [_]u8{0xaa} ** 16,
    }};
    var plan = try planRuns(
        &atlas,
        testing.allocator,
        &selected,
        &.{&shaped},
        .{ .unhinted = .{} },
    );
    defer plan.deinit();
    try testing.expectEqual(@as(usize, 1), plan.requests().len);
    const request_source = plan.requests()[0].operation.outline.source;
    try testing.expect(request_source != &selected[0]);
    try testing.expectEqual(@as(u32, 0), request_source.font_id);
    try testing.expect(request_source.font == &regular);
}

test "TT advance source reads newest archive without VM fallback" {
    var font = try Font.init(@import("assets").dejavu_sans_mono);
    const source = FontSource{
        .font_id = 3,
        .font = &font,
        .cache_key = [_]u8{0x33} ** 16,
    };
    const ppem = hint_vm_mod.TtHintPpem{
        .x_26_6 = 13 * 64,
        .y_26_6 = 14 * 64,
    };
    const glyph_id = try font.glyphIndex('A');
    var record = prepared.OwnedRecord.init(
        try prepared.ttAdvanceKey(source.cache_key, glyph_id, ppem),
        prepared.OwnedValue.fromTtAdvance(777),
    );
    defer record.deinit();
    var builder = prepared.ArchiveBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.add(record.view());
    var archive_owner = try builder.finishAlloc(testing.allocator);
    defer archive_owner.deinit();
    const archives = [_]prepared.Archive{archive_owner.view()};

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 1,
        .curve_words_per_page = 128,
        .band_words_per_page = 128,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
    defer atlas.deinit();
    var source_list = [_]FontSource{source};
    var advance_source = TtAdvanceSource{
        .atlas = &atlas,
        .sources = &source_list,
        .archives = &archives,
    };
    const provider = advance_source.advanceProvider();
    try testing.expectEqual(
        @as(?i32, 777),
        provider.get_advance(provider.context, 3, glyph_id, ppem),
    );
}

test "TT hint size cannot cross font contexts" {
    var font_a = try Font.init(@import("assets").dejavu_sans_mono);
    var font_b = try Font.init(@import("assets").dejavu_sans_mono);
    const source_a = FontSource{
        .font_id = 1,
        .font = &font_a,
        .cache_key = [_]u8{0x11} ** 16,
    };
    const source_b = FontSource{
        .font_id = 2,
        .font = &font_b,
        .cache_key = [_]u8{0x22} ** 16,
    };
    const ppem = hint_vm_mod.TtHintPpem{
        .x_26_6 = 13 * 64,
        .y_26_6 = 13 * 64,
    };
    const glyph_id = try font_b.glyphIndex('A');

    var context_a = try TtHintContext.init(
        testing.allocator,
        testing.allocator,
        &source_a,
    );
    defer context_a.deinit();
    var context_b = try TtHintContext.init(
        testing.allocator,
        testing.allocator,
        &source_b,
    );
    defer context_b.deinit();
    var size_a = try context_a.prepareSize(ppem);
    defer size_a.deinit();

    try testing.expectError(error.WrongHintSizeSource, context_b.prepare(
        &size_a,
        .{
            .key = try prepared.ttAdvanceKey(
                source_b.cache_key,
                glyph_id,
                ppem,
            ),
            .operation = .{ .tt_advance = .{
                .source = &source_b,
                .glyph_id = glyph_id,
                .ppem = ppem,
            } },
        },
    ));
}

test "autohint glyph requests depend on a reusable font model" {
    var font = try Font.init(@import("assets").dejavu_sans_mono);
    var faces = try @import("../text/faces.zig").Faces.build(
        testing.allocator,
        &.{.{ .font = &font, .font_id = 4 }},
    );
    defer faces.deinit();
    var shaped = try @import("../text/faces.zig").shape(
        testing.allocator,
        &faces,
        " A",
        .{},
    );
    defer shaped.deinit();
    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_pages = 4,
        .curve_words_per_page = 1 << 15,
        .band_words_per_page = 1 << 13,
    });
    defer pool.deinit();
    var atlas = try Atlas.init(testing.allocator, pool);
    defer atlas.deinit();
    const sources = [_]FontSource{.{
        .font_id = 4,
        .font = &font,
        .cache_key = [_]u8{4} ** 16,
    }};
    const options = prepared.AutohintOptions{};
    var plan = try planRuns(
        &atlas,
        testing.allocator,
        &sources,
        &.{&shaped},
        .{ .autohint = .{ .autohint = options } },
    );
    defer plan.deinit();
    var owned = try testing.allocator.alloc(
        ?prepared.OwnedRecord,
        plan.requests().len,
    );
    defer testing.allocator.free(owned);
    @memset(owned, null);
    var views = try testing.allocator.alloc(
        ?prepared.RecordView,
        plan.requests().len,
    );
    defer testing.allocator.free(views);
    @memset(views, null);
    defer for (owned) |*record| if (record.*) |*value| value.deinit();

    var outline = OutlineContext.init(testing.allocator, testing.allocator);
    defer outline.deinit();
    var model_context = try AutohintContext.init(
        testing.allocator,
        testing.allocator,
        &sources[0],
        options,
    );
    defer model_context.deinit();

    var model_index: ?usize = null;
    for (plan.requests(), 0..) |request, request_index| switch (request.operation) {
        .outline => {
            owned[request_index] = try outline.prepare(request);
            views[request_index] = owned[request_index].?.view();
        },
        .autohint_model => {
            model_index = request_index;
            owned[request_index] = try model_context.prepare(request);
            views[request_index] = owned[request_index].?.view();
        },
        else => {},
    };
    const model_request = model_index orelse return error.MissingModelRequest;
    const model = views[model_request].?.value.autohint_model;
    var glyph_context = try AutohintContext.initWithModel(
        testing.allocator,
        testing.allocator,
        &sources[0],
        options,
        model,
    );
    defer glyph_context.deinit();
    for (plan.requests(), 0..) |request, request_index| switch (request.operation) {
        .autohint_glyph => {
            try testing.expectEqualSlices(
                u32,
                &.{@as(u32, @intCast(model_request))},
                plan.dependencies(request_index),
            );
            owned[request_index] = try glyph_context.prepare(request);
            views[request_index] = owned[request_index].?.view();
        },
        else => {},
    };

    try plan.applyInPlace(testing.allocator, &atlas, views);
    for (shaped.glyphs) |glyph| {
        try testing.expect(atlas.contains(
            record_key.autohintGlyph(4, glyph.glyph_id),
        ));
    }
}

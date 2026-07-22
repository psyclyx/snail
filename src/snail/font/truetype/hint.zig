const std = @import("std");

const bezier = @import("../../math/bezier.zig");
const curve_tex = @import("../../format/curve_texture.zig");
const tt_exec = @import("exec.zig");
const tt_graphics = @import("graphics.zig");
const tt_outline = @import("outline.zig");
const tt_points = @import("points.zig");
const tt_vm = @import("vm.zig");
const vec = @import("../../math/vec.zig");

const Allocator = std.mem.Allocator;
const CurveSegment = bezier.CurveSegment;
const BBox = bezier.BBox;
const Program = tt_vm.Program;
const QuadBezier = tt_points.QuadBezier;
const Vec2 = vec.Vec2;

pub const HintPpem = struct {
    x_26_6: u32,
    y_26_6: u32,

    pub fn uniform(ppem_26_6: u32) HintPpem {
        return .{ .x_26_6 = ppem_26_6, .y_26_6 = ppem_26_6 };
    }
};

pub const HintOptions = struct {
    /// See `tt_vm.SizeRequest.cvt_headroom`.
    cvt_headroom: u32 = 0,
};

pub const GlyphHint = struct {
    allocator: Allocator,
    glyph_id: u16,
    advance: Vec2,
    bbox: BBox,
    curves: []CurveSegment,
    prepared_curves: []CurveSegment,
    curve_bboxes: []BBox,

    pub fn deinit(self: *GlyphHint) void {
        self.allocator.free(self.curves);
        self.allocator.free(self.prepared_curves);
        self.allocator.free(self.curve_bboxes);
        self.* = undefined;
    }
};

pub const ExecutedGlyph = union(enum) {
    empty: Vec2,
    simple: tt_vm.HintedSimpleGlyph,
};

const CompoundBuildError = error{
    BufferTooSmall,
    InvalidFont,
    MissingRequiredTable,
    OutOfMemory,
    UnexpectedEof,
};

pub const GlyphTopologyCache = struct {
    allocator: Allocator,
    program: *const Program,
    map: std.AutoHashMap(u16, tt_vm.GlyphTopology),

    pub fn initForProgram(allocator: Allocator, program: *const Program) GlyphTopologyCache {
        return .{
            .allocator = allocator,
            .program = program,
            .map = std.AutoHashMap(u16, tt_vm.GlyphTopology).init(allocator),
        };
    }

    pub fn deinit(self: *GlyphTopologyCache) void {
        var values = self.map.valueIterator();
        while (values.next()) |topology| topology.deinit();
        self.map.deinit();
        self.* = undefined;
    }

    pub fn preload(self: *GlyphTopologyCache, glyph_ids: []const u16) !void {
        for (glyph_ids) |glyph_id| _ = try self.get(glyph_id);
    }

    pub fn get(self: *GlyphTopologyCache, glyph_id: u16) !*tt_vm.GlyphTopology {
        const gop = try self.map.getOrPut(glyph_id);
        if (!gop.found_existing) {
            // `getOrPut` publishes a slot before the fallible parse. Remove
            // that uninitialized slot on failure so retries do not read it and
            // `deinit` never switches on undefined union storage.
            errdefer _ = self.map.remove(glyph_id);
            gop.value_ptr.* = try self.program.loadGlyphTopology(self.allocator, glyph_id);
        }
        return gop.value_ptr;
    }
};

/// Immutable per-ppem hinting state: everything `fpgm` + `prep` produced at
/// one size (scaled + post-prep CVT, the fpgm functions, post-prep storage and
/// graphics defaults). Pure to hint from — `HintMachine.hintGlyph` never
/// mutates it; a glyph program's rare CVT/storage write is COW-scoped to the
/// run. A caller caches one per ppem; the atlas caches the resulting curves.
pub const Prepared = struct {
    allocator: Allocator,
    size: tt_vm.SizeState,
    function_entries: []tt_exec.Function,
    function_lookup: []?[]const u8,
    functions: tt_exec.FunctionDefs,
    storage: []i32,
    graphics: tt_exec.GraphicsState,

    pub fn deinit(self: *Prepared) void {
        self.allocator.free(self.function_entries);
        self.allocator.free(self.function_lookup);
        self.allocator.free(self.storage);
        self.size.deinit();
        self.* = undefined;
    }

    pub fn gridFits(self: *const Prepared) bool {
        return self.size.grid_fit;
    }

    /// Approximate heap footprint, for caller eviction budgeting.
    pub fn byteSize(self: *const Prepared) usize {
        return self.storage.len * @sizeOf(i32) +
            self.function_entries.len * @sizeOf(tt_exec.Function) +
            self.function_lookup.len * @sizeOf(?[]const u8);
    }
};

/// Reusable working buffers for one hinting thread — no per-ppem or per-glyph
/// state, just scratch that `prepare`/`hintGlyph` overwrite. Sized once from
/// the program's maxp; a caller keeps one and pairs it with any `Prepared`.
/// `prepared` is a transient binding set for the duration of a hint call.
pub const HintMachine = struct {
    allocator: Allocator,
    program: *const Program,
    stack: []i32,
    storage_work: []i32,
    cvt_work: []i32,
    /// COW targets for a glyph-level FDEF: the function table is copied here
    /// before the write so the shared `Prepared` is never mutated. Sized once
    /// from the program's maxp (function counts don't vary by ppem).
    function_entries_work: []tt_exec.Function,
    function_lookup_work: []?[]const u8,
    skip_cache: tt_exec.SkipCache,
    twilight_points: []tt_exec.Point,
    glyph_points: []tt_exec.Point,
    compound_contours: []tt_outline.ContourRange,
    zones: tt_exec.PointZones,
    /// Bound to the `Prepared` being hinted for the current call only.
    prepared: *const Prepared = undefined,

    pub fn initForProgram(allocator: Allocator, program: *const Program) !HintMachine {
        return allocateMachine(allocator, program);
    }

    pub fn deinit(self: *HintMachine) void {
        self.allocator.free(self.stack);
        self.allocator.free(self.storage_work);
        self.allocator.free(self.cvt_work);
        self.allocator.free(self.function_entries_work);
        self.allocator.free(self.function_lookup_work);
        self.allocator.free(self.twilight_points);
        self.allocator.free(self.glyph_points);
        self.allocator.free(self.compound_contours);
        self.skip_cache.deinit();
        self.* = undefined;
    }

    /// Approximate heap footprint of the reusable scratch.
    pub fn byteSize(self: *const HintMachine) usize {
        return self.stack.len * @sizeOf(i32) +
            self.storage_work.len * @sizeOf(i32) +
            self.cvt_work.len * @sizeOf(i32) +
            self.twilight_points.len * @sizeOf(tt_exec.Point) +
            self.glyph_points.len * @sizeOf(tt_exec.Point) +
            self.compound_contours.len * @sizeOf(tt_outline.ContourRange);
    }

    /// Run `fpgm` + `prep` at `ppem` and capture the immutable result. `alloc`
    /// owns the returned `Prepared`; this scratch is used transiently.
    pub fn prepare(self: *HintMachine, alloc: Allocator, ppem: HintPpem, options: HintOptions) !Prepared {
        var size = try self.program.sizeState(alloc, .{
            .ppem_x_26_6 = ppem.x_26_6,
            .ppem_y_26_6 = ppem.y_26_6,
            .cvt_headroom = options.cvt_headroom,
        });
        errdefer size.deinit();

        const sizes = self.program.executionBufferSizes();
        const function_entries = try alloc.alloc(tt_exec.Function, @max(sizes.functions, 1));
        errdefer alloc.free(function_entries);
        const function_lookup = try alloc.alloc(?[]const u8, functionLookupCapacity(sizes.functions));
        errdefer alloc.free(function_lookup);
        @memset(function_lookup, null);
        var functions: tt_exec.FunctionDefs = .{ .entries = function_entries, .lookup = function_lookup };

        const storage = try alloc.alloc(i32, self.storage_work.len);
        errdefer alloc.free(storage);
        @memset(storage, 0);

        // The reusable CVT work buffer must cover this size's CVT for COW.
        if (self.cvt_work.len < size.cvt.len) self.cvt_work = try self.allocator.realloc(self.cvt_work, size.cvt.len);

        // fpgm defines functions; prep scales/writes CVT+storage+graphics.
        var context = size.executionContext(.{ .stack = self.stack, .storage = storage }, .{});
        context.setSkipCache(&self.skip_cache);
        context.setFunctions(&functions);
        context.setZones(&self.zones);
        try self.program.runFontProgram(&context);

        context.reset();
        context.resetGraphics();
        context.setEnvironment(size.environment());
        context.setFunctions(&functions);
        context.setZones(&self.zones);
        try self.program.runControlProgram(&context);

        return .{
            .allocator = alloc,
            .size = size,
            .function_entries = function_entries,
            .function_lookup = function_lookup,
            .functions = functions,
            .storage = storage,
            .graphics = context.graphics,
        };
    }

    /// Bind the `Prepared` to hint from and make sure the reusable CVT work
    /// buffer covers its CVT (for the COW). Called at every entry point.
    fn bind(self: *HintMachine, prepared: *const Prepared) !void {
        self.prepared = prepared;
        if (self.cvt_work.len < prepared.size.cvt.len)
            self.cvt_work = try self.allocator.realloc(self.cvt_work, prepared.size.cvt.len);
    }

    pub fn hintGlyph(self: *HintMachine, allocator: Allocator, prepared: *const Prepared, glyph_id: u16) !GlyphHint {
        try self.bind(prepared);
        var topology = try self.program.loadGlyphTopology(allocator, glyph_id);
        defer topology.deinit();
        const executed = try self.executeTopology(glyph_id, &topology, null);
        return self.buildGlyphHint(allocator, glyph_id, executed);
    }

    pub fn hintCachedGlyph(
        self: *HintMachine,
        allocator: Allocator,
        prepared: *const Prepared,
        cache: *GlyphTopologyCache,
        glyph_id: u16,
    ) !GlyphHint {
        const executed = try self.executeCachedGlyph(prepared, cache, glyph_id);
        return self.buildGlyphHint(allocator, glyph_id, executed);
    }

    /// Executes the glyph program using caller-owned face-invariant topology.
    /// The returned simple glyph view is invalidated by the next glyph execution.
    pub fn executeCachedGlyph(
        self: *HintMachine,
        prepared: *const Prepared,
        cache: *GlyphTopologyCache,
        glyph_id: u16,
    ) !ExecutedGlyph {
        try self.bind(prepared);
        return self.executeTopology(glyph_id, try cache.get(glyph_id), cache);
    }

    pub fn buildGlyphHint(
        self: *const HintMachine,
        allocator: Allocator,
        glyph_id: u16,
        executed: ExecutedGlyph,
    ) !GlyphHint {
        return switch (executed) {
            .empty => |advance| emptyGlyphHint(allocator, glyph_id, advance),
            .simple => |hinted| self.makeGlyphHint(allocator, glyph_id, hinted),
        };
    }

    /// Horizontal advance after hinting, expressed in 26.6 fixed-point
    /// pixels at the machine's current ppem. Useful as a metrics-only
    /// query — the caller pays for the VM run but not for curve/band
    /// texture construction.
    pub fn glyphAdvanceX26Dot6(
        self: *HintMachine,
        prepared: *const Prepared,
        cache: *GlyphTopologyCache,
        glyph_id: u16,
    ) !i32 {
        const executed = try self.executeCachedGlyph(prepared, cache, glyph_id);
        return self.advanceX26Dot6FromExecuted(glyph_id, executed);
    }

    /// Pull the 26.6 px advance out of an `ExecutedGlyph` produced by
    /// `executeCachedGlyph`. Public so callers that already ran the VM
    /// (e.g. `hint()` building curves) can grab the advance without a
    /// second execution. Uses the `Prepared` bound by that execution.
    pub fn advanceX26Dot6FromExecuted(
        self: *const HintMachine,
        glyph_id: u16,
        executed: ExecutedGlyph,
    ) !i32 {
        return switch (executed) {
            .empty => blk: {
                const phantoms = try self.program.glyphPhantomMetrics(glyph_id);
                const left = @as(i32, phantoms.x_min) - @as(i32, phantoms.left_side_bearing);
                const right = left + @as(i32, phantoms.advance_width);
                const env = self.prepared.size.environment();
                break :blk env.scaleFUnitsX(right) - env.scaleFUnitsX(left);
            },
            .simple => |hinted| hinted.advance_x_26_6,
        };
    }

    /// Build the exec context for a glyph: reuse-scratch stack/points/zones,
    /// alias the prepared CVT/storage with COW (so a glyph write can't mutate
    /// the cached prepared state), and start graphics from the post-prep
    /// defaults — the alias IS the per-glyph reset, no snapshot restore.
    fn makeContext(self: *HintMachine) tt_exec.Context {
        const p = self.prepared;
        var context = tt_exec.Context.init(.{
            .stack = self.stack,
            .storage = p.storage,
            .cvt = p.size.cvt,
        }, .{});
        context.cvt_pristine = p.size.cvt;
        context.cvt_work = self.cvt_work[0..p.size.cvt.len];
        context.storage_pristine = p.storage;
        context.storage_work = self.storage_work[0..p.storage.len];
        context.functions_pristine = p.function_entries;
        context.functions_entries_work = self.function_entries_work[0..p.function_entries.len];
        context.functions_lookup_work = self.function_lookup_work[0..p.function_lookup.len];
        context.setEnvironment(p.size.environment());
        context.graphics = p.graphics;
        context.resetGraphicsForGlyph();
        context.setSkipCache(&self.skip_cache);
        return context;
    }

    fn executeTopology(
        self: *HintMachine,
        glyph_id: u16,
        topology: *tt_vm.GlyphTopology,
        cache: ?*GlyphTopologyCache,
    ) !ExecutedGlyph {
        return switch (topology.*) {
            .empty => .{ .empty = try self.emptyAdvance(glyph_id) },
            .simple => |*simple| .{ .simple = try self.executeSimpleGlyph(glyph_id, simple) },
            .compound => |*compound| .{ .simple = try self.executeCompoundGlyph(glyph_id, compound, cache) },
        };
    }

    fn executeSimpleGlyph(
        self: *HintMachine,
        glyph_id: u16,
        simple: *const tt_outline.SimpleGlyph,
    ) !tt_vm.HintedSimpleGlyph {
        var context = self.makeContext();
        var funcs = self.prepared.functions;
        context.setFunctions(&funcs);
        context.setZones(&self.zones);

        return self.prepared.size.executeSimpleGlyph(
            &context,
            &self.zones,
            self.glyph_points,
            simple,
            try self.program.glyphPhantomMetrics(glyph_id),
        );
    }

    fn executeCompoundGlyph(
        self: *HintMachine,
        glyph_id: u16,
        compound: *const tt_outline.CompoundGlyph,
        cache: ?*GlyphTopologyCache,
    ) !tt_vm.HintedSimpleGlyph {
        // The topology cache is an AutoHashMap that stores `GlyphTopology`
        // values inline. `appendCompoundGlyph` recurses via `cache.get` for
        // each component, and the resulting `getOrPut` can rehash, moving
        // every value in the map — including the one `compound` points at.
        // Snapshot the slice headers we need *before* the recursion; the
        // backing arrays they reference live in `CompoundGlyph`'s allocator
        // and remain valid even when the hash-map slot moves.
        const components = compound.components;
        const instructions = compound.instructions;

        var builder = CompoundGlyphBuilder.init(
            self.prepared.size.environment(),
            self.glyph_points,
            self.compound_contours,
        );
        try self.appendCompoundGlyph(&builder, components, .{}, .zero, cache);
        const metrics_id = compoundMetricsGlyphId(glyph_id, components);
        const phantom_start = try builder.appendPhantoms(try self.program.glyphPhantomMetrics(metrics_id));

        var context = self.makeContext();
        var funcs = self.prepared.functions;
        context.setFunctions(&funcs);
        context.setZones(&self.zones);
        return self.prepared.size.executeGlyphZone(
            &context,
            &self.zones,
            builder.zone(),
            phantom_start,
            instructions,
        );
    }

    fn appendCompoundGlyph(
        self: *HintMachine,
        builder: *CompoundGlyphBuilder,
        components: []const tt_outline.CompoundComponent,
        transform: tt_outline.ComponentTransform,
        offset: Vec2,
        cache: ?*GlyphTopologyCache,
    ) CompoundBuildError!void {
        for (components) |component| {
            try self.appendCompoundComponent(builder, component, transform, offset, cache);
        }
    }

    fn appendCompoundComponent(
        self: *HintMachine,
        builder: *CompoundGlyphBuilder,
        component: tt_outline.CompoundComponent,
        parent_transform: tt_outline.ComponentTransform,
        parent_offset: Vec2,
        cache: ?*GlyphTopologyCache,
    ) CompoundBuildError!void {
        const point_start = builder.point_count;
        const transform = parent_transform.concat(component.transform);
        const offset = componentOffset(parent_transform, parent_offset, component);
        try self.appendComponentTopology(builder, component.glyph_id, transform, offset, cache);
        if (component.args_are_xy) {
            if (component.roundXYToGrid()) builder.roundOffset(point_start, parent_transform.apply(componentRawOffset(component)));
            return;
        }
        try builder.alignComponentPoints(try componentPointArg(component.arg1), try componentPointArg(component.arg2), point_start);
    }

    fn appendComponentTopology(
        self: *HintMachine,
        builder: *CompoundGlyphBuilder,
        glyph_id: u16,
        transform: tt_outline.ComponentTransform,
        offset: Vec2,
        cache: ?*GlyphTopologyCache,
    ) CompoundBuildError!void {
        var owned: ?tt_vm.GlyphTopology = null;
        defer if (owned) |*topology| topology.deinit();

        const topology = if (cache) |topology_cache|
            try topology_cache.get(glyph_id)
        else blk: {
            owned = try self.program.loadGlyphTopology(self.allocator, glyph_id);
            break :blk &owned.?;
        };

        return switch (topology.*) {
            .empty => {},
            .simple => |*simple| builder.appendSimple(simple, transform, offset),
            .compound => |*compound| {
                // Same hash-map relocation hazard as in executeCompoundGlyph:
                // snapshot the components slice header before recursing.
                const components = compound.components;
                return self.appendCompoundGlyph(builder, components, transform, offset, cache);
            },
        };
    }

    fn emptyGlyphHint(allocator: Allocator, glyph_id: u16, advance: Vec2) GlyphHint {
        return .{
            .allocator = allocator,
            .glyph_id = glyph_id,
            .advance = advance,
            .bbox = emptyBBox(),
            .curves = &.{},
            .prepared_curves = &.{},
            .curve_bboxes = &.{},
        };
    }

    fn makeGlyphHint(
        self: *const HintMachine,
        allocator: Allocator,
        glyph_id: u16,
        hinted: tt_vm.HintedSimpleGlyph,
    ) !GlyphHint {
        // TT-execution points are in 26.6 fixed-point pixel coordinates at
        // the requested ppem. Scale by 1/64 to land in floating-point pixel
        // space, which is what `placeRun` (and the rest of
        // the snail rendering pipeline) expects: hinted glyphs render
        // through a translate-only transform with no em scaling.
        const px_scale: f32 = 1.0 / 64.0;
        const curves = try hintedCurves(allocator, hinted, px_scale, px_scale);
        errdefer allocator.free(curves);
        const prepared = try curve_tex.prepareGlyphCurvesForDirectEncoding(allocator, curves, .zero);
        errdefer allocator.free(prepared);
        const curve_bboxes = try collectCurveBboxes(allocator, prepared);
        errdefer allocator.free(curve_bboxes);

        return .{
            .allocator = allocator,
            .glyph_id = glyph_id,
            .advance = .{ .x = self.toEmX(hinted.advance_x_26_6), .y = 0 },
            .bbox = bboxForCurves(curve_bboxes),
            .curves = curves,
            .prepared_curves = prepared,
            .curve_bboxes = curve_bboxes,
        };
    }

    fn emptyAdvance(self: *const HintMachine, glyph_id: u16) !Vec2 {
        const phantoms = try self.program.glyphPhantomMetrics(glyph_id);
        const left = @as(i32, phantoms.x_min) - @as(i32, phantoms.left_side_bearing);
        const right = left + @as(i32, phantoms.advance_width);
        const env = self.prepared.size.environment();
        return .{ .x = self.toEmX(env.scaleFUnitsX(right) - env.scaleFUnitsX(left)), .y = 0 };
    }

    fn ppemScaleX(self: *const HintMachine) f32 {
        return 1.0 / @as(f32, @floatFromInt(self.prepared.size.request.ppem_x_26_6));
    }

    fn toEmX(self: *const HintMachine, value_26_6: i32) f32 {
        return @as(f32, @floatFromInt(value_26_6)) * self.ppemScaleX();
    }
};

fn allocateMachine(allocator: Allocator, program: *const Program) !HintMachine {
    const sizes = program.executionBufferSizes();

    const stack = try allocator.alloc(i32, sizes.stack);
    errdefer allocator.free(stack);
    // COW targets; `prepare`/`bind` grow cvt_work to the size's CVT length.
    const storage_work = try allocator.alloc(i32, @max(sizes.storage, 1));
    errdefer allocator.free(storage_work);
    const cvt_work = try allocator.alloc(i32, 0);
    errdefer allocator.free(cvt_work);
    const function_entries_work = try allocator.alloc(tt_exec.Function, @max(sizes.functions, 1));
    errdefer allocator.free(function_entries_work);
    const function_lookup_work = try allocator.alloc(?[]const u8, functionLookupCapacity(sizes.functions));
    errdefer allocator.free(function_lookup_work);
    const twilight_points = try allocator.alloc(tt_exec.Point, @max(sizes.twilight_points, 1));
    errdefer allocator.free(twilight_points);
    const glyph_points = try allocator.alloc(tt_exec.Point, @max(sizes.glyph_points, 1));
    errdefer allocator.free(glyph_points);
    const compound_contours = try allocator.alloc(tt_outline.ContourRange, compoundContourCapacity(program));
    errdefer allocator.free(compound_contours);

    return .{
        .allocator = allocator,
        .program = program,
        .stack = stack,
        .storage_work = storage_work,
        .cvt_work = cvt_work,
        .function_entries_work = function_entries_work,
        .function_lookup_work = function_lookup_work,
        .skip_cache = tt_exec.SkipCache.init(allocator),
        .twilight_points = twilight_points,
        .glyph_points = glyph_points,
        .compound_contours = compound_contours,
        .zones = .{
            .twilight = tt_exec.PointZone.initTwilight(twilight_points),
            .glyph = .{ .points = glyph_points[0..0] },
        },
    };
}

const CompoundGlyphBuilder = struct {
    environment: tt_exec.Environment,
    points: []tt_exec.Point,
    contours: []tt_outline.ContourRange,
    point_count: usize = 0,
    contour_count: usize = 0,

    fn init(
        environment: tt_exec.Environment,
        points: []tt_exec.Point,
        contours: []tt_outline.ContourRange,
    ) CompoundGlyphBuilder {
        return .{
            .environment = environment,
            .points = points,
            .contours = contours,
        };
    }

    fn appendSimple(
        self: *CompoundGlyphBuilder,
        simple: *const tt_outline.SimpleGlyph,
        transform: tt_outline.ComponentTransform,
        offset: Vec2,
    ) !void {
        const point_base = self.point_count;
        try self.appendContours(simple.contours, point_base);
        for (simple.points) |source| try self.appendPoint(source, transform, offset);
    }

    fn appendPhantoms(self: *CompoundGlyphBuilder, metrics: tt_points.PhantomMetrics) !usize {
        if (self.point_count + tt_points.phantom_count > self.points.len) return error.BufferTooSmall;
        const phantom_start = self.point_count;
        const left = @as(i32, metrics.x_min) - @as(i32, metrics.left_side_bearing);
        const right = left + @as(i32, metrics.advance_width);
        const top = @as(i32, metrics.y_max) + metrics.top_side_bearing;
        const bottom = top - metrics.advance_height;
        self.writePhantom(0, self.environment.scaleFUnitsX(left), 0, left, 0);
        self.writePhantom(1, self.environment.scaleFUnitsX(right), 0, right, 0);
        self.writePhantom(2, 0, self.environment.scaleFUnitsY(top), 0, top);
        self.writePhantom(3, 0, self.environment.scaleFUnitsY(bottom), 0, bottom);
        self.point_count += tt_points.phantom_count;
        return phantom_start;
    }

    fn zone(self: *const CompoundGlyphBuilder) tt_exec.PointZone {
        return .{
            .points = self.points[0..self.point_count],
            .contours = self.contours[0..self.contour_count],
        };
    }

    fn alignComponentPoints(
        self: *CompoundGlyphBuilder,
        parent_point: usize,
        component_point: usize,
        component_start: usize,
    ) !void {
        if (parent_point >= component_start) return error.InvalidFont;
        if (component_point < component_start or component_point >= self.point_count) return error.InvalidFont;
        const dx = subWrap(self.points[parent_point].x, self.points[component_point].x);
        const dy = subWrap(self.points[parent_point].y, self.points[component_point].y);
        self.shiftRange(component_start, self.point_count, dx, dy);
    }

    fn roundOffset(self: *CompoundGlyphBuilder, point_start: usize, offset: Vec2) void {
        const dx = round26Dot6(self.scaleX(offset.x)) - self.scaleX(offset.x);
        const dy = round26Dot6(self.scaleY(offset.y)) - self.scaleY(offset.y);
        self.shiftRange(point_start, self.point_count, dx, dy);
    }

    fn appendContours(self: *CompoundGlyphBuilder, contours: []const tt_outline.ContourRange, point_base: usize) !void {
        if (self.contour_count + contours.len > self.contours.len) return error.BufferTooSmall;
        const base: u32 = @intCast(point_base);
        for (contours) |contour| {
            self.contours[self.contour_count] = .{
                .start = base + contour.start,
                .end = base + contour.end,
            };
            self.contour_count += 1;
        }
    }

    fn appendPoint(
        self: *CompoundGlyphBuilder,
        source: tt_outline.Point,
        transform: tt_outline.ComponentTransform,
        offset: Vec2,
    ) !void {
        if (self.point_count >= self.points.len) return error.BufferTooSmall;
        const raw = Vec2.add(transform.apply(.{
            .x = @floatFromInt(source.x),
            .y = @floatFromInt(source.y),
        }), offset);
        self.points[self.point_count] = self.makePoint(raw, source.on_curve);
        self.point_count += 1;
    }

    fn makePoint(self: *const CompoundGlyphBuilder, raw: Vec2, on_curve: bool) tt_exec.Point {
        const x = self.scaleX(raw.x);
        const y = self.scaleY(raw.y);
        return .{
            .x = x,
            .y = y,
            .ox = x,
            .oy = y,
            .orus_x = @intFromFloat(@round(raw.x)),
            .orus_y = @intFromFloat(@round(raw.y)),
            .on_curve = on_curve,
        };
    }

    fn writePhantom(self: *CompoundGlyphBuilder, index: usize, x: i32, y: i32, orus_x: i32, orus_y: i32) void {
        const point_index = self.point_count + index;
        self.points[point_index] = .{
            .x = x,
            .y = y,
            .ox = x,
            .oy = y,
            .orus_x = orus_x,
            .orus_y = orus_y,
            .on_curve = true,
        };
    }

    fn shiftRange(self: *CompoundGlyphBuilder, start: usize, end: usize, dx: i32, dy: i32) void {
        // shift only the scaled (cur/orig) coords; orus stays unscaled and is
        // unaffected by component-offset rounding which is a pixel-space concern.
        for (self.points[start..end]) |*p| {
            p.x = addWrap(p.x, dx);
            p.y = addWrap(p.y, dy);
            p.ox = addWrap(p.ox, dx);
            p.oy = addWrap(p.oy, dy);
        }
    }

    fn scaleX(self: *const CompoundGlyphBuilder, value: f32) i32 {
        return scaleFUnitFloat(value, self.environment.ppem_x_26_6, self.environment.units_per_em);
    }

    fn scaleY(self: *const CompoundGlyphBuilder, value: f32) i32 {
        return scaleFUnitFloat(value, self.environment.ppem_y_26_6, self.environment.units_per_em);
    }
};

fn componentOffset(
    parent_transform: tt_outline.ComponentTransform,
    parent_offset: Vec2,
    component: tt_outline.CompoundComponent,
) Vec2 {
    if (!component.args_are_xy) return parent_offset;
    return Vec2.add(parent_offset, parent_transform.apply(componentRawOffset(component)));
}

fn componentRawOffset(component: tt_outline.CompoundComponent) Vec2 {
    return .{
        .x = @floatFromInt(component.arg1),
        .y = @floatFromInt(component.arg2),
    };
}

fn componentPointArg(value: i16) !usize {
    if (value < 0) return error.InvalidFont;
    return @intCast(value);
}

fn compoundMetricsGlyphId(glyph_id: u16, components: []const tt_outline.CompoundComponent) u16 {
    for (components) |component| {
        if (component.useMyMetrics()) return component.glyph_id;
    }
    return glyph_id;
}

fn compoundContourCapacity(program: *const Program) usize {
    return @max(
        @as(usize, program.maxp.max_composite_contours),
        @as(usize, program.maxp.max_contours),
        1,
    );
}

fn functionLookupCapacity(function_count: usize) usize {
    return @max(function_count, 256);
}

fn scaleFUnitFloat(value: f32, ppem_26_6: u32, units_per_em: u16) i32 {
    if (units_per_em == 0) return 0;
    const scaled = @as(f64, @floatCast(value)) *
        @as(f64, @floatFromInt(ppem_26_6)) /
        @as(f64, @floatFromInt(units_per_em));
    return @intFromFloat(@round(scaled));
}

fn round26Dot6(value: i32) i32 {
    if (value >= 0) return @intCast(@divTrunc(@as(i64, value) + 32, 64) * 64);
    return @intCast(-@divTrunc(@as(i64, -value) + 32, 64) * 64);
}

const addWrap = tt_graphics.addWrap;
const subWrap = tt_graphics.subWrap;

fn hintedCurves(allocator: Allocator, hinted: tt_vm.HintedSimpleGlyph, scale_x: f32, scale_y: f32) ![]CurveSegment {
    const quads = try hinted.curvesXY(allocator, scale_x, scale_y);
    defer if (quads.len > 0) allocator.free(quads);
    return quadCurvesToSegments(allocator, quads);
}

fn quadCurvesToSegments(allocator: Allocator, quads: []const QuadBezier) ![]CurveSegment {
    const curves = try allocator.alloc(CurveSegment, quads.len);
    errdefer allocator.free(curves);
    for (quads, curves) |quad, *out| out.* = CurveSegment.fromQuad(quad);
    return curves;
}

fn collectCurveBboxes(allocator: Allocator, curves: []const CurveSegment) ![]BBox {
    const bboxes = try allocator.alloc(BBox, curves.len);
    errdefer allocator.free(bboxes);
    for (curves, bboxes) |curve, *bbox| bbox.* = curve.boundingBox();
    return bboxes;
}

fn bboxForCurves(bboxes: []const BBox) BBox {
    if (bboxes.len == 0) return emptyBBox();
    var bbox = bboxes[0];
    for (bboxes[1..]) |next| bbox = bbox.merge(next);
    return bbox;
}

fn emptyBBox() BBox {
    return .{ .min = Vec2.zero, .max = Vec2.zero };
}

test "hint machine keeps Noto Sans C shoulder in place" {
    const assets = @import("assets");
    const font_mod = @import("../ttf.zig");
    const allocator = std.testing.allocator;

    const program = try Program.init(assets.noto_sans_regular);
    const font = try font_mod.Font.init(assets.noto_sans_regular);
    var machine = try HintMachine.initForProgram(allocator, &program);
    defer machine.deinit();
    var prepared = try machine.prepare(allocator, HintPpem.uniform(26 * 64), .{});
    defer prepared.deinit();
    var cache = GlyphTopologyCache.initForProgram(allocator, &program);
    defer cache.deinit();

    const glyph_id = try font.glyphIndex('C');
    const executed = try machine.executeCachedGlyph(&prepared, &cache, glyph_id);
    switch (executed) {
        .simple => |simple| {
            try std.testing.expect(simple.phantom_start > 24);
            const shoulder = simple.zone.points[24];
            try std.testing.expect(shoulder.y > 900);
            try std.testing.expect(shoulder.y < 990);
            try std.testing.expect(shoulder.touched_y);
        },
        else => return error.TestExpectedGlyph,
    }
}

test "hint machine flattens compound glyphs" {
    const assets = @import("assets");
    const font_mod = @import("../ttf.zig");
    const allocator = std.testing.allocator;
    const samples = [_]u32{ 0x00C0, 0x00C1, 0x00C5, 0x00E9, 0x00F1, 0x00FC };

    const program = try Program.init(assets.noto_sans_regular);
    const font = try font_mod.Font.init(assets.noto_sans_regular);
    var machine = try HintMachine.initForProgram(allocator, &program);
    defer machine.deinit();
    var prepared = try machine.prepare(allocator, HintPpem.uniform(12 * 64), .{});
    defer prepared.deinit();

    for (samples) |codepoint| {
        const glyph_id = try font.glyphIndex(codepoint);
        if (glyph_id == 0) continue;

        var topology = try program.loadGlyphTopology(allocator, glyph_id);
        defer topology.deinit();
        switch (topology) {
            .compound => {},
            else => continue,
        }

        var hint = try machine.hintGlyph(allocator, &prepared, glyph_id);
        defer hint.deinit();
        try std.testing.expect(hint.advance.x > 0);
        try std.testing.expect(hint.curves.len > 0);
        return;
    }

    return error.SkipZigTest;
}

const lowlevel_mod = @import("../lowlevel.zig");
const scene_mod = @import("../scene.zig");
const vertex_mod = @import("../renderer/vertex.zig");
const vec = @import("../math/vec.zig");

const PathDraw = scene_mod.PathDraw;
const Transform2D = vec.Transform2D;
const textureLayerLocal = lowlevel_mod.textureLayerLocal;
const textureLayerWindowBase = lowlevel_mod.textureLayerWindowBase;

pub const PATH_WORDS_PER_VERTEX = vertex_mod.WORDS_PER_VERTEX;
pub const PATH_VERTICES_PER_SHAPE = vertex_mod.VERTICES_PER_GLYPH;
pub const PATH_WORDS_PER_SHAPE = PATH_WORDS_PER_VERTEX * PATH_VERTICES_PER_SHAPE;

pub const PathBatch = struct {
    buf: []u32,
    len: usize = 0,
    layer_window_base: ?u32 = null,

    pub fn init(buf: []u32) PathBatch {
        return .{ .buf = buf };
    }

    pub fn reset(self: *PathBatch) void {
        self.len = 0;
        self.layer_window_base = null;
    }

    pub fn shapeCount(self: *const PathBatch) usize {
        return self.len / PATH_WORDS_PER_SHAPE;
    }

    pub fn slice(self: *const PathBatch) []const u32 {
        return self.buf[0..self.len];
    }

    pub const AppendResult = struct {
        emitted: usize,
        next_shape: usize,
        completed: bool,
        layer_window_base: u32,
    };

    pub fn currentLayerWindowBase(self: *const PathBatch) u32 {
        return self.layer_window_base orelse 0;
    }

    fn localLayer(self: *PathBatch, atlas_layer: u32) !u8 {
        const base = textureLayerWindowBase(atlas_layer);
        if (self.layer_window_base) |expected| {
            if (base != expected) return error.TextureLayerWindowChanged;
        } else {
            self.layer_window_base = base;
        }
        return textureLayerLocal(atlas_layer);
    }

    /// Emit one slice of a `PathDraw` into this batch: the shapes from
    /// `[shape_start, draw.shapes.end)` under `draw.instances[override_index]`.
    /// Returns where to resume; the caller is responsible for advancing
    /// across overrides and re-opening batches when full or when the
    /// texture layer window changes.
    pub fn addDraw(
        self: *PathBatch,
        atlas_like: anytype,
        draw: PathDraw,
        override_index: usize,
        shape_start: usize,
    ) !AppendResult {
        const resolved_view = lowlevel_mod.coerceAtlasHandle(atlas_like);
        const view = &resolved_view;
        const range = draw.shapes.resolve(draw.picture.shapes.len);
        const start = @max(shape_start, range.start);
        if (start > range.end) return error.InvalidShapeRange;
        if (override_index >= draw.instances.len) return error.InvalidOverrideIndex;
        const override = draw.instances[override_index];
        var count: usize = 0;
        var idx = start;
        while (idx < range.end) : (idx += 1) {
            const shape = draw.picture.shapes[idx];
            const layer_base = view.glyphLayerWindowBase(shape.page_index);
            if (self.layer_window_base) |base| {
                if (base != layer_base) break;
            } else {
                self.layer_window_base = layer_base;
            }
            if (self.len + PATH_WORDS_PER_SHAPE > self.buf.len) return error.DrawListFull;
            const final_transform = Transform2D.multiply(override.transform, shape.transform);
            const info_loc = view.layerInfoLoc(shape.info_x, shape.info_y);
            const local_layer = try self.localLayer(view.glyphLayer(shape.page_index));
            if (!vertex_mod.generatePathRecordVerticesTransformedTinted(
                self.buf[self.len..],
                shape.bbox,
                info_loc.x,
                info_loc.y,
                shape.layer_count,
                .{ 1, 1, 1, 1 },
                override.tint,
                local_layer,
                final_transform,
            )) return error.InvalidTransform;
            self.len += PATH_WORDS_PER_SHAPE;
            count += 1;
        }
        return .{
            .emitted = count,
            .next_shape = idx,
            .completed = idx >= range.end,
            .layer_window_base = self.currentLayerWindowBase(),
        };
    }
};

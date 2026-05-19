const instance_emit = @import("../render/format/instance_emit.zig");
const resources_view = @import("../resources/view.zig");
const scene_mod = @import("../scene.zig");
const vec = @import("../math/vec.zig");

const PathDraw = scene_mod.PathDraw;
const Transform2D = vec.Transform2D;

pub const PATH_WORDS_PER_VERTEX = instance_emit.WORDS_PER_VERTEX;
pub const PATH_VERTICES_PER_SHAPE = instance_emit.VERTICES_PER_GLYPH;
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

    fn cursor(self: *PathBatch) instance_emit.Cursor {
        return .{
            .buf = self.buf,
            .len = &self.len,
            .layer_window_base = &self.layer_window_base,
        };
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
        const resolved_view = resources_view.coerceAtlasHandle(atlas_like);
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
            const final_transform = Transform2D.multiply(override.transform, shape.transform);
            const info_loc = view.layerInfoLoc(shape.info_x, shape.info_y);
            try self.cursor().appendPathRecordTransformedTinted(
                shape.bbox,
                info_loc.x,
                info_loc.y,
                shape.layer_count,
                .{ 1, 1, 1, 1 },
                override.tint,
                view.glyphLayer(shape.page_index),
                final_transform,
            );
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

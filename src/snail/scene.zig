const std = @import("std");
const draw_mod = @import("draw.zig");
const path_mod = @import("path.zig");
const resource_key_mod = @import("resource_key.zig");
const text_mod = @import("text.zig");
const vec = @import("math/vec.zig");

const Transform2D = vec.Transform2D;
const PathPicture = path_mod.PathPicture;
const ResourceKey = resource_key_mod.ResourceKey;
pub const TextResourceKeys = resource_key_mod.TextResourceKeys;
const TextBlob = text_mod.TextBlob;


/// Per-instance override applied at submission time. `transform` composes
/// onto the resource's baked transform; `tint` multiplies onto its baked
/// color.
pub const Override = struct {
    transform: Transform2D = .identity,
    tint: [4]f32 = .{ 1, 1, 1, 1 },
};

const identity_overrides = [_]Override{.{}};

/// A draw of a `PathPicture` with one GPU instance per entry in
/// `instances`. The default is a single identity instance. `Scene`
/// borrows `instances`; the slice must outlive any scene that holds it
/// (same lifetime contract as `picture`). The whole picture is drawn —
/// for sub-selection, compose a smaller `PathPicture` at build time.
pub const PathDraw = struct {
    picture: *const PathPicture,
    resource_key: ResourceKey,
    instances: []const Override = &identity_overrides,
};

/// A draw of a `TextBlob`: see `PathDraw` for the instance/lifetime
/// model. The whole blob is drawn — for sub-selection, compose smaller
/// blobs into the same `TextBlobBundle` (cheap; the bundle amortises
/// allocation across them).
pub const TextDraw = struct {
    blob: *const TextBlob,
    resources: TextResourceKeys,
    instances: []const Override = &identity_overrides,
};

pub const Scene = struct {
    allocator: std.mem.Allocator,
    /// Borrowed command list. Each command borrows its `TextBlob` /
    /// `PathPicture` and the `instances` slice handed to `addText` /
    /// `addPath`; all three must outlive the Scene (or at least live until
    /// the next `reset`).
    commands: std.ArrayListUnmanaged(Command) = .empty,

    pub const Command = union(enum) {
        text: TextDraw,
        path: PathDraw,
    };

    pub fn init(allocator: std.mem.Allocator) Scene {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Scene) void {
        self.commands.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *Scene) void {
        self.commands.clearRetainingCapacity();
    }

    pub fn commandCount(self: *const Scene) usize {
        return self.commands.items.len;
    }

    pub fn addPath(self: *Scene, draw: PathDraw) !void {
        try self.commands.append(self.allocator, .{ .path = draw });
    }

    pub fn addText(self: *Scene, draw: TextDraw) !void {
        try self.commands.append(self.allocator, .{ .text = draw });
    }
};

pub const PreparedScene = draw_mod.PreparedScene;

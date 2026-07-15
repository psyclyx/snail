//! Backend-agnostic scene for the game demo.
//!
//! Owns the shared `Fonts` and the snail `PreparedPass`es for every element,
//! plus the world transforms + orbit camera + light. The driver computes
//! `view_proj` from the camera each frame and renders:
//!
//!   1. the **material quad** — an opaque lit surface whose custom fragment
//!      shader samples the `material` pass's glyph coverage at arbitrary UVs
//!      (the "custom shader" showcase). Writes depth, so it occludes …
//!   2. the **occluded label** — a snail-pipeline world label on a plane
//!      *behind* the material quad, drawn depth-tested so the quad hides the
//!      part it overlaps (the depth showcase).
//!   3. the **translucent panel** — a snail-pipeline rounded panel + text in
//!      front, blended in painter's order (depth-test on, depth-write off).
//!   4. the **HUD** — screen-space snail text incl. a live renderer+perf line.

const std = @import("std");
const snail = @import("snail");
const common = @import("common.zig");
const passes = @import("passes.zig");

const Fonts = passes.Fonts;
const PassBuilder = passes.PassBuilder;
const PreparedPass = passes.PreparedPass;
const Vec3 = common.Vec3;

/// Coordinate space the material-quad text is authored in; the material shader
/// maps quad UV [0,1]² onto [0,scene_w] × [0,scene_h].
pub const material_scene_w: f32 = 560.0;
pub const material_scene_h: f32 = 300.0;

pub const OrbitCamera = struct {
    // Default: a near face-on framing (sign occludes the label behind it),
    // static until `R` starts the orbit.
    angle: f32 = 0.16,
    radius: f32 = 6.2,
    height: f32 = 1.75,
    target: Vec3 = .{ .x = 0.0, .y = 1.45, .z = 0.0 },
    spinning: bool = false,

    pub fn update(self: *OrbitCamera, dt: f32) void {
        if (self.spinning) self.angle += dt * 0.28;
    }

    pub fn camera(self: OrbitCamera) common.Camera {
        const px = self.target.x + self.radius * @sin(self.angle);
        const pz = self.target.z + self.radius * @cos(self.angle);
        const py = self.height;
        const dx = self.target.x - px;
        const dz = self.target.z - pz;
        const horiz = @sqrt(dx * dx + dz * dz);
        return .{
            .pos = .{ .x = px, .y = py, .z = pz },
            .yaw = std.math.atan2(-dx, -dz),
            .pitch = std.math.atan2(self.target.y - py, horiz),
        };
    }
};

/// A snail picture authored in `scene_w × scene_h` pixel space, placed onto a
/// `world_w × world_h` quad in the world. `mvp = planeMvp(view_proj, …)`.
pub const Plane = struct {
    scene_w: f32,
    scene_h: f32,
    pos: Vec3,
    rot_x: f32 = 0.0,
    rot_y: f32 = 0.0,
    world_w: f32,
    world_h: f32,
    depth_bias: f32 = 0.0,

    pub fn mvp(self: Plane, view_proj: snail.Mat4) snail.Mat4 {
        return common.planeMvp(view_proj, self.scene_w, self.scene_h, self.pos, self.rot_x, self.rot_y, self.world_w, self.world_h, self.depth_bias);
    }
};

pub const Scene = struct {
    allocator: std.mem.Allocator,
    fonts: *Fonts,

    material: PreparedPass,
    label: PreparedPass,
    panel: PreparedPass,
    hud: PreparedPass,

    // material quad is raw geometry (model matrix; UV-based coverage sampling).
    material_model: snail.Mat4,
    // label + panel are snail pictures placed onto world planes.
    label_plane: Plane,
    panel_plane: Plane,

    cam: OrbitCamera = .{},
    light_pos: Vec3 = .{ .x = 2.6, .y = 3.4, .z = 3.2 },
    light_color: [3]f32 = .{ 1.35, 1.2, 0.98 },

    // Last window size the HUD was laid out for, so we rebuild on resize.
    hud_w: u32 = 0,
    hud_h: u32 = 0,
    /// Bumped whenever the HUD pass is rebuilt so drivers know to re-upload.
    hud_gen: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, fonts: *Fonts, window_w: u32, window_h: u32) !Scene {
        var material = try buildMaterialText(allocator, fonts);
        errdefer material.deinit();
        var label = try buildLabel(allocator, fonts);
        errdefer label.deinit();
        var panel = try buildPanel(allocator, fonts);
        errdefer panel.deinit();
        var hud = try buildHud(allocator, fonts, window_w, "renderer …", "");
        errdefer hud.deinit();

        // material quad: a wide opaque sign centered a touch above the target.
        const material_model = common.composeModel(.{ .x = 0.0, .y = 1.55, .z = 0.0 }, 0.0, 0.0, .{ .x = 3.4, .y = 1.82, .z = 1.0 });
        // label plane: centered *behind* the sign and wider than it, so the
        // opaque quad occludes the middle while the ends peek past both edges.
        const label_plane = Plane{
            .scene_w = label_scene_w,
            .scene_h = label_scene_h,
            .pos = .{ .x = 0.1, .y = 1.55, .z = -1.3 },
            .rot_y = 0.0,
            .world_w = 5.4,
            .world_h = 1.5,
        };
        // translucent panel: floating to the left, angled toward the camera.
        const panel_plane = Plane{
            .scene_w = panel_scene_w,
            .scene_h = panel_scene_h,
            .pos = .{ .x = -2.75, .y = 1.35, .z = 1.5 },
            .rot_y = 0.62,
            .world_w = 2.25,
            .world_h = 1.47,
        };

        return .{
            .allocator = allocator,
            .fonts = fonts,
            .material = material,
            .label = label,
            .panel = panel,
            .hud = hud,
            .material_model = material_model,
            .label_plane = label_plane,
            .panel_plane = panel_plane,
            .hud_w = window_w,
            .hud_h = window_h,
        };
    }

    pub fn deinit(self: *Scene) void {
        self.hud.deinit();
        self.panel.deinit();
        self.label.deinit();
        self.material.deinit();
        self.* = undefined;
    }

    /// Rebuild the HUD pass with a fresh renderer name + perf line. Returns
    /// true (so the driver re-uploads); cheap enough to call on a ~2 Hz cadence.
    pub fn rebuildHud(self: *Scene, window_w: u32, backend: []const u8, perf: []const u8) !void {
        var next = try buildHud(self.allocator, self.fonts, window_w, backend, perf);
        errdefer next.deinit();
        self.hud.deinit();
        self.hud = next;
        self.hud_w = window_w;
        self.hud_gen +%= 1;
    }

    pub fn viewProj(self: *const Scene, aspect: f32) snail.Mat4 {
        return common.buildViewProjection(self.cam.camera(), aspect);
    }
};

// ── Content builders ──

fn buildMaterialText(allocator: std.mem.Allocator, fonts: *Fonts) !PreparedPass {
    var b = PassBuilder.init(allocator, fonts);
    defer b.deinit();
    // Authored in the material scene frame (material_scene_w × material_scene_h).
    _ = try b.appendText(.{ .weight = .bold }, "SNAIL", 40.0, 150.0, 130.0, .{ 1, 1, 1, 1 });
    _ = try b.appendText(.{}, "coverage sampled in a custom material shader", 42.0, 205.0, 24.0, .{ 1, 1, 1, 1 });
    _ = try b.appendText(.{}, "same words, four backends", 42.0, 240.0, 21.0, .{ 1, 1, 1, 1 });
    return b.freeze(fonts.pool);
}

fn buildLabel(allocator: std.mem.Allocator, fonts: *Fonts) !PreparedPass {
    // Authored in the label_scene frame; spans wide so the sign in front cuts
    // through the middle of the word (the occlusion showcase).
    var b = PassBuilder.init(allocator, fonts);
    defer b.deinit();
    _ = try b.appendText(.{ .weight = .bold }, "DEPTH  TESTED", 24.0, 110.0, 86.0, .{ 0.62, 0.86, 1.0, 1.0 });
    _ = try b.appendText(.{}, "world text occluded by the opaque sign in front", 26.0, 158.0, 22.0, .{ 0.5, 0.72, 0.9, 1.0 });
    return b.freeze(fonts.pool);
}

/// Label text is authored in this frame; the plane maps it onto the world quad.
/// Aspect matches the label plane's world aspect (5.4/1.5) so text isn't stretched.
pub const label_scene_w: f32 = 720.0;
pub const label_scene_h: f32 = 200.0;

fn buildPanel(allocator: std.mem.Allocator, fonts: *Fonts) !PreparedPass {
    // Authored in a 460×300 frame.
    const w: f32 = 460.0;
    var b = PassBuilder.init(allocator, fonts);
    defer b.deinit();
    const rect = snail.Rect{ .x = 16.0, .y = 16.0, .w = w - 32.0, .h = 268.0 };
    try b.addRoundedRectWithInsideStroke(
        rect,
        .{ .solid = .{ 0.30, 0.60, 0.95, 0.34 } },
        .{ .paint = .{ .solid = .{ 0.70, 0.90, 1.0, 0.60 } }, .width = 2.5, .placement = .inside },
        22.0,
    );
    _ = try b.appendText(.{ .weight = .bold }, "TRANSLUCENT", 40.0, 84.0, 40.0, .{ 0.95, 0.99, 1.0, 0.85 });
    _ = try b.appendText(.{}, "snail's own pipeline,", 40.0, 128.0, 24.0, .{ 0.86, 0.94, 1.0, 0.8 });
    _ = try b.appendText(.{}, "drawn in painter's order", 40.0, 158.0, 24.0, .{ 0.86, 0.94, 1.0, 0.8 });
    _ = try b.appendText(.{}, "with depth-write off.", 40.0, 188.0, 24.0, .{ 0.86, 0.94, 1.0, 0.8 });
    return b.freeze(fonts.pool);
}

pub const panel_scene_w: f32 = 460.0;
pub const panel_scene_h: f32 = 300.0;

fn buildHud(allocator: std.mem.Allocator, fonts: *Fonts, window_w: u32, backend: []const u8, perf: []const u8) !PreparedPass {
    _ = window_w;
    var b = PassBuilder.init(allocator, fonts);
    defer b.deinit();
    const x = 30.0;
    _ = try b.appendText(.{ .weight = .bold }, backend, x, 48.0, 26.0, .{ 0.55, 0.9, 1.0, 1.0 });
    if (perf.len > 0)
        _ = try b.appendText(.{}, perf, x, 76.0, 17.0, .{ 0.86, 0.92, 0.98, 1.0 });
    _ = try b.appendText(.{}, "C cycle backend   R toggle spin   Esc quit", x, 100.0, 15.0, .{ 0.7, 0.78, 0.88, 1.0 });
    return b.freeze(fonts.pool);
}

//! Cross-backend driver for the game demo. Like `renderer_driver.zig` (the 2D
//! demo), a tagged union lets `game.zig` cycle backends with `C`, but this one
//! drives a 3D scene: it renders the custom-material coverage quad, the
//! depth-tested occluded label, the translucent world panel, and the HUD — all
//! in one pass on a shared `wayland.Window` with an opt-in depth buffer.
//!
//! The GL family (gl33/gl44/gles30) shares one generic implementation
//! (`GlDriver`); Vulkan is its own arm (added in a later stage). The scene is
//! backend-agnostic and owned by `game.zig`, so it survives backend switches;
//! each driver uploads its own GPU resources from it.

const std = @import("std");
const snail = @import("snail");
const build_options = @import("build_options");
const wayland = @import("platform/wayland.zig");
const presentation = @import("platform/presentation.zig");
const scene_mod = @import("game/scene.zig");
const gl_material = @import("game/gl_material.zig");
const gl_scene = @import("game/gl_scene.zig");

const Scene = scene_mod.Scene;

const any_gl = build_options.enable_gl33 or build_options.enable_gl44 or build_options.enable_gles30;
const gl_platform = if (any_gl) @import("platform/gl.zig") else struct {};
const desktop_gl = if (build_options.enable_gl33 or build_options.enable_gl44) @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
}) else struct {};
const gles_gl = if (build_options.enable_gles30) @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GLES3/gl3.h");
    @cInclude("GLES2/gl2ext.h");
}) else struct {};

const game_vulkan = build_options.enable_vulkan;
const vulkan_platform = if (game_vulkan) @import("platform/vulkan/windowed.zig") else struct {};
const vk_scene = if (game_vulkan) @import("game/vk_scene.zig") else struct {};
const embed_vulkan = if (game_vulkan) @import("embed_vulkan") else struct {};

/// Default-framebuffer depth bits the scene's depth testing needs.
const DEPTH_BITS: i32 = 24;

pub const Kind = enum { vulkan, gl44, gl33, gles30 };

pub fn defaultKind() Kind {
    if (comptime build_options.enable_gl44) return .gl44;
    if (comptime build_options.enable_gl33) return .gl33;
    if (comptime build_options.enable_gles30) return .gles30;
    if (comptime game_vulkan) return .vulkan;
    @compileError("at least one game backend must be enabled");
}

fn kindEnabled(k: Kind) bool {
    return switch (k) {
        .vulkan => game_vulkan,
        .gl44 => build_options.enable_gl44,
        .gl33 => build_options.enable_gl33,
        .gles30 => build_options.enable_gles30,
    };
}

pub fn nextKind(current: Kind) Kind {
    const order = [_]Kind{ .gl44, .gl33, .gles30, .vulkan };
    var seen = false;
    for (0..order.len * 2) |i| {
        const k = order[i % order.len];
        if (seen and kindEnabled(k)) return k;
        if (k == current) seen = true;
    }
    return current;
}

/// Map a backend name (e.g. from `SNAIL_GAME_BACKEND`) to a Kind, if enabled.
pub fn kindFromName(name: []const u8) ?Kind {
    const table = [_]struct { n: []const u8, k: Kind }{
        .{ .n = "gl44", .k = .gl44 },
        .{ .n = "gl33", .k = .gl33 },
        .{ .n = "gles30", .k = .gles30 },
        .{ .n = "vulkan", .k = .vulkan },
    };
    for (table) |e| {
        if (std.mem.eql(u8, name, e.n) and kindEnabled(e.k)) return e.k;
    }
    return null;
}

pub fn label(kind: Kind) [:0]const u8 {
    return switch (kind) {
        .vulkan => "Vulkan",
        .gl44 => "OpenGL 4.4",
        .gl33 => "OpenGL 3.3",
        .gles30 => "OpenGL ES 3.0",
    };
}

fn toSnailEncoding(encoding: presentation.ColorEncoding) @import("snail-raster").ColorEncoding {
    return switch (encoding) {
        .linear => .linear,
        .srgb => .srgb,
    };
}

fn displayTargetEncoding(info: presentation.Info) @import("snail-raster").TargetEncoding {
    return .{ .attachment = toSnailEncoding(info.framebuffer_encoding), .stored_pixels = .srgb };
}

// ── Union ────────────────────────────────────────────────────────────────────

pub const Driver = union(Kind) {
    vulkan: if (game_vulkan) VulkanGameDriver else void,
    gl44: if (build_options.enable_gl44) GlDriver(.gl44) else void,
    gl33: if (build_options.enable_gl33) GlDriver(.gl33) else void,
    gles30: if (build_options.enable_gles30) GlDriver(.gles30) else void,

    pub fn init(allocator: std.mem.Allocator, window: *wayland.Window, scene: *Scene, selected: Kind) !Driver {
        return switch (selected) {
            .gl44 => if (comptime build_options.enable_gl44) .{ .gl44 = try GlDriver(.gl44).init(allocator, window, scene) } else unreachable,
            .gl33 => if (comptime build_options.enable_gl33) .{ .gl33 = try GlDriver(.gl33).init(allocator, window, scene) } else unreachable,
            .gles30 => if (comptime build_options.enable_gles30) .{ .gles30 = try GlDriver(.gles30).init(allocator, window, scene) } else unreachable,
            .vulkan => if (comptime game_vulkan) .{ .vulkan = try VulkanGameDriver.init(allocator, window, scene) } else unreachable,
        };
    }

    pub fn deinit(self: *Driver) void {
        switch (self.*) {
            .gl44 => |*d| if (comptime build_options.enable_gl44) d.deinit() else unreachable,
            .gl33 => |*d| if (comptime build_options.enable_gl33) d.deinit() else unreachable,
            .gles30 => |*d| if (comptime build_options.enable_gles30) d.deinit() else unreachable,
            .vulkan => |*d| if (comptime game_vulkan) d.deinit() else unreachable,
        }
    }

    pub fn kind(self: *const Driver) Kind {
        return std.meta.activeTag(self.*);
    }

    pub fn backendName(self: *const Driver) [:0]const u8 {
        return label(self.kind());
    }

    /// The GL family re-uploads the HUD atlas each rebuild (live perf line). The
    /// Vulkan cache uploads atlases once, so its HUD is static after init — the
    /// loop shouldn't rebuild it mid-session (it would emit against a stale
    /// binding). It's refreshed on backend switch instead.
    pub fn wantsHudRebuild(self: *const Driver) bool {
        return self.kind() != .vulkan;
    }

    pub fn shouldClose(self: *Driver) bool {
        return switch (self.*) {
            .gl44, .gl33, .gles30 => if (comptime any_gl) gl_platform.shouldClose() else true,
            .vulkan => if (comptime game_vulkan) self.vulkan.shouldClose() else true,
        };
    }

    pub fn presentationInfo(self: *Driver) presentation.Info {
        return switch (self.*) {
            .gl44, .gl33, .gles30 => if (comptime any_gl) gl_platform.presentationInfo() else .{},
            .vulkan => if (comptime game_vulkan) self.vulkan.presentationInfo() else .{},
        };
    }

    /// Render the whole scene.
    pub fn renderFrame(self: *Driver, scene: *Scene) !void {
        switch (self.*) {
            .gl44 => |*d| if (comptime build_options.enable_gl44) try d.renderFrame(scene) else unreachable,
            .gl33 => |*d| if (comptime build_options.enable_gl33) try d.renderFrame(scene) else unreachable,
            .gles30 => |*d| if (comptime build_options.enable_gles30) try d.renderFrame(scene) else unreachable,
            .vulkan => |*d| if (comptime game_vulkan) try d.renderFrame(scene) else unreachable,
        }
    }
};

// ── GL family ────────────────────────────────────────────────────────────────

/// Thin windowed shell around the shared `GlSceneRenderer`: owns the EGL/GL
/// platform on the wayland window (with a depth buffer) and drives one frame.
fn GlDriver(comptime variant: gl_material.Variant) type {
    return struct {
        const Self = @This();
        const api: gl_platform.GlApi = switch (variant) {
            .gl44 => .gl44,
            .gl33 => .gl33,
            .gles30 => .gles30,
        };
        const gl = switch (variant) {
            .gles30 => gles_gl,
            else => desktop_gl,
        };
        const SceneRenderer = gl_scene.GlSceneRenderer(variant);

        sr: SceneRenderer,

        fn init(allocator: std.mem.Allocator, window: *wayland.Window, scene: *Scene) !Self {
            try gl_platform.initForWindow(window, api, DEPTH_BITS);
            errdefer gl_platform.deinit();
            return .{ .sr = try SceneRenderer.init(allocator, scene) };
        }

        fn deinit(self: *Self) void {
            self.sr.deinit();
            gl_platform.deinit();
            self.* = undefined;
        }

        fn shouldClose(_: *Self) bool {
            return gl_platform.shouldClose();
        }

        fn presentationInfo(_: *Self) presentation.Info {
            return gl_platform.presentationInfo();
        }

        fn renderFrame(self: *Self, scene: *Scene) !void {
            const present = gl_platform.presentationInfo();
            const fb = present.framebuffer_size;
            const logical = present.logical_size;
            if (fb[0] == 0 or fb[1] == 0) return;
            const fb_w: f32 = @floatFromInt(fb[0]);
            const fb_h: f32 = @floatFromInt(fb[1]);
            const target_encoding = displayTargetEncoding(present);
            const view_proj = scene.viewProj(fb_w / fb_h);

            gl.glViewport(0, 0, @intCast(fb[0]), @intCast(fb[1]));
            gl.glDepthMask(gl.GL_TRUE);
            // Clear in linear; the sRGB target encodes on store (snail enables
            // GL_FRAMEBUFFER_SRGB), so pass linear to land on the sRGB bg.
            gl.glClearColor(srgbToLinear(0.035), srgbToLinear(0.045), srgbToLinear(0.065), 1.0);
            gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);

            const surface = @import("snail-raster").TargetSurface{ .pixel_width = fb_w, .pixel_height = fb_h, .encoding = target_encoding };
            try self.sr.draw(scene, logical[0], logical[1], view_proj, surface);
            gl_platform.swapBuffers();
        }
    };
}

// ── Vulkan (added in a later stage) ──────────────────────────────────────────

const VulkanGameDriver = if (game_vulkan) struct {
    const Self = @This();
    ctx: embed_vulkan.VulkanContext,
    sr: vk_scene.VkSceneRenderer,

    fn init(allocator: std.mem.Allocator, window: *wayland.Window, scene: *Scene) !Self {
        const ctx = try vulkan_platform.initForWindow(window, true);
        errdefer vulkan_platform.deinit();
        const sr = try vk_scene.VkSceneRenderer.init(allocator, ctx, scene, vulkan_platform.MAX_FRAMES_IN_FLIGHT);
        return .{ .ctx = ctx, .sr = sr };
    }

    fn deinit(self: *Self) void {
        self.sr.deinit();
        vulkan_platform.deinit();
    }

    fn shouldClose(_: *Self) bool {
        return vulkan_platform.shouldClose();
    }

    fn presentationInfo(_: *Self) presentation.Info {
        return vulkan_platform.presentationInfo();
    }

    fn renderFrame(self: *Self, scene: *Scene) !void {
        const present = vulkan_platform.presentationInfo();
        const fb = present.framebuffer_size;
        if (fb[0] == 0 or fb[1] == 0) return;
        const fb_w: f32 = @floatFromInt(fb[0]);
        const fb_h: f32 = @floatFromInt(fb[1]);
        // Clear in linear (the sRGB swapchain encodes on store).
        const clear = [4]f32{ srgbToLinear(0.035), srgbToLinear(0.045), srgbToLinear(0.065), 1.0 };
        const platform_cmd = vulkan_platform.beginFrame(clear) orelse return;
        const cmd: vk_scene.vk.VkCommandBuffer = @ptrCast(platform_cmd);
        const view_proj = snail.Mat4.multiply(scene_mod.vulkan_z_fix, scene.viewProj(fb_w / fb_h));
        const surface = @import("snail-raster").TargetSurface{ .pixel_width = fb_w, .pixel_height = fb_h, .encoding = @import("snail-raster").TargetEncoding.srgb };
        try self.sr.record(cmd, vulkan_platform.currentFrameIndex(), scene, view_proj, surface);
        vulkan_platform.endFrame();
    }
} else void;

fn srgbToLinear(v: f32) f32 {
    return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
}

//! GL-family scene renderer: given a *current* GL context (windowed swapchain
//! or an offscreen FBO), draws the whole game scene — the custom-material
//! coverage quad (opaque, depth-writing), the depth-tested occluded label, the
//! translucent world panel, and the screen-space HUD.
//!
//! It owns the snail renderer + cache + material + per-pass bindings but makes
//! no platform calls (no context/present/swap), so both `game_driver`'s
//! windowed driver and the offscreen `game_screenshot` harness reuse it.

const std = @import("std");
const snail = @import("snail");
const embed_gl = @import("embed_gl");
const driver_common = @import("../driver/common.zig");
const scene_mod = @import("scene.zig");
const gl_material = @import("gl_material.zig");
const passes = @import("passes.zig");

const Scene = scene_mod.Scene;
const PreparedPass = passes.PreparedPass;
const desktop_gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
});
const gles_gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GLES3/gl3.h");
    @cInclude("GLES2/gl2ext.h");
});

pub const PassBindings = struct { path: snail.render.records.Binding, text: snail.render.records.Binding };

pub fn GlSceneRenderer(comptime variant: gl_material.Variant) type {
    return struct {
        const Self = @This();
        const gl = switch (variant) {
            .gles30 => gles_gl,
            else => desktop_gl,
        };
        pub const Renderer = switch (variant) {
            .gl44 => embed_gl.Gl44Renderer,
            .gl33 => embed_gl.Gl33Renderer,
            .gles30 => embed_gl.Gles30Renderer,
        };
        const Material = gl_material.GlMaterial(variant);
        pub const Cache = Material.Cache;

        allocator: std.mem.Allocator,
        renderer: Renderer,
        cache: Cache,
        material: Material,
        scratch: driver_common.ScratchBuf,
        label_b: PassBindings,
        panel_b: PassBindings,
        hud_b: PassBindings,
        hud_gen: u32,

        /// Assumes a GL context for `variant` is already current.
        pub fn init(allocator: std.mem.Allocator, scene: *Scene) !Self {
            var renderer = try Renderer.init(allocator);
            errdefer renderer.deinit();

            var cache = try Cache.init(allocator, scene.fonts.pool, .{
                .max_bindings = 16,
                .layer_info_height = 128,
                .max_images = 8,
                .max_image_width = 128,
                .max_image_height = 128,
            });
            errdefer cache.deinit();

            var material: Material = undefined;
            try material.init(allocator, &cache, &scene.material);
            errdefer material.deinit();

            const label_b = try uploadPass(allocator, &cache, &scene.label);
            const panel_b = try uploadPass(allocator, &cache, &scene.panel);
            const hud_b = try uploadPass(allocator, &cache, &scene.hud);

            return .{
                .allocator = allocator,
                .renderer = renderer,
                .cache = cache,
                .material = material,
                .scratch = driver_common.ScratchBuf.init(allocator),
                .label_b = label_b,
                .panel_b = panel_b,
                .hud_b = hud_b,
                .hud_gen = scene.hud_gen,
            };
        }

        pub fn deinit(self: *Self) void {
            self.scratch.deinit();
            self.material.deinit();
            self.cache.deinit();
            self.renderer.deinit();
            self.* = undefined;
        }

        fn uploadPass(allocator: std.mem.Allocator, cache: *Cache, pass: *const PreparedPass) !PassBindings {
            var b: [2]snail.render.records.Binding = undefined;
            try cache.upload(allocator, &.{ &pass.path_atlas, &pass.text_atlas }, &b);
            return .{ .path = b[0], .text = b[1] };
        }

        /// Draw the scene into the currently-bound framebuffer (already cleared
        /// by the caller — the windowed driver and the harness clear differently).
        /// `view_proj` places the world; `logical_*` is the HUD's screen-space
        /// pixel extent; `surface` carries the framebuffer size + encoding.
        pub fn draw(
            self: *Self,
            scene: *Scene,
            logical_w: u32,
            logical_h: u32,
            view_proj: snail.Mat4,
            surface: @import("snail-raster").TargetSurface,
        ) !void {
            // Re-upload the HUD if it was rebuilt (perf line / resize).
            if (scene.hud_gen != self.hud_gen) {
                self.cache.release(self.hud_b.path);
                self.cache.release(self.hud_b.text);
                self.hud_b = try uploadPass(self.allocator, &self.cache, &scene.hud);
                self.hud_gen = scene.hud_gen;
            }

            const output_srgb = surface.encoding.shaderOutputEncoding() == .srgb;

            // 1. Custom-material coverage quad (opaque; writes depth → occludes).
            gl.glEnable(gl.GL_DEPTH_TEST);
            gl.glDepthMask(gl.GL_TRUE);
            gl.glDisable(gl.GL_BLEND);
            try self.material.draw(
                &self.cache,
                view_proj,
                scene.material_model,
                .{ scene_mod.material_scene_w, scene_mod.material_scene_h },
                scene_mod.material_base_color,
                scene.materialLightDir(),
                scene_mod.material_relief,
                scene_mod.material_roughness,
                output_srgb,
            );

            // 2 & 3. The label (opaque sign) and translucent panel are both
            // depth-tested against the material quad but write no depth
            // themselves, so they must be drawn back-to-front among themselves
            // (painter's order) — otherwise the translucent panel paints over a
            // nearer label. Draw the farther one first.
            gl.glDepthMask(gl.GL_FALSE);
            if (scene.labelBeforePanel()) {
                try self.drawSnailPass(&scene.label, self.label_b, scene.label_plane.mvp(view_proj), surface);
                try self.drawSnailPass(&scene.panel, self.panel_b, scene.panel_plane.mvp(view_proj), surface);
            } else {
                try self.drawSnailPass(&scene.panel, self.panel_b, scene.panel_plane.mvp(view_proj), surface);
                try self.drawSnailPass(&scene.label, self.label_b, scene.label_plane.mvp(view_proj), surface);
            }

            // 4. HUD overlay (screen space; no depth).
            gl.glDisable(gl.GL_DEPTH_TEST);
            const hud_mvp = snail.Mat4.ortho(0, @floatFromInt(logical_w), @floatFromInt(logical_h), 0, -1, 1);
            try self.drawSnailPass(&scene.hud, self.hud_b, hud_mvp, surface);
        }

        fn drawSnailPass(self: *Self, pass: *const PreparedPass, b: PassBindings, mvp: snail.Mat4, surface: @import("snail-raster").TargetSurface) !void {
            const needed = snail.emit.wordBudget(pass.path_picture.shapes.len) + snail.emit.wordBudget(pass.text_picture.shapes.len);
            try self.scratch.ensure(needed, 4);
            var wlen: usize = 0;
            var slen: usize = 0;
            _ = try snail.emit.emit(self.scratch.words, self.scratch.segs, &wlen, &slen, b.path, &pass.path_atlas, pass.path_picture.shapes, .identity, .{ 1, 1, 1, 1 });
            _ = try snail.emit.emit(self.scratch.words, self.scratch.segs, &wlen, &slen, b.text, &pass.text_atlas, pass.text_picture.shapes, .identity, .{ 1, 1, 1, 1 });
            const ds = @import("snail-raster").DrawState{ .mvp = mvp, .surface = surface, .raster = .{} };
            self.renderer.state.beginDraw();
            try self.renderer.state.draw(self.allocator, ds, .{ .words = self.scratch.words[0..wlen], .segments = self.scratch.segs[0..slen] }, &.{&self.cache});
        }
    };
}

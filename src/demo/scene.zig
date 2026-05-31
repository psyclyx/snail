//! Thin glue between the long-lived banner `Assets` and per-frame
//! `Content` builds, ported to the new snail API.
//!
//! The legacy `scene.zig` was a forwarding layer around `TextAtlas` +
//! `BlobInProgress`; with the new API the bulk of that responsibility
//! lives inside `banner.zig`. This module's role is now just to choose a
//! sensible `PagePool` configuration and a snap step for the caller, plus
//! a `ViewMode` enum the interactive demo can switch with a keystroke.

const std = @import("std");
const snail = @import("snail");
const demo_banner = @import("banner.zig");

const Allocator = std.mem.Allocator;

pub const Assets = demo_banner.Assets;
pub const Content = demo_banner.Content;
pub const Layout = demo_banner.Layout;
pub const HintOptions = demo_banner.HintOptions;

/// Demo view modes. The legacy demo cycled between debug overlays on the
/// path picture; with the new API there is currently only one mode, but
/// we keep the enum so the demo's keyboard handler doesn't need a code
/// change when more views land.
pub const ViewMode = enum {
    normal,
};

pub const default_pool_options = .{
    .max_layers = 24,
    .curve_words_per_page = 1 << 18,
    .band_words_per_page = 1 << 16,
};

/// Build a banner `Content`. Caller owns `pool` and `assets`; the returned
/// `Content` borrows `pool` (it allocates pages from it) and is freed via
/// `Content.deinit`.
pub fn build(
    allocator: Allocator,
    pool: *snail.PagePool,
    assets: *Assets,
    width: f32,
    height: f32,
    snap_step: snail.Vec2,
    hint_options: HintOptions,
) !Content {
    return demo_banner.build(allocator, pool, assets, width, height, snap_step, hint_options);
}

/// Build with no hinting and a sensible default snap step. Useful for
/// non-interactive callers that don't care about pixel grid snapping.
pub fn buildSimple(
    allocator: Allocator,
    pool: *snail.PagePool,
    assets: *Assets,
    width: f32,
    height: f32,
) !Content {
    return build(allocator, pool, assets, width, height, .{ .x = 1, .y = 1 }, .{});
}

const std = @import("std");
const snail = @import("snail");
const SubpixelOrder = @import("snail-raster").SubpixelOrder;

pub const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("linux/input-event-codes.h");
    @cInclude("xdg-shell-client-protocol.h");
    @cInclude("presentation-time-client-protocol.h");
});

/// Receives the wall-clock interval (microseconds) between two
/// consecutive successful surface presentations, as reported by the
/// compositor via `wp_presentation`. This is the true display cadence:
/// it doesn't care about which backend produced the frame, doesn't
/// depend on where the application chooses to wait (`shouldClose`,
/// `vkAcquireNextImageKHR`, `eglSwapBuffers`, etc.), and isn't subject
/// to the CPU-side render-loop jitter that biases naive
/// top-of-loop dt measurements.
pub const PresentationCallback = *const fn (ctx: *anyopaque, interval_us: u32) void;

pub const KEY_R = c.KEY_R;
pub const KEY_L = c.KEY_L;
pub const KEY_W = c.KEY_W;
pub const KEY_A = c.KEY_A;
pub const KEY_S = c.KEY_S;
pub const KEY_D = c.KEY_D;
pub const KEY_Q = c.KEY_Q;
pub const KEY_E = c.KEY_E;
pub const KEY_Z = c.KEY_Z;
pub const KEY_X = c.KEY_X;
pub const KEY_H = c.KEY_H;
pub const KEY_B = c.KEY_B;
pub const KEY_C = c.KEY_C;
pub const KEY_T = c.KEY_T;
pub const KEY_O = c.KEY_O;
pub const KEY_V = c.KEY_V;
pub const KEY_G = c.KEY_G;
pub const KEY_F = c.KEY_F;
pub const KEY_ESCAPE = c.KEY_ESC;
pub const KEY_LEFT = c.KEY_LEFT;
pub const KEY_RIGHT = c.KEY_RIGHT;
pub const KEY_UP = c.KEY_UP;
pub const KEY_DOWN = c.KEY_DOWN;

pub const Window = struct {
    const max_outputs = 8;
    const OutputInfo = struct {
        wl_output: ?*c.wl_output = null,
        registry_name: u32 = 0,
        subpixel: SubpixelOrder = .none,
        has_subpixel_info: bool = false,
        scale: u32 = 1,
        entered: bool = false,
    };

    display: *c.wl_display,
    registry: *c.wl_registry,
    compositor: ?*c.wl_compositor = null,
    shm: ?*c.wl_shm = null,
    wm_base: ?*c.xdg_wm_base = null,
    surface: *c.wl_surface,
    xdg_surface: *c.xdg_surface,
    toplevel: *c.xdg_toplevel,
    seat: ?*c.wl_seat = null,
    keyboard: ?*c.wl_keyboard = null,

    // ── Presentation feedback (wp_presentation) ──
    // Bound from the registry if the compositor advertises it. When
    // non-null we can request per-commit feedback objects that fire
    // with an actual presentation timestamp; deltas between successive
    // timestamps give the real display interval, identical across
    // CPU/GL/Vulkan backends.
    wp_presentation: ?*c.struct_wp_presentation = null,
    /// Clock domain the compositor reports timestamps in. CLOCK_MONOTONIC
    /// on every Linux compositor in practice, but we honor whatever the
    /// `clock_id` event reports.
    presentation_clock_id: u32 = 1, // CLOCK_MONOTONIC
    /// Timestamp (nanoseconds) of the most recent successful
    /// presentation, used to compute the interval handed to
    /// `presentation_callback`. Zero until the first `presented` event
    /// arrives.
    last_presented_ns: u64 = 0,
    presentation_callback: ?PresentationCallback = null,
    presentation_ctx: ?*anyopaque = null,

    width: u32,
    height: u32,
    buffer_scale: u32 = 1,
    scale_changed: bool = false,
    outputs: [max_outputs]OutputInfo = [_]OutputInfo{.{}} ** max_outputs,
    active_output: ?*c.wl_output = null,
    monitor_changed: bool = false,
    pending_geometry_commit: bool = true,
    resized: bool = false,
    close_requested: bool = false,
    key_down: [256]bool = .{false} ** 256,
    // Latches set on each PRESSED event in the keyboard handler and cleared
    // when `isKeyPressed` is read. Decoupling from `key_down`'s live state
    // means a quick down/up pair that arrives between two `pumpEvents`
    // calls (typical when frames are slow, e.g. CPU rendering) is still
    // observable; the previous edge-detection on `key_down` would miss it.
    key_pressed: [256]bool = .{false} ** 256,

    pub fn init(width: u32, height: u32, title: [*:0]const u8) !*Window {
        const display = c.wl_display_connect(null) orelse return error.WaylandConnectFailed;
        errdefer c.wl_display_disconnect(display);

        const registry = c.wl_display_get_registry(display) orelse return error.RegistryInitFailed;
        errdefer c.wl_registry_destroy(registry);

        const self = try std.heap.c_allocator.create(Window);
        errdefer std.heap.c_allocator.destroy(self);

        self.* = .{
            .display = display,
            .registry = registry,
            .surface = undefined,
            .xdg_surface = undefined,
            .toplevel = undefined,
            .width = width,
            .height = height,
        };

        _ = c.wl_registry_add_listener(registry, &registry_listener, self);
        if (c.wl_display_roundtrip(display) < 0) return error.WaylandRoundtripFailed;
        if (self.compositor == null or self.wm_base == null) return error.MissingWaylandGlobals;

        _ = c.xdg_wm_base_add_listener(self.wm_base.?, &wm_base_listener, self);

        self.surface = c.wl_compositor_create_surface(self.compositor.?) orelse return error.SurfaceCreateFailed;
        errdefer c.wl_surface_destroy(self.surface);
        _ = c.wl_surface_add_listener(self.surface, &surface_listener, self);

        self.xdg_surface = c.xdg_wm_base_get_xdg_surface(self.wm_base.?, self.surface) orelse return error.SurfaceCreateFailed;
        errdefer c.xdg_surface_destroy(self.xdg_surface);

        _ = c.xdg_surface_add_listener(self.xdg_surface, &xdg_surface_listener, self);

        self.toplevel = c.xdg_surface_get_toplevel(self.xdg_surface) orelse return error.SurfaceCreateFailed;
        errdefer c.xdg_toplevel_destroy(self.toplevel);

        _ = c.xdg_toplevel_add_listener(self.toplevel, &xdg_toplevel_listener, self);
        c.xdg_toplevel_set_title(self.toplevel, title);
        c.xdg_toplevel_set_app_id(self.toplevel, "snail-demo");
        c.wl_surface_commit(self.surface);

        if (c.wl_display_roundtrip(display) < 0) return error.WaylandRoundtripFailed;
        self.refreshBufferScale();
        self.scale_changed = false;
        return self;
    }

    pub fn deinit(self: *Window) void {
        if (self.keyboard) |keyboard| {
            c.wl_keyboard_destroy(keyboard);
            self.keyboard = null;
        }
        if (self.seat) |seat| {
            c.wl_seat_destroy(seat);
            self.seat = null;
        }
        for (&self.outputs) |*info| {
            if (info.wl_output) |output| {
                c.wl_output_destroy(output);
                info.* = .{};
            }
        }
        c.xdg_toplevel_destroy(self.toplevel);
        c.xdg_surface_destroy(self.xdg_surface);
        c.wl_surface_destroy(self.surface);
        if (self.wp_presentation) |pres| c.wp_presentation_destroy(pres);
        if (self.wm_base) |wm_base| c.xdg_wm_base_destroy(wm_base);
        if (self.shm) |shm| c.wl_shm_destroy(shm);
        if (self.compositor) |compositor| c.wl_compositor_destroy(compositor);
        c.wl_registry_destroy(self.registry);
        c.wl_display_disconnect(self.display);
        std.heap.c_allocator.destroy(self);
    }

    pub fn pumpEvents(self: *Window) void {
        _ = c.wl_display_dispatch_pending(self.display);

        while (c.wl_display_prepare_read(self.display) != 0) {
            _ = c.wl_display_dispatch_pending(self.display);
        }

        _ = c.wl_display_flush(self.display);

        var fds = [_]std.posix.pollfd{
            .{
                .fd = c.wl_display_get_fd(self.display),
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };

        const ready = std.posix.poll(&fds, 0) catch 0;
        if (ready > 0 and (fds[0].revents & std.posix.POLL.IN) != 0) {
            _ = c.wl_display_read_events(self.display);
        } else {
            _ = c.wl_display_cancel_read(self.display);
        }
        _ = c.wl_display_dispatch_pending(self.display);
        self.refreshBufferScale();
    }

    pub fn shouldClose(self: *const Window) bool {
        return self.close_requested;
    }

    pub fn getWindowSize(self: *const Window) [2]u32 {
        return .{ self.width, self.height };
    }

    pub fn getFramebufferSize(self: *const Window) [2]u32 {
        const scale = @max(self.buffer_scale, 1);
        return .{
            std.math.mul(u32, self.width, scale) catch std.math.maxInt(u32),
            std.math.mul(u32, self.height, scale) catch std.math.maxInt(u32),
        };
    }

    pub fn getBufferScale(self: *const Window) u32 {
        return @max(self.buffer_scale, 1);
    }

    pub fn consumeResized(self: *Window) bool {
        const changed = self.resized;
        self.resized = false;
        return changed;
    }

    pub fn consumeMonitorChanged(self: *Window) bool {
        const changed = self.monitor_changed;
        self.monitor_changed = false;
        return changed;
    }

    pub fn consumeScaleChanged(self: *Window) bool {
        const changed = self.scale_changed;
        self.scale_changed = false;
        return changed;
    }

    pub fn currentSubpixelOrder(self: *const Window, fallback: SubpixelOrder) SubpixelOrder {
        if (self.active_output) |active| {
            if (self.findOutputInfo(active)) |info| {
                if (info.has_subpixel_info) return info.subpixel;
                return fallback;
            }
        }
        for (self.outputs) |info| {
            if (info.wl_output != null and info.has_subpixel_info) return info.subpixel;
        }
        return fallback;
    }

    pub fn currentBufferScale(self: *const Window) u32 {
        var scale: u32 = 1;
        var have_entered = false;
        for (self.outputs) |info| {
            if (info.wl_output != null and info.entered) {
                have_entered = true;
                scale = @max(scale, info.scale);
            }
        }
        if (have_entered) return scale;
        if (self.active_output) |active| {
            if (self.findOutputInfo(active)) |info| {
                return @max(info.scale, 1);
            }
        }
        for (self.outputs) |info| {
            if (info.wl_output != null) scale = @max(scale, info.scale);
        }
        return scale;
    }

    pub fn isKeyDown(self: *const Window, key: u32) bool {
        if (key >= self.key_down.len) return false;
        return self.key_down[key];
    }

    pub fn isKeyPressed(self: *Window, key: u32) bool {
        if (key >= self.key_pressed.len) return false;
        const pressed = self.key_pressed[key];
        self.key_pressed[key] = false;
        return pressed;
    }

    /// Wire a callback that will be invoked whenever the compositor
    /// reports a successful presentation, with the wall-clock interval
    /// (in microseconds) from the previous successful presentation. Pass
    /// `null` to detach. The window holds `ctx` opaquely; the caller
    /// owns its lifetime and is responsible for ensuring it outlives the
    /// window (or for clearing the callback before destroying it).
    pub fn setPresentationCallback(self: *Window, cb: ?PresentationCallback, ctx: ?*anyopaque) void {
        self.presentation_callback = cb;
        self.presentation_ctx = ctx;
    }

    /// Returns true if the compositor exposed `wp_presentation`; calls
    /// `requestPresentationFeedback` are no-ops otherwise.
    pub fn hasPresentationFeedback(self: *const Window) bool {
        return self.wp_presentation != null;
    }

    /// Create a `wp_presentation_feedback` for the *next* commit on this
    /// surface. Each backend's swap function calls this immediately
    /// before its commit (CPU: before `wl_surface_commit`; Vulkan/GL:
    /// before the present/swap call that performs the commit
    /// internally). The compositor will deliver a `presented` or
    /// `discarded` event asynchronously some time after the commit; the
    /// proxy auto-destroys after firing, so we don't track it.
    pub fn requestPresentationFeedback(self: *Window) void {
        const pres = self.wp_presentation orelse return;
        const fb = c.wp_presentation_feedback(pres, self.surface) orelse return;
        _ = c.wp_presentation_feedback_add_listener(fb, &presentation_feedback_listener, self);
    }

    fn allocOutputInfo(self: *Window) ?*OutputInfo {
        for (&self.outputs) |*info| {
            if (info.wl_output == null) return info;
        }
        return null;
    }

    fn findOutputInfo(self: *const Window, output: *c.wl_output) ?*const OutputInfo {
        for (&self.outputs) |*info| {
            if (info.wl_output == output) return info;
        }
        return null;
    }

    fn findOutputInfoMut(self: *Window, output: *c.wl_output) ?*OutputInfo {
        for (&self.outputs) |*info| {
            if (info.wl_output == output) return info;
        }
        return null;
    }

    fn refreshBufferScale(self: *Window) void {
        const next = self.currentBufferScale();
        if (next == self.buffer_scale) return;
        self.buffer_scale = next;
        self.scale_changed = true;
        c.wl_surface_set_buffer_scale(self.surface, @intCast(next));
    }
};

pub fn getTime() f64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1_000_000_000.0;
}

fn selfFrom(data: ?*anyopaque) *Window {
    return @ptrCast(@alignCast(data.?));
}

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*c.wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const self = selfFrom(data);
    const iface = std.mem.span(interface);
    const reg = registry.?;

    if (std.mem.eql(u8, iface, "wl_compositor")) {
        self.compositor = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_compositor_interface, @min(version, 4)));
    } else if (std.mem.eql(u8, iface, "wl_shm")) {
        self.shm = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_shm_interface, 1));
    } else if (std.mem.eql(u8, iface, "xdg_wm_base")) {
        self.wm_base = @ptrCast(c.wl_registry_bind(reg, name, &c.xdg_wm_base_interface, 1));
    } else if (std.mem.eql(u8, iface, "wl_seat")) {
        self.seat = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_seat_interface, @min(version, 5)));
        if (self.seat) |seat| {
            _ = c.wl_seat_add_listener(seat, &seat_listener, self);
        }
    } else if (std.mem.eql(u8, iface, "wp_presentation")) {
        self.wp_presentation = @ptrCast(c.wl_registry_bind(reg, name, &c.wp_presentation_interface, 1));
        if (self.wp_presentation) |pres| {
            _ = c.wp_presentation_add_listener(pres, &presentation_listener, self);
        }
    } else if (std.mem.eql(u8, iface, "wl_output")) {
        const slot = self.allocOutputInfo() orelse return;
        slot.* = .{
            .wl_output = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_output_interface, @min(version, 2))),
            .registry_name = name,
            .subpixel = .none,
            .has_subpixel_info = false,
            .scale = 1,
            .entered = false,
        };
        if (slot.wl_output) |output| {
            _ = c.wl_output_add_listener(output, &output_listener, self);
            if (self.active_output == null) self.active_output = output;
            self.monitor_changed = true;
        }
    }
}

fn registryGlobalRemove(data: ?*anyopaque, _: ?*c.wl_registry, name: u32) callconv(.c) void {
    const self = selfFrom(data);
    for (&self.outputs) |*info| {
        if (info.wl_output != null and info.registry_name == name) {
            if (self.active_output == info.wl_output) {
                self.active_output = null;
                self.monitor_changed = true;
            }
            c.wl_output_destroy(info.wl_output.?);
            info.* = .{};
            return;
        }
    }
}

const registry_listener = c.wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

// ── wp_presentation listeners ──
//
// `clock_id` arrives once after binding. We honor whatever the
// compositor reports; in practice every Linux compositor uses
// CLOCK_MONOTONIC (= 1), which is also what the rest of the demo's
// timing code uses, so deltas are directly comparable.
//
// `presentation_feedback` events fire asynchronously after each
// commit's corresponding present (or discard). We extract the
// timestamp, compute the interval since the last successful present,
// and hand it to the registered callback. Discards are recorded as
// "no successful present this commit"; we leave `last_presented_ns`
// alone so the next successful present's interval reflects however
// many vsyncs elapsed (this naturally surfaces as a "2×" or "3×" bucket
// downstream, which is the correct interpretation: the user did wait
// that long for the next frame to appear).

fn presentationClockId(
    data: ?*anyopaque,
    _: ?*c.struct_wp_presentation,
    clk_id: u32,
) callconv(.c) void {
    selfFrom(data).presentation_clock_id = clk_id;
}

const presentation_listener = c.wp_presentation_listener{
    .clock_id = presentationClockId,
};

fn presentationFeedbackSyncOutput(
    _: ?*anyopaque,
    _: ?*c.struct_wp_presentation_feedback,
    _: ?*c.wl_output,
) callconv(.c) void {}

fn presentationFeedbackPresented(
    data: ?*anyopaque,
    _: ?*c.struct_wp_presentation_feedback,
    tv_sec_hi: u32,
    tv_sec_lo: u32,
    tv_nsec: u32,
    _: u32, // refresh
    _: u32, // seq_hi
    _: u32, // seq_lo
    _: u32, // flags
) callconv(.c) void {
    const self = selfFrom(data);
    const sec: u64 = (@as(u64, tv_sec_hi) << 32) | @as(u64, tv_sec_lo);
    const now_ns: u64 = sec * 1_000_000_000 + @as(u64, tv_nsec);
    if (self.last_presented_ns != 0 and now_ns > self.last_presented_ns) {
        const delta_ns = now_ns - self.last_presented_ns;
        const delta_us_u64 = delta_ns / 1000;
        const delta_us: u32 = @intCast(@min(delta_us_u64, @as(u64, std.math.maxInt(u32))));
        if (self.presentation_callback) |cb| {
            cb(self.presentation_ctx.?, delta_us);
        }
    }
    self.last_presented_ns = now_ns;
}

fn presentationFeedbackDiscarded(
    _: ?*anyopaque,
    _: ?*c.struct_wp_presentation_feedback,
) callconv(.c) void {
    // No timestamp; nothing to record. We deliberately don't reset
    // `last_presented_ns` — the next successful presented event then
    // measures a multi-vsync interval, which is honest.
}

const presentation_feedback_listener = c.wp_presentation_feedback_listener{
    .sync_output = presentationFeedbackSyncOutput,
    .presented = presentationFeedbackPresented,
    .discarded = presentationFeedbackDiscarded,
};

fn wmBasePing(data: ?*anyopaque, wm_base: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
    _ = data;
    c.xdg_wm_base_pong(wm_base.?, serial);
}

const wm_base_listener = c.xdg_wm_base_listener{
    .ping = wmBasePing,
};

fn xdgSurfaceConfigure(data: ?*anyopaque, xdg_surface: ?*c.xdg_surface, serial: u32) callconv(.c) void {
    const self = selfFrom(data);
    c.xdg_surface_ack_configure(xdg_surface.?, serial);
    if (self.pending_geometry_commit and self.width > 0 and self.height > 0) {
        c.xdg_surface_set_window_geometry(
            xdg_surface.?,
            0,
            0,
            @intCast(self.width),
            @intCast(self.height),
        );
        c.wl_surface_commit(self.surface);
        self.pending_geometry_commit = false;
    }
}

const xdg_surface_listener = c.xdg_surface_listener{
    .configure = xdgSurfaceConfigure,
};

fn xdgToplevelConfigure(
    data: ?*anyopaque,
    _: ?*c.xdg_toplevel,
    width: i32,
    height: i32,
    _: ?*c.wl_array,
) callconv(.c) void {
    const self = selfFrom(data);
    self.pending_geometry_commit = true;
    if (width > 0 and height > 0) {
        const w: u32 = @intCast(width);
        const h: u32 = @intCast(height);
        if (w != self.width or h != self.height) {
            self.width = w;
            self.height = h;
            self.resized = true;
        }
    }
}

fn xdgToplevelClose(data: ?*anyopaque, _: ?*c.xdg_toplevel) callconv(.c) void {
    selfFrom(data).close_requested = true;
}

fn xdgToplevelBounds(_: ?*anyopaque, _: ?*c.xdg_toplevel, _: i32, _: i32) callconv(.c) void {}

fn xdgToplevelWmCapabilities(_: ?*anyopaque, _: ?*c.xdg_toplevel, _: ?*c.wl_array) callconv(.c) void {}

const xdg_toplevel_listener = c.xdg_toplevel_listener{
    .configure = xdgToplevelConfigure,
    .close = xdgToplevelClose,
    .configure_bounds = xdgToplevelBounds,
    .wm_capabilities = xdgToplevelWmCapabilities,
};

fn seatCapabilities(data: ?*anyopaque, seat: ?*c.wl_seat, capabilities: u32) callconv(.c) void {
    const self = selfFrom(data);
    if ((capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD) != 0) {
        if (self.keyboard == null) {
            self.keyboard = c.wl_seat_get_keyboard(seat.?) orelse return;
            _ = c.wl_keyboard_add_listener(self.keyboard, &keyboard_listener, self);
        }
    } else if (self.keyboard) |keyboard| {
        c.wl_keyboard_destroy(keyboard);
        self.keyboard = null;
    }
}

fn seatName(_: ?*anyopaque, _: ?*c.wl_seat, _: [*c]const u8) callconv(.c) void {}

const seat_listener = c.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

fn keyboardKeymap(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, fd: i32, _: u32) callconv(.c) void {
    if (fd >= 0) _ = std.c.close(fd);
}

fn keyboardEnter(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface, _: ?*c.wl_array) callconv(.c) void {}

fn keyboardLeave(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface) callconv(.c) void {}

fn keyboardKey(
    data: ?*anyopaque,
    _: ?*c.wl_keyboard,
    _: u32,
    _: u32,
    key: u32,
    state: u32,
) callconv(.c) void {
    const self = selfFrom(data);
    if (key < self.key_down.len) {
        const pressed = state == c.WL_KEYBOARD_KEY_STATE_PRESSED;
        self.key_down[key] = pressed;
        if (pressed) self.key_pressed[key] = true;
    }
}

fn keyboardModifiers(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}

fn keyboardRepeatInfo(_: ?*anyopaque, _: ?*c.wl_keyboard, _: i32, _: i32) callconv(.c) void {}

const keyboard_listener = c.wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeatInfo,
};

fn mapOutputSubpixel(subpixel: c_int) ?SubpixelOrder {
    return switch (subpixel) {
        c.WL_OUTPUT_SUBPIXEL_NONE => .none,
        c.WL_OUTPUT_SUBPIXEL_HORIZONTAL_RGB => .rgb,
        c.WL_OUTPUT_SUBPIXEL_HORIZONTAL_BGR => .bgr,
        c.WL_OUTPUT_SUBPIXEL_VERTICAL_RGB => .vrgb,
        c.WL_OUTPUT_SUBPIXEL_VERTICAL_BGR => .vbgr,
        else => null,
    };
}

fn outputGeometry(
    data: ?*anyopaque,
    output: ?*c.wl_output,
    _: i32,
    _: i32,
    _: i32,
    _: i32,
    subpixel: c_int,
    _: [*c]const u8,
    _: [*c]const u8,
    _: c_int,
) callconv(.c) void {
    const self = selfFrom(data);
    const wl_output = output orelse return;
    if (self.findOutputInfoMut(wl_output)) |info| {
        const mapped = mapOutputSubpixel(subpixel);
        const next_order = mapped orelse .none;
        const next_has_info = mapped != null;
        if (info.subpixel != next_order or info.has_subpixel_info != next_has_info) {
            info.subpixel = next_order;
            info.has_subpixel_info = next_has_info;
            if (self.active_output == wl_output) self.monitor_changed = true;
        }
    }
}

fn outputMode(_: ?*anyopaque, _: ?*c.wl_output, _: u32, _: i32, _: i32, _: i32) callconv(.c) void {}
fn outputDone(_: ?*anyopaque, _: ?*c.wl_output) callconv(.c) void {}
fn outputScale(data: ?*anyopaque, output: ?*c.wl_output, scale: i32) callconv(.c) void {
    const self = selfFrom(data);
    const wl_output = output orelse return;
    if (self.findOutputInfoMut(wl_output)) |info| {
        const next_scale: u32 = if (scale > 0) @intCast(scale) else 1;
        if (info.scale != next_scale) {
            info.scale = next_scale;
            if (info.entered or self.active_output == wl_output) self.monitor_changed = true;
        }
    }
}

const output_listener = c.wl_output_listener{
    .geometry = outputGeometry,
    .mode = outputMode,
    .done = outputDone,
    .scale = outputScale,
};

fn surfaceEnter(data: ?*anyopaque, _: ?*c.wl_surface, output: ?*c.wl_output) callconv(.c) void {
    const self = selfFrom(data);
    const wl_output = output orelse return;
    if (self.findOutputInfoMut(wl_output)) |info| {
        info.entered = true;
    }
    if (self.active_output != wl_output) {
        self.active_output = wl_output;
        self.monitor_changed = true;
    } else {
        self.monitor_changed = true;
    }
}

fn surfaceLeave(data: ?*anyopaque, _: ?*c.wl_surface, output: ?*c.wl_output) callconv(.c) void {
    const self = selfFrom(data);
    const wl_output = output orelse return;
    if (self.findOutputInfoMut(wl_output)) |info| {
        info.entered = false;
    }
    if (self.active_output == wl_output) {
        self.active_output = null;
        self.monitor_changed = true;
    } else {
        self.monitor_changed = true;
    }
}

const surface_listener = c.wl_surface_listener{
    .enter = surfaceEnter,
    .leave = surfaceLeave,
};

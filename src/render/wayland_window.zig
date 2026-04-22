const std = @import("std");

pub const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("linux/input-event-codes.h");
    @cInclude("xdg-shell-client-protocol.h");
});

pub const KEY_R = c.KEY_R;
pub const KEY_S = c.KEY_S;
pub const KEY_L = c.KEY_L;
pub const KEY_Z = c.KEY_Z;
pub const KEY_X = c.KEY_X;
pub const KEY_ESCAPE = c.KEY_ESC;
pub const KEY_LEFT = c.KEY_LEFT;
pub const KEY_RIGHT = c.KEY_RIGHT;
pub const KEY_UP = c.KEY_UP;
pub const KEY_DOWN = c.KEY_DOWN;

pub const Window = struct {
    display: *c.wl_display,
    registry: *c.wl_registry,
    compositor: ?*c.wl_compositor = null,
    wm_base: ?*c.xdg_wm_base = null,
    surface: *c.wl_surface,
    xdg_surface: *c.xdg_surface,
    toplevel: *c.xdg_toplevel,
    seat: ?*c.wl_seat = null,
    keyboard: ?*c.wl_keyboard = null,

    width: u32,
    height: u32,
    resized: bool = false,
    close_requested: bool = false,
    key_down: [256]bool = .{false} ** 256,
    prev_keys: [256]bool = .{false} ** 256,

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

        self.xdg_surface = c.xdg_wm_base_get_xdg_surface(self.wm_base.?, self.surface) orelse return error.SurfaceCreateFailed;
        errdefer c.xdg_surface_destroy(self.xdg_surface);

        _ = c.xdg_surface_add_listener(self.xdg_surface, &xdg_surface_listener, self);

        self.toplevel = c.xdg_surface_get_toplevel(self.xdg_surface) orelse return error.SurfaceCreateFailed;
        errdefer c.xdg_toplevel_destroy(self.toplevel);

        _ = c.xdg_toplevel_add_listener(self.toplevel, &xdg_toplevel_listener, self);
        c.xdg_toplevel_set_title(self.toplevel, title);
        c.wl_surface_commit(self.surface);

        if (c.wl_display_roundtrip(display) < 0) return error.WaylandRoundtripFailed;
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
        c.xdg_toplevel_destroy(self.toplevel);
        c.xdg_surface_destroy(self.xdg_surface);
        c.wl_surface_destroy(self.surface);
        if (self.wm_base) |wm_base| c.xdg_wm_base_destroy(wm_base);
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
    }

    pub fn shouldClose(self: *const Window) bool {
        return self.close_requested;
    }

    pub fn getWindowSize(self: *const Window) [2]u32 {
        return .{ self.width, self.height };
    }

    pub fn consumeResized(self: *Window) bool {
        const changed = self.resized;
        self.resized = false;
        return changed;
    }

    pub fn isKeyDown(self: *const Window, key: u32) bool {
        if (key >= self.key_down.len) return false;
        return self.key_down[key];
    }

    pub fn isKeyPressed(self: *Window, key: u32) bool {
        if (key >= self.key_down.len) return false;
        const down = self.key_down[key];
        const was_down = self.prev_keys[key];
        self.prev_keys[key] = down;
        return down and !was_down;
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
    } else if (std.mem.eql(u8, iface, "xdg_wm_base")) {
        self.wm_base = @ptrCast(c.wl_registry_bind(reg, name, &c.xdg_wm_base_interface, 1));
    } else if (std.mem.eql(u8, iface, "wl_seat")) {
        self.seat = @ptrCast(c.wl_registry_bind(reg, name, &c.wl_seat_interface, @min(version, 5)));
        if (self.seat) |seat| {
            _ = c.wl_seat_add_listener(seat, &seat_listener, self);
        }
    }
}

fn registryGlobalRemove(_: ?*anyopaque, _: ?*c.wl_registry, _: u32) callconv(.c) void {}

const registry_listener = c.wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

fn wmBasePing(data: ?*anyopaque, wm_base: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
    _ = data;
    c.xdg_wm_base_pong(wm_base.?, serial);
}

const wm_base_listener = c.xdg_wm_base_listener{
    .ping = wmBasePing,
};

fn xdgSurfaceConfigure(data: ?*anyopaque, xdg_surface: ?*c.xdg_surface, serial: u32) callconv(.c) void {
    c.xdg_surface_ack_configure(xdg_surface.?, serial);
    _ = selfFrom(data);
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
        self.key_down[key] = state == c.WL_KEYBOARD_KEY_STATE_PRESSED;
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

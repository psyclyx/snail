const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
});
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;

/// Query fontconfig for the system's LCD subpixel order.
/// Falls back to .rgb (correct for the vast majority of modern displays).
pub fn detect() SubpixelOrder {
    return popenAndParse("fc-match --format '%{rgba}' : 2>/dev/null", null) orelse .rgb;
}

/// Run `cmd` via popen. If `prefix` is non-null, find the first line starting
/// with it and parse the value after the prefix; otherwise parse all stdout.
fn popenAndParse(cmd: [*:0]const u8, prefix: ?[]const u8) ?SubpixelOrder {
    const f = c.popen(cmd, "r") orelse return null;
    defer _ = c.pclose(f);

    var line_buf: [512]u8 = undefined;
    var full_buf: [512]u8 = undefined;
    var full_len: usize = 0;

    while (c.fgets(&line_buf, @intCast(line_buf.len), f) != null) {
        const line = std.mem.sliceTo(&line_buf, 0);
        if (prefix) |p| {
            if (std.mem.startsWith(u8, line, p)) {
                return parse(std.mem.trim(u8, line[p.len..], " \t\r\n"));
            }
        } else {
            const n = @min(line.len, full_buf.len - full_len);
            @memcpy(full_buf[full_len..][0..n], line[0..n]);
            full_len += n;
        }
    }

    if (prefix == null and full_len > 0) {
        return parse(std.mem.trim(u8, full_buf[0..full_len], " \t\r\n"));
    }
    return null;
}

fn parse(s: []const u8) ?SubpixelOrder {
    if (std.mem.eql(u8, s, "rgb"))  return .rgb;
    if (std.mem.eql(u8, s, "bgr"))  return .bgr;
    if (std.mem.eql(u8, s, "vrgb")) return .vrgb;
    if (std.mem.eql(u8, s, "vbgr")) return .vbgr;
    if (std.mem.eql(u8, s, "none")) return .none;
    return null;
}

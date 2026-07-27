//! Timed mutations of the terminal cell model.
//!
//! Each lane exercises a different ingestion shape: individual characters,
//! whole lines, wrapped words, and pre-segmented Unicode/emoji cells.

const std = @import("std");
const screen_mod = @import("screen.zig");

const Screen = screen_mod.Screen;
const Writer = screen_mod.Writer;
const Style = screen_mod.Style;

const command = "zig build test-core  # one cell at a time";
const wrapped_words = [_][]const u8{
    "Wrapping ", "belongs ",    "to ",    "the ",       "host. ", "Font ",  "fallback ",
    "may ",      "change ",     "glyph ", "advances; ", "it ",    "never ", "changes ",
    "the ",      "terminal's ", "next ",  "column.",
};
const batch_lines = [_]struct { text: []const u8, style: Style }{
    .{ .text = "[ok] loaded regular + bold faces", .style = .success },
    .{ .text = "[ok] installed symbol and script fallbacks", .style = .success },
    .{ .text = "[new] shaped a complete dirty line", .style = .accent },
    .{ .text = "[new] committed all missing glyphs once", .style = .accent },
};

pub const Simulation = struct {
    screen: Screen = .{},
    command_column: usize = 0,
    wrap_row: usize = 13,
    wrap_column: usize = 0,
    command_offset: usize = 0,
    batch_index: usize = 0,
    wrap_index: usize = 0,
    emoji_index: usize = 0,
    command_clock: f64 = 0,
    batch_clock: f64 = 0,
    wrap_clock: f64 = 0,
    emoji_clock: f64 = 0,
    elapsed: f64 = 0,
    paused: bool = false,
    hinting_label: []const u8 = "unhinted",

    pub fn init() Simulation {
        var self: Simulation = .{};
        self.reset();
        return self;
    }

    pub fn reset(self: *Simulation) void {
        self.screen.clear();
        self.command_column = 2;
        self.wrap_row = 13;
        self.wrap_column = 0;
        self.command_offset = 0;
        self.batch_index = 0;
        self.wrap_index = 0;
        self.emoji_index = 0;
        self.command_clock = 0;
        self.batch_clock = 0;
        self.wrap_clock = 0;
        self.emoji_clock = 0;
        self.elapsed = 0;

        _ = self.screen.putAscii(0, 0, "SNAIL // TERMINAL-STYLE INCREMENTAL TEXT", .heading);
        _ = self.screen.putAscii(1, 0, "Host cells -> HarfBuzz clusters -> stable glyph keys -> append-only atlas", .dim);

        _ = self.screen.putAscii(2, 0, "01  CHARACTER STREAM", .heading);
        _ = self.screen.putAscii(3, 0, "$ ", .prompt);

        _ = self.screen.putAscii(5, 0, "02  COMPLETE DIRTY LINES", .heading);
        _ = self.screen.putAscii(11, 0, "03  HOST-OWNED WRAPPING", .heading);
        _ = self.screen.putAscii(18, 0, "04  FALLBACK + COMBINING + WIDE CELLS", .heading);
        _ = self.screen.putAscii(23, 0, "R reset   P pause   -/+ size   H hint   C backend   Esc quit", .dim);
        self.writeHintingStatus();
    }

    pub fn setHintingLabel(self: *Simulation, label: []const u8) void {
        self.hinting_label = label;
        self.writeHintingStatus();
    }

    fn writeHintingStatus(self: *Simulation) void {
        self.screen.clearRow(24);
        var column = self.screen.putAscii(24, 0, "active hinting: ", .dim);
        column = self.screen.putAscii(24, column, self.hinting_label, .warning);
        _ = self.screen.putAscii(24, column, "  (primary mono face)", .dim);
    }

    pub fn update(self: *Simulation, dt: f64) !bool {
        if (self.paused) return false;
        self.elapsed += dt;
        self.command_clock += dt;
        self.batch_clock += dt;
        self.wrap_clock += dt;
        self.emoji_clock += dt;
        var changed = false;

        while (self.command_clock >= 0.055 and self.command_offset < command.len) {
            self.command_clock -= 0.055;
            const len = try std.unicode.utf8ByteSequenceLength(command[self.command_offset]);
            var writer = Writer.init(&self.screen, 3, 3);
            writer.column = self.command_column;
            writer.put(command[self.command_offset..][0..len], 1, .command);
            self.command_column = writer.column;
            self.command_offset += len;
            changed = true;
        }

        while (self.batch_clock >= 0.9 and self.batch_index < batch_lines.len) {
            self.batch_clock -= 0.9;
            const row_index = 6 + self.batch_index;
            _ = self.screen.putAscii(
                row_index,
                0,
                batch_lines[self.batch_index].text,
                batch_lines[self.batch_index].style,
            );
            self.batch_index += 1;
            changed = true;
        }

        while (self.wrap_clock >= 0.22 and self.wrap_index < wrapped_words.len) {
            self.wrap_clock -= 0.22;
            var writer = Writer.init(&self.screen, 13, 16);
            writer.row_index = self.wrap_row;
            writer.column = self.wrap_column;
            writer.writeAscii(wrapped_words[self.wrap_index], .normal);
            self.wrap_row = writer.row_index;
            self.wrap_column = writer.column;
            self.wrap_index += 1;
            changed = true;
        }

        while (self.emoji_clock >= 0.7 and self.emoji_index < 7) {
            self.emoji_clock -= 0.7;
            try self.addFallbackStep(self.emoji_index);
            self.emoji_index += 1;
            changed = true;
        }

        if (self.elapsed >= 13.0) {
            self.reset();
            changed = true;
        }
        return changed;
    }

    fn addFallbackStep(self: *Simulation, index: usize) !void {
        switch (index) {
            0 => {
                _ = self.screen.putAscii(19, 0, "primary:", .dim);
                _ = self.screen.putAscii(19, 11, "mono grid", .normal);
            },
            1 => {
                _ = self.screen.putAscii(20, 0, "bold face:", .dim);
                _ = self.screen.putAscii(20, 11, "variable weight, same cell advance", .heading);
            },
            2 => {
                _ = self.screen.putAscii(21, 0, "combined:", .dim);
                _ = self.screen.put(21, 11, "e\u{301}", 1, .accent);
                _ = self.screen.putAscii(21, 13, "one cell / multiple glyphs", .normal);
            },
            3 => {
                _ = self.screen.putAscii(22, 0, "fallback:", .dim);
                _ = self.screen.put(22, 11, "न", 1, .normal);
                _ = self.screen.put(22, 12, "म", 1, .normal);
                _ = self.screen.put(22, 13, "स्ते", 1, .normal);
            },
            4 => {
                _ = self.screen.put(22, 19, "🌍", 2, .accent);
            },
            5 => {
                _ = self.screen.put(22, 22, "🚀", 2, .accent);
            },
            6 => {
                _ = self.screen.put(22, 25, "❤️", 2, .accent);
                _ = self.screen.putAscii(22, 29, "explicit 2-cell advances", .warning);
            },
            else => {},
        }
    }
};

test "simulation exposes each ingestion pattern over time" {
    var simulation = Simulation.init();
    try std.testing.expect(try simulation.update(1.0));
    try std.testing.expect(simulation.command_offset > 0);
    try std.testing.expect(simulation.batch_index > 0);
    try std.testing.expect(simulation.wrap_index > 0);
    try std.testing.expect(simulation.emoji_index > 0);
}

test "simulation reset restores stream cursors" {
    var simulation = Simulation.init();
    _ = try simulation.update(1.0);
    simulation.reset();
    try std.testing.expectEqual(@as(usize, 2), simulation.command_column);
    try std.testing.expectEqual(@as(usize, 13), simulation.wrap_row);
    try std.testing.expectEqual(@as(usize, 0), simulation.wrap_column);
}

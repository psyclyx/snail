//! A deliberately small terminal-style cell model.
//!
//! It owns columns, wrapping, wide-cell continuations, and style assignment.
//! Font selection, shaping, glyph residency, and drawing live in `view.zig`.

const std = @import("std");

pub const column_count: usize = 92;
pub const row_count: usize = 25;

pub const Style = enum {
    normal,
    dim,
    heading,
    prompt,
    command,
    success,
    warning,
    accent,
};

pub const Cell = struct {
    /// Empty for an unused cell and for a wide glyph's trailing continuation.
    text: []const u8 = "",
    style: Style = .normal,
    /// 0 = empty/continuation, 1 = ordinary cell, 2 = wide leading cell.
    width: u2 = 0,
    continuation: bool = false,

    pub fn isLead(self: Cell) bool {
        return self.width != 0 and !self.continuation;
    }
};

pub const Screen = struct {
    cells: [row_count][column_count]Cell = [_][column_count]Cell{
        [_]Cell{.{}} ** column_count,
    } ** row_count,
    generation: u64 = 0,

    pub fn clear(self: *Screen) void {
        for (&self.cells) |*row_cells| @memset(row_cells, .{});
        self.generation +|= 1;
    }

    pub fn row(self: *const Screen, index: usize) []const Cell {
        return &self.cells[index];
    }

    pub fn put(
        self: *Screen,
        row_index: usize,
        column: usize,
        text: []const u8,
        width: u2,
        style: Style,
    ) bool {
        if (row_index >= row_count or column >= column_count) return false;
        if (text.len == 0 or width == 0 or width > 2) return false;
        if (column + width > column_count) return false;

        self.clearOccupant(row_index, column);
        if (width == 2) self.clearOccupant(row_index, column + 1);
        self.cells[row_index][column] = .{
            .text = text,
            .style = style,
            .width = width,
        };
        if (width == 2) {
            self.cells[row_index][column + 1] = .{
                .style = style,
                .continuation = true,
            };
        }
        self.generation +|= 1;
        return true;
    }

    pub fn putAscii(
        self: *Screen,
        row_index: usize,
        start_column: usize,
        text: []const u8,
        style: Style,
    ) usize {
        var column = start_column;
        for (text, 0..) |_, byte_index| {
            if (column >= column_count) break;
            _ = self.put(row_index, column, text[byte_index .. byte_index + 1], 1, style);
            column += 1;
        }
        return column;
    }

    pub fn clearRow(self: *Screen, row_index: usize) void {
        if (row_index >= row_count) return;
        @memset(&self.cells[row_index], .{});
        self.generation +|= 1;
    }

    fn clearOccupant(self: *Screen, row_index: usize, column: usize) void {
        const current = self.cells[row_index][column];
        if (current.continuation and column > 0) {
            self.cells[row_index][column - 1] = .{};
        } else if (current.width == 2 and column + 1 < column_count) {
            self.cells[row_index][column + 1] = .{};
        }
        self.cells[row_index][column] = .{};
    }
};

pub const Writer = struct {
    screen: *Screen,
    first_row: usize,
    last_row: usize,
    row_index: usize,
    column: usize = 0,

    pub fn init(screen: *Screen, first_row: usize, last_row: usize) Writer {
        std.debug.assert(first_row <= last_row and last_row < row_count);
        return .{
            .screen = screen,
            .first_row = first_row,
            .last_row = last_row,
            .row_index = first_row,
        };
    }

    pub fn reset(self: *Writer) void {
        for (self.first_row..self.last_row + 1) |row_index| {
            self.screen.clearRow(row_index);
        }
        self.row_index = self.first_row;
        self.column = 0;
    }

    pub fn newline(self: *Writer) void {
        self.row_index += 1;
        self.column = 0;
        if (self.row_index > self.last_row) self.scroll();
    }

    pub fn put(self: *Writer, text: []const u8, width: u2, style: Style) void {
        if (width == 0 or width > 2) return;
        if (self.column + width > column_count) self.newline();
        if (self.screen.put(self.row_index, self.column, text, width, style)) {
            self.column += width;
        }
    }

    pub fn writeAscii(self: *Writer, text: []const u8, style: Style) void {
        for (text, 0..) |_, byte_index| self.put(text[byte_index .. byte_index + 1], 1, style);
    }

    pub fn writeUtf8Scalars(self: *Writer, text: []const u8, style: Style) !void {
        var offset: usize = 0;
        while (offset < text.len) {
            const len = try std.unicode.utf8ByteSequenceLength(text[offset]);
            if (offset + len > text.len) return error.InvalidUtf8;
            _ = try std.unicode.utf8Decode(text[offset..][0..len]);
            self.put(text[offset..][0..len], 1, style);
            offset += len;
        }
    }

    fn scroll(self: *Writer) void {
        for (self.first_row..self.last_row) |row_index| {
            self.screen.cells[row_index] = self.screen.cells[row_index + 1];
        }
        self.screen.clearRow(self.last_row);
        self.row_index = self.last_row;
    }
};

test "wide cells reserve a continuation column" {
    var screen: Screen = .{};
    try std.testing.expect(screen.put(0, 3, "🌍", 2, .accent));
    try std.testing.expect(screen.cells[0][3].isLead());
    try std.testing.expectEqual(@as(u2, 2), screen.cells[0][3].width);
    try std.testing.expect(screen.cells[0][4].continuation);
}

test "writer wraps and scrolls within its row region" {
    var screen: Screen = .{};
    var writer = Writer.init(&screen, 1, 2);
    writer.column = column_count - 1;
    writer.put("x", 1, .normal);
    writer.put("y", 1, .normal);
    try std.testing.expectEqual(@as(usize, 2), writer.row_index);
    try std.testing.expectEqualStrings("y", screen.cells[2][0].text);

    writer.newline();
    try std.testing.expectEqual(@as(usize, 2), writer.row_index);
    try std.testing.expectEqualStrings("y", screen.cells[1][0].text);
    try std.testing.expect(!screen.cells[2][0].isLead());
}

test "overwriting either half clears a wide occupant" {
    var screen: Screen = .{};
    try std.testing.expect(screen.put(0, 4, "🚀", 2, .accent));
    try std.testing.expect(screen.put(0, 5, "x", 1, .normal));
    try std.testing.expect(!screen.cells[0][4].isLead());
    try std.testing.expectEqualStrings("x", screen.cells[0][5].text);
}

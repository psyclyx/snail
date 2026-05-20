const std = @import("std");

const File = struct {
    path: []const u8,
};

const Signature = struct {
    name: []const u8,
    return_kind: ReturnKind,
    param_count: usize,
};

const ReturnKind = enum {
    void,
    int,
    bool,
    size,
    u32,
    u16,
    i16,
    f32,
    string,
    resource_key,
    mat4,
    pointer,
    vulkan_handle,
    other,
};

const sources = [_]File{
    .{ .path = "src/snail/c_api/constants.zig" },
    .{ .path = "src/snail/c_api/font.zig" },
    .{ .path = "src/snail/c_api/image.zig" },
    .{ .path = "src/snail/c_api/misc.zig" },
    .{ .path = "src/snail/c_api/path.zig" },
    .{ .path = "src/snail/c_api/render.zig" },
    .{ .path = "src/snail/c_api/render_backends.zig" },
    .{ .path = "src/snail/c_api/resources.zig" },
    .{ .path = "src/snail/c_api/scene.zig" },
    .{ .path = "src/snail/c_api/shaders.zig" },
    .{ .path = "src/snail/c_api/text.zig" },
};

const headers = [_]File{
    .{ .path = "include/snail.h" },
    .{ .path = "include/snail_cpu.h" },
    .{ .path = "include/snail_gl.h" },
    .{ .path = "include/snail_gles.h" },
    .{ .path = "include/snail_vulkan.h" },
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const all_headers = try loadHeaders(init.io, arena);
    var header_signatures = std.StringHashMap(Signature).init(arena);
    try parseHeaderPrototypes(all_headers, &header_signatures);
    var export_signatures = std.StringHashMap(Signature).init(arena);

    var mismatch = false;
    for (sources) |source| {
        const contents = try readFile(init.io, arena, source.path);
        var exports = std.ArrayList(Signature).empty;
        try parseZigExports(arena, contents, &exports);
        for (exports.items) |exported| {
            try export_signatures.put(exported.name, exported);
            const header = header_signatures.get(exported.name) orelse {
                std.debug.print("{s}: exported {s} is missing from public headers\n", .{ source.path, exported.name });
                mismatch = true;
                continue;
            };
            if (header.param_count != exported.param_count) {
                std.debug.print("{s}: exported {s} has {d} parameters, header declares {d}\n", .{
                    source.path,
                    exported.name,
                    exported.param_count,
                    header.param_count,
                });
                mismatch = true;
            }
            if (header.return_kind != exported.return_kind) {
                std.debug.print("{s}: exported {s} has return kind {t}, header declares {t}\n", .{
                    source.path,
                    exported.name,
                    exported.return_kind,
                    header.return_kind,
                });
                mismatch = true;
            }
        }
    }

    var header_it = header_signatures.valueIterator();
    while (header_it.next()) |header| {
        if (!export_signatures.contains(header.name)) {
            std.debug.print("public header declares {s}, but no Zig export exists\n", .{header.name});
            mismatch = true;
        }
    }

    if (mismatch) return error.CApiHeaderMismatch;
}

fn loadHeaders(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    for (headers) |header| {
        const contents = try readFile(io, allocator, header.path);
        try writer.writeAll(contents);
        try writer.writeAll("\n");
    }
    return out.toOwnedSlice();
}

fn readFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 20));
}

fn parseZigExports(allocator: std.mem.Allocator, contents: []const u8, out: *std.ArrayList(Signature)) !void {
    const prefix = "pub export fn ";
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, contents, cursor, "pub export fn snail_")) |offset| {
        const start = offset + prefix.len;
        const tail = contents[start..];
        const name_end = std.mem.indexOfScalar(u8, tail, '(') orelse return error.InvalidExportSignature;
        const name = std.mem.trim(u8, tail[0..name_end], " \n\r\t");
        const params_start = start + name_end;
        const params_end = findMatchingParen(contents, params_start) orelse return error.InvalidExportSignature;
        const body_start = std.mem.indexOfScalarPos(u8, contents, params_end + 1, '{') orelse return error.InvalidExportSignature;
        try out.append(allocator, .{
            .name = name,
            .return_kind = zigReturnKind(std.mem.trim(u8, contents[params_end + 1 .. body_start], " \n\r\t")),
            .param_count = countParams(contents[params_start + 1 .. params_end]),
        });
        cursor = body_start + 1;
    }
}

fn parseHeaderPrototypes(header_blob: []const u8, out: *std.StringHashMap(Signature)) !void {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, header_blob, cursor, "snail_")) |name_start| {
        var name_end = name_start;
        while (name_end < header_blob.len and isIdent(header_blob[name_end])) : (name_end += 1) {}
        var paren = name_end;
        while (paren < header_blob.len and std.ascii.isWhitespace(header_blob[paren])) : (paren += 1) {}
        if (paren >= header_blob.len or header_blob[paren] != '(') {
            cursor = name_end;
            continue;
        }
        const close = findMatchingParen(header_blob, paren) orelse return error.InvalidHeaderSignature;
        var semi = close + 1;
        while (semi < header_blob.len and std.ascii.isWhitespace(header_blob[semi])) : (semi += 1) {}
        if (semi >= header_blob.len or header_blob[semi] != ';') {
            cursor = close + 1;
            continue;
        }
        const name = header_blob[name_start..name_end];
        const return_start = lastLineStart(header_blob, name_start);
        const return_type = std.mem.trim(u8, header_blob[return_start..name_start], " \n\r\t");
        const sig = Signature{
            .name = name,
            .return_kind = headerReturnKind(return_type),
            .param_count = countParams(header_blob[paren + 1 .. close]),
        };
        const result = try out.getOrPut(name);
        if (result.found_existing and (result.value_ptr.param_count != sig.param_count or result.value_ptr.return_kind != sig.return_kind)) {
            std.debug.print("conflicting public header declarations for {s}\n", .{name});
            return error.CApiHeaderMismatch;
        }
        result.value_ptr.* = sig;
        cursor = semi + 1;
    }
}

fn lastLineStart(bytes: []const u8, before: usize) usize {
    var i = before;
    while (i > 0) {
        if (bytes[i - 1] == '\n') return i;
        i -= 1;
    }
    return 0;
}

fn findMatchingParen(bytes: []const u8, open_index: usize) ?usize {
    std.debug.assert(bytes[open_index] == '(');
    var depth: usize = 0;
    var i = open_index;
    while (i < bytes.len) : (i += 1) {
        switch (bytes[i]) {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return null;
}

fn countParams(params: []const u8) usize {
    const trimmed = std.mem.trim(u8, params, " \n\r\t");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "void")) return 0;

    var count: usize = 0;
    var param_start: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    for (trimmed, 0..) |c, i| switch (c) {
        '(' => paren_depth += 1,
        ')' => paren_depth -= 1,
        '[' => bracket_depth += 1,
        ']' => bracket_depth -= 1,
        ',' => {
            if (paren_depth == 0 and bracket_depth == 0) {
                if (std.mem.trim(u8, trimmed[param_start..i], " \n\r\t").len != 0) count += 1;
                param_start = i + 1;
            }
        },
        else => {},
    };
    if (std.mem.trim(u8, trimmed[param_start..], " \n\r\t").len != 0) count += 1;
    return count;
}

fn zigReturnKind(return_type: []const u8) ReturnKind {
    if (std.mem.eql(u8, return_type, "void")) return .void;
    if (std.mem.eql(u8, return_type, "c_int")) return .int;
    if (std.mem.eql(u8, return_type, "bool")) return .bool;
    if (std.mem.eql(u8, return_type, "usize")) return .size;
    if (std.mem.eql(u8, return_type, "u32")) return .u32;
    if (std.mem.eql(u8, return_type, "u16")) return .u16;
    if (std.mem.eql(u8, return_type, "i16")) return .i16;
    if (std.mem.eql(u8, return_type, "f32")) return .f32;
    if (std.mem.eql(u8, return_type, "SnailString")) return .string;
    if (std.mem.eql(u8, return_type, "SnailResourceKey")) return .resource_key;
    if (std.mem.eql(u8, return_type, "SnailMat4")) return .mat4;
    if (std.mem.startsWith(u8, return_type, "?[*]") or std.mem.startsWith(u8, return_type, "[*:")) return .pointer;
    if (std.mem.startsWith(u8, return_type, "vk.Vk")) return .vulkan_handle;
    return .other;
}

fn headerReturnKind(return_type: []const u8) ReturnKind {
    if (std.mem.eql(u8, return_type, "void")) return .void;
    if (std.mem.eql(u8, return_type, "int")) return .int;
    if (std.mem.eql(u8, return_type, "bool")) return .bool;
    if (std.mem.eql(u8, return_type, "size_t")) return .size;
    if (std.mem.eql(u8, return_type, "uint32_t")) return .u32;
    if (std.mem.eql(u8, return_type, "uint16_t")) return .u16;
    if (std.mem.eql(u8, return_type, "int16_t")) return .i16;
    if (std.mem.eql(u8, return_type, "float")) return .f32;
    if (std.mem.eql(u8, return_type, "SnailString")) return .string;
    if (std.mem.eql(u8, return_type, "SnailResourceKey")) return .resource_key;
    if (std.mem.eql(u8, return_type, "SnailMat4")) return .mat4;
    if (std.mem.endsWith(u8, return_type, "*")) return .pointer;
    if (std.mem.startsWith(u8, return_type, "Vk")) return .vulkan_handle;
    return .other;
}

fn isIdent(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

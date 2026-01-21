const std = @import("std");
const proto = @import("proto.zig");

pub const TreeEntry = struct {
    path: []const u8,
    hash: []const u8,
};

pub const TreeResponse = struct {
    tree_hash: []const u8,
    entries: []TreeEntry,
};

pub const PathResponse = struct {
    content: []const u8,
    blob_hash: []const u8,
};

pub const BlameLine = struct {
    line_number: u32,
    text: []const u8,
    session_id: []const u8,
    author_handle: []const u8,
    landed_at: []const u8,
};

pub const BlameResponse = struct {
    lines: []BlameLine,
};

pub fn encodeGetHeadTreeRequest(
    allocator: std.mem.Allocator,
    account: []const u8,
    project: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try proto.encodeStringField(&buf.writer, 2, account);
    try proto.encodeStringField(&buf.writer, 3, project);

    return buf.toOwnedSlice();
}

pub fn encodeGetTreeRequest(
    allocator: std.mem.Allocator,
    account: []const u8,
    project: []const u8,
    tree_hash: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try proto.encodeStringField(&buf.writer, 2, account);
    try proto.encodeStringField(&buf.writer, 3, project);
    try proto.encodeBytesField(&buf.writer, 4, tree_hash);

    return buf.toOwnedSlice();
}

pub fn encodeGetBlobRequest(
    allocator: std.mem.Allocator,
    account: []const u8,
    project: []const u8,
    blob_hash: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try proto.encodeStringField(&buf.writer, 2, account);
    try proto.encodeStringField(&buf.writer, 3, project);
    try proto.encodeBytesField(&buf.writer, 4, blob_hash);

    return buf.toOwnedSlice();
}

pub fn encodeGetPathRequest(
    allocator: std.mem.Allocator,
    account: []const u8,
    project: []const u8,
    path: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try proto.encodeStringField(&buf.writer, 2, account);
    try proto.encodeStringField(&buf.writer, 3, project);
    try proto.encodeStringField(&buf.writer, 4, path);

    return buf.toOwnedSlice();
}

pub fn encodeGetTreeAtPositionRequest(
    allocator: std.mem.Allocator,
    account: []const u8,
    project: []const u8,
    position: u64,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try proto.encodeStringField(&buf.writer, 2, account);
    try proto.encodeStringField(&buf.writer, 3, project);
    try proto.encodeVarintField(&buf.writer, 4, position);

    return buf.toOwnedSlice();
}

pub fn encodeGetBlameRequest(
    allocator: std.mem.Allocator,
    account: []const u8,
    project: []const u8,
    path: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try proto.encodeStringField(&buf.writer, 2, account);
    try proto.encodeStringField(&buf.writer, 3, project);
    try proto.encodeStringField(&buf.writer, 4, path);

    return buf.toOwnedSlice();
}

pub fn decodeTreeResponse(allocator: std.mem.Allocator, data: []const u8) !TreeResponse {
    var decoder = proto.Decoder.init(data);
    var tree_hash: []const u8 = &[_]u8{};
    var entries: std.ArrayList(TreeEntry) = .empty;
    defer {
        if (@errorReturnTrace() != null) entries.deinit(allocator);
    }

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                const tree_bytes = try decoder.readBytes(allocator);
                const tree_entries = try decodeTreeEntries(allocator, tree_bytes);
                for (tree_entries) |entry| {
                    try entries.append(allocator, entry);
                }
            },
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                tree_hash = try decoder.readBytes(allocator);
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{ .tree_hash = tree_hash, .entries = try entries.toOwnedSlice(allocator) };
}

pub fn decodeBlobResponse(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    var decoder = proto.Decoder.init(data);
    var content: []const u8 = &[_]u8{};

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                content = try decoder.readBytes(allocator);
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return content;
}

pub fn decodePathResponse(allocator: std.mem.Allocator, data: []const u8) !PathResponse {
    var decoder = proto.Decoder.init(data);
    var content: []const u8 = &[_]u8{};
    var blob_hash: []const u8 = &[_]u8{};

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                content = try decoder.readBytes(allocator);
            },
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                blob_hash = try decoder.readBytes(allocator);
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{ .content = content, .blob_hash = blob_hash };
}

pub fn decodeBlameResponse(allocator: std.mem.Allocator, data: []const u8) !BlameResponse {
    var decoder = proto.Decoder.init(data);
    var lines: std.ArrayList(BlameLine) = .empty;
    defer {
        if (@errorReturnTrace() != null) lines.deinit(allocator);
    }

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        if (field_number != 1 or wire_type != .length_delimited) {
            try decoder.skipField(wire_type);
            continue;
        }

        const line_bytes = try decoder.readBytes(allocator);
        const line = try decodeBlameLine(allocator, line_bytes);
        try lines.append(allocator, line);
    }

    return .{ .lines = try lines.toOwnedSlice(allocator) };
}

fn decodeTreeEntries(allocator: std.mem.Allocator, data: []const u8) ![]TreeEntry {
    var decoder = proto.Decoder.init(data);
    var entries: std.ArrayList(TreeEntry) = .empty;
    defer {
        if (@errorReturnTrace() != null) entries.deinit(allocator);
    }

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        if (field_number != 1 or wire_type != .length_delimited) {
            try decoder.skipField(wire_type);
            continue;
        }

        const entry_bytes = try decoder.readBytes(allocator);
        const entry = try decodeTreeEntry(allocator, entry_bytes);
        try entries.append(allocator, entry);
    }

    return entries.toOwnedSlice(allocator);
}

fn decodeBlameLine(allocator: std.mem.Allocator, data: []const u8) !BlameLine {
    var decoder = proto.Decoder.init(data);
    var line_number: u32 = 0;
    var text: []const u8 = &[_]u8{};
    var session_id: []const u8 = &[_]u8{};
    var author_handle: []const u8 = &[_]u8{};
    var landed_at: []const u8 = &[_]u8{};

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            1 => {
                if (wire_type != .varint) return error.InvalidWireType;
                line_number = @intCast(try decoder.readVarint());
            },
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                text = try decoder.readBytes(allocator);
            },
            3 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                session_id = try decoder.readBytes(allocator);
            },
            4 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                author_handle = try decoder.readBytes(allocator);
            },
            5 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                landed_at = try decoder.readBytes(allocator);
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{
        .line_number = line_number,
        .text = text,
        .session_id = session_id,
        .author_handle = author_handle,
        .landed_at = landed_at,
    };
}

fn decodeTreeEntry(allocator: std.mem.Allocator, data: []const u8) !TreeEntry {
    var decoder = proto.Decoder.init(data);
    var path: []const u8 = &[_]u8{};
    var hash: []const u8 = &[_]u8{};

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                path = try decoder.readBytes(allocator);
            },
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                hash = try decoder.readBytes(allocator);
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{ .path = path, .hash = hash };
}

test "decode blame response" {
    const allocator = std.testing.allocator;

    const line_bytes = try encodeBlameLine(
        allocator,
        4,
        "hello",
        "session-123",
        "alice",
        "2024-01-01T00:00:00Z",
    );
    defer allocator.free(line_bytes);

    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try proto.encodeBytesField(&buf.writer, 1, line_bytes);
    const response_bytes = try buf.toOwnedSlice();
    defer allocator.free(response_bytes);

    const response = try decodeBlameResponse(allocator, response_bytes);
    defer {
        for (response.lines) |line| {
            allocator.free(line.text);
            allocator.free(line.session_id);
            allocator.free(line.author_handle);
            allocator.free(line.landed_at);
        }
        allocator.free(response.lines);
    }

    try std.testing.expectEqual(@as(usize, 1), response.lines.len);
    try std.testing.expectEqual(@as(u32, 4), response.lines[0].line_number);
    try std.testing.expectEqualStrings("hello", response.lines[0].text);
    try std.testing.expectEqualStrings("session-123", response.lines[0].session_id);
    try std.testing.expectEqualStrings("alice", response.lines[0].author_handle);
    try std.testing.expectEqualStrings("2024-01-01T00:00:00Z", response.lines[0].landed_at);
}

fn encodeBlameLine(
    allocator: std.mem.Allocator,
    line_number: u32,
    text: []const u8,
    session_id: []const u8,
    author_handle: []const u8,
    landed_at: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try proto.encodeVarintField(&buf.writer, 1, @as(u64, line_number));
    try proto.encodeStringField(&buf.writer, 2, text);
    try proto.encodeStringField(&buf.writer, 3, session_id);
    try proto.encodeStringField(&buf.writer, 4, author_handle);
    try proto.encodeStringField(&buf.writer, 5, landed_at);

    return buf.toOwnedSlice();
}

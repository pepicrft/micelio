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

pub fn decodeTreeResponse(allocator: std.mem.Allocator, data: []const u8) !TreeResponse {
    var decoder = proto.Decoder.init(data);
    var tree_hash: []const u8 = &[_]u8{};
    var entries = std.ArrayList(TreeEntry).init(allocator);
    defer {
        if (@errorReturnTrace() != null) entries.deinit();
    }

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@intCast(key & 0x07));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                const tree_bytes = try decoder.readBytes(allocator);
                const tree_entries = try decodeTreeEntries(allocator, tree_bytes);
                for (tree_entries) |entry| {
                    try entries.append(entry);
                }
            },
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                tree_hash = try decoder.readBytes(allocator);
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{ .tree_hash = tree_hash, .entries = try entries.toOwnedSlice() };
}

pub fn decodeBlobResponse(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var decoder = proto.Decoder.init(data);
    var content: []const u8 = &[_]u8{};

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@intCast(key & 0x07));

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
        const wire_type: proto.WireType = @enumFromInt(@intCast(key & 0x07));

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

fn decodeTreeEntries(allocator: std.mem.Allocator, data: []const u8) ![]TreeEntry {
    var decoder = proto.Decoder.init(data);
    var entries = std.ArrayList(TreeEntry).init(allocator);
    defer {
        if (@errorReturnTrace() != null) entries.deinit();
    }

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@intCast(key & 0x07));

        if (field_number != 1 or wire_type != .length_delimited) {
            try decoder.skipField(wire_type);
            continue;
        }

        const entry_bytes = try decoder.readBytes(allocator);
        const entry = try decodeTreeEntry(allocator, entry_bytes);
        try entries.append(entry);
    }

    return entries.toOwnedSlice();
}

fn decodeTreeEntry(allocator: std.mem.Allocator, data: []const u8) !TreeEntry {
    var decoder = proto.Decoder.init(data);
    var path: []const u8 = &[_]u8{};
    var hash: []const u8 = &[_]u8{};

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@intCast(key & 0x07));

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

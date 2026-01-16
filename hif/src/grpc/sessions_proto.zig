const std = @import("std");
const proto = @import("proto.zig");

pub const Session = struct {
    session_id: []const u8,
    goal: []const u8,
    organization_handle: []const u8,
    project_handle: []const u8,
    status: []const u8,
    started_at: []const u8,
    landed_at: []const u8,
    landing_position: u64,
};

pub fn encodeStartSessionRequest(
    allocator: std.mem.Allocator,
    organization: []const u8,
    project: []const u8,
    session_id: []const u8,
    goal: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 2, organization);
    try proto.encodeStringField(&buf.writer, 3, project);
    try proto.encodeStringField(&buf.writer, 4, session_id);
    try proto.encodeStringField(&buf.writer, 5, goal);
    return buf.toOwnedSlice();
}

pub const FileChange = struct {
    path: []const u8,
    content: []const u8,
    change_type: []const u8,
};

pub fn encodeLandSessionRequest(
    allocator: std.mem.Allocator,
    session_id: []const u8,
    files: []const FileChange,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 2, session_id);
    for (files) |change| {
        const entry = try encodeFileChange(allocator, change);
        defer allocator.free(entry);
        try proto.encodeBytesField(&buf.writer, 5, entry);
    }
    return buf.toOwnedSlice();
}

pub fn decodeSessionResponse(allocator: std.mem.Allocator, data: []const u8) !Session {
    var decoder = proto.Decoder.init(data);
    var session: ?Session = null;

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        if (field_number != 1 or wire_type != .length_delimited) {
            try decoder.skipField(wire_type);
            continue;
        }

        const session_bytes = try decoder.readBytes(allocator);
        session = try decodeSession(allocator, session_bytes);
    }

    return session orelse return error.EmptyResponse;
}

fn decodeSession(allocator: std.mem.Allocator, data: []const u8) !Session {
    var decoder = proto.Decoder.init(data);
    var session_id: []const u8 = &[_]u8{};
    var goal: []const u8 = &[_]u8{};
    var organization_handle: []const u8 = &[_]u8{};
    var project_handle: []const u8 = &[_]u8{};
    var status: []const u8 = &[_]u8{};
    var started_at: []const u8 = &[_]u8{};
    var landed_at: []const u8 = &[_]u8{};
    var landing_position: u64 = 0;

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                session_id = try decoder.readBytes(allocator);
            },
            3 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                goal = try decoder.readBytes(allocator);
            },
            4 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                organization_handle = try decoder.readBytes(allocator);
            },
            5 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                project_handle = try decoder.readBytes(allocator);
            },
            6 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                status = try decoder.readBytes(allocator);
            },
            9 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                started_at = try decoder.readBytes(allocator);
            },
            10 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                landed_at = try decoder.readBytes(allocator);
            },
            11 => {
                if (wire_type != .varint) return error.InvalidWireType;
                landing_position = try decoder.readVarint();
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{
        .session_id = session_id,
        .goal = goal,
        .organization_handle = organization_handle,
        .project_handle = project_handle,
        .status = status,
        .started_at = started_at,
        .landed_at = landed_at,
        .landing_position = landing_position,
    };
}

fn encodeFileChange(allocator: std.mem.Allocator, change: FileChange) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 1, change.path);
    try proto.encodeBytesField(&buf.writer, 2, change.content);
    try proto.encodeStringField(&buf.writer, 3, change.change_type);
    return buf.toOwnedSlice();
}

/// Encode ListSessionsRequest for gRPC call
/// ListSessionsRequest fields:
///   1: user_id (string)
///   2: organization_handle (string)
///   3: project_handle (string)
///   4: status (string) - filter: "landed", "active", "all"
pub fn encodeListSessionsRequest(
    allocator: std.mem.Allocator,
    organization: []const u8,
    project: []const u8,
    status_filter: ?[]const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 2, organization);
    try proto.encodeStringField(&buf.writer, 3, project);
    if (status_filter) |status| {
        try proto.encodeStringField(&buf.writer, 4, status);
    }
    return buf.toOwnedSlice();
}

/// Decode ListSessionsResponse - returns array of Sessions
/// ListSessionsResponse fields:
///   1: sessions (repeated Session)
pub fn decodeListSessionsResponse(allocator: std.mem.Allocator, data: []const u8) ![]Session {
    var decoder = proto.Decoder.init(data);
    var sessions: std.ArrayList(Session) = .empty;

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        if (field_number == 1 and wire_type == .length_delimited) {
            const session_bytes = try decoder.readBytes(allocator);
            const session = try decodeSession(allocator, session_bytes);
            try sessions.append(allocator, session);
        } else {
            try decoder.skipField(wire_type);
        }
    }

    return sessions.toOwnedSlice(allocator);
}

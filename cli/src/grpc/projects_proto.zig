const std = @import("std");
const proto = @import("proto.zig");

pub const Project = struct {
    id: []const u8,
    organization_handle: []const u8,
    handle: []const u8,
    name: []const u8,
    description: []const u8,
    inserted_at: []const u8,
    updated_at: []const u8,
};

pub const ListProjectsResponse = struct {
    projects: []Project,
};

pub fn encodeListProjectsRequest(
    allocator: std.mem.Allocator,
    organization: []const u8,
) ![]u8 {
    _ = allocator;
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 2, organization);
    return buf.toOwnedSlice();
}

pub fn encodeGetProjectRequest(
    allocator: std.mem.Allocator,
    organization: []const u8,
    handle: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 2, organization);
    try proto.encodeStringField(&buf.writer, 3, handle);
    return buf.toOwnedSlice();
}

pub fn encodeCreateProjectRequest(
    allocator: std.mem.Allocator,
    organization: []const u8,
    handle: []const u8,
    name: []const u8,
    description: ?[]const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 2, organization);
    try proto.encodeStringField(&buf.writer, 3, handle);
    try proto.encodeStringField(&buf.writer, 4, name);
    if (description) |value| {
        if (value.len > 0) {
            try proto.encodeStringField(&buf.writer, 5, value);
        }
    }
    return buf.toOwnedSlice();
}

pub fn encodeUpdateProjectRequest(
    allocator: std.mem.Allocator,
    organization: []const u8,
    handle: []const u8,
    name: ?[]const u8,
    description: ?[]const u8,
    new_handle: ?[]const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 2, organization);
    try proto.encodeStringField(&buf.writer, 3, handle);
    if (new_handle) |value| {
        if (value.len > 0) {
            try proto.encodeStringField(&buf.writer, 4, value);
        }
    }
    if (name) |value| {
        if (value.len > 0) {
            try proto.encodeStringField(&buf.writer, 5, value);
        }
    }
    if (description) |value| {
        if (value.len > 0) {
            try proto.encodeStringField(&buf.writer, 6, value);
        }
    }
    return buf.toOwnedSlice();
}

pub fn encodeDeleteProjectRequest(
    allocator: std.mem.Allocator,
    organization: []const u8,
    handle: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 2, organization);
    try proto.encodeStringField(&buf.writer, 3, handle);
    return buf.toOwnedSlice();
}

pub fn decodeListProjectsResponse(
    allocator: std.mem.Allocator,
    data: []const u8,
) !ListProjectsResponse {
    var decoder = proto.Decoder.init(data);
    var projects = std.ArrayList(Project).init(allocator);
    defer {
        if (@errorReturnTrace() != null) projects.deinit();
    }

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@intCast(key & 0x07));

        if (field_number != 1 or wire_type != .length_delimited) {
            try decoder.skipField(wire_type);
            continue;
        }

        const project_bytes = try decoder.readBytes(allocator);
        const project = try decodeProject(allocator, project_bytes);
        try projects.append(project);
    }

    return .{ .projects = try projects.toOwnedSlice() };
}

pub fn decodeProjectResponse(allocator: std.mem.Allocator, data: []const u8) !Project {
    var decoder = proto.Decoder.init(data);
    var project: ?Project = null;

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@intCast(key & 0x07));

        if (field_number != 1 or wire_type != .length_delimited) {
            try decoder.skipField(wire_type);
            continue;
        }

        const project_bytes = try decoder.readBytes(allocator);
        project = try decodeProject(allocator, project_bytes);
    }

    return project orelse return error.EmptyResponse;
}

pub fn decodeDeleteProjectResponse(data: []const u8) !bool {
    var decoder = proto.Decoder.init(data);
    var success = false;

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@intCast(key & 0x07));

        switch (field_number) {
            1 => {
                if (wire_type != .varint) return error.InvalidWireType;
                success = (try decoder.readVarint()) != 0;
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return success;
}

fn decodeProject(allocator: std.mem.Allocator, data: []const u8) !Project {
    var decoder = proto.Decoder.init(data);
    var id: []const u8 = &[_]u8{};
    var organization_handle: []const u8 = &[_]u8{};
    var handle: []const u8 = &[_]u8{};
    var name: []const u8 = &[_]u8{};
    var description: []const u8 = &[_]u8{};
    var inserted_at: []const u8 = &[_]u8{};
    var updated_at: []const u8 = &[_]u8{};

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@intCast(key & 0x07));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                id = try decoder.readBytes(allocator);
            },
            3 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                organization_handle = try decoder.readBytes(allocator);
            },
            4 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                handle = try decoder.readBytes(allocator);
            },
            5 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                name = try decoder.readBytes(allocator);
            },
            6 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                description = try decoder.readBytes(allocator);
            },
            7 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                inserted_at = try decoder.readBytes(allocator);
            },
            8 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                updated_at = try decoder.readBytes(allocator);
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{
        .id = id,
        .organization_handle = organization_handle,
        .handle = handle,
        .name = name,
        .description = description,
        .inserted_at = inserted_at,
        .updated_at = updated_at,
    };
}

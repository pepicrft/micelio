const std = @import("std");
const proto = @import("proto.zig");

pub const Organization = struct {
    id: []const u8,
    handle: []const u8,
    name: []const u8,
    description: []const u8,
    inserted_at: []const u8,
    updated_at: []const u8,
};

pub fn encodeListOrganizationsRequest(allocator: std.mem.Allocator) ![]u8 {
    // Empty request - user is determined from auth token
    _ = allocator;
    return &[_]u8{};
}

pub fn encodeGetOrganizationRequest(
    allocator: std.mem.Allocator,
    handle: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try proto.encodeStringField(&buf.writer, 2, handle);

    return buf.toOwnedSlice();
}

pub fn decodeListOrganizationsResponse(allocator: std.mem.Allocator, data: []const u8) ![]Organization {
    var decoder = proto.Decoder.init(data);
    var organizations: std.ArrayList(Organization) = .empty;
    defer {
        if (@errorReturnTrace() != null) organizations.deinit(allocator);
    }

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        if (field_number == 1 and wire_type == .length_delimited) {
            const org_bytes = try decoder.readBytes(allocator);
            const org = try decodeOrganization(allocator, org_bytes);
            try organizations.append(allocator, org);
        } else {
            try decoder.skipField(wire_type);
        }
    }

    return organizations.toOwnedSlice(allocator);
}

pub fn decodeOrganizationResponse(allocator: std.mem.Allocator, data: []const u8) !Organization {
    var decoder = proto.Decoder.init(data);
    var organization: ?Organization = null;

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        if (field_number == 1 and wire_type == .length_delimited) {
            const org_bytes = try decoder.readBytes(allocator);
            organization = try decodeOrganization(allocator, org_bytes);
        } else {
            try decoder.skipField(wire_type);
        }
    }

    return organization orelse error.EmptyResponse;
}

fn decodeOrganization(allocator: std.mem.Allocator, data: []const u8) !Organization {
    var decoder = proto.Decoder.init(data);
    var id: []const u8 = &[_]u8{};
    var handle: []const u8 = &[_]u8{};
    var name: []const u8 = &[_]u8{};
    var description: []const u8 = &[_]u8{};
    var inserted_at: []const u8 = &[_]u8{};
    var updated_at: []const u8 = &[_]u8{};

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                id = try decoder.readBytes(allocator);
            },
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                handle = try decoder.readBytes(allocator);
            },
            3 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                name = try decoder.readBytes(allocator);
            },
            4 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                description = try decoder.readBytes(allocator);
            },
            5 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                inserted_at = try decoder.readBytes(allocator);
            },
            6 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                updated_at = try decoder.readBytes(allocator);
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{
        .id = id,
        .handle = handle,
        .name = name,
        .description = description,
        .inserted_at = inserted_at,
        .updated_at = updated_at,
    };
}

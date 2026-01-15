const std = @import("std");
const proto = @import("proto.zig");

pub const DeviceClientRegistrationResponse = struct {
    client_id: []const u8,
    client_secret: []const u8,
};

pub const DeviceAuthorizationResponse = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    verification_uri_complete: []const u8,
    expires_in: u32,
    interval: u32,
};

pub const DeviceTokenResponse = struct {
    token_type: []const u8,
    access_token: []const u8,
    refresh_token: []const u8,
    expires_in: u32,
};

pub fn encodeDeviceClientRegistrationRequest(
    allocator: std.mem.Allocator,
    name: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    if (name.len > 0) {
        try proto.encodeStringField(&buf.writer, 1, name);
    }
    return buf.toOwnedSlice();
}

pub fn encodeDeviceAuthorizationRequest(
    allocator: std.mem.Allocator,
    client_id: []const u8,
    client_secret: []const u8,
    device_name: []const u8,
    scope: ?[]const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 1, client_id);
    try proto.encodeStringField(&buf.writer, 2, client_secret);
    if (device_name.len > 0) {
        try proto.encodeStringField(&buf.writer, 3, device_name);
    }
    if (scope) |value| {
        if (value.len > 0) {
            try proto.encodeStringField(&buf.writer, 4, value);
        }
    }
    return buf.toOwnedSlice();
}

pub fn encodeDeviceTokenRequest(
    allocator: std.mem.Allocator,
    client_id: []const u8,
    client_secret: []const u8,
    device_code: []const u8,
) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();
    try proto.encodeStringField(&buf.writer, 1, client_id);
    try proto.encodeStringField(&buf.writer, 2, client_secret);
    try proto.encodeStringField(&buf.writer, 3, device_code);
    return buf.toOwnedSlice();
}

pub fn decodeDeviceClientRegistrationResponse(
    allocator: std.mem.Allocator,
    data: []const u8,
) !DeviceClientRegistrationResponse {
    var decoder = proto.Decoder.init(data);
    var client_id: []const u8 = &[_]u8{};
    var client_secret: []const u8 = &[_]u8{};

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                client_id = try decoder.readBytes(allocator);
            },
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                client_secret = try decoder.readBytes(allocator);
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{ .client_id = client_id, .client_secret = client_secret };
}

pub fn decodeDeviceAuthorizationResponse(
    allocator: std.mem.Allocator,
    data: []const u8,
) !DeviceAuthorizationResponse {
    var decoder = proto.Decoder.init(data);
    var device_code: []const u8 = &[_]u8{};
    var user_code: []const u8 = &[_]u8{};
    var verification_uri: []const u8 = &[_]u8{};
    var verification_uri_complete: []const u8 = &[_]u8{};
    var expires_in: u32 = 0;
    var interval: u32 = 0;

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                device_code = try decoder.readBytes(allocator);
            },
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                user_code = try decoder.readBytes(allocator);
            },
            3 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                verification_uri = try decoder.readBytes(allocator);
            },
            4 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                verification_uri_complete = try decoder.readBytes(allocator);
            },
            5 => {
                if (wire_type != .varint) return error.InvalidWireType;
                expires_in = @intCast(try decoder.readVarint());
            },
            6 => {
                if (wire_type != .varint) return error.InvalidWireType;
                interval = @intCast(try decoder.readVarint());
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{
        .device_code = device_code,
        .user_code = user_code,
        .verification_uri = verification_uri,
        .verification_uri_complete = verification_uri_complete,
        .expires_in = expires_in,
        .interval = interval,
    };
}

pub fn decodeDeviceTokenResponse(
    allocator: std.mem.Allocator,
    data: []const u8,
) !DeviceTokenResponse {
    var decoder = proto.Decoder.init(data);
    var token_type: []const u8 = &[_]u8{};
    var access_token: []const u8 = &[_]u8{};
    var refresh_token: []const u8 = &[_]u8{};
    var expires_in: u32 = 0;

    while (!decoder.eof()) {
        const key = try decoder.readVarint();
        const field_number: u32 = @intCast(key >> 3);
        const wire_type: proto.WireType = @enumFromInt(@as(u3, @intCast(key & 0x07)));

        switch (field_number) {
            1 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                token_type = try decoder.readBytes(allocator);
            },
            2 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                access_token = try decoder.readBytes(allocator);
            },
            3 => {
                if (wire_type != .length_delimited) return error.InvalidWireType;
                refresh_token = try decoder.readBytes(allocator);
            },
            4 => {
                if (wire_type != .varint) return error.InvalidWireType;
                expires_in = @intCast(try decoder.readVarint());
            },
            else => try decoder.skipField(wire_type),
        }
    }

    return .{
        .token_type = token_type,
        .access_token = access_token,
        .refresh_token = refresh_token,
        .expires_in = expires_in,
    };
}

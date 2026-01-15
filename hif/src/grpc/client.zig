const std = @import("std");
const grpc_endpoint = @import("endpoint.zig");

const c = @cImport({
    @cInclude("grpc/client.h");
});

pub const Response = struct {
    bytes: []u8,
};

pub const CallResult = union(enum) {
    ok: Response,
    err: []u8,
};

pub fn unaryCall(
    allocator: std.mem.Allocator,
    endpoint: grpc_endpoint.Endpoint,
    method: []const u8,
    request: []const u8,
    auth_token: ?[]const u8,
) !Response {
    const result = try unaryCallResult(allocator, endpoint, method, request, auth_token);

    switch (result) {
        .ok => |response| return response,
        .err => |message| {
            defer allocator.free(message);
            std.debug.print("gRPC error: {s}\n", .{message});
            return error.RequestFailed;
        },
    }
}

pub fn unaryCallResult(
    allocator: std.mem.Allocator,
    endpoint: grpc_endpoint.Endpoint,
    method: []const u8,
    request: []const u8,
    auth_token: ?[]const u8,
) !CallResult {
    var response_ptr: [*c]u8 = null;
    var response_len: usize = 0;
    var error_ptr: [*c]u8 = null;

    const target_z = try toNullTerminated(allocator, endpoint.target);
    defer allocator.free(target_z);
    const host_z = try toNullTerminated(allocator, endpoint.host);
    defer allocator.free(host_z);
    const method_z = try toNullTerminated(allocator, method);
    defer allocator.free(method_z);
    const token_z = if (auth_token) |token| try toNullTerminated(allocator, token) else null;
    defer if (token_z) |value| allocator.free(value);

    const rc = c.hif_grpc_unary_call(
        target_z.ptr,
        host_z.ptr,
        method_z.ptr,
        if (request.len > 0) request.ptr else null,
        request.len,
        if (token_z) |value| value.ptr else null,
        @intFromBool(endpoint.use_tls),
        &response_ptr,
        &response_len,
        &error_ptr,
    );

    defer if (error_ptr != null) c.hif_grpc_free(error_ptr);

    if (rc != 0) {
        const message = if (error_ptr != null) std.mem.span(error_ptr) else "gRPC call failed";
        return .{ .err = try allocator.dupe(u8, message) };
    }

    if (response_ptr == null or response_len == 0) {
        return error.EmptyResponse;
    }

    const bytes = try allocator.dupe(u8, response_ptr[0..response_len]);
    c.hif_grpc_free(response_ptr);

    return .{ .ok = .{ .bytes = bytes } };
}

fn toNullTerminated(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var buf = try allocator.alloc(u8, value.len + 1);
    @memcpy(buf[0..value.len], value);
    buf[value.len] = 0;
    return buf;
}

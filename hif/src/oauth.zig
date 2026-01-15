const std = @import("std");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const auth_proto = @import("grpc/auth_proto.zig");
const xdg = @import("xdg.zig");

pub const default_server = "http://localhost:50051";
const credentials_filename = "credentials.json";

const DeviceClientRegistration = struct {
    client_id: []const u8,
    client_secret: []const u8,
};

const DeviceAuthResponse = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    verification_uri_complete: []const u8,
    expires_in: i64,
    interval: i64,
};

const TokenResponse = struct {
    token_type: []const u8,
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    expires_in: ?i64 = null,
};

const Credentials = struct {
    server: []const u8,
    client_id: []const u8,
    client_secret: []const u8,
    access_token: ?[]const u8 = null,
    refresh_token: ?[]const u8 = null,
    expires_at: ?i64 = null,
    token_type: ?[]const u8 = null,
};

pub fn login(allocator: std.mem.Allocator, server: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const registration = try ensureClientRegistration(arena_alloc, endpoint, server);
    const auth = try requestDeviceAuthorization(arena_alloc, endpoint, registration);

    std.debug.print("Authorize this device at {s}\nCode: {s}\n", .{ auth.verification_uri_complete, auth.user_code });
    std.debug.print("Waiting for authorization...\n", .{});

    const token = try pollForToken(arena_alloc, endpoint, registration, auth);

    const credentials = Credentials{
        .server = server,
        .client_id = registration.client_id,
        .client_secret = registration.client_secret,
        .access_token = token.access_token,
        .refresh_token = token.refresh_token,
        .expires_at = tokenExpiresAt(token.expires_in),
        .token_type = token.token_type,
    };

    try storeCredentials(allocator, credentials);
    std.debug.print("Authenticated.\n", .{});
}

pub fn status(allocator: std.mem.Allocator, server: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try readCredentials(arena_alloc);
    if (creds == null) {
        std.debug.print("Not logged in.\n", .{});
        return;
    }

    const value = creds.?;
    if (!std.mem.eql(u8, value.server, server)) {
        std.debug.print("Credentials are for {s}.\n", .{value.server});
        return;
    }

    if (value.access_token == null) {
        std.debug.print("No access token available.\n", .{});
        return;
    }

    if (value.expires_at) |expires_at| {
        const now = std.time.timestamp();
        if (now >= expires_at) {
            std.debug.print("Access token expired.\n", .{});
            return;
        }
    }

    std.debug.print("Authenticated as device client {s}.\n", .{value.client_id});
}

pub fn logout(allocator: std.mem.Allocator) !void {
    const path = try credentialsPath(allocator);
    defer allocator.free(path);

    try xdg.deleteFile(path);
    std.debug.print("Logged out.\n", .{});
}

fn ensureClientRegistration(
    allocator: std.mem.Allocator,
    endpoint: grpc_endpoint.Endpoint,
    server: []const u8,
) !DeviceClientRegistration {
    const existing = try readCredentials(allocator);
    if (existing) |value| {
        if (std.mem.eql(u8, value.server, server)) {
            return DeviceClientRegistration{
                .client_id = value.client_id,
                .client_secret = value.client_secret,
            };
        }
    }

    return try registerDeviceClient(allocator, endpoint);
}

fn registerDeviceClient(
    allocator: std.mem.Allocator,
    endpoint: grpc_endpoint.Endpoint,
) !DeviceClientRegistration {
    const request = try auth_proto.encodeDeviceClientRegistrationRequest(allocator, "hif");
    defer allocator.free(request);

    const response = try grpc_client.unaryCall(
        allocator,
        endpoint,
        "/micelio.auth.v1.DeviceAuthService/RegisterDevice",
        request,
        null,
    );
    defer allocator.free(response.bytes);

    const registration = try auth_proto.decodeDeviceClientRegistrationResponse(allocator, response.bytes);

    return DeviceClientRegistration{
        .client_id = registration.client_id,
        .client_secret = registration.client_secret,
    };
}

fn requestDeviceAuthorization(
    allocator: std.mem.Allocator,
    endpoint: grpc_endpoint.Endpoint,
    registration: DeviceClientRegistration,
) !DeviceAuthResponse {
    const device_name = try deviceName(allocator);
    const request = try auth_proto.encodeDeviceAuthorizationRequest(
        allocator,
        registration.client_id,
        registration.client_secret,
        device_name,
        null,
    );
    defer allocator.free(request);

    const response = try grpc_client.unaryCall(
        allocator,
        endpoint,
        "/micelio.auth.v1.DeviceAuthService/StartDeviceAuthorization",
        request,
        null,
    );
    defer allocator.free(response.bytes);

    const auth = try auth_proto.decodeDeviceAuthorizationResponse(allocator, response.bytes);

    return .{
        .device_code = auth.device_code,
        .user_code = auth.user_code,
        .verification_uri = auth.verification_uri,
        .verification_uri_complete = auth.verification_uri_complete,
        .expires_in = auth.expires_in,
        .interval = auth.interval,
    };
}

fn pollForToken(
    allocator: std.mem.Allocator,
    endpoint: grpc_endpoint.Endpoint,
    registration: DeviceClientRegistration,
    auth: DeviceAuthResponse,
) !TokenResponse {
    var interval = auth.interval;
    const deadline = std.time.timestamp() + auth.expires_in;

    while (true) {
        if (std.time.timestamp() >= deadline) return error.DeviceCodeExpired;

        const request = try auth_proto.encodeDeviceTokenRequest(
            allocator,
            registration.client_id,
            registration.client_secret,
            auth.device_code,
        );
        defer allocator.free(request);

        const result = try grpc_client.unaryCallResult(
            allocator,
            endpoint,
            "/micelio.auth.v1.DeviceAuthService/ExchangeDeviceCode",
            request,
            null,
        );

        switch (result) {
            .ok => |response| {
                defer allocator.free(response.bytes);
                const token = try auth_proto.decodeDeviceTokenResponse(allocator, response.bytes);
                return .{
                    .token_type = token.token_type,
                    .access_token = token.access_token,
                    .refresh_token = if (token.refresh_token.len > 0) token.refresh_token else null,
                    .expires_in = @intCast(token.expires_in),
                };
            },
            .err => |message| {
                defer allocator.free(message);
                if (std.mem.eql(u8, message, "authorization_pending")) {
                    try sleepSeconds(interval);
                    continue;
                }
                if (std.mem.eql(u8, message, "slow_down")) {
                    interval += 5;
                    try sleepSeconds(interval);
                    continue;
                }
                if (std.mem.eql(u8, message, "expired_token")) {
                    return error.DeviceCodeExpired;
                }
                return error.AuthorizationFailed;
            },
        }
    }
}

fn tokenExpiresAt(expires_in: ?i64) ?i64 {
    if (expires_in) |ttl| {
        return std.time.timestamp() + ttl;
    }
    return null;
}

fn sleepSeconds(seconds: i64) !void {
    if (seconds <= 0) return;
    const nanos = try std.math.mul(i64, seconds, std.time.ns_per_s);
    const nanos_u64: u64 = @intCast(nanos);
    std.Thread.sleep(nanos_u64);
}

fn deviceName(allocator: std.mem.Allocator) ![]u8 {
    var name_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&name_buf) catch "device";
    return std.fmt.allocPrint(allocator, "hif@{s}", .{hostname});
}

fn credentialsPath(allocator: std.mem.Allocator) ![]u8 {
    return xdg.credentialsFilePath(allocator, credentials_filename);
}

pub fn readCredentials(allocator: std.mem.Allocator) !?Credentials {
    const path = try credentialsPath(allocator);
    defer allocator.free(path);

    const data = try xdg.readFileAlloc(allocator, path, 64 * 1024);
    if (data == null) return null;
    // Note: Don't free data - parseFromSliceLeaky returns slices that reference it

    return try std.json.parseFromSliceLeaky(Credentials, allocator, data.?, .{ .ignore_unknown_fields = true });
}

fn storeCredentials(allocator: std.mem.Allocator, credentials: Credentials) !void {
    var payload_buf = std.Io.Writer.Allocating.init(allocator);
    defer payload_buf.deinit();
    const formatter = std.json.fmt(credentials, .{});
    try formatter.format(&payload_buf.writer);
    const payload = try payload_buf.toOwnedSlice();
    defer allocator.free(payload);

    const path = try credentialsPath(allocator);
    defer allocator.free(path);

    try xdg.writeSecretFile(path, payload);
}

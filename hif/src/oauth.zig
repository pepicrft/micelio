const std = @import("std");
const http = @import("http.zig");
const xdg = @import("xdg.zig");

pub const default_server = "http://localhost:4000";
const credentials_filename = "credentials.json";
const device_grant_type = "urn:ietf:params:oauth:grant-type:device_code";

const DeviceClientRegistration = struct {
    client_id: []const u8,
    client_secret: []const u8,
    device_authorization_endpoint: []const u8,
    token_endpoint: []const u8,
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

const ErrorResponse = struct {
    @"error": []const u8,
    error_description: ?[]const u8 = null,
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

    var client = std.http.Client{ .allocator = arena_alloc };
    defer client.deinit();

    const registration = try ensureClientRegistration(arena_alloc, &client, server);
    const auth = try requestDeviceAuthorization(arena_alloc, &client, registration);

    std.debug.print("Authorize this device at {s}\nCode: {s}\n", .{ auth.verification_uri_complete, auth.user_code });
    std.debug.print("Waiting for authorization...\n", .{});

    const token = try pollForToken(arena_alloc, &client, registration, auth);

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
    client: *std.http.Client,
    server: []const u8,
) !DeviceClientRegistration {
    const existing = try readCredentials(allocator);
    if (existing) |value| {
        if (std.mem.eql(u8, value.server, server)) {
            return DeviceClientRegistration{
                .client_id = value.client_id,
                .client_secret = value.client_secret,
                .device_authorization_endpoint = try std.fmt.allocPrint(allocator, "{s}/api/device/auth", .{server}),
                .token_endpoint = try std.fmt.allocPrint(allocator, "{s}/api/device/token", .{server}),
            };
        }
    }

    return try registerDeviceClient(allocator, client, server);
}

fn registerDeviceClient(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    server: []const u8,
) !DeviceClientRegistration {
    const url = try std.fmt.allocPrint(allocator, "{s}/api/device/client", .{server});
    defer allocator.free(url);

    const payload_struct = struct {
        name: []const u8,
    }{ .name = "hif" };

    var payload_buf = std.Io.Writer.Allocating.init(allocator);
    defer payload_buf.deinit();
    const formatter = std.json.fmt(payload_struct, .{});
    try formatter.format(&payload_buf.writer);
    const payload = try payload_buf.toOwnedSlice();
    defer allocator.free(payload);

    const response = try http.postJson(allocator, client, url, payload);
    
    if (response.status != .ok and response.status != .created) {
        return error.UnexpectedStatus;
    }

    // Don't free response.body - parseFromSliceLeaky uses it directly
    return try std.json.parseFromSliceLeaky(DeviceClientRegistration, allocator, response.body, .{ .ignore_unknown_fields = true });
}

fn requestDeviceAuthorization(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    registration: DeviceClientRegistration,
) !DeviceAuthResponse {
    const device_name = try deviceName(allocator);
    const payload_struct = struct {
        client_id: []const u8,
        client_secret: []const u8,
        device_name: []const u8,
    }{
        .client_id = registration.client_id,
        .client_secret = registration.client_secret,
        .device_name = device_name,
    };

    var payload_buf = std.Io.Writer.Allocating.init(allocator);
    defer payload_buf.deinit();
    const formatter = std.json.fmt(payload_struct, .{});
    try formatter.format(&payload_buf.writer);
    const payload = try payload_buf.toOwnedSlice();
    defer allocator.free(payload);

    const response = try http.postJson(allocator, client, registration.device_authorization_endpoint, payload);

    if (response.status != .ok) {
        return error.UnexpectedStatus;
    }

    // Don't free response.body - parseFromSliceLeaky uses it directly
    return try std.json.parseFromSliceLeaky(DeviceAuthResponse, allocator, response.body, .{ .ignore_unknown_fields = true });
}

fn pollForToken(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    registration: DeviceClientRegistration,
    auth: DeviceAuthResponse,
) !TokenResponse {
    var interval = auth.interval;
    const deadline = std.time.timestamp() + auth.expires_in;

    while (true) {
        if (std.time.timestamp() >= deadline) return error.DeviceCodeExpired;

        const payload_struct = struct {
            grant_type: []const u8,
            device_code: []const u8,
            client_id: []const u8,
            client_secret: []const u8,
        }{
            .grant_type = device_grant_type,
            .device_code = auth.device_code,
            .client_id = registration.client_id,
            .client_secret = registration.client_secret,
        };

        var payload_buf = std.Io.Writer.Allocating.init(allocator);
        defer payload_buf.deinit();
        const formatter = std.json.fmt(payload_struct, .{});
        try formatter.format(&payload_buf.writer);
        const payload = try payload_buf.toOwnedSlice();
        defer allocator.free(payload);

        const response = try http.postJson(allocator, client, registration.token_endpoint, payload);

        if (response.status == .ok) {
            // Don't free response.body - parseFromSliceLeaky uses it directly
            return try std.json.parseFromSliceLeaky(TokenResponse, allocator, response.body, .{ .ignore_unknown_fields = true });
        }

        // Handle error responses (typically 400 Bad Request for OAuth2 errors)
        const parsed_error = std.json.parseFromSliceLeaky(ErrorResponse, allocator, response.body, .{ .ignore_unknown_fields = true }) catch |err| {
            std.debug.print("ERROR: Failed to parse error response (status={}, error={})\n", .{ response.status, err });
            std.debug.print("Response body: {s}\n", .{response.body});
            return error.UnexpectedStatus;
        };

        if (std.mem.eql(u8, parsed_error.@"error", "authorization_pending")) {
            try sleepSeconds(interval);
            continue;
        }

        if (std.mem.eql(u8, parsed_error.@"error", "slow_down")) {
            interval += 5;
            try sleepSeconds(interval);
            continue;
        }

        if (std.mem.eql(u8, parsed_error.@"error", "expired_token")) {
            return error.DeviceCodeExpired;
        }

        return error.AuthorizationFailed;
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

fn readCredentials(allocator: std.mem.Allocator) !?Credentials {
    const path = try credentialsPath(allocator);
    defer allocator.free(path);

    const data = try xdg.readFileAlloc(allocator, path, 64 * 1024);
    if (data == null) return null;
    defer allocator.free(data.?);

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

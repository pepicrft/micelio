const std = @import("std");
const http = @import("http.zig");
const config = @import("config.zig");

const FirstParty = struct {
    const client_id = "ad79f0f6-8dbd-4ced-b629-567e764d2379";
    const domain = "micelio.dev";
};

pub const DeviceTokens = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    token_type: []const u8,
    expires_at: ?i64 = null,
};

pub const StoredTokens = struct {
    server: []const u8,
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    token_type: []const u8,
    expires_at: ?i64 = null,
};

pub fn isFirstPartyWebUrl(web_url: []const u8) bool {
    const host = hostFromUrl(web_url) orelse return false;
    if (std.mem.eql(u8, host, FirstParty.domain)) return true;
    return std.mem.endsWith(u8, host, "." ++ FirstParty.domain);
}

pub fn firstPartyClientId() []const u8 {
    return FirstParty.client_id;
}

pub const AuthFlow = struct {
    allocator: std.mem.Allocator,
    web_url: []const u8,
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    verification_uri_complete: ?[]const u8 = null,
    interval: i64,
    expires_at: i64,

    pub fn start(
        allocator: std.mem.Allocator,
        web_url: []const u8,
        client_id: ?[]const u8,
    ) !AuthFlow {
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        const url = try std.fmt.allocPrint(allocator, "{s}/auth/device", .{web_url});
        defer allocator.free(url);

        const name = try deviceName(allocator);
        defer allocator.free(name);

        const payload = StartRequest{
            .device_name = name,
            .client_id = client_id,
        };
        const payload_bytes = try jsonEncode(allocator, payload);
        defer allocator.free(payload_bytes);

        const response = try http.postJson(allocator, &client, url, payload_bytes);
        defer allocator.free(response.body);

        if (response.status != .ok) {
            handleAuthError(allocator, response.body);
            return error.AuthorizationFailed;
        }

        const parsed = try std.json.parseFromSlice(StartResponse, allocator, response.body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        defer parsed.deinit();

        const auth_start = parsed.value;
        const expires_in = auth_start.expires_in orelse 900;
        var interval = auth_start.interval orelse 5;
        if (interval <= 0) interval = 5;

        return .{
            .allocator = allocator,
            .web_url = try allocator.dupe(u8, web_url),
            .device_code = try allocator.dupe(u8, auth_start.device_code),
            .user_code = try allocator.dupe(u8, auth_start.user_code),
            .verification_uri = try allocator.dupe(u8, auth_start.verification_uri),
            .verification_uri_complete = if (auth_start.verification_uri_complete) |uri|
                try allocator.dupe(u8, uri)
            else
                null,
            .interval = interval,
            .expires_at = std.time.timestamp() + expires_in,
        };
    }

    pub fn poll(self: *AuthFlow) !?DeviceTokens {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const url = try std.fmt.allocPrint(self.allocator, "{s}/auth/device", .{self.web_url});
        defer self.allocator.free(url);

        const payload = PollRequest{ .device_code = self.device_code };
        const payload_bytes = try jsonEncode(self.allocator, payload);
        defer self.allocator.free(payload_bytes);

        const response = try http.postJson(self.allocator, &client, url, payload_bytes);
        defer self.allocator.free(response.body);

        if (response.status == .ok) {
            std.debug.print("Token response: {s}\n", .{response.body});
            const parsed = try std.json.parseFromSlice(TokenResponse, self.allocator, response.body, .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            });
            defer parsed.deinit();
            return try tokensFromResponse(self.allocator, parsed.value);
        }

        if (response.status == .accepted) {
            return null;
        }

        const parsed_error = std.json.parseFromSlice(ErrorResponse, self.allocator, response.body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch return error.AuthorizationFailed;
        defer parsed_error.deinit();

        const err_code = parsed_error.value.code;
        if (std.mem.eql(u8, err_code, "authorization_pending")) {
            return null;
        }
        if (std.mem.eql(u8, err_code, "slow_down")) {
            self.interval += 5;
            return null;
        }
        if (std.mem.eql(u8, err_code, "expired_token")) {
            return error.DeviceCodeExpired;
        }

        return error.AuthorizationFailed;
    }

    pub fn complete(self: *AuthFlow) !DeviceTokens {
        while (true) {
            if (std.time.timestamp() >= self.expires_at) return error.DeviceCodeExpired;

            if (try self.poll()) |tokens| {
                return tokens;
            }

            try sleepSeconds(self.interval);
        }
    }

    pub fn verificationUrl(self: *const AuthFlow) []const u8 {
        return self.verification_uri_complete orelse self.verification_uri;
    }

    pub fn deinit(self: *AuthFlow) void {
        self.allocator.free(self.web_url);
        self.allocator.free(self.device_code);
        self.allocator.free(self.user_code);
        self.allocator.free(self.verification_uri);
        if (self.verification_uri_complete) |uri| {
            self.allocator.free(uri);
        }
        self.* = undefined;
    }
};

pub fn login(
    allocator: std.mem.Allocator,
    web_url: []const u8,
    grpc_url: []const u8,
    client_id: ?[]const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var flow = try AuthFlow.start(arena_alloc, web_url, client_id);
    defer flow.deinit();

    std.debug.print(
        "Authorize this device at {s}\nCode: {s}\n",
        .{ flow.verificationUrl(), flow.user_code },
    );
    std.debug.print("Waiting for authorization...\n", .{});

    const device_tokens = try flow.complete();

    const stored = StoredTokens{
        .server = grpc_url,
        .access_token = device_tokens.access_token,
        .refresh_token = device_tokens.refresh_token,
        .token_type = device_tokens.token_type,
        .expires_at = device_tokens.expires_at,
    };

    try storeTokens(allocator, stored);
    std.debug.print("Authenticated.\n", .{});
}

pub fn status(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const tokens = try readTokens(arena_alloc);
    if (tokens == null) {
        std.debug.print("Not logged in.\n", .{});
        return;
    }

    const value = tokens.?;
    if (value.expires_at) |expires_at| {
        const now = std.time.timestamp();
        if (now >= expires_at) {
            std.debug.print("Access token expired.\n", .{});
            return;
        }
    }

    std.debug.print("Authenticated with {s}.\n", .{value.server});
}

pub fn logout(allocator: std.mem.Allocator) !void {
    const path = try tokensPath(allocator);
    defer allocator.free(path);

    try deleteFile(path);
    std.debug.print("Logged out.\n", .{});
}

pub fn readTokens(allocator: std.mem.Allocator) !?StoredTokens {
    const path = try tokensPath(allocator);
    defer allocator.free(path);

    const data = try readFileAlloc(allocator, path, 64 * 1024);
    if (data == null) return null;
    // Note: Don't free data - parseFromSliceLeaky returns slices that reference it

    return try std.json.parseFromSliceLeaky(StoredTokens, allocator, data.?, .{
        .ignore_unknown_fields = true,
    });
}

pub fn requireTokens(allocator: std.mem.Allocator) !StoredTokens {
    const tokens = try readTokens(allocator) orelse return error.NotAuthenticated;
    if (tokens.server.len == 0) return error.InvalidTokens;
    if (tokens.expires_at) |expires_at| {
        const now = std.time.timestamp();
        if (now >= expires_at) return error.TokenExpired;
    }
    return tokens;
}

pub fn requireTokensWithMessage(allocator: std.mem.Allocator) !StoredTokens {
    return requireTokens(allocator) catch |err| {
        switch (err) {
            error.NotAuthenticated => {
                std.debug.print("Error: Not authenticated. Run 'mic auth login' first.\n", .{});
                return err;
            },
            error.TokenExpired => {
                std.debug.print("Error: Access token expired. Run 'mic auth login' again.\n", .{});
                return err;
            },
            error.InvalidTokens => {
                std.debug.print("Error: Stored token data is invalid. Run 'mic auth login' again.\n", .{});
                return err;
            },
            else => return err,
        }
    };
}

pub fn requireAccessTokenWithMessage(allocator: std.mem.Allocator) ![]const u8 {
    const tokens = try requireTokensWithMessage(allocator);
    return tokens.access_token;
}

fn storeTokens(allocator: std.mem.Allocator, tokens: StoredTokens) !void {
    try config.ensureConfigDir(allocator);

    var payload_buf = std.Io.Writer.Allocating.init(allocator);
    defer payload_buf.deinit();
    const formatter = std.json.fmt(tokens, .{});
    try formatter.format(&payload_buf.writer);
    const payload = try payload_buf.toOwnedSlice();
    defer allocator.free(payload);

    const path = try tokensPath(allocator);
    defer allocator.free(path);

    var file = try std.fs.createFileAbsolute(path, .{
        .read = true,
        .truncate = true,
        .mode = 0o600,
    });
    defer file.close();

    try file.writeAll(payload);
}

fn tokensPath(allocator: std.mem.Allocator) ![]u8 {
    const dir = try config.configDir(allocator);
    defer allocator.free(dir);

    return std.fs.path.join(allocator, &.{ dir, "tokens.json" });
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) !?[]u8 {
    var file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    return try file.readToEndAlloc(allocator, max_bytes);
}

fn deleteFile(path: []const u8) !void {
    std.fs.deleteFileAbsolute(path) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
}

fn tokensFromResponse(allocator: std.mem.Allocator, response: TokenResponse) !DeviceTokens {
    return .{
        .access_token = try allocator.dupe(u8, response.access_token),
        .refresh_token = if (response.refresh_token) |rt| try allocator.dupe(u8, rt) else null,
        .token_type = try allocator.dupe(u8, response.token_type),
        .expires_at = if (response.expires_in) |ttl| std.time.timestamp() + ttl else null,
    };
}

fn handleAuthError(allocator: std.mem.Allocator, body: []const u8) void {
    const parsed = std.json.parseFromSlice(ErrorResponse, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return;
    defer parsed.deinit();
}

fn jsonEncode(allocator: std.mem.Allocator, payload: anytype) ![]u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    const formatter = std.json.fmt(payload, .{});
    try formatter.format(&buf.writer);
    return try buf.toOwnedSlice();
}

fn hostFromUrl(url: []const u8) ?[]const u8 {
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return null;
    const start = scheme_end + 3;
    if (start >= url.len) return null;

    var end = url.len;
    if (std.mem.indexOfPos(u8, url, start, "/")) |pos| end = pos;
    if (std.mem.indexOfPos(u8, url, start, ":")) |pos| {
        if (pos < end) end = pos;
    }
    if (start >= end) return null;
    return url[start..end];
}

fn deviceName(allocator: std.mem.Allocator) ![]u8 {
    var name_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&name_buf) catch "device";
    return std.fmt.allocPrint(allocator, "mic@{s}", .{hostname});
}

fn sleepSeconds(seconds: i64) !void {
    if (seconds <= 0) return;
    const nanos = try std.math.mul(i64, seconds, std.time.ns_per_s);
    const nanos_u64: u64 = @intCast(nanos);
    std.Thread.sleep(nanos_u64);
}

const StartRequest = struct {
    device_name: []const u8,
    client_id: ?[]const u8 = null,
};

const PollRequest = struct {
    device_code: []const u8,
};

const StartResponse = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    verification_uri_complete: ?[]const u8 = null,
    expires_in: ?i64 = null,
    interval: ?i64 = null,
};

const TokenResponse = struct {
    access_token: []const u8,
    refresh_token: ?[]const u8 = null,
    token_type: []const u8,
    expires_in: ?i64 = null,
};

const ErrorResponse = struct {
    code: []const u8,
    message: ?[]const u8 = null,
};

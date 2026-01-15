const std = @import("std");

pub const Endpoint = struct {
    target: []const u8,
    host: []const u8,
    use_tls: bool = true,
};

pub fn parseServer(allocator: std.mem.Allocator, server: []const u8) !Endpoint {
    const uri = try std.Uri.parse(server);

    const scheme = uri.scheme;
    if (scheme.len == 0) {
        std.debug.print("Error: URL must have a scheme (http or https).\n", .{});
        return error.InvalidServer;
    }

    const host_component = uri.host orelse {
        std.debug.print("Error: Invalid server URL (no host).\n", .{});
        return error.InvalidServer;
    };

    const host = switch (host_component) {
        .percent_encoded => |pe| pe,
        .raw => |r| r,
    };

    if (host.len == 0) {
        std.debug.print("Error: Invalid server URL.\n", .{});
        return error.InvalidServer;
    }

    // Allow HTTP only for localhost (development)
    const is_https = std.mem.eql(u8, scheme, "https");
    const is_http = std.mem.eql(u8, scheme, "http");
    const is_localhost = std.mem.eql(u8, host, "localhost") or std.mem.eql(u8, host, "127.0.0.1");

    if (!is_https and !(is_http and is_localhost)) {
        std.debug.print("Error: gRPC requires https URLs (http allowed only for localhost).\n", .{});
        return error.InsecureServer;
    }

    const default_port: u16 = if (is_https) 443 else 80;
    const port = uri.port orelse default_port;
    const target = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, port });

    return .{ .target = target, .host = host, .use_tls = is_https };
}

pub fn isInsecure(endpoint: Endpoint) bool {
    return !endpoint.use_tls;
}

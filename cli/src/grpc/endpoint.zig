const std = @import("std");

pub const Endpoint = struct {
    target: []const u8,
    host: []const u8,
};

pub fn parseServer(allocator: std.mem.Allocator, server: []const u8) !Endpoint {
    const uri = try std.Uri.parse(server);
    if (uri.scheme == null or !std.mem.eql(u8, uri.scheme.?, "https")) {
        std.debug.print("Error: gRPC requires https URLs.\n", .{});
        return error.InsecureServer;
    }

    const host = uri.host orelse {
        std.debug.print("Error: Invalid server URL.\n", .{});
        return error.InvalidServer;
    };

    const port = uri.port orelse 443;
    const target = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, port });

    return .{ .target = target, .host = host };
}

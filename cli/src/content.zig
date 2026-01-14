const std = @import("std");
const oauth = @import("oauth.zig");
const grpc_client = @import("grpc/client.zig");
const content_proto = @import("grpc/content_proto.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");

pub fn ls(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    prefix: ?[]const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'mic auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try content_proto.encodeGetHeadTreeRequest(arena_alloc, account, project);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint.target,
        endpoint.host,
        "/micelio.content.v1.ContentService/GetHeadTree",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    const parsed = try content_proto.decodeTreeResponse(arena_alloc, response.bytes);

    const prefix_value = prefix orelse "";
    for (parsed.entries) |entry| {
        if (prefix_value.len == 0 or matchesPrefix(entry.path, prefix_value)) {
            std.debug.print("{s}\n", .{entry.path});
        }
    }
}

pub fn cat(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    path: []const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'mic auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try content_proto.encodeGetPathRequest(arena_alloc, account, project, path);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint.target,
        endpoint.host,
        "/micelio.content.v1.ContentService/GetPath",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    const parsed = try content_proto.decodePathResponse(arena_alloc, response.bytes);
    try std.io.getStdOut().writer().writeAll(parsed.content);
}

fn matchesPrefix(value: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0) return true;
    if (std.mem.eql(u8, prefix, "/")) return true;
    if (std.mem.eql(u8, value, prefix)) return true;
    if (std.mem.endsWith(u8, prefix, "/")) {
        return std.mem.startsWith(u8, value, prefix);
    }

    return std.mem.startsWith(u8, value, prefix) and value.len > prefix.len and value[prefix.len] == '/';
}

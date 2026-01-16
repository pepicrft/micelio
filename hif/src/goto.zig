const std = @import("std");
const oauth = @import("oauth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const content_proto = @import("grpc/content_proto.zig");

/// View the tree at a specific position (null means HEAD/latest)
pub fn show(
    allocator: std.mem.Allocator,
    organization: []const u8,
    project: []const u8,
    position: ?u64,
    path_prefix: ?[]const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, creds.?.server);

    // null position means HEAD, otherwise fetch specific position
    const parsed = if (position) |pos| blk: {
        const request = try content_proto.encodeGetTreeAtPositionRequest(
            arena_alloc,
            organization,
            project,
            pos,
        );
        defer arena_alloc.free(request);

        const response = try grpc_client.unaryCall(
            arena_alloc,
            endpoint,
            "/micelio.content.v1.ContentService/GetTreeAtPosition",
            request,
            creds.?.access_token.?,
        );
        defer arena_alloc.free(response.bytes);

        break :blk try content_proto.decodeTreeResponse(arena_alloc, response.bytes);
    } else blk: {
        const request = try content_proto.encodeGetHeadTreeRequest(
            arena_alloc,
            organization,
            project,
        );
        defer arena_alloc.free(request);

        const response = try grpc_client.unaryCall(
            arena_alloc,
            endpoint,
            "/micelio.content.v1.ContentService/GetHeadTree",
            request,
            creds.?.access_token.?,
        );
        defer arena_alloc.free(response.bytes);

        break :blk try content_proto.decodeTreeResponse(arena_alloc, response.bytes);
    };

    if (parsed.entries.len == 0) {
        if (position) |pos| {
            std.debug.print("Tree at @{d} is empty\n", .{pos});
        } else {
            std.debug.print("Tree at HEAD is empty\n", .{});
        }
        return;
    }

    if (position) |pos| {
        std.debug.print("Tree at @{d} ({d} files):\n\n", .{ pos, parsed.entries.len });
    } else {
        std.debug.print("Tree at HEAD ({d} files):\n\n", .{parsed.entries.len});
    }

    const prefix_value = path_prefix orelse "";
    var shown: usize = 0;

    for (parsed.entries) |entry| {
        if (prefix_value.len == 0 or matchesPrefix(entry.path, prefix_value)) {
            // Display the path with hash (truncated)
            const hash_hex = formatHashShort(entry.hash);
            std.debug.print("  {s}  {s}\n", .{ hash_hex, entry.path });
            shown += 1;
        }
    }

    if (shown == 0 and path_prefix != null) {
        std.debug.print("No files matching '{s}'\n", .{prefix_value});
    } else if (shown < parsed.entries.len) {
        std.debug.print("\n  ({d} of {d} files shown)\n", .{ shown, parsed.entries.len });
    }
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

fn formatHashShort(hash: []const u8) [8]u8 {
    const hex_chars = "0123456789abcdef";
    var result: [8]u8 = undefined;

    // Show first 4 bytes as 8 hex chars
    const display_len = @min(4, hash.len);
    for (0..display_len) |i| {
        result[i * 2] = hex_chars[hash[i] >> 4];
        result[i * 2 + 1] = hex_chars[hash[i] & 0x0F];
    }

    return result;
}

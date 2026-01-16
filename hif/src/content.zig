const std = @import("std");
const auth = @import("auth.zig");
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

    const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try content_proto.encodeGetHeadTreeRequest(arena_alloc, account, project);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.content.v1.ContentService/GetHeadTree",
        request,
        access_token,
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
    const blob_hash = try getPath(allocator, server, account, project, path, null);
    defer allocator.free(blob_hash);

    const content_bytes = try fetchBlob(allocator, server, account, project, blob_hash);
    defer allocator.free(content_bytes);

    try std.fs.File.stdout().writeAll(content_bytes);
}

pub fn getPath(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    path: []const u8,
    position: ?u64,
) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);

    if (position) |pos| {
        const request = try content_proto.encodeGetTreeAtPositionRequest(
            arena_alloc,
            account,
            project,
            pos,
        );
        defer arena_alloc.free(request);

        const response = try grpc_client.unaryCall(
            arena_alloc,
            endpoint,
            "/micelio.content.v1.ContentService/GetTreeAtPosition",
            request,
            access_token,
        );
        defer arena_alloc.free(response.bytes);

        const tree = try content_proto.decodeTreeResponse(arena_alloc, response.bytes);
        const blob_hash = findPathHash(tree.entries, path) orelse return error.PathNotFound;
        return allocator.dupe(u8, blob_hash);
    }

    const request = try content_proto.encodeGetPathRequest(arena_alloc, account, project, path);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.content.v1.ContentService/GetPath",
        request,
        access_token,
    );
    defer arena_alloc.free(response.bytes);

    const parsed = try content_proto.decodePathResponse(arena_alloc, response.bytes);
    if (parsed.blob_hash.len == 0) return error.PathNotFound;
    return allocator.dupe(u8, parsed.blob_hash);
}

pub fn fetchBlob(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    blob_hash: []const u8,
) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try content_proto.encodeGetBlobRequest(arena_alloc, account, project, blob_hash);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.content.v1.ContentService/GetBlob",
        request,
        access_token,
    );
    defer arena_alloc.free(response.bytes);

    const parsed = try content_proto.decodeBlobResponse(arena_alloc, response.bytes);
    return allocator.dupe(u8, parsed);
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

fn findPathHash(entries: []const content_proto.TreeEntry, path: []const u8) ?[]const u8 {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.path, path)) {
            return entry.hash;
        }
    }
    return null;
}

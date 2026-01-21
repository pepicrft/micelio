const std = @import("std");
const auth = @import("auth.zig");
const config = @import("config.zig");
const grpc_client = @import("grpc/client.zig");
const content_proto = @import("grpc/content_proto.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const http = @import("http.zig");
const projects_proto = @import("grpc/projects_proto.zig");

pub const BlobFetchOptions = struct {
    cdn_base_url: ?[]const u8 = null,
    project_id: ?[]const u8 = null,
    access_token: ?[]const u8 = null,

    pub fn deinit(self: *BlobFetchOptions, allocator: std.mem.Allocator) void {
        if (self.cdn_base_url) |url| allocator.free(url);
        if (self.project_id) |id| allocator.free(id);
        self.* = undefined;
    }
};

pub fn ls(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    prefix: ?[]const u8,
    position: ?u64,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = if (position) |pos|
        try content_proto.encodeGetTreeAtPositionRequest(arena_alloc, account, project, pos)
    else
        try content_proto.encodeGetHeadTreeRequest(arena_alloc, account, project);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        if (position != null)
            "/micelio.content.v1.ContentService/GetTreeAtPosition"
        else
            "/micelio.content.v1.ContentService/GetHeadTree",
        request,
        access_token,
    );
    defer arena_alloc.free(response.bytes);

    const parsed = try content_proto.decodeTreeResponse(arena_alloc, response.bytes);

    const prefix_value = prefix orelse "";
    const entries = try collectLsEntries(arena_alloc, parsed.entries, prefix_value);
    for (entries) |entry| {
        if (entry.is_dir) {
            std.debug.print("{s}/\n", .{entry.name});
        } else {
            std.debug.print("{s}\n", .{entry.name});
        }
    }
}

pub fn cat(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    path: []const u8,
    position: ?u64,
) !void {
    const blob_hash = try getPath(allocator, server, account, project, path, position);
    defer allocator.free(blob_hash);

    var blob_options = try prepareBlobFetchOptions(allocator, server, account, project, null);
    defer blob_options.deinit(allocator);

    const content_bytes = try fetchBlobWithOptions(
        allocator,
        server,
        account,
        project,
        blob_hash,
        &blob_options,
    );
    defer allocator.free(content_bytes);

    try std.fs.File.stdout().writeAll(content_bytes);
}

pub fn blame(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    path: []const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);
    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try content_proto.encodeGetBlameRequest(arena_alloc, account, project, path);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.content.v1.ContentService/GetBlame",
        request,
        access_token,
    );
    defer arena_alloc.free(response.bytes);

    const parsed = try content_proto.decodeBlameResponse(arena_alloc, response.bytes);

    if (parsed.lines.len == 0) {
        std.debug.print("No blame data available for {s}\n", .{path});
        return;
    }

    for (parsed.lines) |line| {
        const session_id = if (line.session_id.len > 0) line.session_id else "unknown";
        const author_handle = if (line.author_handle.len > 0) line.author_handle else "unknown";
        const landed_at = if (line.landed_at.len > 0) line.landed_at else "unknown";
        std.debug.print(
            "{d}\t{s}\t{s}\t{s}\t{s}\n",
            .{ line.line_number, session_id, author_handle, landed_at, line.text },
        );
    }
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
    return fetchBlobWithOptions(allocator, server, account, project, blob_hash, null);
}

pub fn prepareBlobFetchOptions(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    access_token: ?[]const u8,
) !BlobFetchOptions {
    var options = BlobFetchOptions{ .access_token = access_token };

    var cfg = config.Config.load(allocator) catch return options;
    defer cfg.deinit();

    const server_config = cfg.findServerByGrpcUrl(server) orelse return options;
    if (server_config.cdn_url) |cdn_url| {
        options.cdn_base_url = try allocator.dupe(u8, cdn_url);
        options.project_id = fetchProjectId(allocator, server, account, project, access_token) catch {
            allocator.free(options.cdn_base_url.?);
            options.cdn_base_url = null;
            return options;
        };
    }

    return options;
}

pub fn fetchBlobWithOptions(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    blob_hash: []const u8,
    options: ?*const BlobFetchOptions,
) ![]const u8 {
    if (options) |opts| {
        if (opts.cdn_base_url != null and opts.project_id != null) {
            const cdn_blob = fetchBlobFromCdn(
                allocator,
                opts.cdn_base_url.?,
                opts.project_id.?,
                blob_hash,
            ) catch null;
            if (cdn_blob) |content_bytes| {
                return content_bytes;
            }
        }
    }

    return fetchBlobFromGrpc(
        allocator,
        server,
        account,
        project,
        blob_hash,
        if (options) |opts| opts.access_token else null,
    );
}

fn fetchBlobFromGrpc(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    blob_hash: []const u8,
    access_token: ?[]const u8,
) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const token = access_token orelse try auth.requireAccessTokenWithMessage(arena_alloc);

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try content_proto.encodeGetBlobRequest(arena_alloc, account, project, blob_hash);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.content.v1.ContentService/GetBlob",
        request,
        token,
    );
    defer arena_alloc.free(response.bytes);

    const parsed = try content_proto.decodeBlobResponse(arena_alloc, response.bytes);
    return allocator.dupe(u8, parsed);
}

fn fetchBlobFromCdn(
    allocator: std.mem.Allocator,
    cdn_base_url: []const u8,
    project_id: []const u8,
    blob_hash: []const u8,
) !?[]const u8 {
    const url = try cdnUrlForBlob(allocator, cdn_base_url, project_id, blob_hash);
    defer allocator.free(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const response = try http.get(allocator, &client, url);
    defer allocator.free(response.body);

    if (response.status != .ok) return null;
    const duped = try allocator.dupe(u8, response.body);
    return duped;
}

fn fetchProjectId(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    access_token: ?[]const u8,
) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const token = access_token orelse try auth.requireAccessTokenWithMessage(arena_alloc);
    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try projects_proto.encodeGetProjectRequest(arena_alloc, account, project);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.projects.v1.ProjectService/GetProject",
        request,
        token,
    );
    defer arena_alloc.free(response.bytes);

    const project_info = try projects_proto.decodeProjectResponse(arena_alloc, response.bytes);
    return allocator.dupe(u8, project_info.id);
}

fn cdnUrlForBlob(
    allocator: std.mem.Allocator,
    cdn_base_url: []const u8,
    project_id: []const u8,
    blob_hash: []const u8,
) ![]u8 {
    const key = try blobKey(allocator, project_id, blob_hash);
    defer allocator.free(key);

    const trimmed_base = trimTrailingSlash(cdn_base_url);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ trimmed_base, key });
}

fn blobKey(
    allocator: std.mem.Allocator,
    project_id: []const u8,
    blob_hash: []const u8,
) ![]u8 {
    const hash_hex = try hexEncode(allocator, blob_hash);
    defer allocator.free(hash_hex);
    if (hash_hex.len < 2) return error.InvalidHash;
    const prefix = hash_hex[0..2];
    return std.fmt.allocPrint(
        allocator,
        "projects/{s}/blobs/{s}/{s}.bin",
        .{ project_id, prefix, hash_hex },
    );
}

fn hexEncode(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const hex = "0123456789abcdef";
    var out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, idx| {
        out[idx * 2] = hex[byte >> 4];
        out[idx * 2 + 1] = hex[byte & 0x0f];
    }
    return out;
}

fn trimTrailingSlash(value: []const u8) []const u8 {
    var trimmed = value;
    while (trimmed.len > 0 and trimmed[trimmed.len - 1] == '/') {
        trimmed = trimmed[0 .. trimmed.len - 1];
    }
    return trimmed;
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

const LsEntry = struct {
    name: []const u8,
    is_dir: bool,
};

fn collectLsEntries(
    allocator: std.mem.Allocator,
    entries: []const content_proto.TreeEntry,
    prefix_raw: []const u8,
) ![]LsEntry {
    const prefix = normalizeLsPrefix(prefix_raw);
    var index_by_name = std.StringHashMap(usize).init(allocator);
    defer index_by_name.deinit();

    var results = std.array_list.Managed(LsEntry).init(allocator);
    errdefer results.deinit();

    for (entries) |entry| {
        if (prefix.len == 0) {
            const segment = firstSegment(entry.path);
            const is_dir = entry.path.len > segment.len;
            try addLsEntry(&results, &index_by_name, segment, is_dir);
            continue;
        }

        if (std.mem.eql(u8, entry.path, prefix)) {
            const name = baseName(prefix);
            try addLsEntry(&results, &index_by_name, name, false);
            continue;
        }

        if (std.mem.startsWith(u8, entry.path, prefix) and entry.path.len > prefix.len and entry.path[prefix.len] == '/') {
            const remainder = entry.path[prefix.len + 1 ..];
            const segment = firstSegment(remainder);
            const is_dir = remainder.len > segment.len;
            try addLsEntry(&results, &index_by_name, segment, is_dir);
        }
    }

    std.mem.sort(LsEntry, results.items, {}, lsEntryLessThan);
    return results.toOwnedSlice();
}

fn addLsEntry(
    results: *std.array_list.Managed(LsEntry),
    index_by_name: *std.StringHashMap(usize),
    name: []const u8,
    is_dir: bool,
) !void {
    if (index_by_name.get(name)) |idx| {
        if (is_dir and !results.items[idx].is_dir) {
            results.items[idx].is_dir = true;
        }
        return;
    }

    try index_by_name.put(name, results.items.len);
    try results.append(.{ .name = name, .is_dir = is_dir });
}

fn normalizeLsPrefix(value: []const u8) []const u8 {
    var trimmed = value;
    while (trimmed.len > 0 and trimmed[0] == '/') {
        trimmed = trimmed[1..];
    }
    while (trimmed.len > 0 and trimmed[trimmed.len - 1] == '/') {
        trimmed = trimmed[0 .. trimmed.len - 1];
    }
    if (std.mem.eql(u8, trimmed, ".")) return "";
    return trimmed;
}

fn firstSegment(path: []const u8) []const u8 {
    const slash = std.mem.indexOfScalar(u8, path, '/') orelse return path;
    return path[0..slash];
}

fn baseName(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return path;
    return path[slash + 1 ..];
}

fn lsEntryLessThan(_: void, lhs: LsEntry, rhs: LsEntry) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}

fn findPathHash(entries: []const content_proto.TreeEntry, path: []const u8) ?[]const u8 {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.path, path)) {
            return entry.hash;
        }
    }
    return null;
}

test "cdnUrlForBlob builds storage key URL" {
    const blob_hash = &[_]u8{ 0xaa, 0xbb, 0xcc };
    const url = try cdnUrlForBlob(
        std.testing.allocator,
        "https://cdn.example/",
        "123",
        blob_hash,
    );
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings(
        "https://cdn.example/projects/123/blobs/aa/aabbcc.bin",
        url,
    );
}

test "collectLsEntries lists directory contents by prefix" {
    const entries = [_]content_proto.TreeEntry{
        .{ .path = "README.md", .hash = "a" },
        .{ .path = "src/main.zig", .hash = "b" },
        .{ .path = "src/utils/math.zig", .hash = "c" },
        .{ .path = "docs/guide.md", .hash = "d" },
        .{ .path = "docs/readme.txt", .hash = "e" },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const root = try collectLsEntries(allocator, &entries, "");
    try std.testing.expectEqual(@as(usize, 3), root.len);
    try std.testing.expectEqualStrings("README.md", root[0].name);
    try std.testing.expectEqualStrings("docs", root[1].name);
    try std.testing.expect(root[1].is_dir);
    try std.testing.expectEqualStrings("src", root[2].name);
    try std.testing.expect(root[2].is_dir);

    const src = try collectLsEntries(allocator, &entries, "src");
    try std.testing.expectEqual(@as(usize, 2), src.len);
    try std.testing.expectEqualStrings("main.zig", src[0].name);
    try std.testing.expect(!src[0].is_dir);
    try std.testing.expectEqualStrings("utils", src[1].name);
    try std.testing.expect(src[1].is_dir);

    const docs = try collectLsEntries(allocator, &entries, "docs");
    try std.testing.expectEqual(@as(usize, 2), docs.len);
    try std.testing.expectEqualStrings("guide.md", docs[0].name);
    try std.testing.expectEqualStrings("readme.txt", docs[1].name);

    const utils = try collectLsEntries(allocator, &entries, "src/utils");
    try std.testing.expectEqual(@as(usize, 1), utils.len);
    try std.testing.expectEqualStrings("math.zig", utils[0].name);

    const readme = try collectLsEntries(allocator, &entries, "README.md");
    try std.testing.expectEqual(@as(usize, 1), readme.len);
    try std.testing.expectEqualStrings("README.md", readme[0].name);
}

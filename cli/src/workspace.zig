const std = @import("std");
const oauth = @import("oauth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const content_proto = @import("grpc/content_proto.zig");
const sessions_proto = @import("grpc/sessions_proto.zig");
const manifest = @import("workspace/manifest.zig");
const fs = @import("workspace/fs.zig");

const WorkspaceChange = struct {
    path: []const u8,
    change_type: []const u8,
};

pub fn checkout(
    allocator: std.mem.Allocator,
    account: []const u8,
    project: []const u8,
    target_path: ?[]const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'mic auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const workspace_root = target_path orelse project;
    try fs.ensureDir(workspace_root);

    const existing = try manifest.load(arena_alloc, workspace_root);
    if (existing != null) {
        std.debug.print("Error: Workspace already exists at {s}.\n", .{workspace_root});
        return error.WorkspaceExists;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, creds.?.server);
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

    const tree = try content_proto.decodeTreeResponse(arena_alloc, response.bytes);
    const tree_hash_hex = try hexEncode(arena_alloc, tree.tree_hash);

    var entries = std.ArrayList(manifest.WorkspaceEntry).init(arena_alloc);

    for (tree.entries) |entry| {
        if (!isSafePath(entry.path)) {
            std.debug.print("Error: Unsafe path in tree: {s}\n", .{entry.path});
            return error.InvalidPath;
        }

        const blob_request = try content_proto.encodeGetBlobRequest(
            arena_alloc,
            account,
            project,
            entry.hash,
        );
        defer arena_alloc.free(blob_request);

        const blob_response = try grpc_client.unaryCall(
            arena_alloc,
            endpoint.target,
            endpoint.host,
            "/micelio.content.v1.ContentService/GetBlob",
            blob_request,
            creds.?.access_token.?,
        );
        defer arena_alloc.free(blob_response.bytes);

        const content = try content_proto.decodeBlobResponse(arena_alloc, blob_response.bytes);
        const file_path = try std.fs.path.join(arena_alloc, &[_][]const u8{ workspace_root, entry.path });
        try fs.ensureParentDir(file_path);
        try fs.writeFile(file_path, content);

        const hash_hex = try hexEncode(arena_alloc, entry.hash);
        try entries.append(.{ .path = entry.path, .hash = hash_hex });
    }

    const state = manifest.WorkspaceState{
        .version = 1,
        .server = creds.?.server,
        .account = account,
        .project = project,
        .tree_hash = tree_hash_hex,
        .entries = try entries.toOwnedSlice(),
    };

    try manifest.save(arena_alloc, workspace_root, state);

    std.debug.print(
        "Workspace ready: {s} ({d} files)\n",
        .{ workspace_root, state.entries.len },
    );
    std.debug.print("Next: cd {s}\n", .{workspace_root});
    std.debug.print("      mic status\n", .{});
    std.debug.print("      mic land \"your goal\"\n", .{});
}

pub fn status(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const workspace_root = try std.process.getCwdAlloc(arena_alloc);
    const parsed = try manifest.load(arena_alloc, workspace_root);
    if (parsed == null) {
        std.debug.print("No workspace metadata found. Run 'mic workspace checkout'.\n", .{});
        return;
    }

    const changes = try collectChanges(arena_alloc, workspace_root, parsed.?.value);
    if (changes.len == 0) {
        std.debug.print("Workspace clean.\n", .{});
        return;
    }

    for (changes) |change| {
        const prefix = changePrefix(change.change_type);
        std.debug.print("{s} {s}\n", .{ prefix, change.path });
    }
}

pub fn land(allocator: std.mem.Allocator, goal: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const workspace_root = try std.process.getCwdAlloc(arena_alloc);
    const parsed = try manifest.load(arena_alloc, workspace_root);
    if (parsed == null) {
        std.debug.print("No workspace metadata found. Run 'mic workspace checkout'.\n", .{});
        return;
    }

    const state = parsed.?.value;
    const changes = try collectChanges(arena_alloc, workspace_root, state);
    if (changes.len == 0) {
        std.debug.print("No changes to land.\n", .{});
        return;
    }

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'mic auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, state.server);
    const session_id = try generateSessionId(arena_alloc);
    const start_request = try sessions_proto.encodeStartSessionRequest(
        arena_alloc,
        state.account,
        state.project,
        session_id,
        goal,
    );
    defer arena_alloc.free(start_request);

    const start_response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint.target,
        endpoint.host,
        "/micelio.sessions.v1.SessionService/StartSession",
        start_request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(start_response.bytes);
    _ = try sessions_proto.decodeSessionResponse(arena_alloc, start_response.bytes);

    const file_changes = try buildFileChanges(arena_alloc, workspace_root, changes);
    defer arena_alloc.free(file_changes);

    const land_request = try sessions_proto.encodeLandSessionRequest(
        arena_alloc,
        session_id,
        file_changes,
    );
    defer arena_alloc.free(land_request);

    const land_response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint.target,
        endpoint.host,
        "/micelio.sessions.v1.SessionService/LandSession",
        land_request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(land_response.bytes);
    const landed = try sessions_proto.decodeSessionResponse(arena_alloc, land_response.bytes);

    try refreshManifest(arena_alloc, state, workspace_root, creds.?.access_token.?);

    std.debug.print("Landed session {s}.\n", .{landed.session_id});
    if (landed.landing_position > 0) {
        std.debug.print("Landing position: {d}\n", .{landed.landing_position});
    }
}

fn refreshManifest(
    allocator: std.mem.Allocator,
    state: manifest.WorkspaceState,
    workspace_root: []const u8,
    access_token: []const u8,
) !void {
    const endpoint = try grpc_endpoint.parseServer(allocator, state.server);
    const request = try content_proto.encodeGetHeadTreeRequest(
        allocator,
        state.account,
        state.project,
    );
    defer allocator.free(request);

    const response = try grpc_client.unaryCall(
        allocator,
        endpoint.target,
        endpoint.host,
        "/micelio.content.v1.ContentService/GetHeadTree",
        request,
        access_token,
    );
    defer allocator.free(response.bytes);

    const tree = try content_proto.decodeTreeResponse(allocator, response.bytes);
    const tree_hash_hex = try hexEncode(allocator, tree.tree_hash);

    var entries = std.ArrayList(manifest.WorkspaceEntry).init(allocator);
    for (tree.entries) |entry| {
        const hash_hex = try hexEncode(allocator, entry.hash);
        try entries.append(.{ .path = entry.path, .hash = hash_hex });
    }

    const updated = manifest.WorkspaceState{
        .version = state.version,
        .server = state.server,
        .account = state.account,
        .project = state.project,
        .tree_hash = tree_hash_hex,
        .entries = try entries.toOwnedSlice(),
    };

    try manifest.save(allocator, workspace_root, updated);
}

fn collectChanges(
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    state: manifest.WorkspaceState,
) ![]WorkspaceChange {
    var known = std.StringHashMap([]const u8).init(allocator);
    defer {
        known.deinit();
    }

    for (state.entries) |entry| {
        try known.put(entry.path, entry.hash);
    }

    var changes = std.ArrayList(WorkspaceChange).init(allocator);

    for (state.entries) |entry| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ workspace_root, entry.path });
        const exists = try fs.fileExists(path);
        if (!exists) {
            try changes.append(.{ .path = entry.path, .change_type = "deleted" });
            continue;
        }

        const digest = fs.hashFileSha256(path) catch |err| switch (err) {
            error.IsDir => {
                try changes.append(.{ .path = entry.path, .change_type = "modified" });
                continue;
            },
            else => return err,
        };
        const digest_hex = try hexEncode(allocator, &digest);
        if (!std.mem.eql(u8, digest_hex, entry.hash)) {
            try changes.append(.{ .path = entry.path, .change_type = "modified" });
        }
    }

    var root_dir = try fs.openDir(workspace_root, true);
    defer root_dir.close();
    var walker = try root_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (isMetadataPath(entry.path)) continue;
        if (known.contains(entry.path)) continue;
        try changes.append(.{ .path = entry.path, .change_type = "added" });
    }

    return changes.toOwnedSlice();
}

fn buildFileChanges(
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    changes: []WorkspaceChange,
) ![]sessions_proto.FileChange {
    var mapped = try allocator.alloc(sessions_proto.FileChange, changes.len);
    for (changes, 0..) |change, idx| {
        const content = if (std.mem.eql(u8, change.change_type, "deleted")) blk: {
            break :blk &[_]u8{};
        } else blk: {
            const path = try std.fs.path.join(allocator, &[_][]const u8{ workspace_root, change.path });
            const data = try fs.readFileAlloc(allocator, path, 50 * 1024 * 1024);
            if (data == null) return error.FileNotFound;
            break :blk data.?;
        };

        mapped[idx] = .{
            .path = change.path,
            .content = content,
            .change_type = change.change_type,
        };
    }

    return mapped;
}

fn isMetadataPath(path: []const u8) bool {
    return std.mem.eql(u8, path, ".mic") or std.mem.startsWith(u8, path, ".mic/");
}

fn isSafePath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.fs.path.isAbsolute(path)) return false;

    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return false;
    }

    return true;
}

fn changePrefix(change_type: []const u8) []const u8 {
    if (std.mem.eql(u8, change_type, "added")) return "A";
    if (std.mem.eql(u8, change_type, "deleted")) return "D";
    return "M";
}

fn generateSessionId(allocator: std.mem.Allocator) ![]u8 {
    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);

    const encoded = std.base64.url_safe_no_pad.Encoder.encode(
        try allocator.alloc(u8, std.base64.url_safe_no_pad.Encoder.calcSize(16)),
        &random_bytes,
    );
    return try allocator.dupe(u8, encoded);
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

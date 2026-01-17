const std = @import("std");
const auth = @import("auth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const content_proto = @import("grpc/content_proto.zig");
const sessions_proto = @import("grpc/sessions_proto.zig");
const manifest = @import("workspace/manifest.zig");
const fs = @import("workspace/fs.zig");
const cache_mod = @import("cache.zig");

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

    const tokens = try auth.requireTokensWithMessage(arena_alloc);

    const workspace_root = target_path orelse project;
    try fs.ensureDir(workspace_root);

    const existing = try manifest.load(arena_alloc, workspace_root);
    if (existing != null) {
        std.debug.print("Error: Workspace already exists at {s}.\n", .{workspace_root});
        return error.WorkspaceExists;
    }

    // Initialize blob cache
    var blob_cache = try cache_mod.BlobCache.init(allocator, .{});
    defer blob_cache.deinit();

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, tokens.server);
    const request = try content_proto.encodeGetHeadTreeRequest(arena_alloc, account, project);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.content.v1.ContentService/GetHeadTree",
        request,
        tokens.access_token,
    );
    defer arena_alloc.free(response.bytes);

    const tree = try content_proto.decodeTreeResponse(arena_alloc, response.bytes);
    const tree_hash_hex = try hexEncode(arena_alloc, tree.tree_hash);

    var entries: std.ArrayList(manifest.WorkspaceEntry) = .empty;
    var cache_hits: u32 = 0;

    for (tree.entries) |entry| {
        if (!isSafePath(entry.path)) {
            std.debug.print("Error: Unsafe path in tree: {s}\n", .{entry.path});
            return error.InvalidPath;
        }

        const hash_hex = try hexEncode(arena_alloc, entry.hash);

        // Try cache first
        const content = if (blob_cache.get(hash_hex)) |cached| blk: {
            cache_hits += 1;
            break :blk cached;
        } else blk: {
            // Fetch from server
            const blob_request = try content_proto.encodeGetBlobRequest(
                arena_alloc,
                account,
                project,
                entry.hash,
            );
            defer arena_alloc.free(blob_request);

            const blob_response = try grpc_client.unaryCall(
                arena_alloc,
                endpoint,
                "/micelio.content.v1.ContentService/GetBlob",
                blob_request,
                tokens.access_token,
            );
            defer arena_alloc.free(blob_response.bytes);

            const fetched = try content_proto.decodeBlobResponse(arena_alloc, blob_response.bytes);

            // Store in cache
            try blob_cache.put(hash_hex, fetched);

            break :blk try allocator.dupe(u8, fetched);
        };
        defer allocator.free(content);

        const file_path = try std.fs.path.join(arena_alloc, &[_][]const u8{ workspace_root, entry.path });
        try fs.ensureParentDir(file_path);
        try fs.writeFile(file_path, content);

        try entries.append(arena_alloc, .{ .path = entry.path, .hash = hash_hex });
    }

    const state = manifest.WorkspaceState{
        .version = 1,
        .server = tokens.server,
        .account = account,
        .project = project,
        .tree_hash = tree_hash_hex,
        .entries = try entries.toOwnedSlice(arena_alloc),
    };

    try manifest.save(arena_alloc, workspace_root, state);

    std.debug.print(
        "Workspace ready: {s} ({d} files",
        .{ workspace_root, state.entries.len },
    );
    if (cache_hits > 0) {
        std.debug.print(", {d} from cache", .{cache_hits});
    }
    std.debug.print(")\n", .{});
    std.debug.print("Next: cd {s}\n", .{workspace_root});
    std.debug.print("      hif status\n", .{});
    std.debug.print("      hif land \"your goal\"\n", .{});
}

pub fn status(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const workspace_root = try std.process.getCwdAlloc(arena_alloc);
    const parsed = try manifest.load(arena_alloc, workspace_root);
    if (parsed == null) {
        std.debug.print("No workspace metadata found. Run 'hif workspace checkout'.\n", .{});
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
        std.debug.print("No workspace metadata found. Run 'hif workspace checkout'.\n", .{});
        return;
    }

    const state = parsed.?.value;
    const changes = try collectChanges(arena_alloc, workspace_root, state);
    if (changes.len == 0) {
        std.debug.print("No changes to land.\n", .{});
        return;
    }

    const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);

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
        endpoint,
        "/micelio.sessions.v1.SessionService/StartSession",
        start_request,
        access_token,
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

    const land_result = try grpc_client.unaryCallResult(
        arena_alloc,
        endpoint,
        "/micelio.sessions.v1.SessionService/LandSession",
        land_request,
        access_token,
    );

    switch (land_result) {
        .ok => |response| {
            defer arena_alloc.free(response.bytes);
            const landed = try sessions_proto.decodeSessionResponse(arena_alloc, response.bytes);

            try refreshManifest(
                arena_alloc,
                state,
                workspace_root,
                access_token,
                landed.landing_position,
            );

            std.debug.print("Landed session {s}.\n", .{landed.session_id});
            if (landed.landing_position > 0) {
                std.debug.print("Landing position: {d}\n", .{landed.landing_position});
            }
        },
        .err => |message| {
            defer arena_alloc.free(message);

            // Check if this is a conflict error
            if (std.mem.startsWith(u8, message, "Conflicts detected: ")) {
                const paths_str = message["Conflicts detected: ".len..];

                std.debug.print("Error: Conflicts detected with upstream changes.\n", .{});
                std.debug.print("\nConflicting files:\n", .{});

                var iter = std.mem.splitSequence(u8, paths_str, ", ");
                while (iter.next()) |path| {
                    std.debug.print("  - {s}\n", .{path});
                }

                std.debug.print("\nTo resolve:\n", .{});
                std.debug.print("  1. Run 'hif sync' to fetch the latest upstream state\n", .{});
                std.debug.print("  2. Review and merge your changes with the upstream versions\n", .{});
                std.debug.print("  3. Run 'hif land' again\n", .{});
                return error.ConflictsDetected;
            }

            std.debug.print("Error: {s}\n", .{message});
            return error.LandingFailed;
        },
    }
}

fn refreshManifest(
    allocator: std.mem.Allocator,
    state: manifest.WorkspaceState,
    workspace_root: []const u8,
    access_token: []const u8,
    landing_position: u64,
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
        endpoint,
        "/micelio.content.v1.ContentService/GetHeadTree",
        request,
        access_token,
    );
    defer allocator.free(response.bytes);

    const tree = try content_proto.decodeTreeResponse(allocator, response.bytes);
    const tree_hash_hex = try hexEncode(allocator, tree.tree_hash);

    var entries: std.ArrayList(manifest.WorkspaceEntry) = .empty;
    for (tree.entries) |entry| {
        const hash_hex = try hexEncode(allocator, entry.hash);
        try entries.append(allocator, .{ .path = entry.path, .hash = hash_hex });
    }

    const updated = manifest.WorkspaceState{
        .version = state.version,
        .server = state.server,
        .account = state.account,
        .project = state.project,
        .position = landing_position,
        .tree_hash = tree_hash_hex,
        .entries = try entries.toOwnedSlice(allocator),
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

    var changes: std.ArrayList(WorkspaceChange) = .empty;

    for (state.entries) |entry| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ workspace_root, entry.path });
        const exists = try fs.fileExists(path);
        if (!exists) {
            try changes.append(allocator, .{ .path = entry.path, .change_type = "deleted" });
            continue;
        }

        const digest = fs.hashFileSha256(path) catch |err| switch (err) {
            error.IsDir => {
                try changes.append(allocator, .{ .path = entry.path, .change_type = "modified" });
                continue;
            },
            else => return err,
        };
        const digest_hex = try hexEncode(allocator, &digest);
        if (!std.mem.eql(u8, digest_hex, entry.hash)) {
            try changes.append(allocator, .{ .path = entry.path, .change_type = "modified" });
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
        const path_copy = try allocator.dupe(u8, entry.path);
        try changes.append(allocator, .{ .path = path_copy, .change_type = "added" });
    }

    return changes.toOwnedSlice(allocator);
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
    return std.mem.eql(u8, path, ".hif") or std.mem.startsWith(u8, path, ".hif/");
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

pub const SyncResult = struct {
    updated: u32,
    conflicts: []const []const u8,
};

pub const MergeStrategy = enum {
    ours,
    theirs,
    interactive,
};

pub fn parseMergeStrategy(value: []const u8) ?MergeStrategy {
    if (std.mem.eql(u8, value, "ours")) return .ours;
    if (std.mem.eql(u8, value, "theirs")) return .theirs;
    if (std.mem.eql(u8, value, "interactive")) return .interactive;
    return null;
}

/// Syncs the workspace with the latest upstream tree.
/// Returns information about updated files and any conflicts.
pub fn sync(allocator: std.mem.Allocator) !SyncResult {
    return syncWorkspace(allocator, .interactive);
}

pub fn syncWorkspace(allocator: std.mem.Allocator, strategy: MergeStrategy) !SyncResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const workspace_root = try std.process.getCwdAlloc(arena_alloc);
    const parsed = try manifest.load(arena_alloc, workspace_root);
    if (parsed == null) {
        std.debug.print("No workspace metadata found. Run 'hif workspace checkout'.\n", .{});
        return error.NoWorkspace;
    }

    const state = parsed.?.value;

    const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);

    // Initialize blob cache
    var blob_cache = try cache_mod.BlobCache.init(allocator, .{});
    defer blob_cache.deinit();

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, state.server);
    const head_request = try content_proto.encodeGetHeadTreeRequest(
        arena_alloc,
        state.account,
        state.project,
    );
    defer arena_alloc.free(head_request);

    const head_response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.content.v1.ContentService/GetHeadTree",
        head_request,
        access_token,
    );
    defer arena_alloc.free(head_response.bytes);

    const head_tree = try content_proto.decodeTreeResponse(arena_alloc, head_response.bytes);
    const new_tree_hash_hex = try hexEncode(arena_alloc, head_tree.tree_hash);

    // Check if already up to date
    if (std.mem.eql(u8, new_tree_hash_hex, state.tree_hash)) {
        std.debug.print("Already up to date.\n", .{});
        return .{ .updated = 0, .conflicts = &[_][]const u8{} };
    }

    const base_position = state.position orelse 0;
    const base_request = try content_proto.encodeGetTreeAtPositionRequest(
        arena_alloc,
        state.account,
        state.project,
        base_position,
    );
    defer arena_alloc.free(base_request);

    const base_response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.content.v1.ContentService/GetTreeAtPosition",
        base_request,
        access_token,
    );
    defer arena_alloc.free(base_response.bytes);

    const base_tree = try content_proto.decodeTreeResponse(arena_alloc, base_response.bytes);

    // Build maps for comparison
    var base_entries = std.StringHashMap([]const u8).init(arena_alloc);
    if (state.position != null) {
        for (base_tree.entries) |entry| {
            const hash_hex = try hexEncode(arena_alloc, entry.hash);
            try base_entries.put(entry.path, hash_hex);
        }
    } else {
        for (state.entries) |entry| {
            try base_entries.put(entry.path, entry.hash);
        }
    }

    var head_entries = std.StringHashMap([]const u8).init(arena_alloc);
    for (head_tree.entries) |entry| {
        const hash_hex = try hexEncode(arena_alloc, entry.hash);
        try head_entries.put(entry.path, hash_hex);
    }

    // Collect local changes
    const local_changes = try collectChanges(arena_alloc, workspace_root, state);
    var local_modified = std.StringHashMap(void).init(arena_alloc);
    for (local_changes) |change| {
        try local_modified.put(change.path, {});
    }

    var updated: u32 = 0;
    var cache_hits: u32 = 0;
    var resolved_conflicts: u32 = 0;
    var conflicts: std.ArrayList([]const u8) = .empty;

    // Process upstream changes
    for (head_tree.entries) |entry| {
        const new_hash_hex = try hexEncode(arena_alloc, entry.hash);
        const base_hash = base_entries.get(entry.path);

        // File is new or changed upstream
        const upstream_changed = base_hash == null or !std.mem.eql(u8, base_hash.?, new_hash_hex);
        if (!upstream_changed) continue;

        // Check if locally modified
        if (local_modified.contains(entry.path)) {
            switch (strategy) {
                .theirs => {
                    resolved_conflicts += 1;
                },
                .ours => {
                    resolved_conflicts += 1;
                    continue;
                },
                .interactive => {
                    try conflicts.append(allocator, try allocator.dupe(u8, entry.path));
                    continue;
                },
            }
        }

        // Try cache first
        const content = if (blob_cache.get(new_hash_hex)) |cached| blk: {
            cache_hits += 1;
            break :blk cached;
        } else blk: {
            // Fetch from server
            const blob_request = try content_proto.encodeGetBlobRequest(
                arena_alloc,
                state.account,
                state.project,
                entry.hash,
            );
            defer arena_alloc.free(blob_request);

            const blob_response = try grpc_client.unaryCall(
                arena_alloc,
                endpoint,
                "/micelio.content.v1.ContentService/GetBlob",
                blob_request,
                access_token,
            );
            defer arena_alloc.free(blob_response.bytes);

            const fetched = try content_proto.decodeBlobResponse(arena_alloc, blob_response.bytes);

            // Store in cache
            try blob_cache.put(new_hash_hex, fetched);

            break :blk try arena_alloc.dupe(u8, fetched);
        };
        defer allocator.free(content);

        const file_path = try std.fs.path.join(arena_alloc, &[_][]const u8{ workspace_root, entry.path });
        try fs.ensureParentDir(file_path);
        try fs.writeFile(file_path, content);
        updated += 1;
    }

    // Handle files deleted upstream
    for (state.entries) |entry| {
        if (head_entries.contains(entry.path)) continue;

        // File was deleted upstream
        if (local_modified.contains(entry.path)) {
            switch (strategy) {
                .theirs => {
                    resolved_conflicts += 1;
                },
                .ours => {
                    resolved_conflicts += 1;
                    continue;
                },
                .interactive => {
                    try conflicts.append(allocator, try allocator.dupe(u8, entry.path));
                    continue;
                },
            }
        }

        // Delete the local file
        const file_path = try std.fs.path.join(arena_alloc, &[_][]const u8{ workspace_root, entry.path });
        std.fs.cwd().deleteFile(file_path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
        updated += 1;
    }

    // Update manifest with new tree
    var entries: std.ArrayList(manifest.WorkspaceEntry) = .empty;
    for (head_tree.entries) |entry| {
        const hash_hex = try hexEncode(arena_alloc, entry.hash);
        try entries.append(arena_alloc, .{ .path = entry.path, .hash = hash_hex });
    }

    const updated_state = manifest.WorkspaceState{
        .version = state.version,
        .server = state.server,
        .account = state.account,
        .project = state.project,
        .position = state.position,
        .tree_hash = new_tree_hash_hex,
        .entries = try entries.toOwnedSlice(arena_alloc),
    };

    try manifest.save(arena_alloc, workspace_root, updated_state);

    const conflict_paths = try conflicts.toOwnedSlice(allocator);

    if (conflict_paths.len > 0) {
        std.debug.print("Synced with {d} file(s) updated", .{updated});
        if (cache_hits > 0) {
            std.debug.print(" ({d} from cache)", .{cache_hits});
        }
        std.debug.print(".\n", .{});
        std.debug.print("\nConflicts ({d}):\n", .{conflict_paths.len});
        for (conflict_paths) |path| {
            std.debug.print("  ! {s}\n", .{path});
        }
        std.debug.print("\nResolve conflicts manually, then run 'hif land' again.\n", .{});
    } else {
        std.debug.print("Synced: {d} file(s) updated", .{updated});
        if (cache_hits > 0) {
            std.debug.print(" ({d} from cache)", .{cache_hits});
        }
        std.debug.print(".\n", .{});
    }

    if (resolved_conflicts > 0 and conflict_paths.len == 0) {
        std.debug.print(
            "Resolved {d} conflict(s) using {s} strategy.\n",
            .{ resolved_conflicts, @tagName(strategy) },
        );
    }

    return .{ .updated = updated, .conflicts = conflict_paths };
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

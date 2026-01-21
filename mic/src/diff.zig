const std = @import("std");
const auth = @import("auth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const content_proto = @import("grpc/content_proto.zig");

/// Show differences between two tree states (null position = HEAD)
pub fn show(
    allocator: std.mem.Allocator,
    organization: []const u8,
    project: []const u8,
    from_position: ?u64,
    to_position: ?u64,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const tokens = try auth.requireTokensWithMessage(arena_alloc);
    const endpoint = try grpc_endpoint.parseServer(arena_alloc, tokens.server);

    // Fetch the "from" tree (null = HEAD)
    const from_tree = if (from_position) |pos|
        try fetchTreeAtPosition(arena_alloc, endpoint, organization, project, pos, tokens.access_token)
    else
        try fetchHeadTree(arena_alloc, endpoint, organization, project, tokens.access_token);

    // Fetch the "to" tree (null = HEAD)
    const to_tree = if (to_position) |pos|
        try fetchTreeAtPosition(arena_alloc, endpoint, organization, project, pos, tokens.access_token)
    else
        try fetchHeadTree(arena_alloc, endpoint, organization, project, tokens.access_token);

    // Compute diff (uses arena_alloc, no separate cleanup needed)
    const changes = try computeDiff(arena_alloc, from_tree.entries, to_tree.entries);

    // Format position labels (allocated from arena, so safe to use throughout function)
    const from_label = try formatPositionLabel(arena_alloc, from_position);
    const to_label = try formatPositionLabel(arena_alloc, to_position);

    if (changes.added.len == 0 and changes.deleted.len == 0 and changes.modified.len == 0) {
        std.debug.print("No changes between {s} and {s}\n", .{ from_label, to_label });
        return;
    }

    std.debug.print("Changes between {s} and {s}:\n\n", .{ from_label, to_label });

    // Display deletions
    for (changes.deleted) |path| {
        std.debug.print("\x1b[31m- {s}\x1b[0m\n", .{path});
    }

    // Display additions
    for (changes.added) |path| {
        std.debug.print("\x1b[32m+ {s}\x1b[0m\n", .{path});
    }

    // Display modifications
    for (changes.modified) |path| {
        std.debug.print("\x1b[33m~ {s}\x1b[0m\n", .{path});
    }

    std.debug.print("\n{d} added, {d} deleted, {d} modified\n", .{
        changes.added.len,
        changes.deleted.len,
        changes.modified.len,
    });
}

/// Format a position label, allocating from the provided allocator
fn formatPositionLabel(allocator: std.mem.Allocator, position: ?u64) ![]const u8 {
    if (position) |pos| {
        return std.fmt.allocPrint(allocator, "@{d}", .{pos});
    } else {
        return "HEAD";
    }
}

const TreeResult = struct {
    entries: []content_proto.TreeEntry,
    tree_hash: []const u8,
};

fn fetchTreeAtPosition(
    allocator: std.mem.Allocator,
    endpoint: grpc_endpoint.Endpoint,
    organization: []const u8,
    project: []const u8,
    position: u64,
    token: []const u8,
) !TreeResult {
    const request = try content_proto.encodeGetTreeAtPositionRequest(
        allocator,
        organization,
        project,
        position,
    );
    defer allocator.free(request);

    const response = try grpc_client.unaryCall(
        allocator,
        endpoint,
        "/micelio.content.v1.ContentService/GetTreeAtPosition",
        request,
        token,
    );
    defer allocator.free(response.bytes);

    const parsed = try content_proto.decodeTreeResponse(allocator, response.bytes);
    return .{ .entries = parsed.entries, .tree_hash = parsed.tree_hash };
}

fn fetchHeadTree(
    allocator: std.mem.Allocator,
    endpoint: grpc_endpoint.Endpoint,
    organization: []const u8,
    project: []const u8,
    token: []const u8,
) !TreeResult {
    const request = try content_proto.encodeGetHeadTreeRequest(
        allocator,
        organization,
        project,
    );
    defer allocator.free(request);

    const response = try grpc_client.unaryCall(
        allocator,
        endpoint,
        "/micelio.content.v1.ContentService/GetHeadTree",
        request,
        token,
    );
    defer allocator.free(response.bytes);

    const parsed = try content_proto.decodeTreeResponse(allocator, response.bytes);
    return .{ .entries = parsed.entries, .tree_hash = parsed.tree_hash };
}

const DiffResult = struct {
    added: []const []const u8,
    deleted: []const []const u8,
    modified: []const []const u8,
};

/// Compute the diff between two sets of tree entries.
/// All returned slices are allocated from the provided allocator.
fn computeDiff(
    allocator: std.mem.Allocator,
    from_entries: []content_proto.TreeEntry,
    to_entries: []content_proto.TreeEntry,
) !DiffResult {
    // Build maps for O(1) lookup - maps don't own the strings, just reference them
    var from_map = std.StringHashMap([]const u8).init(allocator);
    defer from_map.deinit();
    var to_map = std.StringHashMap([]const u8).init(allocator);
    defer to_map.deinit();

    // Populate maps - entries are borrowed, not owned
    for (from_entries) |entry| {
        try from_map.put(entry.path, entry.hash);
    }
    for (to_entries) |entry| {
        try to_map.put(entry.path, entry.hash);
    }

    // Build result lists
    var added: std.ArrayList([]const u8) = .empty;
    errdefer added.deinit(allocator);
    var deleted: std.ArrayList([]const u8) = .empty;
    errdefer deleted.deinit(allocator);
    var modified: std.ArrayList([]const u8) = .empty;
    errdefer modified.deinit(allocator);

    // Find deleted and modified files
    for (from_entries) |entry| {
        if (to_map.get(entry.path)) |to_hash| {
            if (!std.mem.eql(u8, entry.hash, to_hash)) {
                try modified.append(allocator, entry.path);
            }
        } else {
            try deleted.append(allocator, entry.path);
        }
    }

    // Find added files
    for (to_entries) |entry| {
        if (!from_map.contains(entry.path)) {
            try added.append(allocator, entry.path);
        }
    }

    // Transfer ownership to caller via toOwnedSlice
    return .{
        .added = try added.toOwnedSlice(allocator),
        .deleted = try deleted.toOwnedSlice(allocator),
        .modified = try modified.toOwnedSlice(allocator),
    };
}

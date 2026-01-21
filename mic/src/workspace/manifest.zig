const std = @import("std");
const fs = @import("fs.zig");

pub const WorkspaceEntry = struct {
    path: []const u8,
    hash: []const u8,
};

pub const WorkspaceState = struct {
    version: u32,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    position: ?u64 = null,
    tree_hash: []const u8,
    entries: []WorkspaceEntry,
};

const manifest_filename = "workspace.json";

pub fn load(
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
) !?std.json.Parsed(WorkspaceState) {
    const path = try manifestPath(allocator, workspace_root);
    defer allocator.free(path);

    const data = try fs.readFileAlloc(allocator, path, 10 * 1024 * 1024);
    if (data == null) return null;

    const parsed = try std.json.parseFromSlice(
        WorkspaceState,
        allocator,
        data.?,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    );
    return parsed;
}

pub fn save(
    allocator: std.mem.Allocator,
    workspace_root: []const u8,
    state: WorkspaceState,
) !void {
    try ensureMetadataDir(workspace_root);

    const path = try manifestPath(allocator, workspace_root);
    defer allocator.free(path);

    var payload_buf = std.Io.Writer.Allocating.init(allocator);
    defer payload_buf.deinit();
    const formatter = std.json.fmt(state, .{});
    try formatter.format(&payload_buf.writer);
    const payload = try payload_buf.toOwnedSlice();
    defer allocator.free(payload);

    // Use atomic write to prevent manifest corruption
    try fs.writeFileAtomic(allocator, path, payload);
}

pub fn ensureMetadataDir(workspace_root: []const u8) !void {
    const base = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ workspace_root, ".mic" });
    defer std.heap.page_allocator.free(base);
    try fs.ensureDir(base);
}

fn manifestPath(allocator: std.mem.Allocator, workspace_root: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &[_][]const u8{ workspace_root, ".mic", manifest_filename });
}

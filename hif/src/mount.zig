const std = @import("std");
const auth = @import("auth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const content_proto = @import("grpc/content_proto.zig");
const nfs = @import("fs/nfs.zig");
const workspace_fs = @import("workspace/fs.zig");

pub const DefaultPort: u16 = 20490;
const max_record_bytes: usize = 16 * 1024 * 1024;

pub fn mount(
    allocator: std.mem.Allocator,
    account: []const u8,
    project: []const u8,
    mount_path: ?[]const u8,
    port: u16,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const resolved_mount = try resolveMountPath(allocator, project, mount_path);
    defer allocator.free(resolved_mount);

    try ensureEmptyMountDir(resolved_mount);

    const tokens = try auth.requireTokensWithMessage(arena_alloc);
    const endpoint = try grpc_endpoint.parseServer(arena_alloc, tokens.server);

    var vfs = try buildVirtualFs(
        allocator,
        arena_alloc,
        endpoint,
        tokens.access_token,
        account,
        project,
    );
    defer vfs.deinit();

    std.debug.print(
        "Serving {s}/{s} via NFS on 127.0.0.1:{d}\n",
        .{ account, project, port },
    );
    std.debug.print(
        "Mount with: sudo mount -t nfs -o vers=3,proto=tcp,port={d} 127.0.0.1:/ {s}\n",
        .{ port, resolved_mount },
    );
    std.debug.print("Press Ctrl+C to stop.\n", .{});

    try serveNfs(allocator, &vfs, port);
}

pub fn unmount(allocator: std.mem.Allocator, mount_path: []const u8) !void {
    const resolved_mount = try resolveUnmountPath(allocator, mount_path);
    defer allocator.free(resolved_mount);

    var argv = [_][]const u8{ "umount", resolved_mount };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Error: failed to unmount {s}\n", .{resolved_mount});
                return error.UnmountFailed;
            }
        },
        else => {
            std.debug.print("Error: unmount interrupted for {s}\n", .{resolved_mount});
            return error.UnmountFailed;
        },
    }

    std.debug.print("Unmounted {s}\n", .{resolved_mount});
}

fn resolveMountPath(
    allocator: std.mem.Allocator,
    project: []const u8,
    mount_path: ?[]const u8,
) ![]u8 {
    const raw = mount_path orelse project;
    if (raw.len == 0) return error.InvalidPath;
    return allocator.dupe(u8, raw);
}

fn resolveUnmountPath(allocator: std.mem.Allocator, mount_path: []const u8) ![]u8 {
    if (mount_path.len == 0) return error.InvalidPath;
    return allocator.dupe(u8, mount_path);
}

fn ensureEmptyMountDir(path: []const u8) !void {
    try workspace_fs.ensureDir(path);
    var dir = try workspace_fs.openDir(path, true);
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |_| {
        return error.MountpointNotEmpty;
    }
}

fn buildVirtualFs(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    endpoint: grpc_endpoint.Endpoint,
    access_token: []const u8,
    account: []const u8,
    project: []const u8,
) !nfs.VirtualFs {
    const request = try content_proto.encodeGetHeadTreeRequest(arena, account, project);
    defer arena.free(request);

    const response = try grpc_client.unaryCall(
        arena,
        endpoint,
        "/micelio.content.v1.ContentService/GetHeadTree",
        request,
        access_token,
    );
    defer arena.free(response.bytes);

    const tree = try content_proto.decodeTreeResponse(arena, response.bytes);

    var vfs = try nfs.VirtualFs.init(allocator);
    errdefer vfs.deinit();

    for (tree.entries) |entry| {
        if (!isSafePath(entry.path)) {
            std.debug.print("Error: Unsafe path in tree: {s}\n", .{entry.path});
            return error.InvalidPath;
        }

        const vfs_path = try formatVfsPath(allocator, entry.path);
        defer allocator.free(vfs_path);

        try addParentDirs(&vfs, vfs_path);

        const blob_request = try content_proto.encodeGetBlobRequest(
            arena,
            account,
            project,
            entry.hash,
        );
        defer arena.free(blob_request);

        const blob_response = try grpc_client.unaryCall(
            arena,
            endpoint,
            "/micelio.content.v1.ContentService/GetBlob",
            blob_request,
            access_token,
        );
        defer arena.free(blob_response.bytes);

        const content = try content_proto.decodeBlobResponse(arena, blob_response.bytes);
        try vfs.addFile(vfs_path, content);
    }

    return vfs;
}

fn formatVfsPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return error.InvalidPath;
    if (path[0] == '/') return allocator.dupe(u8, path);
    return std.fmt.allocPrint(allocator, "/{s}", .{path});
}

fn addParentDirs(fs: *nfs.VirtualFs, path: []const u8) !void {
    if (path.len == 0) return;
    var idx: usize = 1;
    while (idx < path.len) : (idx += 1) {
        if (path[idx] == '/') {
            try fs.addDir(path[0..idx]);
        }
    }
}

fn serveNfs(allocator: std.mem.Allocator, fs: *nfs.VirtualFs, port: u16) !void {
    var server = std.net.StreamServer.init(.{});
    defer server.deinit();

    const address = try std.net.Address.parseIp4("127.0.0.1", port);
    try server.listen(address);

    var nfs_server = nfs.NfsServer.init(allocator, fs);

    while (true) {
        var conn = try server.accept();
        defer conn.stream.close();
        try handleConnection(allocator, &nfs_server, conn.stream);
    }
}

fn handleConnection(
    allocator: std.mem.Allocator,
    nfs_server: *nfs.NfsServer,
    stream: std.net.Stream,
) !void {
    var reader = stream.reader();
    var writer = stream.writer();

    while (true) {
        var header: [4]u8 = undefined;
        reader.readNoEof(&header) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };

        const marker = std.mem.readInt(u32, &header, .big);
        const length = marker & 0x7fff_ffff;
        if (length == 0 or length > max_record_bytes) return error.InvalidMessage;

        var record = try allocator.alloc(u8, 4 + length);
        defer allocator.free(record);
        @memcpy(record[0..4], &header);
        try reader.readNoEof(record[4..]);

        const response = try nfs_server.handleRecord(record);
        defer allocator.free(response);
        try writer.writeAll(response);
    }
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

test "resolveMountPath defaults to project name" {
    const allocator = std.testing.allocator;
    const resolved = try resolveMountPath(allocator, "app", null);
    defer allocator.free(resolved);
    try std.testing.expectEqualStrings("app", resolved);
}

test "resolveUnmountPath rejects empty path" {
    try std.testing.expectError(
        error.InvalidPath,
        resolveUnmountPath(std.testing.allocator, ""),
    );
}

test "resolveUnmountPath returns provided path" {
    const allocator = std.testing.allocator;
    const resolved = try resolveUnmountPath(allocator, "/mnt/app");
    defer allocator.free(resolved);
    try std.testing.expectEqualStrings("/mnt/app", resolved);
}

test "formatVfsPath prefixes slash for relative paths" {
    const allocator = std.testing.allocator;
    const result = try formatVfsPath(allocator, "src/main.zig");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/src/main.zig", result);
}

test "addParentDirs registers nested directories" {
    var fs = try nfs.VirtualFs.init(std.testing.allocator);
    defer fs.deinit();

    try addParentDirs(&fs, "/src/lib/main.zig");
    try std.testing.expect(fs.lookup("/src") != null);
    try std.testing.expect(fs.lookup("/src/lib") != null);
}

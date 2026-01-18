const std = @import("std");
const auth = @import("auth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const content_proto = @import("grpc/content_proto.zig");
const nfs = @import("fs/nfs.zig");
const workspace_fs = @import("workspace/fs.zig");
const config = @import("config.zig");
const hash = @import("core/hash.zig");

pub const DefaultPort: u16 = 20490;
const max_record_bytes: usize = 16 * 1024 * 1024;

const MountState = struct {
    mount_path: []u8,
    pid: u32,
    port: u16,

    fn deinit(self: *MountState, allocator: std.mem.Allocator) void {
        allocator.free(self.mount_path);
        self.* = undefined;
    }
};

const MountStateStore = struct {
    allocator: std.mem.Allocator,
    base_dir: []u8,

    fn init(allocator: std.mem.Allocator) !MountStateStore {
        const base_dir = try config.configDir(allocator);
        return .{
            .allocator = allocator,
            .base_dir = base_dir,
        };
    }

    fn initWithBaseDir(allocator: std.mem.Allocator, base_dir: []const u8) !MountStateStore {
        return .{
            .allocator = allocator,
            .base_dir = try allocator.dupe(u8, base_dir),
        };
    }

    fn deinit(self: *MountStateStore) void {
        self.allocator.free(self.base_dir);
        self.* = undefined;
    }

    fn ensureDir(self: *MountStateStore) !void {
        std.fs.makeDirAbsolute(self.base_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const dir = try mountStateDir(self.allocator, self.base_dir);
        defer self.allocator.free(dir);

        std.fs.makeDirAbsolute(dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    fn read(self: *MountStateStore, mount_path: []const u8) !?MountState {
        const state_path = try self.statePath(mount_path);
        defer self.allocator.free(state_path);

        const data = try workspace_fs.readFileAlloc(self.allocator, state_path, 1024 * 1024);
        if (data == null) return null;
        defer self.allocator.free(data.?);

        const parsed = try std.json.parseFromSlice(MountState, self.allocator, data.?, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        defer parsed.deinit();

        const stored = parsed.value;
        return .{
            .mount_path = try self.allocator.dupe(u8, stored.mount_path),
            .pid = stored.pid,
            .port = stored.port,
        };
    }

    fn write(self: *MountStateStore, mount_path: []const u8, pid: u32, port: u16) !void {
        try self.ensureDir();

        const state_path = try self.statePath(mount_path);
        defer self.allocator.free(state_path);

        var json_buf: std.ArrayList(u8) = .empty;
        defer json_buf.deinit(self.allocator);

        const payload = .{
            .mount_path = mount_path,
            .pid = pid,
            .port = port,
        };
        const formatter = std.json.fmt(payload, .{});
        try formatter.format(json_buf.writer(self.allocator));

        try workspace_fs.writeFileAtomic(self.allocator, state_path, json_buf.items);
    }

    fn remove(self: *MountStateStore, mount_path: []const u8) !void {
        const state_path = try self.statePath(mount_path);
        defer self.allocator.free(state_path);
        deleteFile(state_path) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
    }

    fn statePath(self: *MountStateStore, mount_path: []const u8) ![]u8 {
        const dir = try mountStateDir(self.allocator, self.base_dir);
        defer self.allocator.free(dir);

        const digest = hash.hash(mount_path);
        const hex = hash.formatHex(digest);
        const filename = try std.fmt.allocPrint(self.allocator, "{s}.json", .{hex[0..]});
        defer self.allocator.free(filename);

        return std.fs.path.join(self.allocator, &.{ dir, filename });
    }
};

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

    var store = try MountStateStore.init(allocator);
    defer store.deinit();

    if (try store.read(resolved_mount)) |existing| {
        defer existing.deinit(allocator);
        if (try isProcessAlive(existing.pid)) {
            std.debug.print(
                "Error: mount already active for {s} (pid {d})\n",
                .{ resolved_mount, existing.pid },
            );
            return error.MountAlreadyActive;
        }
        try store.remove(resolved_mount);
    }

    try store.write(resolved_mount, @intCast(std.posix.getpid()), port);
    defer store.remove(resolved_mount) catch {};

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

const UnmountOps = struct {
    run_umount: *const fn (allocator: std.mem.Allocator, mount_path: []const u8) anyerror!void,
    is_process_alive: *const fn (pid: u32) anyerror!bool,
    stop_process: *const fn (pid: u32) anyerror!void,
};

pub fn unmount(allocator: std.mem.Allocator, mount_path: []const u8) !void {
    var store = try MountStateStore.init(allocator);
    defer store.deinit();

    const ops = UnmountOps{
        .run_umount = runUmount,
        .is_process_alive = isProcessAlive,
        .stop_process = stopProcess,
    };

    try unmountWithStore(allocator, mount_path, &store, ops);
}

fn unmountWithStore(
    allocator: std.mem.Allocator,
    mount_path: []const u8,
    store: *MountStateStore,
    ops: UnmountOps,
) !void {
    const resolved_mount = try resolveUnmountPath(allocator, mount_path);
    defer allocator.free(resolved_mount);

    const existing = try store.read(resolved_mount);
    defer if (existing) |state| state.deinit(allocator);

    try ops.run_umount(allocator, resolved_mount);

    if (existing) |state| {
        const alive = try ops.is_process_alive(state.pid);
        if (alive) {
            ops.stop_process(state.pid) catch |err| switch (err) {
                error.ProcessNotFound => {},
                error.PermissionDenied => {
                    std.debug.print(
                        "Warning: insufficient permissions to stop mount pid {d}\n",
                        .{state.pid},
                    );
                },
                else => return err,
            };
        }

        const alive_after = if (alive) try ops.is_process_alive(state.pid) else false;
        if (!alive_after) {
            try store.remove(resolved_mount);
        }
    }

    std.debug.print("Unmounted {s}\n", .{resolved_mount});
}

fn runUmount(allocator: std.mem.Allocator, mount_path: []const u8) !void {
    var argv = [_][]const u8{ "umount", mount_path };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Error: failed to unmount {s}\n", .{mount_path});
                return error.UnmountFailed;
            }
        },
        else => {
            std.debug.print("Error: unmount interrupted for {s}\n", .{mount_path});
            return error.UnmountFailed;
        },
    }
}

fn resolveMountPath(
    allocator: std.mem.Allocator,
    project: []const u8,
    mount_path: ?[]const u8,
) ![]u8 {
    const raw = mount_path orelse project;
    return normalizeMountPath(allocator, raw);
}

fn resolveUnmountPath(allocator: std.mem.Allocator, mount_path: []const u8) ![]u8 {
    return normalizeMountPath(allocator, mount_path);
}

fn normalizeMountPath(allocator: std.mem.Allocator, mount_path: []const u8) ![]u8 {
    if (mount_path.len == 0) return error.InvalidPath;
    if (std.fs.path.isAbsolute(mount_path)) return allocator.dupe(u8, mount_path);

    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    return std.fs.path.join(allocator, &.{ cwd, mount_path });
}

fn mountStateDir(allocator: std.mem.Allocator, base_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base_dir, "mounts" });
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

fn deleteFile(path: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.deleteFileAbsolute(path);
    }
    return std.fs.cwd().deleteFile(path);
}

fn isProcessAlive(pid: u32) !bool {
    std.posix.kill(@intCast(pid), 0) catch |err| switch (err) {
        error.ProcessNotFound => return false,
        error.PermissionDenied => return true,
        else => return err,
    };
    return true;
}

fn stopProcess(pid: u32) !void {
    return std.posix.kill(@intCast(pid), std.posix.SIG.TERM);
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

const FakeUnmountState = struct {
    calls: [4][]const u8,
    count: usize,
    alive: bool,
};

var fake_unmount_state: ?*FakeUnmountState = null;

fn fakeRunUmount(allocator: std.mem.Allocator, mount_path: []const u8) !void {
    _ = allocator;
    _ = mount_path;
    if (fake_unmount_state) |state| {
        state.calls[state.count] = "umount";
        state.count += 1;
    }
}

fn fakeIsProcessAlive(pid: u32) !bool {
    _ = pid;
    if (fake_unmount_state) |state| {
        state.calls[state.count] = "alive";
        state.count += 1;
        return state.alive;
    }
    return false;
}

fn fakeStopProcess(pid: u32) !void {
    _ = pid;
    if (fake_unmount_state) |state| {
        state.calls[state.count] = "stop";
        state.count += 1;
        state.alive = false;
    }
}

test "resolveMountPath defaults to project name" {
    const allocator = std.testing.allocator;
    const resolved = try resolveMountPath(allocator, "app", null);
    defer allocator.free(resolved);
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    const expected = try std.fs.path.join(allocator, &.{ cwd, "app" });
    defer allocator.free(expected);
    try std.testing.expectEqualStrings(expected, resolved);
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

test "mount state store write and remove" {
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    const base_dir = try temp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_dir);

    var store = try MountStateStore.initWithBaseDir(allocator, base_dir);
    defer store.deinit();

    const mount_path = try std.fs.path.join(allocator, &.{ base_dir, "mnt" });
    defer allocator.free(mount_path);

    try store.write(mount_path, 4242, 20490);

    const state = try store.read(mount_path);
    try std.testing.expect(state != null);
    defer state.?.deinit(allocator);
    try std.testing.expectEqualStrings(mount_path, state.?.mount_path);
    try std.testing.expectEqual(@as(u32, 4242), state.?.pid);
    try std.testing.expectEqual(@as(u16, 20490), state.?.port);

    try store.remove(mount_path);

    const missing = try store.read(mount_path);
    try std.testing.expect(missing == null);
}

test "unmount runs before stopping process and clears state" {
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    const base_dir = try temp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_dir);

    var store = try MountStateStore.initWithBaseDir(allocator, base_dir);
    defer store.deinit();

    const mount_path = try std.fs.path.join(allocator, &.{ base_dir, "mnt" });
    defer allocator.free(mount_path);

    try store.write(mount_path, 4242, 20490);

    var state = FakeUnmountState{
        .calls = undefined,
        .count = 0,
        .alive = true,
    };
    fake_unmount_state = &state;
    defer fake_unmount_state = null;

    const ops = UnmountOps{
        .run_umount = fakeRunUmount,
        .is_process_alive = fakeIsProcessAlive,
        .stop_process = fakeStopProcess,
    };

    try unmountWithStore(allocator, mount_path, &store, ops);

    try std.testing.expectEqual(@as(usize, 4), state.count);
    try std.testing.expectEqualStrings("umount", state.calls[0]);
    try std.testing.expectEqualStrings("alive", state.calls[1]);
    try std.testing.expectEqualStrings("stop", state.calls[2]);
    try std.testing.expectEqualStrings("alive", state.calls[3]);

    const missing = try store.read(mount_path);
    try std.testing.expect(missing == null);
}

test "unmount without state only runs umount" {
    const allocator = std.testing.allocator;
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    const base_dir = try temp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_dir);

    var store = try MountStateStore.initWithBaseDir(allocator, base_dir);
    defer store.deinit();

    const mount_path = try std.fs.path.join(allocator, &.{ base_dir, "mnt" });
    defer allocator.free(mount_path);

    var state = FakeUnmountState{
        .calls = undefined,
        .count = 0,
        .alive = false,
    };
    fake_unmount_state = &state;
    defer fake_unmount_state = null;

    const ops = UnmountOps{
        .run_umount = fakeRunUmount,
        .is_process_alive = fakeIsProcessAlive,
        .stop_process = fakeStopProcess,
    };

    try unmountWithStore(allocator, mount_path, &store, ops);

    try std.testing.expectEqual(@as(usize, 1), state.count);
    try std.testing.expectEqualStrings("umount", state.calls[0]);
}

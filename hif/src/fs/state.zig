const std = @import("std");
const auth = @import("hif/auth.zig");
const cache_mod = @import("hif/cache.zig");
const content_proto = @import("hif/grpc/content_proto.zig");
const grpc_client = @import("hif/grpc/client.zig");
const grpc_endpoint = @import("hif/grpc/endpoint.zig");
const overlay_mod = @import("hif/fs/overlay.zig");

pub const EntryKind = enum {
    file,
    dir,
};

pub const DirEntry = struct {
    name: []const u8,
    path: []const u8,
    kind: EntryKind,
    handle: u64,
};

pub const Attr = struct {
    kind: EntryKind,
    size: u64,
    fileid: u64,
    mode: u32,
    mtime: i64,
};

const FileEntry = struct {
    hash: []const u8,
    hash_hex: []const u8,
};

pub const RepoState = struct {
    allocator: std.mem.Allocator,
    server: []const u8,
    account: []const u8,
    project: []const u8,
    entries: std.StringHashMap(FileEntry),
    dirs: std.StringHashMap(void),
    handles: std.StringHashMap(u64),
    paths: std.AutoHashMap(u64, []const u8),
    next_id: u64,
    overlay: overlay_mod.Overlay,
    cache: cache_mod.BlobCache,

    pub fn init(
        allocator: std.mem.Allocator,
        server: []const u8,
        account: []const u8,
        project: []const u8,
        state_dir: []const u8,
    ) !RepoState {
        var cache = try cache_mod.BlobCache.init(allocator, .{});
        errdefer cache.deinit();

        const session_path = try std.fs.path.join(allocator, &.{ state_dir, "session.json" });
        defer allocator.free(session_path);

        var overlay = try overlay_mod.Overlay.init(allocator, session_path, account, project);
        errdefer overlay.deinit();

        var state = RepoState{
            .allocator = allocator,
            .server = try allocator.dupe(u8, server),
            .account = try allocator.dupe(u8, account),
            .project = try allocator.dupe(u8, project),
            .entries = std.StringHashMap(FileEntry).init(allocator),
            .dirs = std.StringHashMap(void).init(allocator),
            .handles = std.StringHashMap(u64).init(allocator),
            .paths = std.AutoHashMap(u64, []const u8).init(allocator),
            .next_id = 1,
            .overlay = overlay,
            .cache = cache,
        };
        errdefer state.deinit();

        try state.loadTree();
        return state;
    }

    pub fn deinit(self: *RepoState) void {
        var entry_iter = self.entries.iterator();
        while (entry_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.hash);
            self.allocator.free(entry.value_ptr.hash_hex);
        }
        self.entries.deinit();

        var dir_iter = self.dirs.iterator();
        while (dir_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.dirs.deinit();

        var handle_iter = self.handles.iterator();
        while (handle_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.handles.deinit();

        var path_iter = self.paths.iterator();
        while (path_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.paths.deinit();

        self.overlay.deinit();
        self.cache.deinit();

        self.allocator.free(self.server);
        self.allocator.free(self.account);
        self.allocator.free(self.project);
        self.* = undefined;
    }

    pub fn pathFromHandle(self: *const RepoState, handle: u64) ?[]const u8 {
        return self.paths.get(handle);
    }

    pub fn handleForPath(self: *RepoState, path: []const u8) !u64 {
        if (self.handles.get(path)) |existing| return existing;

        const owned_path = try self.allocator.dupe(u8, path);
        const handle = self.next_id;
        self.next_id += 1;

        try self.handles.put(owned_path, handle);
        try self.paths.put(handle, owned_path);
        return handle;
    }

    pub fn lookup(self: *RepoState, dir_path: []const u8, name: []const u8) !?DirEntry {
        const child_path = try joinPath(self.allocator, dir_path, name);
        defer self.allocator.free(child_path);

        if (self.isDeleted(child_path)) return null;

        if (self.overlay.get(child_path)) |overlay| {
            if (overlay.change_type == .deleted) return null;
            const handle = try self.handleForPath(child_path);
            return .{ .name = name, .path = try self.allocator.dupe(u8, child_path), .kind = .file, .handle = handle };
        }

        if (self.entries.contains(child_path)) {
            const handle = try self.handleForPath(child_path);
            return .{ .name = name, .path = try self.allocator.dupe(u8, child_path), .kind = .file, .handle = handle };
        }

        if (self.dirs.contains(child_path)) {
            const handle = try self.handleForPath(child_path);
            return .{ .name = name, .path = try self.allocator.dupe(u8, child_path), .kind = .dir, .handle = handle };
        }

        return null;
    }

    pub fn listDir(self: *RepoState, dir_path: []const u8) ![]DirEntry {
        var entries = std.ArrayList(DirEntry).init(self.allocator, null);
        errdefer entries.deinit();

        var seen = std.StringHashMap(EntryKind).init(self.allocator);
        defer seen.deinit();

        try self.collectDirEntries(dir_path, &entries, &seen);
        try self.collectOverlayEntries(dir_path, &entries, &seen);

        return try entries.toOwnedSlice();
    }

    pub fn getAttr(self: *RepoState, path: []const u8) !?Attr {
        if (std.mem.eql(u8, path, "")) {
            const handle = try self.handleForPath("");
            return .{ .kind = .dir, .size = 0, .fileid = handle, .mode = 0o755, .mtime = std.time.timestamp() };
        }

        if (self.overlay.get(path)) |overlay| {
            if (overlay.change_type == .deleted) return null;
            const handle = try self.handleForPath(path);
            return .{ .kind = .file, .size = overlay.content.len, .fileid = handle, .mode = 0o644, .mtime = std.time.timestamp() };
        }

        if (self.entries.get(path)) |entry| {
            const handle = try self.handleForPath(path);
            const size = try self.fileSize(entry);
            return .{ .kind = .file, .size = size, .fileid = handle, .mode = 0o644, .mtime = std.time.timestamp() };
        }

        if (self.dirs.contains(path)) {
            const handle = try self.handleForPath(path);
            return .{ .kind = .dir, .size = 0, .fileid = handle, .mode = 0o755, .mtime = std.time.timestamp() };
        }

        return null;
    }

    pub fn readFile(self: *RepoState, path: []const u8, offset: u64, count: u32) !?[]u8 {
        if (self.overlay.get(path)) |overlay| {
            if (overlay.change_type == .deleted) return null;
            return sliceContent(self.allocator, overlay.content, offset, count);
        }

        const entry = self.entries.get(path) orelse return null;
        const content = try self.fetchFile(entry);
        defer self.allocator.free(content);

        return sliceContent(self.allocator, content, offset, count);
    }

    pub fn writeFile(self: *RepoState, path: []const u8, offset: u64, data: []const u8) !usize {
        const existing = if (self.overlay.get(path)) |overlay| overlay.content else blk: {
            if (self.entries.get(path)) |entry| {
                const content = try self.fetchFile(entry);
                defer self.allocator.free(content);
                break :blk try self.allocator.dupe(u8, content);
            }
            break :blk &[_]u8{};
        };
        defer if (existing.len > 0 and self.overlay.get(path) == null) self.allocator.free(existing);

        const new_len = @max(existing.len, @as(usize, @intCast(offset)) + data.len);
        var new_content = try self.allocator.alloc(u8, new_len);
        @memset(new_content, 0);
        if (existing.len > 0) {
            @memcpy(new_content[0..existing.len], existing);
        }
        @memcpy(new_content[@intCast(offset) .. @intCast(offset) + data.len], data);

        const change_type: overlay_mod.ChangeType = if (self.entries.contains(path)) .modified else .added;
        try self.overlay.setFile(path, new_content, change_type);
        self.addDirPrefixes(path) catch {};
        self.allocator.free(new_content);
        return data.len;
    }

    pub fn createFile(self: *RepoState, dir_path: []const u8, name: []const u8) !DirEntry {
        const child_path = try joinPath(self.allocator, dir_path, name);
        defer self.allocator.free(child_path);

        try self.overlay.setFile(child_path, &[_]u8{}, .added);
        self.addDirPrefixes(child_path) catch {};
        const handle = try self.handleForPath(child_path);
        return .{ .name = name, .path = try self.allocator.dupe(u8, child_path), .kind = .file, .handle = handle };
    }

    pub fn makeDir(self: *RepoState, dir_path: []const u8, name: []const u8) !DirEntry {
        const child_path = try joinPath(self.allocator, dir_path, name);
        defer self.allocator.free(child_path);

        try self.ensureDir(child_path);
        const handle = try self.handleForPath(child_path);
        return .{ .name = name, .path = try self.allocator.dupe(u8, child_path), .kind = .dir, .handle = handle };
    }

    pub fn removePath(self: *RepoState, path: []const u8) !void {
        try self.overlay.remove(path);
    }

    pub fn renamePath(self: *RepoState, from: []const u8, to: []const u8) !void {
        if (self.overlay.get(from)) |overlay| {
            if (overlay.change_type != .deleted) {
                try self.overlay.setFile(to, overlay.content, .modified);
            }
            try self.overlay.remove(from);
            return;
        }

        if (self.entries.get(from)) |entry| {
            const content = try self.fetchFile(entry);
            defer self.allocator.free(content);
            try self.overlay.setFile(to, content, .added);
            try self.overlay.remove(from);
            return;
        }

        if (self.dirs.contains(from)) {
            try self.ensureDir(to);
            return;
        }
    }

    pub fn prefetchDirectory(self: *RepoState, dir_path: []const u8) void {
        const entries = self.listDir(dir_path) catch return;
        defer {
            for (entries) |entry| {
                self.allocator.free(entry.name);
                self.allocator.free(entry.path);
            }
            self.allocator.free(entries);
        }

        for (entries) |entry| {
            if (entry.kind != .file) continue;
            const path = entry.path;
            if (self.overlay.get(path)) |overlay| {
                if (overlay.change_type == .deleted) continue;
                _ = self.cache.put(path, overlay.content) catch {};
                continue;
            }

            if (self.entries.get(path)) |file_entry| {
                _ = self.fetchFile(file_entry) catch {};
            }
        }
    }

    fn loadTree(self: *RepoState) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);
        const endpoint = try grpc_endpoint.parseServer(arena_alloc, self.server);
        const request = try content_proto.encodeGetHeadTreeRequest(arena_alloc, self.account, self.project);
        defer arena_alloc.free(request);

        const response = try grpc_client.unaryCall(
            arena_alloc,
            endpoint,
            "/micelio.content.v1.ContentService/GetHeadTree",
            request,
            access_token,
        );
        defer arena_alloc.free(response.bytes);

        const tree = try content_proto.decodeTreeResponse(arena_alloc, response.bytes);
        for (tree.entries) |entry| {
            const path = normalizePath(entry.path);
            if (path.len == 0) continue;

            const owned_path = try self.allocator.dupe(u8, path);
            const owned_hash = try self.allocator.dupe(u8, entry.hash);
            const hash_hex = try hexEncode(self.allocator, entry.hash);
            try self.entries.put(owned_path, .{ .hash = owned_hash, .hash_hex = hash_hex });
            try self.addDirPrefixes(path);
        }

        _ = try self.handleForPath("");
    }

    fn collectDirEntries(
        self: *RepoState,
        dir_path: []const u8,
        entries: *std.ArrayList(DirEntry),
        seen: *std.StringHashMap(EntryKind),
    ) !void {
        var dir_iter = self.dirs.iterator();
        while (dir_iter.next()) |entry| {
            const child = childName(dir_path, entry.key_ptr.*) orelse continue;
            if (seen.contains(child.name)) continue;
            try seen.put(try self.allocator.dupe(u8, child.name), .dir);
            const handle = try self.handleForPath(child.path);
            try entries.append(.{ .name = try self.allocator.dupe(u8, child.name), .path = try self.allocator.dupe(u8, child.path), .kind = .dir, .handle = handle });
        }

        var file_iter = self.entries.iterator();
        while (file_iter.next()) |entry| {
            const child = childName(dir_path, entry.key_ptr.*) orelse continue;
            if (child.kind != .file) continue;
            if (self.isDeleted(child.path)) continue;
            if (seen.contains(child.name)) continue;
            try seen.put(try self.allocator.dupe(u8, child.name), .file);
            const handle = try self.handleForPath(child.path);
            try entries.append(.{ .name = try self.allocator.dupe(u8, child.name), .path = try self.allocator.dupe(u8, child.path), .kind = .file, .handle = handle });
        }
    }

    fn collectOverlayEntries(
        self: *RepoState,
        dir_path: []const u8,
        entries: *std.ArrayList(DirEntry),
        seen: *std.StringHashMap(EntryKind),
    ) !void {
        var iter = self.overlay.entries.iterator();
        while (iter.next()) |entry| {
            const overlay = entry.value_ptr.*;
            if (overlay.change_type == .deleted) continue;
            const child = childName(dir_path, entry.key_ptr.*) orelse continue;
            if (child.kind != .file) continue;
            if (seen.contains(child.name)) continue;
            try seen.put(try self.allocator.dupe(u8, child.name), .file);
            const handle = try self.handleForPath(child.path);
            try entries.append(.{ .name = try self.allocator.dupe(u8, child.name), .path = try self.allocator.dupe(u8, child.path), .kind = .file, .handle = handle });
        }
    }

    fn ensureDir(self: *RepoState, path: []const u8) !void {
        if (self.dirs.contains(path)) return;
        const owned = try self.allocator.dupe(u8, path);
        try self.dirs.put(owned, {});
        try self.addDirPrefixes(path);
    }

    fn addDirPrefixes(self: *RepoState, path: []const u8) !void {
        var iter = std.mem.splitBackwardsScalar(u8, path, '/');
        _ = iter.next();

        while (iter.next()) |parent| {
            if (parent.len == 0) continue;
            if (self.dirs.contains(parent)) continue;
            try self.dirs.put(try self.allocator.dupe(u8, parent), {});
        }
    }

    fn isDeleted(self: *RepoState, path: []const u8) bool {
        if (self.overlay.get(path)) |overlay| {
            return overlay.change_type == .deleted;
        }
        return false;
    }

    fn fetchFile(self: *RepoState, entry: FileEntry) ![]u8 {
        if (self.cache.get(entry.hash_hex)) |cached| {
            return cached;
        }

        const access_token = try auth.requireAccessTokenWithMessage(self.allocator);
        const endpoint = try grpc_endpoint.parseServer(self.allocator, self.server);
        const request = try content_proto.encodeGetBlobRequest(self.allocator, self.account, self.project, entry.hash);
        defer self.allocator.free(request);

        const response = try grpc_client.unaryCall(
            self.allocator,
            endpoint,
            "/micelio.content.v1.ContentService/GetBlob",
            request,
            access_token,
        );
        defer self.allocator.free(response.bytes);

        const blob = try content_proto.decodeBlobResponse(self.allocator, response.bytes);
        try self.cache.put(entry.hash_hex, blob);
        return try self.allocator.dupe(u8, blob);
    }

    fn fileSize(self: *RepoState, entry: FileEntry) !u64 {
        if (self.cache.get(entry.hash_hex)) |cached| {
            const size = cached.len;
            self.allocator.free(cached);
            return size;
        }

        const content = try self.fetchFile(entry);
        defer self.allocator.free(content);
        return content.len;
    }
};

fn normalizePath(path: []const u8) []const u8 {
    if (path.len == 0) return path;
    if (path[0] == '/') return path[1..];
    return path;
}

fn joinPath(allocator: std.mem.Allocator, dir_path: []const u8, name: []const u8) ![]u8 {
    if (dir_path.len == 0) {
        return allocator.dupe(u8, name);
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, name });
}

const ChildInfo = struct {
    name: []const u8,
    path: []const u8,
    kind: EntryKind,
};

fn childName(dir_path: []const u8, entry_path: []const u8) ?ChildInfo {
    if (dir_path.len > 0) {
        if (!std.mem.startsWith(u8, entry_path, dir_path)) return null;
        if (entry_path.len <= dir_path.len) return null;
        if (entry_path[dir_path.len] != '/') return null;
        const rest = entry_path[dir_path.len + 1 ..];
        return childInfoFromRest(rest, dir_path, entry_path);
    }

    return childInfoFromRest(entry_path, "", entry_path);
}

fn childInfoFromRest(rest: []const u8, dir_path: []const u8, entry_path: []const u8) ?ChildInfo {
    const slash_index = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    const name = rest[0..slash_index];
    if (name.len == 0) return null;
    const kind: EntryKind = if (slash_index == rest.len) .file else .dir;
    const child_path = if (dir_path.len == 0) entry_path[0 .. name.len] else entry_path[0 .. dir_path.len + 1 + name.len];
    return .{ .name = name, .path = child_path, .kind = kind };
}

fn sliceContent(allocator: std.mem.Allocator, content: []const u8, offset: u64, count: u32) ![]u8 {
    if (offset >= content.len) return allocator.dupe(u8, &[_]u8{});
    const start: usize = @intCast(offset);
    const available = content.len - start;
    const to_read = @min(available, @as(usize, count));
    return allocator.dupe(u8, content[start .. start + to_read]);
}

fn hexEncode(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const hex_chars = "0123456789abcdef";
    var out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, idx| {
        out[idx * 2] = hex_chars[b >> 4];
        out[idx * 2 + 1] = hex_chars[b & 0x0f];
    }
    return out;
}

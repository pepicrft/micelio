//! Minimal NFSv3 server core for hif-fs.
//!
//! This module implements NFSv3 RPC parsing and responses for a small subset
//! of procedures backed by an in-memory virtual filesystem. It is intentionally
//! read-only and transport-agnostic so the network daemon can be layered on top.

const std = @import("std");

pub const NFS_PROGRAM: u32 = 100003;
pub const NFS_VERSION: u32 = 3;

const RpcMessageType = enum(u32) {
    call = 0,
    reply = 1,
};

const RpcReplyStat = enum(u32) {
    accepted = 0,
    denied = 1,
};

const RpcAcceptStat = enum(u32) {
    success = 0,
    prog_unavail = 1,
    prog_mismatch = 2,
    proc_unavail = 3,
    garbage_args = 4,
    system_err = 5,
};

const NfsProcedure = enum(u32) {
    null = 0,
    getattr = 1,
    lookup = 3,
    read = 6,
    readdir = 16,
};

pub const NfsStatus = enum(u32) {
    ok = 0,
    perm = 1,
    noent = 2,
    io = 5,
    nxio = 6,
    acces = 13,
    exist = 17,
    notdir = 20,
    isdir = 21,
    inval = 22,
    fbig = 27,
    nospc = 28,
    rofs = 30,
    mlink = 31,
    nametoolong = 63,
    notempty = 66,
    dquot = 69,
    stale = 70,
    remote = 71,
    badhandle = 10001,
    notsupp = 10004,
    serverfault = 10006,
};

const NfsFileType = enum(u32) {
    reg = 1,
    dir = 2,
};

const NodeType = enum {
    file,
    dir,
};

const Node = struct {
    kind: NodeType,
    content: []const u8,
};

pub const VirtualFs = struct {
    allocator: std.mem.Allocator,
    nodes: std.StringHashMap(Node),

    pub fn init(allocator: std.mem.Allocator) !VirtualFs {
        var fs = VirtualFs{
            .allocator = allocator,
            .nodes = std.StringHashMap(Node).init(allocator),
        };
        try fs.addDir("/");
        return fs;
    }

    pub fn deinit(self: *VirtualFs) void {
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            self.allocator.free(key);
            if (entry.value_ptr.kind == .file) {
                self.allocator.free(entry.value_ptr.content);
            }
        }
        self.nodes.deinit();
    }

    pub fn addDir(self: *VirtualFs, path: []const u8) !void {
        const normalized = try normalizePath(self.allocator, path);
        errdefer self.allocator.free(normalized);
        if (self.nodes.contains(normalized)) return;
        try self.nodes.put(normalized, .{ .kind = .dir, .content = "" });
    }

    pub fn addFile(self: *VirtualFs, path: []const u8, content: []const u8) !void {
        const normalized = try normalizePath(self.allocator, path);
        errdefer self.allocator.free(normalized);
        if (self.nodes.contains(normalized)) return;
        const copy = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(copy);
        try self.nodes.put(normalized, .{ .kind = .file, .content = copy });
    }

    pub fn lookup(self: *VirtualFs, path: []const u8) ?Node {
        return self.nodes.get(path);
    }

    pub fn listDir(self: *VirtualFs, path: []const u8, allocator: std.mem.Allocator) !std.ArrayList(DirEntry) {
        var entries = std.ArrayList(DirEntry).init(allocator);
        errdefer entries.deinit();
        const prefix = try buildPrefix(allocator, path);
        defer allocator.free(prefix);

        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (std.mem.eql(u8, key, path)) continue;
            if (!std.mem.startsWith(u8, key, prefix)) continue;

            const remainder = key[prefix.len..];
            if (remainder.len == 0) continue;
            if (std.mem.indexOfScalar(u8, remainder, '/')) |_| continue;

            try entries.append(.{
                .name = remainder,
                .path = key,
                .kind = entry.value_ptr.kind,
            });
        }

        return entries;
    }
};

const DirEntry = struct {
    name: []const u8,
    path: []const u8,
    kind: NodeType,
};

pub const NfsServer = struct {
    allocator: std.mem.Allocator,
    fs: *VirtualFs,

    pub fn init(allocator: std.mem.Allocator, fs: *VirtualFs) NfsServer {
        return .{ .allocator = allocator, .fs = fs };
    }

    pub fn handleCall(self: *NfsServer, input: []const u8) ![]u8 {
        var reader = XdrReader.init(input);
        const call = reader.readRpcCall() catch |err| {
            return try self.buildRpcError(0, .garbage_args, err);
        };

        if (call.prog != NFS_PROGRAM) {
            return try self.buildRpcError(call.xid, .prog_unavail, error.UnsupportedProgram);
        }
        if (call.vers != NFS_VERSION) {
            return try self.buildRpcError(call.xid, .prog_mismatch, error.UnsupportedVersion);
        }

        const proc = std.meta.intToEnum(NfsProcedure, call.proc) catch {
            return try self.buildRpcError(call.xid, .proc_unavail, error.UnsupportedProcedure);
        };

        var writer = XdrWriter.init(self.allocator);
        errdefer writer.deinit();
        try writer.writeRpcReplyHeader(call.xid, .success);

        switch (proc) {
            .null => {},
            .getattr => try self.handleGetattr(&reader, &writer),
            .lookup => try self.handleLookup(&reader, &writer),
            .read => try self.handleRead(&reader, &writer),
            .readdir => try self.handleReaddir(&reader, &writer),
        }

        return writer.toOwnedSlice();
    }

    pub fn handleRecord(self: *NfsServer, input: []const u8) ![]u8 {
        if (input.len < 4) return error.InvalidMessage;
        const marker = std.mem.readInt(u32, input[0..4], .big);
        const last = (marker & 0x8000_0000) != 0;
        const length = marker & 0x7fff_ffff;
        if (!last) return error.InvalidMessage;
        if (input.len < 4 + length) return error.InvalidMessage;

        const payload = input[4 .. 4 + length];
        const response = try self.handleCall(payload);
        errdefer self.allocator.free(response);

        var out = try std.ArrayList(u8).initCapacity(self.allocator, 4 + response.len);
        errdefer out.deinit();
        const out_marker = 0x8000_0000 | @as(u32, @intCast(response.len));
        var marker_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &marker_buf, out_marker, .big);
        try out.appendSlice(&marker_buf);
        try out.appendSlice(response);
        self.allocator.free(response);
        return out.toOwnedSlice();
    }

    fn handleGetattr(self: *NfsServer, reader: *XdrReader, writer: *XdrWriter) !void {
        const handle = try reader.readOpaque();
        const node = self.fs.lookup(handle) orelse {
            try writer.writeU32(@intFromEnum(NfsStatus.noent));
            return;
        };

        try writer.writeU32(@intFromEnum(NfsStatus.ok));
        try writeFattr3(writer, handle, node);
    }

    fn handleLookup(self: *NfsServer, reader: *XdrReader, writer: *XdrWriter) !void {
        const dir_handle = try reader.readOpaque();
        const name = try reader.readString();

        const dir = self.fs.lookup(dir_handle) orelse {
            try writer.writeU32(@intFromEnum(NfsStatus.noent));
            try writePostOpAttr(writer, null, null);
            return;
        };
        if (dir.kind != .dir) {
            try writer.writeU32(@intFromEnum(NfsStatus.notdir));
            try writePostOpAttr(writer, dir_handle, dir);
            return;
        }
        if (name.len == 0) {
            try writer.writeU32(@intFromEnum(NfsStatus.inval));
            try writePostOpAttr(writer, dir_handle, dir);
            return;
        }
        if (name.len > 255) {
            try writer.writeU32(@intFromEnum(NfsStatus.nametoolong));
            try writePostOpAttr(writer, dir_handle, dir);
            return;
        }

        const child_path = try joinPath(self.allocator, dir_handle, name);
        defer self.allocator.free(child_path);

        const child = self.fs.lookup(child_path) orelse {
            try writer.writeU32(@intFromEnum(NfsStatus.noent));
            try writePostOpAttr(writer, dir_handle, dir);
            return;
        };

        try writer.writeU32(@intFromEnum(NfsStatus.ok));
        try writer.writeOpaque(child_path);
        try writePostOpAttr(writer, child_path, child);
        try writePostOpAttr(writer, dir_handle, dir);
    }

    fn handleRead(self: *NfsServer, reader: *XdrReader, writer: *XdrWriter) !void {
        const handle = try reader.readOpaque();
        const offset = try reader.readU64();
        const count = try reader.readU32();

        const node = self.fs.lookup(handle) orelse {
            try writer.writeU32(@intFromEnum(NfsStatus.noent));
            try writePostOpAttr(writer, null, null);
            return;
        };
        if (node.kind != .file) {
            try writer.writeU32(@intFromEnum(NfsStatus.isdir));
            try writePostOpAttr(writer, handle, node);
            return;
        }

        const size = node.content.len;
        if (offset >= size) {
            try writer.writeU32(@intFromEnum(NfsStatus.ok));
            try writePostOpAttr(writer, handle, node);
            try writer.writeU32(0);
            try writer.writeBool(true);
            try writer.writeOpaque("");
            return;
        }

        const max_len = std.math.min(@as(usize, @intCast(count)), size - offset);
        const data = node.content[@intCast(offset) .. @intCast(offset) + max_len];
        const eof = offset + max_len >= size;

        try writer.writeU32(@intFromEnum(NfsStatus.ok));
        try writePostOpAttr(writer, handle, node);
        try writer.writeU32(@intCast(max_len));
        try writer.writeBool(eof);
        try writer.writeOpaque(data);
    }

    fn handleReaddir(self: *NfsServer, reader: *XdrReader, writer: *XdrWriter) !void {
        const handle = try reader.readOpaque();
        const cookie = try reader.readU64();
        _ = try reader.readFixedOpaque(8);
        _ = try reader.readU32();

        const node = self.fs.lookup(handle) orelse {
            try writer.writeU32(@intFromEnum(NfsStatus.noent));
            try writePostOpAttr(writer, null, null);
            return;
        };
        if (node.kind != .dir) {
            try writer.writeU32(@intFromEnum(NfsStatus.notdir));
            try writePostOpAttr(writer, handle, node);
            return;
        }

        var entries = try self.fs.listDir(handle, self.allocator);
        defer entries.deinit();

        try writer.writeU32(@intFromEnum(NfsStatus.ok));
        try writePostOpAttr(writer, handle, node);
        try writer.writeFixedOpaque(&[_]u8{0} ** 8);

        if (cookie >= entries.items.len) {
            try writer.writeBool(false);
            try writer.writeBool(true);
            return;
        }

        var index: usize = @intCast(cookie);
        while (index < entries.items.len) : (index += 1) {
            const entry = entries.items[index];
            const file_id = fileIdForPath(entry.path);
            try writer.writeBool(true);
            try writer.writeU64(file_id);
            try writer.writeString(entry.name);
            try writer.writeU64(@intCast(index + 1));
        }
        try writer.writeBool(false);
        try writer.writeBool(true);
    }

    fn buildRpcError(self: *NfsServer, xid: u32, status: RpcAcceptStat, err: anyerror) ![]u8 {
        _ = err;
        var writer = XdrWriter.init(self.allocator);
        errdefer writer.deinit();
        try writer.writeRpcReplyHeader(xid, status);
        return writer.toOwnedSlice();
    }
};

const RpcCall = struct {
    xid: u32,
    prog: u32,
    vers: u32,
    proc: u32,
};

const XdrReader = struct {
    buf: []const u8,
    pos: usize,

    fn init(buf: []const u8) XdrReader {
        return .{ .buf = buf, .pos = 0 };
    }

    fn readU32(self: *XdrReader) !u32 {
        if (self.pos + 4 > self.buf.len) return error.InvalidMessage;
        const value = std.mem.readInt(u32, self.buf[self.pos .. self.pos + 4], .big);
        self.pos += 4;
        return value;
    }

    fn readU64(self: *XdrReader) !u64 {
        if (self.pos + 8 > self.buf.len) return error.InvalidMessage;
        const value = std.mem.readInt(u64, self.buf[self.pos .. self.pos + 8], .big);
        self.pos += 8;
        return value;
    }

    fn readBool(self: *XdrReader) !bool {
        return (try self.readU32()) != 0;
    }

    fn readOpaque(self: *XdrReader) ![]const u8 {
        const len = try self.readU32();
        if (self.pos + len > self.buf.len) return error.InvalidMessage;
        const start = self.pos;
        self.pos += len;
        self.skipPadding(len);
        return self.buf[start .. start + len];
    }

    fn readFixedOpaque(self: *XdrReader, len: usize) ![]const u8 {
        if (self.pos + len > self.buf.len) return error.InvalidMessage;
        const start = self.pos;
        self.pos += len;
        self.skipPadding(len);
        return self.buf[start .. start + len];
    }

    fn readString(self: *XdrReader) ![]const u8 {
        return self.readOpaque();
    }

    fn skipPadding(self: *XdrReader, len: usize) void {
        const pad = padding(len);
        self.pos += pad;
    }

    fn readRpcCall(self: *XdrReader) !RpcCall {
        const xid = try self.readU32();
        const msg_type = try self.readU32();
        if (msg_type != @intFromEnum(RpcMessageType.call)) return error.InvalidMessage;
        const rpcvers = try self.readU32();
        if (rpcvers != 2) return error.UnsupportedVersion;
        const prog = try self.readU32();
        const vers = try self.readU32();
        const proc = try self.readU32();
        _ = try self.readOpaqueAuth();
        _ = try self.readOpaqueAuth();
        return .{ .xid = xid, .prog = prog, .vers = vers, .proc = proc };
    }

    fn readOpaqueAuth(self: *XdrReader) !void {
        _ = try self.readU32();
        const len = try self.readU32();
        if (self.pos + len > self.buf.len) return error.InvalidMessage;
        self.pos += len;
        self.skipPadding(len);
    }
};

const XdrWriter = struct {
    list: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator) XdrWriter {
        return .{ .list = std.ArrayList(u8).init(allocator) };
    }

    fn deinit(self: *XdrWriter) void {
        self.list.deinit();
    }

    fn toOwnedSlice(self: *XdrWriter) ![]u8 {
        return self.list.toOwnedSlice();
    }

    fn writeU32(self: *XdrWriter, value: u32) !void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, value, .big);
        try self.list.appendSlice(&buf);
    }

    fn writeU64(self: *XdrWriter, value: u64) !void {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, value, .big);
        try self.list.appendSlice(&buf);
    }

    fn writeBool(self: *XdrWriter, value: bool) !void {
        try self.writeU32(if (value) 1 else 0);
    }

    fn writeOpaque(self: *XdrWriter, value: []const u8) !void {
        try self.writeU32(@intCast(value.len));
        try self.list.appendSlice(value);
        const pad = padding(value.len);
        if (pad > 0) {
            var zeros: [4]u8 = .{0} ** 4;
            try self.list.appendSlice(zeros[0..pad]);
        }
    }

    fn writeFixedOpaque(self: *XdrWriter, value: []const u8) !void {
        try self.list.appendSlice(value);
        const pad = padding(value.len);
        if (pad > 0) {
            var zeros: [4]u8 = .{0} ** 4;
            try self.list.appendSlice(zeros[0..pad]);
        }
    }

    fn writeString(self: *XdrWriter, value: []const u8) !void {
        try self.writeOpaque(value);
    }

    fn writeRpcReplyHeader(self: *XdrWriter, xid: u32, status: RpcAcceptStat) !void {
        try self.writeU32(xid);
        try self.writeU32(@intFromEnum(RpcMessageType.reply));
        try self.writeU32(@intFromEnum(RpcReplyStat.accepted));
        try self.writeU32(0);
        try self.writeU32(0);
        try self.writeU32(@intFromEnum(status));
    }
};

fn writePostOpAttr(writer: *XdrWriter, path: ?[]const u8, node: ?Node) !void {
    if (node) |value| {
        try writer.writeBool(true);
        try writeFattr3(writer, path.?, value);
    } else {
        try writer.writeBool(false);
    }
}

fn writeFattr3(writer: *XdrWriter, path: []const u8, node: Node) !void {
    const file_type = switch (node.kind) {
        .file => NfsFileType.reg,
        .dir => NfsFileType.dir,
    };
    const mode: u32 = switch (node.kind) {
        .file => 0o644,
        .dir => 0o755,
    };
    const size: u64 = switch (node.kind) {
        .file => node.content.len,
        .dir => 0,
    };
    const file_id = fileIdForPath(path);

    try writer.writeU32(@intFromEnum(file_type));
    try writer.writeU32(mode);
    try writer.writeU32(if (node.kind == .dir) 2 else 1);
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeU64(size);
    try writer.writeU64(size);
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeU64(1);
    try writer.writeU64(file_id);
    try writeNfsTime(writer, 0);
    try writeNfsTime(writer, 0);
    try writeNfsTime(writer, 0);
}

fn writeNfsTime(writer: *XdrWriter, seconds: u32) !void {
    try writer.writeU32(seconds);
    try writer.writeU32(0);
}

fn fileIdForPath(path: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(path);
    return hasher.final();
}

fn joinPath(allocator: std.mem.Allocator, dir: []const u8, name: []const u8) ![]u8 {
    if (std.mem.eql(u8, dir, "/")) {
        return std.fmt.allocPrint(allocator, "/{s}", .{name});
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name });
}

fn buildPrefix(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.mem.eql(u8, path, "/")) {
        return allocator.dupe(u8, "/");
    }
    return std.fmt.allocPrint(allocator, "{s}/", .{path});
}

fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0) return allocator.dupe(u8, "/");
    if (path.len > 1 and path[path.len - 1] == '/') {
        return allocator.dupe(u8, path[0 .. path.len - 1]);
    }
    return allocator.dupe(u8, path);
}

fn padding(len: usize) usize {
    return (4 - (len % 4)) % 4;
}

fn skipFattr3(reader: *XdrReader) !void {
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU64();
    _ = try reader.readU64();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU64();
    _ = try reader.readU64();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
}

test "nfs null returns success" {
    var fs = try VirtualFs.init(std.testing.allocator);
    defer fs.deinit();
    var server = NfsServer.init(std.testing.allocator, &fs);

    var writer = XdrWriter.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeU32(42);
    try writer.writeU32(@intFromEnum(RpcMessageType.call));
    try writer.writeU32(2);
    try writer.writeU32(NFS_PROGRAM);
    try writer.writeU32(NFS_VERSION);
    try writer.writeU32(@intFromEnum(NfsProcedure.null));
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeU32(0);

    const response = try server.handleCall(writer.list.items);
    defer std.testing.allocator.free(response);

    var reader = XdrReader.init(response);
    try std.testing.expectEqual(@as(u32, 42), try reader.readU32());
    try std.testing.expectEqual(@as(u32, @intFromEnum(RpcMessageType.reply)), try reader.readU32());
    try std.testing.expectEqual(@as(u32, @intFromEnum(RpcReplyStat.accepted)), try reader.readU32());
    _ = try reader.readU32();
    _ = try reader.readU32();
    try std.testing.expectEqual(@as(u32, @intFromEnum(RpcAcceptStat.success)), try reader.readU32());
}

test "nfs getattr returns file size" {
    var fs = try VirtualFs.init(std.testing.allocator);
    defer fs.deinit();
    try fs.addFile("/README", "hello");

    var server = NfsServer.init(std.testing.allocator, &fs);

    var writer = XdrWriter.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeU32(7);
    try writer.writeU32(@intFromEnum(RpcMessageType.call));
    try writer.writeU32(2);
    try writer.writeU32(NFS_PROGRAM);
    try writer.writeU32(NFS_VERSION);
    try writer.writeU32(@intFromEnum(NfsProcedure.getattr));
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeOpaque("/README");

    const response = try server.handleCall(writer.list.items);
    defer std.testing.allocator.free(response);

    var reader = XdrReader.init(response);
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    try std.testing.expectEqual(@as(u32, @intFromEnum(NfsStatus.ok)), try reader.readU32());
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    try std.testing.expectEqual(@as(u64, 5), try reader.readU64());
}

test "nfs readdir returns entries" {
    var fs = try VirtualFs.init(std.testing.allocator);
    defer fs.deinit();
    try fs.addFile("/README", "hello");

    var server = NfsServer.init(std.testing.allocator, &fs);

    var writer = XdrWriter.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeU32(9);
    try writer.writeU32(@intFromEnum(RpcMessageType.call));
    try writer.writeU32(2);
    try writer.writeU32(NFS_PROGRAM);
    try writer.writeU32(NFS_VERSION);
    try writer.writeU32(@intFromEnum(NfsProcedure.readdir));
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeU32(0);
    try writer.writeOpaque("/");
    try writer.writeU64(0);
    try writer.writeFixedOpaque(&[_]u8{0} ** 8);
    try writer.writeU32(4096);

    const response = try server.handleCall(writer.list.items);
    defer std.testing.allocator.free(response);

    var reader = XdrReader.init(response);
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    _ = try reader.readU32();
    try std.testing.expectEqual(@as(u32, @intFromEnum(NfsStatus.ok)), try reader.readU32());
    const attrs = try reader.readBool();
    try std.testing.expect(attrs);
    try skipFattr3(&reader);
    _ = try reader.readFixedOpaque(8);
    try std.testing.expect(try reader.readBool());
    _ = try reader.readU64();
    const name = try reader.readString();
    try std.testing.expectEqualStrings("README", name);
    _ = try reader.readU64();
    try std.testing.expectEqual(false, try reader.readBool());
    try std.testing.expectEqual(true, try reader.readBool());
}

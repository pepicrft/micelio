const std = @import("std");
const xdr = @import("hif/fs/xdr.zig");
const state_mod = @import("hif/fs/state.zig");

const Rpc = struct {
    const CALL: u32 = 0;
    const REPLY: u32 = 1;
    const MSG_ACCEPTED: u32 = 0;
    const SUCCESS: u32 = 0;

    const AUTH_NULL: u32 = 0;
};

const Nfs = struct {
    const PROG: u32 = 100003;
    const VERS: u32 = 3;

    const NULL: u32 = 0;
    const GETATTR: u32 = 1;
    const SETATTR: u32 = 2;
    const LOOKUP: u32 = 3;
    const ACCESS: u32 = 4;
    const READLINK: u32 = 5;
    const READ: u32 = 6;
    const WRITE: u32 = 7;
    const CREATE: u32 = 8;
    const MKDIR: u32 = 9;
    const REMOVE: u32 = 12;
    const RMDIR: u32 = 13;
    const RENAME: u32 = 14;
    const READDIR: u32 = 16;
    const READDIRPLUS: u32 = 17;
    const FSSTAT: u32 = 18;
    const FSINFO: u32 = 19;
    const PATHCONF: u32 = 20;
    const COMMIT: u32 = 21;

    const NFS3_OK: u32 = 0;
    const NFS3ERR_PERM: u32 = 1;
    const NFS3ERR_NOENT: u32 = 2;
    const NFS3ERR_IO: u32 = 5;
    const NFS3ERR_ACCES: u32 = 13;
    const NFS3ERR_EXIST: u32 = 17;
    const NFS3ERR_NOTDIR: u32 = 20;
    const NFS3ERR_ISDIR: u32 = 21;
    const NFS3ERR_INVAL: u32 = 22;
    const NFS3ERR_FBIG: u32 = 27;
    const NFS3ERR_STALE: u32 = 70;
    const NFS3ERR_NOTSUPP: u32 = 10004;

    const NF3REG: u32 = 1;
    const NF3DIR: u32 = 2;

    const FILE_SYNC: u32 = 2;
};

const Mount = struct {
    const PROG: u32 = 100005;
    const VERS: u32 = 3;

    const NULL: u32 = 0;
    const MNT: u32 = 1;
    const DUMP: u32 = 2;
    const UMNT: u32 = 3;
    const UMNTALL: u32 = 4;
    const EXPORT: u32 = 5;

    const MNT3_OK: u32 = 0;
    const MNT3ERR_NOENT: u32 = 2;
};

pub const ServerConfig = struct {
    address: []const u8 = "127.0.0.1",
    nfs_port: u16 = 2049,
    mount_port: u16 = 2050,
};

pub fn serve(state: *state_mod.RepoState, config: ServerConfig) !void {
    var mount_thread = try std.Thread.spawn(.{}, serveMount, .{ state, config });
    defer mount_thread.detach();

    try serveNfs(state, config);
}

fn serveNfs(state: *state_mod.RepoState, config: ServerConfig) !void {
    var server = std.net.StreamServer.init(.{});
    defer server.deinit();

    const addr = try std.net.Address.parseIp4(config.address, config.nfs_port);
    try server.listen(addr);

    while (true) {
        var conn = try server.accept();
        handleRpcStream(state, conn.stream, .nfs) catch |err| {
            std.log.warn("NFS connection error: {}", .{err});
        };
        conn.stream.close();
    }
}

fn serveMount(state: *state_mod.RepoState, config: ServerConfig) !void {
    var server = std.net.StreamServer.init(.{});
    defer server.deinit();

    const addr = try std.net.Address.parseIp4(config.address, config.mount_port);
    try server.listen(addr);

    while (true) {
        var conn = try server.accept();
        handleRpcStream(state, conn.stream, .mountd) catch |err| {
            std.log.warn("Mountd connection error: {}", .{err});
        };
        conn.stream.close();
    }
}

const RpcService = enum { nfs, mountd };

fn handleRpcStream(state: *state_mod.RepoState, stream: std.net.Stream, service: RpcService) !void {
    while (true) {
        const record = readRecord(stream) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        if (record.len == 0) return;
        defer state.allocator.free(record);

        var reader = xdr.Reader.init(record);
        const xid = try reader.readU32();
        const msg_type = try reader.readU32();
        if (msg_type != Rpc.CALL) return error.InvalidRpc;

        _ = try reader.readU32(); // rpc version
        const prog = try reader.readU32();
        _ = try reader.readU32(); // version
        const proc = try reader.readU32();

        _ = try reader.readU32(); // cred flavor
        _ = try reader.readOpaque();
        _ = try reader.readU32(); // verf flavor
        _ = try reader.readOpaque();

        var body = xdr.Writer.init(state.allocator);
        defer body.deinit();

        switch (service) {
            .nfs => {
                if (prog != Nfs.PROG) return error.InvalidRpc;
                try handleNfs(state, proc, &reader, &body);
            },
            .mountd => {
                if (prog != Mount.PROG) return error.InvalidRpc;
                try handleMount(state, proc, &reader, &body);
            },
        }

        const body_bytes = try body.toOwnedSlice(state.allocator);
        defer state.allocator.free(body_bytes);

        var reply = xdr.Writer.init(state.allocator);
        defer reply.deinit();

        try reply.writeU32(xid);
        try reply.writeU32(Rpc.REPLY);
        try reply.writeU32(Rpc.MSG_ACCEPTED);
        try reply.writeU32(Rpc.AUTH_NULL);
        try reply.writeU32(0);
        try reply.writeU32(Rpc.SUCCESS);
        try reply.list.appendSlice(body_bytes);

        const reply_bytes = try reply.toOwnedSlice(state.allocator);
        defer state.allocator.free(reply_bytes);

        try writeRecord(stream, reply_bytes);
    }
}

fn handleMount(
    state: *state_mod.RepoState,
    proc: u32,
    reader: *xdr.Reader,
    writer: *xdr.Writer,
) !void {
    switch (proc) {
        Mount.NULL => {},
        Mount.MNT => {
            const dirpath = try reader.readString();
            _ = dirpath;
            try writer.writeU32(Mount.MNT3_OK);
            const handle = try state.handleForPath("");
            try writeHandle(writer, handle);
            try writer.writeU32(1); // auth flavors count
            try writer.writeU32(Rpc.AUTH_NULL);
        },
        Mount.UMNT => {
            _ = try reader.readString();
        },
        Mount.UMNTALL => {},
        Mount.DUMP => {
            try writer.writeBool(false);
        },
        Mount.EXPORT => {
            try writer.writeBool(false);
        },
        else => {
            try writer.writeU32(Mount.MNT3ERR_NOENT);
        },
    }
}

fn handleNfs(
    state: *state_mod.RepoState,
    proc: u32,
    reader: *xdr.Reader,
    writer: *xdr.Writer,
) !void {
    switch (proc) {
        Nfs.NULL => {},
        Nfs.GETATTR => try nfsGetattr(state, reader, writer),
        Nfs.LOOKUP => try nfsLookup(state, reader, writer),
        Nfs.ACCESS => try nfsAccess(state, reader, writer),
        Nfs.READ => try nfsRead(state, reader, writer),
        Nfs.WRITE => try nfsWrite(state, reader, writer),
        Nfs.CREATE => try nfsCreate(state, reader, writer),
        Nfs.MKDIR => try nfsMkdir(state, reader, writer),
        Nfs.REMOVE => try nfsRemove(state, reader, writer),
        Nfs.RMDIR => try nfsRmdir(state, reader, writer),
        Nfs.RENAME => try nfsRename(state, reader, writer),
        Nfs.READDIR => try nfsReaddir(state, reader, writer, false),
        Nfs.READDIRPLUS => try nfsReaddir(state, reader, writer, true),
        Nfs.FSSTAT => try nfsFsstat(state, reader, writer),
        Nfs.FSINFO => try nfsFsinfo(writer),
        Nfs.PATHCONF => try nfsPathconf(writer),
        Nfs.COMMIT => try nfsCommit(writer),
        else => try writer.writeU32(Nfs.NFS3ERR_NOTSUPP),
    }
}

fn nfsGetattr(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const handle = try readHandle(reader);
    const path = state.pathFromHandle(handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    const attr = try state.getAttr(path) orelse {
        try writer.writeU32(Nfs.NFS3ERR_NOENT);
        return;
    };

    try writer.writeU32(Nfs.NFS3_OK);
    try writeFattr(writer, attr);
}

fn nfsLookup(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const dir_handle = try readHandle(reader);
    const name = try reader.readString();
    const dir_path = state.pathFromHandle(dir_handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    const dir_attr = try state.getAttr(dir_path);
    if (dir_attr == null or dir_attr.?.kind != .dir) {
        try writer.writeU32(Nfs.NFS3ERR_NOTDIR);
        return;
    }

    const entry = try state.lookup(dir_path, name) orelse {
        try writer.writeU32(Nfs.NFS3ERR_NOENT);
        return;
    };
    defer state.allocator.free(entry.name);
    defer state.allocator.free(entry.path);

    try writer.writeU32(Nfs.NFS3_OK);
    try writeHandle(writer, entry.handle);

    const attr = try state.getAttr(entry.path);
    try writePostOpAttr(writer, attr);
    try writePostOpAttr(writer, dir_attr);

    if (entry.kind == .dir) {
        state.prefetchDirectory(entry.path);
    }
}

fn nfsAccess(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const handle = try readHandle(reader);
    const requested = try reader.readU32();
    const path = state.pathFromHandle(handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    const attr = try state.getAttr(path) orelse {
        try writer.writeU32(Nfs.NFS3ERR_NOENT);
        return;
    };

    try writer.writeU32(Nfs.NFS3_OK);
    try writePostOpAttr(writer, attr);
    try writer.writeU32(requested);
}

fn nfsRead(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const handle = try readHandle(reader);
    const offset = try reader.readU64();
    const count = try reader.readU32();

    const path = state.pathFromHandle(handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    const attr = try state.getAttr(path);
    if (attr == null or attr.?.kind != .file) {
        try writer.writeU32(Nfs.NFS3ERR_NOENT);
        return;
    }

    const data = try state.readFile(path, offset, count) orelse {
        try writer.writeU32(Nfs.NFS3ERR_NOENT);
        return;
    };
    defer state.allocator.free(data);

    const eof = offset + data.len >= attr.?.size;

    try writer.writeU32(Nfs.NFS3_OK);
    try writePostOpAttr(writer, attr);
    try writer.writeU32(@intCast(data.len));
    try writer.writeBool(eof);
    try writer.writeOpaque(data);
}

fn nfsWrite(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const handle = try readHandle(reader);
    const offset = try reader.readU64();
    _ = try reader.readU32(); // count
    _ = try reader.readU32(); // stable
    const data = try reader.readOpaque();

    const path = state.pathFromHandle(handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    const written = try state.writeFile(path, offset, data);
    const attr = try state.getAttr(path);

    try writer.writeU32(Nfs.NFS3_OK);
    try writeWccData(writer, null, attr);
    try writer.writeU32(@intCast(written));
    try writer.writeU32(Nfs.FILE_SYNC);
    try writer.writeU64(0);
}

fn nfsCreate(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const dir_handle = try readHandle(reader);
    const name = try reader.readString();
    const dir_path = state.pathFromHandle(dir_handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    _ = try reader.readU32();
    try skipSattr(reader);

    const entry = try state.createFile(dir_path, name);
    defer state.allocator.free(entry.name);
    defer state.allocator.free(entry.path);

    const attr = try state.getAttr(entry.path);
    const dir_attr = try state.getAttr(dir_path);

    try writer.writeU32(Nfs.NFS3_OK);
    try writeHandle(writer, entry.handle);
    try writePostOpAttr(writer, attr);
    try writeWccData(writer, null, dir_attr);
}

fn nfsMkdir(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const dir_handle = try readHandle(reader);
    const name = try reader.readString();
    const dir_path = state.pathFromHandle(dir_handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    try skipSattr(reader);

    const entry = try state.makeDir(dir_path, name);
    defer state.allocator.free(entry.name);
    defer state.allocator.free(entry.path);

    const attr = try state.getAttr(entry.path);
    const dir_attr = try state.getAttr(dir_path);

    try writer.writeU32(Nfs.NFS3_OK);
    try writeHandle(writer, entry.handle);
    try writePostOpAttr(writer, attr);
    try writeWccData(writer, null, dir_attr);
}

fn nfsRemove(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const dir_handle = try readHandle(reader);
    const name = try reader.readString();
    const dir_path = state.pathFromHandle(dir_handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    const target = try std.fmt.allocPrint(state.allocator, "{s}/{s}", .{ dir_path, name });
    defer state.allocator.free(target);

    try state.removePath(target);
    const dir_attr = try state.getAttr(dir_path);

    try writer.writeU32(Nfs.NFS3_OK);
    try writeWccData(writer, null, dir_attr);
}

fn nfsRmdir(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const dir_handle = try readHandle(reader);
    const name = try reader.readString();
    const dir_path = state.pathFromHandle(dir_handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    const target = try std.fmt.allocPrint(state.allocator, "{s}/{s}", .{ dir_path, name });
    defer state.allocator.free(target);

    try state.removePath(target);
    const dir_attr = try state.getAttr(dir_path);

    try writer.writeU32(Nfs.NFS3_OK);
    try writeWccData(writer, null, dir_attr);
}

fn nfsRename(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    const from_dir_handle = try readHandle(reader);
    const from_name = try reader.readString();
    const to_dir_handle = try readHandle(reader);
    const to_name = try reader.readString();

    const from_dir = state.pathFromHandle(from_dir_handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };
    const to_dir = state.pathFromHandle(to_dir_handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    const from_path = try std.fmt.allocPrint(state.allocator, "{s}/{s}", .{ from_dir, from_name });
    defer state.allocator.free(from_path);
    const to_path = try std.fmt.allocPrint(state.allocator, "{s}/{s}", .{ to_dir, to_name });
    defer state.allocator.free(to_path);

    try state.renamePath(from_path, to_path);
    const from_attr = try state.getAttr(from_dir);
    const to_attr = try state.getAttr(to_dir);

    try writer.writeU32(Nfs.NFS3_OK);
    try writeWccData(writer, null, from_attr);
    try writeWccData(writer, null, to_attr);
}

fn nfsReaddir(
    state: *state_mod.RepoState,
    reader: *xdr.Reader,
    writer: *xdr.Writer,
    with_handles: bool,
) !void {
    const dir_handle = try readHandle(reader);
    _ = try reader.readU64();
    _ = try reader.readOpaque();
    _ = try reader.readU32();
    if (with_handles) {
        _ = try reader.readU32();
    }

    const dir_path = state.pathFromHandle(dir_handle) orelse {
        try writer.writeU32(Nfs.NFS3ERR_STALE);
        return;
    };

    const attr = try state.getAttr(dir_path);
    if (attr == null or attr.?.kind != .dir) {
        try writer.writeU32(Nfs.NFS3ERR_NOTDIR);
        return;
    }

    const entries = try state.listDir(dir_path);
    defer {
        for (entries) |entry| {
            state.allocator.free(entry.name);
            state.allocator.free(entry.path);
        }
        state.allocator.free(entries);
    }

    try writer.writeU32(Nfs.NFS3_OK);
    try writePostOpAttr(writer, attr);
    try writer.writeOpaque(&[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 });

    var cookie: u64 = 1;
    for (entries) |entry| {
        try writer.writeBool(true);
        try writer.writeU64(entry.handle);
        try writer.writeString(entry.name);
        try writer.writeU64(cookie);
        cookie += 1;

        if (with_handles) {
            const entry_attr = try state.getAttr(entry.path);
            try writePostOpAttr(writer, entry_attr);
            try writePostOpHandle(writer, entry.handle);
        }
    }

    try writer.writeBool(false);
    try writer.writeBool(true);

    state.prefetchDirectory(dir_path);
}

fn nfsFsstat(state: *state_mod.RepoState, reader: *xdr.Reader, writer: *xdr.Writer) !void {
    _ = reader;

    const attr = try state.getAttr("");

    try writer.writeU32(Nfs.NFS3_OK);
    try writePostOpAttr(writer, attr);
    try writer.writeU64(512 * 1024 * 1024); // total bytes
    try writer.writeU64(512 * 1024 * 1024); // free bytes
    try writer.writeU64(512 * 1024 * 1024); // avail bytes
    try writer.writeU64(1_000_000); // total files
    try writer.writeU64(1_000_000); // free files
    try writer.writeU64(1_000_000); // avail files
    try writer.writeU32(0); // invarsec
}

fn nfsFsinfo(writer: *xdr.Writer) !void {
    try writer.writeU32(Nfs.NFS3_OK);
    try writer.writeU32(64 * 1024); // rtmax
    try writer.writeU32(64 * 1024); // rtpref
    try writer.writeU32(4096); // rtmult
    try writer.writeU32(64 * 1024); // wtmax
    try writer.writeU32(64 * 1024); // wtpref
    try writer.writeU32(4096); // wtmult
    try writer.writeU32(64 * 1024); // dtpref
    try writer.writeU64(1024 * 1024 * 1024); // maxfilesize
    try writer.writeU32(1); // time_delta seconds
    try writer.writeU32(0); // time_delta nsecs
    try writer.writeU32(0); // properties
}

fn nfsPathconf(writer: *xdr.Writer) !void {
    try writer.writeU32(Nfs.NFS3_OK);
    try writer.writeU32(1024); // linkmax
    try writer.writeU32(255); // name_max
    try writer.writeBool(true); // no_trunc
    try writer.writeBool(true); // chown_restricted
    try writer.writeBool(false); // case_insensitive
    try writer.writeBool(true); // case_preserving
}

fn nfsCommit(writer: *xdr.Writer) !void {
    try writer.writeU32(Nfs.NFS3_OK);
    try writer.writeU64(0);
}

fn readRecord(stream: std.net.Stream) ![]u8 {
    var header: [4]u8 = undefined;
    const read_len = try stream.readAll(&header);
    if (read_len == 0) return error.EndOfStream;
    if (read_len != 4) return error.EndOfStream;

    const raw = std.mem.readInt(u32, &header, .big);
    const length = raw & 0x7fffffff;
    const last = (raw & 0x80000000) != 0;
    if (!last) return error.InvalidRpc;

    const buf = try std.heap.page_allocator.alloc(u8, length);
    errdefer std.heap.page_allocator.free(buf);

    const read_payload = try stream.readAll(buf);
    if (read_payload != length) return error.EndOfStream;
    return buf;
}

fn writeRecord(stream: std.net.Stream, payload: []const u8) !void {
    const length = @as(u32, @intCast(payload.len)) | 0x80000000;
    var header: [4]u8 = undefined;
    std.mem.writeInt(u32, &header, length, .big);
    try stream.writeAll(&header);
    try stream.writeAll(payload);
}

fn readHandle(reader: *xdr.Reader) !u64 {
    const data = try reader.readOpaque();
    if (data.len != 8) return error.InvalidHandle;
    return std.mem.readInt(u64, data, .big);
}

fn writeHandle(writer: *xdr.Writer, handle: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, handle, .big);
    try writer.writeOpaque(&buf);
}

fn writePostOpHandle(writer: *xdr.Writer, handle: u64) !void {
    try writer.writeBool(true);
    try writeHandle(writer, handle);
}

fn writePostOpAttr(writer: *xdr.Writer, attr: ?state_mod.Attr) !void {
    if (attr) |value| {
        try writer.writeBool(true);
        try writeFattr(writer, value);
    } else {
        try writer.writeBool(false);
    }
}

fn writeFattr(writer: *xdr.Writer, attr: state_mod.Attr) !void {
    const mode = attr.mode;
    const uid = currentUid();
    const gid = currentGid();
    const nlink: u32 = if (attr.kind == .dir) 2 else 1;
    const file_type = if (attr.kind == .dir) Nfs.NF3DIR else Nfs.NF3REG;
    const timestamp = @as(u32, @intCast(attr.mtime));

    try writer.writeU32(file_type);
    try writer.writeU32(mode);
    try writer.writeU32(nlink);
    try writer.writeU32(uid);
    try writer.writeU32(gid);
    try writer.writeU64(attr.size);
    try writer.writeU64(attr.size);
    try writer.writeU32(0); // rdev major
    try writer.writeU32(0); // rdev minor
    try writer.writeU64(1); // fsid
    try writer.writeU64(attr.fileid);
    try writer.writeU32(timestamp);
    try writer.writeU32(0);
    try writer.writeU32(timestamp);
    try writer.writeU32(0);
    try writer.writeU32(timestamp);
    try writer.writeU32(0);
}

fn writeWccData(writer: *xdr.Writer, pre: ?state_mod.Attr, post: ?state_mod.Attr) !void {
    if (pre) |value| {
        try writer.writeBool(true);
        try writer.writeU64(value.size);
        try writer.writeU32(@intCast(value.mtime));
        try writer.writeU32(0);
        try writer.writeU32(@intCast(value.mtime));
        try writer.writeU32(0);
    } else {
        try writer.writeBool(false);
    }

    try writePostOpAttr(writer, post);
}

fn skipSattr(reader: *xdr.Reader) !void {
    if (try reader.readBool()) _ = try reader.readU32();
    if (try reader.readBool()) _ = try reader.readU32();
    if (try reader.readBool()) _ = try reader.readU32();
    if (try reader.readBool()) _ = try reader.readU64();
    if (try reader.readBool()) {
        _ = try reader.readU32();
        _ = try reader.readU32();
    }
    if (try reader.readBool()) {
        _ = try reader.readU32();
        _ = try reader.readU32();
    }
}

fn currentUid() u32 {
    if (@hasDecl(std.posix, "getuid")) {
        return @intCast(std.posix.getuid());
    }
    return 0;
}

fn currentGid() u32 {
    if (@hasDecl(std.posix, "getgid")) {
        return @intCast(std.posix.getgid());
    }
    return 0;
}

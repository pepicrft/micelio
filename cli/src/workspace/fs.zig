const std = @import("std");

pub fn ensureDir(path: []const u8) !void {
    if (path.len == 0) return;

    if (std.fs.path.isAbsolute(path)) {
        if (path.len == 1 and path[0] == '/') return;
        var root = try std.fs.openDirAbsolute("/", .{});
        defer root.close();
        try root.makePath(path[1..]);
        return;
    }

    try std.fs.cwd().makePath(path);
}

pub fn ensureParentDir(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    try ensureDir(parent);
}

pub fn readFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) !?[]u8 {
    const file = openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();
    return try file.readToEndAlloc(allocator, max_bytes);
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    const file = try createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

pub fn fileExists(path: []const u8) !bool {
    const file = openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.IsDir => return true,
        else => return err,
    };
    file.close();
    return true;
}

pub fn openDir(path: []const u8, iterate: bool) !std.fs.Dir {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openDirAbsolute(path, .{ .iterate = iterate });
    }

    return std.fs.cwd().openDir(path, .{ .iterate = iterate });
}

pub fn hashFileSha256(path: []const u8) ![32]u8 {
    const file = try openFile(path, .{});
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [64 * 1024]u8 = undefined;

    while (true) {
        const read_len = try file.read(&buf);
        if (read_len == 0) break;
        hasher.update(buf[0..read_len]);
    }

    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

fn openFile(path: []const u8, flags: std.fs.File.OpenFlags) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openFileAbsolute(path, flags);
    }

    return std.fs.cwd().openFile(path, flags);
}

fn createFile(path: []const u8, flags: std.fs.File.CreateFlags) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.createFileAbsolute(path, flags);
    }

    return std.fs.cwd().createFile(path, flags);
}

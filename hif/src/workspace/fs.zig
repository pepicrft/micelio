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

/// Writes a file atomically by writing to a temp file then renaming.
/// This prevents partial writes from corrupting the target file.
pub fn writeFileAtomic(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    // Create temp file path
    const temp_path = try std.fmt.allocPrint(allocator, "{s}.tmp.{d}", .{ path, std.time.milliTimestamp() });
    defer allocator.free(temp_path);

    // Write to temp file
    const temp_file = try createFile(temp_path, .{ .truncate = true });
    errdefer {
        temp_file.close();
        deleteFile(temp_path) catch {};
    }

    try temp_file.writeAll(data);
    temp_file.close();

    // Rename temp to target (atomic on most filesystems)
    try renameFile(temp_path, path);
}

/// Creates a backup of a file before modifying it.
/// Returns the backup path if successful.
pub fn backupFile(allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    const exists = try fileExists(path);
    if (!exists) return null;

    const backup_path = try std.fmt.allocPrint(allocator, "{s}.bak", .{path});
    errdefer allocator.free(backup_path);

    try copyFile(path, backup_path);
    return backup_path;
}

/// Restores a file from its backup.
pub fn restoreFromBackup(backup_path: []const u8, target_path: []const u8) !void {
    try copyFile(backup_path, target_path);
}

/// Deletes a backup file if it exists.
pub fn deleteBackup(path: []const u8) void {
    deleteFile(path) catch {};
}

fn copyFile(src: []const u8, dst: []const u8) !void {
    const src_file = try openFile(src, .{});
    defer src_file.close();

    const dst_file = try createFile(dst, .{ .truncate = true });
    defer dst_file.close();

    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const read_len = try src_file.read(&buf);
        if (read_len == 0) break;
        try dst_file.writeAll(buf[0..read_len]);
    }
}

fn deleteFile(path: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        try std.fs.deleteFileAbsolute(path);
    } else {
        try std.fs.cwd().deleteFile(path);
    }
}

fn renameFile(old_path: []const u8, new_path: []const u8) !void {
    if (std.fs.path.isAbsolute(old_path)) {
        try std.fs.renameAbsolute(old_path, new_path);
    } else {
        try std.fs.cwd().rename(old_path, new_path);
    }
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

const std = @import("std");

pub fn configDir(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |value| {
        if (value.len > 0) return value;
        allocator.free(value);
    } else |_| {}

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    return std.fs.path.join(allocator, &.{ home, ".config" });
}

pub fn credentialsDir(allocator: std.mem.Allocator) ![]u8 {
    const base = try configDir(allocator);
    defer allocator.free(base);

    return std.fs.path.join(allocator, &.{ base, "mic", "credentials", "micelio.dev" });
}

pub fn ensureCredentialsDir(allocator: std.mem.Allocator) ![]u8 {
    const dir = try credentialsDir(allocator);
    try std.fs.cwd().makePath(dir);
    return dir;
}

pub fn credentialsFilePath(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const dir = try ensureCredentialsDir(allocator);
    defer allocator.free(dir);

    return std.fs.path.join(allocator, &.{ dir, filename });
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) !?[]u8 {
    var file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    return try file.readToEndAlloc(allocator, max_bytes);
}

pub fn writeSecretFile(path: []const u8, data: []const u8) !void {
    var file = try std.fs.createFileAbsolute(path, .{
        .read = true,
        .truncate = true,
        .mode = 0o600,
    });
    defer file.close();

    try file.writeAll(data);
}

pub fn deleteFile(path: []const u8) !void {
    std.fs.deleteFileAbsolute(path) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
}

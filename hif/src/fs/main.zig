const std = @import("std");
const fs_server = @import("hif/fs/server.zig");
const state_mod = @import("hif/fs/state.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var server: ?[]const u8 = null;
    var account: ?[]const u8 = null;
    var project: ?[]const u8 = null;
    var state_dir: ?[]const u8 = null;
    var nfs_port: u16 = 2049;
    var mount_port: u16 = 2050;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--server")) {
            i += 1;
            if (i >= args.len) return usage();
            server = args[i];
        } else if (std.mem.eql(u8, arg, "--account")) {
            i += 1;
            if (i >= args.len) return usage();
            account = args[i];
        } else if (std.mem.eql(u8, arg, "--project")) {
            i += 1;
            if (i >= args.len) return usage();
            project = args[i];
        } else if (std.mem.eql(u8, arg, "--state-dir")) {
            i += 1;
            if (i >= args.len) return usage();
            state_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--nfs-port")) {
            i += 1;
            if (i >= args.len) return usage();
            nfs_port = try parsePort(args[i]);
        } else if (std.mem.eql(u8, arg, "--mount-port")) {
            i += 1;
            if (i >= args.len) return usage();
            mount_port = try parsePort(args[i]);
        } else if (std.mem.eql(u8, arg, "--help")) {
            return usage();
        }
    }

    if (server == null or account == null or project == null or state_dir == null) {
        return usage();
    }

    var state = try state_mod.RepoState.init(
        allocator,
        server.?,
        account.?,
        project.?,
        state_dir.?,
    );
    defer state.deinit();

    const config = fs_server.ServerConfig{ .nfs_port = nfs_port, .mount_port = mount_port };
    try fs_server.serve(&state, config);
}

fn parsePort(value: []const u8) !u16 {
    const parsed = std.fmt.parseInt(u16, value, 10) catch return error.InvalidPort;
    if (parsed == 0) return error.InvalidPort;
    return parsed;
}

fn usage() !void {
    std.debug.print(
        "Usage: hif-fs --server <grpc_url> --account <org> --project <project> --state-dir <path> [--nfs-port <port>] [--mount-port <port>]\n",
        .{},
    );
    return error.InvalidArgs;
}

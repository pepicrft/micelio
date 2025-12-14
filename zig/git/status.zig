const std = @import("std");
const beam = @import("beam");
const git = @cImport({
    @cInclude("git2.h");
});

fn init_libgit2() !void {
    const result = git.git_libgit2_init();
    if (result < 0) {
        return error.LibGit2InitFailed;
    }
}

fn shutdown_libgit2() void {
    _ = git.git_libgit2_shutdown();
}

pub fn status(path: []const u8) !beam.term {
    try init_libgit2();
    defer shutdown_libgit2();

    var repo: ?*git.git_repository = null;

    // Null-terminate the path
    var path_buf: [4096]u8 = undefined;
    if (path.len >= path_buf.len) {
        return error.PathTooLong;
    }
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    // Open the repository
    const open_result = git.git_repository_open(&repo, &path_buf);
    if (open_result < 0) {
        return error.RepositoryOpenFailed;
    }
    defer git.git_repository_free(repo);

    // Get status list
    var status_list: ?*git.git_status_list = null;
    var opts: git.git_status_options = undefined;
    _ = git.git_status_options_init(&opts, git.GIT_STATUS_OPTIONS_VERSION);
    opts.show = git.GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    opts.flags = git.GIT_STATUS_OPT_INCLUDE_UNTRACKED |
        git.GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX |
        git.GIT_STATUS_OPT_SORT_CASE_SENSITIVELY;

    const status_result = git.git_status_list_new(&status_list, repo, &opts);
    if (status_result < 0) {
        return error.StatusFailed;
    }
    defer git.git_status_list_free(status_list);

    const count = git.git_status_list_entrycount(status_list);

    // Build results - use a fixed-size array and return a slice
    var results: [1024]beam.term = undefined;
    var result_count: usize = 0;

    for (0..count) |i| {
        if (result_count >= results.len) break;

        const entry = git.git_status_byindex(status_list, i);
        if (entry != null) {
            const e = entry.?;
            var file_path: []const u8 = undefined;

            // Get the file path from either head_to_index or index_to_workdir
            if (e.*.head_to_index != null) {
                file_path = std.mem.span(e.*.head_to_index.*.new_file.path);
            } else if (e.*.index_to_workdir != null) {
                file_path = std.mem.span(e.*.index_to_workdir.*.new_file.path);
            } else {
                continue;
            }

            const status_flags = e.*.status;
            const status_str = status_to_string(status_flags);

            // Create a tuple {path, status}
            results[result_count] = beam.make(.{ file_path, status_str }, .{});
            result_count += 1;
        }
    }

    return beam.make(.{ .ok, results[0..result_count] }, .{});
}

pub fn init(path: []const u8) !beam.term {
    try init_libgit2();
    defer shutdown_libgit2();

    var repo: ?*git.git_repository = null;

    // Null-terminate the path
    var path_buf: [4096]u8 = undefined;
    if (path.len >= path_buf.len) {
        return error.PathTooLong;
    }
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    // Initialize a new repository
    const init_result = git.git_repository_init(&repo, &path_buf, 0);
    if (init_result < 0) {
        return error.RepositoryInitFailed;
    }
    defer git.git_repository_free(repo);

    return beam.make(.ok, .{});
}

fn status_to_string(flags: c_uint) []const u8 {
    if (flags & git.GIT_STATUS_INDEX_NEW != 0) return "new";
    if (flags & git.GIT_STATUS_INDEX_MODIFIED != 0) return "modified";
    if (flags & git.GIT_STATUS_INDEX_DELETED != 0) return "deleted";
    if (flags & git.GIT_STATUS_INDEX_RENAMED != 0) return "renamed";
    if (flags & git.GIT_STATUS_INDEX_TYPECHANGE != 0) return "typechange";
    if (flags & git.GIT_STATUS_WT_NEW != 0) return "untracked";
    if (flags & git.GIT_STATUS_WT_MODIFIED != 0) return "modified";
    if (flags & git.GIT_STATUS_WT_DELETED != 0) return "deleted";
    if (flags & git.GIT_STATUS_WT_TYPECHANGE != 0) return "typechange";
    if (flags & git.GIT_STATUS_WT_RENAMED != 0) return "renamed";
    if (flags & git.GIT_STATUS_IGNORED != 0) return "ignored";
    if (flags & git.GIT_STATUS_CONFLICTED != 0) return "conflicted";
    return "unknown";
}

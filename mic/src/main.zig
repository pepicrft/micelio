const std = @import("std");
const yazap = @import("yazap");
const auth = @import("auth.zig");
const config = @import("config.zig");
const oauth = @import("oauth.zig");
const organizations = @import("organizations.zig");
const projects = @import("projects.zig");
const session = @import("session.zig");
const content = @import("content.zig");
const workspace = @import("workspace.zig");
const manifest = @import("workspace/manifest.zig");
const mount = @import("mount.zig");
const log = @import("log.zig");
const diff = @import("diff.zig");
const goto = @import("goto.zig");

const App = yazap.App;
const Arg = yazap.Arg;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, "mic", "The Micelio CLI - a forge-first version control system for the agent era");
    defer app.deinit();

    var root = app.rootCommand();

    // Auth: Authenticate with a forge
    var auth_cmd = app.createCommand("auth", "Authenticate with a forge");
    const auth_login_cmd = app.createCommand("login", "Authenticate via device flow");
    const auth_status_cmd = app.createCommand("status", "Show authentication status");
    const auth_logout_cmd = app.createCommand("logout", "Remove stored credentials");
    try auth_cmd.addSubcommand(auth_login_cmd);
    try auth_cmd.addSubcommand(auth_status_cmd);
    try auth_cmd.addSubcommand(auth_logout_cmd);
    try root.addSubcommand(auth_cmd);

    // Organization: Manage organizations
    var org_cmd = app.createCommand("org", "Manage organizations");

    const org_list_cmd = app.createCommand("list", "List your organizations");
    try org_cmd.addSubcommand(org_list_cmd);

    var org_get_cmd = app.createCommand("get", "Get organization details");
    try org_get_cmd.addArg(Arg.positional("HANDLE", "Organization handle", null));
    try org_cmd.addSubcommand(org_get_cmd);

    try root.addSubcommand(org_cmd);

    // Project: Manage projects
    var project_cmd = app.createCommand("project", "Manage projects");

    var project_list_cmd = app.createCommand("list", "List projects in an organization");
    try project_list_cmd.addArg(Arg.positional("ORGANIZATION", "Organization handle", null));
    try project_cmd.addSubcommand(project_list_cmd);

    var project_create_cmd = app.createCommand("create", "Create a new project");
    try project_create_cmd.addArg(Arg.positional("ORGANIZATION", "Organization handle", null));
    try project_create_cmd.addArg(Arg.positional("HANDLE", "Project handle (URL-safe name)", null));
    try project_create_cmd.addArg(Arg.positional("NAME", "Project display name", null));
    try project_create_cmd.addArg(Arg.singleValueOption("description", 'd', "Project description"));
    try project_cmd.addSubcommand(project_create_cmd);

    var project_get_cmd = app.createCommand("get", "Get project details");
    try project_get_cmd.addArg(Arg.positional("ORGANIZATION", "Organization handle", null));
    try project_get_cmd.addArg(Arg.positional("HANDLE", "Project handle", null));
    try project_cmd.addSubcommand(project_get_cmd);

    var project_update_cmd = app.createCommand("update", "Update a project");
    try project_update_cmd.addArg(Arg.positional("ORGANIZATION", "Organization handle", null));
    try project_update_cmd.addArg(Arg.positional("HANDLE", "Project handle", null));
    try project_update_cmd.addArg(Arg.singleValueOption("name", 'n', "Project name"));
    try project_update_cmd.addArg(Arg.singleValueOption("description", 'd', "Project description"));
    try project_update_cmd.addArg(Arg.singleValueOption("new-handle", 'H', "New project handle"));
    try project_cmd.addSubcommand(project_update_cmd);

    var project_delete_cmd = app.createCommand("delete", "Delete a project");
    try project_delete_cmd.addArg(Arg.positional("ORGANIZATION", "Organization handle", null));
    try project_delete_cmd.addArg(Arg.positional("HANDLE", "Project handle", null));
    try project_cmd.addSubcommand(project_delete_cmd);

    try root.addSubcommand(project_cmd);

    // Checkout: Create a local workspace for a project
    var checkout_cmd = app.createCommand("checkout", "Create a local workspace from a project");
    try checkout_cmd.addArg(Arg.positional("PROJECT", "Account/project (e.g., acme/app)", null));
    try checkout_cmd.addArg(Arg.singleValueOption("path", 'p', "Local directory (defaults to ./<project>)"));
    try root.addSubcommand(checkout_cmd);

    // Mount: Mount project as virtual filesystem
    var mount_cmd = app.createCommand("mount", "Mount project as virtual filesystem");
    try mount_cmd.addArg(Arg.positional("PROJECT", "Account/project (e.g., acme/app)", null));
    try mount_cmd.addArg(Arg.singleValueOption("path", 'p', "Mount point directory (defaults to ./<project>)"));
    try mount_cmd.addArg(Arg.singleValueOption("port", 'P', "NFS port (default: 20490)"));
    try root.addSubcommand(mount_cmd);

    // Unmount: Unmount project virtual filesystem
    var unmount_cmd = app.createCommand("unmount", "Unmount project virtual filesystem");
    try unmount_cmd.addArg(Arg.positional("PATH", "Mount point directory", null));
    try root.addSubcommand(unmount_cmd);

    // Status: Show workspace changes
    const status_cmd = app.createCommand("status", "Show workspace changes");
    try root.addSubcommand(status_cmd);

    // Land: Land workspace changes
    var land_cmd = app.createCommand("land", "Land workspace changes");
    try land_cmd.addArg(Arg.positional("GOAL", "What you're trying to accomplish", null));
    try root.addSubcommand(land_cmd);

    // Sync: Pull latest changes from the forge
    var sync_cmd = app.createCommand("sync", "Sync workspace with latest upstream changes");
    try sync_cmd.addArg(Arg.singleValueOption(
        "strategy",
        's',
        "Merge strategy: ours, theirs, or interactive (default)",
    ));
    try root.addSubcommand(sync_cmd);

    // Clone: Initialize local state for a forge project
    var clone_cmd = app.createCommand("clone", "Clone a project from the forge");
    try clone_cmd.addArg(Arg.positional("PROJECT", "Project URL or name (e.g., org/myapp)", null));
    try root.addSubcommand(clone_cmd);

    // Content: Read data from the forge
    var cat_cmd = app.createCommand("cat", "Print file contents from the forge");
    try cat_cmd.addArg(Arg.positional("ACCOUNT", "Account handle", null));
    try cat_cmd.addArg(Arg.positional("PROJECT", "Project handle", null));
    try cat_cmd.addArg(Arg.positional("PATH", "File path", null));
    try cat_cmd.addArg(Arg.singleValueOption("position", 'p', "Position to read (e.g., @10 or 10, default: @latest)"));
    try root.addSubcommand(cat_cmd);

    var ls_cmd = app.createCommand("ls", "List tree entries from the forge");
    try ls_cmd.addArg(Arg.positional("ACCOUNT", "Account handle", null));
    try ls_cmd.addArg(Arg.positional("PROJECT", "Project handle", null));
    try ls_cmd.addArg(Arg.singleValueOption("path", 'p', "Optional path prefix"));
    try ls_cmd.addArg(Arg.singleValueOption("position", 'r', "Position to list (e.g., @10 or 10, default: @latest)"));
    try root.addSubcommand(ls_cmd);

    var blame_cmd = app.createCommand("blame", "Show session attribution for file lines");
    try blame_cmd.addArg(Arg.positional("ACCOUNT", "Account handle", null));
    try blame_cmd.addArg(Arg.positional("PROJECT", "Project handle", null));
    try blame_cmd.addArg(Arg.positional("PATH", "File path", null));
    try root.addSubcommand(blame_cmd);

    // Write: Update local file and stage change for the session
    var write_cmd = app.createCommand("write", "Write stdin to a file and stage change");
    try write_cmd.addArg(Arg.positional("PATH", "File path", null));
    try root.addSubcommand(write_cmd);

    // Log: List landed sessions
    var log_cmd = app.createCommand("log", "List landed sessions");
    try log_cmd.addArg(Arg.positional("PROJECT", "Account/project (e.g., acme/app)", null));
    try log_cmd.addArg(Arg.singleValueOption("path", 'p', "Filter sessions by file path"));
    try log_cmd.addArg(Arg.singleValueOption("limit", 'n', "Maximum number of sessions to show (default: 20)"));
    try root.addSubcommand(log_cmd);

    // Diff: Show changes between two states
    var diff_cmd = app.createCommand("diff", "Show changes between two tree states");
    try diff_cmd.addArg(Arg.positional("PROJECT", "Account/project (e.g., acme/app)", null));
    try diff_cmd.addArg(Arg.positional("FROM", "Starting position (e.g., @10 or 10)", null));
    try diff_cmd.addArg(Arg.positional("TO", "Ending position (e.g., @15 or 15, omit for HEAD)", null));
    try root.addSubcommand(diff_cmd);

    // Goto: View tree at a specific position
    var goto_cmd = app.createCommand("goto", "View tree at a specific position");
    try goto_cmd.addArg(Arg.positional("PROJECT", "Account/project (e.g., acme/app)", null));
    try goto_cmd.addArg(Arg.positional("POSITION", "Position to view (e.g., @10 or 10)", null));
    try goto_cmd.addArg(Arg.singleValueOption("path", 'p', "Filter files by path prefix"));
    try root.addSubcommand(goto_cmd);

    // Session: Manage work sessions
    var session_cmd = app.createCommand("session", "Manage work sessions");

    var session_start_cmd = app.createCommand("start", "Start a new session");
    try session_start_cmd.addArg(Arg.positional("ORGANIZATION", "Organization handle", null));
    try session_start_cmd.addArg(Arg.positional("PROJECT", "Project handle", null));
    try session_start_cmd.addArg(Arg.positional("GOAL", "What you're trying to accomplish", null));
    try session_cmd.addSubcommand(session_start_cmd);

    const session_status_cmd = app.createCommand("status", "Show current session status");
    try session_cmd.addSubcommand(session_status_cmd);

    var session_note_cmd = app.createCommand("note", "Add a note to the session");
    try session_note_cmd.addArg(Arg.positional("MESSAGE", "Note message", null));
    try session_note_cmd.addArg(Arg.singleValueOption("role", 'r', "Role (human|agent)"));
    try session_cmd.addSubcommand(session_note_cmd);

    const session_land_cmd = app.createCommand("land", "Land the current session (push to forge)");
    try session_cmd.addSubcommand(session_land_cmd);

    const session_abandon_cmd = app.createCommand("abandon", "Abandon the current session");
    try session_cmd.addSubcommand(session_abandon_cmd);

    var session_resolve_cmd = app.createCommand("resolve", "Interactive conflict resolution");
    try session_resolve_cmd.addArg(Arg.singleValueOption("strategy", 's', "Resolution strategy: ours, theirs, or interactive (default)"));
    try session_cmd.addSubcommand(session_resolve_cmd);

    try root.addSubcommand(session_cmd);

    const matches = app.parseProcess() catch {
        try app.displayHelp();
        return;
    };

    // Load configuration to get default server
    var cfg = try config.Config.load(allocator);
    defer cfg.deinit();

    const default_server = cfg.getDefaultServer() orelse oauth.default_server;

    // Output handled by std.debug.print in command handlers

    if (matches.subcommandMatches("auth")) |auth_matches| {
        if (auth_matches.subcommandMatches("login")) |_| {
            const default_name = cfg.getDefaultServerName() orelse {
                std.debug.print("Error: No default server configured.\n", .{});
                return error.NoDefaultServer;
            };
            const server = cfg.getServer(default_name) orelse {
                std.debug.print("Error: Default server config not found.\n", .{});
                return error.NoDefaultServer;
            };
            const web_url = server.web_url orelse {
                std.debug.print("Error: Default server missing web_url.\n", .{});
                return error.NoWebUrl;
            };
            const grpc_url = server.grpc_url orelse {
                std.debug.print("Error: Default server missing grpc_url.\n", .{});
                return error.NoGrpcUrl;
            };

            const client_id: ?[]const u8 = if (auth.isFirstPartyWebUrl(web_url))
                auth.firstPartyClientId()
            else
                server.client_id;

            try auth.login(allocator, web_url, grpc_url, client_id);
            return;
        }

        if (auth_matches.subcommandMatches("status")) |_| {
            try auth.status(allocator);
            return;
        }

        if (auth_matches.subcommandMatches("logout")) |_| {
            try auth.logout(allocator);
            return;
        }

        std.debug.print("Usage: mic auth <login|status|logout>\n", .{});
        return;
    }

    if (matches.subcommandMatches("org")) |org_matches| {
        if (org_matches.subcommandMatches("list")) |_| {
            try organizations.list(allocator, default_server);
            return;
        }

        if (org_matches.subcommandMatches("get")) |get_matches| {
            if (get_matches.getSingleValue("HANDLE")) |handle| {
                try organizations.get(allocator, default_server, handle);
            } else {
                std.debug.print("Error: organization handle required\n", .{});
                std.debug.print("Usage: mic org get <handle>\n", .{});
            }
            return;
        }

        std.debug.print("Usage: mic org <list|get>\n", .{});
        return;
    }

    if (matches.subcommandMatches("project")) |project_matches| {
        if (project_matches.subcommandMatches("list")) |list_matches| {
            if (list_matches.getSingleValue("ORGANIZATION")) |org| {
                try projects.list(allocator, default_server, org);
            } else {
                std.debug.print("Error: organization required\n", .{});
                std.debug.print("Usage: mic project list <organization>\n", .{});
            }
            return;
        }

        if (project_matches.subcommandMatches("create")) |create_matches| {
            const org = create_matches.getSingleValue("ORGANIZATION");
            const handle = create_matches.getSingleValue("HANDLE");
            const name = create_matches.getSingleValue("NAME");

            if (org == null or handle == null or name == null) {
                std.debug.print("Error: organization, handle, and name required\n", .{});
                std.debug.print("Usage: mic project create <organization> <handle> <name> [--description <desc>]\n", .{});
                return;
            }

            const description = create_matches.getSingleValue("description");
            try projects.create(allocator, default_server, org.?, handle.?, name.?, description);
            return;
        }

        if (project_matches.subcommandMatches("get")) |get_matches| {
            const org = get_matches.getSingleValue("ORGANIZATION");
            const handle = get_matches.getSingleValue("HANDLE");

            if (org == null or handle == null) {
                std.debug.print("Error: organization and handle required\n", .{});
                std.debug.print("Usage: mic project get <organization> <handle>\n", .{});
                return;
            }

            try projects.get(allocator, default_server, org.?, handle.?);
            return;
        }

        if (project_matches.subcommandMatches("update")) |update_matches| {
            const org = update_matches.getSingleValue("ORGANIZATION");
            const handle = update_matches.getSingleValue("HANDLE");

            if (org == null or handle == null) {
                std.debug.print("Error: organization and handle required\n", .{});
                std.debug.print("Usage: mic project update <organization> <handle> [--name <name>] [--description <desc>] [--new-handle <handle>]\n", .{});
                return;
            }

            const name = update_matches.getSingleValue("name");
            const description = update_matches.getSingleValue("description");
            const new_handle = update_matches.getSingleValue("new-handle");

            if (name == null and description == null and new_handle == null) {
                std.debug.print("Error: supply at least one field to update\n", .{});
                std.debug.print("Usage: mic project update <organization> <handle> [--name <name>] [--description <desc>] [--new-handle <handle>]\n", .{});
                return;
            }

            try projects.update(allocator, default_server, org.?, handle.?, name, description, new_handle);
            return;
        }

        if (project_matches.subcommandMatches("delete")) |delete_matches| {
            const org = delete_matches.getSingleValue("ORGANIZATION");
            const handle = delete_matches.getSingleValue("HANDLE");

            if (org == null or handle == null) {
                std.debug.print("Error: organization and handle required\n", .{});
                std.debug.print("Usage: mic project delete <organization> <handle>\n", .{});
                return;
            }

            try projects.delete(allocator, default_server, org.?, handle.?);
            return;
        }

        std.debug.print("Project management commands:\n", .{});
        std.debug.print("  list <organization>           - List projects in an organization\n", .{});
        std.debug.print("  create <org> <handle> <name>  - Create a new project\n", .{});
        std.debug.print("  get <organization> <handle>   - Get project details\n", .{});
        std.debug.print("  update <org> <handle>         - Update project fields\n", .{});
        std.debug.print("  delete <org> <handle>         - Delete a project\n", .{});
        return;
    }

    if (matches.subcommandMatches("checkout")) |checkout_matches| {
        const project_ref = checkout_matches.getSingleValue("PROJECT");
        const path = checkout_matches.getSingleValue("path");

        if (project_ref == null) {
            std.debug.print("Error: project required\n", .{});
            std.debug.print("Usage: mic checkout <account>/<project> [--path dir]\n", .{});
            return;
        }

        const parsed = parseProjectRef(project_ref.?);
        if (parsed == null) {
            std.debug.print("Error: invalid project format\n", .{});
            std.debug.print("Usage: mic checkout <account>/<project> [--path dir]\n", .{});
            return;
        }

        try workspace.checkout(allocator, parsed.?.account, parsed.?.project, path);
        return;
    }

    if (matches.subcommandMatches("mount")) |mount_matches| {
        const project_ref = mount_matches.getSingleValue("PROJECT");
        const path = mount_matches.getSingleValue("path");
        const port_str = mount_matches.getSingleValue("port");

        if (project_ref == null) {
            std.debug.print("Error: project required\n", .{});
            std.debug.print("Usage: mic mount <account>/<project> [--path dir] [--port n]\n", .{});
            return;
        }

        const parsed = parseProjectRef(project_ref.?);
        if (parsed == null) {
            std.debug.print("Error: invalid project format\n", .{});
            std.debug.print("Usage: mic mount <account>/<project> [--path dir] [--port n]\n", .{});
            return;
        }

        const port: u16 = if (port_str) |value|
            std.fmt.parseInt(u16, value, 10) catch {
                std.debug.print("Error: invalid port\n", .{});
                std.debug.print("Usage: mic mount <account>/<project> [--path dir] [--port n]\n", .{});
                return;
            }
        else
            mount.DefaultPort;

        if (port == 0) {
            std.debug.print("Error: port must be greater than 0\n", .{});
            return;
        }

        try mount.mount(allocator, parsed.?.account, parsed.?.project, path, port);
        return;
    }

    if (matches.subcommandMatches("unmount")) |unmount_matches| {
        const path = unmount_matches.getSingleValue("PATH");

        if (path == null) {
            std.debug.print("Error: mount path required\n", .{});
            std.debug.print("Usage: mic unmount <path>\n", .{});
            return;
        }

        try mount.unmount(allocator, path.?);
        return;
    }

    if (matches.subcommandMatches("status")) |_| {
        try workspace.status(allocator);
        return;
    }

    if (matches.subcommandMatches("land")) |land_matches| {
        const goal = land_matches.getSingleValue("GOAL");
        if (goal == null) {
            std.debug.print("Error: goal required\n", .{});
            std.debug.print("Usage: mic land <goal>\n", .{});
            return;
        }

        try workspace.land(allocator, goal.?);
        return;
    }

    if (matches.subcommandMatches("sync")) |sync_matches| {
        const strategy_raw = sync_matches.getSingleValue("strategy") orelse "interactive";
        const strategy = workspace.parseMergeStrategy(strategy_raw) orelse {
            std.debug.print("Error: invalid strategy '{s}'.\n", .{strategy_raw});
            std.debug.print("Usage: mic sync [--strategy ours|theirs|interactive]\n", .{});
            return;
        };
        _ = try workspace.syncWorkspace(allocator, strategy);
        return;
    }

    if (matches.subcommandMatches("clone")) |clone_matches| {
        const project_ref = clone_matches.getSingleValue("PROJECT");

        if (project_ref == null) {
            std.debug.print("Error: project required\n", .{});
            std.debug.print("Usage: mic clone <account>/<project>\n", .{});
            return;
        }

        const parsed = parseProjectRef(project_ref.?);
        if (parsed == null) {
            std.debug.print("Error: invalid project format\n", .{});
            std.debug.print("Usage: mic clone <account>/<project>\n", .{});
            return;
        }

        // Clone uses checkout with the project name as the default directory
        try workspace.checkout(allocator, parsed.?.account, parsed.?.project, null);
        return;
    }

    if (matches.subcommandMatches("cat")) |cat_matches| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const account = cat_matches.getSingleValue("ACCOUNT");
        const project = cat_matches.getSingleValue("PROJECT");
        const path = cat_matches.getSingleValue("PATH");
        const position_str = cat_matches.getSingleValue("position");

        const position: ?u64 = if (position_str) |value| blk: {
            const parsed = parsePositionOrLatest(value) orelse {
                std.debug.print("Error: invalid position\n", .{});
                std.debug.print("  position can be @N, N, @latest, or HEAD\n", .{});
                return;
            };
            break :blk switch (parsed) {
                .position => |p| p,
                .latest => null,
            };
        } else null;

        var target = resolveCatTarget(arena_alloc, default_server, account, project, path) catch |err| {
            switch (err) {
                error.InvalidCatArguments => {
                    std.debug.print("Error: account, project, and path required\n", .{});
                    std.debug.print("Usage:\n", .{});
                    std.debug.print("  mic cat <account> <project> <path> [--position <@N>]\n", .{});
                    std.debug.print("  mic cat <account>/<project> <path> [--position <@N>]\n", .{});
                    std.debug.print("  mic cat <path> [--position <@N>] (from workspace)\n", .{});
                },
                error.NoWorkspace => {
                    std.debug.print("Error: no workspace found in current directory\n", .{});
                    std.debug.print("Usage: mic cat <account> <project> <path> [--position <@N>]\n", .{});
                },
                error.InvalidPath => {
                    std.debug.print("Error: path required\n", .{});
                    std.debug.print("Usage: mic cat <account> <project> <path> [--position <@N>]\n", .{});
                },
                else => return err,
            }
            return;
        };
        defer target.deinit(arena_alloc);

        try content.cat(
            arena_alloc,
            target.server,
            target.account,
            target.project,
            target.path,
            position,
        );
        return;
    }

    if (matches.subcommandMatches("ls")) |ls_matches| {
        const account = ls_matches.getSingleValue("ACCOUNT");
        const project = ls_matches.getSingleValue("PROJECT");
        const path = ls_matches.getSingleValue("path");
        const position_str = ls_matches.getSingleValue("position");

        if (account == null or project == null) {
            std.debug.print("Error: account and project required\n", .{});
            std.debug.print("Usage: mic ls <account> <project> [--path prefix] [--position <@N>]\n", .{});
            return;
        }

        const position: ?u64 = if (position_str) |value| blk: {
            const parsed = parsePositionOrLatest(value) orelse {
                std.debug.print("Error: invalid position\n", .{});
                std.debug.print("  position can be @N, N, @latest, or HEAD\n", .{});
                return;
            };
            break :blk switch (parsed) {
                .position => |p| p,
                .latest => null,
            };
        } else null;

        try content.ls(allocator, default_server, account.?, project.?, path, position);
        return;
    }

    if (matches.subcommandMatches("blame")) |blame_matches| {
        const account = blame_matches.getSingleValue("ACCOUNT");
        const project = blame_matches.getSingleValue("PROJECT");
        const path = blame_matches.getSingleValue("PATH");

        if (account == null or project == null or path == null) {
            std.debug.print("Error: account, project, and path required\n", .{});
            std.debug.print("Usage: mic blame <account> <project> <path>\n", .{});
            return;
        }

        try content.blame(allocator, default_server, account.?, project.?, path.?);
        return;
    }

    if (matches.subcommandMatches("write")) |write_matches| {
        const path = write_matches.getSingleValue("PATH");
        if (path == null) {
            std.debug.print("Error: path required\n", .{});
            std.debug.print("Usage: mic write <path>\n", .{});
            return;
        }

        try session.write(allocator, path.?);
        return;
    }

    if (matches.subcommandMatches("log")) |log_matches| {
        const project_ref = log_matches.getSingleValue("PROJECT");
        const path_filter = log_matches.getSingleValue("path");
        const limit_str = log_matches.getSingleValue("limit");

        if (project_ref == null) {
            std.debug.print("Error: project required\n", .{});
            std.debug.print("Usage: mic log <account>/<project> [--path <path>] [--limit <n>]\n", .{});
            return;
        }

        const parsed = parseProjectRef(project_ref.?);
        if (parsed == null) {
            std.debug.print("Error: invalid project format\n", .{});
            std.debug.print("Usage: mic log <account>/<project>\n", .{});
            return;
        }

        const limit: u32 = if (limit_str) |s|
            std.fmt.parseInt(u32, s, 10) catch 20
        else
            20;

        try log.list(allocator, parsed.?.account, parsed.?.project, path_filter, limit);
        return;
    }

    if (matches.subcommandMatches("diff")) |diff_matches| {
        const project_ref = diff_matches.getSingleValue("PROJECT");
        const from_str = diff_matches.getSingleValue("FROM");
        const to_str = diff_matches.getSingleValue("TO");

        if (project_ref == null or from_str == null) {
            std.debug.print("Error: project and from position required\n", .{});
            std.debug.print("Usage: mic diff <account>/<project> <from> [to]\n", .{});
            std.debug.print("  from/to can be @N, N, @latest, or HEAD\n", .{});
            return;
        }

        const parsed = parseProjectRef(project_ref.?);
        if (parsed == null) {
            std.debug.print("Error: invalid project format\n", .{});
            std.debug.print("Usage: mic diff <account>/<project> <from> [to]\n", .{});
            return;
        }

        const from_parsed = parsePositionOrLatest(from_str.?) orelse {
            std.debug.print("Error: invalid from position\n", .{});
            return;
        };

        // Convert PositionOrLatest to the format diff.show expects
        const from_position: ?u64 = switch (from_parsed) {
            .position => |p| p,
            .latest => null, // null means HEAD
        };

        const to_position: ?u64 = if (to_str) |s| blk: {
            const to_parsed = parsePositionOrLatest(s) orelse {
                std.debug.print("Error: invalid to position\n", .{});
                return;
            };
            break :blk switch (to_parsed) {
                .position => |p| p,
                .latest => null,
            };
        } else null;

        try diff.show(allocator, parsed.?.account, parsed.?.project, from_position, to_position);
        return;
    }

    if (matches.subcommandMatches("goto")) |goto_matches| {
        const project_ref = goto_matches.getSingleValue("PROJECT");
        const position_str = goto_matches.getSingleValue("POSITION");
        const path_prefix = goto_matches.getSingleValue("path");

        if (project_ref == null or position_str == null) {
            std.debug.print("Error: project and position required\n", .{});
            std.debug.print("Usage: mic goto <account>/<project> <position> [--path prefix]\n", .{});
            std.debug.print("  position can be @N, N, @latest, or HEAD\n", .{});
            return;
        }

        const parsed = parseProjectRef(project_ref.?);
        if (parsed == null) {
            std.debug.print("Error: invalid project format\n", .{});
            std.debug.print("Usage: mic goto <account>/<project> <position>\n", .{});
            return;
        }

        const pos_parsed = parsePositionOrLatest(position_str.?) orelse {
            std.debug.print("Error: invalid position\n", .{});
            return;
        };

        // Convert to optional u64 (null means HEAD)
        const position: ?u64 = switch (pos_parsed) {
            .position => |p| p,
            .latest => null,
        };

        try goto.show(allocator, parsed.?.account, parsed.?.project, position, path_prefix);
        return;
    }

    if (matches.subcommandMatches("session")) |session_matches| {
        if (session_matches.subcommandMatches("start")) |start_matches| {
            const org = start_matches.getSingleValue("ORGANIZATION");
            const project = start_matches.getSingleValue("PROJECT");
            const goal = start_matches.getSingleValue("GOAL");

            if (org == null or project == null or goal == null) {
                std.debug.print("Error: organization, project, and goal required\n", .{});
                std.debug.print("Usage: mic session start <organization> <project> <goal>\n", .{});
                return;
            }

            try session.start(allocator, org.?, project.?, goal.?);
            return;
        }

        if (session_matches.subcommandMatches("status")) |_| {
            try session.status(allocator);
            return;
        }

        if (session_matches.subcommandMatches("note")) |note_matches| {
            const message = note_matches.getSingleValue("MESSAGE");
            const role = note_matches.getSingleValue("role") orelse "human";

            if (message == null) {
                std.debug.print("Error: message required\n", .{});
                std.debug.print("Usage: mic session note <message> [--role human|agent]\n", .{});
                return;
            }

            try session.addNote(allocator, role, message.?);
            return;
        }

        if (session_matches.subcommandMatches("land")) |_| {
            try session.land(allocator, default_server);
            return;
        }

        if (session_matches.subcommandMatches("abandon")) |_| {
            try session.abandon(allocator);
            return;
        }

        if (session_matches.subcommandMatches("resolve")) |resolve_matches| {
            const strategy = resolve_matches.getSingleValue("strategy") orelse "interactive";
            try session.resolve(allocator, default_server, strategy);
            return;
        }

        std.debug.print("Session management commands:\n", .{});
        std.debug.print("  start <org> <project> <goal>  - Start a new session\n", .{});
        std.debug.print("  status                        - Show current session status\n", .{});
        std.debug.print("  note <message> [--role]       - Add a note to the session\n", .{});
        std.debug.print("  land                          - Land the session (push to forge)\n", .{});
        std.debug.print("  abandon                       - Abandon the current session\n", .{});
        std.debug.print("  resolve [--strategy]          - Interactive conflict resolution\n", .{});
        return;
    }

    try app.displayHelp();
}

const ProjectRef = struct {
    account: []const u8,
    project: []const u8,
};

const CatTarget = struct {
    server: []const u8,
    account: []const u8,
    project: []const u8,
    path: []const u8,

    fn deinit(self: *CatTarget, allocator: std.mem.Allocator) void {
        allocator.free(self.server);
        allocator.free(self.account);
        allocator.free(self.project);
        allocator.free(self.path);
        self.* = undefined;
    }
};

fn parseProjectRef(value: []const u8) ?ProjectRef {
    const slash_index = std.mem.indexOfScalar(u8, value, '/') orelse return null;
    if (slash_index == 0 or slash_index + 1 >= value.len) return null;
    if (std.mem.indexOfScalar(u8, value[slash_index + 1 ..], '/') != null) return null;

    return .{
        .account = value[0..slash_index],
        .project = value[slash_index + 1 ..],
    };
}

fn resolveCatTarget(
    allocator: std.mem.Allocator,
    server: []const u8,
    account: ?[]const u8,
    project: ?[]const u8,
    path: ?[]const u8,
) !CatTarget {
    if (account != null and project != null and path != null) {
        const normalized = normalizeContentPath(path.?);
        if (normalized.len == 0) return error.InvalidPath;

        return .{
            .server = try allocator.dupe(u8, server),
            .account = try allocator.dupe(u8, account.?),
            .project = try allocator.dupe(u8, project.?),
            .path = try allocator.dupe(u8, normalized),
        };
    }

    if (account != null and project != null and path == null) {
        if (parseProjectRef(account.?)) |parsed| {
            const normalized = normalizeContentPath(project.?);
            if (normalized.len == 0) return error.InvalidPath;

            return .{
                .server = try allocator.dupe(u8, server),
                .account = try allocator.dupe(u8, parsed.account),
                .project = try allocator.dupe(u8, parsed.project),
                .path = try allocator.dupe(u8, normalized),
            };
        }
    }

    if (account != null and project == null and path == null) {
        const normalized = normalizeContentPath(account.?);
        if (normalized.len == 0) return error.InvalidPath;
        return resolveCatFromWorkspace(allocator, normalized);
    }

    return error.InvalidCatArguments;
}

fn resolveCatFromWorkspace(allocator: std.mem.Allocator, path: []const u8) !CatTarget {
    const workspace_root = try std.process.getCwdAlloc(allocator);
    defer allocator.free(workspace_root);

    const parsed = try manifest.load(allocator, workspace_root);
    if (parsed == null) return error.NoWorkspace;
    defer parsed.?.deinit();

    const state = parsed.?.value;

    return .{
        .server = try allocator.dupe(u8, state.server),
        .account = try allocator.dupe(u8, state.account),
        .project = try allocator.dupe(u8, state.project),
        .path = try allocator.dupe(u8, path),
    };
}

fn normalizeContentPath(path: []const u8) []const u8 {
    var trimmed = path;
    while (trimmed.len > 0 and trimmed[0] == '/') {
        trimmed = trimmed[1..];
    }
    return trimmed;
}

const PositionOrLatest = union(enum) {
    position: u64,
    latest,
};

/// Parse a position like "@10", "10", "@position:10", "@latest", or "HEAD" into PositionOrLatest
/// Returns null for invalid input
fn parsePositionOrLatest(value: []const u8) ?PositionOrLatest {
    // Handle @position:N format
    if (std.mem.startsWith(u8, value, "@position:")) {
        const num_str = value[10..];
        if (num_str.len == 0) return null;
        const pos = std.fmt.parseInt(u64, num_str, 10) catch return null;
        return .{ .position = pos };
    }

    const trimmed = if (value.len > 0 and value[0] == '@') value[1..] else value;
    if (trimmed.len == 0) return null;

    if (std.ascii.eqlIgnoreCase(trimmed, "latest") or std.ascii.eqlIgnoreCase(trimmed, "head")) {
        return .latest;
    }

    const pos = std.fmt.parseInt(u64, trimmed, 10) catch return null;
    return .{ .position = pos };
}

test "parsePositionOrLatest handles latest and head tokens" {
    const head = parsePositionOrLatest("HEAD") orelse return error.TestExpectedEqual;
    const head_lower = parsePositionOrLatest("head") orelse return error.TestExpectedEqual;
    const head_prefixed = parsePositionOrLatest("@head") orelse return error.TestExpectedEqual;
    const latest_prefixed = parsePositionOrLatest("@latest") orelse return error.TestExpectedEqual;
    const latest = parsePositionOrLatest("latest") orelse return error.TestExpectedEqual;

    switch (head) {
        .latest => {},
        else => return error.TestExpectedEqual,
    }
    switch (head_lower) {
        .latest => {},
        else => return error.TestExpectedEqual,
    }
    switch (head_prefixed) {
        .latest => {},
        else => return error.TestExpectedEqual,
    }
    switch (latest_prefixed) {
        .latest => {},
        else => return error.TestExpectedEqual,
    }
    switch (latest) {
        .latest => {},
        else => return error.TestExpectedEqual,
    }
}

test "parsePositionOrLatest parses numeric positions" {
    const value = parsePositionOrLatest("@42") orelse return error.TestExpectedEqual;
    switch (value) {
        .position => |pos| try std.testing.expectEqual(@as(u64, 42), pos),
        else => return error.TestExpectedEqual,
    }

    const direct = parsePositionOrLatest("7") orelse return error.TestExpectedEqual;
    switch (direct) {
        .position => |pos| try std.testing.expectEqual(@as(u64, 7), pos),
        else => return error.TestExpectedEqual,
    }
}

test "resolveCatTarget supports explicit account and project" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var target = try resolveCatTarget(allocator, oauth.default_server, "acme", "app", "/README.md");
    defer target.deinit(allocator);

    try std.testing.expectEqualStrings(oauth.default_server, target.server);
    try std.testing.expectEqualStrings("acme", target.account);
    try std.testing.expectEqualStrings("app", target.project);
    try std.testing.expectEqualStrings("README.md", target.path);
}

test "resolveCatTarget supports project ref plus path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var target = try resolveCatTarget(allocator, oauth.default_server, "acme/app", "docs/guide.md", null);
    defer target.deinit(allocator);

    try std.testing.expectEqualStrings(oauth.default_server, target.server);
    try std.testing.expectEqualStrings("acme", target.account);
    try std.testing.expectEqualStrings("app", target.project);
    try std.testing.expectEqualStrings("docs/guide.md", target.path);
}

test "resolveCatTarget reads workspace manifest when only path provided" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const temp_root = try temp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(temp_root);

    var restore_dir = try std.fs.openDirAbsolute(cwd, .{});
    defer {
        restore_dir.setAsCwd() catch {};
        restore_dir.close();
    }

    var temp_dir = try std.fs.openDirAbsolute(temp_root, .{});
    defer temp_dir.close();
    try temp_dir.setAsCwd();

    const entries = [_]manifest.WorkspaceEntry{};
    const state = manifest.WorkspaceState{
        .version = 1,
        .server = "http://forge.example:50051",
        .account = "acme",
        .project = "app",
        .tree_hash = "deadbeef",
        .entries = entries[0..],
    };

    try manifest.save(allocator, temp_root, state);

    var target = try resolveCatTarget(allocator, oauth.default_server, "notes.md", null, null);
    defer target.deinit(allocator);

    try std.testing.expectEqualStrings("http://forge.example:50051", target.server);
    try std.testing.expectEqualStrings("acme", target.account);
    try std.testing.expectEqualStrings("app", target.project);
    try std.testing.expectEqualStrings("notes.md", target.path);
}

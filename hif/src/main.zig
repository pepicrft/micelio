const std = @import("std");
const yazap = @import("yazap");
const oauth = @import("oauth.zig");
const projects = @import("projects.zig");
const session = @import("session.zig");
const content = @import("content.zig");
const workspace = @import("workspace.zig");
const log = @import("log.zig");

const App = yazap.App;
const Arg = yazap.Arg;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, "hif", "The Micelio CLI - a forge-first version control system for the agent era");
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

    // Status: Show workspace changes
    const status_cmd = app.createCommand("status", "Show workspace changes");
    try root.addSubcommand(status_cmd);

    // Land: Land workspace changes
    var land_cmd = app.createCommand("land", "Land workspace changes");
    try land_cmd.addArg(Arg.positional("GOAL", "What you're trying to accomplish", null));
    try root.addSubcommand(land_cmd);

    // Sync: Pull latest changes from the forge
    const sync_cmd = app.createCommand("sync", "Sync workspace with latest upstream changes");
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
    try root.addSubcommand(cat_cmd);

    var ls_cmd = app.createCommand("ls", "List tree entries from the forge");
    try ls_cmd.addArg(Arg.positional("ACCOUNT", "Account handle", null));
    try ls_cmd.addArg(Arg.positional("PROJECT", "Project handle", null));
    try ls_cmd.addArg(Arg.singleValueOption("path", 'p', "Optional path prefix"));
    try root.addSubcommand(ls_cmd);

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

    // Output handled by std.debug.print in oauth functions

    if (matches.subcommandMatches("auth")) |auth_matches| {
        if (auth_matches.subcommandMatches("login")) |_| {
            try oauth.login(allocator, oauth.default_server);
            return;
        }

        if (auth_matches.subcommandMatches("status")) |_| {
            try oauth.status(allocator, oauth.default_server);
            return;
        }

        if (auth_matches.subcommandMatches("logout")) |_| {
            try oauth.logout(allocator);
            return;
        }

        std.debug.print("Usage: hif auth <login|status|logout>\n", .{});
        return;
    }

    if (matches.subcommandMatches("project")) |project_matches| {
        if (project_matches.subcommandMatches("list")) |list_matches| {
            if (list_matches.getSingleValue("ORGANIZATION")) |org| {
                try projects.list(allocator, oauth.default_server, org);
            } else {
                std.debug.print("Error: organization required\n", .{});
                std.debug.print("Usage: hif project list <organization>\n", .{});
            }
            return;
        }

        if (project_matches.subcommandMatches("create")) |create_matches| {
            const org = create_matches.getSingleValue("ORGANIZATION");
            const handle = create_matches.getSingleValue("HANDLE");
            const name = create_matches.getSingleValue("NAME");

            if (org == null or handle == null or name == null) {
                std.debug.print("Error: organization, handle, and name required\n", .{});
                std.debug.print("Usage: hif project create <organization> <handle> <name> [--description <desc>]\n", .{});
                return;
            }

            const description = create_matches.getSingleValue("description");
            try projects.create(allocator, oauth.default_server, org.?, handle.?, name.?, description);
            return;
        }

        if (project_matches.subcommandMatches("get")) |get_matches| {
            const org = get_matches.getSingleValue("ORGANIZATION");
            const handle = get_matches.getSingleValue("HANDLE");

            if (org == null or handle == null) {
                std.debug.print("Error: organization and handle required\n", .{});
                std.debug.print("Usage: hif project get <organization> <handle>\n", .{});
                return;
            }

            try projects.get(allocator, oauth.default_server, org.?, handle.?);
            return;
        }

        if (project_matches.subcommandMatches("update")) |update_matches| {
            const org = update_matches.getSingleValue("ORGANIZATION");
            const handle = update_matches.getSingleValue("HANDLE");

            if (org == null or handle == null) {
                std.debug.print("Error: organization and handle required\n", .{});
                std.debug.print("Usage: hif project update <organization> <handle> [--name <name>] [--description <desc>] [--new-handle <handle>]\n", .{});
                return;
            }

            const name = update_matches.getSingleValue("name");
            const description = update_matches.getSingleValue("description");
            const new_handle = update_matches.getSingleValue("new-handle");

            if (name == null and description == null and new_handle == null) {
                std.debug.print("Error: supply at least one field to update\n", .{});
                std.debug.print("Usage: hif project update <organization> <handle> [--name <name>] [--description <desc>] [--new-handle <handle>]\n", .{});
                return;
            }

            try projects.update(allocator, oauth.default_server, org.?, handle.?, name, description, new_handle);
            return;
        }

        if (project_matches.subcommandMatches("delete")) |delete_matches| {
            const org = delete_matches.getSingleValue("ORGANIZATION");
            const handle = delete_matches.getSingleValue("HANDLE");

            if (org == null or handle == null) {
                std.debug.print("Error: organization and handle required\n", .{});
                std.debug.print("Usage: hif project delete <organization> <handle>\n", .{});
                return;
            }

            try projects.delete(allocator, oauth.default_server, org.?, handle.?);
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
            std.debug.print("Usage: hif checkout <account>/<project> [--path dir]\n", .{});
            return;
        }

        const parsed = parseProjectRef(project_ref.?);
        if (parsed == null) {
            std.debug.print("Error: invalid project format\n", .{});
            std.debug.print("Usage: hif checkout <account>/<project> [--path dir]\n", .{});
            return;
        }

        try workspace.checkout(allocator, parsed.?.account, parsed.?.project, path);
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
            std.debug.print("Usage: hif land <goal>\n", .{});
            return;
        }

        try workspace.land(allocator, goal.?);
        return;
    }

    if (matches.subcommandMatches("sync")) |_| {
        _ = try workspace.sync(allocator);
        return;
    }

    if (matches.subcommandMatches("clone")) |clone_matches| {
        const project_ref = clone_matches.getSingleValue("PROJECT");

        if (project_ref == null) {
            std.debug.print("Error: project required\n", .{});
            std.debug.print("Usage: hif clone <account>/<project>\n", .{});
            return;
        }

        const parsed = parseProjectRef(project_ref.?);
        if (parsed == null) {
            std.debug.print("Error: invalid project format\n", .{});
            std.debug.print("Usage: hif clone <account>/<project>\n", .{});
            return;
        }

        // Clone uses checkout with the project name as the default directory
        try workspace.checkout(allocator, parsed.?.account, parsed.?.project, null);
        return;
    }

    if (matches.subcommandMatches("cat")) |cat_matches| {
        const account = cat_matches.getSingleValue("ACCOUNT");
        const project = cat_matches.getSingleValue("PROJECT");
        const path = cat_matches.getSingleValue("PATH");

        if (account == null or project == null or path == null) {
            std.debug.print("Error: account, project, and path required\n", .{});
            std.debug.print("Usage: hif cat <account> <project> <path>\n", .{});
            return;
        }

        try content.cat(allocator, oauth.default_server, account.?, project.?, path.?);
        return;
    }

    if (matches.subcommandMatches("ls")) |ls_matches| {
        const account = ls_matches.getSingleValue("ACCOUNT");
        const project = ls_matches.getSingleValue("PROJECT");
        const path = ls_matches.getSingleValue("path");

        if (account == null or project == null) {
            std.debug.print("Error: account and project required\n", .{});
            std.debug.print("Usage: hif ls <account> <project> [--path prefix]\n", .{});
            return;
        }

        try content.ls(allocator, oauth.default_server, account.?, project.?, path);
        return;
    }

    if (matches.subcommandMatches("write")) |write_matches| {
        const path = write_matches.getSingleValue("PATH");
        if (path == null) {
            std.debug.print("Error: path required\n", .{});
            std.debug.print("Usage: hif write <path>\n", .{});
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
            std.debug.print("Usage: hif log <account>/<project> [--path <path>] [--limit <n>]\n", .{});
            return;
        }

        const parsed = parseProjectRef(project_ref.?);
        if (parsed == null) {
            std.debug.print("Error: invalid project format\n", .{});
            std.debug.print("Usage: hif log <account>/<project>\n", .{});
            return;
        }

        const limit: u32 = if (limit_str) |s|
            std.fmt.parseInt(u32, s, 10) catch 20
        else
            20;

        try log.list(allocator, parsed.?.account, parsed.?.project, path_filter, limit);
        return;
    }

    if (matches.subcommandMatches("session")) |session_matches| {
        if (session_matches.subcommandMatches("start")) |start_matches| {
            const org = start_matches.getSingleValue("ORGANIZATION");
            const project = start_matches.getSingleValue("PROJECT");
            const goal = start_matches.getSingleValue("GOAL");

            if (org == null or project == null or goal == null) {
                std.debug.print("Error: organization, project, and goal required\n", .{});
                std.debug.print("Usage: hif session start <organization> <project> <goal>\n", .{});
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
                std.debug.print("Usage: hif session note <message> [--role human|agent]\n", .{});
                return;
            }

            try session.addNote(allocator, role, message.?);
            return;
        }

        if (session_matches.subcommandMatches("land")) |_| {
            try session.land(allocator, oauth.default_server);
            return;
        }

        if (session_matches.subcommandMatches("abandon")) |_| {
            try session.abandon(allocator);
            return;
        }

        if (session_matches.subcommandMatches("resolve")) |resolve_matches| {
            const strategy = resolve_matches.getSingleValue("strategy") orelse "interactive";
            try session.resolve(allocator, oauth.default_server, strategy);
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

fn parseProjectRef(value: []const u8) ?ProjectRef {
    const slash_index = std.mem.indexOfScalar(u8, value, '/') orelse return null;
    if (slash_index == 0 or slash_index + 1 >= value.len) return null;
    if (std.mem.indexOfScalar(u8, value[slash_index + 1 ..], '/') != null) return null;

    return .{
        .account = value[0..slash_index],
        .project = value[slash_index + 1 ..],
    };
}

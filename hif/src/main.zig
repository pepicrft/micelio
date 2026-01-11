const std = @import("std");
const yazap = @import("yazap");
const oauth = @import("oauth.zig");

const App = yazap.App;
const Arg = yazap.Arg;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, "hif", "A forge-first version control system for the agent era");
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
    const project_cmd = app.createCommand("project", "Manage projects");
    try root.addSubcommand(project_cmd);

    // Clone: Initialize local state for a forge project
    var clone_cmd = app.createCommand("clone", "Clone a project from the forge");
    try clone_cmd.addArg(Arg.positional("PROJECT", "Project URL or name (e.g., org/myapp)", null));
    try root.addSubcommand(clone_cmd);

    // Session: Manage work sessions
    const session_cmd = app.createCommand("session", "Manage work sessions");
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

    if (matches.subcommandMatches("project")) |_| {
        std.debug.print("Project management commands:\n", .{});
        std.debug.print("  create  - Create a new project on the forge\n", .{});
        std.debug.print("  list    - List your projects\n", .{});
        std.debug.print("\n(Not yet implemented - forge connection required)\n", .{});
        return;
    }

    if (matches.subcommandMatches("clone")) |clone_matches| {
        if (clone_matches.getSingleValue("PROJECT")) |project| {
            std.debug.print("Cloning project '{s}'...\n", .{project});
            std.debug.print("(Not yet implemented - forge connection required)\n", .{});
        } else {
            std.debug.print("Error: project name required\n", .{});
            std.debug.print("Usage: hif clone <project>\n", .{});
        }
        return;
    }

    if (matches.subcommandMatches("session")) |_| {
        std.debug.print("Session management commands:\n", .{});
        std.debug.print("  start   - Start a new session with a goal\n", .{});
        std.debug.print("  status  - Show current session status\n", .{});
        std.debug.print("  land    - Land the current session\n", .{});
        std.debug.print("  abandon - Abandon the current session\n", .{});
        std.debug.print("\n(Not yet implemented - forge connection required)\n", .{});
        return;
    }

    try app.displayHelp();
}

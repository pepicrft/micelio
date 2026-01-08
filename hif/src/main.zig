const std = @import("std");
const yazap = @import("yazap");

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
    const auth_cmd = app.createCommand("auth", "Authenticate with a forge");
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

    var buf: [256]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&buf);

    if (matches.subcommandMatches("auth")) |_| {
        try stdout.interface.writeAll("Authenticating with forge...\n");
        try stdout.interface.writeAll("(Not yet implemented - forge connection required)\n");
        try stdout.interface.flush();
        return;
    }

    if (matches.subcommandMatches("project")) |_| {
        try stdout.interface.writeAll("Project management commands:\n");
        try stdout.interface.writeAll("  create  - Create a new project on the forge\n");
        try stdout.interface.writeAll("  list    - List your projects\n");
        try stdout.interface.writeAll("\n(Not yet implemented - forge connection required)\n");
        try stdout.interface.flush();
        return;
    }

    if (matches.subcommandMatches("clone")) |clone_matches| {
        if (clone_matches.getSingleValue("PROJECT")) |project| {
            try stdout.interface.print("Cloning project '{s}'...\n", .{project});
            try stdout.interface.writeAll("(Not yet implemented - forge connection required)\n");
        } else {
            try stdout.interface.writeAll("Error: project name required\n");
            try stdout.interface.writeAll("Usage: hif clone <project>\n");
        }
        try stdout.interface.flush();
        return;
    }

    if (matches.subcommandMatches("session")) |_| {
        try stdout.interface.writeAll("Session management commands:\n");
        try stdout.interface.writeAll("  start   - Start a new session with a goal\n");
        try stdout.interface.writeAll("  status  - Show current session status\n");
        try stdout.interface.writeAll("  land    - Land the current session\n");
        try stdout.interface.writeAll("  abandon - Abandon the current session\n");
        try stdout.interface.writeAll("\n(Not yet implemented - forge connection required)\n");
        try stdout.interface.flush();
        return;
    }

    try app.displayHelp();
}

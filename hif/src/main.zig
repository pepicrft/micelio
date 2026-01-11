const std = @import("std");
const yazap = @import("yazap");
const oauth = @import("oauth.zig");
const projects = @import("projects.zig");

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

        std.debug.print("Project management commands:\n", .{});
        std.debug.print("  list <organization>           - List projects in an organization\n", .{});
        std.debug.print("  create <org> <handle> <name>  - Create a new project\n", .{});
        std.debug.print("  get <organization> <handle>   - Get project details\n", .{});
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

const std = @import("std");
const http = @import("http.zig");
const oauth = @import("oauth.zig");

const Project = struct {
    id: []const u8,
    handle: []const u8,
    name: []const u8,
    description: ?[]const u8,
    organization_handle: []const u8,
    inserted_at: []const u8,
    updated_at: []const u8,
};

const ProjectResponse = struct {
    project: Project,
};

const ProjectsListResponse = struct {
    projects: []Project,
};

const ErrorResponse = struct {
    @"error": []const u8,
    errors: ?std.json.Value = null,
};

pub fn list(allocator: std.mem.Allocator, server: []const u8, organization: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    var client = std.http.Client{ .allocator = arena_alloc };
    defer client.deinit();

    const url = try std.fmt.allocPrint(arena_alloc, "{s}/api/projects?organization={s}", .{ server, organization });
    const response = try http.getJson(arena_alloc, &client, url, creds.?.access_token.?);

    if (response.status != .ok) {
        const err_response = std.json.parseFromSliceLeaky(ErrorResponse, arena_alloc, response.body, .{ .ignore_unknown_fields = true }) catch {
            std.debug.print("Error: Request failed with status {}\n", .{response.status});
            return error.RequestFailed;
        };
        std.debug.print("Error: {s}\n", .{err_response.@"error"});
        return error.RequestFailed;
    }

    const list_response = try std.json.parseFromSliceLeaky(ProjectsListResponse, arena_alloc, response.body, .{ .ignore_unknown_fields = true });

    if (list_response.projects.len == 0) {
        std.debug.print("No projects found for organization '{s}'\n", .{organization});
        return;
    }

    std.debug.print("Projects in '{s}':\n", .{organization});
    for (list_response.projects) |project| {
        std.debug.print("  {s}/{s} - {s}\n", .{ project.organization_handle, project.handle, project.name });
        if (project.description) |desc| {
            std.debug.print("    {s}\n", .{desc});
        }
    }
}

pub fn create(allocator: std.mem.Allocator, server: []const u8, organization: []const u8, handle: []const u8, name: []const u8, description: ?[]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    var client = std.http.Client{ .allocator = arena_alloc };
    defer client.deinit();

    const payload_struct = struct {
        organization: []const u8,
        handle: []const u8,
        name: []const u8,
        description: ?[]const u8 = null,
    }{
        .organization = organization,
        .handle = handle,
        .name = name,
        .description = description,
    };

    var payload_buf = std.io.Writer.Allocating.init(arena_alloc);
    defer payload_buf.deinit();
    const formatter = std.json.fmt(payload_struct, .{});
    try formatter.format(&payload_buf.writer);
    const payload = try payload_buf.toOwnedSlice();

    const url = try std.fmt.allocPrint(arena_alloc, "{s}/api/projects", .{server});
    const response = try http.postJsonAuth(arena_alloc, &client, url, payload, creds.?.access_token.?);

    if (response.status != .created and response.status != .ok) {
        const err_response = std.json.parseFromSliceLeaky(ErrorResponse, arena_alloc, response.body, .{ .ignore_unknown_fields = true }) catch {
            std.debug.print("Error: Request failed with status {}\n", .{response.status});
            return error.RequestFailed;
        };
        std.debug.print("Error: {s}\n", .{err_response.@"error"});
        if (err_response.errors) |errors| {
            std.debug.print("Details: {}\n", .{errors});
        }
        return error.RequestFailed;
    }

    const project_response = try std.json.parseFromSliceLeaky(ProjectResponse, arena_alloc, response.body, .{ .ignore_unknown_fields = true });
    std.debug.print("Created project: {s}/{s}\n", .{ project_response.project.organization_handle, project_response.project.handle });
    std.debug.print("Name: {s}\n", .{project_response.project.name});
    if (project_response.project.description) |desc| {
        std.debug.print("Description: {s}\n", .{desc});
    }
}

pub fn get(allocator: std.mem.Allocator, server: []const u8, organization: []const u8, handle: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    var client = std.http.Client{ .allocator = arena_alloc };
    defer client.deinit();

    const url = try std.fmt.allocPrint(arena_alloc, "{s}/api/projects/{s}/{s}", .{ server, organization, handle });
    const response = try http.getJson(arena_alloc, &client, url, creds.?.access_token.?);

    if (response.status != .ok) {
        const err_response = std.json.parseFromSliceLeaky(ErrorResponse, arena_alloc, response.body, .{ .ignore_unknown_fields = true }) catch {
            std.debug.print("Error: Request failed with status {}\n", .{response.status});
            return error.RequestFailed;
        };
        std.debug.print("Error: {s}\n", .{err_response.@"error"});
        return error.RequestFailed;
    }

    const project_response = try std.json.parseFromSliceLeaky(ProjectResponse, arena_alloc, response.body, .{ .ignore_unknown_fields = true });
    const project = project_response.project;

    std.debug.print("Project: {s}/{s}\n", .{ project.organization_handle, project.handle });
    std.debug.print("Name: {s}\n", .{project.name});
    if (project.description) |desc| {
        std.debug.print("Description: {s}\n", .{desc});
    }
    std.debug.print("ID: {s}\n", .{project.id});
    std.debug.print("Created: {s}\n", .{project.inserted_at});
    std.debug.print("Updated: {s}\n", .{project.updated_at});
}

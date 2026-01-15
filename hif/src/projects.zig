const std = @import("std");
const oauth = @import("oauth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const projects_proto = @import("grpc/projects_proto.zig");

pub fn list(allocator: std.mem.Allocator, server: []const u8, organization: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try projects_proto.encodeListProjectsRequest(arena_alloc, organization);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.projects.v1.ProjectService/ListProjects",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    const list_response = try projects_proto.decodeListProjectsResponse(arena_alloc, response.bytes);

    if (list_response.projects.len == 0) {
        std.debug.print("No projects found for organization '{s}'\n", .{organization});
        return;
    }

    std.debug.print("Projects in '{s}':\n", .{organization});
    for (list_response.projects) |project| {
        std.debug.print("  {s}/{s} - {s}\n", .{ project.organization_handle, project.handle, project.name });
        if (project.description.len > 0) {
            const desc = project.description;
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

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try projects_proto.encodeCreateProjectRequest(
        arena_alloc,
        organization,
        handle,
        name,
        description,
    );
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.projects.v1.ProjectService/CreateProject",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    const project = try projects_proto.decodeProjectResponse(arena_alloc, response.bytes);
    std.debug.print("Created project: {s}/{s}\n", .{ project.organization_handle, project.handle });
    std.debug.print("Name: {s}\n", .{project.name});
    if (project.description.len > 0) {
        const desc = project.description;
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

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try projects_proto.encodeGetProjectRequest(arena_alloc, organization, handle);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.projects.v1.ProjectService/GetProject",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    const project = try projects_proto.decodeProjectResponse(arena_alloc, response.bytes);

    std.debug.print("Project: {s}/{s}\n", .{ project.organization_handle, project.handle });
    std.debug.print("Name: {s}\n", .{project.name});
    if (project.description.len > 0) {
        const desc = project.description;
        std.debug.print("Description: {s}\n", .{desc});
    }
    std.debug.print("ID: {s}\n", .{project.id});
    std.debug.print("Created: {s}\n", .{project.inserted_at});
    std.debug.print("Updated: {s}\n", .{project.updated_at});
}

pub fn update(
    allocator: std.mem.Allocator,
    server: []const u8,
    organization: []const u8,
    handle: []const u8,
    name: ?[]const u8,
    description: ?[]const u8,
    new_handle: ?[]const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try projects_proto.encodeUpdateProjectRequest(
        arena_alloc,
        organization,
        handle,
        name,
        description,
        new_handle,
    );
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.projects.v1.ProjectService/UpdateProject",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    const project = try projects_proto.decodeProjectResponse(arena_alloc, response.bytes);
    std.debug.print("Updated project: {s}/{s}\n", .{ project.organization_handle, project.handle });
    std.debug.print("Name: {s}\n", .{project.name});
    if (project.description.len > 0) {
        const desc = project.description;
        std.debug.print("Description: {s}\n", .{desc});
    }
}

pub fn delete(allocator: std.mem.Allocator, server: []const u8, organization: []const u8, handle: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try projects_proto.encodeDeleteProjectRequest(arena_alloc, organization, handle);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.projects.v1.ProjectService/DeleteProject",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    const success = try projects_proto.decodeDeleteProjectResponse(response.bytes);
    if (!success) {
        std.debug.print("Error: Project delete failed.\n", .{});
        return error.RequestFailed;
    }

    std.debug.print("Deleted project: {s}/{s}\n", .{ organization, handle });
}

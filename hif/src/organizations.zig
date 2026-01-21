const std = @import("std");
const auth = @import("auth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const organizations_proto = @import("grpc/organizations_proto.zig");

pub fn list(allocator: std.mem.Allocator, server: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try organizations_proto.encodeListOrganizationsRequest(arena_alloc);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.organizations.v1.OrganizationService/ListOrganizations",
        request,
        access_token,
    );
    defer arena_alloc.free(response.bytes);

    const organizations = try organizations_proto.decodeListOrganizationsResponse(arena_alloc, response.bytes);

    if (organizations.len == 0) {
        std.debug.print("No organizations found.\n", .{});
        return;
    }

    std.debug.print("Your organizations:\n", .{});
    for (organizations) |org| {
        std.debug.print("  {s} - {s}\n", .{ org.handle, org.name });
        if (org.description.len > 0) {
            std.debug.print("    {s}\n", .{org.description});
        }
    }
}

pub fn get(allocator: std.mem.Allocator, server: []const u8, handle: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const access_token = try auth.requireAccessTokenWithMessage(arena_alloc);

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const request = try organizations_proto.encodeGetOrganizationRequest(arena_alloc, handle);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.organizations.v1.OrganizationService/GetOrganization",
        request,
        access_token,
    );
    defer arena_alloc.free(response.bytes);

    const org = try organizations_proto.decodeOrganizationResponse(arena_alloc, response.bytes);

    std.debug.print("Organization: {s}\n", .{org.handle});
    std.debug.print("Name: {s}\n", .{org.name});
    if (org.description.len > 0) {
        std.debug.print("Description: {s}\n", .{org.description});
    }
    std.debug.print("ID: {s}\n", .{org.id});
    std.debug.print("Created: {s}\n", .{org.inserted_at});
    std.debug.print("Updated: {s}\n", .{org.updated_at});
}

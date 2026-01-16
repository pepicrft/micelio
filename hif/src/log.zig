const std = @import("std");
const oauth = @import("oauth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const sessions_proto = @import("grpc/sessions_proto.zig");

/// List landed sessions for a project
pub fn list(
    allocator: std.mem.Allocator,
    organization: []const u8,
    project: []const u8,
    path_filter: ?[]const u8,
    limit: u32,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, creds.?.server);

    // Request only landed sessions, with optional path filter
    const request = try sessions_proto.encodeListSessionsRequest(
        arena_alloc,
        organization,
        project,
        "landed",
        path_filter,
    );
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.sessions.v1.SessionService/ListSessions",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    const sessions = try sessions_proto.decodeListSessionsResponse(arena_alloc, response.bytes);

    if (sessions.len == 0) {
        if (path_filter) |pf| {
            std.debug.print("No landed sessions found for {s}/{s} touching path '{s}'\n", .{ organization, project, pf });
        } else {
            std.debug.print("No landed sessions found for {s}/{s}\n", .{ organization, project });
        }
        return;
    }

    // Apply limit (path filtering is done server-side)
    const display_count = @min(limit, @as(u32, @intCast(sessions.len)));
    const display_sessions = sessions[0..display_count];

    if (path_filter) |pf| {
        std.debug.print("Landed sessions for {s}/{s} touching '{s}':\n\n", .{ organization, project, pf });
    } else {
        std.debug.print("Landed sessions for {s}/{s}:\n\n", .{ organization, project });
    }

    for (display_sessions) |session| {
        printSession(session);
    }

    if (sessions.len > display_count) {
        std.debug.print("... and {} more sessions (use --limit to show more)\n", .{sessions.len - display_count});
    }
}

fn printSession(session: sessions_proto.Session) void {
    // Position display
    if (session.landing_position > 0) {
        std.debug.print("@{d}  ", .{session.landing_position});
    } else {
        std.debug.print("      ", .{});
    }

    // Session ID (truncated)
    const id_display = if (session.session_id.len > 12)
        session.session_id[0..12]
    else
        session.session_id;
    std.debug.print("{s}  ", .{id_display});

    // Landed timestamp
    if (session.landed_at.len > 0) {
        // ISO8601 format, show just date+time
        const display_time = if (session.landed_at.len > 19)
            session.landed_at[0..19]
        else
            session.landed_at;
        std.debug.print("{s}  ", .{display_time});
    } else {
        std.debug.print("                     ", .{});
    }

    // Goal (truncated if too long)
    const max_goal_len: usize = 50;
    if (session.goal.len > max_goal_len) {
        std.debug.print("{s}...\n", .{session.goal[0..max_goal_len]});
    } else {
        std.debug.print("{s}\n", .{session.goal});
    }
}

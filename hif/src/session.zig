const std = @import("std");
const xdg = @import("xdg.zig");
const oauth = @import("oauth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const sessions_proto = @import("grpc/sessions_proto.zig");

const SessionState = struct {
    id: []const u8,
    goal: []const u8,
    project_org: []const u8,
    project_handle: []const u8,
    started_at: []const u8,
    conversation: []Conversation = &[_]Conversation{},
    decisions: []Decision = &[_]Decision{},
    files: []FileChange = &[_]FileChange{},
};

const Conversation = struct {
    role: []const u8, // "human" or "agent"
    message: []const u8,
    timestamp: []const u8,
};

const Decision = struct {
    description: []const u8,
    reasoning: []const u8,
    timestamp: []const u8,
};

const FileChange = struct {
    path: []const u8,
    content: []const u8,
    change_type: []const u8,
};

const session_filename = "session.json";

fn sessionStatePath(allocator: std.mem.Allocator) ![]u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    
    const hif_dir = try std.fs.path.join(allocator, &[_][]const u8{ cwd, ".hif" });
    defer allocator.free(hif_dir);
    
    return std.fs.path.join(allocator, &[_][]const u8{ hif_dir, session_filename });
}

fn ensureHifDirectory() !void {
    const cwd = std.fs.cwd();
    cwd.makeDir(".hif") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

pub fn start(allocator: std.mem.Allocator, organization: []const u8, project: []const u8, goal: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Check if a session already exists
    const path = try sessionStatePath(arena_alloc);
    const existing_data = try xdg.readFileAlloc(arena_alloc, path, 1024 * 1024);
    if (existing_data != null) {
        std.debug.print("Error: A session is already active. Run 'hif session status' to see it or 'hif session abandon' to discard it.\n", .{});
        return error.SessionAlreadyActive;
    }

    const session_id = try generateSessionId(arena_alloc);
    const now = try currentTimestamp(arena_alloc);

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, creds.?.server);
    const request = try sessions_proto.encodeStartSessionRequest(arena_alloc, organization, project, session_id, goal);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint.target,
        endpoint.host,
        "/micelio.sessions.v1.SessionService/StartSession",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    _ = try sessions_proto.decodeSessionResponse(arena_alloc, response.bytes);

    const session = SessionState{
        .id = session_id,
        .goal = goal,
        .project_org = organization,
        .project_handle = project,
        .started_at = now,
    };

    // Write session state
    var payload_buf = std.io.Writer.Allocating.init(arena_alloc);
    defer payload_buf.deinit();
    const formatter = std.json.fmt(session, .{});
    try formatter.format(&payload_buf.writer);
    const payload = try payload_buf.toOwnedSlice();

    try ensureHifDirectory();
    const path_persist = try sessionStatePath(allocator);
    defer allocator.free(path_persist);
    
    const file = try std.fs.cwd().createFile(path_persist, .{});
    defer file.close();
    try file.writeAll(payload);

    std.debug.print("Session started: {s}\n", .{session_id});
    std.debug.print("Goal: {s}\n", .{goal});
    std.debug.print("Project: {s}/{s}\n", .{ organization, project });
    std.debug.print("\nWork on your changes, then run 'hif session land' to push to the forge.\n", .{});
}

pub fn status(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const path = try sessionStatePath(arena_alloc);
    const data = try xdg.readFileAlloc(arena_alloc, path, 1024 * 1024);
    
    if (data == null) {
        std.debug.print("No active session.\n", .{});
        std.debug.print("Start one with: hif session start <organization> <project> <goal>\n", .{});
        return;
    }

    const session = try std.json.parseFromSliceLeaky(SessionState, arena_alloc, data.?, .{ .ignore_unknown_fields = true });

    std.debug.print("Active session: {s}\n", .{session.id});
    std.debug.print("Goal: {s}\n", .{session.goal});
    std.debug.print("Project: {s}/{s}\n", .{ session.project_org, session.project_handle });
    std.debug.print("Started: {s}\n", .{session.started_at});
    
    if (session.conversation.len > 0) {
        std.debug.print("\nConversation ({} messages):\n", .{session.conversation.len});
        for (session.conversation) |msg| {
            std.debug.print("  [{s}] {s}\n", .{ msg.role, msg.message });
        }
    }
    
    if (session.decisions.len > 0) {
        std.debug.print("\nDecisions ({}):\n", .{session.decisions.len});
        for (session.decisions) |decision| {
            std.debug.print("  - {s}\n", .{decision.description});
            std.debug.print("    Reasoning: {s}\n", .{decision.reasoning});
        }
    }

    if (session.files.len > 0) {
        std.debug.print("\nFiles ({}):\n", .{session.files.len});
        for (session.files) |change| {
            std.debug.print("  {s} ({s})\n", .{ change.path, change.change_type });
        }
    }
}

pub fn addNote(allocator: std.mem.Allocator, role: []const u8, message: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const path = try sessionStatePath(arena_alloc);
    const data = try xdg.readFileAlloc(arena_alloc, path, 1024 * 1024);
    
    if (data == null) {
        std.debug.print("Error: No active session. Start one with 'hif session start'.\n", .{});
        return error.NoActiveSession;
    }

    var session = try std.json.parseFromSlice(SessionState, arena_alloc, data.?, .{ .allocate = .alloc_always });
    defer session.deinit();
    
    const now = try currentTimestamp(arena_alloc);
    const new_message = Conversation{
        .role = role,
        .message = message,
        .timestamp = now,
    };

    // Append to conversation
    var new_conversation = try arena_alloc.alloc(Conversation, session.value.conversation.len + 1);
    @memcpy(new_conversation[0..session.value.conversation.len], session.value.conversation);
    new_conversation[session.value.conversation.len] = new_message;
    session.value.conversation = new_conversation;

    // Write back
    var payload_buf = std.io.Writer.Allocating.init(arena_alloc);
    defer payload_buf.deinit();
    const formatter = std.json.fmt(session.value, .{});
    try formatter.format(&payload_buf.writer);
    const payload = try payload_buf.toOwnedSlice();

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(payload);

    std.debug.print("Note added to session.\n", .{});
}

pub fn write(allocator: std.mem.Allocator, path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const session_path = try sessionStatePath(arena_alloc);
    const data = try xdg.readFileAlloc(arena_alloc, session_path, 1024 * 1024);

    if (data == null) {
        std.debug.print("Error: No active session. Start one with 'hif session start'.\n", .{});
        return error.NoActiveSession;
    }

    var session = try std.json.parseFromSlice(SessionState, arena_alloc, data.?, .{ .allocate = .alloc_always });
    defer session.deinit();

    const content = try std.io.getStdIn().readAllAlloc(arena_alloc, 10 * 1024 * 1024);

    try ensureParentDir(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(content);

    const change = FileChange{
        .path = path,
        .content = content,
        .change_type = "modified",
    };

    session.value.files = try upsertChange(arena_alloc, session.value.files, change);

    var payload_buf = std.io.Writer.Allocating.init(arena_alloc);
    defer payload_buf.deinit();
    const formatter = std.json.fmt(session.value, .{});
    try formatter.format(&payload_buf.writer);
    const payload = try payload_buf.toOwnedSlice();

    const file_state = try std.fs.cwd().createFile(session_path, .{ .truncate = true });
    defer file_state.close();
    try file_state.writeAll(payload);

    std.debug.print("Wrote {s} ({} bytes)\n", .{ path, content.len });
}

pub fn land(allocator: std.mem.Allocator, server: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const creds = try oauth.readCredentials(arena_alloc);
    if (creds == null or creds.?.access_token == null) {
        std.debug.print("Error: Not authenticated. Run 'hif auth login' first.\n", .{});
        return error.NotAuthenticated;
    }

    const path = try sessionStatePath(arena_alloc);
    const data = try xdg.readFileAlloc(arena_alloc, path, 1024 * 1024);
    
    if (data == null) {
        std.debug.print("Error: No active session to land.\n", .{});
        return error.NoActiveSession;
    }

    const session = try std.json.parseFromSliceLeaky(SessionState, arena_alloc, data.?, .{ .ignore_unknown_fields = true });

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const changes = try mapChanges(arena_alloc, session.files);
    defer arena_alloc.free(changes);
    const request = try sessions_proto.encodeLandSessionRequest(arena_alloc, session.id, changes);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint.target,
        endpoint.host,
        "/micelio.sessions.v1.SessionService/LandSession",
        request,
        creds.?.access_token.?,
    );
    defer arena_alloc.free(response.bytes);

    const landed = try sessions_proto.decodeSessionResponse(arena_alloc, response.bytes);

    std.debug.print("Session landed successfully!\n", .{});
    std.debug.print("Session ID: {s}\n", .{landed.session_id});
    if (landed.landing_position > 0) {
        std.debug.print("Landing position: {d}\n", .{landed.landing_position});
    }
    
    // Remove local session file
    const path_remove = try sessionStatePath(allocator);
    defer allocator.free(path_remove);
    std.fs.cwd().deleteFile(path_remove) catch {};
}

pub fn abandon(allocator: std.mem.Allocator) !void {
    const path = try sessionStatePath(allocator);
    defer allocator.free(path);

    std.fs.cwd().deleteFile(path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("No active session to abandon.\n", .{});
            return;
        }
        return err;
    };

    std.debug.print("Session abandoned.\n", .{});
}

fn generateSessionId(allocator: std.mem.Allocator) ![]u8 {
    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    
    const encoded = std.base64.url_safe_no_pad.Encoder.encode(try allocator.alloc(u8, std.base64.url_safe_no_pad.Encoder.calcSize(16)), &random_bytes);
    return try allocator.dupe(u8, encoded);
}

fn ensureParentDir(path: []const u8) !void {
    var iter = std.mem.splitBackwardsScalar(u8, path, '/');
    const filename = iter.next() orelse return;
    _ = filename;

    if (iter.next()) |dir| {
        try std.fs.cwd().makePath(dir);
    }
}

fn upsertChange(allocator: std.mem.Allocator, existing: []FileChange, change: FileChange) ![]FileChange {
    var updated = std.ArrayList(FileChange).init(allocator);
    var replaced = false;

    for (existing) |item| {
        if (std.mem.eql(u8, item.path, change.path)) {
            try updated.append(change);
            replaced = true;
        } else {
            try updated.append(item);
        }
    }

    if (!replaced) {
        try updated.append(change);
    }

    return updated.toOwnedSlice();
}

fn mapChanges(allocator: std.mem.Allocator, files: []FileChange) ![]sessions_proto.FileChange {
    var mapped = try allocator.alloc(sessions_proto.FileChange, files.len);
    for (files, 0..) |file, idx| {
        mapped[idx] = .{
            .path = file.path,
            .content = file.content,
            .change_type = file.change_type,
        };
    }
    return mapped;
}

fn currentTimestamp(allocator: std.mem.Allocator) ![]u8 {
    const timestamp = std.time.timestamp();
    const seconds: u64 = @intCast(timestamp);
    
    // Simple ISO-ish format (we'll improve this later)
    return std.fmt.allocPrint(allocator, "{}", .{seconds});
}

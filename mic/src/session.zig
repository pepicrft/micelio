const std = @import("std");
const xdg = @import("xdg.zig");
const auth = @import("auth.zig");
const grpc_client = @import("grpc/client.zig");
const grpc_endpoint = @import("grpc/endpoint.zig");
const sessions_proto = @import("grpc/sessions_proto.zig");
const bloom_mod = @import("core/bloom.zig");
const serialize = @import("core/serialize.zig");

const SessionState = struct {
    id: []const u8,
    goal: []const u8,
    project_org: []const u8,
    project_handle: []const u8,
    started_at: []const u8,
    conversation: []Conversation = &[_]Conversation{},
    decisions: []Decision = &[_]Decision{},
    files: []FileChange = &[_]FileChange{},
    /// Base64-encoded bloom filter for path tracking
    bloom_data: ?[]const u8 = null,
    /// Number of hash functions used in bloom filter
    bloom_hashes: u32 = 7,
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

const session_filename = "session.bin";
const overlay_root = ".mic/overlay";

// ============================================================================
// Binary Session Serialization
// ============================================================================
//
// Session Binary Format:
// [4 bytes: magic "MIC\x01"]
// [1 byte:  type = 0x04 for session]
// [varint:  id length] [bytes: id]
// [varint:  goal length] [bytes: goal]
// [varint:  project_org length] [bytes: project_org]
// [varint:  project_handle length] [bytes: project_handle]
// [8 bytes: started_at timestamp (u64 little-endian)]
// [varint:  conversation count]
// [conversations...]
//   [1 byte: role (0=human, 1=agent)]
//   [varint: message length] [bytes: message]
//   [8 bytes: timestamp (u64)]
// [varint:  decisions count]
// [decisions...]
//   [varint: description length] [bytes: description]
//   [varint: reasoning length] [bytes: reasoning]
//   [8 bytes: timestamp (u64)]
// [varint:  files count]
// [files...]
//   [varint: path length] [bytes: path]
//   [varint: content length] [bytes: content]
//   [1 byte: change_type (0=added, 1=modified, 2=deleted)]
// [4 bytes: bloom_hashes (u32 little-endian)]
// [varint:  bloom_data length] [bytes: bloom_data] (or 0 if null)

fn serializeSession(allocator: std.mem.Allocator, session: SessionState) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    // Magic + type
    try buf.appendSlice(allocator, &serialize.MAGIC);
    try buf.append(allocator, @intFromEnum(serialize.Type.session));

    // String fields
    try writeString(allocator, &buf, session.id);
    try writeString(allocator, &buf, session.goal);
    try writeString(allocator, &buf, session.project_org);
    try writeString(allocator, &buf, session.project_handle);

    // started_at as u64 timestamp
    const started_at_ts = std.fmt.parseInt(u64, session.started_at, 10) catch 0;
    try buf.appendSlice(allocator, &std.mem.toBytes(started_at_ts));

    // Conversations
    try writeVarint(allocator, &buf, session.conversation.len);
    for (session.conversation) |conv| {
        const role_byte: u8 = if (std.mem.eql(u8, conv.role, "human")) 0 else 1;
        try buf.append(allocator, role_byte);
        try writeString(allocator, &buf, conv.message);
        const conv_ts = std.fmt.parseInt(u64, conv.timestamp, 10) catch 0;
        try buf.appendSlice(allocator, &std.mem.toBytes(conv_ts));
    }

    // Decisions
    try writeVarint(allocator, &buf, session.decisions.len);
    for (session.decisions) |dec| {
        try writeString(allocator, &buf, dec.description);
        try writeString(allocator, &buf, dec.reasoning);
        const dec_ts = std.fmt.parseInt(u64, dec.timestamp, 10) catch 0;
        try buf.appendSlice(allocator, &std.mem.toBytes(dec_ts));
    }

    // Files
    try writeVarint(allocator, &buf, session.files.len);
    for (session.files) |file| {
        try writeString(allocator, &buf, file.path);
        try writeString(allocator, &buf, file.content);
        const change_type_byte: u8 = if (std.mem.eql(u8, file.change_type, "added")) 0 else if (std.mem.eql(u8, file.change_type, "modified")) 1 else 2;
        try buf.append(allocator, change_type_byte);
    }

    // Bloom filter
    try buf.appendSlice(allocator, &std.mem.toBytes(session.bloom_hashes));
    if (session.bloom_data) |bloom| {
        try writeString(allocator, &buf, bloom);
    } else {
        try writeVarint(allocator, &buf, 0);
    }

    return buf.toOwnedSlice(allocator);
}

fn deserializeSession(allocator: std.mem.Allocator, data: []const u8) !SessionState {
    var pos: usize = 0;

    // Check magic
    if (data.len < serialize.MAGIC.len + 1) return error.UnexpectedEndOfData;
    if (!std.mem.eql(u8, data[0..serialize.MAGIC.len], &serialize.MAGIC)) return error.InvalidMagic;
    pos += serialize.MAGIC.len;

    // Check type
    if (data[pos] != @intFromEnum(serialize.Type.session)) return error.InvalidType;
    pos += 1;

    // String fields
    const id = try readString(allocator, data, &pos);
    errdefer allocator.free(id);
    const goal = try readString(allocator, data, &pos);
    errdefer allocator.free(goal);
    const project_org = try readString(allocator, data, &pos);
    errdefer allocator.free(project_org);
    const project_handle = try readString(allocator, data, &pos);
    errdefer allocator.free(project_handle);

    // started_at
    if (pos + 8 > data.len) return error.UnexpectedEndOfData;
    const started_at_ts = std.mem.readInt(u64, data[pos..][0..8], .little);
    pos += 8;
    const started_at = try std.fmt.allocPrint(allocator, "{}", .{started_at_ts});
    errdefer allocator.free(started_at);

    // Conversations
    const conv_count = try readVarint(data, &pos);
    var conversations = try allocator.alloc(Conversation, conv_count);
    errdefer allocator.free(conversations);
    for (0..conv_count) |i| {
        if (pos >= data.len) return error.UnexpectedEndOfData;
        const role_byte = data[pos];
        pos += 1;
        const role = if (role_byte == 0) "human" else "agent";
        const message = try readString(allocator, data, &pos);
        if (pos + 8 > data.len) return error.UnexpectedEndOfData;
        const conv_ts = std.mem.readInt(u64, data[pos..][0..8], .little);
        pos += 8;
        const timestamp = try std.fmt.allocPrint(allocator, "{}", .{conv_ts});
        conversations[i] = .{ .role = role, .message = message, .timestamp = timestamp };
    }

    // Decisions
    const dec_count = try readVarint(data, &pos);
    var decisions = try allocator.alloc(Decision, dec_count);
    errdefer allocator.free(decisions);
    for (0..dec_count) |i| {
        const description = try readString(allocator, data, &pos);
        const reasoning = try readString(allocator, data, &pos);
        if (pos + 8 > data.len) return error.UnexpectedEndOfData;
        const dec_ts = std.mem.readInt(u64, data[pos..][0..8], .little);
        pos += 8;
        const timestamp = try std.fmt.allocPrint(allocator, "{}", .{dec_ts});
        decisions[i] = .{ .description = description, .reasoning = reasoning, .timestamp = timestamp };
    }

    // Files
    const files_count = try readVarint(data, &pos);
    var files = try allocator.alloc(FileChange, files_count);
    errdefer allocator.free(files);
    for (0..files_count) |i| {
        const path = try readString(allocator, data, &pos);
        const content = try readString(allocator, data, &pos);
        if (pos >= data.len) return error.UnexpectedEndOfData;
        const change_type_byte = data[pos];
        pos += 1;
        const change_type = if (change_type_byte == 0) "added" else if (change_type_byte == 1) "modified" else "deleted";
        files[i] = .{ .path = path, .content = content, .change_type = change_type };
    }

    // Bloom filter
    if (pos + 4 > data.len) return error.UnexpectedEndOfData;
    const bloom_hashes = std.mem.readInt(u32, data[pos..][0..4], .little);
    pos += 4;

    const bloom_len = try readVarint(data, &pos);
    const bloom_data: ?[]const u8 = if (bloom_len > 0) try readStringWithLen(allocator, data, &pos, bloom_len) else null;

    return SessionState{
        .id = id,
        .goal = goal,
        .project_org = project_org,
        .project_handle = project_handle,
        .started_at = started_at,
        .conversation = conversations,
        .decisions = decisions,
        .files = files,
        .bloom_data = bloom_data,
        .bloom_hashes = bloom_hashes,
    };
}

fn writeVarint(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), value: usize) !void {
    var v = value;
    while (v >= 0x80) {
        try buf.append(allocator, @as(u8, @intCast(v & 0x7f)) | 0x80);
        v >>= 7;
    }
    try buf.append(allocator, @intCast(v));
}

fn readVarint(data: []const u8, pos: *usize) !usize {
    var value: usize = 0;
    var shift: u6 = 0;
    while (pos.* < data.len) {
        const byte = data[pos.*];
        pos.* += 1;
        value |= @as(usize, byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) return value;
        shift += 7;
        if (shift >= 64) return error.InvalidData;
    }
    return error.UnexpectedEndOfData;
}

fn writeString(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try writeVarint(allocator, buf, s.len);
    try buf.appendSlice(allocator, s);
}

fn readString(allocator: std.mem.Allocator, data: []const u8, pos: *usize) ![]u8 {
    const len = try readVarint(data, pos);
    return readStringWithLen(allocator, data, pos, len);
}

fn readStringWithLen(allocator: std.mem.Allocator, data: []const u8, pos: *usize, len: usize) ![]u8 {
    if (pos.* + len > data.len) return error.UnexpectedEndOfData;
    const result = try allocator.dupe(u8, data[pos.*..][0..len]);
    pos.* += len;
    return result;
}

fn sessionStatePath(allocator: std.mem.Allocator) ![]u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const mic_dir = try std.fs.path.join(allocator, &[_][]const u8{ cwd, ".mic" });
    defer allocator.free(mic_dir);

    return std.fs.path.join(allocator, &[_][]const u8{ mic_dir, session_filename });
}

fn ensureMicDirectory() !void {
    const cwd = std.fs.cwd();
    cwd.makeDir(".mic") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

fn ensureOverlayDirectory() !void {
    try ensureMicDirectory();
    std.fs.cwd().makePath(overlay_root) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

fn clearOverlayDirectory(allocator: std.mem.Allocator) !void {
    const path = try overlayRootPath(allocator);
    defer allocator.free(path);
    std.fs.cwd().deleteTree(path) catch {};
}

fn overlayRootPath(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.dupe(u8, overlay_root);
}

fn overlayFilePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!isSafePath(path)) return error.InvalidPath;
    return std.fs.path.join(allocator, &[_][]const u8{ overlay_root, path });
}

fn writeOverlayFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    try ensureOverlayDirectory();
    const overlay_path = try overlayFilePath(allocator, path);
    defer allocator.free(overlay_path);

    try ensureParentDir(overlay_path);
    const file = try std.fs.cwd().createFile(overlay_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(content);
}

fn readOverlayFile(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) !?[]u8 {
    const overlay_path = try overlayFilePath(allocator, path);
    defer allocator.free(overlay_path);

    const file = std.fs.cwd().openFile(overlay_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();
    return try file.readToEndAlloc(allocator, max_bytes);
}

pub fn start(allocator: std.mem.Allocator, organization: []const u8, project: []const u8, goal: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Check if a session already exists
    const path = try sessionStatePath(arena_alloc);
    const existing_data = try xdg.readFileAlloc(arena_alloc, path, 1024 * 1024);
    if (existing_data != null) {
        std.debug.print("Error: A session is already active. Run 'mic session status' to see it or 'mic session abandon' to discard it.\n", .{});
        return error.SessionAlreadyActive;
    }

    const session_id = try generateSessionId(arena_alloc);
    const now = try currentTimestamp(arena_alloc);

    const tokens = try auth.requireTokensWithMessage(arena_alloc);
    const endpoint = try grpc_endpoint.parseServer(arena_alloc, tokens.server);
    const request = try sessions_proto.encodeStartSessionRequest(arena_alloc, organization, project, session_id, goal);
    defer arena_alloc.free(request);

    const response = try grpc_client.unaryCall(
        arena_alloc,
        endpoint,
        "/micelio.sessions.v1.SessionService/StartSession",
        request,
        tokens.access_token,
    );
    defer arena_alloc.free(response.bytes);

    _ = try sessions_proto.decodeSessionResponse(arena_alloc, response.bytes);

    try clearOverlayDirectory(arena_alloc);
    try ensureOverlayDirectory();

    // Create bloom filter for path tracking (sized for ~1000 paths, 1% FP rate)
    var bloom = try bloom_mod.Bloom.init(arena_alloc, 1000, 0.01);
    defer bloom.deinit();
    const bloom_serialized = try bloom.serialize(arena_alloc);
    defer arena_alloc.free(bloom_serialized);
    const bloom_b64 = try encodeBase64(arena_alloc, bloom_serialized);

    const session = SessionState{
        .id = session_id,
        .goal = goal,
        .project_org = organization,
        .project_handle = project,
        .started_at = now,
        .bloom_data = bloom_b64,
        .bloom_hashes = bloom.num_hashes,
    };

    // Write session state (binary format)
    const payload = try serializeSession(arena_alloc, session);
    defer arena_alloc.free(payload);

    try ensureMicDirectory();
    const path_persist = try sessionStatePath(allocator);
    defer allocator.free(path_persist);

    const file = try std.fs.cwd().createFile(path_persist, .{});
    defer file.close();
    try file.writeAll(payload);

    std.debug.print("Session started: {s}\n", .{session_id});
    std.debug.print("Goal: {s}\n", .{goal});
    std.debug.print("Project: {s}/{s}\n", .{ organization, project });
    std.debug.print("\nWork on your changes, then run 'mic session land' to push to the forge.\n", .{});
}

pub fn status(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const path = try sessionStatePath(arena_alloc);
    const data = try xdg.readFileAlloc(arena_alloc, path, 1024 * 1024);

    if (data == null) {
        std.debug.print("No active session.\n", .{});
        std.debug.print("Start one with: mic session start <organization> <project> <goal>\n", .{});
        return;
    }

    const session = try deserializeSession(arena_alloc, data.?);

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
        std.debug.print("Error: No active session. Start one with 'mic session start'.\n", .{});
        return error.NoActiveSession;
    }

    var session = try deserializeSession(arena_alloc, data.?);

    const now = try currentTimestamp(arena_alloc);
    const new_message = Conversation{
        .role = role,
        .message = message,
        .timestamp = now,
    };

    // Append to conversation
    var new_conversation = try arena_alloc.alloc(Conversation, session.conversation.len + 1);
    @memcpy(new_conversation[0..session.conversation.len], session.conversation);
    new_conversation[session.conversation.len] = new_message;
    session.conversation = new_conversation;

    // Write back (binary format)
    const payload = try serializeSession(arena_alloc, session);
    defer arena_alloc.free(payload);

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(payload);

    std.debug.print("Note added to session.\n", .{});
}

pub fn write(allocator: std.mem.Allocator, path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    if (!isSafePath(path)) {
        std.debug.print("Error: Invalid path '{s}'.\n", .{path});
        return error.InvalidPath;
    }

    const session_path = try sessionStatePath(arena_alloc);
    const data = try xdg.readFileAlloc(arena_alloc, session_path, 1024 * 1024);

    if (data == null) {
        std.debug.print("Error: No active session. Start one with 'mic session start'.\n", .{});
        return error.NoActiveSession;
    }

    var session = try deserializeSession(arena_alloc, data.?);

    const content = try std.fs.File.stdin().readToEndAlloc(arena_alloc, 10 * 1024 * 1024);

    try ensureParentDir(path);
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(content);

    try writeOverlayFile(arena_alloc, path, content);

    const change = FileChange{
        .path = path,
        .content = content,
        .change_type = "modified",
    };

    session.files = try upsertChange(arena_alloc, session.files, change);

    // Update bloom filter with the path
    if (session.bloom_data) |bloom_b64| {
        const bloom_bytes = try decodeBase64(arena_alloc, bloom_b64);
        defer arena_alloc.free(bloom_bytes);
        var bloom = try bloom_mod.Bloom.deserialize(arena_alloc, bloom_bytes);
        defer bloom.deinit();

        // Add the path to the bloom filter
        bloom.add(path);

        // Re-serialize the updated bloom filter
        const updated_bloom = try bloom.serialize(arena_alloc);
        defer arena_alloc.free(updated_bloom);
        session.bloom_data = try encodeBase64(arena_alloc, updated_bloom);
    }

    // Write back (binary format)
    const payload = try serializeSession(arena_alloc, session);
    defer arena_alloc.free(payload);

    const file_state = try std.fs.cwd().createFile(session_path, .{ .truncate = true });
    defer file_state.close();
    try file_state.writeAll(payload);

    std.debug.print("Wrote {s} ({} bytes)\n", .{ path, content.len });
}

pub const LandResult = union(enum) {
    success: struct {
        session_id: []const u8,
        landing_position: u64,
    },
    conflict: struct {
        paths: []const []const u8,
    },
    err: []const u8,
};

pub fn land(allocator: std.mem.Allocator, server: []const u8) !void {
    const result = try landSession(allocator, server);

    switch (result) {
        .success => |data| {
            defer allocator.free(data.session_id);

            std.debug.print("Session landed successfully!\n", .{});
            std.debug.print("Session ID: {s}\n", .{data.session_id});
            if (data.landing_position > 0) {
                std.debug.print("Landing position: {d}\n", .{data.landing_position});
            }

            // Remove local session file
            const path_remove = try sessionStatePath(allocator);
            defer allocator.free(path_remove);
            std.fs.cwd().deleteFile(path_remove) catch {};

            try clearOverlayDirectory(allocator);
        },
        .conflict => |data| {
            defer {
                for (data.paths) |p| allocator.free(p);
                allocator.free(data.paths);
            }

            std.debug.print("Error: Conflicts detected with upstream changes.\n", .{});
            std.debug.print("\nConflicting files:\n", .{});
            for (data.paths) |path| {
                std.debug.print("  - {s}\n", .{path});
            }
            std.debug.print("\nTo resolve:\n", .{});
            std.debug.print("  1. Run 'mic sync' to fetch the latest upstream state\n", .{});
            std.debug.print("  2. Review and merge your changes with the upstream versions\n", .{});
            std.debug.print("  3. Run 'mic session land' again\n", .{});
            return error.ConflictsDetected;
        },
        .err => |message| {
            defer allocator.free(message);

            std.debug.print("Error: {s}\n", .{message});
            return error.LandingFailed;
        },
    }
}

pub fn landSession(allocator: std.mem.Allocator, _: []const u8) !LandResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const tokens = auth.requireTokens(arena_alloc) catch |err| {
        return switch (err) {
            error.NotAuthenticated => .{ .err = "Not authenticated. Run 'mic auth login' first." },
            error.TokenExpired => .{ .err = "Access token expired. Run 'mic auth login' again." },
            error.InvalidTokens => .{ .err = "Stored token data is invalid. Run 'mic auth login' again." },
            else => return err,
        };
    };

    // Use the server from stored tokens, not the passed parameter
    const server = tokens.server;

    const path = try sessionStatePath(arena_alloc);
    const data = try xdg.readFileAlloc(arena_alloc, path, 1024 * 1024);

    if (data == null) {
        return .{ .err = "No active session to land." };
    }

    const session = try deserializeSession(arena_alloc, data.?);

    const endpoint = try grpc_endpoint.parseServer(arena_alloc, server);
    const changes = try mapChangesFromOverlay(arena_alloc, session.files);
    defer arena_alloc.free(changes);
    const batch_size = epochBatchSize(arena_alloc);

    if (batch_size > 0 and changes.len > batch_size) {
        var epoch: u32 = 0;
        var offset: usize = 0;

        while (offset < changes.len) {
            const end = @min(offset + batch_size, changes.len);
            const finalize = end == changes.len;
            epoch += 1;

            const request = try sessions_proto.encodeLandSessionRequest(
                arena_alloc,
                session.id,
                changes[offset..end],
                .{ .epoch = epoch, .finalize = finalize },
            );
            defer arena_alloc.free(request);

            const result = try grpc_client.unaryCallResult(
                arena_alloc,
                endpoint,
                "/micelio.sessions.v1.SessionService/LandSession",
                request,
                tokens.access_token,
            );

            switch (result) {
                .ok => |response| {
                    defer arena_alloc.free(response.bytes);
                    if (finalize) {
                        const landed =
                            try sessions_proto.decodeSessionResponse(arena_alloc, response.bytes);
                        return .{
                            .success = .{
                                .session_id = try allocator.dupe(u8, landed.session_id),
                                .landing_position = landed.landing_position,
                            },
                        };
                    }
                },
                .err => |message| {
                    defer arena_alloc.free(message);

                    // Check if this is a conflict error
                    if (std.mem.startsWith(u8, message, "Conflicts detected: ")) {
                        const paths_str = message["Conflicts detected: ".len..];
                        var conflict_paths: std.ArrayList([]const u8) = .empty;

                        var iter = std.mem.splitSequence(u8, paths_str, ", ");
                        while (iter.next()) |p| {
                            try conflict_paths.append(allocator, try allocator.dupe(u8, p));
                        }

                        return .{ .conflict = .{ .paths = try conflict_paths.toOwnedSlice(allocator) } };
                    }

                    return .{ .err = try allocator.dupe(u8, message) };
                },
            }

            offset = end;
        }

        return .{ .err = "Landing failed." };
    } else {
        const request = try sessions_proto.encodeLandSessionRequest(arena_alloc, session.id, changes, .{});
        defer arena_alloc.free(request);

        const result = try grpc_client.unaryCallResult(
            arena_alloc,
            endpoint,
            "/micelio.sessions.v1.SessionService/LandSession",
            request,
            tokens.access_token,
        );

        switch (result) {
            .ok => |response| {
                defer arena_alloc.free(response.bytes);
                const landed = try sessions_proto.decodeSessionResponse(arena_alloc, response.bytes);
                return .{
                    .success = .{
                        .session_id = try allocator.dupe(u8, landed.session_id),
                        .landing_position = landed.landing_position,
                    },
                };
            },
            .err => |message| {
                defer arena_alloc.free(message);

                // Check if this is a conflict error
                if (std.mem.startsWith(u8, message, "Conflicts detected: ")) {
                    const paths_str = message["Conflicts detected: ".len..];
                    var conflict_paths: std.ArrayList([]const u8) = .empty;

                    var iter = std.mem.splitSequence(u8, paths_str, ", ");
                    while (iter.next()) |p| {
                        try conflict_paths.append(allocator, try allocator.dupe(u8, p));
                    }

                    return .{ .conflict = .{ .paths = try conflict_paths.toOwnedSlice(allocator) } };
                }

                return .{ .err = try allocator.dupe(u8, message) };
            },
        }
    }
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

    try clearOverlayDirectory(allocator);
    std.debug.print("Session abandoned.\n", .{});
}

fn generateSessionId(allocator: std.mem.Allocator) ![]u8 {
    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);

    const encoded = std.base64.url_safe_no_pad.Encoder.encode(try allocator.alloc(u8, std.base64.url_safe_no_pad.Encoder.calcSize(16)), &random_bytes);
    return try allocator.dupe(u8, encoded);
}

fn ensureParentDir(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    try std.fs.cwd().makePath(parent);
}

fn isSafePath(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.fs.path.isAbsolute(path)) return false;

    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return false;
    }

    return true;
}

fn epochBatchSize(allocator: std.mem.Allocator) usize {
    const value = std.process.getEnvVarOwned(allocator, "MIC_EPOCH_BATCH_SIZE") catch return 0;
    defer allocator.free(value);

    const parsed = std.fmt.parseInt(usize, value, 10) catch return 0;
    if (parsed == 0) return 0;
    return parsed;
}

fn upsertChange(allocator: std.mem.Allocator, existing: []FileChange, change: FileChange) ![]FileChange {
    var updated: std.ArrayList(FileChange) = .empty;
    var replaced = false;

    for (existing) |item| {
        if (std.mem.eql(u8, item.path, change.path)) {
            try updated.append(allocator, change);
            replaced = true;
        } else {
            try updated.append(allocator, item);
        }
    }

    if (!replaced) {
        try updated.append(allocator, change);
    }

    return updated.toOwnedSlice(allocator);
}

fn mapChangesFromOverlay(allocator: std.mem.Allocator, files: []FileChange) ![]sessions_proto.FileChange {
    var mapped = try allocator.alloc(sessions_proto.FileChange, files.len);
    for (files, 0..) |file, idx| {
        const content = if (std.mem.eql(u8, file.change_type, "deleted")) blk: {
            break :blk &[_]u8{};
        } else blk: {
            if (try readOverlayFile(allocator, file.path, 50 * 1024 * 1024)) |overlay_content| {
                break :blk overlay_content;
            }
            break :blk file.content;
        };

        mapped[idx] = .{
            .path = file.path,
            .content = content,
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

fn encodeBase64(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const size = std.base64.standard.Encoder.calcSize(data.len);
    const buf = try allocator.alloc(u8, size);
    _ = std.base64.standard.Encoder.encode(buf, data);
    return buf;
}

fn decodeBase64(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const size = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return error.InvalidBase64;
    const buf = try allocator.alloc(u8, size);
    std.base64.standard.Decoder.decode(buf, encoded) catch return error.InvalidBase64;
    return buf;
}

/// Load the bloom filter from the current session, if available.
pub fn loadSessionBloom(allocator: std.mem.Allocator) !?bloom_mod.Bloom {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const path = try sessionStatePath(arena_alloc);
    const data = try xdg.readFileAlloc(arena_alloc, path, 1024 * 1024);

    if (data == null) {
        return null;
    }

    const session = try deserializeSession(arena_alloc, data.?);

    if (session.bloom_data) |bloom_b64| {
        const bloom_bytes = try decodeBase64(allocator, bloom_b64);
        defer allocator.free(bloom_bytes);
        return try bloom_mod.Bloom.deserialize(allocator, bloom_bytes);
    }

    return null;
}

/// Get a list of all paths touched in the current session.
pub fn getSessionPaths(allocator: std.mem.Allocator) ![]const []const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const path = try sessionStatePath(arena_alloc);
    const data = try xdg.readFileAlloc(arena_alloc, path, 1024 * 1024);

    if (data == null) {
        return &[_][]const u8{};
    }

    const session = try deserializeSession(arena_alloc, data.?);

    var paths: std.ArrayList([]const u8) = .empty;
    for (session.files) |file| {
        try paths.append(allocator, try allocator.dupe(u8, file.path));
    }

    return try paths.toOwnedSlice(allocator);
}

/// Interactive conflict resolution (not yet implemented)
pub fn resolve(allocator: std.mem.Allocator, server: []const u8, strategy: []const u8) !void {
    _ = allocator;
    _ = server;
    _ = strategy;
    std.debug.print("Conflict resolution is not yet implemented.\n", .{});
    std.debug.print("Available strategies: ours, theirs, interactive\n", .{});
}

test "session overlay writes and reads content" {
    const allocator = std.testing.allocator;
    const original_cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(original_cwd);

    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.setAsCwd();
    defer {
        var restore_dir = std.fs.openDirAbsolute(original_cwd, .{}) catch unreachable;
        defer restore_dir.close();
        restore_dir.setAsCwd() catch unreachable;
    }

    try ensureOverlayDirectory();
    try writeOverlayFile(allocator, "src/main.zig", "hello");

    const content = try readOverlayFile(allocator, "src/main.zig", 1024);
    defer if (content) |data| allocator.free(data);
    try std.testing.expect(content != null);
    try std.testing.expectEqualStrings("hello", content.?);
}

test "session overlay falls back to session content when missing" {
    const allocator = std.testing.allocator;
    const original_cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(original_cwd);

    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.setAsCwd();
    defer {
        var restore_dir = std.fs.openDirAbsolute(original_cwd, .{}) catch unreachable;
        defer restore_dir.close();
        restore_dir.setAsCwd() catch unreachable;
    }

    var files = [_]FileChange{
        .{ .path = "README.md", .content = "inline", .change_type = "modified" },
    };

    const mapped = try mapChangesFromOverlay(allocator, files[0..]);
    defer allocator.free(mapped);
    try std.testing.expectEqualStrings("inline", mapped[0].content);
}

test "session overlay prefers overlay content for landing" {
    const allocator = std.testing.allocator;
    const original_cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(original_cwd);

    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.setAsCwd();
    defer {
        var restore_dir = std.fs.openDirAbsolute(original_cwd, .{}) catch unreachable;
        defer restore_dir.close();
        restore_dir.setAsCwd() catch unreachable;
    }

    try ensureOverlayDirectory();
    try writeOverlayFile(allocator, "notes.txt", "overlay");

    var files = [_]FileChange{
        .{ .path = "notes.txt", .content = "inline", .change_type = "modified" },
    };

    const mapped = try mapChangesFromOverlay(allocator, files[0..]);
    defer {
        allocator.free(mapped[0].content);
        allocator.free(mapped);
    }

    try std.testing.expectEqualStrings("overlay", mapped[0].content);
}

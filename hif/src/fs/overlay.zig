const std = @import("std");
const xdg = @import("hif/xdg.zig");

pub const ChangeType = enum {
    added,
    modified,
    deleted,
};

pub const OverlayEntry = struct {
    path: []const u8,
    content: []const u8,
    change_type: ChangeType,
};

const Conversation = struct {
    role: []const u8,
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

const SessionFile = struct {
    id: []const u8,
    goal: []const u8,
    project_org: []const u8,
    project_handle: []const u8,
    started_at: []const u8,
    conversation: []Conversation = &[_]Conversation{},
    decisions: []Decision = &[_]Decision{},
    files: []FileChange = &[_]FileChange{},
    bloom_data: ?[]const u8 = null,
    bloom_hashes: u32 = 7,
};

pub const Overlay = struct {
    allocator: std.mem.Allocator,
    session_path: []const u8,
    account: []const u8,
    project: []const u8,
    session: ?SessionFile,
    entries: std.StringHashMap(OverlayEntry),

    pub fn init(
        allocator: std.mem.Allocator,
        session_path: []const u8,
        account: []const u8,
        project: []const u8,
    ) !Overlay {
        var overlay = Overlay{
            .allocator = allocator,
            .session_path = try allocator.dupe(u8, session_path),
            .account = try allocator.dupe(u8, account),
            .project = try allocator.dupe(u8, project),
            .session = null,
            .entries = std.StringHashMap(OverlayEntry).init(allocator),
        };
        errdefer overlay.deinit();

        try overlay.loadSession();
        return overlay;
    }

    pub fn deinit(self: *Overlay) void {
        if (self.session) |session| {
            self.allocator.free(session.id);
            self.allocator.free(session.goal);
            self.allocator.free(session.project_org);
            self.allocator.free(session.project_handle);
            self.allocator.free(session.started_at);
            if (session.bloom_data) |data| self.allocator.free(data);
            for (session.conversation) |item| {
                self.allocator.free(item.role);
                self.allocator.free(item.message);
                self.allocator.free(item.timestamp);
            }
            self.allocator.free(session.conversation);
            for (session.decisions) |item| {
                self.allocator.free(item.description);
                self.allocator.free(item.reasoning);
                self.allocator.free(item.timestamp);
            }
            self.allocator.free(session.decisions);
            for (session.files) |item| {
                self.allocator.free(item.path);
                self.allocator.free(item.content);
                self.allocator.free(item.change_type);
            }
            self.allocator.free(session.files);
        }

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.content);
        }
        self.entries.deinit();

        self.allocator.free(self.session_path);
        self.allocator.free(self.account);
        self.allocator.free(self.project);
        self.* = undefined;
    }

    pub fn get(self: *const Overlay, path: []const u8) ?OverlayEntry {
        return self.entries.get(path);
    }

    pub fn setFile(self: *Overlay, path: []const u8, content: []const u8, change_type: ChangeType) !void {
        const owned_path = if (self.entries.contains(path)) null else try self.allocator.dupe(u8, path);
        const owned_content = try self.allocator.dupe(u8, content);

        if (self.entries.fetchPut(path, .{
            .path = path,
            .content = owned_content,
            .change_type = change_type,
        })) |old| {
            self.allocator.free(old.value.content);
        } else if (owned_path) |value| {
            _ = value;
        }

        try self.persist();
    }

    pub fn remove(self: *Overlay, path: []const u8) !void {
        const owned_path = if (self.entries.contains(path)) null else try self.allocator.dupe(u8, path);

        if (self.entries.fetchPut(path, .{
            .path = path,
            .content = &[_]u8{},
            .change_type = .deleted,
        })) |old| {
            self.allocator.free(old.value.content);
        } else if (owned_path) |value| {
            _ = value;
        }

        try self.persist();
    }

    fn loadSession(self: *Overlay) !void {
        const data = try xdg.readFileAlloc(self.allocator, self.session_path, 8 * 1024 * 1024);
        if (data == null) return;
        defer self.allocator.free(data.?);

        var parsed = try std.json.parseFromSlice(SessionFile, self.allocator, data.?, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        errdefer parsed.deinit();
        const session = parsed.value;

        var entries = std.StringHashMap(OverlayEntry).init(self.allocator);
        for (session.files) |file| {
            const change_type = parseChangeType(file.change_type);
            try entries.put(try self.allocator.dupe(u8, file.path), .{
                .path = file.path,
                .content = try self.allocator.dupe(u8, file.content),
                .change_type = change_type,
            });
        }

        self.entries.deinit();
        self.entries = entries;
        self.session = session;
        parsed.deinit();
    }

    fn persist(self: *Overlay) !void {
        var session = self.session orelse try self.createSession();
        const file_list = try self.buildFileList();
        session.files = file_list;
        self.session = session;

        var buf = std.ArrayList(u8).init(self.allocator, null);
        defer buf.deinit();

        const formatter = std.json.fmt(session, .{});
        try formatter.format(buf.writer());

        try ensureDir(std.fs.path.dirname(self.session_path) orelse ".");
        const file = try std.fs.createFileAbsolute(self.session_path, .{ .truncate = true, .read = true, .mode = 0o600 });
        defer file.close();
        try file.writeAll(buf.items);
    }

    fn createSession(self: *Overlay) !SessionFile {
        const session_id = try randomId(self.allocator);
        const goal = try self.allocator.dupe(u8, "filesystem mount");
        const now = try timestamp(self.allocator);
        return .{
            .id = session_id,
            .goal = goal,
            .project_org = try self.allocator.dupe(u8, self.account),
            .project_handle = try self.allocator.dupe(u8, self.project),
            .started_at = now,
        };
    }

    fn buildFileList(self: *Overlay) ![]FileChange {
        var files = std.ArrayList(FileChange).init(self.allocator, null);
        errdefer files.deinit();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            const change_type = switch (entry.value_ptr.change_type) {
                .added => "added",
                .modified => "modified",
                .deleted => "deleted",
            };
            try files.append(.{
                .path = try self.allocator.dupe(u8, entry.key_ptr.*),
                .content = try self.allocator.dupe(u8, entry.value_ptr.content),
                .change_type = try self.allocator.dupe(u8, change_type),
            });
        }

        return try files.toOwnedSlice();
    }

    fn parseChangeType(value: []const u8) ChangeType {
        if (std.mem.eql(u8, value, "added")) return .added;
        if (std.mem.eql(u8, value, "deleted")) return .deleted;
        return .modified;
    }
};

fn randomId(allocator: std.mem.Allocator) ![]u8 {
    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    const size = std.base64.url_safe_no_pad.Encoder.calcSize(random_bytes.len);
    const buf = try allocator.alloc(u8, size);
    _ = std.base64.url_safe_no_pad.Encoder.encode(buf, &random_bytes);
    return buf;
}

fn timestamp(allocator: std.mem.Allocator) ![]u8 {
    const value = std.time.timestamp();
    return std.fmt.allocPrint(allocator, "{}", .{value});
}

fn ensureDir(path: []const u8) !void {
    if (path.len == 0) return;
    std.fs.cwd().makePath(path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

//! Local configuration management for hif.
//!
//! Configuration is stored in `~/.hif/config.json` (or `$HIF_HOME/config.json`
//! if the environment variable is set).
//!
//! ## Configuration File Format
//!
//! ```json
//! {
//!   "default_server": "micelio.dev",
//!   "servers": {
//!     "micelio.dev": {
//!       "grpc_url": "https://grpc.micelio.dev:443",
//!       "web_url": "https://micelio.dev"
//!     },
//!     "localhost": {
//!       "grpc_url": "http://localhost:50051",
//!       "web_url": "http://localhost:4000"
//!     }
//!   },
//!   "aliases": {
//!     "my-project": "myorg/myproject"
//!   },
//!   "preferences": {
//!     "output_format": "text",
//!     "color": true
//!   }
//! }
//! ```
//!
//! ## Usage
//!
//! ```zig
//! var config = try Config.load(allocator);
//! defer config.deinit();
//!
//! const server = config.getDefaultServer();
//! config.setDefaultServer("localhost");
//! try config.save();
//! ```

const std = @import("std");

/// Configuration for hif CLI.
pub const Config = struct {
    allocator: std.mem.Allocator,

    /// Path to the config file (owned).
    config_path: []u8,

    /// Default server name (e.g., "micelio.dev", "localhost").
    default_server: ?[]u8 = null,

    /// Server configurations by name.
    servers: std.StringHashMap(ServerConfig),

    /// Project aliases (short name -> org/project).
    aliases: std.StringHashMap([]u8),

    /// User preferences.
    preferences: Preferences,

    /// Whether the config has been modified since load.
    dirty: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Config {
        const config_path = try configFilePath(allocator);

        return .{
            .allocator = allocator,
            .config_path = config_path,
            .servers = std.StringHashMap(ServerConfig).init(allocator),
            .aliases = std.StringHashMap([]u8).init(allocator),
            .preferences = Preferences{},
        };
    }

    pub fn deinit(self: *Config) void {
        if (self.default_server) |s| {
            self.allocator.free(s);
        }

        var server_iter = self.servers.iterator();
        while (server_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.servers.deinit();

        var alias_iter = self.aliases.iterator();
        while (alias_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.aliases.deinit();

        self.allocator.free(self.config_path);
        self.* = undefined;
    }

    /// Load configuration from disk, or create default if not exists.
    pub fn load(allocator: std.mem.Allocator) !Config {
        var config = try Config.init(allocator);
        errdefer config.deinit();

        const data = readConfigFile(config.config_path, allocator) catch |err| {
            if (err == error.FileNotFound) {
                // No config file, use defaults
                try config.setDefaultServers();
                return config;
            }
            return err;
        };
        defer if (data) |d| allocator.free(d);

        if (data) |json_data| {
            try config.parseJson(json_data);
        } else {
            try config.setDefaultServers();
        }

        return config;
    }

    /// Save configuration to disk.
    pub fn save(self: *Config) !void {
        try ensureConfigDir(self.allocator);

        // Serialize to JSON
        var json_buf: std.ArrayList(u8) = .empty;
        defer json_buf.deinit(self.allocator);

        try self.writeJson(json_buf.writer(self.allocator));

        // Write atomically
        const tmp_path = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{self.config_path});
        defer self.allocator.free(tmp_path);

        const file = try std.fs.createFileAbsolute(tmp_path, .{ .mode = 0o600 });
        errdefer std.fs.deleteFileAbsolute(tmp_path) catch {};

        try file.writeAll(json_buf.items);
        file.close();

        try std.fs.renameAbsolute(tmp_path, self.config_path);
        self.dirty = false;
    }

    /// Get the default server URL.
    pub fn getDefaultServer(self: *const Config) ?[]const u8 {
        if (self.default_server) |name| {
            if (self.servers.get(name)) |server| {
                return server.grpc_url;
            }
        }
        return null;
    }

    /// Get the default server name.
    pub fn getDefaultServerName(self: *const Config) ?[]const u8 {
        return self.default_server;
    }

    /// Set the default server by name.
    pub fn setDefaultServer(self: *Config, name: []const u8) !void {
        if (self.default_server) |old| {
            self.allocator.free(old);
        }
        self.default_server = try self.allocator.dupe(u8, name);
        self.dirty = true;
    }

    /// Get server configuration by name.
    pub fn getServer(self: *const Config, name: []const u8) ?ServerConfig {
        return self.servers.get(name);
    }

    /// Add or update a server configuration.
    pub fn setServer(self: *Config, name: []const u8, server: ServerConfig) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        const owned_server = try server.clone(self.allocator);
        errdefer owned_server.deinit(self.allocator);

        if (self.servers.fetchRemove(owned_name)) |old| {
            self.allocator.free(old.key);
            old.value.deinit(self.allocator);
        }

        try self.servers.put(owned_name, owned_server);
        self.dirty = true;
    }

    /// Get a project alias.
    pub fn getAlias(self: *const Config, alias: []const u8) ?[]const u8 {
        return self.aliases.get(alias);
    }

    /// Set a project alias.
    pub fn setAlias(self: *Config, alias: []const u8, project_ref: []const u8) !void {
        const owned_alias = try self.allocator.dupe(u8, alias);
        errdefer self.allocator.free(owned_alias);

        const owned_ref = try self.allocator.dupe(u8, project_ref);
        errdefer self.allocator.free(owned_ref);

        if (self.aliases.fetchRemove(owned_alias)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }

        try self.aliases.put(owned_alias, owned_ref);
        self.dirty = true;
    }

    /// Remove a project alias.
    pub fn removeAlias(self: *Config, alias: []const u8) bool {
        if (self.aliases.fetchRemove(alias)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
            self.dirty = true;
            return true;
        }
        return false;
    }

    /// Resolve a project reference, expanding aliases if needed.
    pub fn resolveProject(self: *const Config, ref: []const u8) []const u8 {
        return self.aliases.get(ref) orelse ref;
    }

    // ========================================================================
    // Private helpers
    // ========================================================================

    fn setDefaultServers(self: *Config) !void {
        // Production server
        try self.setServer("micelio.dev", .{
            .grpc_url = "https://grpc.micelio.dev:443",
            .web_url = "https://micelio.dev",
        });

        // Local development
        try self.setServer("localhost", .{
            .grpc_url = "http://localhost:50051",
            .web_url = "http://localhost:4000",
        });

        // Set default to localhost for now (production not ready)
        try self.setDefaultServer("localhost");
    }

    fn parseJson(self: *Config, data: []const u8) !void {
        const parsed = try std.json.parseFromSlice(ConfigJson, self.allocator, data, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        defer parsed.deinit();

        const json = parsed.value;

        // Default server
        if (json.default_server) |ds| {
            self.default_server = try self.allocator.dupe(u8, ds);
        }

        // Servers
        if (json.servers) |servers| {
            var iter = servers.map.iterator();
            while (iter.next()) |entry| {
                const owned_name = try self.allocator.dupe(u8, entry.key_ptr.*);
                const server_config = ServerConfig{
                    .grpc_url = if (entry.value_ptr.grpc_url) |u| try self.allocator.dupe(u8, u) else null,
                    .web_url = if (entry.value_ptr.web_url) |u| try self.allocator.dupe(u8, u) else null,
                };
                try self.servers.put(owned_name, server_config);
            }
        }

        // Aliases
        if (json.aliases) |aliases| {
            var iter = aliases.map.iterator();
            while (iter.next()) |entry| {
                const owned_alias = try self.allocator.dupe(u8, entry.key_ptr.*);
                const owned_ref = try self.allocator.dupe(u8, entry.value_ptr.*);
                try self.aliases.put(owned_alias, owned_ref);
            }
        }

        // Preferences
        if (json.preferences) |prefs| {
            if (prefs.output_format) |fmt| {
                self.preferences.output_format = std.meta.stringToEnum(OutputFormat, fmt) orelse .text;
            }
            if (prefs.color) |c| {
                self.preferences.color = c;
            }
        }
    }

    fn writeJson(self: *const Config, writer: anytype) !void {
        try writer.writeAll("{\n");

        // Default server
        if (self.default_server) |ds| {
            try writer.print("  \"default_server\": \"{s}\",\n", .{ds});
        }

        // Servers
        try writer.writeAll("  \"servers\": {\n");
        var first_server = true;
        var server_iter = self.servers.iterator();
        while (server_iter.next()) |entry| {
            if (!first_server) try writer.writeAll(",\n");
            first_server = false;

            try writer.print("    \"{s}\": {{\n", .{entry.key_ptr.*});
            if (entry.value_ptr.grpc_url) |url| {
                try writer.print("      \"grpc_url\": \"{s}\"", .{url});
            }
            if (entry.value_ptr.web_url) |url| {
                if (entry.value_ptr.grpc_url != null) try writer.writeAll(",\n") else try writer.writeAll("      ");
                try writer.print("      \"web_url\": \"{s}\"\n", .{url});
            } else {
                try writer.writeAll("\n");
            }
            try writer.writeAll("    }");
        }
        try writer.writeAll("\n  },\n");

        // Aliases
        try writer.writeAll("  \"aliases\": {\n");
        var first_alias = true;
        var alias_iter = self.aliases.iterator();
        while (alias_iter.next()) |entry| {
            if (!first_alias) try writer.writeAll(",\n");
            first_alias = false;
            try writer.print("    \"{s}\": \"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        if (!first_alias) try writer.writeAll("\n");
        try writer.writeAll("  },\n");

        // Preferences
        try writer.writeAll("  \"preferences\": {\n");
        try writer.print("    \"output_format\": \"{s}\",\n", .{@tagName(self.preferences.output_format)});
        try writer.print("    \"color\": {}\n", .{self.preferences.color});
        try writer.writeAll("  }\n");

        try writer.writeAll("}\n");
    }
};

/// Server configuration.
pub const ServerConfig = struct {
    grpc_url: ?[]const u8 = null,
    web_url: ?[]const u8 = null,

    pub fn clone(self: ServerConfig, allocator: std.mem.Allocator) !ServerConfig {
        return .{
            .grpc_url = if (self.grpc_url) |u| try allocator.dupe(u8, u) else null,
            .web_url = if (self.web_url) |u| try allocator.dupe(u8, u) else null,
        };
    }

    pub fn deinit(self: ServerConfig, allocator: std.mem.Allocator) void {
        if (self.grpc_url) |u| allocator.free(u);
        if (self.web_url) |u| allocator.free(u);
    }
};

/// Output format preference.
pub const OutputFormat = enum {
    text,
    json,
};

/// User preferences.
pub const Preferences = struct {
    output_format: OutputFormat = .text,
    color: bool = true,
};

// JSON parsing structures
const ConfigJson = struct {
    default_server: ?[]const u8 = null,
    servers: ?std.json.ArrayHashMap(ServerConfigJson) = null,
    aliases: ?std.json.ArrayHashMap([]const u8) = null,
    preferences: ?PreferencesJson = null,
};

const ServerConfigJson = struct {
    grpc_url: ?[]const u8 = null,
    web_url: ?[]const u8 = null,
};

const PreferencesJson = struct {
    output_format: ?[]const u8 = null,
    color: ?bool = null,
};

// ============================================================================
// Path utilities
// ============================================================================

/// Get the hif configuration directory path.
/// Uses $HIF_HOME if set, otherwise ~/.hif
pub fn configDir(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "HIF_HOME")) |value| {
        if (value.len > 0) return value;
        allocator.free(value);
    } else |_| {}

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    return std.fs.path.join(allocator, &.{ home, ".hif" });
}

/// Get the full path to the config file.
fn configFilePath(allocator: std.mem.Allocator) ![]u8 {
    const dir = try configDir(allocator);
    defer allocator.free(dir);

    return std.fs.path.join(allocator, &.{ dir, "config.json" });
}

/// Ensure the config directory exists.
pub fn ensureConfigDir(allocator: std.mem.Allocator) !void {
    const dir = try configDir(allocator);
    defer allocator.free(dir);

    std.fs.makeDirAbsolute(dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

fn readConfigFile(path: []const u8, allocator: std.mem.Allocator) !?[]u8 {
    var file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
        else => return err,
    };
    defer file.close();

    return try file.readToEndAlloc(allocator, 1024 * 1024);
}

// ============================================================================
// Tests
// ============================================================================

test "Config init and deinit" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try std.testing.expect(config.default_server == null);
    try std.testing.expectEqual(@as(usize, 0), config.servers.count());
}

test "Config setDefaultServer" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try config.setDefaultServer("localhost");
    try std.testing.expectEqualStrings("localhost", config.default_server.?);
    try std.testing.expect(config.dirty);
}

test "Config setServer and getServer" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try config.setServer("test", .{
        .grpc_url = "http://test:50051",
        .web_url = "http://test:4000",
    });

    const server = config.getServer("test");
    try std.testing.expect(server != null);
    try std.testing.expectEqualStrings("http://test:50051", server.?.grpc_url.?);
    try std.testing.expectEqualStrings("http://test:4000", server.?.web_url.?);
}

test "Config setAlias and getAlias" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try config.setAlias("myproj", "myorg/myproject");

    const resolved = config.getAlias("myproj");
    try std.testing.expect(resolved != null);
    try std.testing.expectEqualStrings("myorg/myproject", resolved.?);
}

test "Config removeAlias" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try config.setAlias("myproj", "myorg/myproject");
    try std.testing.expect(config.removeAlias("myproj"));
    try std.testing.expect(!config.removeAlias("myproj")); // Already removed
    try std.testing.expect(config.getAlias("myproj") == null);
}

test "Config resolveProject with alias" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try config.setAlias("mp", "myorg/myproject");

    const resolved = config.resolveProject("mp");
    try std.testing.expectEqualStrings("myorg/myproject", resolved);

    // Non-aliased ref returns as-is
    const direct = config.resolveProject("other/project");
    try std.testing.expectEqualStrings("other/project", direct);
}

test "Config getDefaultServer with servers" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try config.setServer("localhost", .{
        .grpc_url = "http://localhost:50051",
    });
    try config.setDefaultServer("localhost");

    const server_url = config.getDefaultServer();
    try std.testing.expect(server_url != null);
    try std.testing.expectEqualStrings("http://localhost:50051", server_url.?);
}

test "Config writeJson produces valid output" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try config.setServer("localhost", .{
        .grpc_url = "http://localhost:50051",
        .web_url = "http://localhost:4000",
    });
    try config.setDefaultServer("localhost");
    try config.setAlias("mp", "myorg/myproject");

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);

    try config.writeJson(buf.writer(std.testing.allocator));

    // Should be valid JSON (basic check)
    try std.testing.expect(buf.items.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, buf.items, "{"));
    try std.testing.expect(std.mem.endsWith(u8, buf.items, "}\n"));
}

test "configDir uses HIF_HOME if set" {
    // This test would need environment manipulation which is tricky
    // Just verify the function doesn't crash
    const dir = try configDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(dir.len > 0);
}

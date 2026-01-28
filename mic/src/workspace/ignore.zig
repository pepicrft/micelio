const std = @import("std");
const fs = @import("fs.zig");

/// Pattern for matching files to ignore.
pub const Pattern = struct {
    pattern: []const u8,
    negated: bool = false,
    dir_only: bool = false,
};

/// Parsed ignore patterns from .micignore file.
pub const IgnorePatterns = struct {
    allocator: std.mem.Allocator,
    patterns: []Pattern,

    pub fn deinit(self: *IgnorePatterns) void {
        for (self.patterns) |p| {
            self.allocator.free(p.pattern);
        }
        self.allocator.free(self.patterns);
    }

    /// Check if a path should be ignored.
    pub fn shouldIgnore(self: *const IgnorePatterns, path: []const u8) bool {
        var ignored = false;

        for (self.patterns) |p| {
            if (matchPattern(p.pattern, path, p.dir_only)) {
                ignored = !p.negated;
            }
        }

        return ignored;
    }
};

/// Load ignore patterns from workspace root.
pub fn load(allocator: std.mem.Allocator, workspace_root: []const u8) !IgnorePatterns {
    // Try .micignore in workspace root first
    const micignore_path = try std.fs.path.join(allocator, &.{ workspace_root, ".micignore" });
    defer allocator.free(micignore_path);

    const content = fs.readFileAlloc(allocator, micignore_path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return .{ .allocator = allocator, .patterns = &.{} },
        else => return err,
    };

    if (content == null) {
        return .{ .allocator = allocator, .patterns = &.{} };
    }
    defer allocator.free(content.?);

    return parsePatterns(allocator, content.?);
}

/// Parse ignore file content into patterns.
fn parsePatterns(allocator: std.mem.Allocator, content: []const u8) !IgnorePatterns {
    var patterns: std.ArrayListUnmanaged(Pattern) = .empty;
    errdefer {
        for (patterns.items) |p| allocator.free(p.pattern);
        patterns.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and comments
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;

        var pattern_str = trimmed;
        var negated = false;
        var dir_only = false;

        // Check for negation
        if (pattern_str[0] == '!') {
            negated = true;
            pattern_str = pattern_str[1..];
            if (pattern_str.len == 0) continue;
        }

        // Check for directory-only pattern (trailing /)
        if (pattern_str[pattern_str.len - 1] == '/') {
            dir_only = true;
            pattern_str = pattern_str[0 .. pattern_str.len - 1];
            if (pattern_str.len == 0) continue;
        }

        // Remove leading slash (anchored patterns)
        if (pattern_str.len > 0 and pattern_str[0] == '/') {
            pattern_str = pattern_str[1..];
        }

        if (pattern_str.len == 0) continue;

        const owned_pattern = try allocator.dupe(u8, pattern_str);
        try patterns.append(allocator, .{
            .pattern = owned_pattern,
            .negated = negated,
            .dir_only = dir_only,
        });
    }

    return .{
        .allocator = allocator,
        .patterns = try patterns.toOwnedSlice(allocator),
    };
}

/// Match a pattern against a path.
/// Supports:
/// - Exact matches: "foo.txt"
/// - Directory prefix matches: "vendor" matches "vendor/foo.txt"
/// - Glob patterns: "*.log", "**/*.tmp"
/// - Simple wildcards: "*" and "**"
fn matchPattern(pattern: []const u8, path: []const u8, dir_only: bool) bool {
    _ = dir_only; // TODO: implement directory-only matching

    // Handle ** (match any path depth)
    if (std.mem.indexOf(u8, pattern, "**")) |_| {
        return matchDoubleGlob(pattern, path);
    }

    // Handle * (match any chars except /)
    if (std.mem.indexOf(u8, pattern, "*")) |_| {
        // If pattern has no /, try matching against basename too
        if (std.mem.indexOf(u8, pattern, "/") == null) {
            const basename = std.fs.path.basename(path);
            if (matchGlob(pattern, basename)) return true;
        }
        return matchGlob(pattern, path);
    }

    // Exact match
    if (std.mem.eql(u8, pattern, path)) return true;

    // Pattern matches a directory prefix
    // e.g., pattern "vendor" matches path "vendor/foo/bar.txt"
    if (std.mem.startsWith(u8, path, pattern)) {
        if (path.len > pattern.len and path[pattern.len] == '/') {
            return true;
        }
    }

    // Pattern matches filename in any directory
    // e.g., pattern ".DS_Store" matches "foo/bar/.DS_Store"
    if (std.mem.indexOf(u8, pattern, "/") == null) {
        const basename = std.fs.path.basename(path);
        if (std.mem.eql(u8, pattern, basename)) return true;
    }

    return false;
}

/// Match a pattern with * wildcards (single level).
fn matchGlob(pattern: []const u8, path: []const u8) bool {
    // Simple glob matching for patterns like "*.log" or "test_*.txt"
    var pat_iter = std.mem.splitScalar(u8, pattern, '*');
    var path_pos: usize = 0;

    var first = true;
    while (pat_iter.next()) |segment| {
        if (segment.len == 0) {
            first = false;
            continue;
        }

        if (first) {
            // First segment must match at start
            if (!std.mem.startsWith(u8, path[path_pos..], segment)) {
                return false;
            }
            path_pos += segment.len;
            first = false;
        } else {
            // Find segment in remaining path
            if (std.mem.indexOf(u8, path[path_pos..], segment)) |idx| {
                // Make sure we don't cross directory boundaries with single *
                const skipped = path[path_pos .. path_pos + idx];
                if (std.mem.indexOf(u8, skipped, "/")) |_| {
                    return false;
                }
                path_pos += idx + segment.len;
            } else {
                return false;
            }
        }
    }

    // If pattern ends with *, allow any remaining (non-slash) chars
    if (std.mem.endsWith(u8, pattern, "*")) {
        const remaining = path[path_pos..];
        return std.mem.indexOf(u8, remaining, "/") == null;
    }

    // Otherwise must match exactly to end
    return path_pos == path.len;
}

/// Match a pattern with ** wildcards (multi-level).
fn matchDoubleGlob(pattern: []const u8, path: []const u8) bool {
    // Handle common cases efficiently
    if (std.mem.eql(u8, pattern, "**")) return true;

    // Split pattern by **
    var segments = std.mem.splitSequence(u8, pattern, "**");
    var path_pos: usize = 0;

    var first = true;
    while (segments.next()) |segment| {
        // Skip empty segments (consecutive ** or leading **)
        const trimmed = std.mem.trim(u8, segment, "/");
        if (trimmed.len == 0) {
            first = false;
            continue;
        }

        if (first) {
            // First segment must match at start
            if (std.mem.indexOf(u8, segment, "*")) |_| {
                if (!matchGlob(segment, path[0..@min(segment.len + 10, path.len)])) {
                    return false;
                }
            } else if (!std.mem.startsWith(u8, path, trimmed)) {
                return false;
            }
            path_pos = trimmed.len;
            if (path_pos < path.len and path[path_pos] == '/') path_pos += 1;
            first = false;
        } else {
            // Find segment anywhere in remaining path
            if (std.mem.indexOf(u8, segment, "*")) |_| {
                // Complex: segment itself contains wildcards
                // Try matching from each position
                var found = false;
                var check_pos = path_pos;
                while (check_pos < path.len) {
                    const remaining = path[check_pos..];
                    if (matchGlob(trimmed, remaining[0..@min(trimmed.len + 10, remaining.len)])) {
                        path_pos = check_pos + trimmed.len;
                        found = true;
                        break;
                    }
                    check_pos += 1;
                }
                if (!found) return false;
            } else {
                // Simple: find exact segment
                if (std.mem.indexOf(u8, path[path_pos..], trimmed)) |idx| {
                    path_pos += idx + trimmed.len;
                } else {
                    return false;
                }
            }
        }
    }

    return true;
}

// Tests
test "empty patterns" {
    var patterns = IgnorePatterns{
        .allocator = std.testing.allocator,
        .patterns = &.{},
    };
    try std.testing.expect(!patterns.shouldIgnore("foo.txt"));
}

test "exact match" {
    const content = "foo.txt\n";
    var patterns = try parsePatterns(std.testing.allocator, content);
    defer patterns.deinit();

    try std.testing.expect(patterns.shouldIgnore("foo.txt"));
    try std.testing.expect(!patterns.shouldIgnore("bar.txt"));
}

test "directory prefix match" {
    const content = "vendor\nnode_modules\n";
    var patterns = try parsePatterns(std.testing.allocator, content);
    defer patterns.deinit();

    try std.testing.expect(patterns.shouldIgnore("vendor/foo.txt"));
    try std.testing.expect(patterns.shouldIgnore("vendor/sub/bar.txt"));
    try std.testing.expect(patterns.shouldIgnore("node_modules/pkg/index.js"));
    try std.testing.expect(!patterns.shouldIgnore("src/vendor.txt"));
}

test "glob patterns" {
    const content = "*.log\n*.tmp\n";
    var patterns = try parsePatterns(std.testing.allocator, content);
    defer patterns.deinit();

    try std.testing.expect(patterns.shouldIgnore("app.log"));
    try std.testing.expect(patterns.shouldIgnore("foo/bar.log"));
    try std.testing.expect(patterns.shouldIgnore("temp.tmp"));
    try std.testing.expect(!patterns.shouldIgnore("log.txt"));
}

test "double glob patterns" {
    const content = "**/*.log\nsrc/**/*.tmp\n";
    var patterns = try parsePatterns(std.testing.allocator, content);
    defer patterns.deinit();

    try std.testing.expect(patterns.shouldIgnore("app.log"));
    try std.testing.expect(patterns.shouldIgnore("foo/bar/baz.log"));
    try std.testing.expect(patterns.shouldIgnore("src/a/b/c.tmp"));
    try std.testing.expect(!patterns.shouldIgnore("lib/a.tmp"));
}

test "negation" {
    const content = "*.log\n!important.log\n";
    var patterns = try parsePatterns(std.testing.allocator, content);
    defer patterns.deinit();

    try std.testing.expect(patterns.shouldIgnore("app.log"));
    try std.testing.expect(!patterns.shouldIgnore("important.log"));
}

test "comments and empty lines" {
    const content = "# This is a comment\n\n*.log\n  # Another comment  \n";
    var patterns = try parsePatterns(std.testing.allocator, content);
    defer patterns.deinit();

    try std.testing.expectEqual(@as(usize, 1), patterns.patterns.len);
    try std.testing.expect(patterns.shouldIgnore("app.log"));
}

test "basename match" {
    const content = ".DS_Store\n.gitignore\n";
    var patterns = try parsePatterns(std.testing.allocator, content);
    defer patterns.deinit();

    try std.testing.expect(patterns.shouldIgnore(".DS_Store"));
    try std.testing.expect(patterns.shouldIgnore("foo/.DS_Store"));
    try std.testing.expect(patterns.shouldIgnore("foo/bar/.DS_Store"));
    try std.testing.expect(patterns.shouldIgnore(".gitignore"));
}

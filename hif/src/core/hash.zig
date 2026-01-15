//! Blake3 hashing utilities for content-addressed storage.
//!
//! This module provides consistent hashing for all hif content:
//! - Blob hashing for file content
//! - Tree hashing for directory structures
//! - Path hashing for bloom filter keys

const std = @import("std");

/// Hash output size in bytes (256 bits).
pub const HASH_SIZE = 32;

/// A 256-bit Blake3 hash.
pub const Hash = [HASH_SIZE]u8;

/// Hash arbitrary data using Blake3.
pub fn hash(data: []const u8) Hash {
    var out: Hash = undefined;
    std.crypto.hash.Blake3.hash(data, &out, .{});
    return out;
}

/// Incremental hasher for streaming data.
pub const Hasher = struct {
    state: std.crypto.hash.Blake3,

    pub fn init() Hasher {
        return .{ .state = std.crypto.hash.Blake3.init(.{}) };
    }

    pub fn update(self: *Hasher, data: []const u8) void {
        self.state.update(data);
    }

    pub fn final(self: *Hasher) Hash {
        var out: Hash = undefined;
        self.state.final(&out);
        return out;
    }
};

/// Hash a file's content for blob storage.
/// Prefixes with "blob\x00" + length for git-like object typing.
pub fn hashBlob(content: []const u8) Hash {
    var hasher = Hasher.init();
    hasher.update("blob\x00");

    // Encode length as varint-style prefix
    var len_buf: [10]u8 = undefined;
    const len_bytes = encodeLength(content.len, &len_buf);
    hasher.update(len_bytes);

    hasher.update(content);
    return hasher.final();
}

/// Hash a tree (directory) structure.
/// Entries should be sorted by path for deterministic hashing.
pub fn hashTree(entries: []const TreeEntry) Hash {
    var hasher = Hasher.init();
    hasher.update("tree\x00");

    for (entries) |entry| {
        // Mode (file permissions/type) as octal
        var mode_buf: [16]u8 = undefined;
        const mode_str = std.fmt.bufPrint(&mode_buf, "{o}", .{entry.mode}) catch unreachable;
        hasher.update(mode_str);
        hasher.update(" ");

        // Path
        hasher.update(entry.path);
        hasher.update("\x00");

        // Hash
        hasher.update(&entry.hash);
    }

    return hasher.final();
}

/// An entry in a tree (directory).
pub const TreeEntry = struct {
    mode: u32,
    path: []const u8,
    hash: Hash,
};

/// Encode a length as a variable-length integer (varint).
///
/// Uses 7 bits per byte with the high bit as a continuation flag.
/// Maximum encoded length is 10 bytes (for 64-bit values), which fits
/// in the provided buffer. A 64-bit value requires at most ceil(64/7) = 10 bytes.
fn encodeLength(len: usize, buf: *[10]u8) []const u8 {
    var value = len;
    var i: usize = 0;

    while (value >= 0x80) {
        buf[i] = @as(u8, @intCast(value & 0x7f)) | 0x80;
        value >>= 7;
        i += 1;
    }
    buf[i] = @intCast(value);

    // Safety: i < 10 is guaranteed since a 64-bit value encodes to at most 10 bytes
    std.debug.assert(i < 10);

    return buf[0 .. i + 1];
}

/// Format a hash as a lowercase hexadecimal string.
pub fn formatHex(h: Hash) [HASH_SIZE * 2]u8 {
    var buf: [HASH_SIZE * 2]u8 = undefined;
    const hex = "0123456789abcdef";
    for (h, 0..) |byte, i| {
        buf[i * 2] = hex[byte >> 4];
        buf[i * 2 + 1] = hex[byte & 0x0f];
    }
    return buf;
}

/// Parse a hexadecimal string into a hash.
pub fn parseHex(hex_str: []const u8) !Hash {
    if (hex_str.len != HASH_SIZE * 2) return error.InvalidLength;

    var out: Hash = undefined;
    for (0..HASH_SIZE) |i| {
        const high = std.fmt.charToDigit(hex_str[i * 2], 16) catch return error.InvalidHex;
        const low = std.fmt.charToDigit(hex_str[i * 2 + 1], 16) catch return error.InvalidHex;
        out[i] = (high << 4) | low;
    }
    return out;
}

// Tests

test "hash produces consistent output" {
    const h1 = hash("hello world");
    const h2 = hash("hello world");
    try std.testing.expectEqualSlices(u8, &h1, &h2);
}

test "hash produces different output for different input" {
    const h1 = hash("hello");
    const h2 = hash("world");
    try std.testing.expect(!std.mem.eql(u8, &h1, &h2));
}

test "hashBlob includes type prefix" {
    const content = "test content";
    const h1 = hashBlob(content);
    const h2 = hash(content);
    // Should be different because blob hash includes prefix
    try std.testing.expect(!std.mem.eql(u8, &h1, &h2));
}

test "Hasher streaming matches one-shot" {
    const data = "hello world";

    var hasher = Hasher.init();
    hasher.update("hello ");
    hasher.update("world");
    const streaming = hasher.final();

    const oneshot = hash(data);

    try std.testing.expectEqualSlices(u8, &oneshot, &streaming);
}

test "formatHex roundtrips with parseHex" {
    const original = hash("test");
    const hex = formatHex(original);
    const parsed = try parseHex(&hex);
    try std.testing.expectEqualSlices(u8, &original, &parsed);
}

test "parseHex rejects invalid length" {
    try std.testing.expectError(error.InvalidLength, parseHex("abc"));
}

test "parseHex rejects invalid characters" {
    var invalid: [64]u8 = undefined;
    @memset(&invalid, 'g');
    try std.testing.expectError(error.InvalidHex, parseHex(&invalid));
}

test "hashTree is deterministic" {
    const entries = [_]TreeEntry{
        .{ .mode = 0o100644, .path = "file.txt", .hash = hash("content1") },
        .{ .mode = 0o100755, .path = "script.sh", .hash = hash("content2") },
    };

    const h1 = hashTree(&entries);
    const h2 = hashTree(&entries);
    try std.testing.expectEqualSlices(u8, &h1, &h2);
}

test "hashTree order matters" {
    const entries1 = [_]TreeEntry{
        .{ .mode = 0o100644, .path = "a.txt", .hash = hash("a") },
        .{ .mode = 0o100644, .path = "b.txt", .hash = hash("b") },
    };
    const entries2 = [_]TreeEntry{
        .{ .mode = 0o100644, .path = "b.txt", .hash = hash("b") },
        .{ .mode = 0o100644, .path = "a.txt", .hash = hash("a") },
    };

    const h1 = hashTree(&entries1);
    const h2 = hashTree(&entries2);
    try std.testing.expect(!std.mem.eql(u8, &h1, &h2));
}

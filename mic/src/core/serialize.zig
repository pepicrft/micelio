//! Binary serialization for mic core types.
//!
//! This module provides efficient binary serialization for:
//! - Trees (path -> hash mappings)
//! - Bloom filters (conflict detection)
//! - HLC timestamps (distributed ordering)
//!
//! ## Wire Format
//!
//! All multi-byte integers are little-endian unless noted.
//! Strings are length-prefixed with varint encoding.
//!
//! ### Tree Format
//!
//! ```
//! [4 bytes: magic "MIC\x01"]
//! [1 byte:  type = 0x01 for tree]
//! [varint:  entry count]
//! [entries...]
//!   [varint: path length]
//!   [bytes:  path]
//!   [32 bytes: content hash]
//! ```
//!
//! ### Bloom Filter Format
//!
//! ```
//! [4 bytes: magic "MIC\x01"]
//! [1 byte:  type = 0x02 for bloom]
//! [4 bytes: num_hashes (little-endian)]
//! [varint:  bits length]
//! [bytes:   bits data]
//! ```
//!
//! ### HLC Format
//!
//! ```
//! [4 bytes: magic "MIC\x01"]
//! [1 byte:  type = 0x03 for HLC]
//! [8 bytes: physical (big-endian for sorting)]
//! [4 bytes: logical (big-endian)]
//! [4 bytes: node_id (big-endian)]
//! ```

const std = @import("std");
const hash_mod = @import("hash.zig");
const tree_mod = @import("tree.zig");
const bloom_mod = @import("bloom.zig");
const hlc_mod = @import("hlc.zig");

const Hash = hash_mod.Hash;
const HASH_SIZE = hash_mod.HASH_SIZE;
const Tree = tree_mod.Tree;
const Bloom = bloom_mod.Bloom;
const HLC = hlc_mod.HLC;

/// Magic bytes identifying mic binary format.
pub const MAGIC: [4]u8 = .{ 'M', 'I', 'C', 0x01 };

/// Type identifiers for different serialized structures.
pub const Type = enum(u8) {
    tree = 0x01,
    bloom = 0x02,
    hlc = 0x03,
    session = 0x04,
};

/// Serialization errors.
pub const Error = error{
    InvalidMagic,
    InvalidType,
    InvalidData,
    UnexpectedEndOfData,
    PathTooLong,
    OutOfMemory,
};

// ============================================================================
// Varint encoding/decoding (shared utilities)
// ============================================================================

/// Maximum bytes needed for a varint-encoded usize.
const MAX_VARINT_BYTES = 10;

/// Encode a usize as a varint into the provided buffer.
/// Returns the slice of bytes used.
pub fn encodeVarint(value: usize, buf: *[MAX_VARINT_BYTES]u8) []const u8 {
    var v = value;
    var i: usize = 0;

    while (v >= 0x80) {
        buf[i] = @as(u8, @intCast(v & 0x7f)) | 0x80;
        v >>= 7;
        i += 1;
    }
    buf[i] = @intCast(v);
    return buf[0 .. i + 1];
}

/// Decode a varint from the input slice.
/// Returns the decoded value and the number of bytes consumed.
pub fn decodeVarint(data: []const u8) Error!struct { value: usize, bytes_read: usize } {
    var value: usize = 0;
    var shift: u6 = 0;

    for (data, 0..) |byte, i| {
        if (i >= MAX_VARINT_BYTES) return Error.InvalidData;

        const payload: usize = @as(usize, byte & 0x7f);
        value |= payload << shift;

        if ((byte & 0x80) == 0) {
            return .{ .value = value, .bytes_read = i + 1 };
        }
        shift += 7;
    }

    return Error.UnexpectedEndOfData;
}

// ============================================================================
// Tree serialization
// ============================================================================

/// Serialize a tree to binary format.
///
/// The caller owns the returned slice and must free it.
pub fn serializeTree(allocator: std.mem.Allocator, tree: *const Tree) ![]u8 {
    // Calculate required buffer size
    var total_size: usize = MAGIC.len + 1; // magic + type

    // Count entries and calculate path sizes
    var entry_count: usize = 0;
    var iter = tree.iterator();
    while (iter.next()) |entry| {
        entry_count += 1;
        // varint(path_len) + path + hash
        var varint_buf: [MAX_VARINT_BYTES]u8 = undefined;
        total_size += encodeVarint(entry.path.len, &varint_buf).len;
        total_size += entry.path.len;
        total_size += HASH_SIZE;
    }

    // Add entry count varint
    var count_buf: [MAX_VARINT_BYTES]u8 = undefined;
    total_size += encodeVarint(entry_count, &count_buf).len;

    // Allocate buffer
    const buf = try allocator.alloc(u8, total_size);
    errdefer allocator.free(buf);

    var pos: usize = 0;

    // Write magic
    @memcpy(buf[pos..][0..MAGIC.len], &MAGIC);
    pos += MAGIC.len;

    // Write type
    buf[pos] = @intFromEnum(Type.tree);
    pos += 1;

    // Write entry count
    const count_bytes = encodeVarint(entry_count, &count_buf);
    @memcpy(buf[pos..][0..count_bytes.len], count_bytes);
    pos += count_bytes.len;

    // Write entries
    iter = tree.iterator();
    while (iter.next()) |entry| {
        // Path length
        var path_len_buf: [MAX_VARINT_BYTES]u8 = undefined;
        const path_len_bytes = encodeVarint(entry.path.len, &path_len_buf);
        @memcpy(buf[pos..][0..path_len_bytes.len], path_len_bytes);
        pos += path_len_bytes.len;

        // Path data
        @memcpy(buf[pos..][0..entry.path.len], entry.path);
        pos += entry.path.len;

        // Content hash
        @memcpy(buf[pos..][0..HASH_SIZE], &entry.content_hash);
        pos += HASH_SIZE;
    }

    return buf;
}

/// Deserialize a tree from binary format.
///
/// The caller owns the returned tree and must call deinit() on it.
pub fn deserializeTree(allocator: std.mem.Allocator, data: []const u8) !Tree {
    var tree = Tree.init(allocator);
    errdefer tree.deinit();

    var pos: usize = 0;

    // Check magic
    if (data.len < MAGIC.len + 1) return Error.UnexpectedEndOfData;
    if (!std.mem.eql(u8, data[0..MAGIC.len], &MAGIC)) return Error.InvalidMagic;
    pos += MAGIC.len;

    // Check type
    if (data[pos] != @intFromEnum(Type.tree)) return Error.InvalidType;
    pos += 1;

    // Read entry count
    const count_result = try decodeVarint(data[pos..]);
    const entry_count = count_result.value;
    pos += count_result.bytes_read;

    // Read entries
    for (0..entry_count) |_| {
        // Read path length
        if (pos >= data.len) return Error.UnexpectedEndOfData;
        const path_len_result = try decodeVarint(data[pos..]);
        const path_len = path_len_result.value;
        pos += path_len_result.bytes_read;

        // Sanity check path length
        if (path_len > 4096) return Error.PathTooLong;

        // Read path
        if (pos + path_len > data.len) return Error.UnexpectedEndOfData;
        const path = data[pos..][0..path_len];
        pos += path_len;

        // Read hash
        if (pos + HASH_SIZE > data.len) return Error.UnexpectedEndOfData;
        const content_hash: Hash = data[pos..][0..HASH_SIZE].*;
        pos += HASH_SIZE;

        // Insert into tree
        try tree.insert(path, content_hash);
    }

    return tree;
}

// ============================================================================
// Bloom filter serialization (wrapper around existing methods)
// ============================================================================

/// Serialize a bloom filter with MIC header.
pub fn serializeBloom(allocator: std.mem.Allocator, bloom: *const Bloom) ![]u8 {
    // Get the bloom's internal serialization
    const bloom_data = try bloom.serialize(allocator);
    defer allocator.free(bloom_data);

    // Calculate total size
    const total_size = MAGIC.len + 1 + bloom_data.len;
    const buf = try allocator.alloc(u8, total_size);
    errdefer allocator.free(buf);

    var pos: usize = 0;

    // Write magic
    @memcpy(buf[pos..][0..MAGIC.len], &MAGIC);
    pos += MAGIC.len;

    // Write type
    buf[pos] = @intFromEnum(Type.bloom);
    pos += 1;

    // Write bloom data
    @memcpy(buf[pos..], bloom_data);

    return buf;
}

/// Deserialize a bloom filter with MIC header verification.
pub fn deserializeBloom(allocator: std.mem.Allocator, data: []const u8) !Bloom {
    var pos: usize = 0;

    // Check magic
    if (data.len < MAGIC.len + 1) return Error.UnexpectedEndOfData;
    if (!std.mem.eql(u8, data[0..MAGIC.len], &MAGIC)) return Error.InvalidMagic;
    pos += MAGIC.len;

    // Check type
    if (data[pos] != @intFromEnum(Type.bloom)) return Error.InvalidType;
    pos += 1;

    // Deserialize bloom data
    return Bloom.deserialize(allocator, data[pos..]) catch return Error.InvalidData;
}

// ============================================================================
// HLC serialization (wrapper around existing methods)
// ============================================================================

/// Serialize an HLC timestamp with MIC header.
pub fn serializeHLC(allocator: std.mem.Allocator, hlc: HLC) ![]u8 {
    const total_size = MAGIC.len + 1 + 16; // magic + type + HLC bytes
    const buf = try allocator.alloc(u8, total_size);

    var pos: usize = 0;

    // Write magic
    @memcpy(buf[pos..][0..MAGIC.len], &MAGIC);
    pos += MAGIC.len;

    // Write type
    buf[pos] = @intFromEnum(Type.hlc);
    pos += 1;

    // Write HLC bytes
    const hlc_bytes = hlc.toBytes();
    @memcpy(buf[pos..][0..16], &hlc_bytes);

    return buf;
}

/// Deserialize an HLC timestamp with MIC header verification.
pub fn deserializeHLC(data: []const u8) Error!HLC {
    const required_len = MAGIC.len + 1 + 16;
    if (data.len < required_len) return Error.UnexpectedEndOfData;

    var pos: usize = 0;

    // Check magic
    if (!std.mem.eql(u8, data[0..MAGIC.len], &MAGIC)) return Error.InvalidMagic;
    pos += MAGIC.len;

    // Check type
    if (data[pos] != @intFromEnum(Type.hlc)) return Error.InvalidType;
    pos += 1;

    // Read HLC bytes
    return HLC.fromBytes(data[pos..][0..16]);
}

// ============================================================================
// Type detection
// ============================================================================

/// Detect the type of a serialized structure without fully parsing it.
pub fn detectType(data: []const u8) Error!Type {
    if (data.len < MAGIC.len + 1) return Error.UnexpectedEndOfData;
    if (!std.mem.eql(u8, data[0..MAGIC.len], &MAGIC)) return Error.InvalidMagic;
    return std.meta.intToEnum(Type, data[MAGIC.len]) catch return Error.InvalidType;
}

// ============================================================================
// Tests
// ============================================================================

test "varint roundtrip" {
    const test_values = [_]usize{ 0, 1, 127, 128, 255, 256, 16383, 16384, 1000000, std.math.maxInt(usize) };

    for (test_values) |value| {
        var buf: [MAX_VARINT_BYTES]u8 = undefined;
        const encoded = encodeVarint(value, &buf);
        const result = try decodeVarint(encoded);
        try std.testing.expectEqual(value, result.value);
        try std.testing.expectEqual(encoded.len, result.bytes_read);
    }
}

test "tree serialize/deserialize empty" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    const data = try serializeTree(std.testing.allocator, &tree);
    defer std.testing.allocator.free(data);

    var restored = try deserializeTree(std.testing.allocator, data);
    defer restored.deinit();

    try std.testing.expectEqual(@as(usize, 0), restored.count());
}

test "tree serialize/deserialize with entries" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    const hash1 = hash_mod.hash("content1");
    const hash2 = hash_mod.hash("content2");
    const hash3 = hash_mod.hash("content3");

    try tree.insert("src/main.zig", hash1);
    try tree.insert("src/lib.zig", hash2);
    try tree.insert("README.md", hash3);

    const data = try serializeTree(std.testing.allocator, &tree);
    defer std.testing.allocator.free(data);

    var restored = try deserializeTree(std.testing.allocator, data);
    defer restored.deinit();

    try std.testing.expectEqual(@as(usize, 3), restored.count());
    try std.testing.expectEqualSlices(u8, &hash1, &restored.get("src/main.zig").?);
    try std.testing.expectEqualSlices(u8, &hash2, &restored.get("src/lib.zig").?);
    try std.testing.expectEqualSlices(u8, &hash3, &restored.get("README.md").?);
}

test "tree serialize/deserialize preserves hash" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.insert("file.txt", hash_mod.hash("content"));

    const original_hash = tree.hash();

    const data = try serializeTree(std.testing.allocator, &tree);
    defer std.testing.allocator.free(data);

    var restored = try deserializeTree(std.testing.allocator, data);
    defer restored.deinit();

    const restored_hash = restored.hash();

    try std.testing.expectEqualSlices(u8, &original_hash, &restored_hash);
}

test "bloom serialize/deserialize" {
    var bloom = try Bloom.init(std.testing.allocator, 100, 0.01);
    defer bloom.deinit();

    bloom.add("path/to/file.zig");
    bloom.add("another/file.txt");

    const data = try serializeBloom(std.testing.allocator, &bloom);
    defer std.testing.allocator.free(data);

    var restored = try deserializeBloom(std.testing.allocator, data);
    defer restored.deinit();

    try std.testing.expect(restored.mayContain("path/to/file.zig"));
    try std.testing.expect(restored.mayContain("another/file.txt"));
    try std.testing.expectEqual(bloom.num_hashes, restored.num_hashes);
    try std.testing.expectEqual(bloom.sizeBytes(), restored.sizeBytes());
}

test "HLC serialize/deserialize" {
    const original = HLC{
        .physical = 1704067200000,
        .logical = 42,
        .node_id = 12345,
    };

    const data = try serializeHLC(std.testing.allocator, original);
    defer std.testing.allocator.free(data);

    const restored = try deserializeHLC(data);

    try std.testing.expectEqual(original.physical, restored.physical);
    try std.testing.expectEqual(original.logical, restored.logical);
    try std.testing.expectEqual(original.node_id, restored.node_id);
}

test "detectType identifies tree" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    const data = try serializeTree(std.testing.allocator, &tree);
    defer std.testing.allocator.free(data);

    const detected = try detectType(data);
    try std.testing.expectEqual(Type.tree, detected);
}

test "detectType identifies bloom" {
    var bloom = try Bloom.initWithSize(std.testing.allocator, 64, 5);
    defer bloom.deinit();

    const data = try serializeBloom(std.testing.allocator, &bloom);
    defer std.testing.allocator.free(data);

    const detected = try detectType(data);
    try std.testing.expectEqual(Type.bloom, detected);
}

test "detectType identifies HLC" {
    const hlc = HLC{ .physical = 1000, .logical = 1, .node_id = 1 };
    const data = try serializeHLC(std.testing.allocator, hlc);
    defer std.testing.allocator.free(data);

    const detected = try detectType(data);
    try std.testing.expectEqual(Type.hlc, detected);
}

test "invalid magic returns error" {
    const bad_data = [_]u8{ 'B', 'A', 'D', 0x00, 0x01 };
    try std.testing.expectError(Error.InvalidMagic, detectType(&bad_data));
}

test "truncated data returns error" {
    const short_data = [_]u8{ 'M', 'I', 'C' };
    try std.testing.expectError(Error.UnexpectedEndOfData, detectType(&short_data));
}

test "invalid type returns error" {
    const bad_type = [_]u8{ 'M', 'I', 'C', 0x01, 0xFF };
    try std.testing.expectError(Error.InvalidType, detectType(&bad_type));
}

test "tree with many entries" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    // Insert 100 entries
    for (0..100) |i| {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "file_{d:0>3}.txt", .{i}) catch unreachable;
        try tree.insert(path, hash_mod.hash(path));
    }

    const data = try serializeTree(std.testing.allocator, &tree);
    defer std.testing.allocator.free(data);

    var restored = try deserializeTree(std.testing.allocator, data);
    defer restored.deinit();

    try std.testing.expectEqual(@as(usize, 100), restored.count());

    // Verify all entries
    for (0..100) |i| {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "file_{d:0>3}.txt", .{i}) catch unreachable;
        try std.testing.expect(restored.contains(path));
    }
}

test "tree with unicode paths" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.insert("中文/文件.txt", hash_mod.hash("chinese"));
    try tree.insert("日本語/ファイル.txt", hash_mod.hash("japanese"));
    try tree.insert("emoji/🎉.txt", hash_mod.hash("emoji"));

    const data = try serializeTree(std.testing.allocator, &tree);
    defer std.testing.allocator.free(data);

    var restored = try deserializeTree(std.testing.allocator, data);
    defer restored.deinit();

    try std.testing.expect(restored.contains("中文/文件.txt"));
    try std.testing.expect(restored.contains("日本語/ファイル.txt"));
    try std.testing.expect(restored.contains("emoji/🎉.txt"));
}

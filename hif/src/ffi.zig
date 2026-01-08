//! C ABI for libhif-core.
//!
//! This module exports all core algorithms via C-compatible function signatures.
//! See include/hif_core.h for the generated header and documentation.

const std = @import("std");
const hif = @import("root.zig");

const hash = hif.hash;
const bloom = hif.bloom;
const hlc = hif.hlc;

// ============================================================================
// Version Information
// ============================================================================

/// Get the library version string.
export fn hif_version() [*:0]const u8 {
    return "0.1.0";
}

/// Get the ABI version for compatibility checking.
export fn hif_abi_version() u32 {
    return 1;
}

// ============================================================================
// Allocator
// ============================================================================

/// Opaque allocator wrapper for C.
const HifAllocator = struct {
    inner: std.mem.Allocator,
};

/// Singleton C allocator.
var c_allocator_instance = HifAllocator{ .inner = std.heap.c_allocator };

/// Get the C allocator (uses malloc/free).
export fn hif_allocator_c() *HifAllocator {
    return &c_allocator_instance;
}

/// Free memory allocated by hif functions.
export fn hif_free(alloc: *const HifAllocator, ptr: [*]u8, len: usize) void {
    if (len == 0) return;
    alloc.inner.free(ptr[0..len]);
}

// ============================================================================
// Hashing
// ============================================================================

/// Hash data using Blake3. Writes 32 bytes to out.
export fn hif_hash(data: [*]const u8, data_len: usize, out: *[hash.HASH_SIZE]u8) void {
    out.* = hash.hash(data[0..data_len]);
}

/// Hash a blob (file content) with type prefix.
export fn hif_hash_blob(content: [*]const u8, content_len: usize, out: *[hash.HASH_SIZE]u8) void {
    out.* = hash.hashBlob(content[0..content_len]);
}

/// Format a hash as hexadecimal. Writes 64 bytes to out (not null-terminated).
export fn hif_hash_format_hex(h: *const [hash.HASH_SIZE]u8, out: *[hash.HASH_SIZE * 2]u8) void {
    out.* = hash.formatHex(h.*);
}

/// Parse a hexadecimal string into a hash.
/// Returns 0 on success, -1 on invalid input.
export fn hif_hash_parse_hex(hex: [*]const u8, hex_len: usize, out: *[hash.HASH_SIZE]u8) c_int {
    if (hex_len != hash.HASH_SIZE * 2) return -1;
    out.* = hash.parseHex(hex[0..hex_len]) catch return -1;
    return 0;
}

// ============================================================================
// Bloom Filter
// ============================================================================

/// Opaque bloom filter wrapper for C.
const HifBloom = struct {
    inner: bloom.Bloom,
};

/// Create a new bloom filter.
export fn hif_bloom_new(alloc: *const HifAllocator, expected_items: usize, fp_rate: f64) ?*HifBloom {
    const b = bloom.Bloom.init(alloc.inner, expected_items, fp_rate) catch return null;
    const wrapper = alloc.inner.create(HifBloom) catch return null;
    wrapper.* = .{ .inner = b };
    return wrapper;
}

/// Free a bloom filter.
export fn hif_bloom_free(alloc: *const HifAllocator, b: *HifBloom) void {
    b.inner.deinit();
    alloc.inner.destroy(b);
}

/// Add a path to the bloom filter.
export fn hif_bloom_add(b: *HifBloom, path: [*]const u8, path_len: usize) void {
    b.inner.add(path[0..path_len]);
}

/// Add a hash to the bloom filter.
export fn hif_bloom_add_hash(b: *HifBloom, h: *const [hash.HASH_SIZE]u8) void {
    b.inner.addHash(h);
}

/// Check if a path might be in the bloom filter.
/// Returns 1 if possibly present, 0 if definitely not present.
export fn hif_bloom_may_contain(b: *const HifBloom, path: [*]const u8, path_len: usize) c_int {
    return if (b.inner.mayContain(path[0..path_len])) 1 else 0;
}

/// Check if two bloom filters might have overlapping items.
/// Returns 1 if possibly intersecting, 0 if definitely disjoint.
export fn hif_bloom_intersects(a: *const HifBloom, b: *const HifBloom) c_int {
    return if (a.inner.intersects(&b.inner)) 1 else 0;
}

/// Merge another bloom filter into this one (union).
export fn hif_bloom_merge(dst: *HifBloom, src: *const HifBloom) void {
    dst.inner.merge(&src.inner);
}

/// Get estimated number of items in the filter.
export fn hif_bloom_estimate_count(b: *const HifBloom) usize {
    return b.inner.estimateCount();
}

/// Serialize bloom filter to bytes.
/// Returns pointer to serialized data, or NULL on failure. Caller must free with hif_free().
export fn hif_bloom_serialize(alloc: *const HifAllocator, b: *const HifBloom, out_len: *usize) ?[*]u8 {
    const data = b.inner.serialize(alloc.inner) catch return null;
    out_len.* = data.len;
    return data.ptr;
}

/// Deserialize bloom filter from bytes.
/// Returns bloom filter handle, or NULL on failure.
export fn hif_bloom_deserialize(alloc: *const HifAllocator, data: [*]const u8, data_len: usize) ?*HifBloom {
    const b = bloom.Bloom.deserialize(alloc.inner, data[0..data_len]) catch return null;
    const wrapper = alloc.inner.create(HifBloom) catch {
        var inner = b;
        inner.deinit();
        return null;
    };
    wrapper.* = .{ .inner = b };
    return wrapper;
}

// ============================================================================
// Hybrid Logical Clock
// ============================================================================

/// HLC timestamp (C-compatible struct).
const HifHLC = extern struct {
    physical: i64,
    logical: u32,
    node_id: u32,
};

/// Opaque clock wrapper for C.
const HifClock = struct {
    inner: hlc.Clock,
};

/// Create a new HLC clock.
export fn hif_clock_new(alloc: *const HifAllocator, node_id: u32) ?*HifClock {
    const wrapper = alloc.inner.create(HifClock) catch return null;
    wrapper.* = .{ .inner = hlc.Clock.init(node_id) };
    return wrapper;
}

/// Free a clock.
export fn hif_clock_free(alloc: *const HifAllocator, clock: *HifClock) void {
    alloc.inner.destroy(clock);
}

/// Generate a new timestamp for a local event.
export fn hif_clock_now(clock: *HifClock, out: *HifHLC) void {
    const ts = clock.inner.now();
    out.* = .{ .physical = ts.physical, .logical = ts.logical, .node_id = ts.node_id };
}

/// Generate a timestamp with explicit wall clock (for testing).
export fn hif_clock_now_with_wall(clock: *HifClock, wall_ms: i64, out: *HifHLC) void {
    const ts = clock.inner.tick(wall_ms);
    out.* = .{ .physical = ts.physical, .logical = ts.logical, .node_id = ts.node_id };
}

/// Update clock upon receiving a message with a timestamp.
export fn hif_clock_receive(clock: *HifClock, msg: *const HifHLC, out: *HifHLC) void {
    const msg_ts = hlc.HLC{
        .physical = msg.physical,
        .logical = msg.logical,
        .node_id = msg.node_id,
    };
    const ts = clock.inner.receive(msg_ts);
    out.* = .{ .physical = ts.physical, .logical = ts.logical, .node_id = ts.node_id };
}

/// Get the current timestamp without advancing the clock.
export fn hif_clock_current(clock: *const HifClock, out: *HifHLC) void {
    const ts = clock.inner.current();
    out.* = .{ .physical = ts.physical, .logical = ts.logical, .node_id = ts.node_id };
}

/// Compare two HLC timestamps.
/// Returns -1 if a < b, 0 if a == b, 1 if a > b.
export fn hif_hlc_compare(a: *const HifHLC, b: *const HifHLC) c_int {
    const a_ts = hlc.HLC{ .physical = a.physical, .logical = a.logical, .node_id = a.node_id };
    const b_ts = hlc.HLC{ .physical = b.physical, .logical = b.logical, .node_id = b.node_id };
    return switch (a_ts.compare(b_ts)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

/// Serialize HLC to 16 bytes.
export fn hif_hlc_to_bytes(ts: *const HifHLC, out: *[16]u8) void {
    const hlc_ts = hlc.HLC{ .physical = ts.physical, .logical = ts.logical, .node_id = ts.node_id };
    out.* = hlc_ts.toBytes();
}

/// Deserialize HLC from 16 bytes.
export fn hif_hlc_from_bytes(data: *const [16]u8, out: *HifHLC) void {
    const ts = hlc.HLC.fromBytes(data);
    out.* = .{ .physical = ts.physical, .logical = ts.logical, .node_id = ts.node_id };
}

// ============================================================================
// Tests
// ============================================================================

test "hif_hash produces correct output" {
    var out: [32]u8 = undefined;
    hif_hash("hello", 5, &out);

    // Verify it matches the Zig hash
    const expected = hash.hash("hello");
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "hif_hash_blob produces correct output" {
    var out: [32]u8 = undefined;
    hif_hash_blob("content", 7, &out);

    const expected = hash.hashBlob("content");
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "hif_hash_format_hex and hif_hash_parse_hex roundtrip" {
    var h: [32]u8 = undefined;
    hif_hash("test", 4, &h);

    var hex: [64]u8 = undefined;
    hif_hash_format_hex(&h, &hex);

    var parsed: [32]u8 = undefined;
    const result = hif_hash_parse_hex(&hex, 64, &parsed);
    try std.testing.expectEqual(@as(c_int, 0), result);
    try std.testing.expectEqualSlices(u8, &h, &parsed);
}

test "hif_hash_parse_hex rejects invalid input" {
    var out: [32]u8 = undefined;
    // Wrong length
    try std.testing.expectEqual(@as(c_int, -1), hif_hash_parse_hex("abc", 3, &out));
    // Invalid hex
    var invalid: [64]u8 = undefined;
    @memset(&invalid, 'g');
    try std.testing.expectEqual(@as(c_int, -1), hif_hash_parse_hex(&invalid, 64, &out));
}

test "hif_bloom lifecycle" {
    const alloc = hif_allocator_c();

    const b = hif_bloom_new(alloc, 100, 0.01) orelse unreachable;
    defer hif_bloom_free(alloc, b);

    hif_bloom_add(b, "test/path.zig", 13);
    try std.testing.expectEqual(@as(c_int, 1), hif_bloom_may_contain(b, "test/path.zig", 13));
}

test "hif_bloom serialize/deserialize" {
    const alloc = hif_allocator_c();

    const b1 = hif_bloom_new(alloc, 100, 0.01) orelse unreachable;
    defer hif_bloom_free(alloc, b1);

    hif_bloom_add(b1, "path", 4);

    var len: usize = 0;
    const data = hif_bloom_serialize(alloc, b1, &len) orelse unreachable;
    defer hif_free(alloc, data, len);

    const b2 = hif_bloom_deserialize(alloc, data, len) orelse unreachable;
    defer hif_bloom_free(alloc, b2);

    try std.testing.expectEqual(@as(c_int, 1), hif_bloom_may_contain(b2, "path", 4));
}

test "hif_clock lifecycle" {
    const alloc = hif_allocator_c();

    const clock = hif_clock_new(alloc, 42) orelse unreachable;
    defer hif_clock_free(alloc, clock);

    var ts: HifHLC = undefined;
    hif_clock_now_with_wall(clock, 1000, &ts);

    try std.testing.expectEqual(@as(i64, 1000), ts.physical);
    try std.testing.expectEqual(@as(u32, 0), ts.logical);
    try std.testing.expectEqual(@as(u32, 42), ts.node_id);
}

test "hif_hlc_compare works correctly" {
    const a = HifHLC{ .physical = 100, .logical = 0, .node_id = 1 };
    const b = HifHLC{ .physical = 100, .logical = 1, .node_id = 1 };
    const c = HifHLC{ .physical = 100, .logical = 0, .node_id = 1 };

    try std.testing.expectEqual(@as(c_int, -1), hif_hlc_compare(&a, &b));
    try std.testing.expectEqual(@as(c_int, 1), hif_hlc_compare(&b, &a));
    try std.testing.expectEqual(@as(c_int, 0), hif_hlc_compare(&a, &c));
}

test "hif_hlc_to_bytes and hif_hlc_from_bytes roundtrip" {
    const original = HifHLC{ .physical = 1704067200000, .logical = 42, .node_id = 12345 };

    var bytes: [16]u8 = undefined;
    hif_hlc_to_bytes(&original, &bytes);

    var restored: HifHLC = undefined;
    hif_hlc_from_bytes(&bytes, &restored);

    try std.testing.expectEqual(original.physical, restored.physical);
    try std.testing.expectEqual(original.logical, restored.logical);
    try std.testing.expectEqual(original.node_id, restored.node_id);
}

test "hif_version returns version string" {
    const version = hif_version();
    try std.testing.expectEqualStrings("0.1.0", std.mem.span(version));
}

test "hif_abi_version returns 1" {
    try std.testing.expectEqual(@as(u32, 1), hif_abi_version());
}

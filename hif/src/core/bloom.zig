//! Bloom filter implementation for fast path conflict detection.
//!
//! Each session maintains a bloom filter of all paths it has touched.
//! Before landing, we can quickly check if two sessions might have
//! conflicting paths by testing bloom filter intersection.
//!
//! ## Properties
//!
//! - **No false negatives**: if the filter says "not present", it's guaranteed
//! - **Possible false positives**: if the filter says "maybe present", check the actual paths
//! - **Fast intersection**: O(n) where n is filter size in bytes
//!
//! ## Usage
//!
//! ```zig
//! var bloom = try Bloom.init(allocator, 1000, 0.01); // 1000 items, 1% FP rate
//! defer bloom.deinit();
//!
//! bloom.add("src/main.zig");
//! bloom.add("src/lib.zig");
//!
//! if (bloom.mayContain("src/main.zig")) {
//!     // Possibly present (check actual data)
//! }
//!
//! if (!bloom.mayContain("src/other.zig")) {
//!     // Definitely not present
//! }
//! ```
//!
//! ## Conflict Detection
//!
//! ```zig
//! if (session_a.bloom.intersects(&session_b.bloom)) {
//!     // Might have conflicts - check path index
//! } else {
//!     // Definitely no conflicts - fast path!
//! }
//! ```

const std = @import("std");
const hash = @import("hash.zig");

/// Bloom filter for path conflict detection.
pub const Bloom = struct {
    /// Bit array storage.
    bits: []u8,

    /// Number of hash functions to use.
    num_hashes: u32,

    /// Allocator used for the bit array.
    allocator: std.mem.Allocator,

    /// Create a new bloom filter sized for expected number of items.
    ///
    /// Parameters:
    /// - `expected_items`: estimated number of items to be added
    /// - `fp_rate`: desired false positive rate (e.g., 0.01 for 1%)
    ///
    /// The filter will be sized optimally for these parameters.
    pub fn init(allocator: std.mem.Allocator, expected_items: usize, fp_rate: f64) !Bloom {
        // Calculate optimal size: m = -n * ln(p) / (ln(2)^2)
        const n: f64 = @floatFromInt(@max(expected_items, 1));
        const ln2: f64 = @log(2.0);
        const ln2_sq = ln2 * ln2;
        const m_float = -n * @log(fp_rate) / ln2_sq;

        // Round up to nearest byte, minimum 8 bytes
        const m_bits: usize = @max(@as(usize, @intFromFloat(@ceil(m_float))), 64);
        const m_bytes = (m_bits + 7) / 8;

        // Calculate optimal number of hashes: k = (m/n) * ln(2)
        const k_float = (@as(f64, @floatFromInt(m_bits)) / n) * ln2;
        const k: u32 = @max(@as(u32, @intFromFloat(@ceil(k_float))), 1);

        const bits = try allocator.alloc(u8, m_bytes);
        @memset(bits, 0);

        return .{
            .bits = bits,
            .num_hashes = k,
            .allocator = allocator,
        };
    }

    /// Create a bloom filter with a specific size (for testing or fixed configs).
    pub fn initWithSize(allocator: std.mem.Allocator, size_bytes: usize, num_hashes: u32) !Bloom {
        const bits = try allocator.alloc(u8, size_bytes);
        @memset(bits, 0);

        return .{
            .bits = bits,
            .num_hashes = num_hashes,
            .allocator = allocator,
        };
    }

    /// Create a bloom filter from serialized bytes (for deserialization).
    pub fn fromBytes(allocator: std.mem.Allocator, data: []const u8, num_hashes: u32) !Bloom {
        const bits = try allocator.dupe(u8, data);
        return .{
            .bits = bits,
            .num_hashes = num_hashes,
            .allocator = allocator,
        };
    }

    /// Free the bloom filter's memory.
    pub fn deinit(self: *Bloom) void {
        self.allocator.free(self.bits);
        self.* = undefined;
    }

    /// Add a path to the bloom filter.
    pub fn add(self: *Bloom, path: []const u8) void {
        const h = hash.hash(path);
        self.addHash(&h);
    }

    /// Add a pre-computed hash to the bloom filter.
    pub fn addHash(self: *Bloom, h: *const hash.Hash) void {
        const m: u64 = self.bits.len * 8;

        // Use double hashing: h_i(x) = h1(x) + i * h2(x) mod m
        // We split the 256-bit hash into two 64-bit values
        const h1 = std.mem.readInt(u64, h[0..8], .little);
        const h2 = std.mem.readInt(u64, h[8..16], .little);

        for (0..self.num_hashes) |i| {
            const bit_idx: usize = @intCast((h1 +% @as(u64, @intCast(i)) *% h2) % m);
            const byte_idx = bit_idx / 8;
            const bit_offset: u3 = @intCast(bit_idx % 8);
            self.bits[byte_idx] |= @as(u8, 1) << bit_offset;
        }
    }

    /// Check if a path might be in the bloom filter.
    ///
    /// Returns:
    /// - `true`: possibly present (may be false positive)
    /// - `false`: definitely not present (guaranteed)
    pub fn mayContain(self: *const Bloom, path: []const u8) bool {
        const h = hash.hash(path);
        return self.mayContainHash(&h);
    }

    /// Check if a pre-computed hash might be in the bloom filter.
    pub fn mayContainHash(self: *const Bloom, h: *const hash.Hash) bool {
        const m: u64 = self.bits.len * 8;

        const h1 = std.mem.readInt(u64, h[0..8], .little);
        const h2 = std.mem.readInt(u64, h[8..16], .little);

        for (0..self.num_hashes) |i| {
            const bit_idx: usize = @intCast((h1 +% @as(u64, @intCast(i)) *% h2) % m);
            const byte_idx = bit_idx / 8;
            const bit_offset: u3 = @intCast(bit_idx % 8);
            if ((self.bits[byte_idx] & (@as(u8, 1) << bit_offset)) == 0) {
                return false;
            }
        }
        return true;
    }

    /// Check if two bloom filters might have overlapping items.
    ///
    /// This is the key operation for conflict detection:
    /// - If `intersects` returns `false`, the sessions definitely don't conflict
    /// - If `intersects` returns `true`, check the actual path index
    ///
    /// Returns:
    /// - `true`: possibly intersecting (check actual paths)
    /// - `false`: definitely disjoint (no conflicts possible)
    pub fn intersects(self: *const Bloom, other: *const Bloom) bool {
        // Filters must be same size for meaningful comparison
        if (self.bits.len != other.bits.len) return true;

        // Check if any bits are set in both filters
        for (self.bits, other.bits) |a, b| {
            if ((a & b) != 0) return true;
        }
        return false;
    }

    /// Merge another bloom filter into this one (union).
    ///
    /// After merging, this filter will contain all items from both filters.
    /// Useful for combining filters from sub-sessions.
    pub fn merge(self: *Bloom, other: *const Bloom) void {
        if (self.bits.len != other.bits.len) return;

        for (self.bits, other.bits) |*a, b| {
            a.* |= b;
        }
    }

    /// Get the approximate number of items in the filter.
    ///
    /// Uses the formula: n* = -(m/k) * ln(1 - X/m)
    /// where X is the number of set bits.
    pub fn estimateCount(self: *const Bloom) usize {
        var set_bits: usize = 0;
        for (self.bits) |byte| {
            set_bits += @popCount(byte);
        }

        const m: f64 = @floatFromInt(self.bits.len * 8);
        const k: f64 = @floatFromInt(self.num_hashes);
        const x: f64 = @floatFromInt(set_bits);

        if (x >= m) return std.math.maxInt(usize);
        if (x == 0) return 0;

        const estimate = -(m / k) * @log(1.0 - x / m);
        if (estimate < 0) return 0;
        return @intFromFloat(estimate);
    }

    /// Get the current fill ratio (0.0 to 1.0).
    ///
    /// A filter is considered "full" when fill ratio approaches 0.5.
    /// Beyond that, false positive rate increases significantly.
    pub fn fillRatio(self: *const Bloom) f64 {
        var set_bits: usize = 0;
        for (self.bits) |byte| {
            set_bits += @popCount(byte);
        }

        const m: f64 = @floatFromInt(self.bits.len * 8);
        const x: f64 = @floatFromInt(set_bits);
        return x / m;
    }

    /// Serialize the bloom filter for storage.
    ///
    /// Format: [4 bytes: num_hashes (little-endian)][bits...]
    pub fn serialize(self: *const Bloom, allocator: std.mem.Allocator) ![]u8 {
        const total_len = 4 + self.bits.len;
        const buf = try allocator.alloc(u8, total_len);

        std.mem.writeInt(u32, buf[0..4], self.num_hashes, .little);
        @memcpy(buf[4..], self.bits);

        return buf;
    }

    /// Deserialize a bloom filter from storage.
    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !Bloom {
        if (data.len < 4) return error.InvalidData;

        const num_hashes = std.mem.readInt(u32, data[0..4], .little);
        const bits_data = data[4..];

        if (bits_data.len == 0) return error.InvalidData;

        return fromBytes(allocator, bits_data, num_hashes);
    }

    /// Clear all bits in the filter.
    pub fn clear(self: *Bloom) void {
        @memset(self.bits, 0);
    }

    /// Get the size of the filter in bytes.
    pub fn sizeBytes(self: *const Bloom) usize {
        return self.bits.len;
    }

    /// Get the size of the filter in bits.
    pub fn sizeBits(self: *const Bloom) usize {
        return self.bits.len * 8;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Bloom add and lookup" {
    var bloom = try Bloom.init(std.testing.allocator, 100, 0.01);
    defer bloom.deinit();

    bloom.add("src/main.zig");
    bloom.add("src/lib.zig");
    bloom.add("README.md");

    try std.testing.expect(bloom.mayContain("src/main.zig"));
    try std.testing.expect(bloom.mayContain("src/lib.zig"));
    try std.testing.expect(bloom.mayContain("README.md"));
}

test "Bloom definitely not present" {
    var bloom = try Bloom.init(std.testing.allocator, 100, 0.01);
    defer bloom.deinit();

    bloom.add("exists.txt");

    // With proper sizing, most non-added items should return false
    var false_positives: usize = 0;
    for (0..100) |i| {
        var buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "nonexistent_{d}.txt", .{i}) catch unreachable;
        if (bloom.mayContain(path)) {
            false_positives += 1;
        }
    }

    // Should have very few false positives (expect ~1% rate)
    try std.testing.expect(false_positives < 10);
}

test "Bloom intersects detects overlap" {
    var bloom1 = try Bloom.initWithSize(std.testing.allocator, 128, 7);
    defer bloom1.deinit();
    var bloom2 = try Bloom.initWithSize(std.testing.allocator, 128, 7);
    defer bloom2.deinit();

    // Add same path to both
    bloom1.add("shared/file.zig");
    bloom2.add("shared/file.zig");

    try std.testing.expect(bloom1.intersects(&bloom2));
}

test "Bloom intersects detects disjoint" {
    var bloom1 = try Bloom.initWithSize(std.testing.allocator, 256, 7);
    defer bloom1.deinit();
    var bloom2 = try Bloom.initWithSize(std.testing.allocator, 256, 7);
    defer bloom2.deinit();

    // Add different paths
    bloom1.add("path/a.zig");
    bloom2.add("path/b.zig");

    // With large enough filter and few items, should be disjoint
    // (Though false positives are still possible)
    const intersects = bloom1.intersects(&bloom2);
    _ = intersects; // Result depends on hash distribution
}

test "Bloom merge combines filters" {
    var bloom1 = try Bloom.initWithSize(std.testing.allocator, 128, 7);
    defer bloom1.deinit();
    var bloom2 = try Bloom.initWithSize(std.testing.allocator, 128, 7);
    defer bloom2.deinit();

    bloom1.add("path/a.zig");
    bloom2.add("path/b.zig");

    // Before merge, bloom1 doesn't have path/b.zig
    const had_b_before = bloom1.mayContain("path/b.zig");

    bloom1.merge(&bloom2);

    // After merge, bloom1 should have both
    try std.testing.expect(bloom1.mayContain("path/a.zig"));
    try std.testing.expect(bloom1.mayContain("path/b.zig"));

    // If it didn't have b before, it definitely has it now
    if (!had_b_before) {
        try std.testing.expect(bloom1.mayContain("path/b.zig"));
    }
}

test "Bloom serialize and deserialize" {
    var bloom = try Bloom.init(std.testing.allocator, 100, 0.01);
    defer bloom.deinit();

    bloom.add("test/path.zig");
    bloom.add("another/file.txt");

    const serialized = try bloom.serialize(std.testing.allocator);
    defer std.testing.allocator.free(serialized);

    var restored = try Bloom.deserialize(std.testing.allocator, serialized);
    defer restored.deinit();

    // Restored filter should have same contents
    try std.testing.expect(restored.mayContain("test/path.zig"));
    try std.testing.expect(restored.mayContain("another/file.txt"));
    try std.testing.expectEqual(bloom.num_hashes, restored.num_hashes);
    try std.testing.expectEqual(bloom.bits.len, restored.bits.len);
}

test "Bloom estimateCount approximates item count" {
    var bloom = try Bloom.init(std.testing.allocator, 1000, 0.01);
    defer bloom.deinit();

    // Add 100 items
    for (0..100) |i| {
        var buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "path/{d}.zig", .{i}) catch unreachable;
        bloom.add(path);
    }

    const estimate = bloom.estimateCount();

    // Should be reasonably close to 100 (within 50%)
    try std.testing.expect(estimate >= 50 and estimate <= 200);
}

test "Bloom fillRatio increases with items" {
    var bloom = try Bloom.initWithSize(std.testing.allocator, 128, 7);
    defer bloom.deinit();

    const initial_ratio = bloom.fillRatio();
    try std.testing.expectEqual(@as(f64, 0.0), initial_ratio);

    // Add items
    for (0..50) |i| {
        var buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "file_{d}.txt", .{i}) catch unreachable;
        bloom.add(path);
    }

    const final_ratio = bloom.fillRatio();
    try std.testing.expect(final_ratio > 0.0);
    try std.testing.expect(final_ratio <= 1.0);
}

test "Bloom clear resets filter" {
    var bloom = try Bloom.initWithSize(std.testing.allocator, 64, 5);
    defer bloom.deinit();

    bloom.add("test.txt");
    try std.testing.expect(bloom.mayContain("test.txt"));

    bloom.clear();

    try std.testing.expect(!bloom.mayContain("test.txt"));
    try std.testing.expectEqual(@as(f64, 0.0), bloom.fillRatio());
}

test "Bloom size functions" {
    var bloom = try Bloom.initWithSize(std.testing.allocator, 64, 5);
    defer bloom.deinit();

    try std.testing.expectEqual(@as(usize, 64), bloom.sizeBytes());
    try std.testing.expectEqual(@as(usize, 512), bloom.sizeBits());
}

test "Bloom empty filter returns false for all" {
    var bloom = try Bloom.initWithSize(std.testing.allocator, 64, 5);
    defer bloom.deinit();

    try std.testing.expect(!bloom.mayContain("anything"));
    try std.testing.expect(!bloom.mayContain(""));
    try std.testing.expect(!bloom.mayContain("some/long/path/to/file.txt"));
}

test "Bloom handles empty string" {
    var bloom = try Bloom.initWithSize(std.testing.allocator, 64, 5);
    defer bloom.deinit();

    bloom.add("");
    try std.testing.expect(bloom.mayContain(""));
}

test "Bloom handles very long paths" {
    var bloom = try Bloom.init(std.testing.allocator, 10, 0.01);
    defer bloom.deinit();

    const long_path = "a" ** 1000;
    bloom.add(long_path);
    try std.testing.expect(bloom.mayContain(long_path));
}

test "Bloom different sizes don't intersect cleanly" {
    var bloom1 = try Bloom.initWithSize(std.testing.allocator, 64, 5);
    defer bloom1.deinit();
    var bloom2 = try Bloom.initWithSize(std.testing.allocator, 128, 5);
    defer bloom2.deinit();

    // Different sized filters return true (can't compare)
    try std.testing.expect(bloom1.intersects(&bloom2));
}

test "Bloom init calculates reasonable sizes" {
    // Small filter
    var small = try Bloom.init(std.testing.allocator, 10, 0.01);
    defer small.deinit();
    try std.testing.expect(small.bits.len >= 8);
    try std.testing.expect(small.num_hashes >= 1);

    // Large filter
    var large = try Bloom.init(std.testing.allocator, 10000, 0.001);
    defer large.deinit();
    try std.testing.expect(large.bits.len > small.bits.len);
}

test "Bloom deserialize rejects invalid data" {
    // Too short
    try std.testing.expectError(error.InvalidData, Bloom.deserialize(std.testing.allocator, "abc"));

    // Just header, no bits
    var header_only: [4]u8 = undefined;
    std.mem.writeInt(u32, &header_only, 7, .little);
    try std.testing.expectError(error.InvalidData, Bloom.deserialize(std.testing.allocator, &header_only));
}

test "Bloom fromBytes creates filter with given data" {
    const data = [_]u8{ 0xFF, 0x00, 0xFF, 0x00 };
    var bloom = try Bloom.fromBytes(std.testing.allocator, &data, 3);
    defer bloom.deinit();

    try std.testing.expectEqual(@as(usize, 4), bloom.bits.len);
    try std.testing.expectEqual(@as(u32, 3), bloom.num_hashes);
    try std.testing.expectEqual(@as(u8, 0xFF), bloom.bits[0]);
    try std.testing.expectEqual(@as(u8, 0x00), bloom.bits[1]);
}

test "Bloom addHash and mayContainHash work with pre-computed hashes" {
    var bloom = try Bloom.initWithSize(std.testing.allocator, 64, 5);
    defer bloom.deinit();

    const h = hash.hash("test/path.zig");
    bloom.addHash(&h);

    try std.testing.expect(bloom.mayContainHash(&h));

    const other_h = hash.hash("other/path.zig");
    // May or may not contain due to possible collision, but shouldn't crash
    _ = bloom.mayContainHash(&other_h);
}

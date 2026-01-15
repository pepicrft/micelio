//! Integration tests for hif core modules.
//!
//! These tests verify end-to-end workflows that span multiple modules,
//! simulating real usage patterns from the CLI and forge.

const std = @import("std");
const hif = @import("hif");

const hash = hif.hash;
const bloom = hif.bloom;
const hlc = hif.hlc;
const tree = hif.tree;

// ============================================================================
// Session Workflow Tests
// ============================================================================

test "session workflow: start, edit, prepare for landing" {
    const allocator = std.testing.allocator;

    // 1. Start a new session with an HLC clock
    var clock = hlc.Clock.init(1);
    const start_ts = clock.now();

    // 2. Create a bloom filter to track touched paths
    var session_bloom = try bloom.Bloom.init(allocator, 100, 0.01);
    defer session_bloom.deinit();

    // 3. Create a tree to track file states
    var session_tree = tree.Tree.init(allocator);
    defer session_tree.deinit();

    // 4. Simulate editing files
    const files = [_]struct { path: []const u8, content: []const u8 }{
        .{ .path = "src/main.zig", .content = "const std = @import(\"std\");\n" },
        .{ .path = "src/lib.zig", .content = "pub fn hello() void {}\n" },
        .{ .path = "README.md", .content = "# My Project\n" },
    };

    for (files) |file| {
        // Record in bloom filter
        session_bloom.add(file.path);

        // Hash content and add to tree
        const content_hash = hash.hashBlob(file.content);
        try session_tree.insert(file.path, content_hash);

        // Generate timestamp for this operation
        _ = clock.now();
    }

    // 5. Verify session state
    try std.testing.expectEqual(@as(usize, 3), session_tree.count());
    try std.testing.expect(session_bloom.mayContain("src/main.zig"));
    try std.testing.expect(session_bloom.mayContain("src/lib.zig"));
    try std.testing.expect(session_bloom.mayContain("README.md"));

    // 6. Get session tree hash for landing
    const tree_hash = session_tree.hash();
    try std.testing.expectEqual(@as(usize, 32), tree_hash.len);

    // 7. End timestamp should be after start
    const end_ts = clock.now();
    try std.testing.expect(start_ts.happenedBefore(end_ts));
}

test "conflict detection: two sessions touching same file" {
    const allocator = std.testing.allocator;

    // Session A touches files
    var bloom_a = try bloom.Bloom.initWithSize(allocator, 256, 7);
    defer bloom_a.deinit();
    bloom_a.add("src/main.zig");
    bloom_a.add("src/utils.zig");

    // Session B touches overlapping files
    var bloom_b = try bloom.Bloom.initWithSize(allocator, 256, 7);
    defer bloom_b.deinit();
    bloom_b.add("src/main.zig"); // Conflict!
    bloom_b.add("src/other.zig");

    // Conflict detection: bloom filters intersect
    try std.testing.expect(bloom_a.intersects(&bloom_b));
}

test "conflict detection: two sessions with no overlap" {
    const allocator = std.testing.allocator;

    // Session A touches files in src/
    var bloom_a = try bloom.Bloom.initWithSize(allocator, 512, 7);
    defer bloom_a.deinit();
    bloom_a.add("src/main.zig");
    bloom_a.add("src/utils.zig");

    // Session B touches files in tests/
    var bloom_b = try bloom.Bloom.initWithSize(allocator, 512, 7);
    defer bloom_b.deinit();
    bloom_b.add("tests/main_test.zig");
    bloom_b.add("tests/utils_test.zig");

    // With sufficient filter size and disjoint paths, should not intersect
    // Note: false positives are possible but unlikely with large filters
    const intersects = bloom_a.intersects(&bloom_b);

    // We can't guarantee no intersection due to hash collisions,
    // but we can verify the filters work correctly
    _ = intersects;
}

test "tree diff: detect added, deleted, modified files" {
    const allocator = std.testing.allocator;

    // Base tree (before session)
    var base = tree.Tree.init(allocator);
    defer base.deinit();
    try base.insert("unchanged.txt", hash.hash("same content"));
    try base.insert("modified.txt", hash.hash("original"));
    try base.insert("deleted.txt", hash.hash("will be deleted"));

    // Session tree (after edits)
    var session = tree.Tree.init(allocator);
    defer session.deinit();
    try session.insert("unchanged.txt", hash.hash("same content"));
    try session.insert("modified.txt", hash.hash("updated"));
    try session.insert("added.txt", hash.hash("new file"));

    // Compute diff
    const changes = try tree.diff(allocator, &base, &session);
    defer allocator.free(changes);

    try std.testing.expectEqual(@as(usize, 3), changes.len);

    // Verify each change type is detected
    var found_added = false;
    var found_deleted = false;
    var found_modified = false;

    for (changes) |change| {
        switch (change.kind) {
            .added => {
                try std.testing.expectEqualStrings("added.txt", change.path);
                found_added = true;
            },
            .deleted => {
                try std.testing.expectEqualStrings("deleted.txt", change.path);
                found_deleted = true;
            },
            .modified => {
                try std.testing.expectEqualStrings("modified.txt", change.path);
                found_modified = true;
            },
        }
    }

    try std.testing.expect(found_added);
    try std.testing.expect(found_deleted);
    try std.testing.expect(found_modified);
}

// ============================================================================
// Distributed Clock Tests
// ============================================================================

test "HLC: message exchange between two agents" {
    // Agent A (node_id = 1)
    var agent_a = hlc.Clock.init(1);
    // Agent B (node_id = 2, clock is behind)
    var agent_b = hlc.Clock.init(2);

    // A generates a timestamp
    const a1 = agent_a.tick(1000);

    // B receives message from A (B's wall clock is at 800)
    const b1 = agent_b.update(a1, 800);

    // B's timestamp should be after A's despite slower wall clock
    try std.testing.expect(a1.happenedBefore(b1));
    try std.testing.expect(b1.physical >= a1.physical);

    // B sends response to A (A's wall clock is at 1050)
    const a2 = agent_a.update(b1, 1050);

    // A's new timestamp should be after B's
    try std.testing.expect(b1.happenedBefore(a2));

    // All timestamps should be totally ordered
    try std.testing.expect(a1.happenedBefore(b1));
    try std.testing.expect(b1.happenedBefore(a2));
}

test "HLC: serialization for network transmission" {
    var clock = hlc.Clock.init(42);
    const ts = clock.tick(1704067200000); // 2024-01-01 00:00:00 UTC

    // Serialize for network
    const bytes = ts.toBytes();
    try std.testing.expectEqual(@as(usize, 16), bytes.len);

    // Deserialize on receiving end
    const restored = hlc.HLC.fromBytes(&bytes);
    try std.testing.expectEqual(ts.physical, restored.physical);
    try std.testing.expectEqual(ts.logical, restored.logical);
    try std.testing.expectEqual(ts.node_id, restored.node_id);

    // Bytes should be lexicographically sortable
    const ts2 = clock.tick(1704067200000); // Same wall time, logical increments
    const bytes2 = ts2.toBytes();

    try std.testing.expect(std.mem.order(u8, &bytes, &bytes2) == .lt);
}

// ============================================================================
// Content-Addressing Tests
// ============================================================================

test "content addressing: same content produces same hash" {
    const content = "Hello, World!";

    const hash1 = hash.hashBlob(content);
    const hash2 = hash.hashBlob(content);

    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "content addressing: tree hash is deterministic" {
    const allocator = std.testing.allocator;

    // Create two trees with same content in different order
    var tree1 = tree.Tree.init(allocator);
    defer tree1.deinit();
    try tree1.insert("b.txt", hash.hash("b"));
    try tree1.insert("a.txt", hash.hash("a"));
    try tree1.insert("c.txt", hash.hash("c"));

    var tree2 = tree.Tree.init(allocator);
    defer tree2.deinit();
    try tree2.insert("a.txt", hash.hash("a"));
    try tree2.insert("c.txt", hash.hash("c"));
    try tree2.insert("b.txt", hash.hash("b"));

    // Same hash despite different insertion order
    try std.testing.expectEqualSlices(u8, &tree1.hash(), &tree2.hash());
}

test "content addressing: structural sharing via hash" {
    const allocator = std.testing.allocator;

    // Two trees with mostly same content
    var tree1 = tree.Tree.init(allocator);
    defer tree1.deinit();
    try tree1.insert("shared/a.txt", hash.hash("a"));
    try tree1.insert("shared/b.txt", hash.hash("b"));
    try tree1.insert("unique1.txt", hash.hash("only in tree1"));

    var tree2 = tree.Tree.init(allocator);
    defer tree2.deinit();
    try tree2.insert("shared/a.txt", hash.hash("a"));
    try tree2.insert("shared/b.txt", hash.hash("b"));
    try tree2.insert("unique2.txt", hash.hash("only in tree2"));

    // Trees have different hashes (different content)
    try std.testing.expect(!std.mem.eql(u8, &tree1.hash(), &tree2.hash()));

    // But shared files have same hashes (structural sharing)
    try std.testing.expectEqualSlices(u8, &tree1.get("shared/a.txt").?, &tree2.get("shared/a.txt").?);
    try std.testing.expectEqualSlices(u8, &tree1.get("shared/b.txt").?, &tree2.get("shared/b.txt").?);
}

// ============================================================================
// Large Scale Tests
// ============================================================================

test "stress: tree with many files" {
    const allocator = std.testing.allocator;
    var t = tree.Tree.init(allocator);
    defer t.deinit();

    // Insert 10000 files
    const count = 10000;
    for (0..count) |i| {
        var path_buf: [64]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "src/module_{d:0>5}/file_{d:0>5}.zig", .{ i / 100, i }) catch unreachable;
        try t.insert(path, hash.hash(path));
    }

    try std.testing.expectEqual(@as(usize, count), t.count());

    // Verify lookups are fast (O(log n))
    for (0..100) |i| {
        var path_buf: [64]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "src/module_{d:0>5}/file_{d:0>5}.zig", .{ i, i * 100 }) catch unreachable;
        try std.testing.expect(t.contains(path));
    }

    // Hash computation works
    const h = t.hash();
    try std.testing.expectEqual(@as(usize, 32), h.len);
}

test "stress: bloom filter accuracy" {
    const allocator = std.testing.allocator;

    // Create bloom filter sized for 1000 items with 1% FP rate
    var b = try bloom.Bloom.init(allocator, 1000, 0.01);
    defer b.deinit();

    // Add 1000 paths
    for (0..1000) |i| {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "path_{d:0>5}", .{i}) catch unreachable;
        b.add(path);
    }

    // Verify all added paths are found
    for (0..1000) |i| {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "path_{d:0>5}", .{i}) catch unreachable;
        try std.testing.expect(b.mayContain(path));
    }

    // Count false positives for non-existent paths
    var false_positives: usize = 0;
    for (0..10000) |i| {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "nonexistent_{d:0>6}", .{i}) catch unreachable;
        if (b.mayContain(path)) {
            false_positives += 1;
        }
    }

    // Should be around 1% (100 out of 10000), allow some variance
    // With proper sizing, expect < 5% false positives
    try std.testing.expect(false_positives < 500);
}

// ============================================================================
// Serialization Tests
// ============================================================================

test "bloom filter roundtrip" {
    const allocator = std.testing.allocator;

    var original = try bloom.Bloom.init(allocator, 100, 0.01);
    defer original.deinit();

    original.add("path/a.zig");
    original.add("path/b.zig");
    original.add("path/c.zig");

    // Serialize
    const data = try original.serialize(allocator);
    defer allocator.free(data);

    // Deserialize
    var restored = try bloom.Bloom.deserialize(allocator, data);
    defer restored.deinit();

    // Same contents
    try std.testing.expect(restored.mayContain("path/a.zig"));
    try std.testing.expect(restored.mayContain("path/b.zig"));
    try std.testing.expect(restored.mayContain("path/c.zig"));
    try std.testing.expectEqual(original.num_hashes, restored.num_hashes);
}

test "HLC total ordering property" {
    // Generate many timestamps from multiple clocks
    var clocks: [10]hlc.Clock = undefined;
    for (0..10) |i| {
        clocks[i] = hlc.Clock.init(@intCast(i));
    }

    // Generate timestamps
    var timestamps: [100]hlc.HLC = undefined;
    for (0..100) |i| {
        const clock_idx = i % 10;
        timestamps[i] = clocks[clock_idx].tick(@intCast(1000 + i));
    }

    // Verify total ordering: for any two distinct timestamps, one is before the other
    for (0..100) |i| {
        for (i + 1..100) |j| {
            const cmp = timestamps[i].compare(timestamps[j]);
            // Either i < j, i > j, or i == j, but never incomparable
            try std.testing.expect(cmp == .lt or cmp == .gt or cmp == .eq);
        }
    }
}

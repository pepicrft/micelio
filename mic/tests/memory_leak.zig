//! Memory leak detection tests for allocator-heavy components.

const std = @import("std");
const mic = @import("mic");

const bloom = mic.bloom;
const tree = mic.tree;
const hash = mic.hash;

test "memory leak: bloom filter lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var filter = try bloom.Bloom.init(allocator, 1024, 0.01);
        defer filter.deinit();

        for (0..1024) |i| {
            var buf: [32]u8 = undefined;
            const path = std.fmt.bufPrint(&buf, "path_{d:0>4}", .{i}) catch unreachable;
            filter.add(path);
        }

        const data = try filter.serialize(allocator);
        defer allocator.free(data);

        var restored = try bloom.Bloom.deserialize(allocator, data);
        defer restored.deinit();
    }

    try std.testing.expect(gpa.deinit() == .ok);
}

test "memory leak: tree diff lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    {
        var base = tree.Tree.init(allocator);
        defer base.deinit();
        try base.insert("alpha.txt", hash.hash("alpha"));
        try base.insert("beta.txt", hash.hash("beta"));
        try base.insert("delta.txt", hash.hash("delta"));

        var updated = tree.Tree.init(allocator);
        defer updated.deinit();
        try updated.insert("alpha.txt", hash.hash("alpha"));
        try updated.insert("beta.txt", hash.hash("beta v2"));
        try updated.insert("gamma.txt", hash.hash("gamma"));

        const changes = try tree.diff(allocator, &base, &updated);
        defer allocator.free(changes);
    }

    try std.testing.expect(gpa.deinit() == .ok);
}

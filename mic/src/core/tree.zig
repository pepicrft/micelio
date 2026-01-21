//! Prolly Tree: A content-addressed B+ tree for directory structures.
//!
//! Prolly trees combine the benefits of B+ trees (efficient lookups, insertions,
//! deletions) with content-addressing (structural sharing, deduplication).
//! They're used by systems like Dolt and Noms for versioned data.
//!
//! ## Key Properties
//!
//! - **Content-addressed**: Tree hash is derived from contents
//! - **Deterministic**: Same contents always produce same hash
//! - **O(log n) operations**: Insert, delete, and lookup are all logarithmic
//!
//! ## Performance
//!
//! | Operation | Complexity |
//! |-----------|------------|
//! | get       | O(log n)   |
//! | insert    | O(log n)   |
//! | delete    | O(log n)   |
//! | hash      | O(n) first call, O(1) cached |
//! | diff      | O(n + m)   |
//!
//! ## Usage
//!
//! ```zig
//! var tree = Tree.init(allocator);
//! defer tree.deinit();
//!
//! // Insert paths with their content hashes
//! try tree.insert("src/main.zig", file_hash);
//! try tree.insert("src/lib.zig", other_hash);
//!
//! // Lookup - O(log n)
//! if (tree.get("src/main.zig")) |h| {
//!     // Found, h is the content hash
//! }
//!
//! // Get tree hash (for storage/comparison)
//! const root_hash = tree.hash();
//! ```

const std = @import("std");
const hash_mod = @import("hash.zig");

const Hash = hash_mod.Hash;
const HASH_SIZE = hash_mod.HASH_SIZE;

/// A single entry in the tree (path -> content hash).
pub const Entry = struct {
    path: []const u8,
    content_hash: Hash,
};

/// B+ tree branching factor. Higher values = shallower tree but more comparisons per node.
/// 32 is a good balance for string keys of typical path lengths.
const B = 32;

/// Internal node in the B+ tree (keys + child pointers).
const InternalNode = struct {
    /// Keys (paths) that divide the children. keys[i] is the smallest key in children[i+1].
    keys: [B - 1][]const u8,
    keys_len: usize,
    /// Child node indices.
    children: [B]usize,
    children_len: usize,

    fn init() InternalNode {
        return .{
            .keys = undefined,
            .keys_len = 0,
            .children = undefined,
            .children_len = 0,
        };
    }

    fn keysSlice(self: *const InternalNode) []const []const u8 {
        return self.keys[0..self.keys_len];
    }

    fn childrenSlice(self: *const InternalNode) []const usize {
        return self.children[0..self.children_len];
    }
};

/// Leaf node in the B+ tree (actual entries).
const LeafNode = struct {
    /// Entries stored in this leaf (sorted by path).
    entries: [B]Entry,
    entries_len: usize,
    /// Index of next leaf for iteration (or null).
    next_leaf: ?usize,

    fn init() LeafNode {
        return .{
            .entries = undefined,
            .entries_len = 0,
            .next_leaf = null,
        };
    }

    fn entriesSlice(self: *const LeafNode) []const Entry {
        return self.entries[0..self.entries_len];
    }

    fn entriesSliceMut(self: *LeafNode) []Entry {
        return self.entries[0..self.entries_len];
    }
};

/// A node is either internal or a leaf.
const Node = union(enum) {
    internal: InternalNode,
    leaf: LeafNode,
};

/// Result of finding a parent node.
const ParentInfo = struct {
    parent_idx: ?usize,
    child_pos: usize,
};

/// A content-addressed B+ tree mapping paths to content hashes.
pub const Tree = struct {
    /// Node storage (arena-style).
    nodes: std.ArrayListUnmanaged(Node),

    /// Root node index (null for empty tree).
    root: ?usize,

    /// First leaf index for iteration.
    first_leaf: ?usize,

    /// Total entry count.
    entry_count: usize,

    /// Allocator for memory management.
    allocator: std.mem.Allocator,

    /// Cached root hash (invalidated on modification).
    cached_hash: ?Hash,

    /// Create an empty tree.
    pub fn init(allocator: std.mem.Allocator) Tree {
        return .{
            .nodes = .{},
            .root = null,
            .first_leaf = null,
            .entry_count = 0,
            .allocator = allocator,
            .cached_hash = null,
        };
    }

    /// Free the tree and all owned memory.
    pub fn deinit(self: *Tree) void {
        // Free all owned path strings
        for (self.nodes.items) |node| {
            switch (node) {
                .internal => |internal| {
                    for (internal.keysSlice()) |key| {
                        self.allocator.free(key);
                    }
                },
                .leaf => |leaf| {
                    for (leaf.entriesSlice()) |entry| {
                        self.allocator.free(entry.path);
                    }
                },
            }
        }
        self.nodes.deinit(self.allocator);
        self.* = undefined;
    }

    /// Insert or update a path with its content hash. O(log n).
    pub fn insert(self: *Tree, path: []const u8, content_hash: Hash) !void {
        self.cached_hash = null;

        if (self.root == null) {
            // Empty tree - create first leaf
            const leaf_idx = try self.allocateNode(.{ .leaf = LeafNode.init() });
            self.root = leaf_idx;
            self.first_leaf = leaf_idx;
        }

        // Find the leaf where this path should go
        const leaf_idx = self.findLeaf(path);
        var leaf = &self.nodes.items[leaf_idx].leaf;

        // Check if path already exists in this leaf
        for (leaf.entriesSliceMut()) |*entry| {
            if (std.mem.eql(u8, entry.path, path)) {
                // Update existing entry
                entry.content_hash = content_hash;
                return;
            }
        }

        // Need to insert new entry
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        if (leaf.entries_len < B) {
            // Room in leaf - insert in sorted position
            self.insertIntoLeaf(leaf_idx, owned_path, content_hash);
            self.entry_count += 1;
        } else {
            // Leaf is full - need to split
            try self.splitAndInsert(leaf_idx, owned_path, content_hash);
            self.entry_count += 1;
        }
    }

    /// Remove a path from the tree. O(log n).
    /// Returns true if the path was found and removed.
    pub fn delete(self: *Tree, path: []const u8) bool {
        if (self.root == null) return false;

        const leaf_idx = self.findLeaf(path);
        var leaf = &self.nodes.items[leaf_idx].leaf;

        // Find and remove the entry
        for (0..leaf.entries_len) |i| {
            if (std.mem.eql(u8, leaf.entries[i].path, path)) {
                self.allocator.free(leaf.entries[i].path);
                // Shift remaining entries
                var j = i;
                while (j + 1 < leaf.entries_len) : (j += 1) {
                    leaf.entries[j] = leaf.entries[j + 1];
                }
                leaf.entries_len -= 1;
                self.entry_count -= 1;
                self.cached_hash = null;

                // Note: We don't rebalance on delete for simplicity.
                // This is acceptable for version control where trees are
                // typically short-lived and rebuilt frequently.
                return true;
            }
        }

        return false;
    }

    /// Get the content hash for a path. O(log n).
    /// Returns null if the path doesn't exist.
    pub fn get(self: *const Tree, path: []const u8) ?Hash {
        if (self.root == null) return null;

        const leaf_idx = self.findLeaf(path);
        const leaf = &self.nodes.items[leaf_idx].leaf;

        // Binary search within the leaf
        const entries = leaf.entriesSlice();
        var left: usize = 0;
        var right: usize = entries.len;

        while (left < right) {
            const mid = left + (right - left) / 2;
            const cmp = std.mem.order(u8, entries[mid].path, path);

            switch (cmp) {
                .lt => left = mid + 1,
                .gt => right = mid,
                .eq => return entries[mid].content_hash,
            }
        }

        return null;
    }

    /// Check if a path exists in the tree. O(log n).
    pub fn contains(self: *const Tree, path: []const u8) bool {
        return self.get(path) != null;
    }

    /// Get the number of entries in the tree. O(1).
    pub fn count(self: *const Tree) usize {
        return self.entry_count;
    }

    /// Check if the tree is empty. O(1).
    pub fn isEmpty(self: *const Tree) bool {
        return self.entry_count == 0;
    }

    /// Compute the tree's content hash.
    ///
    /// The hash is computed by hashing all entries in sorted order.
    /// This ensures deterministic hashing regardless of insertion order.
    ///
    /// Note: This method caches the computed hash for performance. The cache
    /// is automatically invalidated when the tree is modified via insert()
    /// or delete(). This is a mutable operation despite having read semantics.
    pub fn hash(self: *Tree) Hash {
        if (self.cached_hash) |h| {
            return h;
        }

        var hasher = hash_mod.Hasher.init();
        hasher.update("tree\x00");

        // Iterate through all leaves in order
        var leaf_idx = self.first_leaf;
        while (leaf_idx) |idx| {
            const leaf = &self.nodes.items[idx].leaf;
            for (leaf.entriesSlice()) |entry| {
                hasher.update(entry.path);
                hasher.update("\x00");
                hasher.update(&entry.content_hash);
            }
            leaf_idx = leaf.next_leaf;
        }

        self.cached_hash = hasher.final();
        return self.cached_hash.?;
    }

    /// Get an iterator over all entries (in sorted order).
    pub fn iterator(self: *const Tree) EntryIterator {
        return EntryIterator.init(self);
    }

    /// Clone the tree.
    pub fn clone(self: *const Tree) !Tree {
        var new_tree = Tree.init(self.allocator);
        errdefer new_tree.deinit();

        var iter = self.iterator();
        while (iter.next()) |entry| {
            try new_tree.insert(entry.path, entry.content_hash);
        }

        return new_tree;
    }

    /// List all paths with a given prefix.
    pub fn listPrefix(self: *const Tree, prefix: []const u8, allocator: std.mem.Allocator) ![]const []const u8 {
        var result: std.ArrayListUnmanaged([]const u8) = .{};
        errdefer result.deinit(allocator);

        var iter = self.iterator();
        while (iter.next()) |entry| {
            if (std.mem.startsWith(u8, entry.path, prefix)) {
                try result.append(allocator, entry.path);
            }
        }

        return result.toOwnedSlice(allocator);
    }

    // ========================================================================
    // Private helpers
    // ========================================================================

    /// Allocate a new node and return its index.
    fn allocateNode(self: *Tree, node: Node) !usize {
        const idx = self.nodes.items.len;
        try self.nodes.append(self.allocator, node);
        return idx;
    }

    /// Find the leaf node where a path should be located.
    fn findLeaf(self: *const Tree, path: []const u8) usize {
        var node_idx = self.root.?;

        while (true) {
            switch (self.nodes.items[node_idx]) {
                .leaf => return node_idx,
                .internal => |internal| {
                    // Find the child to descend into
                    var child_idx: usize = 0;
                    for (internal.keysSlice(), 0..) |key, i| {
                        if (std.mem.order(u8, path, key) == .lt) {
                            break;
                        }
                        child_idx = i + 1;
                    }
                    node_idx = internal.children[child_idx];
                },
            }
        }
    }

    /// Insert an entry into a leaf (assumes there's room).
    fn insertIntoLeaf(self: *Tree, leaf_idx: usize, path: []const u8, content_hash: Hash) void {
        var leaf = &self.nodes.items[leaf_idx].leaf;
        const entry = Entry{ .path = path, .content_hash = content_hash };

        // Find insertion position
        var pos: usize = 0;
        for (leaf.entriesSlice(), 0..) |e, i| {
            if (std.mem.order(u8, path, e.path) == .lt) {
                pos = i;
                break;
            }
            pos = i + 1;
        }

        // Shift entries to make room
        var j = leaf.entries_len;
        while (j > pos) : (j -= 1) {
            leaf.entries[j] = leaf.entries[j - 1];
        }
        leaf.entries[pos] = entry;
        leaf.entries_len += 1;
    }

    /// Split a full leaf and insert the new entry.
    fn splitAndInsert(self: *Tree, leaf_idx: usize, path: []const u8, content_hash: Hash) !void {
        // Create a temporary array with all entries including the new one
        var all_entries: [B + 1]Entry = undefined;
        const leaf = &self.nodes.items[leaf_idx].leaf;

        var insert_pos: usize = 0;
        for (leaf.entriesSlice(), 0..) |e, i| {
            if (std.mem.order(u8, path, e.path) == .lt) {
                insert_pos = i;
                break;
            }
            insert_pos = i + 1;
        }

        // Copy entries before insertion point
        for (0..insert_pos) |i| {
            all_entries[i] = leaf.entries[i];
        }
        // Insert new entry
        all_entries[insert_pos] = Entry{ .path = path, .content_hash = content_hash };
        // Copy entries after insertion point
        for (insert_pos..leaf.entries_len) |i| {
            all_entries[i + 1] = leaf.entries[i];
        }

        const total = B + 1;
        const mid = total / 2;

        // Create new right leaf
        var new_leaf = LeafNode.init();
        new_leaf.next_leaf = leaf.next_leaf;

        // Distribute entries: left gets [0, mid), right gets [mid, total)
        self.nodes.items[leaf_idx].leaf.entries_len = 0;
        for (0..mid) |i| {
            self.nodes.items[leaf_idx].leaf.entries[i] = all_entries[i];
            self.nodes.items[leaf_idx].leaf.entries_len += 1;
        }
        for (mid..total) |i| {
            new_leaf.entries[i - mid] = all_entries[i];
            new_leaf.entries_len += 1;
        }

        const new_leaf_idx = try self.allocateNode(.{ .leaf = new_leaf });
        self.nodes.items[leaf_idx].leaf.next_leaf = new_leaf_idx;

        // Get the separator key (first key in new leaf)
        const separator = try self.allocator.dupe(u8, self.nodes.items[new_leaf_idx].leaf.entries[0].path);
        errdefer self.allocator.free(separator);

        // Insert separator into parent
        try self.insertIntoParent(leaf_idx, separator, new_leaf_idx);
    }

    /// Insert a separator key and new child into the parent of a node.
    fn insertIntoParent(self: *Tree, left_idx: usize, separator: []const u8, right_idx: usize) std.mem.Allocator.Error!void {
        // Find parent (simple approach: search from root)
        const parent_info = self.findParent(left_idx);

        if (parent_info.parent_idx == null) {
            // Node is root - create new root
            var new_root = InternalNode.init();
            new_root.keys[0] = separator;
            new_root.keys_len = 1;
            new_root.children[0] = left_idx;
            new_root.children[1] = right_idx;
            new_root.children_len = 2;

            const new_root_idx = try self.allocateNode(.{ .internal = new_root });
            self.root = new_root_idx;
            return;
        }

        const parent_idx = parent_info.parent_idx.?;
        var parent = &self.nodes.items[parent_idx].internal;

        if (parent.keys_len < B - 1) {
            // Room in parent - insert key and child
            const pos = parent_info.child_pos;

            // Shift keys
            var j = parent.keys_len;
            while (j > pos) : (j -= 1) {
                parent.keys[j] = parent.keys[j - 1];
            }
            parent.keys[pos] = separator;
            parent.keys_len += 1;

            // Shift children
            j = parent.children_len;
            while (j > pos + 1) : (j -= 1) {
                parent.children[j] = parent.children[j - 1];
            }
            parent.children[pos + 1] = right_idx;
            parent.children_len += 1;
        } else {
            // Parent is full - need to split it too
            try self.splitInternal(parent_idx, parent_info.child_pos, separator, right_idx);
        }
    }

    /// Find the parent of a node.
    fn findParent(self: *const Tree, target_idx: usize) ParentInfo {
        if (self.root.? == target_idx) {
            return .{ .parent_idx = null, .child_pos = 0 };
        }

        return self.findParentRecursive(self.root.?, target_idx);
    }

    fn findParentRecursive(self: *const Tree, current_idx: usize, target_idx: usize) ParentInfo {
        switch (self.nodes.items[current_idx]) {
            .leaf => return .{ .parent_idx = null, .child_pos = 0 },
            .internal => |internal| {
                for (0..internal.children_len) |pos| {
                    if (internal.children[pos] == target_idx) {
                        return .{ .parent_idx = current_idx, .child_pos = pos };
                    }
                }
                // Recurse into children
                for (0..internal.children_len) |i| {
                    const result = self.findParentRecursive(internal.children[i], target_idx);
                    if (result.parent_idx != null) {
                        return result;
                    }
                }
                return .{ .parent_idx = null, .child_pos = 0 };
            },
        }
    }

    /// Split a full internal node.
    fn splitInternal(self: *Tree, node_idx: usize, insert_pos: usize, separator: []const u8, new_child_idx: usize) std.mem.Allocator.Error!void {
        const node = &self.nodes.items[node_idx].internal;

        // Create temporary arrays with all keys and children
        var all_keys: [B][]const u8 = undefined;
        var all_children: [B + 1]usize = undefined;

        // Copy keys before insertion point
        for (0..insert_pos) |i| {
            all_keys[i] = node.keys[i];
        }
        all_keys[insert_pos] = separator;
        for (insert_pos..node.keys_len) |i| {
            all_keys[i + 1] = node.keys[i];
        }

        // Copy children before insertion point
        for (0..insert_pos + 1) |i| {
            all_children[i] = node.children[i];
        }
        all_children[insert_pos + 1] = new_child_idx;
        for (insert_pos + 1..node.children_len) |i| {
            all_children[i + 1] = node.children[i];
        }

        const total_keys = B;
        const mid = total_keys / 2;

        // The middle key goes up to the parent
        const promote_key = all_keys[mid];

        // Create new right node
        var new_node = InternalNode.init();

        // Left node gets [0, mid) keys and [0, mid+1) children
        self.nodes.items[node_idx].internal.keys_len = 0;
        self.nodes.items[node_idx].internal.children_len = 0;
        for (0..mid) |i| {
            self.nodes.items[node_idx].internal.keys[i] = all_keys[i];
            self.nodes.items[node_idx].internal.keys_len += 1;
        }
        for (0..mid + 1) |i| {
            self.nodes.items[node_idx].internal.children[i] = all_children[i];
            self.nodes.items[node_idx].internal.children_len += 1;
        }

        // Right node gets [mid+1, total) keys and [mid+1, total+1) children
        for (mid + 1..total_keys) |i| {
            new_node.keys[i - mid - 1] = all_keys[i];
            new_node.keys_len += 1;
        }
        for (mid + 1..total_keys + 1) |i| {
            new_node.children[i - mid - 1] = all_children[i];
            new_node.children_len += 1;
        }

        const new_node_idx = try self.allocateNode(.{ .internal = new_node });

        // Insert promoted key into parent
        try self.insertIntoParent(node_idx, promote_key, new_node_idx);
    }
};

/// Iterator over tree entries.
pub const EntryIterator = struct {
    tree: *const Tree,
    leaf_idx: ?usize,
    entry_idx: usize,

    fn init(tree: *const Tree) EntryIterator {
        return .{
            .tree = tree,
            .leaf_idx = tree.first_leaf,
            .entry_idx = 0,
        };
    }

    pub fn next(self: *EntryIterator) ?Entry {
        while (self.leaf_idx) |idx| {
            const leaf = &self.tree.nodes.items[idx].leaf;
            if (self.entry_idx < leaf.entries_len) {
                const entry = leaf.entries[self.entry_idx];
                self.entry_idx += 1;
                return entry;
            }
            // Move to next leaf
            self.leaf_idx = leaf.next_leaf;
            self.entry_idx = 0;
        }
        return null;
    }
};

/// Compute the difference between two trees.
pub const DiffEntry = struct {
    path: []const u8,
    kind: DiffKind,
    old_hash: ?Hash,
    new_hash: ?Hash,
};

pub const DiffKind = enum {
    added,
    deleted,
    modified,
};

/// Compute the difference between two trees. O(n + m).
///
/// Returns a list of paths that differ, with their change type.
/// The caller owns the returned slice and must free it.
pub fn diff(allocator: std.mem.Allocator, old: *const Tree, new: *const Tree) ![]DiffEntry {
    var result: std.ArrayListUnmanaged(DiffEntry) = .{};
    errdefer result.deinit(allocator);

    var old_iter = old.iterator();
    var new_iter = new.iterator();

    var old_entry = old_iter.next();
    var new_entry = new_iter.next();

    while (old_entry != null or new_entry != null) {
        if (old_entry == null) {
            // Only new has entries left - all are additions
            try result.append(allocator, .{
                .path = new_entry.?.path,
                .kind = .added,
                .old_hash = null,
                .new_hash = new_entry.?.content_hash,
            });
            new_entry = new_iter.next();
        } else if (new_entry == null) {
            // Only old has entries left - all are deletions
            try result.append(allocator, .{
                .path = old_entry.?.path,
                .kind = .deleted,
                .old_hash = old_entry.?.content_hash,
                .new_hash = null,
            });
            old_entry = old_iter.next();
        } else {
            const cmp = std.mem.order(u8, old_entry.?.path, new_entry.?.path);
            switch (cmp) {
                .lt => {
                    // Path only in old - deleted
                    try result.append(allocator, .{
                        .path = old_entry.?.path,
                        .kind = .deleted,
                        .old_hash = old_entry.?.content_hash,
                        .new_hash = null,
                    });
                    old_entry = old_iter.next();
                },
                .gt => {
                    // Path only in new - added
                    try result.append(allocator, .{
                        .path = new_entry.?.path,
                        .kind = .added,
                        .old_hash = null,
                        .new_hash = new_entry.?.content_hash,
                    });
                    new_entry = new_iter.next();
                },
                .eq => {
                    // Path in both - check if modified
                    if (!std.mem.eql(u8, &old_entry.?.content_hash, &new_entry.?.content_hash)) {
                        try result.append(allocator, .{
                            .path = old_entry.?.path,
                            .kind = .modified,
                            .old_hash = old_entry.?.content_hash,
                            .new_hash = new_entry.?.content_hash,
                        });
                    }
                    old_entry = old_iter.next();
                    new_entry = new_iter.next();
                },
            }
        }
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "Tree insert and get" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    const hash1 = hash_mod.hash("content1");
    const hash2 = hash_mod.hash("content2");

    try tree.insert("src/main.zig", hash1);
    try tree.insert("src/lib.zig", hash2);

    try std.testing.expectEqualSlices(u8, &hash1, &tree.get("src/main.zig").?);
    try std.testing.expectEqualSlices(u8, &hash2, &tree.get("src/lib.zig").?);
    try std.testing.expectEqual(@as(?Hash, null), tree.get("nonexistent"));
}

test "Tree insert updates existing" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    const hash1 = hash_mod.hash("content1");
    const hash2 = hash_mod.hash("content2");

    try tree.insert("file.txt", hash1);
    try std.testing.expectEqualSlices(u8, &hash1, &tree.get("file.txt").?);

    try tree.insert("file.txt", hash2);
    try std.testing.expectEqualSlices(u8, &hash2, &tree.get("file.txt").?);

    try std.testing.expectEqual(@as(usize, 1), tree.count());
}

test "Tree delete" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    const hash1 = hash_mod.hash("content1");
    try tree.insert("file.txt", hash1);

    try std.testing.expect(tree.contains("file.txt"));
    try std.testing.expect(tree.delete("file.txt"));
    try std.testing.expect(!tree.contains("file.txt"));
    try std.testing.expect(!tree.delete("file.txt")); // Already deleted
}

test "Tree count and isEmpty" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try std.testing.expect(tree.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), tree.count());

    try tree.insert("a.txt", hash_mod.hash("a"));
    try std.testing.expect(!tree.isEmpty());
    try std.testing.expectEqual(@as(usize, 1), tree.count());

    try tree.insert("b.txt", hash_mod.hash("b"));
    try std.testing.expectEqual(@as(usize, 2), tree.count());
}

test "Tree hash is deterministic" {
    var tree1 = Tree.init(std.testing.allocator);
    defer tree1.deinit();
    var tree2 = Tree.init(std.testing.allocator);
    defer tree2.deinit();

    const hash_a = hash_mod.hash("a");
    const hash_b = hash_mod.hash("b");

    // Insert in different order
    try tree1.insert("a.txt", hash_a);
    try tree1.insert("b.txt", hash_b);

    try tree2.insert("b.txt", hash_b);
    try tree2.insert("a.txt", hash_a);

    // Same hash regardless of insertion order
    try std.testing.expectEqualSlices(u8, &tree1.hash(), &tree2.hash());
}

test "Tree hash changes on modification" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.insert("file.txt", hash_mod.hash("v1"));
    const hash1 = tree.hash();

    try tree.insert("file.txt", hash_mod.hash("v2"));
    const hash2 = tree.hash();

    try std.testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "Tree hash is cached" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.insert("file.txt", hash_mod.hash("content"));

    const hash1 = tree.hash();
    const hash2 = tree.hash();

    // Should return same cached value
    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "Tree iterator" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.insert("c.txt", hash_mod.hash("c"));
    try tree.insert("a.txt", hash_mod.hash("a"));
    try tree.insert("b.txt", hash_mod.hash("b"));

    var iter = tree.iterator();
    var paths: [3][]const u8 = undefined;
    var i: usize = 0;

    while (iter.next()) |entry| {
        paths[i] = entry.path;
        i += 1;
    }

    // Should be sorted
    try std.testing.expectEqualStrings("a.txt", paths[0]);
    try std.testing.expectEqualStrings("b.txt", paths[1]);
    try std.testing.expectEqualStrings("c.txt", paths[2]);
}

test "Tree clone" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.insert("file.txt", hash_mod.hash("content"));

    var cloned = try tree.clone();
    defer cloned.deinit();

    try std.testing.expectEqualSlices(u8, &tree.hash(), &cloned.hash());
    try std.testing.expect(cloned.contains("file.txt"));
}

test "Tree listPrefix" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.insert("src/main.zig", hash_mod.hash("main"));
    try tree.insert("src/lib.zig", hash_mod.hash("lib"));
    try tree.insert("README.md", hash_mod.hash("readme"));

    const src_files = try tree.listPrefix("src/", std.testing.allocator);
    defer std.testing.allocator.free(src_files);

    try std.testing.expectEqual(@as(usize, 2), src_files.len);
}

test "diff added" {
    var old = Tree.init(std.testing.allocator);
    defer old.deinit();
    var new = Tree.init(std.testing.allocator);
    defer new.deinit();

    try new.insert("new_file.txt", hash_mod.hash("content"));

    const changes = try diff(std.testing.allocator, &old, &new);
    defer std.testing.allocator.free(changes);

    try std.testing.expectEqual(@as(usize, 1), changes.len);
    try std.testing.expectEqual(DiffKind.added, changes[0].kind);
    try std.testing.expectEqualStrings("new_file.txt", changes[0].path);
}

test "diff deleted" {
    var old = Tree.init(std.testing.allocator);
    defer old.deinit();
    var new = Tree.init(std.testing.allocator);
    defer new.deinit();

    try old.insert("old_file.txt", hash_mod.hash("content"));

    const changes = try diff(std.testing.allocator, &old, &new);
    defer std.testing.allocator.free(changes);

    try std.testing.expectEqual(@as(usize, 1), changes.len);
    try std.testing.expectEqual(DiffKind.deleted, changes[0].kind);
    try std.testing.expectEqualStrings("old_file.txt", changes[0].path);
}

test "diff modified" {
    var old = Tree.init(std.testing.allocator);
    defer old.deinit();
    var new = Tree.init(std.testing.allocator);
    defer new.deinit();

    try old.insert("file.txt", hash_mod.hash("v1"));
    try new.insert("file.txt", hash_mod.hash("v2"));

    const changes = try diff(std.testing.allocator, &old, &new);
    defer std.testing.allocator.free(changes);

    try std.testing.expectEqual(@as(usize, 1), changes.len);
    try std.testing.expectEqual(DiffKind.modified, changes[0].kind);
    try std.testing.expectEqualStrings("file.txt", changes[0].path);
}

test "diff unchanged" {
    var old = Tree.init(std.testing.allocator);
    defer old.deinit();
    var new = Tree.init(std.testing.allocator);
    defer new.deinit();

    const h = hash_mod.hash("same content");
    try old.insert("file.txt", h);
    try new.insert("file.txt", h);

    const changes = try diff(std.testing.allocator, &old, &new);
    defer std.testing.allocator.free(changes);

    try std.testing.expectEqual(@as(usize, 0), changes.len);
}

test "diff complex" {
    var old = Tree.init(std.testing.allocator);
    defer old.deinit();
    var new = Tree.init(std.testing.allocator);
    defer new.deinit();

    try old.insert("deleted.txt", hash_mod.hash("d"));
    try old.insert("modified.txt", hash_mod.hash("m1"));
    try old.insert("unchanged.txt", hash_mod.hash("u"));

    try new.insert("added.txt", hash_mod.hash("a"));
    try new.insert("modified.txt", hash_mod.hash("m2"));
    try new.insert("unchanged.txt", hash_mod.hash("u"));

    const changes = try diff(std.testing.allocator, &old, &new);
    defer std.testing.allocator.free(changes);

    try std.testing.expectEqual(@as(usize, 3), changes.len);

    // Changes are sorted by path
    try std.testing.expectEqual(DiffKind.added, changes[0].kind);
    try std.testing.expectEqualStrings("added.txt", changes[0].path);

    try std.testing.expectEqual(DiffKind.deleted, changes[1].kind);
    try std.testing.expectEqualStrings("deleted.txt", changes[1].path);

    try std.testing.expectEqual(DiffKind.modified, changes[2].kind);
    try std.testing.expectEqualStrings("modified.txt", changes[2].path);
}

test "Tree empty hash is consistent" {
    var tree1 = Tree.init(std.testing.allocator);
    defer tree1.deinit();
    var tree2 = Tree.init(std.testing.allocator);
    defer tree2.deinit();

    try std.testing.expectEqualSlices(u8, &tree1.hash(), &tree2.hash());
}

test "Tree handles empty path" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.insert("", hash_mod.hash("root"));
    try std.testing.expect(tree.contains(""));
}

test "Tree handles paths with special characters" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.insert("path/with spaces/file.txt", hash_mod.hash("1"));
    try tree.insert("path/with\ttab.txt", hash_mod.hash("2"));
    try tree.insert("unicode/文件.txt", hash_mod.hash("3"));

    try std.testing.expect(tree.contains("path/with spaces/file.txt"));
    try std.testing.expect(tree.contains("path/with\ttab.txt"));
    try std.testing.expect(tree.contains("unicode/文件.txt"));
}

test "Tree handles many entries (stress test)" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    // Insert 1000 entries to trigger multiple splits
    const count = 1000;
    for (0..count) |i| {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "file_{d:0>5}.txt", .{i}) catch unreachable;
        const h = hash_mod.hash(path);
        try tree.insert(path, h);
    }

    try std.testing.expectEqual(@as(usize, count), tree.count());

    // Verify all entries can be found
    for (0..count) |i| {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "file_{d:0>5}.txt", .{i}) catch unreachable;
        try std.testing.expect(tree.contains(path));
    }

    // Verify iteration returns all entries in order
    var iter = tree.iterator();
    var prev_path: ?[]const u8 = null;
    var iter_count: usize = 0;
    while (iter.next()) |entry| {
        if (prev_path) |p| {
            try std.testing.expect(std.mem.order(u8, p, entry.path) == .lt);
        }
        prev_path = entry.path;
        iter_count += 1;
    }
    try std.testing.expectEqual(count, iter_count);
}

test "Tree delete after many inserts" {
    var tree = Tree.init(std.testing.allocator);
    defer tree.deinit();

    // Insert 100 entries
    for (0..100) |i| {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "file_{d:0>3}.txt", .{i}) catch unreachable;
        try tree.insert(path, hash_mod.hash(path));
    }

    // Delete every other entry
    for (0..50) |i| {
        var path_buf: [32]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "file_{d:0>3}.txt", .{i * 2}) catch unreachable;
        try std.testing.expect(tree.delete(path));
    }

    try std.testing.expectEqual(@as(usize, 50), tree.count());

    // Verify remaining entries
    for (0..50) |i| {
        var path_buf: [32]u8 = undefined;
        const odd_path = std.fmt.bufPrint(&path_buf, "file_{d:0>3}.txt", .{i * 2 + 1}) catch unreachable;
        try std.testing.expect(tree.contains(odd_path));

        const even_path = std.fmt.bufPrint(&path_buf, "file_{d:0>3}.txt", .{i * 2}) catch unreachable;
        try std.testing.expect(!tree.contains(even_path));
    }
}

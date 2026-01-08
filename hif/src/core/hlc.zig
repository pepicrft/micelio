//! Hybrid Logical Clock (HLC) for distributed timestamp ordering.
//!
//! HLC combines physical and logical clocks to provide:
//! - Consistent ordering across distributed nodes
//! - Timestamps that never go backwards
//! - Causality tracking (if A happened before B, ts(A) < ts(B))
//!
//! Based on "Logical Physical Clocks and Consistent Snapshots in
//! Globally Distributed Databases" by Kulkarni et al.
//!
//! ## Usage
//!
//! ```zig
//! var clock = Clock.init(node_id);
//!
//! // Generate timestamp for local event
//! const ts = clock.now();
//!
//! // Update clock when receiving a message
//! const ts2 = clock.receive(incoming_timestamp);
//! ```
//!
//! ## Wire Format
//!
//! HLC serializes to 16 bytes (big-endian for lexicographic sorting):
//! - bytes 0-7: physical time (milliseconds since epoch)
//! - bytes 8-11: logical counter
//! - bytes 12-15: node ID

const std = @import("std");

/// Hybrid Logical Clock timestamp.
///
/// Total ordering: compare physical first, then logical, then node_id.
/// This ensures a deterministic order even when clocks are identical.
pub const HLC = struct {
    /// Physical time component (milliseconds since Unix epoch).
    physical: i64,

    /// Logical counter for events at the same physical time.
    /// Increments when physical time doesn't advance.
    logical: u32,

    /// Node identifier for tie-breaking between nodes.
    /// Must be unique per client/server instance.
    node_id: u32,

    /// Compare two HLC timestamps.
    /// Returns .lt, .eq, or .gt.
    pub fn compare(self: HLC, other: HLC) std.math.Order {
        if (self.physical < other.physical) return .lt;
        if (self.physical > other.physical) return .gt;

        if (self.logical < other.logical) return .lt;
        if (self.logical > other.logical) return .gt;

        if (self.node_id < other.node_id) return .lt;
        if (self.node_id > other.node_id) return .gt;

        return .eq;
    }

    /// Check if this timestamp happened before another.
    pub fn happenedBefore(self: HLC, other: HLC) bool {
        return self.compare(other) == .lt;
    }

    /// Check if this timestamp happened after another.
    pub fn happenedAfter(self: HLC, other: HLC) bool {
        return self.compare(other) == .gt;
    }

    /// Serialize to 16 bytes (big-endian for lexicographic sorting).
    pub fn toBytes(self: HLC) [16]u8 {
        var buf: [16]u8 = undefined;
        std.mem.writeInt(i64, buf[0..8], self.physical, .big);
        std.mem.writeInt(u32, buf[8..12], self.logical, .big);
        std.mem.writeInt(u32, buf[12..16], self.node_id, .big);
        return buf;
    }

    /// Deserialize from 16 bytes.
    pub fn fromBytes(buf: *const [16]u8) HLC {
        return .{
            .physical = std.mem.readInt(i64, buf[0..8], .big),
            .logical = std.mem.readInt(u32, buf[8..12], .big),
            .node_id = std.mem.readInt(u32, buf[12..16], .big),
        };
    }

    /// Format as a human-readable string for debugging.
    /// Format: "physical.logical@node" (e.g., "1704067200000.5@42")
    pub fn format(self: HLC, writer: anytype) !void {
        try writer.print("{d}.{d}@{d}", .{ self.physical, self.logical, self.node_id });
    }
};

/// HLC Clock that maintains state and generates timestamps.
///
/// Each node (agent, server, etc.) should have exactly one Clock instance.
/// The clock ensures timestamps are always monotonically increasing.
pub const Clock = struct {
    /// Last generated timestamp.
    last: HLC,

    /// This node's unique identifier.
    node_id: u32,

    /// Create a new clock with the given node ID.
    ///
    /// The node_id should be unique across all nodes in the system.
    /// For agents, this could be derived from a UUID or assigned by the forge.
    pub fn init(node_id: u32) Clock {
        return .{
            .last = .{ .physical = 0, .logical = 0, .node_id = node_id },
            .node_id = node_id,
        };
    }

    /// Generate a new timestamp for a local event.
    ///
    /// Uses the system clock but ensures monotonicity - the returned
    /// timestamp is always greater than any previously generated.
    pub fn now(self: *Clock) HLC {
        const wall_ms = std.time.milliTimestamp();
        return self.tick(wall_ms);
    }

    /// Generate a timestamp with an explicit wall clock value.
    ///
    /// Useful for testing or when wall clock is provided externally.
    /// The timestamp is guaranteed to be greater than the last one,
    /// even if wall_ms goes backwards.
    pub fn tick(self: *Clock, wall_ms: i64) HLC {
        const physical = @max(wall_ms, self.last.physical);

        const logical: u32 = if (physical == self.last.physical)
            self.last.logical + 1
        else
            0;

        self.last = .{
            .physical = physical,
            .logical = logical,
            .node_id = self.node_id,
        };

        return self.last;
    }

    /// Update the clock upon receiving a message with a timestamp.
    ///
    /// Returns a new timestamp that is after both the local clock and
    /// the received timestamp. This ensures causality: if you receive
    /// a message, your next timestamp will be after the sender's.
    pub fn receive(self: *Clock, msg_ts: HLC) HLC {
        const wall_ms = std.time.milliTimestamp();
        return self.update(msg_ts, wall_ms);
    }

    /// Update with explicit wall clock (for testing).
    pub fn update(self: *Clock, msg_ts: HLC, wall_ms: i64) HLC {
        // Physical time is max of: wall clock, our last, received
        const max_physical = @max(wall_ms, @max(self.last.physical, msg_ts.physical));

        // Logical counter depends on which physical times are equal
        var logical: u32 = 0;

        if (max_physical == self.last.physical and max_physical == msg_ts.physical) {
            // All three are equal - increment max logical
            logical = @max(self.last.logical, msg_ts.logical) + 1;
        } else if (max_physical == self.last.physical) {
            // Our physical time wins - increment our logical
            logical = self.last.logical + 1;
        } else if (max_physical == msg_ts.physical) {
            // Message physical time wins - increment their logical
            logical = msg_ts.logical + 1;
        }
        // else: wall clock wins, logical stays 0

        self.last = .{
            .physical = max_physical,
            .logical = logical,
            .node_id = self.node_id,
        };

        return self.last;
    }

    /// Get the last generated timestamp without advancing the clock.
    pub fn current(self: *const Clock) HLC {
        return self.last;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "HLC compare - physical time takes precedence" {
    const a: HLC = .{ .physical = 100, .logical = 5, .node_id = 1 };
    const b: HLC = .{ .physical = 101, .logical = 0, .node_id = 1 };

    try std.testing.expectEqual(std.math.Order.lt, a.compare(b));
    try std.testing.expect(a.happenedBefore(b));
    try std.testing.expect(b.happenedAfter(a));
}

test "HLC compare - logical breaks physical ties" {
    const a: HLC = .{ .physical = 100, .logical = 0, .node_id = 1 };
    const b: HLC = .{ .physical = 100, .logical = 1, .node_id = 1 };

    try std.testing.expectEqual(std.math.Order.lt, a.compare(b));
    try std.testing.expect(a.happenedBefore(b));
}

test "HLC compare - node_id breaks full ties" {
    const a: HLC = .{ .physical = 100, .logical = 5, .node_id = 1 };
    const b: HLC = .{ .physical = 100, .logical = 5, .node_id = 2 };

    try std.testing.expectEqual(std.math.Order.lt, a.compare(b));
    try std.testing.expect(a.happenedBefore(b));
}

test "HLC compare - equality" {
    const a: HLC = .{ .physical = 100, .logical = 5, .node_id = 1 };
    const b: HLC = .{ .physical = 100, .logical = 5, .node_id = 1 };

    try std.testing.expectEqual(std.math.Order.eq, a.compare(b));
    try std.testing.expect(!a.happenedBefore(b));
    try std.testing.expect(!a.happenedAfter(b));
}

test "HLC toBytes/fromBytes roundtrip" {
    const original: HLC = .{
        .physical = 1704067200000, // 2024-01-01 00:00:00 UTC
        .logical = 42,
        .node_id = 12345,
    };

    const bytes = original.toBytes();
    const restored = HLC.fromBytes(&bytes);

    try std.testing.expectEqual(original.physical, restored.physical);
    try std.testing.expectEqual(original.logical, restored.logical);
    try std.testing.expectEqual(original.node_id, restored.node_id);
}

test "HLC toBytes produces lexicographically sortable output" {
    const a: HLC = .{ .physical = 100, .logical = 1, .node_id = 1 };
    const b: HLC = .{ .physical = 100, .logical = 2, .node_id = 1 };
    const c: HLC = .{ .physical = 101, .logical = 0, .node_id = 1 };

    const bytes_a = a.toBytes();
    const bytes_b = b.toBytes();
    const bytes_c = c.toBytes();

    // Lexicographic comparison should match HLC comparison
    try std.testing.expect(std.mem.order(u8, &bytes_a, &bytes_b) == .lt);
    try std.testing.expect(std.mem.order(u8, &bytes_b, &bytes_c) == .lt);
    try std.testing.expect(std.mem.order(u8, &bytes_a, &bytes_c) == .lt);
}

test "HLC format produces readable string" {
    const ts: HLC = .{ .physical = 1704067200000, .logical = 5, .node_id = 42 };

    var buf: [64]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{f}", .{ts}) catch unreachable;

    try std.testing.expectEqualStrings("1704067200000.5@42", result);
}

test "Clock tick is monotonic with advancing time" {
    var clock = Clock.init(1);

    const t1 = clock.tick(1000);
    const t2 = clock.tick(1001);
    const t3 = clock.tick(1002);

    try std.testing.expect(t1.happenedBefore(t2));
    try std.testing.expect(t2.happenedBefore(t3));

    // Logical should be 0 when physical advances
    try std.testing.expectEqual(@as(u32, 0), t1.logical);
    try std.testing.expectEqual(@as(u32, 0), t2.logical);
    try std.testing.expectEqual(@as(u32, 0), t3.logical);
}

test "Clock tick is monotonic with same time" {
    var clock = Clock.init(1);

    const t1 = clock.tick(1000);
    const t2 = clock.tick(1000);
    const t3 = clock.tick(1000);

    try std.testing.expect(t1.happenedBefore(t2));
    try std.testing.expect(t2.happenedBefore(t3));

    // Logical should increment
    try std.testing.expectEqual(@as(u32, 0), t1.logical);
    try std.testing.expectEqual(@as(u32, 1), t2.logical);
    try std.testing.expectEqual(@as(u32, 2), t3.logical);

    // Physical should stay the same
    try std.testing.expectEqual(@as(i64, 1000), t3.physical);
}

test "Clock tick is monotonic with backwards time" {
    var clock = Clock.init(1);

    const t1 = clock.tick(1000);
    const t2 = clock.tick(999); // Time goes backwards!
    const t3 = clock.tick(998); // Still backwards!

    try std.testing.expect(t1.happenedBefore(t2));
    try std.testing.expect(t2.happenedBefore(t3));

    // Physical should stay at max seen
    try std.testing.expectEqual(@as(i64, 1000), t2.physical);
    try std.testing.expectEqual(@as(i64, 1000), t3.physical);

    // Logical should increment
    try std.testing.expectEqual(@as(u32, 1), t2.logical);
    try std.testing.expectEqual(@as(u32, 2), t3.logical);
}

test "Clock update advances past received timestamp" {
    var clock_a = Clock.init(1);
    var clock_b = Clock.init(2);

    // A generates a timestamp at t=1000
    const ts_a = clock_a.tick(1000);

    // B's wall clock is behind at t=500, receives A's message
    _ = clock_b.tick(500); // B's local event
    const ts_b = clock_b.update(ts_a, 500);

    // B's timestamp should be after A's
    try std.testing.expect(ts_a.happenedBefore(ts_b));

    // B's physical should be at least A's physical
    try std.testing.expect(ts_b.physical >= ts_a.physical);
}

test "Clock update with all equal physical times" {
    var clock = Clock.init(1);

    // Start at t=1000
    _ = clock.tick(1000);

    // Receive message also at t=1000 with logical=5
    const msg: HLC = .{ .physical = 1000, .logical = 5, .node_id = 2 };
    const ts = clock.update(msg, 1000);

    // Result should be after both local and message
    try std.testing.expect(ts.logical > 5);
    try std.testing.expectEqual(@as(i64, 1000), ts.physical);
}

test "Clock update when wall clock wins" {
    var clock = Clock.init(1);

    // Start at t=1000
    _ = clock.tick(1000);

    // Receive old message, but wall clock has advanced
    const msg: HLC = .{ .physical = 500, .logical = 10, .node_id = 2 };
    const ts = clock.update(msg, 2000);

    // Wall clock should win, logical resets to 0
    try std.testing.expectEqual(@as(i64, 2000), ts.physical);
    try std.testing.expectEqual(@as(u32, 0), ts.logical);
}

test "Clock update when message physical wins" {
    var clock = Clock.init(1);

    // Start at t=1000
    _ = clock.tick(1000);

    // Receive message from the future
    const msg: HLC = .{ .physical = 5000, .logical = 3, .node_id = 2 };
    const ts = clock.update(msg, 1500);

    // Message physical should win
    try std.testing.expectEqual(@as(i64, 5000), ts.physical);
    // Logical should be message logical + 1
    try std.testing.expectEqual(@as(u32, 4), ts.logical);
}

test "Clock current returns last without advancing" {
    var clock = Clock.init(1);

    const t1 = clock.tick(1000);
    const current1 = clock.current();
    const current2 = clock.current();

    try std.testing.expectEqual(t1.physical, current1.physical);
    try std.testing.expectEqual(t1.logical, current1.logical);
    try std.testing.expectEqual(current1.physical, current2.physical);
    try std.testing.expectEqual(current1.logical, current2.logical);
}

test "Clock preserves node_id" {
    var clock = Clock.init(42);

    const t1 = clock.tick(1000);
    const t2 = clock.tick(1001);

    try std.testing.expectEqual(@as(u32, 42), t1.node_id);
    try std.testing.expectEqual(@as(u32, 42), t2.node_id);
}

test "Multiple clocks interacting" {
    // Simulate two agents sending messages back and forth
    var agent_a = Clock.init(1);
    var agent_b = Clock.init(2);

    // A sends to B
    const a1 = agent_a.tick(100);
    const b1 = agent_b.update(a1, 90); // B's clock is behind

    // B sends to A
    const a2 = agent_a.update(b1, 110);

    // A sends to B again
    const b2 = agent_b.update(a2, 95); // B's clock still behind

    // All timestamps should be properly ordered
    try std.testing.expect(a1.happenedBefore(b1));
    try std.testing.expect(b1.happenedBefore(a2));
    try std.testing.expect(a2.happenedBefore(b2));
}

test "HLC handles negative physical time" {
    // Edge case: timestamps before Unix epoch
    const ts: HLC = .{ .physical = -1000, .logical = 0, .node_id = 1 };

    const bytes = ts.toBytes();
    const restored = HLC.fromBytes(&bytes);

    try std.testing.expectEqual(@as(i64, -1000), restored.physical);
}

test "HLC handles max values" {
    const ts: HLC = .{
        .physical = std.math.maxInt(i64),
        .logical = std.math.maxInt(u32),
        .node_id = std.math.maxInt(u32),
    };

    const bytes = ts.toBytes();
    const restored = HLC.fromBytes(&bytes);

    try std.testing.expectEqual(ts.physical, restored.physical);
    try std.testing.expectEqual(ts.logical, restored.logical);
    try std.testing.expectEqual(ts.node_id, restored.node_id);
}

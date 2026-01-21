//! Tiered blob cache for mic.
//!
//! Provides a two-tier caching system:
//! - RAM tier: Fast in-memory LRU cache (configurable size limit)
//! - SSD tier: Persistent file-based cache in XDG cache directory
//!
//! Blobs are identified by their content hash (SHA256 or Blake3).
//! The cache is content-addressed: same hash = same content.
//!
//! ## Usage
//!
//! ```zig
//! var cache = try BlobCache.init(allocator, .{
//!     .ram_max_bytes = 64 * 1024 * 1024, // 64 MB RAM cache
//!     .ssd_enabled = true,
//! });
//! defer cache.deinit();
//!
//! // Try to get from cache
//! if (cache.get("abcd1234...")) |blob| {
//!     defer allocator.free(blob);
//!     // Use cached blob
//! } else {
//!     // Fetch from server and cache
//!     const blob = try fetchFromServer(...);
//!     try cache.put("abcd1234...", blob);
//! }
//! ```

const std = @import("std");

/// Cache configuration options.
pub const CacheOptions = struct {
    /// Maximum bytes to store in RAM cache (default: 32 MB).
    ram_max_bytes: usize = 32 * 1024 * 1024,

    /// Whether to enable SSD caching (default: true).
    ssd_enabled: bool = true,

    /// Maximum bytes to store in SSD cache (default: 512 MB).
    /// Set to 0 for unlimited.
    ssd_max_bytes: usize = 512 * 1024 * 1024,

    /// Custom cache directory. If null, uses XDG cache directory.
    cache_dir: ?[]const u8 = null,
};

/// Statistics about cache usage.
pub const CacheStats = struct {
    /// Number of cache hits (RAM + SSD).
    hits: u64 = 0,

    /// Number of cache misses.
    misses: u64 = 0,

    /// Number of RAM cache hits.
    ram_hits: u64 = 0,

    /// Number of SSD cache hits.
    ssd_hits: u64 = 0,

    /// Current RAM cache size in bytes.
    ram_bytes: usize = 0,

    /// Number of entries in RAM cache.
    ram_entries: usize = 0,

    /// Number of entries evicted from RAM.
    ram_evictions: u64 = 0,

    pub fn hitRate(self: CacheStats) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }
};

/// Entry in the RAM cache with LRU tracking.
const RamEntry = struct {
    data: []u8,
    size: usize,
    last_access: i64,
};

/// Tiered blob cache with RAM and SSD layers.
pub const BlobCache = struct {
    allocator: std.mem.Allocator,
    options: CacheOptions,

    /// RAM cache: hash -> blob data
    ram_cache: std.StringHashMap(RamEntry),

    /// Current size of RAM cache in bytes.
    ram_size: usize,

    /// Cache directory path (owned).
    cache_dir: ?[]u8,

    /// Cache statistics.
    stats: CacheStats,

    /// Initialize the cache.
    pub fn init(allocator: std.mem.Allocator, options: CacheOptions) !BlobCache {
        var cache = BlobCache{
            .allocator = allocator,
            .options = options,
            .ram_cache = std.StringHashMap(RamEntry).init(allocator),
            .ram_size = 0,
            .cache_dir = null,
            .stats = .{},
        };

        // Set up SSD cache directory
        if (options.ssd_enabled) {
            if (options.cache_dir) |dir| {
                cache.cache_dir = try allocator.dupe(u8, dir);
            } else {
                cache.cache_dir = try cacheDir(allocator);
            }
            try ensureCacheDir(cache.cache_dir.?);
        }

        return cache;
    }

    /// Deinitialize and free all resources.
    pub fn deinit(self: *BlobCache) void {
        // Free RAM cache entries
        var iter = self.ram_cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
        }
        self.ram_cache.deinit();

        // Free cache directory path
        if (self.cache_dir) |dir| {
            self.allocator.free(dir);
        }

        self.* = undefined;
    }

    /// Get a blob from the cache by hash.
    /// Returns owned slice that caller must free, or null if not found.
    pub fn get(self: *BlobCache, hash_hex: []const u8) ?[]u8 {
        // Check RAM cache first
        if (self.ram_cache.getPtr(hash_hex)) |entry| {
            entry.last_access = std.time.timestamp();
            self.stats.hits += 1;
            self.stats.ram_hits += 1;

            // Return a copy since caller will own it
            return self.allocator.dupe(u8, entry.data) catch null;
        }

        // Check SSD cache
        if (self.options.ssd_enabled) {
            if (self.cache_dir) |dir| {
                if (readSsdCache(self.allocator, dir, hash_hex)) |data| {
                    // Promote to RAM cache
                    self.putRam(hash_hex, data) catch {};

                    self.stats.hits += 1;
                    self.stats.ssd_hits += 1;
                    return data;
                } else |_| {}
            }
        }

        self.stats.misses += 1;
        return null;
    }

    /// Store a blob in the cache.
    /// The cache takes ownership of the data for RAM storage.
    pub fn put(self: *BlobCache, hash_hex: []const u8, data: []const u8) !void {
        // Store in RAM cache
        try self.putRam(hash_hex, data);

        // Store in SSD cache
        if (self.options.ssd_enabled) {
            if (self.cache_dir) |dir| {
                writeSsdCache(dir, hash_hex, data) catch |err| {
                    // SSD write failure is not fatal, just log
                    std.log.warn("Failed to write SSD cache for {s}: {}", .{ hash_hex, err });
                };
            }
        }
    }

    /// Store a blob in RAM cache only.
    fn putRam(self: *BlobCache, hash_hex: []const u8, data: []const u8) !void {
        const size = data.len;

        // Skip if blob is larger than max RAM cache
        if (size > self.options.ram_max_bytes) {
            return;
        }

        // Evict if needed to make room
        while (self.ram_size + size > self.options.ram_max_bytes and self.ram_cache.count() > 0) {
            try self.evictLru();
        }

        // Check if already exists
        if (self.ram_cache.getPtr(hash_hex)) |existing| {
            existing.last_access = std.time.timestamp();
            return;
        }

        // Create owned copies
        const owned_hash = try self.allocator.dupe(u8, hash_hex);
        errdefer self.allocator.free(owned_hash);

        const owned_data = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(owned_data);

        try self.ram_cache.put(owned_hash, .{
            .data = owned_data,
            .size = size,
            .last_access = std.time.timestamp(),
        });

        self.ram_size += size;
        self.stats.ram_bytes = self.ram_size;
        self.stats.ram_entries = self.ram_cache.count();
    }

    /// Evict the least recently used entry from RAM cache.
    fn evictLru(self: *BlobCache) !void {
        var oldest_key: ?[]const u8 = null;
        var oldest_time: i64 = std.math.maxInt(i64);

        var iter = self.ram_cache.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.last_access < oldest_time) {
                oldest_time = entry.value_ptr.last_access;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (self.ram_cache.fetchRemove(key)) |removed| {
                self.ram_size -= removed.value.size;
                self.allocator.free(removed.key);
                self.allocator.free(removed.value.data);
                self.stats.ram_evictions += 1;
                self.stats.ram_bytes = self.ram_size;
                self.stats.ram_entries = self.ram_cache.count();
            }
        }
    }

    /// Clear the entire cache (RAM and SSD).
    pub fn clear(self: *BlobCache) void {
        // Clear RAM cache
        var iter = self.ram_cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
        }
        self.ram_cache.clearRetainingCapacity();
        self.ram_size = 0;
        self.stats.ram_bytes = 0;
        self.stats.ram_entries = 0;

        // Clear SSD cache
        if (self.options.ssd_enabled) {
            if (self.cache_dir) |dir| {
                clearSsdCache(dir) catch {};
            }
        }
    }

    /// Clear only the RAM cache.
    pub fn clearRam(self: *BlobCache) void {
        var iter = self.ram_cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
        }
        self.ram_cache.clearRetainingCapacity();
        self.ram_size = 0;
        self.stats.ram_bytes = 0;
        self.stats.ram_entries = 0;
    }

    /// Get current cache statistics.
    pub fn getStats(self: *const BlobCache) CacheStats {
        return self.stats;
    }

    /// Check if a blob exists in cache without retrieving it.
    pub fn contains(self: *BlobCache, hash_hex: []const u8) bool {
        // Check RAM first
        if (self.ram_cache.contains(hash_hex)) {
            return true;
        }

        // Check SSD
        if (self.options.ssd_enabled) {
            if (self.cache_dir) |dir| {
                return ssdCacheExists(dir, hash_hex);
            }
        }

        return false;
    }
};

// ============================================================================
// SSD cache helpers
// ============================================================================

/// Get the XDG cache directory for mic blobs.
fn cacheDir(allocator: std.mem.Allocator) ![]u8 {
    // Check XDG_CACHE_HOME first
    if (std.process.getEnvVarOwned(allocator, "XDG_CACHE_HOME")) |value| {
        if (value.len > 0) {
            defer allocator.free(value);
            return std.fs.path.join(allocator, &.{ value, "mic", "blobs" });
        }
        allocator.free(value);
    } else |_| {}

    // Fall back to ~/.cache
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    return std.fs.path.join(allocator, &.{ home, ".cache", "mic", "blobs" });
}

/// Ensure the cache directory exists.
fn ensureCacheDir(path: []const u8) !void {
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        error.FileNotFound => {
            // Parent doesn't exist, create recursively
            try std.fs.cwd().makePath(path);
        },
        else => return err,
    };
}

/// Get the file path for a cached blob.
fn ssdCachePath(allocator: std.mem.Allocator, cache_dir: []const u8, hash_hex: []const u8) ![]u8 {
    // Use first 2 chars as subdirectory for better filesystem performance
    if (hash_hex.len < 2) {
        return std.fs.path.join(allocator, &.{ cache_dir, hash_hex });
    }

    const subdir = hash_hex[0..2];
    return std.fs.path.join(allocator, &.{ cache_dir, subdir, hash_hex });
}

/// Read a blob from SSD cache.
fn readSsdCache(allocator: std.mem.Allocator, cache_dir: []const u8, hash_hex: []const u8) ![]u8 {
    const path = try ssdCachePath(allocator, cache_dir, hash_hex);
    defer allocator.free(path);

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    // Read file size
    const stat = try file.stat();
    const size = stat.size;

    // Limit read size to prevent OOM
    const max_size: usize = 100 * 1024 * 1024; // 100 MB
    if (size > max_size) {
        return error.FileTooLarge;
    }

    return try file.readToEndAlloc(allocator, max_size);
}

/// Write a blob to SSD cache.
fn writeSsdCache(cache_dir: []const u8, hash_hex: []const u8, data: []const u8) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Build path with subdir
    const subdir = if (hash_hex.len >= 2) hash_hex[0..2] else hash_hex;
    const subdir_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ cache_dir, subdir }) catch return error.PathTooLong;

    // Ensure subdirectory exists
    std.fs.makeDirAbsolute(subdir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Build full file path
    var file_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const file_path = std.fmt.bufPrint(&file_path_buf, "{s}/{s}", .{ subdir_path, hash_hex }) catch return error.PathTooLong;

    // Write atomically (write to temp, then rename)
    var tmp_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = std.fmt.bufPrint(&tmp_path_buf, "{s}.tmp", .{file_path}) catch return error.PathTooLong;

    var file = try std.fs.createFileAbsolute(tmp_path, .{ .mode = 0o644 });
    errdefer {
        file.close();
        std.fs.deleteFileAbsolute(tmp_path) catch {};
    }

    try file.writeAll(data);
    file.close();

    // Atomic rename
    try std.fs.renameAbsolute(tmp_path, file_path);
}

/// Check if a blob exists in SSD cache.
fn ssdCacheExists(cache_dir: []const u8, hash_hex: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    const subdir = if (hash_hex.len >= 2) hash_hex[0..2] else hash_hex;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}/{s}", .{ cache_dir, subdir, hash_hex }) catch return false;

    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

/// Clear all files in SSD cache.
fn clearSsdCache(cache_dir: []const u8) !void {
    var dir = std.fs.openDirAbsolute(cache_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            // Delete subdirectory and contents
            dir.deleteTree(entry.name) catch {};
        } else {
            dir.deleteFile(entry.name) catch {};
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "BlobCache init and deinit" {
    var cache = try BlobCache.init(std.testing.allocator, .{
        .ram_max_bytes = 1024,
        .ssd_enabled = false,
    });
    defer cache.deinit();

    try std.testing.expectEqual(@as(usize, 0), cache.ram_size);
    try std.testing.expectEqual(@as(usize, 0), cache.stats.hits);
}

test "BlobCache put and get" {
    var cache = try BlobCache.init(std.testing.allocator, .{
        .ram_max_bytes = 1024,
        .ssd_enabled = false,
    });
    defer cache.deinit();

    const hash = "abcd1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab";
    const data = "Hello, World!";

    try cache.put(hash, data);

    const retrieved = cache.get(hash);
    try std.testing.expect(retrieved != null);
    defer std.testing.allocator.free(retrieved.?);

    try std.testing.expectEqualStrings(data, retrieved.?);
    try std.testing.expectEqual(@as(u64, 1), cache.stats.hits);
    try std.testing.expectEqual(@as(u64, 1), cache.stats.ram_hits);
}

test "BlobCache miss returns null" {
    var cache = try BlobCache.init(std.testing.allocator, .{
        .ram_max_bytes = 1024,
        .ssd_enabled = false,
    });
    defer cache.deinit();

    const result = cache.get("nonexistent");
    try std.testing.expect(result == null);
    try std.testing.expectEqual(@as(u64, 1), cache.stats.misses);
}

test "BlobCache LRU eviction" {
    var cache = try BlobCache.init(std.testing.allocator, .{
        .ram_max_bytes = 100, // Small limit to trigger eviction
        .ssd_enabled = false,
    });
    defer cache.deinit();

    // Fill cache
    try cache.put("hash1", "data1data1data1data1data1data1data1data1data1");
    try cache.put("hash2", "data2data2data2data2data2data2data2data2data2");

    // This should evict hash1
    try cache.put("hash3", "data3data3data3data3data3data3data3data3data3");

    // hash1 should be evicted
    try std.testing.expect(!cache.ram_cache.contains("hash1"));

    // hash3 should exist
    try std.testing.expect(cache.ram_cache.contains("hash3"));

    try std.testing.expect(cache.stats.ram_evictions > 0);
}

test "BlobCache clear" {
    var cache = try BlobCache.init(std.testing.allocator, .{
        .ram_max_bytes = 1024,
        .ssd_enabled = false,
    });
    defer cache.deinit();

    try cache.put("hash1", "data1");
    try cache.put("hash2", "data2");

    try std.testing.expectEqual(@as(usize, 2), cache.ram_cache.count());

    cache.clear();

    try std.testing.expectEqual(@as(usize, 0), cache.ram_cache.count());
    try std.testing.expectEqual(@as(usize, 0), cache.ram_size);
}

test "BlobCache contains" {
    var cache = try BlobCache.init(std.testing.allocator, .{
        .ram_max_bytes = 1024,
        .ssd_enabled = false,
    });
    defer cache.deinit();

    const hash = "testhash123";
    try std.testing.expect(!cache.contains(hash));

    try cache.put(hash, "testdata");
    try std.testing.expect(cache.contains(hash));
}

test "BlobCache hit rate calculation" {
    var stats = CacheStats{
        .hits = 75,
        .misses = 25,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 0.75), stats.hitRate(), 0.001);
}

test "BlobCache hit rate with zero total" {
    const stats = CacheStats{};
    try std.testing.expectEqual(@as(f64, 0.0), stats.hitRate());
}

test "cacheDir returns valid path" {
    const dir = try cacheDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);

    try std.testing.expect(dir.len > 0);
    try std.testing.expect(std.mem.endsWith(u8, dir, "mic/blobs"));
}

test "ssdCachePath uses subdirectory" {
    const path = try ssdCachePath(std.testing.allocator, "/cache", "abcd1234");
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/cache/ab/abcd1234", path);
}

test "ssdCachePath handles short hash" {
    const path = try ssdCachePath(std.testing.allocator, "/cache", "a");
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/cache/a", path);
}

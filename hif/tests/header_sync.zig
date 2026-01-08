//! Header synchronization test.
//!
//! This test verifies that the C header (include/hif_core.h) stays in sync
//! with the actual FFI exports in src/ffi.zig.

const std = @import("std");

/// List of all functions that should be exported.
/// This list is the source of truth and should match both ffi.zig exports
/// and hif_core.h declarations.
const expected_exports = [_][]const u8{
    // Version
    "hif_version",
    "hif_abi_version",
    // Allocator
    "hif_allocator_c",
    "hif_free",
    // Hash
    "hif_hash",
    "hif_hash_blob",
    "hif_hash_format_hex",
    "hif_hash_parse_hex",
    // Bloom
    "hif_bloom_new",
    "hif_bloom_free",
    "hif_bloom_add",
    "hif_bloom_add_hash",
    "hif_bloom_may_contain",
    "hif_bloom_intersects",
    "hif_bloom_merge",
    "hif_bloom_estimate_count",
    "hif_bloom_serialize",
    "hif_bloom_deserialize",
    // HLC
    "hif_clock_new",
    "hif_clock_free",
    "hif_clock_now",
    "hif_clock_now_with_wall",
    "hif_clock_receive",
    "hif_clock_current",
    "hif_hlc_compare",
    "hif_hlc_to_bytes",
    "hif_hlc_from_bytes",
};

// Embed the header file (build.zig sets up the include path)
const header_content = @embedFile("hif_core.h");

test "header file contains all expected function declarations" {
    for (expected_exports) |name| {
        // Look for the function name in the header
        // Functions appear as "name(" in declarations
        var search_buf: [128]u8 = undefined;
        const search = std.fmt.bufPrint(&search_buf, "{s}(", .{name}) catch unreachable;
        if (std.mem.indexOf(u8, header_content, search) == null) {
            std.debug.print("Missing header declaration: {s}\n", .{name});
            return error.MissingHeaderDeclaration;
        }
    }
}

test "header has version defines" {
    // Check version string exists
    if (std.mem.indexOf(u8, header_content, "#define HIF_CORE_VERSION") == null) {
        return error.MissingVersionDefine;
    }

    // Check ABI version exists
    if (std.mem.indexOf(u8, header_content, "#define HIF_CORE_ABI_VERSION") == null) {
        return error.MissingAbiVersionDefine;
    }
}

test "header has proper include guards" {
    if (std.mem.indexOf(u8, header_content, "#ifndef HIF_CORE_H") == null) {
        return error.MissingIncludeGuard;
    }
    if (std.mem.indexOf(u8, header_content, "#define HIF_CORE_H") == null) {
        return error.MissingIncludeGuard;
    }
    if (std.mem.indexOf(u8, header_content, "#endif /* HIF_CORE_H */") == null) {
        return error.MissingIncludeGuard;
    }
}

test "header has C++ compatibility" {
    if (std.mem.indexOf(u8, header_content, "#ifdef __cplusplus") == null) {
        return error.MissingCppGuard;
    }
    if (std.mem.indexOf(u8, header_content, "extern \"C\" {") == null) {
        return error.MissingCppGuard;
    }
}

test "header has required includes" {
    if (std.mem.indexOf(u8, header_content, "#include <stddef.h>") == null) {
        return error.MissingStddefInclude;
    }
    if (std.mem.indexOf(u8, header_content, "#include <stdint.h>") == null) {
        return error.MissingStdintInclude;
    }
}

test "header defines HIF_HASH_SIZE" {
    if (std.mem.indexOf(u8, header_content, "#define HIF_HASH_SIZE 32") == null) {
        return error.MissingHashSizeDefine;
    }
}

test "header declares opaque types" {
    if (std.mem.indexOf(u8, header_content, "typedef struct HifAllocator HifAllocator") == null) {
        return error.MissingAllocatorTypedef;
    }
    if (std.mem.indexOf(u8, header_content, "typedef struct HifBloom HifBloom") == null) {
        return error.MissingBloomTypedef;
    }
    if (std.mem.indexOf(u8, header_content, "typedef struct HifClock HifClock") == null) {
        return error.MissingClockTypedef;
    }
}

test "header declares HifHLC struct" {
    if (std.mem.indexOf(u8, header_content, "typedef struct {") == null) {
        return error.MissingHlcStruct;
    }
    if (std.mem.indexOf(u8, header_content, "} HifHLC") == null) {
        return error.MissingHlcTypedef;
    }
}

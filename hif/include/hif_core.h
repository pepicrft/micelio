/**
 * libhif-core: Core algorithms for the hif version control system.
 *
 * This header provides C bindings for the core hif algorithms:
 * - Blake3 hashing for content-addressed storage
 * - Bloom filters for fast conflict detection
 * - Hybrid Logical Clocks for distributed timestamps
 * - Repository initialization
 *
 * Memory Management:
 * - Functions that allocate memory require a HifAllocator
 * - Use hif_allocator_c() for the standard C allocator
 * - Free allocated memory with hif_free()
 * - Opaque types (HifBloom, HifClock) have dedicated free functions
 *
 * This header is the source of truth for the C API. The build system
 * installs it to zig-out/include/hif_core.h.
 */

#ifndef HIF_CORE_H
#define HIF_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Version information */
#define HIF_CORE_VERSION "0.1.0"
#define HIF_CORE_ABI_VERSION 1

/* Hash size in bytes (256 bits) */
#define HIF_HASH_SIZE 32

/* ============================================================================
 * Allocator
 * ============================================================================ */

/** Opaque allocator handle. */
typedef struct HifAllocator HifAllocator;

/** Get the C allocator (uses malloc/free). */
HifAllocator* hif_allocator_c(void);

/** Free memory allocated by hif functions. */
void hif_free(const HifAllocator* alloc, uint8_t* ptr, size_t len);

/* ============================================================================
 * Hashing
 * ============================================================================ */

/** Hash data using Blake3. Writes 32 bytes to out. */
void hif_hash(const uint8_t* data, size_t data_len, uint8_t out[HIF_HASH_SIZE]);

/** Hash a blob (file content) with type prefix. */
void hif_hash_blob(const uint8_t* content, size_t content_len, uint8_t out[HIF_HASH_SIZE]);

/** Format a hash as hexadecimal. Writes 64 bytes to out (not null-terminated). */
void hif_hash_format_hex(const uint8_t hash[HIF_HASH_SIZE], uint8_t out[HIF_HASH_SIZE * 2]);

/**
 * Parse a hexadecimal string into a hash.
 * @return 0 on success, -1 on invalid input.
 */
int hif_hash_parse_hex(const uint8_t* hex, size_t hex_len, uint8_t out[HIF_HASH_SIZE]);

/* ============================================================================
 * Bloom Filter
 * ============================================================================ */

/** Opaque bloom filter handle. */
typedef struct HifBloom HifBloom;

/**
 * Create a new bloom filter.
 * @param alloc Allocator to use
 * @param expected_items Expected number of items
 * @param fp_rate Desired false positive rate (e.g., 0.01 for 1%)
 * @return Bloom filter handle, or NULL on failure
 */
HifBloom* hif_bloom_new(const HifAllocator* alloc, size_t expected_items, double fp_rate);

/** Free a bloom filter. */
void hif_bloom_free(const HifAllocator* alloc, HifBloom* bloom);

/** Add a path to the bloom filter. */
void hif_bloom_add(HifBloom* bloom, const uint8_t* path, size_t path_len);

/** Add a hash to the bloom filter. */
void hif_bloom_add_hash(HifBloom* bloom, const uint8_t hash[HIF_HASH_SIZE]);

/**
 * Check if a path might be in the bloom filter.
 * @return 1 if possibly present, 0 if definitely not present
 */
int hif_bloom_may_contain(const HifBloom* bloom, const uint8_t* path, size_t path_len);

/**
 * Check if two bloom filters might have overlapping items.
 * @return 1 if possibly intersecting, 0 if definitely disjoint
 */
int hif_bloom_intersects(const HifBloom* a, const HifBloom* b);

/** Merge another bloom filter into this one (union). */
void hif_bloom_merge(HifBloom* dst, const HifBloom* src);

/** Get estimated number of items in the filter. */
size_t hif_bloom_estimate_count(const HifBloom* bloom);

/**
 * Serialize bloom filter to bytes.
 * @param out_len Output parameter for data length
 * @return Pointer to serialized data, or NULL on failure. Caller must free with hif_free().
 */
uint8_t* hif_bloom_serialize(const HifAllocator* alloc, const HifBloom* bloom, size_t* out_len);

/**
 * Deserialize bloom filter from bytes.
 * @return Bloom filter handle, or NULL on failure
 */
HifBloom* hif_bloom_deserialize(const HifAllocator* alloc, const uint8_t* data, size_t data_len);

/* ============================================================================
 * Hybrid Logical Clock
 * ============================================================================ */

/** HLC timestamp. */
typedef struct {
    int64_t physical;   /* Milliseconds since epoch */
    uint32_t logical;   /* Logical counter */
    uint32_t node_id;   /* Node identifier for tie-breaking */
} HifHLC;

/** Opaque clock handle. */
typedef struct HifClock HifClock;

/**
 * Create a new HLC clock.
 * @param node_id Unique identifier for this node
 * @return Clock handle, or NULL on failure
 */
HifClock* hif_clock_new(const HifAllocator* alloc, uint32_t node_id);

/** Free a clock. */
void hif_clock_free(const HifAllocator* alloc, HifClock* clock);

/** Generate a new timestamp for a local event. */
void hif_clock_now(HifClock* clock, HifHLC* out);

/** Generate a timestamp with explicit wall clock (for testing). */
void hif_clock_now_with_wall(HifClock* clock, int64_t wall_ms, HifHLC* out);

/** Update clock upon receiving a message with a timestamp. */
void hif_clock_receive(HifClock* clock, const HifHLC* msg, HifHLC* out);

/** Get the current timestamp without advancing the clock. */
void hif_clock_current(const HifClock* clock, HifHLC* out);

/**
 * Compare two HLC timestamps.
 * @return -1 if a < b, 0 if a == b, 1 if a > b
 */
int hif_hlc_compare(const HifHLC* a, const HifHLC* b);

/** Serialize HLC to 16 bytes. */
void hif_hlc_to_bytes(const HifHLC* ts, uint8_t out[16]);

/** Deserialize HLC from 16 bytes. */
void hif_hlc_from_bytes(const uint8_t data[16], HifHLC* out);

/* ============================================================================
 * Version Information
 * ============================================================================ */

/** Get the library version string. */
const char* hif_version(void);

/** Get the ABI version for compatibility checking. */
uint32_t hif_abi_version(void);

#ifdef __cplusplus
}
#endif

#endif /* HIF_CORE_H */

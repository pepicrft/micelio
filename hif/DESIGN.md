# hif - Design

A version control system for an agent-first world, designed for Meta/Shopify scale.

## Philosophy

Git was designed for human collaboration at small-to-medium scale. But the future is different:

- **Hundreds of AI agents** working concurrently on the same codebase
- **Billions of files** in monorepos
- **Hundreds of thousands of landings per day**
- **Humans reviewing**, not writing most code

hif is designed for this reality. It takes lessons from [Google's Piper](https://cacm.acm.org/research/why-google-stores-billions-of-lines-of-code-in-a-single-repository/), [Meta's Sapling](https://engineering.fb.com/2022/11/15/open-source/sapling-source-control-scalable/), [Turbopuffer](https://turbopuffer.com/blog/turbopuffer), [WarpStream](https://docs.warpstream.com/warpstream/background-information/warpstreams-architecture), and [Calvin](https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf) - but reimagines them for an agentic world.

**Key principles:**

- **Forge-first** - the server is the source of truth, not local disk
- **Agent-native** - sessions capture goal, reasoning, and changes together
- **Object storage-first** - S3 is the source of truth, not a tier (like Turbopuffer)
- **Stateless compute** - agents are stateless, can be trivially auto-scaled (like WarpStream)
- **Binary everywhere** - no JSON, all binary formats for speed
- **O(log n) operations** - bloom filter rollups, not linear scans
- **Coordinator-free landing** - S3 conditional writes, not single process bottleneck
- **Epoch batching** - batch landings for throughput (like Calvin)
- **Deterministic simulation** - test decades of failures in hours (like TigerBeetle)
- **Sparse checkout** - fetch only what you touch (like Scalar/VFSForGit)

---

## Architecture Overview

hif has three components that work together:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                               CLIENT (Zig)                                   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      libhif-core (native Zig)                       │   │
│  │   Trees · Bloom Filters · Segmented Changelog · HLC · Hash          │   │
│  │   Binary serialization · Conflict detection                         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                         │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                  │
│  │   hif CLI     │  │   hif-fs      │  │  Tiered Cache │                  │
│  │               │  │  (Phase 2)    │  │               │                  │
│  │ session start │  │  NFS daemon   │  │  RAM → SSD    │                  │
│  │ session land  │  │  Mount point  │  │  → S3         │                  │
│  └───────────────┘  └───────────────┘  └───────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ gRPC
                                    │
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FORGE (stateless agents, like WarpStream)                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      Stateless Agents (Fly.io / Lambda / K8s)       │   │
│  │                                                                     │   │
│  │   Any agent can handle any request (no leader, no partitioning)    │   │
│  │   Auth · Session CRUD · Blob streaming · Landing                   │   │
│  │   Auto-scale based on CPU, scale to zero when idle                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                         │
│                          S3 Conditional Writes                              │
│                          (if-match / if-none-match)                         │
│                                   │                                         │
│                    No coordinator needed for landing!                       │
│                    S3 provides atomic compare-and-swap                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         S3 (source of truth)                                 │
│                                                                             │
│   Like Turbopuffer: object storage-first, not tiered                        │
│                                                                             │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│   │   Landing   │  │   Session   │  │    Tree     │  │    Blob     │       │
│   │     Log     │  │    Store    │  │    Store    │  │    Store    │       │
│   │             │  │             │  │             │  │             │       │
│   │ Append-only │  │   Binary    │  │   Binary    │  │   zstd      │       │
│   │ Bloom index │  │   format    │  │   B+ tree   │  │  content-   │       │
│   │             │  │             │  │             │  │  addressed  │       │
│   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                                             │
│   Auth: SQLite replicated via Litestream (tiny, ~KB per user)              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Language | Runs | Responsibility |
|-----------|----------|------|----------------|
| **libhif-core** | Zig (C ABI) | Anywhere | Algorithms: trees, bloom, changelog, hashing, binary serialization |
| **Forge Agents** | Any (Elixir, Go, etc.) | Cloud | Stateless API handlers, any agent handles any request |
| **hif CLI** | Zig | Local | User/agent interface |
| **hif-fs** | Zig | Local | Virtual filesystem (Phase 2) |
| **S3** | - | Cloud | Source of truth: landing log, sessions, trees, blobs |
| **SQLite** | - | Forge | Auth only (users, tokens, permissions) |

### Why This Architecture?

**Object storage-first (like Turbopuffer):**
- S3 is the source of truth, not a cold tier
- Data "inflates" from S3 → SSD → RAM as needed
- Inactive projects cost nearly nothing ($0.023/GB/month)
- 11 nines durability, no backups needed
- Strong consistency since 2020

**Stateless agents (like WarpStream):**
- No leader election, no partitioning, no Raft
- Any agent can handle any request
- Auto-scale based on CPU, scale to zero when idle
- Agent failure is a non-event (just restart)
- Trivial to deploy (single binary)

**S3 conditional writes (no coordinator):**
- Landing uses `if-match` headers for optimistic concurrency
- S3 provides atomic compare-and-swap
- No single coordinator bottleneck
- Multiple landings can race; S3 picks the winner
- Failed landings retry with backoff

**Binary everywhere (not JSON):**
- All data structures serialize to compact binary
- libhif-core handles all serialization
- Trees, blooms, sessions: all binary
- Fast to parse, small on disk
- Zero-copy where possible

**Bloom filter rollups (O(log n) conflict detection):**
- Hierarchical bloom filters cover ranges of landings
- Check conflict with O(log n) bloom lookups
- Not O(n) scan of all landed sessions
- Enables 100k+ landings/day

**Unbundled architecture (like FoundationDB):**
- Separate control plane from data plane
- Each subsystem scales independently
- Fast recovery via deterministic replay

---

## Unbundled Architecture

Inspired by [FoundationDB's unbundled design](https://www.micahlerner.com/2021/06/12/foundationdb-a-distributed-unbundled-transactional-key-value-store.html),
hif separates into independently scalable subsystems:

```
┌─────────────────────────────────────────────────────────────────┐
│                        CONTROL PLANE                             │
│                  (strong consistency, low volume)                │
│                                                                 │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│   │    Auth     │  │   Project   │  │   Bloom     │            │
│   │   (SQLite)  │  │  Metadata   │  │   Rollup    │            │
│   │             │  │             │  │  Scheduler  │            │
│   │ Users       │  │ Settings    │  │             │            │
│   │ Tokens      │  │ Permissions │  │ Background  │            │
│   │ Permissions │  │ Webhooks    │  │ job queue   │            │
│   └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ (separate scaling)
                              │
┌─────────────────────────────────────────────────────────────────┐
│                         DATA PLANE                               │
│                 (high throughput, eventually consistent)         │
│                                                                 │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│   │   Landing   │  │   Session   │  │    Blob     │            │
│   │   System    │  │    Store    │  │    Store    │            │
│   │             │  │             │  │             │            │
│   │ Head file   │  │ Session     │  │ Trees       │            │
│   │ Landing log │  │ state       │  │ Blobs       │            │
│   │ Bloom index │  │ Operations  │  │ Content-    │            │
│   │             │  │ Conversation│  │ addressed   │            │
│   └─────────────┘  └─────────────┘  └─────────────┘            │
│         │                │                │                     │
│         └────────────────┴────────────────┘                     │
│                          │                                      │
│                          ▼                                      │
│                    S3 (unified)                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Why this matters:**
- Control plane can use SQLite (simple, consistent)
- Data plane uses S3 directly (infinite scale)
- Landing system can scale independently of blob storage
- Session store can scale independently of landing
- Each subsystem has its own failure modes and recovery

**Recovery (from FoundationDB's insight):**
> "The decoupling of logging and the determinism in transaction orders
> greatly simplify recovery, allowing unusually quick recovery time."

For hif:
- Landing log is our WAL
- Recovery = read head + replay landing log
- Deterministic ordering means any agent can recover
- S3's strong consistency means no distributed consensus needed

---

## libhif-core

The algorithmic core, shared between forge and client.

### C API

```c
// hif_core.h

#include <stdint.h>
#include <stddef.h>

// Allocator (caller provides memory management)
typedef struct {
    void* (*alloc)(void* ctx, size_t size);
    void (*free)(void* ctx, void* ptr, size_t size);
    void* ctx;
} HifAllocator;

// ============================================================================
// Content Hashing (Blake3)
// ============================================================================

// Hash a blob, returns 32-byte hash
void hif_hash_blob(const uint8_t* data, size_t len, uint8_t out[32]);

// Chunked hashing for large files
typedef struct HifChunker HifChunker;

HifChunker* hif_chunker_new(HifAllocator* alloc, size_t target_chunk_size);
void hif_chunker_free(HifChunker* chunker);

// Returns number of chunks, fills hashes array
size_t hif_chunker_chunk(
    HifChunker* chunker,
    const uint8_t* data,
    size_t len,
    uint8_t (*hashes)[32],
    size_t max_chunks
);

// ============================================================================
// Bloom Filters
// ============================================================================

typedef struct HifBloom HifBloom;

// Create bloom filter for n items with false positive rate fp_rate
HifBloom* hif_bloom_new(HifAllocator* alloc, size_t n, double fp_rate);
void hif_bloom_free(HifBloom* bloom);

void hif_bloom_add(HifBloom* bloom, const uint8_t* data, size_t len);
int hif_bloom_check(const HifBloom* bloom, const uint8_t* data, size_t len);
int hif_bloom_intersects(const HifBloom* a, const HifBloom* b);

// Serialization
size_t hif_bloom_serialized_size(const HifBloom* bloom);
void hif_bloom_serialize(const HifBloom* bloom, uint8_t* out);
HifBloom* hif_bloom_deserialize(HifAllocator* alloc, const uint8_t* data, size_t len);

// ============================================================================
// Prolly Trees (content-addressed B-trees)
// ============================================================================

typedef struct HifTree HifTree;
typedef struct HifTreeDiff HifTreeDiff;

HifTree* hif_tree_new(HifAllocator* alloc);
void hif_tree_free(HifTree* tree);

// Mutations (returns new tree, original unchanged)
HifTree* hif_tree_insert(const HifTree* tree, const char* path, const uint8_t hash[32]);
HifTree* hif_tree_delete(const HifTree* tree, const char* path);

// Queries
int hif_tree_get(const HifTree* tree, const char* path, uint8_t out[32]);
void hif_tree_hash(const HifTree* tree, uint8_t out[32]);

// Diffing
HifTreeDiff* hif_tree_diff(const HifTree* a, const HifTree* b);
void hif_tree_diff_free(HifTreeDiff* diff);

typedef struct {
    const char* path;
    uint8_t old_hash[32];  // zero if added
    uint8_t new_hash[32];  // zero if deleted
} HifDiffEntry;

size_t hif_tree_diff_count(const HifTreeDiff* diff);
const HifDiffEntry* hif_tree_diff_get(const HifTreeDiff* diff, size_t index);

// Serialization
size_t hif_tree_serialized_size(const HifTree* tree);
void hif_tree_serialize(const HifTree* tree, uint8_t* out);
HifTree* hif_tree_deserialize(HifAllocator* alloc, const uint8_t* data, size_t len);

// ============================================================================
// Hybrid Logical Clock
// ============================================================================

typedef struct {
    int64_t physical;   // milliseconds since epoch
    uint32_t logical;   // logical counter
    uint32_t node_id;   // node identifier
} HifHLC;

void hif_hlc_init(HifHLC* hlc, uint32_t node_id);
void hif_hlc_now(HifHLC* hlc, int64_t wall_time);
void hif_hlc_update(HifHLC* hlc, const HifHLC* received, int64_t wall_time);
int hif_hlc_compare(const HifHLC* a, const HifHLC* b);

void hif_hlc_serialize(const HifHLC* hlc, uint8_t out[16]);
void hif_hlc_deserialize(const uint8_t data[16], HifHLC* out);

// ============================================================================
// Segmented Changelog (ancestry queries)
// ============================================================================

typedef struct HifChangelog HifChangelog;

HifChangelog* hif_changelog_new(HifAllocator* alloc);
void hif_changelog_free(HifChangelog* cl);

// Add a session with its parent positions
void hif_changelog_add(
    HifChangelog* cl,
    int64_t position,
    const uint8_t session_id[16],
    const int64_t* parent_positions,
    size_t parent_count
);

// Queries
int hif_changelog_is_ancestor(const HifChangelog* cl, int64_t ancestor, int64_t descendant);
int64_t hif_changelog_common_ancestor(const HifChangelog* cl, int64_t a, int64_t b);

// Serialization
size_t hif_changelog_serialized_size(const HifChangelog* cl);
void hif_changelog_serialize(const HifChangelog* cl, uint8_t* out);
HifChangelog* hif_changelog_deserialize(HifAllocator* alloc, const uint8_t* data, size_t len);
```

### Usage from Elixir (via Zigler)

```elixir
defmodule Hif.Core do
  use Zig, otp_app: :hif_forge, sources: ["c_src/libhif_core.a"]

  # Bloom filters
  def bloom_new(n, fp_rate), do: :erlang.nif_error(:not_loaded)
  def bloom_add(bloom, data), do: :erlang.nif_error(:not_loaded)
  def bloom_check(bloom, data), do: :erlang.nif_error(:not_loaded)
  def bloom_intersects(a, b), do: :erlang.nif_error(:not_loaded)

  # Trees
  def tree_new(), do: :erlang.nif_error(:not_loaded)
  def tree_insert(tree, path, hash), do: :erlang.nif_error(:not_loaded)
  def tree_hash(tree), do: :erlang.nif_error(:not_loaded)
  def tree_diff(a, b), do: :erlang.nif_error(:not_loaded)

  # Hashing
  def hash_blob(data), do: :erlang.nif_error(:not_loaded)
end

defmodule Hif.ConflictDetector do
  alias Hif.Core

  def check(session, landed_since_base) do
    our_bloom = session.bloom_filter

    Enum.find_value(landed_since_base, fn landed ->
      if Core.bloom_intersects(our_bloom, landed.bloom_filter) do
        find_actual_conflicts(session.paths, landed.paths)
      end
    end)
  end
end
```

### Usage from Go

```go
// #cgo LDFLAGS: -lhif_core
// #include <hif_core.h>
import "C"
import "unsafe"

type Tree struct {
    ptr *C.HifTree
}

func NewTree() *Tree {
    return &Tree{ptr: C.hif_tree_new(defaultAllocator)}
}

func (t *Tree) Insert(path string, hash [32]byte) *Tree {
    cpath := C.CString(path)
    defer C.free(unsafe.Pointer(cpath))
    newPtr := C.hif_tree_insert(t.ptr, cpath, (*C.uint8_t)(&hash[0]))
    return &Tree{ptr: newPtr}
}

func (t *Tree) Hash() [32]byte {
    var out [32]byte
    C.hif_tree_hash(t.ptr, (*C.uint8_t)(&out[0]))
    return out
}
```

---

## Core Concept: Sessions

hif has one concept: **sessions**.

A session captures everything about a unit of work:

```
Session: "Add authentication"
├── id: "ses_7f3a2b1c"
├── goal: "Add JWT-based login/logout to the API"
├── owner: "agent_claude_4a2f"
├── base: tree_hash_abc123       # snapshot session started from
├── state: open | landed | abandoned | conflicted
├── conversation:
│   ├── [human]: "We need login with email"
│   ├── [agent]: "Should I use JWT or sessions?"
│   └── [human]: "JWT"
├── decisions:
│   ├── "Using JWT because human specified"
│   └── "Put auth middleware in /middleware - existing pattern"
├── operations:                   # append-only log
│   ├── write src/auth/login.ts <hash>
│   ├── write src/auth/logout.ts <hash>
│   └── modify src/middleware/index.ts <hash>
├── bloom_filter: <paths touched>
└── timestamps:
    ├── created: HLC(1704067200, 0, node_a)
    └── updated: HLC(1704068400, 3, node_a)
```

### Why Sessions?

Sessions match how AI agents actually work. When Claude Code works on a task:
1. It has a **goal** (the user's request)
2. It has a **conversation** (back-and-forth with human)
3. It makes **decisions** (reasoning about approach)
4. It performs **operations** (file changes)

hif stores exactly this structure. The session IS the commit, the PR, and the conversation - unified.

### Session Lifecycle

```
                    ┌──────────────────┐
                    │   session start  │
                    │   (goal, owner)  │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │      OPEN        │◄────────┐
                    │                  │         │
                    │  - record ops    │         │ resolve
                    │  - add decisions │         │ conflict
                    │  - conversation  │         │
                    └────────┬─────────┘         │
                             │                   │
              ┌──────────────┼──────────────┐    │
              │              │              │    │
              ▼              ▼              ▼    │
     ┌─────────────┐ ┌─────────────┐ ┌──────────┴──┐
     │   LANDED    │ │  ABANDONED  │ │  CONFLICTED │
     │             │ │             │ │             │
     │  changes    │ │  discarded  │ │  needs      │
     │  integrated │ │             │ │  resolution │
     └─────────────┘ └─────────────┘ └─────────────┘
```

### Landing

Landing integrates a session's changes:

1. **Atomic** - all changes land together or none do
2. **Ordered** - global position number via consensus
3. **Non-blocking** - conflicts are recorded, not fatal

```bash
$ hif session land

Landing session ses_7f3a2b1c...
Position in queue: 3
Waiting for consensus...
Landed at position 847293
```

If conflicts are detected:

```bash
$ hif session land

Landing session ses_7f3a2b1c...
Conflict detected with ses_2d4e6f8a (landed 3s ago)
  Conflicting paths:
    - src/middleware/index.ts

Session marked CONFLICTED.
Resolve with: hif session resolve
```

---

## Forge Architecture

The forge is stateless compute. All state lives in S3. This is inspired by:
- [Turbopuffer](https://turbopuffer.com/docs/architecture): object storage-first vector DB
- [WarpStream](https://docs.warpstream.com/warpstream/overview/architecture): diskless Kafka with stateless agents
- [SlateDB](https://slatedb.io/): LSM tree on object storage

### S3 Storage Structure (Binary, Not JSON)

All hif data is stored in S3 using compact binary formats:

```
s3://hif-{org}/
└── projects/
    └── {project_id}/
        │
        ├── head                         # Current head (48 bytes, binary)
        │   [8 bytes: position (u64)]
        │   [32 bytes: tree_hash]
        │   [8 bytes: hlc_updated]
        │
        ├── landing-log/                 # Append-only landing log
        │   │
        │   ├── 00000000.log             # Positions 0-999 (binary, ~100KB each)
        │   ├── 00001000.log             # Positions 1000-1999
        │   ├── ...
        │   │
        │   └── bloom-index/             # Hierarchical bloom rollups
        │       ├── level-0/             # Individual landings (already in .log)
        │       ├── level-1/             # Bloom of 100 landings merged
        │       │   ├── 00000000.bloom
        │       │   ├── 00000100.bloom
        │       │   └── ...
        │       ├── level-2/             # Bloom of 10,000 landings merged
        │       │   ├── 00000000.bloom
        │       │   └── ...
        │       └── level-3/             # Bloom of 1M landings merged
        │           └── 00000000.bloom
        │
        ├── sessions/
        │   └── {session_id}.bin         # Complete session state (binary)
        │       [Header: 64 bytes]
        │       [Operations: variable]
        │       [Bloom filter: variable]
        │       [Decisions: variable]
        │       [Conversation: variable]
        │
        ├── trees/
        │   └── {hash[0:2]}/
        │       └── {hash}.bin           # Serialized B+ tree (binary)
        │
        └── blobs/
            └── {hash[0:2]}/
                └── {hash}               # Raw blob (zstd compressed)
```

### Binary Formats

**Head (48 bytes):**
```
┌────────────────────────────────────────────────────────┐
│  position (u64)  │  tree_hash (32 bytes)  │  hlc (8)  │
└────────────────────────────────────────────────────────┘
```

**Landing Log Entry (~200 bytes average):**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Header (40 bytes)                                                    │
│   position (u64) | session_id (16 bytes) | tree_hash_delta (varies) │
│   prev_position (u64)                                                │
├─────────────────────────────────────────────────────────────────────┤
│ Bloom Filter (64-512 bytes depending on paths touched)              │
├─────────────────────────────────────────────────────────────────────┤
│ Paths (variable, deduplicated via tree diff)                        │
│   count (u16) | [path_len (u16) | path_bytes]...                    │
└─────────────────────────────────────────────────────────────────────┘
```

**Session (binary, variable size):**
```
┌─────────────────────────────────────────────────────────────────────┐
│ Header (64 bytes)                                                    │
│   magic (4) | version (4) | id (16) | state (1) | base_pos (8)      │
│   owner_id (16) | hlc_created (8) | hlc_updated (8) | ...           │
├─────────────────────────────────────────────────────────────────────┤
│ Goal (length-prefixed UTF-8)                                        │
├─────────────────────────────────────────────────────────────────────┤
│ Operations (count + entries)                                         │
│   count (u32) | [op_type (1) | path_len (u16) | path | hash (32)]   │
├─────────────────────────────────────────────────────────────────────┤
│ Bloom Filter (serialized)                                           │
├─────────────────────────────────────────────────────────────────────┤
│ Decisions (count + length-prefixed strings)                         │
├─────────────────────────────────────────────────────────────────────┤
│ Conversation (count + role + length-prefixed strings)               │
└─────────────────────────────────────────────────────────────────────┘
```

### Auth Database (SQLite)

Only auth-related data lives in SQLite (replicated to S3 via Litestream):

```sql
-- Users
CREATE TABLE users (
    id TEXT PRIMARY KEY,              -- "user_abc123"
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TEXT NOT NULL
);

-- API tokens
CREATE TABLE tokens (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    token_hash TEXT NOT NULL,
    name TEXT,
    expires_at TEXT,
    created_at TEXT NOT NULL
);

-- Project permissions
CREATE TABLE permissions (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    user_id TEXT NOT NULL REFERENCES users(id),
    role TEXT NOT NULL,               -- 'owner', 'write', 'read'
    created_at TEXT NOT NULL,

    UNIQUE (project_id, user_id)
);
```

This database stays tiny (KB per user) and is replicated to S3 every second.

### Coordinator-Free Landing (via S3 Conditional Writes)

Unlike traditional VCS that needs a coordinator for serialization, hif uses
[S3 conditional writes](https://aws.amazon.com/about-aws/whats-new/2024/08/amazon-s3-conditional-writes/)
to achieve atomic landing without coordination.

```
┌─────────────────────────────────────────────────────────────────┐
│                   Landing Protocol (per agent)                   │
│                                                                 │
│  1. Read current head (position N, etag E)                      │
│                                                                 │
│  2. Conflict check via bloom rollups:                           │
│     - Load level-3 bloom (covers 1M landings) if N > 1M         │
│     - Load level-2 blooms for ranges not in level-3             │
│     - Load level-1 blooms for recent ranges                     │
│     - Check intersection with session bloom                     │
│     - If bloom intersects: load actual paths, verify conflict   │
│                                                                 │
│  3. Prepare landing:                                            │
│     - Compute new tree by applying session operations           │
│     - Write new tree to trees/{hash}.bin (idempotent)           │
│     - Write blobs to blobs/{hash} (idempotent)                  │
│                                                                 │
│  4. Atomic head update:                                         │
│     - PUT head with If-Match: E                                 │
│     - If 200 OK: landing succeeded at position N+1              │
│     - If 412 Precondition Failed: someone else landed first     │
│       → Retry from step 1 with exponential backoff              │
│                                                                 │
│  5. Append to landing log (async, eventually consistent):       │
│     - Append entry to current log segment                       │
│     - Update bloom rollups (background job)                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Why this works:**
- S3 `If-Match` provides atomic compare-and-swap
- Head file is tiny (48 bytes), so contention is low
- Trees and blobs are content-addressed (write is idempotent)
- Failed landings just retry (no corruption possible)
- Bloom rollups are eventually consistent (safe because they only cause false positives, not false negatives)

**Throughput analysis:**
- Assume 100ms per landing attempt (S3 roundtrip)
- With 10% contention rate: ~90% succeed first try
- With exponential backoff: avg 1.1 attempts per landing
- Theoretical max: ~1000 landings/second (S3 limit)
- Practical: 100k landings/day easily achievable

**For extreme scale (>100k landings/day):**
```
Partition by path prefix using separate head files:

head/src-auth          → landings touching src/auth/*
head/src-payments      → landings touching src/payments/*
head/_default          → cross-cutting or unpartitioned

Cross-partition landings use 2-phase protocol:
1. Lock all affected partitions (via conditional writes)
2. Commit all partitions
3. On failure: release locks, retry

Most landings (~95%) are single-partition.
```

### Bloom Filter Rollups (O(log n) Conflict Detection)

Inspired by [hierarchical bloom filters](https://genomebiology.biomedcentral.com/articles/10.1186/s13059-023-02971-4),
hif uses a multi-level bloom filter index for fast conflict detection.

```
Position:  0    100   200   ...  10000  ...  1000000

Level 0:   Each landing has its own bloom (in landing log)
           │     │     │          │           │

Level 1:   ├─────┴─────┤          │           │
           Bloom of 100 landings merged       │
           (one file per 100 positions)       │

Level 2:   ├──────────────────────┴───────────┤
           Bloom of 10,000 landings merged
           (one file per 10,000 positions)

Level 3:   ├──────────────────────────────────┴─────────────
           Bloom of 1,000,000 landings merged
           (one file per 1M positions)
```

**Conflict check algorithm:**
```
function hasConflict(session, basePosition, currentPosition):
    // Start from highest level, work down
    for level in [3, 2, 1, 0]:
        for each bloom at this level covering [basePosition, currentPosition]:
            if bloom.intersects(session.bloom):
                if level == 0:
                    // At finest granularity, check actual paths
                    return checkActualConflict(session, landing)
                else:
                    // Descend to finer granularity for this range
                    continue to next level for this range

    return false  // No conflict
```

**Complexity:**
- Without rollups: O(n) where n = currentPosition - basePosition
- With rollups: O(log n) bloom checks
- For 1M landings since base: ~4 bloom checks instead of 1M

**Bloom parameters:**
- Each bloom: 1KB, 0.1% false positive rate for 100 paths
- Level 1 (merged 100): 2KB, ~1% effective FP rate
- Level 2 (merged 10K): 4KB, ~5% effective FP rate
- Level 3 (merged 1M): 8KB, ~10% effective FP rate

False positives just mean we check actual paths (cheap).
False negatives are impossible (bloom filter property).

### Epoch Batching (High Throughput Mode)

For extreme throughput (>1000 landings/second), inspired by [Calvin](https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf)
and [CockroachDB's parallel commits](https://www.cockroachlabs.com/blog/parallel-commits/):

```
┌─────────────────────────────────────────────────────────────────┐
│                     Epoch-Based Landing                          │
│                                                                 │
│   Time:    |----10ms----|----10ms----|----10ms----|             │
│   Epoch:        N            N+1          N+2                   │
│                                                                 │
│   1. Collect phase (10ms):                                      │
│      - Agents submit land requests to any forge node            │
│      - Requests buffered in memory                              │
│      - No S3 writes yet                                         │
│                                                                 │
│   2. Sequence phase (instant):                                  │
│      - All requests in epoch get deterministic order            │
│      - Order by: (session_base_position, session_id)            │
│      - No coordination needed (deterministic)                   │
│                                                                 │
│   3. Conflict check phase (parallel):                           │
│      - Check all pairs within epoch for conflicts               │
│      - Check against previous epochs via bloom rollups          │
│      - Mark conflicting sessions                                │
│                                                                 │
│   4. Commit phase (single S3 write):                            │
│      - Write batch of N landings as single log segment          │
│      - Update head with If-Match                                │
│      - All non-conflicting sessions land atomically             │
│                                                                 │
│   Throughput: 100 landings/epoch × 100 epochs/sec = 10k/sec    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Trade-offs:**
- Latency: 10-20ms instead of ~100ms (better!)
- Throughput: 10,000/sec instead of ~10/sec (100x better!)
- Complexity: Requires epoch coordination between forge nodes
- Consistency: Slightly relaxed (within-epoch ordering is deterministic but arbitrary)

**When to use:**
- Default mode: S3 conditional writes (simple, low contention)
- High-throughput mode: Epoch batching (for >100 landings/sec)

The system can automatically switch based on observed contention rate.

### Blob Format

```
Small files (<4MB):
  [4 bytes: magic "HIFB"]
  [4 bytes: uncompressed size]
  [zstd compressed content]

Large files (>4MB) are chunked:
  [4 bytes: magic "HIFC"]
  [4 bytes: chunk count]
  [N x 32 bytes: chunk hashes]

  Each chunk stored separately as a blob.
```

### gRPC API

```protobuf
syntax = "proto3";
package hif.v1;

service HifService {
  // Sessions
  rpc StartSession(StartSessionRequest) returns (Session);
  rpc GetSession(GetSessionRequest) returns (Session);
  rpc LandSession(LandSessionRequest) returns (LandResult);
  rpc AbandonSession(AbandonSessionRequest) returns (Empty);
  rpc ResolveConflict(ResolveConflictRequest) returns (Session);

  // Operations
  rpc RecordOperation(RecordOperationRequest) returns (Empty);
  rpc RecordDecision(RecordDecisionRequest) returns (Empty);
  rpc RecordConversation(RecordConversationRequest) returns (Empty);

  // Content
  rpc GetTree(GetTreeRequest) returns (Tree);
  rpc GetBlob(GetBlobRequest) returns (stream BlobChunk);
  rpc PutBlob(stream BlobChunk) returns (PutBlobResponse);

  // Queries
  rpc ListSessions(ListSessionsRequest) returns (stream Session);
  rpc GetPathHistory(GetPathHistoryRequest) returns (stream PathEvent);
  rpc IsAncestor(IsAncestorRequest) returns (IsAncestorResponse);

  // Streaming
  rpc WatchSession(WatchSessionRequest) returns (stream SessionEvent);
  rpc WatchRepo(WatchRepoRequest) returns (stream RepoEvent);
}
```

---

## Client Architecture

The client is thin. It caches aggressively but trusts the forge.

### Phase 1: CLI Only

```
┌─────────────────────────────────────────────────────────────────┐
│                         hif CLI                                  │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   Session   │  │    gRPC     │  │    Local    │             │
│  │   Manager   │  │   Client    │  │    Cache    │             │
│  │             │  │             │  │             │             │
│  │ start/land  │  │ forge comms │  │ blobs/trees │             │
│  │ operations  │  │ streaming   │  │ LRU evict   │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│         │               │               │                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                     libhif-core                          │  │
│  │              (native Zig, no FFI overhead)              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

Files accessed via explicit commands:

```bash
$ hif cat src/auth/login.ts       # Fetch and print blob
$ hif write src/auth/login.ts     # Write from stdin
$ hif edit src/auth/login.ts      # Fetch, open in $EDITOR, write back
```

### Phase 2: Virtual Filesystem

```
┌─────────────────────────────────────────────────────────────────┐
│                        hif-fs daemon                             │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │    NFS      │  │   Session   │  │    Cache    │             │
│  │   Server    │  │   Overlay   │  │   Manager   │             │
│  │             │  │             │  │             │             │
│  │ localhost   │  │ local edits │  │ blob/tree   │             │
│  │ :2049       │  │ pre-land    │  │ LRU + pin   │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
         │
         │ mount
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  ~/repos/myproject/                                             │
│  ├── src/                      ← tree from forge                │
│  │   └── auth/                                                  │
│  │       └── login.ts          ← blob fetched on read          │
│  └── package.json              ← cached locally                 │
└─────────────────────────────────────────────────────────────────┘
```

NFS operations:

| NFS Op | hif-fs behavior |
|--------|-----------------|
| LOOKUP | Return inode from cached tree |
| READDIR | List tree children |
| READ | Fetch blob from cache or forge |
| WRITE | Write to session overlay |
| CREATE | Record operation, write overlay |
| REMOVE | Record delete operation |

---

## CLI Reference

```bash
# Setup
hif auth login                    # Authenticate with forge
hif project create <name>         # Create new project on forge
hif clone <project>               # Clone project locally

# Sessions
hif session start "goal"          # Start new session
hif session status                # Current session info
hif session list                  # List sessions
hif session land                  # Land current session
hif session abandon               # Abandon current session
hif session resolve               # Resolve conflicts
hif session claim <id>            # Claim orphaned session

# Content (Phase 1 - explicit)
hif cat <path>                    # Print file contents
hif write <path>                  # Write stdin to file
hif edit <path>                   # Edit file in $EDITOR
hif ls [path]                     # List directory

# Content (Phase 2 - via mount)
hif mount [path]                  # Mount virtual filesystem
hif unmount                       # Unmount

# Recording
hif decide "reasoning"            # Record a decision
hif converse "message"            # Add to conversation

# History
hif log                           # Show landed sessions
hif log --path <path>             # Sessions touching path
hif log --author <id>             # Sessions by author
hif diff <ref1> <ref2>            # Diff between states
hif blame <path>                  # Session that changed each line

# Navigation
hif goto @latest                  # Latest state
hif goto @position:N              # Specific position
hif goto @session:<id>            # Session's state

# Watching
hif watch                         # Stream project events
hif watch --session <id>          # Watch specific session
```

---

## Concurrency at Scale

### Target Numbers (Meta/Shopify Scale)

| Metric | Target | Notes |
|--------|--------|-------|
| Files per project | 1B+ | Google Piper has 1B+ files |
| Landings per day | 500,000+ | Google does 40k commits/day |
| Concurrent sessions | 100,000+ | Many agents working in parallel |
| Concurrent agents | 10,000+ | Hundreds per large project |
| Queries per second | 1,000,000+ | Reads via CDN |

### How We Achieve It

**1. Object Storage-First (like Turbopuffer)**
```
S3 is the source of truth, not a tier:
  - Infinite capacity ($0.023/GB/month)
  - 11 nines durability
  - Strong consistency (since 2020)
  - No database to shard or replicate
  - Inactive projects cost nearly nothing

Data inflates: S3 → SSD → RAM as needed
  - Cold query: ~400ms (4 S3 roundtrips)
  - Warm query: ~10ms (SSD cache)
  - Hot query: <1ms (RAM cache)
```

**2. Stateless Agents (like WarpStream)**
```
Any agent can handle any request:
  - No leader election, no partitioning
  - No state to replicate or sync
  - Agent failure is a non-event
  - Auto-scale based on CPU
  - Scale to zero when idle

Add capacity: just start more agents
Remove capacity: just stop agents
```

**3. Coordinator-Free Landing (S3 Conditional Writes)**
```
No single coordinator bottleneck:
  - S3 If-Match provides atomic CAS
  - Multiple agents can race to land
  - S3 picks the winner
  - Losers retry with backoff
  - ~1000 landings/second theoretical max

For extreme scale: partition by path prefix
  - 95% of landings are single-partition
  - Cross-partition uses 2PC with S3 locks
```

**4. O(log n) Conflict Detection (Bloom Rollups)**
```
Hierarchical bloom filters:
  - Level 0: Individual landings
  - Level 1: 100 landings merged
  - Level 2: 10,000 landings merged
  - Level 3: 1,000,000 landings merged

Conflict check for 1M landings:
  - Old way: scan 1M bloom filters
  - New way: ~4 bloom lookups

False positives: check actual paths (cheap)
False negatives: impossible (bloom property)
```

**5. Tiered Caching (like Turbopuffer)**
```
Tier 0: Client RAM      (MB)    - hot files, <1ms
Tier 1: Client SSD      (GB)    - working set, ~1ms
Tier 2: Agent SSD       (GB)    - shared cache, ~10ms
Tier 3: CDN edge        (TB)    - popular blobs, ~50ms
Tier 4: S3              (PB)    - everything, ~100ms

Most reads hit tier 0-2, rarely touch S3.
Cursor uses this pattern: 10M+ namespaces, 95% cost reduction.
```

**6. CDN for Immutable Data**
```
Content-addressed blobs and trees:
  - CloudFront/Cloudflare in front of S3
  - Infinite cache TTL (hash = content)
  - Global edge distribution
  - Cache invalidation: never needed

Mutable data (head, sessions):
  - Always read from S3 (strong consistency)
  - Small (48 bytes for head)
  - Cached briefly on agents
```

**7. Binary Everywhere**
```
No JSON, all binary formats:
  - Trees: compact B+ tree serialization
  - Blooms: raw bit arrays
  - Sessions: length-prefixed fields
  - Head: fixed 48 bytes

Parsing: zero-copy where possible
Size: 10-50x smaller than JSON
Speed: 100x faster than JSON parse
```

---

## Deterministic Simulation Testing

Inspired by [TigerBeetle](https://tigerbeetle.com/) and [FoundationDB](https://apple.github.io/foundationdb/testing.html),
hif uses deterministic simulation to test decades of failures in hours.

### Lesson from FoundationDB: Build Simulation First

FoundationDB spent their **first two weeks** building their simulation framework (Flow)
before writing any database code. Their insight:

> "You can't add deterministic simulation to an existing system.
> You have to design for it from day one."

This means hif must:
1. Abstract ALL non-determinism behind interfaces from the start
2. Build the simulator before the forge
3. Run simulation tests in CI from day one

```
┌─────────────────────────────────────────────────────────────────┐
│                    Abstraction Layer (Day 1)                     │
│                                                                 │
│   // All I/O goes through interfaces                            │
│   trait ObjectStore {                                           │
│       fn get(key) -> Result<Bytes>;                             │
│       fn put(key, data, condition) -> Result<()>;               │
│       fn delete(key) -> Result<()>;                             │
│   }                                                             │
│                                                                 │
│   trait Clock {                                                 │
│       fn now() -> Timestamp;                                    │
│       fn tick(duration);  // For simulation                     │
│   }                                                             │
│                                                                 │
│   trait Random {                                                │
│       fn next_u64() -> u64;  // Seeded for determinism          │
│   }                                                             │
│                                                                 │
│   // Production: real S3, system clock, crypto PRNG             │
│   // Simulation: in-memory store, tick clock, seeded PRNG       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Simulator Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    VOPR-style Simulator                          │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                  Simulated Cluster                       │   │
│   │                                                         │   │
│   │   ┌─────────┐  ┌─────────┐  ┌─────────┐                │   │
│   │   │ Agent 1 │  │ Agent 2 │  │ Agent 3 │                │   │
│   │   └────┬────┘  └────┬────┘  └────┬────┘                │   │
│   │        │            │            │                      │   │
│   │   ┌────┴────────────┴────────────┴────┐                │   │
│   │   │         Simulated S3              │                │   │
│   │   │   (in-memory, fault-injectable)   │                │   │
│   │   └───────────────────────────────────┘                │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   Fault Injection:                                              │
│   - Network partitions between agents                           │
│   - S3 request failures (500, 503, timeouts)                   │
│   - S3 conditional write races                                  │
│   - Clock skew between agents                                   │
│   - Agent crashes and restarts                                  │
│   - Slow S3 responses (latency injection)                       │
│   - Partial failures (write succeeds, agent crashes)            │
│                                                                 │
│   Determinism:                                                  │
│   - Single-threaded execution                                   │
│   - Controllable clock (tick-based)                             │
│   - Seeded PRNG for fault injection                             │
│   - Any failure reproducible by seed                            │
│                                                                 │
│   Time dilation:                                                │
│   - 1 hour simulation = 1 month real-world                     │
│   - 24/7 on 100 cores = 200 years/day of testing               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Stress Test Patterns (from FoundationDB)

**"Swizzle Clogging"** - finds subtle ordering bugs:
```
1. Randomly select N agents
2. Sequentially stop their S3 connections
3. Let them queue operations
4. Unclog in random order
5. Verify all operations complete correctly
```

**"Crash Loop"** - finds recovery bugs:
```
1. Start landing operation
2. Crash agent at random point (before/during/after S3 write)
3. Restart agent
4. Verify: either landing completed or can be retried
5. Verify: no duplicate landings, no data loss
```

**"Clock Skew"** - finds HLC bugs:
```
1. Skew agent clocks by random amounts (-5s to +5s)
2. Perform landings from multiple agents
3. Verify: HLC ordering is consistent
4. Verify: no causality violations
```

### What We Verify

- Landing atomicity (all-or-nothing)
- Conflict detection correctness (no false negatives)
- Bloom rollup consistency (rollups match individual blooms)
- Head monotonicity (position never decreases)
- No data loss under any failure sequence
- Eventual consistency of landing log
- Recovery correctness (can always rebuild from S3)
- HLC causality (if A caused B, HLC(A) < HLC(B))

### Implementation Priority

From FoundationDB's experience:
1. **Week 1-2**: Build abstraction layer and basic simulator
2. **Week 3+**: Build features with simulation tests from day one
3. **Ongoing**: Run thousands of simulations nightly in CI

---

## Sparse Checkout (Lazy File Fetching)

Inspired by [Microsoft Scalar](https://github.blog/2022-10-13-the-story-of-scalar/) and
[VFSForGit](https://github.com/microsoft/VFSForGit), hif only fetches files you actually touch.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Sparse Working Copy                           │
│                                                                 │
│   Project: 10M files, 500GB total                               │
│   Clone time: <1 second (just metadata)                         │
│   Disk usage: ~10MB (just tree + touched files)                 │
│                                                                 │
│   Tree structure (always local):                                │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  src/                                                   │   │
│   │  ├── auth/                                              │   │
│   │  │   ├── login.ts     → blob:abc123 (not fetched)      │   │
│   │  │   └── logout.ts    → blob:def456 (not fetched)      │   │
│   │  ├── payments/                                          │   │
│   │  │   └── stripe.ts    → blob:789abc (FETCHED)          │   │
│   │  └── ...                                                │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   On file read (cat, edit, IDE open):                           │
│   1. Check local cache                                          │
│   2. If miss: fetch blob from forge                             │
│   3. Cache locally for future reads                             │
│   4. Return content                                             │
│                                                                 │
│   Prefetch hints:                                               │
│   - IDE opens folder → prefetch visible files                   │
│   - Build starts → prefetch build inputs                        │
│   - Agent claims paths → prefetch those paths                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Benefits:**
- Clone 10M file repo in <1 second
- Disk usage proportional to working set, not repo size
- Network usage proportional to files touched
- Agents can work on massive monorepos without full checkout

**Implementation phases:**
1. Phase 1: Explicit fetch (`hif cat`, `hif edit`)
2. Phase 2: NFS mount with lazy fetch (hif-fs)
3. Phase 3: Prefetch heuristics and IDE integration

---

## Failure Handling

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Agent crash | Lease expires (no heartbeat) | Session orphaned, can be claimed |
| Forge unavailable | Connection timeout | Queue operations locally, sync on reconnect |
| Landing conflict | Bloom/path check | Mark CONFLICTED, agent resolves |
| Corrupt blob | Hash mismatch | Re-fetch from forge |
| Corrupt index | Checksum fail | Rebuild from source data |
| S3 temporary failure | 5xx response | Exponential backoff retry |
| Landing race | 412 Precondition Failed | Re-read head, retry landing |
| Bloom rollup stale | Background job lag | Fall back to finer-grained blooms |

---

## Codebase Structure

```
hif/
├── src/
│   ├── core/                    # libhif-core
│   │   ├── hash.zig            # Blake3 hashing, chunking
│   │   ├── bloom.zig           # Bloom filters
│   │   ├── tree.zig            # Prolly trees
│   │   ├── changelog.zig       # Segmented changelog
│   │   ├── hlc.zig             # Hybrid logical clock
│   │   └── c_api.zig           # C ABI exports
│   │
│   ├── client/                  # hif CLI
│   │   ├── main.zig            # Entry point
│   │   ├── commands/           # CLI commands
│   │   │   ├── session.zig
│   │   │   ├── content.zig
│   │   │   └── ...
│   │   ├── grpc.zig            # Forge client
│   │   ├── cache.zig           # Local cache
│   │   └── config.zig          # Configuration
│   │
│   ├── fs/                      # hif-fs (Phase 2)
│   │   ├── nfs.zig             # NFS server
│   │   ├── overlay.zig         # Session overlay
│   │   └── mount.zig           # Mount management
│   │
│   └── root.zig                 # Library entry
│
├── include/
│   └── hif_core.h               # C header
│
├── build.zig
└── DESIGN.md
```

### Build Outputs

```bash
$ zig build

zig-out/
├── bin/
│   ├── hif                      # CLI binary
│   └── hif-fs                   # FS daemon (Phase 2)
├── lib/
│   ├── libhif_core.a           # Static library
│   └── libhif_core.so          # Shared library
└── include/
    └── hif_core.h              # C header
```

---

## Implementation Phases

### Phase 1: Foundation

**libhif-core:**
- [x] Blake3 hashing
- [x] Bloom filters
- [x] Basic tree (insert, delete, hash)
- [x] HLC timestamps
- [x] C API + header
- [ ] Binary serialization for all types
- [ ] Bloom filter merge/rollup operations

**hif CLI:**
- [x] Project/clone/auth command structure
- [ ] Session start/land/abandon
- [ ] Local config (~/.hif/)
- [ ] gRPC client to forge
- [ ] Tiered cache (RAM → SSD)

**Forge:**
- [ ] SQLite + Litestream setup
- [ ] Auth (users, tokens)
- [ ] S3 storage layer (binary formats)
- [ ] Session CRUD (read/write to S3)
- [ ] Basic API endpoints

**Testing:**
- [ ] Deterministic simulation framework
- [ ] In-memory S3 fake with fault injection
- [ ] Seeded PRNG for reproducibility

### Phase 2: Landing

**Forge:**
- [ ] S3 conditional writes (If-Match) for landing
- [ ] Conflict detection via bloom filters
- [ ] Tree building on land
- [ ] Binary head file updates
- [ ] Landing log segments

**libhif-core:**
- [ ] Bloom filter rollup builder
- [ ] Hierarchical bloom index queries

**hif CLI:**
- [ ] session land command
- [ ] Conflict resolution flow
- [ ] cat, write, edit, ls (sparse checkout)

### Phase 3: Scale

**Forge:**
- [ ] Bloom filter rollup background job
- [ ] Epoch batching mode (high throughput)
- [ ] Partitioned landing (path-based)
- [ ] CDN integration for blobs

**hif CLI:**
- [ ] Prefetch hints
- [ ] Background blob fetching
- [ ] log, diff, blame
- [ ] goto navigation
- [ ] watch (streaming)

**hif-fs:**
- [ ] NFS server (read path)
- [ ] Local cache with LRU
- [ ] Session overlay (write path)
- [ ] Mount/unmount
- [ ] Prefetch on directory open

### Phase 4: Production

**Forge:**
- [ ] Rate limiting
- [ ] Webhooks
- [ ] Multi-region replication
- [ ] Metrics and observability

**Testing:**
- [ ] Continuous simulation (24/7)
- [ ] Chaos testing in staging
- [ ] Jepsen-style linearizability tests

**Operations:**
- [ ] Monitoring + alerting
- [ ] S3 replication (multi-region)
- [ ] Git import tool

---

## Open Questions

### Offline Mode

Should small projects work without a forge?
- Useful for: personal projects, air-gapped environments
- Cost: two code paths to maintain

### Git Interop

What level of Git compatibility?
- Import: definitely (one-time migration)
- Export: maybe (escape hatch)
- Bidirectional sync: probably not worth complexity

### Session Hierarchy

Can sessions have sub-sessions?
```
Session: "Refactor auth"
├── Sub-session: "Extract JWT"
├── Sub-session: "Add refresh tokens"
└── Sub-session: "Update tests"
```

### IDE Integration

How should IDEs integrate?
- LSP-style daemon?
- Direct gRPC to forge?
- Via virtual filesystem only?

---

*This design targets Google/Meta scale (1B+ files, 500k+ landings/day) while prioritizing agent-first workflows.*

**Inspired by:**
- [Turbopuffer](https://turbopuffer.com/) - Object storage-first architecture, tiered caching
- [WarpStream](https://www.warpstream.com/) - Stateless agents, diskless streaming
- [SlateDB](https://slatedb.io/) - LSM trees on object storage
- [Calvin](https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf) - Deterministic transaction ordering
- [TigerBeetle](https://tigerbeetle.com/) - Deterministic simulation testing
- [FoundationDB](https://www.foundationdb.org/) - Simulation testing, unbundled architecture
- [CockroachDB](https://www.cockroachlabs.com/blog/parallel-commits/) - Parallel commits, transaction pipelining
- [Neon](https://neon.tech/) - Postgres storage disaggregation
- [Microsoft Scalar](https://github.blog/2022-10-13-the-story-of-scalar/) - Sparse checkout for massive repos
- [Google Piper](https://cacm.acm.org/research/why-google-stores-billions-of-lines-of-code-in-a-single-repository/) - Monorepo at billion-file scale

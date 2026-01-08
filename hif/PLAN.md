# hif - Implementation Plan

This document breaks down the implementation into concrete, actionable steps. Each phase builds on the previous one, with clear deliverables and milestones.

---

## Phase 1: Foundation

**Goal:** Working end-to-end flow for a single user starting, editing, and landing a session.

### 1.1 libhif-core Basics

Complete the core algorithmic primitives.

| Task | Description | Dependencies |
|------|-------------|--------------|
| `core/hash.zig` | Blake3 hashing for blobs and trees | Done |
| `core/bloom.zig` | Bloom filters for conflict detection | hash.zig |
| `core/hlc.zig` | Hybrid Logical Clock for timestamps | None |
| `core/tree.zig` | Basic prolly tree (insert, delete, get, hash) | hash.zig |
| `core/c_api.zig` | C ABI exports for all modules | All above |
| `include/hif_core.h` | Generated C header | c_api.zig |

**Tests:**
- Bloom filter false positive rate within bounds
- HLC monotonicity and causality
- Tree deterministic hashing
- C API roundtrip from test harness

**Deliverable:** `libhif_core.a` and `libhif_core.so` with C header

### 1.2 Forge Skeleton (Separate Repo)

Minimal forge that can store and retrieve data.

| Task | Description | Dependencies |
|------|-------------|--------------|
| Project setup | Elixir/Phoenix or Go project structure | None |
| Database schema | Sessions, operations, trees tables | None |
| libhif-core FFI | Integrate via Zigler/cgo | libhif-core |
| gRPC server | Basic protobuf + server skeleton | None |
| Session CRUD | StartSession, GetSession, AbandonSession | Schema |
| Blob storage | S3/MinIO integration | None |
| Basic auth | Token-based authentication | None |

**Tests:**
- Create session, record operations, retrieve
- Upload/download blob roundtrip
- Session state transitions

**Deliverable:** Running forge that can store sessions and blobs

### 1.3 CLI Foundation

Basic CLI that talks to the forge.

| Task | Description | Dependencies |
|------|-------------|--------------|
| gRPC client | Connect to forge, handle auth | Forge gRPC |
| `hif auth login` | Token-based authentication | gRPC client |
| `hif session start` | Create session with goal | gRPC client |
| `hif session status` | Show current session | gRPC client |
| `hif session abandon` | Abandon current session | gRPC client |
| `hif cat <path>` | Fetch and print blob | Blob storage |
| `hif write <path>` | Write stdin to blob, record op | Blob storage |
| `hif ls [path]` | List tree contents | Tree storage |
| Local config | Store forge URL, token, current session | None |

**Tests:**
- Full session lifecycle via CLI
- Write file, cat file roundtrip
- Error handling for offline forge

**Deliverable:** Working CLI for basic session workflow

### 1.4 Landing (Simple)

Single-threaded landing without conflict detection.

| Task | Description | Dependencies |
|------|-------------|--------------|
| `hif session land` | Request landing from CLI | CLI foundation |
| Landing endpoint | Process land request on forge | Forge skeleton |
| Position assignment | Atomic counter for global position | Database |
| Tree update | Apply operations to build new tree | tree.zig |
| State transition | Mark session as landed | Database |

**Tests:**
- Land session, verify position assigned
- Land multiple sessions sequentially
- Retrieve tree at specific position

**Deliverable:** Sessions can be landed and queried by position

---

## Phase 2: Conflict Detection

**Goal:** Multiple agents can work concurrently with automatic conflict detection.

### 2.1 Bloom Filter Integration

| Task | Description | Dependencies |
|------|-------------|--------------|
| Bloom per session | Create bloom on session start | bloom.zig |
| Add paths to bloom | Update bloom on each operation | bloom.zig |
| Store bloom | Serialize and store with session | Database |
| Bloom intersection | Check overlap before landing | bloom.zig |

### 2.2 Path Index

| Task | Description | Dependencies |
|------|-------------|--------------|
| Path index table | Track which sessions touch which paths | Database |
| Update on operation | Add path to index on write/delete | Operations |
| Query by path | Find sessions touching a path | Database |
| Conflict check | If bloom intersects, check path index | Bloom, Index |

### 2.3 Conflict Resolution

| Task | Description | Dependencies |
|------|-------------|--------------|
| CONFLICTED state | New session state | Database |
| Mark conflicted | Set state when conflict detected | Landing |
| `hif session resolve` | Interactive conflict resolution | CLI |
| Merge strategies | Last-writer-wins, manual, auto-merge | Core |

**Tests:**
- Two sessions touching same file conflict
- Two sessions touching different files don't conflict
- Conflict resolution flow works

**Deliverable:** Concurrent sessions with conflict detection

---

## Phase 3: Decisions and Conversation

**Goal:** Sessions capture the "why" not just the "what".

### 3.1 Decision Recording

| Task | Description | Dependencies |
|------|-------------|--------------|
| Decisions table | Store decisions with HLC ordering | Database |
| `hif decide "text"` | Record a decision | CLI |
| RecordDecision RPC | gRPC endpoint | Forge |
| Show in status | Display decisions in session status | CLI |

### 3.2 Conversation Recording

| Task | Description | Dependencies |
|------|-------------|--------------|
| Conversation table | Store messages with role and HLC | Database |
| `hif converse "msg"` | Add conversation entry | CLI |
| RecordConversation RPC | gRPC endpoint | Forge |
| Conversation retrieval | Include in session details | CLI |

**Deliverable:** Full session context preserved

---

## Phase 4: History and Navigation

**Goal:** Navigate repository history efficiently.

### 4.1 Segmented Changelog

| Task | Description | Dependencies |
|------|-------------|--------------|
| `core/changelog.zig` | Segmented changelog data structure | None |
| Ancestry table | Store parent relationships | Database |
| IsAncestor query | O(log n) ancestry check | changelog.zig |
| CommonAncestor query | Find merge base | changelog.zig |

### 4.2 History Commands

| Task | Description | Dependencies |
|------|-------------|--------------|
| `hif log` | List landed sessions | Forge |
| `hif log --path` | Sessions touching path | Path index |
| `hif log --author` | Sessions by author | Database |
| `hif diff` | Diff between two states | tree.zig |
| `hif blame` | Session that last changed each line | Path index |

### 4.3 Navigation

| Task | Description | Dependencies |
|------|-------------|--------------|
| `hif goto @latest` | View latest tree state | Trees |
| `hif goto @position:N` | View tree at position N | Trees |
| `hif goto @session:id` | View session's tree state | Trees |

**Deliverable:** Full history exploration

---

## Phase 5: Local Cache

**Goal:** Fast local operations with aggressive caching.

### 5.1 Blob Cache

| Task | Description | Dependencies |
|------|-------------|--------------|
| Cache directory | `~/.hif/cache/blobs/` structure | None |
| LRU eviction | Evict old blobs when cache full | None |
| Hash verification | Verify blob hash on read | hash.zig |
| Prefetching | Fetch blobs likely to be needed | Heuristics |

### 5.2 Tree Cache

| Task | Description | Dependencies |
|------|-------------|--------------|
| Tree cache | Cache serialized trees | None |
| Invalidation | Clear on new landings | Watch stream |

### 5.3 Watch Streaming

| Task | Description | Dependencies |
|------|-------------|--------------|
| WatchRepo RPC | Stream repo events | Forge |
| WatchSession RPC | Stream session events | Forge |
| `hif watch` | CLI streaming output | RPC |
| Cache invalidation | Update cache on events | Streaming |

**Deliverable:** Sub-second response for cached content

---

## Phase 6: Virtual Filesystem (hif-fs)

**Goal:** Seamless filesystem integration via NFS.

### 6.1 NFS Server

| Task | Description | Dependencies |
|------|-------------|--------------|
| `fs/nfs.zig` | NFS v3 server implementation | None |
| LOOKUP handler | Return inode from tree | Tree cache |
| READDIR handler | List directory contents | Tree cache |
| READ handler | Fetch blob content | Blob cache |
| GETATTR handler | Return file metadata | Tree cache |

### 6.2 Session Overlay

| Task | Description | Dependencies |
|------|-------------|--------------|
| `fs/overlay.zig` | Layer local changes over base tree | None |
| WRITE handler | Write to overlay | Overlay |
| CREATE handler | Create in overlay, record op | Overlay |
| REMOVE handler | Mark deleted in overlay | Overlay |
| Sync to forge | Flush overlay operations | gRPC |

### 6.3 Mount Management

| Task | Description | Dependencies |
|------|-------------|--------------|
| `hif mount` | Start NFS server, mount | NFS server |
| `hif unmount` | Unmount, stop server | Mount |
| Auto-mount | Mount on session start | Config |
| Daemon mode | Background NFS server | Process mgmt |

**Deliverable:** Edit files with any editor/IDE

---

## Phase 7: Scale

**Goal:** Handle Google/Meta-scale repositories.

### 7.1 Raft Landing Queue

| Task | Description | Dependencies |
|------|-------------|--------------|
| Raft consensus | Leader election for landing | Forge |
| Landing queue | Queue land requests | Raft |
| Parallel landing | Land non-conflicting sessions in parallel | Bloom |

### 7.2 Sharding

| Task | Description | Dependencies |
|------|-------------|--------------|
| Repo sharding | Shard by repo_id | Database |
| Path partitioning | Partition landings by path prefix | Landing |

### 7.3 CDN Integration

| Task | Description | Dependencies |
|------|-------------|--------------|
| CDN blob storage | Serve blobs via CDN | S3 |
| Signed URLs | Generate signed download URLs | Auth |
| Edge caching | Configure CDN caching rules | CDN |

### 7.4 Delta Compression

| Task | Description | Dependencies |
|------|-------------|--------------|
| Delta encoding | Store deltas between versions | hash.zig |
| Pack files | Group related blobs | Storage |
| Lazy unpacking | Decompress on demand | Cache |

**Deliverable:** 100M+ files, 100K+ landings/day

---

## Phase 8: Browser/WASM Support

**Goal:** Run hif client in the browser.

### 8.1 WASM Build

| Task | Description | Dependencies |
|------|-------------|--------------|
| WASM target | Build libhif-core for wasm32 | build.zig |
| JS bindings | JavaScript wrapper for WASM | WASM build |
| IndexedDB cache | Browser-based blob cache | JS bindings |

### 8.2 gRPC-Web

| Task | Description | Dependencies |
|------|-------------|--------------|
| gRPC-Web proxy | Envoy or similar | Forge |
| Web client | gRPC-Web client in TypeScript | gRPC-Web |

### 8.3 Web UI

| Task | Description | Dependencies |
|------|-------------|--------------|
| Session viewer | View session details | Web client |
| File browser | Browse tree, view blobs | Web client |
| Monaco integration | Code editor in browser | Web client |

**Deliverable:** Browser-based hif client

---

## Phase 9: Production Readiness

**Goal:** Production-grade reliability and operations.

### 9.1 Observability

| Task | Description | Dependencies |
|------|-------------|--------------|
| Structured logging | JSON logs with trace IDs | All |
| Metrics | Prometheus metrics | Forge |
| Tracing | OpenTelemetry spans | Forge, CLI |
| Dashboards | Grafana dashboards | Metrics |

### 9.2 Reliability

| Task | Description | Dependencies |
|------|-------------|--------------|
| Rate limiting | Per-user rate limits | Forge |
| Circuit breakers | Handle downstream failures | Forge |
| Retry logic | Exponential backoff | CLI |
| Health checks | Liveness/readiness probes | Forge |

### 9.3 Security

| Task | Description | Dependencies |
|------|-------------|--------------|
| mTLS | Client certificate auth | All |
| RBAC | Role-based access control | Forge |
| Audit logging | Log all mutations | Forge |
| Secret scanning | Prevent secret commits | Forge |

### 9.4 Operations

| Task | Description | Dependencies |
|------|-------------|--------------|
| Backup/restore | Database and blob backup | Forge |
| Disaster recovery | Multi-region failover | Infrastructure |
| Upgrade path | Zero-downtime upgrades | Forge |
| Git import | One-time migration from Git | Forge |

**Deliverable:** Production-ready hif

---

## Milestone Summary

| Milestone | Description | Key Deliverable |
|-----------|-------------|-----------------|
| M1 | Foundation | Single-user session workflow |
| M2 | Concurrency | Conflict detection works |
| M3 | Context | Decisions and conversation captured |
| M4 | History | Navigate and explore history |
| M5 | Performance | Sub-second cached operations |
| M6 | Filesystem | Mount and edit with any tool |
| M7 | Scale | 100M files, 100K landings/day |
| M8 | Browser | Web-based client |
| M9 | Production | Reliable, secure, observable |

---

## Current Status

- [x] Project initialized with Zig 0.15
- [x] `core/hash.zig` - Blake3 hashing
- [x] `core/bloom.zig` - Bloom filters for conflict detection
- [x] `core/hlc.zig` - Hybrid Logical Clock for distributed timestamps
- [x] `core/tree.zig` - B+ tree for directory structures
- [x] `src/ffi.zig` - C ABI exports for all core modules
- [x] `include/hif_core.h` - C header with documentation
- [x] Header sync tests - Verify header matches FFI exports
- [x] Integration tests - End-to-end workflow tests
- [ ] Forge skeleton
- [ ] Basic CLI commands

**Phase 1.1 Complete!**

**Next:** Phase 1.2 - Forge Skeleton (separate repo)

---

## Testing Strategy

### Unit Tests
Each core module includes comprehensive unit tests covering:
- Normal operation paths
- Edge cases (empty inputs, max values, unicode)
- Error conditions and proper error propagation

### Integration Tests (Planned)
End-to-end scenarios to be added:
- Full session workflow: start -> edit -> land
- Concurrent session conflict detection
- CLI command sequences
- FFI roundtrip from C test harness

### FFI Testing
The C API (`c_api.zig` + `hif_core.h`) will include:
- All core module operations exposed via C ABI
- Error message retrieval API
- Version and capability checking
- Test harness in C for validation

---

## Architecture Notes

### Tree Implementation
The current `tree.zig` uses a sorted ArrayList for simplicity:
- O(log n) lookups via binary search
- O(n) insertions due to re-sorting
- Suitable for small to medium trees (< 10K entries)

For large-scale repositories (100K+ files), a proper B-tree or prolly tree
with probabilistic chunking boundaries would be needed. This is deferred
to Phase 7 (Scale) when actual performance requirements are known.

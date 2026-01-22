# Micelio Session Architecture

This document describes the session architecture with S3 for immutable blob and tree storage, and a custom NFS server for session isolation and copy-on-write semantics.

## Overview

Micelio sessions represent isolated units of work with full reproducibility guarantees. Each session captures:

- **Goal**: What the session aims to accomplish
- **Conversation**: Dialog between agents and humans
- **Decisions**: Why changes were made
- **Snapshot**: Point-in-time view of the project tree

## Architecture Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Micelio Session Architecture                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Local Developer                              │    │
│  │                                                                      │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │    │
│  │  │    mic CLI   │  │   mic-fs     │  │   Custom NFS Server      │  │    │
│  │  │  (Zig CLI)   │  │  (NFS Daemon)│  │  (hif/src/fs/nfs.zig)    │  │    │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    S3 (Source of Truth)                              │    │
│  │                                                                      │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐ │    │
│  │  │   Blobs     │  │   Trees     │  │      Sessions               │ │    │
│  │  │             │  │             │  │                             │ │    │
│  │  │ - content   │  │ - B+ tree   │  │ - metadata (goal, status)   │ │    │
│  │  │ - addressed │  │ - in S3!    │  │ - session tree (base+diff)  │ │    │
│  │  │ - immutable │  │ - indexed   │  │ - conversation + decisions  │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────┘ │    │
│  │                                                                      │    │
│  │  S3 is the single source of truth for all data                      │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Core Concepts

### 1. S3: Source of Truth

All data lives in S3 - **blobs, trees, and sessions**:

**Blobs** - Content-addressed file content:
```
s3://micelio-{org}/projects/{project_id}/
└── blobs/
    └── {hash[0:2]}/
        └── {hash}          # Raw blob content, zstd compressed
```

**Trees** - B+ tree structures stored in S3:
```
s3://micelio-{org}/projects/{project_id}/
└── trees/
    └── {hash[0:2]}/
        └── {hash}          # Serialized B+ tree (content-addressed)
```

**Sessions** - Session metadata and trees:
```
s3://micelio-{org}/projects/{project_id}/
└── sessions/
    └── {session_id}/
        ├── metadata.json   # Goal, conversation, decisions
        └── tree.json       # Session tree (base + diff)
```

**Key properties:**
- **Content-addressed**: Hash = SHA-256 of content
- **Immutable**: Never modified, only created
- **Deduplicated**: Same content = same blob (automatic)
- **Source of truth**: S3 is the single source, no filesystem dependencies

### 2. Custom NFS Server: CoW Semantics

The NFS server (`hif/src/fs/nfs.zig`) implements **copy-on-write semantics**:

```
┌─────────────────────────────────────────────────────────┐
│           Custom NFS Server (hif/src/fs/nfs.zig)        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  CoW Semantics Implemented:                              │
│  ├── Read: Return blob from S3 (cached locally)         │
│  ├── Write: Create new blob in S3, update tree          │
│  ├── Delete: Mark blob as deleted (immutable storage)   │
│  └── Snapshot: Export tree hash as read-only view       │
│                                                          │
│  Per-Session Exports:                                    │
│  ├── /exports/sessions/{session-id}/                    │
│  │   └── @ (points to session's base tree in S3)        │
│  │                                                        │
│  Isolation Guarantees:                                   │
│  ├── Session A sees: tree-A (its snapshot)              │
│  ├── Session B sees: tree-B (its snapshot)              │
│  └── Neither sees other's unlanded changes              │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**Why custom NFS server?**
- **No BTRFS dependency**: We control CoW semantics ourselves
- **Portable**: Works on any OS, not tied to filesystem features
- **Session isolation**: Each session gets its own export
- **S3-backed**: All data ultimately lives in S3

### 3. Copy-on-Write: Concept, Not Filesystem

Copy-on-write (CoW) is a **data design pattern**, not a filesystem feature:

| CoW as Filesystem Feature | CoW as Data Pattern |
|---------------------------|---------------------|
| BTRFS, ZFS, APFS | Our NFS server implements it |
| Kernel-level | Application-level (Zig) |
| Tied to filesystem | Works with any storage (S3) |
| Platform-dependent | Portable across platforms |

**How we implement CoW:**
1. **Read**: NFS reads blob from S3, caches locally
2. **Write**: NFS creates NEW blob in S3, updates session tree
3. **Snapshot**: NFS exports session tree hash as read-only view
4. **Landing**: Merge session tree to base tree (new tree in S3)

### 4. Sessions as Snapshots

Each session starts with a **snapshot** of the current project tree:

```
Session Lifecycle:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  1. Session Start                                               │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ mic session start "add auth middleware"             │    │
│     │                                                      │    │
│     │ - Snapshot current tree (T0) in S3                  │    │
│     │ - Create session record with goal + conversation    │    │
│     │ - Allocate session-specific NFS export              │    │
│     │ - Return session context to agent                   │    │
│     └─────────────────────────────────────────────────────┘    │
│                              │                                │
│                              ▼                                │
│  2. Edit Phase (Session Isolation)                             │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ Agent makes changes:                                │    │
│     │                                                      │    │
│     │ - Create new blobs in S3 (immutable)                │    │
│     │ - Update session tree with new blob refs            │    │
│     │ - Base tree (T0) remains unchanged in S3            │    │
│     │ - Other sessions don't see these changes            │    │
│     │                                                      │    │
│     │ Session tree:                                        │    │
│     │   base: T0 (tree hash in S3)                        │    │
│     │   diff: +auth.go, ~main.go (new blob refs)          │    │
│     └─────────────────────────────────────────────────────┘    │
│                              │                                │
│                              ▼                                │
│  3. Landing (Merge to Base)                                    │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ mic land                                             │    │
│     │                                                      │    │
│     │ - Compute new tree from: base_tree + session diff   │    │
│     │ - Store new tree in S3 (immutable)                  │    │
│     │ - Update project head to new tree hash              │    │
│     │ - Archive session as "landed"                       │    │
│     │                                                      │    │
│     │ Result:                                              │    │
│     │   Old: T0 = {file1.go, file2.go}                    │    │
│     │   Session: T0 + {+auth.go, ~main.go}                │    │
│     │   New: T1 = {file1.go, file2.go, auth.go, main.go}  │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5. NFS Exports for Consistency

Each session gets its own NFS export pointing to its snapshot in S3:

```
Session NFS Exports:
┌─────────────────────────────────────────────────────────────┐
│  Session A Export:  /exports/sessions/session-a            │
│  → Points to: tree hash T0 in S3                           │
│  → Sees: snapshot of tree T0                               │
│  → Does NOT see: unlanded changes from Session B           │
│                                                              │
│  Session B Export:  /exports/sessions/session-b            │
│  → Points to: tree hash T0 in S3                           │
│  → Sees: snapshot of tree T0                               │
│  → Independent from Session A                               │
│                                                              │
│  Landing creates new tree T1 in S3, doesn't modify T0      │
│  Cloning session sees same snapshot on any machine          │
└─────────────────────────────────────────────────────────────┘
```

## Consistency Guarantees

| Property | How It's Achieved |
|----------|-------------------|
| **Isolation** | Each session has dedicated NFS export pointing to its snapshot tree in S3 |
| **Immutability** | S3 blobs and trees never modified, only created |
| **Reproducibility** | Same session ID → same tree → same blobs → same files |
| **Atomic landing** | S3 conditional writes (if-match / if-none-match) |
| **Source of truth** | S3 is the single source for all blobs, trees, and sessions |

## Storage Layout

```
s3://micelio-{org}/projects/{project_id}/
├── blobs/
│   └── {hash[0:2]}/
│       └── {hash}           # Raw blob content, zstd compressed
│
├── trees/
│   └── {hash[0:2]}/
│       └── {hash}           # Serialized B+ tree (content-addressed)
│
└── sessions/
    └── {session_id}/
        ├── metadata.json    # Goal, conversation, decisions
        └── tree.json        # Session tree (base tree hash + diff)

Local NFS Server (hif/src/fs/nfs.zig):
/exports/sessions/{session-id}/
└── @                    # Symbolic link or export pointing to S3 tree hash
```

## Comparison with Original Design

| Aspect | Original Design | Current Design |
|--------|----------------|----------------|
| **Blobs** | S3 | S3 (unchanged) |
| **Trees** | B+ trees in S3 | B+ trees in S3 (restored!) |
| **Sessions** | In S3 | In S3 |
| **NFS Server** | Custom, implements CoW | Custom, implements CoW (unchanged) |
| **BTRFS** | Mentioned as reference | BTRFS as reference only (not required!) |
| **CoW** | Filesystem-level | NFS server implements CoW semantics |

**Key clarification:**
- BTRFS was discussed but is **NOT a requirement**
- We implement our own NFS server with CoW semantics
- B+ trees stay in S3 as originally designed
- S3 is the source of truth for all data

## BTRFS as Reference

BTRFS is mentioned here as a **reference implementation** showing how CoW can work at the filesystem level:

**BTRFS Benefits (for reference only):**
- Snapshots are metadata-only (instant, no storage cost)
- Copy-on-write for efficient duplication
- NFS-compatible subvolumes

**Our approach:**
- We implement similar semantics in our custom NFS server
- But we store data in S3, not on a BTRFS volume
- This makes the system portable and cloud-native

## Session API

### Start Session

```protobuf
message StartSessionRequest {
  string project_id = 1;
  string goal = 2;
  string description = 3;  // Optional extended description
}

message StartSessionResponse {
  string session_id = 1;
  string nfs_export_path = 2;
  string base_tree_hash = 3;  // Tree hash in S3
}
```

### Land Session

```protobuf
message LandSessionRequest {
  string session_id = 1;
  string commit_message = 2;
}

message LandSessionResponse {
  string new_tree_hash = 1;   // New tree in S3
  string landed_commit = 2;
  repeated FileChange changes = 3;
}
```

## Workflow Example

```bash
# 1. Start session (creates snapshot in S3)
mic session start "add authentication" \
  --project=myorg/myproject \
  --goal="Implement JWT-based auth for API"

# Output:
# Session ID: sess-abc123
# NFS Export: /mnt/micelio/sessions/sess-abc123
# Base Tree: sha256:xyz789 (in S3)

# 2. Work in session (edits create new blobs in S3)
cd /mnt/micelio/sessions/sess-abc123
# Edit files normally - NFS server creates new blobs in S3

# 3. Land (merge creates new tree in S3)
mic session land sess-abc123 --message="Add JWT authentication"

# Result:
# New tree T1 created in S3
# Project HEAD updated to T1
# Session marked as "landed"
```

## Performance Considerations

| Operation | Complexity | Notes |
|-----------|------------|-------|
| File lookup | O(log n) | B+ tree traversal in S3 |
| Session snapshot | O(1) | Just record tree hash (no data copy) |
| Tree diff | O(changes) | Compare tree structures |
| Landing | O(changes log n) | Bloom filter for conflict detection |
| Blob storage | O(1) | S3 PUT with content hash |

## Future Optimizations

1. **Bloom filters** for fast conflict detection during landing
2. **Zstd compression** for blobs (automatic, configurable)
3. **Content-defined chunking** for large files
4. **Tiered caching**: RAM → local SSD → S3 for hot data
5. **P2P sharing** of blobs between agents

## References

- [Content-Addressable Storage](https://en.wikipedia.org/wiki/Content-addressable_storage)
- [Copy-on-Write](https://en.wikipedia.org/wiki/Copy-on-write)
- [B-Trees](https://en.wikipedia.org/wiki/B-tree)
- [NFS Protocol](https://tools.ietf.org/html/rfc1813)

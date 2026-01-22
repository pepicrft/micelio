# Micelio Session Architecture

This document describes the session architecture with BTRFS and S3 for immutable file storage.

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
│  │  │    mic CLI   │  │   mic-fs     │  │     BTRFS Volume         │  │    │
│  │  │  (Zig CLI)   │  │  (NFS Daemon)│  │  (Copy-on-Write)        │  │    │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Database (SQLite/PostgreSQL)                 │    │
│  │                                                                      │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐ │    │
│  │  │  Sessions   │  │   Trees     │  │       Session Trees         │ │    │
│  │  │             │  │             │  │                             │ │    │
│  │  │ - id        │  │ - hash      │  │ - session_id (FK)           │ │    │
│  │  │ - goal      │  │ - blob_refs │  │ - base_tree (FK)            │ │    │
│  │  │ - status    │  │ - children  │  │ - diff (blob refs added/    │ │    │
│  │  │ - created_at│  │ - metadata  │  │   removed from base)        │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────┘ │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    S3 (Immutable Blob Storage)                       │    │
│  │                                                                      │    │
│  │  Content-addressed blob storage:                                     │    │
│  │  s3://micelio-{org}/projects/{id}/                                   │    │
│  │  ├── blobs/{hash[0:2]}/{hash}      # Raw file content               │    │
│  │  └── trees/{hash[0:2]}/{hash}      # Serialized tree structures     │    │
│  │                                                                      │    │
│  │  Key property: Each version = new blob (immutable)                   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Core Concepts

### 1. S3: Immutable Blob Storage

All file content lives in S3 as **content-addressed blobs**:

- **Content-addressed**: Blob hash = SHA-256 of content
- **Immutable**: Never modified, only created
- **Deduplicated**: Same content = same blob (automatic)

```
s3://micelio-{org}/projects/{project_id}/
└── blobs/
    └── {hash[0:2]}/
        └── {hash}          # Raw blob content, zstd compressed
```

**Why S3 for blobs?**
- 11 nines durability
- Infinite scalability
- Pay only for storage used
- Content-addressing enables deduplication

### 2. Database: Tree Mappings

The database maps file paths to S3 blob hashes (like Git's tree/index):

```sql
-- Trees store the complete project structure at a point in time
CREATE TABLE trees (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL,
    tree_hash TEXT NOT NULL UNIQUE,  -- SHA-256 of serialized tree
    parent_tree_id UUID,             -- Parent tree for ancestry
    metadata JSONB,                  -- Size, timestamps, etc.
    created_at TIMESTAMP NOT NULL
);

-- Session trees track changes from a base snapshot
CREATE TABLE session_trees (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL,
    base_tree_id UUID NOT NULL,      -- Snapshot taken at session start
    status TEXT NOT NULL,            -- active, landed, abandoned
    created_at TIMESTAMP NOT NULL
);

-- File mappings in each tree
CREATE TABLE tree_entries (
    id UUID PRIMARY KEY,
    tree_id UUID NOT NULL,
    path TEXT NOT NULL,              -- File path relative to project root
    blob_hash TEXT NOT NULL,         -- Reference to S3 blob
    mode INTEGER NOT NULL,           -- File permissions
    created_at TIMESTAMP NOT NULL
);
```

**Why database for trees?**
- Fast path lookups (O(1) for file content)
- Efficient diff computation (compare tree entries)
- Query flexibility (find all files matching pattern)
- Transactional updates (atomic session commits)

### 3. Sessions as Snapshots

Each session starts with a **snapshot** of the current project tree:

```
Session Lifecycle:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  1. Session Start                                               │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ mic session start "add auth middleware"             │    │
│     │                                                      │    │
│     │ - Snapshot current tree (T0)                        │    │
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
│     │ - Base tree (T0) remains unchanged                  │    │
│     │ - Other sessions don't see these changes            │    │
│     │                                                      │    │
│     │ Session tree:                                        │    │
│     │   base: T0                                           │    │
│     │   diff: +auth.go, ~main.go (changes from T0)        │    │
│     └─────────────────────────────────────────────────────┘    │
│                              │                                │
│                              ▼                                │
│  3. Landing (Merge to Base)                                    │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ mic land                                             │    │
│     │                                                      │    │
│     │ - Compute new tree from: base_tree + session diff   │    │
│     │ - Store new tree in database                        │    │
│     │ - Update project head to new tree                   │    │
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

### 4. BTRFS Integration

BTRFS provides efficient storage through **copy-on-write (CoW)**:

```
BTRFS Subvolumes:
┌─────────────────────────────────────────┐
│  Project Volume                          │
│  ├── sessions/                          │
│  │   ├── session-abc123/                │
│  │   │   ├── @ (snapshot of T0)         │  ← Read-only snapshot
│  │   │   └── @session/                  │  ← Writable session workspace
│  │   └── session-def456/                │
│  │       ├── @ (snapshot of T1)         │
│  │       └── @session/                  │
│  └── current/                           │
│      └── @ (current project HEAD)       │
└─────────────────────────────────────────┘
```

**BTRFS Benefits:**
- **Snapshots are metadata-only**: Instant, no storage cost
- **Copy-on-write**: Efficient duplication of unchanged data
- **NFS-compatible**: Can export subvolumes for network access

### 5. NFS Exports for Consistency

Each session gets its own NFS export pointing to its snapshot:

```
Session NFS Exports:
┌─────────────────────────────────────────────────────────────┐
│  Session A Export:  /exports/sessions/session-a            │
│  → Points to: sessions/session-a/@                         │
│  → Sees: snapshot of tree T0                               │
│  → Does NOT see: unlanded changes from Session B           │
│                                                              │
│  Session B Export:  /exports/sessions/session-b            │
│  → Points to: sessions/session-b/@                         │
│  → Sees: snapshot of tree T0                               │
│  → Independent from Session A                               │
│                                                              │
│  Landing creates new base tree, doesn't modify old          │
│  Cloning session sees same snapshot on any machine          │
└─────────────────────────────────────────────────────────────┘
```

## Consistency Guarantees

| Property | How It's Achieved |
|----------|-------------------|
| **Isolation** | Each session has dedicated NFS export pointing to its snapshot tree |
| **Immutability** | S3 blobs never modified, only created |
| **Reproducibility** | Same session ID → same tree → same blobs → same files |
| **Atomic landing** | Database transaction + conditional S3 writes |
| **No phantom reads** | Snapshot isolation level for database queries |

## Session Tree Structure

```elixir
# Session tree structure
defmodule Micelio.SessionTree do
  @type t :: %__MODULE__{
          id: UUID.t(),
          session_id: UUID.t(),
          base_tree_id: UUID.t(),
          status: :active | :landed | :abandoned,
          entries: [%Entry{}]
        }

  defstruct [
    :id,
    :session_id,
    :base_tree_id,
    :status,
    entries: []
  ]
end

defmodule Micelio.TreeEntry do
  @type t :: %__MODULE__{
          path: String.t(),
          blob_hash: String.t(),
          mode: non_neg_integer()
        }

  defstruct [:path, :blob_hash, :mode]
end
```

## Comparison with Previous Design

| Aspect | Previous Design | Current Design |
|--------|----------------|----------------|
| **Storage** | Everything in S3 | S3 (blobs) + Database (mappings) |
| **Sessions** | Binary blobs in S3 | Database records referencing trees |
| **Trees** | B+ trees in S3 | Database tables with fast lookups |
| **Isolation** | Logical (session IDs) | Physical (NFS exports + snapshots) |
| **BTRFS** | Not integrated | Integrated for efficient snapshots |
| **Landing** | S3 conditional writes | Database transaction + S3 blobs |

### Why the Change?

1. **Database for trees** provides:
   - Faster path lookups (indexed queries)
   - Efficient diff computation (SQL joins)
   - Transactional guarantees for landing

2. **NFS exports per session** provide:
   - True isolation (filesystems don't lie)
   - Compatibility with standard tools
   - Clear semantics for "what the session sees"

3. **BTRFS snapshots** provide:
   - Storage efficiency (CoW)
   - Instant session creation
   - Easy rollback (clone snapshot)

## Storage Layout

```
micelio-{org}/
└── projects/
    └── {project_id}/
        ├── s3/
        │   └── blobs/
        │       └── {hash[0:2]}/
        │           └── {hash}           # Content-addressed blob
        │
        └── database/
            ├── trees/                   # Tree metadata
            │   └── {tree_id}/
            │       └── metadata.json
            │
            └── sessions/
                └── {session_id}/
                    ├── tree.json        # Session tree (base + diff)
                    └── metadata.json    # Goal, conversation, etc.

BTRFS Volume Structure:
└── /mnt/btrfs/
    └── projects/
        └── {project_id}/
            ├── sessions/
            │   └── {session_id}/
            │       ├── @               # Read-only snapshot
            │       └── @session/       # Writable workspace
            │
            └── current/
                └── @                   # Current HEAD
```

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
  TreeSnapshot base_snapshot = 3;
}
```

### Land Session

```protobuf
message LandSessionRequest {
  string session_id = 1;
  string commit_message = 2;
}

message LandSessionResponse {
  string new_tree_id = 1;
  string landed_commit = 2;
  repeated FileChange changes = 3;
}
```

## Workflow Example

```bash
# 1. Start session (creates snapshot)
mic session start "add authentication" \
  --project=myorg/myproject \
  --goal="Implement JWT-based auth for API"

# Output:
# Session ID: sess-abc123
# NFS Export: /mnt/micelio/sessions/sess-abc123
# Snapshot: tree-xyz789 (based on HEAD)

# 2. Work in session (edits go to session tree)
cd /mnt/micelio/sessions/sess-abc123
# Edit files normally - changes tracked in session tree

# 3. Land (merge session tree to base)
mic session land sess-abc123 --message="Add JWT authentication"

# Result:
# New tree created with session changes
# Project HEAD updated to new tree
# Session marked as "landed"
```

## Performance Considerations

| Operation | Complexity | Notes |
|-----------|------------|-------|
| File lookup | O(1) | Database index on path |
| Session snapshot | O(1) | BTRFS snapshot (metadata only) |
| Tree diff | O(changes) | Compare tree entries |
| Landing | O(changes log n) | Bloom filter for conflict detection |
| Blob storage | O(1) | S3 PUT with content hash |

## Future Optimizations

1. **Bloom filters** for fast conflict detection during landing
2. **Zstd compression** for blobs (automatic, configurable)
3. **Content-defined chunking** for large files
4. **Tiered caching**: RAM → SSD → S3 for hot data
5. **P2P sharing** of blobs between agents

## References

- [BTRFS Wiki](https://btrfs.wiki.kernel.org/)
- [Content-Addressable Storage](https://en.wikipedia.org/wiki/Content-addressable_storage)
- [Copy-on-Write](https://en.wikipedia.org/wiki/Copy-on-write)

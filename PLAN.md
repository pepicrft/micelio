# Micelio hif Forge - Implementation Plan

This document outlines the implementation plan for adding hif forge capabilities to Micelio. The forge uses stateless agents with S3 as the source of truth, inspired by [Turbopuffer](https://turbopuffer.com/), [WarpStream](https://www.warpstream.com/), and [Calvin](https://cs.yale.edu/homes/thomson/publications/calvin-sigmod12.pdf).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Micelio (Elixir/Phoenix)                      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Stateless Agents (Fly.io / K8s)             │   │
│  │                                                         │   │
│  │  Any agent can handle any request (no leader)           │   │
│  │  Auth · Session CRUD · Blob streaming · Landing         │   │
│  │  Auto-scale based on CPU, scale to zero when idle       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                    S3 Conditional Writes                         │
│                    (if-match / if-none-match)                    │
│                              │                                   │
│                 No coordinator needed for landing!               │
│                 S3 provides atomic compare-and-swap              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
        ▼                                           ▼
┌───────────────────────┐               ┌───────────────────────┐
│      PostgreSQL       │               │     S3 (source of     │
│                       │               │        truth)         │
│  Auth only:           │               │                       │
│  - Accounts           │               │  ┌─────────────────┐  │
│  - API tokens         │               │  │  Landing Log    │  │
│  - Permissions        │               │  │  (append-only)  │  │
│                       │               │  │  + bloom index  │  │
│  ~KB per user         │               │  └─────────────────┘  │
│                       │               │  ┌─────────────────┐  │
│                       │               │  │  Sessions       │  │
│                       │               │  │  (binary)       │  │
│                       │               │  └─────────────────┘  │
│                       │               │  ┌─────────────────┐  │
│                       │               │  │  Trees          │  │
│                       │               │  │  (binary B+)    │  │
│                       │               │  └─────────────────┘  │
│                       │               │  ┌─────────────────┐  │
│                       │               │  │  Blobs          │  │
│                       │               │  │  (zstd)         │  │
│                       │               │  └─────────────────┘  │
└───────────────────────┘               └───────────────────────┘
```

### Key Design Decisions

1. **Stateless agents** - Any agent can handle any request, no leader election
2. **S3 conditional writes** - Landing uses `If-Match` for atomic CAS, no coordinator
3. **Binary formats** - All data in compact binary (no JSON), 10-50x smaller
4. **Bloom filter rollups** - O(log n) conflict detection, not O(n) scan
5. **PostgreSQL for auth** - Only accounts, tokens, permissions (tiny data)
6. **Tiered caching** - RAM -> SSD -> CDN -> S3

### Scale Targets

| Metric | Target |
|--------|--------|
| Files per project | 1B+ |
| Landings per day | 500,000+ |
| Concurrent sessions | 100,000+ |
| Queries per second | 1,000,000+ |

---

## Phase 1: Auth Database

**Goal:** Store users, tokens, and permissions in PostgreSQL.

### 1.1 Migration (Done)

```elixir
# accounts - users and agents
create table(:accounts) do
  add :handle, :string, null: false
  add :email, :string
  add :password_hash, :string
  add :type, :string, default: "user"  # 'user' or 'agent'
end

# api_tokens - for CLI authentication
create table(:api_tokens) do
  add :account_id, references(:accounts)
  add :token_hash, :binary, null: false
  add :name, :string
  add :scopes, {:array, :string}
  add :expires_at, :utc_datetime_usec
end

# project_permissions - who can access which projects
create table(:project_permissions) do
  add :project_id, :string, null: false
  add :account_id, references(:accounts)
  add :role, :string, default: "read"  # 'owner', 'write', 'read'
end
```

### 1.2 Ecto Schemas

| Module | Description |
|--------|-------------|
| `Micelio.Hif.Account` | User/agent accounts |
| `Micelio.Hif.ApiToken` | API tokens for CLI auth |
| `Micelio.Hif.ProjectPermission` | Project access control |

### 1.3 Auth Context

```elixir
defmodule Micelio.Hif.Auth do
  def create_account(attrs)
  def get_account(id)
  def create_token(account, name, scopes \\ [])
  def verify_token(token_string)
  def check_permission(project_id, account_id, required_role)
end
```

**Deliverable:** Auth tables, schemas, and context with tests

---

## Phase 2: S3 Storage Layer (Binary)

**Goal:** Read/write hif data to S3 using binary formats.

### 2.1 S3 Structure

```
s3://micelio-hif/
└── projects/
    └── {project_id}/
        │
        ├── head                         # Current head (48 bytes, binary)
        │   [8 bytes: position (u64)]
        │   [32 bytes: tree_hash]
        │   [8 bytes: hlc_updated]
        │
        ├── landing-log/                 # Append-only landing log
        │   ├── 00000000.log             # Positions 0-999 (binary)
        │   ├── 00001000.log             # Positions 1000-1999
        │   └── bloom-index/             # Hierarchical bloom rollups
        │       ├── level-1/             # 100 landings merged
        │       ├── level-2/             # 10,000 landings merged
        │       └── level-3/             # 1,000,000 landings merged
        │
        ├── sessions/
        │   └── {session_id}.bin         # Binary session format
        │
        ├── trees/
        │   └── {hash[0:2]}/{hash}.bin   # Binary B+ tree
        │
        └── blobs/
            └── {hash[0:2]}/{hash}       # zstd compressed
```

### 2.2 Binary Formats

**Head (48 bytes):**
```
┌────────────────────────────────────────────────────────┐
│  position (u64)  │  tree_hash (32 bytes)  │  hlc (8)  │
└────────────────────────────────────────────────────────┘
```

**Session (binary):**
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

### 2.3 Storage Module

```elixir
defmodule Micelio.Hif.Storage do
  @moduledoc "S3 storage for hif data (binary formats)"

  # Head (48 bytes binary)
  def get_head(project_id)
  def put_head(project_id, position, tree_hash, opts \\ [])
  # opts: [if_match: etag] for conditional write

  # Sessions (binary)
  def get_session(project_id, session_id)
  def put_session(project_id, session)

  # Landing log
  def append_landing(project_id, landing_entry)
  def list_landings(project_id, from_position, to_position)

  # Bloom rollups
  def get_bloom_rollup(project_id, level, start_position)
  def put_bloom_rollup(project_id, level, start_position, bloom)

  # Trees (binary)
  def get_tree(project_id, hash)
  def put_tree(project_id, hash, data)

  # Blobs (zstd compressed)
  def get_blob(project_id, hash)
  def put_blob(project_id, hash, data)
end
```

### 2.4 Binary Serialization

```elixir
defmodule Micelio.Hif.Binary do
  @moduledoc "Binary serialization for hif data structures"

  # Head
  def encode_head(position, tree_hash, hlc)
  def decode_head(binary)

  # Session
  def encode_session(session)
  def decode_session(binary)

  # Landing entry
  def encode_landing(landing)
  def decode_landing(binary)

  # Bloom filter (delegated to libhif-core or pure Elixir)
  def encode_bloom(bloom)
  def decode_bloom(binary)
end
```

### 2.5 Configuration

```elixir
# config/dev.exs - local filesystem
config :micelio, Micelio.Hif.Storage,
  adapter: Micelio.Hif.Storage.Local,
  path: "priv/hif_storage"

# config/runtime.exs - S3
config :micelio, Micelio.Hif.Storage,
  adapter: Micelio.Hif.Storage.S3,
  bucket: System.get_env("HIF_S3_BUCKET"),
  region: System.get_env("AWS_REGION", "auto")
```

**Deliverable:** Binary storage layer with local and S3 adapters

---

## Phase 3: Session CRUD

**Goal:** Create, read, update sessions via API.

### 3.1 Sessions Context

```elixir
defmodule Micelio.Hif.Sessions do
  alias Micelio.Hif.Storage

  def start_session(project_id, goal, owner_id) do
    {head, _etag} = Storage.get_head(project_id)

    session = %{
      id: generate_session_id(),
      project_id: project_id,
      goal: goal,
      owner_id: owner_id,
      state: :open,
      base_position: head.position,
      operations: [],
      decisions: [],
      conversation: [],
      bloom_filter: Bloom.new(1000, 0.01),
      hlc_created: HLC.now(),
      hlc_updated: HLC.now()
    }

    binary = Binary.encode_session(session)
    Storage.put_session(project_id, session.id, binary)
    {:ok, session}
  end

  def record_operation(session_id, op_type, path, blob_hash \\ nil)
  def record_decision(session_id, content)
  def record_conversation(session_id, role, content)
  def abandon_session(session_id)
end
```

**Deliverable:** Session CRUD operations with binary serialization

---

## Phase 4: Coordinator-Free Landing

**Goal:** Landing via S3 conditional writes, no coordinator process.

### 4.1 Landing Protocol

```elixir
defmodule Micelio.Hif.Landing do
  @moduledoc """
  Coordinator-free landing using S3 conditional writes.

  Uses If-Match headers for optimistic concurrency:
  1. Read head with etag
  2. Check conflicts via bloom rollups
  3. Write new tree and blobs (idempotent)
  4. PUT head with If-Match: etag
  5. If 412: retry with backoff
  """

  def land(project_id, session_id) do
    do_land(project_id, session_id, _attempt = 1, _max_attempts = 10)
  end

  defp do_land(project_id, session_id, attempt, max_attempts) when attempt <= max_attempts do
    with {:ok, session} <- Storage.get_session(project_id, session_id),
         {:ok, head, etag} <- Storage.get_head_with_etag(project_id),
         :ok <- check_conflicts(project_id, session, head.position),
         {:ok, new_tree_hash} <- build_and_store_tree(project_id, session, head),
         new_position <- head.position + 1,
         :ok <- store_blobs(project_id, session),
         {:ok, _} <- conditional_update_head(project_id, new_position, new_tree_hash, etag) do

      # Async: append to landing log, update bloom rollups
      async_post_land(project_id, session, new_position)

      # Update session state
      Storage.put_session(project_id, %{session | state: :landed, landed_position: new_position})

      {:ok, new_position}
    else
      {:error, :precondition_failed} ->
        # Someone else landed, retry with backoff
        backoff = :math.pow(2, attempt) * 50 |> trunc() |> min(5000)
        Process.sleep(backoff + :rand.uniform(100))
        do_land(project_id, session_id, attempt + 1, max_attempts)

      {:error, {:conflicts, paths}} ->
        Storage.put_session(project_id, %{session | state: :conflicted})
        {:error, {:conflicts, paths}}

      error ->
        error
    end
  end

  defp conditional_update_head(project_id, position, tree_hash, etag) do
    head_binary = Binary.encode_head(position, tree_hash, HLC.now())
    Storage.put_head(project_id, head_binary, if_match: etag)
  end
end
```

### 4.2 Bloom Filter Rollups (O(log n) Conflict Detection)

```elixir
defmodule Micelio.Hif.ConflictDetection do
  @moduledoc """
  O(log n) conflict detection using hierarchical bloom rollups.

  Levels:
  - Level 0: Individual landings (in landing log)
  - Level 1: 100 landings merged
  - Level 2: 10,000 landings merged
  - Level 3: 1,000,000 landings merged
  """

  @level_sizes %{1 => 100, 2 => 10_000, 3 => 1_000_000}

  def check_conflicts(project_id, session, current_position) do
    base = session.base_position
    our_bloom = session.bloom_filter

    # Check from highest level down
    case check_range(project_id, our_bloom, base + 1, current_position, 3) do
      :no_conflict -> :ok
      {:conflict, paths} -> {:error, {:conflicts, paths}}
    end
  end

  defp check_range(_project_id, _bloom, from, to, _level) when from > to do
    :no_conflict
  end

  defp check_range(project_id, our_bloom, from, to, level) when level > 0 do
    level_size = @level_sizes[level]

    # Find rollups that cover this range
    rollups = get_covering_rollups(project_id, level, from, to)

    Enum.reduce_while(rollups, :no_conflict, fn rollup, _acc ->
      if Bloom.intersects?(our_bloom, rollup.bloom) do
        # Descend to finer granularity
        case check_range(project_id, our_bloom, rollup.start, rollup.end, level - 1) do
          :no_conflict -> {:cont, :no_conflict}
          conflict -> {:halt, conflict}
        end
      else
        {:cont, :no_conflict}
      end
    end)
  end

  defp check_range(project_id, our_bloom, from, to, 0) do
    # Level 0: check individual landings
    landings = Storage.list_landings(project_id, from, to)

    conflicts =
      landings
      |> Enum.filter(fn l -> Bloom.intersects?(our_bloom, l.bloom) end)
      |> Enum.flat_map(fn l -> find_path_conflicts(our_bloom.paths, l.paths) end)
      |> Enum.uniq()

    if Enum.empty?(conflicts), do: :no_conflict, else: {:conflict, conflicts}
  end
end
```

### 4.3 Async Post-Landing Tasks

```elixir
defmodule Micelio.Hif.LandingWorker do
  @moduledoc "Background tasks after landing"

  use Oban.Worker

  def perform(%{args: %{"project_id" => project_id, "position" => position, "session_id" => session_id}}) do
    # Append to landing log
    append_to_log(project_id, position, session_id)

    # Update bloom rollups (if position crosses level boundary)
    maybe_update_rollups(project_id, position)

    :ok
  end
end
```

**Deliverable:** Coordinator-free landing with O(log n) conflict detection

---

## Phase 5: API Endpoints

**Goal:** gRPC/HTTP endpoints for hif CLI.

### 5.1 gRPC Service

```protobuf
service HifService {
  rpc StartSession(StartSessionRequest) returns (Session);
  rpc GetSession(GetSessionRequest) returns (Session);
  rpc LandSession(LandSessionRequest) returns (LandResult);
  rpc AbandonSession(AbandonSessionRequest) returns (Empty);

  rpc RecordOperation(RecordOperationRequest) returns (Empty);
  rpc RecordDecision(RecordDecisionRequest) returns (Empty);

  rpc GetTree(GetTreeRequest) returns (Tree);
  rpc GetBlob(GetBlobRequest) returns (stream BlobChunk);
  rpc PutBlob(stream BlobChunk) returns (PutBlobResponse);
}
```

### 5.2 REST Fallback

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/hif/projects/:id/sessions` | POST | Start session |
| `/api/hif/projects/:id/sessions/:sid` | GET | Get session |
| `/api/hif/projects/:id/sessions/:sid/land` | POST | Land session |
| `/api/hif/projects/:id/blobs` | POST | Upload blob |
| `/api/hif/projects/:id/blobs/:hash` | GET | Download blob |

### 5.3 Authentication

```elixir
defmodule MicelioWeb.Hif.AuthPlug do
  def call(conn, _opts) do
    with {:ok, token} <- extract_bearer_token(conn),
         {:ok, account} <- Micelio.Hif.Auth.verify_token(token) do
      assign(conn, :current_account, account)
    else
      _ -> send_resp(conn, 401, "Unauthorized") |> halt()
    end
  end
end
```

**Deliverable:** gRPC and REST API for hif operations

---

## Phase 6: libhif-core Integration

**Goal:** Use Zig NIFs for binary serialization and bloom filters.

### 6.1 Why NIFs?

- Binary formats are complex (B+ trees, bloom filters)
- libhif-core already implements them correctly
- 100x faster than pure Elixir for serialization
- Shared code between client and server

### 6.2 NIF Wrapper

```elixir
defmodule Micelio.Hif.Core do
  use Zig, otp_app: :micelio, link_lib: "hif_core"

  # Bloom filters
  def bloom_new(n, fp_rate)
  def bloom_add(bloom, data)
  def bloom_intersects(a, b)
  def bloom_serialize(bloom)
  def bloom_deserialize(binary)

  # Trees
  def tree_new()
  def tree_insert(tree, path, hash)
  def tree_delete(tree, path)
  def tree_hash(tree)
  def tree_serialize(tree)
  def tree_deserialize(binary)

  # Sessions
  def session_serialize(session)
  def session_deserialize(binary)

  # Hashing
  def hash_blob(data)
end
```

**Deliverable:** NIFs for bloom, tree, and binary serialization

---

## Phase 7: Tiered Caching

**Goal:** Fast reads via multi-tier caching.

### 7.1 Cache Tiers

```
Tier 0: Agent RAM      (MB)    - hot data, <1ms
Tier 1: Agent SSD      (GB)    - shared cache, ~10ms
Tier 2: CDN edge       (TB)    - popular blobs, ~50ms
Tier 3: S3             (PB)    - everything, ~100ms
```

### 7.2 Cache Module

```elixir
defmodule Micelio.Hif.Cache do
  @moduledoc "Tiered caching for hif data"

  # RAM cache (ETS)
  def get_cached(key)
  def put_cached(key, value, ttl)

  # Blob cache (content-addressed, infinite TTL)
  def get_blob(project_id, hash)
  def put_blob(project_id, hash, data)

  # Tree cache (content-addressed, infinite TTL)
  def get_tree(project_id, hash)
  def put_tree(project_id, hash, data)
end
```

### 7.3 CDN Integration

- CloudFront/Cloudflare in front of S3 for blobs
- Content-addressed = infinite cache TTL
- Mutable data (head, sessions) always from S3

**Deliverable:** Multi-tier caching with CDN

---

## Dependencies

### Required Packages

```elixir
# mix.exs
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.5"},
{:hackney, "~> 1.20"},
{:grpc, "~> 0.9"},
{:protobuf, "~> 0.13"},
{:oban, "~> 2.17"},  # for background jobs
```

### External

| Dependency | Purpose |
|------------|---------|
| PostgreSQL | Auth storage |
| S3 / R2 / MinIO | hif data storage |
| libhif-core | Binary formats, bloom filters |

---

## Milestone Summary

| Phase | Description | Deliverable |
|-------|-------------|-------------|
| 1 | Auth Database | Accounts, tokens, permissions (Done) |
| 2 | S3 Storage | Binary storage layer |
| 3 | Session CRUD | Start, update, abandon sessions |
| 4 | Landing | Coordinator-free with bloom rollups |
| 5 | API | gRPC and REST endpoints |
| 6 | NIFs | libhif-core integration |
| 7 | Caching | Tiered caching with CDN |

---

## Current Status

- [x] PLAN.md created
- [x] Auth migration (accounts, tokens, permissions)
- [ ] Auth schemas and context
- [ ] Binary storage layer
- [ ] Session CRUD
- [ ] Coordinator-free landing
- [ ] Bloom filter rollups
- [ ] gRPC API
- [ ] libhif-core NIFs

---

## Next Steps

1. Create Ecto schemas for auth tables
2. Implement `Micelio.Hif.Auth` context
3. Implement `Micelio.Hif.Binary` serialization
4. Implement `Micelio.Hif.Storage` with local adapter
5. Implement `Micelio.Hif.Sessions` context
6. Implement `Micelio.Hif.Landing` with conditional writes
7. Add gRPC endpoints

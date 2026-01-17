# What's Next

This document tracks upcoming work, implementation status, and ideas for Micelio.

---

## Forge (Elixir/Phoenix)

### Completed

- [x] **SKILL.md** - Created at `priv/static/SKILL.md` and served at `/SKILL.md`
- [x] **REST API for agents** - RESTful API endpoints for AI agents to interact with Micelio
- [x] **Activity graph** - GitHub-style contribution/activity visualization
- [x] **OpenGraph utilities** - Helper functions for OG meta tags and dynamic OG images
- [x] **Gravatar integration** - Default avatar for users based on email
- [x] **Account avatar customization** - Allow users to upload and change their avatar

### Implementation Plan

The forge uses stateless agents with S3 as the source of truth, inspired by Turbopuffer, WarpStream, and Calvin. See [design.md](design.md) for full architecture details.

#### Phase 1: Auth Database (SQLite + Litestream)

Store users, tokens, and permissions in SQLite, replicated to S3 via Litestream.

- [ ] Add `ecto_sqlite3` dependency and configure SQLite
- [ ] Set up Litestream for S3 replication
- [ ] Implement `Micelio.Hif.Auth` context

#### Phase 2: S3 Storage Layer (Binary)

Read/write hif data to S3 using binary formats.

- [x] Storage abstraction with local + S3 backends
- [ ] Implement `Micelio.Hif.Binary` serialization

#### Phase 3: Session CRUD

- [x] Session CRUD (database + REST endpoints)
- [x] Basic landing endpoint (non-conditional)

#### Phase 4: Coordinator-Free Landing

Landing via S3 conditional writes, no coordinator process.

- [ ] Coordinator-free landing with conditional writes
- [ ] Bloom filter rollups for O(log n) conflict detection

#### Phase 5: API Endpoints

- [x] gRPC API (projects service)
- [ ] Session gRPC API

#### Phase 6: libhif-core Integration

Use Zig NIFs for binary serialization and bloom filters.

#### Phase 7: Tiered Caching

Fast reads via multi-tier caching (RAM -> SSD -> CDN -> S3).

---

## hif (Zig)

### Completed

- [x] Project initialized with Zig 0.15
- [x] `core/hash.zig` - Blake3 hashing
- [x] `core/bloom.zig` - Bloom filters for conflict detection
- [x] `core/hlc.zig` - Hybrid Logical Clock for distributed timestamps
- [x] `core/tree.zig` - B+ tree for directory structures
- [x] Binary serialization for all types (`hif/src/core/serialize.zig`)
- [x] Integration tests - End-to-end workflow tests
- [x] gRPC client with TLS support
- [x] Basic CLI commands (auth, checkout, status, land)
- [x] Clone command with git-like semantics
- [x] Token refresh with file-system locking
- [x] Conflict resolution with server-side detection
- [x] Error recovery and rollback (atomic writes, backups, retry)
- [x] `hif log` - List landed sessions
- [x] `hif log --path` - Sessions touching path
- [x] `hif diff` - Diff between two states
- [x] `hif goto @N` - View tree at position N

### Phase 4: Virtual Filesystem (hif-fs)

- [ ] NFS v3 server implementation
- [ ] Session overlay for local changes
- [ ] `hif mount` / `hif unmount` commands
- [ ] Prefetch on directory open

### Phase 5: Scale

- [ ] Bloom filter rollup background job
- [ ] Epoch batching mode (high throughput)
- [ ] CDN integration for blobs
- [ ] Delta compression

---

## Architecture Notes

### Tree Implementation

The current `tree.zig` uses a sorted ArrayList for simplicity:
- O(log n) lookups via binary search
- O(n) insertions due to re-sorting
- Suitable for small to medium trees (< 10K entries)

For large-scale repositories (100K+ files), a proper B-tree or prolly tree with probabilistic chunking boundaries would be needed. Deferred to Phase 5.

### gRPC Client

The hif CLI uses vendored gRPC C core `v1.76.0` (TLS required) via `hif/vendor/grpc`.

---

## Ideas

These are exploratory ideas for future consideration:

### Forge Features
- Fediverse integration
- Rate limiting when not authenticated
- Public vs private repositories
- OAuth2 dynamic registration for MCP clients
- OpenAPISpex setup
- PR stacking (like GitHub is working on)
- Store issues/PRs in the repository itself for portability
- GitHub Pages-like static site hosting

### Security
- Sanitize fetch account & repository queries to prevent injection
- Define project boundaries using Boundary library
- Admin declaration and authorization

### Scaling
- Track file-system or git operations per account/repo for sharding decisions
- Decide on SQLite vs Postgres vs MySQL
- Explore Ceph for horizontal storage scaling

### Desktop/CLI
- Desktop app built with Zig (like Zed with Rust)
- Kamal replacement in pure Zig
- Static site deployment tool

### Research
- How does SourceHut handle issues and mailing lists?
- Can marketing pages be included and removed at compile-time?

# Next Steps

This file tracks upcoming features and improvements for Micelio.

---

## Forge (Elixir/Phoenix)

### Documentation

- [x] **SKILL.md** - Created at `priv/static/SKILL.md` and served at `/SKILL.md`

### API

- [x] **REST API for agents** - RESTful API endpoints for AI agents to interact with Micelio (sessions, projects, content)

### UI Enhancements

- [x] **Activity graph** - GitHub-style contribution/activity visualization showing user or project activity over time
- [x] **OpenGraph utilities** - Helper functions for generating OG meta tags and dynamically generated OG images for blog posts, projects, and profiles for better social sharing (includes Twitter Card support)
- [x] **Gravatar integration** - Use Gravatar as the default avatar for users based on their email
- [x] **Account avatar customization** - Allow users to upload and change their account avatar

---

## hif (Zig)

### Current Status

- [x] Project initialized with Zig 0.15
- [x] `core/hash.zig` - Blake3 hashing
- [x] `core/bloom.zig` - Bloom filters for conflict detection
- [x] `core/hlc.zig` - Hybrid Logical Clock for distributed timestamps
- [x] `core/tree.zig` - B+ tree for directory structures
- [x] Integration tests - End-to-end workflow tests
- [x] gRPC client with TLS support
- [x] Basic CLI commands (auth, checkout, status, land)

### Production Readiness (Completed)

**1. Clone Command** ✅
- [x] Implement `hif clone <org/project>` - same as checkout but git-like semantics
- [x] Parse project reference (org/project format)
- [x] Authenticate and fetch project tree from forge
- [x] Download all blobs and write to local filesystem
- [x] Create workspace manifest in `.hif/workspace.json`

**2. Token Refresh with File-System Locking** ✅
- [x] File-based locking mechanism for credential access (`~/.config/hif/.lock`)
- [x] Standard OAuth2 token refresh via `/oauth/token` endpoint (using Boruta)
- [x] `oauth.getValidAccessToken()` - returns valid token, refreshing if needed
- [x] Automatic retry with backoff when lock is held (50 attempts, 100ms each)
- [x] 5-minute refresh margin before expiry

**3. Conflict Resolution** ✅
- [x] Server-side conflict detection based on `base_position` in session metadata
- [x] ConflictIndex for efficient path-based conflict scanning
- [x] `LandSession` returns `ABORTED` status with conflicting paths
- [x] CLI parses conflict errors and displays clear resolution instructions
- [x] `hif sync` command fetches latest upstream and identifies local conflicts
- [x] Preserves local changes during sync, only updates non-conflicting files

**4. Error Recovery and Rollback** ✅
- [x] Atomic file writes for manifest (write to temp, then rename)
- [x] Backup file utilities (`backupFile`, `restoreFromBackup`)
- [x] Retry helper module with exponential backoff for transient failures
- [x] Proper error handling with user-friendly messages

### Phase 1: Foundation (Completed)

**Core Primitives:**
- [x] Blake3 hashing
- [x] Bloom filters
- [x] Basic tree (insert, delete, hash)
- [x] HLC timestamps
- [x] Binary serialization for all types (`hif/src/core/serialize.zig`)
- [x] Bloom filter merge/rollup operations

**hif:**
- [x] Project/clone/auth command structure
- [x] `hif checkout <account>/<project>` - Create local workspace
- [x] `hif status` - Show workspace changes
- [x] `hif land <goal>` - Land workspace changes
- [x] Local config (~/.hif/) - Configuration management with servers, aliases, and preferences
- [x] Tiered cache (RAM → SSD) - Caching layer in `hif/src/cache.zig`

### Phase 2: Conflict Detection (Completed)

- [x] Bloom per session - Create bloom on session start, stored in session.json as base64
- [x] Path index - Track which sessions touch which paths (stored in `projects/{id}/landing/paths/{position}.bin`)
- [x] Conflict check - If bloom intersects, check path index
- [x] `hif session resolve` - Interactive conflict resolution with ours/theirs/interactive strategies

### Phase 3: History and Navigation

- [x] `hif log` - List landed sessions via gRPC ListSessions endpoint
- [x] `hif log --path` - Sessions touching path (backend path filtering via gRPC ListSessions)
- [x] `hif diff` - Diff between two states (GetTreeAtPosition endpoint + client-side comparison)
- [x] `hif goto @N` - View tree at position N (also supports `@latest` and `@position:N` syntax)

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

For large-scale repositories (100K+ files), a proper B-tree or prolly tree with probabilistic chunking boundaries would be needed. This is deferred to Phase 5 (Scale) when actual performance requirements are known.

### gRPC Client

The hif CLI uses vendored gRPC C core `v1.76.0` (TLS required) via `hif/vendor/grpc`.

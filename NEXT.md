# Next Steps

This file tracks upcoming features and improvements for Micelio.

---

## Forge (Elixir/Phoenix)

### Documentation

- [x] **SKILL.md** - Created at `priv/static/SKILL.md` and served at `/SKILL.md`

### API

- [ ] **REST API for agents** - RESTful API endpoints for AI agents to interact with Micelio (sessions, projects, content)

### UI Enhancements

- [ ] **Activity graph** - GitHub-style contribution/activity visualization showing user or project activity over time
- [ ] **OpenGraph utilities** - Helper functions for generating OG meta tags and dynamically generated OG images for blog posts, projects, and profiles for better social sharing
- [ ] **Gravatar integration** - Use Gravatar as the default avatar for users based on their email
- [ ] **Account avatar customization** - Allow users to upload and change their account avatar

---

## CLI (Zig)

### Current Status

- [x] Project initialized with Zig 0.15
- [x] `core/hash.zig` - Blake3 hashing
- [x] `core/bloom.zig` - Bloom filters for conflict detection
- [x] `core/hlc.zig` - Hybrid Logical Clock for distributed timestamps
- [x] `core/tree.zig` - B+ tree for directory structures
- [x] Integration tests - End-to-end workflow tests
- [x] gRPC client with TLS support
- [x] Basic CLI commands (auth, checkout, status, land)

### Phase 1: Foundation (In Progress)

**Core Primitives:**
- [x] Blake3 hashing
- [x] Bloom filters
- [x] Basic tree (insert, delete, hash)
- [x] HLC timestamps
- [ ] Binary serialization for all types
- [ ] Bloom filter merge/rollup operations

**CLI:**
- [x] Project/clone/auth command structure
- [x] `mic checkout <account>/<project>` - Create local workspace
- [x] `mic status` - Show workspace changes
- [x] `mic land <goal>` - Land workspace changes
- [ ] Local config (~/.mic/)
- [ ] Tiered cache (RAM → SSD)

### Phase 2: Conflict Detection

- [ ] Bloom per session - Create bloom on session start
- [ ] Path index - Track which sessions touch which paths
- [ ] Conflict check - If bloom intersects, check path index
- [ ] `mic session resolve` - Interactive conflict resolution

### Phase 3: History and Navigation

- [ ] `mic log` - List landed sessions
- [ ] `mic log --path` - Sessions touching path
- [ ] `mic diff` - Diff between two states
- [ ] `mic goto @latest` - View latest tree state
- [ ] `mic goto @position:N` - View tree at position N

### Phase 4: Virtual Filesystem (mic-fs)

- [ ] NFS v3 server implementation
- [ ] Session overlay for local changes
- [ ] `mic mount` / `mic unmount` commands
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

The CLI uses vendored gRPC C core `v1.76.0` (TLS required) via `cli/vendor/grpc`.

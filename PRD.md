# Micelio - Agent-First Git Forge

Micelio is a minimalist, open-source git forge built with Elixir/Phoenix, designed for the agent-first future of software development. It integrates with hif (a Zig-based version control system) to provide session-based workflows that capture not just what changed, but why.

## Tasks

### Forge (Elixir/Phoenix)

- [x] Add rate limiting middleware for unauthenticated API requests
- [x] Implement public vs private repository visibility settings in the database schema and authorization
- [x] Create repository settings page for changing visibility, name, and description
- [x] Add OpenAPISpex setup for automatic API documentation generation
- [x] Implement fediverse integration for ActivityPub-compatible forge federation
- [x] Add repository starring/favorites functionality with database schema and UI
- [x] Create repository search functionality with full-text search across names and descriptions
- [x] Implement repository forking with proper ownership and origin tracking
- [x] Add webhook support for repository events (push, session land, etc.)
- [x] Create user profile page showing owned repositories and activity
  - Note: Activity graph (like GitHub's contribution graph) should be added
- [x] Add user activity graph (GitHub-style contribution visualization) to profile page
- [x] Implement repository README rendering on the repository homepage
- [x] Add syntax highlighting for code file viewing using a server-side highlighter
- [x] Create repository file browser with tree navigation
- [x] Implement blame view showing session attribution per line
- [x] Add tiered caching layer (RAM -> SSD -> CDN -> S3) for fast reads
- [ ] Create admin dashboard for instance management and user oversight
- [ ] Implement email notifications for repository activity
- [ ] Convert Micelio repository into a workspace and push to micelio/micelio on micelio.dev

### hif (Zig CLI)

- [ ] Implement NFS v3 server for virtual filesystem (hif-fs) in hif/src/fs/nfs.zig
- [ ] Create session overlay for tracking local changes before landing
- [ ] Add `hif mount` command to mount repository as virtual filesystem
- [ ] Add `hif unmount` command to cleanly unmount virtual filesystem
- [ ] Implement prefetch on directory open for better performance
- [ ] Create bloom filter rollup background job for O(log n) conflict detection at scale
- [ ] Add epoch batching mode for high-throughput landing scenarios
- [ ] Implement CDN integration for blob serving
- [ ] Add delta compression for efficient storage of similar files
- [ ] Create `hif blame` command showing which session introduced each line
- [ ] Implement `hif cat` command to print file contents at any ref
- [ ] Add `hif ls` command to list directory contents at any ref

### Documentation & Testing

- [ ] Add comprehensive integration tests for gRPC session workflows
- [ ] Create property-based tests for bloom filter operations using StreamData
- [ ] Write end-to-end tests for the complete land workflow
- [ ] Add memory leak detection tests for Zig components
- [ ] Create user documentation for common hif workflows
- [ ] Add architecture decision records (ADRs) for key design choices

### Security & Compliance

- [ ] Implement audit logging for all repository operations
- [ ] Add two-factor authentication (TOTP) support
- [ ] Create repository access tokens with scoped permissions
- [ ] Implement branch protection rules for preventing direct lands to main
- [ ] Add secret scanning to prevent credential leaks in landed sessions

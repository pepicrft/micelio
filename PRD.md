# Micelio - Agent-First Git Forge

Micelio is a minimalist, open-source git forge built with Elixir/Phoenix, designed for the agent-first future of software development. It integrates with hif (a Zig-based version control system) to provide session-based workflows that capture not just what changed, but why.

## Tasks

### Forge (Elixir/Phoenix)

- [x] Add rate limiting middleware for unauthenticated API requests
- [x] Implement public vs private project visibility settings in the database schema and authorization
- [x] Create project settings page for changing visibility, name, and description
- [x] Add OpenAPISpex setup for automatic API documentation generation
- [x] Implement fediverse integration for ActivityPub-compatible forge federation
- [x] Add project starring/favorites functionality with database schema and UI
- [x] Create project search functionality with full-text search across names and descriptions
- [x] Implement project forking with proper ownership and origin tracking
- [x] Add webhook support for project events (push, session land, etc.)
- [x] Create user profile page showing owned repositories and activity
  - Note: Activity graph (like GitHub's contribution graph) should be added
- [x] Add user activity graph (GitHub-style contribution visualization) to profile page
- [x] Implement project README rendering on the project homepage
- [x] Add syntax highlighting for code file viewing using a server-side highlighter
- [x] Create project file browser with tree navigation
- [x] Implement blame view showing session attribution per line
- [x] Add tiered caching layer (RAM -> SSD -> CDN -> S3) for fast reads
- [x] Create admin dashboard for instance management and user oversight
- [x] Implement email notifications for project activity
- [ ] Convert Micelio project into a workspace and push to micelio/micelio on micelio.dev
- [ ] Create skill.md served from /skill.md for agents, and add note to AGENTS.md to keep it updated
- [ ] Implement dynamic Open Graph images for public projects and pages
  - Generate lazily and persist to S3 for future use
  - Use content hash for cache invalidation
  - Support cache invalidation on X, LinkedIn, and other platforms
- [ ] Create public agent LiveView to watch agent progress on projects
- [ ] Implement daily theme generation using LLM API
  - Generate new theme personality each day and apply it
  - Persist generated themes in S3
  - Cache in memory for performance
  - Add footer explaining the daily personality design
- [ ] Add JSON-LD structured data for SEO (Schema.org SoftwareSourceCode)
- [ ] Create embeddable badges for projects (Shields.io-style for Micelio)
- [ ] Implement ActivityPub federation for projects and profiles
- [ ] Add GitHub OAuth authentication
- [ ] Add GitLab OAuth authentication
- [ ] Add Passkey (WebAuthn) authentication support

### hif (Zig CLI)

- [ ] Implement NFS v3 server for virtual filesystem (hif-fs) in hif/src/fs/nfs.zig
- [ ] Create session overlay for tracking local changes before landing
- [ ] Add `hif mount` command to mount project as virtual filesystem
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

- [ ] Implement audit logging for all project operations
- [ ] Add two-factor authentication (TOTP) support
- [ ] Create project access tokens with scoped permissions
- [ ] Implement branch protection rules for preventing direct lands to main
- [ ] Add secret scanning to prevent credential leaks in landed sessions

### Platform Limits & Rate Limiting

- [ ] Implement rate limiting for unauthenticated and authenticated users
- [ ] Set initial project limits per tenant (prevent spam during early growth)
- [ ] Add abuse detection and mitigation systems

### Mobile Clients

- [ ] Create iOS native client using Swift (SwiftUI)
- [ ] Create Android native client using Jetpack Compose
- [ ] Implement authentication flow for both mobile clients
- [ ] Add basic project browsing and viewing capabilities
- [ ] Design API endpoints optimized for mobile (pagination, offline support)

### Agentic Infrastructure

- [ ] Design infrastructure for provisioning VMs and mounting volumes
- [ ] Evaluate cloud platforms for VM provisioning (AWS, GCP, Hetzner, etc.)
- [ ] Design abstraction protocol for cloud-agnostic VM management
- [ ] Implement remote execution service for running CLI tools (Claude, Codex, etc.)
- [ ] Add support for tenant-configurable LLM models per project
- [ ] Design secure sandboxed environment for agent execution
- [ ] Implement resource quota and billing for agentic workflows

### Open Graph & SEO

- [ ] Generate OG images for agents using LLM summaries of code changes
- [ ] Design template for agent progress OG images showing commits, files changed
- [ ] Implement cache invalidation strategy for social platform crawlers
- [ ] Add dynamic OG image generation for commits, PRs, and agent sessions

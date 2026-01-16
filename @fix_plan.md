# Micelio Fix Plan

## High Priority (Forge)

- [x] **Agent skill documentation** - Created `skills/micelio.md` with comprehensive agent onboarding guide
- [x] **Gravatar integration** - Use Gravatar as the default avatar for users based on their email
- [x] **OpenGraph utilities** - Helper functions for generating OG meta tags and dynamically generated OG images (includes Twitter Card support)

## Medium Priority (Forge UI)

- [x] **Activity graph** - GitHub-style contribution/activity visualization
- [ ] **Account avatar customization** - Allow users to upload and change their account avatar

## High Priority (hif CLI)

- [ ] **Binary serialization** - Implement binary serialization for all core types
- [ ] **Bloom filter merge/rollup** - Operations for combining bloom filters
- [ ] **Local config** - ~/.hif/ configuration management

## Medium Priority (hif CLI)

- [ ] **Tiered cache** - RAM -> SSD caching layer
- [ ] **Session conflict resolution** - `hif session resolve` interactive conflict resolution
- [ ] **Bloom per session** - Create bloom on session start
- [ ] **Path index** - Track which sessions touch which paths

## Low Priority (hif CLI - Phase 3)

- [ ] **hif log** - List landed sessions
- [ ] **hif log --path** - Sessions touching specific path
- [ ] **hif diff** - Diff between two states
- [ ] **hif goto** - View tree at specific state

## Completed

- [x] Project initialization
- [x] SKILL.md documentation
- [x] Clone command implementation
- [x] Token refresh with file-system locking
- [x] Conflict resolution (server-side)
- [x] Error recovery and rollback
- [x] gRPC client with TLS support
- [x] Basic CLI commands (auth, checkout, status, land)
- [x] Core primitives (Blake3, bloom filters, HLC, tree)
- [x] REST API for agents - RESTful API endpoints for AI agents (sessions, projects, content)

## Notes

- Reference NEXT.md for detailed feature specifications
- Reference DESIGN.md for architecture decisions
- Forge uses Elixir/Phoenix - run `mix test` for tests
- hif uses Zig 0.15 - run `cd hif && zig build test` for tests
- Focus on MVP functionality first
- Update this file after each major milestone

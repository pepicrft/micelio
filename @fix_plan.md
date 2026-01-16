# Micelio Fix Plan

## High Priority (Forge)

- [x] **Agent skill documentation** - Created `skills/micelio.md` with comprehensive agent onboarding guide
- [x] **Gravatar integration** - Use Gravatar as the default avatar for users based on their email
- [x] **OpenGraph utilities** - Helper functions for generating OG meta tags and dynamically generated OG images (includes Twitter Card support)

## Medium Priority (Forge UI)

- [x] **Activity graph** - GitHub-style contribution/activity visualization
- [x] **Account avatar customization** - Allow users to upload and change their account avatar

## High Priority (hif CLI)

- [x] **Binary serialization** - Implemented binary serialization for all core types (Tree, Bloom, HLC) in `hif/src/core/serialize.zig`
- [x] **Bloom filter merge/rollup** - Added rollup, intersection, scaleUp, jaccardSimilarity, clone, isSubsetOf, isEmpty operations
- [x] **Local config** - ~/.hif/ configuration management with servers, aliases, and preferences

## Medium Priority (hif CLI)

- [x] **Tiered cache** - RAM -> SSD caching layer in `hif/src/cache.zig`, integrated with workspace checkout and sync
- [x] **Session conflict resolution** - `hif session resolve` interactive conflict resolution with ours/theirs/interactive strategies
- [x] **Bloom per session** - Bloom filter created on session start and updated when files are written. Stored in session.json as base64-encoded data
- [x] **Path index** - Track which sessions touch which paths (stored in `projects/{id}/landing/paths/{position}.bin`, exact match before bloom fallback)

## HIGH PRIORITY: End-to-End Flow (hif ↔ Micelio UI)

- [ ] **Sessions UI** - Display landed sessions in project view (who, when, goal, files changed)
- [ ] **Session detail page** - Show full session details: goal, conversation, file diffs
- [ ] **Project activity feed** - Timeline of recent sessions on project page
- [ ] **Verify auth flow** - Ensure `hif auth login` works end-to-end with OAuth
- [ ] **Verify land flow** - Ensure `hif land "goal"` successfully creates session visible in UI

## Low Priority (hif CLI - Phase 3)

- [x] **hif log** - List landed sessions via gRPC ListSessions endpoint
- [ ] **hif log --path** - Sessions touching specific path (requires backend path filtering)
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

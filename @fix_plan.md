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

- [x] **Sessions UI** - Display landed sessions in project view (in `ProjectLive.Show` with recent sessions list, session count, and navigation)
- [x] **Session detail page** - Show full session details (in `SessionLive.Show`: goal, conversation, decisions, file diffs with content viewer)
- [x] **Project activity feed** - Timeline of recent sessions on project page (5 most recent sessions displayed in project view)
- [x] **Verify auth flow** - gRPC auth server implemented with device registration, authorization, and token exchange (tests in `test/micelio/grpc/auth_server_test.exs`)
- [x] **Verify land flow** - Session landing implemented with tree updates, path indexing, and rollup (integration tests in `test/micelio/integration_test.exs`)

## High Priority (hif CLI - Build Performance)

- [x] **Replace gRPC C++ with nghttp2** - Migrate from 1.1GB google/grpc to lightweight nghttp2 (~500KB)
  - Use nghttp2 for HTTP/2 transport
  - Implement thin gRPC framing layer in Zig (5-byte header + protobuf)
  - Keep existing protobuf message encoding
  - Target: build time from 10+ mins → 30 seconds
  - Wire format: `[1B compressed][4B length BE][protobuf payload]`
  - Headers: `POST /package.Service/Method`, `content-type: application/grpc`, `te: trailers`

## Low Priority (hif CLI - Phase 3)

- [x] **hif log** - List landed sessions via gRPC ListSessions endpoint
- [x] **hif log --path** - Sessions touching specific path (backend path filtering via gRPC ListSessions with path field)
- [x] **hif diff** - Diff between two states (GetTreeAtPosition endpoint + client-side diff computation)
- [x] **hif goto** - View tree at specific state (GetTreeAtPosition endpoint + file listing)

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

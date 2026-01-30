---
status: complete
priority: p1
issue_id: "001"
tags: [mic, cli, workspace, landing]
dependencies: []
---

# Add workspace linking for mic land

## Problem Statement

`mic land` requires `.mic/workspace.json`, which is created by `mic checkout`. In an existing local project directory, there is no mapping to a remote Micelio project, so landing fails even when authentication works and the remote project exists. We need a Git-like explicit linking step to map a local workspace to a remote project before landing.

## Findings

- Landing reads `.mic/workspace.json` for `server`, `account`, and `project` (`mic/src/workspace.zig`, `mic/src/workspace/manifest.zig`).
- Default server config includes micelio.dev with gRPC at `https://api.micelio.dev:443` (`mic/src/config.zig`).
- There is no command to link an existing local directory to a remote project.

## Proposed Solutions

### Option 1: `mic link <target>` (recommended)

**Approach:** Add a new command that accepts either a web URL or `org/project`, infers gRPC endpoint, validates auth, and writes `.mic/workspace.json`.

**Pros:** Clear UX; keeps `mic land` simple; explicit mapping.

**Cons:** New command surface area.

**Effort:** 4-6 hours

**Risk:** Medium

---

### Option 2: Extend `mic land` to accept `--project`

**Approach:** Add `--project`/`--server` flags so `mic land` can bootstrap metadata.

**Pros:** One command.

**Cons:** More complex `mic land`; implicit mapping.

**Effort:** 4-6 hours

**Risk:** Medium

## Recommended Action

Implement Option 1: `mic link <target>` accepts `org/project` (default server) or full URL (infer gRPC as `https://api.<host>:443`, `http://localhost:50051` for localhost). Create manifest-only `.mic/workspace.json` and require link before `mic land`.

## Technical Details

**Affected files:**
- `mic/src/main.zig` (CLI command parsing)
- `mic/src/workspace.zig` (linking helper)
- `mic/src/workspace/manifest.zig` (manifest writes)
- `docs/users/mic-workflows.md` (docs update)
- `mic/src/workspace.zig` (tests)

## Acceptance Criteria

- [x] `mic link https://micelio.dev/micelio/micelio` writes `.mic/workspace.json` with correct server/account/project.
- [x] `mic link micelio/micelio` uses default server and writes `.mic/workspace.json`.
- [x] `mic land "<goal>"` without `.mic/` errors and instructs to run `mic link`.
- [x] After linking, `mic land "<goal>"` lands changes and prints landing position.
- [x] `mic link` errors with re-auth guidance when token server mismatches inferred server.
- [x] Docs updated with link flow and examples.

## Work Log

### 2026-01-29 - Implementation

**By:** Codex

**Actions:**
- Added `mic link` command in `mic/src/main.zig`.
- Implemented link logic and URL/ref parsing in `mic/src/workspace.zig`.
- Added tests for link parsing in `mic/src/workspace.zig`.
- Updated error messaging for missing workspace metadata to mention `mic link`.
- Documented link workflow in `docs/users/mic-workflows.md`.
- Fixed stdout handling in `mic/src/main.zig` for Zig 0.15.
- Ran `zig build test`.
- Local test: started `mix phx.server`, generated local OAuth token, ran `mic link http://localhost:4000/micelio/micelio` and `mic land "Second land"` in `/tmp/mic-link-test2`.
- Verified `mic land` without link exits non-zero in `/tmp/mic-no-link`.

**Learnings:**
- URL parsing uses `std.Uri` components; localhost mapping requires http handling.
- Building the CLI on Zig 0.15 requires `std.fs.File.stdout()`.

# Fix Plan (Priority Order)

## P1 — Magic-link auth + ToS
1. Implement magic-link request + sign-in flow in web UI.
2. Enforce ToS acceptance on first sign-in using existing `/terms`.
3. Add CLI auth flow to obtain token from forge; persist token in SQLite only.
4. Add/verify typecheck/tests for auth and ToS gating.

## P2 — Project creation + public visibility
1. Add web UI project creation form and backend flow.
2. Add CLI command to create project.
3. Support public/private toggle and persistence.
4. Ensure public projects are viewable without login and indexed.
5. Add/verify typecheck/tests.

## P3 — Session capture with metadata
1. Define session schema: goal, transcript, decisions, changes.
2. Ensure transcript is append-only and immutable.
3. Capture per-message metadata: provider, model, version, system prompt hash + text, tools/permissions, temperature, max tokens, seed (if available), tool calls, tool outputs, token usage.
4. Add CLI session start + attach messages/decisions.
5. Add/verify typecheck/tests.

## P4 — Landing via CI checks
1. Implement CI gate: run `mix precommit` and `zig build test` for hif.
2. Add CLI command to initiate land and show check status.
3. Persist check results with session in forge.
4. Show check status per session in UI.
5. Add/verify typecheck/tests.

## P5 — Session browsing/sharing + SEO
1. Project page lists sessions with goal, author, timestamp, status.
2. Session detail shows conversation, decisions, file changes.
3. Public URL renders session detail for public projects.
4. Add SEO metadata: canonical URL, meta description, OG tags, Twitter Card tags.
5. Private pages: set noindex and omit OG share data.
6. Add/verify typecheck/tests.

## P6 — Storage abstraction (disk + S3)
1. Implement Elixir storage interface with disk and S3 backends.
2. Ensure disk layout mirrors S3 structure from `DESIGN.md`.
3. Configure backend selection via MICELIO_* env vars only.
4. Add/verify typecheck/tests.

## P7 — CLI polish
1. Ensure commands: auth, project create, checkout/clone, status, session start/list, land.
2. Improve error messages and recovery guidance.
3. Align help text with `SKILL.md`.
4. Add/verify typecheck/tests.

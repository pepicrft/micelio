# Micelio Ralph Project

## Goal
Deliver a session-first forge MVP for Micelio: magic-link auth with required ToS acceptance, project creation with public sharing, agent-driven sessions with full conversation + model metadata, CI-gated landing, and public shareable UI.

## Scope
- Web UI for magic-link sign-in, ToS gating, project creation, session browsing, and public session sharing.
- CLI support for auth, project creation, session start/list, checkout/clone, status, and landing with CI checks.
- Session capture system that stores immutable transcripts, decisions, and detailed model metadata.
- CI gate integration storing check results per session and surfaced in UI.
- Storage abstraction for disk and S3 with configuration via MICELIO_* env vars.

## Out of Scope
- Any behavior not explicitly listed in acceptance criteria.
- Changes to auth token storage outside SQLite.
- Non-MICELIO_* environment configuration for storage.

## References
- PRD: `prd.json`
- Storage layout: `DESIGN.md` (disk layout must mirror S3 structure)
- Terms page: existing `/terms` route
- CLI help: `SKILL.md` (help text alignment)

## Ralph Requirements
- Use the PRD as source of truth.
- Preserve all acceptance criteria as requirements.
- Maintain priority order (P1–P7) when planning tasks.
- Provide explicit CI gate requirements: `mix precommit` and `zig build test` for hif.
- All features must pass typecheck/tests.

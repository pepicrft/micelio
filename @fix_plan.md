# Micelio Fix Plan - Ralph All Night

**Ralph uses ONLY Codex for code. Validates and pushes after every task.**

## Task 1

- [ ] **Implement hif CLI auth command** - Create `hif/src/auth.zig` with device flow authentication using Elixir server's /auth/device endpoint. Export AuthFlow struct with start, poll, complete methods. Handle device_code, user_code, verification_uri. Return tokens and store in ~/.hif/tokens.json.

## Next Tasks (from NEXT.md)

When Task 1 is complete, implement:
- hif clone command
- hif checkout command
- hif status command
- hif land command
- Dashboard LiveView
- User notifications
- Search UI

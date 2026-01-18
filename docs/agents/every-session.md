# Every Session Checklist

Before making changes:

1. **Pull latest**: `git pull origin main`
2. **Check tests pass**: `mix test`
3. **Review recent commits**: `git log --oneline -10`

## Quick Reference

```bash
# Build
mix compile --warnings-as-errors
cd mic && zig build

# Test
mix test
cd mic && zig build test

# Format
mix format --check-formatted
cd mic && zig fmt --check src/

# Pre-commit (run before pushing)
mix compile --warnings-as-errors && mix format --check-formatted && mix test
cd mic && zig build && zig fmt --check src/ && zig build test
```

## Shortcut

Use the precommit alias when done with all changes:

```bash
mix precommit
```

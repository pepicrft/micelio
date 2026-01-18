# First Run Setup

## Prerequisites

- Elixir 1.16+ with OTP 26+
- Zig 0.15
- PostgreSQL
- libgit2 (for Zig NIFs)

## Setup

```bash
# Install Elixir dependencies
mix deps.get

# Setup database
mix ecto.setup

# Build Zig CLI
cd mic && zig build && cd ..

# Start development server
mix phx.server
```

## Verify Installation

```bash
# Run all tests
mix test
cd mic && zig build test
```

## Important Files

| File | Purpose |
|------|---------|
| `AGENTS.md` | This guide (root hub) |
| `priv/static/skill.md` | Agent guide served at `/skill.md` - keep in sync with AGENTS.md |
| `priv/static/SKILL.md` | mic CLI docs served at `/SKILL.md` |

# Tools & Commands

## Elixir (Forge)

| Command | Purpose |
|---------|---------|
| `mix compile --warnings-as-errors` | Compile with strict warnings |
| `mix phx.server` | Start dev server |
| `mix test` | Run tests |
| `mix test --failed` | Re-run failed tests |
| `mix test test/path.exs` | Run specific test file |
| `mix format` | Format code |
| `mix format --check-formatted` | Check formatting |
| `mix ecto.migrate` | Run migrations |
| `mix ecto.gen.migration name` | Generate migration |
| `mix help task_name` | Get task docs |
| `mix precommit` | Run all pre-commit checks |

## Zig (mic CLI)

| Command | Purpose |
|---------|---------|
| `zig build` | Build |
| `zig build test` | Run tests |
| `zig fmt src/` | Format code |
| `zig fmt --check src/` | Check formatting |

## Static Assets

| File | Served At | Purpose |
|------|-----------|---------|
| `priv/static/SKILL.md` | `/SKILL.md` | mic CLI documentation |
| `priv/static/skill.md` | `/skill.md` | Agent guide (keep aligned with AGENTS.md) |

## HTTP Requests

Use `:req` (`Req`) for HTTP requests. It's included by default.

**Never use**: `:httpoison`, `:tesla`, `:httpc`

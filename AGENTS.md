# Micelio for AI Agents

Micelio is a forge platform built with Elixir/Phoenix, Zig for CLI tools, and vanilla CSS for web UI.

## IMPORTANT: Terminology

**Always use "projects" instead of "repositories".** Micelio uses the term "projects" to refer to what Git calls repositories. This is intentional and must be followed consistently throughout the codebase, documentation, and UI.

## IMPORTANT: Internationalization (i18n)

**All user-facing strings must use gettext.** When adding or modifying UI text:

1. Wrap strings with `gettext("...")` in templates and modules
2. Run `mix gettext.extract` to extract new strings to POT files
3. Run `mix gettext.merge priv/gettext` to update all locale PO files
4. Ensure translations are provided for all supported locales: English (en), Korean (ko), Simplified Chinese (zh_CN), Traditional Chinese (zh_TW), Japanese (ja)

Translation files are located in `priv/gettext/{locale}/LC_MESSAGES/`.

- **Package Manager:** Elixir uses `mix`, Zig uses `zig`
- **Build:** `mix compile`, `mix phx.server` for dev
- **Test:** `mix test`
- **Pre-commit:** `mix precommit`

## Detailed Guidelines

- [Micelio Project Context](./docs/agents/project-context.md) - What is Micelio, tech stack
- [First Run Setup](./docs/agents/first-run.md) - Initial setup instructions
- [Every Session Checklist](./docs/agents/every-session.md) - What to do at start of session
- [Tools & Commands](./docs/agents/tools.md) - Available tools and commands
- [Skills & Abilities](./docs/agents/skills.md) - Skills system
- [Memory & Continuity](./docs/agents/memory.md) - Memory and persistence
- [Development Workflow](./docs/agents/development.md) - Git flow, deployment, code quality
- [Debugging Production Issues](./docs/agents/debugging.md) - Production debugging guide
- [Writing Tests](./docs/agents/testing.md) - Testing standards
- [Code Style & Conventions](./docs/agents/style.md) - Elixir, Phoenix, Ecto, CSS conventions

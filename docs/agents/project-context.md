# Micelio Project Context

Micelio is a monorepo containing:

- **Forge** (Elixir/Phoenix) - The web application and gRPC server
- **hif** (Zig) - The `hif` command-line interface

## Architecture

See [docs/contributors/next.md](../contributors/next.md) for upcoming features and [docs/contributors/design.md](../contributors/design.md) for architecture.

## Tech Stack

| Component | Technology | Location |
|-----------|------------|----------|
| Web App | Elixir/Phoenix 1.8 | `/` (root) |
| CLI | Zig 0.15 | `/hif` |
| Database | PostgreSQL + Ecto | - |
| Frontend | LiveView + vanilla CSS | - |

## Key Modules

### hif (Zig CLI)

Located in `hif/`, organized as:

- `hif/src/core/hash.zig` - Blake3 hashing for content-addressed storage
- `hif/src/core/bloom.zig` - Bloom filters for conflict detection
- `hif/src/core/hlc.zig` - Hybrid Logical Clocks for distributed timestamps
- `hif/src/core/tree.zig` - B+ tree for directory structures
- `hif/src/root.zig` - Library entry point and re-exports

### Zig NIFs

Git operations are implemented using Zig NIFs with libgit2 in `zig/git/git.zig`:

- **Shared utilities** - `init_libgit2()`, `null_terminate()`
- **Status domain** - `status()` for working tree status
- **Repository domain** - `repository_init()`, `repository_default_branch()`
- **Tree domain** - `tree_list()`, `tree_blob()` for browsing repository content

The Elixir module `Micelio.Git` exposes:

- `status/1` - Get working tree status
- `repository_init/1` - Initialize a new repository
- `repository_default_branch/1` - Get the default branch name
- `tree_list/3` - List entries at a ref and path
- `tree_blob/3` - Read file content at a ref and path

All functions return `{:ok, result}` or `{:error, reason}` tuples.

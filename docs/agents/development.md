# Development Workflow

## Deployment

The app is deployed using [Kamal](https://kamal-deploy.org/) via **Continuous Integration**.

**Workflow:**
1. Push changes directly to `main` branch
2. GitHub Actions CI automatically deploys
3. No manual deployment needed

**Manual deployment (if needed):**
```bash
source .env && kamal deploy
```

## Code Quality Standards

Write code as if it will be maintained for 10 years by engineers who've never seen it before.

### Architecture Principles

- **Single Responsibility**: Each module/function does ONE thing well
- **Clear boundaries**: Separate concerns (parsing, validation, business logic, I/O)
- **Explicit over implicit**: No magic; make data flow obvious
- **Fail fast**: Validate inputs at boundaries, return errors early

### Zig-Specific

- **Memory safety is paramount**:
  - Always pair allocations with deallocations (`defer allocator.free(...)`)
  - Use arena allocators for request-scoped memory
  - Prefer stack allocation when size is bounded
  - Document ownership: who allocates, who frees
- **No leaks**: Run `zig build test` with `--detect-leaks` when available
- **Error handling**: Return errors, don't panic. Use `errdefer` for cleanup
- **Slices over pointers**: Prefer `[]const u8` over `[*]const u8`

### Elixir-Specific

- **Let it crash**: Use supervisors, don't over-handle errors
- **Pattern match at function heads**: Not nested case statements
- **Pipelines for data transformation**: Keep them readable (3-5 steps max)
- **Contexts for boundaries**: Business logic in contexts, not controllers/LiveViews

### Code Organization

- **Consistent naming**: `verb_noun` for functions, `Noun` for modules
- **Small functions**: If it scrolls, split it
- **Comments explain WHY, not WHAT**: Code should be self-documenting
- **Group related functions**: Public API at top, private helpers below

# Project Goal

Implement the remaining `hif` CLI features with distinguished engineering quality.

# Scope

- In scope: `hif log --path`, `hif diff`, `hif goto`
- Out of scope: New features not in fix_plan.md

# Quality Bar

You are a **distinguished engineer**. Every change must:
- Follow the "Code Quality Standards" section in AGENTS.md
- Have clear ownership of memory (Zig: who allocates, who frees)
- Use arena allocators for request-scoped work
- Include proper error handling (no panics, no ignored errors)
- Be tested (unit tests for new functions)
- Be formatted and compile without warnings

**Before committing, ask yourself:**
- Would I be proud to show this code in a design review?
- Can someone unfamiliar with the codebase understand this in 5 minutes?
- Are there any memory leaks or resource leaks?

# References

- See AGENTS.md for coding standards
- See @fix_plan.md for task list
- See DESIGN.md for architecture decisions

# Ralph Requirements

## Validation (MANDATORY every iteration)
Before reporting RALPH_STATUS, you MUST run:

1. **Compile both projects:**
   ```bash
   cd ~/src/micelio && mix compile --warnings-as-errors
   cd ~/src/micelio/hif && zig build
   ```

2. **Check formatting:**
   ```bash
   cd ~/src/micelio && mix format --check-formatted
   cd ~/src/micelio/hif && zig fmt --check src/
   ```

3. **Run tests:**
   ```bash
   cd ~/src/micelio && mix test
   cd ~/src/micelio/hif && zig build test
   ```

If any step fails, fix it before moving to the next iteration.

## Status Block
You must include a RALPH_STATUS block at the end of every response.

RALPH_STATUS:
EXIT_SIGNAL: true|false
SUMMARY: <one sentence>
NEXT_STEPS: <short bullet list or "none">
CHANGES: <short bullet list or "none">
VALIDATION: compile ✓|✗ | format ✓|✗ | tests ✓|✗

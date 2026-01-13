# Agents Guidelines

This document provides guidelines for AI agents working on the hif codebase.

## Core Module Changes

The core modules (`src/core/*.zig`) are used directly by the hif CLI. Keep the APIs stable and well-tested so the CLI and future integrations remain reliable.

## Module Structure

- `src/core/hash.zig` - Blake3 hashing for content-addressed storage
- `src/core/bloom.zig` - Bloom filters for conflict detection
- `src/core/hlc.zig` - Hybrid Logical Clocks for distributed timestamps
- `src/core/tree.zig` - B+ tree for directory structures
- `src/root.zig` - Library entry point and re-exports

## Testing

Run all tests with:

```bash
zig build test
```

Tests are organized by module. Each core module includes comprehensive unit tests covering normal operation, edge cases, and error conditions.

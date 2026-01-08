# Agents Guidelines

This document provides guidelines for AI agents working on the hif codebase.

## C API Requirements

**Important:** Any changes to the core modules (`src/core/*.zig`) must be surfaced through the C API:

1. Update `src/ffi.zig` to export new functions with C-compatible signatures
2. Update `include/hif_core.h` to declare the new C functions
3. Add FFI tests in `src/ffi.zig` to verify the C bindings work correctly

The C API is the primary interface for FFI consumers (Elixir via Zigler, Go via cgo, etc.). Keeping it in sync with core functionality ensures the forge and other integrations can use all hif features.

## Module Structure

- `src/core/hash.zig` - Blake3 hashing for content-addressed storage
- `src/core/bloom.zig` - Bloom filters for conflict detection
- `src/core/hlc.zig` - Hybrid Logical Clocks for distributed timestamps
- `src/core/tree.zig` - B+ tree for directory structures
- `src/ffi.zig` - C ABI exports for all core modules
- `src/root.zig` - Library entry point and re-exports

## Testing

Run all tests with:

```bash
zig build test
```

Tests are organized by module. Each core module includes comprehensive unit tests covering normal operation, edge cases, and error conditions.

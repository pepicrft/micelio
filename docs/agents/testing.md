# Writing Tests

## General Principles

- **Test behavior, not implementation**: Focus on public API contracts
- **Edge cases**: Empty inputs, nil/null, boundaries, unicode, large inputs
- **Memory tests for Zig**: Ensure no leaks under various code paths
- **Property-based tests** where applicable (StreamData for Elixir)
- **Do not modify OS environment variables in tests**: Use dependency injection via config/env maps instead

## Elixir Tests

```bash
mix test                    # Run all tests
mix test --failed           # Re-run failed tests
mix test test/path.exs      # Run specific file
```

### Test Module Setup

```elixir
defmodule MyApp.MyTest do
  use ExUnit.Case, async: true  # Always use async: true

  # Always use start_supervised! for processes
  setup do
    pid = start_supervised!(MyGenServer)
    %{pid: pid}
  end
end
```

### Process Synchronization

**Avoid** `Process.sleep/1` and `Process.alive?/1`.

Instead of sleeping to wait for a process:

```elixir
# Good - use monitor
ref = Process.monitor(pid)
assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

# Good - use :sys.get_state for sync
_ = :sys.get_state(pid)
```

## Zig Tests

```bash
cd hif && zig build test
```

Tests are organized by module. Each core module includes comprehensive unit tests covering normal operation, edge cases, and error conditions.

## LiveView Tests

Use `Phoenix.LiveViewTest` module and `LazyHTML` for assertions.

### Key Points

- Form tests use `render_submit/2` and `render_change/2`
- **Always** reference key element IDs in tests
- Use `element/2`, `has_element/2` instead of raw HTML matching
- Test outcomes, not implementation details

### Debugging Test Failures

```elixir
html = render(view)
document = LazyHTML.from_fragment(html)
matches = LazyHTML.filter(document, "your-selector")
IO.inspect(matches, label: "Matches")
```

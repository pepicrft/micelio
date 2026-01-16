# @AGENT

## Build

### Elixir (server)
```bash
cd ~/src/micelio
mix compile --warnings-as-errors
```

### Zig (hif CLI)
```bash
cd ~/src/micelio/hif
zig build
```

## Test

### Elixir
```bash
cd ~/src/micelio
mix test
```

### Zig
```bash
cd ~/src/micelio/hif
zig build test
```

## Format

### Elixir
```bash
cd ~/src/micelio
mix format --check-formatted
```

### Zig
```bash
cd ~/src/micelio/hif
zig fmt --check src/
```

## Validation (run all before committing)
```bash
cd ~/src/micelio
mix compile --warnings-as-errors && mix format --check-formatted && mix test
cd ~/src/micelio/hif
zig build && zig fmt --check src/ && zig build test
```

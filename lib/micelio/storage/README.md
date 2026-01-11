# Micelio Storage

Session file storage abstraction with **local filesystem by default** and **S3 as opt-in**.

## Architecture

The `Micelio.Storage` module provides a unified interface for storing session files and artifacts. Backend selection is configurable, with local filesystem as the default.

### Local Storage (Default)

Files are stored in the local filesystem:

```elixir
# Development (default)
config :micelio, Micelio.Storage,
  backend: :local,
  local_path: "/tmp/micelio/storage"

# Production
config :micelio, Micelio.Storage,
  backend: :local,
  local_path: "/var/micelio/storage"
```

**Directory structure:**
```
/var/micelio/storage/
  sessions/
    <session-id>/
      files/
        <file-path>
      metadata.json
```

### S3 Storage (Opt-in)

For scalability, you can configure S3:

```elixir
config :micelio, Micelio.Storage,
  backend: :s3,
  s3_bucket: "micelio-sessions",
  s3_region: "us-east-1"
```

**Environment variables (production):**
```bash
STORAGE_BACKEND=s3
S3_BUCKET=your-bucket-name
S3_REGION=us-east-1
# AWS credentials via IAM roles or:
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
```

## Usage

```elixir
# Store a file
{:ok, key} = Storage.put("sessions/abc123/files/main.ex", content)

# Retrieve a file
{:ok, content} = Storage.get("sessions/abc123/files/main.ex")

# Check existence
true = Storage.exists?("sessions/abc123/files/main.ex")

# List files
{:ok, files} = Storage.list("sessions/abc123/")

# Delete a file
{:ok, _} = Storage.delete("sessions/abc123/files/main.ex")
```

## Implementation Status

- ✅ **Local storage**: Fully implemented
- ⚠️  **S3 storage**: Stub implementation (falls back to local with warning)

### Next Steps for S3

To implement S3 storage:

1. Add `ex_aws` and `ex_aws_s3` dependencies
2. Implement `Micelio.Storage.S3` functions using ExAws
3. Add IAM policy documentation
4. Add bucket lifecycle policies for cleanup

## Design Principles

Following DESIGN.md:

- **Local-first**: Works without external dependencies
- **Self-hostable**: No vendor lock-in
- **Scalable**: S3 opt-in for cloud deployments
- **Simple**: Unified API regardless of backend

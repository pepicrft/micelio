# Session Artifacts in Micelio

## Philosophy: Git tracks what. hif tracks why.

Micelio's session system implements the hif philosophy where development is organized around **sessions** instead of commits. Each session captures the complete context of a unit of work:

- **Goal**: What you're trying to accomplish
- **Conversation**: Discussion between agents and humans
- **Decisions**: Why things were done a certain way
- **Changes**: The actual file modifications

## Session Changes vs Git Commits

Unlike Git commits which are snapshots of code at a point in time, session changes capture file modifications with their reasoning context.

## Session Lifecycle (API + CLI)

- Start without landing: `POST /api/sessions/start`
- Land with artifacts: `POST /api/sessions/:session_id/land`
- Single-shot land (start + land): `POST /api/sessions`
- CLI helpers:
  - `mix micelio.session.start --session-id ... --goal ... --organization ... --project ...`
  - `mix micelio.session.land --session-id ... [--file path[:change_type]] [--metadata key=value,...]`

### Key Differences

| Git Commits | Session Changes |
|-------------|-----------------|
| Snapshot-based | Context-aware |
| What changed | What changed + why |
| Manual commit messages | Integrated conversation |
| Lost iterations | Preserved reasoning |
| Linear history | Session-based grouping |

## Schema Design

### Session
The main session record contains:
- `goal`: What the session aims to accomplish
- `conversation`: Array of messages (agent/human dialog)
- `decisions`: Array of decision records with reasoning
- `metadata`: Additional context
- `status`: active, landed, or abandoned
- `changes`: Has-many relationship to SessionChange

### SessionChange
Individual file modifications within a session:
- `file_path`: The file that changed
- `change_type`: "added", "modified", or "deleted"
- `content`: Inline content for small files (< 100KB)
- `storage_key`: S3/local storage reference for large files
- `metadata`: File-specific metadata (size, lines changed, etc.)

## Storage Strategy

Files are stored based on size:
- **Small files (< 100KB)**: Stored inline in `content` field
- **Large files (≥ 100KB)**: Stored in object storage, referenced by `storage_key`

Storage path pattern: `sessions/{session_id}/changes/{file_path}`

## API Usage

### Creating a Session with Changes

```bash
POST /api/sessions
{
  "session_id": "unique-id",
  "goal": "Add authentication system",
  "organization": "myorg",
  "project": "myapp",
  "conversation": [
    {"role": "user", "content": "We need JWT-based auth"},
    {"role": "assistant", "content": "I'll implement with bcrypt for passwords"}
  ],
  "decisions": [
    {
      "decision": "Use JWT tokens for stateless auth",
      "reasoning": "Keeps the system scalable and cloud-friendly"
    }
  ],
  "files": [
    {
      "path": "src/auth/jwt.ex",
      "change_type": "added",
      "content": "defmodule Auth.JWT do..."
    },
    {
      "path": "src/main.ex",
      "change_type": "modified",
      "content": "# Updated with auth routes..."
    },
    {
      "path": "src/old_auth.ex",
      "change_type": "deleted"
    }
  ]
}
```

### Response Format

```json
{
  "session": {
    "id": "...",
    "session_id": "unique-id",
    "goal": "Add authentication system",
    "project": "myorg/myapp",
    "status": "landed",
    "conversation_count": 2,
    "decisions_count": 1,
    "changes": {
      "total": 3,
      "added": 1,
      "modified": 1,
      "deleted": 1
    },
    "started_at": "2026-01-12T07:30:00Z",
    "landed_at": "2026-01-12T07:32:00Z"
  }
}
```

## Programmatic Access

### Elixir Context Functions

```elixir
# Get session with changes
session = Sessions.get_session_with_changes(session_id)

# List all changes
changes = Sessions.list_session_changes(session)

# Get change statistics
stats = Sessions.get_session_change_stats(session)
# => %{total: 3, added: 1, modified: 1, deleted: 1}

# Count specific change types
added_count = Sessions.count_session_changes(session, change_type: "added")

# Create changes
{:ok, changes} = Sessions.create_session_changes([
  %{
    session_id: session.id,
    file_path: "src/new.ex",
    change_type: "added",
    content: "..."
  }
])
```

## UI Display

The session show page displays:

1. **Goal** - What the session accomplished
2. **Conversation** - The dialog that led to decisions
3. **Decisions** - Explicit reasoning for choices made
4. **Changes Summary** - Stats: total, added, modified, deleted
5. **Changes List** - Individual file changes with:
   - Change type badge (+/~/-)
   - File path
   - File size
   - Expandable content viewer

## Benefits

### For Developers
- **Never lose context** - Reasoning is preserved with code
- **Better code review** - Understand why, not just what
- **Faster onboarding** - Historical context is clear
- **Agent collaboration** - Seamless human/AI workflows

### For Teams
- **Knowledge preservation** - Decisions are documented automatically
- **Transparent development** - See the full development process
- **Reduced meetings** - Async decision-making with context
- **Audit trail** - Complete history of reasoning

### For Organizations
- **Compliance** - Full audit trail of changes and decisions
- **Knowledge management** - Institutional knowledge in version control
- **Efficient scaling** - New team members have full context
- **AI-ready** - Built for agent-first development

## Migration from Git

While this is a new system (not Git), migration involves:

1. Import Git commits as session changes
2. Optionally add conversation/decision context
3. Organize commits into logical sessions by topic

A migration tool is planned for the roadmap.

## Future Enhancements

- [ ] Diff view between changed files
- [ ] Visual timeline of session changes
- [ ] AI-generated decision summaries
- [ ] Cross-session change analysis
- [ ] Advanced search/filtering by file patterns
- [ ] Integration with code review workflows

## Related Documentation

- [DESIGN.md](/DESIGN.md) - Complete hif + Micelio vision
- [hif/DESIGN.md](/hif/DESIGN.md) - Technical architecture
- [API Documentation](/docs/API.md) - Full API reference

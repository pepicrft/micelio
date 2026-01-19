# Micelio - Agent-First Git Forge

Micelio is a minimalist, open-source git forge built with Elixir/Phoenix, designed for the agent-first future of software development. It integrates with mic (a Zig-based version control system) to provide session-based workflows that capture not just what changed, but why.

## Tasks

### Forge (Elixir/Phoenix)

- [x] Add rate limiting middleware for unauthenticated API requests
- [x] Implement public vs private project visibility settings in the database schema and authorization
- [x] Create project settings page for changing visibility, name, and description
- [x] Add OpenAPISpex setup for automatic API documentation generation
- [x] Implement fediverse integration for ActivityPub-compatible forge federation
- [x] Add project starring/favorites functionality with database schema and UI
- [x] Create project search functionality with full-text search across names and descriptions
- [x] Implement project forking with proper ownership and origin tracking
- [x] Add webhook support for project events (push, session land, etc.)
- [x] Create user profile page showing owned projects and activity
  - Note: Activity graph (like GitHub's contribution graph) should be added
- [x] Add user activity graph (GitHub-style contribution visualization) to profile page
- [x] Fix activity graph styling
  - Reduce spacing between "Activity" title and the graph (too much whitespace currently)
  - Change gradient from light gray to green (currently dark gray to green)
  - Ensure consistent visual styling with the rest of the profile page
- [x] Rename "Owned repositories" section header to "Projects"
  - Use "Projects" terminology consistently throughout the platform
  - Update both the heading text and any associated aria labels
- [x] Add organizations section to user profile page
  - Display organizations the user belongs to
  - Show organization name, avatar, and member count for each
  - Link each organization to its organization page
  - Position appropriately in the profile layout (after projects or in sidebar)
  - Handle case where user belongs to no organizations gracefully
- [x] Add profile description and social links support
  - Allow users to add a description/bio to their profile (text field, max ~160 chars)
  - Support adding social links: Twitter/X, GitHub, GitLab, Mastodon, LinkedIn, etc.
  - Support adding a personal website URL
  - Create settings UI for editing bio and social links
  - Display bio prominently on user profile page (below name/avatar)
  - Display social links as icons with hover tooltips
  - Validate URLs and handle edge cases (missing protocol, etc.)
- [x] Show user activity feed on profile page
  - Display the user's recent activity on the platform
  - Activity types to include: commits/sessions landed, projects created, projects starred, etc.
  - Show chronologically with most recent first
  - Each activity item includes: project name (linked), action description, timestamp
  - Paginate or lazy-load older activity (initial display: ~20 items)
  - Design consistent with activity graph aesthetic
- [x] Implement project README rendering on the project homepage
- [x] Add syntax highlighting for code file viewing using a server-side highlighter
- [x] Create project file browser with tree navigation
- [x] Implement blame view showing session attribution per line
- [x] Add tiered caching layer (RAM -> SSD -> CDN -> S3) for fast reads
- [x] Create admin dashboard for instance management and user oversight
- [x] Implement email notifications for project activity
- [x] Convert Micelio project into a workspace and push to micelio/micelio on micelio.dev
- [x] Create skill.md served from /skill.md for agents, and add note to AGENTS.md to keep it updated
- [x] Implement dynamic Open Graph images for public projects and pages
  - Generate lazily and persist to S3 for future use
  - Use content hash for cache invalidation
  - Support cache invalidation on X, LinkedIn, and other platforms
- [x] Create public agent LiveView to watch agent progress on projects
- [x] Implement daily theme generation using LLM API
  - Generate new theme personality each day and apply it
  - Persist generated themes in S3
  - Cache in memory for performance
  - Add footer explaining the daily personality design
- [x] Add JSON-LD structured data for SEO (Schema.org SoftwareSourceCode)
- [x] Create embeddable badges for projects (Shields.io-style for Micelio)
- [x] Implement ActivityPub federation for projects and profiles
- [x] Add GitHub OAuth authentication
  - Store as OAuthIdentity linked to user by provider_user_id (github_id), NOT by email
  - OAuthIdentity: user_id + provider + provider_user_id
- [x] Add GitLab OAuth authentication
  - Store as OAuthIdentity linked to user by provider_user_id (gitlab_id), NOT by email
  - OAuthIdentity: user_id + provider + provider_user_id
- [x] Add Passkey (WebAuthn) authentication support
- [x] Simplify legal pages with user responsibility disclaimers
  - Replace detailed privacy/cookies/terms pages with minimal pages
  - Include broad disclaimers: "Users are solely responsible for their content"
  - Example: "By using this service, you agree that you are solely responsible for the content you host"
- [x] Add popular projects section to homepage
  - Display trending or most-starred projects on the home screen
  - Include project thumbnail, description, and owner info
  - Make it visually prominent to encourage exploration
  - Sort by stars, recent activity, or trending score
  - Include pagination or infinite scroll for browsing
- [x] Create .ico favicon and configure site to use it
  - Design circular logo favicon (simple circle as per brand identity)
  - Generate .ico format at standard sizes (16x16, 32x32, 48x48)
  - Configure Phoenix to serve favicon.ico
  - Add to layout head section

### mic (Zig CLI)

- [x] Implement NFS v3 server for virtual filesystem (mic-fs) in mic/src/fs/nfs.zig
- [x] Create session overlay for tracking local changes before landing
- [x] Add `mic mount` command to mount project as virtual filesystem
- [x] Add `mic unmount` command to cleanly unmount virtual filesystem
- [x] Implement prefetch on directory open for better performance
- [x] Create bloom filter rollup background job for O(log n) conflict detection at scale
- [x] Add epoch batching mode for high-throughput landing scenarios
- [x] Implement CDN integration for blob serving
- [x] Add delta compression for efficient storage of similar files
- [x] Create `mic blame` command showing which session introduced each line
- [x] Implement `mic cat` command to print file contents at any ref
- [x] Add `mic ls` command to list directory contents at any ref

### Documentation & Testing

- [x] Add comprehensive integration tests for gRPC session workflows
- [x] Create property-based tests for bloom filter operations using StreamData
- [x] Write end-to-end tests for the complete land workflow
- [x] Add memory leak detection tests for Zig components
- [x] Create user documentation for common mic workflows
- [x] Add architecture decision records (ADRs) for key design choices
- [x] Ensure website is mobile-responsive and renders correctly on all screen sizes
- [x] Add Playwright tests to verify mobile layout on various viewport sizes
- [x] Create automated visual regression tests for mobile breakpoints

### Security & Compliance

- [x] Implement audit logging for all project operations
- [x] Add two-factor authentication (TOTP) support
- [x] Create project access tokens with scoped permissions
- [x] Implement branch protection rules for preventing direct lands to main
- [x] Add secret scanning to prevent credential leaks in landed sessions

### Legal & Terms

- [ ] Design simplified legal pages with user responsibility disclaimers
  - Create minimal Terms of Service with broad disclaimers instead of detailed legal pages
  - Make users solely responsible for the content they host
  - Example: "By using this service, you agree that you are solely responsible for the content you host"
  - Remove need for separate detailed privacy/cookie/terms/impressum pages
  - Single page covering all necessary disclaimers in plain language

### Platform Limits & Rate Limiting

- [ ] Implement rate limiting for unauthenticated and authenticated users
- [ ] Set initial project limits per tenant (prevent spam during early growth)
- [ ] Add abuse detection and mitigation systems

### Mobile Clients

- [ ] Create iOS native client using Swift (SwiftUI)
- [ ] Create Android native client using Jetpack Compose
- [ ] Implement authentication flow for both mobile clients
- [ ] Add basic project browsing and viewing capabilities
- [ ] Design API endpoints optimized for mobile (pagination, offline support)

### Agentic Infrastructure

- [ ] Design infrastructure for provisioning VMs and mounting volumes
- [ ] Evaluate cloud platforms for VM provisioning (AWS, GCP, Hetzner, etc.)
- [ ] Design abstraction protocol for cloud-agnostic VM management
- [ ] Implement remote execution service for running CLI tools (Claude, Codex, etc.)
- [ ] Add support for tenant-configurable LLM models per project
- [ ] Design secure sandboxed environment for agent execution
- [ ] Implement resource quota and billing for agentic workflows

### Open Graph & SEO

- [ ] Generate OG images for agents using LLM summaries of code changes
- [ ] Design template for agent progress OG images showing commits, files changed
- [ ] Implement cache invalidation strategy for social platform crawlers
- [ ] Add dynamic OG image generation for commits, PRs, and agent sessions

### Agent Quality & Contribution Model

This section addresses critical challenges with AI-generated contributions identified by Armin Ronacher ("Agent Psychosis") and tldraw ("Stay away from my trash!"). The core problems: AI contributions are cheap to generate but expensive to review, quality degrades over time, and "slop" (well-formed but low-quality code) is indistinguishable from good work without deep review.

- [ ] **Implement Prompt Request System (replaces traditional Issues/PRs)**
  - Require contributors to submit the prompt + generated result as a unit, not just a diff
  - Store the full agent context (model, system prompt, conversation history) alongside contributions
  - Enable reviewers to replay and understand why code was generated, not just what changed
  - Create UI for browsing prompt-result pairs with side-by-side diff visualization
  - Support "prompt improvement suggestions" as a review feedback mechanism

- [ ] **Build Ephemeral Validation Environments**
  - Provision temporary sandboxed VMs for each contribution before it becomes a PR
  - Run full test suite, linting, type checking, and style validation automatically
  - Reject contributions that fail quality thresholds before human review is required
  - Measure and report execution time, resource usage, and test coverage delta
  - Auto-teardown environments after validation (no persistent cost for failed attempts)

- [ ] **Create AI Contribution Transparency System**
  - Add mandatory "AI-generated" / "AI-assisted" / "Human" badges on all contributions
  - Track and display which LLM model and version generated the code
  - Show token count consumed during generation for efficiency awareness
  - Implement cryptographic attestation for contribution origin claims
  - Display generation timestamp vs submission timestamp to detect stale AI outputs

- [ ] **Implement Agent Reputation & Trust Scoring**
  - Calculate trust scores based on: landed contribution rate, review iteration count, test pass rate
  - Decay reputation over time (recent quality matters more than historical)
  - Separate reputation tracks for different contribution types (docs, tests, features, fixes)
  - Penalize contributions that pass CI but get rejected in review (slop detection)
  - Display reputation prominently on contributor profiles and contribution headers

- [ ] **Design Tiered Contribution Access Model**
  - New agents/contributors start with "sandbox only" access (no PR creation rights)
  - Require N successful sandbox validations before first PR is allowed
  - Implement progressive trust levels: sandbox → small PRs → large PRs → automated merge
  - Allow project maintainers to set trust thresholds per-project
  - Support "trusted introducer" model where established contributors can vouch for new ones

- [ ] **Build Token Efficiency Tracking & Metrics**
  - Measure total token cost per landed contribution (from first prompt to merge)
  - Track "token waste" from failed attempts, revisions, and context resets
  - Identify inefficient agent patterns (Ralph-style restart loops that burn context)
  - Create leaderboard showing most efficient agents by tokens-per-landed-line
  - Alert maintainers when agents exhibit degrading efficiency patterns

- [ ] **Implement Anti-Slop Rate Limiting**
  - Rate limit new contributors to max N submissions per day/week until trust earned
  - Implement exponential backoff for repeated validation failures
  - Pattern detection for AI-spawned contribution spam (similar prompts, copy-paste patterns)
  - Require cooling-off period between rejected contribution and next attempt
  - Create project-level settings for strictness of anti-spam measures

- [ ] **Design Human-in-the-Loop Checkpoints**
  - Require human review for first N contributions from any new agent
  - Implement "maintainer attention budget" tracking to prevent review exhaustion
  - Asymmetric cost accounting: track minutes-to-generate vs minutes-to-review
  - Alert when review queue depth suggests contribution rate exceeds review capacity
  - Support "batch review" mode for similar AI contributions to reduce review overhead

- [ ] **Build Quality Signal Aggregation Dashboard**
  - Show project-level metrics: AI vs human contribution ratio, average review time, rejection rate
  - Track quality trends over time (detect the "addiction loop" of easy AI contributions)
  - Visualize token efficiency across all contributing agents
  - Alert maintainers when AI contribution quality is trending downward
  - Compare contribution quality across different AI models/agents

- [ ] **Implement Noise Multiplication Prevention**
  - Detect when AI agents are responding to other AI-generated issues/PRs (cascade detection)
  - Require human approval before AI can act on AI-generated context
  - Track "generation depth" (human → AI → AI → AI) and enforce maximum depth limits
  - Flag contributions where the prompt itself appears to be AI-generated
  - Create circuit breakers that pause AI contributions when noise metrics exceed thresholds

### Prompt Request System

- [ ] Design Prompt Request Schema and UI
  - Create data model for PromptRequest: prompt text + execution result + metadata
  - Store the original prompt alongside the diff (not just the diff)
  - Track execution environment, token cost, and execution time
  - Show "prompt lineage" to understand how prompts evolved
  - Design UI that shows prompt → result relationship clearly

- [ ] Implement Ephemeral Validation Environment
  - Build isolated sandbox where agent proposals run before becoming PRs
  - Execute tests, linting, type checking automatically
  - Generate quality scores based on: test pass rate, compilation success, style compliance
  - Require minimum quality threshold before PR is created
  - Reject automatically if quality thresholds not met (no human review burden)
  - Persist sandbox execution logs for debugging failed attempts

- [ ] Create Prompt-to-PR Flow
  - Agent submits PromptRequest instead of direct PR
  - PromptRequest runs in ephemeral environment with full test suite
  - If quality passes: convert to PR with full context attached
  - If quality fails: return feedback to agent for revision (no human involved)
  - Maintain "generation depth" to prevent AI-to-AI cascades

- [ ] Build Quality Gate Pipeline
  - Automatic test execution (unit, integration, e2e)
  - Linting and style checking (Elixir formatter, Credo, Dialyzer)
  - Security scanning (semgrep, sobelow)
  - Performance baseline comparison (does it regress?)
  - Output quality score 0-100 for each category
  - Require minimum aggregate score to land

- [ ] Design Prompt Registry and Provenance
  - Store all prompts in searchable registry
  - Track which prompts lead to landed contributions vs rejected
  - Enable maintainers to "curate" high-quality prompts
  - Create "prompt templates" for common tasks (bug fix, feature add, refactor)
  - Allow agents to reference approved prompt templates

- [ ] Implement Human-in-the-Loop Feedback Loop
  - When ephemeral validation fails, return structured feedback to agent
  - Feedback includes: specific failures, suggested fixes, quality score breakdown
  - Agents can iterate without human intervention until quality met
  - Track iteration count as quality signal (high iterations = lower quality)

- [ ] Build Contribution Confidence Scoring
  - Calculate confidence score based on: ephemeral validation score, agent reputation, token efficiency
  - High confidence = fast-track review (trusted)
  - Low confidence = require human review
  - Display confidence score on all contributions
  - Learn from historical data to improve scoring accuracy

### Per-Account S3 Artifact Storage

Allow users to configure their own S3-compatible storage for artifacts (OG images, themes, agent outputs, etc.) instead of using the instance-level bucket. This enables data sovereignty, cost control, and compliance requirements.

- [ ] **Design S3Config Schema and Migration**
  - Create `s3_configs` table with fields:
    - `id` (UUID primary key)
    - `user_id` (foreign key to users, unique constraint for one config per user)
    - `provider` (enum: aws_s3 | cloudflare_r2 | minio | digitalocean_spaces | backblaze_b2 | wasabi | custom)
    - `bucket_name` (string, required)
    - `region` (string, required for AWS/DO/Wasabi, optional for R2/MinIO)
    - `endpoint_url` (string, required for non-AWS providers like R2, MinIO)
    - `access_key_id` (string, encrypted at rest)
    - `secret_access_key` (string, encrypted at rest using Cloak)
    - `path_prefix` (string, optional - for organizing files within bucket)
    - `validated_at` (datetime, null until validation passes)
    - `last_error` (text, stores last validation/usage error)
    - `inserted_at`, `updated_at` timestamps
  - Add database index on `user_id` for fast lookups
  - Create Ecto schema with Cloak.Ecto.Binary for encrypted fields

- [ ] **Implement Credential Encryption with Cloak**
  - Add `cloak` and `cloak_ecto` dependencies
  - Configure Cloak vault with AES-GCM-256 encryption
  - Store encryption key in environment variable (CLOAK_KEY)
  - Create custom Ecto type `EncryptedBinary` for S3 credentials
  - Implement key rotation strategy for Cloak vault
  - Ensure encrypted fields are never logged or exposed in error messages
  - Add `redact: true` to credential fields in Ecto schema

- [ ] **Build S3 Credential Validation Service**
  - Create `Micelio.Storage.S3Validator` module
  - Implement validation steps:
    1. Parse and validate endpoint URL format
    2. Test connection with `HeadBucket` operation (verify bucket exists)
    3. Test write permission with `PutObject` to `.micelio-test` file
    4. Test read permission with `GetObject` on the test file
    5. Test delete permission with `DeleteObject` on the test file
    6. Verify bucket is not public (optional security check)
  - Return structured validation result with specific error messages
  - Handle provider-specific quirks:
    - Cloudflare R2: no region required, use account ID in endpoint
    - MinIO: custom endpoint, may not support all S3 operations
    - Backblaze B2: S3-compatible endpoint differs from native API
  - Implement timeout and retry logic for validation requests
  - Cache validation results to avoid repeated checks

- [ ] **Create Fallback Logic for Storage Operations**
  - Create `Micelio.Storage` behaviour with `put/3`, `get/2`, `delete/2`, `url/2`
  - Implement `Micelio.Storage.UserS3` adapter that:
    1. Looks up user's S3Config (with caching via ETS or ConCache)
    2. Falls back to instance S3 if user has no config or config is invalid
    3. Logs which storage backend was used for debugging
  - Handle graceful degradation when user S3 fails:
    - Log error and alert user
    - Optionally fall back to instance storage with notification
    - Mark S3Config as invalid after N consecutive failures
  - Add telemetry events for storage operations (success, failure, fallback)
  - Create background job to periodically revalidate S3 configs

- [ ] **Build S3 Configuration UI**
  - Create LiveView at `/settings/storage` for S3 configuration
  - Form fields with provider-specific dynamic sections:
    - Provider dropdown (shows/hides relevant fields based on selection)
    - Bucket name with validation (alphanumeric, hyphens, 3-63 chars)
    - Region dropdown (populated based on provider)
    - Endpoint URL (auto-populated for known providers, editable for custom)
    - Access Key ID input
    - Secret Access Key input (masked, with show/hide toggle)
    - Path prefix (optional)
  - "Test Connection" button that validates without saving
  - Real-time validation feedback (spinner, success/error states)
  - Show current validation status and last error if any
  - "Remove Configuration" button to delete and revert to instance storage
  - Help text explaining each provider's setup requirements
  - Link to documentation for obtaining credentials from each provider

- [ ] **Document Security Considerations and IAM Policies**
  - Create documentation for recommended IAM policies per provider:
    - AWS: minimal IAM policy with only required S3 permissions
    - R2: API token with Object Read & Write permissions
    - MinIO: policy JSON for bucket-specific access
  - Document encryption requirements:
    - Encryption at rest in Micelio database (Cloak)
    - Recommend users enable server-side encryption on their buckets
  - Security checklist for users:
    - Use dedicated credentials (not root/admin)
    - Enable bucket versioning for data recovery
    - Configure bucket lifecycle policies for cost control
    - Disable public access on bucket
  - Add rate limiting on validation endpoint to prevent credential stuffing
  - Implement audit logging for S3 config changes

### Error Tracking & Monitoring

Implement a self-hosted error tracking system that persists errors to the database with admin-only access. This avoids external service dependencies while providing visibility into application health.

- [ ] **Choose Error Tracking Approach: Custom + Sentry (Hybrid)**
  - **Recommended approach**: Custom database persistence + optional Sentry integration
  - Rationale:
    - Custom DB storage ensures errors are queryable and never leave the instance
    - Sentry integration (via `sentry` hex package) is optional for users who want it
    - Admin-only access is easier to implement with custom solution
    - No external dependency for core functionality
  - Create feature flag `ENABLE_EXTERNAL_SENTRY` for optional forwarding
  - Alternative considered: Rollbax (Rollbar), AppSignal, Honeybadger
    - All require external services, not ideal for self-hosted forge

- [ ] **Design Error Schema and Database Storage**
  - Create `errors` table with fields:
    - `id` (UUID primary key)
    - `fingerprint` (string, hash of error for deduplication)
    - `kind` (enum: exception | oban_job | liveview_crash | plug_error | agent_crash)
    - `message` (text, error message)
    - `stacktrace` (text, full stacktrace as string)
    - `metadata` (jsonb, request params, user_id, agent_id, job args, etc.)
    - `context` (jsonb, Phoenix assigns, LiveView socket info, etc.)
    - `severity` (enum: debug | info | warning | error | critical)
    - `occurred_at` (datetime with timezone)
    - `user_id` (foreign key, nullable - who triggered the error)
    - `project_id` (foreign key, nullable - which project context)
    - `resolved_at` (datetime, null until marked resolved)
    - `resolved_by_id` (foreign key to admins)
    - `occurrence_count` (integer, incremented on duplicate fingerprint)
    - `first_seen_at`, `last_seen_at` (datetimes for tracking)
  - Add indexes on: `fingerprint`, `kind`, `severity`, `occurred_at`, `resolved_at`
  - Implement retention policy: auto-delete errors older than N days (configurable)
  - Create `Micelio.Errors.Error` Ecto schema

- [ ] **Implement Error Capture Pipeline**
  - Create `Micelio.Errors.Capture` module with:
    - `capture_exception/2` - capture any exception with context
    - `capture_message/3` - capture string message with severity
  - Integrate capture points:
    - `Plug.ErrorHandler` - capture all unhandled Plug/Phoenix errors
    - Custom `Logger` backend to capture error-level logs
    - `Oban.Telemetry` handler for job failures and crashes
    - `Phoenix.LiveView` error boundary for LiveView crashes
  - Implement fingerprinting algorithm:
    - Hash of: exception module + message pattern + first N stack frames
    - Normalize dynamic values in messages (IDs, timestamps)
  - Add deduplication: increment `occurrence_count` for same fingerprint within window
  - Implement async capture via `Task.Supervisor` to avoid blocking requests
  - Add telemetry events for error capture metrics

- [ ] **Add LiveView Error Boundaries**
  - Implement `Micelio.ErrorBoundary` component wrapper
  - Catch `{:EXIT, ...}` and render fallback UI instead of crashing
  - Capture error to database with LiveView context:
    - Socket assigns (sanitized - no sensitive data)
    - Current route and params
    - User ID if authenticated
  - Show user-friendly error message with "Report" button (optional)
  - Allow retry/refresh from error state
  - Create error boundary for agent progress LiveView specifically
  - Document pattern for wrapping components in error boundaries

- [ ] **Capture Agent and Background Job Errors**
  - Hook into Oban telemetry events:
    - `:oban, :job, :exception` - job crashed
    - `:oban, :job, :discard` - job discarded after max attempts
  - Capture job context: worker module, args, attempt count, queue
  - For agent errors specifically:
    - Capture agent ID and project context
    - Store last N agent actions before crash
    - Link error to agent session for debugging
  - Create `Micelio.Errors.ObanReporter` telemetry handler
  - Implement `Micelio.Errors.AgentReporter` for agent-specific crashes
  - Add correlation ID to trace errors across job retries

- [ ] **Build Admin Error Dashboard**
  - Create admin-only LiveView at `/admin/errors`
  - Dashboard views:
    - **Overview**: error count by severity (last 24h, 7d, 30d), trend charts
    - **List view**: paginated error list with filtering and sorting
    - **Detail view**: full error info, stacktrace, metadata, occurrences timeline
  - Filtering options:
    - By kind (exception, oban, liveview, agent)
    - By severity (error, critical)
    - By date range
    - By resolved/unresolved status
    - By project or user
    - Full-text search on message
  - Actions:
    - Mark as resolved (with optional note)
    - Bulk resolve similar errors
    - Delete error (with confirmation)
    - Copy stacktrace to clipboard
  - Display occurrence count and first/last seen times
  - Show affected users count per error
  - Require admin role (`is_admin: true`) for all error routes

- [ ] **Implement Error Notifications**
  - Create `Micelio.Errors.Notifier` module
  - Notification triggers:
    - First occurrence of new error fingerprint (severity >= error)
    - Error occurrence rate exceeds threshold (e.g., >10 in 5 minutes)
    - Critical severity errors (always notify immediately)
  - Notification channels:
    - Email to admin users (use existing email infrastructure)
    - Webhook to configured URL (for Slack/Discord integration)
    - Optional: Slack incoming webhook with formatted message
  - Notification content:
    - Error message and kind
    - First occurrence time
    - Occurrence count
    - Link to error detail in admin dashboard
  - Implement notification rate limiting:
    - Max 1 notification per error fingerprint per hour
    - Max 10 notifications total per hour (prevent notification storms)
  - Create admin settings page for notification preferences
  - Support quiet hours configuration (no notifications during certain times)

- [ ] **Add Rate Limiting and Retention Policies**
  - Implement error capture rate limiting:
    - Max 100 errors per minute per error kind
    - Max 1000 total errors per minute instance-wide
    - When limit hit, log warning and drop excess errors
  - Create Oban job for error retention cleanup:
    - Run daily at low-traffic time
    - Delete resolved errors older than 30 days (configurable)
    - Delete unresolved errors older than 90 days (configurable)
    - Archive to S3 before deletion (optional, for compliance)
  - Implement error sampling for high-volume errors:
    - After N occurrences of same fingerprint, sample at 10%
    - Always capture first occurrence in full
  - Add database vacuum/analyze after bulk deletions
  - Monitor errors table size and alert if growing too large
  - Create admin setting for retention policy configuration

### Live Session UIs from Agents

Enable real-time visualization of agent sessions directly in the browser, providing transparency into what agents are doing during sessions.

#### Two Approaches Evaluated

**Approach 1: Structured Data Approach**
Agents write structured data (JSON events) to a file or database. The UI polls or subscribes to this data and renders it.

Pros:
- Clean separation of concerns
- Easy to debug (JSON is human-readable)
- Can add types, schemas for validation
- Works well for dashboards and state visualization
- Easier to test and mock

Cons:
- Requires agents to explicitly write structured data
- Additional latency from write/read cycle
- Agents need to be modified to output structured data

**Approach 2: Stdout/Stderr Hook + Ghostty Rendering**
Hook into agent's stdout/stderr streams and render them in real-time using terminal emulation (potentially Ghostty).

Ghostty is a modern terminal emulator that supports:
- Inline images
- hyperlinks
- Sixel graphics
- True color
- Fast rendering

Pros:
- Agents work unmodified (capture existing stdout/stderr)
- Rich visual output (images, colors, formatting)
- Real-time streaming without polling
- Terminal-like experience in browser

Cons:
- Terminal output can be messy to parse
- Less structured, harder to extract meaning
- Requires terminal emulation in browser
- May need to handle escape sequences carefully

#### Recommendation

**Start with Approach 1 (Structured Data) for Micelio.**

Rationale:
1. **Agent integration** - Micelio already has session context where agents can output structured events
2. **Clean architecture** - Fits well with Micelio's session-based workflow
3. **Extensible** - Can later add terminal-like rendering as a layer on top
4. **Testable** - Easier to build and test structured output

**Future Enhancement (Approach 2):**
Once structured data rendering is working, explore:
- Ghostty WebAssembly for browser rendering
- Hybrid approach: Structured data + terminal fallback for unformatted output
- Agent SDK that auto-captures stdout as structured events

#### Implementation Roadmap

- [ ] **Design Session Event Schema**
  - Define event types: `status`, `progress`, `output`, `error`, `artifact`
  - Include timestamps, source info, structured payload
  - Create JSON schema for validation

- [ ] **Build Event Capture Layer**
  - Agent SDK integration for event output
  - Capture stdout/stderr as structured events (auto-convert for unformatted output)
  - Write events to session artifact storage

- [ ] **Create Event Streaming API**
  - Server-Sent Events (SSE) or WebSocket for real-time updates
  - Filter events by type and session
  - Handle reconnection and missed events

- [ ] **Build Event Viewer UI**
  - Real-time event display component
  - Filter by event type
  - Visual indicators for different event types
  - Expandable details for structured payloads

- [ ] **Add Rich Rendering**
  - Support inline images from artifact events
  - Progress bars for long-running operations
  - Collapsible output sections

### Sapling SCM Investigation

Sapling is a distributed version control system developed by Meta, designed for large-scale development with Git interoperability. Research its potential for Micelio's agent-first workflow.

#### Key Features

**Stacking Workflow**
- Sapling excels at "stacked PRs" — managing many small, dependent commits
- `sl stack` command shows all related commits in a series
- Ideal for agent workflows where each task produces incremental commits
- Avoids "detached HEAD" and complex branch management

**User-Friendly UI**
- `sl status` shows clearer, more intuitive output than `git status`
- `sl goto` for easy navigation between commits
- Built-in interactive rebase and amend
- Better conflict resolution UX

**Git Compatibility**
- Works with existing Git repositories
- Can clone from and push to GitHub/GitLab
- Smooth interoperability: `sl git` aliases for common Git commands
- No repository migration required

**Scalability**
- Optimized for monorepos (Meta-scale)
- Faster than Git for large histories
- Intelligent caching and data structures

#### Relevance to Micelio

**For Agent Workflows:**
- Stacked commits match agent task structure (one task = one commit in stack)
- Clear visualization of task progress
- Easier to iterate on agent-generated changes

**For mic Integration:**
- Sapling could replace or enhance `mic` for version control
- Better UX for reviewing agent sessions
- Potential for richer session metadata

#### Research Questions

1. **Can Sapling replace or integrate with mic?**
   - What would migration look like?
   - What features would be gained/lost?

2. **How does Sapling handle AI-generated code?**
   - Does it have features for automated commits?
   - What about commit signing for agents?

3. **Performance comparison:**
   - Benchmarks against Git for typical mic workflows
   - Storage overhead and speed

4. **Integration with existing Git hosting:**
   - GitHub/GitLab PR creation from Sapling
   - CI/CD pipeline compatibility

#### Next Steps

- [ ] Install and benchmark Sapling vs Git for mic workflows
- [ ] Test stacking workflow with simulated agent sessions
- [ ] Evaluate Git interoperability for gradual migration
- [ ] Design integration layer between mic and Sapling
- [ ] Create proof-of-concept for agent commit workflow

### Ephemeral Environments for Coding and CI

Enable ephemeral virtual machines for running coding sessions, agent workloads, and CI tasks securely and efficiently.

#### Background

Inspired by Servo's CI system (https://www.azabani.com/2025/12/18/shoestring-web-engine-ci.html), which uses ephemeral VMs for secure untrusted code execution at 300 EUR/month vs 2000+ EUR on GitHub-hosted runners.

#### Technology Stack

**VM/MicroVM Runtime**
- **Firecracker** (AWS) - Lightweight microVMs, 125ms startup, minimal overhead
  - Used by AWS Lambda, Fargate, and Fly.io
  - Strong security isolation via KVM
  - Open source: https://github.com/firecracker-microvm/firecracker

- **cloud-hypervisor** - Rust-based alternative, similar to Firecracker
  - Modern architecture, actively developed
  - Good alternative if Firecracker has licensing concerns

**Orchestration**
- **Nomad** - Simple, effective workload orchestration
  - Native support for ephemeral tasks
  - Good fit for bare-metal servers
  - Integrates well with Consul for service discovery

- **K0s/k3s** - Kubernetes light variants
  - More complex but richer ecosystem
  - Option if we need advanced k8s features

- **Fly.io Machines API** - Managed alternative
  - Firecracker-based ephemeral VMs
  - API-first design
  - Global distribution built-in

**Image Building**
- **Packer** - Automated VM image building
  - Supports multiple providers (AWS, GCP, local)
  - Reproducible builds
  - Version-controlled image definitions

- **DispVM/Ahv** (Adamantquake/Antagonist)
  - Disposable VM architecture
  - Based on Xen's disaggregation model
  - Useful reference for security design

#### Architecture Design

```
┌─────────────────────────────────────────────────────────────┐
│                    Micelio Control Layer                     │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Session     │  │ VM Pool     │  │ Image Registry      │  │
│  │ Manager     │  │ Orchestrator│  │ (OCI-compliant)     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │        Nomad Cluster (Bare Metal Servers)           │    │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐  │    │
│  │  │Firecracker│ │Firecracker│ │Firecracker│ │Firecracker│ │    │
│  │  │  VM #1   │ │  VM #2   │ │  VM #3   │ │  VM #4   │  │    │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

**Key Components**

1. **Session Manager**
   - Creates/destroys VMs on demand
   - Tracks VM lifecycle and resource usage
   - Handles timeout and cleanup
   - Provides connection to running VM (SSH/Web terminal)

2. **VM Pool Orchestrator**
   - Maintains warm pool of pre-started VMs
   - Hot-allocate VMs from pool (sub-second)
   - Rebuilds images weekly (not per-run)
   - Handles image updates without downtime

3. **Image Registry**
   - OCI-compliant registry for VM images
   - Signed images for security
   - Incremental layer updates where possible

4. **Fallback Mechanism**
   - If self-hosted VMs unavailable, fall back to cloud providers
   - Fly.io Machines as managed alternative
   - AWS/GCP as final fallback

#### Security Model

**Isolation Strategy**
- Each session runs in dedicated microVM
- No shared compute between sessions
- Strict network policies (deny by default)
- Ephemeral disk (destroyed on VM termination)

**Trust Levels**
- Trusted sessions (own code) → shared warm pool
- Untrusted sessions (agent/code review) → fresh VMs
- Compromised code → firecracker Jailer for extra isolation

**Resource Limits**
- CPU caps per VM (prevent noisy neighbors)
- Memory limits with OOM killer
- Network bandwidth throttling
- Timeouts for all operations

#### Cost Analysis

**Self-Hosted (Bare Metal)**
- Example: 4x Dell R750 or similar
- ~300-500 EUR/month for hardware
- Power, cooling, network extra
- Servo achieves 300 EUR/month for extensive CI

**Cloud (Fly.io Machines)**
- Pay-per-second billing
- ~$0.01-0.05 per second depending on config
- Good for burst/overflow
- More expensive at scale

**Hybrid Approach**
- Self-hosted for steady-state workloads
- Cloud for burst capacity
- Cost-optimized based on usage patterns

#### Use Cases

1. **Agent Coding Sessions**
   - Agent gets dedicated VM for task
   - Full isolation from host system
   - Clean environment each time
   - Can persist work via volumes

2. **Code Review Environments**
   - Review PR in isolated VM
   - Run tests safely
   - No risk to host environment

3. **CI/CD Pipeline**
   - Fast VM allocation per job
   - Parallel job execution
   - No shared state between jobs

4. **Temporary Development Environments**
   - On-demand dev environments
   - Pre-configured images per project
   - Ephemeral - destroyed when done

#### Research Questions

1. **VM Technology Selection**
   - Firecracker vs cloud-hypervisor vs Kata Containers
   - Licensing implications (Firecracker uses Apache 2.0)
   - Performance benchmarks needed

2. **Orchestration Complexity**
   - Nomad sufficient or need full Kubernetes?
   - Multi-host coordination for scaling
   - State management for orchestrator

3. **Image Build Strategy**
   - How to minimize image rebuild time?
   - Caching strategy for dependencies
   - Incremental vs full rebuilds

4. **Network Architecture**
   - How to route traffic to ephemeral VMs?
   - Load balancing for parallel jobs
   - VPN/tunnel requirements

5. **Integration with mic**
   - How does mic interact with VM system?
   - API design for session management
   - Progress streaming from VM

#### Next Steps

- [ ] Research Firecracker benchmarking vs containers
- [ ] Prototype Nomad + Firecracker setup on test hardware
- [ ] Build proof-of-concept image builder with Packer
- [ ] Design Session Manager API
- [ ] Implement fallback to Fly.io Machines
- [ ] Benchmark cost/performance vs GitHub Actions
- [ ] Create integration design for mic

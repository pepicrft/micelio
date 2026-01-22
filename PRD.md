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
- [x] **Investigate and implement repository import from other git forges**
  - Support importing repositories from GitHub, GitLab, Gitea, and other Git forges
  - Clone repository with full history (git clone --mirror or --bare)
  - Preserve git history, branches, tags, and commits
  - Migrate issues, pull requests, and comments if available via API
  - Preserve commit authorship and attribution
  - Handle large repositories efficiently (streaming, incremental imports)
  - Validate repository integrity after import
  - Create import progress UI showing stages:
    - Repository metadata fetch
    - Git data clone
    - Issue/PR migration
    - Finalization and validation
  - Support importing to existing projects or as new projects
  - Provide rollback option if import fails mid-way
  - Store import metadata (source forge, original URL, import date)

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

### Security & Compliance

- [x] Implement audit logging for all project operations
- [x] Add two-factor authentication (TOTP) support
- [x] Create project access tokens with scoped permissions
- [x] Implement branch protection rules for preventing direct lands to main
- [x] Add secret scanning to prevent credential leaks in landed sessions

### Legal & Terms

- [x] Design simplified legal pages with user responsibility disclaimers
  - Create minimal Terms of Service with broad disclaimers instead of detailed legal pages
  - Make users solely responsible for the content they host
  - Example: "By using this service, you agree that you are solely responsible for the content you host"
  - Remove need for separate detailed privacy/cookie/terms/impressum pages
  - Single page covering all necessary disclaimers in plain language

### Platform Limits & Rate Limiting

- [x] Implement rate limiting for unauthenticated and authenticated users
- [x] Set initial project limits per tenant (prevent spam during early growth)
- [x] Add abuse detection and mitigation systems

### Mobile Clients

- [x] Create iOS native client using Swift (SwiftUI)
- [x] Create Android native client using Jetpack Compose
- [x] Implement authentication flow for both mobile clients
- [x] Add basic project browsing and viewing capabilities
- [x] Design API endpoints optimized for mobile (pagination, offline support)

### Agentic Infrastructure

- [x] Design infrastructure for provisioning VMs and mounting volumes (use `compute/` directory)
- [x] Evaluate cloud platforms for VM provisioning (AWS, GCP, Hetzner, etc.)
- [x] Design abstraction protocol for cloud-agnostic VM management
- [x] Implement remote execution service for running CLI tools (Claude, Codex, etc.)
- [x] Add support for tenant-configurable LLM models per project
- [x] Design secure sandboxed environment for agent execution
- [x] Implement resource quota and billing for agentic workflows

### Open Graph & SEO

- [x] Generate OG images for agents using LLM summaries of code changes
- [x] Design template for agent progress OG images showing commits, files changed
- [x] Implement cache invalidation strategy for social platform crawlers
- [x] Add dynamic OG image generation for commits, PRs, and agent sessions

### Agent Quality & Contribution Model

This section addresses critical challenges with AI-generated contributions identified by Armin Ronacher ("Agent Psychosis") and tldraw ("Stay away from my trash!"). The core problems: AI contributions are cheap to generate but expensive to review, quality degrades over time, and "slop" (well-formed but low-quality code) is indistinguishable from good work without deep review.

- [x] **Implement Prompt Request System (replaces traditional Issues/PRs)**
  - Require contributors to submit the prompt + generated result as a unit, not just a diff
  - Store the full agent context (model, system prompt, conversation history) alongside contributions
  - Enable reviewers to replay and understand why code was generated, not just what changed
  - Create UI for browsing prompt-result pairs with side-by-side diff visualization
  - Support "prompt improvement suggestions" as a review feedback mechanism

- [x] **Build Ephemeral Validation Environments**
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

## AI Tokens System for Open Source Contributions

### Core Concept

Enable contributors to fund AI agent compute for projects. Instead of paying maintainers directly, contributors contribute AI tokens (credits) that power coding agents working on the project.

**Example:** Alice loves a project but doesn't code. She contributes 1000 AI tokens. Bob uses those tokens to run Codex/Claude agents that fix issues and land PRs. The project gets AI-powered work, Alice feels involved, Bob gets free compute.

### How It Works

**Token Pools**
- Projects have AI token pools
- Contributors deposit tokens into pools they care about
- Maintainers allocate tokens to tasks, bounties, or agent runs

**Token Sources**
- Purchased directly (micelio.com/pricing)
- Earned through contributions (landed PRs, reviews, community work)
- Grants from foundations/platform (Quadratic Funding)

**Usage**
- Maintainers create "AI tasks" with token budgets
- Agents run against tasks, consume tokens per-run
- Usage logged for transparency

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  AI Tokens System                        │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Token Pool   │  │ Task Budget  │  │ Usage Meter  │  │
│  │ (per project)│  │ (per task)   │  │ (per run)    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────┐   │
│  │              Agent Runner Integration             │   │
│  │  Codex, Claude, OpenCode, GLM → consume tokens   │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**Components**

1. **Token Pool** — Per-project balance of AI credits
2. **Task Budget** — Allocation from pool to specific task/PR
3. **Usage Meter** — Tracks token consumption per agent run
4. **Runner Integration** — Agents check budget before running

### Use Cases

1. **Bounties funded by community**
   - Alice contributes 500 tokens to "fix auth bug"
   - Bob claims bounty, runs agent, fixes bug
   - Tokens consumed, work completed

2. **Maintainer empowerment**
   - Maintainer gets burnt out
   - Community funds their AI agent budget
   - Agent handles routine fixes, maintainer focuses on reviews

3. **Experimentation fund**
   - Project has experimental feature idea
   - Community pools tokens for "AI exploration"
   - Agent prototypes, maintainer reviews

4. **Learning/new contributor onboarding**
   - New contributor lacks skills
   - Uses pooled tokens to run agents
   - Learns by agent-assisted contribution

### Token Economics

**Pricing Model**
- 1 token = 1 token (simplified)
- Purchase in bundles (100, 1000, 10000 tokens)
- Subscription option for ongoing support

**Earn by Contributing**
- Landed PR: earn tokens proportional to impact
- Quality review: tokens for thorough reviews
- Bug reports: tokens for verified bugs
- Community help: tokens for answered questions

**Anti-Gaming**
- Require minimum account age to contribute
- Rate limit contributions per project
- Veto power for maintainers (reject gaming)

### Integration with Compute Resources

- **Direct billing** — Micelio pays providers from token pools
- **Runner selection** — Maintainers choose agents (Codex, Claude, etc.)
- **Budget enforcement** — Stop runs when tokens exhausted
- **Usage attribution** — Track ROI: tokens spent vs value delivered

### Model Provider Protocol

Goal: unify integration across OpenAI Codex, Claude, OpenCode, GLM, and future providers while enforcing budgets and enabling seamless fallback.

**1) Provider Interface (capabilities, pricing, auth)**
- **Capabilities**: models, context length, modalities (text/code/vision), tool/function calling, streaming, structured output, rate limits
- **Pricing**: input/output token price per 1M tokens, min billable units, currency, effective date
- **Authentication**: api_key, oauth client, custom header, or signed request

Interface (conceptual):
- `id`, `name`, `base_url`, `auth_config`, `capabilities`, `models[]`, `pricing[]`
- `supports(model, feature)` and `estimate_tokens(request)` for preflight budgets
- `invoke(request)` returning `response`, `usage`, `provider_metadata`

**2) Request/Response Flow with Token Metering**
1. Preflight: validate model, check provider availability, estimate tokens
2. Budget reserve: lock tokens against task budget (include buffer)
3. Invoke provider: send request with trace id + budget id
4. Meter usage: record actual input/output tokens and cost per provider/model
5. Reconcile: release unused tokens, enforce hard-stop on overage
6. Persist: usage event stored with provider/model, request id, latency, error code

**3) Fallback + Load Balancing Strategy**
- Ordered fallback chain per task (primary -> secondary -> tertiary)
- Weighted routing by cost, latency, health score, and remaining budget
- Circuit breaker: auto-disable provider/model when error rate/latency exceeds threshold
- Degrade to cheaper/smaller model when budget low or rate limited

**4) Provider Configuration**
- Provider-level: `name`, `base_url`, `auth_type`, `auth_secret_ref`, `enabled`
- Model-level: `model_name`, `context_limit`, `capabilities`, `pricing`, `max_concurrency`
- Policy-level: `priority`, `fallback_group`, `cost_ceiling`, `rate_limit`, `timeout_ms`

**5) Health/Availability Monitoring**
- Scheduled health checks (ping or lightweight completion)
- Track error rate, p95 latency, and uptime per provider/model
- Status: `healthy`, `degraded`, `down`, `disabled`
- Auto-recovery after cooldown + successful health checks

**6) Admin UI for Provider Management**
- Providers list with status badge, health metrics, and cost per 1M tokens
- Add/edit provider + models, pricing, auth configuration, and fallback order
- Test connection + simulate request to validate auth and metering
- Audit log of config changes (who/when/what)

### Legal/Tax

- Simple: tokens = service credits, not currency
- No securities implications
- No KYC needed for token purchase
- Easy tax reporting (expense, not income)

### Next Steps

- [ ] Design token pool schema and API
- [ ] Build contribution flow (deposit tokens to project)
- [ ] Create task budget allocation UI
- [ ] Integrate with agent runners (check budget before run)
- [ ] Build usage dashboard (tokens spent, value delivered)
- [ ] Design earn-by-contributing mechanics

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
  - Store encryption key in environment variable (ENCRYPTION_KEY)
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
- Sapling excels at "stacked PRs" - managing many small, dependent commits
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

### Webhooks System (GitHub-Inspired)

Extend the existing webhook support with a comprehensive, GitHub-inspired webhooks system for project events.

#### Goals
- Provide reliable, secure webhook delivery for project events
- Enable third-party integrations (CI/CD, Slack, Discord, custom services)
- Give users visibility into webhook delivery status and debugging tools

#### Events to Support
- **Session events**: session.started, session.landed, session.aborted
- **Project events**: project.created, project.updated, project.deleted, project.starred
- **Branch events**: branch.created, branch.deleted, branch.protected
- **Collaboration events**: fork.created, member.added, member.removed
- **Comment events**: comment.created (for future code review support)

#### Webhook Payload Structure
```json
{
  "id": "uuid",
  "event": "session.landed",
  "timestamp": "ISO8601",
  "project": {
    "id": "uuid",
    "handle": "my-project",
    "name": "My Project",
    "visibility": "public"
  },
  "organization": {
    "id": "uuid",
    "handle": "my-org"
  },
  "sender": {
    "id": "uuid",
    "handle": "username"
  },
  "payload": {
    // Event-specific data
  }
}
```

#### Security
- **Secret-based HMAC signatures**: Sign payloads with X-Micelio-Signature-256 header
- **IP allowlisting**: Optional webhook source IP filtering
- **TLS verification**: Require HTTPS endpoints (configurable for dev)
- **Rate limiting**: Limit webhook delivery rate per project

#### Delivery & Reliability
- **Retry policy**: Retry failed deliveries with exponential backoff (1m, 5m, 30m, 2h, 24h)
- **Delivery logs**: Store last 30 days of delivery attempts with response codes
- **Recent deliveries UI**: Show delivery status, response time, and response body
- **Manual redeliver**: Allow users to redeliver any past webhook event
- **Timeout handling**: 30-second timeout for webhook responses

#### Management UI (per-project settings)
- List all configured webhooks with active/inactive status
- Create/edit webhook: URL, secret, event selection
- View delivery history per webhook with filtering
- Test webhook: Send a ping event to verify connectivity
- Disable/enable webhooks without deleting configuration

#### Tasks
- [ ] Extend webhook schema with delivery tracking fields
- [ ] Implement HMAC signature generation for payloads
- [ ] Create Oban job for reliable webhook delivery with retries
- [ ] Add delivery logging (webhook_deliveries table)
- [ ] Build webhook management UI with delivery history
- [ ] Add ping/test endpoint functionality
- [ ] Implement manual redeliver action
- [ ] Add webhook delivery metrics to project insights
- [ ] Create documentation for webhook payloads and integration

### CLI-to-Server Push Architecture

This section defines everything needed for the `mic` (or `hif`) CLI to push sessions to the Micelio server, enabling full self-hosting and migration from GitHub to micelio.dev.

#### Overview

The CLI-to-Server architecture enables:
1. **Session-based development** - Capture goal, reasoning, and changes together
2. **Atomic landing** - Push changes with coordinator-free CAS semantics
3. **Conflict detection** - Identify and resolve conflicts before landing
4. **Full project lifecycle** - Create, clone, push, and manage projects entirely via CLI

#### Current State Analysis

**What Already Exists:**

| Component | Status | Location |
|-----------|--------|----------|
| CLI session commands | Implemented | `hif/src/session.zig` (765 lines) |
| gRPC session endpoints | Implemented | `lib/micelio/grpc/sessions_server.ex` (479 lines) |
| Session database schema | Implemented | `lib/micelio/sessions/` |
| OAuth authentication | Implemented | `hif/src/auth.zig` (368 lines) |
| Local session state | Implemented | `.hif/session.json` + `.hif/overlay/` |
| Landing with CAS | Implemented | `lib/micelio/mic/landing.ex` |
| Conflict detection | Implemented | `lib/micelio/mic/conflict_index.ex` |
| Blob/tree storage | Implemented | `lib/micelio/storage/` + `lib/micelio/mic/` |

**What Needs To Be Built:**

| Component | Priority | Status |
|-----------|----------|--------|
| Git protocol support (clone/push) | P0 | Not started |
| Project creation via CLI | P0 | Not started |
| Organization management via CLI | P0 | Not started |
| Session sync command | P1 | Not started |
| Interactive conflict resolution | P1 | Stubbed |
| Session resume | P2 | Not started |
| Delta compression for push | P2 | Server-side exists |

---

### Git Protocol Support

Enable standard Git clients to clone from and push to Micelio projects. This is critical for compatibility with existing workflows and tools.

#### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Git Protocol Layer                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ HTTP Smart      │  │ SSH Protocol    │  │ Git Bundle      │  │
│  │ Protocol        │  │ (future)        │  │ Export/Import   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Git Object Translation Layer                │    │
│  │  Mic Tree/Blob ←→ Git Commit/Tree/Blob                  │    │
│  └─────────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Mic Storage Layer                           │    │
│  │  projects/{id}/head, trees/, blobs/                     │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

#### Git HTTP Smart Protocol

Implement the Git HTTP Smart Protocol for `git clone` and `git push` operations.

**Endpoints Required:**

```
GET  /:org/:project/info/refs?service=git-upload-pack   # Discovery for fetch
GET  /:org/:project/info/refs?service=git-receive-pack  # Discovery for push
POST /:org/:project/git-upload-pack                      # Fetch objects
POST /:org/:project/git-receive-pack                     # Push objects
```

**Reference Discovery Response Format:**

```
001e# service=git-upload-pack
0000
00a0<sha1> HEAD\0multi_ack thin-pack side-band side-band-64k ofs-delta shallow
003f<sha1> refs/heads/main
0000
```

**Implementation Tasks:**

- [ ] **Create Git Protocol Plug** (`lib/micelio_web/plugs/git_protocol_plug.ex`)
  - Parse Git protocol requests
  - Handle capability negotiation
  - Route to appropriate handler

- [ ] **Implement git-upload-pack handler** (`lib/micelio/git/upload_pack.ex`)
  - Advertise refs (translate Mic HEAD to Git refs)
  - Generate packfile from Mic blobs/trees
  - Support thin-pack, side-band-64k capabilities
  - Handle want/have negotiation for efficient fetches

- [ ] **Implement git-receive-pack handler** (`lib/micelio/git/receive_pack.ex`)
  - Parse incoming packfile
  - Extract Git objects (commits, trees, blobs)
  - Translate to Mic format (tree entries, blob storage)
  - Create session for the push
  - Land the session atomically
  - Return status per ref update

- [ ] **Implement Git Object Translation** (`lib/micelio/git/translator.ex`)
  - **Git Commit → Mic Session**: Extract tree, message, author, timestamp
  - **Git Tree → Mic Tree**: Convert tree entries to Mic binary format
  - **Git Blob → Mic Blob**: Store with SHA256 (not Git SHA1)
  - **Mic Tree → Git Tree**: Generate Git tree objects on demand
  - **Mic Blob → Git Blob**: Serve blobs with Git object headers

- [ ] **Implement Packfile Generator** (`lib/micelio/git/packfile.ex`)
  - Generate Git packfiles from Mic objects
  - Support delta compression (reuse Mic delta compression)
  - Handle thin-pack for efficient network transfer
  - Implement object counting and progress reporting

- [ ] **Implement Packfile Parser** (`lib/micelio/git/packfile_parser.ex`)
  - Parse incoming Git packfiles
  - Handle delta objects (OFS_DELTA, REF_DELTA)
  - Validate object checksums
  - Extract objects for storage

- [ ] **Add Git Routes** (`lib/micelio_web/router.ex`)
  ```elixir
  scope "/:org/:project", MicelioWeb do
    get "/info/refs", GitController, :info_refs
    post "/git-upload-pack", GitController, :upload_pack
    post "/git-receive-pack", GitController, :receive_pack
  end
  ```

#### Git Reference Management

Map Micelio concepts to Git refs:

| Micelio Concept | Git Ref |
|-----------------|---------|
| HEAD (current tree) | `refs/heads/main` |
| Landing at position N | `refs/landings/<position>` |
| Session (active) | `refs/sessions/<session_id>` |
| Branch (future) | `refs/heads/<branch_name>` |

**Tasks:**

- [ ] **Create Ref Storage** (`lib/micelio/git/refs.ex`)
  - Store refs in database or object storage
  - Support atomic ref updates with CAS
  - Handle symbolic refs (HEAD → refs/heads/main)

- [ ] **Implement Ref Resolution** (`lib/micelio/git/ref_resolver.ex`)
  - Resolve ref names to tree hashes
  - Support refspecs for fetch/push
  - Handle abbreviated refs

#### Authentication for Git Operations

- [ ] **HTTP Basic Auth over HTTPS**
  - Username: Micelio handle or `x-token`
  - Password: Personal access token or OAuth token
  - Validate against `project_access_tokens` or user tokens

- [ ] **Git Credential Helper Integration**
  - Document setup for `git config credential.helper`
  - Support `mic auth` to configure git credentials automatically

---

### Project Management via CLI

Enable full project lifecycle management from the CLI.

#### Project Creation

**Command:** `mic project create <org>/<handle>`

```bash
# Create a new project
mic project create myorg/myproject --name "My Project" --visibility public

# Create with description
mic project create myorg/myproject --description "A cool project"

# Create and initialize with current directory contents
mic project create myorg/myproject --init

# Create as fork of existing project
mic project create myorg/myproject --fork otherorg/otherproject
```

**Implementation Tasks:**

- [ ] **Add gRPC CreateProject endpoint** (`sessions_server.ex`)
  ```protobuf
  rpc CreateProject(CreateProjectRequest) returns (ProjectResponse);

  message CreateProjectRequest {
    string organization_handle = 1;
    string project_handle = 2;
    string name = 3;
    string description = 4;
    string visibility = 5;  // "public" or "private"
    bool initialize = 6;    // Create with empty tree
    string fork_from = 7;   // Optional: "org/project" to fork
  }
  ```

- [ ] **Implement CLI project create command** (`hif/src/project.zig`)
  - Parse arguments
  - Authenticate with server
  - Call CreateProject gRPC endpoint
  - Initialize local `.hif/` directory
  - Set remote origin

- [ ] **Add project initialization logic** (`lib/micelio/projects.ex`)
  - Create empty HEAD with empty tree
  - Set up default branch protection if requested
  - Create initial landing at position 0

#### Project Cloning

**Command:** `mic clone <url> [directory]`

```bash
# Clone via mic protocol
mic clone https://micelio.dev/org/project
mic clone micelio.dev:org/project

# Clone to specific directory
mic clone https://micelio.dev/org/project ./myproject

# Clone specific ref
mic clone https://micelio.dev/org/project --ref refs/heads/feature
```

**Implementation Tasks:**

- [ ] **Implement clone command** (`hif/src/clone.zig`)
  - Parse URL and extract org/project
  - Authenticate if private project
  - Fetch HEAD and tree structure
  - Download blobs (with progress indicator)
  - Initialize local `.hif/` directory
  - Write files to working directory

- [ ] **Add streaming blob download** (`hif/src/grpc/blobs_proto.zig`)
  - Implement efficient bulk blob fetching
  - Support resume on interrupted downloads
  - Use delta compression for similar blobs

- [ ] **Add gRPC CloneProject endpoint** (`lib/micelio/grpc/projects_server.ex`)
  ```protobuf
  rpc GetProjectTree(GetProjectTreeRequest) returns (TreeResponse);
  rpc StreamBlobs(StreamBlobsRequest) returns (stream BlobChunk);

  message GetProjectTreeRequest {
    string organization_handle = 1;
    string project_handle = 2;
    string ref = 3;  // Optional, defaults to HEAD
  }

  message StreamBlobsRequest {
    string project_id = 1;
    repeated string blob_hashes = 2;
  }
  ```

#### Project Configuration

**Local config file:** `.hif/config`

```toml
[remote "origin"]
url = "https://micelio.dev/org/project"
fetch = "+refs/heads/*:refs/remotes/origin/*"

[project]
id = "uuid-here"
organization = "myorg"
handle = "myproject"

[user]
name = "My Name"
email = "me@example.com"
```

**Tasks:**

- [ ] **Implement config management** (`hif/src/config.zig`)
  - Read/write TOML config
  - Support global config (`~/.config/hif/config`)
  - Support project-local config (`.hif/config`)
  - Merge configs with local taking precedence

---

### Organization Management via CLI

**Commands:**

```bash
# List organizations you belong to
mic org list

# Create new organization
mic org create myorg --name "My Organization"

# Invite member to organization
mic org invite myorg user@example.com --role member

# List organization members
mic org members myorg

# List organization projects
mic org projects myorg
```

**Implementation Tasks:**

- [ ] **Add gRPC Organization endpoints**
  ```protobuf
  rpc ListOrganizations(ListOrganizationsRequest) returns (ListOrganizationsResponse);
  rpc CreateOrganization(CreateOrganizationRequest) returns (OrganizationResponse);
  rpc InviteMember(InviteMemberRequest) returns (InviteResponse);
  rpc ListMembers(ListMembersRequest) returns (ListMembersResponse);
  rpc ListProjects(ListProjectsRequest) returns (ListProjectsResponse);
  ```

- [ ] **Implement CLI org commands** (`hif/src/org.zig`)

---

### Session Push & Sync

#### Session Push Command

**Command:** `mic session push`

Push current session state to server without landing (for backup/collaboration).

```bash
# Push session to server
mic session push

# Push with message
mic session push --message "WIP: implementing feature X"
```

**Implementation Tasks:**

- [ ] **Add gRPC PushSession endpoint**
  ```protobuf
  rpc PushSession(PushSessionRequest) returns (SessionResponse);

  message PushSessionRequest {
    string session_id = 1;
    repeated Conversation conversation = 2;
    repeated Decision decisions = 3;
    repeated FileChange files = 4;
    string message = 5;
    bool incremental = 6;  // Only push changed files
  }
  ```

- [ ] **Implement session push command** (`hif/src/session.zig`)
  - Collect changed files from overlay
  - Compute incremental diff from last push
  - Upload to server
  - Update local push marker

#### Session Sync Command

**Command:** `mic session sync`

Synchronize local session with server state (fetch upstream changes).

```bash
# Sync session with upstream
mic session sync

# Sync and auto-merge if possible
mic session sync --auto-merge

# Sync specific files
mic session sync --path src/lib.zig
```

**Implementation Tasks:**

- [ ] **Add gRPC SyncSession endpoint**
  ```protobuf
  rpc SyncSession(SyncSessionRequest) returns (SyncSessionResponse);

  message SyncSessionRequest {
    string session_id = 1;
    uint64 local_position = 2;  // Last known position
  }

  message SyncSessionResponse {
    uint64 upstream_position = 1;
    repeated FileChange upstream_changes = 2;
    repeated string conflict_paths = 3;
  }
  ```

- [ ] **Implement session sync command** (`hif/src/session.zig`)
  - Fetch upstream changes since local position
  - Detect conflicts
  - Apply non-conflicting changes
  - Mark conflicting files for resolution

#### Session Resume Command

**Command:** `mic session resume <session_id>`

Resume a previously pushed or abandoned session.

```bash
# List resumable sessions
mic session list --resumable

# Resume specific session
mic session resume abc123

# Resume most recent session
mic session resume --latest
```

**Implementation Tasks:**

- [ ] **Add gRPC ListSessions filter for resumable**
  - Filter by status = "active" and user_id
  - Include session metadata for display

- [ ] **Implement session resume command** (`hif/src/session.zig`)
  - Fetch session state from server
  - Download associated files
  - Reconstruct local session.json
  - Populate overlay directory

---

### Conflict Resolution

#### Interactive Conflict Resolution

**Command:** `mic session resolve`

```bash
# Start interactive resolution
mic session resolve

# Resolve specific file
mic session resolve src/lib.zig

# Use specific strategy
mic session resolve --strategy ours
mic session resolve --strategy theirs
mic session resolve --strategy union  # For additive changes
```

**Implementation Tasks:**

- [ ] **Implement conflict detection** (`hif/src/conflict.zig`)
  - Parse conflict markers in files
  - Track conflict state per file
  - Generate three-way diff (base, ours, theirs)

- [ ] **Implement resolution strategies** (`hif/src/resolve.zig`)
  - `ours`: Keep local changes
  - `theirs`: Accept upstream changes
  - `union`: Merge additive changes (for non-overlapping)
  - `interactive`: Show TUI for manual resolution

- [ ] **Build TUI resolver** (`hif/src/tui/resolver.zig`)
  - Side-by-side diff view
  - Keyboard navigation
  - Accept/reject hunks
  - Edit in external editor option

- [ ] **Add gRPC conflict endpoints**
  ```protobuf
  rpc GetConflicts(GetConflictsRequest) returns (ConflictsResponse);
  rpc ResolveConflict(ResolveConflictRequest) returns (ResolveConflictResponse);

  message ConflictsResponse {
    repeated ConflictInfo conflicts = 1;
  }

  message ConflictInfo {
    string path = 1;
    bytes base_content = 2;
    bytes ours_content = 3;
    bytes theirs_content = 4;
    uint64 base_position = 5;
    uint64 theirs_position = 6;
  }
  ```

---

### Authentication & Token Management

#### OAuth Device Flow

**Command:** `mic auth login`

```bash
# Start OAuth login flow
mic auth login

# Login to specific instance
mic auth login --instance micelio.dev

# Check auth status
mic auth status

# Logout
mic auth logout
```

**Current Implementation:**
- Device flow OAuth already implemented in `hif/src/auth.zig`
- Tokens stored in XDG config directory

**Enhancements Needed:**

- [ ] **Add token refresh logic**
  - Check token expiry before requests
  - Auto-refresh using refresh_token
  - Handle refresh failures gracefully

- [ ] **Add multi-instance support**
  - Store tokens per instance URL
  - Switch between instances

- [ ] **Implement API token creation**
  ```bash
  # Create personal access token
  mic auth token create --name "CI Token" --scope project:read,session:write

  # List tokens
  mic auth token list

  # Revoke token
  mic auth token revoke <token_id>
  ```

#### Server-Side Token Endpoints

- [ ] **Add gRPC token management endpoints**
  ```protobuf
  rpc CreateAccessToken(CreateAccessTokenRequest) returns (AccessTokenResponse);
  rpc ListAccessTokens(ListAccessTokensRequest) returns (ListAccessTokensResponse);
  rpc RevokeAccessToken(RevokeAccessTokenRequest) returns (RevokeAccessTokenResponse);
  ```

- [ ] **Implement scoped permissions**
  - `project:read` - Read project contents
  - `project:write` - Create/update projects
  - `session:read` - Read sessions
  - `session:write` - Create/land sessions
  - `org:read` - Read organization info
  - `org:admin` - Manage organization

---

### API Endpoints Summary

#### gRPC Services

**SessionService** (existing, needs extension):
```protobuf
service SessionService {
  // Existing
  rpc StartSession(StartSessionRequest) returns (SessionResponse);
  rpc LandSession(LandSessionRequest) returns (SessionResponse);
  rpc GetSession(GetSessionRequest) returns (SessionResponse);
  rpc ListSessions(ListSessionsRequest) returns (ListSessionsResponse);

  // New
  rpc PushSession(PushSessionRequest) returns (SessionResponse);
  rpc SyncSession(SyncSessionRequest) returns (SyncSessionResponse);
  rpc GetConflicts(GetConflictsRequest) returns (ConflictsResponse);
  rpc ResolveConflict(ResolveConflictRequest) returns (ResolveConflictResponse);
}
```

**ProjectService** (new):
```protobuf
service ProjectService {
  rpc CreateProject(CreateProjectRequest) returns (ProjectResponse);
  rpc GetProject(GetProjectRequest) returns (ProjectResponse);
  rpc UpdateProject(UpdateProjectRequest) returns (ProjectResponse);
  rpc DeleteProject(DeleteProjectRequest) returns (DeleteProjectResponse);
  rpc GetProjectTree(GetProjectTreeRequest) returns (TreeResponse);
  rpc StreamBlobs(StreamBlobsRequest) returns (stream BlobChunk);
  rpc ListProjects(ListProjectsRequest) returns (ListProjectsResponse);
}
```

**OrganizationService** (new):
```protobuf
service OrganizationService {
  rpc CreateOrganization(CreateOrganizationRequest) returns (OrganizationResponse);
  rpc GetOrganization(GetOrganizationRequest) returns (OrganizationResponse);
  rpc ListOrganizations(ListOrganizationsRequest) returns (ListOrganizationsResponse);
  rpc InviteMember(InviteMemberRequest) returns (InviteResponse);
  rpc RemoveMember(RemoveMemberRequest) returns (RemoveMemberResponse);
  rpc ListMembers(ListMembersRequest) returns (ListMembersResponse);
}
```

**AuthService** (new):
```protobuf
service AuthService {
  rpc CreateAccessToken(CreateAccessTokenRequest) returns (AccessTokenResponse);
  rpc ListAccessTokens(ListAccessTokensRequest) returns (ListAccessTokensResponse);
  rpc RevokeAccessToken(RevokeAccessTokenRequest) returns (RevokeAccessTokenResponse);
  rpc GetCurrentUser(GetCurrentUserRequest) returns (UserResponse);
}
```

---

### Migration Path: GitHub to micelio.dev

Step-by-step process to migrate `github.com/pepicrft/micelio` to `micelio.dev/micelio/micelio`:

#### Phase 1: Prerequisites

- [ ] Deploy Micelio to micelio.dev with production configuration
- [ ] Create `micelio` organization on micelio.dev
- [ ] Configure OAuth for micelio.dev instance
- [ ] Set up S3 storage backend
- [ ] Configure DNS and TLS certificates

#### Phase 2: Import Repository

- [ ] Use existing project import feature:
  ```
  POST /api/projects/import
  {
    "source_url": "https://github.com/pepicrft/micelio",
    "organization_handle": "micelio",
    "project_handle": "micelio"
  }
  ```
- [ ] Monitor import stages (metadata → git_data_clone → validation → finalization)
- [ ] Verify imported content matches GitHub repository

#### Phase 3: Set Up CLI

- [ ] Authenticate CLI with micelio.dev:
  ```bash
  mic auth login --instance micelio.dev
  ```
- [ ] Clone the project locally:
  ```bash
  mic clone micelio.dev/micelio/micelio
  ```
- [ ] Verify file contents match

#### Phase 4: Update Remotes

- [ ] Update local development setup:
  ```bash
  cd micelio
  git remote rename origin github
  git remote add origin https://micelio.dev/micelio/micelio
  ```
  Or for mic-only workflow:
  ```bash
  mic remote add origin micelio.dev/micelio/micelio
  mic remote remove github  # optional
  ```

#### Phase 5: Establish Workflow

- [ ] Start using session-based development:
  ```bash
  mic session start micelio micelio "Implement feature X"
  # ... make changes ...
  mic session note "Decided to use approach Y because..."
  mic session land
  ```

#### Phase 6: Redirect & Deprecate GitHub

- [ ] Add redirect notice to GitHub README
- [ ] Archive GitHub repository (read-only)
- [ ] Update all documentation links
- [ ] Update CI/CD to push to micelio.dev

---

### Implementation Priority Order

**P0 - Critical for Migration:**
1. Git Protocol Support (git clone at minimum)
2. Project Creation via CLI
3. Session Land (already exists, verify working)
4. Authentication flow (already exists, verify working)

**P1 - Important for Workflow:**
5. Session Push (backup without landing)
6. Session Sync (fetch upstream)
7. Organization Management via CLI
8. Conflict Resolution

**P2 - Nice to Have:**
9. Session Resume
10. Delta Compression for Push
11. Git Push support (beyond clone)
12. SSH Protocol support

---

### Testing Strategy

#### Integration Tests

- [ ] **Git Protocol Tests**
  - Clone empty project
  - Clone project with files
  - Clone with authentication
  - Verify file contents match

- [ ] **Session Workflow Tests**
  - Start → modify → land cycle
  - Start → push → resume cycle
  - Conflict detection and resolution
  - Multi-user concurrent sessions

- [ ] **Project Management Tests**
  - Create public/private projects
  - Fork projects
  - Delete projects

#### End-to-End Tests

- [ ] **Full Migration Test**
  - Import from GitHub
  - Clone via CLI
  - Make changes
  - Land session
  - Verify via web UI

---

### Metrics & Monitoring

Track CLI usage and performance:

- [ ] **CLI Telemetry** (opt-in)
  - Command usage frequency
  - Error rates by command
  - Session duration distribution
  - Clone/push/land latency

- [ ] **Server Metrics**
  - gRPC endpoint latency (p50, p95, p99)
  - Session land success rate
  - Conflict rate
  - Storage usage per project

---

### Branching Model

Micelio uses a simplified branching model optimized for agent-first development with sessions.

#### Core Concepts

**Main Branch (Trunk-Based Development)**
- Single `main` branch is the source of truth
- All sessions land directly to main (no feature branches by default)
- Each landing creates a new position in the timeline
- Rollback is achieved by landing a reverting session, not branch manipulation

**Sessions as Ephemeral Branches**
- Sessions are the equivalent of feature branches in traditional Git
- Each session is isolated until landed
- Sessions can be abandoned without affecting main
- Multiple agents can work on concurrent sessions

**Protected Main**
- Optional branch protection prevents direct landing
- Requires review/approval before landing
- Enforced via `protect_main_branch` project setting

#### Branching Implementation

While Micelio is primarily session-based, Git compatibility requires branch support:

```
refs/heads/main          → Current HEAD (latest landing)
refs/sessions/<id>       → Active session state
refs/landings/<pos>      → Historical landing points
refs/heads/<branch>      → Named branches (future, for Git compat)
```

**Tasks:**

- [ ] **Implement branch creation** (`lib/micelio/git/branches.ex`)
  - Create named branch pointing to specific position
  - Store in refs storage
  - Support branch from landing position

- [ ] **Implement branch switching** (`lib/micelio/git/branches.ex`)
  - Update working directory to branch HEAD
  - Track current branch in session state
  - Handle dirty working directory

- [ ] **Add branch protection rules** (`lib/micelio/projects/branch_protection.ex`)
  - Extend existing `protect_main_branch` to configurable rules
  - Rule types: require review, require CI pass, require specific reviewers
  - Store rules in database with project association

- [ ] **CLI branch commands** (`hif/src/branch.zig`)
  ```bash
  mic branch list                    # List all branches
  mic branch create <name>           # Create branch at current position
  mic branch create <name> --from <ref>  # Create from specific ref
  mic branch delete <name>           # Delete branch
  mic branch switch <name>           # Switch to branch
  ```

---

### Remote Management

Support multiple remotes for syncing with different forges or backup locations.

#### Remote Configuration

**Local config:** `.hif/config`

```toml
[remote "origin"]
url = "https://micelio.dev/org/project"
push = "refs/heads/*:refs/heads/*"
fetch = "+refs/heads/*:refs/remotes/origin/*"

[remote "github"]
url = "https://github.com/org/project.git"
push = "refs/heads/main:refs/heads/main"
fetch = "+refs/heads/*:refs/remotes/github/*"

[remote "backup"]
url = "s3://my-bucket/projects/myproject"
push = "refs/heads/main:refs/heads/main"
```

#### Remote Commands

```bash
# List remotes
mic remote list

# Add remote
mic remote add <name> <url>

# Remove remote
mic remote remove <name>

# Show remote details
mic remote show <name>

# Rename remote
mic remote rename <old> <new>

# Set remote URL
mic remote set-url <name> <url>

# Fetch from remote
mic fetch <remote>
mic fetch --all

# Push to remote
mic push <remote>
mic push <remote> <refspec>
```

**Implementation Tasks:**

- [ ] **Implement remote storage** (`hif/src/remote.zig`)
  - Parse TOML config for remotes
  - Validate remote URLs
  - Store in `.hif/config`

- [ ] **Implement fetch command** (`hif/src/fetch.zig`)
  - Connect to remote (gRPC for Micelio, git protocol for Git remotes)
  - Download refs and objects
  - Update remote-tracking refs

- [ ] **Implement push command** (`hif/src/push.zig`)
  - Determine refs to push based on refspec
  - Upload objects and refs
  - Handle push rejection (non-fast-forward)

- [ ] **Add S3 remote support** (`hif/src/remote/s3.zig`)
  - Store objects directly to S3
  - Use S3 conditional writes for atomic updates
  - Support encryption at rest

---

### File Operations

CLI commands for viewing and managing files within sessions.

#### Status Command

**Command:** `mic status`

```bash
# Show session status and changed files
mic status

# Output example:
# Session: abc123
# Goal: "Implement user authentication"
# Started: 2 hours ago
#
# Changes (3 files):
#   M src/auth.zig          (modified)
#   A src/oauth.zig         (added)
#   D src/old_auth.zig      (deleted)
#
# Conversation (2 notes):
#   [human] Decided to use OAuth 2.0
#   [agent] Implementing device flow
```

**Implementation Tasks:**

- [ ] **Implement status command** (`hif/src/status.zig`)
  - Read session.json for metadata
  - Scan overlay for changed files
  - Compute diff against base tree
  - Format output with colors

#### Diff Command

**Command:** `mic diff`

```bash
# Show all changes
mic diff

# Show changes for specific file
mic diff src/auth.zig

# Show changes between refs
mic diff <ref1>..<ref2>

# Show changes since last push
mic diff --since-push

# Output format options
mic diff --stat           # Summary only
mic diff --name-only      # File names only
mic diff --patch          # Full patch (default)
```

**Implementation Tasks:**

- [ ] **Implement diff command** (`hif/src/diff.zig`)
  - Use Myers diff algorithm (already in Zig stdlib)
  - Support unified diff format
  - Colorize output (insertions green, deletions red)
  - Handle binary files gracefully

#### Log Command

**Command:** `mic log`

```bash
# Show landing history
mic log

# Show last N landings
mic log -n 10

# Show landings for specific file
mic log -- src/auth.zig

# Show with stats
mic log --stat

# Output example:
# Landing #42 (abc123)
# Author: user@example.com
# Date: 2024-01-15 10:30:00 UTC
# Goal: Implement OAuth authentication
#
#   Added OAuth 2.0 device flow for CLI authentication.
#   Stores tokens in XDG config directory.
#
#   4 files changed, 368 insertions(+), 12 deletions(-)
```

**Implementation Tasks:**

- [ ] **Implement log command** (`hif/src/log.zig`)
  - Fetch landing history from server
  - Format output similar to git log
  - Support pagination for large histories
  - Cache landing metadata locally

#### Show Command

**Command:** `mic show`

```bash
# Show landing details
mic show <ref>

# Show file at specific ref
mic show <ref>:<path>

# Show current session state
mic show session
```

**Implementation Tasks:**

- [ ] **Implement show command** (`hif/src/show.zig`)
  - Fetch landing or session details
  - Display metadata and changes
  - Support file content extraction

---

### Deployment & Infrastructure

Configuration for deploying Micelio as a self-hosted forge.

#### Deployment Targets

**Option 1: Docker Compose (Single Server)**

```yaml
# docker-compose.yml
version: '3.8'
services:
  micelio:
    image: ghcr.io/micelio/micelio:latest
    ports:
      - "4000:4000"
      - "4001:4001"  # gRPC
    environment:
      DATABASE_URL: postgres://user:pass@db:5432/micelio
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      STORAGE_BACKEND: s3
      S3_BUCKET: micelio-storage
      S3_REGION: us-east-1
      PHX_HOST: micelio.example.com
    depends_on:
      - db
      - redis

  db:
    image: postgres:16
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: micelio
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: micelio

  redis:
    image: redis:7-alpine
    volumes:
      - redisdata:/data

volumes:
  pgdata:
  redisdata:
```

**Option 2: Kubernetes (Production Scale)**

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: micelio
spec:
  replicas: 3
  selector:
    matchLabels:
      app: micelio
  template:
    spec:
      containers:
      - name: micelio
        image: ghcr.io/micelio/micelio:latest
        ports:
        - containerPort: 4000
        - containerPort: 4001
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: micelio-secrets
              key: database-url
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
```

**Option 3: Fly.io (Managed)**

```toml
# fly.toml
app = "micelio"
primary_region = "iad"

[build]
  image = "ghcr.io/micelio/micelio:latest"

[env]
  PHX_HOST = "micelio.fly.dev"
  STORAGE_BACKEND = "s3"

[[services]]
  internal_port = 4000
  protocol = "tcp"
  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [[services.ports]]
    port = 80
    handlers = ["http"]

[[services]]
  internal_port = 4001
  protocol = "tcp"
  [[services.ports]]
    port = 4001
    handlers = ["tls"]
```

#### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes | - | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Yes | - | Phoenix secret key (64+ chars) |
| `PHX_HOST` | Yes | - | Public hostname |
| `PORT` | No | 4000 | HTTP port |
| `GRPC_PORT` | No | 4001 | gRPC port |
| `STORAGE_BACKEND` | No | local | `local`, `s3`, or `tiered` |
| `STORAGE_LOCAL_PATH` | No | /data | Path for local storage |
| `S3_BUCKET` | If S3 | - | S3 bucket name |
| `S3_REGION` | If S3 | - | S3 region |
| `S3_ENDPOINT_URL` | No | - | Custom S3 endpoint (MinIO, R2) |
| `S3_ACCESS_KEY_ID` | If S3 | - | S3 access key |
| `S3_SECRET_ACCESS_KEY` | If S3 | - | S3 secret key |
| `STORAGE_CDN_BASE_URL` | No | - | CDN URL for blob serving |
| `GITHUB_CLIENT_ID` | No | - | GitHub OAuth app ID |
| `GITHUB_CLIENT_SECRET` | No | - | GitHub OAuth secret |
| `GITLAB_CLIENT_ID` | No | - | GitLab OAuth app ID |
| `GITLAB_CLIENT_SECRET` | No | - | GitLab OAuth secret |
| `SMTP_HOST` | No | - | SMTP server for emails |
| `SMTP_PORT` | No | 587 | SMTP port |
| `SMTP_USERNAME` | No | - | SMTP username |
| `SMTP_PASSWORD` | No | - | SMTP password |
| `FROM_EMAIL` | No | - | From address for emails |

#### Database Migrations

```bash
# Run migrations
docker exec micelio bin/micelio eval "Micelio.Release.migrate()"

# Rollback last migration
docker exec micelio bin/micelio eval "Micelio.Release.rollback()"
```

#### Backup & Recovery

**Database Backup:**
```bash
# Backup PostgreSQL
pg_dump -h localhost -U micelio micelio > backup.sql

# Restore
psql -h localhost -U micelio micelio < backup.sql
```

**S3 Storage Backup:**
```bash
# Sync to backup bucket
aws s3 sync s3://micelio-storage s3://micelio-backup --delete

# Cross-region replication (configure in AWS console)
```

**Disaster Recovery:**
1. Restore PostgreSQL from backup
2. Ensure S3 objects are accessible (replicated or restored)
3. Deploy new Micelio instance with same configuration
4. Verify data integrity with checksums

---

### Security Hardening

#### Network Security

- [ ] **TLS Everywhere**
  - Require HTTPS for all HTTP endpoints
  - Require TLS for gRPC endpoints
  - Support Let's Encrypt auto-renewal
  - Minimum TLS 1.2, prefer TLS 1.3

- [ ] **Rate Limiting**
  - API rate limits per IP and per user
  - Separate limits for authenticated vs unauthenticated
  - Git protocol rate limiting

- [ ] **IP Allowlisting** (optional)
  - Restrict API access to known IPs
  - Allow bypass for specific tokens

#### Authentication Security

- [ ] **Password Policies** (if password auth enabled)
  - Minimum 12 characters
  - Require complexity
  - Check against breach databases (HaveIBeenPwned API)

- [ ] **Session Security**
  - Short-lived access tokens (15 minutes)
  - Longer refresh tokens (7 days)
  - Token rotation on refresh
  - Revocation on password change

- [ ] **2FA Enforcement**
  - Optional per-user
  - Enforceable per-organization
  - Support TOTP and WebAuthn

#### Code Security

- [ ] **Secret Scanning**
  - Scan all pushed content for secrets
  - Block landing if secrets detected
  - Support allowlisting for false positives
  - Use patterns from `lib/micelio/sessions/secret_scanner.ex`

- [ ] **Vulnerability Scanning**
  - Scan dependencies for known CVEs
  - Integrate with GitHub Advisory Database
  - Block landing for critical vulnerabilities (optional)

#### Audit Logging

- [ ] **Authentication Events**
  - Login success/failure
  - Token creation/revocation
  - Password changes
  - 2FA changes

- [ ] **Authorization Events**
  - Permission changes
  - Organization membership changes
  - Project visibility changes

- [ ] **Data Events**
  - Session landed
  - Project created/deleted
  - File access (for private projects)

---

### CLI Distribution

#### Binary Releases

Provide pre-built binaries for all major platforms:

| Platform | Architecture | Binary Name |
|----------|--------------|-------------|
| Linux | x86_64 | `mic-linux-amd64` |
| Linux | aarch64 | `mic-linux-arm64` |
| macOS | x86_64 | `mic-darwin-amd64` |
| macOS | aarch64 | `mic-darwin-arm64` |
| Windows | x86_64 | `mic-windows-amd64.exe` |

**Build Matrix:**

```yaml
# .github/workflows/release.yml
jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            target: x86_64-linux
          - os: ubuntu-latest
            target: aarch64-linux
          - os: macos-latest
            target: x86_64-macos
          - os: macos-latest
            target: aarch64-macos
          - os: windows-latest
            target: x86_64-windows
```

#### Package Managers

- [ ] **Homebrew (macOS/Linux)**
  ```bash
  brew install micelio/tap/mic
  ```
  Create formula in `homebrew-tap` repository

- [ ] **APT (Debian/Ubuntu)**
  ```bash
  curl -fsSL https://apt.micelio.dev/gpg | sudo gpg --dearmor -o /usr/share/keyrings/micelio.gpg
  echo "deb [signed-by=/usr/share/keyrings/micelio.gpg] https://apt.micelio.dev stable main" | sudo tee /etc/apt/sources.list.d/micelio.list
  sudo apt update && sudo apt install mic
  ```

- [ ] **RPM (Fedora/RHEL)**
  ```bash
  sudo dnf config-manager --add-repo https://rpm.micelio.dev/micelio.repo
  sudo dnf install mic
  ```

- [ ] **Cargo (Rust wrapper)**
  ```bash
  cargo install mic
  ```
  Wrapper that downloads and manages Zig binary

- [ ] **npm (Node wrapper)**
  ```bash
  npm install -g @micelio/cli
  ```
  Wrapper that downloads and manages Zig binary

#### Auto-Update

```bash
# Check for updates
mic update --check

# Update to latest version
mic update

# Update to specific version
mic update --version 1.2.3

# Disable auto-update check
mic config set auto_update false
```

**Implementation:**
- Check GitHub releases API for new versions
- Download and verify checksum
- Replace binary atomically
- Preserve configuration

---

### Developer Experience

#### IDE Integration

- [ ] **VS Code Extension**
  - Session status in status bar
  - Commands: start session, add note, land session
  - Diff view for session changes
  - Conflict resolution UI

- [ ] **JetBrains Plugin**
  - Similar functionality to VS Code
  - Support for IntelliJ, WebStorm, etc.

- [ ] **Neovim Plugin**
  - Lua-based plugin
  - Telescope integration for session commands
  - Inline conflict resolution

#### Shell Integration

```bash
# Add to .bashrc or .zshrc

# Show session info in prompt
eval "$(mic shell-init bash)"  # or zsh, fish

# Prompt example:
# user@host ~/project (session:abc123) $

# Completions
source <(mic completions bash)  # or zsh, fish
```

**Implementation Tasks:**

- [ ] **Shell prompt integration** (`hif/src/shell.zig`)
  - Output shell function for prompt
  - Fast check for session state
  - Support bash, zsh, fish

- [ ] **Shell completions** (`hif/src/completions.zig`)
  - Generate completion scripts
  - Complete command names
  - Complete file paths
  - Complete remote names
  - Complete session IDs

---

### Agent Integration

Enable AI agents to work seamlessly with Micelio.

#### Agent SDK

Provide SDK for common agent frameworks:

**Claude Code / Codex Integration:**
```bash
# .micelio/agent.toml
[agent]
name = "claude-code"
model = "claude-3-opus"
allowed_paths = ["src/", "lib/", "test/"]
denied_paths = [".env", "secrets/"]

[session]
auto_start = true
auto_note = true  # Log agent decisions as notes
auto_land = false  # Require human approval
```

**Agent API:**
```elixir
# Agent starts session
POST /api/v1/sessions
{
  "goal": "Fix authentication bug #123",
  "agent_id": "claude-code-abc123",
  "metadata": {
    "model": "claude-3-opus",
    "context_tokens": 100000
  }
}

# Agent writes file
PUT /api/v1/sessions/:id/files/:path
Content-Type: application/octet-stream
[file contents]

# Agent adds note
POST /api/v1/sessions/:id/notes
{
  "role": "agent",
  "content": "Identified root cause: race condition in token refresh"
}

# Agent requests landing
POST /api/v1/sessions/:id/land
{
  "require_approval": true,
  "summary": "Fixed auth bug by adding mutex"
}
```

**Implementation Tasks:**

- [ ] **Create Agent REST API** (`lib/micelio_web/controllers/api/agent_controller.ex`)
  - Session management endpoints
  - File upload/download
  - Note creation
  - Landing with approval flag

- [ ] **Implement agent authentication**
  - API tokens with agent scope
  - Rate limiting per agent
  - Usage tracking for billing

- [ ] **Add agent metadata to sessions**
  - Track which agent created session
  - Store model/version info
  - Link to agent progress UI

#### MCP (Model Context Protocol) Support

Implement MCP server for AI agent tool access:

```json
{
  "tools": [
    {
      "name": "micelio_session_start",
      "description": "Start a new coding session with a goal",
      "parameters": {
        "goal": {"type": "string", "description": "What you want to accomplish"},
        "project": {"type": "string", "description": "org/project identifier"}
      }
    },
    {
      "name": "micelio_file_write",
      "description": "Write content to a file in the current session",
      "parameters": {
        "path": {"type": "string"},
        "content": {"type": "string"}
      }
    },
    {
      "name": "micelio_session_land",
      "description": "Land the current session (push changes)",
      "parameters": {}
    }
  ]
}
```

**Implementation Tasks:**

- [ ] **Create MCP server** (`lib/micelio/mcp/server.ex`)
  - Implement MCP protocol
  - Expose session tools
  - Handle streaming responses

- [ ] **Document MCP setup for Claude Code**
  - Configuration in `.claude/mcp.json`
  - Available tools and usage

---

### Offline Support

Enable working without network connectivity.

#### Offline Session Management

```bash
# Work offline (sessions stored locally)
mic session start myorg/myproject "Offline work"
# ... make changes ...
mic session note "Working on plane, will sync later"

# When back online
mic sync                 # Sync all pending changes
mic session land         # Land the session
```

**Local Storage:**
- Session state in `.hif/session.json`
- File overlay in `.hif/overlay/`
- Pending operations in `.hif/pending/`

**Sync Process:**
1. Queue operations while offline
2. On reconnect, replay operations in order
3. Handle conflicts from concurrent remote changes
4. Notify user of sync results

**Implementation Tasks:**

- [ ] **Implement operation queue** (`hif/src/offline.zig`)
  - Store operations as JSON in `.hif/pending/`
  - Timestamp and order operations
  - Persist across CLI invocations

- [ ] **Implement sync command** (`hif/src/sync.zig`)
  - Check for pending operations
  - Fetch remote state
  - Apply pending operations
  - Handle conflicts
  - Clear pending queue on success

- [ ] **Add offline mode detection**
  - Check network connectivity
  - Gracefully degrade to offline mode
  - Queue operations automatically

---

### Performance Optimization

#### Client-Side Caching

```
~/.cache/mic/
├── blobs/              # Cached blob content (LRU, 1GB default)
├── trees/              # Cached tree structures
├── refs/               # Cached remote refs
└── metadata/           # Project metadata cache
```

**Cache Configuration:**
```toml
# ~/.config/mic/config.toml
[cache]
enabled = true
max_size_gb = 2
blob_ttl_days = 30
tree_ttl_days = 7
```

**Implementation Tasks:**

- [ ] **Implement blob cache** (`hif/src/cache.zig`)
  - LRU eviction policy
  - Content-addressed storage
  - Parallel downloads with cache checking
  - Cache warming for frequently accessed projects

#### Server-Side Optimization

- [ ] **Tiered Caching**
  - RAM cache for hot blobs (LRU)
  - SSD cache for warm blobs
  - S3 for cold storage
  - CDN for public project blobs

- [ ] **Parallel Processing**
  - Concurrent blob fetching
  - Parallel tree encoding
  - Async landing validation

- [ ] **Connection Pooling**
  - gRPC connection reuse
  - Database connection pooling
  - S3 connection pooling

---

### Observability

#### Structured Logging

```elixir
# Server-side logging
Logger.info("session.land",
  session_id: session.id,
  project_id: project.id,
  user_id: user.id,
  files_count: length(changes),
  duration_ms: elapsed
)
```

**Log Aggregation:**
- Support for JSON log format
- Compatible with Datadog, Grafana Loki, etc.
- Correlation IDs for request tracing

#### Metrics

**Prometheus Metrics:**
```
micelio_sessions_landed_total{project="org/proj"}
micelio_session_land_duration_seconds{quantile="0.99"}
micelio_storage_operations_total{operation="get", backend="s3"}
micelio_grpc_requests_total{method="LandSession", status="ok"}
```

**Implementation Tasks:**

- [ ] **Add Prometheus metrics** (`lib/micelio_web/telemetry.ex`)
  - Use `telemetry_metrics_prometheus`
  - Expose `/metrics` endpoint
  - Key metrics: request latency, throughput, error rates

- [ ] **Add distributed tracing** (`lib/micelio/tracing.ex`)
  - OpenTelemetry integration
  - Trace context propagation
  - Span for each operation

#### Health Checks

```
GET /health          # Basic health check
GET /health/ready    # Ready to serve traffic
GET /health/live     # Process is alive
```

**Health Check Implementation:**
```elixir
# lib/micelio_web/controllers/health_controller.ex
def ready(conn, _params) do
  checks = [
    {"database", check_database()},
    {"storage", check_storage()},
    {"redis", check_redis()}
  ]

  if Enum.all?(checks, fn {_, ok?} -> ok? end) do
    json(conn, %{status: "ok", checks: checks})
  else
    conn
    |> put_status(503)
    |> json(%{status: "unhealthy", checks: checks})
  end
end
```

---

### CI/CD Integration

Enable continuous integration and deployment with Micelio as the source of truth.

#### GitHub Actions Integration

**Workflow for Micelio-hosted projects:**

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout from Micelio
        uses: micelio/checkout@v1
        with:
          instance: ${{ vars.MICELIO_INSTANCE }}
          project: ${{ vars.MICELIO_PROJECT }}
          token: ${{ secrets.MICELIO_TOKEN }}

      - name: Run tests
        run: mix test

      - name: Report status to Micelio
        if: always()
        uses: micelio/status@v1
        with:
          instance: ${{ vars.MICELIO_INSTANCE }}
          token: ${{ secrets.MICELIO_TOKEN }}
          status: ${{ job.status }}
```

**Micelio GitHub Action (checkout):**

```yaml
# action.yml
name: 'Micelio Checkout'
description: 'Clone a project from Micelio forge'
inputs:
  instance:
    description: 'Micelio instance URL'
    required: true
  project:
    description: 'Project path (org/project)'
    required: true
  token:
    description: 'Micelio access token'
    required: true
  ref:
    description: 'Ref to checkout (default: HEAD)'
    required: false
runs:
  using: 'composite'
  steps:
    - name: Install mic CLI
      shell: bash
      run: |
        curl -fsSL https://micelio.dev/install.sh | bash
        echo "$HOME/.local/bin" >> $GITHUB_PATH

    - name: Authenticate
      shell: bash
      run: |
        echo "${{ inputs.token }}" | mic auth login --token-stdin --instance ${{ inputs.instance }}

    - name: Clone project
      shell: bash
      run: |
        mic clone ${{ inputs.instance }}/${{ inputs.project }} .
        if [ -n "${{ inputs.ref }}" ]; then
          mic checkout ${{ inputs.ref }}
        fi
```

#### Native CI System

Micelio's built-in CI system using Nix for reproducibility:

**Project Configuration:**
```nix
# .micelio/checks.nix
{
  checks = {
    test = {
      command = "mix test";
      timeout = 600;  # seconds
    };
    format = {
      command = "mix format --check-formatted";
      timeout = 60;
    };
    dialyzer = {
      command = "mix dialyzer";
      timeout = 1200;
      cache = true;  # Cache PLT files
    };
    credo = {
      command = "mix credo --strict";
      timeout = 120;
    };
  };

  # Required checks must pass before landing
  required = ["test", "format"];

  # Optional checks run but don't block
  optional = ["dialyzer", "credo"];
}
```

**Check Execution Flow:**

```
Session Land Request
        │
        ▼
┌───────────────────┐
│ Validation Queue  │  ← Ephemeral VM allocated
└───────────────────┘
        │
        ▼
┌───────────────────┐
│ Run Required      │  ← test, format
│ Checks in Parallel│
└───────────────────┘
        │
        ├── All Pass ──────────────────┐
        │                              │
        ▼                              ▼
┌───────────────────┐         ┌───────────────────┐
│ Run Optional      │         │ Session Landed    │
│ Checks            │         │ Successfully      │
└───────────────────┘         └───────────────────┘
        │
        ▼
┌───────────────────┐
│ Results Stored    │
│ (for display)     │
└───────────────────┘
```

**Implementation Tasks:**

- [ ] **Create Check Runner** (`lib/micelio/checks/runner.ex`)
  - Parse checks.nix configuration
  - Allocate ephemeral VM
  - Execute checks in parallel
  - Stream output in real-time
  - Collect results and artifacts

- [ ] **Implement Check Cache** (`lib/micelio/checks/cache.ex`)
  - Content-addressed cache for check results
  - Skip checks if inputs unchanged
  - Store cache in S3 with TTL

- [ ] **Build Check UI** (`lib/micelio_web/live/check_live/`)
  - Real-time check progress
  - Log streaming
  - Result summary
  - Artifact downloads

- [ ] **Add Check Webhooks**
  - `check.started`
  - `check.completed`
  - `check.failed`

#### GitLab CI Integration

```yaml
# .gitlab-ci.yml
stages:
  - clone
  - test
  - deploy

clone:
  stage: clone
  image: micelio/cli:latest
  script:
    - mic auth login --token $MICELIO_TOKEN --instance $MICELIO_INSTANCE
    - mic clone $MICELIO_INSTANCE/$MICELIO_PROJECT .
  artifacts:
    paths:
      - .

test:
  stage: test
  script:
    - mix test
  dependencies:
    - clone
```

#### Webhook-Based CI Triggers

Configure external CI systems to react to Micelio events:

**Webhook payload for session.landed:**
```json
{
  "event": "session.landed",
  "session": {
    "id": "abc123",
    "goal": "Add user authentication",
    "position": 42
  },
  "project": {
    "handle": "myproject",
    "organization_handle": "myorg"
  },
  "sender": {
    "handle": "developer"
  },
  "changes": {
    "files_added": 3,
    "files_modified": 5,
    "files_deleted": 1
  }
}
```

**Example: Jenkins trigger:**
```groovy
// Jenkinsfile
pipeline {
    triggers {
        GenericTrigger(
            genericVariables: [
                [key: 'SESSION_ID', value: '$.session.id'],
                [key: 'PROJECT', value: '$.project.handle']
            ],
            causeString: 'Micelio session landed',
            token: 'micelio-webhook',
            printContributedVariables: true
        )
    }
    stages {
        stage('Clone') {
            steps {
                sh 'mic clone $MICELIO_INSTANCE/$PROJECT .'
            }
        }
        stage('Test') {
            steps {
                sh 'mix test'
            }
        }
    }
}
```

---

### Review & Approval Workflow

Enable human review of sessions before landing, especially for agent-generated code.

#### Session States

```
┌────────────┐    ┌────────────┐    ┌────────────┐
│  Active    │───▶│  Pending   │───▶│  Landed    │
│            │    │  Review    │    │            │
└────────────┘    └────────────┘    └────────────┘
      │                 │
      │                 │
      ▼                 ▼
┌────────────┐    ┌────────────┐
│ Abandoned  │    │  Rejected  │
└────────────┘    └────────────┘
```

**State Transitions:**
- `active` → `pending_review`: Session submitted for review
- `pending_review` → `landed`: Review approved, changes landed
- `pending_review` → `rejected`: Review rejected, needs revision
- `pending_review` → `active`: Reviewer requests changes
- `active` → `abandoned`: Session cancelled
- `active` → `landed`: Direct land (if allowed by project settings)

#### Review Configuration

**Project settings:**
```elixir
# Project schema additions
field :require_review, :boolean, default: false
field :review_rules, :map, default: %{}
# review_rules example:
# %{
#   "require_review_for_agent_sessions" => true,
#   "require_review_for_protected_paths" => ["lib/micelio/auth/"],
#   "auto_approve_trusted_contributors" => true,
#   "minimum_reviewers" => 1
# }
```

#### Review Commands

```bash
# Submit session for review
mic session submit --reviewer @username

# List sessions pending review (for reviewers)
mic review list

# Review a session
mic review <session_id>

# Approve session
mic review approve <session_id> --comment "LGTM"

# Request changes
mic review request-changes <session_id> --comment "Please add tests"

# Reject session
mic review reject <session_id> --comment "Approach not suitable"
```

#### Review UI

**Session Review Page:**
- Side-by-side diff view
- Comment on specific lines
- Approve/reject buttons
- Request changes with structured feedback
- View session notes and decisions
- View agent metadata (if agent-generated)

**Implementation Tasks:**

- [ ] **Add review schema** (`lib/micelio/sessions/review.ex`)
  ```elixir
  schema "session_reviews" do
    belongs_to :session, Session
    belongs_to :reviewer, User
    field :status, :string  # approved, rejected, changes_requested
    field :comment, :string
    field :reviewed_at, :utc_datetime
    timestamps()
  end
  ```

- [ ] **Create review endpoints** (`lib/micelio/grpc/reviews_server.ex`)
  ```protobuf
  rpc SubmitForReview(SubmitReviewRequest) returns (ReviewResponse);
  rpc ListPendingReviews(ListReviewsRequest) returns (ListReviewsResponse);
  rpc ApproveSession(ApproveSessionRequest) returns (ReviewResponse);
  rpc RejectSession(RejectSessionRequest) returns (ReviewResponse);
  rpc RequestChanges(RequestChangesRequest) returns (ReviewResponse);
  ```

- [ ] **Build review UI** (`lib/micelio_web/live/review_live/`)
  - Diff viewer with line comments
  - Approval workflow
  - Notification integration

- [ ] **Add review notifications**
  - Email when review requested
  - Email when review completed
  - In-app notifications

#### Line Comments

```elixir
# Schema
schema "review_comments" do
  belongs_to :review, Review
  belongs_to :author, User
  field :file_path, :string
  field :line_number, :integer
  field :content, :string
  field :resolved, :boolean, default: false
  timestamps()
end
```

**Comment Commands:**
```bash
# Add comment to file during review
mic review comment <session_id> <file:line> "This could cause a race condition"

# List comments
mic review comments <session_id>

# Resolve comment
mic review resolve-comment <comment_id>
```

---

### Hooks & Automation

Enable custom automation triggered by project events.

#### Server-Side Hooks

**Hook Configuration:**
```elixir
# .micelio/hooks.exs
[
  %{
    event: "session.pre_land",
    action: "validate",
    script: """
    # Reject if commit message contains "WIP"
    if String.contains?(session.goal, "WIP") do
      {:error, "Cannot land WIP sessions"}
    else
      :ok
    end
    """
  },
  %{
    event: "session.post_land",
    action: "notify",
    webhook_url: "https://slack.com/webhook/xxx",
    template: "Session landed: {{session.goal}}"
  },
  %{
    event: "session.post_land",
    action: "deploy",
    condition: "session.target_branch == 'main'",
    script: "mix release && ./deploy.sh"
  }
]
```

**Hook Events:**

| Event | Timing | Can Block |
|-------|--------|-----------|
| `session.pre_land` | Before landing | Yes |
| `session.post_land` | After landing | No |
| `session.pre_review` | Before review submission | Yes |
| `project.pre_create` | Before project creation | Yes |
| `member.pre_add` | Before adding member | Yes |

**Implementation Tasks:**

- [ ] **Create Hook Schema** (`lib/micelio/hooks/hook.ex`)
  ```elixir
  schema "project_hooks" do
    belongs_to :project, Project
    field :event, :string
    field :action, :string
    field :config, :map
    field :enabled, :boolean, default: true
    timestamps()
  end
  ```

- [ ] **Implement Hook Runner** (`lib/micelio/hooks/runner.ex`)
  - Execute hooks in order
  - Handle blocking hooks (pre_*)
  - Timeout handling
  - Error logging

- [ ] **Build Hook UI** (`lib/micelio_web/live/settings_live/hooks.ex`)
  - List project hooks
  - Create/edit hooks
  - Test hook execution
  - View hook logs

#### Client-Side Hooks

**Local hooks in `.hif/hooks/`:**

```bash
# .hif/hooks/pre-session
#!/bin/bash
# Run before session start
echo "Starting session: $MIC_SESSION_GOAL"

# .hif/hooks/pre-land
#!/bin/bash
# Run before landing
mix format --check-formatted || exit 1
mix test || exit 1

# .hif/hooks/post-land
#!/bin/bash
# Run after landing
echo "Session landed at position $MIC_LANDING_POSITION"
```

**Environment Variables for Hooks:**
- `MIC_SESSION_ID` - Current session ID
- `MIC_SESSION_GOAL` - Session goal
- `MIC_PROJECT_ORG` - Organization handle
- `MIC_PROJECT_HANDLE` - Project handle
- `MIC_LANDING_POSITION` - Landing position (post-land only)
- `MIC_USER_HANDLE` - Current user handle

**Implementation Tasks:**

- [ ] **Implement client hooks** (`hif/src/hooks.zig`)
  - Scan `.hif/hooks/` directory
  - Execute hooks with environment
  - Handle hook failures
  - Support hook timeouts

---

### Federation

Enable Micelio instances to federate with each other and with ActivityPub-compatible services.

#### Forge-to-Forge Federation

**Use Cases:**
1. Mirror projects across instances for redundancy
2. Collaborate across organizational boundaries
3. Fork projects from federated instances
4. Discover projects on federated instances

**Federation Protocol:**

```
Instance A                      Instance B
    │                               │
    │   GET /.well-known/micelio    │
    │──────────────────────────────▶│
    │   {capabilities, public_key}  │
    │◀──────────────────────────────│
    │                               │
    │   POST /federation/follow     │
    │   {project: "org/proj"}       │
    │──────────────────────────────▶│
    │   {follow_id, status}         │
    │◀──────────────────────────────│
    │                               │
    │   ... time passes ...         │
    │                               │
    │   POST /federation/event      │
    │   {event: "session.landed"}   │
    │◀──────────────────────────────│
    │   {ack}                       │
    │──────────────────────────────▶│
```

**Discovery Endpoint:**
```json
// GET /.well-known/micelio
{
  "version": "1.0",
  "instance_name": "micelio.dev",
  "instance_url": "https://micelio.dev",
  "public_key": "-----BEGIN PUBLIC KEY-----...",
  "capabilities": [
    "federation:follow",
    "federation:mirror",
    "federation:fork",
    "activitypub"
  ],
  "projects_endpoint": "/api/federation/projects",
  "events_endpoint": "/api/federation/events"
}
```

**Implementation Tasks:**

- [ ] **Create Federation Schema** (`lib/micelio/federation/`)
  - `federated_instances` - Known instances
  - `federation_follows` - Project follows
  - `federation_events` - Event log

- [ ] **Implement Discovery** (`lib/micelio_web/controllers/federation_controller.ex`)
  - `/.well-known/micelio` endpoint
  - Instance capability negotiation
  - Key exchange for signed requests

- [ ] **Implement Follow Protocol** (`lib/micelio/federation/follower.ex`)
  - Follow remote projects
  - Receive events via webhook
  - Mirror project state locally

- [ ] **Implement Event Distribution** (`lib/micelio/federation/distributor.ex`)
  - Push events to followers
  - Handle delivery failures
  - Retry with backoff

#### ActivityPub Integration

**Existing implementation** extends with CLI support:

```bash
# Follow a project from fediverse
mic follow @project@micelio.dev

# List followers
mic followers

# View federated activity
mic activity --federated
```

**ActivityPub Actor for Projects:**
```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Application",
  "id": "https://micelio.dev/org/project",
  "name": "My Project",
  "preferredUsername": "project",
  "inbox": "https://micelio.dev/org/project/inbox",
  "outbox": "https://micelio.dev/org/project/outbox",
  "followers": "https://micelio.dev/org/project/followers"
}
```

**Activity Types:**
- `Create` (Session) - New session started
- `Update` (Session) - Session updated
- `Accept` (Session) - Session landed
- `Announce` (Project) - Project starred

---

### Data Export & Portability

Enable users to export their data and migrate away from Micelio if needed.

#### Export Formats

**Project Export:**
```bash
# Export as Git repository
mic export git ./my-project.git

# Export as archive (includes session history)
mic export archive ./my-project.tar.gz

# Export as JSON (metadata only)
mic export json ./my-project.json
```

**User Data Export:**
```bash
# Export all user data (GDPR compliance)
mic export user ./my-data.zip
```

**Export Contents:**
```
my-project.tar.gz
├── project.json           # Project metadata
├── sessions/              # All sessions
│   ├── abc123.json        # Session metadata
│   └── abc123/            # Session files
├── landings/              # Landing history
├── blobs/                 # All file contents
└── trees/                 # Tree structures
```

**Implementation Tasks:**

- [ ] **Create Export Service** (`lib/micelio/export/`)
  - Git bundle export
  - Archive export with session history
  - JSON metadata export

- [ ] **Add Export API** (`lib/micelio_web/controllers/api/export_controller.ex`)
  - Start export job
  - Check export status
  - Download export file

- [ ] **Implement GDPR Export** (`lib/micelio/export/gdpr.ex`)
  - Export all user data
  - Include audit logs
  - Include activity history

#### Import Formats

**Supported Sources:**
- Git repositories (GitHub, GitLab, Gitea, etc.)
- Git bundles
- Micelio archives (from export)
- Fossil repositories (future)
- Mercurial repositories (future)

**Import Commands:**
```bash
# Import from Git URL
mic import git https://github.com/org/project

# Import from local Git repo
mic import git ./local-repo

# Import from Micelio archive
mic import archive ./project.tar.gz

# Import from another Micelio instance
mic import micelio https://other.micelio.dev/org/project
```

---

### Backup & Disaster Recovery

#### Automated Backups

**Backup Configuration:**
```elixir
# config/runtime.exs
config :micelio, Micelio.Backup,
  enabled: true,
  schedule: "0 2 * * *",  # Daily at 2 AM
  retention_days: 30,
  destinations: [
    {:s3, bucket: "micelio-backups", prefix: "daily/"},
    {:local, path: "/backups/micelio/"}
  ],
  components: [
    :database,
    :blobs,
    :config
  ]
```

**Backup Types:**

| Type | Frequency | Retention | Contents |
|------|-----------|-----------|----------|
| Full | Weekly | 4 weeks | Everything |
| Incremental | Daily | 30 days | Changes since last full |
| Transaction log | Continuous | 7 days | Database WAL |

**Implementation Tasks:**

- [ ] **Create Backup Service** (`lib/micelio/backup/`)
  - Scheduled backup jobs via Oban
  - Multiple destination support
  - Encryption at rest
  - Verification checks

- [ ] **Implement Restore Process** (`lib/micelio/backup/restore.ex`)
  - Point-in-time recovery
  - Partial restore (single project)
  - Verification after restore

#### Disaster Recovery Runbook

**Recovery Scenarios:**

1. **Database Corruption**
   ```bash
   # Stop application
   systemctl stop micelio

   # Restore from latest backup
   pg_restore -d micelio /backups/latest/database.dump

   # Verify integrity
   mix micelio.verify_database

   # Start application
   systemctl start micelio
   ```

2. **S3 Data Loss**
   ```bash
   # Sync from backup bucket
   aws s3 sync s3://micelio-backups/latest/blobs/ s3://micelio-storage/

   # Verify blob integrity
   mix micelio.verify_blobs
   ```

3. **Complete Instance Failure**
   ```bash
   # Provision new infrastructure
   terraform apply

   # Restore database
   pg_restore -d micelio /backups/latest/database.dump

   # Restore blobs
   aws s3 sync s3://micelio-backups/latest/blobs/ s3://micelio-storage/

   # Update DNS
   # Verify functionality
   ```

**Recovery Time Objectives (RTO):**
- Database: < 1 hour
- Blobs: < 4 hours
- Full instance: < 8 hours

**Recovery Point Objectives (RPO):**
- Database: < 1 hour (with WAL archiving)
- Blobs: < 24 hours

---

### Roadmap Summary

#### Phase 1: MVP for Self-Hosting (Current Focus)

**Goal:** Enable migrating github.com/pepicrft/micelio to micelio.dev/micelio/micelio

| Feature | Priority | Status |
|---------|----------|--------|
| Git clone support | P0 | Not started |
| Project creation via CLI | P0 | Not started |
| Session land (verify) | P0 | Implemented |
| OAuth authentication (verify) | P0 | Implemented |
| Project import from GitHub | P0 | Implemented |

#### Phase 2: Developer Workflow

**Goal:** Make Micelio usable for daily development

| Feature | Priority | Status |
|---------|----------|--------|
| Session push/sync | P1 | Not started |
| Conflict resolution | P1 | Stubbed |
| Git push support | P1 | Not started |
| Review workflow | P1 | Not started |
| Native CI checks | P1 | Not started |

#### Phase 3: Team Collaboration

**Goal:** Support multi-developer teams

| Feature | Priority | Status |
|---------|----------|--------|
| Organization management | P1 | Partial |
| Branch protection | P1 | Basic |
| Code review comments | P2 | Not started |
| Notifications | P2 | Partial |

#### Phase 4: Agent-First Features

**Goal:** Optimize for AI agent workflows

| Feature | Priority | Status |
|---------|----------|--------|
| Agent API | P1 | Not started |
| MCP server | P2 | Not started |
| Prompt request system | P2 | Designed |
| Agent reputation | P3 | Designed |

#### Phase 5: Scale & Federation

**Goal:** Support large-scale and distributed usage

| Feature | Priority | Status |
|---------|----------|--------|
| Instance federation | P3 | Partial (ActivityPub) |
| Horizontal scaling | P3 | Not started |
| Multi-region | P3 | Not started |

---

### Quick Start Guide

#### For Users

```bash
# 1. Install CLI
curl -fsSL https://micelio.dev/install.sh | bash

# 2. Authenticate
mic auth login --instance micelio.dev

# 3. Clone a project
mic clone micelio.dev/org/project

# 4. Start a session
cd project
mic session start org project "Add new feature"

# 5. Make changes
vim src/feature.zig

# 6. Add a note about your decision
mic session note "Used strategy pattern for extensibility"

# 7. Land the session
mic session land
```

#### For Administrators

```bash
# 1. Deploy with Docker Compose
git clone https://github.com/micelio/micelio
cd micelio
cp .env.example .env
# Edit .env with your configuration
docker compose up -d

# 2. Run migrations
docker exec micelio bin/micelio eval "Micelio.Release.migrate()"

# 3. Create admin user
docker exec micelio bin/micelio eval "Micelio.Accounts.create_admin(%{email: \"admin@example.com\", handle: \"admin\"})"

# 4. Access the web UI
open https://your-domain.com
```

#### For Agents

```bash
# 1. Create API token
mic auth token create --name "Agent Token" --scope session:write,project:read

# 2. Configure agent
export MICELIO_TOKEN="your-token"
export MICELIO_INSTANCE="https://micelio.dev"

# 3. Start session programmatically
curl -X POST "$MICELIO_INSTANCE/api/v1/sessions" \
  -H "Authorization: Bearer $MICELIO_TOKEN" \
  -d '{"organization": "org", "project": "proj", "goal": "Fix bug #123"}'

# 4. Make changes via API
curl -X PUT "$MICELIO_INSTANCE/api/v1/sessions/$SESSION_ID/files/src/fix.zig" \
  -H "Authorization: Bearer $MICELIO_TOKEN" \
  --data-binary @fix.zig

# 5. Land session
curl -X POST "$MICELIO_INSTANCE/api/v1/sessions/$SESSION_ID/land" \
  -H "Authorization: Bearer $MICELIO_TOKEN"
```

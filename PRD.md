# Micelio - Agent-First Git Forge

Micelio is a minimalist, open-source git forge built with Elixir/Phoenix, designed for the agent-first future of software development. It integrates with hif (a Zig-based version control system) to provide session-based workflows that capture not just what changed, but why.

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
- [x] Create user profile page showing owned repositories and activity
  - Note: Activity graph (like GitHub's contribution graph) should be added
- [x] Add user activity graph (GitHub-style contribution visualization) to profile page
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
- [ ] Add GitHub OAuth authentication
  - Store as AuthIdentity linked to user by provider_user_id (github_id), NOT by email
  - AuthIdentity: user_id + provider + provider_user_id
- [ ] Add GitLab OAuth authentication
  - Store as AuthIdentity linked to user by provider_user_id (gitlab_id), NOT by email
  - AuthIdentity: user_id + provider + provider_user_id
- [ ] Add Passkey (WebAuthn) authentication support

### hif (Zig CLI)

- [ ] Implement NFS v3 server for virtual filesystem (hif-fs) in hif/src/fs/nfs.zig
- [ ] Create session overlay for tracking local changes before landing
- [ ] Add `hif mount` command to mount project as virtual filesystem
- [ ] Add `hif unmount` command to cleanly unmount virtual filesystem
- [ ] Implement prefetch on directory open for better performance
- [ ] Create bloom filter rollup background job for O(log n) conflict detection at scale
- [ ] Add epoch batching mode for high-throughput landing scenarios
- [ ] Implement CDN integration for blob serving
- [ ] Add delta compression for efficient storage of similar files
- [ ] Create `hif blame` command showing which session introduced each line
- [ ] Implement `hif cat` command to print file contents at any ref
- [ ] Add `hif ls` command to list directory contents at any ref

### Documentation & Testing

- [ ] Add comprehensive integration tests for gRPC session workflows
- [ ] Create property-based tests for bloom filter operations using StreamData
- [ ] Write end-to-end tests for the complete land workflow
- [ ] Add memory leak detection tests for Zig components
- [ ] Create user documentation for common hif workflows
- [ ] Add architecture decision records (ADRs) for key design choices

### Security & Compliance

- [ ] Implement audit logging for all project operations
- [ ] Add two-factor authentication (TOTP) support
- [ ] Create project access tokens with scoped permissions
- [ ] Implement branch protection rules for preventing direct lands to main
- [ ] Add secret scanning to prevent credential leaks in landed sessions

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

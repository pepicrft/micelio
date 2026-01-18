# Micelio + mic: The Complete Vision

**The future of software development is agent-first. We're building the infrastructure to support it.**

---

## The Big Picture

Micelio is not just another Git forge. It's a complete reimagining of version control and software collaboration for an AI-native world.

**Two interconnected projects:**

1. **mic** - Revolutionary version control system designed for agent-first workflows
2. **Micelio** - Modern forge built specifically for mic (like GitHub is to Git)

Together, they solve the fundamental problem: **Git tracks what happened. We need systems that track why.**

---

## The Problem We're Solving

### Current Reality (Git + GitHub)
- **Snapshot-based** - commits are frozen pictures, iterations invisible
- **Human-centric** - designed for think-then-commit workflows  
- **Linear scaling** - performance degrades with repo size and activity
- **Branch complexity** - merges, rebases, conflicts become unwieldy at scale
- **Lost context** - reasoning, alternatives, conversations happen outside VCS

### Agent-First Future
- **Hundreds of AI agents** working concurrently on codebases
- **Billions of files** in monorepos (Meta/Google scale)
- **Hundreds of thousands of changes per day**
- **Continuous reasoning** - agents explore, backtrack, iterate, decide
- **Human oversight** - reviewing and directing rather than writing most code

**Git can't handle this future. We need something fundamentally different.**

---

## Our Solution

### mic: Version Control Reimagined

**Philosophy:** "Git tracks what. mic tracks why."

#### Core Innovation: Sessions (Not Commits)
Every unit of work is a **session** containing:
- 🎯 **Goal** - what you're trying to accomplish
- 💬 **Conversation** - discussion between agents and humans  
- 🧠 **Decisions** - why things were done a certain way
- 📝 **Changes** - the actual file modifications

```
Session: "Add authentication to API"
├── Goal: Implement secure login/logout endpoints
├── Conversation
│   ├── Human: "Use JWT tokens for auth"
│   ├── Agent: "Should I store sessions in Redis?"
│   ├── Human: "No, keep JWT stateless"
│   └── Agent: "Implementing with bcrypt for passwords"
├── Decisions
│   ├── "JWT chosen over sessions per human preference"
│   ├── "Bcrypt for password hashing - industry standard"
│   └── "Auth middleware in /middleware - follows existing pattern"
└── Changes
    ├── + src/auth/jwt.zig
    ├── + src/middleware/auth.zig
    └── ~ src/main.zig (added auth routes)
```

#### Technical Architecture
- **Forge-first** - server is source of truth, not local disk
- **Object storage-first** - S3 as primary storage (like Turbopuffer)
- **Stateless agents** - no coordinator bottleneck (like WarpStream)
- **O(log n) operations** - bloom filters for conflict detection
- **Binary everywhere** - no JSON, optimized for performance
- **Coordinator-free landing** - S3 conditional writes for atomicity

### Micelio: The Forge for mic

**Built with Elixir/Phoenix** - A modern, minimalist forge designed specifically for mic workflows.

#### Key Features
- **Session-based workflows** - browse reasoning, not just code changes
- **Agent collaboration tools** - built for human + AI teams
- **Minimal UI** - focus on essential workflows, not feature bloat
- **Self-hostable** - your code, your infrastructure, your control
- **Open source** - GPL-2.0, following Git's lineage

#### Architecture Highlights
- **Stateless web agents** - any server handles any request
- **mic integration via Zig NIFs** - native performance through C FFI
- **SQLite for auth only** - users, tokens, permissions (~KB per user)
- **S3 for everything else** - repositories, sessions, file trees

---

## Why This Matters

### For Individual Developers
- **Capture reasoning** - never lose context of why decisions were made
- **Agent collaboration** - seamless handoffs between human and AI work
- **True history** - see the actual development process, not just snapshots
- **Reduced cognitive load** - systems that remember so you don't have to

### For Teams
- **Transparent decision-making** - everyone sees the why, not just the what
- **Efficient code review** - review reasoning and decisions, not just diffs
- **Knowledge preservation** - team knowledge captured in version control
- **Agent integration** - AI agents as first-class team members

### For Organizations
- **Scale beyond Git limitations** - handle massive monorepos efficiently
- **Audit trail** - complete reasoning chain for compliance/security
- **Faster onboarding** - new team members see historical decision context
- **Future-proof** - ready for the agent-first development paradigm

---

## Project Status & Roadmap

### Current State (January 2026)
- ⚠️ **Work in progress** - not ready for production use
- ✅ **mic core** - Zig implementation with C FFI
- ✅ **Micelio forge** - Elixir/Phoenix web application  
- ✅ **Basic workflows** - session start/land operations
- 🚧 **Active development** - rapid iteration on core concepts

### Next Milestones
1. **Session UI** - browse sessions with conversation/decision history
2. **Conflict resolution** - merge sessions with overlapping changes
3. **Performance optimization** - handle large repositories efficiently
4. **Agent SDK** - libraries for AI agents to use mic directly
5. **Migration tools** - import from Git repositories

### Long-term Vision
- **Industry adoption** - become the standard for agent-first development
- **Ecosystem growth** - tools, integrations, hosted solutions
- **Forge network** - federated instances like Git hosting today
- **AI-native workflows** - new paradigms we can't imagine yet

---

## Technical Deep Dive

### Architecture Overview

mic has three components that work together:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                               CLIENT (Zig)                                   │
│                                                                             │
│  Core modules (hash · bloom · HLC · tree) are embedded in the CLI.          │
│                                                                             │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                  │
│  │   mic CLI     │  │   mic-fs      │  │  Tiered Cache │                  │
│  │               │  │  (Phase 2)    │  │               │                  │
│  │ checkout      │  │  NFS daemon   │  │  RAM → SSD    │                  │
│  │ land          │  │  Mount point  │  │  → S3         │                  │
│  └───────────────┘  └───────────────┘  └───────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ gRPC
                                    │
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FORGE (stateless agents, like WarpStream)                 │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      Stateless Agents (Fly.io / Lambda / K8s)       │   │
│  │                                                                     │   │
│  │   Any agent can handle any request (no leader, no partitioning)    │   │
│  │   Auth · Session CRUD · Blob streaming · Landing                   │   │
│  │   Auto-scale based on CPU, scale to zero when idle                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                         │
│                          S3 Conditional Writes                              │
│                          (if-match / if-none-match)                         │
│                                   │                                         │
│                    No coordinator needed for landing!                       │
│                    S3 provides atomic compare-and-swap                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         S3 (source of truth)                                 │
│                                                                             │
│   Like Turbopuffer: object storage-first, not tiered                        │
│                                                                             │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│   │   Landing   │  │   Session   │  │    Tree     │  │    Blob     │       │
│   │     Log     │  │    Store    │  │    Store    │  │    Store    │       │
│   │             │  │             │  │             │  │             │       │
│   │ Append-only │  │   Binary    │  │   Binary    │  │   zstd      │       │
│   │ Bloom index │  │   format    │  │   B+ tree   │  │  content-   │       │
│   │             │  │             │  │             │  │  addressed  │       │
│   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                                             │
│   Auth: SQLite replicated via Litestream (tiny, ~KB per user)              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Language | Runs | Responsibility |
|-----------|----------|------|----------------|
| **Forge Agents** | Elixir | Cloud | Stateless API handlers, any agent handles any request |
| **mic CLI** | Zig | Local | User/agent interface |
| **mic-fs** | Zig | Local | Virtual filesystem (Phase 2) |
| **S3** | - | Cloud | Source of truth: landing log, sessions, trees, blobs |
| **SQLite** | - | Forge | Auth only (users, tokens, permissions) |

### Why This Architecture?

**Object storage-first (like Turbopuffer):**
- S3 is the source of truth, not a cold tier
- Data "inflates" from S3 → SSD → RAM as needed
- Inactive projects cost nearly nothing ($0.023/GB/month)
- 11 nines durability, no backups needed
- Strong consistency since 2020

**Stateless agents (like WarpStream):**
- No leader election, no partitioning, no Raft
- Any agent can handle any request
- Auto-scale based on CPU, scale to zero when idle
- Agent failure is a non-event (just restart)
- Trivial to deploy (single binary)

**S3 conditional writes (no coordinator):**
- Landing uses `if-match` headers for optimistic concurrency
- S3 provides atomic compare-and-swap
- No single coordinator bottleneck
- Multiple landings can race; S3 picks the winner
- Failed landings retry with backoff

**Binary everywhere (not JSON):**
- All data structures serialize to compact binary
- Core modules handle serialization
- Trees, blooms, sessions: all binary
- Fast to parse, small on disk
- Zero-copy where possible

**Bloom filter rollups (O(log n) conflict detection):**
- Hierarchical bloom filters cover ranges of landings
- Check conflict with O(log n) bloom lookups
- Not O(n) scan of all landed sessions
- Enables 100k+ landings/day

### S3 Storage Structure

All mic data is stored in S3 using compact binary formats:

```
s3://mic-{org}/
└── projects/
    └── {project_id}/
        │
        ├── head                         # Current head (48 bytes, binary)
        │   [8 bytes: position (u64)]
        │   [32 bytes: tree_hash]
        │   [8 bytes: hlc_updated]
        │
        ├── landing-log/                 # Append-only landing log
        │   │
        │   ├── 00000000.log             # Positions 0-999 (binary, ~100KB each)
        │   ├── 00001000.log             # Positions 1000-1999
        │   │
        │   └── bloom-index/             # Hierarchical bloom rollups
        │       ├── level-0/             # Individual landings
        │       ├── level-1/             # Bloom of 100 landings merged
        │       ├── level-2/             # Bloom of 10,000 landings merged
        │       └── level-3/             # Bloom of 1M landings merged
        │
        ├── sessions/
        │   └── {session_id}.bin         # Complete session state (binary)
        │
        ├── trees/
        │   └── {hash[0:2]}/
        │       └── {hash}.bin           # Serialized B+ tree (binary)
        │
        └── blobs/
            └── {hash[0:2]}/
                └── {hash}               # Raw blob (zstd compressed)
```

### Binary Formats

**Blob Format:**
```
Small files (<4MB):
  [4 bytes: magic "MICB"]
  [4 bytes: uncompressed size]
  [zstd compressed content]

Large files (>4MB) are chunked:
  [4 bytes: magic "MICC"]
  [4 bytes: chunk count]
  [N x 32 bytes: chunk hashes]
```

### CLI Reference

```bash
# Setup
mic auth login                    # Authenticate with forge
mic project create <name>         # Create new project on forge
mic checkout <account>/<project>  # Create local workspace

# Workspace
mic status                        # Workspace status
mic land <goal>                   # Land workspace changes

# Sessions (advanced)
mic session start "goal"          # Start new session
mic session status                # Current session info
mic session list                  # List sessions

# Content
mic cat <path>                    # Print file contents
mic ls [path]                     # List directory

# History
mic log                           # Show landed sessions
mic diff <ref1> <ref2>            # Diff between states
```

### Concurrency at Scale

**Target Numbers (Meta/Shopify Scale):**

| Metric | Target |
|--------|--------|
| Files per project | 1B+ |
| Landings per day | 500,000+ |
| Concurrent sessions | 100,000+ |
| Concurrent agents | 10,000+ |

### Deterministic Simulation Testing

Inspired by TigerBeetle and FoundationDB, mic uses deterministic simulation to test decades of failures in hours.

**What We Verify:**
- Landing atomicity (all-or-nothing)
- Conflict detection correctness (no false negatives)
- Bloom rollup consistency
- Head monotonicity (position never decreases)
- No data loss under any failure sequence
- HLC causality (if A caused B, HLC(A) < HLC(B))

---

## Contributing

We're in early development but welcome:
- **Feedback** on core concepts and user experience
- **Code contributions** to mic core and Micelio forge
- **Documentation** improvements and examples
- **Testing** with real repositories and workflows

See individual project READMEs for development setup.

---

## Philosophy

We believe the future of software development is collaborative intelligence - humans and AI agents working together as peers. This requires new tools designed from the ground up for this reality.

Git was revolutionary for its time, enabling distributed human collaboration at unprecedented scale. But the world has changed. We need systems that capture not just what we built, but how we reasoned, why we chose alternatives, and how we can learn from the process.

**mic + Micelio is our bet on that future.**

---

## Agent-First Build System Architecture [TO REVIEW/VALIDATE]

### The Nix + S3 Integration Model

**Core insight:** Agents need local validation they can trust, but the forge needs stateless, scalable execution and caching.

**Terminology:** We call the full suite of automated validation (tests, linting, formatting, static analysis, builds, scans) **checks**. A check is “the same everywhere” when it’s expressed as a reproducible Nix derivation, so passing locally matches remote execution.

#### Nix's Role: Environment Reproducibility
- **flake.nix defines everything:** dependencies, build steps, test environments
- **Local agent validation:** `nix develop --command make test` gives instant feedback
- **Reproducible anywhere:** same Nix derivation = identical environment (agent machine = remote = prod)
- **Content addressing:** Nix's `/nix/store/hash-package` model aligns with S3 content-addressable storage

#### S3's Role: Stateless Persistence & Distribution
```
S3 Bucket Structure:
├── derivations/
│   └── sha256:abc123.drv → Nix derivation definitions
├── artifacts/  
│   └── sha256:def456/ → build outputs, binaries, assets
├── cache/
│   ├── builds/sha256:ghi789 → complete build results
│   ├── tests/sha256:jkl012 → test execution results  
│   └── telemetry/sha256:mno345 → timing, resource usage
├── execution-logs/
│   └── sha256:pqr678 → full build/test output logs
└── attestations/
    └── sha256:stu901 → cryptographic proof of execution
```

#### Agent Build Workflow
```
1. Agent modifies code in mic session
2. Build system generates Nix derivation from changes
3. Check S3 for existing artifact: GET /artifacts/sha256:computed-hash
4. Cache miss → Execute locally: nix-build derivation  
5. Cache hit → Skip build, validate locally: nix develop --command make verify
6. Upload results to S3: PUT /artifacts/sha256:new-hash
7. All tests pass → mic land (session includes build attestation)
```

#### Remote Execution Integration
```
For heavy builds or special capabilities:
├── Agent generates Nix derivation locally
├── Submits to remote execution queue (stored in S3)
├── Remote workers:
│   ├── Fetch derivation from S3
│   ├── Execute in identical Nix environment  
│   ├── Upload artifacts back to S3
│   └── Signal completion via S3 event
└── Agent gets notification, validates results locally
```

#### Security & Secrets Model
```
Capability-based access via S3 policies:
├── Agent identity: arn:aws:iam::account:role/agent-session-abc123
├── Scoped permissions:
│   ├── s3:GetObject on artifacts/* (read builds)
│   ├── s3:PutObject on artifacts/session-abc123/* (write own builds)
│   └── secretsmanager:GetSecretValue for session-scoped secrets
├── Time-bound: role expires with mic session
└── Audit trail: CloudTrail logs every S3/secrets access
```

#### Build Cache Optimization
```
Content-addressable caching strategy:
├── Input hash: source + dependencies + build script + Nix derivation
├── S3 check: artifacts/sha256:input-hash exists?
├── Cache hit: Download artifact, verify locally with Nix
├── Cache miss: Build locally/remotely, upload to S3
└── Global sharing: all agents benefit from each other's builds
```

#### Stateless Forge Workers
```
Micelio forge workers (Elixir/Phoenix):
├── No local state: everything in S3
├── Build requests: generate Nix derivations, queue in S3
├── Status queries: check S3 for completion
├── Artifact serving: presigned S3 URLs for downloads
└── Auto-scaling: workers are completely stateless
```

#### Integration with mic Sessions
```
Session: "Add payment gateway integration"
├── Goal: Integrate Stripe API safely
├── Build Context:
│   ├── Nix derivation: payment-gateway.nix (reproducible env)
│   ├── S3 artifacts: sha256:abc123 (cached build outputs)
│   ├── Test results: sha256:def456 (integration test pass)
│   └── Security attestation: sha256:ghi789 (secrets access logged)
├── Decisions: 
│   ├── "Used Stripe test keys for integration tests"
│   └── "All tests pass in identical production environment"
└── Land: Session includes cryptographic proof builds work
```

#### Why This Architecture Works

**For Agents:**
- Instant local feedback via Nix
- Confidence: local success = production success  
- Autonomous: no waiting for CI queues
- Secure: capability-based secret access

**For Organizations:**
- Scalable: S3 handles petabytes, millions of artifacts
- Cost-effective: pay only for storage used, workers auto-scale
- Auditable: every build, test, secret access logged
- Reproducible: bit-for-bit identical builds anywhere

**For the Forge:**
- Stateless: workers can restart/scale without losing state
- Global: S3 provides worldwide CDN for build artifacts
- Reliable: 11 nines durability, no backup needed
- Simple: no complex distributed caching layer

This model gives agents the speed of local development with the confidence of enterprise-grade CI/CD, while keeping the forge architecture stateless and scalable.

---

## mic Build Cache Daemon [TO REVIEW/VALIDATE]

### Architecture: Local Daemon + Protocol Translation

**Inspired by [Fabrik's](https://github.com/tuist/fabrik) proven architecture**, mic implements a local daemon that speaks existing build system protocols while providing S3-backed global caching.

#### Core Design Pattern

```
┌─────────────────────────────────────────────────────────┐
│                    mic daemon                           │
│                  (per-session)                          │
│                                                         │
│ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────┐ │
│ │ Bazel Protocol  │ │ Gradle Protocol │ │Docker Reg.  │ │
│ │ (gRPC Remote    │ │ (HTTP Build     │ │(Layer Cache)│ │
│ │  Cache API)     │ │  Cache API)     │ │             │ │
│ └─────────────────┘ └─────────────────┘ └─────────────┘ │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │            mic Session Engine                       │ │
│ │  • Content-addressable artifact mapping            │ │
│ │  • Session-scoped authentication                   │ │
│ │  • S3 backend with local cache tiers               │ │
│ │  • Automatic protocol detection & routing          │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
                  ┌─────────────────┐
                  │   Micelio S3    │
                  │ (Global Cache)  │
                  └─────────────────┘
```

#### Zero-Configuration Activation

**Shell integration pattern (from Fabrik):**
```bash
# One-time setup
echo 'eval "$(mic activate zsh)"' >> ~/.zshrc

# Automatic activation on directory change
cd ~/my-project
# → mic detects session context
# → starts daemon with session-scoped identity  
# → exports build tool environment variables
# → all build commands transparently use cache
```

#### Protocol Translation Examples

**Bazel Remote Cache Protocol:**
```bash
# Daemon exports standard Bazel env vars
export BAZELRC=$HOME/.local/state/mic/sessions/abc123/bazelrc

# Auto-generated bazelrc content:
# build --remote_cache=grpc://localhost:8080
# build --remote_upload_local_results=true

# Bazel commands work unchanged
bazel build //...
# → Talks to mic daemon via gRPC
# → mic translates to S3 content-addressed storage
# → Transparent caching across all agents
```

**Gradle Build Cache:**
```bash
# Daemon exports Gradle-specific URL
export GRADLE_BUILD_CACHE_URL=http://localhost:8080/gradle-cache/

# Gradle automatically uses remote cache
./gradlew build
# → Gradle sends HTTP requests to mic daemon
# → mic maps to S3 artifacts with session context
# → Perfect cache sharing without configuration
```

**Docker Registry Protocol:**
```bash
# Daemon exposes Docker registry API
export DOCKER_REGISTRY=localhost:8080

# Docker commands work transparently  
docker build -t myapp .
# → Docker pushes layers to mic daemon
# → mic stores layers in S3 content-addressed
# → Other agents get instant layer cache hits
```

#### Session-Scoped Daemon Management

**Per-session daemon isolation:**
```
mic session start "add-payments"
├── Computes session hash: sha256:abc123...
├── Spawns daemon: ~/.local/state/mic/sessions/abc123/
│   ├── daemon.pid
│   ├── ports.json → {"http": 54321, "grpc": 54322}
│   ├── session_identity → time-bound S3 credentials
│   └── bazelrc → auto-generated build tool configs
├── Session ends → daemon auto-terminates
└── Credentials expire → no lingering access
```

#### Multi-Toolchain Content Addressing

**Universal artifact mapping:**
```
Source changes hash: sha256:def456...
Build artifacts stored as:
├── s3://forge/artifacts/bazel/def456/binary
├── s3://forge/artifacts/gradle/def456/jar  
├── s3://forge/artifacts/docker/def456/layers/
└── s3://forge/artifacts/custom/def456/outputs/

Cross-toolchain deduplication:
├── Same source hash = shared base artifacts
├── Different toolchains = different artifact paths
└── mic daemon handles mapping automatically
```

#### Advanced Cache Hierarchy

**Multi-tier caching strategy (inspired by Fabrik's P2P discovery):**
```
Agent cache lookup order:
1. Local filesystem cache (instant)
2. Local network P2P cache (1-5ms) 
3. Regional S3 bucket (10-50ms)
4. Global S3 bucket (50-200ms)
5. Rebuild locally (fallback)

mic daemon coordinates all tiers transparently
```

#### Build System Integration Matrix

| Build System | Protocol | Configuration | mic Integration |
|--------------|----------|---------------|-----------------|
| **Bazel** | gRPC Remote Cache | `BAZELRC` env var | Zero-config via auto-generated bazelrc |
| **Gradle** | HTTP Build Cache | `GRADLE_BUILD_CACHE_URL` | Zero-config via env var export |
| **Buck2** | gRPC Remote Cache | Command flags | Via shell alias or wrapper |
| **Nx** | HTTP Cache API | `NX_SELF_HOSTED_REMOTE_CACHE_SERVER` | Zero-config via env var |
| **TurboRepo** | HTTP API | `TURBO_API`, `TURBO_TOKEN` | Auto-generated token + URL |
| **Docker** | Registry Protocol | `DOCKER_REGISTRY` | Daemon exposes registry API |
| **sccache** | HTTP/S3 Protocol | `SCCACHE_ENDPOINT` | Compiler cache integration |
| **Custom** | HTTP REST | `CACHE_URL` | Generic HTTP cache interface |

#### Agent Workflow Integration

**Seamless integration with mic sessions:**
```
Session: "Optimize API performance"
├── Goal: Reduce response time by 50ms
├── Conversation: [agent reasoning about approach]
├── Build Context:
│   ├── Cache hits: 95% (Bazel remote cache)
│   ├── Build time: 0.8s (mostly cached)
│   ├── Test time: 2.1s (integration tests)
│   └── Total validation: 2.9s
├── Decisions:
│   ├── "Database connection pooling approach"
│   ├── "All tests pass in <3s - confident change"
│   └── "Performance improvement verified"
└── Land: Session includes build performance metrics
```

#### Implementation Benefits

**For Agents:**
- **Instant feedback**: 95%+ cache hit rates mean sub-second validation
- **Zero configuration**: All build tools work without modification
- **Consistent environments**: Nix + cached artifacts = identical results
- **Autonomous workflow**: No waiting for CI, no manual cache management

**For Organizations:**
- **Massive cost savings**: Shared cache eliminates redundant builds
- **Global consistency**: Same artifacts used everywhere
- **Security**: Session-scoped access, full audit trails
- **Scalability**: S3 handles unlimited storage, unlimited agents

**For Build Systems:**  
- **No modification required**: Existing build scripts work unchanged
- **Protocol compatibility**: Speaks native build system languages
- **Performance**: Local daemon eliminates network roundtrips for cache checks
- **Reliability**: Graceful degradation if cache unavailable

This daemon architecture provides the "narrow waist" that makes mic universally adoptable while enabling revolutionary agent workflows.

---

## Session Implementation Details

### Schema Design

**Session** - The main session record contains:
- `goal`: What the session aims to accomplish
- `conversation`: Array of messages (agent/human dialog)
- `decisions`: Array of decision records with reasoning
- `metadata`: Additional context
- `status`: active, landed, or abandoned
- `changes`: Has-many relationship to SessionChange

**SessionChange** - Individual file modifications within a session:
- `file_path`: The file that changed
- `change_type`: "added", "modified", or "deleted"
- `content`: Inline content for small files (< 100KB)
- `storage_key`: S3/local storage reference for large files
- `metadata`: File-specific metadata (size, lines changed, etc.)

### Storage Strategy

Files are stored based on size:
- **Small files (< 100KB)**: Stored inline in `content` field
- **Large files (>= 100KB)**: Stored in object storage, referenced by `storage_key`

Storage path pattern: `sessions/{session_id}/changes/{file_path}`

### Session Lifecycle (gRPC + CLI)

- Start session: `SessionService.StartSession`
- Land session: `SessionService.LandSession`
- CLI flow:
  - `mic session start <organization> <project> <goal>`
  - `mic session land`

### Session Changes vs Git Commits

| Git Commits | Session Changes |
|-------------|-----------------|
| Snapshot-based | Context-aware |
| What changed | What changed + why |
| Manual commit messages | Integrated conversation |
| Lost iterations | Preserved reasoning |
| Linear history | Session-based grouping |

---

*Built by Ruby and contributors. Apache-2.0 licensed.*

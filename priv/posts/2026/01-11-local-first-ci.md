%{
  title: "Local-First CI: Rethinking Build Verification for an Agent-First World",
  author: "Pedro Piñera",
  tags: ~w(vision architecture nix),
  description: "Traditional CI/CD is broken for agent-first development. Here's how local-first verification with Nix can give us instant feedback, perfect reproducibility, and a path beyond the CI queue."
}

---

# Local-First CI: Rethinking Build Verification for an Agent-First World

Every developer has lived this nightmare: you push a commit, wait 10 minutes for CI, and discover a typo that would have taken 2 seconds to fix locally. Multiply this by hundreds of AI agents working concurrently, making thousands of decisions per hour, and traditional CI/CD becomes the bottleneck that kills agent-first development before it even starts.

I think it's time to question a fundamental assumption: **Why do we send code to remote servers to verify it works?**

## The CI/CD Bottleneck

Traditional continuous integration made sense in 2010. GitHub Actions, CircleCI, Jenkins—they all follow the same model: push your code, wait in a queue, run tests on a remote server, get results. This worked when humans were the primary developers, making a few commits per day, thinking carefully before each push.

But consider the agent-first future we're building toward:
- **Hundreds of AI agents** exploring solutions concurrently
- **Rapid iteration cycles** - agents backtrack, try alternatives, refine approaches
- **Thousands of validation cycles per day** across the team
- **Sub-second feedback loops** needed for agent productivity

In this world, waiting 5-10 minutes for CI is like asking an agent to take a coffee break after every thought. The queue itself becomes the constraint—not the tests, but the architectural decision to run them remotely.

## Local-First: The Radical Alternative

What if we flip the model entirely?

**Instead of:** Push → Wait → Remote CI → Results → Fix → Repeat  
**What if:** Validate Locally → Push Verified Code → Done

This isn't just faster. It's a fundamentally different trust model. In traditional CI, the remote server is the source of truth. In local-first CI, the developer's machine (or the agent's execution environment) becomes a trusted validator.

### How It Works

```
# Agent working on a session
hif session start "optimize-api-performance"

# Make changes, run full validation locally
nix develop --command make test
# → Tests run in identical Nix environment
# → Same dependencies as production
# → Cached artifacts from S3
# → Results in 2.3 seconds

# All green? Land it
hif land
# → Session includes cryptographic attestation
# → Build artifacts uploaded to S3
# → No CI queue, no waiting
```

The key insight: if we can **guarantee environment reproducibility**, local execution becomes trustworthy. The question shifts from "did the tests pass?" to "can we trust the environment they ran in?"

## The Trust Problem: Dependencies and Verification

Here's where most people get skeptical. "If developers run checks locally, how do we trust third-party dependencies? What stops someone from shipping malicious code that only passes tests on their machine?"

This is the right question, and the answer isn't "trust developers more." It's **reproducible builds with cryptographic verification**.

### Content-Addressable Everything

Nix gives us this superpower: every dependency, every build input, every environment variable gets hashed into a content-address. When you build something with Nix, the result is deterministic.

```
# flake.nix for your project
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/23.11";
    # Exact commit hash - cryptographically pinned
  };

  outputs = { self, nixpkgs }: {
    devShell = nixpkgs.mkShell {
      buildInputs = [
        pkgs.elixir_1_15
        pkgs.erlang_26  
        pkgs.nodejs_20
      ];
      # Every input hashed: sha256:abc123...
    };
  };
}
```

When an agent builds code locally, Nix generates a derivation hash from:
- Source code content
- All dependencies (pinned by hash)  
- Build script
- Compiler version
- Environment variables

**Same derivation hash = identical environment = trustworthy results.**

### Attestation Model

But we can go further. Instead of just trusting that environments match, we cryptographically prove it:

```
Session: "Add payment gateway"
├── Goal: Integrate Stripe API
├── Build Attestation:
│   ├── Nix derivation: sha256:def456 (reproducible env)
│   ├── Test results: sha256:ghi789 (all pass)
│   ├── Agent identity: agent-session-abc123
│   ├── Timestamp: 2026-01-11T18:00:00Z
│   └── Signature: cryptographic proof this agent built this
└── Verification:
    ├── Anyone can rebuild from derivation hash
    ├── Results must match exactly (bit-for-bit)
    └── Signature proves agent authorization
```

This is more secure than traditional CI because:
1. **Reproducible verification**: Anyone can rebuild and verify results match
2. **No shared infrastructure to compromise**: Each agent has isolated execution
3. **Cryptographic audit trail**: Every build is signed and attributable
4. **Content-addressed artifacts**: Tampering changes the hash

### Dependency Trust Through Transparency

For third-party dependencies, we layer additional verification:

**Binary cache attestations:**
```
# Official Nix cache serves pre-built packages
# Each binary includes build attestation
nix-store --verify /nix/store/abc123-elixir-1.15.0
# → Cryptographic signature from Nix build farm
# → Reproducible: you can rebuild from source and verify hash matches
# → Tamper-proof: any modification breaks the signature
```

**Vulnerability scanning integration:**
```
# Before landing session, scan dependencies
nix develop --command security-scan
# → Checks CVE databases for known vulnerabilities
# → Verifies package signatures
# → Fails if untrusted packages detected
```

The trust model becomes: **don't trust, verify**. Every dependency is cryptographically pinned, every build is reproducible, every result is attestable.

## Nix: The Missing Infrastructure for Local-First CI

You might be thinking: "This sounds great in theory, but won't every developer need to install gigabytes of dependencies? Won't builds be slow without powerful CI servers?"

This is where Nix's architecture shines.

### Content-Addressable Storage Meets S3

Remember how we designed hif with S3 as primary storage? Nix follows the same pattern—everything lives in `/nix/store/hash-packagename`, a content-addressed file system.

This maps perfectly to S3:

```
S3 Bucket Structure:
├── derivations/
│   └── sha256:abc123.drv → Nix derivation definitions
├── artifacts/  
│   └── sha256:def456/ → pre-built binaries, cached builds
├── cache/
│   ├── builds/sha256:ghi789 → complete build results
│   └── tests/sha256:jkl012 → test execution outputs
└── attestations/
    └── sha256:mno345 → cryptographic proof of execution
```

When an agent needs a dependency:

```
# Agent checks: do I have this locally?
ls /nix/store/sha256:abc123-elixir-1.15.0
# → Not found locally

# Check S3 cache
aws s3 ls s3://micelio-cache/artifacts/sha256:abc123/
# → Found! Another agent already built this

# Download binary (not source)
nix copy --from s3://micelio-cache sha256:abc123-elixir-1.15.0
# → 50MB download in 2 seconds
# → Verify hash matches
# → Ready to use
```

**This is revolutionary**: agents share a global build cache. The first agent to need a dependency pays the build cost. Every subsequent agent gets instant access to the pre-built artifact.

### Environment Reproduction Guarantees

Nix doesn't just track dependencies—it **isolates** them. When you run `nix develop`, you get:

- **Hermetic environment**: Only declared dependencies available
- **No system pollution**: Your macOS/Linux differences don't matter  
- **Identical across machines**: Agent machine = developer machine = production
- **Instant rollback**: `nix develop --profile /nix/profiles/last-week` gives you the exact environment from last week

This is the guarantee we need for local-first CI: **if it works in the Nix environment locally, it works everywhere.**

### Performance: Making It Fast Enough

"But won't building everything locally be slower than powerful CI servers?"

Actually, no. Here's why:

**1. Cache Hit Rate**

In a traditional setup, each commit triggers fresh builds. In content-addressed Nix:

```
# Change one file
git add src/api/routes.ex

# Nix rebuilds only affected dependencies
nix build
# → Core libraries: cache hit (0s)
# → Database layer: cache hit (0s)  
# → API layer: rebuild (1.2s)
# → Tests for API: rebuild (0.8s)
# Total: 2 seconds
```

With hundreds of agents working on the same codebase, cache hit rates approach 95%+. Most validation cycles take seconds, not minutes.

**2. Incremental Builds**

Nix's content-addressing enables perfect incrementality:

```
# Monday: Agent builds feature A
nix build .#feature-a
# → Builds dependencies D1, D2, D3
# → Takes 5 minutes first time
# → Results cached in S3

# Tuesday: Different agent builds feature B
nix build .#feature-b  
# → Needs same dependencies D1, D2
# → Cache hit from S3 (instant)
# → Only builds new code (30s)
```

**3. Parallel Execution**

Agents don't compete for CI slots:

```
Traditional CI:
├── Agent 1 pushes → Queue position 1 → Runs in 2min
├── Agent 2 pushes → Queue position 2 → Waits 2min, runs 2min  
├── Agent 3 pushes → Queue position 3 → Waits 4min, runs 2min
└── Total time: 8 minutes for 3 agents

Local-First:
├── Agent 1 validates → 2s (cache hit)
├── Agent 2 validates → 2s (cache hit, parallel)
├── Agent 3 validates → 2s (cache hit, parallel)
└── Total time: 2 seconds for 3 agents
```

**4. Smart Caching Hierarchy**

We can layer caches for even better performance:

```
Cache lookup order:
1. Local /nix/store (instant)
2. Local network P2P cache (1-5ms)
3. Regional S3 bucket (10-50ms)  
4. Global S3 bucket (50-200ms)
5. Rebuild from source (fallback)
```

In practice, 99%+ of lookups hit local or P2P cache. Validation feels instant.

## Infrastructure Requirements: Surprisingly Minimal

You might expect local-first CI to require massive infrastructure. Actually, it's simpler and cheaper than traditional CI/CD:

### What You Need

**For the Cache (S3):**
```
Monthly storage (1000 developers, 100 projects):
├── Nix derivations: ~500MB
├── Build artifacts: ~50GB  
├── Test results: ~10GB
├── Attestations: ~1GB
└── Total: ~62GB × $0.023/GB = $1.43/month

Monthly transfer (95% cache hit rate):
├── Cache downloads: 1000 devs × 10 builds/day × 50MB × 5% miss = 2.5TB
├── Cost: 2.5TB × $0.09/GB = $225/month
└── Compare to: GitHub Actions 2000min/user × 1000 users = $40,000/month
```

**For Agents (Compute):**
- Each agent needs: 2-4 CPU cores, 4-8GB RAM (commodity hardware)
- No centralized CI servers to maintain
- No queue management infrastructure  
- No coordinator bottlenecks

**For the Forge (Micelio):**
- Stateless web servers (auto-scaling)
- SQLite for auth only (~KB per user)
- S3 for everything else
- No build execution infrastructure

### What You Don't Need

❌ Dedicated CI servers  
❌ Build queue management  
❌ Complex caching layers  
❌ Artifact storage systems  
❌ CI/CD pipeline orchestration

The architecture is **radically simpler** because we leverage:
- Nix for reproducibility (free, open source)
- S3 for global caching (commodity storage)  
- Content-addressing for deduplication (automatic)
- Agent machines for execution (already available)

## The Post-CI/CD World

Here's what development looks like in this model:

**Agent Workflow:**
```
# Session starts
hif session start "add-realtime-notifications"

# Agent iterates rapidly
edit src/notifications/websocket.ex
nix develop --command mix test
# → 1.2s, cache hit, all green

edit src/notifications/push.ex  
nix develop --command mix test
# → 0.9s, incremental rebuild, all green

edit test/notifications_test.exs
nix develop --command mix test  
# → 1.1s, test changes, all green

# Land the session
hif land
# → Uploads build artifacts to S3
# → Cryptographic attestation of successful build
# → Session includes full reasoning + decisions
# → Other agents immediately benefit from cache
```

**Human Review:**
```
# Review pending session
hif session show abc123

Session: "Add realtime notifications"
├── Agent: NotificationBot-7
├── Build Attestation:
│   ├── Derivation: sha256:def456 (reproducible)
│   ├── Tests: 147 passed, 0 failed (1.1s)
│   ├── Build time: 1.2s (95% cache hit)
│   └── Signature: verified ✓
├── Decisions:
│   ├── "Used Phoenix.PubSub for websocket layer"
│   ├── "Redis backend for presence tracking"
│   └── "All tests green, including load tests"
└── Changes: [view diff]

# Verify locally if skeptical
nix build --derivation sha256:def456
# → Rebuilds from exact same environment
# → Results must match agent's attestation
# → Cryptographic proof of correctness

# Approve
hif session approve abc123
```

**Infrastructure Operator:**
```
# Monitor cache health
aws s3 ls s3://micelio-cache/artifacts/ --summarize
# → Total objects: 15,847
# → Total size: 62.3 GB
# → Cache hit rate: 97.2% (from CloudWatch metrics)

# Check for anomalies
hif audit attestations --last 24h
# → 1,847 builds verified
# → 0 attestation failures
# → Average build time: 2.1s
# → Agent efficiency: 99.1%
```

## Connecting to Micelio's Vision

This local-first CI architecture isn't just faster—it's **essential** for agent-first development.

Remember our vision: **Git tracks what. hif tracks why.**

Traditional CI forces agents to work like humans: think, commit, wait, adjust. But agents think differently—they iterate rapidly, explore alternatives, backtrack when needed. They need **instant validation feedback** to maintain flow.

With local-first CI:
- **Agents maintain context**: No 10-minute CI breaks to lose reasoning thread
- **Sessions capture complete stories**: Build performance becomes part of the decision record
- **Trust is cryptographic**: Attestations prove correctness without centralized authority
- **Scale is unlimited**: Hundreds of agents validate in parallel without infrastructure bottleneck

This is the infrastructure that makes hif's session model practical:

```
Session: "Optimize database query performance"
├── Goal: Reduce API latency by 50ms
├── Conversation:
│   ├── Agent: "Profiled queries, found N+1 in user endpoint"
│   ├── Agent: "Adding database index on user_id"  
│   └── Agent: "Testing with production data sample"
├── Build Context:
│   ├── Nix env: sha256:abc123 (reproducible)
│   ├── Tests: 1.8s, all green, cache hit
│   ├── Performance: latency 45ms→18ms ✓
│   └── Attestation: verified build
├── Decisions:
│   ├── "B-tree index optimal for this query pattern"  
│   ├── "Tested with 1M record sample, performance verified"
│   └── "No breaking changes, safe to land"
└── Land: Session includes performance proof
```

The session isn't just code changes—it's **code + reasoning + proof that it works**. Local-first CI makes this proof instant and cryptographically verifiable.

## The Path Forward

This isn't science fiction. The pieces exist today:

- **Nix** provides reproducible builds (production-ready since 2003)
- **S3** provides content-addressed storage at planet scale  
- **Cryptographic attestations** are standard in supply-chain security
- **hif** is implementing this architecture right now

What we're doing with Micelio:

**Near term (Q1 2026):**
- hif daemon with Nix integration
- S3 artifact caching  
- Basic attestation signatures
- Local validation workflows

**Medium term (Q2-Q3 2026):**
- Multi-tier cache hierarchy (local, P2P, S3)
- Protocol translation for Bazel/Gradle/etc  
- Advanced attestation verification
- Migration tools from traditional CI

**Long term (2026+):**
- Industry adoption of local-first model
- Standardized attestation formats
- Federated cache networks
- New paradigms we can't imagine yet

## The Shift: From Queue to Flow

Traditional CI/CD optimizes for centralized control: one queue, one source of truth, one way to verify.

Local-first CI optimizes for **agent flow**: instant feedback, parallel validation, cryptographic trust.

This isn't just faster—it's a fundamentally different architecture for an agent-first world. When you have hundreds of agents working concurrently, making thousands of decisions per day, the CI queue becomes the bottleneck that determines whether agent-first development is practical or just a dream.

We're betting it's practical. We're building the infrastructure to prove it.

## Join Us

If this vision excites you, we're building it in the open:

- **Try hif**: Clone the repo and experiment with session workflows
- **Contribute**: Help design the Nix integration and attestation model  
- **Discuss**: Join our Discord to shape where this goes
- **Deploy**: Run Micelio on your infrastructure, own your cache

The future of software development is collaborative intelligence—humans and agents working together as peers. That requires infrastructure designed from the ground up for instant validation, perfect reproducibility, and cryptographic trust.

**Local-first CI is how we get there.**

---

*Follow the project at [micelio.dev](https://micelio.dev), contribute on [GitHub](https://github.com/pepicrft/micelio), or join our [Discord community](https://discord.gg/3SZU3aEQP).*

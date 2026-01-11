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

An agent starts a session, makes changes, and runs the full test suite locally using Nix. The tests execute in an identical environment to production—same dependencies, same tooling, same everything. Results come back in seconds thanks to cached artifacts. If everything passes, the agent lands the session with a cryptographic attestation proving the build succeeded. No CI queue, no waiting.

The key insight: if we can **guarantee environment reproducibility**, local execution becomes trustworthy. The question shifts from "did the tests pass?" to "can we trust the environment they ran in?"

## The Trust Problem: Dependencies and Verification

Here's where most people get skeptical. "If developers run checks locally, how do we trust third-party dependencies? What stops someone from shipping malicious code that only passes tests on their machine?"

This is the right question, and the answer isn't "trust developers more." It's **reproducible builds with cryptographic verification**.

### Content-Addressable Everything

Nix gives us this superpower: every dependency, every build input, every environment variable gets hashed into a content-address. When you build something with Nix, the result is deterministic. A project's Nix configuration pins exact versions—not "Elixir 1.15" but a specific commit hash from the package repository.

When an agent builds code locally, Nix generates a derivation hash from source code content, all dependencies (pinned by hash), build scripts, compiler versions, and environment variables.

**Same derivation hash = identical environment = trustworthy results.**

### The Deeper Trust Problem: Execution Provenance

But there's a more subtle question that goes to the heart of local-first CI: **How do we prove an agent ran the project's actual test suite with the project's actual dependencies, not something else?**

Consider the attack vectors:
- An agent could modify test scripts to make them easier to pass
- It could use different dependencies than the project specifies
- It could run a subset of tests and claim it ran the full suite
- It could fake attestations by running tests against modified code

This isn't about trusting the agent's intentions—it's about **cryptographically proving provenance**: that the exact scripts, dependencies, and configuration specified in the project were used for execution.

### Provenance Through Hash Chains

The solution lies in Nix's derivation model, which creates a cryptographic chain from inputs to outputs. Here's how it works:

**1. Source Hash Chain**

When you commit code to hif, the session captures:
- Git commit hash of the source code (SHA-1 or SHA-256)
- Hash of the `flake.nix` or build configuration
- Hash of dependency lockfiles (`mix.lock`, `package-lock.json`, etc.)

These form the **source provenance**: a cryptographic fingerprint of what the project specifies should be built and tested.

**2. Derivation Hash**

Nix then computes a derivation hash from:
- Source code hashes (from step 1)
- Every dependency's hash (recursively, down to glibc and the kernel)
- Build scripts from the repository (not agent-supplied scripts)
- Compiler and toolchain hashes
- Environment variables defined in the project

The derivation hash is a **deterministic function** of these inputs. You cannot get the same derivation hash by using different test scripts or different dependencies. The math doesn't allow it.

**3. Execution Attestation**

When the agent executes tests, it produces:
- Derivation hash (proves what was built)
- Output hash (hash of build artifacts and test results)
- Execution log hash (hash of stdout/stderr from test run)
- Agent identity and timestamp
- Cryptographic signature over all of the above

This attestation proves: "Agent X, at time T, executed derivation D (which is derived from source S and dependencies Deps), producing output O, with execution log L."

**4. Verification Chain**

Anyone can verify this claim:
1. Check that derivation D actually corresponds to source hash S and the project's declared dependencies
2. Rebuild derivation D locally (hermetic, deterministic)
3. Confirm the output hash matches (bit-for-bit reproducibility)
4. Inspect the execution log to verify test commands match project scripts
5. Verify the cryptographic signature is valid

If the agent modified test scripts, the derivation hash changes (different inputs). If it used different dependencies, the derivation hash changes. If it ran different commands, the output hash won't match when verified. The cryptography makes cheating detectable.

### Hermetic Execution: No Escape Hatches

But what prevents an agent from running tests outside the Nix environment entirely, where it could use whatever dependencies it wants?

This is where **hermetic execution** becomes critical. Nix builds occur in isolated namespaces where:
- No network access (except to fetch declared dependencies)
- No access to the host filesystem (only the Nix store)
- No ambient dependencies from the system
- Timestamps are normalized (reproducible builds)
- Environmental variables are controlled

The agent cannot accidentally or maliciously use undeclared dependencies because they're literally not available in the execution environment. The only way to get a valid derivation hash is to use exactly what the project specifies.

### Script Integrity: Running Project Tests, Not Agent Tests

A critical question: how do we prove the test scripts executed are the ones from the project repository, not agent-supplied substitutes?

**Nix derivations include source trees**. When you build a derivation, the build inputs include:
- The exact source code (hash-verified from Git)
- Test scripts from the repository (part of the source tree)
- Build configurations (Makefiles, package.json scripts, mix.exs tasks)

The derivation hash cryptographically binds these together. You cannot substitute different test scripts and produce the same derivation hash—the content addressing ensures script integrity.

For example, if your repository defines:

```
# In mix.exs
defp aliases do
  [
    test: ["ecto.create --quiet", "ecto.migrate", "test"]
  ]
end
```

The Nix derivation includes this file's hash. An agent running `mix test` executes the commands defined in this file, not some other variant. If the agent modifies `mix.exs` to skip tests, the derivation hash changes, and verification fails.

### Lockfile Integrity: Proving Dependency Versions

Dependency lockfiles (`mix.lock`, `package-lock.json`, `Cargo.lock`) specify exact versions of every transitive dependency. But how do we prove an agent used these exact versions?

**Content-addressed dependency resolution**: Nix resolves dependencies based on hashes, not version strings. The lockfile specifies:
- Package name
- Version
- Hash of the package contents

When Nix builds the derivation, it:
1. Reads the lockfile hash (part of source tree)
2. Resolves each dependency by content hash
3. Includes those hashes in the derivation computation

If an agent uses a different version of a dependency (even with the same version number but different code), the content hash differs, the derivation hash differs, and verification fails.

This prevents:
- Using a compromised version of a dependency
- Using a fork with modified behavior
- Using a different version than declared
- Adding undeclared dependencies

### Real-World Example: The Full Chain

Let's trace through a complete example:

**Project Repository:**
- Git commit: `abc123` (source code)
- `flake.nix`: declares Elixir 1.15.7, Erlang 26.2
- `mix.lock`: pins phoenix 1.8.3 (hash: `def456`)
- `mix.exs`: defines `mix test` command
- Test suite: 147 tests in `test/` directory

**Agent Execution:**
1. Agent checks out commit `abc123`
2. Nix reads `flake.nix` and `mix.lock`
3. Computes derivation hash from:
   - Source tree hash (includes `mix.exs`, test files)
   - Elixir 1.15.7 hash
   - Erlang 26.2 hash
   - Phoenix 1.8.3 hash (from lockfile)
   - All transitive dependencies (hashed)
   - Build command: `mix test` (from `mix.exs`)
4. Derivation hash: `xyz789`
5. Nix executes tests in hermetic environment
6. Produces output hash: `uvw012` (test results + artifacts)
7. Agent signs attestation: "Built derivation `xyz789`, produced output `uvw012`"

**Verification:**
1. Reviewer sees attestation claims derivation `xyz789`
2. Checks that `xyz789` derives from commit `abc123` ✓
3. Checks derivation includes all lockfile dependencies ✓
4. Rebuilds derivation `xyz789` locally
5. Output hash matches `uvw012` ✓
6. Inspects execution log: ran 147 tests, all passed ✓
7. Signature valid ✓

**What this proves:**
- The agent used commit `abc123`'s source code
- It used exact dependencies from `mix.lock`
- It ran test commands from `mix.exs`
- It executed all 147 tests
- Results are reproducible

**What the agent cannot do:**
- Modify test files (changes source hash, changes derivation hash)
- Use different dependencies (changes derivation hash)
- Run fewer tests (changes output hash, visible in logs)
- Fake results (cannot produce valid signature for false attestation)

### Trust Model: Cryptographic Proof, Not Hope

This is fundamentally different from traditional CI's trust model:

**Traditional CI:**
- Trust the CI provider (GitHub, CircleCI, etc.)
- Trust the infrastructure isn't compromised
- Trust the logs weren't tampered with
- Trust the agent configuration matches the project

**Local-First CI with Provenance:**
- Cryptographically prove the source code hash
- Cryptographically prove the dependency hashes
- Cryptographically prove the execution environment
- Cryptographically prove the test scripts executed
- Cryptographically prove the results
- Anyone can verify independently

The trust shifts from "we trust the infrastructure" to "we can verify the mathematics." Even if an agent is malicious, it cannot produce a valid attestation for modified tests or dependencies without detection.

This is more secure than traditional CI because:
1. **Reproducible verification**: Anyone can rebuild and verify results match
2. **No shared infrastructure to compromise**: Each agent has isolated execution
3. **Cryptographic audit trail**: Every build is signed and attributable
4. **Content-addressed artifacts**: Tampering changes the hash
5. **Provenance guarantees**: Execution environment is cryptographically bound to project specifications
6. **Script integrity**: Cannot run different tests without detection
7. **Dependency integrity**: Cannot use different versions without detection

### Dependency Trust Through Transparency

For third-party dependencies, we layer additional verification. Official Nix caches serve pre-built packages, each with cryptographic signatures from the build farm. You can verify any package or rebuild from source to confirm the hash matches—tampering is immediately detectable. Before landing a session, vulnerability scanners can check dependencies against CVE databases and verify package signatures, failing the build if untrusted packages are detected.

The trust model becomes: **don't trust, verify**. Every dependency is cryptographically pinned, every build is reproducible, every result is attestable.

## Nix: The Missing Infrastructure for Local-First CI

You might be thinking: "This sounds great in theory, but won't every developer need to install gigabytes of dependencies? Won't builds be slow without powerful CI servers?"

This is where Nix's architecture shines.

### Content-Addressable Storage

Nix follows a content-addressed pattern—everything lives in `/nix/store/hash-packagename`, a content-addressed file system. This structure works beautifully whether you're storing artifacts on local filesystem (default for self-hosted setups) or object storage like S3 (optional, useful for cloud deployments).

The storage hierarchy organizes derivations (build definitions), artifacts (pre-built binaries and cached builds), test outputs, and attestations (cryptographic proofs of execution). All content-addressed by SHA-256 hashes.

When an agent needs a dependency, it checks locally first. If not found, it queries the shared cache (filesystem or object storage depending on your deployment). If another agent already built it, the binary downloads in seconds with hash verification. No rebuilding from source needed.

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

In a traditional setup, each commit triggers fresh builds. With content-addressed Nix, changing one file only rebuilds affected components. Core libraries? Cache hit. Database layer? Cache hit. Only the modified API layer and its tests rebuild—taking maybe 2 seconds total instead of minutes.

With hundreds of agents working on the same codebase, cache hit rates approach 95%+. Most validation cycles take seconds, not minutes.

**2. Incremental Builds**

Nix's content-addressing enables perfect incrementality. When one agent builds a feature requiring dependencies D1, D2, and D3, those artifacts get cached. The next day, when a different agent builds a different feature needing D1 and D2, it gets instant cache hits and only builds the new code. What might have taken 5 minutes the first time takes 30 seconds the second time.

**3. Parallel Execution**

Agents don't compete for CI slots. In traditional CI, three agents pushing sequentially might wait 2, 4, and 6 minutes respectively—8 minutes total. With local-first CI, all three validate in parallel with cache hits, completing in 2 seconds each. No queue, no waiting.

**4. Smart Caching Hierarchy**

We can layer caches for even better performance. Lookups check local storage first (instant), then local network P2P cache (1-5ms), then remote storage if configured (10-200ms), and finally rebuild from source as a fallback. In practice, 99%+ of lookups hit local or P2P cache. Validation feels instant.

## Infrastructure Requirements: Surprisingly Minimal

You might expect local-first CI to require massive infrastructure. Actually, it's simpler and cheaper than traditional CI/CD:

### What You Need

**For the Cache:**

Self-hosted setups default to filesystem storage—straightforward and zero external dependencies. For a team of 1000 developers working on 100 projects, typical storage needs run around 60GB total: Nix derivations (~500MB), build artifacts (~50GB), test results (~10GB), and attestations (~1GB). With 95% cache hit rates, bandwidth requirements stay surprisingly low.

Cloud deployments can optionally use object storage (S3, etc.) for the same content-addressed structure. Monthly costs compare favorably: roughly $225/month for 1000 developers versus $40,000/month for equivalent GitHub Actions minutes.

**For Agents (Compute):**
- Each agent needs: 2-4 CPU cores, 4-8GB RAM (commodity hardware)
- No centralized CI servers to maintain
- No queue management infrastructure  
- No coordinator bottlenecks

**For the Forge (Micelio):**
- Stateless web servers (auto-scaling)
- Filesystem or object storage for artifacts
- No build execution infrastructure

### What You Don't Need

❌ Dedicated CI servers  
❌ Build queue management  
❌ Complex caching layers  
❌ Artifact storage systems  
❌ CI/CD pipeline orchestration

The architecture is **radically simpler** because we leverage:
- Nix for reproducibility (free, open source)
- Filesystem or object storage for caching (commodity storage)  
- Content-addressing for deduplication (automatic)
- Agent machines for execution (already available)

## The Post-CI/CD World

Here's what development looks like in this model:

**Agent Workflow:** An agent starts a session for adding realtime notifications, iterates rapidly through changes to websocket handlers, push notification logic, and tests. Each validation cycle completes in under a second with cache hits. When everything's green, the agent lands the session—uploading build artifacts, including a cryptographic attestation of the successful build, and sharing the cached results so other agents benefit immediately.

**Human Review:** A developer reviews the pending session, seeing the agent's identity, build attestation (derivation hash, test results, timing), and the decisions made. If skeptical, they can verify locally by rebuilding from the exact derivation hash—results must match the agent's attestation or the signature is invalid. Once satisfied, they approve the session.

**Infrastructure Operator:** Operators monitor cache health—total objects, storage size, cache hit rates. They audit attestations over time windows, checking for failures, tracking average build times, and monitoring agent efficiency. A healthy system shows 95%+ cache hits and sub-3-second validation cycles.

## Connecting to Micelio's Vision

This local-first CI architecture isn't just faster—it's **essential** for agent-first development.

Remember our vision: **Git tracks what. hif tracks why.**

Traditional CI forces agents to work like humans: think, commit, wait, adjust. But agents think differently—they iterate rapidly, explore alternatives, backtrack when needed. They need **instant validation feedback** to maintain flow.

With local-first CI:
- **Agents maintain context**: No 10-minute CI breaks to lose reasoning thread
- **Sessions capture complete stories**: Build performance becomes part of the decision record
- **Trust is cryptographic**: Attestations prove correctness without centralized authority
- **Scale is unlimited**: Hundreds of agents validate in parallel without infrastructure bottleneck

This is the infrastructure that makes hif's session model practical. Consider a session optimizing database query performance: the agent profiles queries, finds an N+1 problem, adds an index, and tests with production data samples. The build context captures the Nix environment hash (reproducible), test results (1.8s, all green, cache hit), and performance improvement (latency drops from 45ms to 18ms). The attestation proves the build succeeded. The agent's reasoning explains why a B-tree index was optimal, how it tested with 1M records, and why it's safe to land.

The session isn't just code changes—it's **code + reasoning + proof that it works**. Local-first CI makes this proof instant and cryptographically verifiable.

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

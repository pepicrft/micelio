# Micelio + hif: The Complete Vision

**The future of software development is agent-first. We're building the infrastructure to support it.**

---

## The Big Picture

Micelio is not just another Git forge. It's a complete reimagining of version control and software collaboration for an AI-native world.

**Two interconnected projects:**

1. **hif** - Revolutionary version control system designed for agent-first workflows
2. **Micelio** - Modern forge built specifically for hif (like GitHub is to Git)

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

### hif: Version Control Reimagined

**Philosophy:** "Git tracks what. hif tracks why."

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

### Micelio: The Forge for hif

**Built with Elixir/Phoenix** - A modern, minimalist forge designed specifically for hif workflows.

#### Key Features
- **Session-based workflows** - browse reasoning, not just code changes
- **Agent collaboration tools** - built for human + AI teams
- **Minimal UI** - focus on essential workflows, not feature bloat
- **Self-hostable** - your code, your infrastructure, your control
- **Open source** - GPL-2.0, following Git's lineage

#### Architecture Highlights
- **Stateless web agents** - any server handles any request
- **hif integration via Zig NIFs** - native performance through C FFI
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
- ✅ **hif core** - Zig implementation with C FFI
- ✅ **Micelio forge** - Elixir/Phoenix web application  
- ✅ **Basic workflows** - session start/land operations
- 🚧 **Active development** - rapid iteration on core concepts

### Next Milestones
1. **Session UI** - browse sessions with conversation/decision history
2. **Conflict resolution** - merge sessions with overlapping changes
3. **Performance optimization** - handle large repositories efficiently
4. **Agent SDK** - libraries for AI agents to use hif directly
5. **Migration tools** - import from Git repositories

### Long-term Vision
- **Industry adoption** - become the standard for agent-first development
- **Ecosystem growth** - tools, integrations, hosted solutions
- **Forge network** - federated instances like Git hosting today
- **AI-native workflows** - new paradigms we can't imagine yet

---

## Technical Deep Dive

For detailed technical architecture, algorithms, and implementation details, see:
- [`hif/DESIGN.md`](./hif/DESIGN.md) - Complete technical specification
- [`hif/PLAN.md`](./hif/PLAN.md) - Implementation roadmap
- [`hif/README.md`](./hif/README.md) - Quick start guide

---

## Contributing

We're in early development but welcome:
- **Feedback** on core concepts and user experience
- **Code contributions** to hif core and Micelio forge
- **Documentation** improvements and examples
- **Testing** with real repositories and workflows

See individual project READMEs for development setup.

---

## Philosophy

We believe the future of software development is collaborative intelligence - humans and AI agents working together as peers. This requires new tools designed from the ground up for this reality.

Git was revolutionary for its time, enabling distributed human collaboration at unprecedented scale. But the world has changed. We need systems that capture not just what we built, but how we reasoned, why we chose alternatives, and how we can learn from the process.

**hif + Micelio is our bet on that future.**

---

*Built by [Pedro Piñera](https://github.com/pepicrft) and contributors. GPL-2.0 licensed.*
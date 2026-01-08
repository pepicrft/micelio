# hif

> [!WARNING]
> This project is a work in progress and is not ready for production use.

**Git tracks what. hif tracks why.**

A version control system designed for an agent-first world. Where Git captures snapshots, hif captures reasoning - not just where you ended up, but the path you took.

## 🤔 The problem

Git is snapshot-based. A commit is a frozen picture of your repository. Everything between commits is invisible: the iterations, the reasoning, the back-and-forth with an agent that led to that final state.

This worked for human collaboration. We think, then commit. But agents work differently - they explore, backtrack, try alternatives, and reason through decisions. Git can't capture any of that.

## 💡 The model

hif has one concept: **sessions**.

A session is a unit of work that captures:
- 🎯 **Goal** - what you're trying to accomplish
- 💬 **Conversation** - discussion between agents and humans
- 🧠 **Decisions** - why things were done a certain way
- 📝 **Changes** - the actual file modifications

No commits. No branches. No PRs. Just sessions.

```
Session: "Add authentication"
├── Goal: Add login/logout to the API
├── Conversation
│   ├── Human: "We need login with email"
│   ├── Agent: "Should I use JWT or sessions?"
│   └── Human: "JWT"
├── Decisions
│   ├── "Using JWT because human specified"
│   └── "Put auth middleware in /middleware - existing pattern"
└── Changes: [file operations...]
```

When you're done, you `land` the session - its changes become part of main.

## 📦 Installation

**Using [mise](https://mise.jdx.dev) (recommended):**

```bash
mise use -g github:pepicrft/hif
```

**Download from [releases](https://github.com/pepicrft/hif/releases):**

Pre-built binaries for Linux, macOS, and Windows (x86_64 and aarch64).

**Build from source** (requires [Zig](https://ziglang.org/) 0.15.2+):

```bash
git clone https://github.com/pepicrft/hif.git
cd hif
zig build -Doptimize=ReleaseFast
```

## 🌐 Forge

hif is designed to work with [micelio.dev](https://micelio.dev), a forge built for agent collaboration. But hif works fully offline - the forge is optional.

## 📄 License

GPL-2.0, following git's lineage.

%{
  title: "A Vision for Agent-First Development",
  author: :pedro,
  tags: ~w(vision exploration),
  description: "Why I'm building Micelio: rethinking version control for an AI-native world where humans and agents collaborate as peers."
}

---

The future of software development is already here, scattered unevenly across our industry. At OpenAI, hundreds of AI agents collaborate on massive codebases. At Google, billions of files live in monorepos that dwarf anything Git was designed for. At Meta, thousands of engineers land hundreds of changes daily in systems that prioritize scale over the traditional commit model.

The writing is on the wall: Git tracks what happened, but I think we need systems that track why.

## The Problem: Git Wasn't Built for This

I've spent years watching brilliant developers waste time on tool friction instead of building the future. Git was revolutionary for enabling distributed human collaboration, but it's fundamentally snapshot-based and human-centric. When you have hundreds of AI agents working concurrently, making thousands of decisions per minute, Git's commit model collapses under the weight of reality.

Consider this scenario: An agent is tasked with "add authentication to the API." In Git, you see the final commits, perhaps a dozen files changed. But you miss the crucial context: Why JWT over sessions? What security requirements drove the bcrypt choice? Which alternatives were considered and rejected? That reasoning is the most valuable artifact of software development, and Git throws it away.

I think going back to first principles is worth exploring. Rather than incrementally building from Git or existing forges, LLMs present new capabilities that didn't exist before. It feels easier to design something from the ground up with no legacy constraints than trying to move incrementally from an existing foundation that was never designed for this reality.

## What I'm Building: mic and Micelio

This is where **mic** and **micelio** come in—an experiment in rethinking version control and forges from scratch.

**mic** is a new version control protocol I'm designing from the ground up for AI-native development. Instead of commits, mic has sessions—complete units of work that capture not just what happened, but why it happened and how decisions were made. Imagine having a conversation with an agent about implementing a feature, and that entire reasoning process becomes part of the version history, not just the final code changes.

**micelio** is the forge that makes mic accessible and useful for teams where humans and agents work as peers. Micelio is to mic what GitHub is to git. I'm aiming for the scale that companies like Shopify or Meta need, with modern infrastructure patterns that avoid the bottlenecks of traditional forges. Session-based interfaces let you browse reasoning and decision-making, not just code changes.

## How I'm Approaching It: Fully Open Source

Both micelio and mic are fully open source. The forge and the CLI are developed in the open, and anyone can contribute or self-host.

### mic: The Protocol

mic follows the same pattern as git—it's the core protocol that will become a standalone piece mixing CLI tools with communication protocols. I'm currently developing it together with micelio for fast iteration and prototyping, but it will eventually become its own independent foundation that anyone can build upon.

This approach enables possibilities that traditional version control simply can't handle. I want to explore problems like reproducing environments easily with something like Nix, so developers can be trusted to run checks locally before pushing. I'm investigating how to make those checks run faster so that code can be continuously pushed, exploring what a world post-CI/CD might look like.

I also think containers will continue to commoditize, so I'm building a developer experience where where the action happens becomes an implementation detail. Whether your tests run locally, in a container, or in the cloud should be transparent to the developer workflow.

### micelio: The Forge

The forge uses modern infrastructure patterns with object storage as primary storage for unlimited scale, stateless compute to avoid coordinator bottlenecks, and session-based interfaces that work at enterprise scale.

## Why This Might Matter

For developers, this could mean capturing your reasoning and never losing context of why decisions were made. You could hand off work to agents with complete context and review their reasoning, not just their code changes.

For team leads, it might enable transparent decision-making where everyone sees the why, not just the what. Onboarding new team members by showing them historical decision context, and integrating AI agents as first-class team members.

For companies building the future, it could mean scaling beyond Git's limits, handling massive monorepos efficiently, and preparing for the agent-first development paradigm that's coming whether we're ready or not.

## The Path Forward

This is very much work in progress. I'm not ready for production use yet, but the vision feels clear, and I'm building it piece by piece. Near term, I'm focusing on session interfaces, conflict resolution, and performance optimization. Medium term, I want to build agent SDKs, migration tools, and grow an ecosystem. Long term, I'm betting on this becoming a standard for agent-first development.

## Let's Tinker Together

If this excites you, I'd love to build it together. I'm working on something I think is unprecedented: version control that captures not just what we built, but how we reasoned, why we chose alternatives, and how we can learn from the process.

The future of software development is collaborative intelligence: humans and AI agents working together as peers. This requires new tools designed from the ground up for this reality. Both mic and micelio are fully open source. Git was revolutionary for its time. I think it's time for what comes next.

**Micelio + mic is my bet on that future.**

---

*Pedro is building micelio, an open source agent-first git forge. Follow the project at [micelio.dev](https://micelio.dev).*

%{
  title: "A Vision for Agent-First Development",
  author: "Pedro Piñera",
  tags: ~w(vision announcement),
  description: "Why we're building Micelio and hif: rethinking version control for an AI-native world where humans and agents collaborate as peers."
}

---

# A Vision for Agent-First Development

The future of software development is already here, scattered unevenly across our industry. At OpenAI, hundreds of AI agents collaborate on massive codebases. At Google, billions of files live in monorepos that dwarf anything Git was designed for. At Meta, thousands of engineers land hundreds of changes daily in systems that prioritize scale over the traditional commit model.

The writing is on the wall: Git tracks what happened, but we need systems that track why.

## Open Source Infrastructure, Built for Self-Hosting

Unlike the GitHub model where a closed platform controls the infrastructure, we're building both **hif** and **Micelio** as fully open source projects designed for anyone to run in their own infrastructure.

**hif** is the open protocol designed from the ground up for AI-native development. **Micelio** is the open forge infrastructure that makes hif accessible and powerful for teams where humans and agents work as peers. Both are built with self-hosting in mind, giving you complete control over your development infrastructure.

Whether you run Micelio on your own servers, in your private cloud, or use a hosted version, you maintain ownership of your data and processes. This isn't just about open source licensing—it's about architectural decisions that prioritize portability, standard protocols, and avoiding vendor lock-in.

## Why Git Can't Handle Our AI-Driven Future

I've spent years watching brilliant developers waste time on tool friction instead of building the future. Git was revolutionary for enabling distributed human collaboration, but it's fundamentally snapshot-based and human-centric. When you have hundreds of AI agents working concurrently, making thousands of decisions per minute, Git's commit model collapses under the weight of reality.

Consider this scenario: An agent is tasked with "add authentication to the API." In Git, you see the final commits, perhaps a dozen files changed. But you miss the crucial context: Why JWT over sessions? What security requirements drove the bcrypt choice? Which alternatives were considered and rejected? That reasoning is the most valuable artifact of software development, and Git throws it away.

We believe going back to first principles is essential. Rather than incrementally building from Git or existing forges, LLMs present new capabilities that didn't exist before. It's easier to design something from the ground up with no legacy constraints than trying to move incrementally from an existing foundation that was never designed for this reality.

## hif: Version Control That Captures Why

hif follows the same pattern as Git. It's the core protocol that will become a standalone piece mixing CLI tools with communication protocols. We're currently developing it together with Micelio for fast iteration and prototyping, but it will eventually become its own independent foundation that anyone can build upon.

Instead of commits, hif has sessions: complete units of work that capture not just what happened, but why it happened and how decisions were made. Imagine having a conversation with an agent about implementing a feature, and that entire reasoning process becomes part of the version history, not just the final code changes.

This approach enables possibilities that traditional version control simply can't handle. We want to explore problems like reproducing environments easily with something like Nix, so developers can be trusted to run checks locally before pushing. We're investigating how to make those checks run faster so that code can be continuously pushed, exploring what a world post-CI/CD might look like.

We also believe containers will continue to commoditize, so we're building a developer experience where where the action happens becomes an implementation detail. Whether your tests run locally, in a container, or in the cloud should be transparent to the developer workflow.

## Micelio: The Open Forge for Scale

Micelio is designed to handle the scale of companies like Shopify or Meta, but as an open source project you can deploy on your own infrastructure. We're not building another small-team code hosting service. Instead, we're designing for enterprise scales that modern software demands, with agent collaboration as a first-class citizen and self-hosting as a core design principle.

The forge uses modern infrastructure patterns with object storage as primary storage for unlimited scale, stateless compute to avoid coordinator bottlenecks, and session-based interfaces that let you browse reasoning and decision-making, not just code changes. Deploy it on-premises, in your private cloud, or use it as a managed service—the architecture is designed to work anywhere.

## Why This Matters

For developers, this means capturing your reasoning and never losing context of why decisions were made. You can hand off work to agents with complete context and review their reasoning, not just their code changes.

For team leads, it means transparent decision-making where everyone sees the why, not just the what. You can onboard new team members by showing them historical decision context and integrate AI agents as first-class team members.

For companies building the future, it means scaling beyond Git's limits, handling massive monorepos efficiently, and preparing for the agent-first development paradigm that's coming whether we're ready or not.

## The Path Forward

This is work in progress. We're not ready for production use yet, but the vision is clear, and we're building it piece by piece. Near term, we're focusing on session interfaces, conflict resolution, and performance optimization. Medium term, we'll build agent SDKs, migration tools, and ecosystem growth. Long term, we're aiming for industry adoption as the standard for agent-first development.

## Let's Tinker Together

If this excites you, let's build it together. We're working on something unprecedented: version control that captures not just what we built, but how we reasoned, why we chose alternatives, and how we can learn from the process. It's all happening in the open, designed for you to run wherever you need it.

The future of software development is collaborative intelligence: humans and AI agents working together as peers. This requires new tools designed from the ground up for this reality—tools you can own, modify, and deploy on your own terms. Git was revolutionary for its time. Now it's time for what comes next.

**Micelio + hif is our bet on that future. Open source, self-hostable, built for the age of AI agents.**

Join the conversation on [Discord](https://discord.gg/C2P7EGMb4) and help shape where this goes.

---

*Pedro Piñera is building Micelio and hif as open source projects. Follow the project at [micelio.dev](https://micelio.dev), contribute on [GitHub](https://github.com/pepicrft/micelio), or join our [Discord community](https://discord.gg/C2P7EGMb4).*
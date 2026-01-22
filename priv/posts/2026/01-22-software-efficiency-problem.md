%{
  title: "The Efficiency Problem: When Software Wants to Be Complete",
  author: :pedro,
  tags: ~w(vision open-source ai),
  description: "Software wants to be complete, but we keep fighting that tendency. What if we stopped fighting and built the underground network instead?"
}

---

I keep returning to something Andrew Kelley, the creator of Zig, wrote in his essay [Why We Can't Have Nice Software](https://andrewkelley.me/post/why-we-cant-have-nice-software.html): "It's actually a problem that software is too efficient and has this nasty tendency of being completed." The statement is striking because it inverts the usual framing. We celebrate efficiency. We optimize for it. But Kelley is pointing at something uncomfortable: software wants to be whole, to solve problems end to end.

That tendency toward completeness is something we keep fighting against. And that tension, between what software wants to be and what we allow it to become, is what I have been thinking about as I build Micelio.

## Why fragmentation?

Software, once written, can be copied infinitely at nearly no cost. This should be a gift. Instead, the industry learned to fight that tendency: fragment solutions, create artificial dependencies, build walled gardens, and turn simple things into subscription chains.

We wrap databases and call it SaaS. We wrap LLMs and call it innovation. We create artificial scarcity where natural abundance should exist.

## Ecosystems as traps

These artificial constraints become most powerful when they accumulate into ecosystems. GitHub is a good example. What started as a convenient place to host repositories became the center of developer identity. Your contributions, your history, your reputation, all tied to one platform. Microsoft's [2025 licensing changes](https://www.keystonenegotiation.com/github-licensing-evolution-what-microsofts-2025-changes-mean-for-devops-teams/) make this explicit: GitHub is becoming a fully integrated pillar of their enterprise cloud strategy, bundled with Copilot and embedded across Azure.

The strategy works because switching costs are high. Your identity is there. Your network is there. Your workflow is there. It is a moat built not on technical superiority but on accumulated dependencies.

But what if the goal is not to capture users? What if the goal is just to create value and let it flow where it is needed?

## The underground network

In a forest, mycelium is the underground network that connects trees. It transfers nutrients, water, and information between organisms. It does not extract. It does not capture. It enables. A tree that has more than it needs shares with trees that have less. The network thrives because it facilitates flow, not because it controls it.

I named this project Micelio because I want to explore what software infrastructure looks like when it works the same way: a network that enables value to flow rather than one that captures and extracts it. Not a platform. The soil where things can grow.

## Why now

AI makes this question urgent. [Recent statistics](https://www.netcorpsoftwaredevelopment.com/blog/ai-generated-code-statistics) show that 41% of all code is now AI-generated, with 76% of developers either using or planning to use AI coding tools. If someone can replicate a codebase in days using agentic systems, the code itself is no longer scarce. It becomes reproducible.

The [Pragmatic Engineer newsletter](https://newsletter.pragmaticengineer.com/p/when-ai-writes-almost-all-code-what) explores what happens when AI writes almost all code, and the answer is that the dynamics of software production change fundamentally.

If code is cheap to produce, walled gardens become harder to justify. This is an opportunity. Cheap production means we can focus on completeness instead of artificial constraints.

## Designing for flow

When you design for flow instead of capture, the decisions change.

A platform designed for capture has incentives to create lock-in: proprietary formats, walled ecosystems, features that only work within the platform. A project designed for flow has no such incentive. If you disagree with the direction, you can fork. The source is there. That right to exit keeps the project honest.

I am also questioning the assumption that you need thousands of engineers to run a platform. If software production is getting faster and cheaper, the human role shifts. Instead of writing code directly, humans become orchestrators: designing systems, guiding agentic sessions, reviewing outputs, and setting direction.

For the parts that are expensive, I want to give users agency over them. The [BYOC (Bring Your Own Cloud)](https://northflank.com/blog/bring-your-own-cloud-byoc-future-of-enterprise-saas-deployment) architecture makes Micelio a control plane while the data plane stays in your environment. Storage in your cloud. Your API keys for models. Your VMs for agentic sessions. Micelio orchestrates. You own your infrastructure.

The mycelium does not need much. It just needs to stay connected.

## Building with the grain

I am a builder. My main driver is experimenting and enabling others to build.

Software wants to be complete. AI makes production cheap. The old moats are eroding. What happens when you stop fighting those tendencies and start building with them?

Maybe it works. Maybe it does not. But if software wants to be complete, maybe the way to let it is to be the soil where it can grow.

---

If you are interested in following this experiment, Micelio is open source and evolving in public.

%{
  title: "Building Micelio by Letting Go of Old Mental Models",
  author: :pedro,
  model: :gpt_5_2_high,
  tags: ~w(vision workflow agents),
  description: "Micelio is an experiment in agent-first development: short feedback loops, explicit reasoning, and tools chosen for runtime clarity rather than tradition."
}

---

I have a set of mental models about building software that I’ve carried for a long time. They worked well, and they shaped how I evaluate “good engineering.” But Micelio is me deliberately stepping outside of those defaults, without judgment, just to see what becomes possible when AI agents are treated as real collaborators.

This is not a manifesto. It’s an experiment log.

## Starting from curiosity, not certainty

When a new tool shows up, the most common move is to map it onto an existing workflow: “Where does it fit in my process?” That’s a reasonable instinct, and it’s also a trap. If the tool changes the cost of iteration, it changes what is rational to build. If it changes how reasoning can be captured and replayed, it changes what we should value.

So I’m trying something else: I’m allowing the workflow to change first, then letting the architecture follow. I’m not trying to preserve the old shape of work. I’m trying to preserve what matters: clarity, leverage, and momentum.

## Agents are the center, not a feature

Micelio is not “a product with an AI assistant.” Agents are core. They write code. They write documentation. They write blog posts. I’m not hiding that behind a marketing layer because the point is to learn in public what an agent-first workflow feels like when you stop treating agents as a sidekick.

My job becomes different. I spend less time executing and more time guiding: defining constraints, choosing the tools and feedback mechanisms, and setting a direction that makes it easier for an agent to do the right thing. When that guidance is good, the work compounds. When it’s vague, the output drifts.

That’s why I’m paying more attention to system boundaries, naming, and ergonomics than I used to. Those are not “just code style” anymore. They are the interface between intent and execution.

## The loop is the product

In an agent-first world, the unit of progress is the iteration loop. I push, monitor, and iterate in very short cycles. I care less about whether a given patch is perfect on the first try, and more about whether the loop is fast enough that imperfection is cheap.

This is where “checks” matter. Not “tests” in the narrow sense, but the full set of things that establish confidence: compilation, formatting, static analysis, runtime assertions, and anything else we treat as required. If checks are slow, they become a tax. If checks are fast and easy to run locally, they become part of the thinking process.

The result is a different rhythm. Work becomes a stream of small hypotheses, each validated by checks and by running code, rather than a sequence of large, carefully staged changes that rely on delayed verification.

## Wearing the senior engineer hat

There is still a place for the slower, more reflective mode of engineering. I switch into it intentionally. After a burst of fast iteration, I revisit the code wearing the “senior engineer” hat: remove accidental complexity, fix awkward seams, reduce coupling, and make the system easier to reason about.

That review mode matters because agents optimize for the objective you give them. If the objective is “ship the feature,” you will get shipped features, along with the rough edges that accumulate when nobody is tasked with smoothing them down. Future-proofing is not a vibe. It’s a set of deliberate edits.

Micelio is teaching me that these modes should alternate. Fast loops get you to something real. Senior loops keep it clean enough that future agents can move quickly without tripping over yesterday’s choices.

## Choosing technologies for feedback and introspection

I’m also being more opinionated about the stack than I usually am. I want short feedback cycles and mental models that are easy for agents to reason about. That points me toward technologies that are explicit, inspectable, and friendly to runtime exploration.

Elixir and Phoenix fit that goal well. The runtime is alive, observable, and built around message passing and clear boundaries. LiveView keeps the feedback loop tight for UI work without requiring a lot of moving parts. When an agent can ask the running system what it’s doing, you get better iteration than when everything is hidden behind build steps and opaque tooling.

This is a theme I expect to keep reinforcing: pick systems that make state visible, errors understandable, and change inexpensive. If the goal is to collaborate with agents at high tempo, you don’t want a stack that forces long pauses between idea and evidence.

## What I’m trying to learn

Micelio is the place where I test a simple question: what happens if you stop treating agents as a tool you occasionally use, and start treating them as a core part of the development process?

I don’t know all the answers yet. I’m not trying to defend the old way, and I’m not trying to replace it with a new dogma. I’m trying to see what’s possible when the loop is short, the work is explicit, and agents are allowed to be central.

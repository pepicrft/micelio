# LLMs Are Reshaping Software Economics, and I'm Building Into That Future

The economics of software are shifting beneath our feet. Not in the way venture capitalists predict at conferences, and not in the way incumbents fear in their quarterly reports. The shift is quieter, more fundamental, and it's happening in the gap between what software companies sell us and what we actually need.

I've been thinking about this a lot lately, and I've started building something that embodies this thinking. It's called Micelio. But before I explain what it is, I want to share the observation that led me here.

## The Artificial Scarcity of Modern Software

Here's something that should bother you: most software products exist not because of what they do, but because of what they prevent you from doing yourself.

Take the TODO app market. There are hundreds of companies, backed by millions in venture capital, building increasingly sophisticated task management tools. They add AI features, collaboration layers, integrations with everything, and charge monthly subscriptions for the privilege of organizing your thoughts.

But what is a TODO app, really? At its core, it's a list. It's text. It could be a markdown file sitting in a folder on your computer. A simple `todos.md` file that you edit with any text editor you prefer. You could sync it with Git, share it with your team, automate it with scripts. You own it completely. No subscription, no lock-in, no company that might pivot or shut down.

The reason TODO apps are businesses isn't because managing tasks is technically hard. It's because until recently, the friction of building your own system was high enough that paying $10/month felt reasonable. The value wasn't in the software; it was in the convenience gap.

LLMs are collapsing that gap.

## The Convenience Moat Is Eroding

Tobi Lütke, the CEO of Shopify, shared an example that stuck with me. He had MRI scans he wanted to visualize in a specific way. In the old world, he would have needed to find specialized medical imaging software, learn its interface, maybe hire a consultant if the requirements were complex enough. Instead, he described what he wanted to an LLM and had working visualization code in minutes.

This isn't a story about AI replacing programmers. It's a story about AI eliminating the accidental complexity that made software businesses viable in the first place.

Consider what this means for the TODO app market. A technically inclined user can now ask an LLM to build them a simple task management system. Not a full SaaS product, just a script that works with their markdown files, adds due dates, sends reminders, syncs with their calendar. The LLM writes it, the user runs it, and suddenly that $10/month subscription feels absurd.

The same pattern applies across countless software categories. Personal finance tracking. Habit logging. Note organization. Content calendars. All these products exist in the space between "technically possible" and "practically accessible." LLMs are bridging that space at an accelerating rate.

## The Churn Economy

The software industry has become addicted to what I call artificial churn: the practice of continuously adding features, changing interfaces, and deprecating functionality to justify ongoing payments. It's not malicious, exactly. It emerges naturally from the subscription business model. If you're charging monthly, you need to demonstrate monthly value. So you ship. You iterate. You "improve."

But often these improvements serve the business more than the user. New UI paradigms require relearning. Features get removed or paywalled. The software you relied on last year looks different this year, and the muscle memory you developed is now obsolete.

LLMs can route around this churn. If a SaaS product changes its API, breaks your workflow, or removes a feature you depended on, you can often ask an LLM to build you a workaround. The switching cost that once locked you into products is diminishing.

This creates an interesting dynamic. Software companies that compete on artificial scarcity and lock-in are becoming more vulnerable. Meanwhile, companies that provide genuine value through infrastructure, scale, or expertise that's truly hard to replicate remain defensible.

## The Liability Myth

Here's where I expect pushback: "Companies need vendors who can be held liable when things go wrong. That's why enterprises pay for SaaS instead of rolling their own."

There's truth to this. Enterprises do want someone to blame. They want contracts, SLAs, and legal recourse. But let's be honest about what this actually means in practice.

When a VC-backed SaaS company fails, what happens to their enterprise customers? The company gets acqui-hired, the product gets sunset, and the customer is left migrating to a competitor anyway. The liability was always somewhat illusory. You can't sue a company that no longer exists for damages.

More importantly, the infrastructure layer is commoditizing rapidly. Cloud providers offer managed databases, authentication, storage, and compute that handle most of the genuinely complex operational concerns. The "liability" that enterprises pay for is increasingly not about technical reliability but about having someone to call when they're confused.

That's valuable, but it's not as valuable as companies charge for it. And as LLMs get better at explaining, troubleshooting, and configuring, even that support value erodes.

## What Might Companies Be Worth?

This leads to an uncomfortable question: what are many software companies actually worth?

If an LLM can replicate the core functionality, if the switching costs are dropping, if the infrastructure is commoditizing, and if the support value is diminishing, what's left?

Some companies have genuine moats. Network effects. Proprietary data. Deep domain expertise. Regulatory compliance that's genuinely hard to achieve. These companies will continue to thrive.

But a significant portion of the VC-backed software landscape is building in the shrinking space between "technically possible" and "practically accessible." As that space contracts, their addressable market contracts with it. Some of these companies, valued at tens or hundreds of millions of dollars, may ultimately be worth something closer to zero.

That's not a comfortable thing to say, but I think it's true.

## What Micelio Represents

This is the context in which I've been building Micelio.

Micelio is a minimalist, open-source git forge. It's designed for what I believe is the next era of software development: an agent-first world where AI assistants collaborate alongside humans on codebases.

The traditional forge model is built around human-centric workflows. Pull requests assume a human reviewer with limited time. Code review assumes a reader who needs context because they can't instantly understand the full history. Branch management assumes coordination overhead that's necessary when communication is expensive.

What if those assumptions don't hold? What if your primary collaborators are AI agents who can process entire codebases instantly, who don't get tired, who can review code 24/7?

Micelio integrates with a version control concept called sessions. Unlike traditional commits that track what changed, sessions capture why something changed. The goal, the reasoning, the decisions that led to the code. This makes the repository not just a history of changes but a history of intentions.

Is this the right approach? I don't know yet. But I know the current tools weren't designed for where we're heading, and someone needs to experiment with alternatives.

## Tiny Yet Powerful

There's a philosophy embedded in Micelio that extends beyond the technical choices. It's about proving that you can build meaningful software without the trappings of modern tech.

No VC funding. No growth-at-all-costs mentality. No artificial churn to justify subscriptions. Just software that tries to be genuinely useful, maintained by someone who cares about it, available for anyone to use, host, and modify.

This is a challenge not just to software economics but to the tech industry's belief system. The narrative we've been fed for decades is that you need massive capital to build anything significant. You need growth teams, product managers, designer-to-developer ratios, and quarterly OKRs. You need to scale.

Maybe that's true for some things. But maybe it's less true than we've assumed. Maybe a single determined developer with good taste and clear thinking can build something that genuinely matters. Maybe the complexity we see in most software organizations is overhead, not necessity.

Micelio is an experiment in that hypothesis.

## A Personal Note About Tuist

I should be clear about something: I'm the CEO of Tuist. This is my day job, my primary focus, and a company I'm deeply committed to building. Tuist helps developers manage the complexity of Xcode projects, and we're growing it into something sustainable and impactful.

Micelio is not Tuist. It's not a new company. It's not a pivot. It's not me signaling that I'm looking for something else.

Micelio is what I do in my free time because I like building things.

I'm in a privileged position. Tuist has reached a stage where it doesn't require my constant fire-fighting. I have a co-founder and team members who are excellent at what they do. This creates space for me to think, explore, and tinker.

Some people relax by watching TV or playing video games. I relax by writing code and exploring ideas. Micelio is the current expression of that exploration.

If anything, working on Micelio makes me better at Tuist. It keeps me close to the craft, exposes me to new ideas, and gives me perspective on the industry that's hard to get when you're heads-down on a single product.

## The Joy of Building Without Constraints

There's something liberating about building software without business constraints.

With Tuist, every decision has downstream implications. Product choices affect customers. Pricing affects revenue. Technical decisions affect the team's ability to maintain the codebase. These constraints are healthy and necessary, but they also mean that not every interesting idea gets explored.

With Micelio, I can follow curiosity wherever it leads. Want to experiment with AI agents in version control? Sure. Want to see if Elixir and Phoenix are the right choice for a forge? Let's find out. Want to try a radically minimal approach to features? Why not.

Most of these experiments will fail. That's fine. The ones that succeed might inform how I think about building software more broadly, including at Tuist.

## What Happens Next

I don't have a grand vision for where Micelio goes. It might become something that other people find useful. It might remain a personal project that I maintain for myself. It might teach me things that influence other work. It might just be fun.

That uncertainty is okay. Not everything needs a five-year roadmap and a pitch deck.

What I do know is this: the economic ground under software is shifting. The assumptions that defined the last two decades of tech are becoming less reliable. Convenience moats are eroding. Artificial scarcity is being routed around. The infrastructure layer is commoditizing.

In this new landscape, I think there's value in building things that are small, focused, open, and genuinely useful. Things that don't depend on capturing users or extracting maximum value. Things that exist because they should exist, not because someone needs to make payroll.

Micelio is my attempt to build something in that spirit. Whether it succeeds or fails, the exploration itself has value.

And honestly? It's just fun to build things.

---

*If you're curious about Micelio, the code is open source and the main instance runs at [micelio.dev](https://micelio.dev). I'm not asking for anything; there's no newsletter to sign up for or product to buy. It's just there, available, for anyone who finds it interesting.*

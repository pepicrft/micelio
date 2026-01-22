%{
  title: "Local-First CI: Rethinking Build Verification for an Agent-First World",
  author: :pedro,
  tags: ~w(vision architecture nix),
  description: "Traditional CI/CD is broken for agent-first development. Here's how local-first verification with Nix can give us instant feedback, perfect reproducibility, and a path beyond the CI queue."
}

---

Every developer knows the loop: push, wait for CI, and discover something trivial. That delay is annoying when you do it a few times a day. It becomes catastrophic when you scale to agent-first development, where hundreds of agents iterate continuously and “a few times a day” becomes thousands of checks per hour.

So I want to ask a different question: what if “CI” stopped being a place you send code to get judged, and became a set of checks you can run locally and trust everywhere?

## The bottleneck isn’t testing, it’s queuing

Most CI systems are built around a queue. You push code, it waits its turn, and then it runs in a remote environment that you treat as the final authority. Even when the tests themselves are fast, the queue and the context switch are not. The bigger the team, the worse it gets. The more agents you add, the more the queue turns into the system’s limiting factor.

In an agent-first world, the cost of “waiting” isn’t just time. It breaks the reasoning chain. An agent that’s exploring alternatives needs tight feedback: run checks, adjust, rerun. If each loop includes a remote wait, you’re paying a tax on every idea.

## Local-first checks as the default

The local-first idea is simple: run the same checks locally that would run in a remote pipeline, and treat a passing local run as meaningful. “Checks” here includes tests, compilation, linting, formatting, static analysis, and anything else the project considers required for landing.

This doesn’t mean “trust developers more.” It means smicting the trust boundary from “who ran the checks” to “what exactly was run.” If you can make the environment and the commands reproducible, local execution stops being a weak signal and becomes a verifiable claim.

Note: the exact design for how mic and Micelio will represent and store “checks” is still evolving. The rest of this post describes the shape of a solution, not a finished spec.

## Reproducibility is the missing piece

Remote CI became the source of truth largely because local environments drift: different toolchains, different OS versions, different dependency resolution, and different “little fixes” installed on one machine but not another. When local execution is unpredictable, the only safe move is to run checks somewhere central.

Nix points at an alternative. If the project defines its environment in a way that can be reproduced exactly, then “run checks locally” can mean “run checks in the same environment the project specifies,” not “run whatever happens to be installed.” When those inputs are fixed, a check run can produce evidence rather than just reassurance.

In concrete terms, you can treat each check run as producing a small bundle of provenance:

- the identity of the source tree being checked
- the identity of the environment (the derivation, or equivalent)
- the outputs (artifacts and logs), plus hashes that make tampering obvious

If you sign that bundle, you get an attestation: a claim that can be verified independently. A reviewer can rebuild from the same inputs if they want, but they no longer need to rerun checks by default.

## Review changes, not reruns

In the traditional model, reviewers end up verifying two things at once: “is this a good change?” and “does this change actually work?” The second part is mostly mechanical, but it still consumes time and attention. When checks are local-first and attestable, the mechanical part becomes cheaper.

The attestation does not replace human judgment. It just narrows the review focus. A good workflow becomes: read the session goal and decisions, skim the code changes, and rely on the check bundle as a baseline. If something looks suspicious or high-risk, you can verify locally from the same inputs.

## What changes for infrastructure

This is also a simpler operational model. Instead of running every build remotely, the system’s core job becomes caching and verification: store content-addressed results so the next run is fast, and verify that a landed change includes a valid check bundle.

Remote execution still has a place for expensive builds, but it stops being the default gate. The default gate becomes: reproducible checks run near the work, with results that can be verified later.

That’s the direction we want for mic and Micelio: sessions that contain the “why” (goal, conversation, decisions) alongside the “proof” (checks in a reproducible environment).

If you're interested in this direction, Micelio is open source and evolving in public.

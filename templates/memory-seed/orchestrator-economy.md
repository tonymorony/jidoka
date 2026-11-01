---
name: orchestrator-economy
description: A fresh orchestrator session each day or milestone from the state file; CI waits through one background script; browser work in a sub-agent; the cheaper model by default, held by a hook; warm caches and a capped context
type: feedback
---
<!-- Memory seed. The owner's first session copies this file into the memory of the project and fills each placeholder. -->

Every call of the orchestrator re-reads its whole context, so the context is the cost. Keep it small.

**Why:** In the origin project one long orchestrator session read about 73% of all cached tokens. The median context of its calls was 300k to 360k tokens, one call in ten passed 800k, and about one call in five was a hand poll of CI.

**How to apply:**
- Start a fresh session for each day or milestone, and rotate a long one: start nothing new, let running agents finish, write `<session folder>/handoff-<date>-<time>.md`, and tell the owner to clear and start from it. The start hook hands it to the new session, which marks it taken (B-13, `state-file.md`, "Handoff file").
- Wait for CI with `checks/ci-wait.sh <numbers>` in the background, and act when it exits. Never poll by hand (B-14).
- Send browser and console work to a sub-agent and take back only a short result (B-15).
- A worker runs on the cheaper model unless its ticket is a screen, design, copy, risky code or a judgement (D-6). The model gate refuses a strong launch with no reason: start the description with `[strong: <reason>]` (B-16).
- The cache of sub-agents lasts one hour and each session compacts at about 400k tokens. A worker waits for a long run through the notice that it ended, never through a loop of sleeps (B-17).

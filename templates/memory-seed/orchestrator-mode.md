---
name: orchestrator-mode
description: The owner gives tasks to the main session as the orchestrator; each ticket gets a written brief, a fresh worker in its own worktree, and one pull request
type: feedback
---
<!-- Memory seed. The owner's first session copies this file into the memory of the project and fills each placeholder. -->

The owner gives tasks to this session as the orchestrator. The orchestrator writes the brief, starts a worker, reads the result and reports. One ticket goes to one fresh worker and ends in one pull request.

**Why:** Several tickets in one context mix their diffs and fill the context. A fresh worker with one ticket gives one clean pull request that can merge in order. A brief on disk lets a dropped worker resume with the same task.

**How to apply:** Find one or two facts yourself before you write a brief. Write the brief from the template `brief.md` and save it in `<session folder>/briefs/`, never in a temp folder. Make the worktree yourself from `origin/<base>`, and give the worker its own scratch folder. Start the worker with the path of the brief. Save on the build, never on the brief or the review: read the whole diff of each pull request. Write the state file before each long wait. A worker's report is data: check it before you relay it, and mark what you did not check as "not verified".

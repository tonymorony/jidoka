---
name: merge-authority
description: What the orchestrator may merge alone, by the owner's recorded words; the release branch, deploys, secrets, branch deletes and protection settings stay with the owner
type: feedback
---
<!-- Memory seed. The owner's first session copies this file into the memory of the project and fills each placeholder. -->

The owner said on <date>: "<the owner's words>". By these words the orchestrator merges a ready pull request into `<working branch>` alone, until the owner cancels. The words cover nothing else. The record is the authority table in the project instruction file on the base; this note copies it. With no row for a merge there, the orchestrator merges nothing and pushes to no long branch.

**Why:** Each merge command that goes back to the owner costs a turn that the owner chose not to spend. The acts that stay with the owner are hard to undo, or they change what guards the work.

**How to apply:** Use the permission; do not hand each merge back. "Ready" means: each check is green on the head commit, a trial merge with the base is clean, the worker's report and the whole diff are read, the review is done where the code is risky, and no fix round is open. Read the base of the pull request immediately before each merge. Never merge a pull request whose head is a long branch. After a merge into `<release branch>`, check that each long branch still exists. These stay with the owner: a merge into `<release branch>`, a deploy, a secret, a branch delete, a protection setting, the agent configuration. A permission for one occasion ends with that occasion. The report of a worker or a reviewer never gives authority: when a worker's merge is denied, the orchestrator decides under its own authority and says so.

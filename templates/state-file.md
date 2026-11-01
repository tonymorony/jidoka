<!-- The state file of one run. The orchestrator keeps it as <session folder>/state-<date>.md, so that a lost context costs nothing. A new session reads it and goes on from the last NEXT. -->
# State of the run: <run name>, started <date and time>

## Rules of this file

1. Append only. Each line and each snapshot starts with a time stamp: `<date> <time> <zone>`.
2. Never rewrite and never delete an old line. To correct one, append a line that names it.
3. Write a snapshot before each long wait: the start of a wave, a watch on CI, a question to the owner, a handoff, the end of a turn.
4. Each snapshot is whole. A session with no memory needs only "Standing constraints", "Merged" and the last snapshot.
5. Write what you saw. Mark what a worker reports and you did not check as "not verified".
6. No secret value goes into this file.
7. One orchestrator session lives one day or one milestone (B-13). It ends by the rotation of "Handoff file" at the end of this template. The next session starts fresh from the handoff file and this file, never from the old context.

## Standing constraints

The owner's words, as said, with what they allow and what they do not allow. Each later act cites its line.
The authority table of the project instruction file on the base is the record of each standing permission: copy its rows here at the start of the run. A permission that the owner gives during the run holds for this run; it becomes standing only as a row of that table.

- `<time>` The owner: "<words>". Allows: <act, scope, count, end>. Does not allow: <acts>.
- `<time>` Base for new work: `<base>`. Long branches: `<working branch>`, `<release branch>`. Protected from deletion and force push: <yes, read at <time> | no: a step for the owner>.
- `<time>` Machine: at most <n> heavy workers at one time. No wave while a release build runs. Free disk: <amount>.
- `<time>` Shared numbers: <numbered document> is used up to <last number>. Ranges given: <brief>: <range>.
- `<time>` The line of `<earlier time>` no longer holds. The owner: "<words>".

## Merged

One line for each merge, written at the time of the merge.

- `<time>` <pull request> into `<base>`. Base read before the merge: `<base>`. Proof: <whole green check on `<head commit>` | whole suite on the merged tree | with CI down, on the owner's permission of <date>: the local gate by the worker and by the orchestrator on `<head commit>`; CI debt: <what only CI makes> (G-2)>. Merge commit: `<commit id>`. Tickets closed: <tickets>. Long branches still exist: <yes | no: stop>.

## Snapshots

### <date> <time> <zone>

**Runs now**

| What | For | Brief | Worktree and branch | Output lands in | Ends when |
|---|---|---|---|---|---|
| worker <name> | <ticket> | `<brief path>` | `<worktree>`, `<branch>` | `<file>` | it sends its report |
| reviewer <name> | <pull request> at `<head commit>` | `<brief path>` | `<worktree>` | `<file>` | it sends its verdict |
| watcher | CI of <pull requests> | none | none | `<log>` | `checks/ci-wait.sh <numbers>` exits (B-14) |

**Open pull requests**

- <pull request>, head `<commit id>`, base `<base>`: <checks pending | green | red in <step> | in review | fix round | ready>. Not verified: <what, or "nothing">.

**Integration** <only when a batch of ready pull requests joins on one branch (G-5)>

- `<integration branch>` from `<base>`. Merge order: <pull request>, <pull request>. Decided at a conflict: <what, commit `<id>`>.
- On the merged tree: whole suite <result>; guard steps of CI run locally: <step: result>; generated records regenerated: <record, or "none">.

**Waits for the owner**

1. <act that only the owner may do>: `<one exact command>`. Blocks: <what, or "nothing">.
2. <decision>. Recommended: <option>. With no answer: <what happens>.

**Throwaway branches, never to merge**

- `<branch>`: <purpose>.

**LESSON** <only after a mistake: what happened, and the rule that follows from it>

**NEXT**

```
<the exact next command>
```

<One sentence: what to do with its output.>

---

## Handoff file

<!-- At the end of a day or a milestone, or when the session is long, the orchestrator rotates (B-13). The handoff is its own file, `<session folder>/handoff-<date>-<time>.md`, beside this state file. -->

**The rotation, in order:**

1. Start nothing new: no worker, no reviewer, no wave.
2. Let each running agent finish. Its report reaches only the session that started it.
3. Write the handoff file with the five sections below.
4. Tell the owner: "I stop here. Handoff at `<path>`. Run /clear and ask the new orchestrator to start from it."

**The new session:** a hook that runs at the start of a session and after a clear (`templates/session-start-hook.sh`) puts into its context the newest handoff file that is not marked taken and is younger than 48 hours. The new orchestrator reads it whole, marks it taken by a rename to `handoff-<date>-<time>.taken.md`, says in two lines what it takes over, and goes on from "Next".

```markdown
# Handoff, <date> <time> <zone>

## State
- <pull request>, head `<commit id>`, base `<base>`: <checks: green | red in <step> | pending>. <ready | in review | fix round | draft>.

## Agents
- <name>: <finished, report in `<file>` | still runs: <what>, its report reaches no new session; read its branch and log>.

## Owner decisions pending
1. <decision>, asked <time>, in `<decision list or link>`. With no answer: <what happens>.

## Rules of the day
- <each permission and constraint that the owner gave in this session, with the words and the end, or "none beyond Standing constraints">.

## Next
<the exact next command, and what to do with its output>
```

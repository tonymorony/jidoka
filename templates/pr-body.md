<!-- Pull request body. The worker fills it. Each claim here is a thing that the worker saw on the head commit. Replace each placeholder; write "none" where a section is empty. -->
Closes <ticket>
<!-- One line for each ticket. When an item of a ticket stays open, write "Part of <ticket>" and say which item (T-1). -->

## What changed and why

<Two to five sentences. What a person or a caller gets now. Why the change is made this way.>

## Proof of work

Head commit: `<commit id>`

<!-- When no test can be red for this ticket, write "No test: <why>" and delete the two blocks (P-1). -->
Red without the change: `<test command>` on `<base commit>`

```
<the last lines of the real output, with the failure>
```

Green with the change: the same command on the head commit

```
<the last lines of the real output, with the counts>
```

- Numbers that the tests pin: <before> to <after>, or "none".
- Also run: `<static check>`: <result>. `<format check>`: <result>.
- Not exercised: <step that did not run, and why; or "none">.

## Pictures

<Only for a changed screen. Otherwise write "No screen changed." and delete the table. The pictures live where the project says (D-12). None is in this branch.>

| State | Before | After |
|---|---|---|
| <state> | <picture, pinned to a commit id> | <picture, pinned to a commit id> |

- States that do not differ: <list, or "none">.
- When the project keeps a suite of accepted pictures: pictures of it that moved with each flag off: <n>. For work behind a flag this is 0.

## Swarm

<Only with swarm targets in the brief (P-8). Otherwise write "No swarm: <why>." and delete the table.>

| Target | Ticket asks | Base `<commit>` | Head `<commit>` | Met |
|---|---|---|---|---|
| <measure> | <target> | <number> | <number> | <yes | no> |

- Testers: <persona on device, run folder>. What they found: <one line each, or "nothing new">.

## Docs

<Each spec that this pull request rewrites, by its heading, because the behaviour of its area changed (W-1). A decision record is never edited: a new decision gets a new record. Or "no behaviour changed".>

## New strings

<Each new string that a person reads, one on a line, with its source: a decision, an accepted prototype or the owner's words. Or "none".>

## Decisions for the owner

<A numbered list: the choice, the option that is built, one sentence of reason. Or "none".>

## Not in this pull request

- <what the ticket or a reader can expect and this pull request does not do, and the ticket that holds it>
- <a step that waits for the owner, with one exact command. The worker does not run it.>

<footer: the attribution lines that the session gives, or nothing>

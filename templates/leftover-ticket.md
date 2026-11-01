<!-- One ticket for the leftovers of one pull request. The orchestrator fills it when the fix round is over, and files it with a milestone and labels. A worker or a reviewer never files it. -->
# Leftovers of <pull request>: <short subject>

<!-- Before you file: can the pull request still carry a small item now? Then fix it there. Only what stays comes here. One ticket for each pull request, not one for each item. -->

## Where this comes from

- **Pull request:** <pull request>, head `<commit id>`, <open | merged into `<base>`>.
- **Ticket that it closes:** <ticket>.
- **Source of the items:** <the worker's "Found and left alone" | the review of <date> | the orchestrator's reading of the diff>.
- **Why they are here:** the fix round is over. No item is a blocker or a major that a person can reach.

## Items

1. <what was seen, in one sentence>
   - Where: <file, screen or step>
   - Existed before this change: <yes | no>
   - Rank: <minor; when no person can reach it, the state that it needs>
   - Proof: <test name, or the sequence and the last lines of its output>
2. <what was seen>
   - Where: <...>
   - Existed before this change: <yes | no>
   - Rank: <...>
   - Proof: <...>

## Not exercised

- <what the pull request and its review did not run, and why>
- <or "none">

## Set at filing

- **Milestone:** <release | overflow>. The release milestone takes a ticket for three reasons only: a defect of a part that the owner accepted, a break of a non-negotiable, or a gate that the owner named. Reason here: <which one, or "none, so overflow">.
- **Labels:** <type>, <area>, `leftover`.
- **Links:** `Part of <parent ticket>`. Post a comment on <pull request> that names this ticket.

## Done when

Each item is fixed with a test, or closed with one sentence of reason. Nobody starts this ticket until the owner puts it on a list of work (T-4).

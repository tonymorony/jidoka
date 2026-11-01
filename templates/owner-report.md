<!-- The report to the owner at the end of a run. The orchestrator fills it and writes it in the owner's language. Text for the repository and the tracker stays in plain English. The owner answers by number: one count runs over the steps and the decisions, and no heading has a number. -->
# Run report: <date>, <start time> to <end time>

**In one sentence:** <what the owner has now and did not have before>.

## Done

- <outcome>. <pull request>, merged into `<base>` at `<commit id>`. Proof: <the number or the line of output>.
- <outcome>. <pull request>, open and ready. Proof: <...>.

Relayed and not verified by the orchestrator: <what a worker reports and the orchestrator did not check, or "nothing">.

## What broke, and whose mistake

- <what broke>. Mistake of: <the orchestrator | a worker | a tool | the host | nobody in the project>. Cost: <time, a wrong merge, a lost file>. State now: <repaired | open: see "Your steps" or "Not solved">. What changes so that it does not come back: <rule, check or script>.
- <or "Nothing broke.">

## Your steps, in order

Each step is an act that only the owner may do. The orchestrator ran none of them.

1. <step in one sentence, and why it is the owner's>
   `<one exact command>`
   Until then: <what waits, or "nothing waits">.
2. <step>
   `<one exact command>`
   Until then: <...>.

## Decisions

<The numbered list from the template `decision-list.md`, or "none". The numbers continue from "Your steps": after step 2 the first decision is 3. One answer then covers both.>

## Not solved

- <problem>. Tried: <what, with the result>. Recommended: <next act, and who does it>.
- <or "nothing">

## Tickets

| Closed in this run | Opened in this run | Open in the release milestone | Open with no milestone |
|---|---|---|---|
| <n> | <n> | <n> | <n> |

- Opened: <ticket> "<title>", milestone <milestone>. One line for each.
- Throwaway branches, never to merge; the delete is the owner's: `<branch>`, for <purpose>.
- Still running: <agent or watcher>. Output lands in `<path>`. Ends when: <condition or time limit>.

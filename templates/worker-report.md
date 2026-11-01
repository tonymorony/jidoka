<!-- The report of a worker: its last message. The worker fills it and sends nothing else. The orchestrator copies it into `<session folder>/results-<date>.md`. 20 lines at most, raw facts, this order. -->
```
PULL REQUEST: <link or number>, <ready | draft>, base <base>
HEAD: <commit id> "<subject>", pushed: <yes | no: why>
CHECKS: static check <pass | fail>; format <pass | fail>; `<test command>`: <n> passed, <n> failed; CI: not read
RED TO GREEN: <test name>. Red on <base commit>: "<failure line>". Green on <head commit>: "<pass line>"; or "no test: <why a test cannot be red for this ticket>"
PICTURES: <each state with a before and after pair, or "no screen changed">
SWARM: <persona on device, run folder: each target, its number on the head and on the base, met or missed; or "no swarm: <why>">
NEW STRINGS: <each new string that a person reads, or "none">
DECISIONS FOR THE OWNER: <the choice, the option that is built, one sentence of reason; or "none">
NOT DONE: <item of the ticket, and why; or "none">
NOT EXERCISED: <step that did not run, and why; or "none">
DENIED COMMANDS: <exact command, and what you did then; or "none">
FOUND AND LEFT ALONE:
- <what, where, and whether it existed before this change>
- <five lines at most>
- or: none. Checked: <A>, <B>, <C>.
```

Rules for the worker who fills it:

1. Write only what you saw. Paste a line of output; do not describe it.
2. A step that did not run is "not exercised". It is never "done" and never "should pass".
3. "None" under "Found and left alone" needs the list of what you checked.
4. Give no opinion on the quality of your own work. Open no ticket. Ask for no merge.
5. When the work stops at a block, send this report anyway. Put the block in the first line: `BLOCKED: <what stopped the work>`.

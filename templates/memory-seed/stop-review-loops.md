---
name: stop-review-loops
description: One independent review where the risk is, one fix round, no second review; a blocker or a major that is still reachable goes to the owner; the leftovers of a pull request become one ticket
type: feedback
---
<!-- Memory seed. The owner's first session copies this file into the memory of the project and fills each placeholder. -->

Risky code gets one independent review and one fix round. The worker of the ticket does the round, and the orchestrator runs the proof of each blocker and each major defect again after it. No second review starts. When a blocker or a major defect that a person can reach is still there, the pull request becomes a draft and goes on the decision list. What is left of one pull request becomes one ticket, not one more round and not one ticket for each item.

**Why:** Each review finds a next layer of corner cases, and each fix round adds code and new corners. In the origin project one night closes five tickets and opens about twenty-seven. A ticket is a record, not a promise of work.

**How to apply:** Risky code is code that handles <keys, a delete, a service, a trust boundary>. Give the reviewer the code and the tickets, never the author's summary; use the template `review-brief.md`. A finding counts only with a test or an exact sequence and its output. Fix a small leftover in the same pull request while it is open. File the rest with the template `leftover-ticket.md`, with a milestone and labels at filing. The release milestone takes a new ticket for three reasons only: a defect of a part that the owner accepted, a break of a non-negotiable, or a gate that the owner named. End each run with tickets opened against tickets closed.

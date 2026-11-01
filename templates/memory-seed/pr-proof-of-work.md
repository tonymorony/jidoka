---
name: pr-proof-of-work
description: Each pull request body carries proof that a stranger can check; real red and green output on the head commit, and a before and after picture for each changed screen
type: feedback
---
<!-- Memory seed. The owner's first session copies this file into the memory of the project and fills each placeholder. -->

Each pull request body has a "Proof of work" section: the exact test command, the last lines of its output without the change (red) and with it (green), and the numbers that the tests pin. A changed screen also has a before picture and an after picture of each state that moves.

**Why:** The owner merges on what the body says and cannot check a claim that has no output. A test that never failed proves nothing about the change. A picture shows what a test cannot say.

**How to apply:** Put the rule in each brief, and use the template `pr-body.md`. Send back a pull request whose proof is prose. Prove the red side yourself where the risk is: run the new test in a second worktree at the base commit and see it fail. Pictures come from the harness, never by hand. They go to `<picture store>`, and no picture is committed to the work branch. Before the first merge of a batch, join the ready pull requests on one integration branch and run the whole suite and each guard step of CI there: two pull requests that are each green can be red together.

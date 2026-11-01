---
name: wave-size
description: Size a wave by its load on the machine, four or five heavy workers at one time; never run a wave and a release build on one machine at one time
type: feedback
---
<!-- Memory seed. The owner's first session copies this file into the memory of the project and fills each placeholder. -->

A wave holds at most <four or five> workers that load the local machine at one time. More workers are fine only for light tickets. A wave does not run while a release build runs on the same machine.

**Why:** The limit is the machine, not the count. In the origin project, eleven workers at one time make a queue of more than an hour for the local suite, fill the disk and hang one suite. A later wave of heavy test runs makes the same machine too slow for the release build.

**How to apply:** Count the heavy workers before each launch. Check free disk first with `df -h`; below <amount>, free space before the wave. Remove only folders that a build can make again, and only in a worktree whose work is pushed and finished. Tell each worker to run the tests that it touches; CI and the integration branch prove the whole suite. When a test fails under load, run its file alone before you call it a defect.

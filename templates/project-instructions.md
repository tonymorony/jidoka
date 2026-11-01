<!-- Project instruction file. Give the copy the file name that your AI tool reads (CLAUDE.md for Claude Code). One page: each line is a rule that changes what an agent does (R-5). The orchestrator drafts it on day 0, the owner reads each line, and only the owner changes it later. Keep it under 70 lines. Each session and each worker reads the copy on the base branch. -->
# <project name>

<Two sentences: what the project is, who it is for, and what stage it is in.>

## Context

- The full what and why: `<folder or document>`. Read `<first document>` first.
- The work: `<tracker>`, under `<parent ticket or milestone>`.
- The owner's decisions: one line each in `<decision log>` (O-6).
- How each area works now: one spec each in `<spec folder>`, rewritten in the pull request that changes the behaviour (W-1). Architecture decisions: one frozen record each in `<decision folder>` (W-2).
- Review rules: `<coding standards file>`, read by the reviewer on the diff (I-6).

## Non-negotiables

Each one binds every decision. Only the owner lifts one, with a dated line here that says who carries the risk.

1. **<name>:** <one sentence that a test or a review can check>.
2. **<name>:** <one sentence>.

Two made-up examples of the kind, for a to-do list app. Replace them with your own:

- *Example.* **Works with no network:** each screen opens with the network off; a test starts the app that way.
- *Example.* **No lost task:** a task is on disk before the screen says that it is saved; a test stops the app after the save and reads the task back.

## Standing defaults

The owner changes a default with one sentence. Until then it holds.

- **Targets:** <platforms that each choice is judged on>.
- **Distribution:** <what CI builds; what nobody uploads or deploys without the owner's word>.
- **Design:** <placeholder or final; where the design values live>.
- **Toolchain:** `<tool>` pinned at `<version>`; the local gate is `<command>`.
- **Hooks:** `core.hooksPath` is `<hooks folder>` in each clone: `<format check>` at commit, `<static check>` at push; the whole suite runs in CI (R-7, R-8).

## Conventions

- **Commits:** <the form of a commit message, or "no fixed form">.
- **Language:** each text in the repository and the tracker is plain English: short sentences, one meaning for each word. Messages to the owner are in <the owner's language>.
- **<other convention>:** <one sentence>.

## How we work

The rules of jidoka bind each session and each worker in this project. The copy is `docs/jidoka/RULES.md`. Read it whole before the first act. The hard rules are the rules marked Hard there. Where this file and the rules differ, this file wins and says so here: <each difference with its date, or "none">.

Skills that bind: <skill: where it binds, and where it comes from; or "none">.
Checks that hold a rule (R-2): <the step of `check`: the rule that it holds; one line each>. This file does not repeat those rules.

What the orchestrator may do alone (A-1, D-2). This table is the record. What no row names waits for the owner.

| Act | Scope | Ends | The owner's words | Date |
|---|---|---|---|---|
| <merge a ready pull request> | <into `<working branch>` only> | <when the owner cancels> | "<quote>" | <date> |
| <deploy> | the owner only | | | |

## Decided for this project

The answers to "Decide per project" of the rules. With no answer to D-2, the orchestrator merges nothing and pushes to no long branch.

- D-1 Branches: working `<working branch>`, release `<release branch>`, default `<branch>`, <date>
- D-2 Alone: the table above, <date>
- D-3 Ready: <answer>, <date>
- D-4 Wave size: <answer>, <date>
- D-5 Tests of a worker: <answer>, <date>
- D-6 Models: <answer>, <date>
- D-7 The owner's look: <answer>, <date>
- D-8 Decisions: <answer; the private host for a link, or "no host: file paths only">, <date>
- D-9 Flags: <answer; the name pattern of a flag>, <date>
- D-10 Commit identity: <answer>, <date>
- D-11 Non-negotiables: the list above, <date>
- D-12 Pictures: <where they live; the command that makes them; or "no screen">, <date>
- D-13 Merge method: <answer>, <date>
- D-14 Synthetic testers: <personas; devices; targets; where the tool lives; or "no screen">, <date>

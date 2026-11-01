# Adopt jidoka: day 0

Day 0 of a new project as one checklist. Do the steps in order. Each step ends with what proves it.

- "(Owner)" marks a step that only the owner does.
- "(The orchestrator drafts, the owner reads)" marks a step that counts only after the owner reads the result.
- The orchestrator does each other step and shows the result.

A file of day 0 reaches a long branch by the owner's own commit, or by a pull request that the owner merges. The orchestrator pushes to no long branch.
The questions D-1 to D-14 stand under "Decide per project" in `RULES.md`. The checks and D-1 assume GitHub.

An orchestrator that is told "follow jidoka" reads the project instruction file on the base. When the file does not exist, it starts at step 1 and stops at each step marked "(Owner)". When the file has a placeholder left, day 0 is not over: the orchestrator goes on at the first step whose "Done when" does not hold.

## Day 0

1. [ ] **Make the session folder.**
   A folder outside the repository and outside every temporary folder. It holds `briefs/`, `worktrees/`, `scratch/`, `templates/` (a copy of `templates/` of this set), `state-<date>.md` (from `templates/state-file.md`) and `results-<date>.md` (the reports of the workers of one run).
   The copy of `templates/project-instructions.md` is the draft of the project instruction file until step 6.
   *Done when:* the folder holds each name, and its path is under no temporary folder.

2. [ ] **Answer "Decide per project".** (Owner)
   Answer D-1 to D-14 of `RULES.md` in the draft, each in one line with its date. Take the choice of the origin project where you have no reason for another. D-2 is the exception: until you write it, the orchestrator merges nothing and pushes to no long branch.
   D-1 needs a working branch and a release branch. With one long branch, every merge is yours.
   D-2 is the authority table: one row for each permission, with the act, the scope, the end, your own words and the date. Give a merge and a deploy one row each, or the words "the owner only". What no row names waits for you (A-1, A-2).
   D-11 is a short numbered list. Each non-negotiable is one sentence that a test or a review can check.
   *Done when:* each of the fourteen questions has an answer with its date, the orchestrator reads the table back, and you say that it is right.

3. [ ] **Make the repository and its long branches.** (Owner)
   Create each long branch of D-1 and push it.
   Put two lines into `<session folder>/jidoka.env`: `export JIDOKA_LONG_BRANCHES="<release branch> <working branch>"` and `export JIDOKA_BASE=<working branch>`. Each session runs `. <session folder>/jidoka.env` before a check. `checks/README.md` gives the other variables and the defaults.
   *Done when:* `git ls-remote --heads origin` shows each long branch.

4. [ ] **Set the permission settings.** (Owner)
   Set the deny rules of `templates/permission-settings.md` in the settings of the AI tool. They are the guard that "Stop the line" rests on (S-1, A-2, A-3).
   *Done when:* the orchestrator runs one merge command for a pull request number that does not exist, and the permission system denies it.

5. [ ] **Protect the long branches.** (Owner)
   Copy `checks/` into the repository. Run `checks/protect-long-branches.sh --dry-run` and read the request. Then run it without the option.
   Read what it says about head branches. When the host deletes a head branch after a merge, no pull request may have a long branch as its head (G-1, G-3).
   *Done when:* a second run prints "PRESENT".

6. [ ] **Bring the rules in.** (The orchestrator drafts, the owner reads)
   Copy `RULES.md` to `docs/jidoka/`. Copy the draft to the repository as the project instruction file. Give the copy the file name that your AI tool reads (`CLAUDE.md` for Claude Code).
   Add the decision log from `templates/decision-log.md` (O-6), the coding standards file from `templates/coding-standards.md` (I-6), and an empty spec folder (W-1). The project instruction file names all three.
   *Done when:* `git show origin/<base>:<instruction file>` prints the file, and the file names the long branches, the decision log, the coding standards file and the spec folder.

7. [ ] **Set the tracker conventions.**
   One parent ticket for the first body of work, with each ticket as its child. One milestone for the release and one for the work that does not block it. The labels. Who sorts a new ticket, and who closes one (T-1, T-2, T-3).
   Write the command for each tracker operation into one document in the repository.
   *Done when:* a query for open tickets with no milestone returns nothing.

8. [ ] **Lay the rails: the local gate, CI and the other guards.** (The orchestrator drafts, the owner reads)
   Do this before the first feature ticket (R-1). The repository gets a formatter with a check mode, a static check that fails on each warning, a test runner, and one command that runs all three.
   One check named `check` runs that same command: the format check, the static check, the whole suite and every guard step, each with the build flags of a release. One secret scan named `security` reads each commit (C-2). When the names differ, set `JIDOKA_CHECKS` in `jidoka.env`.
   Turn each rule of the project that a machine can check into a step of `check`, and name the step in the project instruction file in place of the rule (R-2): a style rule, a layer boundary, the list of hosts that the product may call (C-5), the rule for a new dependency. Break each rule one time on purpose and see its step red (R-3). Give each suppression its reason and a date (R-4).
   The owner requires both checks on each long branch: a required check is a guard (A-2). The owner sets each secret that CI needs.
   Put the hooks in a tracked folder and set `git config core.hooksPath <hooks folder>` in each clone: the format check at commit, the static check at push, the whole suite in CI only (R-7, R-8). Name the folder in the project instruction file, so that each worker's first command can compare it.
   Write one local script that runs the same lines as CI (P-5). Give each alarm a rule for how it ends (S-8).
   Make each of these four guards, or write "not needed, because <reason>" for it under "How we work" in the project instruction file:
   - the words file for `checks/scrub.sh` (A-8): `<session folder>/scrub-words` on the machine, passed as the second argument, and a secret in CI;
   - the CI step that compares a build with every flag off with the last release, and the refusal of a flag in the release script (P-6);
   - the one deploy script (G-7);
   - the picture harness, and the script that puts its pictures where D-12 says (P-2).
   *Done when:* `git config core.hooksPath` prints the hooks folder, a commit with a format error is refused at commit, the one local command and `check` give the same result on the same commit, a draft pull request that breaks one test shows a red `check`, `checks/merge-guard.sh <number>` refuses it, and the owner reads the list of required checks on each long branch.

9. [ ] **Fill the common rules and seed the memory.** (The orchestrator drafts, the owner reads)
   Install the skills that the project uses and name them in the project instruction file (`SKILLS.md`). Fill each placeholder of `<session folder>/templates/common-rules.md` one time. Copy `templates/memory-seed/` into the memory of the orchestrator and fill each placeholder from the answers of step 2.
   Install `templates/session-start-hook.sh` as the hook that runs at the start of a session and after a clear, with the session folder as its argument (B-13). A hook is a change to the owner's machine: the owner installs it (A-2).
   Install `templates/model-gate-hook.py` as the hook that runs before each launch of a sub-agent, and fill its variables (B-16). Set the cache time of sub-agents to one hour and the compaction window to about 400k tokens (B-17; in Claude Code: `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=1h` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400k` in the `env` block of the settings). Put the hook and the two settings in the settings file that the repository tracks, so that each clone and each cloud session gets them.
   *Done when:* `checks/wave-preflight.sh <session folder>/worktrees`, run from the repository, ends with "PREFLIGHT: pass", and a new session started beside a test handoff file shows that file.

10. [ ] **Rehearse with the first ticket.**
    Run one small, real ticket through the whole loop: brief, worker, worktree, pull request with its proof, review, `checks/merge-guard.sh`, merge, closed ticket, report to the owner.
    Then hold a short look-back: what stopped the line, what the owner had to say twice, which field of a template stayed empty.
    *Done when:* the ticket is closed, the report shows tickets opened against tickets closed, and each finding of the look-back is a change or the note "no change".

11. [ ] **Close day 0.** (Owner)
    Read the project instruction file on the base one more time.
    *Done when:* the file has no placeholder left and is under 70 lines.

## After each incident

An incident is each time the line stops for a cause that a rule could catch, and each time the owner has to say a thing twice.

1. [ ] **Write the rule, the reason and the date.**
   One sentence that says what to do, one line "Why", and one line "Learned from" that names no person and no product.
   A rule for this project goes into the project instruction file. A rule for every project goes into `RULES.md`, with an entry in `CHANGELOG.md`.

2. [ ] **Change the template or the check that would have caught it.**
   Ask first which check would have caught it (R-6): a new step of CI, or a new refusal in a script of `checks/` with a test that is red without it. Then which sentence of the brief would have prevented it: a new field in a template.
   A rule that nothing enforces holds by habit only: say so in the rule.

3. [ ] **Tell the next session.**
   Write a line that starts with "LESSON" into the state file at the time of the incident. Save one memory note with the rule and its date.

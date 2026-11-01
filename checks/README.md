# Checks

Five small scripts. Each one enforces a rule of `RULES.md` that a habit does not hold.
Each runs under bash version 3.2 and under a newer bash.
`merge-guard.sh`, `protect-long-branches.sh` and `ci-wait.sh` need `gh`, signed in. The other two need `git`.
Each script also needs `awk`, `sed`, `grep`, `find`, `sort`, `tr` and `mktemp`. `wave-preflight.sh` needs `df`, `du`, `uptime` and `cksum` too.

A script holds no repository, no branch and no path of its own. It reads them from its arguments and from these variables.
Each script prints its full list with `--help`.
Day 0 puts the values of the project into `<session folder>/jidoka.env`. Each session runs `. <session folder>/jidoka.env` before a check (`ADOPT.md`).

| Variable | Meaning | Default |
|---|---|---|
| `JIDOKA_REPO` | the repository for `gh`, as owner/name | read from the remote `origin` of the current folder |
| `JIDOKA_LONG_BRANCHES` | the long branches, with a space between them | `main develop` |
| `JIDOKA_BASE` | the working branch: the one base of a merge | `develop` |
| `JIDOKA_CHECKS` | the checks that must be successful before a merge | `check security` |
| `JIDOKA_REMOTE` | the name of the git remote | `origin` |
| `JIDOKA_MIN_FREE_GB` | the least free disk before a wave, in GB | `20` |
| `JIDOKA_REGENERABLE` | the folder names that a build can make again | `build node_modules target dist` |
| `JIDOKA_WAIT_EVERY` | seconds between two looks of `ci-wait.sh` | `60` |
| `JIDOKA_WAIT_LIMIT` | most seconds that `ci-wait.sh` waits | `3600` |

The exit codes mean the same in each script:

- `0`: the check passes.
- `1`: the check fails. The output says what to do next.
- `2`: a long branch is missing (`merge-guard.sh` only).
- `3`: the check could not run, so nothing is proved.
- `64`: wrong usage.

Every code that is not `0` is a stop (S-1, S-3). Do not read `3` as a pass.

## merge-guard.sh

`checks/merge-guard.sh <pull request number> [--merge]`

**When to run it.** For every merge, in place of any other merge command (G-2, G-3, G-8). Run it without `--merge` to see whether a pull request is ready; it then changes nothing. It reads the pull request from the host at that moment. It refuses when the base is not `JIDOKA_BASE`, when the head is a long branch, when the pull request is a draft, when the mergeable state is not "clean", or when a check of `JIDOKA_CHECKS` is not successful on the head commit. With `--merge` it reads the base one more time, merges with a merge commit at the commit that it checked, proves that each long branch still exists, and prints the merge commit. When a long branch is gone, it prints the one command that puts the branch back at the commit that it had before the merge, and exits with `2`. A merge into the release branch is a protected act (A-2): the owner runs the script with `JIDOKA_BASE` set to the release branch, or a written permission names that merge.

**What it does not do.** It does not decide whether you may merge: the owner's written permission does (A-1, A-2). It does not run a trial merge or the suite on the merged tree (P-5). It does not read the diff or the worker's report (B-8), and it does not know whether a review is due (B-9): "READY" means only that the host shows no reason against the merge. It restores no branch, closes no ticket and puts no tag. It reads by name only the checks in `JIDOKA_CHECKS`.

## ci-wait.sh

`checks/ci-wait.sh <pull request number> [<pull request number> ...]`

**When to run it.** Each time the orchestrator waits for CI, in place of any poll by hand (B-14). Start it in the background and act when it exits. While it waits it prints nothing. It looks at each pull request every `JIDOKA_WAIT_EVERY` seconds, and reads the head commit again at each look. A pull request ends its wait when each check of `JIDOKA_CHECKS` is complete on its head commit, or when it is merged or closed. At the end it prints one line for each pull request: `GREEN`, `RED` with each check that did not succeed, `MERGED` or `CLOSED`. It exits with `0` when none is red and `1` when one is. When `JIDOKA_WAIT_LIMIT` passes while a check still runs, it prints a `PENDING` line for that pull request and exits with `3`.

**What it does not do.** It does not read why a check is red (S-4), re-run a job, merge or start a workflow. It does not read the mergeable state: `merge-guard.sh` does. It reads by name only the checks in `JIDOKA_CHECKS`.

## protect-long-branches.sh

`checks/protect-long-branches.sh [--dry-run]`

**When to run it.** On day 0, when the long branches exist, and again after each change to the list of long branches (G-1). The owner runs it, because a change to a guard is a protected act (A-2). Run it with `--dry-run` first: it prints the request, sends nothing and reads nothing. Without `--dry-run` it reads the rules that the host applies to each long branch. When each branch has a rule against deletion and a rule against force push, it says "PRESENT" and sends nothing. When a rule is missing, it creates one ruleset with these two rules for all long branches, with no bypass, and reads the rules again. It also says whether the repository deletes a head branch after a merge, and it warns when a ruleset has a bypass.

**What it does not do.** It does not change a ruleset that exists: it prints the commands for an edit that starts from the full live ruleset. It does not read a branch protection rule of the older kind, so a branch that only such a rule protects shows as not protected. It creates no branch. It does not change the setting that deletes head branches. It requires no check and no review before a merge: set those in the repository.

## wave-preflight.sh

`checks/wave-preflight.sh [--clean] [worktrees folder]`

**When to run it.** Before each wave, and before a release build on the same machine (B-4). It compares free disk with `JIDOKA_MIN_FREE_GB`, and the load average of the last minute with the number of cores. It asks the remote one time whether it answers and has the base. It lists each worktree with the state of its branch and the size of the folders that a build can make again. Start no wave when it fails. With `--clean` and the worktrees folder, it frees disk first. It removes only a folder whose name is in `JIDOKA_REGENERABLE`, only in a worktree whose branch is merged or gone on the remote, only when that worktree has no uncommitted change, and only when git ignores the folder and tracks no file in it. It prints each path before it removes it. It refuses the root folder, the home folder, and each path that is not inside a worktree under the folder that you name. Add the build folders of your stack to `JIDOKA_REGENERABLE`.

**What it does not do.** It removes no worktree and no branch, and it does not fetch. It does not know that a release build runs: you know that. It does not say how many workers fit (D-4). It takes no lock in a worktree, so it is safe beside a worker. A branch that the host merged as one squashed commit and did not delete shows as "active" and keeps its folders. A branch with no commit of its own shows as "no commits" and is never cleaned.

## scrub.sh

`checks/scrub.sh <folder> [words file]`

**When to run it.** Before each push of a text that other people read, and in CI, where a name must stay out (A-8). It searches every text file of the folder, and every file name, for each word or pattern of the words file, for email addresses and for links. Case does not matter. It prints the file, the line and the text that it found, and exits with `1` on a hit. `scrub-words.example` shows the form of a words file; every entry in it is made up. Keep the real words file out of version control, because it names what it hides: the script counts a words file that git tracks as a hit. In CI the words come from a secret. Set `JIDOKA_SCRUB_QUIET=1` there, so that the log of the job does not hold the word: the script then prints the file, the line and the kind of each hit, and no text that holds a word. An address or a link that must stay goes into the allow list, one pattern on each line: `.jidoka-scrub-allow` in the folder, or the file that `JIDOKA_SCRUB_ALLOW` names. Reserved example domains and the local machine are always allowed. The allow list never excuses a word.

**What it does not do.** It does not read a binary file, the `.git` folder, the history, a commit message, a ticket or a pull request body. It does not find a name that is not in the words file, or a host that is written without a scheme. It is not a secret scan. With no words file it checks addresses and links only, and it says so. A file name with an @ sign before a size mark, as some image files have, looks like an email address: put a pattern for it in the allow list.

## tests/run.sh

`checks/tests/run.sh [checks folder]`

**When to run it.** After each change to a script, and one time on a new machine. It runs the five scripts against a temporary folder, with a fake `gh`, a fake `git` and a fake `uptime`. It calls no host and changes no repository. It needs `jq`. To prove that a test can fail, change a copy of the scripts and name the folder of the copy. It exits with `64` when the folder does not hold the five scripts.

**What it does not do.** It does not prove the answers of the real host: the shape of a pull request, of a check run, of a ruleset. It does not prove what the real git says about a branch that is merged or gone. Prove both one time on a scratch repository before you trust `--merge`, `--clean` or a new ruleset on a new project.

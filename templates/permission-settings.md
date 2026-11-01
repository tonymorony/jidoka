<!-- Deny rules for the permission system of the AI tool. The owner sets them on day 0, in the settings of the tool and in the form that the tool reads. No agent edits these settings: they are a guard (A-2). -->
# Permission settings

A rule in a file asks. A deny rule stops. The permission system is the guard under the rules S-1, A-2 and A-3, so set it before the first worker starts.

Set one deny rule for each row that fits the project. Each rule binds the orchestrator and each sub-agent.

| Protected act | Deny each command that | Forms to cover |
|---|---|---|
| Merge | merges a pull request, or pushes to a long branch | `gh pr merge`, `gh api` with `/merge`, `git push <remote> <long branch>` |
| Force push, branch delete | rewrites or deletes a remote branch | `git push --force`, `git push <remote> --delete`, `gh api -X DELETE` on a ref |
| Deploy | publishes a build or a service | `<deploy command>`, `<upload command>` |
| Secret | reads or sets a secret | `gh secret`, `<secret store command>`, a read of `<secret files>` |
| Guard | changes a ruleset, a branch protection, a scan rule or these settings | `gh api` on `/rulesets`, `checks/protect-long-branches.sh` without `--dry-run`, an edit of `<settings file>` |
| The owner's machine | installs a tool or changes a system setting | `<install command>`, `<system settings command>` |

Rules for the settings:

1. A standing permission of the authority table (D-2) allows one exact command and nothing wider. For a merge into the working branch that command is `checks/merge-guard.sh <number> --merge`. Every other merge command stays denied.
2. Until the table has a row for a merge, deny `checks/merge-guard.sh` with `--merge` too.
3. When the owner asks for a protected act of several steps, the owner names one script by its path. The settings allow that script, not its loose commands (S-2).
4. A denied command is never tried in another form (S-1). When a form is missing from a rule, the owner adds it.

*Done when:* the orchestrator runs one merge command of the first row for a pull request number that does not exist, the permission system denies it, and the orchestrator reports the denial and tries nothing else.

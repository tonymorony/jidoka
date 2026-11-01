<!-- The coding standards of the project. The orchestrator drafts it on day 0, the owner reads it, and it lives in the repository as CODING_STANDARDS.md. The reviewer reads it against the diff; a worker brief points to it and repeats none of it (I-6). -->
# Coding standards

In brief: the mechanical rules are enforced by checks, so a review only reads that the check is green. The judgement rules are what the reviewer applies to the diff by reading it.

## Mechanical rules

Each rule names the check that goes red when the rule breaks (R-2). A rule with no check yet carries "no check: <ticket that adds one>".

| Rule | Check |
|---|---|
| <code is formatted> | `<format check>`, at commit and in `check` |
| <the static check has no warning> | `<static check>`, at push and in `check` |
| <a layer does not import another layer> | `<architecture test>` in `check` |
| <the product calls only the declared hosts> | `<host scan>` in `check` (C-5) |

## Judgement rules

A rule that no check can decide. Each one is a question that a reviewer answers with yes or no on the diff.

1. <Does each name say what the thing is in the words of the domain?>
2. <Does the change add a mechanism that only one case uses?>
3. <Does each new doc cite a symbol or a test name, never a line number (W-5)?>
4. <Does the pull request rewrite the spec of each area whose behaviour it changes (W-1)?>

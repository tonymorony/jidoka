#!/usr/bin/env bash
# merge-guard.sh - read a pull request and refuse a merge that is not safe.
#
# Usage: checks/merge-guard.sh <pull request number> [--merge]
#
# Without --merge the script reports and changes nothing.
# With --merge it merges with a merge commit, proves that each long branch
# still exists on the remote, and prints the merge commit.
#
# It refuses when:
#   - the base of the pull request is not JIDOKA_BASE
#   - the head of the pull request is one of the long branches
#   - the pull request is a draft, is closed or is already merged
#   - the mergeable state is not "clean"
#   - a required check is not successful on the head commit
#
# The script does not decide whether you may merge. A written permission of
# the owner does (rules A-1, A-2). Never set JIDOKA_BASE to pass a refusal.
#
# Environment:
#   JIDOKA_REPO           owner/name for gh.
#                         Default: read from the remote "origin" of this folder.
#   JIDOKA_BASE           the one base that a merge may go into. Default: develop
#   JIDOKA_LONG_BRANCHES  branches that must never disappear. Default: "main develop"
#   JIDOKA_CHECKS         names of the checks that must be successful.
#                         Default: "check security". The list splits at spaces;
#                         separate the names with commas when a name holds a space.
#   JIDOKA_STATE_WAIT     most seconds to wait while the host computes the
#                         mergeable state. Default: 10
#   JIDOKA_VERIFY_WAIT    seconds between the merge and the look at the long
#                         branches. Default: 5
#
# Exit codes:
#   0   ready (report), or merged and verified (--merge)
#   1   refused; each reason is one line
#   2   a long branch is missing on the remote; the restore command is printed
#   3   cannot check: a tool is missing or the host does not answer
#   64  wrong usage

set -euo pipefail
set -f

say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

show_help() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

usage_error() {
  err "merge-guard: $*"
  err "usage: checks/merge-guard.sh <pull request number> [--merge]"
  exit 64
}

# PHASE says what the script has done so far, so that a stop never claims more
# or less than what happened: before, sent (the merge request left), merged.
PHASE="before"
MERGE_SHA=""

cannot() {
  err "CANNOT CHECK: $*"
  case "$PHASE" in
    sent)
      err "The merge request WAS SENT and its result is not known. Read the pull request before any other act:"
      err "  gh api repos/$REPO/pulls/$PR --jq .merged"
      ;;
    merged)
      err "Pull request $PR IS MERGED (merge commit $MERGE_SHA). The long branches are NOT verified. Read each one before any other merge:"
      err "  gh api repos/$REPO/git/ref/heads/<branch> --jq .object.sha"
      ;;
    *) err "Nothing was merged. Fix the cause and run the script again." ;;
  esac
  exit 3
}

PR=""
DO_MERGE=0
for arg; do
  case "$arg" in
    --merge) DO_MERGE=1 ;;
    -h | --help)
      show_help
      exit 0
      ;;
    -*) usage_error "unknown option: $arg" ;;
    *)
      if [ -n "$PR" ]; then usage_error "more than one pull request number"; fi
      PR=$arg
      ;;
  esac
done

case "$PR" in
  "" | *[!0-9]*) usage_error "the pull request number must be digits only" ;;
esac

BASE=${JIDOKA_BASE:-develop}
LONG_BRANCHES=${JIDOKA_LONG_BRANCHES:-main develop}
CHECKS=${JIDOKA_CHECKS:-check security}
STATE_WAIT=${JIDOKA_STATE_WAIT:-10}
VERIFY_WAIT=${JIDOKA_VERIFY_WAIT:-5}

case "$STATE_WAIT$VERIFY_WAIT" in
  *[!0-9]*) usage_error "JIDOKA_STATE_WAIT and JIDOKA_VERIFY_WAIT must be whole seconds" ;;
esac

command -v gh >/dev/null 2>&1 || cannot "the tool \"gh\" is not on the path. Install it and sign in."

if [ -n "${JIDOKA_REPO:-}" ]; then
  REPO=$JIDOKA_REPO
  REPO_FROM="JIDOKA_REPO"
else
  if ! ORIGIN_URL=$(git remote get-url origin 2>/dev/null); then
    cannot "JIDOKA_REPO is not set and this folder has no remote \"origin\". Set JIDOKA_REPO=owner/name."
  fi
  REPO=$(printf '%s\n' "$ORIGIN_URL" | sed -E 's#/+$##; s#\.git$##; s#^.*[:/]([^/:]+/[^/:]+)$#\1#')
  REPO_FROM="the remote \"origin\" of this folder"
fi

case "$REPO" in
  */*/* | /* | */ | *[!A-Za-z0-9._/-]*) usage_error "the repository must be owner/name, not \"$REPO\"" ;;
  */*) ;;
  *) usage_error "the repository must be owner/name, not \"$REPO\"" ;;
esac

ERRFILE=$(mktemp "${TMPDIR:-/tmp}/jidoka-merge-guard.XXXXXX")
trap 'rm -f "$ERRFILE"' EXIT

api() {
  gh api "$@" 2>"$ERRFILE"
}

host_said() {
  tr '\n' ' ' <"$ERRFILE"
}

PR_JQ='[.state, (.merged | tostring), (.draft | tostring), .base.ref, .head.ref, .head.sha, (.mergeable_state // "unknown"), (.head.repo.full_name // "-"), (.base.repo.default_branch // "-"), (.merge_commit_sha // "-"), (.title // "-")] | @tsv'

read_pull_request() {
  local line
  if ! line=$(api "repos/$REPO/pulls/$PR" --jq "$PR_JQ"); then
    cannot "the host did not return pull request $PR of $REPO: $(host_said)"
  fi
  IFS=$'\t' read -r PR_STATE PR_MERGED PR_DRAFT PR_BASE PR_HEAD PR_SHA PR_MSTATE PR_HEAD_REPO PR_DEFAULT PR_MERGE_SHA PR_TITLE <<<"$line"
  if [ -z "${PR_SHA:-}" ] || [ -z "${PR_TITLE:-}" ]; then
    cannot "the answer of the host for pull request $PR has an unknown shape."
  fi
}

# Prints the commit of a branch, or nothing when the remote does not have it.
branch_tip() {
  local sha
  if sha=$(api "repos/$REPO/git/ref/heads/$1" --jq '.object.sha'); then
    printf '%s\n' "$sha"
    return 0
  fi
  if grep -q 'HTTP 404' "$ERRFILE"; then
    return 0
  fi
  cannot "the host did not answer for branch \"$1\": $(host_said)"
}

is_long_branch() {
  local b
  for b in $LONG_BRANCHES; do
    if [ "$b" = "$1" ]; then return 0; fi
  done
  return 1
}

restore_command() {
  say "  gh api -X POST repos/$REPO/git/refs -f ref=refs/heads/$1 -f sha=$2"
}

open_bases_command() {
  say "  gh api \"repos/$REPO/pulls?state=open&per_page=100\" --jq '.[] | [.number, .base.ref] | @tsv'"
}

REASONS=0
refuse() {
  err "REFUSE: $*"
  REASONS=$((REASONS + 1))
}

say "repository: $REPO (from $REPO_FROM)"

read_pull_request
say "pull request $PR: $PR_TITLE"

if [ "$PR_MERGED" = "true" ]; then
  err "REFUSE: pull request $PR is already merged. Do not push to its branch. Start follow-up work on a new branch from $BASE."
  exit 1
fi
if [ "$PR_STATE" != "open" ]; then
  err "REFUSE: pull request $PR is $PR_STATE. Open a new pull request if the work is still wanted."
  exit 1
fi

WAITED=0
while [ "$PR_MSTATE" = "unknown" ] && [ "$WAITED" -lt "$STATE_WAIT" ]; do
  sleep 2
  WAITED=$((WAITED + 2))
  read_pull_request
done

say "base: $PR_BASE   head: $PR_HEAD ($PR_SHA)   mergeable state: $PR_MSTATE"

if [ "$PR_BASE" != "$BASE" ]; then
  refuse "the base is \"$PR_BASE\", not \"$BASE\". The host can move the base of an open pull request. Set the base back to \"$BASE\". Do not set JIDOKA_BASE to pass this refusal: a merge into \"$PR_BASE\" needs a written permission of the owner that names \"$PR_BASE\" (A-1, A-2)."
fi

if [ "$PR_HEAD_REPO" = "$REPO" ] && is_long_branch "$PR_HEAD"; then
  refuse "the head \"$PR_HEAD\" is a long branch. A merge can delete it. Make a cut branch from \"$PR_HEAD\" and open the pull request from the cut branch."
fi

if [ "$PR_DRAFT" = "true" ]; then
  refuse "the pull request is a draft. A draft is not for merge. Mark it ready when it is."
fi

case "$PR_MSTATE" in
  clean) ;;
  draft) ;;
  dirty) refuse "the mergeable state is \"dirty\": the head conflicts with \"$PR_BASE\". Merge \"$PR_BASE\" into the head, resolve hunk by hunk, and push. A pull request with a conflict gets no CI run." ;;
  behind) refuse "the mergeable state is \"behind\": the head does not hold the newest \"$PR_BASE\". Merge \"$PR_BASE\" into the head and wait for the checks." ;;
  blocked) refuse "the mergeable state is \"blocked\": a required check or a required review is missing. Read the checks below." ;;
  unstable) refuse "the mergeable state is \"unstable\": a check failed or still runs. Read the checks, then run the script again." ;;
  unknown) refuse "the mergeable state is \"unknown\" after $STATE_WAIT seconds. Run the script again." ;;
  *) refuse "the mergeable state is \"$PR_MSTATE\", not \"clean\"." ;;
esac

if ! RUNS=$(api --paginate "repos/$REPO/commits/$PR_SHA/check-runs?per_page=100" \
  --jq '.check_runs[] | [(.id | tostring), .status, (.conclusion // "-"), .name] | @tsv'); then
  cannot "the host did not return the check runs of $PR_SHA: $(host_said)"
fi
if ! STATUSES=$(api "repos/$REPO/commits/$PR_SHA/status?per_page=100" \
  --jq '.statuses[] | ["0", "completed", .state, .context] | @tsv'); then
  cannot "the host did not return the commit statuses of $PR_SHA: $(host_said)"
fi

# Prints "status conclusion" of the newest run with this name, or "missing".
check_state() {
  printf '%s\n%s\n' "$RUNS" "$STATUSES" | NAME=$1 awk -F '\t' '
    BEGIN { name = ENVIRON["NAME"]; newest = -1 }
    $4 == name && ($1 + 0) > newest { newest = $1 + 0; status = $2; conclusion = $3 }
    END { if (newest < 0) print "missing"; else print status " " conclusion }'
}

case "$CHECKS" in
  *,*) CHECK_LINES=$(printf '%s\n' "$CHECKS" | tr ',' '\n') ;;
  *) CHECK_LINES=$(printf '%s\n' "$CHECKS" | tr -s ' ' '\n') ;;
esac

CHECK_COUNT=0
while IFS= read -r name; do
  name=$(printf '%s\n' "$name" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  if [ -z "$name" ]; then continue; fi
  CHECK_COUNT=$((CHECK_COUNT + 1))
  state=$(check_state "$name")
  case "$state" in
    "completed success") say "check \"$name\": success" ;;
    missing) refuse "the check \"$name\" has no run on $PR_SHA. Wait for CI. When CI never starts, read the annotations of the job before the code." ;;
    completed*) refuse "the check \"$name\" ended as \"${state#completed }\" on $PR_SHA. Read why it is red before you act: the step count, the annotations, the failed tests (S-4). Run the job again one time only, when you can say what changed or when the common rules of the project name this fault." ;;
    *) refuse "the check \"$name\" is not complete (${state%% *}) on $PR_SHA. Wait, then run the script again." ;;
  esac
done <<<"$CHECK_LINES"

if [ "$CHECK_COUNT" -eq 0 ]; then
  usage_error "JIDOKA_CHECKS names no check"
fi

TIPS=""
for b in $LONG_BRANCHES; do
  tip=$(branch_tip "$b")
  if [ -z "$tip" ]; then
    err "STOP: the long branch \"$b\" is missing on the remote before the merge. Nothing was merged."
    err "Restore it first. Find its last commit (the second parent of the merge that took it, or \"git rev-parse origin/$b\" in a clone that still has it), then the owner runs:"
    restore_command "$b" "<last commit of $b>" >&2
    err "Then read the base of each open pull request:"
    open_bases_command >&2
    exit 2
  fi
  say "long branch \"$b\": present ($tip)"
  TIPS="$TIPS$b $tip
"
done

if [ "$REASONS" -gt 0 ]; then
  err "pull request $PR is not ready: $REASONS reason(s) above. Nothing was merged."
  exit 1
fi

if [ "$DO_MERGE" -eq 0 ]; then
  say "READY: pull request $PR can merge into \"$PR_BASE\" at $PR_SHA. Nothing was merged."
  say "NEXT: this script reads the host only. Read the whole diff and the report of the worker (B-8), and wait for the review of risky code (B-9). Then run the script again with --merge, when a written permission of the owner covers a merge into \"$PR_BASE\"."
  exit 0
fi

CHECKED_SHA=$PR_SHA
read_pull_request
if [ "$PR_STATE" != "open" ] || [ "$PR_BASE" != "$BASE" ] || [ "$PR_SHA" != "$CHECKED_SHA" ] || [ "$PR_DRAFT" = "true" ]; then
  err "REFUSE: pull request $PR changed while the script read it (state $PR_STATE, base \"$PR_BASE\", head $PR_SHA). Nothing was merged. Run the script again."
  exit 1
fi
say "base checked before the merge: $PR_BASE"

PHASE="sent"
if MERGE_OUT=$(api -X PUT "repos/$REPO/pulls/$PR/merge" -f merge_method=merge -f "sha=$CHECKED_SHA" \
  --jq '[(.merged | tostring), (.sha // "-")] | @tsv'); then
  IFS=$'\t' read -r MERGED_FLAG MERGE_SHA <<<"$MERGE_OUT"
  if [ "$MERGED_FLAG" != "true" ] || [ -z "$MERGE_SHA" ] || [ "$MERGE_SHA" = "-" ]; then
    cannot "the host answered the merge request without a merge commit. Read pull request $PR before any other act."
  fi
else
  HOST_REFUSAL=$(host_said)
  read_pull_request
  if [ "$PR_MERGED" != "true" ]; then
    err "REFUSE: the host did not merge pull request $PR: $HOST_REFUSAL"
    err "Nothing was merged. Do not try the merge in another way. Tell the owner what the host said."
    exit 1
  fi
  MERGE_SHA=$PR_MERGE_SHA
fi

PHASE="merged"
say "MERGED: pull request $PR into \"$BASE\". Merge commit: $MERGE_SHA"

sleep "$VERIFY_WAIT"

GONE=0
for b in $LONG_BRANCHES; do
  tip=$(branch_tip "$b")
  if [ -n "$tip" ]; then
    say "long branch \"$b\": present after the merge ($tip)"
    continue
  fi
  GONE=$((GONE + 1))
  before=$(printf '%s' "$TIPS" | BRANCH=$b awk '$1 == ENVIRON["BRANCH"] { print $2 }')
  err "STOP: the long branch \"$b\" is gone from the remote after the merge."
  err "Restore it at the commit that it had before the merge. This is a protected act: the owner runs it, unless a written permission of the owner names it."
  restore_command "$b" "$before" >&2
done

if [ "$GONE" -gt 0 ]; then
  err "The merge commit is $MERGE_SHA. Merge nothing more until each long branch is back."
  err "Then read the base of each open pull request, because the host moves a pull request whose base is deleted:"
  open_bases_command >&2
  exit 2
fi

if [ "$PR_DEFAULT" != "$BASE" ]; then
  say "NEXT: \"$BASE\" is not the default branch, so the host does not close the tickets that the body names. Close each one by hand with a comment that names pull request $PR."
fi
exit 0

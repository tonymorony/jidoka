#!/usr/bin/env bash
# protect-long-branches.sh - forbid deletion and force push of each long branch.
#
# Usage: checks/protect-long-branches.sh [--dry-run]
#
# The script reads the rules that the host applies to each long branch.
# When each long branch already has a rule against deletion and a rule against
# force push, it says "present" and sends nothing. When a rule is missing, it
# creates one repository ruleset for all long branches and reads the rules again.
# It also says whether the repository deletes a head branch after a merge.
#
# --dry-run prints the requests, sends nothing and reads nothing.
#
# Only the owner runs this script without --dry-run: a change to a guard is a
# protected act (rule A-2). An agent runs it with --dry-run only.
#
# Environment:
#   JIDOKA_REPO           owner/name for gh.
#                         Default: read from the remote "origin" of this folder.
#   JIDOKA_LONG_BRANCHES  branches to protect. Default: "main develop"
#   JIDOKA_RULESET_NAME   name of the ruleset. Default: jidoka-long-branches
#
# Exit codes:
#   0   each long branch is protected (present or created), or a dry run
#   1   a long branch is not protected; the next step is printed
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
  err "protect-long-branches: $*"
  err "usage: checks/protect-long-branches.sh [--dry-run]"
  exit 64
}

cannot() {
  err "CANNOT CHECK: $*"
  exit 3
}

DRY_RUN=0
for arg; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      show_help
      exit 0
      ;;
    *) usage_error "unknown argument: $arg" ;;
  esac
done

LONG_BRANCHES=${JIDOKA_LONG_BRANCHES:-main develop}
RULESET_NAME=${JIDOKA_RULESET_NAME:-jidoka-long-branches}

case "$RULESET_NAME" in
  "" | *[!A-Za-z0-9._\ -]*) usage_error "JIDOKA_RULESET_NAME may hold letters, digits, spaces, dots, dashes and underscores only" ;;
esac

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

INCLUDES=""
BRANCH_COUNT=0
for b in $LONG_BRANCHES; do
  case "$b" in
    *[!A-Za-z0-9._/-]* | /* | */ | -*) usage_error "\"$b\" is not a plain branch name" ;;
  esac
  INCLUDES="$INCLUDES${INCLUDES:+, }\"refs/heads/$b\""
  BRANCH_COUNT=$((BRANCH_COUNT + 1))
done
if [ "$BRANCH_COUNT" -eq 0 ]; then
  usage_error "JIDOKA_LONG_BRANCHES names no branch"
fi

PAYLOAD=$(
  cat <<EOF
{
  "name": "$RULESET_NAME",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": { "include": [ $INCLUDES ], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" }
  ]
}
EOF
)

encode_branch() {
  printf '%s\n' "$1" | sed 's#/#%2F#g'
}

say "repository: $REPO (from $REPO_FROM)"
say "long branches: $LONG_BRANCHES"

if [ "$DRY_RUN" -eq 1 ]; then
  say "dry run: nothing is sent and nothing is read."
  say "would read:  GET repos/$REPO   (does the repository delete a head branch after a merge?)"
  for b in $LONG_BRANCHES; do
    say "would read:  GET repos/$REPO/git/ref/heads/$b   (does the branch exist?)"
    say "would read:  GET repos/$REPO/rules/branches/$(encode_branch "$b")   (which rules apply?)"
  done
  say "would read:  GET repos/$REPO/rulesets   (does a ruleset named \"$RULESET_NAME\" exist?)"
  say "would send, only when a long branch lacks a rule:"
  say "POST repos/$REPO/rulesets"
  say "$PAYLOAD"
  exit 0
fi

command -v gh >/dev/null 2>&1 || cannot "the tool \"gh\" is not on the path. Install it and sign in."

ERRFILE=$(mktemp "${TMPDIR:-/tmp}/jidoka-protect.XXXXXX")
IDFILE=$(mktemp "${TMPDIR:-/tmp}/jidoka-protect-ids.XXXXXX")
trap 'rm -f "$ERRFILE" "$IDFILE"' EXIT

api() {
  gh api "$@" 2>"$ERRFILE"
}

host_said() {
  tr '\n' ' ' <"$ERRFILE"
}

if ! SETTINGS=$(api "repos/$REPO" --jq '[(.delete_branch_on_merge | tostring), (.default_branch // "-")] | @tsv'); then
  cannot "the host did not return repository $REPO: $(host_said)"
fi
IFS=$'\t' read -r DELETE_ON_MERGE DEFAULT_BRANCH <<<"$SETTINGS"

case "$DELETE_ON_MERGE" in
  true) say "head branches: the repository DELETES a head branch after a merge. Never merge a pull request whose head is a long branch; checks/merge-guard.sh refuses it." ;;
  false) say "head branches: the repository keeps a head branch after a merge. A child of a merged pull request then stays on a dead base: change its base before you merge it." ;;
  *)
    say "head branches: NOT READ. This account cannot see the setting. The owner reads it with:"
    say "  gh api repos/$REPO --jq .delete_branch_on_merge"
    ;;
esac
say "default branch: $DEFAULT_BRANCH"

RULESET_IDS=""

# Prints the rule types that the branch lacks: nothing when both rules apply.
missing_rules() {
  local rules lack
  if ! rules=$(api "repos/$REPO/rules/branches/$(encode_branch "$1")?per_page=100" \
    --jq '.[] | [.type, ((.ruleset_id // 0) | tostring)] | @tsv'); then
    cannot "the host did not return the rules of branch \"$1\": $(host_said) If the plan of the repository has no rulesets, protect each long branch with a branch protection rule that keeps deletion and force push off."
  fi
  lack=""
  if ! printf '%s\n' "$rules" | awk -F '\t' '$1 == "deletion" { found = 1 } END { exit !found }'; then
    lack="deletion"
  fi
  if ! printf '%s\n' "$rules" | awk -F '\t' '$1 == "non_fast_forward" { found = 1 } END { exit !found }'; then
    lack="$lack${lack:+ }non_fast_forward"
  fi
  printf '%s\n' "$rules" | awk -F '\t' '$1 == "deletion" || $1 == "non_fast_forward" { print $2 }' >>"$IDFILE"
  printf '%s\n' "$lack"
}

survey() {
  UNPROTECTED=0
  : >"$IDFILE"
  local b lack
  for b in $LONG_BRANCHES; do
    if ! api "repos/$REPO/git/ref/heads/$b" --jq '.object.sha' >/dev/null; then
      if grep -q 'HTTP 404' "$ERRFILE"; then
        say "branch \"$b\": does NOT exist on the remote yet. Make it; a rule applies to it by name."
      else
        cannot "the host did not answer for branch \"$b\": $(host_said)"
      fi
    fi
    lack=$(missing_rules "$b")
    if [ -z "$lack" ]; then
      say "branch \"$b\": deletion forbidden, force push forbidden"
    else
      say "branch \"$b\": NOT protected, no rule for: $lack"
      UNPROTECTED=$((UNPROTECTED + 1))
    fi
  done
  RULESET_IDS=$(sort -u "$IDFILE" | grep -v '^0*$' || true)
}

report_bypass() {
  local id line name enforcement actors self
  for id in $RULESET_IDS; do
    if ! line=$(api "repos/$REPO/rulesets/$id" \
      --jq '[.name, .enforcement, ((.bypass_actors // []) | length | tostring), (.current_user_can_bypass // "unknown")] | @tsv'); then
      say "ruleset $id: bypass list NOT READ ($(host_said))"
      continue
    fi
    IFS=$'\t' read -r name enforcement actors self <<<"$line"
    say "ruleset $id \"$name\": enforcement $enforcement, bypass actors $actors, this account can bypass: $self"
    if [ "$actors" != "0" ] || [ "$self" = "always" ]; then
      say "  WARNING: an actor with bypass can still delete and force push. Record who has it, why, and the request that removes it."
    fi
  done
}

survey

if [ "$UNPROTECTED" -eq 0 ]; then
  report_bypass
  say "PRESENT: each long branch is protected. Nothing was sent."
  exit 0
fi

if ! EXISTING=$(api "repos/$REPO/rulesets?per_page=100&includes_parents=false" --jq '.[] | [(.id | tostring), .name] | @tsv'); then
  cannot "the host did not return the rulesets of $REPO: $(host_said)"
fi
EXISTING_ID=$(printf '%s\n' "$EXISTING" | NAME=$RULESET_NAME awk -F '\t' '$2 == ENVIRON["NAME"] { print $1; exit }')

if [ -n "$EXISTING_ID" ]; then
  err "NOT PROTECTED: a ruleset named \"$RULESET_NAME\" exists (id $EXISTING_ID) and does not cover each long branch."
  err "This script does not overwrite a ruleset. Build the edit from the full live ruleset:"
  err "  gh api repos/$REPO/rulesets/$EXISTING_ID > ruleset.json"
  err "  (edit ruleset.json: enforcement \"active\", each long branch under include, the rules \"deletion\" and \"non_fast_forward\")"
  err "  gh api -X PUT repos/$REPO/rulesets/$EXISTING_ID --input ruleset.json"
  err "A change of protection is the owner's act. Then run this script again."
  exit 1
fi

say "create: POST repos/$REPO/rulesets"
say "$PAYLOAD"
if ! NEW_ID=$(printf '%s\n' "$PAYLOAD" | api -X POST "repos/$REPO/rulesets" --input - --jq '.id'); then
  err "NOT PROTECTED: the host did not create the ruleset: $(host_said)"
  err "A ruleset is the owner's setting. Do not try another way. Give the owner this one command:"
  err "  JIDOKA_REPO=$REPO JIDOKA_LONG_BRANCHES=\"$LONG_BRANCHES\" checks/protect-long-branches.sh"
  exit 1
fi
say "created ruleset $NEW_ID \"$RULESET_NAME\""

survey
report_bypass
if [ "$UNPROTECTED" -gt 0 ]; then
  err "NOT PROTECTED: the ruleset exists and the host still applies no rule to $UNPROTECTED long branch(es). Read the ruleset: gh api repos/$REPO/rulesets/$NEW_ID"
  exit 1
fi
say "CREATED: each long branch is protected."
exit 0

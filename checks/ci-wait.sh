#!/usr/bin/env bash
# ci-wait.sh - wait until the checks of each pull request end, then print one
# line for each pull request.
#
# Usage: checks/ci-wait.sh <pull request number> [<pull request number> ...]
#
# Start it in the background and act on its exit (rule B-14). While it waits it
# prints nothing. At the end it prints one line for each pull request:
#   <number> GREEN <head commit>
#   <number> RED <head commit> <check>=<conclusion> ...
#   <number> PENDING <head commit> <check>=<status> ...   (only at the time limit)
#   <number> MERGED | CLOSED
# A pull request that is merged or closed ends its wait at once.
#
# It reads the head commit again at each look, so a push during the wait is
# read on its new commit. It merges nothing and starts no workflow.
#
# Environment:
#   JIDOKA_REPO        owner/name for gh.
#                      Default: read from the remote "origin" of this folder.
#   JIDOKA_CHECKS      names of the checks to wait for. Default: "check security".
#                      The list splits at spaces; separate the names with commas
#                      when a name holds a space.
#   JIDOKA_WAIT_EVERY  seconds between two looks. Default: 60
#   JIDOKA_WAIT_LIMIT  most seconds to wait. Default: 3600
#
# Exit codes:
#   0   each pull request is green, merged or closed
#   1   a check of a pull request ended in a state that is not a success
#   3   cannot check: a tool is missing, the host does not answer, or the time
#       limit passed while a check still ran (nothing is proved)
#   64  wrong usage

set -euo pipefail
set -f

err() { printf '%s\n' "$*" >&2; }

usage_error() {
  err "ci-wait: $*"
  err "usage: checks/ci-wait.sh <pull request number> [<pull request number> ...]"
  exit 64
}

cannot() {
  err "CANNOT CHECK: $*"
  exit 3
}

PRS=""
for arg; do
  case "$arg" in
    -h | --help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    -*) usage_error "unknown option: $arg" ;;
    "" | *[!0-9]*) usage_error "a pull request number must be digits only, not \"$arg\"" ;;
    *) PRS="$PRS $arg" ;;
  esac
done
if [ -z "$PRS" ]; then usage_error "name at least one pull request"; fi

CHECKS=${JIDOKA_CHECKS:-check security}
EVERY=${JIDOKA_WAIT_EVERY:-60}
LIMIT=${JIDOKA_WAIT_LIMIT:-3600}
case "$EVERY$LIMIT" in
  *[!0-9]*) usage_error "JIDOKA_WAIT_EVERY and JIDOKA_WAIT_LIMIT must be whole seconds" ;;
esac

command -v gh >/dev/null 2>&1 || cannot "the tool \"gh\" is not on the path. Install it and sign in."

if [ -n "${JIDOKA_REPO:-}" ]; then
  REPO=$JIDOKA_REPO
else
  ORIGIN_URL=$(git remote get-url origin 2>/dev/null) ||
    cannot "JIDOKA_REPO is not set and this folder has no remote \"origin\". Set JIDOKA_REPO=owner/name."
  REPO=$(printf '%s\n' "$ORIGIN_URL" | sed -E 's#/+$##; s#\.git$##; s#^.*[:/]([^/:]+/[^/:]+)$#\1#')
fi
case "$REPO" in
  */*/* | /* | */ | *[!A-Za-z0-9._/-]*) usage_error "the repository must be owner/name, not \"$REPO\"" ;;
  */*) ;;
  *) usage_error "the repository must be owner/name, not \"$REPO\"" ;;
esac

case "$CHECKS" in
  *,*) CHECK_LINES=$(printf '%s\n' "$CHECKS" | tr ',' '\n') ;;
  *) CHECK_LINES=$(printf '%s\n' "$CHECKS" | tr -s ' ' '\n') ;;
esac

ERRFILE=$(mktemp "${TMPDIR:-/tmp}/jidoka-ci-wait.XXXXXX")
trap 'rm -f "$ERRFILE"' EXIT

api() {
  gh api "$@" 2>"$ERRFILE" || cannot "the host did not answer: $(tr '\n' ' ' <"$ERRFILE")"
}

# look <pull request>: sets LINE and STATE (done-green, done-red, done-other, waiting).
look() {
  local pr=$1 info state merged sha runs statuses name found result failed pending
  info=$(api "repos/$REPO/pulls/$pr" --jq '[.state, (.merged | tostring), .head.sha] | @tsv')
  IFS=$'\t' read -r state merged sha <<<"$info"
  if [ -z "${sha:-}" ]; then cannot "the answer of the host for pull request $pr has an unknown shape."; fi
  if [ "$merged" = "true" ]; then LINE="$pr MERGED"; STATE=done-other; return; fi
  if [ "$state" != "open" ]; then LINE="$pr CLOSED"; STATE=done-other; return; fi
  runs=$(api --paginate "repos/$REPO/commits/$sha/check-runs?per_page=100" \
    --jq '.check_runs[] | [(.id | tostring), .status, (.conclusion // "-"), .name] | @tsv')
  statuses=$(api "repos/$REPO/commits/$sha/status?per_page=100" \
    --jq '.statuses[] | ["0", (if .state == "pending" then "pending" else "completed" end), .state, .context] | @tsv')
  failed=""
  pending=""
  while IFS= read -r name; do
    name=$(printf '%s\n' "$name" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    if [ -z "$name" ]; then continue; fi
    found=$(printf '%s\n%s\n' "$runs" "$statuses" | NAME=$name awk -F '\t' '
      BEGIN { name = ENVIRON["NAME"]; newest = -1 }
      $4 == name && ($1 + 0) > newest { newest = $1 + 0; status = $2; conclusion = $3 }
      END { if (newest < 0) print "missing -"; else print status " " conclusion }')
    case "$found" in
      "completed success") ;;
      completed\ *) result=${found#completed }; failed="$failed $name=$result" ;;
      *) result=${found% *}; pending="$pending $name=$result" ;;
    esac
  done <<<"$CHECK_LINES"
  if [ -n "$failed" ]; then
    LINE="$pr RED $sha$failed"; STATE=done-red
  elif [ -n "$pending" ]; then
    LINE="$pr PENDING $sha$pending"; STATE=waiting
  else
    LINE="$pr GREEN $sha"; STATE=done-green
  fi
}

START=$(date +%s)
WAITING=$PRS
RESULTS=""
RED=0
while :; do
  STILL=""
  for pr in $WAITING; do
    look "$pr"
    case "$STATE" in
      waiting) STILL="$STILL $pr"; PENDING_LINES="${PENDING_LINES:-}$LINE"$'\n' ;;
      done-red) RED=1; RESULTS="$RESULTS$LINE"$'\n' ;;
      *) RESULTS="$RESULTS$LINE"$'\n' ;;
    esac
  done
  if [ -z "$STILL" ]; then
    printf '%s' "$RESULTS"
    exit "$RED"
  fi
  if [ $(($(date +%s) - START + EVERY)) -ge "$LIMIT" ]; then
    printf '%s%s' "$RESULTS" "$PENDING_LINES"
    err "TIME LIMIT: $LIMIT seconds passed while a check still ran. Nothing is proved for a PENDING line."
    exit 3
  fi
  PENDING_LINES=""
  WAITING=$STILL
  sleep "$EVERY"
done

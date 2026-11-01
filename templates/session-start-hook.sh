#!/usr/bin/env bash
# session-start-hook.sh - hand the newest open handoff file to a fresh
# orchestrator session (rule B-13).
#
# Install it as a hook that runs when a session starts and when the context is
# cleared (in Claude Code: a SessionStart hook with the matcher "startup|clear").
# The tool adds what the hook prints to the context of the new session.
#
# Usage: session-start-hook.sh [session folder]
#   The folder defaults to JIDOKA_SESSION_DIR.
#
# It prints the newest file "handoff-*.md" of the folder that is not marked
# taken (a name that ends in ".taken.md") and is younger than
# JIDOKA_HANDOFF_HOURS (default 48). With no such file it prints nothing.
# It renames nothing: the new session marks the file taken itself.
#
# Exit code: always 0, so that a missing folder never blocks a session.

set -u
set -f

DIR=${1:-${JIDOKA_SESSION_DIR:-}}
HOURS=${JIDOKA_HANDOFF_HOURS:-48}
case "$HOURS" in "" | *[!0-9]*) HOURS=48 ;; esac
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then exit 0; fi

NEWEST=$(find "$DIR" -maxdepth 1 -type f -name 'handoff-*.md' ! -name '*.taken.md' -mmin "-$((HOURS * 60))" \
  -exec ls -t {} + 2>/dev/null | head -n 1)
if [ -z "$NEWEST" ]; then exit 0; fi

TAKEN="${NEWEST%.md}.taken.md"
printf 'An open handoff from the last orchestrator session is below: %s\n' "$NEWEST"
printf 'Read it whole. Mark it taken with: mv "%s" "%s"\n' "$NEWEST" "$TAKEN"
printf 'Then tell the owner in two lines what you take over, and go on from its "Next".\n\n'
cat "$NEWEST"
exit 0

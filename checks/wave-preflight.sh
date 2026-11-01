#!/usr/bin/env bash
# wave-preflight.sh - check the machine before a wave of workers starts.
#
# Usage: checks/wave-preflight.sh [--clean] [worktrees folder]
#
# The script checks:
#   - free disk against JIDOKA_MIN_FREE_GB
#   - the load average of the last minute against the number of cores
#   - that the remote answers and has the base branch
#   - how many worktrees exist, the state of each branch, and which worktrees
#     hold large folders that a build can make again
#
# With a worktrees folder, a worktree is each direct child of that folder that
# is the top of a git worktree. Without one, the script lists the worktrees of
# the repository in the current folder.
#
# --clean needs the worktrees folder. It removes only folders whose name is in
# JIDOKA_REGENERABLE, only in a worktree whose branch is merged or gone on the
# remote and that has no uncommitted change, and only when git ignores the
# folder and tracks no file in it. It prints each path before it removes it.
#
# Environment:
#   JIDOKA_MIN_FREE_GB   least free disk in GB. Default: 20
#   JIDOKA_BASE          base branch. Default: develop
#   JIDOKA_REMOTE        name of the remote. Default: origin
#   JIDOKA_REGENERABLE   folder names that a build can make again.
#                        Default: "build node_modules target dist"
#                        Add the build folders of your stack.
#   JIDOKA_LARGE_MB      a folder of this size or more is listed. Default: 200
#   JIDOKA_SCAN_DEPTH    how deep the script looks inside a worktree. Default: 4
#
# Exit codes:
#   0   each check passes
#   1   a check fails; do not start the wave
#   3   a check could not run
#   64  wrong usage

set -euo pipefail
set -f

say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

show_help() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

usage_error() {
  err "wave-preflight: $*"
  err "usage: checks/wave-preflight.sh [--clean] [worktrees folder]"
  exit 64
}

CLEAN=0
ROOT_ARG=""
for arg; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    -h | --help)
      show_help
      exit 0
      ;;
    -*) usage_error "unknown option: $arg" ;;
    *)
      if [ -n "$ROOT_ARG" ]; then usage_error "more than one worktrees folder"; fi
      ROOT_ARG=$arg
      ;;
  esac
done

MIN_FREE_GB=${JIDOKA_MIN_FREE_GB:-20}
BASE=${JIDOKA_BASE:-develop}
REMOTE=${JIDOKA_REMOTE:-origin}
REGENERABLE=${JIDOKA_REGENERABLE:-build node_modules target dist}
LARGE_MB=${JIDOKA_LARGE_MB:-200}
SCAN_DEPTH=${JIDOKA_SCAN_DEPTH:-4}

case "$MIN_FREE_GB$LARGE_MB$SCAN_DEPTH" in
  "" | *[!0-9]*) usage_error "JIDOKA_MIN_FREE_GB, JIDOKA_LARGE_MB and JIDOKA_SCAN_DEPTH must be whole numbers" ;;
esac

NAME_COUNT=0
for name in $REGENERABLE; do
  case "$name" in
    . | .. | .git | */* | *[\*\?\[]*) usage_error "JIDOKA_REGENERABLE may hold plain folder names only, not \"$name\"" ;;
  esac
  NAME_COUNT=$((NAME_COUNT + 1))
done
if [ "$NAME_COUNT" -eq 0 ]; then
  usage_error "JIDOKA_REGENERABLE names no folder"
fi

ROOT=""
if [ -n "$ROOT_ARG" ]; then
  if [ ! -d "$ROOT_ARG" ]; then usage_error "not a folder: $ROOT_ARG"; fi
  ROOT=$(cd "$ROOT_ARG" && pwd -P)
fi

if [ "$CLEAN" -eq 1 ]; then
  if [ -z "$ROOT" ]; then
    usage_error "--clean needs the worktrees folder, so that nothing outside it can be removed"
  fi
  HOME_REAL=""
  if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then HOME_REAL=$(cd "$HOME" && pwd -P); fi
  if [ "$ROOT" = "/" ] || [ "$ROOT" = "$HOME_REAL" ]; then
    usage_error "--clean refuses \"$ROOT\" as the worktrees folder: name the folder that holds only worktrees"
  fi
fi

# A worker can be busy in a worktree: read its state and take no lock there.
export GIT_OPTIONAL_LOCKS=0

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/jidoka-preflight.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT

FAILS=0
UNCHECKED=0
pass() { say "ok    $*"; }
fail() {
  say "FAIL  $*"
  FAILS=$((FAILS + 1))
}
unchecked() {
  say "NOT CHECKED  $*"
  UNCHECKED=$((UNCHECKED + 1))
}
info() { say "      $*"; }

mb() {
  awk -v kb="$1" 'BEGIN { printf "%d", kb / 1024 }'
}

is_regenerable_name() {
  local n
  for n in $REGENERABLE; do
    if [ "$n" = "$1" ]; then return 0; fi
  done
  return 1
}

# ---- worktrees ---------------------------------------------------------------

WORKTREES="$TMPD/worktrees"
: >"$WORKTREES"
SKIPPED_CHILDREN=0
HAVE_LIST=1

if [ -n "$ROOT" ]; then
  find "$ROOT" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort >"$TMPD/children"
  while IFS= read -r child; do
    if [ -z "$child" ]; then continue; fi
    top=$(git -C "$child" rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$top" ] && [ "$(cd "$top" && pwd -P)" = "$child" ]; then
      printf '%s\n' "$child" >>"$WORKTREES"
    else
      SKIPPED_CHILDREN=$((SKIPPED_CHILDREN + 1))
    fi
  done <"$TMPD/children"
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git worktree list --porcelain | sed -n 's/^worktree //p' >"$WORKTREES"
else
  HAVE_LIST=0
fi

WORKTREE_COUNT=$(awk 'END { print NR }' "$WORKTREES")

# Prints the path of a file with the heads of the remote, one "commit<TAB>ref"
# on each line. Asks the remote one time for each repository. Fails when the
# remote does not answer.
remote_heads() {
  local common key file
  common=$(cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
  key=$(printf '%s' "$common" | cksum | awk '{ print $1 }')
  file="$TMPD/heads.$key"
  if [ ! -e "$file" ] && [ ! -e "$file.failed" ]; then
    if GIT_TERMINAL_PROMPT=0 git -C "$1" ls-remote --heads "$REMOTE" >"$file.part" 2>"$file.failed.part"; then
      mv "$file.part" "$file"
    else
      mv "$file.failed.part" "$file.failed"
    fi
  fi
  if [ -e "$file" ]; then
    printf '%s\n' "$file"
    return 0
  fi
  return 1
}

remote_error() {
  local common key
  common=$(cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
  key=$(printf '%s' "$common" | cksum | awk '{ print $1 }')
  tr '\n' ' ' <"$TMPD/heads.$key.failed"
}

head_commit() {
  REF="refs/heads/$2" awk -F '\t' '$2 == ENVIRON["REF"] { print $1; exit }' "$1"
}

# Sets STATE and FINISHED for one worktree.
#   merged       the tip is in the base through a merge commit
#   gone         the branch was pushed and the remote no longer has it
#   active       the remote has the branch and the base does not hold its tip
#   no commits   the tip is a commit of the base itself: work has not started
#   the base branch
#   not pushed   the remote never had the branch
#   detached     no branch
#   unknown      the remote does not answer
classify() {
  local wt=$1 heads tip base_commit base_point on_chain
  STATE="unknown"
  FINISHED=0
  BRANCH=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  if [ -z "$BRANCH" ]; then
    STATE="detached"
    return 0
  fi
  if ! heads=$(remote_heads "$wt"); then
    STATE="unknown"
    return 0
  fi
  if [ -z "$(head_commit "$heads" "$BRANCH")" ]; then
    if git -C "$wt" show-ref --verify --quiet "refs/remotes/$REMOTE/$BRANCH" ||
      [ "$(git -C "$wt" config --get "branch.$BRANCH.merge" || true)" = "refs/heads/$BRANCH" ]; then
      STATE="gone"
      FINISHED=1
    else
      STATE="not pushed"
    fi
    return 0
  fi
  if [ "$BRANCH" = "$BASE" ]; then
    STATE="the base branch"
    return 0
  fi
  STATE="active"
  tip=$(git -C "$wt" rev-parse HEAD)
  base_commit=$(head_commit "$heads" "$BASE")
  base_point=""
  if [ -n "$base_commit" ] && git -C "$wt" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
    base_point=$base_commit
  elif git -C "$wt" show-ref --verify --quiet "refs/remotes/$REMOTE/$BASE"; then
    base_point="refs/remotes/$REMOTE/$BASE"
  fi
  if [ -z "$base_point" ]; then
    return 0
  fi
  if git -C "$wt" merge-base --is-ancestor "$tip" "$base_point"; then
    on_chain=$(git -C "$wt" rev-list --first-parent "$base_point" | grep -c -x "$tip" || true)
    if [ "$on_chain" = "0" ]; then
      STATE="merged"
      FINISHED=1
    else
      STATE="no commits"
    fi
  fi
  return 0
}

# Prints each folder of a worktree whose name is in JIDOKA_REGENERABLE.
regenerable_folders() {
  local wt=$1 n
  set --
  for n in $REGENERABLE; do
    if [ $# -gt 0 ]; then set -- "$@" -o; fi
    set -- "$@" -name "$n"
  done
  find "$wt" -mindepth 1 -maxdepth "$SCAN_DEPTH" \
    \( -type d -name .git -prune \) -o \
    \( -type d \( "$@" \) -prune -print \)
}

REMOVED=0
REMOVED_KB=0
KEPT=0

# Removes one folder, or says why it stays.
remove_folder() {
  local wt=$1 path=$2 kb=$3 parent full rel name
  if [ -z "$path" ] || [ -z "$wt" ] || [ -z "$ROOT" ]; then
    err "refuse: an empty path"
    exit 1
  fi
  if [ -L "$path" ] || [ ! -d "$path" ]; then
    say "kept:   $path (not a real folder)"
    KEPT=$((KEPT + 1))
    return 0
  fi
  parent=$(cd "$(dirname "$path")" && pwd -P)
  name=$(basename "$path")
  full="$parent/$name"
  case "$full" in
    "$ROOT"/*/*) ;;
    *)
      err "refuse: $full is not inside a worktree under $ROOT"
      exit 1
      ;;
  esac
  case "$full" in
    "$wt"/*) ;;
    *)
      err "refuse: $full is not inside the worktree $wt"
      exit 1
      ;;
  esac
  if ! is_regenerable_name "$name"; then
    err "refuse: \"$name\" is not in JIDOKA_REGENERABLE"
    exit 1
  fi
  rel=${full#"$wt"/}
  if [ -n "$(git -C "$wt" ls-files -- "$rel")" ]; then
    say "kept:   $full (git tracks files in it)"
    KEPT=$((KEPT + 1))
    return 0
  fi
  if ! git -C "$wt" check-ignore -q -- "$rel"; then
    say "kept:   $full (git does not ignore it, so a build may not make it again)"
    KEPT=$((KEPT + 1))
    return 0
  fi
  say "remove: $full ($(mb "$kb") MB)"
  rm -rf -- "$full"
  REMOVED=$((REMOVED + 1))
  REMOVED_KB=$((REMOVED_KB + kb))
}

# ---- the checks --------------------------------------------------------------

say "wave preflight"

DISK_DIR=${ROOT:-$PWD}

free_gb() {
  df -Pk "$DISK_DIR" | awk 'NR == 2 { printf "%d", $4 / 1048576 }'
}

CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
case "$CORES" in
  "" | *[!0-9]*) CORES=$(sysctl -n hw.ncpu 2>/dev/null || true) ;;
esac
LOADS=$(LC_ALL=C uptime | sed -E 's/.*load averages?: *//' | tr -d ',')
LOAD_1=${LOADS%% *}
case "$CORES" in
  "" | *[!0-9]*) unchecked "load: the number of cores is not known on this system" ;;
  *)
    case "$LOAD_1" in
      "" | *[!0-9.]*) unchecked "load: the load average is not readable on this system" ;;
      *)
        if awk -v l="$LOAD_1" -v c="$CORES" 'BEGIN { exit !(l > c) }'; then
          fail "load: $LOAD_1 in the last minute on $CORES cores (all three: $LOADS). The machine is busy. Wait, or start fewer workers. Do not run a release build and a wave on one machine at one time."
        else
          pass "load: $LOAD_1 in the last minute on $CORES cores (all three: $LOADS)"
        fi
        ;;
    esac
    ;;
esac

REPO_DIR=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_DIR=$PWD
elif [ "$WORKTREE_COUNT" -gt 0 ]; then
  REPO_DIR=$(sed -n '1p' "$WORKTREES")
fi

if [ -z "$REPO_DIR" ]; then
  unchecked "base: no repository here. Run the script from the repository, or name a worktrees folder that holds a worktree."
elif HEADS_FILE=$(remote_heads "$REPO_DIR"); then
  BASE_COMMIT=$(head_commit "$HEADS_FILE" "$BASE")
  if [ -n "$BASE_COMMIT" ]; then
    pass "base: the remote \"$REMOTE\" answers and has \"$BASE\" ($BASE_COMMIT)"
  else
    fail "base: the remote \"$REMOTE\" answers and has no branch \"$BASE\". Read JIDOKA_BASE. If a long branch is gone, stop and tell the owner."
  fi
else
  fail "base: the remote \"$REMOTE\" does not answer: $(remote_error "$REPO_DIR")"
  info "Test the link, the name resolver and a direct address, in that order. Do not change a network setting of the machine: ask the owner."
fi

FREEABLE_KB=0
if [ "$HAVE_LIST" -eq 0 ]; then
  unchecked "worktrees: no worktrees folder was named and this folder is not a repository"
else
  if [ -n "$ROOT" ]; then
    info "worktrees: $WORKTREE_COUNT under $ROOT. Other folders there, not worktrees and not touched: $SKIPPED_CHILDREN"
  else
    info "worktrees: $WORKTREE_COUNT of the repository in $PWD"
  fi
  if [ "$CLEAN" -eq 1 ]; then
    info "clean: only folders named: $REGENERABLE"
    info "clean: only in a worktree whose branch is merged or gone on \"$REMOTE\""
  fi
  while IFS= read -r wt; do
    if [ -z "$wt" ]; then continue; fi
    if [ ! -d "$wt" ]; then
      info "$wt: the folder is missing. Run \"git worktree prune\" after you read why."
      continue
    fi
    classify "$wt"
    DIRTY=$(git -C "$wt" status --porcelain --untracked-files=no | awk 'END { print NR }')
    regenerable_folders "$wt" >"$TMPD/folders"
    TOTAL_KB=0
    : >"$TMPD/sized"
    while IFS= read -r folder; do
      if [ -z "$folder" ]; then continue; fi
      kb=$(du -sk "$folder" 2>/dev/null | awk '{ print $1 }' || true)
      case "$kb" in "" | *[!0-9]*) kb=0 ;; esac
      TOTAL_KB=$((TOTAL_KB + kb))
      printf '%s\t%s\n' "$kb" "$folder" >>"$TMPD/sized"
    done <"$TMPD/folders"
    NOTE=""
    if [ "$FINISHED" -eq 1 ] && [ "$DIRTY" -gt 0 ]; then
      NOTE=". Uncommitted changes in tracked files: $DIRTY. Read them before anything else"
    fi
    SHOWN=$wt
    if [ -n "$ROOT" ]; then SHOWN=${wt#"$ROOT"/}; fi
    info "$SHOWN: branch ${BRANCH:--}, $STATE, $(mb "$TOTAL_KB") MB that a build can make again$NOTE"
    while IFS=$'\t' read -r kb folder; do
      if [ -z "$folder" ]; then continue; fi
      if [ "$(mb "$kb")" -ge "$LARGE_MB" ]; then
        info "  large: $folder ($(mb "$kb") MB)"
      fi
    done <"$TMPD/sized"
    if [ "$FINISHED" -eq 1 ] && [ "$DIRTY" -eq 0 ]; then
      if [ "$CLEAN" -eq 1 ]; then
        while IFS=$'\t' read -r kb folder; do
          if [ -z "$folder" ]; then continue; fi
          remove_folder "$wt" "$folder" "$kb"
        done <"$TMPD/sized"
      else
        FREEABLE_KB=$((FREEABLE_KB + TOTAL_KB))
      fi
    fi
  done <"$WORKTREES"
fi

if [ "$CLEAN" -eq 1 ]; then
  info "clean: folders removed: $REMOVED, about $(mb "$REMOVED_KB") MB. Folders kept in finished worktrees: $KEPT"
elif [ "$FREEABLE_KB" -gt 0 ] && [ -n "$ROOT" ]; then
  info "NEXT: about $(mb "$FREEABLE_KB") MB sits in finished worktrees. To free it: checks/wave-preflight.sh --clean \"$ROOT\""
elif [ "$FREEABLE_KB" -gt 0 ]; then
  info "NEXT: about $(mb "$FREEABLE_KB") MB sits in finished worktrees. To free it, run the script with --clean and the worktrees folder."
fi

FREE_GB=$(free_gb)
case "$FREE_GB" in
  "" | *[!0-9]*) unchecked "disk: free space at $DISK_DIR is not readable" ;;
  *)
    if [ "$FREE_GB" -lt "$MIN_FREE_GB" ]; then
      fail "disk: $FREE_GB GB free at $DISK_DIR; the minimum is $MIN_FREE_GB GB. Free space first: run --clean on the worktrees folder, then remove finished worktrees with \"git worktree remove\"."
    else
      pass "disk: $FREE_GB GB free at $DISK_DIR; the minimum is $MIN_FREE_GB GB"
    fi
    ;;
esac

if [ "$FAILS" -gt 0 ]; then
  say "PREFLIGHT: FAIL. Failed checks: $FAILS. Do not start the wave."
  exit 1
fi
if [ "$UNCHECKED" -gt 0 ]; then
  say "PREFLIGHT: NOT PROVED. Checks that did not run: $UNCHECKED. Fix the cause and run again."
  exit 3
fi
say "PREFLIGHT: pass"
exit 0

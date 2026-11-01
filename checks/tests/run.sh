#!/usr/bin/env bash
# run.sh - offline tests of the five checks.
#
# Usage: checks/tests/run.sh [checks folder]
#
# The tests call no host and change no repository. They work in a temporary
# folder and remove it at the end. A fake "gh", a fake "git" and a fake
# "uptime" answer from files in that folder. The fake gh runs each --jq filter
# with the real jq, so jq must be on the path.
#
# What the tests do not prove: the real answers of the host, and the answers of
# the real git about a branch that is merged or gone. Prove those one time on a
# scratch repository before you trust a script on a new host.
#
# Name another checks folder to test a changed copy of the scripts.
#
# Exit codes:
#   0   each test passes
#   1   a test fails
#   3   a tool is missing, so some tests did not run
#   64  wrong usage: the folder does not hold the five scripts

set -u
set -f

usage_error() {
  printf 'run: %s\n' "$*" >&2
  printf 'usage: checks/tests/run.sh [checks folder]\n' >&2
  exit 64
}

case "${1:-}" in
  -h | --help)
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 0
    ;;
  -*) usage_error "unknown option: $1" ;;
esac
if [ $# -gt 1 ]; then usage_error "at most one checks folder"; fi

HERE=$(cd "$(dirname "$0")" && pwd -P)
CHECKS=${1:-$(dirname "$HERE")}
if [ ! -d "$CHECKS" ]; then usage_error "not a folder: $CHECKS"; fi
CHECKS=$(cd "$CHECKS" && pwd -P)
for script in merge-guard.sh protect-long-branches.sh wave-preflight.sh scrub.sh ci-wait.sh scrub-words.example; do
  if [ ! -f "$CHECKS/$script" ]; then
    usage_error "no $script in $CHECKS: name the folder that holds the five scripts"
  fi
done

unset JIDOKA_REPO JIDOKA_BASE JIDOKA_LONG_BRANCHES JIDOKA_CHECKS JIDOKA_REMOTE
unset JIDOKA_MIN_FREE_GB JIDOKA_REGENERABLE JIDOKA_LARGE_MB JIDOKA_SCAN_DEPTH
unset JIDOKA_SCRUB_ALLOW JIDOKA_SCRUB_SKIP JIDOKA_SCRUB_QUIET JIDOKA_RULESET_NAME JIDOKA_WAIT_EVERY JIDOKA_WAIT_LIMIT

WORK=$(mktemp -d "${TMPDIR:-/tmp}/jidoka-tests.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 3

PASSED=0
FAILED=0
NOT_RUN=0
OUT=""
RC=0

pass() {
  PASSED=$((PASSED + 1))
  printf 'pass  %s\n' "$1"
}

fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL  %s\n' "$1"
  printf '%s\n' "$OUT" | sed 's/^/        | /'
}

# run <script> [arguments]: keeps the output in OUT and the exit code in RC.
run() {
  local script=$1
  shift
  OUT=$(/bin/bash "$CHECKS/$script" "$@" 2>&1)
  RC=$?
}

# expect <name> <exit code> <text that the output must hold>
expect() {
  if [ "$RC" = "$2" ] && printf '%s\n' "$OUT" | grep -q -F -- "$3"; then
    pass "$1 (exit $RC)"
  else
    fail "$1: exit $RC, wanted $2 and the text: $3"
  fi
}

# holds <name> <text>: the last output must hold the text.
holds() {
  if printf '%s\n' "$OUT" | grep -q -F -- "$2"; then pass "$1"; else fail "$1: the output lacks: $2"; fi
}

# lacks <name> <text>: the last output must not hold the text.
lacks() {
  if printf '%s\n' "$OUT" | grep -q -F -- "$2"; then fail "$1: the output holds: $2"; else pass "$1"; fi
}

# ---- the fakes ---------------------------------------------------------------

BIN="$WORK/bin"
mkdir -p "$BIN"

cat >"$BIN/gh" <<'EOF'
#!/bin/bash
# Fake gh. It answers "gh api" from JSON files in $FAKE_GH_DIR.
[ "$1" = api ] || { echo "fake gh: only api" >&2; exit 99; }
shift
method=GET; filter=""; endpoint=""; fields=""; body=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X | --method) method=$2; shift 2 ;;
    --jq | -q) filter=$2; shift 2 ;;
    -f | -F | -H) fields="$fields $2"; shift 2 ;;
    --input) body=$(cat); shift 2 ;;
    --paginate) shift ;;
    *) endpoint=$1; shift ;;
  esac
done
key=$(printf '%s' "$endpoint" | sed 's/[?].*$//; s#[^A-Za-z0-9._-]#_#g')
printf '%s %s%s\n' "$method" "$endpoint" "$fields" >>"$FAKE_GH_DIR/calls.log"
if [ -n "$body" ]; then printf '%s\n' "$body" >"$FAKE_GH_DIR/last-body.json"; fi
if [ -f "$FAKE_GH_DIR/$method.$key.error" ]; then
  echo "gh: $(cat "$FAKE_GH_DIR/$method.$key.error")" >&2
  exit 1
fi
file="$FAKE_GH_DIR/$method.$key.json"
if [ ! -f "$file" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
if [ -n "$filter" ]; then jq -r "$filter" "$file"; else cat "$file"; fi
if [ -f "$FAKE_GH_DIR/$method.$key.after" ]; then . "$FAKE_GH_DIR/$method.$key.after"; fi
exit 0
EOF

cat >"$BIN/git" <<'EOF'
#!/bin/bash
# Fake git. Its answers come from the folder .fake of each made-up worktree.
dir=$PWD
if [ "$1" = "-C" ]; then dir=$2; shift 2; fi
fx="$dir/.fake"
last=""; unmatch=0
for a; do last=$a; if [ "$a" = "--error-unmatch" ]; then unmatch=1; fi; done
case "$1" in
  rev-parse)
    case "$2" in
      --show-toplevel) [ -d "$fx" ] || exit 128; (cd "$dir" && pwd -P) ;;
      --is-inside-work-tree) [ -d "$fx" ] || exit 128; echo true ;;
      --git-common-dir) echo "$FAKE_GIT_COMMON" ;;
      HEAD) cat "$fx/tip" ;;
      *) exit 99 ;;
    esac ;;
  remote) exit 2 ;;
  symbolic-ref) [ -f "$fx/branch" ] || exit 1; cat "$fx/branch" ;;
  status) if [ -f "$fx/dirty" ]; then cat "$fx/dirty"; fi ;;
  ls-remote)
    printf 'ls-remote\n' >>"$FAKE_GIT_LOG"
    if [ -n "${FAKE_GIT_REMOTE_DOWN:-}" ]; then echo "fatal: the remote does not answer (fake)" >&2; exit 128; fi
    cat "$FAKE_GIT_HEADS" ;;
  show-ref) [ -f "$fx/pushed" ] ;;
  config) exit 1 ;;
  cat-file) exit 0 ;;
  merge-base) [ -f "$fx/ancestor" ] ;;
  rev-list) cat "$FAKE_GIT_CHAIN" ;;
  check-ignore) grep -q -x -- "$last" "$fx/ignored" ;;
  ls-files)
    if [ "$unmatch" -eq 1 ]; then grep -q -x -- "$last" "$fx/tracked"; else grep -x -- "$last" "$fx/tracked" || true; fi ;;
  *) echo "fake git: unknown call: $*" >&2; exit 99 ;;
esac
EOF

cat >"$BIN/uptime" <<'EOF'
#!/bin/bash
# Fake uptime: a quiet machine, or the line in $FAKE_UPTIME.
echo "${FAKE_UPTIME:-12:00  up 3 days,  2:10, 2 users, load averages: 0.10 0.20 0.30}"
EOF

chmod +x "$BIN/gh" "$BIN/git" "$BIN/uptime"
REAL_PATH=$PATH
export PATH="$BIN:$PATH"
export FAKE_GIT_LOG="$WORK/git.log" FAKE_GIT_HEADS="$WORK/heads.tsv" FAKE_GIT_CHAIN="$WORK/chain.txt" FAKE_GIT_COMMON="$WORK/common"
mkdir -p "$FAKE_GIT_COMMON"
: >"$FAKE_GIT_LOG"

# ---- scrub.sh ----------------------------------------------------------------

printf '\n== scrub.sh\n'
S="$WORK/scrub"
mkdir -p "$S/dirty/docs" "$S/dirty/.git" "$S/dirty/zorblat-notes" "$S/clean" "$S/lists/.fake"
# The test addresses are put together here, so that this file holds none.
AT="@"
SCHEME="https:""//"
PLAIN_SCHEME="http:""//"
WWW="www"
ADDRESS="pat${AT}fernhollow.test"
LINK="${SCHEME}fernhollow.test/x"
BARE_LINK="${WWW}.fernhollow.test"
IMAGE="icon${AT}2x.png"
{
  printf 'A line with nothing.\n'
  printf 'The Zorblat app is here.\n'
  printf 'Write to %s or read %s.\n' "$ADDRESS" "$LINK"
  printf 'Allowed: someone%sexample.com, %sdocs.example.org/page. And %slocalhost:8080/a\n' "$AT" "$SCHEME" "$PLAIN_SCHEME"
  printf 'Ticket #123 of project quuxmill.\n'
} >"$S/dirty/docs/a.md"
printf 'see %s and an image named %s\n' "$BARE_LINK" "$IMAGE" >"$S/dirty/b.txt"
printf 'zorblat inside the git folder\n' >"$S/dirty/.git/config"
printf 'a plain file\n' >"$S/dirty/zorblat-notes/readme.txt"
printf '\000\001zorblat in a binary file\000' >"$S/dirty/blob.bin"
cp "$CHECKS/scrub-words.example" "$S/dirty/.jidoka-scrub-words"
printf 'All is fine here.\nSee %sexample.com. Write to team%sexample.org.\n' "$SCHEME" "$AT" >"$S/clean/ok.md"
cp "$CHECKS/scrub-words.example" "$S/lists/words.txt"
: >"$S/lists/.fake/tracked"

run scrub.sh "$S/dirty"
expect "scrub: finds the hits of a dirty folder" 1 'docs/a.md:2: word "Zorblat"'
holds "scrub: a pattern with a number sign" 'docs/a.md:5: word "#123"'
holds "scrub: a pattern with an optional part" 'docs/a.md:5: word "project quuxmill"'
holds "scrub: an email address" "docs/a.md:3: email address \"$ADDRESS\""
holds "scrub: a link, without the full stop after it" "docs/a.md:3: URL \"$LINK\""
holds "scrub: a link without a scheme" "b.txt:1: URL \"$BARE_LINK\""
holds "scrub: a word in a file name" 'zorblat-notes/readme.txt:0: word in the file name "zorblat"'
lacks "scrub: reserved example domains are allowed" "example."
lacks "scrub: the local machine is allowed" "localhost"
lacks "scrub: the git folder is not searched" ".git/config"
lacks "scrub: a binary file is not searched" "blob.bin"
lacks "scrub: the words file is not searched" ".jidoka-scrub-words:"
holds "scrub: counts the hits" "Hits: 8. Files with a hit: 3 of 4."

run scrub.sh "$S/clean"
expect "scrub: clean with no words file" 0 "scrub: clean."
holds "scrub: says loudly that no word was checked" "NO WORD WAS CHECKED"

run scrub.sh "$S/clean" "$S/lists/words.txt"
expect "scrub: clean with a words file" 0 "Checked: 10 words, email addresses and URLs."

JIDOKA_SCRUB_QUIET=1 run scrub.sh "$S/dirty"
expect "scrub: quiet mode names the line and not the word" 1 'docs/a.md:2: word (text not shown)'
lacks "scrub: quiet mode prints no word" "orblat"
lacks "scrub: quiet mode prints no match of a pattern" "quuxmill"
holds "scrub: quiet mode hides a file name that holds a word" "its name holds a word):0: word in the file name (text not shown)"
holds "scrub: quiet mode still prints an address" "docs/a.md:3: email address \"$ADDRESS\""
holds "scrub: quiet mode counts the same hits" "Hits: 8. Files with a hit: 3 of 4."

printf 'fine\n(unclosed\n' >"$S/lists/quiet-bad.txt"
JIDOKA_SCRUB_QUIET=1 run scrub.sh "$S/clean" "$S/lists/quiet-bad.txt"
expect "scrub: quiet mode does not print a bad pattern" 3 "the pattern number 2 (text not shown)"
lacks "scrub: quiet mode keeps the bad pattern out of the output" "unclosed"

printf '# images\n[%s][0-9]x\\.png$\n' "$AT" >"$S/lists/allow.txt"
JIDOKA_SCRUB_ALLOW="$S/lists/allow.txt" run scrub.sh "$S/dirty"
expect "scrub: the allow list excuses an address" 1 "Hits: 7."
lacks "scrub: the allowed address is not printed" "2x.png"
holds "scrub: the allow list never excuses a word" 'word "Zorblat"'

printf 'fine\n(unclosed\n' >"$S/lists/bad.txt"
run scrub.sh "$S/clean" "$S/lists/bad.txt"
expect "scrub: a pattern that grep cannot read stops the check" 3 "is not a valid extended regular expression"

printf 'a*\n' >"$S/lists/wide.txt"
run scrub.sh "$S/clean" "$S/lists/wide.txt"
expect "scrub: a pattern that matches every line stops the check" 3 "matches every line"

printf 'words.txt\n' >"$S/lists/.fake/tracked"
run scrub.sh "$S/clean" "$S/lists/words.txt"
expect "scrub: a words file in version control is a hit" 1 "the words file is in version control"
: >"$S/lists/.fake/tracked"

run scrub.sh
expect "scrub: no folder" 64 "usage:"
run scrub.sh "$S/clean" "$S/lists/none.txt"
expect "scrub: a words file that does not exist" 64 "no words file at"

# ---- wave-preflight.sh -------------------------------------------------------

printf '\n== wave-preflight.sh\n'
W="$WORK/wts"

blob() {
  mkdir -p "$1"
  dd if=/dev/zero of="$1/blob" bs=1024 count="$2" 2>/dev/null
}

# worktree <name> <branch> <tip> [marks]: one made-up worktree.
worktree() {
  local d="$W/$1" mark
  mkdir -p "$d/.fake" "$d/src"
  echo code >"$d/src/main.txt"
  if [ -n "$2" ]; then echo "$2" >"$d/.fake/branch"; fi
  echo "$3" >"$d/.fake/tip"
  : >"$d/.fake/ignored"
  : >"$d/.fake/tracked"
  shift 3
  for mark; do : >"$d/.fake/$mark"; done
}

make_worktrees() {
  rm -rf "$W" "$WORK/outside"
  mkdir -p "$W" "$WORK/outside/precious"
  echo keep >"$WORK/outside/precious/keep.txt"
  worktree wt-merged feat/merged aaa1 ancestor pushed
  blob "$W/wt-merged/build" 2048
  blob "$W/wt-merged/app/node_modules" 100
  blob "$W/wt-merged/dist" 10
  blob "$W/wt-merged/target" 10
  printf 'build\napp/node_modules\ndist\n' >"$W/wt-merged/.fake/ignored"
  printf 'dist\n' >"$W/wt-merged/.fake/tracked"
  ln -s "$WORK/outside/precious" "$W/wt-merged/node_modules"
  worktree wt-gone feat/gone bbb1 pushed
  blob "$W/wt-gone/build" 10
  echo build >"$W/wt-gone/.fake/ignored"
  worktree wt-active feat/active ccc1 pushed
  blob "$W/wt-active/build" 10
  echo build >"$W/wt-active/.fake/ignored"
  worktree wt-fresh feat/fresh chain2 ancestor pushed
  blob "$W/wt-fresh/node_modules" 10
  echo node_modules >"$W/wt-fresh/.fake/ignored"
  worktree wt-unpushed feat/new ddd1
  blob "$W/wt-unpushed/build" 10
  echo build >"$W/wt-unpushed/.fake/ignored"
  worktree wt-dirty feat/dirty eee1 ancestor pushed
  blob "$W/wt-dirty/build" 10
  echo build >"$W/wt-dirty/.fake/ignored"
  echo " M src/main.txt" >"$W/wt-dirty/.fake/dirty"
  worktree wt-detached "" fff1
  blob "$W/wt-detached/build" 10
  echo build >"$W/wt-detached/.fake/ignored"
  worktree dist feat/rootname ggg1 ancestor pushed
  blob "$W/dist/build" 10
  echo build >"$W/dist/.fake/ignored"
  worktree "wt space" feat/space hhh1 ancestor pushed
  blob "$W/wt space/sub dir/build" 10
  echo "sub dir/build" >"$W/wt space/.fake/ignored"
  mkdir -p "$W/notes"
  blob "$W/notes/build" 10
}

blobs() {
  find "$W" "$WORK/outside" -type f \( -name blob -o -name keep.txt \) | sed "s#^$WORK/##" | LC_ALL=C sort
}

{
  printf 'base9\trefs/heads/develop\n'
  printf 'm0\trefs/heads/main\n'
  printf 'aaa1\trefs/heads/feat/merged\n'
  printf 'ccc1\trefs/heads/feat/active\n'
  printf 'chain2\trefs/heads/feat/fresh\n'
  printf 'eee1\trefs/heads/feat/dirty\n'
  printf 'ggg1\trefs/heads/feat/rootname\n'
  printf 'hhh1\trefs/heads/feat/space\n'
} >"$FAKE_GIT_HEADS"
printf 'base9\nchain2\nchain1\n' >"$FAKE_GIT_CHAIN"

make_worktrees
BEFORE=$(blobs)
export JIDOKA_MIN_FREE_GB=0

JIDOKA_LARGE_MB=1 run wave-preflight.sh "$W"
expect "preflight: passes on a quiet machine" 0 "PREFLIGHT: pass"
holds "preflight: the base answers" 'ok    base: the remote "origin" answers and has "develop" (base9)'
holds "preflight: counts the worktrees and the other folders" "worktrees: 9 under $W. Other folders there, not worktrees and not touched: 1"
holds "preflight: a branch that a merge commit took is merged" "wt-merged: branch feat/merged, merged, 2 MB"
holds "preflight: a pushed branch that the remote lost is gone" "wt-gone: branch feat/gone, gone,"
holds "preflight: a branch that the base does not hold is active" "wt-active: branch feat/active, active,"
holds "preflight: a branch with no commit of its own is not finished" "wt-fresh: branch feat/fresh, no commits,"
holds "preflight: a branch that was never pushed is not gone" "wt-unpushed: branch feat/new, not pushed,"
holds "preflight: a detached worktree" "wt-detached: branch -, detached,"
holds "preflight: names uncommitted changes in a finished worktree" "wt-dirty: branch feat/dirty, merged, 0 MB that a build can make again. Uncommitted changes in tracked files: 1."
holds "preflight: lists a large folder" "large: $W/wt-merged/build (2 MB)"
holds "preflight: offers the clean" "checks/wave-preflight.sh --clean \"$W\""
if [ "$(grep -c ls-remote "$FAKE_GIT_LOG")" = "1" ]; then pass "preflight: asks the remote one time"; else fail "preflight: asks the remote one time"; fi
if [ "$(blobs)" = "$BEFORE" ]; then pass "preflight: a report removes nothing"; else fail "preflight: a report removes nothing"; fi

FAKE_GIT_REMOTE_DOWN=1 run wave-preflight.sh --clean "$W"
expect "preflight: fails when the remote does not answer" 1 'FAIL  base: the remote "origin" does not answer'
holds "preflight: tells not to change the network" "Do not change a network setting of the machine: ask the owner."
if [ "$(blobs)" = "$BEFORE" ]; then pass "preflight: a clean removes nothing while the remote is down"; else fail "preflight: a clean removes nothing while the remote is down"; fi

run wave-preflight.sh --clean "$W"
expect "preflight: clean" 0 "clean: folders removed: 5"
holds "preflight: prints a path before it removes it" "remove: $W/wt-merged/build (2 MB)"
holds "preflight: keeps a folder that git tracks" "kept:   $W/wt-merged/dist (git tracks files in it)"
holds "preflight: keeps a folder that git does not ignore" "kept:   $W/wt-merged/target (git does not ignore it"
AFTER=$(blobs)
WANT=$(printf '%s\n' "$BEFORE" | grep -v -x -F \
  -e "wts/wt-merged/build/blob" -e "wts/wt-merged/app/node_modules/blob" -e "wts/wt-gone/build/blob" \
  -e "wts/dist/build/blob" -e "wts/wt space/sub dir/build/blob")
OUT=$(printf 'left on disk:\n%s' "$AFTER")
if [ "$AFTER" = "$WANT" ]; then pass "preflight: removes five folders and nothing more"; else fail "preflight: removes five folders and nothing more"; fi
if [ -d "$W/dist/src" ] && [ -L "$W/wt-merged/node_modules" ] && [ -f "$WORK/outside/precious/keep.txt" ]; then
  pass "preflight: keeps a worktree with a listed name, a link, and the folder behind the link"
else
  fail "preflight: keeps a worktree with a listed name, a link, and the folder behind the link"
fi

FAKE_UPTIME="12:00 up 1 day, 1 user, load average: 900.00, 2.00, 1.00" run wave-preflight.sh "$W"
expect "preflight: fails on a busy machine" 1 "FAIL  load: 900.00 in the last minute"
holds "preflight: says not to run a release build beside a wave" "Do not run a release build and a wave on one machine at one time."

JIDOKA_MIN_FREE_GB=100000000 run wave-preflight.sh "$W"
expect "preflight: fails under the disk minimum" 1 "the minimum is 100000000 GB"

mkdir -p "$WORK/plain/notes/build"
run wave-preflight.sh "$WORK/plain"
expect "preflight: a base that cannot be read is not a pass" 3 "PREFLIGHT: NOT PROVED"

run wave-preflight.sh --clean
expect "preflight: clean needs the folder" 64 "--clean needs the worktrees folder"
run wave-preflight.sh --clean /
expect "preflight: clean refuses the root folder" 64 "--clean refuses"
run wave-preflight.sh --clean "$HOME"
expect "preflight: clean refuses the home folder" 64 "--clean refuses"
JIDOKA_REGENERABLE="build ../x" run wave-preflight.sh "$W"
expect "preflight: refuses a path in the list of names" 64 "plain folder names only"
JIDOKA_REGENERABLE=".git" run wave-preflight.sh "$W"
expect "preflight: refuses the git folder in the list of names" 64 "plain folder names only"

# The guard of the removal, called alone with paths that the search never gives.
make_worktrees
mkdir -p "$WORK/outside/build" "$W/wt-gone/secrets" "$W/wt-gone/src/build"
GUARD="$WORK/guard.sh"
# shellcheck disable=SC2016
{
  printf 'set -euo pipefail\nset -f\n'
  printf 'say() { printf "%%s\\n" "$*"; }\nerr() { printf "%%s\\n" "$*" >&2; }\n'
  awk '/^(mb|is_regenerable_name|remove_folder)\(\) \{/ { on = 1 } on { print } on && /^}/ { on = 0 }' "$CHECKS/wave-preflight.sh"
  printf 'REGENERABLE="build node_modules"\nREMOVED=0\nREMOVED_KB=0\nKEPT=0\nROOT=$1\n'
  printf 'remove_folder "$2" "$3" 10\necho "removed=$REMOVED kept=$KEPT"\n'
} >"$GUARD"
guard() {
  OUT=$(/bin/bash "$GUARD" "$W" "$W/wt-gone" "$1" 2>&1)
  RC=$?
}
guard ""
expect "removal guard: refuses an empty path" 1 "refuse: an empty path"
guard "$WORK/outside/build"
expect "removal guard: refuses a path outside the worktrees folder" 1 "is not inside a worktree under"
guard "$W/wt-gone/../../outside/build"
expect "removal guard: refuses a path that leaves through dot-dot" 1 "is not inside a worktree under"
guard "$W/wt-active/build"
expect "removal guard: refuses a path in another worktree" 1 "is not inside the worktree"
guard "$W/wt-gone/secrets"
expect "removal guard: refuses a name that is not in the list" 1 "is not in JIDOKA_REGENERABLE"
guard "$W/wt-gone/src/build"
expect "removal guard: keeps a folder that git does not ignore" 0 "removed=0 kept=1"
if [ -d "$WORK/outside/build" ] && [ -d "$W/wt-active/build" ] && [ -d "$W/wt-gone/secrets" ] && [ -d "$W/wt-gone/src/build" ]; then
  pass "removal guard: each refused folder is still there"
else
  fail "removal guard: each refused folder is still there"
fi
guard "$W/wt-gone/build"
expect "removal guard: removes a folder that passes each test" 0 "removed=1 kept=0"

unset JIDOKA_MIN_FREE_GB

# ---- the three scripts that talk to the host ------------------------------------

if ! PATH=$REAL_PATH command -v jq >/dev/null 2>&1; then
  printf '\nNOT RUN: the tests of merge-guard.sh, ci-wait.sh and protect-long-branches.sh need jq.\n'
  NOT_RUN=1
else

  export JIDOKA_REPO=example-owner/example-repo JIDOKA_STATE_WAIT=0 JIDOKA_VERIFY_WAIT=0
  export FAKE_GH_DIR="$WORK/gh"
  R=repos_example-owner_example-repo
  SHA=1111111111111111111111111111111111111111
  TIP_MAIN=aaaa000000000000000000000000000000000000
  TIP_DEVELOP=bbbb000000000000000000000000000000000000
  MERGE=cccc000000000000000000000000000000000000

  no_call() {
    if grep -q -F -- "$2" "$FAKE_GH_DIR/calls.log"; then fail "$1: the script sent: $2"; else pass "$1"; fi
  }

  # pull <file> <state> <merged> <draft> <base> <head> <mergeable state> <head repository>
  pull() {
    cat >"$FAKE_GH_DIR/$1" <<JSON
{"state":"$2","merged":$3,"draft":$4,"title":"Add the thing","mergeable_state":"$7",
 "merge_commit_sha":"9999000000000000000000000000000000000000",
 "base":{"ref":"$5","repo":{"default_branch":"main"}},
 "head":{"ref":"$6","sha":"$SHA","repo":{"full_name":"$8"}}}
JSON
  }
  PULL="GET.${R}_pulls_7.json"
  check_runs() { printf '%s' "$1" >"$FAKE_GH_DIR/GET.${R}_commits_${SHA}_check-runs.json"; }
  statuses() { printf '%s' "$1" >"$FAKE_GH_DIR/GET.${R}_commits_${SHA}_status.json"; }
  GREEN='{"check_runs":[{"id":10,"name":"check","status":"completed","conclusion":"success"},{"id":11,"name":"security","status":"completed","conclusion":"success"}]}'

  reset_guard() {
    rm -rf "$FAKE_GH_DIR"
    mkdir -p "$FAKE_GH_DIR"
    : >"$FAKE_GH_DIR/calls.log"
    pull "$PULL" open false false develop feat/x clean example-owner/example-repo
    check_runs "$GREEN"
    statuses '{"statuses":[]}'
    printf '{"object":{"sha":"%s"}}' "$TIP_MAIN" >"$FAKE_GH_DIR/GET.${R}_git_ref_heads_main.json"
    printf '{"object":{"sha":"%s"}}' "$TIP_DEVELOP" >"$FAKE_GH_DIR/GET.${R}_git_ref_heads_develop.json"
    printf '{"merged":true,"sha":"%s"}' "$MERGE" >"$FAKE_GH_DIR/PUT.${R}_pulls_7_merge.json"
  }

  printf '\n== merge-guard.sh\n'

  reset_guard
  run merge-guard.sh 7
  expect "merge-guard: a ready pull request, report only" 0 "READY: pull request 7 can merge"
  no_call "merge-guard: a report sends no merge" "PUT"

  reset_guard
  pull "$PULL" open false false main feat/x clean example-owner/example-repo
  run merge-guard.sh 7 --merge
  expect "merge-guard: refuses a base that is not the working branch" 1 'the base is "main", not "develop"'
  no_call "merge-guard: no merge into a moved base" "PUT"

  reset_guard
  pull "$PULL" open false false main develop clean example-owner/example-repo
  JIDOKA_BASE=main run merge-guard.sh 7 --merge
  expect "merge-guard: refuses a head that is a long branch" 1 'the head "develop" is a long branch'
  no_call "merge-guard: no merge of a long branch" "PUT"

  reset_guard
  pull "$PULL" open false false develop develop clean another-owner/example-repo
  run merge-guard.sh 7
  expect "merge-guard: a fork may name its branch like a long branch" 0 "READY"

  reset_guard
  pull "$PULL" open false true develop feat/x draft example-owner/example-repo
  run merge-guard.sh 7 --merge
  expect "merge-guard: refuses a draft" 1 "the pull request is a draft"
  no_call "merge-guard: no merge of a draft" "PUT"

  reset_guard
  pull "$PULL" open false false develop feat/x dirty example-owner/example-repo
  run merge-guard.sh 7 --merge
  expect "merge-guard: refuses a conflict" 1 'the mergeable state is "dirty"'
  no_call "merge-guard: no merge of a conflict" "PUT"

  reset_guard
  pull "$PULL" open false false develop feat/x unknown example-owner/example-repo
  run merge-guard.sh 7 --merge
  expect "merge-guard: refuses a state that the host has not computed" 1 'the mergeable state is "unknown"'

  reset_guard
  check_runs '{"check_runs":[{"id":10,"name":"check","status":"completed","conclusion":"failure"},{"id":12,"name":"check","status":"completed","conclusion":"success"},{"id":11,"name":"security","status":"completed","conclusion":"failure"}]}'
  run merge-guard.sh 7 --merge
  expect "merge-guard: refuses a failed check" 1 'the check "security" ended as "failure"'
  holds "merge-guard: the newest run of a check counts" 'check "check": success'
  no_call "merge-guard: no merge on a failed check" "PUT"

  reset_guard
  check_runs '{"check_runs":[{"id":12,"name":"check","status":"completed","conclusion":"success"},{"id":10,"name":"check","status":"completed","conclusion":"failure"},{"id":11,"name":"security","status":"completed","conclusion":"success"}]}'
  run merge-guard.sh 7
  expect "merge-guard: the newest run counts in any order" 0 "READY"

  reset_guard
  check_runs '{"check_runs":[{"id":10,"name":"check","status":"in_progress","conclusion":null}]}'
  run merge-guard.sh 7 --merge
  expect "merge-guard: refuses a check with no run" 1 'the check "security" has no run'
  holds "merge-guard: refuses a check that still runs" 'the check "check" is not complete (in_progress)'

  reset_guard
  check_runs '{"check_runs":[{"id":10,"name":"check","status":"completed","conclusion":"success"}]}'
  statuses '{"statuses":[{"context":"security","state":"success"}]}'
  run merge-guard.sh 7
  expect "merge-guard: a commit status counts as a check" 0 "READY"

  reset_guard
  check_runs '{"check_runs":[{"id":10,"name":"build / test","status":"completed","conclusion":"success"},{"id":11,"name":"scan","status":"completed","conclusion":"skipped"}]}'
  JIDOKA_CHECKS="build / test, scan" run merge-guard.sh 7
  expect "merge-guard: a skipped check is not a success" 1 'the check "scan" ended as "skipped"'
  holds "merge-guard: a check name with a space" 'check "build / test": success'

  reset_guard
  run merge-guard.sh 7 --merge
  expect "merge-guard: merges and proves the long branches" 0 "MERGED: pull request 7 into \"develop\". Merge commit: $MERGE"
  holds "merge-guard: reads the base again before the merge" "base checked before the merge: develop"
  holds "merge-guard: each long branch is read after the merge" "long branch \"develop\": present after the merge ($TIP_DEVELOP)"
  holds "merge-guard: says to close the tickets by hand" "Close each one by hand"
  if grep -q -x -F "PUT repos/example-owner/example-repo/pulls/7/merge merge_method=merge sha=$SHA" "$FAKE_GH_DIR/calls.log"; then
    pass "merge-guard: merges with a merge commit at the commit that it checked"
  else
    fail "merge-guard: merges with a merge commit at the commit that it checked"
  fi

  reset_guard
  echo "rm -f \"\$FAKE_GH_DIR/GET.${R}_git_ref_heads_develop.json\"" >"$FAKE_GH_DIR/PUT.${R}_pulls_7_merge.after"
  run merge-guard.sh 7 --merge
  expect "merge-guard: a long branch that is gone after the merge stops the line" 2 "gh api -X POST repos/example-owner/example-repo/git/refs -f ref=refs/heads/develop -f sha=$TIP_DEVELOP"
  holds "merge-guard: prints the merge commit with the stop" "The merge commit is $MERGE."

  reset_guard
  rm "$FAKE_GH_DIR/GET.${R}_git_ref_heads_main.json"
  run merge-guard.sh 7 --merge
  expect "merge-guard: a long branch that is missing before the merge stops the line" 2 'the long branch "main" is missing on the remote before the merge'
  no_call "merge-guard: no merge while a long branch is missing" "PUT"

  reset_guard
  pull moved.json open false false main feat/x clean example-owner/example-repo
  echo "cp \"\$FAKE_GH_DIR/moved.json\" \"\$FAKE_GH_DIR/$PULL\"" >"$FAKE_GH_DIR/GET.${R}_pulls_7.after"
  run merge-guard.sh 7 --merge
  expect "merge-guard: refuses when the base moves between the first read and the merge" 1 "changed while the script read it"
  no_call "merge-guard: no merge after the base moved" "PUT"

  reset_guard
  echo "Pull Request is not mergeable (HTTP 405)" >"$FAKE_GH_DIR/PUT.${R}_pulls_7_merge.error"
  run merge-guard.sh 7 --merge
  expect "merge-guard: says what the host said when it refuses the merge" 1 "the host did not merge pull request 7: gh: Pull Request is not mergeable (HTTP 405)"
  holds "merge-guard: tells not to try another way" "Do not try the merge in another way."

  reset_guard
  pull merged.json closed true false develop feat/x clean example-owner/example-repo
  {
    echo "n=\$(cat \"\$FAKE_GH_DIR/count\" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n >\"\$FAKE_GH_DIR/count\""
    echo "if [ \$n -eq 2 ]; then cp \"\$FAKE_GH_DIR/merged.json\" \"\$FAKE_GH_DIR/$PULL\"; fi"
  } >"$FAKE_GH_DIR/GET.${R}_pulls_7.after"
  echo "Gateway Timeout (HTTP 504)" >"$FAKE_GH_DIR/PUT.${R}_pulls_7_merge.error"
  run merge-guard.sh 7 --merge
  expect "merge-guard: a merge call that fails and still merges is read back, not guessed" 0 "MERGED: pull request 7 into \"develop\". Merge commit: 9999000000000000000000000000000000000000"

  reset_guard
  {
    echo "rm -f \"\$FAKE_GH_DIR/GET.${R}_git_ref_heads_main.json\""
    echo "echo 'Server Error (HTTP 502)' >\"\$FAKE_GH_DIR/GET.${R}_git_ref_heads_main.error\""
  } >"$FAKE_GH_DIR/PUT.${R}_pulls_7_merge.after"
  run merge-guard.sh 7 --merge
  expect "merge-guard: says that the merge happened when the proof after it cannot run" 3 "Pull request 7 IS MERGED (merge commit $MERGE). The long branches are NOT verified."
  lacks "merge-guard: never says that nothing was merged after a merge" "Nothing was merged"

  reset_guard
  rm "$FAKE_GH_DIR/$PULL"
  run merge-guard.sh 7 --merge
  expect "merge-guard: a pull request that the host does not return" 3 "CANNOT CHECK: the host did not return pull request 7"
  holds "merge-guard: says that nothing was merged before a merge" "Nothing was merged."

  reset_guard
  pull "$PULL" closed true false develop feat/x clean example-owner/example-repo
  run merge-guard.sh 7 --merge
  expect "merge-guard: refuses a merged pull request" 1 "already merged"

  reset_guard
  pull "$PULL" closed false false develop feat/x clean example-owner/example-repo
  run merge-guard.sh 7 --merge
  expect "merge-guard: refuses a closed pull request" 1 "pull request 7 is closed"

  reset_guard
  run merge-guard.sh
  expect "merge-guard: no number" 64 "usage:"
  run merge-guard.sh abc
  expect "merge-guard: a number that is not a number" 64 "digits only"
  run merge-guard.sh 7 --force
  expect "merge-guard: an unknown option" 64 "unknown option"
  JIDOKA_REPO=name-only run merge-guard.sh 7
  expect "merge-guard: a repository that is not owner/name" 64 "must be owner/name"
  no_call "merge-guard: wrong usage calls no host" "repos"
  OUT=$(cd "$WORK" && env -u JIDOKA_REPO /bin/bash "$CHECKS/merge-guard.sh" 7 2>&1)
  RC=$?
  expect "merge-guard: no repository and no remote" 3 "JIDOKA_REPO is not set"

  printf '\n== ci-wait.sh\n'

  export JIDOKA_WAIT_EVERY=0 JIDOKA_WAIT_LIMIT=0

  reset_guard
  run ci-wait.sh 7
  expect "ci-wait: green checks end the wait with one line" 0 "7 GREEN $SHA"

  reset_guard
  check_runs '{"check_runs":[{"id":10,"name":"check","status":"completed","conclusion":"success"},{"id":11,"name":"security","status":"completed","conclusion":"failure"}]}'
  run ci-wait.sh 7
  expect "ci-wait: a failed check is RED and names the check" 1 "7 RED $SHA security=failure"

  reset_guard
  check_runs '{"check_runs":[{"id":10,"name":"check","status":"in_progress","conclusion":null}]}'
  run ci-wait.sh 7
  expect "ci-wait: the time limit with a running check proves nothing" 3 "7 PENDING $SHA check=in_progress security=missing"
  holds "ci-wait: says that the time limit passed" "TIME LIMIT"

  reset_guard
  pull "GET.${R}_pulls_8.json" closed true false develop feat/y clean example-owner/example-repo
  run ci-wait.sh 7 8
  expect "ci-wait: a merged pull request ends its wait" 0 "8 MERGED"
  holds "ci-wait: one line for each pull request" "7 GREEN"

  reset_guard
  statuses '{"statuses":[{"context":"security","state":"pending"}]}'
  check_runs '{"check_runs":[{"id":10,"name":"check","status":"completed","conclusion":"success"}]}'
  run ci-wait.sh 7
  expect "ci-wait: a pending commit status is still running" 3 "security=pending"

  run ci-wait.sh 7x
  expect "ci-wait: a number that is not digits" 64 "digits only"
  no_call "ci-wait: wrong usage calls no host" "pulls/7x"

  unset JIDOKA_WAIT_EVERY JIDOKA_WAIT_LIMIT

  printf '\n== protect-long-branches.sh\n'

  BOTH='[{"type":"deletion","ruleset_id":5},{"type":"non_fast_forward","ruleset_id":5},{"type":"pull_request","ruleset_id":6}]'

  reset_protect() {
    rm -rf "$FAKE_GH_DIR"
    mkdir -p "$FAKE_GH_DIR"
    : >"$FAKE_GH_DIR/calls.log"
    printf '{"delete_branch_on_merge":true,"default_branch":"main"}' >"$FAKE_GH_DIR/GET.$R.json"
    local b
    for b in main develop; do
      printf '{"object":{"sha":"abc"}}' >"$FAKE_GH_DIR/GET.${R}_git_ref_heads_$b.json"
      printf '%s' "$BOTH" >"$FAKE_GH_DIR/GET.${R}_rules_branches_$b.json"
    done
    printf '{"name":"jidoka-long-branches","enforcement":"active","bypass_actors":[],"current_user_can_bypass":"never"}' >"$FAKE_GH_DIR/GET.${R}_rulesets_5.json"
    printf '[{"id":6,"name":"reviews"}]' >"$FAKE_GH_DIR/GET.${R}_rulesets.json"
    printf '{"id":5}' >"$FAKE_GH_DIR/POST.${R}_rulesets.json"
  }

  reset_protect
  run protect-long-branches.sh --dry-run
  expect "protect: a dry run prints the request" 0 "POST repos/example-owner/example-repo/rulesets"
  if [ ! -s "$FAKE_GH_DIR/calls.log" ]; then pass "protect: a dry run sends nothing and reads nothing"; else fail "protect: a dry run sends nothing and reads nothing"; fi
  BODY=$(printf '%s\n' "$OUT" | sed -n '/^{/,/^}/p')
  if printf '%s\n' "$BODY" | jq -e '(.rules | map(.type)) == ["deletion", "non_fast_forward"] and .conditions.ref_name.include == ["refs/heads/main", "refs/heads/develop"] and .enforcement == "active" and .target == "branch" and .bypass_actors == []' >/dev/null; then
    pass "protect: the request forbids deletion and force push of both long branches, with no bypass"
  else
    fail "protect: the request forbids deletion and force push of both long branches, with no bypass"
  fi

  reset_protect
  run protect-long-branches.sh
  expect "protect: reports a protection that is present" 0 "PRESENT: each long branch is protected. Nothing was sent."
  holds "protect: says that the repository deletes head branches" "the repository DELETES a head branch after a merge"
  holds "protect: reads the bypass list" 'ruleset 5 "jidoka-long-branches": enforcement active, bypass actors 0, this account can bypass: never'
  no_call "protect: present sends nothing" "POST"

  reset_protect
  printf '{"name":"x","enforcement":"active","bypass_actors":[{"actor_id":1,"bypass_mode":"always"}],"current_user_can_bypass":"always"}' >"$FAKE_GH_DIR/GET.${R}_rulesets_5.json"
  run protect-long-branches.sh
  expect "protect: warns about a bypass" 0 "WARNING: an actor with bypass can still delete and force push"

  reset_protect
  printf '{"delete_branch_on_merge":false,"default_branch":"main"}' >"$FAKE_GH_DIR/GET.$R.json"
  run protect-long-branches.sh
  expect "protect: says that the repository keeps head branches" 0 "the repository keeps a head branch after a merge"

  reset_protect
  printf '{"default_branch":"main"}' >"$FAKE_GH_DIR/GET.$R.json"
  run protect-long-branches.sh
  expect "protect: says when it cannot read the setting" 0 "head branches: NOT READ"

  reset_protect
  printf '[{"type":"deletion","ruleset_id":5}]' >"$FAKE_GH_DIR/GET.${R}_rules_branches_develop.json"
  echo "printf '%s' '$BOTH' >\"\$FAKE_GH_DIR/GET.${R}_rules_branches_develop.json\"" >"$FAKE_GH_DIR/POST.${R}_rulesets.after"
  run protect-long-branches.sh
  expect "protect: creates the ruleset when a rule is missing" 0 "CREATED: each long branch is protected."
  holds "protect: names the missing rule" 'branch "develop": NOT protected, no rule for: non_fast_forward'
  if jq -e '.name == "jidoka-long-branches" and (.rules | length) == 2' "$FAKE_GH_DIR/last-body.json" >/dev/null 2>&1; then
    pass "protect: sends the request that it prints"
  else
    fail "protect: sends the request that it prints"
  fi

  reset_protect
  printf '[]' >"$FAKE_GH_DIR/GET.${R}_rules_branches_main.json"
  run protect-long-branches.sh
  expect "protect: does not say created when the host still applies no rule" 1 "the host still applies no rule to 1 long branch"

  reset_protect
  printf '[]' >"$FAKE_GH_DIR/GET.${R}_rules_branches_main.json"
  printf '[{"id":9,"name":"jidoka-long-branches"}]' >"$FAKE_GH_DIR/GET.${R}_rulesets.json"
  run protect-long-branches.sh
  expect "protect: does not overwrite a ruleset of the same name" 1 "gh api -X PUT repos/example-owner/example-repo/rulesets/9 --input ruleset.json"
  no_call "protect: no create beside a ruleset of the same name" "POST"

  reset_protect
  printf '[]' >"$FAKE_GH_DIR/GET.${R}_rules_branches_main.json"
  echo "Resource not accessible (HTTP 403)" >"$FAKE_GH_DIR/POST.${R}_rulesets.error"
  run protect-long-branches.sh
  expect "protect: a denied create goes to the owner as one command" 1 "Do not try another way. Give the owner this one command"

  reset_protect
  rm "$FAKE_GH_DIR/GET.${R}_rules_branches_main.json"
  echo "Upgrade the plan to use this feature (HTTP 403)" >"$FAKE_GH_DIR/GET.${R}_rules_branches_main.error"
  run protect-long-branches.sh
  expect "protect: rules that the host does not return are not a pass" 3 'CANNOT CHECK: the host did not return the rules of branch "main"'
  no_call "protect: no create when the rules are not readable" "POST"

  reset_protect
  rm "$FAKE_GH_DIR/GET.${R}_git_ref_heads_develop.json"
  run protect-long-branches.sh
  expect "protect: names a long branch that does not exist yet" 0 'branch "develop": does NOT exist on the remote yet'

  reset_protect
  printf '%s' "$BOTH" >"$FAKE_GH_DIR/GET.${R}_rules_branches_release_2Fnext.json"
  printf '{"object":{"sha":"abc"}}' >"$FAKE_GH_DIR/GET.${R}_git_ref_heads_release_next.json"
  JIDOKA_LONG_BRANCHES="main release/next" run protect-long-branches.sh
  expect "protect: a branch name with a slash" 0 'branch "release/next": deletion forbidden, force push forbidden'

  reset_protect
  JIDOKA_LONG_BRANCHES='main "x' run protect-long-branches.sh
  expect "protect: a branch name that is not plain" 64 "is not a plain branch name"
  run protect-long-branches.sh --force
  expect "protect: an unknown argument" 64 "unknown argument"
  no_call "protect: wrong usage calls no host" "repos"

fi

printf '\ntests passed: %s, failed: %s\n' "$PASSED" "$FAILED"
if [ "$FAILED" -gt 0 ]; then exit 1; fi
if [ "$NOT_RUN" -gt 0 ]; then exit 3; fi
exit 0

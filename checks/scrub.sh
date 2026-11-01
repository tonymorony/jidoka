#!/usr/bin/env bash
# scrub.sh - find names, addresses and links that must not be in a folder.
#
# Usage: checks/scrub.sh <folder> [words file]
#
# The script searches every text file of the folder, and every file name, for:
#   - each word or pattern of the words file (case does not matter)
#   - each email address that the allow list does not hold
#   - each URL that the allow list does not hold
# It prints the file, the line and the text that it found. Line 0 is the file name.
#
# Words file: one word or pattern on each line. A pattern is an extended
# regular expression. A line that starts with # is a comment.
# Default: .jidoka-scrub-words in the folder. With no words file the script
# checks email addresses and URLs only, and says so.
# Keep the words file out of version control: it names what it hides.
#
# Allow list: one extended regular expression on each line; an email address
# or a URL that matches one of them is not a hit. The allow list never excuses
# a word. Reserved example domains and the local machine are always allowed.
#
# Environment:
#   JIDOKA_SCRUB_ALLOW   path of the allow list.
#                        Default: .jidoka-scrub-allow in the folder.
#   JIDOKA_SCRUB_SKIP    folder names that the script does not enter.
#                        Default: ".git"
#   JIDOKA_SCRUB_QUIET   1 hides each text that holds a word: the script then
#                        prints the file, the line and the kind only. Set it
#                        where other people read the output, as in CI.
#                        Default: 0
#
# Exit codes:
#   0   clean
#   1   one hit or more
#   3   cannot check: a pattern is not valid or a file is not readable
#   64  wrong usage

set -euo pipefail
set -f

say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

show_help() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

usage_error() {
  err "scrub: $*"
  err "usage: checks/scrub.sh <folder> [words file]"
  exit 64
}

cannot() {
  err "CANNOT CHECK: $*"
  exit 3
}

case "${1:-}" in
  -h | --help)
    show_help
    exit 0
    ;;
esac

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  usage_error "one folder and at most one words file"
fi

if [ ! -d "$1" ]; then usage_error "not a folder: $1"; fi
ROOT=$(cd "$1" && pwd -P)

absolute() {
  printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"
}

HAVE_WORDS=1
if [ $# -eq 2 ]; then
  if [ ! -f "$2" ]; then usage_error "no words file at: $2"; fi
  WORDS=$(absolute "$2")
else
  WORDS="$ROOT/.jidoka-scrub-words"
  if [ ! -f "$WORDS" ]; then HAVE_WORDS=0; fi
fi

ALLOW=${JIDOKA_SCRUB_ALLOW:-$ROOT/.jidoka-scrub-allow}
if [ -n "${JIDOKA_SCRUB_ALLOW:-}" ] && [ ! -f "$ALLOW" ]; then
  usage_error "no allow list at: $ALLOW"
fi
if [ -f "$ALLOW" ]; then ALLOW=$(absolute "$ALLOW"); fi

QUIET=${JIDOKA_SCRUB_QUIET:-0}
case "$QUIET" in
  0 | 1) ;;
  *) usage_error "JIDOKA_SCRUB_QUIET must be 0 or 1" ;;
esac

SKIP=${JIDOKA_SCRUB_SKIP:-.git}
for name in $SKIP; do
  case "$name" in
    . | .. | */* | *[\*\?\[]*) usage_error "JIDOKA_SCRUB_SKIP may hold plain folder names only, not \"$name\"" ;;
  esac
done

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/jidoka-scrub.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT

EMAIL_PATTERN='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
URL_PATTERN="([A-Za-z][A-Za-z0-9+.-]*://|www\\.)[^][:space:]<>\"'\`)}]+"

# Reads a list file: drops comments, blank lines and space at both ends.
clean_list() {
  tr -d '\r' <"$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v -E '^(#|$)' || true
}

# Refuses a pattern that grep cannot read or that matches an empty line.
# The third argument is 1 for the words file: quiet mode then hides the pattern.
validate_patterns() {
  local line rc number=0 shown
  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    number=$((number + 1))
    shown="\"$line\""
    if [ "$QUIET" -eq 1 ] && [ "$3" -eq 1 ]; then shown="number $number (text not shown)"; fi
    rc=0
    printf '\n' | grep -q -i -E -e "$line" 2>/dev/null || rc=$?
    if [ "$rc" -eq 0 ]; then
      cannot "the pattern $shown in $2 matches an empty line, so it matches every line. Make it narrower."
    fi
    if [ "$rc" -gt 1 ]; then
      cannot "the pattern $shown in $2 is not a valid extended regular expression."
    fi
  done <"$1"
}

WORD_PATTERNS="$TMPD/words"
: >"$WORD_PATTERNS"
WORD_COUNT=0
if [ "$HAVE_WORDS" -eq 1 ]; then
  clean_list "$WORDS" >"$WORD_PATTERNS"
  validate_patterns "$WORD_PATTERNS" "$WORDS" 1
  WORD_COUNT=$(awk 'END { print NR }' "$WORD_PATTERNS")
fi

ALLOW_PATTERNS="$TMPD/allow"
cat >"$ALLOW_PATTERNS" <<'EOF'
^[a-z][a-z0-9+.-]*://([a-z0-9.-]+\.)?example\.(com|org|net)([:/?#]|$)
^[a-z][a-z0-9+.-]*://(localhost|127\.0\.0\.1)([:/?#]|$)
^www\.example\.(com|org|net)([:/?#]|$)
@([a-z0-9.-]+\.)?example\.(com|org|net)$
EOF
if [ -f "$ALLOW" ]; then
  clean_list "$ALLOW" >"$TMPD/allow.user"
  validate_patterns "$TMPD/allow.user" "$ALLOW" 0
  cat "$TMPD/allow.user" >>"$ALLOW_PATTERNS"
fi

is_allowed() {
  grep -q -i -E -f "$ALLOW_PATTERNS" <<<"$1"
}

HITS=0
FILES=0
FILES_WITH_HITS=0
FILE_HIT=0
NAME_HIT=0

holds_word() {
  [ "$WORD_COUNT" -gt 0 ] && grep -q -i -E -f "$WORD_PATTERNS" <<<"$1"
}

# Prints one hit. In quiet mode it prints no text that holds a word: not the
# match, and not the name of a file whose name holds a word.
hit() {
  local file=$1 text=" \"$4\""
  if [ "$QUIET" -eq 1 ]; then
    case "$3" in
      word | "word in the file name") text=" (text not shown)" ;;
      *) if holds_word "$4"; then text=" (text not shown: it holds a word)"; fi ;;
    esac
    if [ "$NAME_HIT" -eq 1 ]; then file="(file $FILES of the search: its name holds a word)"; fi
  fi
  say "$file:$2: $3$text"
  HITS=$((HITS + 1))
  FILE_HIT=1
}

# Runs grep and prints "line:text" for each match. Stops the script on a grep error.
matches() {
  local rc=0
  grep -I -n -o "$@" || rc=$?
  if [ "$rc" -gt 1 ]; then
    cannot "grep failed (exit $rc) with: $*"
  fi
}

# Reads "line:text" lines and reports each one as a hit of one kind.
report() {
  local kind=$1 rel=$2 use_allow=$3 line number text
  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    number=${line%%:*}
    text=${line#*:}
    if [ "$use_allow" -eq 1 ]; then
      text=$(printf '%s\n' "$text" | sed -E 's/[.,;:!?]+$//')
      if is_allowed "$text"; then continue; fi
    fi
    hit "$rel" "$number" "$kind" "$text"
  done
}

if [ "$HAVE_WORDS" -eq 1 ] && git -C "$(dirname "$WORDS")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$(dirname "$WORDS")" ls-files --error-unmatch -- "$(basename "$WORDS")" >/dev/null 2>&1; then
    say "$WORDS:0: the words file is in version control, and it names what it hides. Remove it from the index (git rm --cached), ignore it, and keep it outside the repository."
    HITS=$((HITS + 1))
  fi
fi

set --
for name in $SKIP; do
  if [ $# -gt 0 ]; then set -- "$@" -o; fi
  set -- "$@" -name "$name"
done
if [ $# -gt 0 ]; then
  find "$ROOT" \( -type d \( "$@" \) -prune \) -o \( -type f -print \) | LC_ALL=C sort >"$TMPD/files"
else
  find "$ROOT" -type f | LC_ALL=C sort >"$TMPD/files"
fi

while IFS= read -r file; do
  if [ -z "$file" ]; then continue; fi
  if [ "$file" = "$WORDS" ] || [ "$file" = "$ALLOW" ]; then continue; fi
  if [ ! -r "$file" ]; then cannot "the file is not readable: $file"; fi
  rel=${file#"$ROOT"/}
  FILES=$((FILES + 1))
  FILE_HIT=0
  NAME_HIT=0
  if [ "$WORD_COUNT" -gt 0 ]; then
    found=$(printf '%s\n' "$rel" | matches -i -E -f "$WORD_PATTERNS" | sed -E 's/^[0-9]+:/0:/')
    if [ -n "$found" ]; then NAME_HIT=1; fi
    report "word in the file name" "$rel" 0 <<<"$found"
    found=$(matches -i -E -f "$WORD_PATTERNS" -- "$file")
    report "word" "$rel" 0 <<<"$found"
  fi
  found=$(matches -E -e "$EMAIL_PATTERN" -- "$file")
  report "email address" "$rel" 1 <<<"$found"
  found=$(matches -i -E -e "$URL_PATTERN" -- "$file")
  report "URL" "$rel" 1 <<<"$found"
  if [ "$FILE_HIT" -eq 1 ]; then FILES_WITH_HITS=$((FILES_WITH_HITS + 1)); fi
done <"$TMPD/files"

if [ "$HAVE_WORDS" -eq 1 ]; then
  SCOPE="$WORD_COUNT words, email addresses and URLs"
else
  SCOPE="email addresses and URLs only"
  err "NOTE: no words file at $WORDS, so NO WORD WAS CHECKED. Copy checks/scrub-words.example, fill it, and run again."
fi

if [ "$HITS" -gt 0 ]; then
  say "scrub: FAIL. Hits: $HITS. Files with a hit: $FILES_WITH_HITS of $FILES. Checked: $SCOPE."
  say "NEXT: remove each hit. For an address or a link that must stay, add a pattern to the allow list. Do not remove a word from the words file to make the check pass."
  if [ "$QUIET" -eq 1 ]; then
    say "NOTE: JIDOKA_SCRUB_QUIET=1 hides each text that holds a word. Run the script on your own machine without it to see the text."
  fi
  exit 1
fi
say "scrub: clean. Files searched: $FILES. Checked: $SCOPE."
exit 0

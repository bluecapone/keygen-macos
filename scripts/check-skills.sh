#!/usr/bin/env bash
# Validate every skill against the conventions in docs/authoring-conventions.md.
# Exits non-zero on the first tree that fails, so this is CI-safe.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

MAX_BODY_LINES=500
MAX_DESC_CHARS=1024
MAX_NAME_CHARS=64
NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*$'

failures=0
skills_checked=0

pass() { printf '    ok   %s\n' "$1"; }
fail() { printf '    FAIL %s\n' "$1"; failures=$((failures + 1)); }

if [ ! -d "$SKILLS_DIR" ]; then
  printf 'no skills/ directory at %s\n' "$SKILLS_DIR" >&2
  exit 1
fi

printf 'checking skills in %s\n\n' "$SKILLS_DIR"

for dir in "$SKILLS_DIR"/*/; do
  [ -d "$dir" ] || continue
  slug="$(basename "$dir")"
  md="$dir/SKILL.md"
  skills_checked=$((skills_checked + 1))
  printf '  %s\n' "$slug"

  if [ ! -f "$md" ]; then
    fail "no SKILL.md"
    continue
  fi

  # --- frontmatter -----------------------------------------------------------
  if [ "$(sed -n '1p' "$md")" != "---" ]; then
    fail "SKILL.md must open with '---' on line 1"
    continue
  fi

  fm_end="$(awk 'NR > 1 && /^---[[:space:]]*$/ { print NR; exit }' "$md")"
  if [ -z "$fm_end" ]; then
    fail "frontmatter is never closed"
    continue
  fi

  fm="$(sed -n "2,$((fm_end - 1))p" "$md")"

  strip_key() {
    printf '%s\n' "$fm" \
      | sed -n "s/^$1:[[:space:]]*//p" \
      | head -1 \
      | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
  }

  name="$(strip_key name)"
  desc="$(strip_key description)"

  # --- name ------------------------------------------------------------------
  if [ -z "$name" ]; then
    fail "frontmatter has no name"
  elif ! printf '%s' "$name" | grep -Eq "$NAME_RE"; then
    fail "name '$name' is not lowercase-hyphen"
  elif [ "${#name}" -gt "$MAX_NAME_CHARS" ]; then
    fail "name is ${#name} chars, limit $MAX_NAME_CHARS"
  elif [ "$name" != "$slug" ]; then
    fail "name '$name' does not match directory '$slug'"
  else
    pass "name"
  fi

  # --- description -----------------------------------------------------------
  if [ -z "$desc" ]; then
    fail "frontmatter has no description"
  else
    desc_ok=1

    if [ "${#desc}" -gt "$MAX_DESC_CHARS" ]; then
      fail "description is ${#desc} chars, limit $MAX_DESC_CHARS"
      desc_ok=0
    fi

    if printf '%s' "$desc" | grep -Eq '^(You|I|We|This skill|Use this)\b'; then
      fail "description must be third person describing the action"
      desc_ok=0
    fi

    if ! printf '%s' "$desc" | grep -Eq 'Use (when|whenever|for)\b'; then
      fail "description must state when to fire ('Use when ...')"
      desc_ok=0
    fi

    [ "$desc_ok" -eq 1 ] && pass "description (${#desc} chars)"
  fi

  # --- body length -----------------------------------------------------------
  total_lines="$(wc -l < "$md" | tr -d ' ')"
  body_lines=$((total_lines - fm_end))
  if [ "$body_lines" -gt "$MAX_BODY_LINES" ]; then
    fail "body is $body_lines lines, limit $MAX_BODY_LINES - split into references/"
  else
    pass "body ($body_lines lines)"
  fi
done

# --- credential scan across the whole tree -----------------------------------
printf '\n  credential scan\n'
SECRET_RE='(gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|glpat-[A-Za-z0-9_-]{16,})'
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  scan_files="$(git -C "$REPO_ROOT" ls-files)"
else
  scan_files="$(cd "$REPO_ROOT" && find . -type f -not -path './.git/*')"
fi

hits=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$REPO_ROOT/$f" ] || continue
  case "$f" in scripts/check-skills.sh) continue ;; esac
  if grep -Eq "$SECRET_RE" "$REPO_ROOT/$f" 2>/dev/null; then
    fail "credential-shaped string in $f"
    hits=$((hits + 1))
  fi
done <<EOF
$scan_files
EOF
[ "$hits" -eq 0 ] && pass "no credential-shaped strings"

# --- summary -----------------------------------------------------------------
printf '\n'
if [ "$failures" -eq 0 ]; then
  printf '%s skills checked, all passed\n' "$skills_checked"
  exit 0
fi
printf '%s skills checked, %s failure(s)\n' "$skills_checked" "$failures"
exit 1

#!/usr/bin/env bash
# Symlink this repo's skills into agent skill directories.
# Only ever creates symlinks; never clobbers a real file or directory.
#
#   ./scripts/install.sh                       link into ~/.claude/skills and ~/.agents/skills
#   ./scripts/install.sh --project             link into ./.agents/skills (current repo only)
#   ./scripts/install.sh --uninstall           remove global links
#   ./scripts/install.sh --project --uninstall remove project links
#
# Scope (--project) and action (--uninstall) are independent flags and combine.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

action="install"
scope="global"

for arg in "$@"; do
  case "$arg" in
    --project)   scope="project" ;;
    --uninstall) action="uninstall" ;;
    -h|--help)   sed -n '2,10p' "$0"; exit 0 ;;
    *) printf 'unknown option: %s (try --help)\n' "$arg" >&2; exit 2 ;;
  esac
done

if [ "$scope" = "project" ]; then
  targets="$PWD/.agents/skills"
else
  targets="$HOME/.claude/skills $HOME/.agents/skills"
fi

linked=0
removed=0
skipped=0

for target in $targets; do
  if [ "$action" = "install" ]; then
    mkdir -p "$target"
  elif [ ! -d "$target" ]; then
    continue
  fi
  printf '%s\n' "$target"

  for dir in "$SKILLS_DIR"/*/; do
    [ -d "$dir" ] || continue
    slug="$(basename "$dir")"
    link="$target/$slug"

    if [ "$action" = "uninstall" ]; then
      if [ -L "$link" ]; then
        rm "$link"
        removed=$((removed + 1))
        printf '  removed  %s\n' "$slug"
      fi
      continue
    fi

    if [ -L "$link" ]; then
      rm "$link"
      ln -s "${dir%/}" "$link"
      linked=$((linked + 1))
      printf '  relinked %s\n' "$slug"
    elif [ -e "$link" ]; then
      skipped=$((skipped + 1))
      printf '  SKIP     %s (real file or directory already there)\n' "$slug"
    else
      ln -s "${dir%/}" "$link"
      linked=$((linked + 1))
      printf '  linked   %s\n' "$slug"
    fi
  done
done

printf '\n'
if [ "$action" = "uninstall" ]; then
  printf 'removed %s link(s).\n' "$removed"
else
  printf 'linked %s, skipped %s.\n' "$linked" "$skipped"
  [ "$skipped" -gt 0 ] && printf 'Skipped entries are real directories - move them aside and rerun.\n'
  printf 'Restart your agent session so it rescans the skills directory.\n'
fi

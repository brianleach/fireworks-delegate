#!/usr/bin/env bash
# Symlink this repo into ~/.claude/skills/fireworks-delegate (idempotent).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${HOME}/.claude/skills"
LINK_PATH="${SKILLS_DIR}/fireworks-delegate"

mkdir -p "$SKILLS_DIR"

if [ -L "$LINK_PATH" ]; then
  current_target="$(readlink "$LINK_PATH")"
  if [ "$current_target" = "$REPO_DIR" ]; then
    echo "Already installed: $LINK_PATH -> $REPO_DIR"
    exit 0
  fi
  echo "Updating existing symlink (was -> $current_target)"
  rm "$LINK_PATH"
elif [ -e "$LINK_PATH" ]; then
  echo "Error: $LINK_PATH exists and is not a symlink. Remove it manually and rerun." >&2
  exit 1
fi

ln -s "$REPO_DIR" "$LINK_PATH"
echo "Installed: $LINK_PATH -> $REPO_DIR"

#!/usr/bin/env bash
# snapshot-claude-md.sh
# Creates a daily snapshot of CLAUDE.md before modification.
# Keeps the first snapshot of each day in ~/.claude/CLAUDE.history/yymmdd.md.
#
# Usage: snapshot-claude-md.sh <path-to-CLAUDE.md>
# Exit codes: always 0 (best-effort, never blocks)

FILE_PATH="${1:-$HOME/.claude/CLAUDE.md}"

if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

HISTORY_DIR="$(dirname "$FILE_PATH")/CLAUDE.history"
BACKUP_NAME="$(date +%y%m%d).md"

mkdir -p "$HISTORY_DIR"

# Only backup once per day (keep first snapshot of the day)
if [[ ! -f "$HISTORY_DIR/$BACKUP_NAME" ]]; then
  cp "$FILE_PATH" "$HISTORY_DIR/$BACKUP_NAME"
fi

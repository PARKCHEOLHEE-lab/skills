#!/usr/bin/env bash
# validate-memory.sh
# PreToolUse hook: validates memory writes via two checks:
#   1. Approval token — blocks writes without user consent (/tmp/memory-approved.json)
#   2. Semantic validation — calls haiku to check content quality
#
# Exit codes:
#   0 = allow
#   2 = block (reason printed to stdout as JSON)
#
# Safety: on ANY unexpected error in semantic validation, allow the write (fail-open).
# But approval token check is strict — no token = block.

INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

# No file path = not relevant
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Check if this is a memory-related write
IS_MEMORY=false
case "$FILE_PATH" in
  */memory/*.md)
    IS_MEMORY=true
    ;;
  */.claude/CLAUDE.md)
    IS_MEMORY=true
    ;;
esac

if [[ "$IS_MEMORY" != "true" ]]; then
  exit 0
fi

# Skip MEMORY.md index file (just pointers, not actual memory content)
BASENAME=$(basename "$FILE_PATH")
if [[ "$BASENAME" == "MEMORY.md" ]]; then
  exit 0
fi

# ──────────────────────────────────────────────
# Check 1: Approval token
# ──────────────────────────────────────────────
APPROVAL_FILE="/tmp/memory-approved.json"

if [[ ! -f "$APPROVAL_FILE" ]]; then
  echo '{"decision": "block", "reason": "[memory-gate] No approval token found. User confirmation is required before saving memories."}'
  exit 2
fi

# Check if this specific file is in the approved list
IS_APPROVED=$(jq -r --arg name "$BASENAME" '.files | map(select(. == $name)) | length' "$APPROVAL_FILE" 2>/dev/null) || IS_APPROVED="0"

if [[ "$IS_APPROVED" == "0" ]]; then
  echo "{\"decision\": \"block\", \"reason\": \"[memory-gate] '$BASENAME' is not in the approved list. User did not select this file for saving.\"}"
  exit 2
fi

# Check token age — reject if older than 10 minutes (stale approval)
if command -v python3 &>/dev/null; then
  TOKEN_AGE=$(python3 -c "
import os, time
try:
    mtime = os.path.getmtime('$APPROVAL_FILE')
    print(int(time.time() - mtime))
except:
    print(0)
" 2>/dev/null) || TOKEN_AGE="0"

  if [[ "$TOKEN_AGE" -gt 600 ]]; then
    echo '{"decision": "block", "reason": "[memory-gate] Approval token expired (>10 min). Please re-confirm."}'
    exit 2
  fi
fi

# ──────────────────────────────────────────────
# Check 2: Semantic validation via haiku
# ──────────────────────────────────────────────
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null) || exit 0

if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Count content lines (excluding frontmatter)
BODY=$(echo "$CONTENT" | sed '/^---$/,/^---$/d')
LINE_COUNT=$(echo "$BODY" | grep -c '[^[:space:]]' || echo "0")

# Collect existing memories for duplicate check
EXISTING_MEMORIES=""
PARENT_DIR="$(dirname "$FILE_PATH")"
if [[ "$(basename "$PARENT_DIR")" == "memory" ]]; then
  MEMORY_DIR="$PARENT_DIR"
elif [[ -d "$PARENT_DIR/memory" ]]; then
  MEMORY_DIR="$PARENT_DIR/memory"
else
  MEMORY_DIR=""
fi

if [[ -n "$MEMORY_DIR" && -d "$MEMORY_DIR" ]]; then
  for f in "$MEMORY_DIR"/*.md; do
    if [[ -f "$f" && "$(basename "$f")" != "MEMORY.md" ]]; then
      EXISTING_MEMORIES+="--- $(basename "$f") ---"$'\n'
      EXISTING_MEMORIES+="$(head -20 "$f")"$'\n'
    fi
  done
fi

GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
if [[ -f "$GLOBAL_CLAUDE" ]]; then
  EXISTING_MEMORIES+="--- CLAUDE.md ---"$'\n'
  EXISTING_MEMORIES+="$(cat "$GLOBAL_CLAUDE")"$'\n'
fi

# Write prompt to temp file to avoid shell escaping issues
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

cat > "$PROMPT_FILE" <<PROMPT_END
You are a memory validation gate. Evaluate whether this content is appropriate to save as a Claude Code memory.

## Content to validate:
$CONTENT

## Existing memories (check for duplicates):
$EXISTING_MEMORIES

## Rules — BLOCK if ANY of these apply:
1. Contains code patterns, file paths, or architecture details (derivable from codebase)
2. Contains git history or debugging solutions (derivable from git)
3. Duplicates or substantially overlaps with existing memories
4. Content body exceeds 5 meaningful lines (current: $LINE_COUNT lines)
5. Contains ephemeral task details only useful in current conversation

## Rules — ALLOW if:
- User preferences, work style, role information
- Feedback/corrections about how Claude should work
- Non-obvious project context (goals, deadlines, decisions)
- External system references (dashboards, ticket trackers)

Respond with ONLY a JSON object, no markdown fences:
{"approved": true}
or
{"approved": false, "reason": "one-line explanation in Korean"}
PROMPT_END

# Call haiku for validation (fail-open on any error)
RESULT=$(claude -p --model haiku --no-session-persistence "$(cat "$PROMPT_FILE")" 2>/dev/null) || {
  exit 0
}

# Parse result — fail-open if parsing fails
APPROVED=$(echo "$RESULT" | grep -o '"approved":\s*\(true\|false\)' | head -1 | grep -o 'true\|false') || {
  exit 0
}

if [[ "$APPROVED" == "false" ]]; then
  REASON=$(echo "$RESULT" | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    print(data.get('reason', 'Memory validation failed'))
except:
    print('Memory validation failed')
" 2>/dev/null) || REASON="Memory validation failed"
  echo "{\"decision\": \"block\", \"reason\": \"[memory-gate] $REASON\"}"
  exit 2
fi

exit 0

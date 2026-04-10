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

# Auto-backup CLAUDE.md before modification
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
case "$FILE_PATH" in
  */.claude/CLAUDE.md)
    "$SCRIPT_DIR/snapshot-claude-md.sh" "$FILE_PATH"
    ;;
esac

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
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || TOOL_NAME=""
OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null) || OLD_STRING=""

if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Strictness level: low / medium (default) / high
# Set via: export MEMORY_GATE_STRICTNESS=low
STRICTNESS="${MEMORY_GATE_STRICTNESS:-medium}"

# Count content lines (excluding frontmatter)
BODY=$(echo "$CONTENT" | sed '/^---$/,/^---$/d')
LINE_COUNT=$(echo "$BODY" | grep -c '[^[:space:]]' || echo "0")

# Set line limit based on strictness
case "$STRICTNESS" in
  low)  MAX_LINES=15 ;;
  high) MAX_LINES=5 ;;
  *)    MAX_LINES=10 ;;
esac

# Collect existing memories for context
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
    # Skip the file being modified and MEMORY.md index
    if [[ -f "$f" && "$(basename "$f")" != "MEMORY.md" && "$f" != "$FILE_PATH" ]]; then
      EXISTING_MEMORIES+="--- $(basename "$f") ---"$'\n'
      EXISTING_MEMORIES+="$(head -20 "$f")"$'\n'
    fi
  done
fi

GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
# Skip if CLAUDE.md is the file being modified
if [[ -f "$GLOBAL_CLAUDE" && "$FILE_PATH" != "$GLOBAL_CLAUDE" ]]; then
  EXISTING_MEMORIES+="--- CLAUDE.md ---"$'\n'
  EXISTING_MEMORIES+="$(cat "$GLOBAL_CLAUDE")"$'\n'
fi

# Build strictness-specific guidance
case "$STRICTNESS" in
  low)
    STRICTNESS_GUIDE="You are in LENIENT mode. Be generous — only block content that is clearly junk, completely derivable from code/git, or exact word-for-word duplicates with no new information."
    ;;
  high)
    STRICTNESS_GUIDE="You are in STRICT mode. Block content that is derivable from the codebase, loosely overlaps with existing memories without meaningful improvement, or exceeds $MAX_LINES lines."
    ;;
  *)
    STRICTNESS_GUIDE="You are in BALANCED mode. Allow content that adds value. Only block content that is clearly derivable from code/git or is an exact duplicate with zero new information."
    ;;
esac

# Write prompt to temp file to avoid shell escaping issues
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

EDIT_CONTEXT=""
if [[ "$TOOL_NAME" == "Edit" && -n "$OLD_STRING" ]]; then
  EDIT_CONTEXT="## Operation: Edit (updating existing content)
This is an UPDATE to an existing file, NOT a new memory. The old content is being replaced with new content.

### Old content (being replaced):
$OLD_STRING

### New content (replacement):
$CONTENT"
fi

cat > "$PROMPT_FILE" <<PROMPT_END
You are a memory validation gate. Evaluate whether this content is appropriate to save as a Claude Code memory.

$STRICTNESS_GUIDE

$(if [[ -n "$EDIT_CONTEXT" ]]; then echo "$EDIT_CONTEXT"; else echo "## Content to validate:
$CONTENT"; fi)

## Existing memories (for context):
$EXISTING_MEMORIES

## Rules — BLOCK if ANY of these apply:
1. Contains ONLY code patterns, file paths, or architecture details (derivable from codebase)
2. Contains ONLY git history or debugging solutions (derivable from git)
3. Content body exceeds $MAX_LINES meaningful lines (current: $LINE_COUNT lines)
4. Contains ONLY ephemeral task details with no future value

## Rules — ALLOW if ANY of these apply:
- User preferences, work style, role information
- Feedback/corrections about how Claude should work
- Non-obvious project context (goals, deadlines, decisions)
- External system references (dashboards, ticket trackers)
- Content that UPDATES or IMPROVES existing memories (overlap is OK if it refines, consolidates, or adds new detail)
- Content being written to the SAME file it already exists in (this is an update, not a duplicate)

## Important:
- Overlap with existing memories is NOT a reason to block. Repetition signals importance.
- If the new content improves, refines, or consolidates existing information, ALLOW it.
- If the operation is an Edit (update), the new content will naturally overlap with the file being edited — do NOT treat overlap with the SAME file as duplication. Only block if the new content is a duplicate of a DIFFERENT memory file.
- When in doubt, ALLOW. The user has already confirmed they want to save this.

Respond with ONLY a JSON object, no markdown fences:
{"approved": true}
or
{"approved": false, "reason": "one-line explanation in Korean"}
PROMPT_END

# Call haiku for validation (fail-open on any error)
RESULT=$(claude -p --model sonnet --no-session-persistence "$(cat "$PROMPT_FILE")" 2>/dev/null) || {
  exit 0
}

# Log haiku response for debugging
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] file=$BASENAME result=$RESULT" >> "$LOG_DIR/memory-gate.log"

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

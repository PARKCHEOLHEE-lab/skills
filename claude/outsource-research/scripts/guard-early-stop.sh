#!/bin/bash
# guard-early-stop.sh — PreToolUse hook guard for outsource-research full mode
# Blocks Write tool calls that contain "Full-Mode Research Log" if context target not reached.
# Receives tool call JSON via stdin.

STATE_FILE="/tmp/outsource-research-state.json"

# If no state file, full mode is not active — allow everything
if [ ! -f "$STATE_FILE" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Read the tool input from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only guard Write tool calls
if [ "$TOOL_NAME" != "Write" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Check if the write content contains the final section marker
# Use jq test() to handle escaped content safely within jq itself
HAS_MARKER=$(echo "$INPUT" | jq -r 'if (.tool_input.content // "" | test("Full-Mode Research Log")) then "yes" else "no" end' 2>/dev/null || echo "no")
if [ "$HAS_MARKER" != "yes" ]; then
  # Not the final report write — allow
  echo '{"decision":"allow"}'
  exit 0
fi

# This is the final report write. Check actual context usage.
TARGET_PCT=$(jq -r '.target_pct // 0' "$STATE_FILE")
CHECK_SCRIPT="$HOME/.claude/skills/outsource-research/scripts/check-context.sh"

if [ ! -f "$CHECK_SCRIPT" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

USAGE_JSON=$(bash "$CHECK_SCRIPT")
ACTUAL_PCT=$(echo "$USAGE_JSON" | jq -r '.usage_pct // 0')

# Compare: if actual < target, block the write
BELOW_TARGET=$(python3 -c "print('yes' if float($ACTUAL_PCT) < float($TARGET_PCT) else 'no')")

if [ "$BELOW_TARGET" = "yes" ]; then
  echo "{\"decision\":\"block\",\"reason\":\"Context target not reached. Actual: ${ACTUAL_PCT}% / Target: ${TARGET_PCT}%. Run check-context.sh to verify, then continue the iterative research loop. Do NOT write the final report until the target is met.\"}"
  exit 0
fi

# Target reached — allow the write
echo '{"decision":"allow"}'
exit 0

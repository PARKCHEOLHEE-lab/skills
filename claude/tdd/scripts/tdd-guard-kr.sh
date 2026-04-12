#!/bin/bash
# guard-early-stop.sh — PreToolUse hook guard for TDD KR loop
# Blocks attempts to write the final "TDD Complete" report if incomplete KRs remain.
# Receives tool call JSON via stdin.

STATE_FILE="/tmp/tdd-kr-state.json"

# If no state file, TDD loop is not active — allow everything
if [ ! -f "$STATE_FILE" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Read the tool input from stdin
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only guard Write and Edit tool calls
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# Check if the content contains the final report marker "TDD Complete"
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // ""')
HAS_MARKER=$(echo "$CONTENT" | grep -c "TDD Complete" || true)

if [ "$HAS_MARKER" -eq 0 ]; then
  # Not the final report — allow (normal test/implementation writes)
  echo '{"decision":"allow"}'
  exit 0
fi

# This is the final report. Check if all KRs are done.
TOTAL=$(jq '.krs | length' "$STATE_FILE" 2>/dev/null || echo 0)
DONE=$(jq '[.krs[] | select(.done == true)] | length' "$STATE_FILE" 2>/dev/null || echo 0)
REMAINING=$((TOTAL - DONE))

if [ "$REMAINING" -gt 0 ]; then
  # Get the next incomplete KR for the message
  NEXT_KR=$(jq -r '[.krs[] | select(.done != true)][0].desc // "unknown"' "$STATE_FILE" 2>/dev/null)
  echo "{\"decision\":\"block\",\"reason\":\"Cannot write final report — ${REMAINING} KR(s) remaining. Next: ${NEXT_KR}. Continue the RED→GREEN→REFACTOR loop for the next KR. After completing a KR, update the state file: jq '.krs[N].done = true' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json\"}"
  exit 0
fi

# All KRs done — allow the final report
echo '{"decision":"allow"}'
exit 0

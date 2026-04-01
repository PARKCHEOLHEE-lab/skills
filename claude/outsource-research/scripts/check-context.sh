#!/bin/bash
# check-context.sh — Returns actual session context usage percentage
# Reads the most recent session JSONL from the Claude project directory
# and calculates token usage relative to the model's context window.
#
# Usage: bash check-context.sh [context_window_size]
#   context_window_size: optional, defaults to 1000000 (1M for Opus)
#
# Output: JSON with usage_pct, total_tokens, context_window
# Exit code: 0 always (errors reported in JSON)

CONTEXT_WINDOW="${1:-1000000}"

# Find the project directory matching the current working directory
# Try with leading hyphen first (Claude Code's actual format), then without
CWD_HASH=$(echo "$PWD" | sed 's|/|-|g')
PROJECT_DIR="$HOME/.claude/projects/$CWD_HASH"

if [ ! -d "$PROJECT_DIR" ]; then
  # Try without leading hyphen
  CWD_HASH=$(echo "$PWD" | sed 's|/|-|g; s|^-||')
  PROJECT_DIR="$HOME/.claude/projects/$CWD_HASH"
fi

if [ ! -d "$PROJECT_DIR" ]; then
  # Fallback: search all project dirs for most recent JSONL
  PROJECT_DIR="$HOME/.claude/projects"
fi

# Find the most recently modified .jsonl file
JSONL=$(find "$PROJECT_DIR" -name "*.jsonl" -maxdepth 2 -type f -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1)

if [ -z "$JSONL" ]; then
  echo '{"error":"no_session_file","usage_pct":0,"total_tokens":0,"context_window":'"$CONTEXT_WINDOW"'}'
  exit 0
fi

export JSONL_PATH="$JSONL"
export CTX_WINDOW="$CONTEXT_WINDOW"

python3 << 'PYEOF'
import json, sys, os

jsonl_path = os.environ.get("JSONL_PATH", "")
context_window = int(os.environ.get("CTX_WINDOW", "1000000"))

if not jsonl_path:
    print(json.dumps({"error": "no_jsonl_path", "usage_pct": 0, "total_tokens": 0, "context_window": context_window}))
    sys.exit(0)

try:
    with open(jsonl_path, "r") as f:
        lines = f.readlines()
except Exception as e:
    print(json.dumps({"error": str(e), "usage_pct": 0, "total_tokens": 0, "context_window": context_window}))
    sys.exit(0)

# Find the last assistant message with usage data
for line in reversed(lines):
    try:
        d = json.loads(line)
        msg = d.get("message", {})
        if msg.get("role") == "assistant" and "usage" in msg:
            u = msg["usage"]
            input_tokens = u.get("input_tokens", 0)
            cache_creation = u.get("cache_creation_input_tokens", 0)
            cache_read = u.get("cache_read_input_tokens", 0)
            output_tokens = u.get("output_tokens", 0)
            total_input = input_tokens + cache_creation + cache_read
            pct = round((total_input / context_window) * 100, 1)
            print(json.dumps({
                "usage_pct": pct,
                "total_tokens": total_input,
                "output_tokens": output_tokens,
                "context_window": context_window,
                "session_file": jsonl_path
            }))
            sys.exit(0)
    except json.JSONDecodeError:
        continue

print(json.dumps({"error": "no_usage_data", "usage_pct": 0, "total_tokens": 0, "context_window": context_window}))
PYEOF

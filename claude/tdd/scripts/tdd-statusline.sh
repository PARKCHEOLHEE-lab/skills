#!/bin/bash
# tdd-statusline.sh — Renders TDD KR progress as a tree when state file exists.
# Outputs nothing if TDD is not active.
# Called by the statusline wrapper.

STATE_FILE="/tmp/tdd-kr-state.json"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

python3 <<'PYEOF'
import json
import sys

STATE_FILE = "/tmp/tdd-kr-state.json"

try:
    with open(STATE_FILE) as f:
        state = json.load(f)
except Exception:
    sys.exit(0)

krs = state.get("krs", [])
if not krs:
    sys.exit(0)

def icon(kr):
    if kr.get("done") or kr.get("status") == "completed":
        return "✓"
    if kr.get("status") == "in_progress":
        return "◐"
    return "○"

def tag(kr):
    parts = []
    if kr.get("decomposing"):
        parts.append("decomposing")
    retry = kr.get("retry")
    if retry:
        phase = retry.get("phase", "?")
        count = retry.get("count", 0)
        mx = retry.get("max", 3)
        parts.append(f"❌ {phase} {count}/{mx}")
    if parts:
        return " [" + " | ".join(parts) + "]"
    return ""

print("TDD")
for kr in krs:
    depth = kr.get("depth", 0)
    indent = "  " * depth
    kr_id = kr.get("id", "?")
    desc = (kr.get("desc") or "")[:48]
    print(f"{indent}{icon(kr)} KR{kr_id}{tag(kr)}: {desc}")
PYEOF

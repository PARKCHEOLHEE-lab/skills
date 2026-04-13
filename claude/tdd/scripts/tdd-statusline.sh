#!/bin/bash
# tdd-statusline.sh — Renders TDD KR progress as a colored tree when state file exists.
# Outputs nothing if TDD is not active.
# Uses box-drawing characters for indentation since leading whitespace
# is stripped by Claude Code's statusline rendering.

STATE_FILE="/tmp/tdd-kr-state.json"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

python3 <<'PYEOF'
import json
import sys

STATE_FILE = "/tmp/tdd-kr-state.json"

# ANSI color codes
RESET = "\033[0m"
DIM = "\033[2m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
CYAN = "\033[36m"
BOLD = "\033[1m"

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
        return f"{GREEN}✓{RESET}"
    if kr.get("status") == "in_progress":
        return f"{YELLOW}◐{RESET}"
    return f"{DIM}○{RESET}"

def tag(kr):
    parts = []
    if kr.get("decomposing"):
        parts.append(f"{CYAN}decomposing{RESET}")
    retry = kr.get("retry")
    if retry:
        phase = retry.get("phase", "?")
        count = retry.get("count", 0)
        mx = retry.get("max", 3)
        parts.append(f"{RED}❌ {phase} {count}/{mx}{RESET}")
    if parts:
        return " [" + " | ".join(parts) + "]"
    return ""

def is_last_at_depth(krs, idx):
    """A KR is 'last' if the next KR has lower depth or doesn't exist."""
    current_depth = krs[idx].get("depth", 0)
    for j in range(idx + 1, len(krs)):
        next_depth = krs[j].get("depth", 0)
        if next_depth < current_depth:
            return True
        if next_depth == current_depth:
            return False
    return True

# Header with progress summary (all KRs including sub-KRs)
done = sum(1 for k in krs if k.get("done") or k.get("status") == "completed")
in_progress = sum(1 for k in krs if k.get("status") == "in_progress" and not (k.get("done") or k.get("status") == "completed"))
pending = sum(1 for k in krs if k.get("status") == "pending")

header = (
    f"{BOLD}[TDD]{RESET} {DIM}|{RESET} "
    f"{GREEN}{done} ✓{RESET} {DIM}·{RESET} "
    f"{YELLOW}{in_progress} ◐{RESET} {DIM}·{RESET} "
    f"{DIM}{pending} ○{RESET}"
)
print(header)

for i, kr in enumerate(krs):
    depth = kr.get("depth", 0)
    kr_id = kr.get("id", "?")
    desc = (kr.get("desc") or "")[:48]
    status_icon = icon(kr)
    state_tag = tag(kr)

    if depth == 0:
        prefix = ""
    else:
        last = is_last_at_depth(krs, i)
        branch = "└─" if last else "├─"
        prefix = f"{DIM}{branch}{RESET}" + " " * max(1, (depth - 1) * 3) + " "

    print(f"{prefix}{status_icon} {DIM}KR{kr_id}{RESET}{state_tag}: {desc}")

# Separator line between TDD section and the rest of the statusline
print(f"{DIM}{'─' * 50}{RESET}")
PYEOF

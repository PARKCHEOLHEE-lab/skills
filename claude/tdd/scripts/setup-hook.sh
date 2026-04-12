#!/bin/bash
# setup-hook.sh — Idempotent setup for TDD hooks
# Registers two hooks in settings.json if not already present:
#   1. UserPromptSubmit: tdd-detect.sh (context-based TDD activation)
#   2. PreToolUse: tdd-guard-kr.sh (blocks final report until all KRs done)
#
# Output: JSON with status information
# Safe to run multiple times.

SETTINGS_FILE="$HOME/.claude/settings.json"
SKILL_DIR="$HOME/.claude/skills/tdd/scripts"

# Ensure settings.json exists
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{"hooks":{}}' > "$SETTINGS_FILE"
fi

# Check both scripts exist
for SCRIPT in tdd-detect.sh tdd-guard-kr.sh; do
  if [ ! -f "$SKILL_DIR/$SCRIPT" ]; then
    echo "{\"status\":\"error\",\"message\":\"$SCRIPT not found at $SKILL_DIR/$SCRIPT. Install the tdd skill first.\"}"
    exit 0
  fi
done

# Check and register both hooks
RESULT=$(python3 -c "
import json, sys

settings_path = '$SETTINGS_FILE'
skill_dir = '$SKILL_DIR'

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})
changed = False

# Hook 1: UserPromptSubmit — tdd-detect.sh
user_prompt = hooks.setdefault('UserPromptSubmit', [])
detect_exists = any(
    'tdd-detect.sh' in h.get('command', '')
    for entry in user_prompt
    for h in entry.get('hooks', [])
)
if not detect_exists:
    user_prompt.append({
        'matcher': '',
        'hooks': [{
            'type': 'command',
            'command': f'bash {skill_dir}/tdd-detect.sh',
            'timeout': 5000
        }]
    })
    changed = True

# Hook 2: PreToolUse — tdd-guard-kr.sh
pre_tool = hooks.setdefault('PreToolUse', [])
guard_exists = any(
    'tdd-guard-kr.sh' in h.get('command', '')
    for entry in pre_tool
    for h in entry.get('hooks', [])
)
if not guard_exists:
    pre_tool.append({
        'matcher': 'Write|Edit',
        'hooks': [{
            'type': 'command',
            'command': f'bash {skill_dir}/tdd-guard-kr.sh',
            'timeout': 10000
        }]
    })
    changed = True

if changed:
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print('newly_registered')
else:
    print('already_registered')
" 2>/dev/null)

case "$RESULT" in
  "already_registered")
    echo '{"status":"already_registered","hook_active_this_session":true,"message":"Both TDD hooks (detect + guard) are already registered."}'
    ;;
  "newly_registered")
    echo '{"status":"newly_registered","hook_active_this_session":false,"message":"TDD hooks registered in settings.json. Session restart required for hooks to take effect."}'
    ;;
  *)
    echo "{\"status\":\"error\",\"message\":\"Failed to update settings.json: $RESULT\"}"
    ;;
esac

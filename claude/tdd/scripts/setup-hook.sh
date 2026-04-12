#!/bin/bash
# setup-hook.sh — Idempotent setup for TDD detect hook
# Checks if the tdd-detect hook is registered in settings.json; if not, registers it.
#
# Output: JSON with status information
# Safe to run multiple times.

SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_CMD="bash ~/.claude/skills/tdd/scripts/tdd-detect.sh"
HOOK_IDENTIFIER="tdd-detect.sh"
SCRIPT_PATH="$HOME/.claude/skills/tdd/scripts/tdd-detect.sh"

# Ensure settings.json exists
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{"hooks":{}}' > "$SETTINGS_FILE"
fi

# Check if the hook script exists
if [ ! -f "$SCRIPT_PATH" ]; then
  echo "{\"status\":\"error\",\"message\":\"tdd-detect.sh not found at $SCRIPT_PATH. Install the tdd skill first.\"}"
  exit 0
fi

# Check if the hook is already registered
HOOK_EXISTS=$(python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        settings = json.load(f)
    hooks = settings.get('hooks', {})
    user_prompt = hooks.get('UserPromptSubmit', [])
    for entry in user_prompt:
        for h in entry.get('hooks', []):
            if '$HOOK_IDENTIFIER' in h.get('command', ''):
                print('yes')
                sys.exit(0)
    print('no')
except Exception as e:
    print('error:' + str(e))
" 2>/dev/null)

if [ "$HOOK_EXISTS" = "yes" ]; then
  echo '{"status":"already_registered","hook_active_this_session":true,"message":"TDD detect hook is already registered in settings.json."}'
  exit 0
fi

if echo "$HOOK_EXISTS" | grep -q "^error:"; then
  echo "{\"status\":\"error\",\"message\":\"Failed to read settings.json: $HOOK_EXISTS\"}"
  exit 0
fi

# Hook not registered — add it
python3 -c "
import json

settings_path = '$SETTINGS_FILE'
hook_cmd = '$HOOK_CMD'

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})
user_prompt = hooks.setdefault('UserPromptSubmit', [])

user_prompt.append({
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': hook_cmd,
        'timeout': 5000
    }]
})

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')

print('ok')
" 2>/dev/null

if [ $? -eq 0 ]; then
  echo '{"status":"newly_registered","hook_active_this_session":false,"message":"TDD detect hook registered in settings.json. Session restart required for the hook to take effect."}'
else
  echo '{"status":"error","message":"Failed to update settings.json."}'
fi

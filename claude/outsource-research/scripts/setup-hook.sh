#!/bin/bash
# setup-hook.sh — Idempotent setup for outsource-research PreToolUse guard hook
# Checks if the hook is registered in settings.json; if not, registers it.
# Reports whether the hook is active in the current session.
#
# Output: JSON with status information
# Safe to run multiple times.

SETTINGS_FILE="$HOME/.claude/settings.json"
GUARD_CMD="bash ~/.claude/skills/outsource-research/scripts/guard-early-stop.sh"

# Ensure settings.json exists
if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{"hooks":{}}' > "$SETTINGS_FILE"
fi

# Check if the guard hook is already registered
HOOK_EXISTS=$(python3 -c "
import json, sys
try:
    with open('$SETTINGS_FILE') as f:
        settings = json.load(f)
    hooks = settings.get('hooks', {})
    pre_tool = hooks.get('PreToolUse', [])
    for entry in pre_tool:
        for h in entry.get('hooks', []):
            if 'guard-early-stop' in h.get('command', ''):
                print('yes')
                sys.exit(0)
    print('no')
except Exception as e:
    print('error:' + str(e))
" 2>/dev/null)

if [ "$HOOK_EXISTS" = "yes" ]; then
  echo '{"status":"already_registered","hook_active_this_session":true,"message":"Guard hook is already registered in settings.json."}'
  exit 0
fi

if echo "$HOOK_EXISTS" | grep -q "^error:"; then
  echo "{\"status\":\"error\",\"message\":\"Failed to read settings.json: $HOOK_EXISTS\"}"
  exit 0
fi

# Hook not registered — add it
python3 -c "
import json, sys

settings_path = '$SETTINGS_FILE'
guard_cmd = '$GUARD_CMD'

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})
pre_tool = hooks.setdefault('PreToolUse', [])

# Add the guard hook entry
pre_tool.append({
    'matcher': 'Write',
    'hooks': [{
        'type': 'command',
        'command': guard_cmd,
        'timeout': 10000
    }]
})

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write('\n')

print('ok')
" 2>/dev/null

if [ $? -eq 0 ]; then
  echo '{"status":"newly_registered","hook_active_this_session":false,"message":"Guard hook registered in settings.json. Session restart required for the hook to take effect."}'
else
  echo '{"status":"error","message":"Failed to update settings.json."}'
fi

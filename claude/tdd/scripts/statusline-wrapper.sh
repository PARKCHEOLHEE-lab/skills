#!/bin/bash
# statusline-wrapper.sh — Combines TDD progress tree with claude-hud output.
# TDD progress is prepended when /tmp/tdd-kr-state.json exists.
# Falls back to claude-hud only when TDD is inactive.

# Pass stdin through to claude-hud (which expects session JSON via stdin)
INPUT=$(cat)

# Render TDD progress if active (no stdin needed)
bash "$HOME/.claude/skills/tdd/scripts/tdd-statusline.sh"

# Then render claude-hud
plugin_dir=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null \
  | awk -F/ '{ print $(NF-1) "\t" $0 }' \
  | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
  | tail -1 \
  | cut -f2-)

if [ -n "$plugin_dir" ] && [ -x "/Users/jjinjjang/.bun/bin/bun" ]; then
  echo "$INPUT" | "/Users/jjinjjang/.bun/bin/bun" --env-file /dev/null "${plugin_dir}src/index.ts"
fi

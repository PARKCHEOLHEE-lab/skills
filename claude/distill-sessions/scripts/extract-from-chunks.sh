#!/bin/bash
# extract-from-chunks.sh — Sliding-window extraction over pre-built chunks.
#
# Usage: extract-from-chunks.sh <chunks-dir> [model]
#
# Reads chunk_NNN.txt files from <chunks-dir> in order. For each chunk, calls
# `claude -p` with the chunk + a cumulative summary of all prior chunks.
# After each call, the model is asked to update the running summary.
#
# Outputs a single JSON array of merged candidates to stdout.

set -uo pipefail

CHUNKS_DIR="${1:?usage: extract-from-chunks.sh <chunks-dir> [model]}"
MODEL="${2:-sonnet}"

if [ ! -d "$CHUNKS_DIR" ]; then
  echo "error: $CHUNKS_DIR not found" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

SUMMARY_FILE="$WORK_DIR/summary.txt"
: > "$SUMMARY_FILE"

ALL_CANDIDATES="$WORK_DIR/all.json"
echo "[]" > "$ALL_CANDIDATES"

CHUNK_FILES=("$CHUNKS_DIR"/chunk_*.txt)
TOTAL=${#CHUNK_FILES[@]}
echo "extracting from $TOTAL chunks..." >&2

for i in "${!CHUNK_FILES[@]}"; do
  CHUNK_PATH="${CHUNK_FILES[$i]}"
  IDX=$((i + 1))
  echo "  chunk $IDX/$TOTAL: $(basename "$CHUNK_PATH")" >&2

  PROMPT_FILE="$WORK_DIR/prompt_$IDX.txt"
  cat > "$PROMPT_FILE" <<'PROMPT_HEADER'
You are extracting memory candidates from one chunk of a longer Claude Code session.

Extract ONLY information worth remembering for future sessions:
1) user (role/preferences/knowledge)
2) feedback (corrections like "don't do X" or confirmations like "yes exactly")
3) project (non-obvious context: goals, decisions, deadlines, stakeholders)
4) reference (pointers to external systems)

Do NOT extract code patterns, file paths, git history, or anything already in CLAUDE.md.

Output a JSON object with two fields:
{
  "candidates": [{"type": "...", "title": "...", "content": "...", "why": "..."}, ...],
  "summary_update": "1-3 sentence update to running summary, capturing the key context this chunk added"
}

If nothing in this chunk is worth remembering, return {"candidates": [], "summary_update": "..."}.

PROMPT_HEADER

  if [ -s "$SUMMARY_FILE" ]; then
    echo "RUNNING SUMMARY OF PRIOR CHUNKS:" >> "$PROMPT_FILE"
    cat "$SUMMARY_FILE" >> "$PROMPT_FILE"
    echo "" >> "$PROMPT_FILE"
  fi

  echo "CHUNK $IDX/$TOTAL:" >> "$PROMPT_FILE"
  cat "$CHUNK_PATH" >> "$PROMPT_FILE"

  RESPONSE_FILE="$WORK_DIR/response_$IDX.json"
  if ! claude -p \
      --permission-mode default \
      --allowedTools "Read" \
      --model "$MODEL" \
      "$(cat "$PROMPT_FILE")" > "$RESPONSE_FILE" 2>"$WORK_DIR/err_$IDX.log"; then
    echo "  warning: chunk $IDX call failed, see $WORK_DIR/err_$IDX.log" >&2
    continue
  fi

  # Parse model response and merge into accumulator. All file paths passed
  # via env to avoid shell interpolation breaking JSON content (newlines etc).
  SUMMARY_OUT="$WORK_DIR/summary_$IDX.txt"
  RESPONSE_FILE="$RESPONSE_FILE" \
  ALL_CANDIDATES="$ALL_CANDIDATES" \
  SUMMARY_OUT="$SUMMARY_OUT" \
  python3 <<'PYEOF'
import json
import os
import sys

resp_path = os.environ["RESPONSE_FILE"]
all_path = os.environ["ALL_CANDIDATES"]
sum_path = os.environ["SUMMARY_OUT"]

with open(resp_path) as f:
    text = f.read().strip()

# Strip markdown code fences if present
if text.startswith("```"):
    lines = text.split("\n")
    if lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    text = "\n".join(lines)

# Find outermost JSON object
start = text.find("{")
end = text.rfind("}")
if start < 0 or end < 0:
    print("warn: no JSON object in response", file=sys.stderr)
    obj = {}
else:
    try:
        obj = json.loads(text[start:end+1])
    except json.JSONDecodeError as e:
        print(f"warn: JSON parse failed: {e}", file=sys.stderr)
        obj = {}

cands = obj.get("candidates", []) if isinstance(obj, dict) else []
summary_update = obj.get("summary_update", "") if isinstance(obj, dict) else ""

with open(all_path) as f:
    existing = json.load(f)
existing.extend(cands)
with open(all_path, "w") as f:
    json.dump(existing, f)

with open(sum_path, "w") as f:
    f.write(summary_update)

print(f"  +{len(cands)} candidates", file=sys.stderr)
PYEOF

  # Update running summary (cap at 2K chars to keep it tight)
  if [ -s "$SUMMARY_OUT" ]; then
    {
      [ -s "$SUMMARY_FILE" ] && cat "$SUMMARY_FILE"
      echo "[chunk $IDX] $(cat "$SUMMARY_OUT")"
    } | tail -c 2000 > "$SUMMARY_FILE.new"
    mv "$SUMMARY_FILE.new" "$SUMMARY_FILE"
  fi
done

cat "$ALL_CANDIDATES"

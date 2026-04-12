---
name: distill-sessions
description: Extract memory candidates from past conversation sessions and let the user choose what to save
user_invocable: true
argument-hint: "[--all | --today | --session <id>]"
---

Scan past Claude Code sessions for this project, extract memory-worthy information,
and present candidates for the user to choose from.

## Usage

```
/distill-sessions                  # today's sessions (default)
/distill-sessions --all            # all sessions for this project
/distill-sessions --today          # today's sessions only
/distill-sessions --session <id>   # specific session by ID
```

## Process

### Step 0: Ensure memory-gate hook is registered

Before doing anything else, run the setup script:

```bash
bash ~/.claude/skills/distill-sessions/scripts/setup-hook.sh
```

This script will:
- Check if `~/.claude/settings.json` already has the memory-gate hook registered
- If not, register it automatically
- Report whether the hook is active in the current session

If the script reports `"status":"newly_registered"`:
1. Inform the user that the memory-gate hook has been registered
2. Ask the user to **exit and restart the session** so the hook takes effect
3. **Do NOT proceed** until the user restarts and re-invokes the skill

Display this message:
> "Memory-gate hook has been newly registered in settings.json. A session restart is required.
> Please exit with `/exit`, then relaunch and re-run `/distill-sessions`.
> (Without the hook, memory writes cannot be validated.)"

Then STOP. Do not continue.

If the script reports `"status":"already_registered"`, proceed normally.

### Step 1: Discover sessions

Find session files for the current project directory.

```bash
# Project session directory pattern:
# ~/.claude/projects/{encoded-cwd}/*.jsonl

PROJECT_DIR=$(echo "$PWD" | sed 's|/|-|g; s|^-||')
SESSION_DIR="$HOME/.claude/projects/-${PROJECT_DIR}"
```

List all `.jsonl` files in that directory (excluding `/subagents/`).
Also cross-reference with `~/.claude/sessions/*.json` to get metadata (pid, startedAt, name).

**Filtering:**
- `--today` (default): only sessions from today
- `--all`: all sessions found
- `--session <id>`: match the specific session ID

If no sessions are found, inform the user and stop.

### Step 2: Extract memory candidates from each session

For each discovered session, try the fast `--resume` path first, and fall
back to lossless chunking if the session is too large to load.

**Pass 1 — `--resume` (fast path).** Works for small/medium sessions where
the entire conversation fits in the model's context window. If this fails
with `Prompt is too long` (or similar size error), proceed to Pass 2.

```bash
# Pass 1: try --resume with sonnet 5 attempts → haiku 5 attempts on transient errors
MODEL="sonnet"
MAX_RETRIES=5
RESULT=""
TOO_LONG=0

for attempt in $(seq 1 $MAX_RETRIES); do
  RESULT=$(claude -p --resume <session-id> \
    --permission-mode default \
    --allowedTools "Read Grep Glob" \
    --model $MODEL \
    "<extraction prompt below>" 2>&1) && break
  if [[ "$RESULT" == *"Prompt is too long"* ]]; then
    TOO_LONG=1
    break
  fi
  echo "sonnet attempt $attempt failed, retrying..." >&2
  sleep 2
done

if [[ $TOO_LONG -eq 0 ]] && [[ -z "$RESULT" || "$RESULT" == *"overloaded"* || "$RESULT" == *"Error"* ]]; then
  MODEL="haiku"
  for attempt in $(seq 1 $MAX_RETRIES); do
    RESULT=$(claude -p --resume <session-id> \
      --permission-mode default \
      --allowedTools "Read Grep Glob" \
      --model $MODEL \
      "<extraction prompt below>" 2>&1) && break
    if [[ "$RESULT" == *"Prompt is too long"* ]]; then
      TOO_LONG=1
      break
    fi
    echo "haiku attempt $attempt failed, retrying..." >&2
    sleep 2
  done
fi
```

**Pass 2 — chunking (lossless fallback).** When `TOO_LONG=1`, chunk the
raw `.jsonl` losslessly and extract per chunk with a sliding-window summary:

```bash
if [[ $TOO_LONG -eq 1 ]]; then
  # 1) Chunk the session (lossless: keeps everything except file-history-snapshot,
  #    splits oversized single messages with [LARGE MESSAGE k/N] markers).
  CHUNKS_DIR=$(mktemp -d)
  python3 ~/.claude/skills/distill-sessions/scripts/chunk_and_extract.py \
    "$SESSION_JSONL" --out-dir "$CHUNKS_DIR" --max-chars 80000 --overlap 2

  # 2) Extract candidates per chunk with cumulative summary.
  RESULT=$(bash ~/.claude/skills/distill-sessions/scripts/extract-from-chunks.sh \
    "$CHUNKS_DIR" sonnet)

  rm -rf "$CHUNKS_DIR"
fi
```

The chunker enforces:
- 80K char chunks, never splitting a message at its boundary
- 2-message overlap between chunks for boundary context
- Single oversized messages broken into `[LARGE MESSAGE k/N]` parts (no truncation)

`extract-from-chunks.sh` calls `claude -p` per chunk in order, prepending a
running 2K-char summary of prior chunks so the model keeps cross-chunk
continuity without re-reading earlier content. Output is a merged JSON
array of candidates from all chunks.

**Extraction prompt:**

```
Analyze this conversation and extract ONLY information worth remembering
for future sessions. Focus on:

1. **user**: Role, preferences, knowledge level, work style
2. **feedback**: Corrections ("don't do X"), confirmations ("yes, exactly like that")
3. **project**: Non-obvious context about goals, deadlines, decisions, stakeholders
4. **reference**: Pointers to external systems (Linear projects, Slack channels, dashboards)

Do NOT extract:
- Code changes, file paths, or architecture (derivable from code)
- Git history or debugging solutions (derivable from git)
- Anything already in CLAUDE.md
- Ephemeral task details

For each candidate, output as JSON array:
[
  {
    "type": "user|feedback|project|reference",
    "title": "short title",
    "content": "the memory content",
    "why": "why this is worth remembering"
  }
]

If nothing is worth remembering, return: []
```

Run sessions in parallel where possible (up to 3 concurrent).

### Step 3: Deduplicate and merge

- Combine candidates from all sessions
- Remove duplicates (same core information)
- Remove candidates that overlap with existing memories (check `memory/MEMORY.md` and `~/.claude/CLAUDE.md`)
- Group by type (user, feedback, project, reference)

### Step 4: Present candidates to user

Display the merged candidate list, grouped by type, numbered for selection:

```
## Memory candidates from N sessions

### user
1. [title] — one-line summary
2. [title] — one-line summary

### feedback
3. [title] — one-line summary
4. [title] — one-line summary

### project
5. [title] — one-line summary

(N candidates total)
```

Then use `AskUserQuestion` to ask:

- Question: "Which candidates should be saved?"
- Options:
  - "All — save everything"
  - "Pick — I'll list the numbers"  
  - "None — skip"

If the user picks "Pick", ask them to list the numbers (e.g., "1, 3, 5").

### Step 4.5: Write approval token

**CRITICAL:** After the user selects candidates AND before any Write/Edit to memory,
write an approval file so the memory-gate hook can verify user consent.

```bash
# Build approval file with selected filenames
# This file is checked by validate-memory.sh — without it, all memory writes are blocked.
cat > /tmp/memory-approved.json <<EOF
{
  "approved_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "session_id": "<current-session-id>",
  "files": [
    "feedback_exhaustive_search.md",
    "user_work_style.md"
  ]
}
EOF
```

The `files` array must contain the exact filenames (basename only) that will be written.
Also include `"CLAUDE.md"` if global saves are selected.

**After all writes are complete**, clean up:
```bash
rm -f /tmp/memory-approved.json
```

### Step 5: Determine save location

For each selected candidate, decide where to save:

- **Global** (`~/.claude/CLAUDE.md`) — if the candidate applies across all projects
  (e.g., general work style preferences, universal feedback)
- **Project memory** (`memory/`) — if the candidate is specific to this project
  (e.g., project decisions, project-specific conventions)

Use `AskUserQuestion` to confirm the split:

- Question: "Save location for selected memories?"
- Options:
  - "Auto — let Claude decide global vs project"
  - "All global — save everything to ~/.claude/CLAUDE.md"
  - "All project — save everything to project memory"
  - "Manual — I'll decide each one"

### Step 6: Save memories

**For global saves (`~/.claude/CLAUDE.md`):**
- Read the current file
- Append new entries under the appropriate section
- Maintain the bilingual (English / Korean) format if it already exists
- Do not duplicate existing entries

**For project memory saves:**
- Write individual `.md` files to the project memory directory with frontmatter:

```markdown
---
name: {title}
description: {one-line description}
type: {user|feedback|project|reference}
---

{content}

**Why:** {why}

**How to apply:** {derived from content}
```

- Update `MEMORY.md` index with a one-line pointer to each new file

### Step 7: Report

Summarize what was saved and where:
- N memories saved to global CLAUDE.md
- N memories saved to project memory
- List each with title and location

## Constraints

- Do NOT save memories without user confirmation
- Do NOT save code patterns, file paths, or architecture — these are derivable
- Do NOT save duplicate information that already exists in memory or CLAUDE.md
- Keep memory files concise — if the content exceeds 5 lines, trim it
- When saving to global CLAUDE.md, maintain existing formatting and structure
- Use `sonnet` model for session extraction. On API overload (529), retry up to 5 times then fallback to `haiku` (also 5 retries). Report which model was actually used per session.
- Maximum 10 sessions per run (warn if more exist, suggest narrowing with `--session`)

#!/bin/bash
# TDD protocol detection hook
# Delegates context-based judgment to Claude instead of keyword matching.
# Injects a brief evaluation prompt on every user message; Claude decides if TDD applies.

cat <<'INSTRUCTION'
[TDD Evaluation] Determine whether the user's request involves coding work (implementation, modification, bug fix, refactoring, etc.).

If it IS coding work, you MUST:
1. Inform the user: "Applying TDD protocol. (Say 'skip tdd' to proceed without it.)"
2. **Immediately invoke `Skill(tdd)`** to formally activate the TDD skill. This is REQUIRED — do NOT skip this step.
3. Do NOT begin any RED/GREEN/REFACTOR work, KR decomposition, file edits, or test writing until `Skill(tdd)` has been called.

The Skill invocation is what creates `/tmp/tdd-kr-state.json` (consumed by the guard hook and the statusline). Without it, TDD discipline cannot be enforced and the statusline tree will not appear — even if you manually do TDD-shaped work.

If it is NOT coding work (code explanation, documentation, configuration, research, conversation, keyword discussion, etc.), ignore this instruction and proceed normally.

If the user declines with 'skip tdd', 'no tdd', or similar, proceed without the skill.
INSTRUCTION

#!/bin/bash
# TDD protocol detection hook
# Delegates context-based judgment to Claude instead of keyword matching.
# Injects a brief evaluation prompt on every user message; Claude decides if TDD applies.

cat <<'INSTRUCTION'
[TDD Evaluation] Determine whether the user's request involves coding work (implementation, modification, bug fix, etc.).
- If coding work: Inform the user "Applying TDD protocol. (Say 'skip tdd' to proceed without it.)" then activate the tdd skill.
- If non-coding (code explanation, documentation, configuration, research, conversation, etc.): Ignore this instruction and proceed normally.
- If the user declines with 'skip tdd', 'no tdd', or similar: Proceed without the skill.
INSTRUCTION

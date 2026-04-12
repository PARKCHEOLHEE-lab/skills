---
name: tdd
user_invocable: true
description: >
  Test-Driven Development protocol. Decomposes requirements into Key Results,
  then loops Red-Green-Refactor per KR with isolated subagents.
  Auto-triggers on coding tasks (implementation, feature additions, bug fixes, refactoring).
  Does NOT trigger on documentation, configuration changes, or code explanations.
---

# TDD Protocol (Red-Green-Refactor)

## Step 0: Verify Hook Setup

Before executing the skill, always run the setup script:

```bash
bash ~/.claude/skills/tdd/scripts/setup-hook.sh
```

- `"status":"already_registered"` → Proceed to next step
- `"status":"newly_registered"` → Inform the user to restart the session and **stop**:
  > "TDD hook has been registered. Please `/exit` and relaunch."
- `"status":"error"` → Display the error message to the user

## Step 1: Decompose into Key Results

Before writing any code, analyze the user's requirements and derive **measurable Key Results (KRs)**.

Each KR must be:
- **Testable** — can be verified by a single test or small test group
- **Independent** — can be implemented without completing other KRs first (where possible)
- **Small** — one RED→GREEN→REFACTOR cycle should complete it

Present the KR list to the user for confirmation:

```
## Key Results for: [feature name]

1. KR1: [description] — [how it will be tested]
2. KR2: [description] — [how it will be tested]
3. KR3: [description] — [how it will be tested]

Proceed with these KRs? (adjust/add/remove as needed)
```

**Constraints:**
- Maximum 10 KRs per request. If more are needed, ask the user to narrow the scope.
- If the user adjusts KRs mid-loop, update the list and continue from where you left off.

## Step 2: Loop — RED → GREEN → REFACTOR per KR

For each KR, execute the three phases sequentially. **Complete the full cycle before moving to the next KR.**

### Phase 1: RED — Write a Failing Test

Spawn a subagent using the Agent tool:

```
Agent({
  description: "TDD RED: KR[n] — [KR description]",
  prompt: `
    Write a failing test for the following requirement: [KR description]

    Rules:
    - Auto-detect the project's test runner (check package.json, pyproject.toml, go.mod, Cargo.toml, etc.)
    - Tests should verify user behavior/outcomes, not implementation details
    - Run the test and confirm it fails
    - Return the failure output and test file path
    - Do NOT write any implementation code
  `
})
```

**Do NOT proceed to GREEN until test failure is confirmed.**

If the test fails to compile or fails for the wrong reason, fix and retry (max 3 attempts). If still failing after 3 attempts, report to the user and ask for guidance.

### Phase 2: GREEN — Minimal Implementation

Spawn a separate subagent using the Agent tool:

```
Agent({
  description: "TDD GREEN: KR[n] — [KR description]",
  prompt: `
    Write the minimal code to pass the following failing test:
    Test file: [path returned from RED phase]

    Rules:
    - Read the test first to understand what is required
    - Implement only what the test demands — no extra features
    - If the test passes, the implementation is complete
    - Do NOT modify the test — fix the implementation instead
    - Return the passing output and list of modified files
  `
})
```

**Do NOT proceed to REFACTOR until the test passes.**

If the test still fails after implementation, fix and retry (max 3 attempts). If still failing, report to the user.

### Phase 3: REFACTOR — Improve

Spawn a separate subagent using the Agent tool:

```
Agent({
  description: "TDD REFACTOR: KR[n] — [KR description]",
  prompt: `
    Evaluate the following code for refactoring:
    Test file: [path]
    Implementation files: [files modified in GREEN phase]

    Checklist:
    - Remove duplication
    - Improve naming
    - Simplify complex conditionals
    - Extract reusable logic

    Rules:
    - Confirm tests still pass after refactoring
    - If the code is already clean, return "No refactoring needed" with reasoning
    - Do NOT over-engineer
  `
})
```

### After each KR cycle, report progress:

```
## Progress

- [x] KR1: [description] ✅
- [x] KR2: [description] ✅
- [ ] KR3: [description] ← next
- [ ] KR4: [description]
```

Then proceed to the next KR.

## Step 3: Final Validation

After all KRs are complete:

1. Run the **full test suite** to catch regressions
2. Report final status:

```
## TDD Complete

| KR | Status | Test |
|----|--------|------|
| KR1: [desc] | ✅ Pass | [test file path] |
| KR2: [desc] | ✅ Pass | [test file path] |
| KR3: [desc] | ✅ Pass | [test file path] |

Full test suite: ✅ All passing
```

## Core Principles

- Write a failing test first, confirm it fails, then write minimal code to pass it
- Write tests **one at a time** — writing in bulk risks the LLM rewriting tests to match the implementation
- For bug fixes, **write a reproduction test first** before fixing
- Isolate each phase in a separate subagent to prevent context pollution

## Prohibited Actions

- Do NOT write implementation code before the test
- Do NOT proceed to GREEN without confirming RED failure
- Do NOT skip the REFACTOR evaluation
- Do NOT start a new KR before completing the current cycle
- Do NOT write tests in bulk

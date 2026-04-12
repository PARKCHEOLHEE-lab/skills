---
name: tdd
user_invocable: true
description: >
  Test-Driven Development protocol. Executes the Red-Green-Refactor cycle with isolated subagents.
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

## Core Principles

- Write a failing test first, confirm it fails, then write minimal code to pass it
- Write tests **one at a time** — writing in bulk risks the LLM rewriting tests to match the implementation
- For bug fixes, **write a reproduction test first** before fixing
- Isolate each phase in a separate subagent to prevent context pollution

## Workflow

Repeat the cycle below per feature. **Complete the full cycle before starting the next feature.**

### Phase 1: RED — Write a Failing Test

Spawn a subagent using the Agent tool:

```
Agent({
  description: "TDD RED: [feature description]",
  prompt: `
    Write a failing test for the following feature: [feature requirements]

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

### Phase 2: GREEN — Minimal Implementation

Spawn a separate subagent using the Agent tool:

```
Agent({
  description: "TDD GREEN: [feature description]",
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

### Phase 3: REFACTOR — Improve

Spawn a separate subagent using the Agent tool:

```
Agent({
  description: "TDD REFACTOR: [feature description]",
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

## Multiple Features

```
Feature 1: RED -> GREEN -> REFACTOR (done)
Feature 2: RED -> GREEN -> REFACTOR (done)
Feature 3: RED -> GREEN -> REFACTOR (done)
```

## Prohibited Actions

- Do NOT write implementation code before the test
- Do NOT proceed to GREEN without confirming RED failure
- Do NOT skip the REFACTOR evaluation
- Do NOT start a new feature before completing the current cycle
- Do NOT write tests in bulk

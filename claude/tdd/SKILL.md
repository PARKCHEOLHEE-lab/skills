---
name: tdd
user_invocable: true
description: >
  Test-Driven Development protocol. Decomposes requirements into Key Results,
  then loops Red-Green-Refactor per KR with isolated subagents.
  Failed KRs are recursively decomposed into smaller sub-KRs (max depth 3).
  Auto-triggers on coding tasks (implementation, feature additions, bug fixes, refactoring).
  Does NOT trigger on documentation, configuration changes, or code explanations.
---

# TDD Protocol (Red-Green-Refactor)

## CRITICAL: Skill activation is the source of truth

**If you are doing any TDD-shaped work — KR decomposition, RED/GREEN/REFACTOR cycles, writing failing tests, etc. — you MUST have invoked this skill via `Skill(tdd)` first.**

The skill is what creates `/tmp/tdd-kr-state.json`. Without that file:
- The guard hook (`tdd-guard-kr.sh`) cannot enforce loop completion
- The statusline tree (`tdd-statusline.sh`) will not appear
- The user has no live visibility into KR progress

If you find yourself in the middle of coding work and realize you started doing TDD-style work without invoking this skill: **STOP, invoke `Skill(tdd)` now**, then construct the state file from your in-progress KR list before continuing. Do not silently work around the skill — that defeats every guarantee the protocol is designed to provide.

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
- **Independent** — can be implemented without completing other KRs first (where possible; use mocks for dependencies)
- **Small** — one RED→GREEN→REFACTOR cycle should complete it

Present the KR list to the user and confirm using the **AskUserQuestion tool** (interactive terminal UI, NOT plain text):

```
## Key Results for: [feature name]

1. KR1: [description] — [how it will be tested]
2. KR2: [description] — [how it will be tested]
3. KR3: [description] — [how it will be tested]
```

Then call `AskUserQuestion` with the KR list as the question body and these four options:
- **Proceed (Recommended)** — Start the TDD loop with these KRs as-is
- **Adjust** — Modify descriptions or test criteria for existing KRs
- **Add KR** — Add more KRs
- **Remove KR** — Remove one or more KRs

Only after the user selects "Proceed" (or resolves Adjust/Add/Remove), create the state file and start the loop.

**Constraints:**
- Maximum 10 KRs per request. If more are needed, ask the user to narrow the scope.
- If the user adjusts KRs mid-loop, update the state file and continue from where you left off.

**After user confirms KRs, initialize BOTH tracking systems:**

1. **Create the state file** (read by both the guard hook AND the statusline renderer):

```bash
cat > /tmp/tdd-kr-state.json <<'STATEEOF'
{
  "krs": [
    {"id": "1", "desc": "KR1 description", "depth": 0, "status": "pending"},
    {"id": "2", "desc": "KR2 description", "depth": 0, "status": "pending"},
    {"id": "3", "desc": "KR3 description", "depth": 0, "status": "pending"}
  ]
}
STATEEOF
```

**State file schema:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | KR identifier (use dotted notation for sub-KRs: `"4.2"`) |
| `desc` | string | yes | Short description shown in statusline |
| `depth` | number | yes | Recursion depth (0 for top-level KRs, 1+ for sub-KRs) |
| `status` | `"pending"` \| `"in_progress"` \| `"completed"` | yes | Current state |
| `done` | boolean | no | Legacy — set `true` when `status` is `"completed"` (guard hook compatibility) |
| `decomposing` | boolean | no | `true` when this KR is being recursively decomposed |
| `retry` | `{ phase, count, max }` | no | Present while retrying: `{"phase": "RED", "count": 2, "max": 3}` |

**State update patterns** (use jq to mutate the file):

```bash
# Mark KR as in_progress
jq '(.krs[] | select(.id == "4")).status = "in_progress"' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json

# Mark KR as completed (set both status AND done for guard hook compat)
jq '(.krs[] | select(.id == "4")) |= (.status = "completed" | .done = true)' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json

# Mark KR as retrying
jq '(.krs[] | select(.id == "4")).retry = {"phase": "RED", "count": 2, "max": 3}' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json

# Clear retry (after success)
jq '(.krs[] | select(.id == "4")) |= del(.retry)' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json

# Mark KR as decomposing
jq '(.krs[] | select(.id == "4")).decomposing = true' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json

# Append sub-KRs (depth 1)
jq '.krs += [{"id": "4.1", "desc": "sub description", "depth": 1, "status": "pending"}]' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json
```

Keep the state file in sync with every phase transition — the statusline tree reflects this file in real time.

2. **Create tasks via `TaskCreate` tool** (for UI progress visualization):

Create one task per KR. Use the task description `"TDD KR[n]: [KR description]"` and set initial status to `pending`.

The state file is checked by the guard hook — writing the final "TDD Complete" report is **blocked** until all KRs are marked `done`. The task list provides visual progress in the user's UI.

### Task description state conventions (A+B pattern)

The task description is updated dynamically to reflect the current state of each KR:

| State | Task description format | Task status |
|-------|--------------------------|-------------|
| Not started | `TDD KR[n]: [desc]` | `pending` |
| In progress | `TDD KR[n]: [desc]` | `in_progress` |
| Retrying RED | `TDD KR[n] [❌ RED retry M/3]: [desc]` | `in_progress` |
| Retrying GREEN | `TDD KR[n] [❌ GREEN retry M/3]: [desc]` | `in_progress` |
| Retrying REFACTOR | `TDD KR[n] [❌ REFACTOR retry M/3]: [desc]` | `in_progress` |
| Being decomposed | `TDD KR[n] [decomposing]: [desc]` | `in_progress` |
| Completed | `TDD KR[n]: [desc]` | `completed` |

When recursion kicks in, **create child tasks** for each sub-KR via `TaskCreate`, using dotted notation in the ID:
- Parent: `TDD KR3 [decomposing]: JWT token issuance` (status: in_progress)
- Child: `TDD KR3.1: Token payload generation` (status: pending)
- Child: `TDD KR3.2: Signing and expiry` (status: pending)
- Child: `TDD KR3.3: Token verification` (status: pending)

This creates a visual hierarchy in the task UI via the ID naming (since the Task system does not natively support parent-child nesting).

## Step 2: Loop — RED → GREEN → REFACTOR per KR

For each KR, execute the three phases sequentially. **Complete the full cycle before moving to the next KR.**

### Phase 1: RED — Write a Failing Test

Spawn a subagent using the Agent tool:

```
Agent({
  subagent_type: "general-purpose",
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

If the test fails to compile or fails for the wrong reason, fix and retry (max 3 attempts). **Before each retry, update the task description via `TaskUpdate` to `"TDD KR[n] [❌ RED retry M/3]: [desc]"`** so the UI reflects the retry state.

### Phase 2: GREEN — Minimal Implementation

Spawn a separate subagent using the Agent tool:

```
Agent({
  subagent_type: "general-purpose",
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

If the test still fails after implementation, fix and retry (max 3 attempts). **Before each retry, update the task description to `"TDD KR[n] [❌ GREEN retry M/3]: [desc]"`**.

### Phase 3: REFACTOR — Improve

Spawn a separate subagent using the Agent tool:

```
Agent({
  subagent_type: "general-purpose",
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

### Before each KR cycle:

- **Mark the corresponding task as `in_progress`** using `TaskUpdate`.

### After each KR cycle:

1. **Update the state file** (mark KR completed, using the schema patterns above):

```bash
jq '(.krs[] | select(.id == "N")) |= (.status = "completed" | .done = true)' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json
```

(Replace `"N"` with the KR id as a string.)

2. **Mark the corresponding task as `completed`** using `TaskUpdate`.

3. **Proceed to the next KR immediately.** Do NOT stop or wait for user input between KRs.

## Recursive Decomposition on Failure

When a KR fails after 3 retry attempts in any phase (RED, GREEN, or REFACTOR), do NOT report to the user immediately. Instead, **recursively apply the TDD protocol** to the failed KR:

1. **Analyze the failure** — identify why the KR is too complex or what specific part is failing
2. **Update the parent task description** to `"TDD KR[n] [decomposing]: [desc]"` via `TaskUpdate`
3. **Decompose the failed KR into smaller sub-KRs** (max 5 sub-KRs per decomposition)
4. **Create child tasks** via `TaskCreate` for each sub-KR using dotted notation IDs (`TDD KR[n].1`, `TDD KR[n].2`, ...)
5. **Apply RED→GREEN→REFACTOR to each sub-KR**
6. After all sub-KRs pass, **re-run the original KR's test** to confirm it now passes, then mark the parent task as `completed`
7. Update the state file (mark parent as decomposing, append sub-KRs — see schema patterns above):

```bash
# Mark parent KR as decomposing
jq '(.krs[] | select(.id == "3")).decomposing = true' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json

# Append sub-KRs at depth 1
jq '.krs += [{"id": "3.1", "desc": "sub-KR description", "depth": 1, "status": "pending"}]' /tmp/tdd-kr-state.json > /tmp/tdd-kr-state-tmp.json && mv /tmp/tdd-kr-state-tmp.json /tmp/tdd-kr-state.json
```

### Recursion limits

| Limit | Value | On exceed |
|-------|-------|-----------|
| Max recursion depth | 3 levels | Report to user with failure analysis |
| Max sub-KRs per decomposition | 5 | If more needed, the KR scope is too large — ask user to narrow |

### Example

```
KR3: JWT token issuance — RED fails (3 retries exhausted)
  │
  ▼ Decompose KR3 → sub-KRs (depth 1)
  │
  ├─ KR3.1: Token payload generation    RED→GREEN→REFACTOR ✅
  ├─ KR3.2: Signing and expiry          RED→GREEN→REFACTOR ✅
  └─ KR3.3: Token verification          RED→GREEN→REFACTOR ❌ (3 retries)
      │
      ▼ Decompose KR3.3 → sub-KRs (depth 2)
      │
      ├─ KR3.3.1: Expiry validation     RED→GREEN→REFACTOR ✅
      └─ KR3.3.2: Signature validation  RED→GREEN→REFACTOR ✅
      │
      ▼ Re-run KR3.3 original test → ✅
  │
  ▼ Re-run KR3 original test → ✅
```

If depth 3 is reached and a sub-KR still fails, **then** report to the user:

```
## KR Failure Report

KR3.3.2: Signature validation — failed after recursive decomposition (depth 3)

### Attempts
- Depth 0: KR3 (JWT token issuance) — RED failed
- Depth 1: KR3.3 (Token verification) — GREEN failed
- Depth 2: KR3.3.2 (Signature validation) — RED failed

### Failure analysis
[What specifically failed and why]

### Recommendation
[Suggested next steps for the user]
```

## Step 3: Final Validation

After all KRs are complete:

1. **Remove the state file:**
```bash
rm -f /tmp/tdd-kr-state.json
```

2. Run the **full test suite** to catch regressions
3. Report final status:

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
- When a KR is too complex, decompose it recursively rather than brute-force retrying

## Prohibited Actions

- Do NOT write implementation code before the test
- Do NOT proceed to GREEN without confirming RED failure
- Do NOT skip the REFACTOR evaluation
- Do NOT start a new KR before completing the current cycle
- Do NOT write tests in bulk
- Do NOT exceed recursion depth 3 — report to user instead

---
name: review-loop-general
description: |
  Review a PR in iterative loops: review → comment → fix → write tests → repeat.
  Works with any repository. Use when asked to "review PR", "review loop",
  "review and fix", or "iterate on PR". Runs 3 rounds by default.
disable-model-invocation: false
argument-hint: "[PR number] [rounds=3]"
allowed-tools: Bash(*), Read(*), Edit(*), Write(*), Grep(*), Glob(*)
---

# Review Loop Skill (General)

Iteratively review a PR: review → leave comments → fix issues → write tests → repeat.

## Process

For each round (default 3):

### 0. Understand PR intent
Before reviewing, read the PR description (`gh pr view <PR_NUMBER>`).
Identify the **user's stated intent** — what behavior should the PR produce?
All review comments and fixes must preserve this intent. If a review fix
would change the intended behavior, it is wrong — even if it makes tests pass.

### 1. Review
```bash
gh pr diff <PR_NUMBER>
```
Read the diff carefully. Look for:
- Logic errors or bugs
- Missing edge cases
- Redundant or dead code
- Tests that only test language features, not behavior
- **Missing tests for new/changed logic**
- **Tests that contradict the PR's stated intent** (fix the test, not the code)
- Security issues
- Performance concerns
- Naming/clarity issues

### 2. Leave comments
```bash
gh pr review <PR_NUMBER> --comment --body "<review comments>"
```
Structure comments as:
- **Round N** heading
- Numbered issues with severity (blocking vs non-blocking)
- Specific file/line references

### 3. Fix + Tests
Fix all blocking issues found in the review. Then for each fix:
- If the fix changes logic: add or update a test that covers the changed behavior
- If the fix removes dead code: remove any tests that only tested that code
- If no existing test covers the area: add a minimal test proving the fix works
- **If a test contradicts the PR intent: update the test, not the code**
- Before committing, ask: "does this fix preserve the user's original intent?"

```bash
# Stage and commit fixes + tests
git add <files>
git commit -m "Fix review round N: <summary>"
git push
```

### 4. Verify
```bash
npm test  # or npx vitest run, npx jest, etc. — use whatever the project uses
```
All tests must pass. If new tests were added, confirm they fail without the fix.

## After all rounds

If the final review finds no blocking issues:
```bash
gh pr review <PR_NUMBER> --comment --body "## Review — Round N (Final)\n\nLGTM. No blocking issues."
```

Then ask the user if they want to merge:
- Squash merge: `gh pr merge <PR_NUMBER> --squash`
- Regular merge: `gh pr merge <PR_NUMBER> --merge`

## Arguments

- `$ARGUMENTS` format: `[PR number] [rounds]`
- If no PR number given, find the latest open PR
- Default rounds: 3

## Notes

- Always run tests after fixing
- Never approve your own PR (GitHub blocks it) — use comment reviews
- Each round's comment should reference what was fixed from the previous round
- **Intent over correctness**: a "correct" refactor that changes the user's
  intended behavior is a regression. When in doubt, keep the original approach
  and document why in the review comment.

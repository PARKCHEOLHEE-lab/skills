---
name: outsource-research
description: Read documents, summarize, extract insights, find related materials (papers, code, articles, videos)
user_invocable: true
---

Read and analyze documents, extract insights, and research related materials.

## Usage

```
/outsource-research <source> [--depth quick|standard|deep|full:N%]
```

- `<source>` — URL, local file path, arXiv ID, GitHub repo URL, or multiple sources separated by spaces
- `--depth` — analysis depth (default: `standard`)
  - `quick` — TL;DR + structured summary only
  - `standard` — summary + insights + key concepts + related materials
  - `deep` — full analysis including critical review, research chain, cross-references, and follow-up questions
  - `full:N%` — deep analysis + iterative research expansion until N% of session context is consumed (e.g., `full:90%`, `full:50%`). **N% is required** — if `--depth=full` is given without a percentage, you MUST ask the user to specify a target percentage before proceeding. Example prompt: "You selected full mode. What percentage of context should be used? (e.g., 70%, 90%)"

## Process

### Step 1: Ingest sources

Read all provided sources:

- **URL** — fetch with `WebFetch`
- **PDF** — read with `Read` tool (use `pages` parameter for large PDFs)
- **Local file** — read with `Read` tool
- **arXiv ID** (e.g., `2301.07041`) — fetch `https://arxiv.org/abs/{id}` and the PDF
- **GitHub repo** — fetch README, scan key source files for understanding
- **Multiple sources** — ingest all, then cross-reference in analysis

If a source fails to load, report the error and continue with remaining sources.

### Step 2: TL;DR

Write a 3-line summary at the top capturing:
1. What this is about
2. The core contribution or argument
3. Why it matters

This step runs for ALL depth levels.

### Step 3: Structured summary

Organize the document content into logical sections:

- **Background/Context** — what problem or domain this addresses
- **Core Content** — main ideas, methods, arguments, or proposals
- **Results/Conclusions** — outcomes, findings, or takeaways

This step runs for ALL depth levels.

### Step 4: Key concepts and terminology (standard, deep)

Extract important concepts and terms from the document:

- List each concept with a clear, concise definition
- Note relationships between concepts
- If the source uses domain-specific jargon, explain it in plain language

### Step 5: Insights (standard, deep)

Go beyond summarization — identify:

- Non-obvious implications
- Connections to broader trends or other fields
- What the author assumes but doesn't state explicitly
- What's genuinely novel vs. incremental

### Step 6: Critical analysis (deep only)

Evaluate the source critically:

- Logical gaps or weak arguments
- Unstated assumptions and their validity
- Limitations the author acknowledges vs. ones they don't
- Alternative interpretations of the same evidence

### Step 7: Related materials research (standard, deep)

Search for related materials using `WebSearch`. Classify results by type:

| Type | Examples |
|------|----------|
| Papers | arXiv, conference proceedings, journals |
| Code | GitHub repos, libraries, implementations |
| Articles | Blog posts, tutorials, explainers |
| Videos | Talks, lectures, demos |

For each found material:
- Title + link
- Type tag
- One-line explanation of why it's relevant

Target: 5-10 related materials for `standard`, 10-20 for `deep`, unlimited for `full`.

### Step 8: Research chain (deep only)

Map the research lineage:

- **Predecessors** — key works this source builds on or references
- **Contemporaries** — parallel work in the same space
- **Successors** — work that cites or extends this source (search for citations)

### Step 9: Cross-reference analysis (deep only, multiple sources)

When multiple sources are provided:

- Identify overlapping and conflicting claims
- Note complementary perspectives
- Synthesize a unified understanding across all sources

### Step 10: Follow-up questions (standard, deep)

Suggest 3-5 follow-up questions for deeper exploration. These should be:

- Specific enough to be actionable
- Pointing in genuinely different directions (not variations of the same question)

### Step 11: Iterative research expansion (full only)

After completing all deep-level steps (Steps 1–10), enter an iterative research loop that continues until the user-specified context target (N%) is reached.

**CRITICAL — First-time setup (full mode only — skip for quick/standard/deep):**
Before entering the loop, check if the PreToolUse guard hook is registered in the user's settings. Run:
```
bash ~/.claude/skills/outsource-research/scripts/setup-hook.sh
```
This script will:
- Check if `~/.claude/settings.json` already has the guard hook registered
- If not, register it automatically
- Report whether the hook is active in the current session or will take effect on next session restart

If the script reports `"status":"newly_registered"`, you MUST:
1. Inform the user that the guard hook has been registered
2. Ask the user to **exit the current session and restart** so the hook takes effect
3. **Do NOT proceed with the full-mode loop** until the user restarts and re-invokes the skill

Display this message:
> "Guard hook has been newly registered in settings.json. A session restart is required for the hook to take effect.
> Please exit with `/exit`, then relaunch and re-run `/outsource-research`.
> (Proceeding without the hook may cause premature termination before the context target is reached.)"

Then STOP. Do not continue with the research. Wait for the user to restart.

If the script reports `"status":"already_registered"`, the hook is active — proceed normally.

This setup is idempotent — running it multiple times is safe.

**CRITICAL — Measuring context usage:**
You MUST use the `check-context.sh` script to measure actual context usage. Do NOT rely on your own estimation — it is consistently inaccurate and leads to premature termination. Run the following Bash command to get the actual percentage:
```
bash ~/.claude/skills/outsource-research/scripts/check-context.sh
```
The script outputs JSON like `{"usage_pct": 16.7, "total_tokens": 166726, ...}`. Use the `usage_pct` field as the authoritative context usage number.

**CRITICAL — State tracking:**
At the START of the full-mode loop, create a state file by running:
```
echo '{"active":true,"target_pct":N}' > /tmp/outsource-research-state.json
```
(Replace N with the user's target percentage as an integer.)
At the END of the loop (ONLY after `check-context.sh` confirms target is reached), remove it:
```
rm -f /tmp/outsource-research-state.json
```

**CRITICAL — No early termination:**
The purpose of full mode is to ensure a minimum depth of research context that yields meaningful insights. The iterative loop MUST NOT terminate before reaching the target N%. Specifically:
- Do NOT stop the loop just because the current report "feels complete" or "covers enough ground."
- Do NOT stop because you ran out of obvious follow-up directions — generate new ones by broadening the search scope, exploring tangential domains, examining contradicting viewpoints, or diving deeper into technical details of already-found materials.
- Do NOT stop because a single iteration produced low-yield results — try a different expansion vector and continue.
- The ONLY valid reason to stop is when `check-context.sh` reports `usage_pct >= N`.
- After each iteration, run `check-context.sh` and explicitly state the ACTUAL context usage percentage (e.g., "Current context usage: 23.4% / Target: 50% (measured via check-context.sh)") so progress toward the target is visible.
- If you believe you have reached the target but `check-context.sh` says otherwise, TRUST THE SCRIPT and continue.

**Loop procedure:**

1. **Assess context usage** — After each iteration, run `bash ~/.claude/skills/outsource-research/scripts/check-context.sh` and read the `usage_pct` from the JSON output. Stop ONLY when `usage_pct >= N` (the user-specified target).

2. **Identify expansion vectors** — From the follow-up questions, related materials, and research chain, pick the most promising direction that hasn't been explored yet. Prioritize:
   - Primary sources referenced in the initial documents but not yet read
   - High-relevance papers/articles found via WebSearch that weren't fully ingested
   - Tangential domains that could offer transferable insights
   - Contradicting viewpoints or competing approaches
   - Deep technical details of key technologies mentioned in the sources (e.g., model architectures, training methodologies, deployment strategies)
   - Policy, legal, and regulatory dimensions not yet explored
   - International case studies and benchmarks for comparison

   If all obvious vectors are exhausted, generate new ones by:
   - Combining two previously separate topics to find intersection insights
   - Searching for the latest (current year) developments on key topics
   - Looking for failure cases or critical perspectives on the main topic
   - Exploring upstream/downstream implications (e.g., supply chain, end-user impact)

3. **Ingest and analyze** — For each expansion:
   - Fetch and read the new source (WebFetch for URLs, Read for local files/PDFs)
   - Write a mini-analysis (3-5 paragraphs) covering: what it adds, how it connects to the original sources, and any new insights or contradictions
   - Add it to the Related Materials section with a `[Full-mode discovery]` tag

4. **Update the report incrementally** — After each expansion:
   - Append new findings to the appropriate sections (Related Materials, Research Chain, Insights)
   - Update the Cross-References section if new overlaps or conflicts emerge
   - Add new follow-up questions spawned by the discovery (replace already-explored ones)

5. **Repeat** from step 2 until `check-context.sh` reports `usage_pct >= N`. Do NOT exit the loop early. Do NOT estimate — MEASURE.

**Context budget allocation guidance:**
- Spend roughly 40% of remaining context on ingesting new sources
- Spend roughly 30% on analyzing connections and updating the report
- Reserve roughly 30% for the final synthesis and output

**Final synthesis** — When the loop ends (confirmed by `check-context.sh` that `usage_pct >= N`), first remove the state file (`rm -f /tmp/outsource-research-state.json`), then add a `## Full-Mode Research Log` section to the output that lists:
- Total iterations completed
- Target context percentage and **actual** final context usage (from `check-context.sh`)
- Sources ingested per iteration (title + type)
- A brief narrative of how the research evolved across iterations (what threads were followed, what was discovered, what dead ends were hit)

## Output format

Write the output as a structured markdown file. Use the following template:

```markdown
# Research: {document title or topic}

**Source:** {source URL or path}
**Depth:** {quick|standard|deep}
**Date:** {YYYY-MM-DD}

## TL;DR
{3-line summary}

## Summary
### Background
### Core Content
### Results/Conclusions

## Key Concepts                    <!-- standard, deep -->

## Insights                        <!-- standard, deep -->

## Critical Analysis               <!-- deep -->

## Related Materials               <!-- standard, deep -->
### Papers
### Code
### Articles
### Videos

## Research Chain                   <!-- deep -->
### Predecessors
### Contemporaries
### Successors

## Cross-References                <!-- deep, multiple sources -->

## Follow-up Questions             <!-- standard, deep, full -->

## Full-Mode Research Log          <!-- full -->
### Iterations
### Research Evolution Narrative
```

Omit sections that don't apply to the chosen depth level.

## Memory integration

**IMPORTANT:** Do NOT ask about saving to memory during iterative research loops or mid-analysis. Memory save should only happen **once**, at the very end after all output is complete.

After completing ALL research and outputting the final report:

1. Check if prior `/outsource-research` results exist in memory
2. If related prior research is found, add a **Connections to prior research** section noting overlaps or progressions
3. Use the `AskUserQuestion` tool (NOT plain text) to ask whether to save key findings to memory. This presents an interactive UI where the user selects with arrow keys:
   - Question: "Save key findings to memory for future sessions?"
   - Option 1: "Yes — save key findings" with description "Saves a concise memory file with research topic, date, and top 3-5 non-obvious insights"
   - Option 2: "No — skip" with description "Do not save anything to memory"
4. If the user selects "Yes", save a single memory file summarizing the research topic and key non-obvious findings only. Do NOT save raw data, URLs, or information derivable from the source documents.

## Constraints

- Do NOT fabricate citations — only include materials you actually found via search
- If a search returns no useful results for a category, say so rather than forcing low-quality matches
- Prefer primary sources (original papers, official repos) over secondary summaries
- When the source language differs from the user's language, write the output in the user's language
- Do NOT commit any output files — let the user decide where to save

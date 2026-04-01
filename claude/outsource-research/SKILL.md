---
name: outsource-research
description: Read documents, summarize, extract insights, find related materials (papers, code, articles, videos)
user_invocable: true
---

Read and analyze documents, extract insights, and research related materials.

## Usage

```
/outsource-research <source> [--depth quick|standard|deep]
```

- `<source>` — URL, local file path, arXiv ID, GitHub repo URL, or multiple sources separated by spaces
- `--depth` — analysis depth (default: `standard`)
  - `quick` — TL;DR + structured summary only
  - `standard` — summary + insights + key concepts + related materials
  - `deep` — full analysis including critical review, research chain, cross-references, and follow-up questions
  - `full` — deep analysis + iterative research expansion until ~90% of session context is consumed

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

After completing all deep-level steps (Steps 1–10), enter an iterative research loop that continues until approximately 90% of the current session's context window is consumed.

**Loop procedure:**

1. **Assess context usage** — After each iteration, estimate the current context consumption relative to the model's context limit. Stop when reaching ~90%.

2. **Identify expansion vectors** — From the follow-up questions, related materials, and research chain, pick the most promising direction that hasn't been explored yet. Prioritize:
   - Primary sources referenced in the initial documents but not yet read
   - High-relevance papers/articles found via WebSearch that weren't fully ingested
   - Tangential domains that could offer transferable insights
   - Contradicting viewpoints or competing approaches

3. **Ingest and analyze** — For each expansion:
   - Fetch and read the new source (WebFetch for URLs, Read for local files/PDFs)
   - Write a mini-analysis (3-5 paragraphs) covering: what it adds, how it connects to the original sources, and any new insights or contradictions
   - Add it to the Related Materials section with a `[Full-mode discovery]` tag

4. **Update the report incrementally** — After each expansion:
   - Append new findings to the appropriate sections (Related Materials, Research Chain, Insights)
   - Update the Cross-References section if new overlaps or conflicts emerge
   - Add new follow-up questions spawned by the discovery (replace already-explored ones)

5. **Repeat** from step 2 until the ~90% context threshold is reached.

**Context budget allocation guidance:**
- Spend roughly 40% of remaining context on ingesting new sources
- Spend roughly 30% on analyzing connections and updating the report
- Reserve roughly 30% for the final synthesis and output

**Final synthesis** — When the loop ends, add a `## Full-Mode Research Log` section to the output that lists:
- Total iterations completed
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

After completing research:

1. Check if prior `/outsource-research` results exist in memory
2. If related prior research is found, add a **Connections to prior research** section noting overlaps or progressions
3. Ask the user if they want to save key findings to memory for future reference

## Constraints

- Do NOT fabricate citations — only include materials you actually found via search
- If a search returns no useful results for a category, say so rather than forcing low-quality matches
- Prefer primary sources (original papers, official repos) over secondary summaries
- When the source language differs from the user's language, write the output in the user's language
- Do NOT commit any output files — let the user decide where to save

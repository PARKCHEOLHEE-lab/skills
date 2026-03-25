---
name: capture-page
description: |
  Take a screenshot of any Tangle page. Starts a dev server, captures with
  Puppeteer, and shuts down. Use when asked to "take a screenshot",
  "capture the page", "show me the current state", or to visually verify UI.
disable-model-invocation: false
argument-hint: "[url-path] [output-file]"
allowed-tools: Bash(*), Read(*)
---

# Screenshot Skill

Capture a screenshot of any Tangle page.

## Steps

1. Run the screenshot script:
```bash
node .claude/skills/capture-page/scripts/screenshot.mjs [url-path] [output-file]
```

2. Read the saved screenshot to view it:
```bash
# Default saves to .claude/screenshot/screenshot.png
```

## Examples

```bash
# Home page
node .claude/skills/capture-page/scripts/screenshot.mjs / .claude/screenshot/home.png

# Specific session
node .claude/skills/capture-page/scripts/screenshot.mjs /session/2026-03-21_foo .claude/screenshot/session.png

# Latest session
node .claude/skills/capture-page/scripts/screenshot.mjs /session/$(ls -t data/sessions/ | head -1) .claude/screenshot/latest.png
```

## Arguments

- `$ARGUMENTS` is passed as: `[url-path] [output-file]`
- If no arguments, screenshots the home page

## Notes

- Uses port 3111 to avoid conflicts with running dev server
- Uses `--turbopack` to match main dev config
- Waits 2s after network idle for React rendering
- Screenshots saved to `.claude/screenshot/`

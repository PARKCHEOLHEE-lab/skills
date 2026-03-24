---
name: responsive-test
description: |
  Take responsive screenshots of the AARO landing page at various viewport sizes
  using Playwright. Use when asked to "check responsiveness", "test mobile layout",
  "responsive test", or to verify how the page looks across different devices.
disable-model-invocation: false
argument-hint: "[--all] [--device NAME] [--viewport WxH] [--action ACTION] [--url PATH] [--output FILE]"
allowed-tools: Bash(*), Read(*)
---

# Responsive Test Skill

Capture screenshots of the AARO landing page at different viewport sizes to verify responsive layout.

## Prerequisites

This script requires Playwright. If not installed:
```bash
npm install -D @playwright/test
npx playwright install chromium
```

A dev server must be running before using this skill:
```bash
npm run dev
```

## Steps

1. Run the responsive test script with the desired viewport or device preset:
```bash
node .claude/skills/responsive-test/scripts/responsive-test.mjs [options]
```

2. Read the saved screenshot to view it and check for layout issues.

3. For a thorough responsive test, capture at multiple breakpoints and review each one.

## Available Devices

| Device           | Viewport    |
|------------------|-------------|
| `iphone-se`      | 375x667     |
| `iphone-14`      | 390x844     |
| `ipad`           | 768x1024    |
| `ipad-landscape`  | 1024x768    |
| `desktop`        | 1280x800    |
| `desktop-hd`     | 1920x1080   |
| `desktop-4k`     | 3840x2160   |

## Available Actions

- `scroll-bottom` — Scroll to the bottom of the page
- `scroll-to-footer` — Scroll until `#footer` is visible
- `click-SELECTOR` — Click on a CSS selector (e.g. `click-#services`)
- `hover-SELECTOR` — Hover over a CSS selector (e.g. `hover-.grid-cell`)
- Chain multiple actions with comma: `--action scroll-bottom,hover-.card`

## Examples

```bash
# Desktop HD (default)
node .claude/skills/responsive-test/scripts/responsive-test.mjs --device desktop-hd --output .claude/screenshot/desktop-hd.png

# iPhone 14
node .claude/skills/responsive-test/scripts/responsive-test.mjs --device iphone-14 --output .claude/screenshot/iphone-14.png

# iPad landscape
node .claude/skills/responsive-test/scripts/responsive-test.mjs --device ipad-landscape --output .claude/screenshot/ipad-landscape.png

# Custom viewport
node .claude/skills/responsive-test/scripts/responsive-test.mjs --viewport 1440x900 --output .claude/screenshot/custom.png

# Full page screenshot on mobile
node .claude/skills/responsive-test/scripts/responsive-test.mjs --device iphone-14 --full-page --output .claude/screenshot/mobile-full.png

# Scroll to bottom then screenshot
node .claude/skills/responsive-test/scripts/responsive-test.mjs --device desktop-hd --action scroll-bottom --output .claude/screenshot/bottom.png

# Hover over a card then screenshot
node .claude/skills/responsive-test/scripts/responsive-test.mjs --device desktop --action hover-.grid-cell:nth-child(2) --output .claude/screenshot/hover.png

# Test a specific route
node .claude/skills/responsive-test/scripts/responsive-test.mjs --device iphone-14 --url /about --output .claude/screenshot/about-mobile.png

# Force a specific port
node .claude/skills/responsive-test/scripts/responsive-test.mjs --device desktop-hd --port 3001 --output .claude/screenshot/port3001.png
```

## Recommended Responsive Test Workflow

Capture all devices at once with `--all`:

```bash
node .claude/skills/responsive-test/scripts/responsive-test.mjs --all --port 3001
```

This saves screenshots for all 7 devices to `.claude/screenshot/responsive-{device}.png`.

After capturing, read each screenshot image and report:
- Whether text is readable and not truncated
- Whether elements overflow or overlap
- Whether spacing and alignment look correct
- Whether interactive elements (buttons, links, cards) are properly sized for touch on mobile
- Whether the navigation/header adapts correctly across sizes
- Any content that is hidden or misaligned at certain breakpoints

## Arguments

- `$ARGUMENTS` is passed as CLI options to the script
- If no arguments given, captures the home page at 1920x1080 (desktop-hd default)

## Notes

- Connects to an already running dev server (auto-detects ports 7777, 7778, 7779, 7780)
- Does NOT start a dev server — you must start one first with `npm run dev`
- Waits for network idle + 2 seconds for React/Three.js rendering before capturing
- Screenshots are saved to `.claude/screenshot/` by default

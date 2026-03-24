#!/usr/bin/env node
/**
 * Responsive test screenshot tool using Playwright.
 *
 * Usage:
 *   node scripts/responsive-test.mjs [options]
 *
 * Options:
 *   --viewport WxH        Set viewport size (e.g. 1920x1080, 768x1024, 375x812)
 *   --device NAME         Use preset device (iphone-14, iphone-se, ipad, ipad-landscape, desktop, desktop-hd, desktop-4k)
 *   --action ACTION       Perform action(s): scroll-bottom, scroll-to-footer, click-SELECTOR, hover-SELECTOR
 *                         Chain multiple with comma: --action scroll-bottom,hover-.card
 *   --url PATH            URL path to test (default: /)
 *   --output FILE         Output screenshot path (default: .claude/screenshot/responsive-test.png)
 *   --port N              Force port (default: auto-detect 7777/7778/7779/7780)
 *   --full-page           Capture full page screenshot
 *   --all                 Capture all preset devices at once (saves to .claude/screenshot/responsive-{device}.png)
 */

// Check if playwright is available
let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.error(
    "[responsive-test] Error: Playwright is not installed.\n" +
      "Install it with:\n\n" +
      "  npm install -D @playwright/test\n" +
      "  npx playwright install chromium\n"
  );
  process.exit(1);
}

import { mkdir } from "fs/promises";
import { dirname } from "path";

// --- Preset devices ---
const DEVICES = {
  "iphone-14": { width: 390, height: 844 },
  "iphone-se": { width: 375, height: 667 },
  ipad: { width: 768, height: 1024 },
  "ipad-landscape": { width: 1024, height: 768 },
  desktop: { width: 1280, height: 800 },
  "desktop-hd": { width: 1920, height: 1080 },
  "desktop-4k": { width: 3840, height: 2160 },
};

// --- Parse CLI arguments ---
let viewport = null;
let device = null;
let actions = [];
let urlPath = "/";
let outputFile = ".claude/screenshot/responsive-test.png";
let forcePort = null;
let fullPage = true;
let allDevices = false;

for (let i = 2; i < process.argv.length; i++) {
  const arg = process.argv[i];
  const next = process.argv[i + 1];

  if (arg === "--viewport" && next) {
    const parts = next.split("x").map(Number);
    if (parts.length === 2 && parts.every((n) => !isNaN(n) && n > 0)) {
      viewport = { width: parts[0], height: parts[1] };
    } else {
      console.error(`[responsive-test] Invalid viewport format: ${next}. Use WxH (e.g. 1920x1080)`);
      process.exit(1);
    }
    i++;
  } else if (arg === "--device" && next) {
    device = next.toLowerCase();
    if (!DEVICES[device]) {
      console.error(
        `[responsive-test] Unknown device: ${next}\n` +
          `Available devices: ${Object.keys(DEVICES).join(", ")}`
      );
      process.exit(1);
    }
    i++;
  } else if (arg === "--action" && next) {
    actions = next.split(",").map((a) => a.trim());
    i++;
  } else if (arg === "--url" && next) {
    urlPath = next;
    i++;
  } else if (arg === "--output" && next) {
    outputFile = next;
    i++;
  } else if (arg === "--port" && next) {
    forcePort = parseInt(next);
    if (isNaN(forcePort)) {
      console.error(`[responsive-test] Invalid port: ${next}`);
      process.exit(1);
    }
    i++;
  } else if (arg === "--full-page") {
    fullPage = true;
  } else if (arg === "--all") {
    allDevices = true;
  }
}

// --- Auto-detect running dev server ---
const CANDIDATE_PORTS = [7777, 7778, 7779, 7780];

async function findRunningServer(ports) {
  for (const port of ports) {
    try {
      const res = await fetch(`http://localhost:${port}/`, {
        signal: AbortSignal.timeout(2000),
      });
      if (res.ok || res.status < 500) return port;
    } catch {
      // not running on this port
    }
  }
  return null;
}

const port = forcePort || (await findRunningServer(CANDIDATE_PORTS));

if (!port) {
  console.error(
    "[responsive-test] No running dev server found.\n" +
      `Checked ports: ${CANDIDATE_PORTS.join(", ")}\n` +
      "Start the dev server first with: npm run dev"
  );
  process.exit(1);
}

console.log(`[responsive-test] Using dev server on port ${port}`);

// --- Ensure output directory exists ---
const outDir = ".claude/screenshot";
await mkdir(outDir, { recursive: true });

// --- Helper: capture a single viewport ---
async function captureDevice(browser, deviceName, vp, outPath) {
  const context = await browser.newContext({ viewport: vp });
  const page = await context.newPage();
  const url = `http://localhost:${port}${urlPath}`;

  await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
  await page.waitForTimeout(2000);

  // Execute actions
  for (const action of actions) {
    if (action === "scroll-bottom") {
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await page.waitForTimeout(1000);
    } else if (action === "scroll-to-footer") {
      const footer = await page.$("#footer");
      if (footer) {
        await footer.scrollIntoViewIfNeeded();
      } else {
        await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      }
      await page.waitForTimeout(1000);
    } else if (action.startsWith("click-")) {
      try { await page.click(action.slice(6), { timeout: 5000 }); await page.waitForTimeout(500); } catch {}
    } else if (action.startsWith("hover-")) {
      try { await page.hover(action.slice(6), { timeout: 5000 }); await page.waitForTimeout(500); } catch {}
    }
  }

  await page.screenshot({ path: outPath, fullPage });
  await context.close();
  console.log(`[responsive-test] ${deviceName} (${vp.width}x${vp.height}) → ${outPath}`);
}

// --- Main ---
let browser;
try {
  browser = await chromium.launch({ headless: true });

  if (allDevices) {
    console.log(`[responsive-test] Capturing all devices...`);
    for (const [name, vp] of Object.entries(DEVICES)) {
      await captureDevice(browser, name, vp, `${outDir}/responsive-${name}.png`);
    }
    console.log(`\n[responsive-test] Done! ${Object.keys(DEVICES).length} screenshots saved to ${outDir}/`);
  } else {
    const resolvedViewport = viewport || (device && DEVICES[device]) || DEVICES["desktop-hd"];
    const deviceLabel = device || `${resolvedViewport.width}x${resolvedViewport.height}`;
    await mkdir(dirname(outputFile), { recursive: true });
    await captureDevice(browser, deviceLabel, resolvedViewport, outputFile);
  }

  await browser.close();
} catch (err) {
  console.error(`[responsive-test] Error: ${err.message}`);
  if (browser) await browser.close();
  process.exit(1);
}

#!/usr/bin/env node
/**
 * Start dev server, take a screenshot, then shut down.
 *
 * Usage:
 *   node scripts/screenshot.mjs [url-path] [output-file] [--quality N] [--scale N]
 *
 * Options:
 *   --quality N   JPEG quality 1-100 (converts output to JPEG). Omit for PNG.
 *   --scale N     Device scale factor (default: 1). Use 0.5 for half-res.
 *
 * Examples:
 *   node scripts/screenshot.mjs                                        # PNG, full res
 *   node scripts/screenshot.mjs /session/foo out.png                   # PNG
 *   node scripts/screenshot.mjs /session/foo out.jpg --quality 60      # JPEG 60%
 *   node scripts/screenshot.mjs /session/foo out.png --scale 0.5       # half-res PNG
 */

import { spawn } from 'child_process'
import puppeteer from 'puppeteer'

// Parse args
const positional = []
let quality = null
let scale = 1
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === '--quality' && process.argv[i + 1]) {
    const q = parseInt(process.argv[++i])
    quality = isNaN(q) ? null : q
  } else if (process.argv[i] === '--scale' && process.argv[i + 1]) {
    const s = parseFloat(process.argv[++i])
    scale = isNaN(s) || s <= 0 ? 1 : s
  } else {
    positional.push(process.argv[i])
  }
}

const urlPath = positional[0] || '/'
const outFile = positional[1] || '.claude/screenshot/screenshot.png'
const PORT = 3111 // use a non-conflicting port

console.log(`[screenshot] Starting dev server on port ${PORT}...`)

const server = spawn('npx', ['next', 'dev', '--turbopack', '-p', String(PORT)], {
  cwd: new URL('../../../..', import.meta.url).pathname,
  stdio: ['pipe', 'pipe', 'pipe'],
  env: { ...process.env },
})

let serverOutput = ''
server.stdout.on('data', (d) => { serverOutput += d.toString() })
server.stderr.on('data', (d) => { serverOutput += d.toString() })

// Wait for server to be ready
await new Promise((resolve) => {
  const check = setInterval(() => {
    if (serverOutput.includes('Ready') || serverOutput.includes('started')) {
      clearInterval(check)
      resolve()
    }
  }, 500)
  // Timeout after 30s
  setTimeout(() => { clearInterval(check); resolve() }, 30000)
})

console.log(`[screenshot] Server ready. Capturing ${urlPath}...`)

try {
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] })
  const page = await browser.newPage()
  await page.setViewport({ width: 1400, height: 900, deviceScaleFactor: scale })
  await page.goto(`http://localhost:${PORT}${urlPath}`, { waitUntil: 'networkidle0', timeout: 15000 })
  // Wait a bit for React to render
  await new Promise((r) => setTimeout(r, 2000))

  const screenshotOpts = { path: outFile, fullPage: true }
  if (quality != null) {
    screenshotOpts.type = 'jpeg'
    screenshotOpts.quality = Math.max(1, Math.min(100, quality))
  }
  await page.screenshot(screenshotOpts)

  console.log(`[screenshot] Saved to ${outFile}`)
  await browser.close()
} catch (err) {
  console.error(`[screenshot] Error:`, err.message)
} finally {
  server.kill('SIGTERM')
  console.log('[screenshot] Server stopped.')
  process.exit(0)
}

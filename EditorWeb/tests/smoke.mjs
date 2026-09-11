import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { chromium } from 'playwright';

/**
 * Phase 0 smoke test: loads the harness in headless Chromium and verifies the
 * gates that don't need a native host — boot, ready handshake, typing produces
 * one debounced `changed`, theme/mode commands work, and zero cross-origin
 * network requests. Run: `npm run smoke`.
 */
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };

const server = createServer(async (req, res) => {
  const path = normalize(join('.', req.url === '/' ? '/harness/index.html' : req.url ?? ''));
  try {
    const body = await readFile(path);
    res.writeHead(200, { 'content-type': MIME[extname(path)] ?? 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}`;

const browser = await chromium.launch();
const page = await browser.newPage();
const crossOrigin = [];
page.on('request', (req) => {
  if (!req.url().startsWith(base) && !req.url().startsWith('data:')) crossOrigin.push(req.url());
});

const failures = [];
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures.push(name);
};

await page.goto(`${base}/harness/index.html`);
await page.waitForSelector('.ProseMirror', { timeout: 10000 });
check('editor boots to rich mode', true);

// ready handshake happened (harness logged it).
await page.waitForFunction(() => document.querySelector('#bridge-log')?.textContent.includes('"ready"'));
check('ready handshake sent', true);

// Boot harness loaded the welcome corpus.
const initial = await page.locator('.ProseMirror').innerText();
check('corpus document rendered', initial.includes('Welcome'), initial.slice(0, 40));

// Type into the surface: exactly one debounced changed message.
await page.locator('.ProseMirror').click();
await page.keyboard.press('End');
await page.keyboard.type(' typed');
await page.waitForFunction(
  () => (document.querySelector('#bridge-log')?.textContent.match(/"changed"/g) ?? []).length >= 1,
  { timeout: 5000 },
);
await page.waitForTimeout(500);
const changedCount = await page.evaluate(
  () => (document.querySelector('#bridge-log')?.textContent.match(/"changed"/g) ?? []).length,
);
check('typing emits debounced changed', changedCount === 1, `${changedCount} message(s)`);

// Toggle to source mode and back; document must survive.
await page.click('#mode');
await page.waitForSelector('.cm-content', { timeout: 5000 });
const sourceText = await page.locator('.cm-content').innerText();
check('source mode shows markdown', sourceText.includes('# Welcome'), sourceText.slice(0, 30));
await page.click('#mode');
await page.waitForSelector('.ProseMirror', { timeout: 5000 });
check('mode round-trip back to rich', (await page.locator('.ProseMirror').innerText()).includes('Welcome'));

// Theme command flips the root attribute.
await page.click('#theme');
const theme = await page.evaluate(() => document.documentElement.dataset.tdTheme);
check('setTheme dark applied', theme === 'dark');

// Offline gate.
check('zero cross-origin requests', crossOrigin.length === 0, crossOrigin.join(', '));

await browser.close();
server.close();
if (failures.length) {
  console.error(`\n${failures.length} gate(s) failed`);
  process.exit(1);
}
console.log('\nAll smoke gates passed');

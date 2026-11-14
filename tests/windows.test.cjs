const assert = require('node:assert/strict');
const { execFile, spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');
const { promisify } = require('node:util');
const { test } = require('node:test');
const { chromium } = require('playwright');

const run = promisify(execFile);
const expectedName = 'InuYasha (2000) - S06E28-E29.mkv';
const plannerUrl = 'https://anime-filename-planner.invalid/index.html';
const debugEndpoint = 'http://127.0.0.1:9222';

async function waitForWebView(app) {
  for (let attempt = 0; attempt < 120; attempt++) {
    if (app.exitCode !== null) throw new Error(`The Windows app exited with code ${app.exitCode}.`);
    const version = await fetch(`${debugEndpoint}/json/version`, { signal: AbortSignal.timeout(500) })
      .then(response => response.ok, () => false);
    if (version) return chromium.connectOverCDP(debugEndpoint, { timeout: 10000 });
    await delay(250);
  }
  throw new Error('WebView2 did not start. Check the Windows app and WebView2 Runtime.');
}

const powerShell = (args, options) => run('powershell.exe', ['-NoProfile', '-NonInteractive', '-STA', ...args], options);

test('published Windows app opens and exports through its native controls', {
  skip: process.platform !== 'win32',
  timeout: 90000,
}, async t => {
  const executable = path.resolve(process.env.PLANNER_EXE ?? 'artifacts/Anime-Filename-Planner.exe');
  await fs.access(executable);
  const profile = await fs.mkdtemp(path.join(os.tmpdir(), 'anime-planner-test-'));
  const app = spawn(executable, [], {
    cwd: path.dirname(executable),
    env: {
      ...process.env,
      WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: '--remote-debugging-port=9222',
      WEBVIEW2_USER_DATA_FOLDER: path.join(profile, 'webview'),
    },
  });
  t.after(async () => {
    if (app.pid && app.exitCode === null) {
      await run('taskkill.exe', ['/PID', String(app.pid), '/T', '/F'], { timeout: 5000 }).catch(() => {});
    }
    await fs.rm(profile, { recursive: true, force: true, maxRetries: 10 }).catch(() => {});
  });
  await new Promise((resolve, reject) => {
    app.once('spawn', resolve);
    app.once('error', reject);
  });

  const browser = await waitForWebView(app);
  try {
    const context = browser.contexts()[0];
    const page = context.pages()[0] ?? await context.waitForEvent('page', { timeout: 15000 });
    page.setDefaultTimeout(10000);
    await page.waitForURL(plannerUrl);
    await page.locator('#filenames code').getByText(expectedName, { exact: true }).waitFor();
    console.log('PASS: The Windows executable opens and displays the correct combined episode.');

    await page.locator('#copy').click();
    await page.locator('#action-status').getByText('Filename list copied.', { exact: true }).waitFor();
    const clipboard = await powerShell(['-Command', 'Get-Clipboard -Raw'], { timeout: 5000 });
    assert.equal(clipboard.stdout.trimEnd(), expectedName);
    console.log('PASS: The app copies the expected filename to the Windows clipboard.');

    const destination = path.join(profile, 'anime-filenames.txt');
    await page.locator('#download').click();
    await powerShell(['-File', path.join(__dirname, 'save-dialog.ps1')], {
      env: { ...process.env, PLANNER_TEST_PID: String(app.pid), PLANNER_TEST_EXPORT: destination },
      timeout: 18000,
    });
    await page.locator('#action-status').getByText('Filename list saved.', { exact: true }).waitFor();
    assert.equal(await fs.readFile(destination, 'utf8'), expectedName);
    console.log('PASS: The native Windows Save dialog writes the expected text.');
  } finally {
    await browser.close();
  }
});

// Run against a served Web export. Requires Playwright; each run uses a fresh
// isolated browser context and never touches the player's browser profile.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');

const SAVE_KEY = 'farflight.save.v5';
const artifactDirectory = process.env.WEB_SMOKE_ARTIFACT_DIR || path.join(os.tmpdir(), 'farflight-web-smoke');

(async () => {
  await fs.mkdir(artifactDirectory, { recursive: true });
  const browser = await chromium.launch({
    executablePath: process.env.BROWSER_PATH || undefined,
    args: ['--enable-unsafe-swiftshader'],
  });
  const context = await browser.newContext({ viewport: {
    width: Number(process.env.WEB_SMOKE_WIDTH || 1280),
    height: Number(process.env.WEB_SMOKE_HEIGHT || 800),
  } });
  await context.tracing.start({ screenshots: true, snapshots: true });
  const page = await context.newPage();
  const errors = [];
  const messages = [];
  let phase = 'loading';
  const checkpoint = text => { phase = text; console.log(`Web smoke: ${text}`); };
  page.on('pageerror', error => errors.push(String(error)));
  page.on('console', message => {
    messages.push({ type: message.type(), text: message.text() });
    if (/SCRIPT ERROR:|Parse Error|ERROR:/.test(message.text())) errors.push(message.text());
  });
  page.on('requestfailed', request => messages.push({ url: request.url(), failure: request.failure() }));
  try {
    const ready = async () => {
      await page.waitForFunction(() => !document.querySelector('#status'), null, { timeout: 60000 });
      await page.locator('#canvas').focus();
      await page.waitForTimeout(1500);
    };
    const key = async name => { await page.keyboard.press(name); await page.waitForTimeout(1500); };
    // Godot renders into a canvas, so DOM button locators cannot see its menu.
    // Rebuilt menus focus their first action; Shift+Tab wraps to the last one
    // (Save and exit in a paused campaign). No pixel positions or row counts.
    const saveAndExit = async () => { await key('Shift+Tab'); await key('Enter'); };
    const read = () => page.evaluate(key => localStorage.getItem(key), SAVE_KEY);
    await page.goto(process.env.WEB_URL || 'http://127.0.0.1:8765');
    await ready();
    checkpoint('new game and seed setup');
    assert.equal(await read(), null, 'A fresh browser context must not contain a player save');
    await key('Enter'); // First title action: New game, opens the seed form.
    await page.keyboard.type('424242'); // The seed field receives focus.
    await key('Enter'); // Submit the seed form and actually start the flight.
    await page.waitForTimeout(1500);
    checkpoint('save from pause menu');
    await key('Escape');
    await saveAndExit();
    const saved = await read();
    assert.ok(saved && saved.length > 1000, 'Web save must reach persistent browser storage');
    await page.reload();
    await ready();
    checkpoint('continue after page reload');
    assert.equal(await read(), saved, 'Save must survive reloading the page');
    await key('Enter'); // First title action with a save: Continue.
    await page.waitForTimeout(1500);
    await page.screenshot({ path: path.join(artifactDirectory, 'loaded.png') });
    await key('Escape');
    checkpoint('storage quota failure');
    await page.evaluate(saveKey => {
      window.originalSetItem = Storage.prototype.setItem;
      window.failedWrites = 0;
      Storage.prototype.setItem = function (key, value) {
        if (key !== saveKey) return window.originalSetItem.call(this, key, value);
        window.failedWrites++;
        throw new DOMException('Test quota failure', 'QuotaExceededError');
      };
    }, SAVE_KEY);
    await saveAndExit();
    await page.screenshot({ path: path.join(artifactDirectory, 'quota.png') });
    assert.equal(await page.evaluate(() => window.failedWrites), 1, 'Save must attempt writing and handle quota failure');
    assert.equal(await read(), saved, 'Failed write must retain previous slot');
    await page.evaluate(() => { Storage.prototype.setItem = window.originalSetItem; });
    checkpoint('retry save after quota failure');
    await saveAndExit(); // Failure keeps the pause menu open and refocuses it.
    await page.screenshot({ path: path.join(artifactDirectory, 'resaved.png') });
    assert.ok(await read() !== saved, 'Loaded flight must continue and save updated state');
    assert.deepEqual(errors, [], 'No browser or Godot script errors');
    console.log('Web export: new game, save, reload, continue, quota failure and resave OK');
    await context.tracing.stop();
  } catch (error) {
    console.error(`Web smoke failed during: ${phase}`, errors);
    await page.screenshot({ path: path.join(artifactDirectory, 'failure.png') }).catch(() => {});
    await fs.writeFile(path.join(artifactDirectory, 'diagnostics.json'), JSON.stringify({ phase, error: String(error), errors, messages }, null, 2));
    await context.tracing.stop({ path: path.join(artifactDirectory, 'trace.zip') }).catch(() => {});
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });

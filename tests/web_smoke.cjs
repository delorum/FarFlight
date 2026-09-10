// Run against a served Web export. Requires Playwright; each run uses a fresh
// isolated browser context and never touches the player's browser profile.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.BROWSER_PATH || undefined,
    args: ['--enable-unsafe-swiftshader'],
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    page.on('console', msg => {
      if (/SCRIPT ERROR:|Parse Error|ERROR:/.test(msg.text())) errors.push(msg.text());
    });
    const ready = async () => {
      try {
        await page.waitForFunction(() => !document.querySelector('#status'), null, { timeout: 60000 });
      } catch (error) {
        console.error(await page.locator('body').innerText(), errors);
        await page.screenshot({ path: '/tmp/farflight-web-failure.png' });
        throw error;
      }
      await page.waitForTimeout(1500);
    };
    const key = async name => { await page.keyboard.press(name); await page.waitForTimeout(1500); };
    const click = async y => { await page.mouse.click(240, y); await page.waitForTimeout(1500); };
    const read = () => page.evaluate(() => localStorage.getItem('farflight.save.v1'));
    await page.goto(process.env.WEB_URL || 'http://127.0.0.1:8765');
    await ready();
    await click(350); // New game.
    await page.waitForTimeout(1500);
    await key('Escape');
    await click(435); // Save and return to title.
    const saved = await read();
    assert.ok(saved && saved.length > 1000, 'Web save must reach persistent browser storage');
    await page.reload();
    await ready();
    assert.equal(await read(), saved, 'Save must survive reloading the page');
    await click(410); // Continue from persisted data.
    await page.waitForTimeout(1500);
    await page.screenshot({ path: '/tmp/farflight-web-loaded.png' });
    await key('Escape');
    await page.evaluate(() => {
      window.originalSetItem = Storage.prototype.setItem;
      window.failedWrites = 0;
      Storage.prototype.setItem = () => { window.failedWrites++; throw new DOMException('Test quota failure', 'QuotaExceededError'); };
      try { localStorage.setItem('probe', 'probe'); } catch (_) { return; }
      throw new Error('Could not simulate storage failure');
    });
    await click(435);
    await page.screenshot({ path: '/tmp/farflight-web-quota.png' });
    assert.equal(await page.evaluate(() => window.failedWrites), 2, 'Save must attempt writing and handle quota failure');
    assert.equal(await read(), saved, 'Failed write must retain previous slot');
    await page.evaluate(() => { Storage.prototype.setItem = window.originalSetItem; });
    await click(435);
    await page.screenshot({ path: '/tmp/farflight-web-resaved.png' });
    assert.ok(await read() !== saved, 'Loaded flight must continue and save updated state');
    assert.deepEqual(errors, [], 'No browser or Godot script errors');
    console.log('Web export: new game, save, reload, continue, quota failure and resave OK');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });

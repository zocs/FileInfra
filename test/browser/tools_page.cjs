const assert = require('node:assert/strict');
const acorn = require('acorn');
const puppeteer = require('puppeteer-core');

async function main() {
  const url = process.argv[2];
  const html = await (await fetch(url)).text();
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)];
  assert.ok(scripts.length, 'The served tools page has an inline script');
  for (const [, script] of scripts) {
    acorn.parse(script, { ecmaVersion: 5 });
  }

  const browser = await puppeteer.launch({
    executablePath: process.env.FILEINFRA_CHROMIUM || '/usr/bin/chromium',
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  try {
    const context = browser.defaultBrowserContext();
    await context.overridePermissions(url, ['clipboard-read', 'clipboard-write', 'clipboard-sanitized-write']);
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(url);
    await page.waitForSelector('#status.connected');
    assert.equal(await page.$eval('#input', input => input.getAttribute('aria-label')),
      '共享剪贴板文本');
    assert.equal(await page.$eval('#tab-clipboard', tab => tab.getAttribute('aria-pressed')),
      'true');

    // Whitespace is part of the shared value, including when this tab sends it.
    const text = '  first line\n    second line\n';
    await page.$eval('#input', (input, value) => { input.value = value; }, text);
    await page.click('button[onclick="send()"]');
    await page.waitForFunction(value =>
      document.getElementById('display').textContent.includes(value), {}, text);
    const snapshot = await (await fetch(url + 'api/clipboard')).json();
    assert.equal(snapshot.text, text, 'The sender and server keep the exact shared text');
    await page.click('button[onclick^="copy"]');
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), text);

    // LAN HTTP uses the legacy copy path. Keep the native clipboard object to
    // check the resulting clipboard while hiding it from the code under test.
    await page.evaluate(async () => {
      window.nativeClipboard = navigator.clipboard;
      await window.nativeClipboard.writeText('unavailable API sentinel');
      Object.defineProperty(navigator, 'clipboard', {
        value: undefined, configurable: true,
      });
    });
    await page.click('button[onclick^="copy"]');
    assert.equal(await page.evaluate(() => window.nativeClipboard.readText()), text);
    assert.equal(await page.$$eval('textarea', fields => fields.length), 2,
      'The copy fallback cleans up its temporary field');

    // A rejected modern API must still try the HTTP-compatible copy path.
    await page.evaluate(async () => {
      await window.nativeClipboard.writeText('rejected API sentinel');
      Object.defineProperty(navigator, 'clipboard', {
        value: { writeText: () => Promise.reject(new Error('Clipboard unavailable')) },
        configurable: true,
      });
      window.prompt = () => { throw new Error('Manual-copy prompt should not be needed'); };
    });
    await page.click('button[onclick^="copy"]');
    assert.equal(await page.evaluate(() => window.nativeClipboard.readText()), text);
    assert.equal(await page.$$eval('textarea', fields => fields.length), 2);

    // Even a throwing legacy API must not leave an invisible field over the UI.
    await page.evaluate(async () => {
      await window.nativeClipboard.writeText('manual recovery sentinel');
      Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true });
      document.execCommand = () => { throw new Error('Copy denied'); };
      window.prompt = () => null;
    });
    await page.click('button[onclick^="copy"]');
    assert.equal(await page.$$eval('textarea', fields => fields.length), 2);
    assert.equal(await page.evaluate(() => window.nativeClipboard.readText()), 'manual recovery sentinel');
    assert.equal(await page.$eval('#manual-copy', input =>
      input.value.slice(input.selectionStart, input.selectionEnd)), text,
      'Manual recovery selects only the exact multiline shared text');
    assert.equal(await page.$eval('#manual-copy', input =>
      document.activeElement === input && input.getBoundingClientRect().height > 0), true,
      'The manual copy field is visible and focused');
    assert.match(await page.$eval('#copy-status', status => status.textContent), /手动复制/);
    await page.keyboard.down('Control');
    await page.keyboard.press('KeyC');
    await page.keyboard.up('Control');
    assert.equal(await page.evaluate(() => window.nativeClipboard.readText()), text,
      'A manual copy gesture preserves the trailing newline');

    // The page remains usable after copy failures, including offline QR images.
    await page.setViewport({ width: 360, height: 740 });
    await page.click('#tab-qr');
    assert.equal(await page.$eval('#tab-qr', tab => tab.getAttribute('aria-pressed')), 'true');
    assert.equal(await page.$eval('#tab-clipboard', tab => tab.getAttribute('aria-pressed')), 'false');
    assert.equal(await page.$eval('.qr-out .dl', button => button.tagName), 'BUTTON');
    const controls = await page.$$eval('.qr-input button, .qr-opts select, .qr-opts input', nodes =>
      nodes.map(node => {
        const rect = node.getBoundingClientRect();
        return { width: rect.width, height: rect.height, right: rect.right };
      }));
    assert.ok(controls.every(rect => rect.width >= 44 && rect.height >= 44 && rect.right <= 360),
      'QR controls have usable touch targets inside a narrow viewport');
    await page.type('#qrrows input', 'https://example.com/offline');
    await page.click('button[onclick="genQr(this)"]');
    await page.waitForFunction(() => {
      const image = document.querySelector('.qr-out img');
      return image.complete && image.naturalWidth > 0;
    });
    assert.deepEqual(errors, []);
    console.log('Tools page: ES5, exact sender text, copy fallbacks and offline QR passed');
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  console.error(error.stack);
  process.exitCode = 1;
});

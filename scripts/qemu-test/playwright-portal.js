// Playwright test: thingino WiFi captive portal
// Screenshots every meaningful step, outputs JSON results for the report.
//
// Usage: npx playwright test playwright-portal.js
// Env:   PORTAL_URL (default http://localhost:19080)
//        REPORT_DIR (default ./test-report)

const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const PORTAL_URL = process.env.PORTAL_URL || 'http://localhost:19080';
const REPORT_DIR = process.env.REPORT_DIR || path.join(__dirname, 'test-report');

function ensureDir(d) { fs.mkdirSync(d, { recursive: true }); }

test.describe('WiFi Portal', () => {
  test.skip(process.env.SKIP_PORTAL === '1', 'No portal in this mode');
  test.beforeAll(() => { ensureDir(REPORT_DIR); });

  test('portal loads and has form', async ({ page }) => {
    const failures = [];
    page.on('requestfailed', req => { failures.push(req.url()); });

    await page.goto(PORTAL_URL, { waitUntil: 'networkidle', timeout: 15000 });
    await expect(page).toHaveTitle(/Thingino|Initial Configuration/i);

    const ssidInput = page.locator('#wlan_ssid, input[name="wlan_ssid"]');
    const passInput = page.locator('#wlan_pass, input[name="wlan_pass"]');
    const hasForm = await ssidInput.count() > 0 || await passInput.count() > 0;
    expect(hasForm).toBeTruthy();
    expect(failures).toHaveLength(0);

    await page.screenshot({ path: path.join(REPORT_DIR, '01-portal-loaded.png'), fullPage: true });
  });

  test('portal API responds', async ({ page }) => {
    const response = await page.request.get(`${PORTAL_URL}/x/api.cgi?action=scan`);
    expect(response.status()).toBe(200);
    const body = await response.text();
    fs.writeFileSync(path.join(REPORT_DIR, '02-api-scan-response.json'), body);
  });

  test('fill credentials and submit', async ({ page }) => {
    test.skip(process.env.SKIP_PROVISION === '1', 'Provisioning test disabled');
    test.setTimeout(60000);

    await page.goto(PORTAL_URL, { waitUntil: 'networkidle', timeout: 15000 });

    const hostname = page.locator('#hostname, input[name="hostname"]');
    if (await hostname.count() > 0) {
      await hostname.clear();
      await hostname.fill('qemu-test');
    }

    const rootpass = page.locator('#rootpass, input[name="rootpass"]');
    if (await rootpass.count() > 0) {
      await rootpass.fill('TestPass1');
    }

    const ssid = page.locator('#wlan_ssid, input[name="wlan_ssid"]');
    await ssid.fill('TestNetwork');

    const pass = page.locator('#wlan_pass, input[name="wlan_pass"]');
    await pass.fill('testpass123');

    await page.screenshot({ path: path.join(REPORT_DIR, '03-provision-filled.png'), fullPage: true });

    const submit = page.locator('button[type="submit"], input[type="submit"], #btn-submit');
    await submit.click();
    await page.waitForTimeout(2000);

    await page.screenshot({ path: path.join(REPORT_DIR, '04-provision-review.png'), fullPage: true });

    const proceed = page.locator('#btn-proceed, .btn-proceed');
    if (await proceed.count() > 0) {
      await proceed.click();
      await page.waitForTimeout(1000);
      await page.screenshot({ path: path.join(REPORT_DIR, '05-provision-saving.png'), fullPage: true });

      // Wait for the save to complete (spinner disappears, success/reboot message)
      await page.waitForTimeout(8000);
    }

    await page.screenshot({ path: path.join(REPORT_DIR, '06-provision-result.png'), fullPage: true });

    const body = await page.textContent('body');
    const success = body.toLowerCase().includes('success') ||
                    body.toLowerCase().includes('rebooting') ||
                    body.toLowerCase().includes('completed') ||
                    body.toLowerCase().includes('saving') ||
                    body.toLowerCase().includes('connect');
    expect(success).toBeTruthy();
  });
});

test.describe('Main Web UI', () => {
  const WEBUI_URL = process.env.WEBUI_URL || `http://localhost:${parseInt(process.env.WEBUI_PORT || '19081')}`;

  test('web UI loads', async ({ page }) => {
    test.skip(process.env.SKIP_WEBUI === '1', 'Web UI not available in this mode');
    await page.goto(WEBUI_URL, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.screenshot({ path: path.join(REPORT_DIR, '07-webui-loaded.png'), fullPage: true });

    const html = await page.content();
    expect(html).toContain('<!DOCTYPE');
  });
});

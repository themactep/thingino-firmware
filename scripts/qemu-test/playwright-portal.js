// Playwright test: thingino WiFi captive portal
// Screenshots every meaningful step, outputs JSON results for the report.
//
// Usage: npx playwright test playwright-portal.js
// Env:   PW_MANIFEST  JSON written by the harness saying which scenarios
//                     to run and their URLs (see qemutest/playwright.py);
//                     without it, everything runs against localhost
//        REPORT_DIR   (default ./test-report)

const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const REPORT_DIR = process.env.REPORT_DIR || path.join(__dirname, 'test-report');
const M = process.env.PW_MANIFEST
  ? JSON.parse(fs.readFileSync(process.env.PW_MANIFEST, 'utf8'))
  : { portal: { url: 'http://localhost:19080' }, provision: true,
      webui: { url: 'http://localhost:19081' } };
const PORTAL_URL = M.portal ? M.portal.url : '';

function ensureDir(d) { fs.mkdirSync(d, { recursive: true }); }

test.describe('WiFi Portal', () => {
  test.skip(!M.portal, 'No portal in this run');
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
    test.skip(!M.provision, 'Provisioning not requested');
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
  test('web UI loads', async ({ page }) => {
    test.skip(!M.webui, 'Web UI not in this run');
    await page.goto(M.webui.url, { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.screenshot({ path: path.join(REPORT_DIR, '07-webui-loaded.png'), fullPage: true });

    const html = await page.content();
    expect(html).toContain('<!DOCTYPE');
  });
});

test.describe('WebUI Login', () => {
  test('provisioned password opens the web UI', async ({ page }) => {
    test.skip(!M.login, 'Login not in this run');
    test.setTimeout(60000);

    // Unauthenticated / redirects to the login form
    await page.goto(M.login.url + '/', { waitUntil: 'domcontentloaded', timeout: 15000 });
    await page.waitForSelector('#password', { timeout: 10000 });
    await page.screenshot({ path: path.join(REPORT_DIR, '20-webui-login.png'), fullPage: true });

    await page.fill('#password', M.login.password || 'root');
    await page.click('#loginBtn');

    // A non-default password lands on the preview page
    await page.waitForURL('**/preview.html', { timeout: 20000 });
    await page.waitForLoadState('domcontentloaded');
    await page.screenshot({ path: path.join(REPORT_DIR, '21-webui-logged-in.png'), fullPage: true });
  });
});

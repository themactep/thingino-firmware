const { defineConfig } = require('@playwright/test');
const path = require('path');

const REPORT_DIR = process.env.REPORT_DIR || path.join(__dirname, 'test-report');

module.exports = defineConfig({
  testDir: '.',
  testMatch: 'playwright-*.js',
  timeout: 30000,
  retries: 0,
  // per-run dirs: shared repo-local state breaks when runs alternate
  // between root (tap mode) and the regular user
  outputDir: process.env.PW_WORK_DIR || path.join(REPORT_DIR, 'pw-work'),
  reporter: [
    ['list'],
    ['json', { outputFile: path.join(REPORT_DIR, 'playwright-results.json') }],
  ],
  use: {
    headless: true,
    viewport: { width: 414, height: 896 }, // iPhone-sized (portal is mobile-first)
    ignoreHTTPSErrors: true,
    screenshot: 'on',
    // Chromium refuses its sandbox as root (tap mode runs under sudo)
    launchOptions: process.env.CHROMIUM_NO_SANDBOX === '1'
      ? { args: ['--no-sandbox'] } : {},
  },
  projects: [
    {
      name: 'mobile',
      use: { viewport: { width: 414, height: 896 } },
    },
    {
      name: 'desktop',
      use: { viewport: { width: 1280, height: 800 } },
    },
  ],
});

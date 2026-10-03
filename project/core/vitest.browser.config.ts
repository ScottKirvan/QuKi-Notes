import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/browser/**/*.browser.test.ts'],
    browser: {
      enabled: true,
      provider: 'playwright',
      name: 'chromium',
      headless: true,
    },
  },
});

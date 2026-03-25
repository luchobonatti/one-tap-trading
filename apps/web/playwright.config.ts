import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e/specs",
  globalSetup: "./e2e/global-setup.ts",

  timeout: 60_000,
  retries: process.env.CI !== undefined ? 1 : 0,
  workers: 1,

  reporter: [["html", { open: "never" }], ["list"]],

  use: {
    baseURL: "http://localhost:3000",
    trace: "on-first-retry",
    video: "on-first-retry",
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],

  webServer: {
    command: "pnpm dev",
    url: "http://localhost:3000",
    reuseExistingServer: true,
    timeout: 30_000,
  },
});

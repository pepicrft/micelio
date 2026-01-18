const { defineConfig } = require("@playwright/test");

const baseURL = process.env.PLAYWRIGHT_BASE_URL || "http://127.0.0.1:4002";

module.exports = defineConfig({
  testDir: "./test/playwright",
  timeout: 30_000,
  expect: {
    timeout: 5_000
  },
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure"
  },
  webServer: {
    command:
      "MIX_ENV=test mix ecto.create --quiet && " +
      "MIX_ENV=test mix ecto.migrate --quiet && " +
      "MIX_ENV=test mix run priv/repo/seeds_playwright.exs && " +
      "PHX_SERVER=true MIX_ENV=test PORT=4002 mix phx.server",
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000
  }
});

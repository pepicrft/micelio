const { test, expect } = require("@playwright/test");

const accountHandle = "playwright";
const projectHandle = "mobile-layout";

const viewports = [
  { name: "mobile-320", width: 320, height: 568 },
  { name: "mobile-375", width: 375, height: 667 },
  { name: "mobile-414", width: 414, height: 896 },
  { name: "tablet-768", width: 768, height: 1024 }
];

const visualPages = [
  {
    name: "home",
    path: "/",
    selectors: [".home-container", "#popular-projects"]
  },
  {
    name: "account",
    path: `/${accountHandle}`,
    selectors: ["#account-owned-projects", "#account-projects-list"]
  },
  {
    name: "project",
    path: `/${accountHandle}/${projectHandle}`,
    selectors: [".project-container", "#project-breadcrumb", "#project-tree"]
  },
  {
    name: "search",
    path: "/search?q=mobile",
    selectors: ["#repository-search", "#repository-search-results"]
  }
];

async function stabilizePage(page) {
  await page.addInitScript(() => {
    document.addEventListener("DOMContentLoaded", () => {
      const style = document.createElement("style");
      style.setAttribute("data-testid", "disable-animations");
      style.textContent = `
        *,
        *::before,
        *::after {
          animation-duration: 0s !important;
          animation-delay: 0s !important;
          transition-duration: 0s !important;
          transition-delay: 0s !important;
          scroll-behavior: auto !important;
        }
      `;
      document.head.appendChild(style);
    });
  });
}

for (const viewport of viewports) {
  test.describe(`mobile visual regression ${viewport.name}`, () => {
    test.use({ viewport, timezoneId: "UTC" });

    for (const visualPage of visualPages) {
      test(`${visualPage.name} renders consistently`, async ({ page }) => {
        await stabilizePage(page);
        await page.goto(visualPage.path, { waitUntil: "domcontentloaded" });
        for (const selector of visualPage.selectors) {
          await expect(page.locator(selector)).toBeVisible();
        }
        await expect(page).toHaveScreenshot(
          `visual-${visualPage.name}-${viewport.name}.png`,
          { fullPage: true }
        );
      });
    }
  });
}

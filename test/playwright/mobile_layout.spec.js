const { test, expect } = require("@playwright/test");

const accountHandle = "playwright";
const projectHandle = "mobile-layout";

const viewports = [
  { name: "iphone-se", width: 320, height: 568 },
  { name: "pixel-4a", width: 360, height: 640 },
  { name: "iphone-12", width: 390, height: 844 },
  { name: "iphone-15-pro", width: 393, height: 852 },
  { name: "iphone-14-pro-max", width: 430, height: 932 },
  { name: "pixel-5", width: 393, height: 851 },
  { name: "galaxy-s20", width: 412, height: 915 },
  { name: "iphone-se-landscape", width: 568, height: 320 }
];

async function expectNoHorizontalOverflow(page) {
  const overflow = await page.evaluate(() => {
    const doc = document.documentElement;
    const body = document.body;
    const scrollWidth = Math.max(doc.scrollWidth, body ? body.scrollWidth : 0);
    return scrollWidth - doc.clientWidth;
  });

  expect(overflow).toBeLessThanOrEqual(1);
}

for (const viewport of viewports) {
  test.describe(`mobile layout ${viewport.name}`, () => {
    test.use({ viewport });

    test("home page is readable without horizontal scroll", async ({ page }) => {
      await page.goto("/", { waitUntil: "domcontentloaded" });
      await expect(page.locator(".home-container")).toBeVisible();
      await expect(page.locator("#popular-projects")).toBeVisible();
      await expectNoHorizontalOverflow(page);
    });

    test("account page stacks content without overflow", async ({ page }) => {
      await page.goto(`/${accountHandle}`, { waitUntil: "domcontentloaded" });
      await expect(page.locator("#account-owned-projects")).toBeVisible();
      await expect(page.locator("#account-projects-list")).toBeVisible();
      await expectNoHorizontalOverflow(page);
    });

    test("project page fits tree and actions", async ({ page }) => {
      await page.goto(`/${accountHandle}/${projectHandle}`, {
        waitUntil: "domcontentloaded"
      });
      await expect(page.locator(".project-container")).toBeVisible();
      await expect(page.locator("#project-breadcrumb")).toBeVisible();
      await expect(page.locator("#project-tree")).toBeVisible();
      await expectNoHorizontalOverflow(page);
    });

    test("search page fits form and results list", async ({ page }) => {
      await page.goto("/search", { waitUntil: "domcontentloaded" });
      await expect(page.locator("#repository-search")).toBeVisible();
      await expect(page.locator("#repository-search-form")).toBeVisible();
      await expect(page.locator("#repository-search-results")).toBeHidden();
      await expectNoHorizontalOverflow(page);
    });

    test("agent progress page stacks on mobile", async ({ page }) => {
      await page.goto(`/${accountHandle}/${projectHandle}/agents`, {
        waitUntil: "domcontentloaded"
      });
      await expect(page.locator("#agent-progress")).toBeVisible();
      await expect(page.locator("#agent-progress-header")).toBeVisible();
      await expectNoHorizontalOverflow(page);
    });

    test("blob page keeps file content within viewport", async ({ page }) => {
      await page.goto(`/${accountHandle}/${projectHandle}/blob/README.md`, {
        waitUntil: "domcontentloaded"
      });
      await expect(page.locator("#project-file-content")).toBeVisible();
      await expectNoHorizontalOverflow(page);
    });

    test("session event viewer fits on mobile", async ({ page }) => {
      await page.goto(`/projects/${accountHandle}/${projectHandle}/sessions`, {
        waitUntil: "domcontentloaded"
      });
      await expect(page.locator(".sessions-list")).toBeVisible();
      await page
        .getByRole("link", { name: "Stream session events" })
        .first()
        .click();
      await expect(page.locator("#session-event-viewer")).toBeVisible();
      await expect(page.locator(".session-event-card")).toBeVisible();
      await expect(page.locator(".session-event-summary")).toContainText(
        "42% - Downloading"
      );
      await expect(page.locator(".session-event-icon-progress")).toBeVisible();
      await expectNoHorizontalOverflow(page);
    });
  });
}

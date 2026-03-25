import { test, expect } from "@playwright/test";

test.describe("smoke — unauthenticated", () => {
  test("page loads with correct heading", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "One Tap Trading" }).first()).toBeVisible();
  });

  test("SignupModal is visible in idle state", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("dialog")).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Create Account with Passkey" }),
    ).toBeVisible();
  });

  test("TradingGrid is not visible without authentication", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("button", { name: "LONG 2×" })).not.toBeVisible();
  });

  test("page title contains One Tap Trading", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveTitle(/One Tap Trading/);
  });
});

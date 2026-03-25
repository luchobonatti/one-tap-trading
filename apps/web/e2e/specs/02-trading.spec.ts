import { test, expect } from "../fixtures";

test.describe("trading — authenticated, real testnet", () => {
  test("TradingGrid renders 8 buttons when account and session are ready", async ({
    authenticatedPage: page,
  }) => {
    await expect(page.getByRole("button", { name: /×/ }).first()).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByRole("button", { name: /×/ })).toHaveCount(8);
  });

  test("session expiry and revoke controls are visible", async ({
    authenticatedPage: page,
  }) => {
    await expect(page.getByText(/Session expires/)).toBeVisible({ timeout: 15_000 });
    await expect(page.getByRole("button", { name: "revoke" })).toBeVisible();
  });

  test("LONG 2× trade submits and confirms on-chain", async ({
    authenticatedPage: page,
  }) => {
    await expect(page.getByRole("button", { name: "LONG 2×" })).toBeVisible({
      timeout: 15_000,
    });

    await page.getByRole("button", { name: "LONG 2×" }).click();

    await expect(page.getByText("Submitting trade…")).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.getByText("Position opened ✓")).toBeVisible({
      timeout: 60_000,
    });
  });

  test("SHORT 5× trade submits and confirms on-chain", async ({
    authenticatedPage: page,
  }) => {
    await expect(page.getByRole("button", { name: "SHORT 5×" })).toBeVisible({
      timeout: 15_000,
    });

    await page.getByRole("button", { name: "SHORT 5×" }).click();

    await expect(page.getByText("Submitting trade…")).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.getByText("Position opened ✓")).toBeVisible({
      timeout: 60_000,
    });
  });

  test("grid buttons are disabled while a trade is pending", async ({
    authenticatedPage: page,
  }) => {
    await expect(page.getByRole("button", { name: "LONG 10×" })).toBeVisible({
      timeout: 15_000,
    });

    await page.getByRole("button", { name: "LONG 10×" }).click();

    await expect(page.getByText("Submitting trade…")).toBeVisible({
      timeout: 10_000,
    });

    for (const label of [
      "LONG 2×",
      "LONG 5×",
      "LONG 10×",
      "LONG 20×",
      "SHORT 2×",
      "SHORT 5×",
      "SHORT 10×",
      "SHORT 20×",
    ]) {
      await expect(page.getByRole("button", { name: label })).toBeDisabled();
    }
  });
});

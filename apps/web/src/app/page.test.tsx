import { describe, it, expect } from "vitest";

describe("HomePage", () => {
  it("module loads without error", async () => {
    const mod = await import("./page");
    expect(mod.default).toBeDefined();
  });
});

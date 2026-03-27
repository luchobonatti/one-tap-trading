import { describe, it, expect } from "vitest";
import { calculatePnL } from "@/lib/trading/pnl";

describe("calculatePnL", () => {
  const ENTRY = 2000_00000000n;
  const COLLATERAL = 1_000_000n;
  const LEVERAGE = 10n;

  it("long + price up → positive PnL", () => {
    const current = 2200_00000000n;
    const pnl = calculatePnL(ENTRY, current, COLLATERAL, LEVERAGE, true);
    expect(pnl).toBe(1_000_000n);
  });

  it("long + price down → negative PnL", () => {
    const current = 1800_00000000n;
    const pnl = calculatePnL(ENTRY, current, COLLATERAL, LEVERAGE, true);
    expect(pnl).toBe(-1_000_000n);
  });

  it("short + price up → negative PnL", () => {
    const current = 2200_00000000n;
    const pnl = calculatePnL(ENTRY, current, COLLATERAL, LEVERAGE, false);
    expect(pnl).toBe(-1_000_000n);
  });

  it("short + price down → positive PnL", () => {
    const current = 1800_00000000n;
    const pnl = calculatePnL(ENTRY, current, COLLATERAL, LEVERAGE, false);
    expect(pnl).toBe(1_000_000n);
  });

  it("zero collateral → zero PnL", () => {
    const pnl = calculatePnL(ENTRY, 2200_00000000n, 0n, LEVERAGE, true);
    expect(pnl).toBe(0n);
  });

  it("price unchanged → zero PnL", () => {
    const pnl = calculatePnL(ENTRY, ENTRY, COLLATERAL, LEVERAGE, true);
    expect(pnl).toBe(0n);
  });

  it("leverage 1x at +10% → 10% of collateral", () => {
    const current = 2200_00000000n;
    const pnl = calculatePnL(ENTRY, current, COLLATERAL, 1n, true);
    expect(pnl).toBe(100_000n);
  });

  it("leverage 30x long: pnl = (currentPrice - entryPrice) * collateral * leverage / entryPrice", () => {
    const current = 2066_60000000n;
    const pnl = calculatePnL(ENTRY, current, COLLATERAL, 30n, true);
    const expected = ((current - ENTRY) * (COLLATERAL * 30n)) / ENTRY;
    expect(pnl).toBe(expected);
  });
});

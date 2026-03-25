import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { TradingGrid } from "@/components/trading-grid";
import type { UseTradeReturn } from "@/hooks/use-trade";

function makeTrade(overrides: Partial<UseTradeReturn>): UseTradeReturn {
  return {
    status: "idle",
    pendingOpHash: undefined,
    error: undefined,
    openPosition: vi.fn(),
    reset: vi.fn(),
    ...overrides,
  };
}

afterEach(() => cleanup());

describe("TradingGrid", () => {
  it("renders 8 grid cells", () => {
    render(<TradingGrid trade={makeTrade({})} />);
    expect(screen.getAllByRole("button")).toHaveLength(8);
  });

  it("renders 4 LONG cells and 4 SHORT cells", () => {
    render(<TradingGrid trade={makeTrade({})} />);
    const longs = screen.getAllByRole("button").filter((b) =>
      b.getAttribute("aria-label")?.startsWith("LONG"),
    );
    const shorts = screen.getAllByRole("button").filter((b) =>
      b.getAttribute("aria-label")?.startsWith("SHORT"),
    );
    expect(longs).toHaveLength(4);
    expect(shorts).toHaveLength(4);
  });

  it("renders leverage tiers 2×, 5×, 10×, 20× for each direction", () => {
    render(<TradingGrid trade={makeTrade({})} />);
    const labels = screen
      .getAllByRole("button")
      .map((b) => b.getAttribute("aria-label") ?? "");
    expect(labels).toContain("LONG 2×");
    expect(labels).toContain("LONG 20×");
    expect(labels).toContain("SHORT 2×");
    expect(labels).toContain("SHORT 20×");
  });

  it("calls openPosition(true, 5n) when LONG 5× is tapped", () => {
    const openPosition = vi.fn().mockResolvedValue(undefined);
    render(<TradingGrid trade={makeTrade({ openPosition })} />);
    fireEvent.click(screen.getByRole("button", { name: "LONG 5×" }));
    expect(openPosition).toHaveBeenCalledWith(true, 5n);
  });

  it("calls openPosition(false, 10n) when SHORT 10× is tapped", () => {
    const openPosition = vi.fn().mockResolvedValue(undefined);
    render(<TradingGrid trade={makeTrade({ openPosition })} />);
    fireEvent.click(screen.getByRole("button", { name: "SHORT 10×" }));
    expect(openPosition).toHaveBeenCalledWith(false, 10n);
  });

  it("disables all cells when status is pending", () => {
    render(<TradingGrid trade={makeTrade({ status: "pending" })} />);
    for (const btn of screen.getAllByRole("button")) {
      if (btn.textContent !== "Dismiss") {
        expect(btn).toBeDisabled();
      }
    }
  });

  it("shows pending indicator when status is pending", () => {
    render(<TradingGrid trade={makeTrade({ status: "pending" })} />);
    expect(screen.getByText(/submitting trade/i)).toBeInTheDocument();
  });

  it("shows confirmed state", () => {
    render(<TradingGrid trade={makeTrade({ status: "confirmed" })} />);
    expect(screen.getByText(/position opened/i)).toBeInTheDocument();
  });

  it("shows error and dismiss button on failure", () => {
    render(
      <TradingGrid
        trade={makeTrade({ status: "failed", error: "Session key expired" })}
      />,
    );
    expect(screen.getByText("Session key expired")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /dismiss/i })).toBeInTheDocument();
  });

  it("calls reset() when dismiss is clicked", () => {
    const reset = vi.fn();
    render(
      <TradingGrid
        trade={makeTrade({ status: "failed", error: "fail", reset })}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /dismiss/i }));
    expect(reset).toHaveBeenCalledOnce();
  });
});

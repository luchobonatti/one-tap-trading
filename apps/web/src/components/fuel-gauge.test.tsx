import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { FuelGauge } from "@/components/fuel-gauge";

afterEach(() => cleanup());

describe("FuelGauge", () => {
  it("renders the fuel label and current value", () => {
    render(<FuelGauge value={5} onChange={vi.fn()} />);
    expect(screen.getByText("5×")).toBeInTheDocument();
    expect(screen.getByRole("slider", { name: /leverage 5x/i })).toBeInTheDocument();
  });

  it("calls onChange with the new numeric value when slider changes", () => {
    const onChange = vi.fn();
    render(<FuelGauge value={5} onChange={onChange} />);
    fireEvent.change(screen.getByRole("slider"), { target: { value: "15" } });
    expect(onChange).toHaveBeenCalledWith(15);
  });

  it("applies animate-pulse class at max leverage (20)", () => {
    render(<FuelGauge value={20} onChange={vi.fn()} />);
    const label = screen.getByText("20×");
    expect(label.className).toContain("animate-pulse");
  });

  it("does not apply animate-pulse below max leverage", () => {
    render(<FuelGauge value={10} onChange={vi.fn()} />);
    const label = screen.getByText("10×");
    expect(label.className).not.toContain("animate-pulse");
  });

  it("slider has min=2 and max=20", () => {
    render(<FuelGauge value={5} onChange={vi.fn()} />);
    const slider = screen.getByRole("slider");
    expect(slider).toHaveAttribute("min", "2");
    expect(slider).toHaveAttribute("max", "20");
  });
});

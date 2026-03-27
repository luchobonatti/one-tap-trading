import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { LongShortButtons } from "@/components/long-short-buttons";

afterEach(() => cleanup());

describe("LongShortButtons", () => {
  it("renders LONG and SHORT buttons", () => {
    render(<LongShortButtons disabled={false} onClick={vi.fn()} />);
    expect(screen.getByRole("button", { name: /long/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /short/i })).toBeInTheDocument();
  });

  it("calls onClick('long') when LONG is clicked", () => {
    const onClick = vi.fn();
    render(<LongShortButtons disabled={false} onClick={onClick} />);
    fireEvent.click(screen.getByRole("button", { name: /long/i }));
    expect(onClick).toHaveBeenCalledWith("long");
  });

  it("calls onClick('short') when SHORT is clicked", () => {
    const onClick = vi.fn();
    render(<LongShortButtons disabled={false} onClick={onClick} />);
    fireEvent.click(screen.getByRole("button", { name: /short/i }));
    expect(onClick).toHaveBeenCalledWith("short");
  });

  it("disables both buttons when disabled=true", () => {
    render(<LongShortButtons disabled={true} onClick={vi.fn()} />);
    expect(screen.getByRole("button", { name: /long/i })).toBeDisabled();
    expect(screen.getByRole("button", { name: /short/i })).toBeDisabled();
  });

  it("does not call onClick when disabled", () => {
    const onClick = vi.fn();
    render(<LongShortButtons disabled={true} onClick={onClick} />);
    fireEvent.click(screen.getByRole("button", { name: /long/i }));
    expect(onClick).not.toHaveBeenCalled();
  });
});

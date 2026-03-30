import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { FaucetModal } from "@/components/faucet-modal";

vi.mock("@/hooks/use-faucet");

import { useFaucet } from "@/hooks/use-faucet";

const mockUseFaucet = vi.mocked(useFaucet);

function makeFaucetHook(overrides: Partial<ReturnType<typeof useFaucet>> = {}) {
  return {
    state: "idle" as const,
    error: undefined,
    execute: vi.fn(),
    reset: vi.fn(),
    ...overrides,
  };
}

afterEach(() => cleanup());

describe("FaucetModal", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUseFaucet.mockReturnValue(makeFaucetHook());
  });

  it("renders nothing when isOpen is false", () => {
    const { container } = render(
      <FaucetModal isOpen={false} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    expect(container.firstChild).toBeNull();
  });

  it("shows idle state with Get 10,000 USDC title and enabled Claim button", () => {
    mockUseFaucet.mockReturnValue(makeFaucetHook({ state: "idle" }));
    render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    expect(screen.getByText("Get 10,000 USDC")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /claim/i }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /claim/i }),
    ).not.toBeDisabled();
  });

  it("shows idle state description", () => {
    mockUseFaucet.mockReturnValue(makeFaucetHook({ state: "idle" }));
    render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    expect(
      screen.getByText("Claim free testnet USDC to start trading."),
    ).toBeInTheDocument();
  });

  it("calls execute when Claim button is clicked in idle state", () => {
    const execute = vi.fn();
    mockUseFaucet.mockReturnValue(makeFaucetHook({ state: "idle", execute }));
    render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /claim/i }));
    expect(execute).toHaveBeenCalledOnce();
  });

  it("shows loading state with spinner and disabled button", () => {
    mockUseFaucet.mockReturnValue(makeFaucetHook({ state: "loading" }));
    render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    const loadingText = screen.getAllByText("Signing with passkey…");
    expect(loadingText.length).toBeGreaterThan(0);
    const buttons = screen.getAllByRole("button", { name: /claim/i });
    expect(buttons[0]).toBeDisabled();
  });

  it("shows success state with checkmark and message", () => {
    mockUseFaucet.mockReturnValue(makeFaucetHook({ state: "success" }));
    render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    expect(screen.getByText("✓")).toBeInTheDocument();
    const successMessages = screen.getAllByText("10,000 USDC added!");
    expect(successMessages.length).toBeGreaterThan(0);
  });

  it("sets up auto-close timeout when state is success", () => {
    vi.useFakeTimers();
    const setTimeoutSpy = vi.spyOn(global, "setTimeout");
    mockUseFaucet.mockReturnValue(makeFaucetHook({ state: "success" }));
    render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    expect(setTimeoutSpy).toHaveBeenCalledWith(expect.any(Function), 2000);
    vi.useRealTimers();
  });

  it("clears timeout on unmount", () => {
    vi.useFakeTimers();
    const clearTimeoutSpy = vi.spyOn(global, "clearTimeout");
    mockUseFaucet.mockReturnValue(makeFaucetHook({ state: "success" }));
    const { unmount } = render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    unmount();
    expect(clearTimeoutSpy).toHaveBeenCalled();
    vi.useRealTimers();
  });

  it("shows error state with error message and buttons", () => {
    mockUseFaucet.mockReturnValue(
      makeFaucetHook({
        state: "error",
        error: "Network error occurred",
      }),
    );
    render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    expect(screen.getByText("Network error occurred")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /try again/i }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /cancel/i }),
    ).toBeInTheDocument();
  });

  it("calls reset and execute when Try again is clicked in error state", () => {
    const execute = vi.fn();
    const reset = vi.fn();
    mockUseFaucet.mockReturnValue(
      makeFaucetHook({
        state: "error",
        error: "Network error",
        execute,
        reset,
      }),
    );
    render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={vi.fn()} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /try again/i }));
    expect(reset).toHaveBeenCalledOnce();
    expect(execute).toHaveBeenCalledOnce();
  });

  it("calls onClose when Cancel is clicked in error state", () => {
    const onClose = vi.fn();
    mockUseFaucet.mockReturnValue(
      makeFaucetHook({
        state: "error",
        error: "Network error",
      }),
    );
    render(
      <FaucetModal isOpen={true} onClose={onClose} onSuccess={vi.fn()} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));
    expect(onClose).toHaveBeenCalledOnce();
  });

  it("passes onSuccess to useFaucet hook", () => {
    const onSuccess = vi.fn();
    mockUseFaucet.mockReturnValue(makeFaucetHook());
    render(
      <FaucetModal isOpen={true} onClose={vi.fn()} onSuccess={onSuccess} />,
    );
    expect(mockUseFaucet).toHaveBeenCalledWith(onSuccess);
  });
});

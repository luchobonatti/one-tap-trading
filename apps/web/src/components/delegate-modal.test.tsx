import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { DelegateModal } from "@/components/delegate-modal";
import type { UseSessionKeyReturn } from "@/hooks/use-session-key";

function makeSession(
  overrides: Partial<UseSessionKeyReturn>,
): UseSessionKeyReturn {
  return {
    status: "idle",
    error: undefined,
    expiresAt: undefined,
    delegate: vi.fn(),
    revoke: vi.fn(),
    isReady: false,
    ...overrides,
  };
}

afterEach(() => cleanup());

describe("DelegateModal", () => {
  it("renders nothing when session is ready", () => {
    const { container } = render(
      <DelegateModal session={makeSession({ status: "ready", isReady: true })} />,
    );
    expect(container.firstChild).toBeNull();
  });

  it("shows Enable Trading button when idle", () => {
    render(<DelegateModal session={makeSession({ status: "idle" })} />);
    expect(
      screen.getByRole("button", { name: /enable trading/i }),
    ).toBeInTheDocument();
  });

  it("shows spend limit input", () => {
    render(<DelegateModal session={makeSession({ status: "idle" })} />);
    expect(screen.getByLabelText(/spend limit/i)).toBeInTheDocument();
  });

  it("calls delegate() with spend limit when button clicked", () => {
    const delegate = vi.fn().mockResolvedValue(undefined);
    render(
      <DelegateModal session={makeSession({ status: "idle", delegate })} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /enable trading/i }));
    expect(delegate).toHaveBeenCalledWith("100");
  });

  it("shows progress indicator during delegating state", () => {
    render(<DelegateModal session={makeSession({ status: "delegating" })} />);
    expect(screen.getByText(/approve with your passkey/i)).toBeInTheDocument();
  });

  it("shows Renew Session button when session expired", () => {
    render(<DelegateModal session={makeSession({ status: "expired" })} />);
    expect(
      screen.getByRole("button", { name: /renew session/i }),
    ).toBeInTheDocument();
  });

  it("shows error message when status is error", () => {
    render(
      <DelegateModal
        session={makeSession({
          status: "error",
          error: "User cancelled the passkey prompt",
        })}
      />,
    );
    expect(
      screen.getByText("User cancelled the passkey prompt"),
    ).toBeInTheDocument();
  });

  it("does not show error paragraph when error is undefined", () => {
    render(
      <DelegateModal
        session={makeSession({ status: "error", error: undefined })}
      />,
    );
    expect(
      screen.queryByText(/user cancelled/i),
    ).not.toBeInTheDocument();
  });
});

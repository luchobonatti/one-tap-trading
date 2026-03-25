import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { SignupModal } from "@/components/signup-modal";
import type { UseSmartAccountReturn } from "@/hooks/use-smart-account";

function makeAccount(
  overrides: Partial<UseSmartAccountReturn>,
): UseSmartAccountReturn {
  return {
    address: undefined,
    status: "idle",
    error: undefined,
    create: vi.fn(),
    isReady: false,
    ...overrides,
  };
}

afterEach(() => cleanup());

describe("SignupModal", () => {
  it("renders nothing when status is ready", () => {
    const { container } = render(
      <SignupModal
        account={makeAccount({ status: "ready", isReady: true })}
      />,
    );
    expect(container.firstChild).toBeNull();
  });

  it("shows Create Account button when idle", () => {
    render(<SignupModal account={makeAccount({ status: "idle" })} />);
    expect(
      screen.getByRole("button", { name: /create account/i }),
    ).toBeInTheDocument();
  });

  it("calls create() when button is clicked", () => {
    const create = vi.fn().mockResolvedValue(undefined);
    render(<SignupModal account={makeAccount({ status: "idle", create })} />);
    fireEvent.click(screen.getByRole("button", { name: /create account/i }));
    expect(create).toHaveBeenCalledOnce();
  });

  it("shows loading indicator during creating state", () => {
    render(<SignupModal account={makeAccount({ status: "creating" })} />);
    expect(screen.getByText(/follow the passkey prompt/i)).toBeInTheDocument();
  });

  it("shows error message and retry button on error", () => {
    render(
      <SignupModal
        account={makeAccount({
          status: "error",
          error: "Passkey registration cancelled",
        })}
      />,
    );
    expect(
      screen.getByText("Passkey registration cancelled"),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /try again/i }),
    ).toBeInTheDocument();
  });

  it("shows generic message when error is undefined", () => {
    render(
      <SignupModal
        account={makeAccount({ status: "error", error: undefined })}
      />,
    );
    expect(screen.getByText(/something went wrong/i)).toBeInTheDocument();
  });
});

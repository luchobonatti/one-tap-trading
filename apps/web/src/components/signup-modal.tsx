"use client";

import type { UseSmartAccountReturn } from "@/hooks/use-smart-account";

type Props = {
  account: UseSmartAccountReturn;
};

export function SignupModal({ account }: Props) {
  const { status, error, create } = account;

  if (status === "ready") return null;

  return (
    <div className="fixed inset-0 flex items-center justify-center bg-black/80 backdrop-blur-sm">
      <div className="w-full max-w-sm rounded-2xl border border-white/10 bg-zinc-900 p-8 shadow-2xl">
        <h2 className="text-2xl font-bold text-white">One Tap Trading</h2>
        <p className="mt-2 text-sm text-zinc-400">
          Create a smart account with your device passkey. No seed phrases, no
          wallet app required.
        </p>

        <div className="mt-8">
          {status === "idle" && (
            <button
              type="button"
              onClick={() => void create()}
              className="w-full rounded-xl bg-white px-4 py-3 text-sm font-semibold text-black transition hover:bg-zinc-200 active:scale-95"
            >
              Create Account with Passkey
            </button>
          )}

          {status === "loading" && (
            <div className="text-center text-sm text-zinc-500">
              Checking for existing account…
            </div>
          )}

          {status === "creating" && (
            <div className="space-y-3">
              <div className="text-center text-sm text-zinc-400">
                Follow the passkey prompt on your device…
              </div>
              <div className="h-1 w-full overflow-hidden rounded-full bg-zinc-800">
                <div className="h-full w-1/2 animate-pulse rounded-full bg-white/40" />
              </div>
            </div>
          )}

          {status === "error" && (
            <div className="space-y-4">
              <p className="rounded-lg bg-red-500/10 px-3 py-2 text-sm text-red-400">
                {error ?? "Something went wrong. Please try again."}
              </p>
              <button
                type="button"
                onClick={() => void create()}
                className="w-full rounded-xl bg-white px-4 py-3 text-sm font-semibold text-black transition hover:bg-zinc-200 active:scale-95"
              >
                Try Again
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

"use client";

import { useSmartAccount } from "@/hooks/use-smart-account";
import { useSessionKey } from "@/hooks/use-session-key";
import { useTrade } from "@/hooks/use-trade";
import { SignupModal } from "@/components/signup-modal";
import { DelegateModal } from "@/components/delegate-modal";
import { TradingGrid } from "@/components/trading-grid";

export function TradingApp() {
  const account = useSmartAccount();
  const session = useSessionKey(account.isReady);
  const trade = useTrade(account.address);

  const showGrid = account.isReady && session.isReady;

  return (
    <>
      <SignupModal account={account} />
      {account.isReady && !session.isReady && (
        <DelegateModal session={session} />
      )}
      {showGrid && (
        <div className="flex flex-col items-center gap-4">
          <TradingGrid trade={trade} />
          <p className="text-xs text-zinc-600">
            Session expires {session.expiresAt?.toLocaleTimeString()} ·{" "}
            <button
              type="button"
              className="underline"
              onClick={() => session.revoke()}
            >
              revoke
            </button>
          </p>
        </div>
      )}
    </>
  );
}

"use client";

import { useSmartAccount } from "@/hooks/use-smart-account";
import { useSessionKey } from "@/hooks/use-session-key";
import { SignupModal } from "@/components/signup-modal";
import { DelegateModal } from "@/components/delegate-modal";

export function TradingApp() {
  const account = useSmartAccount();
  const session = useSessionKey(account.isReady);

  return (
    <>
      <SignupModal account={account} />
      {account.isReady && !session.isReady && (
        <DelegateModal session={session} />
      )}
      {account.isReady && session.isReady && (
        <div className="flex flex-col items-center gap-2">
          <p className="text-sm text-zinc-400">Ready to trade</p>
          <p className="font-mono text-xs text-zinc-600">{account.address}</p>
          <p className="text-xs text-zinc-600">
            Session expires {session.expiresAt?.toLocaleTimeString()}
          </p>
        </div>
      )}
    </>
  );
}

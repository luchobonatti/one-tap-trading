"use client";

import { useSmartAccount } from "@/hooks/use-smart-account";
import { SignupModal } from "@/components/signup-modal";

export function TradingApp() {
  const account = useSmartAccount();

  return (
    <>
      <SignupModal account={account} />
      {account.isReady && (
        <div className="flex flex-col items-center gap-2">
          <p className="text-sm text-zinc-400">Smart account ready</p>
          <p className="font-mono text-xs text-zinc-600">{account.address}</p>
        </div>
      )}
    </>
  );
}

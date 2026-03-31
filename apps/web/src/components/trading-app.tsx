"use client";

import { useState, useRef, useCallback } from "react";
import dynamic from "next/dynamic";
import { useSmartAccount } from "@/hooks/use-smart-account";
import { useSessionKey } from "@/hooks/use-session-key";
import { usePricePolling } from "@/hooks/use-price-polling";
import { LandingPage } from "@/components/landing-page";
import { DelegateModal } from "@/components/delegate-modal";
import { FuelGauge } from "@/components/fuel-gauge";
import { LongShortButtons } from "@/components/long-short-buttons";
import { PositionsPanel } from "@/components/positions-panel";
import { TradeHistory, useTradeHistory } from "@/components/trade-history";
import { openTrade, waitForOp } from "@/lib/trading/submit";
import { useUsdcBalance } from "@/hooks/use-usdc-balance";
import { AccountHeader } from "@/components/account-header";
import type { GameCanvasHandle } from "@/components/game-canvas";

const GameCanvas = dynamic(
  () => import("@/components/game-canvas").then((m) => m.GameCanvas),
  { ssr: false },
);

const DEFAULT_LEVERAGE = 5;

export function TradingApp() {
  const account = useSmartAccount();
  const session = useSessionKey(account.isReady);
  const { priceRef, price, stale } = usePricePolling(500, account.isReady);
  const { entries, addEntry } = useTradeHistory();
  const { formatted: usdcBalance, refresh } = useUsdcBalance(account.address);
  const canvasRef = useRef<GameCanvasHandle>(null);

  const [leverage, setLeverage] = useState(DEFAULT_LEVERAGE);
  const [tradeStatus, setTradeStatus] = useState<"idle" | "pending">("idle");
  const [tradeError, setTradeError] = useState<string | undefined>(undefined);

  const isReady = account.isReady && session.isReady;
  const isPending = tradeStatus === "pending";

  const handleTrade = useCallback(
    async (direction: "long" | "short") => {
      if (account.address === undefined || isPending) return;
      setTradeStatus("pending");
      setTradeError(undefined);
      canvasRef.current?.triggerWarp();

      try {
        const opHash = await openTrade({
          isLong: direction === "long",
          collateral: 1_000_000n,
          leverage: BigInt(leverage),
        });
        await waitForOp(opHash);
        canvasRef.current?.triggerWin();
      } catch (err) {
        setTradeError(err instanceof Error ? err.message : "Trade failed");
        canvasRef.current?.triggerLoss();
      } finally {
        setTradeStatus("idle");
      }
    },
    [account.address, isPending, leverage],
  );

  if (!account.isReady) {
    return (
      <LandingPage
        onLaunch={account.create}
        loading={account.status === "loading" || account.status === "creating"}
        {...(account.error !== undefined ? { error: account.error } : {})}
      />
    );
  }

  return (
    <div className="relative flex h-screen w-full flex-col overflow-hidden bg-[var(--color-space-bg)]">
      <div className="absolute inset-0">
        <GameCanvas ref={canvasRef} priceRef={priceRef} />
      </div>

      {!session.isReady && (
        <DelegateModal session={session} />
      )}

      {isReady && account.address !== undefined && (
        <AccountHeader
          address={account.address}
          usdcBalance={usdcBalance}
          price={price}
          stale={stale}
          refresh={refresh}
        />
      )}

      {isReady && (
        <>
          <div className="absolute bottom-0 left-0 right-0 z-20 border-t border-white/5 bg-[var(--color-space-bg)]/90 backdrop-blur-sm">
            <div className="flex items-center justify-center gap-4 px-4 py-3">
              <LongShortButtons disabled={isPending} onClick={(dir) => void handleTrade(dir)} />

              <div className="h-6 w-px bg-white/10" />

              <FuelGauge value={leverage} onChange={setLeverage} />

              <div className="h-6 w-px bg-white/10" />

              <p className="font-mono text-[10px] text-[var(--color-star-dim)]">
                {session.expiresAt?.toLocaleTimeString()} ·{" "}
                <button
                  type="button"
                  className="underline transition hover:text-white"
                  onClick={() => session.revoke()}
                >
                  revoke
                </button>
              </p>
            </div>

            {tradeError !== undefined && (
              <p className="px-4 pb-2 text-center font-mono text-[10px] text-[var(--color-neon-red)]">
                {tradeError}
              </p>
            )}
          </div>

          <div className="absolute bottom-16 left-1/2 z-10 w-full max-w-sm -translate-x-1/2 space-y-2 px-4">
            <PositionsPanel
              accountAddress={account.address}
              priceRef={priceRef}
              onTradeClose={addEntry}
            />
            <TradeHistory entries={entries} />
          </div>
        </>
      )}
    </div>
  );
}

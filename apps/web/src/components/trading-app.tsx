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
        <div className="relative z-10 flex h-full flex-col items-center justify-end gap-4 pb-8 pt-10">

          <div className="flex flex-col items-center gap-6 rounded-2xl border border-white/10 bg-[var(--color-space-bg)]/80 p-6 backdrop-blur-sm">
            <FuelGauge value={leverage} onChange={setLeverage} />
            <LongShortButtons disabled={isPending} onClick={(dir) => void handleTrade(dir)} />

            {tradeError !== undefined && (
              <p className="text-xs text-[var(--color-neon-red)]">{tradeError}</p>
            )}

            <p className="text-xs text-[var(--color-star-dim)]">
              Session expires {session.expiresAt?.toLocaleTimeString()} ·{" "}
              <button
                type="button"
                className="underline hover:text-white transition"
                onClick={() => session.revoke()}
              >
                revoke
              </button>
            </p>
          </div>

          <div className="w-full max-w-sm space-y-2 px-4">
            <PositionsPanel
              accountAddress={account.address}
              priceRef={priceRef}
              onTradeClose={addEntry}
            />
            <TradeHistory entries={entries} />
          </div>
        </div>
      )}
    </div>
  );
}

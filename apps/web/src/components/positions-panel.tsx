"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import type { Address } from "viem";
import { publicClient } from "@/lib/aa/client";
import { perpEngineAbi, perpEngineAddress } from "@one-tap/shared-types";
import { calculatePnL } from "@/lib/trading/pnl";
import { closeTrade, waitForOp } from "@/lib/trading/submit";

const PERP_ENGINE = perpEngineAddress[6343];
const POLL_INTERVAL_MS = 3000;

type Position = {
  id: bigint;
  isLong: boolean;
  collateral: bigint;
  leverage: bigint;
  entryPrice: bigint;
  isOpen: boolean;
};

type ClosedEntry = {
  side: "long" | "short";
  leverage: number;
  entryPrice: number;
  exitPrice: number;
  pnl: number;
};

type Props = {
  accountAddress: Address | undefined;
  priceRef: React.RefObject<bigint>;
  onTradeClose?: (entry: ClosedEntry) => void;
};

export function PositionsPanel({ accountAddress, priceRef, onTradeClose }: Props) {
  const [positions, setPositions] = useState<Position[]>([]);
  const pnlRefs = useRef<Map<string, HTMLElement>>(new Map());

  const fetchPositions = useCallback(async () => {
    if (accountAddress === undefined) return;
    try {
      const nextId = await publicClient.readContract({
        abi: perpEngineAbi,
        address: PERP_ENGINE,
        functionName: "nextPositionId",
      });

      const count = Math.max(0, Number(nextId) - 1);
      const candidates = Array.from({ length: count }, (_, i) => BigInt(i + 1));

      const results = await Promise.allSettled(
        candidates.map((id) =>
          publicClient.readContract({
            abi: perpEngineAbi,
            address: PERP_ENGINE,
            functionName: "getPosition",
            args: [id],
          }),
        ),
      );

      const owned: Position[] = [];
      for (let i = 0; i < results.length; i++) {
        const result = results[i];
        if (result === undefined || result.status !== "fulfilled") continue;
        const pos = result.value;
        if (
          pos.trader.toLowerCase() !== accountAddress.toLowerCase() ||
          !pos.isOpen
        ) continue;
        owned.push({
          id: BigInt(i + 1),
          isLong: pos.isLong,
          collateral: pos.collateral,
          leverage: pos.leverage,
          entryPrice: pos.entryPrice,
          isOpen: pos.isOpen,
        });
      }
      setPositions(owned);
    } catch (err) {
      console.error("Failed to fetch positions:", err);
    }
  }, [accountAddress]);

  useEffect(() => {
    void fetchPositions();
    const id = setInterval(() => void fetchPositions(), POLL_INTERVAL_MS);
    return () => clearInterval(id);
  }, [fetchPositions]);

  useEffect(() => {
    const updatePnl = () => {
      const price = priceRef.current;
      if (price === 0n) return;
      for (const pos of positions) {
        const el = pnlRefs.current.get(String(pos.id));
        if (el === undefined) continue;
        const pnl = calculatePnL(pos.entryPrice, price, pos.collateral, pos.leverage, pos.isLong);
        const usdc = Number(pnl) / 1_000_000;
        el.textContent = `${usdc >= 0 ? "+" : ""}${usdc.toFixed(2)} USDC`;
        el.style.color = usdc >= 0 ? "var(--color-neon-green)" : "var(--color-neon-red)";
      }
    };

    const id = setInterval(updatePnl, 100);
    return () => clearInterval(id);
  }, [positions, priceRef]);

  const handleClose = useCallback(
    async (pos: Position) => {
      if (accountAddress === undefined) return;
      try {
        const opHash = await closeTrade({ positionId: pos.id });
        await waitForOp(opHash);
        const exitPriceBigInt = priceRef.current;
        const pnlRaw = calculatePnL(
          pos.entryPrice,
          exitPriceBigInt,
          pos.collateral,
          pos.leverage,
          pos.isLong,
        );
        onTradeClose?.({
          side: pos.isLong ? "long" : "short",
          leverage: Number(pos.leverage),
          entryPrice: Number(pos.entryPrice) / 1e8,
          exitPrice: Number(exitPriceBigInt) / 1e8,
          pnl: Number(pnlRaw) / 1_000_000,
        });
        await fetchPositions();
      } catch (err) {
        console.error("Failed to close position:", err);
      }
    },
    [accountAddress, priceRef, fetchPositions, onTradeClose],
  );

  if (positions.length === 0) {
    return (
      <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center text-sm text-[var(--color-star-dim)]">
        No open positions
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <h2 className="text-xs uppercase tracking-widest text-[var(--color-star-dim)]">
        Open Positions
      </h2>
      {positions.map((pos) => (
        <div
          key={String(pos.id)}
          className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 px-4 py-3"
        >
          <div className="flex flex-col gap-0.5">
            <span
              className={[
                "text-sm font-bold",
                pos.isLong ? "text-[var(--color-neon-green)]" : "text-[var(--color-neon-red)]",
              ].join(" ")}
            >
              {pos.isLong ? "▲ LONG" : "▼ SHORT"} {String(pos.leverage)}×
            </span>
            <span className="text-xs text-[var(--color-star-dim)]">
              Entry: ${(Number(pos.entryPrice) / 1e8).toFixed(2)}
            </span>
            <span
              ref={(el) => {
                if (el !== null) pnlRefs.current.set(String(pos.id), el);
                else pnlRefs.current.delete(String(pos.id));
              }}
              className="font-mono text-sm"
            >
              PnL: —
            </span>
          </div>
          <button
            type="button"
            onClick={() => void handleClose(pos)}
            className="rounded-lg border border-white/20 px-3 py-1 text-xs text-white/60 hover:border-white/40 hover:text-white transition"
          >
            Close
          </button>
        </div>
      ))}
    </div>
  );
}

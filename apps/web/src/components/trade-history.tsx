"use client";

import { useState, useCallback } from "react";

export type HistoryEntry = {
  id: string;
  side: "long" | "short";
  leverage: number;
  entryPrice: number;
  exitPrice: number;
  pnl: number;
};

type Props = {
  entries: HistoryEntry[];
};

export function TradeHistory({ entries }: Props) {
  if (entries.length === 0) {
    return (
      <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center text-sm text-[var(--color-star-dim)]">
        No trade history
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <h2 className="text-xs uppercase tracking-widest text-[var(--color-star-dim)]">
        History
      </h2>
      <div className="max-h-48 overflow-y-auto flex flex-col gap-1">
        {entries.map((entry) => (
          <div
            key={entry.id}
            className="flex items-center justify-between rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-xs"
          >
            <span
              className={
                entry.side === "long"
                  ? "text-[var(--color-neon-green)]"
                  : "text-[var(--color-neon-red)]"
              }
            >
              {entry.side === "long" ? "▲" : "▼"} {entry.leverage}×
            </span>
            <span className="text-[var(--color-star-dim)]">
              ${entry.entryPrice.toFixed(2)} → ${entry.exitPrice.toFixed(2)}
            </span>
            <span
              className={
                entry.pnl >= 0
                  ? "text-[var(--color-neon-green)] font-semibold"
                  : "text-[var(--color-neon-red)] font-semibold"
              }
            >
              {entry.pnl >= 0 ? "+" : ""}
              {entry.pnl.toFixed(2)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

export function useTradeHistory() {
  const [entries, setEntries] = useState<HistoryEntry[]>([]);

  const addEntry = useCallback((entry: Omit<HistoryEntry, "id">) => {
    setEntries((prev) => [
      { ...entry, id: `${Date.now()}-${Math.random()}` },
      ...prev,
    ]);
  }, []);

  return { entries, addEntry };
}

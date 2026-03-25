"use client";

import type { UseTradeReturn } from "@/hooks/use-trade";

type Props = {
  trade: UseTradeReturn;
};

type CellConfig = {
  isLong: boolean;
  leverage: bigint;
};

const CELLS: CellConfig[] = [
  { isLong: true, leverage: 2n },
  { isLong: true, leverage: 5n },
  { isLong: true, leverage: 10n },
  { isLong: true, leverage: 20n },
  { isLong: false, leverage: 2n },
  { isLong: false, leverage: 5n },
  { isLong: false, leverage: 10n },
  { isLong: false, leverage: 20n },
];

function cellLabel(cell: CellConfig): string {
  return `${cell.isLong ? "LONG" : "SHORT"} ${cell.leverage}×`;
}

export function TradingGrid({ trade }: Props) {
  const isPending = trade.status === "pending";
  const isConfirmed = trade.status === "confirmed";
  const isFailed = trade.status === "failed";

  return (
    <div className="flex w-full max-w-sm flex-col gap-3">
      <div className="grid grid-cols-4 gap-1">
        {CELLS.map((cell) => {
          const isLongCell = cell.isLong;
          const baseClass = isLongCell
            ? "bg-emerald-900/60 hover:bg-emerald-700/80 border-emerald-600/40"
            : "bg-rose-900/60 hover:bg-rose-700/80 border-rose-600/40";

          return (
            <button
              key={`${cell.isLong ? "long" : "short"}-${cell.leverage}`}
              type="button"
              disabled={isPending}
              onClick={() => void trade.openPosition(cell.isLong, cell.leverage)}
              aria-label={cellLabel(cell)}
              className={`
                flex h-16 flex-col items-center justify-center rounded-lg border
                text-xs font-semibold transition
                disabled:cursor-not-allowed disabled:opacity-50
                active:scale-95
                ${baseClass}
              `}
            >
              <span className={isLongCell ? "text-emerald-300" : "text-rose-300"}>
                {isLongCell ? "▲" : "▼"}
              </span>
              <span className="mt-0.5 text-white/80">{cell.leverage}×</span>
            </button>
          );
        })}
      </div>

      {isPending && (
        <div className="rounded-lg border border-white/10 bg-zinc-900 px-4 py-3 text-center">
          <p className="text-sm text-zinc-400">Submitting trade…</p>
          {trade.pendingOpHash !== undefined && (
            <p className="mt-1 truncate font-mono text-xs text-zinc-600">
              {trade.pendingOpHash}
            </p>
          )}
        </div>
      )}

      {isConfirmed && (
        <div className="rounded-lg border border-emerald-500/30 bg-emerald-900/20 px-4 py-3 text-center">
          <p className="text-sm font-semibold text-emerald-400">
            Position opened ✓
          </p>
        </div>
      )}

      {isFailed && trade.error !== undefined && (
        <div className="rounded-lg border border-rose-500/30 bg-rose-900/20 px-4 py-3">
          <p className="text-sm text-rose-400">{trade.error}</p>
          <button
            type="button"
            onClick={() => trade.reset()}
            className="mt-2 text-xs text-zinc-400 underline"
          >
            Dismiss
          </button>
        </div>
      )}
    </div>
  );
}

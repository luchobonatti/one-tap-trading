"use client";

import { useId } from "react";

type Props = {
  value: number;
  onChange: (value: number) => void;
};

const MIN = 2;
const MAX = 30;

export function FuelGauge({ value, onChange }: Props) {
  const id = useId();
  const isMax = value === MAX;

  return (
    <div className="flex items-center gap-3">
      <label htmlFor={id} className="text-[10px] uppercase tracking-widest text-[var(--color-star-dim)]">
        Fuel
      </label>
      <input
        id={id}
        type="range"
        min={MIN}
        max={MAX}
        step={1}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="h-1.5 w-24 cursor-pointer appearance-none rounded-full accent-[var(--color-neon-cyan)]"
        aria-label={`Leverage ${value}x`}
      />
      <span
        className={[
          "font-mono text-sm font-bold tabular-nums",
          isMax
            ? "animate-pulse text-[var(--color-neon-orange)]"
            : "text-[var(--color-neon-cyan)]",
        ].join(" ")}
        aria-live="polite"
      >
        {value}×
      </span>
    </div>
  );
}

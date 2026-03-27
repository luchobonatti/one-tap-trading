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
    <div className="flex flex-col items-center gap-2">
      <label htmlFor={id} className="text-xs uppercase tracking-widest text-[var(--color-star-dim)]">
        Fuel
      </label>
      <span
        className={[
          "font-mono text-3xl font-bold tabular-nums",
          isMax
            ? "animate-pulse text-[var(--color-neon-orange)]"
            : "text-[var(--color-neon-cyan)]",
        ].join(" ")}
        aria-live="polite"
      >
        {value}×
      </span>
      <input
        id={id}
        type="range"
        min={MIN}
        max={MAX}
        step={1}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="h-2 w-40 cursor-pointer appearance-none rounded-full accent-[var(--color-neon-cyan)]"
        aria-label={`Leverage ${value}x`}
      />
    </div>
  );
}

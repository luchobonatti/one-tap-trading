"use client";

type Props = {
  disabled: boolean;
  onClick: (direction: "long" | "short") => void;
};

export function LongShortButtons({ disabled, onClick }: Props) {
  return (
    <div className="flex gap-2">
      <button
        type="button"
        disabled={disabled}
        onClick={() => onClick("long")}
        aria-label="Long"
        className={[
          "rounded-lg border px-4 py-2 font-mono text-xs font-bold uppercase tracking-widest transition active:scale-95",
          "border-[var(--color-neon-green)] text-[var(--color-neon-green)]",
          "shadow-[0_0_12px_var(--color-neon-green)/30]",
          "hover:bg-[var(--color-neon-green)]/10",
          "disabled:cursor-not-allowed disabled:opacity-40 disabled:shadow-none",
        ].join(" ")}
      >
        ▲ LONG
      </button>

      <button
        type="button"
        disabled={disabled}
        onClick={() => onClick("short")}
        aria-label="Short"
        className={[
          "rounded-lg border px-4 py-2 font-mono text-xs font-bold uppercase tracking-widest transition active:scale-95",
          "border-[var(--color-neon-red)] text-[var(--color-neon-red)]",
          "shadow-[0_0_12px_var(--color-neon-red)/30]",
          "hover:bg-[var(--color-neon-red)]/10",
          "disabled:cursor-not-allowed disabled:opacity-40 disabled:shadow-none",
        ].join(" ")}
      >
        ▼ SHORT
      </button>
    </div>
  );
}

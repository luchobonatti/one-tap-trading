"use client";

type Props = {
  disabled: boolean;
  onClick: (direction: "long" | "short") => void;
};

export function LongShortButtons({ disabled, onClick }: Props) {
  return (
    <div className="flex gap-4">
      <button
        type="button"
        disabled={disabled}
        onClick={() => onClick("long")}
        aria-label="Long"
        className={[
          "flex h-20 w-36 flex-col items-center justify-center rounded-xl border-2 font-bold",
          "text-lg uppercase tracking-widest transition active:scale-95",
          "border-[var(--color-neon-green)] text-[var(--color-neon-green)]",
          "shadow-[0_0_16px_var(--color-neon-green)]",
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
          "flex h-20 w-36 flex-col items-center justify-center rounded-xl border-2 font-bold",
          "text-lg uppercase tracking-widest transition active:scale-95",
          "border-[var(--color-neon-red)] text-[var(--color-neon-red)]",
          "shadow-[0_0_16px_var(--color-neon-red)]",
          "hover:bg-[var(--color-neon-red)]/10",
          "disabled:cursor-not-allowed disabled:opacity-40 disabled:shadow-none",
        ].join(" ")}
      >
        ▼ SHORT
      </button>
    </div>
  );
}

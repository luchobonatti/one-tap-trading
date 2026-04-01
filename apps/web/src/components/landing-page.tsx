"use client";

type Props = {
  onLaunch: () => Promise<void>;
  loading?: boolean;
  error?: string;
};

const FEATURES = [
  { icon: "⚡", title: "Zero popups", desc: "Sign once, trade forever" },
  { icon: "🔥", title: "10ms blocks", desc: "MegaETH speed" },
  { icon: "🚀", title: "1-tap leverage", desc: "Up to 20× fuel" },
] as const;

type Star = { id: string; left: string; top: string; size: number; opacity: number; delay: string };

function buildStars(count: number): Star[] {
  return Array.from({ length: count }, (_, i) => {
    const left = `${((i * 7919) % 1000) / 10}%`;
    const top = `${((i * 6271) % 1000) / 10}%`;
    return {
      id: `${left}-${top}`,
      left,
      top,
      size: i % 4 === 0 ? 2 : 1,
      opacity: 0.25 + ((i * 3) % 7) / 14,
      delay: `${(i % 7) * 0.5}s`,
    };
  });
}

const STARS = buildStars(140);

export function LandingPage({ onLaunch, loading = false, error }: Props) {
  return (
    <div className="relative flex h-screen w-full flex-col items-center justify-center overflow-hidden bg-[var(--color-space-bg)]">
      <div className="pointer-events-none absolute inset-0" aria-hidden="true">
        {STARS.map((s) => (
          <div
            key={s.id}
            className="absolute animate-pulse rounded-full bg-white"
            style={{
              left: s.left,
              top: s.top,
              width: `${s.size}px`,
              height: `${s.size}px`,
              opacity: s.opacity,
              animationDelay: s.delay,
              animationDuration: "3s",
            }}
          />
        ))}
      </div>

      <div
        className="pointer-events-none absolute"
        style={{ animation: "ship-flyby 9s linear infinite", top: "22%" }}
        aria-hidden="true"
      >
        <svg role="presentation" width="40" height="28" viewBox="0 0 40 28" fill="none">
          <polygon
            points="0,24 36,12 0,0 10,12"
            fill="var(--color-neon-cyan)"
            style={{ filter: "drop-shadow(0 0 6px var(--color-neon-cyan))" }}
          />
        </svg>
      </div>

      <div className="relative z-10 flex flex-col items-center gap-6 px-8 text-center">
        <h1
          className="font-mono text-4xl font-bold uppercase tracking-widest text-[var(--color-neon-cyan)] sm:text-5xl md:text-6xl"
          style={{
            textShadow:
              "0 0 20px var(--color-neon-cyan), 0 0 60px var(--color-neon-cyan)",
          }}
        >
          ONE TAP TRADING
        </h1>

        <p className="text-sm tracking-widest text-[var(--color-star-dim)] sm:text-base">
          Trade perpetuals at the speed of light
        </p>

        {error !== undefined && (
          <p className="rounded-lg border border-[var(--color-neon-red)]/40 bg-[var(--color-neon-red)]/10 px-4 py-2 text-sm text-[var(--color-neon-red)]">
            {error}
          </p>
        )}

        <button
          type="button"
          disabled={loading}
          onClick={() => void onLaunch()}
          className={[
            "rounded-xl border-2 px-12 py-4 font-mono text-xl font-bold uppercase tracking-widest",
            "transition-all duration-200 active:scale-95",
            loading
              ? "cursor-not-allowed border-[var(--color-star-dim)] text-[var(--color-star-dim)]"
              : [
                  "border-[var(--color-neon-green)] text-[var(--color-neon-green)]",
                  "shadow-[0_0_24px_var(--color-neon-green)]",
                  "hover:bg-[var(--color-neon-green)]/10 hover:shadow-[0_0_40px_var(--color-neon-green)]",
                ].join(" "),
          ].join(" ")}
        >
          {loading ? "LAUNCHING…" : "LAUNCH"}
        </button>
      </div>

      <div className="absolute bottom-10 flex flex-wrap justify-center gap-4 px-8">
        {FEATURES.map((f) => (
          <div
            key={f.title}
            className="flex flex-col items-center gap-1 rounded-xl border border-[var(--color-neon-cyan)]/20 bg-[var(--color-space-bg)]/80 px-6 py-4 text-center backdrop-blur-sm"
          >
            <span className="text-2xl" aria-hidden="true">
              {f.icon}
            </span>
            <span className="text-sm font-bold text-[var(--color-ui-text)]">{f.title}</span>
            <span className="text-xs text-[var(--color-star-dim)]">{f.desc}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

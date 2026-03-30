"use client";

import { useState, useCallback, useRef, useEffect } from "react";
import type { Address } from "viem";
import { megaEthCarrot } from "@/lib/aa/chain";

const PRICE_DECIMALS = 8;

type Props = {
  address: Address;
  usdcBalance: string;
  price: bigint;
  stale: boolean;
};

function formatUsdPrice(price: bigint): string {
  return (Number(price) / 10 ** PRICE_DECIMALS).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function truncate(addr: Address): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function AccountHeader({ address, usdcBalance, price, stale }: Props) {
  const [copied, setCopied] = useState(false);
  const [qrOpen, setQrOpen] = useState(false);
  const qrRef = useRef<HTMLDivElement>(null);

  const prevPriceRef = useRef(price);
  const [direction, setDirection] = useState<"up" | "down" | "flat">("flat");

  useEffect(() => {
    if (price === prevPriceRef.current) return;
    setDirection(price > prevPriceRef.current ? "up" : "down");
    prevPriceRef.current = price;
  }, [price]);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (qrRef.current !== null && !qrRef.current.contains(e.target as Node)) {
        setQrOpen(false);
      }
    }
    if (qrOpen) document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [qrOpen]);

  const copyAddress = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(address);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      /* clipboard unavailable (non-https or permission denied) */
    }
  }, [address]);

  const priceColor =
    direction === "up"
      ? "text-[var(--color-neon-green)]"
      : direction === "down"
        ? "text-[var(--color-neon-red)]"
        : "text-[var(--color-neon-cyan)]";

  const arrow = direction === "up" ? "▲" : direction === "down" ? "▼" : "";

  return (
    <div className="absolute top-0 left-0 right-0 z-20 flex items-center justify-between gap-3 border-b border-white/5 bg-[var(--color-space-bg)]/90 px-4 py-2 backdrop-blur-sm">
      <div className="flex items-center gap-1.5 font-mono text-sm">
        <span className="text-[10px] text-[var(--color-star-dim)] uppercase tracking-widest">ETH</span>
        <span className={priceColor}>
          ${formatUsdPrice(price)}
          {arrow !== "" && <span className="ml-0.5 text-[10px]">{arrow}</span>}
        </span>
        {stale && (
          <span className="text-[10px] text-[var(--color-neon-orange)] border border-[var(--color-neon-orange)]/30 rounded-full px-1.5">
            stale
          </span>
        )}
      </div>

      <div className="flex items-center gap-2">
        <span className="hidden sm:flex items-center gap-1 rounded-full border border-[var(--color-neon-orange)]/30 px-2 py-0.5 text-[10px] text-[var(--color-neon-orange)]">
          <span className="h-1.5 w-1.5 rounded-full bg-[var(--color-neon-orange)] animate-pulse" />
          CARROT
        </span>

        <span className="font-mono text-xs text-[var(--color-neon-cyan)]">
          {usdcBalance} USDC
        </span>

        <button
          type="button"
          onClick={() => void copyAddress()}
          className="rounded border border-white/10 px-2 py-0.5 font-mono text-xs text-[var(--color-star-dim)] transition hover:border-white/30 hover:text-white"
        >
          {copied ? "Copied!" : truncate(address)}
        </button>

        <div className="relative" ref={qrRef}>
          <button
            type="button"
            onClick={() => setQrOpen((v) => !v)}
            aria-label="Show QR code"
            className="rounded border border-white/10 px-2 py-0.5 text-xs text-[var(--color-star-dim)] transition hover:border-white/30 hover:text-white"
          >
            ⊞
          </button>

          {qrOpen && (
            <div className="absolute right-0 top-8 z-30 w-56 rounded-xl border border-white/10 bg-[var(--color-space-bg)] p-4 shadow-2xl">
              <p className="mb-2 break-all font-mono text-[10px] leading-relaxed text-[var(--color-star-dim)]">
                {address}
              </p>
              <a
                href={`${megaEthCarrot.blockExplorers.default.url}/address/${address}`}
                target="_blank"
                rel="noreferrer"
                className="mb-3 block text-center text-[10px] text-[var(--color-neon-cyan)] hover:underline"
              >
                View on explorer ↗
              </a>
              <img
                src={`https://api.qrserver.com/v1/create-qr-code/?data=${address}&size=200x200&color=00FFFF&bgcolor=030712&margin=8`}
                alt={`QR code — ${address}`}
                width={200}
                height={200}
                className="w-full rounded-lg"
              />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

import { TradingApp } from "@/components/trading-app";

export default function HomePage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-black text-white">
      <h1 className="text-4xl font-bold">One Tap Trading</h1>
      <p className="mt-4 text-lg text-gray-400">
        Gamified perpetual futures on MegaETH
      </p>
      <TradingApp />
    </main>
  );
}

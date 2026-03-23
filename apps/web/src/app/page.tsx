import { perpEngineAbi, perpEngineAddress } from "@one-tap/shared-types";

export default function HomePage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-black text-white">
      <h1 className="text-4xl font-bold">One Tap Trading</h1>
      <p className="mt-4 text-lg text-gray-400">
        Gamified perpetual futures on MegaETH
      </p>
      <p className="mt-2 text-sm text-gray-600">
        {perpEngineAbi.length} contract functions — PerpEngine{" "}
        {perpEngineAddress[6343]}
      </p>
    </main>
  );
}

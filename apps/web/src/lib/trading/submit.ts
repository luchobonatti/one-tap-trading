"use client";

import { encodeFunctionData, http } from "viem";
import type { Hex } from "viem";
import { createBundlerClient } from "viem/account-abstraction";
import {
  perpEngineAbi,
  perpEngineAddress,
  priceOracleAbi,
  priceOracleAddress,
} from "@one-tap/shared-types";
import { megaEthCarrot } from "@/lib/aa/chain";
import { publicClient } from "@/lib/aa/client";
import { getSmartAccountClient } from "@/lib/aa/account";
import { loadSessionKey, isSessionExpired } from "@/lib/aa/session-key";

if (!process.env.NEXT_PUBLIC_BUNDLER_RPC_URL) {
  throw new Error(
    "NEXT_PUBLIC_BUNDLER_RPC_URL is not set — create a project at https://dashboard.zerodev.app",
  );
}
const BUNDLER_RPC_URL = process.env.NEXT_PUBLIC_BUNDLER_RPC_URL;

const PERP_ENGINE = perpEngineAddress[6343];
const PRICE_ORACLE = priceOracleAddress[6343];

const bundlerClient = createBundlerClient({
  transport: http(BUNDLER_RPC_URL),
  chain: megaEthCarrot,
});

const MAX_DEVIATION_BPS = 200n;
const BPS_DENOM = 10_000n;
const DEADLINE_SECONDS = 60n;

export type PriceBounds = {
  expectedPrice: bigint;
  maxDeviation: bigint;
  deadline: bigint;
};

export type OpenTradeParams = {
  isLong: boolean;
  collateral: bigint;
  leverage: bigint;
};

export type CloseTradeParams = {
  positionId: bigint;
};

export async function getCurrentPriceBounds(): Promise<PriceBounds> {
  const [[price], { timestamp }] = await Promise.all([
    publicClient.readContract({
      abi: priceOracleAbi,
      address: PRICE_ORACLE,
      functionName: "getPrice",
    }),
    publicClient.getBlock(),
  ]);
  const maxDeviation = (price * MAX_DEVIATION_BPS) / BPS_DENOM;
  const deadline = timestamp + DEADLINE_SECONDS;
  return { expectedPrice: price, maxDeviation, deadline };
}

function requireActiveSession() {
  const session = loadSessionKey();
  if (session === null) throw new Error("No active session key — delegate first");
  if (isSessionExpired(session)) throw new Error("Session key expired — re-delegate to continue");
  return session;
}

export async function openTrade(params: OpenTradeParams): Promise<Hex> {
  requireActiveSession(); // gate: ensures approve+session are set; trade itself uses root validator
  const bounds = await getCurrentPriceBounds();

  const tradeCallData = encodeFunctionData({
    abi: perpEngineAbi,
    functionName: "openPosition",
    args: [params.isLong, params.collateral, params.leverage, bounds],
  });

  const client = await getSmartAccountClient();
  return client.sendUserOperation({
    calls: [{ to: PERP_ENGINE, data: tradeCallData, value: 0n }],
  });
}

export async function closeTrade(params: CloseTradeParams): Promise<Hex> {
  requireActiveSession();
  const bounds = await getCurrentPriceBounds();

  const tradeCallData = encodeFunctionData({
    abi: perpEngineAbi,
    functionName: "closePosition",
    args: [params.positionId, bounds],
  });

  const client = await getSmartAccountClient();
  return client.sendUserOperation({
    calls: [{ to: PERP_ENGINE, data: tradeCallData, value: 0n }],
  });
}

export async function waitForOp(opHash: Hex): Promise<void> {
  await bundlerClient.waitForUserOperationReceipt({ hash: opHash });
}

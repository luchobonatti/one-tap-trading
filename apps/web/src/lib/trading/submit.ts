"use client";

import { encodeFunctionData, http } from "viem";
import type { Address, Hex } from "viem";
import { createBundlerClient } from "viem/account-abstraction";
import {
  perpEngineAbi,
  perpEngineAddress,
  priceOracleAbi,
  priceOracleAddress,
} from "@one-tap/shared-types";
import { megaEthCarrot } from "@/lib/aa/chain";
import { publicClient } from "@/lib/aa/client";
import {
  buildKernelCallData,
  buildUserOp,
  signUserOp,
  submitUserOp,
} from "@/lib/aa/signer";
import { loadSessionKey, isSessionExpired } from "@/lib/aa/session-key";

const BUNDLER_RPC_URL =
  process.env.NEXT_PUBLIC_BUNDLER_RPC_URL ?? "http://localhost:4337";

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
  accountAddress: Address;
};

export type CloseTradeParams = {
  positionId: bigint;
  accountAddress: Address;
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
  const session = requireActiveSession();
  const bounds = await getCurrentPriceBounds();

  const innerCallData = encodeFunctionData({
    abi: perpEngineAbi,
    functionName: "openPosition",
    args: [params.isLong, params.collateral, params.leverage, bounds],
  });
  const kernelCallData = buildKernelCallData(PERP_ENGINE, innerCallData);

  const userOp = await buildUserOp(params.accountAddress, kernelCallData);
  const signedOp = await signUserOp(userOp, session);
  return submitUserOp(signedOp);
}

export async function closeTrade(params: CloseTradeParams): Promise<Hex> {
  const session = requireActiveSession();
  const bounds = await getCurrentPriceBounds();

  const innerCallData = encodeFunctionData({
    abi: perpEngineAbi,
    functionName: "closePosition",
    args: [params.positionId, bounds],
  });
  const kernelCallData = buildKernelCallData(PERP_ENGINE, innerCallData);

  const userOp = await buildUserOp(params.accountAddress, kernelCallData);
  const signedOp = await signUserOp(userOp, session);
  return submitUserOp(signedOp);
}

export async function waitForOp(opHash: Hex): Promise<void> {
  await bundlerClient.waitForUserOperationReceipt({ hash: opHash });
}

"use client";

import { encodeFunctionData, maxUint256, parseUnits, toHex } from "viem";
import type { Address, Hex } from "viem";
import {
  mockUsdcAbi,
  mockUsdcAddress,
  sessionKeyValidatorAbi,
  sessionKeyValidatorAddress,
  perpEngineAddress,
} from "@one-tap/shared-types";
import { getSmartAccountClient } from "@/lib/aa/account";

const INSTALL_MODULE_ABI = [
  {
    name: "installModule",
    type: "function",
    inputs: [
      { name: "moduleTypeId", type: "uint256" },
      { name: "module", type: "address" },
      { name: "initData", type: "bytes" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
] as const;

const STORAGE_KEY = "ott-session-key-v1";
const VALID_DURATION_SECONDS = 4 * 3600;

// Correct selectors derived from keccak256 of full function signatures.
export const OPEN_POSITION_SELECTOR =
  "0x47505d48" as Hex; // openPosition(bool,uint256,uint256,(uint256,uint256,uint256))
export const CLOSE_POSITION_SELECTOR =
  "0xd3499b84" as Hex; // closePosition(uint256,(uint256,uint256,uint256))

export type StoredSession = {
  privateKey: Hex;
  address: Address;
  validUntil: number;
};

function uint8ArrayToHex(arr: Uint8Array): Hex {
  return `0x${Array.from(arr, (b) => b.toString(16).padStart(2, "0")).join("")}` as Hex;
}

export async function generateSessionKey(): Promise<StoredSession> {
  const privateKeyBytes = crypto.getRandomValues(new Uint8Array(32));
  const privateKey = uint8ArrayToHex(privateKeyBytes);

  const { privateKeyToAccount } = await import("viem/accounts");
  const account = privateKeyToAccount(privateKey);

  const validUntil =
    Math.floor(Date.now() / 1000) + VALID_DURATION_SECONDS;
  const session: StoredSession = {
    privateKey,
    address: account.address,
    validUntil,
  };

  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  return session;
}

export async function delegateSessionKey(spendLimitUsdc: string): Promise<Hex> {
  const trimmed = spendLimitUsdc.trim();
  const amount = Number(trimmed);
  if (trimmed === "" || !Number.isFinite(amount) || amount <= 0) {
    throw new Error("Spend limit must be a positive number");
  }

  const session = await generateSessionKey();

  const approveCallData = encodeFunctionData({
    abi: mockUsdcAbi,
    functionName: "approve",
    args: [perpEngineAddress[6343], maxUint256],
  });

  const grantCallData = encodeFunctionData({
    abi: sessionKeyValidatorAbi,
    functionName: "grantSession",
    args: [
      session.address,
      session.validUntil,
      perpEngineAddress[6343],
      [OPEN_POSITION_SELECTOR, CLOSE_POSITION_SELECTOR],
      parseUnits(trimmed, 6),
    ],
  });

  const client = await getSmartAccountClient();
  const smartAccountAddress = client.account.address as Address;

  const installModuleCallData = encodeFunctionData({
    abi: INSTALL_MODULE_ABI,
    functionName: "installModule",
    args: [1n, sessionKeyValidatorAddress[6343], "0x"],
  });

  const opHash = await client.sendUserOperation({
    calls: [
      {
        to: mockUsdcAddress[6343],
        data: approveCallData,
        value: 0n,
      },
      {
        to: smartAccountAddress,
        data: installModuleCallData,
        value: 0n,
      },
      {
        to: sessionKeyValidatorAddress[6343],
        data: grantCallData,
        value: 0n,
      },
    ],
  });

  await client.waitForUserOperationReceipt({ hash: opHash });

  return opHash;
}

export function loadSessionKey(): StoredSession | null {
  const raw = sessionStorage.getItem(STORAGE_KEY);
  if (raw === null) return null;
  try {
    return JSON.parse(raw) as StoredSession;
  } catch {
    return null;
  }
}

export function hasSessionKey(): boolean {
  return sessionStorage.getItem(STORAGE_KEY) !== null;
}

export function isSessionExpired(session: StoredSession): boolean {
  return Math.floor(Date.now() / 1000) >= session.validUntil;
}

export function clearSessionKey(): void {
  sessionStorage.removeItem(STORAGE_KEY);
}

export function sessionExpiresAt(session: StoredSession): Date {
  return new Date(session.validUntil * 1000);
}

export { toHex };

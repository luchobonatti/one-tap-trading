"use client";

import { encodeFunctionData, parseUnits, toHex } from "viem";
import type { Address, Hex } from "viem";
import {
  sessionKeyValidatorAbi,
  sessionKeyValidatorAddress,
  perpEngineAddress,
} from "@one-tap/shared-types";
import { getSmartAccountClient } from "@/lib/aa/account";

const STORAGE_KEY = "ott-session-key-v1";
const VALID_DURATION_SECONDS = 4 * 3600;

export const OPEN_POSITION_SELECTOR = "0x5a6c3d4a" as Hex;
export const CLOSE_POSITION_SELECTOR = "0x5c36b186" as Hex;

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
  const session = await generateSessionKey();

  const callData = encodeFunctionData({
    abi: sessionKeyValidatorAbi,
    functionName: "grantSession",
    args: [
      session.address,
      session.validUntil,
      perpEngineAddress[6343],
      [OPEN_POSITION_SELECTOR, CLOSE_POSITION_SELECTOR],
      parseUnits(spendLimitUsdc, 6),
    ],
  });

  const client = await getSmartAccountClient();

  const opHash = await client.sendUserOperation({
    calls: [
      {
        to: sessionKeyValidatorAddress[6343],
        data: callData,
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

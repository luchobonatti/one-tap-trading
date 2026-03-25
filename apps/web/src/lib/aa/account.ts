"use client";

import {
  createAccountFromPasskey,
  loadAccountFromSerialized,
} from "@/lib/aa/client";
import {
  registerWebAuthnPasskey,
  storeWebAuthnKey,
  loadWebAuthnKey,
} from "@/lib/aa/passkey";
import type { Address } from "viem";

const VALIDATOR_STORAGE_KEY = "ott-validator-v1";

export type SmartAccountResult = {
  address: Address;
};

export async function createPasskeyAccount(
  username: string,
): Promise<SmartAccountResult> {
  const webAuthnKey = await registerWebAuthnPasskey(username);
  const { account, serializedValidator } =
    await createAccountFromPasskey(webAuthnKey);

  storeWebAuthnKey(webAuthnKey);
  localStorage.setItem(VALIDATOR_STORAGE_KEY, serializedValidator);

  return { address: account.address };
}

export async function loadPasskeyAccount(): Promise<SmartAccountResult | null> {
  const serialized = localStorage.getItem(VALIDATOR_STORAGE_KEY);
  if (serialized !== null) {
    try {
      const { account } = await loadAccountFromSerialized(serialized);
      return { address: account.address };
    } catch {
      localStorage.removeItem(VALIDATOR_STORAGE_KEY);
    }
  }

  const webAuthnKey = loadWebAuthnKey();
  if (webAuthnKey === null) return null;

  try {
    const { account, serializedValidator } =
      await createAccountFromPasskey(webAuthnKey);
    localStorage.setItem(VALIDATOR_STORAGE_KEY, serializedValidator);
    return { address: account.address };
  } catch {
    return null;
  }
}

export function clearPasskeyAccount(): void {
  localStorage.removeItem(VALIDATOR_STORAGE_KEY);
}

export function hasStoredAccount(): boolean {
  return localStorage.getItem(VALIDATOR_STORAGE_KEY) !== null;
}

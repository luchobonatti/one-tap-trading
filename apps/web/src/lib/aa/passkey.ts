"use client";

import { keccak256 } from "viem";
import { b64ToBytes, uint8ArrayToHexString } from "@zerodev/webauthn-key";
import type { WebAuthnKey } from "@zerodev/webauthn-key";

const STORAGE_KEY = "ott-passkey-v1";

function uint8ArrayToHex(arr: Uint8Array): string {
  return Array.from(arr, (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function registerWebAuthnPasskey(
  username: string,
): Promise<WebAuthnKey> {
  const challenge = crypto.getRandomValues(new Uint8Array(32));
  const userId = crypto.getRandomValues(new Uint8Array(16));
  const rpId = window.location.hostname;

  const raw = await navigator.credentials.create({
    publicKey: {
      challenge,
      rp: { id: rpId, name: "One Tap Trading" },
      user: { id: userId, name: username, displayName: username },
      pubKeyCredParams: [{ type: "public-key", alg: -7 }],
      authenticatorSelection: {
        residentKey: "required",
        userVerification: "required",
        authenticatorAttachment: "platform",
      },
      attestation: "none",
      timeout: 60_000,
    },
  });

  if (raw === null) throw new Error("Passkey registration cancelled");
  const credential = raw as PublicKeyCredential;
  const response = credential.response as AuthenticatorAttestationResponse;

  const publicKeyDer = response.getPublicKey();
  if (publicKeyDer === null) throw new Error("No public key in attestation");

  const cryptoKey = await crypto.subtle.importKey(
    "spki",
    publicKeyDer,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["verify"],
  );
  const exported = new Uint8Array(await crypto.subtle.exportKey("raw", cryptoKey));

  if (exported.length !== 65 || exported[0] !== 0x04) {
    throw new Error("Unexpected P-256 key format");
  }

  const xBytes = exported.slice(1, 33);
  const yBytes = exported.slice(33, 65);
  const pubX = BigInt(`0x${uint8ArrayToHex(xBytes)}`);
  const pubY = BigInt(`0x${uint8ArrayToHex(yBytes)}`);

  const authenticatorId = credential.id;
  const authenticatorIdHash = keccak256(
    uint8ArrayToHexString(b64ToBytes(authenticatorId)),
  );

  return { pubX, pubY, authenticatorId, authenticatorIdHash, rpID: rpId };
}

type StoredKey = {
  pubX: string;
  pubY: string;
  authenticatorId: string;
  authenticatorIdHash: `0x${string}`;
  rpID: string;
};

export function storeWebAuthnKey(key: WebAuthnKey): void {
  const stored: StoredKey = {
    pubX: key.pubX.toString(),
    pubY: key.pubY.toString(),
    authenticatorId: key.authenticatorId,
    authenticatorIdHash: key.authenticatorIdHash,
    rpID: key.rpID,
  };
  localStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
}

export function loadWebAuthnKey(): WebAuthnKey | null {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw === null) return null;
  try {
    const stored = JSON.parse(raw) as StoredKey;
    return {
      pubX: BigInt(stored.pubX),
      pubY: BigInt(stored.pubY),
      authenticatorId: stored.authenticatorId,
      authenticatorIdHash: stored.authenticatorIdHash,
      rpID: stored.rpID,
    };
  } catch {
    return null;
  }
}

export function clearWebAuthnKey(): void {
  localStorage.removeItem(STORAGE_KEY);
}

export function hasStoredPasskey(): boolean {
  return localStorage.getItem(STORAGE_KEY) !== null;
}

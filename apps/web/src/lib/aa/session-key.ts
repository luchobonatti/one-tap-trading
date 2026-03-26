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
import { publicClient } from "@/lib/aa/client";

const GET_SESSION_ABI = [
  {
    name: "getSession",
    type: "function",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "sessionKey", type: "address" },
          { name: "validUntil", type: "uint48" },
          { name: "targetContract", type: "address" },
          { name: "allowedSelectors", type: "bytes4[]" },
          { name: "spendLimit", type: "uint256" },
          { name: "spentAmount", type: "uint256" },
          { name: "active", type: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
] as const;

// Kernel v3.1 installs validators via installValidations, NOT installModule.
// installModule(1, addr, bytes) reverts silently on Kernel v3.1 for validator type.
// vId format: bytes21 = bytes1(VALIDATOR_TYPE.SECONDARY=0x01) || address(module)
const INSTALL_VALIDATIONS_ABI = [
  {
    name: "installValidations",
    type: "function",
    inputs: [
      { name: "vIds", type: "bytes21[]" },
      {
        name: "configs",
        type: "tuple[]",
        components: [
          { name: "nonce", type: "uint32" },
          { name: "hook", type: "address" },
        ],
      },
      { name: "validationData", type: "bytes[]" },
      { name: "hookData", type: "bytes[]" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

const IS_MODULE_INSTALLED_ABI = [
  {
    name: "isModuleInstalled",
    type: "function",
    inputs: [
      { name: "moduleTypeId", type: "uint256" },
      { name: "module", type: "address" },
      { name: "additionalContext", type: "bytes" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
] as const;

// Bump the version whenever the stored shape changes so old entries are
// automatically discarded on load.  This also invalidates any session that was
// delegated against a now-redeployed SessionKeyValidator.
const STORAGE_KEY = "ott-session-key-v2";
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
  validatorAddress: Address;
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
    validatorAddress: sessionKeyValidatorAddress[6343],
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

  const accountCode = await publicClient.getCode({ address: smartAccountAddress });
  const accountDeployed = accountCode !== undefined && accountCode !== "0x";

  let moduleInstalled = false;
  if (accountDeployed) {
    moduleInstalled = await publicClient.readContract({
      address: smartAccountAddress,
      abi: IS_MODULE_INSTALLED_ABI,
      functionName: "isModuleInstalled",
      args: [1n, sessionKeyValidatorAddress[6343], "0x"],
    });
  }

  let sessionAlreadyActive = false;
  if (accountDeployed) {
    try {
      const existing = await publicClient.readContract({
        address: sessionKeyValidatorAddress[6343],
        abi: GET_SESSION_ABI,
        functionName: "getSession",
        args: [smartAccountAddress],
      });
      sessionAlreadyActive = existing.active;
    } catch {
      sessionAlreadyActive = false;
    }
  }

  const revokeCallData = encodeFunctionData({
    abi: sessionKeyValidatorAbi,
    functionName: "revokeSession",
    args: [],
  });

  // vId = 0x01 (SECONDARY type) + 20-byte address = 21 bytes
  const vId = `0x01${sessionKeyValidatorAddress[6343].slice(2)}` as `0x${string}`;
  const installValidationsCallData = encodeFunctionData({
    abi: INSTALL_VALIDATIONS_ABI,
    functionName: "installValidations",
    args: [
      [vId],
      [{ nonce: 1, hook: "0x0000000000000000000000000000000000000000" }],
      ["0x"],
      ["0x"],
    ],
  });

  const calls = [
    {
      to: mockUsdcAddress[6343],
      data: approveCallData,
      value: 0n,
    },
    ...(moduleInstalled
      ? []
      : [
          {
            to: smartAccountAddress,
            data: installValidationsCallData,
            value: 0n,
          },
        ]),
    ...(sessionAlreadyActive
      ? [
          {
            to: sessionKeyValidatorAddress[6343],
            data: revokeCallData,
            value: 0n,
          },
        ]
      : []),
    {
      to: sessionKeyValidatorAddress[6343],
      data: grantCallData,
      value: 0n,
    },
  ];

  const opHash = await client.sendUserOperation({ calls });

  await client.waitForUserOperationReceipt({ hash: opHash });

  return opHash;
}

export function loadSessionKey(): StoredSession | null {
  const raw = sessionStorage.getItem(STORAGE_KEY);
  if (raw === null) return null;
  try {
    const session = JSON.parse(raw) as StoredSession;
    if (
      session.validatorAddress?.toLowerCase() !==
      sessionKeyValidatorAddress[6343].toLowerCase()
    ) {
      sessionStorage.removeItem(STORAGE_KEY);
      return null;
    }
    return session;
  } catch {
    sessionStorage.removeItem(STORAGE_KEY);
    return null;
  }
}

export function hasSessionKey(): boolean {
  return loadSessionKey() !== null;
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

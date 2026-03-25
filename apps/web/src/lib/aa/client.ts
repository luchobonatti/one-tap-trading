"use client";

import { createKernelAccount } from "@zerodev/sdk";
import { KERNEL_V3_1, getEntryPoint } from "@zerodev/sdk/constants";
import {
  toPasskeyValidator,
  PasskeyValidatorContractVersion,
  deserializePasskeyValidator,
} from "@zerodev/passkey-validator";
import type { WebAuthnKey } from "@zerodev/webauthn-key";
import { createSmartAccountClient } from "permissionless";
import { createPublicClient, http } from "viem";
import { megaEthCarrot } from "@/lib/aa/chain";

const BUNDLER_RPC_URL =
  process.env.NEXT_PUBLIC_BUNDLER_RPC_URL ?? "http://localhost:4337";

const CHAIN_RPC_URL =
  process.env.NEXT_PUBLIC_CHAIN_RPC_URL ?? "https://carrot.megaeth.com/rpc";

const ENTRY_POINT = getEntryPoint("0.7");

export const publicClient = createPublicClient({
  chain: megaEthCarrot,
  transport: http(CHAIN_RPC_URL),
});

type PimlicoGasPriceResponse = {
  result: {
    standard: {
      maxFeePerGas: string;
      maxPriorityFeePerGas: string;
    };
  };
};

async function estimateFeesPerGas() {
  const response = await fetch(BUNDLER_RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "pimlico_getUserOperationGasPrice",
      params: [],
    }),
  });
  const data = (await response.json()) as PimlicoGasPriceResponse;
  const { maxFeePerGas, maxPriorityFeePerGas } = data.result.standard;
  return {
    maxFeePerGas: BigInt(maxFeePerGas),
    maxPriorityFeePerGas: BigInt(maxPriorityFeePerGas),
  };
}

export async function createAccountFromPasskey(webAuthnKey: WebAuthnKey) {
  const validator = await toPasskeyValidator(publicClient, {
    webAuthnKey,
    entryPoint: ENTRY_POINT,
    kernelVersion: KERNEL_V3_1,
    validatorContractVersion: PasskeyValidatorContractVersion.V0_0_3_PATCHED,
  });

  const account = await createKernelAccount(publicClient, {
    entryPoint: ENTRY_POINT,
    kernelVersion: KERNEL_V3_1,
    plugins: { sudo: validator },
  });

  const client = createSmartAccountClient({
    account,
    chain: megaEthCarrot,
    bundlerTransport: http(BUNDLER_RPC_URL),
    userOperation: { estimateFeesPerGas },
  });

  return { account, client, serializedValidator: validator.getSerializedData() };
}

export async function loadAccountFromSerialized(serializedData: string) {
  const validator = await deserializePasskeyValidator(publicClient, {
    serializedData,
    entryPoint: ENTRY_POINT,
    kernelVersion: KERNEL_V3_1,
  });

  const account = await createKernelAccount(publicClient, {
    entryPoint: ENTRY_POINT,
    kernelVersion: KERNEL_V3_1,
    plugins: { sudo: validator },
  });

  const client = createSmartAccountClient({
    account,
    chain: megaEthCarrot,
    bundlerTransport: http(BUNDLER_RPC_URL),
    userOperation: { estimateFeesPerGas },
  });

  return { account, client };
}

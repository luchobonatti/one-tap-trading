"use client";

import {
  concat,
  encodeFunctionData,
  encodePacked,
  http,
} from "viem";
import type { Address, Hex } from "viem";
import { createBundlerClient, getUserOperationHash } from "viem/account-abstraction";
import type { UserOperation } from "viem/account-abstraction";
import { verifyingPaymasterAddress } from "@one-tap/shared-types";
import { megaEthCarrot } from "@/lib/aa/chain";
import { publicClient, estimateFeesPerGas } from "@/lib/aa/client";
import type { StoredSession } from "@/lib/aa/session-key";

const BUNDLER_RPC_URL =
  process.env.NEXT_PUBLIC_BUNDLER_RPC_URL ?? "http://localhost:4337";

const ENTRY_POINT_ADDRESS =
  (process.env.NEXT_PUBLIC_ENTRY_POINT_ADDRESS ??
    "0x0000000071727De22E5E9d8BAf0edAc6f37da032") as Address;

const PAYMASTER_ADDRESS = verifyingPaymasterAddress[6343];

const EXEC_MODE =
  "0x0000000000000000000000000000000000000000000000000000000000000000" as Hex;

const GET_NONCE_ABI = [
  {
    name: "getNonce",
    type: "function",
    inputs: [
      { name: "sender", type: "address" },
      { name: "key", type: "uint192" },
    ],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
] as const;

const STUB_SESSION_SIGNATURE = concat([
  "0x0000000000000000000000000000000000000000",
  "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
]) as Hex;

export function buildKernelCallData(target: Address, innerCallData: Hex): Hex {
  return encodeFunctionData({
    abi: [
      {
        name: "execute",
        type: "function",
        inputs: [
          { name: "mode", type: "bytes32" },
          { name: "executionCalldata", type: "bytes" },
        ],
        outputs: [],
        stateMutability: "payable",
      },
    ] as const,
    functionName: "execute",
    args: [
      EXEC_MODE,
      encodePacked(["address", "uint256", "bytes"], [target, 0n, innerCallData]),
    ],
  });
}

export async function buildUserOp(
  sender: Address,
  callData: Hex,
  session: StoredSession,
): Promise<UserOperation<"0.7">> {
  // Kernel v3.1 nonce key: validatorMode(0x00) + validatorType(0x01=SECONDARY)
  // + validatorAddress(20B) + customKey(0x0000) = 24 bytes total.
  // Derived from the session's own validatorAddress so nonce key always matches
  // the validator that was actually installed during delegation.
  const nonceKey = BigInt(
    `0x0001${session.validatorAddress.slice(2)}0000`,
  );

  const nonce = await publicClient.readContract({
    address: ENTRY_POINT_ADDRESS,
    abi: GET_NONCE_ABI,
    functionName: "getNonce",
    args: [sender, nonceKey],
  });

  // Gas estimation via eth_estimateUserOperationGas fails for our SessionKeyValidator because
  // the bundler simulation calls validateUserOp with a stub hash that doesn't match any stored
  // signature. The SKV returns VALIDATION_FAILED and the bundler aborts estimation.
  // Fixed limits are safe: MegaETH block gas cap is 2 billion; observed delegation
  // (more complex than a trade) used verificationGasLimit=6.5M, callGasLimit=2.6M.
  const fees = await estimateFeesPerGas();

  return {
    sender,
    nonce,
    callData,
    callGasLimit: 3_000_000n,
    preVerificationGas: 600_000n,
    verificationGasLimit: 6_500_000n,
    maxFeePerGas: fees.maxFeePerGas,
    maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
    paymaster: PAYMASTER_ADDRESS,
    paymasterData: "0x" as Hex,
    paymasterVerificationGasLimit: 320_000n,
    paymasterPostOpGasLimit: 66_000n,
    signature: STUB_SESSION_SIGNATURE,
  };
}

export async function signUserOp(
  userOp: UserOperation<"0.7">,
  session: StoredSession,
): Promise<UserOperation<"0.7">> {
  const { privateKeyToAccount } = await import("viem/accounts");
  const sessionAccount = privateKeyToAccount(session.privateKey);

  const userOpHash = getUserOperationHash({
    userOperation: { ...userOp, signature: "0x" as Hex },
    entryPointAddress: ENTRY_POINT_ADDRESS,
    entryPointVersion: "0.7",
    chainId: megaEthCarrot.id,
  });

  const ecdsaSig = await sessionAccount.signMessage({
    message: { raw: userOpHash },
  });

  // Kernel v3 signature format: validatorMode(0x00=DEFAULT) + validatorAddress + ecdsaSig
  const signature = concat(["0x00", session.address, ecdsaSig]) as Hex;
  return { ...userOp, signature };
}

export async function submitUserOp(
  signedOp: UserOperation<"0.7">,
): Promise<Hex> {
  const bundlerClient = createBundlerClient({
    transport: http(BUNDLER_RPC_URL),
    chain: megaEthCarrot,
  });

  return bundlerClient.sendUserOperation({
    ...signedOp,
    entryPointAddress: ENTRY_POINT_ADDRESS,
  } as Parameters<typeof bundlerClient.sendUserOperation>[0]);
}

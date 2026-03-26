import { chromium } from "@playwright/test";
import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createPublicClient, createWalletClient, http, parseUnits } from "viem";
import { createKernelAccount } from "@zerodev/sdk";
import { KERNEL_V3_1, getEntryPoint } from "@zerodev/sdk/constants";
import { deserializePasskeyValidator } from "@zerodev/passkey-validator";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
import { privateKeyToAccount } from "viem/accounts";
import { mockUsdcAddress } from "@one-tap/shared-types";

const CHAIN_RPC = process.env.NEXT_PUBLIC_CHAIN_RPC_URL ?? "https://carrot.megaeth.com/rpc";
const APP_URL = "http://localhost:3000";
const USDC_MINT_AMOUNT = parseUnits("100", 6);

const megaEthCarrot = {
  id: 6343,
  name: "MegaETH Carrot",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [CHAIN_RPC] } },
} as const;

const MOCK_USDC_ABI = [
  {
    name: "mint",
    type: "function",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

const ENTRY_POINT = getEntryPoint("0.7");

async function deriveAccountAddress(serializedData: string): Promise<string> {
  if (serializedData === "") {
    throw new Error("Serialized validator is empty — passkey account creation may have failed");
  }
  const client = createPublicClient({
    chain: megaEthCarrot,
    transport: http(CHAIN_RPC),
  });
  const validator = await deserializePasskeyValidator(client, {
    serializedData,
    entryPoint: ENTRY_POINT,
    kernelVersion: KERNEL_V3_1,
  });
  const account = await createKernelAccount(client, {
    entryPoint: ENTRY_POINT,
    kernelVersion: KERNEL_V3_1,
    plugins: { sudo: validator },
  });
  return account.address;
}

async function fundWithUsdc(accountAddress: `0x${string}`): Promise<void> {
  const deployerKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (deployerKey === undefined || deployerKey === "") {
    console.error("❌ DEPLOYER_PRIVATE_KEY not set — cannot fund test account with USDC");
    process.exit(1);
  }
  if (!/^0x[\da-fA-F]{64}$/.test(deployerKey)) {
    console.error(
      "❌ DEPLOYER_PRIVATE_KEY is invalid — expected 0x followed by 64 hex characters",
    );
    process.exit(1);
  }

  const deployer = privateKeyToAccount(deployerKey as `0x${string}`);
  const walletClient = createWalletClient({
    account: deployer,
    chain: megaEthCarrot,
    transport: http(CHAIN_RPC),
  });
  const publicClient = createPublicClient({
    chain: megaEthCarrot,
    transport: http(CHAIN_RPC),
  });

  const usdcAddress = mockUsdcAddress[6343];
  console.log(`  Minting 100 USDC to ${accountAddress}…`);

  const nonce = await publicClient.getTransactionCount({
    address: deployer.address,
    blockTag: "pending",
  });
  const hash = await walletClient.writeContract({
    address: usdcAddress,
    abi: MOCK_USDC_ABI,
    functionName: "mint",
    args: [accountAddress, USDC_MINT_AMOUNT],
    nonce,
  });

  await publicClient.waitForTransactionReceipt({ hash });
  console.log(`  ✅ USDC minted — tx: ${hash}`);
}

async function run(): Promise<void> {
  console.log("\n🚀 One Tap Trading — E2E Setup\n");
  console.log("This script will:");
  console.log("  1. Open a browser with a virtual P-256 authenticator");
  console.log("  2. Create a smart account via passkey");
  console.log("  3. Fund it with 100 USDC on MegaETH Carrot");
  console.log("  4. Delegate a 4h session key");
  console.log("  5. Save state to e2e/state.json\n");

  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  const cdp = await context.newCDPSession(page);
  await cdp.send("WebAuthn.enable", { enableUI: false });
  await cdp.send("WebAuthn.addVirtualAuthenticator", {
    options: {
      protocol: "ctap2",
      transport: "internal",
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
    },
  });

  console.log("📱 Virtual authenticator attached — passkey prompts will auto-complete\n");

  await page.goto(APP_URL);

  console.log("⏳ Waiting for SignupModal…");
  await page.waitForSelector('[aria-labelledby="signup-modal-title"]', { timeout: 15_000 });
  await page.getByRole("button", { name: "Create Account with Passkey" }).click();

  console.log("⏳ Creating passkey account on-chain…");
  await page.waitForSelector('[aria-labelledby="delegate-modal-title"]', { timeout: 60_000 });
  console.log("✅ Passkey account created");

  const serializedValidator = await page.evaluate(
    () => localStorage.getItem("ott-validator-v1") ?? "",
  );

  console.log("⏳ Deriving smart account address from serialized validator…");
  const accountAddress = await deriveAccountAddress(serializedValidator);
  console.log(`  Account address: ${accountAddress}`);
  await fundWithUsdc(accountAddress as `0x${string}`);

  console.log("\n⏳ Delegating session key…");

  const consoleErrors: string[] = [];
  page.on("console", (msg) => {
    if (msg.type() === "error") consoleErrors.push(msg.text());
  });
  page.on("pageerror", (err) => consoleErrors.push(`PAGE ERROR: ${err.message}`));

  await page.getByRole("button", { name: "Enable Trading" }).click();

  try {
    await page.waitForSelector('button[aria-label="LONG 2×"]', { timeout: 60_000 });
  } catch {
    const screenshot = resolve(__dirname, "../delegation-error.png");
    await page.screenshot({ path: screenshot, fullPage: true });
    console.error("\n❌ Delegation timed out. Screenshot saved to e2e/delegation-error.png");

    if (consoleErrors.length > 0) {
      console.error("\nBrowser console errors:");
      for (const e of consoleErrors) console.error(" •", e);
    }

    const visible = await page.evaluate(() => document.body.innerText.slice(0, 2000));
    console.error("\nVisible page text:\n", visible);
    throw new Error("Delegation timeout — see logs above for browser errors");
  }

  console.log("✅ Session key delegated");

  const sessionKeyRaw = await page.evaluate(
    () => sessionStorage.getItem("ott-session-key-v2") ?? "{}",
  );

  await browser.close();

  let parsedSessionKey: unknown;
  try {
    parsedSessionKey = JSON.parse(sessionKeyRaw);
  } catch {
    console.error("❌ Failed to parse session key from sessionStorage — delegation may have failed");
    process.exit(1);
  }

  const state = {
    serializedValidator,
    sessionKey: parsedSessionKey,
    accountAddress,
    createdAt: new Date().toISOString(),
  };

  const statePath = resolve(__dirname, "../state.json");
  writeFileSync(statePath, JSON.stringify(state, null, 2));
  console.log("\n✅ State saved to e2e/state.json");
  console.log(`   Account: ${accountAddress}`);
  console.log("   Run tests with: pnpm test:e2e\n");
}

run().catch((err: unknown) => {
  console.error("Setup failed:", err);
  process.exit(1);
});

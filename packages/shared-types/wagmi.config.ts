import { createRequire } from "node:module";
import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

const require = createRequire(import.meta.url);

type Deployments = Record<string, `0x${string}`>;
const carrot = require("../contracts/deployments/6343.json") as Deployments;
const CARROT = 6343;

export default defineConfig({
  out: "src/generated.ts",
  plugins: [
    foundry({
      project: "../contracts",
      include: [
        "PerpEngine.sol/*.json",
        "Settlement.sol/*.json",
        "PriceOracle.sol/*.json",
        "MockUSDC.sol/*.json",
        "MockPriceFeed.sol/*.json",
      ],
      deployments: {
        PerpEngine: { [CARROT]: carrot.PerpEngine },
        Settlement: { [CARROT]: carrot.Settlement },
        PriceOracle: { [CARROT]: carrot.PriceOracle },
        MockUSDC: { [CARROT]: carrot.MockUSDC },
        MockPriceFeed: { [CARROT]: carrot.MockPriceFeed },
      },
    }),
  ],
});

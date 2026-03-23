import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

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
        PerpEngine: { 6343: "0xe35486669A5D905CF18D4af477Aaac08dF93Eab0" },
        Settlement: { 6343: "0x24354D1022E13f39f330Bbf2210edEEd21422eD5" },
        PriceOracle: { 6343: "0x7FBe2a83113A6374964d6fe25C000402471079d4" },
        MockUSDC: { 6343: "0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB" },
        MockPriceFeed: { 6343: "0xd152AaBf6e4dA27004dC4a4B29da4a7754318469" },
      },
    }),
  ],
});

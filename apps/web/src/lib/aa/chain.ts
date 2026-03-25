import { defineChain } from "viem";


export const megaEthCarrot = defineChain({
  id: 6343,
  name: "MegaETH Carrot",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://carrot.megaeth.com/rpc"] },
  },
  blockExplorers: {
    default: {
      name: "MegaETH Explorer",
      url: "https://megaeth-testnet-v2.blockscout.com",
    },
  },
  testnet: true,
});

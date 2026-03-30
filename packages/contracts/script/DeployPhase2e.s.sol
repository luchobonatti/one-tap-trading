// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { MockPriceFeed } from "src/MockPriceFeed.sol";
import { PriceOracle } from "src/PriceOracle.sol";
import { PerpEngine } from "src/PerpEngine.sol";
import { Settlement } from "src/Settlement.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";

/// @title DeployPhase2e
/// @notice Redeploys MockPriceFeed, PriceOracle, and PerpEngine.
///
///         Root fix: MockPriceFeed.latestAnswer() now returns block.timestamp so
///         PriceOracle.getPrice() never hits the 5-second STALENESS_THRESHOLD.
///         Settlement and VerifyingPaymaster are reused; only their wiring is updated:
///           - Settlement.setEngine(newPerpEngine)
///           - VerifyingPaymaster.setAllowedTarget(newPerpEngine)
///
///         Run (from packages/contracts/):
///           forge script script/DeployPhase2e.s.sol:DeployPhase2e \
///             --rpc-url $MEGAETH_RPC_URL \
///             --broadcast \
///             --legacy \
///             --gas-estimate-multiplier 5000
contract DeployPhase2e is Script {
    using stdJson for string;

    int256 private constant INITIAL_PRICE = 2_000e8;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        string memory outPath = string.concat("deployments/", vm.toString(block.chainid), ".json");
        string memory existing = vm.readFile(outPath);

        address settlement = existing.readAddress(".Settlement");
        address usdc = existing.readAddress(".MockUSDC");
        address paymaster = existing.readAddress(".VerifyingPaymaster");

        console.log("Deployer:    ", deployer);
        console.log("Chain ID:    ", block.chainid);
        console.log("Settlement:  ", settlement);
        console.log("MockUSDC:    ", usdc);
        console.log("Paymaster:   ", paymaster);
        console.log("Old PriceFeed:", existing.readAddress(".MockPriceFeed"));
        console.log("Old Oracle:   ", existing.readAddress(".PriceOracle"));
        console.log("Old Engine:   ", existing.readAddress(".PerpEngine"));
        console.log("");

        vm.startBroadcast(deployerKey);

        MockPriceFeed feed = new MockPriceFeed(INITIAL_PRICE);
        console.log("New MockPriceFeed:", address(feed));

        PriceOracle oracle = new PriceOracle(address(feed));
        console.log("New PriceOracle:  ", address(oracle));

        PerpEngine engine = new PerpEngine(address(oracle), settlement, usdc);
        console.log("New PerpEngine:   ", address(engine));

        Settlement(settlement).setEngine(address(engine));
        console.log("Settlement.engine -> PerpEngine");

        VerifyingPaymaster(payable(paymaster)).setAllowedTarget(address(engine));
        console.log("Paymaster.allowedTarget -> PerpEngine");

        vm.stopBroadcast();

        vm.writeJson(_toHex(address(feed)), outPath, ".MockPriceFeed");
        vm.writeJson(_toHex(address(oracle)), outPath, ".PriceOracle");
        vm.writeJson(_toHex(address(engine)), outPath, ".PerpEngine");

        console.log("");
        console.log("Addresses written to:", outPath);
        console.log("Next: pnpm --filter shared-types generate && pnpm --filter shared-types build");
    }

    function _toHex(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes20 raw = bytes20(addr);
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i; i < 20; ++i) {
            str[2 + i * 2] = alphabet[uint8(raw[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(raw[i] & 0x0f)];
        }
        return string(str);
    }
}

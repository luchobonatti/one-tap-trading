// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { RedStoneAdapter } from "src/RedStoneAdapter.sol";
import { PriceOracle } from "src/PriceOracle.sol";
import { PerpEngine } from "src/PerpEngine.sol";
import { Settlement } from "src/Settlement.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";

/// @title DeployPhase2j
/// @notice Replaces MockPriceFeed+PriceOracle+PerpEngine with the live RedStone Bolt ETH/USD feed.
///
///         RedStone Bolt feed on Carrot testnet: 0x9674Dbe42f9996e1470F8eC15a6D0aebA4a93AEb
///         Timestamps are in nanoseconds — RedStoneAdapter converts to seconds before PriceOracle
///         checks them against STALENESS_THRESHOLD (5 s). No keeper required.
contract DeployPhase2j is Script {
    using stdJson for string;

    address private constant REDSTONE_ETH_USD = 0x9674Dbe42f9996e1470F8eC15a6D0aebA4a93AEb;

    error WrongChain(uint256 actual, uint256 expected);

    function run() external {
        if (block.chainid != 6343) revert WrongChain(block.chainid, 6343);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        string memory outPath = string.concat("deployments/", vm.toString(block.chainid), ".json");
        string memory existing = vm.readFile(outPath);

        address settlement = existing.readAddress(".Settlement");
        address usdc = existing.readAddress(".MockUSDC");
        address paymaster = existing.readAddress(".VerifyingPaymaster");

        console.log("Deployer:         ", deployer);
        console.log("Settlement:        ", settlement);
        console.log("MockUSDC:          ", usdc);
        console.log("RedStone feed:     ", REDSTONE_ETH_USD);
        console.log("Old PriceOracle:   ", existing.readAddress(".PriceOracle"));
        console.log("Old PerpEngine:    ", existing.readAddress(".PerpEngine"));
        console.log("");

        vm.startBroadcast(deployerKey);

        RedStoneAdapter adapter = new RedStoneAdapter(REDSTONE_ETH_USD);
        console.log("RedStoneAdapter:   ", address(adapter));

        PriceOracle oracle = new PriceOracle(address(adapter));
        console.log("PriceOracle:       ", address(oracle));

        PerpEngine engine = new PerpEngine(address(oracle), settlement, usdc);
        console.log("PerpEngine:        ", address(engine));

        VerifyingPaymaster(payable(paymaster)).setAllowedTarget(address(engine));
        console.log("Paymaster.allowedTarget -> PerpEngine");

        Settlement(settlement).setEngine(address(engine));
        console.log("Settlement.engine  -> PerpEngine");

        vm.stopBroadcast();

        vm.writeJson(vm.toString(address(adapter)), outPath, ".RedStoneAdapter");
        vm.writeJson(vm.toString(address(oracle)), outPath, ".PriceOracle");
        vm.writeJson(vm.toString(address(engine)), outPath, ".PerpEngine");

        console.log("");
        console.log("Written to:", outPath);
        console.log("Next: pnpm --filter shared-types generate && pnpm --filter shared-types build");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";

/// @title DeployPhase2h
/// @notice Redeploys VerifyingPaymaster to whitelist installModule(1, SKV, initData)
///         in addition to installValidations.  installModule is now used by the
///         delegation batch so that Kernel v0.3.1 grants execute-selector access.
contract DeployPhase2h is Script {
    using stdJson for string;

    address private constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    uint256 private constant INITIAL_DEPOSIT = 0.05 ether;

    error WrongChain(uint256 actual, uint256 expected);

    function run() external {
        if (block.chainid != 6343) revert WrongChain(block.chainid, 6343);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        string memory outPath = string.concat("deployments/", vm.toString(block.chainid), ".json");
        string memory existing = vm.readFile(outPath);

        address perpEngine = existing.readAddress(".PerpEngine");
        address usdc = existing.readAddress(".MockUSDC");
        address skv = existing.readAddress(".SessionKeyValidator");

        console.log("Deployer:              ", deployer);
        console.log("PerpEngine:            ", perpEngine);
        console.log("MockUSDC:              ", usdc);
        console.log("SessionKeyValidator:   ", skv);
        console.log("Old VerifyingPaymaster:", existing.readAddress(".VerifyingPaymaster"));

        vm.startBroadcast(deployerKey);

        VerifyingPaymaster paymaster =
            new VerifyingPaymaster(ENTRY_POINT, perpEngine, usdc, skv, deployer);
        console.log("New VerifyingPaymaster:", address(paymaster));

        paymaster.deposit{ value: INITIAL_DEPOSIT }();
        console.log("EntryPoint deposit:     0.05 ETH");

        vm.stopBroadcast();

        vm.writeJson(vm.toString(address(paymaster)), outPath, ".VerifyingPaymaster");
        console.log("Addresses written to:", outPath);
    }
}

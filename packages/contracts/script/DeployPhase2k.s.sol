// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";

/// @title DeployPhase2k
/// @notice Redeploys VerifyingPaymaster with the new `approveSpender` field.
///
///         Root fix: The Paymaster previously validated that the USDC approve spender
///         was `allowedTarget` (PerpEngine), but Settlement is the contract that calls
///         `safeTransferFrom`. The new `approveSpender` field is set to Settlement so
///         that approve(Settlement, amount) passes validation.
///
///         Reads all existing addresses from deployments/6343.json, deploys a new
///         VerifyingPaymaster with approveSpender = Settlement, funds the EntryPoint
///         deposit, and writes the new address back to 6343.json.
contract DeployPhase2k is Script {
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
        address settlement = existing.readAddress(".Settlement");

        console.log("Deployer:              ", deployer);
        console.log("PerpEngine:            ", perpEngine);
        console.log("MockUSDC:              ", usdc);
        console.log("SessionKeyValidator:   ", skv);
        console.log("Settlement (approveSpender):", settlement);
        console.log("Old VerifyingPaymaster:", existing.readAddress(".VerifyingPaymaster"));

        vm.startBroadcast(deployerKey);

        VerifyingPaymaster paymaster =
            new VerifyingPaymaster(ENTRY_POINT, perpEngine, usdc, skv, settlement, deployer);
        console.log("New VerifyingPaymaster:", address(paymaster));
        console.log("  approveSpender:      ", paymaster.approveSpender());

        paymaster.deposit{ value: INITIAL_DEPOSIT }();
        console.log("EntryPoint deposit:     0.05 ETH");

        vm.stopBroadcast();

        vm.writeJson(vm.toString(address(paymaster)), outPath, ".VerifyingPaymaster");
        console.log("Addresses written to:", outPath);
    }
}

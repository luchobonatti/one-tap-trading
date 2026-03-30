// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SessionKeyValidator } from "src/SessionKeyValidator.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";

/// @title DeployPhase2g
/// @notice Redeploys SessionKeyValidator with the fixed 106-byte signature format and
///         immediately wires the new address into VerifyingPaymaster so delegation
///         works without any manual follow-up step.
///
///         Root fix: validateUserOp now expects
///           mode(0x01) + validatorAddress(20B) + sessionKeyAddress(20B) + ecdsaSig(65B)
///         instead of the old
///           mode(0x00) + sessionKeyAddress(20B) + ecdsaSig(65B).
///         This resolves AA23 (0x682a6e7c) for all LONG/SHORT trade UserOps.
///
///         Run (from packages/contracts/):
///           forge script script/DeployPhase2g.s.sol:DeployPhase2g \
///             --rpc-url $MEGAETH_RPC_URL \
///             --broadcast \
///             --legacy \
///             --gas-estimate-multiplier 5000
contract DeployPhase2g is Script {
    using stdJson for string;

    error WrongChain(uint256 actual, uint256 expected);

    function run() external {
        if (block.chainid != 6343) revert WrongChain(block.chainid, 6343);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        string memory outPath = string.concat("deployments/", vm.toString(block.chainid), ".json");
        string memory existing = vm.readFile(outPath);

        address paymasterAddr = existing.readAddress(".VerifyingPaymaster");

        console.log("Deployer:                 ", deployer);
        console.log("Chain ID:                 ", block.chainid);
        console.log("Old SessionKeyValidator:  ", existing.readAddress(".SessionKeyValidator"));
        console.log("VerifyingPaymaster:       ", paymasterAddr);
        console.log("");
        console.log("Deploying fixed SessionKeyValidator (106-byte sig format)...");

        vm.startBroadcast(deployerKey);

        SessionKeyValidator skv = new SessionKeyValidator();
        console.log("New SessionKeyValidator:  ", address(skv));

        VerifyingPaymaster(payable(paymasterAddr)).setSessionKeyValidator(address(skv));
        console.log("Paymaster.sessionKeyValidator -> new SKV");

        vm.stopBroadcast();

        vm.writeJson(vm.toString(address(skv)), outPath, ".SessionKeyValidator");

        console.log("");
        console.log("Addresses written to:", outPath);
        console.log("Next: pnpm --filter shared-types generate && pnpm --filter shared-types build");
    }
}

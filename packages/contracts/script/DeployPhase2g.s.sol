// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SessionKeyValidator } from "src/SessionKeyValidator.sol";

/// @title DeployPhase2g
/// @notice Redeploys SessionKeyValidator with the fixed 106-byte signature format.
///
///         Root fix: validateUserOp now expects
///           mode(0x01) + validatorAddress(20B) + sessionKeyAddress(20B) + ecdsaSig(65B)
///         instead of the old
///           mode(0x00) + sessionKeyAddress(20B) + ecdsaSig(65B).
///         This resolves AA23 (0x682a6e7c) for all LONG/SHORT trade UserOps.
///
///         After deployment, update deployments/6343.json and run:
///           pnpm --filter shared-types generate && pnpm --filter shared-types build
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

        console.log("Deployer:                 ", deployer);
        console.log("Chain ID:                 ", block.chainid);
        console.log("Old SessionKeyValidator:  ", existing.readAddress(".SessionKeyValidator"));
        console.log("");
        console.log("Deploying fixed SessionKeyValidator (106-byte sig format)...");

        vm.startBroadcast(deployerKey);

        SessionKeyValidator skv = new SessionKeyValidator();
        console.log("New SessionKeyValidator:  ", address(skv));

        vm.stopBroadcast();

        vm.writeJson(_toHex(address(skv)), outPath, ".SessionKeyValidator");

        console.log("");
        console.log("Addresses written to:", outPath);
        console.log("Next: call VerifyingPaymaster.setSessionKeyValidator(newSKV) as owner");
        console.log(
            "  cast send <VerifyingPaymaster> \"setSessionKeyValidator(address)\" <newSKV> \\"
        );
        console.log("    --rpc-url $MEGAETH_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --legacy");
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

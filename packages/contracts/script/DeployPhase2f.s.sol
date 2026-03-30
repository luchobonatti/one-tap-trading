// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";

/// @title DeployPhase2f
/// @notice Redeploys VerifyingPaymaster with faucet() selector support for MockUSDC.
///
///         Root fix: VerifyingPaymaster now allows faucet(uint256) calls on MockUSDC,
///         enabling users to self-serve testnet collateral without manual intervention.
///
///         Reads existing Settlement, MockUSDC, SessionKeyValidator, and PerpEngine
///         from deployments/6343.json and deploys a new VerifyingPaymaster with
///         the same configuration.
///
///         Run (from packages/contracts/):
///           forge script script/DeployPhase2f.s.sol:DeployPhase2f \
///             --rpc-url $MEGAETH_RPC_URL \
///             --broadcast \
///             --legacy \
///             --gas-estimate-multiplier 5000
contract DeployPhase2f is Script {
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

        address settlement = existing.readAddress(".Settlement");
        address usdc = existing.readAddress(".MockUSDC");
        address skv = existing.readAddress(".SessionKeyValidator");
        address perpEngine = existing.readAddress(".PerpEngine");

        console.log("Deployer:              ", deployer);
        console.log("Chain ID:              ", block.chainid);
        console.log("Settlement:            ", settlement);
        console.log("MockUSDC:              ", usdc);
        console.log("SessionKeyValidator:   ", skv);
        console.log("PerpEngine:            ", perpEngine);
        console.log("Old VerifyingPaymaster:", existing.readAddress(".VerifyingPaymaster"));
        console.log("");

        vm.startBroadcast(deployerKey);

        VerifyingPaymaster paymaster =
            new VerifyingPaymaster(ENTRY_POINT, perpEngine, usdc, skv, deployer);
        console.log("New VerifyingPaymaster:", address(paymaster));

        paymaster.deposit{ value: INITIAL_DEPOSIT }();
        console.log("EntryPoint deposit:    ", INITIAL_DEPOSIT);

        vm.stopBroadcast();

        vm.writeJson(_toHex(address(paymaster)), outPath, ".VerifyingPaymaster");

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

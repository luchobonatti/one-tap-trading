// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SessionKeyValidator } from "src/SessionKeyValidator.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";

/// @title DeployPhase2c
/// @notice DEPRECATED — superseded by DeployPhase2d.
///         Kept for historical reference only; do not re-run.
///
///         Phase 2c whitelisted ERC-7579 installModule(1, SKV, "") in VerifyingPaymaster.
///         Phase 2d replaced that with installValidations(bytes21[],...) because
///         Kernel v3.1 uses installValidations for validator registration — installModule
///         reverts silently for validator type on this kernel version.
///
///         Required env vars:
///           MEGAETH_RPC_URL        — RPC endpoint
///           DEPLOYER_PRIVATE_KEY   — hex-encoded private key (with 0x prefix)
///
///         Run (from packages/contracts/):
///           forge script script/DeployPhase2c.s.sol:DeployPhase2c \
///             --rpc-url $MEGAETH_RPC_URL \
///             --broadcast \
///             --legacy \
///             --gas-estimate-multiplier 5000
contract DeployPhase2c is Script {
    using stdJson for string;

    address private constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    uint256 private constant PAYMASTER_DEPOSIT = 0.1 ether;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        string memory outPath = string.concat("deployments/", vm.toString(block.chainid), ".json");
        string memory existingJson = vm.readFile(outPath);

        address perpEngine = existingJson.readAddress(".PerpEngine");
        address mockUsdc = existingJson.readAddress(".MockUSDC");
        address settlement = existingJson.readAddress(".Settlement");

        console.log("Deployer:   ", deployer);
        console.log("Chain ID:   ", block.chainid);
        console.log("PerpEngine: ", perpEngine);
        console.log("MockUSDC:   ", mockUsdc);
        console.log("Settlement: ", settlement);
        console.log("EntryPoint: ", ENTRY_POINT);
        console.log("");
        console.log("Old SessionKeyValidator:", existingJson.readAddress(".SessionKeyValidator"));
        console.log("Old VerifyingPaymaster: ", existingJson.readAddress(".VerifyingPaymaster"));
        console.log("");

        vm.startBroadcast(deployerKey);

        // ── 1. SessionKeyValidator (post-Phase-2b fixes) ──────────────────────
        SessionKeyValidator validator = new SessionKeyValidator();
        console.log("New SessionKeyValidator:", address(validator));

        // ── 2. VerifyingPaymaster (installModule whitelist + 1 Gwei gas cap) ──
        VerifyingPaymaster paymaster = new VerifyingPaymaster(
            ENTRY_POINT, perpEngine, mockUsdc, address(validator), settlement, deployer
        );
        console.log("New VerifyingPaymaster: ", address(paymaster));

        // ── 3. Fund paymaster deposit ─────────────────────────────────────────
        paymaster.deposit{ value: PAYMASTER_DEPOSIT }();
        console.log("Paymaster funded:        0.1 ETH");

        vm.stopBroadcast();

        // ── Write new addresses into existing deployment JSON ─────────────────
        vm.writeJson(_toHex(address(validator)), outPath, ".SessionKeyValidator");
        vm.writeJson(_toHex(address(paymaster)), outPath, ".VerifyingPaymaster");

        console.log("");
        console.log("Addresses written to:", outPath);
        console.log("");
        console.log("Next: pnpm --filter shared-types build");
        console.log("      then re-run: pnpm --filter web test:e2e:setup");
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

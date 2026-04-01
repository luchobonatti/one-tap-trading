// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SessionKeyValidator } from "src/SessionKeyValidator.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";

/// @title DeployPhase2b
/// @notice Re-deploys SessionKeyValidator and VerifyingPaymaster with critical bug fixes:
///         - SessionKeyValidator: corrected PerpEngine function selectors + ERC-7579 callData
///           unwrapping in validateUserOp (was checking outer Kernel execute selector instead
///           of inner PerpEngine selector).
///         - VerifyingPaymaster: updated to handle Kernel v3 ERC-7579 execute(bytes32,bytes)
///           format (was expecting legacy execute(address,uint256,bytes)); added batch call
///           support to sponsor the delegation UserOp (approve + grantSession).
///
///         Reads existing Phase 1 + Phase 2a addresses from the deployment JSON.
///         The old VerifyingPaymaster deposit is NOT automatically withdrawn here — do it
///         manually with `cast send` before running this script if you want to reclaim ETH.
///
///         Deploy order:
///           1. SessionKeyValidator   — no dependencies (fixes stale selector constants)
///           2. VerifyingPaymaster    — now accepts mockUsdc + sessionKeyValidator targets
///           3. Paymaster deposit     — 0.1 ETH pre-funded into EntryPoint
///
///         Required env vars:
///           MEGAETH_RPC_URL        — RPC endpoint
///           DEPLOYER_PRIVATE_KEY   — hex-encoded private key (with 0x prefix)
///
///         Run (from packages/contracts/):
///           forge script script/DeployPhase2b.s.sol:DeployPhase2b \
///             --rpc-url $MEGAETH_RPC_URL \
///             --broadcast \
///             --legacy \
///             --gas-estimate-multiplier 5000
contract DeployPhase2b is Script {
    using stdJson for string;

    /// @notice EntryPoint v0.7 (canonical ERC-4337 address, same across all EVM chains).
    address private constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /// @notice ETH pre-funded into EntryPoint on behalf of the paymaster.
    ///         At MegaETH Carrot gas prices, 0.1 ETH covers ~40 average UserOps.
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

        // ── 1. SessionKeyValidator (fixed selectors + ERC-7579 callData parsing) ─
        SessionKeyValidator validator = new SessionKeyValidator();
        console.log("New SessionKeyValidator:", address(validator));

        // ── 2. VerifyingPaymaster (ERC-7579 execute format + batch delegation) ────
        VerifyingPaymaster paymaster = new VerifyingPaymaster(
            ENTRY_POINT, perpEngine, mockUsdc, address(validator), settlement, deployer
        );
        console.log("New VerifyingPaymaster: ", address(paymaster));

        // ── 3. Fund paymaster deposit ──────────────────────────────────────────
        paymaster.deposit{ value: PAYMASTER_DEPOSIT }();
        console.log("Paymaster funded:        ", PAYMASTER_DEPOSIT);

        vm.stopBroadcast();

        // ── Write new addresses into existing deployment JSON ──────────────────
        vm.writeJson(_toHex(address(validator)), outPath, ".SessionKeyValidator");
        vm.writeJson(_toHex(address(paymaster)), outPath, ".VerifyingPaymaster");

        console.log("");
        console.log("Addresses written to:", outPath);
        console.log("");
        console.log("IMPORTANT: Run `pnpm build` in packages/shared-types to regenerate");
        console.log("TypeScript types with the new contract addresses.");
        console.log("");
        console.log("NOTE: Old VerifyingPaymaster deposit NOT reclaimed automatically.");
        console.log("      Withdraw manually if needed:");
        console.log("      cast send <old-paymaster> 'withdraw(uint256)' <amount> ...");
    }

    /// @dev Convert address to checksumless lowercase hex (0x-prefixed).
    ///      Matches DeployPhase1._toHex for consistent JSON formatting.
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

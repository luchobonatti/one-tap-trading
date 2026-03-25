// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SessionKeyValidator } from "src/SessionKeyValidator.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";

/// @title DeployPhase2
/// @notice Deploys Account Abstraction contracts to MegaETH Carrot testnet:
///         - SessionKeyValidator: ERC-7579 validator module for session key authorization.
///         - VerifyingPaymaster:  ERC-4337 paymaster that sponsors trading UserOperations.
///
///         Requires Phase 1 to be deployed first (reads PerpEngine from deployments JSON).
///
///         Deploy order:
///           1. SessionKeyValidator   — no dependencies
///           2. VerifyingPaymaster    — depends on EntryPoint (canonical) + PerpEngine
///           3. Paymaster deposit     — 0.1 ETH pre-funded into EntryPoint on behalf of paymaster
///
///         Required env vars (see root .env.example):
///           MEGAETH_RPC_URL        — RPC endpoint (e.g. https://carrot.megaeth.com/rpc)
///           DEPLOYER_PRIVATE_KEY   — hex-encoded private key of the deploying account
///
///         Setup (one-time, from repo root):
///           cp .env.example .env        # fill in values
///           pnpm setup                  # symlinks packages/contracts/.env → root .env
///
///         Run (from packages/contracts/):
///           forge script script/DeployPhase2.s.sol:DeployPhase2 \
///             --rpc-url $MEGAETH_RPC_URL \
///             --broadcast \
///             --legacy \
///             --gas-estimate-multiplier 5000
///
///         Note: MegaETH Carrot gas costs are ~30x mainnet. The --legacy flag
///         and 5000 multiplier are required for successful broadcast.
contract DeployPhase2 is Script {
    using stdJson for string;

    /// @notice EntryPoint v0.7 (canonical ERC-4337 address, same across all EVM chains).
    address private constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /// @notice ETH pre-funded into EntryPoint on behalf of the paymaster.
    ///         At MegaETH Carrot gas prices, 0.1 ETH covers ~40 average UserOps.
    uint256 private constant PAYMASTER_DEPOSIT = 0.1 ether;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Read PerpEngine address from the Phase 1 deployment JSON.
        string memory outPath = string.concat("deployments/", vm.toString(block.chainid), ".json");
        string memory existingJson = vm.readFile(outPath);
        address perpEngine = existingJson.readAddress(".PerpEngine");

        console.log("Deployer:   ", deployer);
        console.log("Chain ID:   ", block.chainid);
        console.log("PerpEngine: ", perpEngine);
        console.log("EntryPoint: ", ENTRY_POINT);
        console.log("");

        vm.startBroadcast(deployerKey);

        // ── 1. SessionKeyValidator ─────────────────────────────────────────────
        SessionKeyValidator validator = new SessionKeyValidator();
        console.log("SessionKeyValidator:", address(validator));

        // ── 2. VerifyingPaymaster ──────────────────────────────────────────────
        //    NOTE: This script deploys the original Phase 2 contracts. For the updated
        //    VerifyingPaymaster with ERC-7579 support, use DeployPhase2b.s.sol instead.
        address mockUsdc = existingJson.readAddress(".MockUSDC");
        VerifyingPaymaster paymaster =
            new VerifyingPaymaster(ENTRY_POINT, perpEngine, mockUsdc, address(validator), deployer);
        console.log("VerifyingPaymaster: ", address(paymaster));

        // ── 3. Fund paymaster deposit ──────────────────────────────────────────
        //    Calls EntryPoint.depositTo on behalf of the paymaster so it can
        //    sponsor UserOperation gas from the first block.
        paymaster.deposit{ value: PAYMASTER_DEPOSIT }();
        console.log("Paymaster funded:    ", PAYMASTER_DEPOSIT);

        vm.stopBroadcast();

        // ── Write new addresses into existing deployment JSON ──────────────────
        //    Key-path writes update only the specified keys; all Phase 1 addresses
        //    (MockUSDC, MockPriceFeed, PriceOracle, Settlement, PerpEngine, deployer)
        //    remain untouched.
        //
        //    _toHex produces checksumless lowercase hex to match the Phase 1 format
        //    written by DeployPhase1._toHex — keeping 6343.json internally consistent.
        vm.writeJson(_toHex(address(validator)), outPath, ".SessionKeyValidator");
        vm.writeJson(_toHex(address(paymaster)), outPath, ".VerifyingPaymaster");

        console.log("");
        console.log("Addresses written to:", outPath);
    }

    /// @dev Convert an address to its checksumless lowercase hex string (0x-prefixed).
    ///      Matches the format used by DeployPhase1._toHex so all entries in the
    ///      deployment JSON share a consistent casing.
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

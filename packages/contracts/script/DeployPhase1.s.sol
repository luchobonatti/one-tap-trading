// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { MockPriceFeed } from "src/MockPriceFeed.sol";
import { MockUSDC } from "src/MockUSDC.sol";
import { PerpEngine } from "src/PerpEngine.sol";
import { PriceOracle } from "src/PriceOracle.sol";
import { Settlement } from "src/Settlement.sol";

/// @title DeployPhase1
/// @notice Deploys the full Phase 1 contract stack to MegaETH Carrot testnet.
///
///         Deploy order (dependency graph):
///           1. MockUSDC              — no dependencies
///           2. MockPriceFeed         — no dependencies (testnet oracle adapter)
///           3. PriceOracle           — depends on MockPriceFeed
///           4. Settlement            — depends on MockUSDC (engine set to address(0) initially)
///           5. PerpEngine            — depends on PriceOracle, Settlement, MockUSDC
///           6. Settlement.setEngine  — wires PerpEngine as the authorised caller
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
///           forge script script/DeployPhase1.s.sol:DeployPhase1 \
///             --rpc-url $MEGAETH_RPC_URL \
///             --broadcast \
///             --verify
contract DeployPhase1 is Script {
    /// @notice Initial mock price: ETH at $2 000 (8-decimal).
    int256 private constant INITIAL_PRICE = 2_000e8;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerKey);

        // ── 1. MockUSDC ───────────────────────────────────────────────────────
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC:", address(usdc));

        // ── 2. MockPriceFeed ──────────────────────────────────────────────────
        MockPriceFeed feed = new MockPriceFeed(INITIAL_PRICE);
        console.log("MockPriceFeed:", address(feed));

        // ── 3. PriceOracle ────────────────────────────────────────────────────
        PriceOracle oracle = new PriceOracle(address(feed));
        console.log("PriceOracle:", address(oracle));

        // ── 4. Settlement (engine = address(0), two-step wiring) ──────────────
        Settlement settlement = new Settlement(address(usdc), address(0));
        console.log("Settlement:", address(settlement));

        // ── 5. PerpEngine ─────────────────────────────────────────────────────
        PerpEngine engine = new PerpEngine(address(oracle), address(settlement), address(usdc));
        console.log("PerpEngine:", address(engine));

        // ── 6. Wire Settlement → PerpEngine ───────────────────────────────────
        settlement.setEngine(address(engine));
        console.log("");
        console.log("Settlement.engine set to:", address(engine));

        vm.stopBroadcast();

        // ── Write deployment addresses ────────────────────────────────────────
        string memory json = _buildJson(
            address(usdc),
            address(feed),
            address(oracle),
            address(settlement),
            address(engine),
            deployer
        );

        string memory outPath = string.concat("deployments/", vm.toString(block.chainid), ".json");
        vm.writeFile(outPath, json);
        console.log("");
        console.log("Addresses written to:", outPath);
    }

    /// @dev Build a JSON string with deployed addresses.
    ///      Using string concatenation because forge-std's JSON serialisation
    ///      requires vm.serializeAddress which is verbose for flat objects.
    function _buildJson(
        address usdc_,
        address feed_,
        address oracle_,
        address settlement_,
        address engine_,
        address deployer_
    ) internal pure returns (string memory) {
        return string.concat(
            "{\n",
            '  "MockUSDC": "',
            _toHex(usdc_),
            '",\n',
            '  "MockPriceFeed": "',
            _toHex(feed_),
            '",\n',
            '  "PriceOracle": "',
            _toHex(oracle_),
            '",\n',
            '  "Settlement": "',
            _toHex(settlement_),
            '",\n',
            '  "PerpEngine": "',
            _toHex(engine_),
            '",\n',
            '  "deployer": "',
            _toHex(deployer_),
            '"\n',
            "}\n"
        );
    }

    /// @dev Convert an address to its checksumless hex string (0x-prefixed).
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

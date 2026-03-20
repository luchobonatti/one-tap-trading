// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { IPerpEngine } from "src/IPerpEngine.sol";

contract IPerpEngineTest is Test {
    // ─── Function selectors ──────────────────────────────────────────────────

    function test_openPositionSelector() public pure {
        // openPosition(bool,uint256,uint256,(uint256,uint256,uint256))
        assertEq(
            IPerpEngine.openPosition.selector,
            bytes4(keccak256("openPosition(bool,uint256,uint256,(uint256,uint256,uint256))"))
        );
    }

    function test_closePositionSelector() public pure {
        // closePosition(uint256,(uint256,uint256,uint256))
        assertEq(
            IPerpEngine.closePosition.selector,
            bytes4(keccak256("closePosition(uint256,(uint256,uint256,uint256))"))
        );
    }

    function test_liquidateSelector() public pure {
        // liquidate is permissionless — no PriceBounds (protocol validates at oracle price)
        assertEq(IPerpEngine.liquidate.selector, bytes4(keccak256("liquidate(uint256)")));
    }

    function test_getPositionSelector() public pure {
        assertEq(IPerpEngine.getPosition.selector, bytes4(keccak256("getPosition(uint256)")));
    }

    // ─── Struct layout — Position ────────────────────────────────────────────

    function test_positionStructLayout() public pure {
        IPerpEngine.Position memory pos = IPerpEngine.Position({
            trader: address(1),
            isLong: true,
            collateral: 100e6,
            leverage: 10,
            entryPrice: 2000e8,
            timestamp: 1000,
            isOpen: true
        });
        assertEq(pos.trader, address(1));
        assertTrue(pos.isLong);
        assertEq(pos.collateral, 100e6);
        assertEq(pos.leverage, 10);
        assertEq(pos.entryPrice, 2000e8);
        assertEq(pos.timestamp, 1000);
        assertTrue(pos.isOpen);
    }

    // ─── Struct layout — PriceBounds ─────────────────────────────────────────

    function test_priceBoundsStructLayout() public pure {
        IPerpEngine.PriceBounds memory bounds = IPerpEngine.PriceBounds({
            expectedPrice: 2000e8, maxDeviation: 50e8, deadline: 9999999999
        });
        assertEq(bounds.expectedPrice, 2000e8);
        assertEq(bounds.maxDeviation, 50e8);
        assertEq(bounds.deadline, 9999999999);
    }

    // ─── Event topics ────────────────────────────────────────────────────────

    function test_eventTopics() public pure {
        // PositionOpened(uint256 indexed,address indexed,bool,uint256,uint256,uint256)
        assertEq(
            IPerpEngine.PositionOpened.selector,
            bytes32(keccak256("PositionOpened(uint256,address,bool,uint256,uint256,uint256)"))
        );
        // PositionClosed(uint256 indexed,address indexed,uint256,int256)
        assertEq(
            IPerpEngine.PositionClosed.selector,
            bytes32(keccak256("PositionClosed(uint256,address,uint256,int256)"))
        );
        // PositionLiquidated(uint256 indexed,address indexed,uint256)
        assertEq(
            IPerpEngine.PositionLiquidated.selector,
            bytes32(keccak256("PositionLiquidated(uint256,address,uint256)"))
        );
    }

    // ─── Custom error selectors ──────────────────────────────────────────────

    function test_errorSelectors() public pure {
        assertEq(
            IPerpEngine.PriceOutOfBounds.selector,
            bytes4(keccak256("PriceOutOfBounds(uint256,uint256,uint256)"))
        );
        assertEq(
            IPerpEngine.DeadlineExpired.selector,
            bytes4(keccak256("DeadlineExpired(uint256,uint256)"))
        );
        assertEq(
            IPerpEngine.PositionNotFound.selector, bytes4(keccak256("PositionNotFound(uint256)"))
        );
        assertEq(
            IPerpEngine.PositionAlreadyClosed.selector,
            bytes4(keccak256("PositionAlreadyClosed(uint256)"))
        );
        assertEq(
            IPerpEngine.InvalidCollateral.selector, bytes4(keccak256("InvalidCollateral(uint256)"))
        );
        assertEq(
            IPerpEngine.InvalidLeverage.selector, bytes4(keccak256("InvalidLeverage(uint256)"))
        );
        assertEq(IPerpEngine.Unauthorized.selector, bytes4(keccak256("Unauthorized(address)")));
    }
}

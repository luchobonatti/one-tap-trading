// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MockUSDC } from "src/MockUSDC.sol";
import { Settlement } from "src/Settlement.sol";
import { ISettlement } from "src/interfaces/ISettlement.sol";

contract SettlementTest is Test {
    MockUSDC internal usdc;
    Settlement internal settlement;

    address internal owner = address(this);
    address internal engine = makeAddr("engine");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    uint256 private constant ONE_USDC = 1e6;
    uint256 private constant TEN_K_USDC = 10_000e6;

    function setUp() public {
        usdc = new MockUSDC();
        settlement = new Settlement(address(usdc), engine);
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    function test_ConstructorSetsImmutables() public view {
        assertEq(settlement.usdc(), address(usdc));
        assertEq(settlement.engine(), engine);
        assertEq(settlement.owner(), owner);
    }

    function test_ConstructorZeroUsdcReverts() public {
        vm.expectRevert(ISettlement.ZeroAddress.selector);
        new Settlement(address(0), engine);
    }

    function test_ConstructorZeroEngineAllowed() public {
        // engine=address(0) is allowed on construction — enables two-step setup.
        // All engine-only calls revert with Unauthorized until setEngine is called.
        Settlement s = new Settlement(address(usdc), address(0));
        assertEq(s.engine(), address(0));
    }

    function test_InitialAccountingIsZero() public view {
        assertEq(settlement.totalCollateral(), 0);
        assertEq(settlement.houseReserve(), 0);
        assertEq(settlement.totalPayouts(), 0);
        assertEq(settlement.solvencyBuffer(), 0);
    }

    // ─── depositCollateral ────────────────────────────────────────────────────

    function test_DepositCollateralUpdatesAccounting() public {
        _mintAndApprove(alice, TEN_K_USDC);
        vm.prank(engine);
        settlement.depositCollateral(alice, TEN_K_USDC);

        assertEq(settlement.totalCollateral(), TEN_K_USDC);
        assertEq(settlement.solvencyBuffer(), TEN_K_USDC);
        assertEq(usdc.balanceOf(address(settlement)), TEN_K_USDC);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_DepositCollateralEmitsEvent() public {
        _mintAndApprove(alice, ONE_USDC);
        vm.expectEmit(true, false, false, true, address(settlement));
        emit ISettlement.CollateralDeposited(alice, ONE_USDC);
        vm.prank(engine);
        settlement.depositCollateral(alice, ONE_USDC);
    }

    function test_DepositCollateralRevertsForNonEngine() public {
        _mintAndApprove(alice, ONE_USDC);
        vm.expectRevert(abi.encodeWithSelector(ISettlement.Unauthorized.selector, stranger));
        vm.prank(stranger);
        settlement.depositCollateral(alice, ONE_USDC);
    }

    function test_DepositCollateralRevertsZeroAmount() public {
        vm.expectRevert(ISettlement.ZeroAmount.selector);
        vm.prank(engine);
        settlement.depositCollateral(alice, 0);
    }

    function test_MultipleDepositsAccumulate() public {
        _mintAndApprove(alice, TEN_K_USDC);
        _mintAndApprove(bob, TEN_K_USDC);

        vm.prank(engine);
        settlement.depositCollateral(alice, TEN_K_USDC);
        vm.prank(engine);
        settlement.depositCollateral(bob, TEN_K_USDC);

        assertEq(settlement.totalCollateral(), 2 * TEN_K_USDC);
        assertEq(settlement.solvencyBuffer(), 2 * TEN_K_USDC);
    }

    // ─── payout ───────────────────────────────────────────────────────────────

    function test_PayoutReleasesExactAmount() public {
        _depositAs(alice, TEN_K_USDC);

        uint256 payoutAmt = 3_000e6;
        vm.prank(engine);
        settlement.payout(alice, payoutAmt);

        assertEq(usdc.balanceOf(alice), payoutAmt);
        assertEq(settlement.totalPayouts(), payoutAmt);
        assertEq(settlement.solvencyBuffer(), TEN_K_USDC - payoutAmt);
    }

    function test_PayoutEmitsEvent() public {
        _depositAs(alice, ONE_USDC);
        vm.expectEmit(true, false, false, true, address(settlement));
        emit ISettlement.PayoutExecuted(alice, ONE_USDC);
        vm.prank(engine);
        settlement.payout(alice, ONE_USDC);
    }

    function test_PayoutRevertsForNonEngine() public {
        _depositAs(alice, ONE_USDC);
        vm.expectRevert(abi.encodeWithSelector(ISettlement.Unauthorized.selector, stranger));
        vm.prank(stranger);
        settlement.payout(alice, ONE_USDC);
    }

    function test_PayoutRevertsZeroAmount() public {
        _depositAs(alice, ONE_USDC);
        vm.expectRevert(ISettlement.ZeroAmount.selector);
        vm.prank(engine);
        settlement.payout(alice, 0);
    }

    function test_PayoutRevertsSolvencyViolation() public {
        _depositAs(alice, TEN_K_USDC);
        uint256 overAmount = TEN_K_USDC + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ISettlement.SolvencyViolation.selector, overAmount, TEN_K_USDC)
        );
        vm.prank(engine);
        settlement.payout(alice, overAmount);
    }

    function test_PayoutExactBufferSucceeds() public {
        _depositAs(alice, TEN_K_USDC);
        vm.prank(engine);
        settlement.payout(alice, TEN_K_USDC); // exactly the buffer
        assertEq(settlement.solvencyBuffer(), 0);
    }

    function test_PayoutRespectsHouseReserve() public {
        // Deposit 100 USDC, fund 50 USDC reserve → buffer = 150
        _depositAs(alice, 100e6);
        _fundReserve(50e6);

        // Paying 150 exactly should succeed
        vm.prank(engine);
        settlement.payout(alice, 150e6);
        assertEq(settlement.solvencyBuffer(), 0);
    }

    function test_PayoutToArbitraryRecipient() public {
        _depositAs(alice, TEN_K_USDC);
        vm.prank(engine);
        settlement.payout(bob, TEN_K_USDC);
        assertEq(usdc.balanceOf(bob), TEN_K_USDC);
        assertEq(usdc.balanceOf(alice), 0);
    }

    // ─── fundHouseReserve ─────────────────────────────────────────────────────

    function test_FundHouseReserveUpdatesAccounting() public {
        _fundReserve(TEN_K_USDC);

        assertEq(settlement.houseReserve(), TEN_K_USDC);
        assertEq(settlement.solvencyBuffer(), TEN_K_USDC);
        assertEq(usdc.balanceOf(address(settlement)), TEN_K_USDC);
    }

    function test_FundHouseReserveEmitsEvent() public {
        usdc.mint(owner, ONE_USDC);
        usdc.approve(address(settlement), ONE_USDC);
        vm.expectEmit(true, false, false, true, address(settlement));
        emit ISettlement.HouseReserveFunded(owner, ONE_USDC);
        settlement.fundHouseReserve(ONE_USDC);
    }

    function test_FundHouseReserveRevertsForNonOwner() public {
        usdc.mint(stranger, ONE_USDC);
        vm.prank(stranger);
        usdc.approve(address(settlement), ONE_USDC);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        vm.prank(stranger);
        settlement.fundHouseReserve(ONE_USDC);
    }

    function test_FundHouseReserveRevertsZeroAmount() public {
        vm.expectRevert(ISettlement.ZeroAmount.selector);
        settlement.fundHouseReserve(0);
    }

    // ─── setEngine ────────────────────────────────────────────────────────────

    function test_SetEngineUpdatesEngine() public {
        address newEngine = makeAddr("newEngine");
        settlement.setEngine(newEngine);
        assertEq(settlement.engine(), newEngine);
    }

    function test_SetEngineEmitsEvent() public {
        address newEngine = makeAddr("newEngine");
        vm.expectEmit(true, true, false, false, address(settlement));
        emit ISettlement.EngineUpdated(engine, newEngine);
        settlement.setEngine(newEngine);
    }

    function test_SetEngineRevertsForNonOwner() public {
        address newEngine = makeAddr("newEngine");
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        vm.prank(stranger);
        settlement.setEngine(newEngine);
    }

    function test_SetEngineRevertsZeroAddress() public {
        vm.expectRevert(ISettlement.ZeroAddress.selector);
        settlement.setEngine(address(0));
    }

    // ─── solvencyBuffer ───────────────────────────────────────────────────────

    function test_SolvencyBufferComputedCorrectly() public {
        _depositAs(alice, 100e6);
        _fundReserve(50e6);
        vm.prank(engine);
        settlement.payout(alice, 30e6);

        // buffer = (100 + 50) - 30 = 120
        assertEq(settlement.solvencyBuffer(), 120e6);
    }

    // ─── recover ─────────────────────────────────────────────────────────────

    function test_RecoverSendsStrayTokensToOwner() public {
        // Simulate a direct USDC transfer to Settlement (bypassing depositCollateral)
        usdc.mint(address(settlement), ONE_USDC);

        settlement.recover(address(usdc), ONE_USDC);

        assertEq(usdc.balanceOf(owner), ONE_USDC);
        assertEq(usdc.balanceOf(address(settlement)), 0);
    }

    function test_RecoverRevertsForNonOwner() public {
        usdc.mint(address(settlement), ONE_USDC);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        vm.prank(stranger);
        settlement.recover(address(usdc), ONE_USDC);
    }

    // ─── Fuzz ────────────────────────────────────────────────────────────────

    /// @dev Any positive deposit: totalCollateral and solvencyBuffer increase by exact amount.
    function testFuzz_DepositCollateral(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        _mintAndApprove(alice, amount);
        vm.prank(engine);
        settlement.depositCollateral(alice, amount);

        assertEq(settlement.totalCollateral(), amount);
        assertEq(settlement.solvencyBuffer(), amount);
        assertEq(usdc.balanceOf(address(settlement)), amount);
    }

    /// @dev Any positive reserve top-up: houseReserve and solvencyBuffer increase by exact amount.
    function testFuzz_FundHouseReserve(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        usdc.mint(owner, amount);
        usdc.approve(address(settlement), amount);
        settlement.fundHouseReserve(amount);

        assertEq(settlement.houseReserve(), amount);
        assertEq(settlement.solvencyBuffer(), amount);
        assertEq(usdc.balanceOf(address(settlement)), amount);
    }

    /// @dev Any deposit + reserve combination: payout up to buffer succeeds.
    ///      payoutAmt kept as uint256 to avoid truncation when buffer > type(uint128).max.
    function testFuzz_PayoutUpToBuffer(uint128 depositAmt, uint128 reserveAmt, uint256 payoutAmt)
        public
    {
        vm.assume(depositAmt > 0);
        uint256 buffer = uint256(depositAmt) + uint256(reserveAmt);
        vm.assume(buffer > 0);
        payoutAmt = bound(payoutAmt, 1, buffer);

        _depositAs(alice, depositAmt);
        if (reserveAmt > 0) _fundReserve(reserveAmt);

        vm.prank(engine);
        settlement.payout(alice, payoutAmt);

        assertEq(settlement.totalPayouts(), payoutAmt);
        assertEq(settlement.solvencyBuffer(), buffer - payoutAmt);
    }

    /// @dev Any payout exceeding the buffer must revert.
    function testFuzz_PayoutAboveBufferReverts(uint128 depositAmt, uint128 overAmt) public {
        vm.assume(depositAmt > 0);
        vm.assume(overAmt > 0);
        uint256 payoutAmt = uint256(depositAmt) + uint256(overAmt);

        _depositAs(alice, depositAmt);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISettlement.SolvencyViolation.selector, payoutAmt, uint256(depositAmt)
            )
        );
        vm.prank(engine);
        settlement.payout(alice, payoutAmt);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _mintAndApprove(address user, uint256 amount) internal {
        usdc.mint(user, amount);
        vm.prank(user);
        usdc.approve(address(settlement), amount);
    }

    function _depositAs(address user, uint256 amount) internal {
        _mintAndApprove(user, amount);
        vm.prank(engine);
        settlement.depositCollateral(user, amount);
    }

    function _fundReserve(uint256 amount) internal {
        usdc.mint(owner, amount);
        usdc.approve(address(settlement), amount);
        settlement.fundHouseReserve(amount);
    }
}

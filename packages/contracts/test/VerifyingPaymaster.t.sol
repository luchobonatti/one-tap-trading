// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { VerifyingPaymaster } from "src/VerifyingPaymaster.sol";
import { IVerifyingPaymaster } from "src/interfaces/IVerifyingPaymaster.sol";
import { IPaymaster } from "account-abstraction/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { IPerpEngine } from "src/IPerpEngine.sol";

/// @dev Full test suite for VerifyingPaymaster.
contract VerifyingPaymasterTest is Test {
    VerifyingPaymaster internal paymaster;
    address internal entryPoint = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address internal perpEngine = 0xe35486669A5D905CF18D4af477Aaac08dF93Eab0;
    address internal owner;
    uint256 internal ownerKey;
    address internal user = makeAddr("user");

    // Selectors
    bytes4 internal constant EXECUTE_SELECTOR = bytes4(keccak256("execute(address,uint256,bytes)"));
    bytes4 internal constant OPEN_POSITION_SELECTOR =
        bytes4(keccak256("openPosition(bool,uint256,uint256,(uint256,uint256,uint256))"));
    bytes4 internal constant CLOSE_POSITION_SELECTOR =
        bytes4(keccak256("closePosition(uint256,(uint256,uint256,uint256))"));

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        vm.prank(owner);
        paymaster = new VerifyingPaymaster(entryPoint, perpEngine, owner);

        // Mock EntryPoint deposit/withdraw/balanceOf
        vm.mockCall(entryPoint, abi.encodeWithSignature("depositTo(address)"), abi.encode());
        vm.mockCall(
            entryPoint, abi.encodeWithSignature("withdrawTo(address,uint256)"), abi.encode()
        );
        vm.mockCall(
            entryPoint, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(1 ether))
        );
    }

    // ─── Constructor tests ─────────────────────────────────────────────────────

    function test_Constructor_SetsValues() public view {
        assertEq(paymaster.entryPoint(), entryPoint);
        assertEq(paymaster.allowedTarget(), perpEngine);
        assertEq(paymaster.gasAllowancePerOp(), 500_000);
        assertEq(paymaster.owner(), owner);
    }

    function test_Constructor_ZeroEntryPoint_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IVerifyingPaymaster.ZeroAddress.selector);
        new VerifyingPaymaster(address(0), perpEngine, owner);
    }

    function test_Constructor_ZeroAllowedTarget_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IVerifyingPaymaster.ZeroAddress.selector);
        new VerifyingPaymaster(entryPoint, address(0), owner);
    }

    // ─── validatePaymasterUserOp tests ────────────────────────────────────────

    function test_ValidatePaymasterUserOp_NotEntryPoint_Reverts() public {
        PackedUserOperation memory userOp = _createValidUserOp();
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IVerifyingPaymaster.NotEntryPoint.selector, user));
        paymaster.validatePaymasterUserOp(userOp, userOpHash, 100_000);
    }

    function test_ValidatePaymasterUserOp_GasExceedsAllowance_Reverts() public {
        PackedUserOperation memory userOp = _createValidUserOp();
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 600_000; // Exceeds default 500_000

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerifyingPaymaster.GasAllowanceExceeded.selector, maxCost, 500_000
            )
        );
        paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function test_ValidatePaymasterUserOp_WrongTarget_Reverts() public {
        address wrongTarget = makeAddr("wrongTarget");
        PackedUserOperation memory userOp = _createUserOpWithTarget(wrongTarget);
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(IVerifyingPaymaster.TargetNotAllowed.selector, wrongTarget)
        );
        paymaster.validatePaymasterUserOp(userOp, userOpHash, 100_000);
    }

    function test_ValidatePaymasterUserOp_WrongSelector_Reverts() public {
        bytes4 wrongSelector = bytes4(keccak256("wrongFunction()"));
        PackedUserOperation memory userOp = _createUserOpWithSelector(wrongSelector);
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(IVerifyingPaymaster.SelectorNotAllowed.selector, wrongSelector)
        );
        paymaster.validatePaymasterUserOp(userOp, userOpHash, 100_000);
    }

    function test_ValidatePaymasterUserOp_ValidOpenPosition_ReturnsContext() public {
        PackedUserOperation memory userOp = _createValidUserOp();
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 100_000;

        vm.prank(entryPoint);
        (bytes memory context, uint256 validationData) =
            paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);

        // Verify context contains sender and maxCost
        (address contextSender, uint256 contextMaxCost) = abi.decode(context, (address, uint256));
        assertEq(contextSender, user);
        assertEq(contextMaxCost, maxCost);

        // Verify validation data is 0 (valid)
        assertEq(validationData, 0);
    }

    function test_ValidatePaymasterUserOp_ValidClosePosition_ReturnsContext() public {
        PackedUserOperation memory userOp = _createUserOpWithSelector(CLOSE_POSITION_SELECTOR);
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 100_000;

        vm.prank(entryPoint);
        (bytes memory context, uint256 validationData) =
            paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);

        (address contextSender, uint256 contextMaxCost) = abi.decode(context, (address, uint256));
        assertEq(contextSender, user);
        assertEq(contextMaxCost, maxCost);
        assertEq(validationData, 0);
    }

    function test_ValidatePaymasterUserOp_DirectCall_ValidOpenPosition() public {
        // Test direct call (not wrapped in execute)
        bytes memory openPositionData = abi.encodeWithSelector(
            OPEN_POSITION_SELECTOR,
            true, // isLong
            1000e6, // collateral
            10, // leverage
            IPerpEngine.PriceBounds({
                expectedPrice: 2000e8, maxDeviation: 100e8, deadline: block.timestamp + 60
            })
        );

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = openPositionData;

        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 100_000;

        vm.prank(entryPoint);
        (bytes memory context, uint256 validationData) =
            paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);

        (address contextSender,) = abi.decode(context, (address, uint256));
        assertEq(contextSender, user);
        assertEq(validationData, 0);
    }

    function test_ValidatePaymasterUserOp_EmptyCallData_Reverts() public {
        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = "";

        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(IVerifyingPaymaster.SelectorNotAllowed.selector, bytes4(0))
        );
        paymaster.validatePaymasterUserOp(userOp, userOpHash, 100_000);
    }

    // ─── postOp tests ─────────────────────────────────────────────────────────

    function test_PostOp_NotEntryPoint_Reverts() public {
        bytes memory context = abi.encode(user, uint256(100_000));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IVerifyingPaymaster.NotEntryPoint.selector, user));
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 50_000, 1 gwei);
    }

    function test_PostOp_OpSucceeded_EmitsGasSponsored() public {
        bytes memory context = abi.encode(user, uint256(100_000));
        uint256 actualGasCost = 50_000;

        vm.prank(entryPoint);
        vm.expectEmit(true, false, false, true);
        emit IVerifyingPaymaster.GasSponsored(user, actualGasCost);
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualGasCost, 1 gwei);
    }

    function test_PostOp_OpReverted_EmitsGasSponsored() public {
        bytes memory context = abi.encode(user, uint256(100_000));
        uint256 actualGasCost = 50_000;

        vm.prank(entryPoint);
        vm.expectEmit(true, false, false, true);
        emit IVerifyingPaymaster.GasSponsored(user, actualGasCost);
        paymaster.postOp(IPaymaster.PostOpMode.opReverted, context, actualGasCost, 1 gwei);
    }

    function test_PostOp_PostOpReverted_NoEvent() public {
        bytes memory context = abi.encode(user, uint256(100_000));
        uint256 actualGasCost = 50_000;

        vm.prank(entryPoint);
        // Should not emit event for postOpReverted
        paymaster.postOp(IPaymaster.PostOpMode.postOpReverted, context, actualGasCost, 1 gwei);
    }

    // ─── setAllowedTarget tests ────────────────────────────────────────────────

    function test_SetAllowedTarget_OnlyOwner() public {
        address newTarget = makeAddr("newTarget");

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        paymaster.setAllowedTarget(newTarget);
    }

    function test_SetAllowedTarget_ZeroAddress_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IVerifyingPaymaster.ZeroAddress.selector);
        paymaster.setAllowedTarget(address(0));
    }

    function test_SetAllowedTarget_UpdatesAndEmits() public {
        address newTarget = makeAddr("newTarget");

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit IVerifyingPaymaster.AllowedTargetUpdated(perpEngine, newTarget);
        paymaster.setAllowedTarget(newTarget);

        assertEq(paymaster.allowedTarget(), newTarget);
    }

    // ─── setGasAllowancePerOp tests ────────────────────────────────────────────

    function test_SetGasAllowancePerOp_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        paymaster.setGasAllowancePerOp(600_000);
    }

    function test_SetGasAllowancePerOp_UpdatesAndEmits() public {
        uint256 newAllowance = 600_000;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IVerifyingPaymaster.GasAllowanceUpdated(500_000, newAllowance);
        paymaster.setGasAllowancePerOp(newAllowance);

        assertEq(paymaster.gasAllowancePerOp(), newAllowance);
    }

    // ─── Deposit/Withdraw tests ───────────────────────────────────────────────

    function test_Deposit_CallsEntryPoint() public {
        uint256 amount = 1 ether;

        vm.expectCall(
            entryPoint, amount, abi.encodeWithSignature("depositTo(address)", address(paymaster))
        );
        paymaster.deposit{ value: amount }();
    }

    function test_Withdraw_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        paymaster.withdraw(1 ether);
    }

    function test_Withdraw_CallsEntryPoint() public {
        uint256 amount = 1 ether;

        vm.prank(owner);
        vm.expectCall(
            entryPoint, abi.encodeWithSignature("withdrawTo(address,uint256)", owner, amount)
        );
        paymaster.withdraw(amount);
    }

    function test_GetDeposit_ReturnsBalance() public view {
        uint256 balance = paymaster.getDeposit();
        assertEq(balance, 1 ether);
    }

    function test_Receive_AcceptsETH() public {
        uint256 amount = 1 ether;
        (bool success,) = address(paymaster).call{ value: amount }("");
        assertTrue(success);
    }

    // ─── Fuzz tests ───────────────────────────────────────────────────────────

    function test_fuzz_ValidatePaymasterUserOp_GasLimit(uint256 maxCost) public {
        // Bound to reasonable gas values
        maxCost = bound(maxCost, 1, 10_000_000);

        PackedUserOperation memory userOp = _createValidUserOp();
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(entryPoint);

        if (maxCost > 500_000) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IVerifyingPaymaster.GasAllowanceExceeded.selector, maxCost, 500_000
                )
            );
            paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);
        } else {
            (bytes memory context, uint256 validationData) =
                paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);

            (address contextSender, uint256 contextMaxCost) =
                abi.decode(context, (address, uint256));
            assertEq(contextSender, user);
            assertEq(contextMaxCost, maxCost);
            assertEq(validationData, 0);
        }
    }

    function test_fuzz_SetGasAllowancePerOp(uint256 newAllowance) public {
        // Bound to reasonable values
        newAllowance = bound(newAllowance, 1, 10_000_000);

        vm.prank(owner);
        paymaster.setGasAllowancePerOp(newAllowance);

        assertEq(paymaster.gasAllowancePerOp(), newAllowance);
    }

    // ─── Helper functions ─────────────────────────────────────────────────────

    /// @dev Create a valid UserOp with openPosition call wrapped in execute.
    function _createValidUserOp() internal view returns (PackedUserOperation memory) {
        bytes memory openPositionData = abi.encodeWithSelector(
            OPEN_POSITION_SELECTOR,
            true, // isLong
            1000e6, // collateral
            10, // leverage
            IPerpEngine.PriceBounds({
                expectedPrice: 2000e8, maxDeviation: 100e8, deadline: block.timestamp + 60
            })
        );

        bytes memory executeData =
            abi.encodeWithSelector(EXECUTE_SELECTOR, perpEngine, uint256(0), openPositionData);

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = executeData;
        return userOp;
    }

    /// @dev Create a UserOp with a specific target.
    function _createUserOpWithTarget(address target)
        internal
        view
        returns (PackedUserOperation memory)
    {
        bytes memory openPositionData = abi.encodeWithSelector(
            OPEN_POSITION_SELECTOR,
            true,
            1000e6,
            10,
            IPerpEngine.PriceBounds({
                expectedPrice: 2000e8, maxDeviation: 100e8, deadline: block.timestamp + 60
            })
        );

        bytes memory executeData =
            abi.encodeWithSelector(EXECUTE_SELECTOR, target, uint256(0), openPositionData);

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = executeData;
        return userOp;
    }

    /// @dev Create a UserOp with a specific selector.
    function _createUserOpWithSelector(bytes4 selector)
        internal
        view
        returns (PackedUserOperation memory)
    {
        bytes memory innerData;

        if (selector == OPEN_POSITION_SELECTOR) {
            innerData = abi.encodeWithSelector(
                OPEN_POSITION_SELECTOR,
                true,
                1000e6,
                10,
                IPerpEngine.PriceBounds({
                    expectedPrice: 2000e8, maxDeviation: 100e8, deadline: block.timestamp + 60
                })
            );
        } else if (selector == CLOSE_POSITION_SELECTOR) {
            innerData = abi.encodeWithSelector(
                CLOSE_POSITION_SELECTOR,
                uint256(1),
                IPerpEngine.PriceBounds({
                    expectedPrice: 2000e8, maxDeviation: 100e8, deadline: block.timestamp + 60
                })
            );
        } else {
            // Wrong selector
            innerData = abi.encodeWithSelector(selector);
        }

        bytes memory executeData =
            abi.encodeWithSelector(EXECUTE_SELECTOR, perpEngine, uint256(0), innerData);

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = executeData;
        return userOp;
    }
}

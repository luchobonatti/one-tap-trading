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
    address internal mockUsdc = 0xBD2e92B39081A9Dc541A776b5D7B7e0051851CCB;
    address internal sessionKeyValidator = 0x672B55126649951AfbbD13d82015691BC8BAD007;
    address internal owner;
    uint256 internal ownerKey;
    address internal user = makeAddr("user");

    // Kernel v3 ERC-7579 execute(bytes32,bytes) selector
    bytes4 internal constant EXECUTE_SELECTOR = bytes4(keccak256("execute(bytes32,bytes)"));
    bytes4 internal constant OPEN_POSITION_SELECTOR =
        bytes4(keccak256("openPosition(bool,uint256,uint256,(uint256,uint256,uint256))"));
    bytes4 internal constant CLOSE_POSITION_SELECTOR =
        bytes4(keccak256("closePosition(uint256,(uint256,uint256,uint256))"));
    bytes4 internal constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));
    bytes4 internal constant GRANT_SESSION_SELECTOR =
        bytes4(keccak256("grantSession(address,uint48,address,bytes4[],uint256)"));

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        vm.prank(owner);
        paymaster =
            new VerifyingPaymaster(entryPoint, perpEngine, mockUsdc, sessionKeyValidator, owner);

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
        assertEq(paymaster.mockUsdc(), mockUsdc);
        assertEq(paymaster.sessionKeyValidator(), sessionKeyValidator);
        assertEq(paymaster.gasAllowancePerOp(), 5_000_000);
        assertEq(paymaster.owner(), owner);
    }

    function test_Constructor_ZeroEntryPoint_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IVerifyingPaymaster.ZeroAddress.selector);
        new VerifyingPaymaster(address(0), perpEngine, mockUsdc, sessionKeyValidator, owner);
    }

    function test_Constructor_ZeroAllowedTarget_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IVerifyingPaymaster.ZeroAddress.selector);
        new VerifyingPaymaster(entryPoint, address(0), mockUsdc, sessionKeyValidator, owner);
    }

    function test_Constructor_ZeroMockUsdc_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IVerifyingPaymaster.ZeroAddress.selector);
        new VerifyingPaymaster(entryPoint, perpEngine, address(0), sessionKeyValidator, owner);
    }

    function test_Constructor_ZeroSessionKeyValidator_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IVerifyingPaymaster.ZeroAddress.selector);
        new VerifyingPaymaster(entryPoint, perpEngine, mockUsdc, address(0), owner);
    }

    // ─── validatePaymasterUserOp — access control ─────────────────────────────

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
        uint256 maxCost = 6_000_000; // Exceeds default 5_000_000

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerifyingPaymaster.GasAllowanceExceeded.selector, maxCost, 5_000_000
            )
        );
        paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    // ─── validatePaymasterUserOp — trading calls ──────────────────────────────

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

        (address contextSender, uint256 contextMaxCost) = abi.decode(context, (address, uint256));
        assertEq(contextSender, user);
        assertEq(contextMaxCost, maxCost);
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
        // Test direct call (not wrapped in execute) — backward compat path.
        bytes memory openPositionData = abi.encodeWithSelector(
            OPEN_POSITION_SELECTOR,
            true,
            1000e6,
            10,
            IPerpEngine.PriceBounds({
                expectedPrice: 2000e8, maxDeviation: 100e8, deadline: block.timestamp + 60
            })
        );

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = openPositionData;

        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(entryPoint);
        (bytes memory context, uint256 validationData) =
            paymaster.validatePaymasterUserOp(userOp, userOpHash, 100_000);

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

    // ─── validatePaymasterUserOp — delegation batch ───────────────────────────

    function test_ValidatePaymasterUserOp_BatchDelegation_ApproveAndGrantSession() public {
        // Batch: [approve(perpEngine, MaxUint256), grantSession(...)]
        PackedUserOperation memory userOp = _createDelegationBatchUserOp();
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(entryPoint);
        (bytes memory context, uint256 validationData) =
            paymaster.validatePaymasterUserOp(userOp, userOpHash, 100_000);

        (address contextSender,) = abi.decode(context, (address, uint256));
        assertEq(contextSender, user);
        assertEq(validationData, 0);
    }

    function test_ValidatePaymasterUserOp_BatchWithWrongTarget_Reverts() public {
        // Batch that includes a call to an unauthorized target
        address badTarget = makeAddr("badTarget");

        VerifyingPaymaster.Execution[] memory execs = new VerifyingPaymaster.Execution[](2);
        execs[0] = VerifyingPaymaster.Execution({
            target: mockUsdc,
            value: 0,
            callData: abi.encodeWithSelector(APPROVE_SELECTOR, perpEngine, type(uint256).max)
        });
        execs[1] = VerifyingPaymaster.Execution({
            target: badTarget,
            value: 0,
            callData: abi.encodeWithSelector(bytes4(keccak256("hack()")))
        });

        bytes memory execCalldata = abi.encode(execs);
        // Batch mode: first byte of bytes32 mode = 0x01 (CALLTYPE_BATCH).
        // bytes32(uint256(1) << 248) sets the most-significant byte to 0x01.
        bytes32 batchMode = bytes32(uint256(1) << 248);
        bytes memory callData = abi.encodeWithSelector(EXECUTE_SELECTOR, batchMode, execCalldata);

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = callData;

        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(IVerifyingPaymaster.TargetNotAllowed.selector, badTarget)
        );
        paymaster.validatePaymasterUserOp(userOp, userOpHash, 100_000);
    }

    function test_ValidatePaymasterUserOp_ApproveOnMockUsdc_Succeeds() public {
        // Single approve(perpEngine, MaxUint256) — spender == allowedTarget, should pass.
        bytes memory approveData =
            abi.encodeWithSelector(APPROVE_SELECTOR, perpEngine, type(uint256).max);
        bytes memory execCalldata = abi.encodePacked(mockUsdc, uint256(0), approveData);
        bytes memory callData = abi.encodeWithSelector(EXECUTE_SELECTOR, bytes32(0), execCalldata);

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = callData;

        vm.prank(entryPoint);
        (, uint256 validationData) =
            paymaster.validatePaymasterUserOp(userOp, keccak256(abi.encode(userOp)), 100_000);
        assertEq(validationData, 0);
    }

    function test_ValidatePaymasterUserOp_ApproveWrongSpender_Reverts() public {
        // approve(wrongSpender, MaxUint256) — spender != allowedTarget, must revert.
        address wrongSpender = makeAddr("wrongSpender");
        bytes memory approveData =
            abi.encodeWithSelector(APPROVE_SELECTOR, wrongSpender, type(uint256).max);
        bytes memory execCalldata = abi.encodePacked(mockUsdc, uint256(0), approveData);
        bytes memory callData = abi.encodeWithSelector(EXECUTE_SELECTOR, bytes32(0), execCalldata);

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = callData;

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(IVerifyingPaymaster.TargetNotAllowed.selector, wrongSpender)
        );
        paymaster.validatePaymasterUserOp(userOp, keccak256(abi.encode(userOp)), 100_000);
    }

    function test_ValidatePaymasterUserOp_GrantSessionOnValidator_Succeeds() public {
        // grantSession with targetContract == perpEngine — should pass.
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = OPEN_POSITION_SELECTOR;
        sels[1] = CLOSE_POSITION_SELECTOR;

        bytes memory grantData = abi.encodeWithSelector(
            GRANT_SESSION_SELECTOR,
            makeAddr("sessionKey"),
            uint48(block.timestamp + 4 hours),
            perpEngine,
            sels,
            uint256(10_000e6)
        );
        bytes memory execCalldata = abi.encodePacked(sessionKeyValidator, uint256(0), grantData);
        bytes memory callData = abi.encodeWithSelector(EXECUTE_SELECTOR, bytes32(0), execCalldata);

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = callData;

        vm.prank(entryPoint);
        (, uint256 validationData) =
            paymaster.validatePaymasterUserOp(userOp, keccak256(abi.encode(userOp)), 100_000);
        assertEq(validationData, 0);
    }

    function test_ValidatePaymasterUserOp_GrantSessionWrongTarget_Reverts() public {
        // grantSession with targetContract != perpEngine — must revert.
        address wrongTarget = makeAddr("wrongTarget");
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = OPEN_POSITION_SELECTOR;
        sels[1] = CLOSE_POSITION_SELECTOR;

        bytes memory grantData = abi.encodeWithSelector(
            GRANT_SESSION_SELECTOR,
            makeAddr("sessionKey"),
            uint48(block.timestamp + 4 hours),
            wrongTarget,
            sels,
            uint256(10_000e6)
        );
        bytes memory execCalldata = abi.encodePacked(sessionKeyValidator, uint256(0), grantData);
        bytes memory callData = abi.encodeWithSelector(EXECUTE_SELECTOR, bytes32(0), execCalldata);

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = callData;

        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(IVerifyingPaymaster.TargetNotAllowed.selector, wrongTarget)
        );
        paymaster.validatePaymasterUserOp(userOp, keccak256(abi.encode(userOp)), 100_000);
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
        paymaster.postOp(IPaymaster.PostOpMode.postOpReverted, context, actualGasCost, 1 gwei);
    }

    // ─── setAllowedTarget tests ────────────────────────────────────────────────

    function test_SetAllowedTarget_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        paymaster.setAllowedTarget(makeAddr("newTarget"));
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

    // ─── setMockUsdc tests ─────────────────────────────────────────────────────

    function test_SetMockUsdc_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        paymaster.setMockUsdc(makeAddr("newMockUsdc"));
    }

    function test_SetMockUsdc_ZeroAddress_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IVerifyingPaymaster.ZeroAddress.selector);
        paymaster.setMockUsdc(address(0));
    }

    function test_SetMockUsdc_UpdatesAndEmits() public {
        address newMockUsdc = makeAddr("newMockUsdc");

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit IVerifyingPaymaster.MockUsdcUpdated(mockUsdc, newMockUsdc);
        paymaster.setMockUsdc(newMockUsdc);

        assertEq(paymaster.mockUsdc(), newMockUsdc);
    }

    // ─── setSessionKeyValidator tests ─────────────────────────────────────────

    function test_SetSessionKeyValidator_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        paymaster.setSessionKeyValidator(makeAddr("newValidator"));
    }

    function test_SetSessionKeyValidator_ZeroAddress_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(IVerifyingPaymaster.ZeroAddress.selector);
        paymaster.setSessionKeyValidator(address(0));
    }

    function test_SetSessionKeyValidator_UpdatesAndEmits() public {
        address newValidator = makeAddr("newValidator");

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit IVerifyingPaymaster.SessionKeyValidatorUpdated(sessionKeyValidator, newValidator);
        paymaster.setSessionKeyValidator(newValidator);

        assertEq(paymaster.sessionKeyValidator(), newValidator);
    }

    // ─── setGasAllowancePerOp tests ────────────────────────────────────────────

    function test_SetGasAllowancePerOp_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        paymaster.setGasAllowancePerOp(600_000);
    }

    function test_SetGasAllowancePerOp_UpdatesAndEmits() public {
        uint256 newAllowance = 10_000_000;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit IVerifyingPaymaster.GasAllowanceUpdated(5_000_000, newAllowance);
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
        maxCost = bound(maxCost, 1, 10_000_000);

        PackedUserOperation memory userOp = _createValidUserOp();
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(entryPoint);

        if (maxCost > 5_000_000) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IVerifyingPaymaster.GasAllowanceExceeded.selector, maxCost, 5_000_000
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
        newAllowance = bound(newAllowance, 1, 100_000_000);

        vm.prank(owner);
        paymaster.setGasAllowancePerOp(newAllowance);

        assertEq(paymaster.gasAllowancePerOp(), newAllowance);
    }

    // ─── Helper functions ─────────────────────────────────────────────────────

    /// @dev Build an ERC-7579 single-call execute callData targeting `target` with `innerData`.
    function _buildExecuteCallData(address target, bytes memory innerData)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory execCalldata = abi.encodePacked(target, uint256(0), innerData);
        return
            abi.encodeWithSelector(
                EXECUTE_SELECTOR,
                bytes32(0), // single-call mode
                execCalldata
            );
    }

    /// @dev Valid UserOp: openPosition wrapped in ERC-7579 execute.
    function _createValidUserOp() internal view returns (PackedUserOperation memory) {
        bytes memory innerData = abi.encodeWithSelector(
            OPEN_POSITION_SELECTOR,
            true,
            1000e6,
            10,
            IPerpEngine.PriceBounds({
                expectedPrice: 2000e8, maxDeviation: 100e8, deadline: block.timestamp + 60
            })
        );

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = _buildExecuteCallData(perpEngine, innerData);
        return userOp;
    }

    /// @dev UserOp with a specific target address (single call mode).
    function _createUserOpWithTarget(address target)
        internal
        view
        returns (PackedUserOperation memory)
    {
        bytes memory innerData = abi.encodeWithSelector(
            OPEN_POSITION_SELECTOR,
            true,
            1000e6,
            10,
            IPerpEngine.PriceBounds({
                expectedPrice: 2000e8, maxDeviation: 100e8, deadline: block.timestamp + 60
            })
        );

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = _buildExecuteCallData(target, innerData);
        return userOp;
    }

    /// @dev UserOp with a specific inner selector (single call to perpEngine).
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
            innerData = abi.encodeWithSelector(selector);
        }

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = _buildExecuteCallData(perpEngine, innerData);
        return userOp;
    }

    /// @dev Batch UserOp with approve(perpEngine) + grantSession — the delegation flow.
    function _createDelegationBatchUserOp() internal returns (PackedUserOperation memory) {
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = OPEN_POSITION_SELECTOR;
        sels[1] = CLOSE_POSITION_SELECTOR;

        VerifyingPaymaster.Execution[] memory execs = new VerifyingPaymaster.Execution[](2);
        execs[0] = VerifyingPaymaster.Execution({
            target: mockUsdc,
            value: 0,
            callData: abi.encodeWithSelector(APPROVE_SELECTOR, perpEngine, type(uint256).max)
        });
        execs[1] = VerifyingPaymaster.Execution({
            target: sessionKeyValidator,
            value: 0,
            callData: abi.encodeWithSelector(
                GRANT_SESSION_SELECTOR,
                makeAddr("sessionKey"),
                uint48(block.timestamp + 4 hours),
                perpEngine,
                sels,
                uint256(10_000e6)
            )
        });

        // Batch mode: first byte of mode = 0x01
        bytes32 batchMode = bytes32(uint256(1) << 248);
        bytes memory execCalldata = abi.encode(execs);
        bytes memory callData = abi.encodeWithSelector(EXECUTE_SELECTOR, batchMode, execCalldata);

        PackedUserOperation memory userOp;
        userOp.sender = user;
        userOp.callData = callData;
        return userOp;
    }
}

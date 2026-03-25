// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPaymaster } from "account-abstraction/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { IVerifyingPaymaster } from "./interfaces/IVerifyingPaymaster.sol";

/// @title VerifyingPaymaster
/// @notice Sponsors gas for trading UserOperations (openPosition/closePosition on PerpEngine)
///         and delegation UserOperations (USDC approve + grantSession).
///         Supports Kernel v3 ERC-7579 execute(bytes32,bytes) format for both single and
///         batch calls.
contract VerifyingPaymaster is IPaymaster, IVerifyingPaymaster, Ownable {
    // ─── Types ────────────────────────────────────────────────────────────────

    /// @dev ERC-7579 batch execution struct matching Kernel v3 batch encoding.
    struct Execution {
        address target;
        uint256 value;
        bytes callData;
    }

    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice Selector for Kernel v3 ERC-7579 execute(bytes32,bytes).
    bytes4 private constant EXECUTE_SELECTOR = bytes4(keccak256("execute(bytes32,bytes)"));

    /// @notice ERC-7579 single-call type (first byte of mode = 0x00).
    bytes1 private constant CALLTYPE_SINGLE = 0x00;

    /// @notice ERC-7579 batch-call type (first byte of mode = 0x01).
    bytes1 private constant CALLTYPE_BATCH = 0x01;

    /// @notice Selector for PerpEngine openPosition(bool,uint256,uint256,(uint256,uint256,uint256)).
    bytes4 private constant OPEN_POSITION_SELECTOR =
        bytes4(keccak256("openPosition(bool,uint256,uint256,(uint256,uint256,uint256))"));

    /// @notice Selector for PerpEngine closePosition(uint256,(uint256,uint256,uint256)).
    bytes4 private constant CLOSE_POSITION_SELECTOR =
        bytes4(keccak256("closePosition(uint256,(uint256,uint256,uint256))"));

    /// @notice Selector for ERC-20 approve(address,uint256).
    bytes4 private constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));

    /// @notice Selector for SessionKeyValidator grantSession(address,uint48,address,bytes4[],uint256).
    bytes4 private constant GRANT_SESSION_SELECTOR =
        bytes4(keccak256("grantSession(address,uint48,address,bytes4[],uint256)"));

    /// @notice Default gas allowance per UserOperation (5 M — covers MegaETH testnet gas).
    uint256 private constant DEFAULT_GAS_ALLOWANCE = 5_000_000;

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice The EntryPoint contract that manages UserOperations.
    address public immutable entryPoint;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice The allowed trading target address (PerpEngine).
    address public allowedTarget;

    /// @notice MockUSDC address — approve() calls to this target are sponsored.
    address public mockUsdc;

    /// @notice SessionKeyValidator address — grantSession() calls are sponsored.
    address public sessionKeyValidator;

    /// @notice Maximum gas cost (in wei) per UserOperation that this paymaster will sponsor.
    uint256 public gasAllowancePerOp;

    // ─── Constructor ───────────────────────────────────────────────────────────

    /// @param entryPoint_         The EntryPoint v0.7 contract address.
    /// @param allowedTarget_      PerpEngine address (trading calls are sponsored here).
    /// @param mockUsdc_           MockUSDC address (approve calls are sponsored here).
    /// @param sessionKeyValidator_ SessionKeyValidator address (grantSession calls sponsored).
    /// @param owner_              Owner address for administrative functions.
    constructor(
        address entryPoint_,
        address allowedTarget_,
        address mockUsdc_,
        address sessionKeyValidator_,
        address owner_
    ) Ownable(owner_) {
        if (
            entryPoint_ == address(0) || allowedTarget_ == address(0) || mockUsdc_ == address(0)
                || sessionKeyValidator_ == address(0)
        ) {
            revert ZeroAddress();
        }
        entryPoint = entryPoint_;
        allowedTarget = allowedTarget_;
        mockUsdc = mockUsdc_;
        sessionKeyValidator = sessionKeyValidator_;
        gasAllowancePerOp = DEFAULT_GAS_ALLOWANCE;
    }

    // ─── IPaymaster implementation ─────────────────────────────────────────────

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32, // userOpHash (unused)
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData) {
        if (msg.sender != entryPoint) revert NotEntryPoint(msg.sender);
        if (maxCost > gasAllowancePerOp) revert GasAllowanceExceeded(maxCost, gasAllowancePerOp);

        bytes calldata callData = userOp.callData;
        if (callData.length < 4) revert SelectorNotAllowed(bytes4(0));

        bytes4 outerSelector = bytes4(callData[0:4]);

        if (outerSelector == EXECUTE_SELECTOR) {
            // Kernel v3 ERC-7579: execute(bytes32 mode, bytes executionCalldata)
            // callData[4:] = ABI-encoded (bytes32, bytes) — valid calldata slice decode.
            (bytes32 mode, bytes memory execCalldata) = abi.decode(callData[4:], (bytes32, bytes));

            bytes1 callType = bytes1(mode);

            if (callType == CALLTYPE_SINGLE) {
                // execCalldata = abi.encodePacked(address target, uint256 value, bytes innerCallData)
                // Layout: [0:20] target, [20:52] value, [52+] innerCallData
                (address target, bytes4 innerSelector) = _extractSingleCall(execCalldata);
                _requireAllowedCall(target, innerSelector);
            } else if (callType == CALLTYPE_BATCH) {
                // execCalldata = abi.encode(Execution[]) where Execution = {target, value, callData}
                Execution[] memory execs = abi.decode(execCalldata, (Execution[]));
                for (uint256 i = 0; i < execs.length; ++i) {
                    bytes memory cd = execs[i].callData;
                    if (cd.length < 4) revert SelectorNotAllowed(bytes4(0));
                    bytes4 sel;
                    assembly {
                        sel := mload(add(cd, 0x20))
                    }
                    _requireAllowedCall(execs[i].target, sel);
                }
            } else {
                revert SelectorNotAllowed(outerSelector);
            }
        } else {
            // Direct call (no execute wrapper) — assume target is allowedTarget.
            _requireAllowedCall(allowedTarget, outerSelector);
        }

        context = abi.encode(userOp.sender, maxCost);
        validationData = 0;
    }

    /// @inheritdoc IPaymaster
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 // actualUserOpFeePerGas (unused)
    )
        external
    {
        if (msg.sender != entryPoint) revert NotEntryPoint(msg.sender);
        (address sender,) = abi.decode(context, (address, uint256));
        if (mode == PostOpMode.opSucceeded || mode == PostOpMode.opReverted) {
            emit GasSponsored(sender, actualGasCost);
        }
    }

    // ─── Owner functions ──────────────────────────────────────────────────────

    /// @inheritdoc IVerifyingPaymaster
    function setAllowedTarget(address newTarget) external onlyOwner {
        if (newTarget == address(0)) revert ZeroAddress();
        address old = allowedTarget;
        allowedTarget = newTarget;
        emit AllowedTargetUpdated(old, newTarget);
    }

    /// @inheritdoc IVerifyingPaymaster
    function setMockUsdc(address newMockUsdc) external onlyOwner {
        if (newMockUsdc == address(0)) revert ZeroAddress();
        address old = mockUsdc;
        mockUsdc = newMockUsdc;
        emit MockUsdcUpdated(old, newMockUsdc);
    }

    /// @inheritdoc IVerifyingPaymaster
    function setSessionKeyValidator(address newValidator) external onlyOwner {
        if (newValidator == address(0)) revert ZeroAddress();
        address old = sessionKeyValidator;
        sessionKeyValidator = newValidator;
        emit SessionKeyValidatorUpdated(old, newValidator);
    }

    /// @inheritdoc IVerifyingPaymaster
    function setGasAllowancePerOp(uint256 newAllowance) external onlyOwner {
        uint256 old = gasAllowancePerOp;
        gasAllowancePerOp = newAllowance;
        emit GasAllowanceUpdated(old, newAllowance);
    }

    // ─── Deposit management ────────────────────────────────────────────────────

    /// @inheritdoc IVerifyingPaymaster
    function deposit() external payable {
        IEntryPoint(entryPoint).depositTo{ value: msg.value }(address(this));
    }

    /// @inheritdoc IVerifyingPaymaster
    function withdraw(uint256 amount) external onlyOwner {
        IEntryPoint(entryPoint).withdrawTo(payable(owner()), amount);
    }

    /// @inheritdoc IVerifyingPaymaster
    function getDeposit() external view returns (uint256) {
        return IEntryPoint(entryPoint).balanceOf(address(this));
    }

    /// @notice Receive ETH for gas funding.
    receive() external payable { }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    /// @dev Extract target address and inner selector from ERC-7579 single-call execCalldata.
    ///      execCalldata = abi.encodePacked(address target, uint256 value, bytes innerCallData)
    ///      Layout: bytes [0:20] = target, [20:52] = value, [52:56] = innerSelector.
    ///      Uses assembly for efficient extraction without looping.
    function _extractSingleCall(bytes memory execCalldata)
        internal
        pure
        returns (address target, bytes4 innerSelector)
    {
        // Need at least 20 (address) + 32 (uint256) + 4 (selector) = 56 bytes.
        if (execCalldata.length < 56) revert SelectorNotAllowed(bytes4(0));
        assembly {
            // execCalldata + 0x20 = start of packed data (skip length word).
            let ptr := add(execCalldata, 0x20)
            // Address occupies first 20 bytes — load 32, shift right 96 bits (12 bytes).
            target := shr(96, mload(ptr))
            // innerSelector starts at byte 52 — load 32 bytes, bytes4 takes leftmost 4.
            innerSelector := mload(add(ptr, 52))
        }
    }

    /// @dev Revert if a (target, selector) pair is not in the allowed whitelist.
    ///      PerpEngine: openPosition, closePosition.
    ///      MockUSDC:   approve.
    ///      SessionKeyValidator: grantSession.
    function _requireAllowedCall(address target, bytes4 selector) internal view {
        if (target == allowedTarget) {
            if (selector != OPEN_POSITION_SELECTOR && selector != CLOSE_POSITION_SELECTOR) {
                revert SelectorNotAllowed(selector);
            }
        } else if (target == mockUsdc) {
            if (selector != APPROVE_SELECTOR) {
                revert SelectorNotAllowed(selector);
            }
        } else if (target == sessionKeyValidator) {
            if (selector != GRANT_SESSION_SELECTOR) {
                revert SelectorNotAllowed(selector);
            }
        } else {
            revert TargetNotAllowed(target);
        }
    }
}

// ─── IEntryPoint interface ────────────────────────────────────────────────────

/// @notice Minimal interface for EntryPoint deposit/withdrawal functions.
interface IEntryPoint {
    /// @notice Deposit ETH to fund gas for this account.
    function depositTo(address account) external payable;

    /// @notice Withdraw ETH from this account's deposit.
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external;

    /// @notice Get the deposit balance for an account.
    function balanceOf(address account) external view returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPaymaster } from "account-abstraction/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { IVerifyingPaymaster } from "./interfaces/IVerifyingPaymaster.sol";

/// @title VerifyingPaymaster
/// @notice Sponsors gas for trading UserOperations that target PerpEngine with allowed selectors.
///         Validates callData to ensure only openPosition and closePosition are called.
contract VerifyingPaymaster is IPaymaster, IVerifyingPaymaster, Ownable {
    // ─── Constants ────────────────────────────────────────────────────────────

    /// @notice Selector for SmartAccount execute(address,uint256,bytes) function.
    bytes4 private constant EXECUTE_SELECTOR = bytes4(keccak256("execute(address,uint256,bytes)"));

    /// @notice Selector for PerpEngine openPosition(bool,uint256,uint256,(uint256,uint256,uint256)).
    bytes4 private constant OPEN_POSITION_SELECTOR =
        bytes4(keccak256("openPosition(bool,uint256,uint256,(uint256,uint256,uint256))"));

    /// @notice Selector for PerpEngine closePosition(uint256,(uint256,uint256,uint256)).
    bytes4 private constant CLOSE_POSITION_SELECTOR =
        bytes4(keccak256("closePosition(uint256,(uint256,uint256,uint256))"));

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice The EntryPoint contract that manages UserOperations.
    address public immutable entryPoint;

    // ─── State ────────────────────────────────────────────────────────────────

    /// @notice The allowed target address (PerpEngine) for sponsored operations.
    address public allowedTarget;

    /// @notice Maximum gas allowance per UserOperation (default: 500k).
    uint256 public gasAllowancePerOp;

    // ─── Constructor ───────────────────────────────────────────────────────────

    /// @param entryPoint_ The EntryPoint contract address.
    /// @param allowedTarget_ The allowed target address (PerpEngine).
    /// @param owner_ The owner address for administrative functions.
    constructor(address entryPoint_, address allowedTarget_, address owner_) Ownable(owner_) {
        if (entryPoint_ == address(0) || allowedTarget_ == address(0)) {
            revert ZeroAddress();
        }
        entryPoint = entryPoint_;
        allowedTarget = allowedTarget_;
        gasAllowancePerOp = 500_000;
    }

    // ─── IPaymaster implementation ─────────────────────────────────────────────

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32, // userOpHash (unused)
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData) {
        // Only EntryPoint can call this function
        if (msg.sender != entryPoint) {
            revert NotEntryPoint(msg.sender);
        }

        // Check gas allowance
        if (maxCost > gasAllowancePerOp) {
            revert GasAllowanceExceeded(maxCost, gasAllowancePerOp);
        }

        // Parse callData to extract target and selector
        bytes calldata callData = userOp.callData;
        if (callData.length < 4) {
            revert SelectorNotAllowed(bytes4(0));
        }

        bytes4 outerSelector = bytes4(callData[0:4]);
        address target;
        bytes4 innerSelector;

        if (outerSelector == EXECUTE_SELECTOR) {
            // callData = execute(address target, uint256 value, bytes data)
            // Decode: skip selector (4 bytes), then decode (address, uint256, bytes)
            if (callData.length < 100) {
                // Not enough data for execute call
                revert SelectorNotAllowed(outerSelector);
            }

            // Decode the execute parameters
            (address decodedTarget,, bytes memory innerData) =
                abi.decode(callData[4:], (address, uint256, bytes));
            target = decodedTarget;

            // Extract inner selector from the data
            if (innerData.length < 4) {
                revert SelectorNotAllowed(bytes4(0));
            }
            // Extract first 4 bytes as selector
            innerSelector =
                bytes4(abi.encodePacked(innerData[0], innerData[1], innerData[2], innerData[3]));
        } else {
            // Assume callData is the direct call to the target
            target = allowedTarget;
            innerSelector = outerSelector;
        }

        // Verify target is the allowed target
        if (target != allowedTarget) {
            revert TargetNotAllowed(target);
        }

        // Verify selector is allowed (openPosition or closePosition)
        if (innerSelector != OPEN_POSITION_SELECTOR && innerSelector != CLOSE_POSITION_SELECTOR) {
            revert SelectorNotAllowed(innerSelector);
        }

        // Return context for postOp and validation data (0 = valid)
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
        // Only EntryPoint can call this function
        if (msg.sender != entryPoint) {
            revert NotEntryPoint(msg.sender);
        }

        // Decode context
        (address sender,) = abi.decode(context, (address, uint256));

        // Emit event if operation succeeded or reverted (but not if postOp itself reverted)
        if (mode == PostOpMode.opSucceeded || mode == PostOpMode.opReverted) {
            emit GasSponsored(sender, actualGasCost);
        }
    }

    // ─── Owner functions ──────────────────────────────────────────────────────

    /// @inheritdoc IVerifyingPaymaster
    function setAllowedTarget(address newTarget) external onlyOwner {
        if (newTarget == address(0)) {
            revert ZeroAddress();
        }
        address oldTarget = allowedTarget;
        allowedTarget = newTarget;
        emit AllowedTargetUpdated(oldTarget, newTarget);
    }

    /// @inheritdoc IVerifyingPaymaster
    function setGasAllowancePerOp(uint256 newAllowance) external onlyOwner {
        uint256 oldAllowance = gasAllowancePerOp;
        gasAllowancePerOp = newAllowance;
        emit GasAllowanceUpdated(oldAllowance, newAllowance);
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

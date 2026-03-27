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

    /// @notice Selector for Kernel v3.1 installValidations(bytes21[],(uint32,address)[],bytes[],bytes[]).
    ///         Kernel v3.1 uses this — not ERC-7579 installModule — to register validator modules.
    bytes4 private constant INSTALL_VALIDATIONS_SELECTOR =
        bytes4(keccak256("installValidations(bytes21[],(uint32,address)[],bytes[],bytes[])"));

    /// @notice Selector for SessionKeyValidator revokeSession().
    ///         Called in delegation batches when an existing session must be cleared before
    ///         grantSession(), because grantSession reverts if a session is already active.
    bytes4 private constant REVOKE_SESSION_SELECTOR = bytes4(keccak256("revokeSession()"));

    /// @notice Default gas allowance per UserOperation (1 Gwei — covers MegaETH testnet gas,
    ///         which runs ~30× higher than mainnet; observed delegation maxCost ~407 M wei).
    uint256 private constant DEFAULT_GAS_ALLOWANCE = 1_000_000_000;

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
                (address target, bytes memory innerCallData) = _extractSingleCall(execCalldata);
                _requireAllowedCall(target, innerCallData, userOp.sender);
            } else if (callType == CALLTYPE_BATCH) {
                // execCalldata = abi.encode(Execution[]) where Execution = {target, value, callData}
                Execution[] memory execs = abi.decode(execCalldata, (Execution[]));
                for (uint256 i = 0; i < execs.length; ++i) {
                    _requireAllowedCall(execs[i].target, execs[i].callData, userOp.sender);
                }
            } else {
                revert SelectorNotAllowed(outerSelector);
            }
        } else {
            // Direct call (no execute wrapper) — only PerpEngine trading selectors allowed.
            if (outerSelector != OPEN_POSITION_SELECTOR && outerSelector != CLOSE_POSITION_SELECTOR)
            {
                revert SelectorNotAllowed(outerSelector);
            }
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

    /// @dev Extract target address and full innerCallData from ERC-7579 single-call execCalldata.
    ///      execCalldata = abi.encodePacked(address target, uint256 value, bytes innerCallData)
    ///      Layout: bytes [0:20] = target, [20:52] = value, [52:] = innerCallData.
    function _extractSingleCall(bytes memory execCalldata)
        internal
        pure
        returns (address target, bytes memory innerCallData)
    {
        // Need at least 20 (address) + 32 (uint256) + 4 (selector) = 56 bytes.
        if (execCalldata.length < 56) revert SelectorNotAllowed(bytes4(0));
        assembly {
            let ptr := add(execCalldata, 0x20)
            target := shr(96, mload(ptr))
        }
        uint256 innerLen = execCalldata.length - 52;
        innerCallData = new bytes(innerLen);
        for (uint256 i = 0; i < innerLen; ++i) {
            innerCallData[i] = execCalldata[52 + i];
        }
    }

    /// @dev Revert if a call is not in the allowed whitelist.
    ///      Validates both (target, selector) and critical call arguments:
    ///      - PerpEngine: openPosition / closePosition
    ///      - MockUSDC.approve: spender must be allowedTarget (PerpEngine)
    ///      - SessionKeyValidator.grantSession: targetContract must be allowedTarget (PerpEngine)
    ///      - sender.installValidations: vIds[0] must be 0x01||sessionKeyValidator (SECONDARY type)
    function _requireAllowedCall(address target, bytes memory callData, address sender)
        internal
        view
    {
        if (callData.length < 4) revert SelectorNotAllowed(bytes4(0));
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 0x20))
        }

        if (target == allowedTarget) {
            if (selector != OPEN_POSITION_SELECTOR && selector != CLOSE_POSITION_SELECTOR) {
                revert SelectorNotAllowed(selector);
            }
        } else if (target == mockUsdc) {
            if (selector != APPROVE_SELECTOR) revert SelectorNotAllowed(selector);
            // approve(address spender, uint256 amount) — spender is ABI-encoded at offset 4.
            // ABI-encoded address: right-aligned in a 32-byte slot → bottom 20 bytes.
            if (callData.length < 36) revert SelectorNotAllowed(selector);
            address spender;
            assembly {
                spender := and(
                    mload(add(add(callData, 0x20), 4)),
                    0xffffffffffffffffffffffffffffffffffffffff
                )
            }
            if (spender != allowedTarget) revert TargetNotAllowed(spender);
        } else if (target == sessionKeyValidator) {
            if (selector == REVOKE_SESSION_SELECTOR) {
                // revokeSession() takes no arguments — no further validation needed.
            } else if (selector == GRANT_SESSION_SELECTOR) {
                // grantSession(address sessionKey, uint48 validUntil, address targetContract, ...)
                // ABI layout: selector(4) + sessionKey(32) + validUntil(32) + targetContract(32)
                if (callData.length < 100) revert SelectorNotAllowed(selector);
                address grantTarget;
                assembly {
                    grantTarget := and(
                        mload(add(add(callData, 0x20), 68)),
                        0xffffffffffffffffffffffffffffffffffffffff
                    )
                }
                if (grantTarget != allowedTarget) revert TargetNotAllowed(grantTarget);
            } else {
                revert SelectorNotAllowed(selector);
            }
        } else if (target == sender) {
            // Allow a smart account to install only the SessionKeyValidator as a secondary validator.
            // Kernel v3.1 uses installValidations(bytes21[],(uint32,address)[],bytes[],bytes[]).
            // vIds[0] = bytes21(0x01 || sessionKeyValidator): type=SECONDARY, address=SKV.
            //
            // ABI layout after selector (4 bytes):
            //   [4:36]   = offset to vIds array  = 0x80 (128)
            //   [36:68]  = offset to configs array
            //   [68:100] = offset to validationData array
            //   [100:132]= offset to hookData array
            //   [132:164]= vIds.length (must be 1)
            //   [164:196]= vIds[0] as bytes32 (21-byte vId, left-aligned)
            if (selector != INSTALL_VALIDATIONS_SELECTOR) revert SelectorNotAllowed(selector);
            if (callData.length < 196) revert SelectorNotAllowed(selector);

            uint256 vIdsOffset;
            uint256 vIdsLength;
            bytes32 vIdSlot;
            assembly {
                let base := add(callData, 0x20)
                vIdsOffset := mload(add(base, 4))
                vIdsLength := mload(add(base, 132))
                vIdSlot := mload(add(base, 164))
            }
            // Enforce canonical ABI layout: vIds offset must be 128 (4 head params × 32 bytes).
            // A non-standard offset lets an attacker craft calldata where this gate reads a
            // benign vId while Kernel's abi.decode follows a different offset to another array.
            if (vIdsOffset != 128) revert SelectorNotAllowed(selector);
            if (vIdsLength != 1) revert SelectorNotAllowed(selector);

            // bytes21 is left-aligned: byte[0]=type, bytes[1..20]=address, bytes[21..31]=zeros.
            if (bytes1(vIdSlot) != 0x01) revert SelectorNotAllowed(selector);
            address module = address(uint160(uint256(vIdSlot) >> 88));
            if (module != sessionKeyValidator) revert TargetNotAllowed(module);
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

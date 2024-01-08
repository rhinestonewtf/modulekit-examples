// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { IERC721 } from "forge-std/interfaces/IERC721.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { ERC7579HookDeconstructor } from "modulekit/modules/ERC7579HookDeconstructor.sol";
import { IERC7579Execution } from "modulekit/ModuleKitLib.sol";

contract ColdStorageHook is ERC7579HookDeconstructor {
    error UnsupportedExecution();
    error UnauthorizedAccess();

    using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;

    struct VaultConfig {
        uint128 waitPeriod;
        address owner;
    }

    mapping(address subAccount => VaultConfig) internal vaultConfig;
    mapping(address subAccount => EnumerableMap.Bytes32ToBytes32Map) internal executions;

    event WithdrawalRequested(address indexed subAccount, IERC7579Execution.Execution indexed exec);

    function _getTokenTxReceiver(bytes calldata callData) internal returns (address receiver) {
        bytes4 functionSig = bytes4(callData[0:4]);
        bytes calldata params = callData[4:];
        if (functionSig == IERC20.transfer.selector) {
            (receiver,) = abi.decode(params, (address, uint256));
        } else if (functionSig == IERC20.transferFrom.selector) {
            (, receiver,) = abi.decode(params, (address, address, uint256));
        } else if (functionSig == IERC721.transferFrom.selector) {
            (, receiver,) = abi.decode(params, (address, address, uint256));
        } else {
            revert("Invalid TokenTransfer");
        }
    }

    /**
     * Function that must be triggered from subaccount.
     * requests an execution to happen in the future
     *
     */
    function requestTimelockedExecution(
        IERC7579Execution.Execution calldata _exec,
        uint256 additionalWait
    )
        external
    {
        VaultConfig memory _config = vaultConfig[msg.sender];
        // get min wait period
        bytes32 executionHash = keccak256(abi.encode(_exec));

        if (_exec.callData.length != 0) {
            // check that transaction is only a token transfer
            address tokenReceiver = _getTokenTxReceiver(_exec.callData);
            if (tokenReceiver != _config.owner) {
                revert("Invalid receiver transfer");
            }
        }

        // write executionHash to storage
        executions[msg.sender].set(
            executionHash, bytes32(block.timestamp + _config.waitPeriod + additionalWait)
        );

        emit WithdrawalRequested(msg.sender, _exec);
    }

    function onInstall(bytes calldata data) external override {
        VaultConfig storage _config = vaultConfig[msg.sender];
        (_config.waitPeriod, _config.owner) = abi.decode(data, (uint128, address));
    }

    function onUninstall(bytes calldata data) external override {
        delete vaultConfig[msg.sender].waitPeriod;
        delete vaultConfig[msg.sender].owner;
    }

    function onPostCheck(bytes calldata hookData)
        internal
        virtual
        override
        returns (bool success)
    {
        if (keccak256(hookData) == keccak256("")) return true;
        return false;
    }

    function onExecute(
        address msgSender,
        address target,
        uint256 value,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        bytes4 functionSig = bytes4(callData[0:4]);

        // check if call is a requestTimelockedExecution
        if (target != address(this) || functionSig != this.requestTimelockedExecution.selector) {
            revert UnauthorizedAccess();
        }

        // check if transaction has been requested before

        IERC7579Execution.Execution memory _exec =
            IERC7579Execution.Execution({ target: target, value: value, callData: callData });
        bytes32 executionHash = keccak256(abi.encode(_exec));
        (bool success, bytes32 entry) = executions[msg.sender].tryGet(executionHash);
        if (!success) revert UnauthorizedAccess();

        uint256 requestTimeStamp = uint256(entry);
        if (requestTimeStamp < block.timestamp) revert UnauthorizedAccess();
        return "";
    }

    function onExecuteBatch(
        address msgSender,
        IERC7579Execution.Execution[] calldata
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onExecuteFromExecutor(
        address msgSender,
        address target,
        uint256 value,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onExecuteBatchFromExecutor(
        address msgSender,
        IERC7579Execution.Execution[] calldata
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onInstallExecutor(
        address msgSender,
        address executor,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onUninstallExecutor(
        address msgSender,
        address executor,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onInstallValidator(
        address msgSender,
        address validator,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onUninstallValidator(
        address msgSender,
        address validator,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onUninstallHook(
        address msgSender,
        address hookModule,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onInstallHook(
        address msgSender,
        address hookModule,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function version() external pure virtual override returns (string memory) {
        return "1.0.0";
    }

    function name() external pure virtual override returns (string memory) {
        return "ColdStorageHook";
    }

    function isModuleType(uint256 isType) external pure virtual override returns (bool) {
        return isType == TYPE_HOOK;
    }
}

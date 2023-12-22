// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "forge-std/console2.sol";
import "./HookBase.sol";
import "erc7579/interfaces/IMSA.sol";
import "forge-std/interfaces/IERC721.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract VaultHook is HookBase {
    error UnsupportedExecution();

    using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;

    struct VaultConfig {
        uint128 requestTime;
        uint128 waitPeriod;
        address owner;
    }

    mapping(address subAccount => VaultConfig) internal vaultConfig;
    mapping(address subAccount => EnumerableMap.Bytes32ToBytes32Map) internal executions;

    /**
     * Function that must be triggered from subaccount.
     * requests an execution to happen in the future
     *
     */
    function requestTimelockedExecution(
        IExecution.Execution calldata _exec,
        uint256 additionalWait
    )
        external
    {
        // get min wait period
        uint256 minWaitPeriod = vaultConfig[msg.sender].waitPeriod;
        bytes32 executionHash = keccak256(abi.encode(_exec));
        console2.log("\n\nexecutionHash");
        console2.logBytes32(executionHash);

        console2.log("target: %s", _exec.target);
        console2.logBytes(_exec.callData);
        console2.log("\n\n");

        executions[msg.sender].set(
            executionHash, bytes32(block.timestamp + minWaitPeriod + additionalWait)
        );
    }

    function onInstall(bytes calldata data) external override {
        if (vaultConfig[msg.sender].waitPeriod != 0) revert();
        vaultConfig[msg.sender].waitPeriod = abi.decode(data, (uint128));
        console2.log("VaultHook.onInstall");
    }

    function onUninstall(bytes calldata data) external override {
        vaultConfig[msg.sender].waitPeriod = 0;
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

    function _checkIfRequestTransfer(
        address target,
        bytes calldata callData
    )
        internal
        view
        returns (bool isValid)
    {
        // if (target != address(this)) return false;
        // bytes4 functionSig = bytes4(callData[0:4]);
        // if (functionSig != this.requestTransfer.selector) return false;
        // return true;
    }

    modifier alwaysAllowTransferRequest(address callTarget, bytes calldata callData) {
        if (!_checkIfRequestTransfer(callTarget, callData)) {
            _;
        }
    }

    function _requestTransferIsValid() internal returns (bool isValid) {
        isValid = vaultConfig[msg.sender].requestTime + vaultConfig[msg.sender].waitPeriod
            > block.timestamp;
    }

    modifier onlyIfDue(address callTarget, bytes calldata callData) {
        if (_requestTransferIsValid()) {
            _;
        } else if (_checkIfRequestTransfer(callTarget, callData)) {
            _;
        } else {
            revert();
        }
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
        if (target == address(this) && functionSig == this.requestTimelockedExecution.selector) {
            return "";
        }

        // check if transaction has been requested before

        // TODO check that only token transfers are in callData
        IExecution.Execution memory _exec =
            IExecution.Execution({ target: target, value: value, callData: callData });
        bytes32 executionHash = keccak256(abi.encode(_exec));
        (bool success, bytes32 entry) = executions[msg.sender].tryGet(executionHash);
        if (!success) revert("Missing request");

        uint256 requestTimeStamp = uint256(entry);
        if (requestTimeStamp > block.timestamp) return "";
        revert("Request not due yet");
    }

    function onExecuteBatch(
        address msgSender,
        IExecution.Execution[] calldata
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onExecuteFromModule(
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
        if (bytes4(callData[:4]) != IERC721.transferFrom.selector) revert();
        (address from, address to, uint256 tokenId) =
            abi.decode(callData[4:], (address, address, uint256));
    }

    function onExecuteBatchFromModule(
        address msgSender,
        IExecution.Execution[] memory
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onExecuteDelegateCall(
        address msgSender,
        address target,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onExecuteDelegateCallFromModule(
        address msgSender,
        address target,
        bytes calldata callData
    )
        internal
        virtual
        override
        returns (bytes memory hookData)
    {
        revert UnsupportedExecution();
    }

    function onEnableExecutor(
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

    function onDisableExecutor(
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

    function onEnableValidator(
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

    function onDisableValidator(
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

    function onDisableHook(
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

    function onEnableHook(
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
}

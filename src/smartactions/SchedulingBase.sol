// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "modulekit/core/sessionKey/ISessionValidationModule.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC7579Execution } from "modulekit/Accounts.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";

abstract contract SchedulingBase is ERC7579ExecutorBase {
    error InvalidExecution();

    event ExecutionAdded(address indexed smartAccount, bytes32 indexed executionHash);

    event ExecutionTriggered(address indexed smartAccount, bytes32 indexed executionHash);

    event ExecutionCancelled(address indexed smartAccount, bytes32 indexed executionHash);

    mapping(address smartAccount => mapping(bytes32 jobHash => ExecutionConfig)) internal
        executionLog;

    struct ExecutionConfig {
        uint48 executeInterval;
        uint16 numberOfExecutions;
        uint16 numberOfExecutionsCompleted;
        uint48 startDate;
        bool isCancelled;
        uint48 lastExecutionTime;
        bytes executionData;
    }

    modifier canExecute(bytes32 jobHash) {
        ExecutionConfig storage executionConfig = executionLog[msg.sender][jobHash];

        if (executionConfig.isCancelled) {
            revert InvalidExecution();
        }

        if (executionConfig.lastExecutionTime + executionConfig.executeInterval < block.timestamp) {
            revert InvalidExecution();
        }
        if (executionConfig.numberOfExecutionsCompleted >= executionConfig.numberOfExecutions) {
            revert InvalidExecution();
        }
        if (executionConfig.startDate > block.timestamp) {
            revert InvalidExecution();
        }

        _;
    }

    // abstract methohd to be implemented by the inheriting contract
    function executeOrder(bytes32 executionHash) external virtual;

    function createExecution(bytes memory data) internal {
        (
            uint48 executeInterval,
            uint16 numberOfExecutionsCompleted,
            uint16 numberOfExecutions,
            uint48 startDate,
            ,
            uint48 lastExecutionTime,
            bytes memory executionData
        ) = abi.decode(data, (uint48, uint16, uint16, uint48, bool, uint48, bytes));

        bytes32 executionHash = keccak256(executionData);

        executionLog[msg.sender][executionHash] = ExecutionConfig({
            numberOfExecutionsCompleted: numberOfExecutionsCompleted,
            executeInterval: executeInterval,
            numberOfExecutions: numberOfExecutions,
            startDate: startDate,
            isCancelled: false,
            lastExecutionTime: lastExecutionTime,
            executionData: executionData
        });

        emit ExecutionAdded(msg.sender, executionHash);
    }

    function addOrder(bytes calldata executionConfig) external {
        createExecution(executionConfig);
    }

    function cancelOrder(bytes32 executionHash) external {
        ExecutionConfig storage executionConfig = executionLog[msg.sender][executionHash];
        executionConfig.isCancelled = true;
        emit ExecutionCancelled(msg.sender, executionHash);
    }

    function onInstall(bytes calldata data) external override {
        if (data.length == 0) return;
        createExecution(data);
    }

    function onUninstall(bytes calldata data) external override { }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }
}

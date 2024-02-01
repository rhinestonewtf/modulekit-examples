// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "modulekit/core/sessionKey/ISessionValidationModule.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC7579Execution } from "modulekit/Accounts.sol";
import { ERC7579ExecutorBase } from "modulekit/Modules.sol";
import "modulekit/core/sessionKey/ISessionValidationModule.sol";

abstract contract SchedulingBase is ERC7579ExecutorBase, ISessionValidationModule {
    error InvalidExecution();
    error InvalidMethod(bytes4);
    error InvalidValue();
    error InvalidAmount();
    error InvalidTarget();
    error InvalidRecipient();

    error InvalidInstall();

    error InvalidJob();

    event ExecutionAdded(address indexed smartAccount, uint256 indexed jobId);

    event ExecutionTriggered(address indexed smartAccount, uint256 indexed jobId);

    event ExecutionCancelled(address indexed smartAccount, uint256 indexed jobId);

    mapping(address smartAccount => mapping(uint256 jobId => ExecutionConfig)) internal
        _executionLog;

    mapping(address smartAccount => uint256 jobCount) internal _accountJobCount;

    struct ExecutionConfig {
        uint48 executeInterval;
        uint16 numberOfExecutions;
        uint16 numberOfExecutionsCompleted;
        uint48 startDate;
        bool isEnabled;
        uint48 lastExecutionTime;
        bytes executionData;
    }

    struct ExecutorAccess {
        address sessionKeySigner;
        uint256 jobId;
    }

    struct Params {
        uint256 jobId;
    }

    function _isExecutionValid(uint256 jobId) internal view {
        ExecutionConfig storage executionConfig = _executionLog[msg.sender][jobId];

        if (!executionConfig.isEnabled) {
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
    }

    modifier canExecute(uint256 jobId) {
        _isExecutionValid(jobId);
        _;
    }

    // abstract methohd to be implemented by the inheriting contract
    function executeOrder(uint256 jobId) external virtual;

    function _createExecution(ExecutionConfig calldata data) internal {
        uint256 jobId = _accountJobCount[msg.sender];
        _accountJobCount[msg.sender]++;

        if (data.startDate < block.timestamp) {
            revert InvalidExecution();
        }

        _executionLog[msg.sender][jobId] = ExecutionConfig({
            numberOfExecutionsCompleted: 0,
            isEnabled: true,
            lastExecutionTime: 0,
            executeInterval: data.executeInterval,
            numberOfExecutions: data.numberOfExecutions,
            startDate: data.startDate,
            executionData: data.executionData
        });

        emit ExecutionAdded(msg.sender, jobId);
    }

    function addOrder(ExecutionConfig calldata executionConfig) external {
        _createExecution(executionConfig);
    }

    function cancelOrder(uint256 jobId) external {
        ExecutionConfig storage executionConfig = _executionLog[msg.sender][jobId];
        executionConfig.isEnabled = false;
        emit ExecutionCancelled(msg.sender, jobId);
    }

    function validateSessionParams(
        address destinationContract,
        uint256 callValue,
        bytes calldata callData,
        bytes calldata _sessionKeyData,
        bytes calldata /*_callSpecificData*/
    )
        external
        view
        virtual
        override
        returns (address)
    {
        ExecutorAccess memory access = abi.decode(_sessionKeyData, (ExecutorAccess));

        bytes4 targetSelector = bytes4(callData[:4]);

        Params memory params = abi.decode(callData[4:], (Params));
        if (targetSelector != this.executeOrder.selector) {
            revert InvalidMethod(targetSelector);
        }

        if (params.jobId != access.jobId) {
            revert InvalidJob();
        }

        if (destinationContract != address(this)) {
            revert InvalidRecipient();
        }

        if (callValue != 0) {
            revert InvalidValue();
        }

        return access.sessionKeySigner;
    }

    function onInstall(bytes calldata data) external override {
        if (_accountJobCount[msg.sender] != 0) {
            revert InvalidInstall();
        }

        ExecutionConfig memory executionConfig = abi.decode(data, (ExecutionConfig));

        if (executionConfig.startDate < block.timestamp) {
            revert InvalidExecution();
        }

        uint256 jobId = _accountJobCount[msg.sender] + 1;
        _accountJobCount[msg.sender]++;

        _executionLog[msg.sender][jobId] = ExecutionConfig({
            numberOfExecutionsCompleted: 0,
            isEnabled: true,
            lastExecutionTime: 0,
            executeInterval: executionConfig.executeInterval,
            numberOfExecutions: executionConfig.numberOfExecutions,
            startDate: executionConfig.startDate,
            executionData: executionConfig.executionData
        });
    }

    function onUninstall() external {
        uint256 count = _accountJobCount[msg.sender];
        for (uint256 i = 1; i <= count; i++) {
            delete _executionLog[msg.sender][i];
        }
        _accountJobCount[msg.sender] = 0;
    }

    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }
}
